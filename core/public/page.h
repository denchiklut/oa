#ifndef OA_PUBLIC_PAGE_H_
#define OA_PUBLIC_PAGE_H_

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "oa/public/devtools.h"

namespace oa {

enum class OpenDisposition {
  kForegroundTab,
  kBackgroundTab,
  kNewWindow,
  kPopup,
  // The app's own split view, as ArcCore's split view disposition: from the
  // page menu's Open Link in Split View. Blink's own, a ⌘⌥-click, is a
  // background tab, as ArcCore's.
  kSplitView,
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

// Chrome asks before it installs or removes an extension, as ArcCore's two
// consent calls on the page do.
struct ExtensionRequest {
  enum class Kind {
    kInstall,
    kUninstall,
  };
  uint64_t id = 0;
  Kind kind = Kind::kInstall;
  std::string extension_id;
  std::string name;
  // An NSImage; null for an uninstall.
  std::shared_ptr<void> icon;
  // Chrome's permission warnings, one line each.
  std::vector<std::string> permissions;
};

// Chromium's media session for the page, as ADK's media session state and
// content type report it.
struct MediaSessionState {
  enum class Status {
    kActive,
    kDucking,
    kSuspended,
    kInactive,
  };
  enum class ContentType {
    kUnknown,
    kAudioOnly,
    kVideoOnly,
    kAudioVideo,
  };
  Status status = Status::kInactive;
  ContentType content_type = ContentType::kUnknown;
};

// What Chromium asks of the window that shows a page's video in
// picture-in-picture, as ArcCore's media session delegate reports it.
struct PictureInPictureEvent {
  enum class Kind {
    kCreated,
    kShow,
    kHide,
    kClose,
    kResolutionChanged,
    kDestroyed,
  };
  Kind kind = Kind::kCreated;
  // kCreated: the video element's bounds in the page. kResolutionChanged: the
  // video's natural size.
  double x = 0;
  double y = 0;
  double width = 0;
  double height = 0;
};

// A WebUI dialog Chrome shows over the page, such as print preview, as
// ArcCore's ArcWebDialog. Sizes are in points.
struct WebDialog {
  uint64_t id = 0;
  std::string title;
  std::string accessible_title;
  int preferred_width = 0;
  int preferred_height = 0;
  int minimum_width = 0;
  int minimum_height = 0;
};

// sRGB and unpremultiplied, as SkColor4f.
struct Color {
  float red = 0;
  float green = 0;
  float blue = 0;
  float alpha = 1;
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
  // Call once; dropping it unanswered declines.
  using ExtensionReply = std::function<void(bool accepted)>;

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
    // The page menu's Open Link in Incognito Window, as ArcCore's: only the
    // address, which the app opens in its profile's incognito window.
    virtual void OnPageOpenLinkInIncognitoWindow(const std::string& url) = 0;
    // The page menu's Open Link in Little Oa, as ArcCore's little window
    // disposition, which the app answers by opening its own window: only the
    // address.
    virtual void OnPageOpenLinkInLittleWindow(const std::string& url) = 0;
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
    virtual void OnPageExtensionRequest(const ExtensionRequest& request,
                                        ExtensionReply reply) = 0;
    // The engine took the request down unanswered, as when the extension went
    // away meanwhile.
    virtual void OnPageExtensionRequestClosed(
        const ExtensionRequest& request) = 0;
    // `ns_view` comes with kCreated: an NSView that draws the video, the
    // engine's until kDestroyed. The app hosts it in a window of its own and
    // sizes it.
    virtual void OnPagePictureInPicture(const PictureInPictureEvent& event,
                                        void* ns_view) = 0;
    // `ns_view` draws the dialog, the engine's until OnPageWebDialogClosed.
    // The app shows it over the page's window, as ArcCore's showWebUIDialog.
    virtual void OnPageWebDialog(const WebDialog& dialog, void* ns_view) = 0;
    // The dialog closed itself, from its own buttons or Escape, or with the
    // page.
    virtual void OnPageWebDialogClosed(const WebDialog& dialog) = 0;
    // Every thumbnail Chrome's tab thumbnail helper makes of the page, whoever
    // asked, as ArcCore's thumbnailReady: an NSImage of one pixel a point that
    // lives only for the call.
    virtual void OnPageThumbnail(void* ns_image) = 0;
    // The page consumed a raw key down, as ArcCore's didConsumeKey: the key's
    // code and its NSEvent modifier flags. Only the page's main widget
    // reports, so a key consumed in a frame of another process doesn't.
    virtual void OnPageConsumedKey(int key_code,
                                   unsigned long modifier_flags) = 0;
    // Each result Chrome's find tab helper has for the page's find, as
    // ArcCore's find completion: -1 for what it doesn't know yet.
    virtual void OnPageFindResult(int number_of_matches,
                                  int active_match_ordinal) = 0;
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
  // Chrome's session ID of the page's tab, as ArcCore's restoration data keeps
  // it: kept while the page lives.
  virtual int32_t GetTabSessionID() const = 0;
  // The app profile whose context the page was made in, as ADK's
  // BrowserContextID; a move to another window keeps it.
  virtual std::string GetProfileID() const = 0;
  virtual bool CanGoBack() const = 0;
  virtual bool CanGoForward() const = 0;
  // An NSImage, held by the tab while it keeps the icon; null until it has one.
  virtual void* Favicon() const = 0;
  virtual SecurityLevel GetSecurityLevel() const = 0;
  // The main frame's compositor frames' root background colour, as ArcCore
  // keeps it: none until the first frame, then the last one, across
  // navigations and crashes.
  virtual std::optional<Color> GetRootBackgroundColor() const = 0;
  virtual NavigationResult GetNavigationResult() const = 0;
  // While the page captures from them, as ArcCore's media session reports.
  virtual bool IsCameraOn() const = 0;
  virtual bool IsMicrophoneOn() const = 0;
  virtual bool IsAudible() const = 0;
  virtual bool IsMuted() const = 0;
  // While the page's main widget has the keyboard, as ArcCore's hasFocus: its
  // view is the window's first responder and the window is key.
  virtual bool HasFocus() const = 0;
  // Null while the page has no media session.
  virtual std::optional<MediaSessionState> GetMediaSessionState() const = 0;
  // As ArcCore's cached selectedText: what the user last selected in any of
  // the page's frames that could be copied, so none in a password field that
  // hides it. A script's selection doesn't count, and a navigation keeps it.
  virtual std::string SelectedText() const = 0;
  // As ADK's zoomLevel, a factor: Chrome's zoom level for the page's host in
  // its profile, so every page of the host follows a change.
  virtual float ZoomFactor() const = 0;
  // While a pinch has scaled the page.
  virtual bool IsPageScaled() const = 0;

