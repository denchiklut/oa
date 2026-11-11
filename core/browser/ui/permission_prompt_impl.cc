// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/permission_prompt_impl.h"

#include <variant>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/permission_bubble/permission_prompt.h"
#include "chrome/browser/ui/url_identity.h"
#include "components/permissions/permission_request.h"
#include "components/permissions/request_type.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/page_impl.h"

namespace oa {

namespace {

uint64_t NextRequestID() {
  static uint64_t last = 0;
  return ++last;
}

PermissionKind ToKind(permissions::RequestType type) {
  using permissions::RequestType;
  switch (type) {
    case RequestType::kAmbientLogin:
      return PermissionKind::kAmbientLogin;
    case RequestType::kArSession:
      return PermissionKind::kArSession;
    case RequestType::kCameraPanTiltZoom:
      return PermissionKind::kCameraPanTiltZoom;
    case RequestType::kCameraStream:
      return PermissionKind::kCamera;
    case RequestType::kCapturedSurfaceControl:
      return PermissionKind::kCapturedSurfaceControl;
    case RequestType::kClipboard:
      return PermissionKind::kClipboard;
    case RequestType::kTopLevelStorageAccess:
      return PermissionKind::kTopLevelStorageAccess;
    case RequestType::kDiskQuota:
      return PermissionKind::kDiskQuota;
    case RequestType::kFileSystemAccess:
      return PermissionKind::kFileSystemAccess;
    case RequestType::kGeolocation:
      return PermissionKind::kGeolocation;
    case RequestType::kHandTracking:
      return PermissionKind::kHandTracking;
    case RequestType::kIdentityProvider:
      return PermissionKind::kIdentityProvider;
    case RequestType::kIdleDetection:
      return PermissionKind::kIdleDetection;
    case RequestType::kLocalFonts:
      return PermissionKind::kLocalFonts;
    case RequestType::kLocalNetwork:
      return PermissionKind::kLocalNetwork;
    case RequestType::kLoopbackNetwork:
      return PermissionKind::kLoopbackNetwork;
    case RequestType::kMicStream:
      return PermissionKind::kMicrophone;
    case RequestType::kMidiSysex:
      return PermissionKind::kMidiSysex;
    case RequestType::kMultipleDownloads:
      return PermissionKind::kMultipleDownloads;
    case RequestType::kNotifications:
      return PermissionKind::kNotifications;
    case RequestType::kKeyboardLock:
      return PermissionKind::kKeyboardLock;
    case RequestType::kPointerLock:
      return PermissionKind::kPointerLock;
    case RequestType::kRegisterProtocolHandler:
      return PermissionKind::kProtocolHandler;
    case RequestType::kSensors:
      return PermissionKind::kSensors;
    case RequestType::kStorageAccess:
      return PermissionKind::kStorageAccess;
    case RequestType::kVrSession:
      return PermissionKind::kVrSession;
    case RequestType::kWebAppInstallation:
      return PermissionKind::kWebAppInstallation;
    case RequestType::kWindowManagement:
      return PermissionKind::kWindowManagement;
  }
}

}  // namespace

// static
void PermissionPromptImpl::InstallFactory() {
  SetPermissionPromptFactoryForEmbedder(&PermissionPromptImpl::Create);
}

// static
std::unique_ptr<permissions::PermissionPrompt> PermissionPromptImpl::Create(
    content::WebContents* web_contents,
    Delegate* delegate) {
  return std::make_unique<PermissionPromptImpl>(web_contents, delegate);
}

PermissionPromptImpl::PermissionPromptImpl(content::WebContents* web_contents,
                                           Delegate* delegate)
    : delegate_(delegate->GetWeakPtr()) {
  if (PageImpl* page = PageImpl::FromWebContents(web_contents)) {
    page_ = page->GetWeakPtr();
  }
  constexpr UrlIdentity::TypeSet kAllowedTypes = {
      UrlIdentity::Type::kDefault, UrlIdentity::Type::kChromeExtension,
      UrlIdentity::Type::kIsolatedWebApp, UrlIdentity::Type::kFile};
  constexpr UrlIdentity::FormatOptions kOptions = {
      .default_options = {
          UrlIdentity::DefaultFormatOptions::kOmitCryptographicScheme}};
  const UrlIdentity identity = UrlIdentity::CreateFromUrl(
      Profile::FromBrowserContext(web_contents->GetBrowserContext()),
      delegate->GetRequestingOrigin(), kAllowedTypes, kOptions);
  request_.id = NextRequestID();
  request_.name_or_origin = base::UTF16ToUTF8(identity.name);
  request_.is_origin = identity.type == UrlIdentity::Type::kDefault ||
                       identity.type == UrlIdentity::Type::kFile;
  for (const auto& request : delegate->Requests()) {
    request_.kinds.push_back(ToKind(request->request_type()));
  }
  // As Arc's: shown from a task, once the request manager has taken the
  // prompt; a reply before that would be dropped.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&PermissionPromptImpl::Show, weak_factory_.GetWeakPtr()));
}

PermissionPromptImpl::~PermissionPromptImpl() {
  if (page_ && shown_) {
    page_->ClosePermissionRequest(request_);
  }
}

void PermissionPromptImpl::Show() {
  if (!page_) {
    // As Arc's when the page has no UI delegate.
    Reply(PermissionResponse::kDismiss);
    return;
  }
  shown_ = true;
  page_->RequestPermission(request_, [weak = weak_factory_.GetWeakPtr()](
                                         PermissionResponse response) {
    if (weak) {
      weak->Reply(response);
    }
  });
}

// Each call can delete this prompt.
void PermissionPromptImpl::Reply(PermissionResponse response) {
  if (!delegate_) {
    return;
  }
  switch (response) {
    case PermissionResponse::kAllow:
      delegate_->Accept(std::monostate());
      return;
    case PermissionResponse::kAllowThisTime:
      delegate_->AcceptThisTime(std::monostate());
      return;
    case PermissionResponse::kDeny:
      delegate_->Deny(std::monostate());
      return;
    case PermissionResponse::kDismiss:
      delegate_->Dismiss(std::monostate());
      return;
  }
}

// As Arc's prompt: Chromium need not ask it to move.
bool PermissionPromptImpl::UpdateAnchor() {
  return false;
}

// As Arc's: a tab switch takes the prompt down and asks again on return, so
// nothing counts as ignored.
permissions::PermissionPrompt::TabSwitchingBehavior
PermissionPromptImpl::GetTabSwitchingBehavior() {
  return kDestroyPromptButKeepRequestPending;
}

permissions::PermissionPromptDisposition
PermissionPromptImpl::GetPromptDisposition() const {
  return permissions::PermissionPromptDisposition::ANCHORED_BUBBLE;
}

bool PermissionPromptImpl::IsAskPrompt() const {
  return true;
}

std::optional<gfx::Rect> PermissionPromptImpl::GetViewBoundsInScreen() const {
  return std::nullopt;
}

std::vector<permissions::ElementAnchoredBubbleVariant>
PermissionPromptImpl::GetPromptVariants() const {
  return {};
}

std::optional<permissions::feature_params::PermissionElementPromptPosition>
PermissionPromptImpl::GetPromptPosition() const {
  return std::nullopt;
}

}  // namespace oa
