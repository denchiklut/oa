// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_SESSION_RESTORATION_H_
#define OA_BROWSER_SESSION_RESTORATION_H_

#include <cstdint>
#include <optional>
#include <string>

class Profile;

namespace content {
class WebContents;
}

namespace oa {

// ADK's SessionRestorationState: while a profile the app asked a Browser of is
// still to restore its last session, or restoring it, every Browser parks the
// tabs Chrome adds. When no profile is, each hands its parked pages over.
class SessionRestoration {
 public:
  static void Install();
  // The app asked for a Browser in `profile_id`.
  static void Expect(const std::string& profile_id);
  // That Browser is there, Chrome having started the profile's restore with it
  // or not; `profile` is null if it couldn't load.
  static void Resolve(const std::string& profile_id, Profile* profile);
  // Chrome can drop a restore with the Browser that started it.
  static void OnBrowserGone();
  static bool IsWaiting();
  // The session ID `contents`' tab had in the last session, if Chrome restored
  // it from there.
  static std::optional<int32_t> LastSessionID(content::WebContents* contents);
  // As ADK's onFinishedRestoringWindows: from now on, a Browser Chrome
  // restored for a window the app didn't bring back is closed.
  static void FinishedRestoringWindows();
};

}  // namespace oa

#endif  // OA_BROWSER_SESSION_RESTORATION_H_
