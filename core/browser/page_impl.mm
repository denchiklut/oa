#include "oa/browser/page_impl.h"

#import <AppKit/AppKit.h>

#include <set>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/no_destructor.h"
#include "base/strings/utf_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/bind_post_task.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/tab_restore_service_factory.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "chrome/browser/tab_contents/tab_util.h"
#include "chrome/browser/ui/browser_live_tab_context.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/security_state/core/security_state.h"
#include "components/sessions/content/content_live_tab.h"
#include "components/sessions/core/tab_restore_service.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "content/public/browser/frame_tree_node_id.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/referrer.h"
#include "content/public/common/url_constants.h"
#include "oa/browser/window_browser.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/blink/public/common/renderer_preferences/renderer_preferences.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace oa {
namespace {

const void* const kPageMarkerKey = &kPageMarkerKey;

class PageMarker : public base::SupportsUserData::Data {
 public:
  explicit PageMarker(base::WeakPtr<PageImpl> page) : page_(std::move(page)) {}
  PageImpl* page() const { return page_.get(); }

 private:
  base::WeakPtr<PageImpl> page_;
};

std::set<PageImpl*>& OpenPages() {
  static base::NoDestructor<std::set<PageImpl*>> pages;
  return *pages;
}

bool ToOpenDisposition(WindowOpenDisposition disposition,
                       OpenDisposition* result) {
  switch (disposition) {
    case WindowOpenDisposition::NEW_FOREGROUND_TAB:
    case WindowOpenDisposition::SINGLETON_TAB:
    case WindowOpenDisposition::SWITCH_TO_TAB:
      *result = OpenDisposition::kForegroundTab;
      return true;
    case WindowOpenDisposition::NEW_BACKGROUND_TAB:
      *result = OpenDisposition::kBackgroundTab;
      return true;
    case WindowOpenDisposition::NEW_WINDOW:
      *result = OpenDisposition::kNewWindow;
      return true;
    case WindowOpenDisposition::NEW_POPUP:
      *result = OpenDisposition::kPopup;
      return true;
    default:
      return false;
  }
}

RendererExit ToRendererExit(base::TerminationStatus status) {
  switch (status) {
    case base::TERMINATION_STATUS_NORMAL_TERMINATION:
      return RendererExit::kNormal;
    case base::TERMINATION_STATUS_PROCESS_WAS_KILLED:
      return RendererExit::kKilled;
    case base::TERMINATION_STATUS_PROCESS_CRASHED:
      return RendererExit::kCrashed;
    case base::TERMINATION_STATUS_STILL_RUNNING:
      return RendererExit::kStillRunning;
    case base::TERMINATION_STATUS_LAUNCH_FAILED:
      return RendererExit::kLaunchFailed;
    case base::TERMINATION_STATUS_OOM:
      return RendererExit::kOutOfMemory;
    case base::TERMINATION_STATUS_EVICTED_FOR_MEMORY:
      return RendererExit::kEvictedForMemory;
    default:
      return RendererExit::kAbnormal;
  }
}

}  // namespace

// static
std::unique_ptr<PageImpl> PageImpl::Create(WindowBrowser* window_browser,
                                           Page::Observer* observer) {
  std::unique_ptr<PageImpl> page(new PageImpl(window_browser, observer));
  if (!page->Insert(
          content::WebContents::Create(content::WebContents::CreateParams(
              window_browser->browser()->GetProfile())))) {
    return nullptr;
  }
  return page;
}

