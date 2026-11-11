// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_SITE_SETTINGS_H_
#define OA_PUBLIC_SITE_SETTINGS_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

// A profile's settings for a site, by origin, as Chrome's page info reads them
// (components/page_info/page_info.cc). No Chromium headers here.

namespace oa {

// The settings page info lists on macOS (its kPermissionType[]), in its order.
// Each is one of Chromium's ContentSettingsType values. The values are this
// list's positions, so they stay put when Chromium renumbers its types; append
// new ones at the end.
enum class SiteSettingType : int32_t {
  kGeolocation = 0,
  kGeolocationWithOptions = 1,
  kCamera = 2,
  kCameraPanTiltZoom = 3,
  kMicrophone = 4,
  kSensors = 5,
  kNotifications = 6,
  kJavaScript = 7,
  kImages = 8,
  kPopups = 9,
  kWindowManagement = 10,
  kAds = 11,
  kBackgroundSync = 12,
  kSound = 13,
  kAutomaticDownloads = 14,
  kMidiSysex = 15,
  kClipboardReadWrite = 16,
  kUsbGuard = 17,
  kHidGuard = 18,
  kSerialGuard = 19,
  kFileSystemWriteGuard = 20,
  kLocalFonts = 21,
  kBluetoothGuard = 22,
  kBluetoothScanning = 23,
  kHandTracking = 24,
  kVr = 25,
  kAr = 26,
  kIdleDetection = 27,
  kFederatedIdentityApi = 28,
  kAutomaticPictureInPicture = 29,
  kCapturedSurfaceControl = 30,
  kAutomaticFullscreen = 31,
  kKeyboardLock = 32,
  kPointerLock = 33,
  kWebAppInstallation = 34,
  kLocalNetwork = 35,
  kLoopbackNetwork = 36,
};

// What a setting lets the site do: Chromium's ContentSetting, with its values.
// A setting whose value isn't a ContentSetting, for example geolocation with
// options, reads as kDefault.
enum class SiteSettingValue : int32_t {
  kDefault = 0,
  kAllow = 1,
  kBlock = 2,
  kAsk = 3,
  kSessionOnly = 4,
};

struct SiteSetting {
  SiteSettingType type;
  SiteSettingValue value;
};

// The settings of `origin`'s site that differ from Chrome's: the site has its
// own value, something other than the user set it (a policy or an extension),
// or the user changed its default. In page info's order. Nullopt if the app
// profile `profile_id` hasn't loaded or `origin` isn't a valid URL. Only the
// URL's origin counts.
std::optional<std::vector<SiteSetting>> GetChangedSiteSettings(
    const std::string& profile_id,
    const std::string& origin);

// The value of one setting for `origin`'s site, whether or not it was changed.
// Nullopt as for GetChangedSiteSettings().
std::optional<SiteSettingValue> GetSiteSetting(const std::string& profile_id,
                                               const std::string& origin,
                                               SiteSettingType type);

// Sets one setting for `origin`'s site in the app profile `profile_id`, as
// Chrome's site settings page does: for the whole origin, without reloading
// its pages. kDefault resets it. Does nothing for an invalid URL, or a setting
// whose value isn't a ContentSetting.
void SetSiteSetting(const std::string& profile_id,
                    const std::string& origin,
                    SiteSettingType type,
                    SiteSettingValue value);

}  // namespace oa

#endif  // OA_PUBLIC_SITE_SETTINGS_H_
