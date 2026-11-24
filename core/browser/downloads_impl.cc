// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include <optional>
#include <utility>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_core_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/common/pref_names.h"
#include "components/download/content/public/all_download_item_notifier.h"
#include "components/download/public/common/download_item.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/download_manager.h"
#include "oa/browser/page_impl.h"
#include "oa/browser/profile_services.h"
#include "oa/public/downloads.h"
#include "url/gurl.h"

namespace oa {
namespace {

DownloadState ToDownloadState(download::DownloadItem::DownloadState state) {
  switch (state) {
    case download::DownloadItem::COMPLETE:
      return DownloadState::kComplete;
    case download::DownloadItem::CANCELLED:
      return DownloadState::kCancelled;
    case download::DownloadItem::INTERRUPTED:
      return DownloadState::kInterrupted;
    default:
      return DownloadState::kInProgress;
  }
}

Download ToDownload(download::DownloadItem* item) {
  Download download;
  download.id = item->GetGuid();
  download.state = ToDownloadState(item->GetState());
  download.received_bytes = item->GetReceivedBytes();
  download.total_bytes = item->GetTotalBytes();
  download.bytes_per_second = item->CurrentSpeed();
  base::TimeDelta remaining;
  if (item->TimeRemaining(&remaining)) {
    download.remaining_seconds = remaining.InSeconds();
  }
  download.target_path = item->GetTargetFilePath().value();
  download.source_url = item->GetURL().spec();
  download.start_time = item->GetStartTime().InSecondsFSinceUnixEpoch();
  download.is_paused = item->IsPaused();
  download.is_done = item->IsDone();
  download.can_resume = item->CanResume();
  return download;
}

// Oa's own: what Chrome's downloads page leaves out too, the fetches Chromium
// makes for itself.
bool IsListed(download::DownloadItem* item) {
  return !item->IsTransient() && !item->IsTemporary();
}

// As ArcCore's: an observer of every item of the context's DownloadManager,
// beside Chrome's own delegate, history and target determiner. An incognito
// one follows its profile's off-the-record profile as Chromium makes and
// destroys it.
class DownloadsImpl : public Downloads,
                      public download::AllDownloadItemNotifier::Observer,
                      public ProfileObserver {
 public:
  DownloadsImpl(const std::string& profile_id,
                BrowserContextType type,
                Downloads::Observer* observer)
      : type_(type), observer_(observer) {
    LoadBrowserProfile(profile_id, base::BindOnce(&DownloadsImpl::Start,
                                                  weak_factory_.GetWeakPtr()));
  }

  // Downloads:
  void Pause(const std::string& id) override {
    if (download::DownloadItem* item = Find(id)) {
      item->Pause();
    }
  }
  void Resume(const std::string& id) override {
    if (download::DownloadItem* item = Find(id)) {
      item->Resume(/*user_resume=*/true);
    }
  }
  void Cancel(const std::string& id) override {
    if (download::DownloadItem* item = Find(id)) {
      item->Cancel(/*user_cancel=*/true);
    }
  }
  void Remove(const std::string& id) override {
    if (download::DownloadItem* item = Find(id)) {
      item->Remove();
    }
  }

  // download::AllDownloadItemNotifier::Observer:
  void OnManagerInitialized(content::DownloadManager* manager) override {
    content::DownloadManager::DownloadVector items;
    manager->GetAllDownloads(&items);
    std::vector<Download> downloads;
    for (download::DownloadItem* item : items) {
      if (IsListed(item)) {
        downloads.push_back(ToDownload(item));
      }
    }
    Post(base::BindOnce(
        [](std::vector<Download> downloads, Downloads::Observer* observer) {
          observer->OnDownloadsInitialized(downloads);
        },
        std::move(downloads)));
  }
  void OnDownloadCreated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    PostItem(item, &Downloads::Observer::OnDownloadCreated);
  }
  void OnDownloadUpdated(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    PostItem(item, &Downloads::Observer::OnDownloadUpdated);
  }
  void OnDownloadRemoved(content::DownloadManager* manager,
                         download::DownloadItem* item) override {
    if (!IsListed(item)) {
      return;
    }
    Post(base::BindOnce(
        [](std::string id, Downloads::Observer* observer) {
          observer->OnDownloadRemoved(id);
        },
        item->GetGuid()));
  }
  // As seen in Arc: an incognito context's downloads leave the list with it.
  void OnManagerGoingDown(content::DownloadManager* manager) override {
    if (type_ != BrowserContextType::kIncognito) {
      return;
    }
    content::DownloadManager::DownloadVector items;
    manager->GetAllDownloads(&items);
    for (download::DownloadItem* item : items) {
      OnDownloadRemoved(manager, item);
    }
  }

