#ifndef OA_BROWSER_UI_JAVASCRIPT_DIALOG_IMPL_H_
#define OA_BROWSER_UI_JAVASCRIPT_DIALOG_IMPL_H_

#include <memory>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "components/javascript_dialogs/app_modal_dialog_controller.h"
#include "components/javascript_dialogs/app_modal_dialog_view.h"
#include "components/javascript_dialogs/tab_modal_dialog_view.h"
#include "content/public/browser/javascript_dialog_manager.h"
#include "oa/public/page.h"

namespace content {
class WebContents;
}

namespace oa {

class PageImpl;

// Makes Chrome's dialog managers build these views for every alert, confirm,
// prompt and beforeunload. Call after Chrome has installed its own factories.
void InstallJavaScriptDialogFactories();

// Chrome's TabModalDialogManager owns the policy; this view only carries the
// dialog to the page's observer and the reply back. Deletes itself.
class TabModalDialogImpl : public javascript_dialogs::TabModalDialogView {
 public:
  static base::WeakPtr<javascript_dialogs::TabModalDialogView> Create(
      content::WebContents* parent_web_contents,
      content::WebContents* alerting_web_contents,
      const std::u16string& title,
      content::JavaScriptDialogType dialog_type,
      const std::u16string& message_text,
      const std::u16string& default_prompt_text,
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
      base::OnceClosure dialog_closed_callback);

  TabModalDialogImpl(const TabModalDialogImpl&) = delete;
  TabModalDialogImpl& operator=(const TabModalDialogImpl&) = delete;
  ~TabModalDialogImpl() override;

  // javascript_dialogs::TabModalDialogView:
  void CloseDialogWithoutCallback() override;
  std::u16string GetUserInput() override;

 private:
  TabModalDialogImpl(
      base::WeakPtr<PageImpl> page,
      Dialog dialog,
      content::JavaScriptDialogManager::DialogClosedCallback dialog_callback);

  void Show();
  void Reply(bool accepted, const std::string& text, bool suppress);

  base::WeakPtr<PageImpl> page_;
  Dialog dialog_;
  content::JavaScriptDialogManager::DialogClosedCallback dialog_callback_;
  base::WeakPtrFactory<TabModalDialogImpl> weak_factory_{this};
};

// Chrome routes beforeunload through the app-modal queue. Deletes itself, as
// Chrome's views do.
class AppModalDialogImpl : public javascript_dialogs::AppModalDialogView {
 public:
  static javascript_dialogs::AppModalDialogView* Create(
      std::unique_ptr<javascript_dialogs::AppModalDialogController> controller);

  AppModalDialogImpl(const AppModalDialogImpl&) = delete;
  AppModalDialogImpl& operator=(const AppModalDialogImpl&) = delete;
  ~AppModalDialogImpl() override;

  // javascript_dialogs::AppModalDialogView:
  void ShowAppModalDialog() override;
  void ActivateAppModalDialog() override;
  void CloseAppModalDialog() override;
  void AcceptAppModalDialog() override;
  void CancelAppModalDialog() override;
  bool IsShowing() const override;

 private:
  explicit AppModalDialogImpl(
      std::unique_ptr<javascript_dialogs::AppModalDialogController> controller);

  void Reply(bool accepted, const std::string& text, bool suppress);

  std::unique_ptr<javascript_dialogs::AppModalDialogController> controller_;
  Dialog dialog_;
  bool showing_ = false;
  base::WeakPtrFactory<AppModalDialogImpl> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_UI_JAVASCRIPT_DIALOG_IMPL_H_
