// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/permission_prompt_impl.h"

#include <variant>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/permission_bubble/permission_prompt.h"

namespace oa {

// static
void PermissionPromptImpl::InstallFactory() {
  SetPermissionPromptFactoryForEmbedder(&PermissionPromptImpl::Create);
}

// static
std::unique_ptr<permissions::PermissionPrompt> PermissionPromptImpl::Create(
    content::WebContents* web_contents,
    Delegate* delegate) {
  return std::make_unique<PermissionPromptImpl>(delegate);
}

PermissionPromptImpl::PermissionPromptImpl(Delegate* delegate) {
  // Once the request manager has taken this prompt, as a prompt the user
  // closed without answering. That deletes the prompt.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<Delegate> delegate) {
                       if (delegate) {
                         delegate->Ignore(std::monostate());
                       }
                     },
                     delegate->GetWeakPtr()));
}

PermissionPromptImpl::~PermissionPromptImpl() = default;

bool PermissionPromptImpl::UpdateAnchor() {
  return true;
}

permissions::PermissionPrompt::TabSwitchingBehavior
PermissionPromptImpl::GetTabSwitchingBehavior() {
  return kDestroyPromptAndIgnoreRequest;
}

permissions::PermissionPromptDisposition
PermissionPromptImpl::GetPromptDisposition() const {
  return permissions::PermissionPromptDisposition::NONE_VISIBLE;
}

bool PermissionPromptImpl::IsAskPrompt() const {
  return false;
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
