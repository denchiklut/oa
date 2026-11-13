// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_EXTENSIONS_CONTAINER_IMPL_H_
#define OA_BROWSER_UI_EXTENSIONS_CONTAINER_IMPL_H_

#include <map>
#include <memory>
#include <string>

#include "base/callback_list.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "chrome/browser/ui/extensions/extension_popup_types.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class ExtensionActionViewModel;

namespace extensions {
class ExtensionViewHost;
}

namespace oa {

class WindowBrowser;

// The extensions container Chrome's extension code looks up on a Browser, as
// ArcCore's: it keeps a view model per action, hands an action's popup page to
// the app in place of Chrome's bubble, and reports the actions up. Owned by
// its WindowBrowser.
class ExtensionsContainerImpl : public ExtensionsContainer,
                                public ToolbarActionsModel::Observer {
 public:
  explicit ExtensionsContainerImpl(WindowBrowser* window_browser);
  ExtensionsContainerImpl(const ExtensionsContainerImpl&) = delete;
  ExtensionsContainerImpl& operator=(const ExtensionsContainerImpl&) = delete;
  ~ExtensionsContainerImpl() override;

  void ExecuteAction(const std::string& id);
  void SetPinned(const std::string& id, bool pinned);
  void ShowContextMenu(const std::string& id);
  void FocusPopup();
  // Posts the actions to the window's observer, once for any number of calls.
  void ReportActions();

  // ExtensionsContainer:
  ToolbarActionViewModel* GetActionForId(const std::string& action_id) override;
  void HideActivePopup() override;
  void CloseExtensionsMenuIfOpen() override;
  bool ShowToolbarActionPopupForAPICall(const std::string& action_id,
                                        ShowPopupCallback callback) override;
  void ToggleExtensionsMenu() override;
  bool HasAnyExtensions() const override;

  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override;
  void OnToolbarActionsModelShutdown() override;

 private:
  class ActionDelegate;
  class Popup;
  struct Action;

  void ClosePopup(bool delete_now);
  bool IsShowingPopup(const std::string& id) const;
  void ShowPopup(const std::string& id,
                 std::unique_ptr<extensions::ExtensionViewHost> host,
                 ShowPopupCallback callback);
  void SendActions();

  const raw_ptr<WindowBrowser> window_browser_;
  raw_ptr<ToolbarActionsModel> model_;
  // Built on first use: the Browser is still being constructed when this is.
  std::map<std::string, std::unique_ptr<Action>> actions_;
  std::unique_ptr<Popup> popup_;
  bool report_pending_ = false;
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      model_observation_{this};
  ui::ScopedUnownedUserData<ExtensionsContainer> scoped_unowned_user_data_;
  base::WeakPtrFactory<ExtensionsContainerImpl> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_UI_EXTENSIONS_CONTAINER_IMPL_H_
