#include "oa/browser/page_impl.h"

#import <AppKit/AppKit.h>

#include <set>
#include <utility>
#include <vector>

#include "base/location.h"
#include "base/no_destructor.h"
#include "base/strings/utf_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "content/public/common/referrer.h"
#include "oa/browser/window_browser.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
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
    : window_browser_(window_browser->GetWeakPtr()), observer_(observer) {}

PageImpl::~PageImpl() {
  observer_ = nullptr;
  Drop();
}

bool PageImpl::Insert(std::unique_ptr<content::WebContents> contents) {
  content::WebContents* page = contents.get();
  page->SetUserData(kPageMarkerKey,
                    std::make_unique<PageMarker>(weak_factory_.GetWeakPtr()));
  if (!window_browser_ || !window_browser_->Insert(std::move(contents))) {
    return false;
  }
  // Hidden until its view first joins a window, as Chrome's background tabs.
  page->WasHidden();
  Bind(page);
  OpenPages().insert(this);
  return true;
}

void PageImpl::Bind(content::WebContents* contents) {
  set_inner(contents->GetDelegate());
  contents->SetDelegate(this);
  Observe(contents);
}

void PageImpl::Unbind() {
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

void PageImpl::OnRemovedFromStrip() {
  if (closing_) {
    return;
  }
  Unbind();
  NotifyClosed();
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

void PageImpl::Close() {
  content::WebContents* contents = web_contents();
  if (!contents) {
    return;
  }
  if (!window_browser_) {
    Drop();
    return;
  }
  // A PageImpl of its own owns the page while its unload handlers run.
  observer_ = nullptr;
  Unbind();
  OpenPages().erase(this);
  auto* closing = new PageImpl(window_browser_.get(), /*observer=*/nullptr);
  closing->closing_ = true;
  contents->SetUserData(
      kPageMarkerKey,
      std::make_unique<PageMarker>(closing->weak_factory_.GetWeakPtr()));
  closing->Bind(contents);
  OpenPages().insert(closing);
  if (!window_browser_->Close(contents)) {
    closing->Drop();
  }
}

void PageImpl::Drop() {
  content::WebContents* contents = web_contents();
  if (!contents) {
    return;
  }
  Unbind();
  if (window_browser_) {
    window_browser_->Remove(contents);
  }
  OpenPages().erase(this);
  if (closing_) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                                  this);
  }
}

content::WebContents* PageImpl::OpenURLFromTab(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)> callback) {
  if (params.disposition == WindowOpenDisposition::CURRENT_TAB) {
    return ForwardingWebContentsDelegate::OpenURLFromTab(source, params,
                                                         std::move(callback));
  }
  return nullptr;
}

content::WebContents* PageImpl::AddNewContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    WindowOpenDisposition disposition,
    const blink::mojom::WindowFeatures& window_features,
    bool user_gesture,
    bool* was_blocked) {
  if (was_blocked) {
    *was_blocked = true;
  }
  return nullptr;
}

void PageImpl::ActivateContents(content::WebContents* contents) {}

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
  if (closing_) {
    ForwardingWebContentsDelegate::CloseContents(source);
  }
}

content::JavaScriptDialogManager* PageImpl::GetJavaScriptDialogManager(
    content::WebContents* source) {
  return content::WebContentsDelegate::GetJavaScriptDialogManager(source);
}

bool PageImpl::HandleContextMenu(content::RenderFrameHost& render_frame_host,
                                 const content::ContextMenuParams& params) {
  return true;
}

bool PageImpl::CanEnterFullscreenModeForTab(
    content::RenderFrameHost* requesting_frame) {
  return false;
}

void PageImpl::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  NotifyStateChanged();
}

void PageImpl::LoadProgressChanged(double progress) {
  load_progress_ = progress;
  NotifyStateChanged();
}

void PageImpl::TitleWasSet(content::NavigationEntry* entry) {
  NotifyStateChanged();
}

void PageImpl::WebContentsDestroyed() {
  set_inner(nullptr);
  if (closing_) {
    OpenPages().erase(this);
    base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                                  this);
    return;
  }
  NotifyClosed();
}

void PageImpl::NotifyStateChanged() {
  if (observer_) {
    observer_->OnPageStateChanged();
  }
}

void PageImpl::NotifyClosed() {
  if (!OpenPages().erase(this)) {
    return;
  }
  if (observer_) {
    observer_->OnPageClosed();
  }
}

}  // namespace oa
