#ifndef OA_BROWSER_PAGE_IMPL_H_
#define OA_BROWSER_PAGE_IMPL_H_

#include <functional>
#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/process/kill.h"
#include "base/scoped_observation.h"
#include "components/favicon/core/favicon_driver.h"
#include "components/favicon/core/favicon_driver_observer.h"
#include "content/public/browser/web_contents_observer.h"
#include "oa/browser/forwarding_web_contents_delegate.h"
#include "oa/public/page.h"

namespace content {
class WebContents;
}

namespace oa {

class WindowBrowser;

// One of the app's pages: a //chrome tab in its window's Browser. The
// WebContents carries a marker back to this object, which is also its
// delegate in front of the Browser's.
class PageImpl : public Page,
                 public ForwardingWebContentsDelegate,
                 public content::WebContentsObserver,
                 public favicon::FaviconDriverObserver {
 public:
  static std::unique_ptr<PageImpl> Create(WindowBrowser* window_browser,
                                          Page::Observer* observer);
  static PageImpl* FromWebContents(content::WebContents* contents);
  static void CloseAll();

  PageImpl(const PageImpl&) = delete;
  PageImpl& operator=(const PageImpl&) = delete;
  ~PageImpl() override;

  void Rebind(content::WebContents* new_contents);
  void OnRemovedFromStrip();
  // From the dialog views Chrome's managers create for this page.
  void RunDialog(const Dialog& dialog, DialogReply reply);
  void DismissDialog(const Dialog& dialog);
  // Runs the beforeunload handler as quitting does and keeps the page either
  // way. A handler-less page answers at once.
  void AskToLeave(std::function<void(bool leave)> callback);
  base::WeakPtr<PageImpl> GetWeakPtr() { return weak_factory_.GetWeakPtr(); }

  // Page:
  void SetObserver(Page::Observer* observer) override;
  void* NativeView() const override;
  std::string VisibleURL() const override;
  std::string Title() const override;
  bool IsLoading() const override;
  double LoadProgress() const override;
  bool CanGoBack() const override;
  bool CanGoForward() const override;
  void* Favicon() const override;
  SecurityLevel GetSecurityLevel() const override;
  NavigationResult GetNavigationResult() const override;
  void Load(const std::string& url) override;
  void GoBack() override;
  void GoForward() override;
  void Reload() override;
  void Stop() override;
  void Activate() override;
  void SetKeepsAddress(bool keeps_address) override;
  void MoveToWindow(const std::string& window_id) override;
  void Snapshot(SnapshotCallback callback) override;
  void Close() override;
  void Drop() override;

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
  bool HandleContextMenu(content::RenderFrameHost& render_frame_host,
                         const content::ContextMenuParams& params) override;
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
  void WebContentsDestroyed() override;

  // favicon::FaviconDriverObserver:
  void OnFaviconUpdated(favicon::FaviconDriver* favicon_driver,
                        NotificationIconType notification_icon_type,
                        const GURL& icon_url,
                        bool icon_url_changed,
                        const gfx::Image& image) override;

 private:
  PageImpl(WindowBrowser* window_browser, Page::Observer* observer);

  bool Insert(std::unique_ptr<content::WebContents> contents);
  std::unique_ptr<PageImpl> Wrap(
      std::unique_ptr<content::WebContents> contents);
  void Bind(content::WebContents* contents);
  bool KeepsAddressAgainst(const content::OpenURLParams& params) const;
  void Unbind();
  void NotifyStateChanged();
  void NotifyClosed();

  base::WeakPtr<WindowBrowser> window_browser_;
  raw_ptr<Page::Observer> observer_;
  bool closing_ = false;
  std::function<void(bool leave)> leave_callback_;
  bool keeps_address_ = false;
  int dialogs_shown_ = 0;
  bool suppress_dialogs_ = false;
  double load_progress_ = 0;
  NavigationResult navigation_result_ = NavigationResult::kNone;
  base::ScopedObservation<favicon::FaviconDriver,
                          favicon::FaviconDriverObserver>
      favicon_observation_{this};
  base::WeakPtrFactory<PageImpl> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_PAGE_IMPL_H_
