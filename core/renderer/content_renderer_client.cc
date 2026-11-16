#include "oa/renderer/content_renderer_client.h"
#include <map>
#include <utility>
#include "base/functional/bind.h"
#include "chrome/renderer/chrome_content_renderer_client.h"
#include "content/public/renderer/render_frame.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_visitor.h"
#include "content/public/renderer/render_thread.h"
#include "content/public/renderer/render_thread_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver.h"
#include "oa/common/ad_block_rules.h"
#include "oa/common/ad_blocker.mojom.h"
#include "services/network/public/cpp/resource_request.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/platform/url_loader_throttle_provider.h"
#include "third_party/blink/public/platform/web_security_origin.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"

namespace oa {
namespace {
class FrameOrigins : public base::RefCountedThreadSafe<FrameOrigins> {
 public:
  url::Origin Get(const blink::LocalFrameToken& token) const {
    base::AutoLock guard(lock_);
    auto found = origins_.find(token);
    return found == origins_.end() ? url::Origin() : found->second;
  }
  void Set(const blink::LocalFrameToken& token, url::Origin origin) {
    base::AutoLock guard(lock_);
    origins_[token] = std::move(origin);
  }
  void Remove(const blink::LocalFrameToken& token) {
    base::AutoLock guard(lock_);
    origins_.erase(token);
  }

 private:
  friend class base::RefCountedThreadSafe<FrameOrigins>;
  ~FrameOrigins() = default;
  mutable base::Lock lock_;
  std::map<blink::LocalFrameToken, url::Origin> origins_ GUARDED_BY(lock_);
};

class FrameObserver : public content::RenderFrameObserver {
 public:
  FrameObserver(content::RenderFrame* frame,
                scoped_refptr<FrameOrigins> origins)
      : RenderFrameObserver(frame),
        origins_(std::move(origins)),
        token_(frame->GetWebFrame()->GetLocalFrameToken()) {
    DidCreateNewDocument();
  }
  void DidCreateNewDocument() override {
    origins_->Set(token_,
                  render_frame()->GetWebFrame()->Top()->GetSecurityOrigin());
  }
  void OnDestruct() override {
    origins_->Remove(token_);
    delete this;
  }

