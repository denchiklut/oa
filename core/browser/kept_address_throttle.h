#ifndef OA_BROWSER_KEPT_ADDRESS_THROTTLE_H_
#define OA_BROWSER_KEPT_ADDRESS_THROTTLE_H_

#include "content/public/browser/navigation_throttle.h"

namespace content {
class NavigationThrottleRegistry;
}

namespace oa {

// Sends a cross-origin link click on a page that keeps its address to a new
// page, as Arc does for a pinned tab.
class KeptAddressThrottle : public content::NavigationThrottle {
 public:
  static void MaybeAdd(content::NavigationThrottleRegistry& registry);

  explicit KeptAddressThrottle(content::NavigationThrottleRegistry& registry);
  ~KeptAddressThrottle() override;

  // content::NavigationThrottle:
  ThrottleCheckResult WillStartRequest() override;
  const char* GetNameForLogging() override;
};

}  // namespace oa

#endif  // OA_BROWSER_KEPT_ADDRESS_THROTTLE_H_
