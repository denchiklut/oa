#ifndef OA_PUBLIC_PAGE_H_
#define OA_PUBLIC_PAGE_H_

#include <functional>
#include <memory>
#include <string>

namespace oa {

enum class OpenDisposition {
  kForegroundTab,
  kBackgroundTab,
  kNewWindow,
  kPopup,
};

class Page {
 public:
  // The NSImage lives only for the call; null if nothing could be copied.
  using SnapshotCallback = std::function<void(void* ns_image)>;

  class Observer {
   public:
    virtual void OnPageStateChanged() = 0;
    // The page opened another page, already a background tab in this page's
    // Browser. The observer owns it; destroying it drops it.
    virtual void OnPageOpenedPage(std::unique_ptr<Page> page,
                                  const std::string& target_url,
                                  OpenDisposition disposition) = 0;
    virtual void OnPageClosed() = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Page() = default;

  virtual void SetObserver(Observer* observer) = 0;
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
  // The same tab, WebContents and history move; nothing happens if it is there.
  virtual void MoveToWindow(const std::string& window_id) = 0;
  // Fails while the page has nothing drawn, for example when no window shows
  // it.
  virtual void Snapshot(SnapshotCallback callback) = 0;
  // Closes as the user would: unload handlers run and Chrome records the tab.
  virtual void Close() = 0;
  // Destroys the page without unload handlers or a closed-tab entry.
  virtual void Drop() = 0;
};

}  // namespace oa

#endif  // OA_PUBLIC_PAGE_H_
