// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/extensions_container_impl.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <optional>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/i18n/case_conversion.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/extensions/extension_action_delegate.h"
#include "chrome/browser/ui/extensions/extension_action_view_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "oa/browser/image_handle.h"
#include "oa/browser/window_browser.h"
#include "oa/public/browser.h"
#include "ui/base/cocoa/menu_utils.h"
#include "ui/base/models/image_model.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_util_mac.h"
#include "ui/menus/cocoa/menu_controller.h"
#include "ui/menus/simple_menu_model.h"

namespace oa {
namespace {

// Chrome's toolbar button: its 16 pt icon with room for the badge.
constexpr gfx::Size kIconSize(28, 28);

}  // namespace

struct ExtensionsContainerImpl::Action {
  std::unique_ptr<ExtensionActionViewModel> model;
  base::CallbackListSubscription icon_subscription;
};

// An action's popup page: its host, kept here as ArcCore's container keeps it
// where Chrome's delegate builds a views bubble, and the host's view, which
// only tells the app the page's size.
class ExtensionsContainerImpl::Popup : public extensions::ExtensionView,
                                       public content::WebContentsObserver {
 public:
  Popup(ExtensionsContainerImpl* container,
        const std::string& id,
        std::unique_ptr<extensions::ExtensionViewHost> host,
        ShowPopupCallback callback)
      : container_(container),
        id_(id),
        host_(std::move(host)),
        callback_(std::move(callback)) {
    Observe(host_->host_contents());
    host_->set_view(this);
    // The page closing itself, as window.close() and Esc do.
    host_->SetCloseHandler(base::BindOnce(
        [](Popup* popup, extensions::ExtensionHost* host) {
          if (popup->container_ && popup->container_->popup_.get() == popup) {
            popup->container_->HideActivePopup();
          }
        },
        base::Unretained(this)));
  }

  ~Popup() override {
    if (callback_) {
      std::move(callback_).Run(nullptr);
    }
  }

  const std::string& id() const { return id_; }
  bool shown() const { return shown_; }

  void Load() {
    if (host_->has_loaded_once()) {
      OnLoaded();
    } else {
      host_->CreateRendererSoon();
    }
  }

  void Focus() { host_->host_contents()->Focus(); }

  // The container no longer shows this popup; it is deleted from a task.
  void Detach() { container_ = nullptr; }

  // extensions::ExtensionView:
  gfx::NativeView GetNativeView() override {
    return host_->host_contents()->GetNativeView();
  }
  void ResizeDueToAutoResize(content::WebContents* web_contents,
                             const gfx::Size& new_size) override {
    size_ = new_size;
    Browser::Observer* observer = Observer();
    if (shown_ && observer) {
      observer->OnExtensionPopupResized(size_.width(), size_.height());
    }
  }
  void RenderFrameCreated(content::RenderFrameHost* frame_host) override {
    SizeFromPage(frame_host);
  }
  bool HandleKeyboardEvent(
      content::WebContents* source,
      const input::NativeWebKeyboardEvent& event) override {
    return false;
  }
  // As Chrome's popup: shown once the page has loaded, so it opens at its
  // size.
  void OnLoaded() override {
    if (shown_ || !container_) {
      return;
    }
    Browser::Observer* observer = Observer();
    if (!observer) {
      container_->HideActivePopup();
      return;
    }
    shown_ = true;
    if (size_.IsEmpty()) {
      size_ = extensions::kExtensionPopupMinSize;
    }
    host_->host_contents()->WasShown();
    observer->OnExtensionPopupOpened(
        id_, (__bridge void*)GetNativeView().GetNativeNSView(), size_.width(),
        size_.height());
    if (callback_) {
      std::move(callback_).Run(host_.get());
    }
  }

  // content::WebContentsObserver:
  // The popup's page loads in a frame that replaces the first one.
  void RenderFrameHostChanged(content::RenderFrameHost* old_host,
                              content::RenderFrameHost* new_host) override {
    SizeFromPage(new_host);
  }

 private:
  Browser::Observer* Observer() const {
    return container_ ? container_->window_browser_->observer() : nullptr;
  }

  void SizeFromPage(content::RenderFrameHost* frame_host) {
    if (frame_host == host_->host_contents()->GetPrimaryMainFrame() &&
        frame_host->IsRenderFrameLive() && frame_host->GetView()) {
      // Oa's own: Chrome's limits. Arc's are unknown.
      frame_host->GetView()->EnableAutoResize(
          extensions::kExtensionPopupMinSize,
          extensions::kExtensionPopupMaxSize);
    }
  }

  raw_ptr<ExtensionsContainerImpl> container_;
  const std::string id_;
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  ShowPopupCallback callback_;
  gfx::Size size_;
  bool shown_ = false;
};

class ExtensionsContainerImpl::ActionDelegate : public ExtensionActionDelegate {
 public:
  explicit ActionDelegate(ExtensionsContainerImpl* container)
      : container_(container) {}