  virtual void Load(const std::string& url) = 0;
  virtual void GoBack() = 0;
  virtual void GoForward() = 0;
  virtual void Reload() = 0;
  virtual void ReloadBypassingCache() = 0;
  // Chrome's Save Page As panel over the page's window, as ArcCore's save.
  virtual void SavePage() = 0;
  // Chrome's print preview for the page, as ArcCore's print: nothing for a
  // crashed page or one outside a Browser.
  virtual void Print() = 0;
  virtual void Stop() = 0;
  virtual void Activate() = 0;
  // As ArcCore's find: through Chrome's find tab helper, never case-sensitive,
  // scrolling to the active match. Empty text clears the find and reports no
  // matches at once.
  virtual void Find(const std::string& text, bool forward, bool find_match) = 0;
  // As ArcCore's stopFind: the active match stays as the page's selection.
  virtual void StopFinding() = 0;
  // As a pinned tab: a link to another host opens a new page, reported
  // through the observer, instead of navigating this one.
  virtual void SetKeepsAddress(bool keeps_address) = 0;
  // As ADK's setWebContentsMuted: the page stays muted across navigations.
  virtual void SetMuted(bool muted) = 0;
  // As ADK's setZoomFactor: kept for the page's host in its profile.
  virtual void SetZoomFactor(float factor) = 0;
  // As ADK's resetZoomAndScaleFactors: 100 %, not the profile's default zoom,
  // and the pinch undone.
  virtual void ResetZoomAndScaleFactors() = 0;
  // A new background page in this page's window with a copy of its history,
  // loading its current entry, as ADK's cloneWebContent. Null without a page.
  virtual std::unique_ptr<Page> Clone() = 0;
  // The same tab, WebContents and history move; nothing happens if it is there.
  virtual void MoveToWindow(const std::string& window_id) = 0;
  // Fails while the page has nothing drawn, for example when no window shows
  // it.
  virtual void Snapshot(SnapshotCallback callback) = 0;
  // As adding and removing an observer of ArcCore's thumbnails generator.
  // While observed, Chrome makes the page's tab thumbnail by itself, after a
  // load and after a URL change inside the document, hidden or not, and as
  // its tab stops being the window's active one; the observer gets every one.
  // Starting sends the stored thumbnail again.
  virtual void StartObservingThumbnails() = 0;
  virtual void StopObservingThumbnails() = 0;
  // As ArcCore's request, which does nothing unobserved: Chrome copies a
  // visible page's whole view into its tab thumbnail, scaled down to its tab
  // preview size and sent through JPEG, in the display's colours; a hidden
  // page's stored thumbnail is sent again. Nothing comes while a navigation
  // loads.
  virtual void RequestThumbnail() = 0;
  // Through the page's media session, as ArcCore's request: false when the
  // page has a picture-in-picture video already, has no media session, or the
  // session can't enter picture-in-picture. Playing or not is the app's check.
  virtual bool RequestPictureInPicture() = 0;
  // False when the page has no picture-in-picture video.
  virtual bool EndPictureInPicture(bool pause_video) = 0;
  // Closes as the user would: unload handlers run and Chrome records the tab.
  virtual void Close() = 0;
  // Destroys the page without unload handlers or a closed-tab entry.
  virtual void Drop() = 0;
  // Lives as long as the page.
  virtual DevTools* GetDevTools() = 0;
};

}  // namespace oa

#endif  // OA_PUBLIC_PAGE_H_
