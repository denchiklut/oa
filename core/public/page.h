#ifndef OA_PUBLIC_PAGE_H_
#define OA_PUBLIC_PAGE_H_

#include <cstdint>
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

enum class SecurityLevel {
  kNeutral,
  kSecure,
  kWarning,
  kDangerous,
};

// How the page's last navigation ended, as Arc's navigation result: none from
// a navigation's start until its document loads or fails.
enum class NavigationResult {
  kNone,
  kLoaded,
  kFailed,
};

// How a page's renderer process ended, from base::TerminationStatus.
enum class RendererExit {
  kNormal,
  kAbnormal,
  kKilled,
  kCrashed,
  kStillRunning,
  kLaunchFailed,
  kOutOfMemory,
  kEvictedForMemory,
};

struct Dialog {
  enum class Kind {
    kAlert,
    kConfirm,
    kPrompt,
    kBeforeUnload,
  };
  uint64_t id = 0;
  Kind kind = Kind::kAlert;
  std::string title;
  std::string message;
  std::string default_text;
  bool is_reload = false;
  // From the page's seventh dialog on, as Arc offers it.
  bool offers_suppression = false;
};

class Page {
 public:
  // The NSImage lives only for the call; null if nothing could be copied.
  using SnapshotCallback = std::function<void(void* ns_image)>;
  // Call once. `suppress` answers this page's later dialogs without asking.
  using DialogReply = std::function<
      void(bool accepted, const std::string& text, bool suppress)>;

  class Observer {
   public:
    virtual void OnPageStateChanged() = 0;
    // The page opened another page, already a background tab in this page's
    // Browser. The observer owns it; destroying it drops it.
    virtual void OnPageOpenedPage(std::unique_ptr<Page> page,
                                  const std::string& target_url,
                                  OpenDisposition disposition) = 0;
    virtual void OnPageWantsActivation() = 0;
    // The app decides which exits show the page as crashed, as Arc's does.
    virtual void OnPageRendererGone(RendererExit exit) = 0;
    // Also after a reload of a page whose renderer was gone.
    virtual void OnPageRendererReady() = 0;
    // The reply is safe to call after the dialog was dismissed; it is ignored.
    virtual void OnPageDialog(const Dialog& dialog, DialogReply reply) = 0;
    // The engine closed the dialog: a navigation, a tab switch, a close.
    virtual void OnPageDialogDismissed(const Dialog& dialog) = 0;
    // A beforeunload handler kept the page after Close().
    virtual void OnPageCloseCancelled() = 0;
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
  // An NSImage, held by the tab while it keeps the icon; null until it has one.
  virtual void* Favicon() const = 0;
  virtual SecurityLevel GetSecurityLevel() const = 0;
  virtual NavigationResult GetNavigationResult() const = 0;

  virtual void Load(const std::string& url) = 0;
  virtual void GoBack() = 0;
  virtual void GoForward() = 0;
  virtual void Reload() = 0;
  virtual void Stop() = 0;
  virtual void Activate() = 0;
  // As a pinned tab: a link to another host opens a new page, reported
  // through the observer, instead of navigating this one.
  virtual void SetKeepsAddress(bool keeps_address) = 0;
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
