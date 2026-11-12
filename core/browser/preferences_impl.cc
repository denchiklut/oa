// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "oa/browser/profile_services.h"
#include "oa/public/preferences.h"

namespace oa {
namespace {

// As ArcCore's preferences_impl.cc: a registrar on the profile's prefs whose
// changes go to the app's observer.
class PreferencesImpl : public Preferences, public ProfileObserver {
 public:
  PreferencesImpl(const std::string& profile_id, Observer* observer)
      : profile_id_(profile_id), observer_(observer) {
    LoadBrowserProfile(profile_id, base::BindOnce(&PreferencesImpl::Start,
                                                  weak_factory_.GetWeakPtr()));
  }

  // Preferences:
  void SetDownloadDirectory(const std::string& directory) override {
    LoadBrowserProfile(
        profile_id_,
        base::BindOnce(
            [](const base::FilePath& directory, Profile* profile) {
              if (profile) {
                DownloadPrefs::FromBrowserContext(profile)->SetDownloadPath(
                    directory);
              }
            },
            base::FilePath(directory)));
  }
  void SetAsksWhereToSaveDownloads(bool asks) override {
    LoadBrowserProfile(profile_id_, base::BindOnce(
                                        [](bool asks, Profile* profile) {
                                          if (profile) {
                                            profile->GetPrefs()->SetBoolean(
                                                prefs::kPromptForDownload,
                                                asks);
                                          }
                                        },
                                        asks));
  }

  // ProfileObserver:
  void OnProfileWillBeDestroyed(Profile* profile) override {
    registrar_.RemoveAll();
    profile_observation_.Reset();
    profile_ = nullptr;
  }

 private:
  void Start(Profile* profile) {
    if (!profile) {
      return;
    }
    profile_ = profile;
    profile_observation_.Observe(profile);
    registrar_.Init(profile->GetPrefs());
    const auto changed = base::BindRepeating(
        &PreferencesImpl::DownloadLocationChanged, base::Unretained(this));
    registrar_.Add(prefs::kDownloadDefaultDirectory, changed);
    registrar_.Add(prefs::kPromptForDownload, changed);
    DownloadLocationChanged();
  }

  // Posted, so DownloadPrefs has taken the new value first.
  void DownloadLocationChanged() {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&PreferencesImpl::ReportDownloadLocation,
                                  weak_factory_.GetWeakPtr()));
  }

  void ReportDownloadLocation() {
    if (!profile_) {
      return;
    }
    DownloadPrefs* prefs = DownloadPrefs::FromBrowserContext(profile_);
    observer_->OnDownloadLocationChanged(
        {prefs->DownloadPath().value(), prefs->PromptForDownload()});
  }

  const std::string profile_id_;
  raw_ptr<Observer> observer_;
  raw_ptr<Profile> profile_ = nullptr;
  PrefChangeRegistrar registrar_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::WeakPtrFactory<PreferencesImpl> weak_factory_{this};
};

}  // namespace

std::unique_ptr<Preferences> ObservePreferences(
    const std::string& profile_id,
    Preferences::Observer* observer) {
  return std::make_unique<PreferencesImpl>(profile_id, observer);
}

}  // namespace oa
