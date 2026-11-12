// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "base/files/file_path.h"
#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "chrome/common/pref_names.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "components/search_engines/template_url_service_observer.h"
#include "oa/browser/profile_services.h"
#include "oa/public/preferences.h"

namespace oa {
namespace {

SearchEngine ToSearchEngine(const TemplateURL& engine) {
  return SearchEngine{base::UTF16ToUTF8(engine.short_name()),
                      base::UTF16ToUTF8(engine.keyword()), engine.url(),
                      engine.favicon_url().spec(), engine.prepopulate_id() > 0};
}

// As ArcCore's preferences_impl.cc: a registrar on the profile's prefs whose
// changes go to the app's observer, and Chromium's search engines.
class PreferencesImpl : public Preferences,
                        public ProfileObserver,
                        public TemplateURLServiceObserver {
 public:
  PreferencesImpl(const std::string& profile_id, Observer* observer)
      : profile_id_(profile_id), observer_(observer) {
    LoadBrowserProfile(profile_id, base::BindOnce(&PreferencesImpl::Start,
                                                  weak_factory_.GetWeakPtr()));
  }

  // Preferences:
  std::optional<DownloadLocation> GetDownloadLocation() const override {
    if (!profile_) {
      return std::nullopt;
    }
    DownloadPrefs* prefs = DownloadPrefs::FromBrowserContext(profile_);
    return DownloadLocation{prefs->DownloadPath().value(),
                            prefs->PromptForDownload()};
  }
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

  std::optional<std::vector<SearchEngine>> GetSearchEngines() const override {
    TemplateURLService* service = LoadedSearchEngines();
    if (!service) {
      return std::nullopt;
    }
    std::vector<SearchEngine> engines;
    for (const TemplateURL* engine : service->GetTemplateURLs()) {
      if (service->ShowInDefaultList(engine)) {
        engines.push_back(ToSearchEngine(*engine));
      }
    }
    return engines;
  }
  std::optional<SearchEngine> GetDefaultSearchEngine() const override {
    TemplateURLService* service = LoadedSearchEngines();
    const TemplateURL* engine =
        service ? service->GetDefaultSearchProvider() : nullptr;
    if (!engine) {
      return std::nullopt;
    }
    return ToSearchEngine(*engine);
  }
  void SetDefaultSearchEngine(const std::string& keyword) override {
    TemplateURLService* service = LoadedSearchEngines();
    TemplateURL* engine =
        service ? service->GetTemplateURLForKeyword(base::UTF8ToUTF16(keyword))
                : nullptr;
    if (engine && service->CanMakeDefault(engine)) {
      service->SetUserSelectedDefaultSearchProvider(engine);
    }
  }
  std::optional<bool> GetSearchSuggestEnabled() const override {
    if (!profile_) {
      return std::nullopt;
    }
    return profile_->GetPrefs()->GetBoolean(prefs::kSearchSuggestEnabled);
  }
  void SetSearchSuggestEnabled(bool enabled) override {
    LoadBrowserProfile(profile_id_, base::BindOnce(
                                        [](bool enabled, Profile* profile) {
                                          if (profile) {
                                            profile->GetPrefs()->SetBoolean(
                                                prefs::kSearchSuggestEnabled,
                                                enabled);
                                          }
                                        },
                                        enabled));
  }

  // TemplateURLServiceObserver:
  void OnTemplateURLServiceChanged() override {
    Post(&Observer::OnSearchEnginesChanged);
  }
  void OnTemplateURLServiceShuttingDown() override {
    search_engines_observation_.Reset();
  }

  // ProfileObserver:
  void OnProfileWillBeDestroyed(Profile* profile) override {
    search_engines_observation_.Reset();
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
    registrar_.Add(
        prefs::kSearchSuggestEnabled,
        base::BindRepeating(&PreferencesImpl::Post, base::Unretained(this),
                            &Observer::OnSearchSuggestEnabledChanged));
    DownloadLocationChanged();
    Post(&Observer::OnSearchSuggestEnabledChanged);
    if (TemplateURLService* service =
            TemplateURLServiceFactory::GetForProfile(profile)) {
      search_engines_observation_.Observe(service);
      if (service->loaded()) {
        Post(&Observer::OnSearchEnginesChanged);
      } else {
        service->Load();
      }
    }
  }

  TemplateURLService* LoadedSearchEngines() const {
    TemplateURLService* service =
        profile_ ? TemplateURLServiceFactory::GetForProfile(profile_) : nullptr;
    return service && service->loaded() ? service : nullptr;
  }

  void Post(void (Observer::*event)()) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&PreferencesImpl::Report,
                                  weak_factory_.GetWeakPtr(), event));
  }

  void Report(void (Observer::*event)()) {
    if (profile_) {
      (observer_.get()->*event)();
    }
  }

  // Posted, so DownloadPrefs has taken the new value before it is read.
  void DownloadLocationChanged() {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&PreferencesImpl::ReportDownloadLocation,
                                  weak_factory_.GetWeakPtr()));
  }

  void ReportDownloadLocation() {
    if (profile_) {
      observer_->OnDownloadLocationChanged();
    }
  }

  const std::string profile_id_;
  raw_ptr<Observer> observer_;
  raw_ptr<Profile> profile_ = nullptr;
  PrefChangeRegistrar registrar_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::ScopedObservation<TemplateURLService, TemplateURLServiceObserver>
      search_engines_observation_{this};
  base::WeakPtrFactory<PreferencesImpl> weak_factory_{this};
};

}  // namespace

std::unique_ptr<Preferences> ObservePreferences(
    const std::string& profile_id,
    Preferences::Observer* observer) {
  return std::make_unique<PreferencesImpl>(profile_id, observer);
}

}  // namespace oa
