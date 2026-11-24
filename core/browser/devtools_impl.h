#ifndef OA_BROWSER_DEVTOOLS_IMPL_H_
#define OA_BROWSER_DEVTOOLS_IMPL_H_

#include <string>

#include "base/memory/raw_ptr.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "content/public/browser/web_contents_observer.h"
#include "oa/public/devtools.h"

namespace oa {

class PageImpl;

// A page's DevTools, as ArcCore's arc::WebContents::DevTools::Impl, which
// Chrome's entry points for the page find on its WebContents. Owned by its
// page; observes the frontend's WebContents from its first display.
class DevToolsImpl : public DevTools,
                     public DevToolsWindow::Embedder,
                     public content::WebContentsObserver {
 public:
  explicit DevToolsImpl(PageImpl* page);
  DevToolsImpl(const DevToolsImpl&) = delete;
  DevToolsImpl& operator=(const DevToolsImpl&) = delete;
  ~DevToolsImpl() override;

  // DevToolsWindow::Embedder:
  void Toggle(bool force_open, const DevToolsToggleAction& action) override;
  void InspectElement(content::RenderFrameHost* inspected_frame_host,
                      int x,
                      int y) override;
  void DockSideRequested(const std::string& dock_side) override;
  void InspectModeChanged(const std::string& inspect_mode) override;
  void NeedsFocus() override;

  // DevTools:
  void SetObserver(Observer* observer) override;
  void* NativeView() const override;
  void Open() override;
  void OpenInspectView() override;
  void OpenConsoleView() override;
  void OpenNetworkView() override;
  void Close() override;
  void Focus() override;
  void CurrentPanel(PanelCallback callback) override;

  // content::WebContentsObserver:
  void WebContentsDestroyed() override;

 private:
  void OpenPanel(const std::string& panel, const DevToolsToggleAction& action);

  raw_ptr<PageImpl> page_;
  raw_ptr<Observer> observer_ = nullptr;
  bool picking_element_ = false;
};

}  // namespace oa

#endif  // OA_BROWSER_DEVTOOLS_IMPL_H_
