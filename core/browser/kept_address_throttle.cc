#include "oa/browser/kept_address_throttle.h"

#include <memory>

#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/navigation_throttle_registry.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/page_impl.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace oa {

// static
void KeptAddressThrottle::MaybeAdd(
    content::NavigationThrottleRegistry& registry) {
  if (PageImpl::FromWebContents(
          registry.GetNavigationHandle().GetWebContents())) {
    registry.AddThrottle(std::make_unique<KeptAddressThrottle>(registry));
  }
}

KeptAddressThrottle::KeptAddressThrottle(
    content::NavigationThrottleRegistry& registry)
    : content::NavigationThrottle(registry) {}

KeptAddressThrottle::~KeptAddressThrottle() = default;

content::NavigationThrottle::ThrottleCheckResult
KeptAddressThrottle::WillStartRequest() {
  content::NavigationHandle* handle = navigation_handle();
  content::WebContents* contents = handle->GetWebContents();
  PageImpl* page = PageImpl::FromWebContents(contents);
  if (!page || !page->keeps_address() || !handle->IsInPrimaryMainFrame() ||
      !handle->IsRendererInitiated() || !handle->HasUserGesture() ||
      !ui::PageTransitionCoreTypeIs(handle->GetPageTransition(),
                                    ui::PAGE_TRANSITION_LINK)) {
    return PROCEED;
  }
  const GURL& current = contents->GetLastCommittedURL();
  if (!current.is_valid() || url::IsSameOriginWith(current, handle->GetURL())) {
    return PROCEED;
  }
  content::OpenURLParams params =
      content::OpenURLParams::FromNavigationHandle(handle);
  params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
  page->OpenURLFromTab(contents, params, {});
  return CANCEL_AND_IGNORE;
}

const char* KeptAddressThrottle::GetNameForLogging() {
  return "OaKeptAddressThrottle";
}

}  // namespace oa
