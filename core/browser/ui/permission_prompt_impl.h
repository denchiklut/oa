// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_PERMISSION_PROMPT_IMPL_H_
#define OA_BROWSER_UI_PERMISSION_PROMPT_IMPL_H_

#include <memory>
#include <optional>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "components/permissions/permission_prompt.h"
#include "oa/public/page.h"

namespace content {
class WebContents;
}

namespace oa {

class PageImpl;

// The prompt for every permission request a page makes, in place of Chrome's
// Views prompts, which need a BrowserView (ADR 0008 §4). As Arc's: it carries
// the request to the page's observer and the reply back, and reports its close
// when Chromium takes it down.
class PermissionPromptImpl : public permissions::PermissionPrompt {
 public:
  // Makes CreatePermissionPrompt() return a PermissionPromptImpl for every
  // request. Call before the browser starts.
  static void InstallFactory();

  PermissionPromptImpl(content::WebContents* web_contents, Delegate* delegate);
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

  void Show();
  void Reply(PermissionResponse response);

  base::WeakPtr<PageImpl> page_;
  base::WeakPtr<Delegate> delegate_;
  PermissionRequest request_;
  bool shown_ = false;
  base::WeakPtrFactory<PermissionPromptImpl> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_UI_PERMISSION_PROMPT_IMPL_H_
