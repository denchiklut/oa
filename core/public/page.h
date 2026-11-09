#ifndef OA_PUBLIC_PAGE_H_
#define OA_PUBLIC_PAGE_H_

#include <functional>
#include <string>

namespace oa {

class Page {
 public:
  // Receives the page's last frame as an NSImage, or null if none could be
  // copied. The image lives only for the call.
  using SnapshotCallback = std::function<void(void* ns_image)>;

  class Observer {
   public:
    virtual void OnPageStateChanged() = 0;
    virtual void OnPageClosed() = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Page() = default;

  virtual void* NativeView() const = 0;
  virtual std::string VisibleURL() const = 0;
  virtual std::string Title() const = 0;
  virtual bool IsLoading() const = 0;
  virtual double LoadProgress() const = 0;
  virtual bool CanGoBack() const = 0;
  virtual bool CanGoForward() const = 0;

  virtual void Load(const std::string& url) = 0;
  virtual void GoBack() = 0;
  virtual void GoForward() = 0;
  virtual void Reload() = 0;
  virtual void Stop() = 0;
  virtual void Activate() = 0;
  // Moves the page into the Browser of the app's window `window_id`, keeping
  // its WebContents, history and session ID. Nothing happens if it is there.
  virtual void MoveToWindow(const std::string& window_id) = 0;
  // Copies the page's last frame, for the window it left. Fails while the
  // page has nothing drawn, for example when no window shows it.
  virtual void Snapshot(SnapshotCallback callback) = 0;
  // Closes as the user would: unload handlers run and Chrome records the tab.
  virtual void Close() = 0;
  // Destroys the page without unload handlers or a closed-tab entry.
  virtual void Drop() = 0;
};

}  // namespace oa

#endif  // OA_PUBLIC_PAGE_H_
