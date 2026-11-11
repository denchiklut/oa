// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include <array>
#include <variant>

#include "base/functional/bind.h"
#include "chrome/browser/content_settings/host_content_settings_map_factory.h"
#include "chrome/browser/permissions/permission_decision_auto_blocker_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/content_settings/core/browser/content_settings_registry.h"
#include "components/content_settings/core/browser/host_content_settings_map.h"
#include "components/content_settings/core/browser/permission_settings_info.h"
#include "components/content_settings/core/browser/permission_settings_registry.h"
#include "components/content_settings/core/common/content_settings.h"
#include "components/content_settings/core/common/content_settings_pattern.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/permissions/permission_decision_auto_blocker.h"
#include "components/permissions/permission_uma_util.h"
#include "components/permissions/permission_util.h"
#include "oa/browser/profile_services.h"
#include "oa/public/site_settings.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace oa {
namespace {

// Page info's kPermissionType[] on macOS, in its order
// (components/page_info/page_info.cc). SiteSettingType values index it.
constexpr auto kSiteSettingTypes = std::to_array<ContentSettingsType>({
    ContentSettingsType::GEOLOCATION,
    ContentSettingsType::GEOLOCATION_WITH_OPTIONS,
    ContentSettingsType::MEDIASTREAM_CAMERA,
    ContentSettingsType::CAMERA_PAN_TILT_ZOOM,
    ContentSettingsType::MEDIASTREAM_MIC,
    ContentSettingsType::SENSORS,
    ContentSettingsType::NOTIFICATIONS,
    ContentSettingsType::JAVASCRIPT,
    ContentSettingsType::IMAGES,
    ContentSettingsType::POPUPS,
    ContentSettingsType::WINDOW_MANAGEMENT,
    ContentSettingsType::ADS,
    ContentSettingsType::BACKGROUND_SYNC,
    ContentSettingsType::SOUND,
    ContentSettingsType::AUTOMATIC_DOWNLOADS,
    ContentSettingsType::MIDI_SYSEX,
    ContentSettingsType::CLIPBOARD_READ_WRITE,
    ContentSettingsType::USB_GUARD,
    ContentSettingsType::HID_GUARD,
    ContentSettingsType::SERIAL_GUARD,
    ContentSettingsType::FILE_SYSTEM_WRITE_GUARD,
    ContentSettingsType::LOCAL_FONTS,
    ContentSettingsType::BLUETOOTH_GUARD,
    ContentSettingsType::BLUETOOTH_SCANNING,
    ContentSettingsType::HAND_TRACKING,
    ContentSettingsType::VR,
    ContentSettingsType::AR,
    ContentSettingsType::IDLE_DETECTION,
    ContentSettingsType::FEDERATED_IDENTITY_API,
    ContentSettingsType::AUTO_PICTURE_IN_PICTURE,
    ContentSettingsType::CAPTURED_SURFACE_CONTROL,
    ContentSettingsType::AUTOMATIC_FULLSCREEN,
    ContentSettingsType::KEYBOARD_LOCK,
    ContentSettingsType::POINTER_LOCK,
    ContentSettingsType::WEB_APP_INSTALLATION,
    ContentSettingsType::LOCAL_NETWORK,
    ContentSettingsType::LOOPBACK_NETWORK,
});
static_assert(kSiteSettingTypes.size() ==
              static_cast<size_t>(SiteSettingType::kLoopbackNetwork) + 1);

// Chromium's type for `type`, or DEFAULT for a value outside the list, which
// the app can send across the bridge.
ContentSettingsType ToContentSettingsType(SiteSettingType type) {
  const auto index = static_cast<size_t>(type);
  return index < kSiteSettingTypes.size() ? kSiteSettingTypes[index]
                                          : ContentSettingsType::DEFAULT;
}

// As page info's toggle (PageInfoUI::IsToggleOn): a device guard has no
// Allow, so its Ask is what the row shows as allowed.
SiteSettingValue ToSiteSettingValue(ContentSettingsType type,
                                    const PermissionSetting& setting) {
  const ContentSetting* value = std::get_if<ContentSetting>(&setting);
  if (!value) {
    return SiteSettingValue::kDefault;
  }
  if (permissions::PermissionUtil::IsGuardContentSetting(type) &&
      *value == CONTENT_SETTING_ASK) {
    return SiteSettingValue::kAllow;
  }
  switch (*value) {
    case CONTENT_SETTING_ALLOW:
      return SiteSettingValue::kAllow;
    case CONTENT_SETTING_BLOCK:
      return SiteSettingValue::kBlock;
    case CONTENT_SETTING_ASK:
      return SiteSettingValue::kAsk;
    case CONTENT_SETTING_SESSION_ONLY:
      return SiteSettingValue::kSessionOnly;
    default:
      return SiteSettingValue::kDefault;
  }
}

ContentSetting ToContentSetting(ContentSettingsType type,
                                SiteSettingValue value) {
  switch (value) {
    case SiteSettingValue::kAllow:
      return permissions::PermissionUtil::IsGuardContentSetting(type)
                 ? CONTENT_SETTING_ASK
                 : CONTENT_SETTING_ALLOW;
    case SiteSettingValue::kBlock:
      return CONTENT_SETTING_BLOCK;
    case SiteSettingValue::kAsk:
      return CONTENT_SETTING_ASK;
    case SiteSettingValue::kSessionOnly:
      return CONTENT_SETTING_SESSION_ONLY;
    case SiteSettingValue::kDefault:
      return CONTENT_SETTING_DEFAULT;
  }
  return CONTENT_SETTING_DEFAULT;
}

// `url`'s origin as a URL, which keys its site's settings, or an empty URL if
// it has none.
GURL OriginURL(const std::string& url) {
  const GURL gurl(url);
  if (!gurl.is_valid()) {
    return GURL();
  }
  const url::Origin origin = url::Origin::Create(gurl);
  return origin.opaque() ? GURL() : origin.GetURL();
}

// The map of the app profile `profile_id`, or null until it has loaded.
HostContentSettingsMap* LoadedMap(const std::string& profile_id) {
  Profile* profile = GetLoadedBrowserProfile(profile_id);
  return profile ? HostContentSettingsMapFactory::GetForProfile(profile)
                 : nullptr;
}

// Whether page info lists `type` for `url` (PageInfo::ShouldShowPermission),
// without a page: its rules for what a page uses, such as sound it played, are
// left out, and so is its term that a changed default must not be ASK. Sets
// `value` to the setting's value for the site.
bool IsChanged(HostContentSettingsMap* map,
               bool is_off_the_record,
               ContentSettingsType type,
               const GURL& url,
               PermissionSetting* value) {
  const content_settings::PermissionSettingsInfo* info =
      content_settings::PermissionSettingsRegistry::GetInstance()->Get(type);
  if (!info) {
    return false;
  }
  content_settings::SettingInfo setting_info;
  *value = map->GetPermissionSetting(url, url, type, &setting_info);
  const PermissionSetting factory_default = info->GetInitialDefaultSetting();
  // A rule with two wildcards is the type's default.
  const bool is_default =
      setting_info.primary_pattern == ContentSettingsPattern::Wildcard() &&
      setting_info.secondary_pattern == ContentSettingsPattern::Wildcard();
  if (!is_default) {
    // A grant off the record reads as undecided there, which page info
    // doesn't count as the site's own decision.
    const bool is_off_the_record_default =
        is_off_the_record && info->delegate().IsUndecided(*value) &&
        info->delegate().IsUndecided(factory_default);
    if (!is_off_the_record_default) {
      return true;
    }
  }
  if (setting_info.source != content_settings::SettingSource::kUser) {
    return true;
  }
  const PermissionSetting default_setting =
      is_default ? *value : map->GetDefaultPermissionSetting(type, nullptr);
  return default_setting != factory_default;
}

}  // namespace

