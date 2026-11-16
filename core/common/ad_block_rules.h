#ifndef OA_COMMON_AD_BLOCK_RULES_H_
#define OA_COMMON_AD_BLOCK_RULES_H_

#include <memory>
#include <string>
#include <vector>

#include "base/memory/read_only_shared_memory_region.h"
#include "base/memory/ref_counted.h"
#include "base/synchronization/lock.h"
#include "third_party/blink/public/common/loader/url_loader_throttle.h"
#include "url/gurl.h"
#include "url/origin.h"

namespace network {
struct ResourceRequest;
}

namespace oa {

class AdBlockRules : public base::RefCountedThreadSafe<AdBlockRules> {
 public:
  static scoped_refptr<AdBlockRules> Map(
      base::ReadOnlySharedMemoryRegion region);
  explicit AdBlockRules(base::ReadOnlySharedMemoryMapping mapping);
  bool Blocks(const network::ResourceRequest& request, bool browser) const;
  std::string Styles(const GURL& url, const url::Origin& parent) const;

 private:
  friend class base::RefCountedThreadSafe<AdBlockRules>;
  ~AdBlockRules();
  base::ReadOnlySharedMemoryMapping mapping_;
};

struct AdBlockSnapshot {
  scoped_refptr<AdBlockRules> rules;
  std::vector<std::string> excluded_hosts;
  bool IsExcluded(const url::Origin& origin) const;
};

class AdBlockState : public base::RefCountedThreadSafe<AdBlockState> {
 public:
  AdBlockState();
  AdBlockSnapshot Get() const;
  void SetRules(scoped_refptr<AdBlockRules> rules);
  void SetExcludedHosts(std::vector<std::string> hosts);

 private:
  friend class base::RefCountedThreadSafe<AdBlockState>;
  ~AdBlockState();
  mutable base::Lock lock_;
  AdBlockSnapshot snapshot_ GUARDED_BY(lock_);
};

class AdBlockThrottle : public blink::URLLoaderThrottle {
 public:
  explicit AdBlockThrottle(scoped_refptr<AdBlockState> state,
                           url::Origin top_origin,
                           bool browser);
  ~AdBlockThrottle() override;
  void WillStartRequest(network::ResourceRequest* request,
                        bool* defer) override;

 private:
  scoped_refptr<AdBlockState> state_;
  url::Origin top_origin_;
  bool browser_;
};

base::ReadOnlySharedMemoryRegion CompileBlockLists(
    const std::vector<std::string>& lists);

}  // namespace oa
#endif
