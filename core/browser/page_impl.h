#ifndef OA_BROWSER_PAGE_IMPL_H_
#define OA_BROWSER_PAGE_IMPL_H_

#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/process/kill.h"
#include "base/scoped_observation.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/ui/thumbnails/thumbnail_image.h"
#include "components/favicon/core/favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "components/find_in_page/find_result_observer.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/sessions/core/session_id.h"
#include "components/zoom/zoom_controller.h"
#include "components/zoom/zoom_observer.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/web_contents_observer.h"
#include "oa/browser/forwarding_web_contents_delegate.h"
#include "oa/public/page.h"
#include "third_party/skia/include/core/SkColor.h"

class ThumbnailTabHelper;

namespace cc {
class RenderFrameMetadata;
}

namespace content {
class WebContents;
}  // namespace content

namespace oa {

class DevToolsImpl;
class WindowBrowser;

// One of the app's pages: a //chrome tab in its window's Browser. The
// WebContents carries a marker back to this object, which is also its
// delegate in front of the Browser's.
class PageImpl : public Page,
                 public ForwardingWebContentsDelegate,
                 public content::WebContentsObserver,
                 public content::RenderWidgetHost::InputEventObserver,
                 public content::RenderWidgetHostObserver,
                 public favicon::FaviconDriverObserver,
                 public find_in_page::FindResultObserver,
                 public MediaStreamCaptureIndicator::Observer,
                 public zoom::ZoomObserver {
 public:
  static std::unique_ptr<PageImpl> Create(WindowBrowser* window_browser,
                                          Page::Observer* observer);
  static std::unique_ptr<PageImpl> Restore(WindowBrowser* window_browser,
                                           int32_t session_id,
                                           Page::Observer* observer);
  static PageImpl* FromWebContents(content::WebContents* contents);
  // A page for a tab Chrome put in `window_browser`'s strip itself.
  static std::unique_ptr<PageImpl> AdoptInserted(
      WindowBrowser* window_browser,
      content::WebContents* contents);
  static void CloseAll();
  // Before the browser starts.
  static void InstallFrameMetadataObserver();

  PageImpl(const PageImpl&) = delete;
  PageImpl& operator=(const PageImpl&) = delete;
  ~PageImpl() override;

  void Rebind(content::WebContents* new_contents);
  void OnRemovedFromStrip(std::optional<SessionID> session_id);
  // From the dialog views Chrome's managers create for this page.
  void RunDialog(const Dialog& dialog, DialogReply reply);
  void DismissDialog(const Dialog& dialog);
  // From the permission prompts Chrome's request manager creates for this
  // page.
  void RequestPermission(const PermissionRequest& request,
                         PermissionReply reply);
  void ClosePermissionRequest(const PermissionRequest& request);
  // From Chrome's extension install prompt and uninstall dialog.
  void RequestExtension(const ExtensionRequest& request, ExtensionReply reply);
  void CloseExtensionRequest(const ExtensionRequest& request);
  // From the window Chromium shows this page's picture-in-picture video in.
  void NotifyPictureInPicture(const PictureInPictureEvent& event,
                              void* ns_view = nullptr);
  // From a WebUI dialog Chrome shows over this page. False when nothing
  // watches the page to show it.
  bool NotifyWebDialog(const WebDialog& dialog, void* ns_view);
  void NotifyWebDialogClosed(const WebDialog& dialog);
  // Runs the beforeunload handler as quitting does and keeps the page either
  // way. A handler-less page answers at once.
  void AskToLeave(std::function<void(bool leave)> callback);
  base::WeakPtr<PageImpl> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }
  DevToolsImpl* devtools() const { return devtools_.get(); }

