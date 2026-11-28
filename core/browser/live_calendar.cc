// Copyright 2026 The Oa Authors
#include "oa/public/live_calendar.h"

#include <map>
#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

#include "base/base64.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/string_util.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/devtools_agent_host_client.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/storage_partition.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "net/cookies/canonical_cookie.h"
#include "net/cookies/cookie_options.h"
#include "net/cookies/cookie_util.h"
#include "oa/browser/profile_services.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace oa {
namespace {

bool IsGoogleDomain(std::string_view domain) {
  std::string lowered = base::ToLowerASCII(domain);
  return lowered == "google.com" || base::EndsWith(lowered, ".google.com");
}

bool IsCalendarEventsURL(const std::string& url_spec) {
  GURL url(url_spec);
  if (!url.is_valid() || !url.SchemeIs("https") ||
      !IsGoogleDomain(url.host())) {
    return false;
  }
  return url.path().find("/events") != std::string::npos;
}

bool IsSignedOutRedirect(const GURL& url) {
  if (!url.is_valid()) {
    return false;
  }
  std::string host = base::ToLowerASCII(url.host());
  return host == "accounts.google.com" || host == "workspace.google.com" ||
         (host == "www.google.com" &&
          base::StartsWith(url.path(), "/calendar/about"));
}

// Self-owned session for one background Google Calendar capture. Tears down its
// WebContents and ephemeral off-the-record profile on completion or timeout.
class LiveCalendarSession : public content::DevToolsAgentHostClient,
                            public content::WebContentsObserver {
 public:
  static void Start(const std::string& profile_id,
                    int account_number,
                    std::function<void(LiveCalendarCapture)> done) {
    auto* session = new LiveCalendarSession(
        profile_id, std::max(0, account_number), std::move(done));
    session->Begin();
  }

  ~LiveCalendarSession() override { Cleanup(); }

 private:
  LiveCalendarSession(std::string profile_id,
                      int account_number,
                      std::function<void(LiveCalendarCapture)> done)
      : profile_id_(std::move(profile_id)),
        account_number_(account_number),
        done_(std::move(done)),
        otr_id_(Profile::OTRProfileID::CreateUnique("oa::live_calendar")) {}

  void Begin() {
    timeout_timer_.Start(
        FROM_HERE, base::Seconds(20),
        base::BindOnce(&LiveCalendarSession::Finish, weak_factory_.GetWeakPtr(),
                       /*signed_out=*/false));
    LoadBrowserProfile(profile_id_,
                       base::BindOnce(&LiveCalendarSession::OnProfileLoaded,
                                      weak_factory_.GetWeakPtr()));
  }

  void OnProfileLoaded(Profile* profile) {
    if (!profile) {
      Finish(/*signed_out=*/false);
      return;
    }
    auto* cookies = profile->GetDefaultStoragePartition()
                        ->GetCookieManagerForBrowserProcess();
    if (!cookies) {
      Finish(/*signed_out=*/false);
      return;
    }
    cookies->GetAllCookies(base::BindOnce(&LiveCalendarSession::OnCookiesLoaded,
                                          weak_factory_.GetWeakPtr()));
  }

  void OnCookiesLoaded(const std::vector<net::CanonicalCookie>& all_cookies) {
    Profile* profile = GetLoadedBrowserProfile(profile_id_);
    if (!profile) {
      Finish(/*signed_out=*/false);
      return;
    }
    std::vector<net::CanonicalCookie> google_cookies;
    for (const auto& cookie : all_cookies) {
      if (IsGoogleDomain(cookie.Domain())) {
        google_cookies.push_back(cookie);
      }
    }
    if (google_cookies.empty()) {
      Finish(/*signed_out=*/true);
      return;
    }
    Profile* otr =
        profile->GetOffTheRecordProfile(otr_id_, /*create_if_needed=*/true);
    if (!otr) {
      Finish(/*signed_out=*/false);
      return;
    }
    auto* otr_cookies =
        otr->GetDefaultStoragePartition()->GetCookieManagerForBrowserProcess();
    if (!otr_cookies) {
      Finish(/*signed_out=*/false);
      return;
    }
    pending_cookies_ = google_cookies.size();
    net::CookieOptions options = net::CookieOptions::MakeAllInclusive();
    for (const auto& cookie : google_cookies) {
      GURL source = net::cookie_util::SimulatedCookieSource(cookie, "https");
      otr_cookies->SetCanonicalCookie(
          cookie, source, options,
          base::BindOnce(&LiveCalendarSession::OnCookieSeeded,
                         weak_factory_.GetWeakPtr()));
    }
  }

  void OnCookieSeeded(net::CookieAccessResult) {
    if (pending_cookies_ == 0) {
      return;
    }
    if (--pending_cookies_ == 0) {
      LaunchHiddenPage();
    }
  }

  void LaunchHiddenPage() {
    Profile* profile = GetLoadedBrowserProfile(profile_id_);
    if (!profile || !profile->HasOffTheRecordProfile(otr_id_)) {
      Finish(/*signed_out=*/false);
      return;
    }
    Profile* otr =
        profile->GetOffTheRecordProfile(otr_id_, /*create_if_needed=*/false);
    if (!otr) {
      Finish(/*signed_out=*/false);
      return;
    }
    content::WebContents::CreateParams params(otr);
    params.initially_hidden = true;
    web_contents_ = content::WebContents::Create(params);
    Observe(web_contents_.get());
    agent_host_ =
        content::DevToolsAgentHost::GetOrCreateFor(web_contents_.get());
    agent_host_->AttachClient(this);
    SendCDP("Network.enable", base::DictValue());

    GURL url("https://calendar.google.com/calendar/u/" +
             std::to_string(account_number_) + "/r");
    content::NavigationController::LoadURLParams load_params(url);
    load_params.transition_type = ui::PAGE_TRANSITION_AUTO_TOPLEVEL;
    web_contents_->GetController().LoadURLWithParams(load_params);
  }

  int SendCDP(const std::string& method, base::DictValue params) {
    if (!agent_host_) {
      return 0;
    }
    int id = next_command_id_++;
    base::DictValue message;
    message.Set("id", id);
    message.Set("method", method);
    if (!params.empty()) {
      message.Set("params", std::move(params));
    }
    if (auto json = base::WriteJson(message)) {
      agent_host_->DispatchProtocolMessage(this, base::as_byte_span(*json));
    }
    return id;
  }

  // content::WebContentsObserver:
  void DidFinishNavigation(content::NavigationHandle* handle) override {
    if (!handle->IsInPrimaryMainFrame() || !handle->HasCommitted()) {
      return;
    }
    if (IsSignedOutRedirect(handle->GetURL())) {
      Finish(/*signed_out=*/true);
    }
  }

  // content::DevToolsAgentHostClient:
  void DispatchProtocolMessage(content::DevToolsAgentHost* agent_host,
                               base::span<const uint8_t> message) override {
    if (finished_) {
      return;
    }
    std::string_view text(reinterpret_cast<const char*>(message.data()),
                          message.size());
    std::optional<base::DictValue> dict =
        base::JSONReader::ReadDict(text, base::JSON_PARSE_RFC);
    if (!dict) {
      return;
    }
    if (const std::string* method = dict->FindString("method")) {
      const base::DictValue* params = dict->FindDict("params");
      if (!params) {
        return;
      }
      if (*method == "Network.responseReceived") {
        const std::string* request_id = params->FindString("requestId");
        const base::DictValue* response = params->FindDict("response");
        if (!request_id || !response) {
          return;
        }
        const std::string* url = response->FindString("url");
        std::optional<int> status = response->FindInt("status");
        if (url && status && *status == 200 && IsCalendarEventsURL(*url)) {
          matching_requests_.insert(*request_id);
        }
      } else if (*method == "Network.loadingFinished") {
        const std::string* request_id = params->FindString("requestId");
        if (request_id && matching_requests_.erase(*request_id) > 0) {
          base::DictValue req;
          req.Set("requestId", *request_id);
          int command_id = SendCDP("Network.getResponseBody", std::move(req));
          if (command_id > 0) {
            body_commands_.insert(command_id);
          }
        }
      }
      return;
    }
    std::optional<int> id = dict->FindInt("id");
    if (!id || body_commands_.erase(*id) == 0) {
      return;
    }
    const base::DictValue* result = dict->FindDict("result");
    if (!result) {
      return;
    }
    const std::string* body = result->FindString("body");
    if (!body || body->empty()) {
      return;
    }
    std::string decoded;
    if (result->FindBool("base64Encoded").value_or(false)) {
      if (!base::Base64Decode(*body, &decoded)) {
        return;
      }
    } else {
      decoded = *body;
    }
    if (decoded.find("\"items\"") == std::string::npos) {
      return;
    }
    payloads_.push_back(std::move(decoded));
    // Give secondary calendar requests a brief window to finish once primary
    // events arrive.
    settle_timer_.Start(
        FROM_HERE, base::Milliseconds(1500),
        base::BindOnce(&LiveCalendarSession::Finish, weak_factory_.GetWeakPtr(),
                       /*signed_out=*/false));
  }

  void AgentHostClosed(content::DevToolsAgentHost* agent_host) override {
    agent_host_ = nullptr;
  }

  void Finish(bool signed_out) {
    if (finished_) {
      return;
    }
    finished_ = true;
    timeout_timer_.Stop();
    settle_timer_.Stop();
    LiveCalendarCapture capture;
    capture.signed_out = signed_out;
    capture.event_payloads = std::move(payloads_);
    auto done = std::move(done_);
    Cleanup();
    if (done) {
      done(std::move(capture));
    }
    base::SequencedTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE, this);
  }

