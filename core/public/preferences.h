// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_PREFERENCES_H_
#define OA_PUBLIC_PREFERENCES_H_

#include <memory>
#include <string>

// A profile's preferences the app reads and sets, as ArcCore's browser context
// preferences does. No Chromium headers here.

namespace oa {

struct DownloadLocation {
  // Where downloads go and where a Save panel starts.
  std::string directory;
  // Chromium asks where to save each download, in its Save panel.
  bool asks_each_time = false;
};

class Preferences {
 public:
  // Every call is posted, as ArcCore posts its observers'.
  class Observer {
   public:
    // Once the profile has loaded, then after each change from anywhere,
    // Chrome's settings page included.
    virtual void OnDownloadLocationChanged(
        const DownloadLocation& location) = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Preferences() = default;

  // Chrome's download.default_directory and savefile.default_directory.
  virtual void SetDownloadDirectory(const std::string& directory) = 0;
  // Chrome's download.prompt_for_download.
  virtual void SetAsksWhereToSaveDownloads(bool asks) = 0;
};

// Loads the app profile `profile_id` if needed, then reports its preferences
// to `observer` until the result is destroyed.
std::unique_ptr<Preferences> ObservePreferences(
    const std::string& profile_id,
    Preferences::Observer* observer);

}  // namespace oa

#endif  // OA_PUBLIC_PREFERENCES_H_
