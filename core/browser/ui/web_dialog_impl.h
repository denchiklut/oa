// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_WEB_DIALOG_IMPL_H_
#define OA_BROWSER_UI_WEB_DIALOG_IMPL_H_

#include <memory>

#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner_helpers.h"
#include "chrome/browser/ui/webui/constrained_web_dialog_ui.h"
#include "content/public/browser/web_contents_observer.h"
#include "oa/public/page.h"
#include "ui/web_dialogs/web_dialog_web_contents_delegate.h"

namespace oa {

class PageImpl;

// A WebUI dialog Chrome shows over a page, such as print preview, as
// ArcCore's constrained dialog delegate, made by //oa's
// ShowConstrainedWebDialog(): the page's observer shows the dialog's view. It
// owns itself and the dialog's WebContents, unless Chrome takes that back,
// until it closes. It observes the page it is over.
class WebDialogImpl : public ConstrainedWebDialogDelegate,
                      public ui::WebDialogWebContentsDelegate,
                      public content::WebContentsObserver {
 public:
  WebDialogImpl(const WebDialogImpl&) = delete;
  WebDialogImpl& operator=(const WebDialogImpl&) = delete;

  // ConstrainedWebDialogDelegate:
  const ui::WebDialogDelegate* GetWebDialogDelegate() const override;
  ui::WebDialogDelegate* GetWebDialogDelegate() override;
  void OnDialogCloseFromWebUI() override;
  std::unique_ptr<content::WebContents> ReleaseWebContents() override;
  content::WebContents* GetWebContents() override;
  gfx::NativeWindow GetNativeDialog() override;
  gfx::Size GetConstrainedWebDialogMinimumSize() const override;
  gfx::Size GetConstrainedWebDialogMaximumSize() const override;
  gfx::Size GetConstrainedWebDialogPreferredSize() const override;

  // ui::WebDialogWebContentsDelegate:
  void CloseContents(content::WebContents* source) override;
  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override;

  // content::WebContentsObserver:
  void WebContentsDestroyed() override;

 private:
  friend class base::DeleteHelper<WebDialogImpl>;
  friend ConstrainedWebDialogDelegate* ::ShowConstrainedWebDialog(
      content::BrowserContext* browser_context,
      std::unique_ptr<ui::WebDialogDelegate> delegate,
      content::WebContents* overshadowed);

  WebDialogImpl(content::BrowserContext* browser_context,
                std::unique_ptr<ui::WebDialogDelegate> delegate,
                content::WebContents* initiator);
  ~WebDialogImpl() override;

  void Show();
  void Close();

  std::unique_ptr<ui::WebDialogDelegate> delegate_;
  std::unique_ptr<content::WebContents> owned_contents_;
  base::WeakPtr<content::WebContents> contents_;
  base::WeakPtr<PageImpl> page_;
  WebDialog dialog_;
  bool closed_via_web_ui_ = false;
  bool closed_ = false;
};

}  // namespace oa

#endif  // OA_BROWSER_UI_WEB_DIALOG_IMPL_H_