  // ExtensionActionDelegate:
  void AttachToModel(ExtensionActionViewModel* model) override {
    model_ = model;
  }
  void DetachFromModel() override { model_ = nullptr; }
  void RegisterCommand() override {}
  void UnregisterCommand() override {}
  bool IsShowingPopup() const override {
    return model_ && container_->IsShowingPopup(model_->GetId());
  }
  void HidePopup() override {
    if (IsShowingPopup()) {
      container_->HideActivePopup();
    }
  }
  gfx::NativeView GetPopupNativeViewForTesting() override {
    return gfx::NativeView();
  }
  void TriggerPopup(std::unique_ptr<extensions::ExtensionViewHost> host,
                    PopupShowAction show_action,
                    bool by_user,
                    ShowPopupCallback callback) override {
    container_->ShowPopup(model_->GetId(), std::move(host),
                          std::move(callback));
  }
  void ShowContextMenuAsFallback() override {
    container_->ShowContextMenu(model_->GetId());
  }
  void CloseExtensionsMenuIfOpen() override {}

 private:
  const raw_ptr<ExtensionsContainerImpl> container_;
  raw_ptr<ExtensionActionViewModel> model_ = nullptr;
};

ExtensionsContainerImpl::ExtensionsContainerImpl(WindowBrowser* window_browser)
    : window_browser_(window_browser),
      model_(ToolbarActionsModel::Get(window_browser->browser()->GetProfile())),
      scoped_unowned_user_data_(
          window_browser->browser()->GetUnownedUserDataHost(),
          *this) {
  if (model_) {
    model_observation_.Observe(model_.get());
  }
}

ExtensionsContainerImpl::~ExtensionsContainerImpl() {
  // At once: the host's delegate points at the Browser, which is going.
  ClosePopup(/*delete_now=*/true);
}

void ExtensionsContainerImpl::ExecuteAction(const std::string& id) {
  if (ToolbarActionViewModel* action = GetActionForId(id)) {
    action->ExecuteUserAction(
        ToolbarActionViewModel::InvocationSource::kToolbarButton);
  }
}

void ExtensionsContainerImpl::SetPinned(const std::string& id, bool pinned) {
  if (model_ && model_->HasAction(id) && !model_->IsActionForcePinned(id) &&
      model_->IsActionPinned(id) != pinned) {
    model_->SetActionVisibility(id, pinned);
  }
}

void ExtensionsContainerImpl::ShowContextMenu(const std::string& id) {
  ToolbarActionViewModel* action = GetActionForId(id);
  ui::MenuModel* menu =
      action ? action->GetContextMenu(extensions::ExtensionContextMenuModel::
                                          ContextMenuSource::kToolbarAction)
             : nullptr;
  if (!menu) {
    return;
  }
  // As Arc's menu: its wording, where Chrome's names the product and its
  // toolbar, and the pin after the removal.
  using Menu = extensions::ExtensionContextMenuModel;
  auto* items = static_cast<ui::SimpleMenuModel*>(menu);
  const std::optional<size_t> pin =
      items->GetIndexOfCommandId(Menu::TOGGLE_VISIBILITY);
  if (pin) {
    items->RemoveItemAt(*pin);
  }
  const std::optional<size_t> uninstall =
      items->GetIndexOfCommandId(Menu::UNINSTALL);
  if (uninstall) {
    items->SetLabel(*uninstall, u"Remove from Oa");
  }
  if (pin) {
    items->InsertItemAt(uninstall ? *uninstall + 1 : *pin,
                        Menu::TOGGLE_VISIBILITY,
                        model_->IsActionPinned(id) ? u"Unpin" : u"Pin");
  }
  MenuControllerCocoa* controller =
      [[MenuControllerCocoa alloc] initWithModel:menu
                                   isContextMenu:YES
                                        delegate:nil];
  NSWindow* window =
      NSApp.currentEvent.window
          ?: window_browser_->GetNativeWindow().GetNativeNSWindow();
  NSEvent* event = ui::EventForPositioningContextMenuRelativeToWindow(
      window.mouseLocationOutsideOfEventStream, window);
  // Runs a nested loop; a command can close the Browser and this with it.
  ui::ShowContextMenu(controller.menu, event, window.contentView,
                      /*allow_nested_tasks=*/true);
}

void ExtensionsContainerImpl::FocusPopup() {
  if (popup_ && popup_->shown()) {
    popup_->Focus();
  }
}

void ExtensionsContainerImpl::ReportActions() {
  if (report_pending_) {
    return;
  }
  report_pending_ = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&ExtensionsContainerImpl::SendActions,
                                weak_factory_.GetWeakPtr()));
}

