#include "oa/browser/browser_client.h"

#include "oa/browser/kept_address_throttle.h"

namespace oa {

BrowserClient::BrowserClient() = default;

BrowserClient::~BrowserClient() = default;

void BrowserClient::CreateThrottlesForNavigation(
    content::NavigationThrottleRegistry& registry) {
  ChromeContentBrowserClient::CreateThrottlesForNavigation(registry);
  KeptAddressThrottle::MaybeAdd(registry);
}

}  // namespace oa
