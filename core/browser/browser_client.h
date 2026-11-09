#ifndef OA_BROWSER_BROWSER_CLIENT_H_
#define OA_BROWSER_BROWSER_CLIENT_H_

#include "chrome/browser/chrome_content_browser_client.h"

namespace content {
class NavigationThrottleRegistry;
}

namespace oa {

class BrowserClient : public ChromeContentBrowserClient {
 public:
  BrowserClient();
  ~BrowserClient() override;

  // ChromeContentBrowserClient:
  void CreateThrottlesForNavigation(
      content::NavigationThrottleRegistry& registry) override;
};

}  // namespace oa

#endif  // OA_BROWSER_BROWSER_CLIENT_H_
