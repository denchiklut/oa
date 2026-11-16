#ifndef OA_PUBLIC_AD_BLOCKER_H_
#define OA_PUBLIC_AD_BLOCKER_H_

#include <functional>
#include <string>
#include <vector>

namespace oa {
void SetBlockLists(std::vector<std::string> lists,
                   std::function<void(bool)> completion);
void SetAdBlockExcludedHosts(std::vector<std::string> hosts);
void ShutdownAdBlocker();
}  // namespace oa

#endif
