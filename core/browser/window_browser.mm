#include "oa/browser/window_browser.h"

#import <AppKit/AppKit.h>

#include <utility>
#include <vector>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/tab_list/tab_removed_reason.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/create_browser_window.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/page_impl.h"
#include "oa/browser/ui/browser_window_impl.h"
#include "ui/base/window_open_disposition.h"

namespace oa {
namespace {

std::vector<WindowBrowser*>& AllWindowBrowsers() {
  static base::NoDestructor<std::vector<WindowBrowser*>> all;
  return *all;
}

NSMapTable<NSString*, NSWindow*>* AttachedWindows() {
  static NSMapTable<NSString*, NSWindow*>* windows =
      [NSMapTable strongToWeakObjectsMapTable];
  return windows;
}

std::vector<base::WeakPtr<WindowBrowser>> OpenWindowBrowsers(
    const std::string* window_id) {
  std::vector<base::WeakPtr<WindowBrowser>> result;
  for (WindowBrowser* window_browser : AllWindowBrowsers()) {
    if (!window_id || window_browser->window_id() == *window_id) {
      result.push_back(window_browser->GetWeakPtr());
    }
  }
  return result;
}

void AskPagesToLeave(std::vector<base::WeakPtr<PageImpl>> pages,
                     size_t index,
                     std::function<void(bool leave)> completion) {
  while (index < pages.size() && !pages[index]) {
    ++index;
  }
  if (index == pages.size()) {
    completion(true);
    return;
  }
  PageImpl* page = pages[index].get();
  page->AskToLeave([pages = std::move(pages), index,
                    completion = std::move(completion)](bool leave) mutable {
    if (!leave) {
      completion(false);
      return;
    }
    AskPagesToLeave(std::move(pages), index + 1, std::move(completion));
  });
}

void RemoveAllTabs(base::WeakPtr<WindowBrowser> window_browser) {
  while (window_browser) {
    TabStripModel* model = window_browser->browser()->GetTabStripModel();
    if (model->empty()) {
      return;
    }
    const int count = model->count();
    content::WebContents* contents = model->GetWebContentsAt(count - 1);
    if (PageImpl* page = PageImpl::FromWebContents(contents)) {
      page->Drop();
    }
    if (window_browser && model->count() == count) {
      model->DetachAndDeleteWebContentsAt(count - 1);
    }
  }
}

}  // namespace

// static
WindowBrowser* WindowBrowser::Find(const std::string& window_id,
                                   Profile* profile) {
  for (WindowBrowser* window_browser : AllWindowBrowsers()) {
    if (!window_browser->closing_ && window_browser->window_id_ == window_id &&
        window_browser->browser_->GetProfile() == profile) {
      return window_browser;
    }
  }
  return nullptr;
}

// static
WindowBrowser* WindowBrowser::GetOrCreate(const std::string& window_id,
                                          Profile* profile) {
  if (WindowBrowser* window_browser = Find(window_id, profile)) {
    return window_browser;
  }
  if (GetBrowserWindowCreationStatusForProfile(*profile) !=
      BrowserWindowInterface::CreationStatus::kOk) {
    LOG(ERROR) << "oa: can't create a Browser for this profile now";
    return nullptr;
  }
  BrowserWindowInterface* browser = CreateBrowserWindow(
      BrowserWindowCreateParams(BrowserWindowInterface::TYPE_NORMAL, *profile,
                                /*from_user_gesture=*/false));
  BrowserWindowImpl* window = BrowserWindowImpl::FromBrowser(browser);
  CHECK(window) << "BrowserWindowImpl::InstallFactory() wasn't called";
  window->window_browser()->window_id_ = window_id;
  return window->window_browser();
}

// static
void WindowBrowser::AttachWindow(const std::string& window_id,
                                 void* ns_window) {
  NSString* key = base::SysUTF8ToNSString(window_id);
  if (![AttachedWindows() objectForKey:key]) {
    [AttachedWindows() setObject:(__bridge NSWindow*)ns_window forKey:key];
  }
}

// static
void WindowBrowser::CloseWindow(const std::string& window_id) {
  [AttachedWindows() removeObjectForKey:base::SysUTF8ToNSString(window_id)];
  for (base::WeakPtr<WindowBrowser>& window_browser :
       OpenWindowBrowsers(&window_id)) {
    RemoveAllTabs(window_browser);
  }
}

// static
void WindowBrowser::AskToLeave(const std::string& window_id,
                               std::function<void(bool leave)> completion) {
  std::vector<base::WeakPtr<PageImpl>> pages;
  for (base::WeakPtr<WindowBrowser>& window_browser :
       OpenWindowBrowsers(&window_id)) {
    TabStripModel* model = window_browser->browser()->GetTabStripModel();
    for (int index = 0; index < model->count(); ++index) {
      if (PageImpl* page =
              PageImpl::FromWebContents(model->GetWebContentsAt(index))) {
        pages.push_back(page->GetWeakPtr());
      }
    }
  }
  AskPagesToLeave(std::move(pages), 0, std::move(completion));
}

// static
void WindowBrowser::CloseAll() {
  for (base::WeakPtr<WindowBrowser>& window_browser :
       OpenWindowBrowsers(nullptr)) {
    RemoveAllTabs(window_browser);
  }
}

WindowBrowser::WindowBrowser(BrowserWindowInterface* browser)
    : browser_(browser) {
  browser_->GetTabStripModel()->AddObserver(this);
  AllWindowBrowsers().push_back(this);
}

WindowBrowser::~WindowBrowser() {
  std::erase(AllWindowBrowsers(), this);
  browser_->GetTabStripModel()->RemoveObserver(this);
}

gfx::NativeWindow WindowBrowser::GetNativeWindow() const {
  if (window_id_.empty()) {
    return gfx::NativeWindow();
  }
  return gfx::NativeWindow(
      [AttachedWindows() objectForKey:base::SysUTF8ToNSString(window_id_)]);
}

bool WindowBrowser::Insert(std::unique_ptr<content::WebContents> contents) {
  if (closing_) {
    return false;
  }
  NavigateParams params(browser_, std::move(contents));
  params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
  params.user_gesture = false;
  Navigate(&params);
  return params.navigated_or_inserted_contents != nullptr;
}

std::unique_ptr<tabs::TabModel> WindowBrowser::Detach(
    content::WebContents* contents) {
  TabStripModel* model = browser_->GetTabStripModel();
  const int index = model->GetIndexOfWebContents(contents);
  if (index == TabStripModel::kNoTab) {
    return nullptr;
  }
  return model->DetachTabAtForInsertion(index);
}

bool WindowBrowser::InsertDetached(std::unique_ptr<tabs::TabModel> tab) {
  if (closing_) {
    return false;
  }
  TabStripModel* model = browser_->GetTabStripModel();
  model->InsertDetachedTabAt(
      model->count(), std::move(tab),
      model->empty() ? AddTabTypes::ADD_ACTIVE : AddTabTypes::ADD_NONE);
  return true;
}

void WindowBrowser::Activate(content::WebContents* contents) {
  TabStripModel* model = browser_->GetTabStripModel();
  const int index = model->GetIndexOfWebContents(contents);
  if (index == TabStripModel::kNoTab || index == model->active_index()) {
    return;
  }
  base::AutoReset<bool> guard(&activating_, true);
  model->ActivateTabAt(index);
}

bool WindowBrowser::Close(content::WebContents* contents) {
  TabStripModel* model = browser_->GetTabStripModel();
  const int index = model->GetIndexOfWebContents(contents);
  if (index == TabStripModel::kNoTab) {
    return false;
  }
  model->CloseWebContentsAt(index,
                            TabCloseTypes::CLOSE_USER_GESTURE |
                                TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
  return true;
}

void WindowBrowser::Remove(content::WebContents* contents) {
  TabStripModel* model = browser_->GetTabStripModel();
  const int index = model->GetIndexOfWebContents(contents);
  if (index != TabStripModel::kNoTab) {
    model->DetachAndDeleteWebContentsAt(index);
  }
}

void WindowBrowser::OnWindowClosing() {
  closing_ = true;
}

void WindowBrowser::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  switch (change.type()) {
    case TabStripModelChange::kReplaced: {
      const TabStripModelChange::Replace* replace = change.GetReplace();
      if (PageImpl* page = PageImpl::FromWebContents(replace->old_contents)) {
        page->Rebind(replace->new_contents);
      }
      break;
    }
    case TabStripModelChange::kRemoved:
      for (const TabStripModelChange::RemovedTab& removed :
           change.GetRemove()->contents) {
        if (!TabRemoveReasonUtils::WillDeleteWebContents(
                removed.remove_reason)) {
          continue;
        }
        if (PageImpl* page = PageImpl::FromWebContents(removed.contents)) {
          page->OnRemovedFromStrip(removed.session_id);
        }
      }
      break;
    case TabStripModelChange::kSelectionOnly:
    case TabStripModelChange::kInserted:
    case TabStripModelChange::kMoved:
      break;
  }
}

}  // namespace oa
