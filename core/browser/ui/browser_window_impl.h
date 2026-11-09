// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_BROWSER_WINDOW_IMPL_H_
#define OA_BROWSER_UI_BROWSER_WINDOW_IMPL_H_

#include <memory>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"

class BrowserWindowInterface;

namespace oa {

class SidePanelUIImpl;
class WindowBrowser;

// The window of every //chrome Browser in the app, with none of Chrome's views
// (ADR 0008 §5). The app's NSWindow, once attached, answers the ui::BaseWindow
// questions. Everything that would show Chrome UI is a no-op until the app
// draws its own.
//
// Chrome creates one for each Browser through the factory that
// SetFactoryForEmbedder() installs, including for Browsers it creates itself.
// The Browser owns it.
class BrowserWindowImpl : public BrowserWindow, public ExclusiveAccessContext {
 public:
  // Makes BrowserWindow::CreateBrowserWindow() return a BrowserWindowImpl for
  // every Browser. Call before the browser starts.
  static void InstallFactory();

  // The window of `browser`, or null if it isn't one of ours.
  static BrowserWindowImpl* FromBrowser(BrowserWindowInterface* browser);

  BrowserWindowImpl(const BrowserWindowImpl&) = delete;
  BrowserWindowImpl& operator=(const BrowserWindowImpl&) = delete;

  BrowserWindowInterface* browser() const { return browser_; }
  // The Oa window's Browser and strip logic. Never null.
  WindowBrowser* window_browser() const { return window_browser_.get(); }

  // ui::BaseWindow:
  void Show() override;
  void ShowInactive() override;
  void Hide() override;
  bool IsVisible() const override;
  void SetBounds(const gfx::Rect& bounds) override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  bool IsActive() const override;
  void FlashFrame(bool flash) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;
  gfx::NativeWindow GetNativeWindow() const override;
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  gfx::Rect GetBounds() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  bool IsFullscreen() const override;

  // BrowserWindow:
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  void SetTopControlsShownRatio(content::WebContents* web_contents,
                                float ratio) override;
  bool DoBrowserControlsShrinkRendererSize(
      const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  const ui::ColorProvider* GetColorProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateTitleBar() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          int index,
                          int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  void SetContentsSize(const gfx::Size& size) override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  LocationBar* GetLocationBar() const override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  PinnedToolbarActions* GetPinnedToolbarActions() override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  void FocusAppMenu() override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data,
                           const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  bool IsToolbarVisible() const override;
  bool IsLocationBarVisible() const override;
  bool IsToolbarShowing() const override;
  bool IsUnframedModeEnabled() const override;
  void ShowChromeLabs() override;
  BrowserView* AsBrowserView() override;
  void ShowUpdateChromeDialog() override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  void ShowIntentPickerBubble(
      std::vector<apps::IntentPickerAppInfo> app_info,
      bool show_stay_in_chrome,
      bool show_remember_selection,
      apps::IntentPickerBubbleType bubble_type,
      const std::optional<url::Origin>& initiating_origin,
      IntentPickerResponse callback) override;
  ShowTranslateBubbleResult ShowTranslateBubble(
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type,
      bool is_user_gesture) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ConfirmBrowserCloseWithPendingDownloads(
      int download_count,
      DownloadCloseType dialog_type,
      base::OnceCallback<void(bool)> callback) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost()
      override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(
      content::WebContents* web_contents) override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_keyboard) override;
  void ShowHatsDialog(
      const std::string& site_id,
      const std::optional<std::string>& hats_histogram_name,
      const std::optional<uint64_t> hats_survey_ukm_id,
      base::OnceClosure success_callback,
      base::OnceClosure failure_callback,
      const SurveyBitsData& product_specific_bits_data,
      const SurveyStringData& product_specific_string_data) override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  void ShowEmojiPanel() override;
  void ShowCaretBrowsingDialog() override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;

  // ExclusiveAccessContext: fullscreen and pointer lock stay off until the app
  // implements them.
  Profile* GetProfile() override;
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override;
  void ExitFullscreen() override;
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override;
  bool IsExclusiveAccessBubbleDisplayed() const override;
  void OnExclusiveAccessUserInput() override;
  content::WebContents* GetWebContentsForExclusiveAccess() override;
  bool CanUserEnterFullscreen() const override;
  bool CanUserExitFullscreen() const override;

 protected:
  // BrowserWindow:
  void DeleteBrowserWindow() override;

 private:
  class LocationBarImpl;
  class ModalDialogHost;

  explicit BrowserWindowImpl(BrowserWindowInterface* browser);
  ~BrowserWindowImpl() override;

  static std::unique_ptr<BrowserWindow, BrowserWindowDeleter> Create(
      BrowserWindowInterface* browser,
      bool user_gesture,
      bool in_tab_dragging);

  const raw_ptr<BrowserWindowInterface> browser_;
  std::unique_ptr<WindowBrowser> window_browser_;
  std::unique_ptr<LocationBarImpl> location_bar_;
  std::unique_ptr<SidePanelUIImpl> side_panel_ui_;
  // Where Chrome's dialogs over a page, such as print preview, go.
  std::unique_ptr<ModalDialogHost> modal_dialog_host_;
};

}  // namespace oa

#endif  // OA_BROWSER_UI_BROWSER_WINDOW_IMPL_H_