  // Page:
  void SetObserver(Page::Observer* observer) override;
  void* NativeView() const override;
  std::string VisibleURL() const override;
  std::string Title() const override;
  bool IsLoading() const override;
  double LoadProgress() const override;
  int32_t GetTabSessionID() const override;
  bool CanGoBack() const override;
  bool CanGoForward() const override;
  void* Favicon() const override;
  SecurityLevel GetSecurityLevel() const override;
  std::optional<Color> GetRootBackgroundColor() const override;
  NavigationResult GetNavigationResult() const override;
  bool IsCameraOn() const override;
  bool IsMicrophoneOn() const override;
  bool IsAudible() const override;
  bool IsMuted() const override;
  bool HasFocus() const override;
  std::optional<MediaSessionState> GetMediaSessionState() const override;
  std::string SelectedText() const override;
  float ZoomFactor() const override;
  bool IsPageScaled() const override;
  void Load(const std::string& url) override;
  void GoBack() override;
  void GoForward() override;
  void Reload() override;
  void ReloadBypassingCache() override;
  void SavePage() override;
  void Print() override;
  void Stop() override;
  void Activate() override;
  void Find(const std::string& text, bool forward, bool find_match) override;
  void StopFinding() override;
  void SetKeepsAddress(bool keeps_address) override;
  void SetMuted(bool muted) override;
  void SetZoomFactor(float factor) override;
  void ResetZoomAndScaleFactors() override;
  std::unique_ptr<Page> Clone() override;
  void MoveToWindow(const std::string& window_id) override;
  void Snapshot(SnapshotCallback callback) override;
  void StartObservingThumbnails() override;
  void StopObservingThumbnails() override;
  void RequestThumbnail() override;
  bool RequestPictureInPicture() override;
  bool EndPictureInPicture(bool pause_video) override;
  void Close() override;
  void Drop() override;
  DevTools* GetDevTools() override;

  // content::WebContentsDelegate:
  content::WebContents* OpenURLFromTab(
      content::WebContents* source,
      const content::OpenURLParams& params,
      base::OnceCallback<void(content::NavigationHandle&)>
          navigation_handle_callback) override;
  content::WebContents* AddNewContents(
      content::WebContents* source,
      std::unique_ptr<content::WebContents> new_contents,
      const GURL& target_url,
      WindowOpenDisposition disposition,
      const blink::mojom::WindowFeatures& window_features,
      bool user_gesture,
      bool* was_blocked) override;
  void ActivateContents(content::WebContents* contents) override;
  void NavigationStateChanged(content::WebContents* source,
                              content::InvalidateTypes changed_flags) override;
  void LoadingStateChanged(content::WebContents* source,
                           bool should_show_loading_ui) override;
  void CloseContents(content::WebContents* source) override;
  bool CanEnterFullscreenModeForTab(
      content::RenderFrameHost* requesting_frame) override;
  void BeforeUnloadFired(content::WebContents* tab,
                         bool proceed,
                         bool* proceed_to_fire_unload) override;

  // content::WebContentsObserver:
  void BeforeUnloadFired(bool proceed) override;
  void PrimaryMainFrameRenderProcessGone(
      base::TerminationStatus status) override;
  void RenderViewReady() override;
  void DidStartNavigation(
      content::NavigationHandle* navigation_handle) override;
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override;
  void DidFinishLoad(content::RenderFrameHost* render_frame_host,
                     const GURL& validated_url) override;
  void DidFailLoad(content::RenderFrameHost* render_frame_host,
                   const GURL& validated_url,
                   int error_code) override;
  void LoadProgressChanged(double progress) override;
  void TitleWasSet(content::NavigationEntry* entry) override;
  void DidChangeVisibleSecurityState() override;
  void RenderFrameHostChanged(content::RenderFrameHost* old_host,
                              content::RenderFrameHost* new_host) override;
  void OnWebContentsFocused(
      content::RenderWidgetHost* render_widget_host) override;
  void OnWebContentsLostFocus(
      content::RenderWidgetHost* render_widget_host) override;
  void WebContentsDestroyed() override;
  void OnAudioStateChanged(bool audible) override;
  void DidUpdateAudioMutingState(bool muted) override;
  void OnTextSelectionChanged(content::RenderFrameHost* render_frame_host,
                              std::u16string_view selected_text) override;