// static
std::unique_ptr<PageImpl> PageImpl::Restore(WindowBrowser* window_browser,
                                            int32_t session_id,
                                            Page::Observer* observer) {
  BrowserWindowInterface* browser = window_browser->browser();
  sessions::TabRestoreService* service =
      TabRestoreServiceFactory::GetForProfile(browser->GetProfile());
  BrowserLiveTabContext* context = BrowserLiveTabContext::From(browser);
  if (!service || !context) {
    return nullptr;
  }
  // In the background: the app's sidebar selects the tab, not Chrome.
  std::optional<std::vector<sessions::LiveTab*>> tabs =
      service->RestoreEntryById(context,
                                SessionID::FromSerializedValue(session_id),
                                WindowOpenDisposition::NEW_BACKGROUND_TAB);
  if (!tabs || tabs->size() != 1) {
    return nullptr;
  }
  content::WebContents* contents =
      &static_cast<sessions::ContentLiveTab*>(tabs->front())->GetWebContents();
  // Chrome hides the view of a tab restored in the background until a
  // BrowserView shows it; Oa has none.
  contents->GetNativeView().GetNativeNSView().hidden = NO;
  std::unique_ptr<PageImpl> page(new PageImpl(window_browser, observer));
  page->Adopt(contents);
  return page;
}

// static
PageImpl* PageImpl::FromWebContents(content::WebContents* contents) {
  auto* marker =
      static_cast<PageMarker*>(contents->GetUserData(kPageMarkerKey));
  return marker ? marker->page() : nullptr;
}

// static
void PageImpl::CloseAll() {
  std::vector<PageImpl*> pages(OpenPages().begin(), OpenPages().end());
  for (PageImpl* page : pages) {
    page->Drop();
  }
}

PageImpl::PageImpl(WindowBrowser* window_browser, Page::Observer* observer)
    : window_browser_(window_browser->GetWeakPtr()), observer_(observer) {
  capture_observation_.Observe(MediaCaptureDevicesDispatcher::GetInstance()
                                   ->GetMediaStreamCaptureIndicator()
                                   .get());
}

PageImpl::~PageImpl() {
  observer_ = nullptr;
  Drop();
}

bool PageImpl::Insert(std::unique_ptr<content::WebContents> contents) {
  content::WebContents* page = contents.get();
  if (!window_browser_ || !window_browser_->Insert(std::move(contents))) {
    return false;
  }
  // Hidden until its view first joins a window, as Chrome's background tabs.
  page->WasHidden();
  Adopt(page);
  return true;
}

void PageImpl::Adopt(content::WebContents* contents) {
  contents->SetUserData(
      kPageMarkerKey, std::make_unique<PageMarker>(weak_factory_.GetWeakPtr()));
  Bind(contents);
  OpenPages().insert(this);
}

std::unique_ptr<PageImpl> PageImpl::Wrap(
    std::unique_ptr<content::WebContents> contents) {
  if (!window_browser_) {
    return nullptr;
  }
  std::unique_ptr<PageImpl> page(
      new PageImpl(window_browser_.get(), /*observer=*/nullptr));
  if (!page->Insert(std::move(contents))) {
    return nullptr;
  }
  return page;
}

void PageImpl::Bind(content::WebContents* contents) {
  set_inner(contents->GetDelegate());
  contents->SetDelegate(this);
  contents->GetMutableRendererPrefs()->browser_handles_all_top_level_requests =
      keeps_address_;
  contents->SyncRendererPrefs();
  Observe(contents);
  favicon_observation_.Reset();
  if (auto* driver = favicon::ContentFaviconDriver::FromWebContents(contents)) {
    favicon_observation_.Observe(driver);
  }
}

void PageImpl::Unbind() {
  favicon_observation_.Reset();
  if (content::WebContents* contents = web_contents()) {
    contents->RemoveUserData(kPageMarkerKey);
    if (contents->GetDelegate() == this) {
      contents->SetDelegate(inner());
    }
  }
  Observe(nullptr);
  set_inner(nullptr);
}

void PageImpl::Rebind(content::WebContents* new_contents) {
  Unbind();
  new_contents->SetUserData(
      kPageMarkerKey, std::make_unique<PageMarker>(weak_factory_.GetWeakPtr()));
  Bind(new_contents);
  NotifyStateChanged();
}

void PageImpl::OnRemovedFromStrip(std::optional<SessionID> session_id) {
  Unbind();
  NotifyClosed(session_id);
}

void PageImpl::SetObserver(Page::Observer* observer) {
  observer_ = observer;
}

void* PageImpl::NativeView() const {
  if (!web_contents()) {
    return nullptr;
  }
  return (__bridge void*)web_contents()->GetNativeView().GetNativeNSView();
}