  void Cleanup() {
    if (agent_host_) {
      agent_host_->DetachClient(this);
      agent_host_ = nullptr;
    }
    Observe(nullptr);
    web_contents_.reset();
    if (Profile* profile = GetLoadedBrowserProfile(profile_id_);
        profile && profile->HasOffTheRecordProfile(otr_id_)) {
      if (Profile* otr = profile->GetOffTheRecordProfile(
              otr_id_, /*create_if_needed=*/false)) {
        profile->DestroyOffTheRecordProfile(otr);
      }
    }
  }

  std::string profile_id_;
  int account_number_ = 0;
  std::function<void(LiveCalendarCapture)> done_;
  Profile::OTRProfileID otr_id_;
  size_t pending_cookies_ = 0;
  int next_command_id_ = 1;
  bool finished_ = false;
  std::set<std::string> matching_requests_;
  std::set<int> body_commands_;
  std::vector<std::string> payloads_;
  std::unique_ptr<content::WebContents> web_contents_;
  scoped_refptr<content::DevToolsAgentHost> agent_host_;
  base::OneShotTimer timeout_timer_;
  base::OneShotTimer settle_timer_;
  base::WeakPtrFactory<LiveCalendarSession> weak_factory_{this};
};

}  // namespace

void FetchLiveCalendar(const std::string& profile_id,
                       int account_number,
                       std::function<void(LiveCalendarCapture)> done) {
  LiveCalendarSession::Start(profile_id, account_number, std::move(done));
}

}  // namespace oa
