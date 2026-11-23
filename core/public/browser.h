// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_BROWSER_H_
#define OA_PUBLIC_BROWSER_H_

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "oa/public/page.h"

// One app window's side in one profile: Chromium's Browser for the pair, in
// the shape of ArcCore's ArcBrowser and its delegate. No Chromium headers
// here.

namespace oa {

// As ArcCore's ArcExtensionToolbarAction, for the window's active page.
struct ExtensionToolbarAction {
  std::string id;
  std::string accessible_name;
  std::string tooltip;
  // An NSImage with the badge drawn in.
  std::shared_ptr<void> icon;
  bool enabled = false;
  // Among Chrome's pinned extensions; -1 when it isn't pinned.
  int pinned_position = -1;
};

// A page Chrome's session restore brought back, with the session ID its tab
// had in the last session.
struct RestoredPage {
  int32_t last_session_id;
  std::unique_ptr<Page> page;
};

class Browser {
 public:
  // The toolbar actions and opened pages are posted; a popup's events come as
  // they happen.
  class Observer {
   public:
    // The whole list, after any of it changed and when the active page did.
    virtual void OnExtensionToolbarActionsChanged(
        const std::vector<ExtensionToolbarAction>& actions) = 0;
    // An action's popup page has loaded. `ns_view` is the page's NSView, which
    // the engine keeps until the popup closes; one popup shows at a time.
    virtual void OnExtensionPopupOpened(const std::string& extension_id,
                                        void* ns_view,
                                        int width,
                                        int height) = 0;
    virtual void OnExtensionPopupResized(int width, int height) = 0;
    // The view is about to go: the page closed itself, another popup opened or
    // CloseExtensionPopup() was called.
    virtual void OnExtensionPopupClosed() = 0;
    // Chromium put a page in the window's tab strip itself, as an extension's
    // chrome.tabs.create does. The observer owns it; destroying it drops it.
    virtual void OnBrowserOpenedPage(std::unique_ptr<Page> page,
                                     bool is_active) = 0;
    // As ADK's onReceivedRestoredWebContents: once the profiles the app asked
    // Browsers of have restored their last session or had none to restore,
    // the pages Chrome restored into this window's Browser, in one batch that
    // may be empty. The observer owns them.
    virtual void OnBrowserRestoredPages(std::vector<RestoredPage> pages) = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Browser() = default;

  // As a click on its toolbar button: its popup, its click event or its side
  // panel, for the window's active page.
  virtual void ExecuteExtensionAction(const std::string& id) = 0;
  virtual void SetExtensionPinned(const std::string& id, bool pinned) = 0;
  // Chrome's menu for the action, at the mouse.
  virtual void ShowExtensionContextMenu(const std::string& id) = 0;
  virtual void FocusExtensionPopup() = 0;
  virtual void CloseExtensionPopup() = 0;
};

// Loads the app profile `profile_id` if needed, makes `window_id`'s Browser
// for it, and reports that Browser to `observer` until the result is
// destroyed. As Arc's, the Browser stays while the result does, with pages or
// without.
std::unique_ptr<Browser> ObserveBrowser(const std::string& window_id,
                                        const std::string& profile_id,
                                        Browser::Observer* observer);

}  // namespace oa

#endif  // OA_PUBLIC_BROWSER_H_
