#ifndef OA_PUBLIC_PAGE_H_
#define OA_PUBLIC_PAGE_H_

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

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

// Chromium's permissions::RequestType on macOS, as ADK's request types mirror
// it.
enum class PermissionKind {
  kAmbientLogin,
  kArSession,
  kCameraPanTiltZoom,
  kCamera,
  kCapturedSurfaceControl,
  kClipboard,
  kTopLevelStorageAccess,
  kDiskQuota,
  kFileSystemAccess,
  kGeolocation,
  kHandTracking,
  kIdentityProvider,
  kIdleDetection,
  kLocalFonts,
  kLocalNetwork,
  kLoopbackNetwork,
  kMicrophone,
  kMidiSysex,
  kMultipleDownloads,
  kNotifications,
  kKeyboardLock,
  kPointerLock,
  kProtocolHandler,
  kSensors,
  kStorageAccess,
  kVrSession,
  kWebAppInstallation,
  kWindowManagement,
};

// What Chromium's request manager shows at once: one site, one or more kinds
// merged, as camera and microphone are.
struct PermissionRequest {
  uint64_t id = 0;
  // The host as Chromium's prompts show it, or an extension's name.
  std::string name_or_origin;
  bool is_origin = true;
  std::vector<PermissionKind> kinds;
};

enum class PermissionResponse {
  kAllow,
  kAllowThisTime,
  kDeny,
  kDismiss,
};

class Page {
 public:
  // The NSImage lives only for the call; null if nothing could be copied.
  using SnapshotCallback = std::function<void(void* ns_image)>;
  // Call once. `suppress` answers this page's later dialogs without asking.
  using DialogReply = std::function<
      void(bool accepted, const std::string& text, bool suppress)>;
  // Call once; ignored after the request was closed.
  using PermissionReply = std::function<void(PermissionResponse response)>;

  class Observer {
   public:
    virtual void OnPageStateChanged() = 0;
    // The page opened another page, already a background tab in this page's
    // Browser. The observer owns it; destroying it drops it. `by_page` tells
    // the page's own open, as a link or window.open, from one the browser
    // made for the user, as the context menu's are.
    virtual void OnPageOpenedPage(std::unique_ptr<Page> page,
                                  const std::string& target_url,
                                  OpenDisposition disposition,
                                  bool by_page) = 0;
    virtual void OnPageWantsActivation() = 0;
    // The app decides which exits show the page as crashed, as Arc's does.
    virtual void OnPageRendererGone(RendererExit exit) = 0;
    // Also after a reload of a page whose renderer was gone.
    virtual void OnPageRendererReady() = 0;
    // The reply is safe to call after the dialog was dismissed; it is ignored.
    virtual void OnPageDialog(const Dialog& dialog, DialogReply reply) = 0;
    // The engine closed the dialog: a navigation, a tab switch, a close.
    virtual void OnPageDialogDismissed(const Dialog& dialog) = 0;
    // Only while the page's tab is the active one; a tab switch closes it and
    // asks again on return, as Arc's prompt does.
    virtual void OnPagePermissionRequest(const PermissionRequest& request,
                                         PermissionReply reply) = 0;
    // Also after a reply, once Chromium has taken the prompt down.
    virtual void OnPagePermissionRequestClosed(
        const PermissionRequest& request) = 0;
    // A beforeunload handler kept the page after Close().
    virtual void OnPageCloseCancelled() = 0;
    virtual void OnPageClosed(std::optional<int32_t> session_id) = 0;

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
  // While the page captures from them, as ArcCore's media session reports.
  virtual bool IsCameraOn() const = 0;
  virtual bool IsMicrophoneOn() const = 0;

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