std::string PageImpl::VisibleURL() const {
  return web_contents() ? web_contents()->GetVisibleURL().spec()
                        : std::string();
}

std::string PageImpl::Title() const {
  return web_contents() ? base::UTF16ToUTF8(web_contents()->GetTitle())
                        : std::string();
}

bool PageImpl::IsLoading() const {
  return web_contents() && web_contents()->IsLoading();
}

double PageImpl::LoadProgress() const {
  return load_progress_;
}

bool PageImpl::CanGoBack() const {
  return web_contents() && web_contents()->GetController().CanGoBack();
}

bool PageImpl::CanGoForward() const {
  return web_contents() && web_contents()->GetController().CanGoForward();
}

void* PageImpl::Favicon() const {
  auto* driver =
      web_contents()
          ? favicon::ContentFaviconDriver::FromWebContents(web_contents())
          : nullptr;
  if (!driver || !driver->FaviconIsValid()) {
    return nullptr;
  }
  return (__bridge void*)driver->GetFavicon().ToNSImage();
}

SecurityLevel PageImpl::GetSecurityLevel() const {
  if (!web_contents()) {
    return SecurityLevel::kNeutral;
  }
  switch (chrome_security_state::GetSecurityLevel(web_contents())) {
    case security_state::SECURE:
      return SecurityLevel::kSecure;
    case security_state::WARNING:
      return SecurityLevel::kWarning;
    case security_state::DANGEROUS:
      return SecurityLevel::kDangerous;
    default:
      return SecurityLevel::kNeutral;
  }
}

NavigationResult PageImpl::GetNavigationResult() const {
  return navigation_result_;
}

bool PageImpl::IsCameraOn() const {
  return web_contents() && MediaCaptureDevicesDispatcher::GetInstance()
                               ->GetMediaStreamCaptureIndicator()
                               ->IsCapturingVideo(web_contents());
}

bool PageImpl::IsMicrophoneOn() const {
  return web_contents() && MediaCaptureDevicesDispatcher::GetInstance()
                               ->GetMediaStreamCaptureIndicator()
                               ->IsCapturingAudio(web_contents());
}

void PageImpl::Load(const std::string& url) {
  GURL gurl(url);
  if (!web_contents() || !gurl.is_valid()) {
    return;
  }
  web_contents()->GetController().LoadURL(
      gurl, content::Referrer(),
      ui::PageTransitionFromInt(ui::PAGE_TRANSITION_TYPED |
                                ui::PAGE_TRANSITION_FROM_ADDRESS_BAR),
      std::string());
}

void PageImpl::GoBack() {
  if (CanGoBack()) {
    web_contents()->GetController().GoBack();
  }
}

void PageImpl::GoForward() {
  if (CanGoForward()) {
    web_contents()->GetController().GoForward();
  }
}

void PageImpl::Reload() {
  if (web_contents()) {
    web_contents()->GetController().Reload(content::ReloadType::NORMAL,
                                           /*check_for_repost=*/false);
  }
}

void PageImpl::Stop() {
  if (web_contents()) {
    web_contents()->Stop();
  }
}

void PageImpl::Activate() {
  if (!window_browser_ || !web_contents()) {
    return;
  }
  window_browser_->Activate(web_contents());
  NSWindow* window = window_browser_->GetNativeWindow().GetNativeNSWindow();
  if (window.isKeyWindow) {
    web_contents()->Focus();
  }
}

// As Arc: the renderer hands every top-level navigation to the browser, which
// then sends a link to another host to a new page from OpenURLFromTab.
void PageImpl::SetKeepsAddress(bool keeps_address) {
  keeps_address_ = keeps_address;
  if (content::WebContents* contents = web_contents()) {
    contents->GetMutableRendererPrefs()
        ->browser_handles_all_top_level_requests = keeps_address;
    contents->SyncRendererPrefs();
  }
}