  // content::RenderWidgetHost::InputEventObserver:
  void OnInputEventAck(const content::RenderWidgetHost& widget_host,
                       blink::mojom::InputEventResultSource source,
                       blink::mojom::InputEventResultState state,
                       const blink::WebInputEvent& event) override;

  // content::RenderWidgetHostObserver:
  void RenderWidgetHostDestroyed(
      content::RenderWidgetHost* widget_host) override;

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* favicon_driver,
                        NotificationIconType notification_icon_type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override;

  // find_in_page::FindResultObserver:
  void OnFindResultAvailable(content::WebContents* web_contents) override;
  void OnFindTabHelperDestroyed(find_in_page::FindTabHelper* helper) override;

  // MediaStreamCaptureIndicator::Observer:
  void OnIsCapturingVideoChanged(content::WebContents* contents,
                                 bool is_capturing_video) override;
  void OnIsCapturingAudioChanged(content::WebContents* contents,
                                 bool is_capturing_audio) override;

  // zoom::ZoomObserver:
  void OnZoomControllerDestroyed(
      zoom::ZoomController* zoom_controller) override;
  void OnZoomChanged(
      const zoom::ZoomController::ZoomChangedEventData& data) override;

 private:
  PageImpl(WindowBrowser* window_browser, Page::Observer* observer);

  bool Insert(std::unique_ptr<content::WebContents> contents);
  void Adopt(content::WebContents* contents);
  std::unique_ptr<PageImpl> Wrap(
      std::unique_ptr<content::WebContents> contents);
  void Bind(content::WebContents* contents);
  zoom::ZoomController* GetZoomController() const;
  bool KeepsAddressAgainst(const content::OpenURLParams& params) const;
  void Unbind();
  static void OnFrameMetadata(content::RenderWidgetHost* widget_host,
                              content::WebContents* web_contents,
                              const cc::RenderFrameMetadata& metadata);
  void ObserveMainWidget();
  void StopObservingMainWidget();
  ThumbnailTabHelper* ThumbnailHelper() const;
  void SubscribeToThumbnail();
  void OnThumbnail(gfx::ImageSkia image);
  void NotifyStateChanged();
  void NotifyClosed(std::optional<SessionID> session_id);

  base::WeakPtr<WindowBrowser> window_browser_;
  raw_ptr<Page::Observer> observer_;
  bool closing_ = false;
  std::function<void(bool leave)> leave_callback_;
  bool keeps_address_ = false;
  int dialogs_shown_ = 0;
  bool suppress_dialogs_ = false;
  double load_progress_ = 0;
  NavigationResult navigation_result_ = NavigationResult::kNone;
  std::optional<SkColor4f> root_background_color_;
  bool has_focus_ = false;
  std::u16string selected_text_;
  // As ArcCore drops its find completion on stopFind: results that come after
  // aren't reported.
  bool finding_ = false;
  base::ScopedObservation<find_in_page::FindTabHelper,
                          find_in_page::FindResultObserver>
      find_observation_{this};
  base::ScopedObservation<favicon::FaviconDriver,
                          favicon::FaviconDriverObserver>
      favicon_observation_{this};
  base::ScopedObservation<MediaStreamCaptureIndicator,
                          MediaStreamCaptureIndicator::Observer>
      capture_observation_{this};
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHostObserver>
      main_widget_observation_{this};
  base::ScopedObservation<zoom::ZoomController, zoom::ZoomObserver>
      zoom_observation_{this};
  bool observing_thumbnails_ = false;
  std::unique_ptr<ThumbnailImage::Subscription> thumbnail_subscription_;
  std::unique_ptr<DevToolsImpl> devtools_;
  base::WeakPtrFactory<PageImpl> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_PAGE_IMPL_H_