std::optional<std::vector<SiteSetting>> GetChangedSiteSettings(
    const std::string& profile_id,
    const std::string& origin) {
  Profile* profile = GetLoadedBrowserProfile(profile_id);
  const GURL url = OriginURL(origin);
  if (!profile || !url.is_valid()) {
    return std::nullopt;
  }
  HostContentSettingsMap* map =
      HostContentSettingsMapFactory::GetForProfile(profile);
  std::vector<SiteSetting> settings;
  for (size_t index = 0; index < kSiteSettingTypes.size(); ++index) {
    // Page info lists it in place of GEOLOCATION only under
    // kApproximateGeolocationPermission, off on macOS; its structured value
    // has no row here.
    if (kSiteSettingTypes[index] ==
        ContentSettingsType::GEOLOCATION_WITH_OPTIONS) {
      continue;
    }
    PermissionSetting value;
    if (IsChanged(map, profile->IsOffTheRecord(), kSiteSettingTypes[index], url,
                  &value)) {
      settings.push_back({static_cast<SiteSettingType>(index),
                          ToSiteSettingValue(kSiteSettingTypes[index], value)});
    }
  }
  return settings;
}

std::optional<SiteSettingValue> GetSiteSetting(const std::string& profile_id,
                                               const std::string& origin,
                                               SiteSettingType type) {
  HostContentSettingsMap* map = LoadedMap(profile_id);
  const GURL url = OriginURL(origin);
  const ContentSettingsType content_type = ToContentSettingsType(type);
  if (!map || !url.is_valid() ||
      !content_settings::PermissionSettingsRegistry::GetInstance()->Get(
          content_type)) {
    return std::nullopt;
  }
  return ToSiteSettingValue(
      content_type, map->GetPermissionSetting(url, url, content_type, nullptr));
}

void SetSiteSetting(const std::string& profile_id,
                    const std::string& origin,
                    SiteSettingType type,
                    SiteSettingValue value) {
  const GURL url = OriginURL(origin);
  const ContentSettingsType content_type = ToContentSettingsType(type);
  if (!url.is_valid() ||
      !content_settings::ContentSettingsRegistry::GetInstance()->Get(
          content_type)) {
    return;
  }
  // As ArcCore's SiteSettingsManager: SiteSettingsHandler::
  // HandleSetOriginPermissions for one type, without its reload infobar.
  LoadBrowserProfile(
      profile_id,
      base::BindOnce(
          [](const GURL& url, ContentSettingsType type, ContentSetting setting,
             Profile* profile) {
            if (!profile) {
              return;
            }
            // Site Controls is the app's page info.
            permissions::PermissionUmaUtil::ScopedRevocationReporter reporter(
                profile, url, url, type, permissions::PermissionSourceUI::OIB);
            if (setting != CONTENT_SETTING_BLOCK) {
              if (permissions::PermissionDecisionAutoBlocker* blocker =
                      PermissionDecisionAutoBlockerFactory::GetForProfile(
                          profile)) {
                blocker->RemoveEmbargoAndResetCounts(url, type);
              }
            }
            HostContentSettingsMapFactory::GetForProfile(profile)
                ->SetContentSettingDefaultScope(url, url, type, setting);
          },
          url, content_type, ToContentSetting(content_type, value)));
}

}  // namespace oa