// Hosts, not origins: Arc peeks example.com → www.example.com and navigates
// an http → https change in place.
bool PageImpl::KeepsAddressAgainst(const content::OpenURLParams& params) const {
  if (!keeps_address_ || !params.is_renderer_initiated || params.post_data ||
      ui::PageTransitionCoreTypeIs(params.transition,
                                   ui::PAGE_TRANSITION_FORM_SUBMIT) ||
      !params.url.SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  const GURL& current = web_contents()->GetLastCommittedURL();
  return current.SchemeIsHTTPOrHTTPS() && current.host() != params.url.host();
}

void PageImpl::MoveToWindow(const std::string& window_id) {
  content::WebContents* contents = web_contents();
  if (!contents || !window_browser_) {
    return;
  }
  WindowBrowser* target = WindowBrowser::GetOrCreate(
      window_id, window_browser_->browser()->GetProfile());
  if (!target || target == window_browser_.get()) {
    return;
  }
  // The same tab moves, so its WebContents, history, tab helpers and session
  // ID stay. Leaving the strip clears its delegate; the new Browser's goes in
  // on insertion, and this page's goes in front of it again.
  std::unique_ptr<tabs::TabModel> tab = window_browser_->Detach(contents);
  if (!tab) {
    return;
  }
  set_inner(nullptr);
  window_browser_ = target->GetWeakPtr();
  target->InsertDetached(std::move(tab));
  Bind(contents);
}

void PageImpl::Snapshot(SnapshotCallback callback) {
  content::RenderWidgetHostView* view =
      web_contents() ? web_contents()->GetRenderWidgetHostView() : nullptr;
  if (!view || !view->IsSurfaceAvailableForCopy()) {
    callback(nullptr);
    return;
  }
  // The result can arrive on another sequence.
  view->CopyFromSurface(
      gfx::Rect(), gfx::Size(), base::Seconds(2),
      base::BindPostTaskToCurrentDefault(base::BindOnce(
          [](SnapshotCallback callback,
             const content::CopyFromSurfaceResult& result) {
            if (!result.has_value() || result->bitmap.drawsNothing()) {
              callback(nullptr);
              return;
            }
            NSImage* image = skia::SkBitmapToNSImage(result->bitmap);
            callback((__bridge void*)image);
          },
          std::move(callback))));
}

void PageImpl::AskToLeave(std::function<void(bool leave)> callback) {
  content::WebContents* contents = web_contents();
  if (!contents || closing_ || leave_callback_) {
    callback(!contents);
    return;
  }
  leave_callback_ = std::move(callback);
  contents->DispatchBeforeUnload(/*auto_cancel=*/false);
}

void PageImpl::Close() {
  content::WebContents* contents = web_contents();
  if (!contents) {
    return;
  }
  closing_ = true;
  if (!window_browser_ || !window_browser_->Close(contents)) {
    Drop();
  }
}

void PageImpl::Drop() {
  if (leave_callback_) {
    std::exchange(leave_callback_, nullptr)(true);
  }
  content::WebContents* contents = web_contents();
  if (!contents) {
    return;
  }
  Unbind();
  if (window_browser_) {
    window_browser_->Remove(contents);
  }
  OpenPages().erase(this);
}

void PageImpl::RunDialog(const Dialog& dialog, DialogReply reply) {
  if (suppress_dialogs_ || !observer_) {
    // A silenced or unwatched page gets Chrome's answers: alerts and unloads
    // go on, questions are declined.
    const bool accepted = dialog.kind == Dialog::Kind::kAlert ||
                          dialog.kind == Dialog::Kind::kBeforeUnload;
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(
                       [](DialogReply reply, bool accepted) {
                         reply(accepted, std::string(), false);
                       },
                       std::move(reply), accepted));
    return;
  }
  Dialog shown = dialog;
  shown.offers_suppression =
      dialog.kind != Dialog::Kind::kBeforeUnload && ++dialogs_shown_ >= 7;
  observer_->OnPageDialog(
      shown, [weak = weak_factory_.GetWeakPtr(), reply = std::move(reply)](
                 bool accepted, const std::string& text, bool suppress) {
        if (weak && suppress) {
          weak->suppress_dialogs_ = true;
        }
        reply(accepted, text, suppress);
      });
}

