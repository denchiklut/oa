#include "oa/browser/ui/javascript_dialog_impl.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/ui/javascript_dialogs/javascript_tab_modal_dialog_manager_delegate_desktop.h"
#include "components/javascript_dialogs/app_modal_dialog_manager.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "oa/browser/page_impl.h"

namespace oa {

namespace {

uint64_t NextDialogID() {
  static uint64_t last = 0;
  return ++last;
}

Dialog::Kind ToKind(content::JavaScriptDialogType type) {
  switch (type) {
    case content::JAVASCRIPT_DIALOG_TYPE_CONFIRM:
      return Dialog::Kind::kConfirm;
    case content::JAVASCRIPT_DIALOG_TYPE_PROMPT:
      return Dialog::Kind::kPrompt;
    default:
      return Dialog::Kind::kAlert;
  }
}

}  // namespace

void InstallJavaScriptDialogFactories() {
  JavaScriptTabModalDialogManagerDelegateDesktop::SetViewFactoryForEmbedder(
      &TabModalDialogImpl::Create);
  javascript_dialogs::AppModalDialogManager::GetInstance()
      ->SetNativeDialogFactory(
          base::BindRepeating(&AppModalDialogImpl::Create));
}

// static
base::WeakPtr<javascript_dialogs::TabModalDialogView>
TabModalDialogImpl::Create(
    content::WebContents* parent_web_contents,
    content::WebContents* alerting_web_contents,
    const std::u16string& title,
    content::JavaScriptDialogType dialog_type,
    const std::u16string& message_text,
    const std::u16string& default_prompt_text,
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback,
    base::OnceClosure dialog_closed_callback) {
  Dialog dialog;
  dialog.id = NextDialogID();
  dialog.kind = ToKind(dialog_type);
  dialog.title = base::UTF16ToUTF8(title);
  dialog.message = base::UTF16ToUTF8(message_text);
  dialog.default_text = base::UTF16ToUTF8(default_prompt_text);
  PageImpl* page = PageImpl::FromWebContents(parent_web_contents);
  auto* view =
      new TabModalDialogImpl(page ? page->GetWeakPtr() : nullptr,
                             std::move(dialog), std::move(dialog_callback));
  return view->weak_factory_.GetWeakPtr();
}

TabModalDialogImpl::TabModalDialogImpl(
    base::WeakPtr<PageImpl> page,
    Dialog dialog,
    content::JavaScriptDialogManager::DialogClosedCallback dialog_callback)
    : page_(std::move(page)),
      dialog_(std::move(dialog)),
      dialog_callback_(std::move(dialog_callback)) {
  // The manager stores the view after Create() returns; a reply before that
  // would be dropped.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&TabModalDialogImpl::Show, weak_factory_.GetWeakPtr()));
}

TabModalDialogImpl::~TabModalDialogImpl() = default;

void TabModalDialogImpl::Show() {
  if (!page_) {
    Reply(false, std::string(), false);
    return;
  }
  page_->RunDialog(dialog_,
                   [weak = weak_factory_.GetWeakPtr()](
                       bool accepted, const std::string& text, bool suppress) {
                     if (weak) {
                       weak->Reply(accepted, text, suppress);
                     }
                   });
}

void TabModalDialogImpl::Reply(bool accepted,
                               const std::string& text,
                               bool suppress) {
  std::move(dialog_callback_).Run(accepted, base::UTF8ToUTF16(text));
  delete this;
}

void TabModalDialogImpl::CloseDialogWithoutCallback() {
  if (page_) {
    page_->DismissDialog(dialog_);
  }
  delete this;
}

std::u16string TabModalDialogImpl::GetUserInput() {
  return base::UTF8ToUTF16(dialog_.default_text);
}

// static
javascript_dialogs::AppModalDialogView* AppModalDialogImpl::Create(
    std::unique_ptr<javascript_dialogs::AppModalDialogController> controller) {
  content::WebContents* web_contents = controller->web_contents();
  auto* view = new AppModalDialogImpl(std::move(controller));
  // As Chrome's views: the asking tab comes forward when the dialog is made.
  if (web_contents && web_contents->GetDelegate()) {
    web_contents->GetDelegate()->ActivateContents(web_contents);
  }
  return view;
}

AppModalDialogImpl::AppModalDialogImpl(
    std::unique_ptr<javascript_dialogs::AppModalDialogController> controller)
    : controller_(std::move(controller)) {
  dialog_.id = NextDialogID();
  dialog_.kind = controller_->is_before_unload_dialog()
                     ? Dialog::Kind::kBeforeUnload
                     : ToKind(controller_->javascript_dialog_type());
  dialog_.title = base::UTF16ToUTF8(controller_->title());
  dialog_.message = base::UTF16ToUTF8(controller_->message_text());
  dialog_.default_text = base::UTF16ToUTF8(controller_->default_prompt_text());
  dialog_.is_reload = controller_->is_reload();
}

AppModalDialogImpl::~AppModalDialogImpl() = default;

void AppModalDialogImpl::ShowAppModalDialog() {
  showing_ = true;
  PageImpl* page = PageImpl::FromWebContents(controller_->web_contents());
  if (!page) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&AppModalDialogImpl::Reply, weak_factory_.GetWeakPtr(),
                       false, std::string(), false));
    return;
  }
  page->RunDialog(dialog_,
                  [weak = weak_factory_.GetWeakPtr()](
                      bool accepted, const std::string& text, bool suppress) {
                    if (weak) {
                      weak->Reply(accepted, text, suppress);
                    }
                  });
}

void AppModalDialogImpl::Reply(bool accepted,
                               const std::string& text,
                               bool suppress) {
  showing_ = false;
  if (accepted) {
    controller_->OnAccept(base::UTF8ToUTF16(text), suppress);
  } else {
    controller_->OnCancel(suppress);
  }
  delete this;
}

void AppModalDialogImpl::ActivateAppModalDialog() {}

void AppModalDialogImpl::CloseAppModalDialog() {
  if (PageImpl* page = PageImpl::FromWebContents(controller_->web_contents());
      page && showing_) {
    page->DismissDialog(dialog_);
  }
  showing_ = false;
  controller_->OnClose();
  delete this;
}

void AppModalDialogImpl::AcceptAppModalDialog() {
  if (PageImpl* page = PageImpl::FromWebContents(controller_->web_contents());
      page && showing_) {
    page->DismissDialog(dialog_);
  }
  Reply(true, dialog_.default_text, false);
}

void AppModalDialogImpl::CancelAppModalDialog() {
  if (PageImpl* page = PageImpl::FromWebContents(controller_->web_contents());
      page && showing_) {
    page->DismissDialog(dialog_);
  }
  Reply(false, std::string(), false);
}

bool AppModalDialogImpl::IsShowing() const {
  return showing_;
}

}  // namespace oa
