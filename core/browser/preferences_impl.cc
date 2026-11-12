// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_service.h"
#include "oa/browser/profile_services.h"
#include "oa/public/preferences.h"

namespace oa {

std::optional<DownloadLocation> GetDownloadLocation(
    const std::string& profile_id) {
  Profile* profile = GetLoadedBrowserProfile(profile_id);
  if (!profile) {
    return std::nullopt;
  }
  DownloadPrefs* prefs = DownloadPrefs::FromBrowserContext(profile);
  return DownloadLocation{prefs->DownloadPath().value(),
                          prefs->PromptForDownload()};
}

void SetDownloadDirectory(const std::string& profile_id,
                          const std::string& directory) {
  LoadBrowserProfile(
      profile_id,
      base::BindOnce(
          [](const base::FilePath& directory, Profile* profile) {
            if (profile) {
              DownloadPrefs::FromBrowserContext(profile)->SetDownloadPath(
                  directory);
            }
          },
          base::FilePath(directory)));
}

void SetAsksWhereToSaveDownloads(const std::string& profile_id, bool asks) {
  LoadBrowserProfile(profile_id, base::BindOnce(
                                     [](bool asks, Profile* profile) {
                                       if (profile) {
                                         profile->GetPrefs()->SetBoolean(
                                             prefs::kPromptForDownload, asks);
                                       }
                                     },
                                     asks));
}

}  // namespace oa
