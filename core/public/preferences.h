// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_PREFERENCES_H_
#define OA_PUBLIC_PREFERENCES_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

// A profile's preferences the app reads and sets, as ArcCore's browser context
// preferences does. No Chromium headers here.

namespace oa {

struct DownloadLocation {
  // Where downloads go and where a Save panel starts.
  std::string directory;
  // Chromium asks where to save each download, in its Save panel.
  bool asks_each_time = false;
};

// One of Chromium's search engines, as ArcCore's ArcSearchEngine.
struct SearchEngine {
  std::string name;
  std::string keyword;
  // Chromium's URL template, with {searchTerms}.
  std::string url;
  std::string favicon_url;
  bool is_prepopulated = false;
};

class Preferences {
 public:
  // Every call is posted, as ArcCore posts its observers'.
  class Observer {
   public:
    // Once the profile has loaded, then after each change from anywhere,
    // Chrome's settings page included.
    virtual void OnDownloadLocationChanged() = 0;
    // Chromium's search engines or the default among them changed.
    virtual void OnSearchEnginesChanged() = 0;
    virtual void OnSearchSuggestEnabledChanged() = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Preferences() = default;

  // Read from the profile when asked, as ArcCore's getters are; nullopt until
  // the profile has loaded.
  virtual std::optional<DownloadLocation> GetDownloadLocation() const = 0;
  // Chrome's download.default_directory and savefile.default_directory.
  virtual void SetDownloadDirectory(const std::string& directory) = 0;
  // Chrome's download.prompt_for_download.
  virtual void SetAsksWhereToSaveDownloads(bool asks) = 0;

  // The engines Chrome's settings offer as the default; nullopt until the
  // profile's search engines have loaded.
  virtual std::optional<std::vector<SearchEngine>> GetSearchEngines() const = 0;
  virtual std::optional<SearchEngine> GetDefaultSearchEngine() const = 0;
  // By keyword, as the user's choice, as Chrome's settings page sets it.
  virtual void SetDefaultSearchEngine(const std::string& keyword) = 0;
  // Chrome's search.suggest_enabled; nullopt until the profile has loaded.
  virtual std::optional<bool> GetSearchSuggestEnabled() const = 0;
  virtual void SetSearchSuggestEnabled(bool enabled) = 0;
};

// Loads the app profile `profile_id` if needed, then reports its preferences
// to `observer` until the result is destroyed.
std::unique_ptr<Preferences> ObservePreferences(
    const std::string& profile_id,
    Preferences::Observer* observer);

}  // namespace oa

#endif  // OA_PUBLIC_PREFERENCES_H_
