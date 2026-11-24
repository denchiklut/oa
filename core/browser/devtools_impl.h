#ifndef OA_BROWSER_DEVTOOLS_IMPL_H_
#define OA_BROWSER_DEVTOOLS_IMPL_H_

#include <string>

#include "base/memory/raw_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "oa/public/devtools.h"

struct DevToolsToggleAction;

namespace oa {

class PageImpl;

// A page's DevTools, as ArcCore's arc::WebContents::DevTools::Impl. Owned by
// its page; observes the frontend's WebContents from its first display.
class DevToolsImpl : public DevTools, public content::WebContentsObserver {
 public:
  // Before the browser starts.
  static void InstallEmbedder();

  explicit DevToolsImpl(PageImpl* page);
  DevToolsImpl(const DevToolsImpl&) = delete;
  DevToolsImpl& operator=(const DevToolsImpl&) = delete;
  ~DevToolsImpl() override;

  // As ArcCore's Impl::Toggle, for Chrome's own entry points, as the page
  // menu's Inspect.
  void Toggle(bool force_open, const DevToolsToggleAction& action);
  void DockSideRequested(const std::string& dock_side);

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
};

}  // namespace oa

#endif  // OA_BROWSER_DEVTOOLS_IMPL_H_
