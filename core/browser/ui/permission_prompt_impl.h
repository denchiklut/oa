// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_PERMISSION_PROMPT_IMPL_H_
#define OA_BROWSER_UI_PERMISSION_PROMPT_IMPL_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "components/permissions/permission_prompt.h"

namespace content {
class WebContents;
}

namespace oa {

// The prompt for every permission request a page makes, in place of Chrome's
// Views prompts, which need a BrowserView (ADR 0008 §4).
//
// Until the app draws permission prompts (C6), it shows nothing and ignores
// the request: the page's request fails, and nothing is saved for the site.
class PermissionPromptImpl : public permissions::PermissionPrompt {
 public:
  // Makes CreatePermissionPrompt() return a PermissionPromptImpl for every
  // request. Call before the browser starts.
  static void InstallFactory();

  explicit PermissionPromptImpl(Delegate* delegate);
  PermissionPromptImpl(const PermissionPromptImpl&) = delete;
  PermissionPromptImpl& operator=(const PermissionPromptImpl&) = delete;
  ~PermissionPromptImpl() override;

  // permissions::PermissionPrompt:
  bool UpdateAnchor() override;
  TabSwitchingBehavior GetTabSwitchingBehavior() override;
  permissions::PermissionPromptDisposition GetPromptDisposition()
      const override;
  bool IsAskPrompt() const override;
  std::optional<gfx::Rect> GetViewBoundsInScreen() const override;
  std::vector<permissions::ElementAnchoredBubbleVariant> GetPromptVariants()
      const override;
  std::optional<permissions::feature_params::PermissionElementPromptPosition>
  GetPromptPosition() const override;

 private:
  static std::unique_ptr<permissions::PermissionPrompt> Create(
      content::WebContents* web_contents,
      Delegate* delegate);
};

}  // namespace oa

#endif  // OA_BROWSER_UI_PERMISSION_PROMPT_IMPL_H_
