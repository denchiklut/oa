// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_HISTORY_H_
#define OA_PUBLIC_HISTORY_H_

#include <functional>
#include <string>
#include <vector>

// A profile's history and stored favicons, as ADK reaches them through
// ArcCore's history service and favicon provider. No Chromium headers here.

namespace oa {

struct HistoryEntry {
  std::string url;
  std::string title;
};

// Chromium's history text search in the app profile `profile_id`, newest
// first and at most `max_results`, as ArcCore's history query options ask it.
// It matches words of a page's URL and title, so a host can find another
// site's page. Loads the profile if needed; empty if it can't.
void QueryHistory(
    const std::string& profile_id,
    const std::string& search_text,
    int max_results,
    std::function<void(std::vector<HistoryEntry> entries)> completion);

// The 16 pt icon the profile's favicon service keeps for a page: an NSImage
// that lives only for the call, null when it has none.
void GetFaviconForPage(const std::string& profile_id,
                       const std::string& page_url,
                       std::function<void(void* ns_image)> completion);

}  // namespace oa

#endif  // OA_PUBLIC_HISTORY_H_
