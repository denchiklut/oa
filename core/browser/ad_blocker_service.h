#ifndef OA_BROWSER_AD_BLOCKER_SERVICE_H_
#define OA_BROWSER_AD_BLOCKER_SERVICE_H_
#include "oa/common/ad_block_rules.h"
namespace content {
class RenderProcessHost;
}
namespace oa {
scoped_refptr<AdBlockState> BrowserAdBlockState();
void BindAdBlockRenderer(content::RenderProcessHost* host);
}  // namespace oa
#endif
