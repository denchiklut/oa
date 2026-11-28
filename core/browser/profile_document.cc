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
            constexpr auto annotation = net::DefineNetworkTrafficAnnotation(
                "oa_live_folder_document", R"(
            semantics {
              sender: "Oa Live Folders"
              description: "Reads the GitHub pull request dashboard for a pinned folder."
              trigger: "Enabling or refreshing the folder, or focusing its Space."
              data: "GitHub pull request query and the profile's GitHub session cookies."
              destination: WEBSITE
            }
            policy {
              cookies_allowed: YES
              cookies_store: "user"
              setting: "Removing the GitHub Live Folder stops its refreshes."
              policy_exception_justification: "Opt-in sidebar feature."
            })");
            auto request = std::make_unique<network::ResourceRequest>();
            request->url = url;
            request->site_for_cookies = net::SiteForCookies::FromUrl(url);
            request->credentials_mode =
                network::mojom::CredentialsMode::kInclude;
            request->headers.SetHeader("Accept", "text/html");
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
