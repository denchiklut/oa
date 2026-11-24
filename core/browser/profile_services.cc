// Copyright 2026 The Oa Authors
#include "oa/browser/profile_services.h"

#include <map>
#include <memory>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/prefs/incognito_mode_prefs.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_attributes_entry.h"
#include "chrome/browser/profiles/profile_attributes_init_params.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profile_metrics.h"
#include "oa/public/profiles.h"

namespace oa {
namespace {
struct ProfileEntry {
  raw_ptr<Profile> profile = nullptr;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
  std::vector<base::OnceCallback<void(Profile*)>> callbacks;
  bool ready = false;
};
constexpr char kDirectoryPrefix[] = "Oa-";

auto& Entries() {
  static base::NoDestructor<std::map<std::string, ProfileEntry>> entries;
  return *entries;
}

// Identifiers are app UUIDs, never user-supplied directory paths.
bool IsValidIdentifier(const std::string& identifier) {
  return !identifier.empty() && identifier.size() <= 64 &&
         base::ContainsOnlyChars(identifier, "0123456789abcdefABCDEF-");
}

base::FilePath ProfilePath(const std::string& identifier) {
  return g_browser_process->profile_manager()->user_data_dir().AppendASCII(
      kDirectoryPrefix + identifier);
}

Profile* ContextOf(Profile* profile, BrowserContextType type, bool create) {
  if (!profile || type == BrowserContextType::kNormal) {
    return profile;
  }
  return IncognitoModePrefs::IsIncognitoAllowed(profile)
             ? profile->GetPrimaryOTRProfile(create)
             : nullptr;
}

bool SetLocalName(const std::string& identifier, const std::string& name) {
  ProfileAttributesEntry* entry =
      g_browser_process->profile_manager()
          ->GetProfileAttributesStorage()
          .GetProfileAttributesWithPath(ProfilePath(identifier));
  if (entry) {
    entry->SetLocalProfileName(base::UTF8ToUTF16(name),
                               /*is_default_name=*/false);
  }
  return entry != nullptr;
}
}  // namespace

void LoadBrowserProfile(const std::string& identifier,
                        base::OnceCallback<void(Profile*)> ready) {
  if (!IsValidIdentifier(identifier)) {
    std::move(ready).Run(nullptr);
    return;
  }
  auto [it, inserted] = Entries().try_emplace(identifier);
  auto& entry = it->second;
  if (entry.ready) {
    std::move(ready).Run(entry.profile);
    return;
  }
  entry.callbacks.push_back(std::move(ready));
  if (!inserted) {
    return;
  }
  auto* manager = g_browser_process->profile_manager();
  manager->CreateProfileAsync(
      ProfilePath(identifier),
      base::BindOnce(
          [](std::string key, Profile* profile) {
            auto found = Entries().find(key);
            // Deleted while it loaded.
            if (found == Entries().end()) {
              return;
            }
            auto& entry = found->second;
            entry.profile = profile;
            if (profile) {
              entry.keep_alive = std::make_unique<ScopedProfileKeepAlive>(
                  profile, ProfileKeepAliveOrigin::kBrowserWindow);
            }
            entry.ready = true;
            auto callbacks = std::move(entry.callbacks);
            for (auto& callback : callbacks) {
              std::move(callback).Run(profile);
            }
          },
          identifier));
}

Profile* GetLoadedBrowserProfile(const std::string& identifier) {
  auto found = Entries().find(identifier);
  if (found == Entries().end() || !found->second.ready) {
    return nullptr;
  }
  return found->second.profile;
}

void LoadBrowserContext(const std::string& identifier,
                        BrowserContextType type,
                        base::OnceCallback<void(Profile*)> ready) {
  LoadBrowserProfile(
      identifier,
      base::BindOnce(
          [](BrowserContextType type, base::OnceCallback<void(Profile*)> ready,
             Profile* profile) {
            std::move(ready).Run(ContextOf(profile, type, /*create=*/true));
          },
          type, std::move(ready)));
}

Profile* GetLoadedBrowserContext(const std::string& identifier,
                                 BrowserContextType type) {
  return ContextOf(GetLoadedBrowserProfile(identifier), type,
                   /*create=*/false);
}

bool IsIncognitoDisabled(const std::string& profile_id) {
  Profile* profile = GetLoadedBrowserProfile(profile_id);
  return profile && !IncognitoModePrefs::IsIncognitoAllowed(profile);
}

std::vector<ProfileAttributes> GetAvailableProfileAttributes() {
  std::vector<ProfileAttributes> profiles;
  for (ProfileAttributesEntry* entry : g_browser_process->profile_manager()
                                           ->GetProfileAttributesStorage()
                                           .GetAllProfilesAttributes()) {
    const std::string directory = entry->GetPath().BaseName().AsUTF8Unsafe();
    // Chrome's initial profile is there too; the app never uses it.
    if (auto identifier = base::RemovePrefix(directory, kDirectoryPrefix)) {
      profiles.push_back({.id = std::string(*identifier),
                          .name = base::UTF16ToUTF8(entry->GetName())});
    }
  }
  return profiles;
}

void CreateProfile(const std::string& name,
                   std::function<void(const std::string&)> completion) {
  const std::string identifier =
      base::ToUpperASCII(base::Uuid::GenerateRandomV4().AsLowercaseString());
  // The entry first, so the profile starts with the name: Chrome reads it from
  // there when it sets up the new profile's preferences.
  ProfileAttributesInitParams params;
  params.profile_path = ProfilePath(identifier);
  params.profile_name = base::UTF8ToUTF16(name);
  g_browser_process->profile_manager()
      ->GetProfileAttributesStorage()
      .AddProfile(std::move(params));
  LoadBrowserProfile(identifier,
                     base::BindOnce(
                         [](std::string identifier,
                            std::function<void(const std::string&)> completion,
                            Profile* profile) {
                           completion(profile ? identifier : std::string());
                         },
                         identifier, std::move(completion)));
}

void SetProfileName(const std::string& profile_id, const std::string& name) {
  if (!IsValidIdentifier(profile_id)) {
    return;
  }
  if (SetLocalName(profile_id, name)) {
    return;
  }
  LoadBrowserProfile(profile_id, base::BindOnce(
                                     [](std::string identifier,
                                        std::string name, Profile* profile) {
                                       if (profile) {
                                         SetLocalName(identifier, name);
                                       }
                                     },
                                     profile_id, name));
}

bool DeleteProfile(const std::string& profile_id) {
  if (!IsValidIdentifier(profile_id)) {
    return false;
  }
  auto* manager = g_browser_process->profile_manager();
  const base::FilePath path = ProfilePath(profile_id);
  if (!manager->GetProfileByPath(path) &&
      !manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(
          path)) {
    return false;
  }
  // As ArcCore: its own hold on the profile goes first, so Chrome can unload
  // it and wipe the directory now rather than at the next launch.
  auto found = Entries().find(profile_id);
  if (found != Entries().end()) {
    auto callbacks = std::move(found->second.callbacks);
    Entries().erase(found);
    for (auto& callback : callbacks) {
      std::move(callback).Run(nullptr);
    }
  }
  manager->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(
      path, base::DoNothing(), ProfileMetrics::DELETE_PROFILE_SETTINGS);
  return true;
}

void UnloadBrowserProfiles() {
  auto entries = std::move(Entries());
  Entries().clear();
  for (auto& [identifier, entry] : entries) {
    for (auto& callback : entry.callbacks) {
      std::move(callback).Run(nullptr);
    }
  }
}
}  // namespace oa
