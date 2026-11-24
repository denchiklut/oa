#ifndef OA_PUBLIC_DEVTOOLS_H_
#define OA_PUBLIC_DEVTOOLS_H_

#include <functional>
#include <string>

namespace oa {

// A page's DevTools, as ArcCore's ArcWebContentsDevTools: Chrome's own
// frontend, which the app shows beside the page or in a window of its own.
class DevTools {
 public:
  // The frontend's dock side, as ArcDevToolsDisplayStyle.
  enum class Display {
    kUndocked,
    kLeft,
    kRight,
    kBottom,
  };
  using PanelCallback = std::function<void(const std::string& panel)>;

  class Observer {
   public:
    // As the frontend opens and whenever its dock side changes.
    virtual void OnDevToolsDisplay(Display display) = 0;
    virtual void OnDevToolsClosed() = 0;
    // As ArcCore's webContentsDevToolsNeedsFocus:, when the frontend asks to
    // be brought forward.
    virtual void OnDevToolsNeedsFocus() = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~DevTools() = default;

  virtual void SetObserver(Observer* observer) = 0;
  // The frontend's NSView, from the first display until closed.
  virtual void* NativeView() const = 0;
  // Each opens the frontend on its panel, or shows the panel in the open one,
  // as ArcCore's do; the inspect view also turns on the element picker.
  virtual void Open() = 0;
  virtual void OpenInspectView() = 0;
  virtual void OpenConsoleView() = 0;
  virtual void OpenNetworkView() = 0;
  virtual void Close() = 0;
  // Gives the frontend the keyboard, once its view is in a window.
  virtual void Focus() = 0;
  // The shown panel's ID, as "console"; empty while closed.
  virtual void CurrentPanel(PanelCallback callback) = 0;
};

}  // namespace oa

#endif  // OA_PUBLIC_DEVTOOLS_H_
