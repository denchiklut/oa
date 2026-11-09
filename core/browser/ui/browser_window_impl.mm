// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/browser_window_impl.h"

#import <AppKit/AppKit.h>

#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/observer_list.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/web_modal/modal_dialog_host.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "content/public/browser/eye_dropper.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/ui/side_panel_ui_impl.h"
#include "oa/browser/window_browser.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_key.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/native_theme/native_theme.h"

namespace oa {

// The location bar Chrome expects every window to have. The app draws its own
// address field, so this one has no omnibox and shows nothing.
class BrowserWindowImpl::LocationBarImpl : public LocationBar {
 public:
  explicit LocationBarImpl(BrowserWindowInterface* browser)
      : LocationBar(/*command_updater=*/nullptr), browser_(browser) {}
  ~LocationBarImpl() override = default;

  // LocationBar:
  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override {}
  void FocusSearch() override {}
  void UpdateFocusBehavior(bool toolbar_visible) override {}
  void UpdateContentSettingsIcons() override {}
  void SaveStateToContents(content::WebContents* contents) override {}
  void Revert() override {}
  OmniboxView* GetOmniboxView() override { return nullptr; }
  OmniboxPopupView* GetOmniboxPopupView() override { return nullptr; }
  OmniboxController* GetOmniboxController() override { return nullptr; }
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override { return false; }
  content::WebContents* GetWebContents() override {
    return browser_->GetTabStripModel()->GetActiveWebContents();
  }
  LocationBarModel* GetLocationBarModel() override { return nullptr; }
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override {
    return std::nullopt;
  }
  ChipController* GetChipController() override { return nullptr; }
  void AnnounceAlert(const std::u16string& announcement) override {}
  void OnChanged() override {}
  void UpdateWithoutTabRestore() override {}
  ui::TrackedElement* GetAnchorOrNull() override { return nullptr; }
  BrowserWindowInterface* GetBrowser() override { return browser_; }
  Profile* GetProfile() override { return browser_->GetProfile(); }
  bool IsInitialized() const override { return true; }
  bool IsVisible() const override { return false; }
  bool IsDrawn() const override { return false; }
  bool IsFullscreen() const override { return false; }
  bool IsEditingOrEmpty() const override { return false; }
  bool IsMouseHovered() const override { return false; }
  bool IsFocusWithin() const override { return false; }
  void InvalidateLayout() override {}
  gfx::Rect Bounds() const override { return gfx::Rect(); }
  gfx::Rect BoundsInScreen() const override { return gfx::Rect(); }
  gfx::Size MinimumSize() const override { return gfx::Size(); }
  gfx::Size PreferredSize() const override { return gfx::Size(); }
  void Update(content::WebContents* contents) override {}
  void ResetTabState(content::WebContents* contents) override {}
  bool HasSecurityStateChanged() override { return false; }
  LocationBarTesting* GetLocationBarForTesting() override { return nullptr; }

 private:
  const raw_ptr<BrowserWindowInterface> browser_;
};

namespace {

// The app's window for a Browser, or nil before one is attached and for
// Browsers Chrome creates itself.
NSWindow* AppWindow(const WindowBrowser* window_browser) {
  return window_browser->GetNativeWindow().GetNativeNSWindow();
}

}  // namespace

// Where Chrome puts a dialog over one of the window's pages, such as print
// preview: the app's window. Chrome sizes the dialog to fit it. With no Views
// widget to parent it to, the dialog opens as a window of its own, which the
// page's tab puts over this one (TabImpl::AttachPrintPreview()).
class BrowserWindowImpl::ModalDialogHost
    : public web_modal::WebContentsModalDialogHost {
 public:
  explicit ModalDialogHost(const WindowBrowser* window_browser)
      : window_browser_(window_browser) {}
  ModalDialogHost(const ModalDialogHost&) = delete;
  ModalDialogHost& operator=(const ModalDialogHost&) = delete;
  ~ModalDialogHost() override {
    for (web_modal::ModalDialogHostObserver& observer : observers_) {
      observer.OnHostDestroying();
    }
  }

  // web_modal::WebContentsModalDialogHost:
  gfx::Size GetMaximumDialogSize() override {
    NSWindow* window = AppWindow(window_browser_);
    if (!window) {
      return gfx::Size();
    }
    const NSSize size = window.contentView.bounds.size;
    return gfx::Size(size.width, size.height);
  }

  // web_modal::ModalDialogHost:
  gfx::NativeView GetHostView() const override {
    NSWindow* window = AppWindow(window_browser_);
    return window ? gfx::NativeView(window.contentView) : gfx::NativeView();
  }
  gfx::Point GetDialogPosition(const gfx::Size& size) override {
    const gfx::Size host = GetMaximumDialogSize();
    return gfx::Point((host.width() - size.width()) / 2,
                      (host.height() - size.height()) / 2);
  }
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.AddObserver(observer);
  }
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override {
    observers_.RemoveObserver(observer);
  }

