// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_PREFERENCES_H_
#define OA_PUBLIC_PREFERENCES_H_

#include <optional>
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

// Nullopt until the app profile `profile_id` has loaded.
std::optional<DownloadLocation> GetDownloadLocation(
    const std::string& profile_id);

// Chrome's download.default_directory and savefile.default_directory.
void SetDownloadDirectory(const std::string& profile_id,
                          const std::string& directory);

// Chrome's download.prompt_for_download.
void SetAsksWhereToSaveDownloads(const std::string& profile_id, bool asks);

}  // namespace oa

#endif  // OA_PUBLIC_PREFERENCES_H_
