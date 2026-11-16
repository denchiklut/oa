#include "oa/browser/ad_blocker_service.h"
#include <map>
#include <utility>
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/task/thread_pool.h"
#include "content/public/browser/render_process_host.h"
#include "ipc/ipc_channel_proxy.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "oa/common/ad_blocker.mojom.h"
#include "oa/public/ad_blocker.h"

namespace oa {
namespace {
struct Service {
  scoped_refptr<AdBlockState> state = base::MakeRefCounted<AdBlockState>();
  base::ReadOnlySharedMemoryRegion region;
  std::map<int, mojo::AssociatedRemote<mojom::AdBlockerAgent>> agents;
  uint64_t revision = 0;
};
Service& GetService() {
  static base::NoDestructor<Service> service;
  return *service;
}
void PublishRules() {
  auto& service = GetService();
  for (auto& [id, agent] : service.agents) {
    agent->SetRules(service.region.IsValid()
                        ? service.region.Duplicate()
                        : base::ReadOnlySharedMemoryRegion());
  }
}
}  // namespace

scoped_refptr<AdBlockState> BrowserAdBlockState() {
  return GetService().state;
}

void BindAdBlockRenderer(content::RenderProcessHost* host) {
  auto& service = GetService();
  int id = host->GetDeprecatedID();
  auto& agent = service.agents[id];
  agent.reset();
  host->GetChannel()->GetRemoteAssociatedInterface(&agent);
  agent.set_disconnect_handler(
      base::BindOnce([](int id) { GetService().agents.erase(id); }, id));
  agent->SetExcludedHosts(service.state->Get().excluded_hosts);
  agent->SetRules(service.region.IsValid()
                      ? service.region.Duplicate()
                      : base::ReadOnlySharedMemoryRegion());
}

void SetBlockLists(std::vector<std::string> lists,
                   std::function<void(bool)> completion) {
  auto& service = GetService();
  uint64_t revision = ++service.revision;
  if (lists.empty()) {
    service.region = {};
    service.state->SetRules(nullptr);
    PublishRules();
    completion(true);
    return;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&CompileBlockLists, std::move(lists)),
      base::BindOnce(
          [](uint64_t revision, std::function<void(bool)> completion,
             base::ReadOnlySharedMemoryRegion region) {
            auto& service = GetService();
            if (revision != service.revision || !region.IsValid()) {
              completion(false);
              return;
            }
            auto rules = AdBlockRules::Map(region.Duplicate());
            if (!rules) {
              completion(false);
              return;
            }
            service.region = std::move(region);
            service.state->SetRules(std::move(rules));
            PublishRules();
            completion(true);
          },
          revision, std::move(completion)));
}
void SetAdBlockExcludedHosts(std::vector<std::string> hosts) {
  auto& service = GetService();
  service.state->SetExcludedHosts(hosts);
  for (auto& [id, agent] : service.agents) {
    agent->SetExcludedHosts(hosts);
  }
}
void ShutdownAdBlocker() {
  auto& service = GetService();
  ++service.revision;
  service.agents.clear();
  service.region = {};
  service.state->SetRules(nullptr);
}
}  // namespace oa