 private:
  const raw_ptr<const WindowBrowser> window_browser_;
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

// static
void BrowserWindowImpl::InstallFactory() {
  BrowserWindow::SetFactoryForEmbedder(&BrowserWindowImpl::Create);
}

// static
BrowserWindowImpl* BrowserWindowImpl::FromBrowser(
    BrowserWindowInterface* browser) {
  // The factory makes every Browser's window one of these.
  return static_cast<BrowserWindowImpl*>(BrowserWindow::FromBrowser(browser));
}

// static
std::unique_ptr<BrowserWindow, BrowserWindowDeleter> BrowserWindowImpl::Create(
    BrowserWindowInterface* browser,
    bool user_gesture,
    bool in_tab_dragging) {
  return std::unique_ptr<BrowserWindow, BrowserWindowDeleter>(
      new BrowserWindowImpl(browser));
}

BrowserWindowImpl::BrowserWindowImpl(BrowserWindowInterface* browser)
    : browser_(browser),
      window_browser_(std::make_unique<WindowBrowser>(browser)),
      location_bar_(std::make_unique<LocationBarImpl>(browser)),
      side_panel_ui_(std::make_unique<SidePanelUIImpl>(browser)),
      modal_dialog_host_(
          std::make_unique<ModalDialogHost>(window_browser_.get())) {}

BrowserWindowImpl::~BrowserWindowImpl() {
  // BrowserWindow implementations tear the Browser's features down before
  // they go.
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  modal_dialog_host_.reset();
  window_browser_.reset();
}

void BrowserWindowImpl::DeleteBrowserWindow() {
  delete this;
}

// ui::BaseWindow: the app's NSWindow, when one is attached. The app owns its
// window, so nothing here opens, moves or closes it.

void BrowserWindowImpl::Show() {
  [AppWindow(window_browser_.get()) makeKeyAndOrderFront:nil];
}

void BrowserWindowImpl::ShowInactive() {
  [AppWindow(window_browser_.get()) orderFront:nil];
}

void BrowserWindowImpl::Hide() {}

bool BrowserWindowImpl::IsVisible() const {
  return AppWindow(window_browser_.get()).visible;
}

void BrowserWindowImpl::SetBounds(const gfx::Rect& bounds) {}

void BrowserWindowImpl::Close() {
  // Called when the strip empties, or when Chrome closes the Browser itself.
  // New pages for this window go to a new Browser from now on.
  window_browser_->OnWindowClosing();
  // Out of the strip's notification, as a Views window closes. The unload
  // controller closes any tabs left, then schedules the Browser's deletion.
  // The app's NSWindow stays open.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<BrowserWindowInterface> browser) {
            if (browser) {
              UnloadController::From(browser.get())->OnWindowClosing();
            }
          },
          browser_->GetWeakPtr()));
}

void BrowserWindowImpl::Activate() {
  NSWindow* window = AppWindow(window_browser_.get());
  if (!window) {
    return;
  }
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  [window makeKeyAndOrderFront:nil];
}

void BrowserWindowImpl::Deactivate() {}

bool BrowserWindowImpl::IsActive() const {
  return AppWindow(window_browser_.get()).keyWindow;
}

void BrowserWindowImpl::FlashFrame(bool flash) {}

ui::ZOrderLevel BrowserWindowImpl::GetZOrderLevel() const {
  return ui::ZOrderLevel::kNormal;
}

void BrowserWindowImpl::SetZOrderLevel(ui::ZOrderLevel order) {}

gfx::NativeWindow BrowserWindowImpl::GetNativeWindow() const {
  return window_browser_->GetNativeWindow();
}

