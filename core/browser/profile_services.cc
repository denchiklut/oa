// Copyright 2026 The Oa Authors
#include "oa/browser/profile_services.h"

#include <map>
#include <memory>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/string_util.h"
#include "base/functional/callback_helpers.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/delete_profile_helper.h"
#include "chrome/browser/profiles/profile_attributes_storage.h"
#include "chrome/browser/profiles/profile_metrics.h"
#include "chrome/browser/profiles/keep_alive/profile_keep_alive_types.h"
#include "chrome/browser/profiles/keep_alive/scoped_profile_keep_alive.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"

namespace oa {
namespace {
struct ProfileEntry {
  raw_ptr<Profile> profile = nullptr;
  std::unique_ptr<ScopedProfileKeepAlive> keep_alive;
  std::vector<base::OnceCallback<void(Profile*)>> callbacks;
  bool ready = false;
};
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
      "Oa-" + identifier);
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
  if (!inserted)
    return;
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
            for (auto& callback : callbacks)
              std::move(callback).Run(profile);
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

void DeleteBrowserProfile(const std::string& identifier) {
  if (!IsValidIdentifier(identifier)) {
    return;
  }
  // Callbacks still waiting for it get no profile.
  auto found = Entries().find(identifier);
  if (found != Entries().end()) {
    auto callbacks = std::move(found->second.callbacks);
    // Releases the keep-alive, so Chrome can unload the profile.
    Entries().erase(found);
    for (auto& callback : callbacks) {
      std::move(callback).Run(nullptr);
    }
  }
  auto* manager = g_browser_process->profile_manager();
  const base::FilePath path = ProfilePath(identifier);
  // A profile never loaded has no directory or attributes to delete.
  if (!manager->GetProfileByPath(path) &&
      !manager->GetProfileAttributesStorage().GetProfileAttributesWithPath(
          path)) {
    return;
  }
  // Closes the profile's Browsers, forgets it and wipes its directory: at once
  // if it can, else at the next launch (CleanUpDeletedProfiles).
  manager->GetDeleteProfileHelper().MaybeScheduleProfileForDeletion(
      path, base::DoNothing(), ProfileMetrics::DELETE_PROFILE_SETTINGS);
}
}  // namespace oa
