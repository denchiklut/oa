// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_DOWNLOADS_H_
#define OA_PUBLIC_DOWNLOADS_H_

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// A profile's downloads as Chromium runs and remembers them, in the shape of
// ArcCore's browser context downloads and its download item. No Chromium
// headers here.

namespace oa {

class Page;

// Chromium's DownloadItem::DownloadState.
enum class DownloadState {
  kInProgress,
  kComplete,
  kCancelled,
  kInterrupted,
};

// One download at the time of an event.
struct Download {
  // Chromium's GUID for it, the same after a relaunch.
  std::string id;
  DownloadState state = DownloadState::kInProgress;
  int64_t received_bytes = 0;
  // 0 while the size is unknown.
  int64_t total_bytes = 0;
  int64_t bytes_per_second = 0;
  // -1 while Chromium has no estimate, as ArcCore reports it.
  int64_t remaining_seconds = -1;
  // Empty until Chromium has chosen where the file goes.
  std::string target_path;
  std::string source_url;
  // Seconds since 1970.
  double start_time = 0;
  bool is_paused = false;
  bool is_done = false;
  bool can_resume = false;
};

class Downloads {
 public:
  // Every call is posted, as ArcCore posts its delegate's, so the app may act
  // on a download from inside one.
  class Observer {
   public:
    // Once, with the downloads Chromium's history brought back and any already
    // running.
    virtual void OnDownloadsInitialized(
        const std::vector<Download>& downloads) = 0;
    // `page` started it and is still open; null otherwise, as for a download
    // from an earlier launch.
    virtual void OnDownloadCreated(const Download& download, Page* page) = 0;
    virtual void OnDownloadUpdated(const Download& download, Page* page) = 0;
    // Gone from Chromium's history too; its file stays.
    virtual void OnDownloadRemoved(const std::string& id) = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Downloads() = default;

  virtual void Pause(const std::string& id) = 0;
  virtual void Resume(const std::string& id) = 0;
  // Deletes the partial file.
  virtual void Cancel(const std::string& id) = 0;
  // Cancels it first if it is running.
  virtual void Remove(const std::string& id) = 0;
};

// Loads the app profile `profile_id` if needed, then reports its downloads to
// `observer` until the result is destroyed.
std::unique_ptr<Downloads> ObserveDownloads(const std::string& profile_id,
                                            Downloads::Observer* observer);

}  // namespace oa

#endif  // OA_PUBLIC_DOWNLOADS_H_