void PageImpl::DismissDialog(const Dialog& dialog) {
  if (observer_) {
    observer_->OnPageDialogDismissed(dialog);
  }
}

void PageImpl::RequestPermission(const PermissionRequest& request,
                                 PermissionReply reply) {
  if (!observer_) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](PermissionReply reply) { reply(PermissionResponse::kDismiss); },
            std::move(reply)));
    return;
  }
  observer_->OnPagePermissionRequest(request, std::move(reply));
}

void PageImpl::ClosePermissionRequest(const PermissionRequest& request) {
  if (observer_) {
    observer_->OnPagePermissionRequestClosed(request);
  }
}

content::WebContents* PageImpl::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)> callback) {
  OpenDisposition disposition;
  if (params.disposition == WindowOpenDisposition::CURRENT_TAB) {
    if (!KeepsAddressAgainst(params)) {
      return ForwardingWebContentsDelegate::OpenURLFromTab(source, params,
                                                           std::move(callback));
    }
    disposition = OpenDisposition::kForegroundTab;
  } else if (!ToOpenDisposition(params.disposition, &disposition)) {
    return nullptr;
  }
  if (!observer_ || !window_browser_) {
    return nullptr;
  }
  Profile* profile = window_browser_->browser()->GetProfile();
  std::unique_ptr<PageImpl> opened =
      Wrap(content::WebContents::Create(content::WebContents::CreateParams(
          profile, tab_util::GetSiteInstanceForNewTab(profile, params.url))));
  if (!opened) {
    return nullptr;
  }
  content::WebContents* page = opened->web_contents();
  content::NavigationController::LoadURLParams load(params);
  // The request's frame is the source's; the new page loads in its own.
  load.frame_tree_node_id = content::FrameTreeNodeId();
  load.should_replace_current_entry = false;
  base::WeakPtr<content::NavigationHandle> navigation =
      page->GetController().LoadURLWithParams(load);
  if (navigation && callback) {
    std::move(callback).Run(*navigation);
  }
  observer_->OnPageOpenedPage(std::move(opened), params.url.spec(),
                              disposition);
  return page;
}

content::WebContents* PageImpl::AddNewContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    WindowOpenDisposition disposition,
    const blink::mojom::WindowFeatures& window_features,
    bool user_gesture,
    bool* was_blocked) {
  // Window features are ignored, as Arc does.
  OpenDisposition open_disposition;
  if (!observer_ || !ToOpenDisposition(disposition, &open_disposition)) {
    return nullptr;
  }
  content::WebContents* page = new_contents.get();
  std::unique_ptr<PageImpl> opened = Wrap(std::move(new_contents));
  if (!opened) {
    return nullptr;
  }
  observer_->OnPageOpenedPage(
      std::move(opened),
      target_url.is_valid() ? target_url.spec() : std::string(),
      open_disposition);
  return page;
}

void PageImpl::ActivateContents(content::WebContents* contents) {
  if (observer_) {
    observer_->OnPageWantsActivation();
  }
}

void PageImpl::NavigationStateChanged(content::WebContents* source,
                                      content::InvalidateTypes changed_flags) {
  NotifyStateChanged();
  ForwardingWebContentsDelegate::NavigationStateChanged(source, changed_flags);
}

void PageImpl::LoadingStateChanged(content::WebContents* source,
                                   bool should_show_loading_ui) {
  if (!source->IsLoading()) {
    load_progress_ = 0;
  }
  NotifyStateChanged();
  ForwardingWebContentsDelegate::LoadingStateChanged(source,
                                                     should_show_loading_ui);
}

void PageImpl::CloseContents(content::WebContents* source) {
  ForwardingWebContentsDelegate::CloseContents(source);
}

bool PageImpl::CanEnterFullscreenModeForTab(
    content::RenderFrameHost* requesting_frame) {
  return false;
}

// Chrome would close the page once the handler lets it go; asking keeps it.
void PageImpl::BeforeUnloadFired(content::WebContents* tab,
                                 bool proceed,
                                 bool* proceed_to_fire_unload) {
  if (!leave_callback_) {
    ForwardingWebContentsDelegate::BeforeUnloadFired(tab, proceed,
                                                     proceed_to_fire_unload);
    return;
  }
  *proceed_to_fire_unload = false;
  std::exchange(leave_callback_, nullptr)(proceed);
}

