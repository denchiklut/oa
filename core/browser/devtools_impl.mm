#include "oa/browser/devtools_impl.h"

#import <AppKit/AppKit.h>

#include <utility>

#include "base/functional/bind.h"
#include "base/values.h"
#include "chrome/browser/devtools/devtools_toggle_action.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "content/public/browser/devtools_agent_host.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/page_impl.h"

namespace oa {
namespace {

// Oa's own, as ArcCore's is not traced: the frontend has no call for its
// shown panel, so it is read off the panel its main tab strip shows.
constexpr char16_t kCurrentPanelScript[] =
    uR"(document.querySelector('.main-tabbed-pane > .view-container .panel')
    ?.getAttribute('jslog')?.match(/context: ([^;]+)/)?.[1] ?? '')";

}  // namespace

DevToolsImpl::DevToolsImpl(PageImpl* page) : page_(page) {}

DevToolsImpl::~DevToolsImpl() = default;

void DevToolsImpl::Toggle(bool force_open, const DevToolsToggleAction& action) {
  if (!force_open && DevToolsWindow::GetInstanceForInspectedWebContents(
                         page_->web_contents())) {
    Close();
    return;
  }
  switch (action.type()) {
    case DevToolsToggleAction::kInspect:
    case DevToolsToggleAction::kShowElementsPanel:
      OpenPanel("elements", action);
      break;
    case DevToolsToggleAction::kShowConsolePanel:
      OpenPanel("console", action);
      break;
    case DevToolsToggleAction::kPauseInDebugger:
      OpenPanel("sources", action);
      break;
    default:
      OpenPanel(std::string(), action);
      break;
  }
}

// As ArcCore's Impl: the agent picks the element, and DevTools opens on
// Elements.
void DevToolsImpl::InspectElement(
    content::RenderFrameHost* inspected_frame_host,
    int x,
    int y) {
  scoped_refptr<content::DevToolsAgentHost> agent(
      content::DevToolsAgentHost::GetOrCreateForTab(page_->web_contents()));
  agent->InspectElement(inspected_frame_host, x, y);
  OpenPanel("elements", DevToolsToggleAction::ShowElementsPanel());
}

void DevToolsImpl::DockSideRequested(const std::string& dock_side) {
  DevToolsWindow* window =
      DevToolsWindow::GetInstanceForInspectedWebContents(page_->web_contents());
  if (!window) {
    return;
  }
  Observe(window->GetDevToolsWebContents());
  Display display;
  if (dock_side == "undocked") {
    display = Display::kUndocked;
  } else if (dock_side == "left") {
    display = Display::kLeft;
  } else if (dock_side == "right") {
    display = Display::kRight;
  } else if (dock_side == "bottom") {
    display = Display::kBottom;
  } else {
    return;
  }
  if (observer_) {
    observer_->OnDevToolsDisplay(display);
  }
}

void DevToolsImpl::NeedsFocus() {
  if (observer_) {
    observer_->OnDevToolsNeedsFocus();
  }
}

void DevToolsImpl::SetObserver(Observer* observer) {
  observer_ = observer;
}

void* DevToolsImpl::NativeView() const {
  if (!web_contents()) {
    return nullptr;
  }
  return (__bridge void*)web_contents()->GetNativeView().GetNativeNSView();
}

void DevToolsImpl::Open() {
  OpenPanel("elements", DevToolsToggleAction::Show());
}

void DevToolsImpl::OpenInspectView() {
  OpenPanel("elements", DevToolsToggleAction::Inspect());
}

void DevToolsImpl::OpenConsoleView() {
  OpenPanel("console", DevToolsToggleAction::ShowConsolePanel());
}

void DevToolsImpl::OpenNetworkView() {
  OpenPanel("network", DevToolsToggleAction::Show());
}

void DevToolsImpl::Close() {
  if (page_->web_contents()) {
    DevToolsWindow::CloseForEmbedder(page_->web_contents());
  }
}

void DevToolsImpl::Focus() {
  if (web_contents()) {
    web_contents()->Focus();
  }
}

void DevToolsImpl::CurrentPanel(PanelCallback callback) {
  if (!web_contents()) {
    callback(std::string());
    return;
  }
  web_contents()->GetPrimaryMainFrame()->ExecuteJavaScript(
      kCurrentPanelScript,
      base::BindOnce(
          [](PanelCallback callback, base::Value result) {
            callback(result.is_string() ? result.GetString() : std::string());
          },
          std::move(callback)));
}

void DevToolsImpl::WebContentsDestroyed() {
  Observe(nullptr);
  if (observer_) {
    observer_->OnDevToolsClosed();
  }
}

void DevToolsImpl::OpenPanel(const std::string& panel,
                             const DevToolsToggleAction& action) {
  if (page_->web_contents()) {
    DevToolsWindow::OpenForEmbedder(page_->web_contents(), panel, action);
  }
}

}  // namespace oa
