// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/web_dialog_impl.h"

#import <AppKit/AppKit.h>

#include <string>
#include <utility>

#include "base/functional/bind.h"
#include "base/location.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/renderer_preferences_util.h"
#include "chrome/browser/ui/webui/chrome_web_contents_handler.h"
#include "components/guest_view/browser/guest_view_base.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_delegate.h"
#include "content/public/common/referrer.h"
#include "oa/browser/page_impl.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/common/renderer_preferences/renderer_preferences.h"
#include "ui/base/page_transition_types.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "ui/web_dialogs/web_dialog_delegate.h"

namespace oa {

namespace {

uint64_t NextWebDialogID() {
  static uint64_t last = 0;
  return ++last;
}

}  // namespace

// static
void WebDialogImpl::InstallFactory() {
  SetConstrainedWebDialogFactoryForEmbedder(&WebDialogImpl::Create);
}

// static
ConstrainedWebDialogDelegate* WebDialogImpl::Create(
    content::BrowserContext* browser_context,
    std::unique_ptr<ui::WebDialogDelegate> delegate,
    content::WebContents* initiator,
    const gfx::Size& min_size,
    const gfx::Size& max_size) {
  auto* dialog = new WebDialogImpl(browser_context, std::move(delegate),
                                   initiator, min_size, max_size);
  dialog->Show();
  return dialog;
}

// As Chrome's Views dialog, without its widget: the same WebContents setup,
// and the WebUI finds this through its user data.
WebDialogImpl::WebDialogImpl(content::BrowserContext* browser_context,
                             std::unique_ptr<ui::WebDialogDelegate> delegate,
                             content::WebContents* initiator,
                             const gfx::Size& min_size,
                             const gfx::Size& max_size)
    : ui::WebDialogWebContentsDelegate(
          browser_context,
          std::make_unique<ChromeWebContentsHandler>()),
      content::WebContentsObserver(
          guest_view::GuestViewBase::GetTopLevelWebContents(initiator)),
      delegate_(std::move(delegate)),
      min_size_(min_size),
      max_size_(max_size) {
  if (PageImpl* page = PageImpl::FromWebContents(web_contents())) {
    page_ = page->GetWeakPtr();
  }
  owned_contents_ = content::WebContents::Create(
      content::WebContents::CreateParams(browser_context));
  contents_ = owned_contents_->GetWeakPtr();
  zoom::ZoomController::CreateForWebContents(contents_.get());
  contents_->SetDelegate(this);
  renderer_preferences_util::UpdateFromSystemSettings(
      contents_->GetMutableRendererPrefs(),
      Profile::FromBrowserContext(browser_context));
  contents_->SyncRendererPrefs();
  ConstrainedWebDialogUI::SetConstrainedDelegate(contents_.get(), this);
  contents_->GetController().LoadURL(
      delegate_->GetDialogContentURL(), content::Referrer(),
      ui::PAGE_TRANSITION_AUTO_TOPLEVEL, std::string());
}

WebDialogImpl::~WebDialogImpl() {
  if (contents_) {
    ConstrainedWebDialogUI::ClearConstrainedDelegate(contents_.get());
  }
}

void WebDialogImpl::Show() {
  dialog_.id = NextWebDialogID();
  dialog_.title = base::UTF16ToUTF8(delegate_->GetDialogTitle());
  dialog_.accessible_title =
      base::UTF16ToUTF8(delegate_->GetAccessibleDialogTitle());
  const gfx::Size preferred = GetConstrainedWebDialogPreferredSize();
  dialog_.preferred_width = preferred.width();
  dialog_.preferred_height = preferred.height();
  const gfx::Size minimum = GetConstrainedWebDialogMinimumSize();
  dialog_.minimum_width = minimum.width();
  dialog_.minimum_height = minimum.height();
  NSView* view = contents_->GetNativeView().GetNativeNSView();
  if (!page_ || !page_->NotifyWebDialog(dialog_, (__bridge void*)view)) {
    // No app window to show it in: it closes as if cancelled, once Chrome has
    // taken it.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(&WebDialogImpl::Close, weak_factory_.GetWeakPtr()));
    return;
  }
  // As the Views dialog's initially focused view.
  contents_->Focus();
}

// As the Views dialog's widget closing: the delegate hears of a close the
// WebUI didn't make, and the dialog goes once the WebUI's message returns.
void WebDialogImpl::Close() {
  if (closed_) {
    return;
  }
  closed_ = true;
  if (!closed_via_web_ui_) {
    delegate_->OnDialogClosed(std::string());
  }
  if (page_) {
    page_->NotifyWebDialogClosed(dialog_);
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->DeleteSoon(FROM_HERE,
                                                                this);
}

const ui::WebDialogDelegate* WebDialogImpl::GetWebDialogDelegate() const {
  return delegate_.get();
}

ui::WebDialogDelegate* WebDialogImpl::GetWebDialogDelegate() {
  return delegate_.get();
}

void WebDialogImpl::OnDialogCloseFromWebUI() {
  closed_via_web_ui_ = true;
  Close();
}

std::unique_ptr<content::WebContents> WebDialogImpl::ReleaseWebContents() {
  return std::move(owned_contents_);
}

content::WebContents* WebDialogImpl::GetWebContents() {
  return contents_.get();
}

gfx::NativeWindow WebDialogImpl::GetNativeDialog() {
  return contents_ ? contents_->GetTopLevelNativeWindow() : gfx::NativeWindow();
}

gfx::Size WebDialogImpl::GetConstrainedWebDialogMinimumSize() const {
  gfx::Size size = min_size_;
  if (size.IsEmpty()) {
    delegate_->GetMinimumDialogSize(&size);
  }
  return size;
}

gfx::Size WebDialogImpl::GetConstrainedWebDialogMaximumSize() const {
  return max_size_;
}

// Oa's own for an auto-resizing dialog: it keeps the size it opened at,
// within its bounds. Only Chrome's sign-in confirmation asks for one.
gfx::Size WebDialogImpl::GetConstrainedWebDialogPreferredSize() const {
  if (closed_) {
    return gfx::Size();
  }
  gfx::Size size;
  delegate_->GetDialogSize(&size);
  if (!max_size_.IsEmpty()) {
    size.SetToMax(min_size_);
    size.SetToMin(max_size_);
  }
  return size;
}

void WebDialogImpl::CloseContents(content::WebContents* source) {
  Close();
}

// As Chrome's Views dialog: Escape the dialog's page leaves closes it, and
// other keys go to the page it is over, as its window's shortcuts.
bool WebDialogImpl::HandleKeyboardEvent(
    content::WebContents* source,
    const input::NativeWebKeyboardEvent& event) {
  if (event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
      event.windows_key_code == ui::VKEY_ESCAPE &&
      !(event.GetModifiers() & blink::WebInputEvent::kKeyModifiers)) {
    delegate_->OnDialogClosingFromKeyEvent();
    Close();
    return true;
  }
  content::WebContents* initiator = web_contents();
  if (!initiator || !initiator->GetDelegate()) {
    return false;
  }
  return initiator->GetDelegate()->HandleKeyboardEvent(initiator, event);
}

void WebDialogImpl::WebContentsDestroyed() {
  Close();
}

}  // namespace oa
