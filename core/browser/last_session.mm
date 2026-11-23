// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/sessions/session_restore.h"
#include "chrome/browser/sessions/session_service.h"
#include "chrome/browser/sessions/session_service_factory.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/startup/startup_tab.h"
#include "components/sessions/core/session_id.h"
#include "components/tabs/public/tab_interface.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/page_impl.h"
#include "oa/browser/profile_services.h"
#include "oa/browser/ui/browser_window_impl.h"
#include "oa/browser/window_browser.h"
#include "oa/public/engine.h"

namespace oa {
namespace {

// A profile's restore under way: the tabs Chrome restored so far, by the
// session ID each had in the last session.
struct PendingRestore {
  std::vector<std::pair<base::WeakPtr<content::WebContents>, int32_t>> tabs;
  std::function<void(std::vector<RestoredPage>)> completion;
};

std::map<Profile*, PendingRestore>& PendingRestores() {
  static base::NoDestructor<std::map<Profile*, PendingRestore>> pending;
  return *pending;
}

base::CallbackListSubscription& RestoredSubscription() {
  static base::NoDestructor<base::CallbackListSubscription> subscription;
  return *subscription;
}

void OnTabRestored(content::WebContents* contents, SessionID id) {
  auto it = PendingRestores().find(
      Profile::FromBrowserContext(contents->GetBrowserContext()));
  if (it != PendingRestores().end()) {
    it->second.tabs.emplace_back(contents->GetWeakPtr(), id.id());
  }
}

// As ArcCore's pending browsers: the restored tabs stay in the Browsers Chrome
// made for them, with no window, until the app moves each page to its window.
void OnSessionRestored(Profile* profile, int /*tab_count*/) {
  auto it = PendingRestores().find(profile);
  if (it == PendingRestores().end()) {
    return;
  }
  PendingRestore pending = std::move(it->second);
  PendingRestores().erase(it);
  std::vector<RestoredPage> pages;
  for (auto& [contents, id] : pending.tabs) {
    tabs::TabInterface* tab =
        contents ? tabs::TabInterface::MaybeGetFromContents(contents.get())
                 : nullptr;
    BrowserWindowImpl* window =
        tab ? BrowserWindowImpl::FromBrowser(tab->GetBrowserWindowInterface())
            : nullptr;
    if (!window) {
      continue;
    }
    pages.push_back({id, PageImpl::AdoptInserted(window->window_browser(),
                                                 contents.get())});
  }
  pending.completion(std::move(pages));
}

}  // namespace

void RestoreLastSession(
    const std::string& profile_id,
    std::function<void(std::vector<RestoredPage>)> completion) {
  LoadBrowserProfile(
      profile_id,
      base::BindOnce(
          [](std::function<void(std::vector<RestoredPage>)> completion,
             Profile* profile) {
            if (!profile || PendingRestores().contains(profile) ||
                SessionRestore::IsRestoring(profile) ||
                !SessionServiceFactory::GetForProfile(profile)) {
              completion({});
              return;
            }
            SessionService::SetLastSessionRestoreForEmbedder(true);
            SessionRestore::SetRestoredTabCallbackForEmbedder(
                base::BindRepeating(&OnTabRestored));
            if (!RestoredSubscription()) {
              RestoredSubscription() =
                  SessionRestore::RegisterOnSessionRestoredCallback(
                      base::BindRepeating(&OnSessionRestored));
            }
            PendingRestores()[profile].completion = std::move(completion);
            SessionRestore::RestoreSession(
                profile, /*browser=*/nullptr,
                SessionRestore::RESTORE_BROWSER |
                    SessionRestore::ALWAYS_CREATE_TABBED_BROWSER,
                {});
          },
          std::move(completion)));
}

void SaveSessionsForQuit() {
  ProfileManager::ShutdownSessionServices();
}

}  // namespace oa
