// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/browser_impl.h"

#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "chrome/browser/profiles/profile.h"
#include "oa/browser/profile_services.h"
#include "oa/browser/ui/extensions_container_impl.h"
#include "oa/browser/window_browser.h"

namespace oa {
namespace {

class BrowserImpl;

std::vector<BrowserImpl*>& AllBrowsers() {
  static base::NoDestructor<std::vector<BrowserImpl*>> all;
  return *all;
}

// The app's handle on a window's Browser in one profile. The WindowBrowser
// goes when its last page does and a new one comes with the next page, so it
// is looked up for each call and it looks its observer up here.
class BrowserImpl : public Browser {
 public:
  BrowserImpl(const std::string& window_id,
              const std::string& profile_id,
              Browser::Observer* observer)
      : window_id_(window_id), observer_(observer) {
    LoadBrowserProfile(profile_id, base::BindOnce(&BrowserImpl::Start,
                                                  weak_factory_.GetWeakPtr()));
  }

  ~BrowserImpl() override {
    std::erase(AllBrowsers(), this);
    CloseExtensionPopup();
  }

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
    if (!profile) {
      return;
    }
    profile_ = profile->GetWeakPtr();
    AllBrowsers().push_back(this);
    if (ExtensionsContainerImpl* container = Container()) {
      container->ReportActions();
    }
  }

  ExtensionsContainerImpl* Container() {
    WindowBrowser* window_browser =
        profile_ ? WindowBrowser::Find(window_id_, profile_.get()) : nullptr;
    return window_browser ? window_browser->extensions_container() : nullptr;
  }

  const std::string window_id_;
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

std::unique_ptr<Browser> ObserveBrowser(const std::string& window_id,
                                        const std::string& profile_id,
                                        Browser::Observer* observer) {
  return std::make_unique<BrowserImpl>(window_id, profile_id, observer);
}

}  // namespace oa
