// Copyright 2026 The Oa Authors
#ifndef OA_BROWSER_PROFILE_SERVICES_H_
#define OA_BROWSER_PROFILE_SERVICES_H_

#include <string>

#include "base/functional/callback.h"
#include "oa/public/profiles.h"
class Profile;
namespace oa {
// Loads an app profile asynchronously, without exposing Profile across the
// public bridge.
void LoadBrowserProfile(const std::string& identifier,
                        base::OnceCallback<void(Profile*)> ready);
// The app profile's Chromium profile if it has loaded, else null.
Profile* GetLoadedBrowserProfile(const std::string& identifier);
// The profile's context of `type`, loading the profile if needed. An incognito
// one is null while Chrome's policy disallows it. Chromium destroys it when its
// last Browser closes; the next call makes a new one.
void LoadBrowserContext(const std::string& identifier,
                        BrowserContextType type,
                        base::OnceCallback<void(Profile*)> ready);
// Null until loaded, and for an incognito one Chromium doesn't have.
Profile* GetLoadedBrowserContext(const std::string& identifier,
                                 BrowserContextType type);
// The app profile a context is of, its own or its incognito one.
std::string GetBrowserProfileIdentifier(Profile* context);
// Before the browser process tears down: a raw_ptr still pointing at a profile
// ProfileManager destroyed aborts the exit.
void UnloadBrowserProfiles();
}  // namespace oa
#endif