 private:
  scoped_refptr<FrameOrigins> origins_;
  blink::LocalFrameToken token_;
};

class AdBlockerAgent : public content::RenderThreadObserver,
                       public mojom::AdBlockerAgent,
                       public content::RenderFrameVisitor {
 public:
  explicit AdBlockerAgent(scoped_refptr<AdBlockState> state)
      : state_(std::move(state)) {
    content::RenderThread::Get()->AddObserver(this);
  }
  ~AdBlockerAgent() override {
    content::RenderThread::Get()->RemoveObserver(this);
  }
  void RegisterMojoInterfaces(
      blink::AssociatedInterfaceRegistry* registry) override {
    registry->AddInterface<mojom::AdBlockerAgent>(base::BindRepeating(
        [](AdBlockerAgent* agent,
           mojo::PendingAssociatedReceiver<mojom::AdBlockerAgent> receiver) {
          agent->receiver_.reset();
          agent->receiver_.Bind(std::move(receiver));
        },
        base::Unretained(this)));
  }
  void UnregisterMojoInterfaces(
      blink::AssociatedInterfaceRegistry* registry) override {
    registry->RemoveInterface(mojom::AdBlockerAgent::Name_);
  }
  void SetRules(base::ReadOnlySharedMemoryRegion region) override {
    if (!region.IsValid()) {
      state_->SetRules(nullptr);
    } else {
      auto rules = AdBlockRules::Map(std::move(region));
      if (!rules) {
        return;
      }
      state_->SetRules(std::move(rules));
    }
    styles_.clear();
    content::RenderFrame::ForEach(this);
  }
  void SetExcludedHosts(const std::vector<std::string>& hosts) override {
    state_->SetExcludedHosts(hosts);
    content::RenderFrame::ForEach(this);
  }
  bool Visit(content::RenderFrame* frame) override {
    auto* web_frame = frame->GetWebFrame();
    auto document = web_frame->GetDocument();
    if (document.IsNull()) {
      return true;
    }
    auto key = blink::WebString::FromAscii("blocklist");
    auto snapshot = state_->Get();
    const GURL url = document.Url();
    auto parent = web_frame->Parent() ? web_frame->Parent()->GetSecurityOrigin()
                                      : document.GetSecurityOrigin();
    std::string css;
    if (snapshot.rules && !snapshot.IsExcluded(url::Origin::Create(url)) &&
        !snapshot.IsExcluded(web_frame->Top()->GetSecurityOrigin())) {
      auto cache_key =
          std::make_pair(url.spec(), url::Origin(parent).Serialize());
      auto found = styles_.find(cache_key);
      if (found == styles_.end()) {
        if (styles_.size() >= 128) {
          styles_.clear();
        }
        found = styles_
                    .emplace(std::move(cache_key),
                             snapshot.rules->Styles(url, parent))
                    .first;
      }
      css = found->second;
    }
    document.RemoveInsertedStyleSheet(key);
    if (!css.empty()) {
      document.InsertStyleSheet(blink::WebString::FromUtf8(css), &key);
    }
    return true;
  }

 private:
  scoped_refptr<AdBlockState> state_;
  mojo::AssociatedReceiver<mojom::AdBlockerAgent> receiver_{this};
  std::map<std::pair<std::string, std::string>, std::string> styles_;
};

class ThrottleProvider : public blink::URLLoaderThrottleProvider {
 public:
  ThrottleProvider(std::unique_ptr<blink::URLLoaderThrottleProvider> chrome,
                   scoped_refptr<AdBlockState> state,
                   scoped_refptr<FrameOrigins> origins)
      : chrome_(std::move(chrome)),
        state_(std::move(state)),
        origins_(std::move(origins)) {}
  std::unique_ptr<blink::URLLoaderThrottleProvider> Clone() override {
    return std::make_unique<ThrottleProvider>(chrome_->Clone(), state_,
                                              origins_);
  }
  std::vector<std::unique_ptr<blink::URLLoaderThrottle>> CreateThrottles(
      base::optional_ref<const blink::LocalFrameToken> token,
      const network::ResourceRequest& request) override {
    auto throttles = chrome_->CreateThrottles(token, request);
    auto top = token ? origins_->Get(*token) : url::Origin();
    if (token && content::RenderThread::IsMainThread()) {
      if (auto* frame = blink::WebLocalFrame::FromFrameToken(*token)) {
        top = frame->Top()->GetSecurityOrigin();
      }
    }
    throttles.push_back(std::make_unique<AdBlockThrottle>(state_, top, false));
    return throttles;
  }
  void SetOnline(bool online) override { chrome_->SetOnline(online); }

 private:
  std::unique_ptr<blink::URLLoaderThrottleProvider> chrome_;
  scoped_refptr<AdBlockState> state_;
  scoped_refptr<FrameOrigins> origins_;
};

class ContentRendererClient : public ChromeContentRendererClient {
 public:
  void RenderFrameCreated(content::RenderFrame* frame) override {
    ChromeContentRendererClient::RenderFrameCreated(frame);
    new FrameObserver(frame, origins_);
  }
  void RenderThreadStarted() override {
    ChromeContentRendererClient::RenderThreadStarted();
    agent_ = std::make_unique<AdBlockerAgent>(state_);
  }
  void RunScriptsAtDocumentStart(content::RenderFrame* frame) override {
    agent_->Visit(frame);
    ChromeContentRendererClient::RunScriptsAtDocumentStart(frame);
  }
  std::unique_ptr<blink::URLLoaderThrottleProvider>
  CreateURLLoaderThrottleProvider(
      blink::URLLoaderThrottleProviderType type) override {
    return std::make_unique<ThrottleProvider>(
        ChromeContentRendererClient::CreateURLLoaderThrottleProvider(type),
        state_, origins_);
  }

 private:
  scoped_refptr<AdBlockState> state_ = base::MakeRefCounted<AdBlockState>();
  scoped_refptr<FrameOrigins> origins_ = base::MakeRefCounted<FrameOrigins>();
  std::unique_ptr<AdBlockerAgent> agent_;
};
}  // namespace
std::unique_ptr<content::ContentRendererClient> CreateRendererClient() {
  return std::make_unique<ContentRendererClient>();
}
}  // namespace oa
