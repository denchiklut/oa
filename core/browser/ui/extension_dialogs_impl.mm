// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/extension_dialogs_impl.h"

#import <AppKit/AppKit.h>

#include <memory>
#include <utility>

#include "base/auto_reset.h"
#include "base/functional/bind.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/extensions/extension_install_prompt.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/extensions/extension_uninstall_dialog.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/extensions/extension_install_ui.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/common/extension.h"
#include "oa/browser/image_handle.h"
#include "oa/browser/page_impl.h"
#include "oa/browser/window_browser.h"
#include "ui/gfx/image/image.h"

namespace oa {
namespace {

uint64_t NextRequestID() {
  static uint64_t last = 0;
  return ++last;
}

// Chrome's flows wait for an answer, so one always comes: the app's, or a
// decline when the app drops the request unanswered, as a closed page does.
Page::ExtensionReply MakeReply(base::OnceCallback<void(bool)> done) {
  struct Answer {
    explicit Answer(base::OnceCallback<void(bool)> done)
        : done(std::move(done)) {}
    ~Answer() { Run(false); }
    void Run(bool accepted) {
      if (done) {
        std::move(done).Run(accepted);
      }
    }
    base::OnceCallback<void(bool)> done;
  };
  auto answer = std::make_shared<Answer>(std::move(done));
  return [answer](bool accepted) { answer->Run(accepted); };
}

// As ArcCore's prompt: the page that asked, or the active page of the
// Browser the parent window has for the profile.
PageImpl* FindPage(content::WebContents* contents,
                   gfx::NativeWindow window,
                   Profile* profile) {
  PageImpl* page = contents ? PageImpl::FromWebContents(contents) : nullptr;
  return page ? page : WindowBrowser::ActivePage(window, profile);
}

void ShowInstallDialog(
    std::unique_ptr<ExtensionInstallPromptShowParams> show_params,
    ExtensionInstallPrompt::DoneCallback done,
    std::unique_ptr<extensions::InstallPromptData> prompt) {
  using Payload = ExtensionInstallPrompt::DoneCallbackPayload;
  using Result = ExtensionInstallPrompt::Result;
  PageImpl* page =
      FindPage(show_params->GetParentWebContents(),
               show_params->GetParentWindow(), show_params->profile());
  // Re-enable and permission prompts are declined until they have dialogs.
  if (!page || !prompt->extension() ||
      prompt->type() != extensions::InstallPromptData::INSTALL_PROMPT) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(std::move(done), Payload(Result::ABORTED)));
    return;
  }
  ExtensionRequest request;
  request.id = NextRequestID();
  request.kind = ExtensionRequest::Kind::kInstall;
  request.extension_id = prompt->extension()->id();
  request.name = prompt->extension()->name();
  for (size_t index = 0; index < prompt->GetPermissionCount(); ++index) {
    request.permissions.push_back(
        base::UTF16ToUTF8(prompt->GetPermission(index)));
  }
  if (!prompt->icon().IsEmpty()) {
    request.icon = ToImageHandle(prompt->icon().ToNSImage());
  }
  prompt->OnDialogOpened();
  page->RequestExtension(
      request,
      MakeReply(base::BindOnce(
          [](std::unique_ptr<extensions::InstallPromptData> prompt,
             std::unique_ptr<ExtensionInstallPromptShowParams> show_params,
             ExtensionInstallPrompt::DoneCallback done, bool accepted) {
            if (accepted) {
              prompt->OnDialogAccepted();
            } else {
              prompt->OnDialogCanceled();
            }
            std::move(done).Run(
                Payload(accepted ? Result::ACCEPTED : Result::USER_CANCELED));
          },
          std::move(prompt), std::move(show_params), std::move(done))));
}

class UninstallDialog : public extensions::ExtensionUninstallDialog {
 public:
  UninstallDialog(Profile* profile,
                  gfx::NativeWindow parent,
                  Delegate* delegate)
      : ExtensionUninstallDialog(profile, parent, delegate),
        profile_(profile->GetWeakPtr()) {}

 private:
  // extensions::ExtensionUninstallDialog:
  void Show() override {
    PageImpl* page =
        profile_ ? FindPage(nullptr, parent(), profile_.get()) : nullptr;
    if (!page) {
      Finish(false);
      return;
    }
    page_ = page->GetWeakPtr();
    request_.id = NextRequestID();
    request_.kind = ExtensionRequest::Kind::kUninstall;
    request_.extension_id = extension()->id();
    request_.name = extension()->name();
    page->RequestExtension(
        request_, MakeReply(base::BindOnce(&UninstallDialog::Finish,
                                           weak_factory_.GetWeakPtr())));
  }
  void Close() override {
    if (page_ && !finished_) {
      page_->CloseExtensionRequest(request_);
    }
    Finish(false);
  }

  // Deletes this: the dialog's owner drops it once it has closed.
  void Finish(bool accepted) {
    if (finished_) {
      return;
    }
    finished_ = true;
    OnDialogClosed(accepted ? CLOSE_ACTION_UNINSTALL : CLOSE_ACTION_CANCELED);
  }

  base::WeakPtr<Profile> profile_;
  base::WeakPtr<PageImpl> page_;
  ExtensionRequest request_;
  bool finished_ = false;
  base::WeakPtrFactory<UninstallDialog> weak_factory_{this};
};

std::unique_ptr<extensions::ExtensionUninstallDialog> CreateUninstallDialog(
    Profile* profile,
    gfx::NativeWindow parent,
    extensions::ExtensionUninstallDialog::Delegate* delegate) {
  return std::make_unique<UninstallDialog>(profile, parent, delegate);
}

}  // namespace

void InstallExtensionDialogs() {
  ExtensionInstallPrompt::SetShowDialogForEmbedder(&ShowInstallDialog);
  extensions::ExtensionUninstallDialog::SetFactoryForEmbedder(
      &CreateUninstallDialog);
  // As Arc, nothing shows once an install ends. Chrome's bubble and its error
  // dialog are views anchored to its toolbar; this is the switch its tests
  // use, which needs no patch.
  static base::NoDestructor<base::AutoReset<bool>> no_install_ui(
      ExtensionInstallUI::disable_ui_for_tests(true));
}

}  // namespace oa
