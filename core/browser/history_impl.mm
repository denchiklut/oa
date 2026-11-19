// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#import <AppKit/AppKit.h>

#include <utility>

#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/cancelable_task_tracker.h"
#include "chrome/browser/favicon/favicon_service_factory.h"
#include "chrome/browser/history/history_service_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "components/favicon/core/favicon_service.h"
#include "components/favicon_base/favicon_types.h"
#include "components/history/core/browser/history_service.h"
#include "components/history/core/browser/history_types.h"
#include "components/keyed_service/core/service_access_type.h"
#include "oa/browser/profile_services.h"
#include "oa/public/history.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace oa {
namespace {

// Never destroyed: a query whose profile went away is dropped by its service.
base::CancelableTaskTracker& Tracker() {
  static base::NoDestructor<base::CancelableTaskTracker> tracker;
  return *tracker;
}

}  // namespace

void QueryHistory(const std::string& profile_id,
                  const std::string& search_text,
                  int max_results,
                  std::function<void(std::vector<HistoryEntry>)> completion) {
  LoadBrowserProfile(
      profile_id,
      base::BindOnce(
          [](const std::string& search_text, int max_results,
             std::function<void(std::vector<HistoryEntry>)> completion,
             Profile* profile) {
            history::HistoryService* service =
                profile ? HistoryServiceFactory::GetForProfile(
                              profile, ServiceAccessType::EXPLICIT_ACCESS)
                        : nullptr;
            if (!service) {
              completion({});
              return;
            }
            history::QueryOptions options;
            options.max_count = max_results;
            service->QueryHistory(
                base::UTF8ToUTF16(search_text), options,
                base::BindOnce(
                    [](std::function<void(std::vector<HistoryEntry>)>
                           completion,
                       history::QueryResults results) {
                      std::vector<HistoryEntry> entries;
                      for (const history::URLResult& result : results) {
                        entries.push_back({result.url().spec(),
                                           base::UTF16ToUTF8(result.title())});
                      }
                      completion(std::move(entries));
                    },
                    std::move(completion)),
                &Tracker());
          },
          search_text, max_results, std::move(completion)));
}

void GetFaviconForPage(const std::string& profile_id,
                       const std::string& page_url,
                       std::function<void(void*)> completion) {
  LoadBrowserProfile(
      profile_id,
      base::BindOnce(
          [](const GURL& page_url, std::function<void(void*)> completion,
             Profile* profile) {
            favicon::FaviconService* service =
                profile ? FaviconServiceFactory::GetForProfile(
                              profile, ServiceAccessType::EXPLICIT_ACCESS)
                        : nullptr;
            if (!service || !page_url.is_valid()) {
              completion(nullptr);
              return;
            }
            service->GetFaviconImageForPageURL(
                page_url,
                base::BindOnce(
                    [](std::function<void(void*)> completion,
                       const favicon_base::FaviconImageResult& result) {
                      completion(
                          result.image.IsEmpty()
                              ? nullptr
                              : (__bridge void*)result.image.ToNSImage());
                    },
                    std::move(completion)),
                &Tracker());
          },
          GURL(page_url), std::move(completion)));
}

}  // namespace oa
