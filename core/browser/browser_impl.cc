// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/browser_impl.h"

#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "chrome/browser/profiles/profile.h"
#include "oa/browser/profile_services.h"
#include "oa/browser/session_restoration.h"
#include "oa/browser/ui/extensions_container_impl.h"
#include "oa/browser/window_browser.h"

namespace oa {
namespace {

class BrowserImpl;

std::vector<BrowserImpl*>& AllBrowsers() {
  static base::NoDestructor<std::vector<BrowserImpl*>> all;
  return *all;
}

// The app's handle on a window's Browser in one profile. As ADK's
// ensureBrowserCreated, the WindowBrowser is made with the handle, before any
// page, and as Arc's it stays with no pages until the handle goes. Chrome can
// still close it, so it is looked up for each call and it looks its observer
// up here.
class BrowserImpl : public Browser {
 public:
  BrowserImpl(const std::string& window_id,
              const std::string& profile_id,
              BrowserContextType type,
              BrowserType browser_type,
              Browser::Observer* observer)
      : window_id_(window_id),
        profile_id_(profile_id),
        restores_(type == BrowserContextType::kNormal),
        observer_(observer) {
    AllBrowsers().push_back(this);
    if (browser_type == BrowserType::kPopup) {
      WindowBrowser::MarkPopup(window_id);
    }
    // As ADK's: the profile is expected to restore before its Browser is
    // asked for, so the first Browser's own restored tabs are parked too. An
    // incognito context never restores.
    if (restores_) {
      SessionRestoration::Expect(profile_id_);
    }
    LoadBrowserContext(
        profile_id, type,
        base::BindOnce(&BrowserImpl::Start, weak_factory_.GetWeakPtr()));
  }

  ~BrowserImpl() override {
    std::erase(AllBrowsers(), this);
    CloseExtensionPopup();
    if (!started_) {
      if (restores_) {
        SessionRestoration::Resolve(profile_id_, nullptr);
      }
    } else if (WindowBrowser* window_browser = FindWindowBrowser()) {
      window_browser->CloseIfEmpty();
    }
  }

  // The restored pages come once, even when there are none.
  void HandOff() {
    if (!started_) {
      return;
    }
    WindowBrowser* window_browser = FindWindowBrowser();
    std::vector<RestoredPage> restored =
        window_browser ? window_browser->AdoptParked(observer_)
                       : std::vector<RestoredPage>();
    if (std::exchange(awaits_restored_pages_, false) || !restored.empty()) {
      observer_->OnBrowserRestoredPages(std::move(restored));
    }
  }

  base::WeakPtr<BrowserImpl> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }

  const std::string& window_id() const { return window_id_; }
  Profile* profile() const { return profile_.get(); }
  Browser::Observer* observer() const { return observer_; }

  // Browser:
  void ExecuteExtensionAction(const std::string& id) override {
    if (ExtensionsContainerImpl* container = Container()) {
      container->ExecuteAction(id);
    }
  }
  void SetExtensionPinned(const std::string& id, bool pinned) override {
    if (ExtensionsContainerImpl* container = Container()) {
      container->SetPinned(id, pinned);
    }
  }
  void ShowExtensionContextMenu(const std::string& id) override {
    if (ExtensionsContainerImpl* container = Container()) {
      container->ShowContextMenu(id);
    }
  }
  void FocusExtensionPopup() override {
    if (ExtensionsContainerImpl* container = Container()) {
      container->FocusPopup();
    }
  }
  void CloseExtensionPopup() override {
    if (ExtensionsContainerImpl* container = Container()) {
      container->HideActivePopup();
    }
  }

 private:
  void Start(Profile* profile) {
    started_ = true;
    if (profile) {
      profile_ = profile->GetWeakPtr();
      // The profile's first Browser starts Chrome's restore of its session.
      WindowBrowser::GetOrCreate(window_id_, profile);
    }
    if (restores_) {
      SessionRestoration::Resolve(profile_id_, profile);
    }
    if (ExtensionsContainerImpl* container = Container()) {
      container->ReportActions();
    }
  }

  WindowBrowser* FindWindowBrowser() {
    return profile_ ? WindowBrowser::Find(window_id_, profile_.get()) : nullptr;
  }

  ExtensionsContainerImpl* Container() {
    WindowBrowser* window_browser = FindWindowBrowser();
    return window_browser ? window_browser->extensions_container() : nullptr;
  }

  const std::string window_id_;
  const std::string profile_id_;
  const bool restores_;
  bool started_ = false;
  bool awaits_restored_pages_ = true;
  const raw_ptr<Browser::Observer> observer_;
  base::WeakPtr<Profile> profile_;
  base::WeakPtrFactory<BrowserImpl> weak_factory_{this};
};

}  // namespace

Browser::Observer* FindBrowserObserver(const std::string& window_id,
                                       Profile* profile) {
  for (BrowserImpl* browser : AllBrowsers()) {
    if (browser->profile() == profile && browser->window_id() == window_id) {
      return browser->observer();
    }
  }
  return nullptr;
}

void HandOffRestoredPages() {
  std::vector<base::WeakPtr<BrowserImpl>> browsers;
  for (BrowserImpl* browser : AllBrowsers()) {
    browsers.push_back(browser->GetWeakPtr());
  }
  for (base::WeakPtr<BrowserImpl>& browser : browsers) {
    if (browser) {
      browser->HandOff();
    }
  }
}

std::unique_ptr<Browser> ObserveBrowser(const std::string& window_id,
                                        const std::string& profile_id,
                                        BrowserContextType type,
                                        BrowserType browser_type,
                                        Browser::Observer* observer) {
  return std::make_unique<BrowserImpl>(window_id, profile_id, type,
                                       browser_type, observer);
}

}  // namespace oa
