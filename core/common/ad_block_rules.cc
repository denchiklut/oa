#include "oa/common/ad_block_rules.h"

#include <algorithm>
#include <sstream>
#include <utility>

#include "base/containers/span.h"
#include "components/subresource_filter/core/common/first_party_origin.h"
#include "components/subresource_filter/core/common/indexed_ruleset.h"
#include "components/subresource_filter/tools/ruleset_converter/rule_stream.h"
#include "net/base/net_errors.h"
#include "services/network/public/cpp/resource_request.h"

namespace oa {
namespace {
namespace proto = url_pattern_index::proto;
using subresource_filter::IndexedRulesetMatcher;

proto::ElementType ElementType(network::mojom::RequestDestination destination) {
  using Destination = network::mojom::RequestDestination;
  switch (destination) {
    case Destination::kScript:
      return proto::ELEMENT_TYPE_SCRIPT;
    case Destination::kImage:
      return proto::ELEMENT_TYPE_IMAGE;
    case Destination::kStyle:
      return proto::ELEMENT_TYPE_STYLESHEET;
    case Destination::kFont:
      return proto::ELEMENT_TYPE_FONT;
    case Destination::kAudio:
    case Destination::kVideo:
    case Destination::kTrack:
      return proto::ELEMENT_TYPE_MEDIA;
    case Destination::kFrame:
    case Destination::kDocument:
    case Destination::kFencedframe:
    case Destination::kIframe:
      return proto::ELEMENT_TYPE_SUBDOCUMENT;
    case Destination::kObject:
    case Destination::kEmbed:
      return proto::ELEMENT_TYPE_OBJECT;
    case Destination::kWebBundle:
      return proto::ELEMENT_TYPE_WEBBUNDLE;
    default:
      return proto::ELEMENT_TYPE_OTHER;
  }
}
}  // namespace

base::ReadOnlySharedMemoryRegion CompileBlockLists(
    const std::vector<std::string>& lists) {
  subresource_filter::RulesetIndexer indexer(1);
  for (const auto& text : lists) {
    auto input = subresource_filter::RuleInputStream::Create(
        std::make_unique<std::istringstream>(text),
        subresource_filter::RulesetFormat::kFilterList);
    for (auto type = input->FetchNextRule();
         type != proto::RULE_TYPE_UNSPECIFIED; type = input->FetchNextRule()) {
      if (type == proto::RULE_TYPE_URL) {
        indexer.AddUrlRule(input->GetUrlRule());
      } else if (type == proto::RULE_TYPE_STYLE) {
        auto rule = input->GetStyleRule();
        if (rule.selector().find("+js") == std::string::npos &&
            !subresource_filter::DeleteStyleRuleOrAmend(&rule)) {
          indexer.AddStyleRuleFromProto(rule);
        }
      }
    }
  }
  indexer.Finish();
  auto memory = base::ReadOnlySharedMemoryRegion::Create(indexer.data().size());
  if (!memory.IsValid()) {
    return {};
  }
  memory.mapping.GetMemoryAsSpan<uint8_t>().copy_from(indexer.data());
  return std::move(memory.region);
}

scoped_refptr<AdBlockRules> AdBlockRules::Map(
    base::ReadOnlySharedMemoryRegion region) {
  auto mapping = region.Map();
  if (!mapping.IsValid() ||
      !IndexedRulesetMatcher::Verify(mapping.GetMemoryAsSpan<const uint8_t>(),
                                     0, "Oa.AdBlock")) {
    return nullptr;
  }
  return base::MakeRefCounted<AdBlockRules>(std::move(mapping));
}

AdBlockRules::AdBlockRules(base::ReadOnlySharedMemoryMapping mapping)
    : mapping_(std::move(mapping)) {}
AdBlockRules::~AdBlockRules() = default;

bool AdBlockRules::Blocks(const network::ResourceRequest& request,
                          bool browser) const {
  if (!request.url.SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  const auto origin =
      request.request_initiator.value_or(url::Origin::Create(request.url));
  if (!origin.opaque() && !origin.GetURL().SchemeIsHTTPOrHTTPS()) {
    return false;
  }
  subresource_filter::FirstPartyOrigin first_party(origin);
  if (browser &&
      (!first_party.IsThirdParty(request.url) ||
       request.destination == network::mojom::RequestDestination::kDocument)) {
    return false;
  }
  IndexedRulesetMatcher matcher(mapping_.GetMemoryAsSpan<const uint8_t>());
  if (matcher.ShouldDisableFilteringForDocument(
          request.url, origin, proto::ACTIVATION_TYPE_DOCUMENT)) {
    return false;
  }
  bool generic_disabled = matcher.ShouldDisableFilteringForDocument(
      request.url, origin, proto::ACTIVATION_TYPE_GENERICBLOCK);
  return matcher.GetLoadPolicyForResourceLoad(request.url, first_party,
                                              ElementType(request.destination),
                                              generic_disabled, nullptr) ==
         subresource_filter::LoadPolicy::DISALLOW;
}

std::string AdBlockRules::Styles(const GURL& url,
                                 const url::Origin& parent) const {
  if (!url.SchemeIsHTTPOrHTTPS()) {
    return {};
  }
  auto bytes = mapping_.GetMemoryAsSpan<const uint8_t>();
  IndexedRulesetMatcher matcher(bytes);
  if (matcher.ShouldDisableFilteringForDocument(
          url, parent, proto::ACTIVATION_TYPE_DOCUMENT) ||
      matcher.ShouldDisableFilteringForDocument(
          url, parent, proto::ACTIVATION_TYPE_ELEMHIDE)) {
    return {};
  }
  auto origin = url::Origin::Create(url);
  std::vector<std::string_view> selectors;
  matcher.GetDomainSelectors(origin, selectors);
  if (!matcher.ShouldDisableFilteringForDocument(
          url, parent, proto::ACTIVATION_TYPE_GENERICHIDE)) {
    const auto* styles =
        subresource_filter::flat::GetIndexedRuleset(bytes.data())
            ->style_rule_index();
    auto collect = [&](const auto* entries, bool classes) {
      if (!entries) {
        return;
      }
      for (const auto* entry : *entries) {
        auto name = entry->name()->string_view();
        if (name.starts_with('.') || name.starts_with('#')) {
          name.remove_prefix(1);
        }
        auto hash = subresource_filter::GetStyleRuleHash(name);
        if (classes) {
          matcher.GetSelectorsByClass(origin, name, hash, selectors);
        } else {
          matcher.GetSelectorsById(origin, name, hash, selectors);
        }
      }
    };
    collect(styles->class_map(), true);
    collect(styles->id_map(), false);
  }
  std::ranges::sort(selectors);
  selectors.erase(std::unique(selectors.begin(), selectors.end()),
                  selectors.end());
  std::string css;
  for (auto selector : selectors) {
    css.append(selector);
    css.append("{display:none!important;}\n");
  }
  return css;
}

bool AdBlockSnapshot::IsExcluded(const url::Origin& origin) const {
  return std::ranges::contains(excluded_hosts, origin.host());
}

AdBlockState::AdBlockState() = default;
AdBlockState::~AdBlockState() = default;
AdBlockSnapshot AdBlockState::Get() const {
  base::AutoLock guard(lock_);
  return snapshot_;
}
void AdBlockState::SetRules(scoped_refptr<AdBlockRules> rules) {
  base::AutoLock guard(lock_);
  snapshot_.rules = std::move(rules);
}
void AdBlockState::SetExcludedHosts(std::vector<std::string> hosts) {
  base::AutoLock guard(lock_);
  snapshot_.excluded_hosts = std::move(hosts);
}

AdBlockThrottle::AdBlockThrottle(scoped_refptr<AdBlockState> state,
                                 bool browser)
    : state_(std::move(state)), browser_(browser) {}
AdBlockThrottle::~AdBlockThrottle() = default;

void AdBlockThrottle::WillStartRequest(network::ResourceRequest* request,
                                       bool* defer) {
  auto snapshot = state_->Get();
  if (!snapshot.rules) {
    return;
  }
  // As Arc: the page is known only from the request. A renderer's requests
  // carry their top frame's origin (a Chromium patch); the browser's carry it
  // in their isolation info.
  if (snapshot.IsExcluded(request->request_initiator.value_or(
          url::Origin::Create(request->url))) ||
      (request->top_frame_origin &&
       snapshot.IsExcluded(*request->top_frame_origin))) {
    return;
  }
  if (request->trusted_params) {
    const auto& top =
        request->trusted_params->isolation_info.top_frame_origin();
    if (top && snapshot.IsExcluded(*top)) {
      return;
    }
  }
  if (snapshot.rules->Blocks(*request, browser_)) {
    delegate_->CancelWithError(net::ERR_BLOCKED_BY_CLIENT, "Oa ad blocker");
  }
}
}  // namespace oa