  // ProfileObserver:
  // Posted: the profile is still being set up when this is called.
  void OnOffTheRecordProfileCreated(Profile* off_the_record) override {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&DownloadsImpl::WatchOffTheRecord,
                                  weak_factory_.GetWeakPtr()));
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    notifier_.reset();
    profile_observation_.Reset();
  }

 private:
  void Start(Profile* profile) {
    if (!profile) {
      return;
    }
    if (type_ == BrowserContextType::kIncognito) {
      profile_observation_.Observe(profile);
      WatchOffTheRecord();
      return;
    }
    notifier_.emplace(profile->GetDownloadManager(), this);
    // Under kDeferredDownloadHistoryLoading the history waits for a download
    // UI to ask for it, as Chrome's bubble and downloads page do.
    DownloadCoreServiceFactory::GetForBrowserContext(profile)
        ->InitializeHistory(
            DownloadCoreService::DownloadHistoryLoadTrigger::kDownloadBubble);
  }

  void WatchOffTheRecord() {
    Profile* profile = profile_observation_.GetSource();
    Profile* off_the_record =
        profile ? profile->GetPrimaryOTRProfile(/*create_if_needed=*/false)
                : nullptr;
    if (!off_the_record) {
      return;
    }
    notifier_.emplace(off_the_record->GetDownloadManager(), this);
    // Chrome's download UI, made with the manager, sets an off-the-record
    // profile to ask where each file goes. Arc's doesn't ask (seen), so the
    // profile's own setting shows through again.
    off_the_record->GetPrefs()->ClearPref(prefs::kPromptForDownload);
  }

  download::DownloadItem* Find(const std::string& id) {
    content::DownloadManager* manager =
        notifier_ ? notifier_->GetManager() : nullptr;
    return manager ? manager->GetDownloadByGuid(id) : nullptr;
  }

  void PostItem(download::DownloadItem* item,
                void (Downloads::Observer::*event)(const Download&, Page*)) {
    if (!IsListed(item)) {
      return;
    }
    content::WebContents* contents =
        content::DownloadItemUtils::GetWebContents(item);
    PageImpl* page = contents ? PageImpl::FromWebContents(contents) : nullptr;
    Post(base::BindOnce(
        [](Download download, base::WeakPtr<PageImpl> page,
           void (Downloads::Observer::*event)(const Download&, Page*),
           Downloads::Observer* observer) {
          (observer->*event)(download, page.get());
        },
        ToDownload(item), page ? page->GetWeakPtr() : nullptr, event));
  }

  void Post(base::OnceCallback<void(Downloads::Observer*)> call) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](base::WeakPtr<DownloadsImpl> self,
                          base::OnceCallback<void(Downloads::Observer*)> call) {
                         if (self) {
                           std::move(call).Run(self->observer_);
                         }
                       },
                       weak_factory_.GetWeakPtr(), std::move(call)));
  }

  const BrowserContextType type_;
  raw_ptr<Downloads::Observer> observer_;
  std::optional<download::AllDownloadItemNotifier> notifier_;
  base::ScopedObservation<Profile, ProfileObserver> profile_observation_{this};
  base::WeakPtrFactory<DownloadsImpl> weak_factory_{this};
};

}  // namespace

std::unique_ptr<Downloads> ObserveDownloads(const std::string& profile_id,
                                            BrowserContextType type,
                                            Downloads::Observer* observer) {
  return std::make_unique<DownloadsImpl>(profile_id, type, observer);
}

}  // namespace oa