void PageImpl::BeforeUnloadFired(bool proceed) {
  if (proceed || !closing_) {
    return;
  }
  closing_ = false;
  if (observer_) {
    observer_->OnPageCloseCancelled();
  }
}

// Unlike RenderFrameCreated, this comes after a crashed page's replacement
// frame becomes primary; Arc and Chrome's sad tab clear theirs here too.
void PageImpl::RenderViewReady() {
  if (observer_) {
    observer_->OnPageRendererReady();
  }
}

void PageImpl::PrimaryMainFrameRenderProcessGone(
    base::TerminationStatus status) {
  if (observer_) {
    observer_->OnPageRendererGone(ToRendererExit(status));
  }
}

// As ArcCore: an error page's own document loading doesn't count as loaded,
// and a navigation that never commits leaves the result cleared.
void PageImpl::DidStartNavigation(
    content::NavigationHandle* navigation_handle) {
  if (navigation_handle->IsInPrimaryMainFrame()) {
    navigation_result_ = NavigationResult::kNone;
    NotifyStateChanged();
  }
}

void PageImpl::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  if (navigation_handle->IsInPrimaryMainFrame() &&
      navigation_handle->HasCommitted()) {
    if (navigation_handle->IsSameDocument()) {
      navigation_result_ = NavigationResult::kLoaded;
    } else if (navigation_handle->IsErrorPage()) {
      navigation_result_ = NavigationResult::kFailed;
    }
  }
  NotifyStateChanged();
}

void PageImpl::DidFinishLoad(content::RenderFrameHost* render_frame_host,
                             const GURL& validated_url) {
  if (render_frame_host->IsInPrimaryMainFrame() &&
      !validated_url.SchemeIs(content::kChromeErrorScheme)) {
    navigation_result_ = NavigationResult::kLoaded;
    NotifyStateChanged();
  }
}

void PageImpl::DidFailLoad(content::RenderFrameHost* render_frame_host,
                           const GURL& validated_url,
                           int error_code) {
  if (render_frame_host->IsInPrimaryMainFrame() &&
      !validated_url.SchemeIs(content::kChromeErrorScheme)) {
    navigation_result_ = NavigationResult::kFailed;
    NotifyStateChanged();
  }
}

void PageImpl::LoadProgressChanged(double progress) {
  load_progress_ = progress;
  NotifyStateChanged();
}

void PageImpl::TitleWasSet(content::NavigationEntry* entry) {
  NotifyStateChanged();
}

void PageImpl::DidChangeVisibleSecurityState() {
  NotifyStateChanged();
}

void PageImpl::OnFaviconUpdated(favicon::FaviconDriver* favicon_driver,
                                NotificationIconType notification_icon_type,
                                const GURL& icon_url,
                                bool icon_url_changed,
                                const gfx::Image& image) {
  NotifyStateChanged();
}

void PageImpl::OnIsCapturingVideoChanged(content::WebContents* contents,
                                         bool is_capturing_video) {
  if (contents == web_contents()) {
    NotifyStateChanged();
  }
}

void PageImpl::OnIsCapturingAudioChanged(content::WebContents* contents,
                                         bool is_capturing_audio) {
  if (contents == web_contents()) {
    NotifyStateChanged();
  }
}

void PageImpl::WebContentsDestroyed() {
  favicon_observation_.Reset();
  set_inner(nullptr);
  NotifyClosed(std::nullopt);
}

void PageImpl::NotifyStateChanged() {
  if (observer_) {
    observer_->OnPageStateChanged();
  }
}

void PageImpl::NotifyClosed(std::optional<SessionID> session_id) {
  if (!OpenPages().erase(this)) {
    return;
  }
  if (observer_) {
    observer_->OnPageClosed(session_id && session_id->is_valid()
                                ? std::optional(session_id->id())
                                : std::nullopt);
  }
}

}  // namespace oa
