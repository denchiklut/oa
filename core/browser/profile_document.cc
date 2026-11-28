// Copyright 2026 The Oa Authors
#include "oa/public/profile_document.h"

#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/time/time.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/storage_partition.h"
#include "net/cookies/site_for_cookies.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "oa/browser/profile_services.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/gurl.h"

namespace oa {

void LoadProfileDocument(
    const std::string& profile_id,
    BrowserContextType type,
    const std::string& url,
    std::function<void(std::string, int, std::optional<std::string>)> done) {
  LoadBrowserContext(
      profile_id, type,
      base::BindOnce(
          [](GURL url, decltype(done) done, Profile* profile) {
            if (!profile || !url.SchemeIs("https")) {
              done({}, 0, std::nullopt);
              return;
            }
            constexpr auto annotation =
                net::DefineNetworkTrafficAnnotation("oa_sidebar_document", R"(
            semantics {
              sender: "Oa Sidebar"
              description: "Reads GitHub pull requests for Live Folders or Gmail unread feeds for sidebar previews."
              trigger: "Showing or refreshing an enabled Live Folder or Gmail preview or Favorite."
              data: "The requested dashboard or inbox URL and the profile's session cookies for the destination."
              destination: WEBSITE
            }
            policy {
              cookies_allowed: YES
              cookies_store: "user"
              setting: "Remove the Live Folder or disable Google Mail in Previews Settings."
              policy_exception_justification: "Controlled by sidebar items and preview preferences."
            })");
            auto request = std::make_unique<network::ResourceRequest>();
            request->url = url;
            request->site_for_cookies = net::SiteForCookies::FromUrl(url);
            request->credentials_mode =
                network::mojom::CredentialsMode::kInclude;
            request->headers.SetHeader(
                "Accept",
                url.host() == "mail.google.com"
                    ? "application/atom+xml, application/xml, text/xml"
                    : "text/html");
            auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                           annotation);
            loader->SetTimeoutDuration(base::Seconds(20));
            auto* download = loader.get();
            download->DownloadToString(
                profile->GetDefaultStoragePartition()
                    ->GetURLLoaderFactoryForBrowserProcess()
                    .get(),
                base::BindOnce(
                    [](decltype(loader) loader, decltype(done) done,
                       std::optional<std::string> body) {
                      auto* response = loader->ResponseInfo();
                      int status = response && response->headers
                                       ? response->headers->response_code()
                                       : 0;
                      done(loader->GetFinalURL().spec(), status,
                           std::move(body));
                    },
                    std::move(loader), std::move(done)),
                4 * 1024 * 1024);
          },
          GURL(url), std::move(done)));
}

}  // namespace oa