gfx::Rect BrowserWindowImpl::GetRestoredBounds() const {
  return GetBounds();
}

ui::mojom::WindowShowState BrowserWindowImpl::GetRestoredState() const {
  return ui::mojom::WindowShowState::kNormal;
}

gfx::Rect BrowserWindowImpl::GetBounds() const {
  NSWindow* window = AppWindow(window_browser_.get());
  return window ? gfx::ScreenRectFromNSRect(window.frame) : gfx::Rect();
}

bool BrowserWindowImpl::IsMaximized() const {
  return AppWindow(window_browser_.get()).zoomed;
}

bool BrowserWindowImpl::IsMinimized() const {
  return AppWindow(window_browser_.get()).miniaturized;
}

void BrowserWindowImpl::Maximize() {}

void BrowserWindowImpl::Minimize() {}

void BrowserWindowImpl::Restore() {}

bool BrowserWindowImpl::IsFullscreen() const {
  NSWindow* window = AppWindow(window_browser_.get());
  return window && (window.styleMask & NSWindowStyleMaskFullScreen);
}

// BrowserWindow.

bool BrowserWindowImpl::IsOnCurrentWorkspace() const {
  NSWindow* window = AppWindow(window_browser_.get());
  return !window || window.onActiveSpace;
}

bool BrowserWindowImpl::IsVisibleOnScreen() const {
  return IsVisible() && !IsMinimized();
}

void BrowserWindowImpl::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool BrowserWindowImpl::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* BrowserWindowImpl::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* BrowserWindowImpl::GetThemeProvider() const {
  return nullptr;
}

const ui::ColorProvider* BrowserWindowImpl::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::ColorProviderKey());
}

int BrowserWindowImpl::GetTopControlsHeight() const {
  return 0;
}

void BrowserWindowImpl::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

std::vector<StatusBubble*> BrowserWindowImpl::GetStatusBubbles() {
  return {};
}

void BrowserWindowImpl::UpdateTitleBar() {}

void BrowserWindowImpl::UpdateLoadingAnimations(bool is_visible) {}

void BrowserWindowImpl::OnActiveTabChanged(content::WebContents* old_contents,
                                           content::WebContents* new_contents,
                                           int index,
                                           int reason) {}

void BrowserWindowImpl::OnTabDetached(content::WebContents* contents,
                                      bool was_active) {}

gfx::Size BrowserWindowImpl::GetContentsSize() const {
  return GetBounds().size();
}

void BrowserWindowImpl::SetContentsSize(const gfx::Size& size) {}

bool BrowserWindowImpl::GetCanResize() {
  return true;
}

ui::mojom::WindowShowState BrowserWindowImpl::GetWindowShowState() const {
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  return IsMaximized() ? ui::mojom::WindowShowState::kMaximized
                       : ui::mojom::WindowShowState::kNormal;
}

LocationBar* BrowserWindowImpl::GetLocationBar() const {
  return location_bar_.get();
}

ui::AcceleratorProvider* BrowserWindowImpl::GetAcceleratorProvider() {
  return nullptr;
}

PinnedToolbarActions* BrowserWindowImpl::GetPinnedToolbarActions() {
  return nullptr;
}

autofill::AutofillBubbleHandler* BrowserWindowImpl::GetAutofillBubbleHandler() {
  return nullptr;
}

void BrowserWindowImpl::SetFocusToLocationBar(bool is_user_initiated) {}

void BrowserWindowImpl::UpdateReloadStopState(bool is_loading, bool force) {}

void BrowserWindowImpl::UpdateToolbar(content::WebContents* contents) {}

bool BrowserWindowImpl::UpdateToolbarSecurityState() {
  return false;
}

void BrowserWindowImpl::UpdateCustomTabBarVisibility(bool visible,
                                                     bool animate) {}

void BrowserWindowImpl::ResetToolbarTabState(content::WebContents* contents) {}

void BrowserWindowImpl::FocusToolbar() {}

void BrowserWindowImpl::ToolbarSizeChanged(bool is_animating) {}

void BrowserWindowImpl::TabDraggingStatusChanged(bool is_dragging) {}

void BrowserWindowImpl::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}

void BrowserWindowImpl::FocusAppMenu() {}

void BrowserWindowImpl::ShowAppMenu() {}

