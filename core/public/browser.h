// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_BROWSER_H_
#define OA_PUBLIC_BROWSER_H_

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

class Browser {
 public:
  // The toolbar actions are posted; a popup's events come as they happen.
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

// Loads the app profile `profile_id` if needed, then reports `window_id`'s
// Browser for it to `observer` until the result is destroyed. The Browser
// itself comes and goes with the window's pages in that profile.
std::unique_ptr<Browser> ObserveBrowser(const std::string& window_id,
                                        const std::string& profile_id,
                                        Browser::Observer* observer);

}  // namespace oa

#endif  // OA_PUBLIC_BROWSER_H_
