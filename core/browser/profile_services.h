// Copyright 2026 The Oa Authors
#ifndef OA_BROWSER_PROFILE_SERVICES_H_
#define OA_BROWSER_PROFILE_SERVICES_H_

#include <string>

#include "base/functional/callback.h"
class Profile;
namespace oa {
// Loads an app profile asynchronously, without exposing Profile across the
// public bridge.
void LoadBrowserProfile(const std::string& identifier,
                        base::OnceCallback<void(Profile*)> ready);
// The app profile's Chromium profile if it has loaded, else null.
Profile* GetLoadedBrowserProfile(const std::string& identifier);
// Before the browser process tears down: a raw_ptr still pointing at a profile
// ProfileManager destroyed aborts the exit.
void UnloadBrowserProfiles();
}  // namespace oa
#endif