void ExtensionsContainerImpl::SendActions() {
  report_pending_ = false;
  Browser::Observer* observer = window_browser_->observer();
  content::WebContents* contents =
      window_browser_->browser()->GetTabStripModel()->GetActiveWebContents();
  if (!observer || !contents || !model_ || !model_->actions_initialized()) {
    return;
  }
  std::vector<std::pair<std::u16string, ExtensionToolbarAction>> named;
  const std::vector<std::string>& pinned = model_->pinned_action_ids();
  for (const std::string& id : model_->action_ids()) {
    ToolbarActionViewModel* action = GetActionForId(id);
    if (!action) {
      continue;
    }
    ExtensionToolbarAction item;
    item.id = id;
    item.accessible_name =
        base::UTF16ToUTF8(action->GetAccessibleName(contents));
    item.tooltip = base::UTF16ToUTF8(action->GetTooltip(contents));
    item.enabled = action->IsEnabled(contents);
    const auto position = std::ranges::find(pinned, id);
    if (position != pinned.end()) {
      item.pinned_position = static_cast<int>(position - pinned.begin());
    }
    item.icon = ToImageHandle(gfx::NSImageFromImageSkia(
        action->GetIcon(contents, kIconSize).GetImage().AsImageSkia()));
    named.emplace_back(base::i18n::ToLower(action->GetActionName()),
                       std::move(item));
  }
  // Oa's own: by name, as Chrome's extensions menu lists them. Arc's order
  // isn't known.
  std::ranges::stable_sort(named, {},
                           [](const auto& entry) { return entry.first; });
  std::vector<ExtensionToolbarAction> actions;
  for (auto& entry : named) {
    actions.push_back(std::move(entry.second));
  }
  observer->OnExtensionToolbarActionsChanged(actions);
}

ToolbarActionViewModel* ExtensionsContainerImpl::GetActionForId(
    const std::string& action_id) {
  if (!model_ || !model_->HasAction(action_id)) {
    return nullptr;
  }
  std::unique_ptr<Action>& action = actions_[action_id];
  if (!action) {
    action = std::make_unique<Action>();
    action->model = ExtensionActionViewModel::Create(
        action_id, window_browser_->browser(),
        std::make_unique<ActionDelegate>(this));
    action->icon_subscription =
        action->model->RegisterIconUpdateObserver(base::BindRepeating(
            &ExtensionsContainerImpl::ReportActions, base::Unretained(this)));
  }
  return action->model.get();
}

void ExtensionsContainerImpl::HideActivePopup() {
  // From a task: the host may be the caller, closing itself.
  ClosePopup(/*delete_now=*/false);
}

void ExtensionsContainerImpl::CloseExtensionsMenuIfOpen() {}

bool ExtensionsContainerImpl::ShowToolbarActionPopupForAPICall(
    const std::string& action_id,
    ShowPopupCallback callback) {
  ToolbarActionViewModel* action = GetActionForId(action_id);
  if (!action) {
    return false;
  }
  action->TriggerPopupForAPI(std::move(callback));
  return true;
}

void ExtensionsContainerImpl::ToggleExtensionsMenu() {}

bool ExtensionsContainerImpl::HasAnyExtensions() const {
  return model_ && !model_->action_ids().empty();
}

void ExtensionsContainerImpl::OnToolbarActionAdded(
    const ToolbarActionsModel::ActionId& id) {
  ReportActions();
}

void ExtensionsContainerImpl::OnToolbarActionRemoved(
    const ToolbarActionsModel::ActionId& id) {
  if (IsShowingPopup(id)) {
    HideActivePopup();
  }
  actions_.erase(id);
  ReportActions();
}

void ExtensionsContainerImpl::OnToolbarActionUpdated(
    const ToolbarActionsModel::ActionId& id) {
  ReportActions();
}

void ExtensionsContainerImpl::OnToolbarModelInitialized() {
  ReportActions();
}

void ExtensionsContainerImpl::OnToolbarPinnedActionsChanged() {
  ReportActions();
}

void ExtensionsContainerImpl::OnToolbarActionsModelShutdown() {
  HideActivePopup();
  actions_.clear();
  model_observation_.Reset();
  model_ = nullptr;
}

void ExtensionsContainerImpl::ClosePopup(bool delete_now) {
  if (!popup_) {
    return;
  }
  std::unique_ptr<Popup> popup = std::move(popup_);
  popup->Detach();
  Browser::Observer* observer = window_browser_->observer();
  if (popup->shown() && observer) {
    observer->OnExtensionPopupClosed();
  }
  if (!delete_now) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(
        FROM_HERE, std::move(popup));
  }
}

bool ExtensionsContainerImpl::IsShowingPopup(const std::string& id) const {
  return popup_ && popup_->id() == id;
}

void ExtensionsContainerImpl::ShowPopup(
    const std::string& id,
    std::unique_ptr<extensions::ExtensionViewHost> host,
    ShowPopupCallback callback) {
  HideActivePopup();
  popup_ =
      std::make_unique<Popup>(this, id, std::move(host), std::move(callback));
  popup_->Load();
}

}  // namespace oa