void BrowserWindowImpl::PreHandleDragUpdate(const content::DropData& drop_data,
                                            const gfx::PointF& point) {}

void BrowserWindowImpl::PreHandleDragExit() {}

void BrowserWindowImpl::HandleDragEnded() {}

content::KeyboardEventProcessingResult
BrowserWindowImpl::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // Chrome's accelerators don't run: the app's menu owns every shortcut.
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool BrowserWindowImpl::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // The page didn't handle the key, so it may be one of the app's menu
  // shortcuts. Without Chrome's views nothing else redispatches it.
  if (event.skip_if_unhandled) {
    return false;
  }
  NSEvent* ns_event = event.os_event.Get();
  if (!ns_event || ns_event.type != NSEventTypeKeyDown) {
    return false;
  }
  return [NSApp.mainMenu performKeyEquivalent:ns_event];
}

bool BrowserWindowImpl::IsTabStripEditable() const {
  return true;
}

void BrowserWindowImpl::DisableTabStripEditingForTesting() {}

bool BrowserWindowImpl::IsToolbarVisible() const {
  return false;
}

bool BrowserWindowImpl::IsLocationBarVisible() const {
  return false;
}

bool BrowserWindowImpl::IsToolbarShowing() const {
  return false;
}

bool BrowserWindowImpl::IsUnframedModeEnabled() const {
  return false;
}

void BrowserWindowImpl::ShowChromeLabs() {}

BrowserView* BrowserWindowImpl::AsBrowserView() {
  return nullptr;
}

void BrowserWindowImpl::ShowUpdateChromeDialog() {}

void BrowserWindowImpl::ShowBookmarkBubble(const GURL& url,
                                           bool already_bookmarked) {}

void BrowserWindowImpl::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {}

ShowTranslateBubbleResult BrowserWindowImpl::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController* BrowserWindowImpl::GetDownloadBubbleUIController() {
  return nullptr;
}

void BrowserWindowImpl::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  // No warning to show yet: the Browser closes, as the app already decided.
  std::move(callback).Run(true);
}

std::unique_ptr<FindBar> BrowserWindowImpl::CreateFindBar() {
  return nullptr;
}

web_modal::WebContentsModalDialogHost*
BrowserWindowImpl::GetWebContentsModalDialogHost() {
  return modal_dialog_host_.get();
}

web_modal::WebContentsModalDialogHost*
BrowserWindowImpl::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return modal_dialog_host_.get();
}

void BrowserWindowImpl::ShowAvatarBubbleFromAvatarButton(
    bool is_source_keyboard) {}

void BrowserWindowImpl::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  std::move(failure_callback).Run();
}

void BrowserWindowImpl::ShowIncognitoClearBrowsingDataDialog() {}

void BrowserWindowImpl::ShowIncognitoHistoryDisclaimerDialog() {}

ExclusiveAccessContext* BrowserWindowImpl::GetExclusiveAccessContext() {
  return this;
}

std::string BrowserWindowImpl::GetWorkspace() const {
  return std::string();
}

bool BrowserWindowImpl::IsVisibleOnAllWorkspaces() const {
  return false;
}

void BrowserWindowImpl::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

void BrowserWindowImpl::ShowCaretBrowsingDialog() {}

std::unique_ptr<content::EyeDropper> BrowserWindowImpl::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  return nullptr;
}

void BrowserWindowImpl::CreateTabSearchBubble() {}

void BrowserWindowImpl::CloseTabSearchBubble() {}

// ExclusiveAccessContext.

Profile* BrowserWindowImpl::GetProfile() {
  return browser_->GetProfile();
}

void BrowserWindowImpl::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {}

void BrowserWindowImpl::ExitFullscreen() {}

void BrowserWindowImpl::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {}

bool BrowserWindowImpl::IsExclusiveAccessBubbleDisplayed() const {
  return false;
}

void BrowserWindowImpl::OnExclusiveAccessUserInput() {}

content::WebContents* BrowserWindowImpl::GetWebContentsForExclusiveAccess() {
  return browser_->GetTabStripModel()->GetActiveWebContents();
}

bool BrowserWindowImpl::CanUserEnterFullscreen() const {
  return false;
}

bool BrowserWindowImpl::CanUserExitFullscreen() const {
  return true;
}

}  // namespace oa
