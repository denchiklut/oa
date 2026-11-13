#ifndef OA_OBJC_OACORE_H_
#define OA_OBJC_OACORE_H_

// OaCore's Objective-C API: the only symbols the app uses. Every call happens
// on the main thread, which is Chromium's UI thread.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OAPage;

typedef NS_ENUM(NSInteger, OAPageOpenDisposition) {
  OAPageOpenDispositionForegroundTab,
  OAPageOpenDispositionBackgroundTab,
  OAPageOpenDispositionNewWindow,
  OAPageOpenDispositionPopup,
};

typedef NS_ENUM(NSInteger, OAPageSecurityLevel) {
  OAPageSecurityLevelNeutral,
  OAPageSecurityLevelSecure,
  OAPageSecurityLevelWarning,
  OAPageSecurityLevelDangerous,
};

typedef NS_ENUM(NSInteger, OAPageNavigationResult) {
  OAPageNavigationResultNone,
  OAPageNavigationResultLoaded,
  OAPageNavigationResultFailed,
};

typedef NS_ENUM(NSInteger, OAPageRendererExit) {
  OAPageRendererExitNormal,
  OAPageRendererExitAbnormal,
  OAPageRendererExitKilled,
  OAPageRendererExitCrashed,
  OAPageRendererExitStillRunning,
  OAPageRendererExitLaunchFailed,
  OAPageRendererExitOutOfMemory,
  OAPageRendererExitEvictedForMemory,
};

typedef NS_ENUM(NSInteger, OAPageMediaSessionStatus) {
  OAPageMediaSessionStatusNone,
  OAPageMediaSessionStatusActive,
  OAPageMediaSessionStatusDucking,
  OAPageMediaSessionStatusSuspended,
  OAPageMediaSessionStatusInactive,
};

typedef NS_ENUM(NSInteger, OAPageMediaContentType) {
  OAPageMediaContentTypeUnknown,
  OAPageMediaContentTypeAudioOnly,
  OAPageMediaContentTypeVideoOnly,
  OAPageMediaContentTypeAudioVideo,
};

typedef NS_ENUM(NSInteger, OAPagePictureInPictureEvent) {
  OAPagePictureInPictureEventCreated,
  OAPagePictureInPictureEventShow,
  OAPagePictureInPictureEventHide,
  OAPagePictureInPictureEventClose,
  OAPagePictureInPictureEventResolutionChanged,
  OAPagePictureInPictureEventDestroyed,
};

typedef NS_ENUM(NSInteger, OAPageDialogKind) {
  OAPageDialogKindAlert,
  OAPageDialogKindConfirm,
  OAPageDialogKindPrompt,
  OAPageDialogKindBeforeUnload,
};

@interface OAPageDialog : NSObject
@property(nonatomic, readonly) OAPageDialogKind kind;
@property(nonatomic, readonly) NSString* title;
@property(nonatomic, readonly) NSString* message;
@property(nonatomic, readonly) NSString* defaultText;
@property(nonatomic, readonly, getter=isReload) BOOL reload;
@property(nonatomic, readonly) BOOL offersSuppression;
- (instancetype)init NS_UNAVAILABLE;
- (void)acceptWithText:(nullable NSString*)text suppress:(BOOL)suppress;
- (void)cancelWithSuppress:(BOOL)suppress;
@end

typedef NS_ENUM(NSInteger, OAPagePermissionResponse) {
  OAPagePermissionResponseAllow,
  OAPagePermissionResponseAllowThisTime,
  OAPagePermissionResponseDeny,
  OAPagePermissionResponseDismiss,
};

@interface OAPagePermissionRequest : NSObject
@property(nonatomic, readonly) NSString* nameOrOrigin;
@property(nonatomic, readonly) BOOL nameIsOrigin;
// `oa::PermissionKind` values, in Chromium's order for the merged request.
@property(nonatomic, readonly) NSArray<NSNumber*>* kinds;
- (instancetype)init NS_UNAVAILABLE;
- (void)respond:(OAPagePermissionResponse)response;
@end

typedef NS_ENUM(NSInteger, OAPageExtensionRequestKind) {
  OAPageExtensionRequestKindInstall,
  OAPageExtensionRequestKindUninstall,
};

// Chrome asking before it installs or removes an extension, as ArcCore's two
// consent calls on the page.
@interface OAPageExtensionRequest : NSObject
@property(nonatomic, readonly) OAPageExtensionRequestKind kind;
@property(nonatomic, readonly) NSString* extensionIdentifier;
@property(nonatomic, readonly) NSString* name;
// Nil for an uninstall.
@property(nonatomic, readonly, nullable) NSImage* icon;
// Chrome's permission warnings, one line each.
@property(nonatomic, readonly) NSArray<NSString*>* permissions;
- (instancetype)init NS_UNAVAILABLE;
// Once; a request released unanswered is declined.
- (void)respond:(BOOL)accepted;
@end

@protocol OAPageDelegate <NSObject>
- (void)pageDidChangeState:(OAPage*)page;
// `openedPage` has no delegate yet; releasing it drops the page.
- (void)page:(OAPage*)page
    didOpenPage:(OAPage*)openedPage
      targetURL:(nullable NSURL*)targetURL
    disposition:(OAPageOpenDisposition)disposition
         byPage:(BOOL)byPage;
- (void)pageWantsActivation:(OAPage*)page;
- (void)page:(OAPage*)page rendererGone:(OAPageRendererExit)exit;
- (void)pageRendererReady:(OAPage*)page;
- (void)page:(OAPage*)page didRequestDialog:(OAPageDialog*)dialog;
- (void)page:(OAPage*)page didDismissDialog:(OAPageDialog*)dialog;
- (void)page:(OAPage*)page
    didRequestPermission:(OAPagePermissionRequest*)request;
- (void)page:(OAPage*)page
    didClosePermissionRequest:(OAPagePermissionRequest*)request;
- (void)page:(OAPage*)page didRequestExtension:(OAPageExtensionRequest*)request;
- (void)page:(OAPage*)page
    didCloseExtensionRequest:(OAPageExtensionRequest*)request;
// `view` comes with Created and draws the page's picture-in-picture video,
// the engine's until Destroyed. `rect` is the video element's bounds in the
// page for Created and holds the video's natural size for ResolutionChanged.
- (void)page:(OAPage*)page
    pictureInPicture:(OAPagePictureInPictureEvent)event
                view:(nullable NSView*)view
                rect:(NSRect)rect;
- (void)pageDidCancelClose:(OAPage*)page;
// `sessionID` is -1 when Chrome kept no record of the tab.
- (void)page:(OAPage*)page didCloseWithSessionID:(int32_t)sessionID;
@end

@interface OAPage : NSObject
@property(nonatomic, weak, nullable) id<OAPageDelegate> delegate;
// Nil once the page is closed or dropped.
@property(nonatomic, readonly, nullable) NSView* view;
@property(nonatomic, readonly, nullable) NSURL* url;
@property(nonatomic, readonly) NSString* title;
@property(nonatomic, readonly, getter=isLoading) BOOL loading;
@property(nonatomic, readonly) double loadProgress;
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
// Nil until Chromium's favicon driver has an icon for the page.
@property(nonatomic, readonly, nullable) NSImage* favicon;
@property(nonatomic, readonly) OAPageSecurityLevel securityLevel;
@property(nonatomic, readonly) OAPageNavigationResult navigationResult;
@property(nonatomic, readonly, getter=isCameraOn) BOOL cameraOn;
@property(nonatomic, readonly, getter=isMicrophoneOn) BOOL microphoneOn;
@property(nonatomic, readonly, getter=isAudible) BOOL audible;
// None while the page has no media session.
@property(nonatomic, readonly) OAPageMediaSessionStatus mediaSessionStatus;
@property(nonatomic, readonly) OAPageMediaContentType mediaContentType;
// Links to another host open a new page instead of navigating this one.
@property(nonatomic) BOOL keepsAddress;
- (instancetype)init NS_UNAVAILABLE;
- (void)loadURL:(NSURL*)url;
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stopLoading;
- (void)activate;
- (void)moveToWindowWithIdentifier:(NSString*)identifier;
// Nil while the page has nothing drawn, for example when no window shows it.
- (void)snapshotWithCompletion:(void (^)(NSImage* _Nullable image))completion;
// NO when the engine refuses: the page has a picture-in-picture video already,
// or no media session that can enter picture-in-picture.
- (BOOL)requestPictureInPicture;
// NO when the page has no picture-in-picture video.
- (BOOL)exitPictureInPictureAndPause:(BOOL)pause;
- (void)close;
- (void)drop;
@end

typedef NS_ENUM(NSInteger, OADownloadState) {
  OADownloadStateInProgress,
  OADownloadStateComplete,
  OADownloadStateCancelled,
  OADownloadStateInterrupted,
};

// A download at the time of an event, as ArcCore's ArcDownloadItem reads it.
@interface OADownload : NSObject
@property(nonatomic, readonly) NSString* identifier;
@property(nonatomic, readonly) OADownloadState state;
@property(nonatomic, readonly) int64_t receivedBytes;
// 0 while the size is unknown.
@property(nonatomic, readonly) int64_t totalBytes;
@property(nonatomic, readonly) int64_t bytesPerSecond;
// -1 while Chromium has no estimate.
@property(nonatomic, readonly) int64_t remainingSeconds;
// Nil until Chromium has chosen where the file goes.
@property(nonatomic, readonly, nullable) NSURL* targetFileURL;
@property(nonatomic, readonly, nullable) NSURL* sourceURL;
@property(nonatomic, readonly) NSDate* startTime;
@property(nonatomic, readonly, getter=isPaused) BOOL paused;
@property(nonatomic, readonly, getter=isDone) BOOL done;
@property(nonatomic, readonly) BOOL canResume;
// The page that started it, while that page is open.
@property(nonatomic, readonly, weak, nullable) OAPage* page;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol OADownloadsDelegate <NSObject>
// Once, with the downloads Chromium's history brought back.
- (void)downloadsDidInitialize:(NSArray<OADownload*>*)downloads;
- (void)downloadWasCreated:(OADownload*)download;
- (void)downloadWasUpdated:(OADownload*)download;
- (void)downloadWasRemovedWithIdentifier:(NSString*)identifier;
@end

// A profile's downloads, as ArcCore's ArcBrowserContextDownloads.
@interface OADownloads : NSObject
// Setting it the first time loads the profile and starts the events.
@property(nonatomic, weak, nullable) id<OADownloadsDelegate> delegate;
- (instancetype)init NS_UNAVAILABLE;
- (void)pauseDownloadWithIdentifier:(NSString*)identifier;
- (void)resumeDownloadWithIdentifier:(NSString*)identifier;
// Deletes the partial file.
- (void)cancelDownloadWithIdentifier:(NSString*)identifier;
// From Chromium's history too, cancelling it first if it runs; a finished
// file stays.
- (void)removeDownloadWithIdentifier:(NSString*)identifier;
@end

// `type` is an `oa::SiteSettingType`, `value` an `oa::SiteSettingValue`.
@interface OASiteSetting : NSObject
@property(nonatomic, readonly) NSInteger type;
@property(nonatomic, readonly) NSInteger value;
- (instancetype)init NS_UNAVAILABLE;
@end

// One of Chromium's search engines, as ArcCore's ArcSearchEngine.
@interface OASearchEngine : NSObject
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSString* keyword;
// Chromium's URL template, with {searchTerms}.
@property(nonatomic, readonly) NSString* url;
@property(nonatomic, readonly, nullable) NSURL* faviconURL;
@property(nonatomic, readonly, getter=isPrepopulated) BOOL prepopulated;
- (instancetype)init NS_UNAVAILABLE;
@end

@class OAPreferences;

@protocol OAPreferencesDelegate <NSObject>
// Once the profile has loaded, then after each change from anywhere.
- (void)preferencesDidChange:(OAPreferences*)preferences;
@end

// A profile's preferences, as ArcCore's ArcBrowserContextPreferences.
@interface OAPreferences : NSObject
// Setting it the first time loads the profile and starts the events.
@property(nonatomic, weak, nullable) id<OAPreferencesDelegate> delegate;
// Where downloads go and a Save panel starts, read from the profile. Nil
// until it has loaded.
@property(nonatomic, copy, nullable) NSURL* downloadDirectory;
// Chromium asks where to save each download.
@property(nonatomic) BOOL asksWhereToSaveDownloads;
// The engines Chrome's settings offer as the default; nil until loaded.
@property(nonatomic, readonly, nullable)
    NSArray<OASearchEngine*>* searchEngines;
@property(nonatomic, readonly, nullable) OASearchEngine* defaultSearchEngine;
// Chrome's search.suggest_enabled.
@property(nonatomic) BOOL searchSuggestEnabled;
- (instancetype)init NS_UNAVAILABLE;
// As the user's choice, as Chrome's settings page sets it.
- (void)setDefaultSearchEngineWithKeyword:(NSString*)keyword;
@end

// A Chromium omnibox match, as ArcCore's ArcAutocompleteMatch.
@interface OAAutocompleteMatch : NSObject
// Chromium's match type string, such as "history-url".
@property(nonatomic, readonly) NSString* type;
// Chromium's provider name, such as "HistoryURL".
@property(nonatomic, readonly) NSString* provider;
@property(nonatomic, readonly) NSString* contents;
@property(nonatomic, readonly) NSString* matchDescription;
@property(nonatomic, readonly, nullable) NSURL* destinationURL;
@property(nonatomic, readonly) NSString* fillIntoEdit;
@property(nonatomic, readonly) NSString* inlineAutocompletion;
@property(nonatomic, readonly) NSString* keyword;
@property(nonatomic, readonly) NSInteger relevance;
@property(nonatomic, readonly) BOOL allowedToBeDefault;
@property(nonatomic, readonly, getter=isDeletable) BOOL deletable;
@property(nonatomic, readonly) BOOL swapsContentsAndDescription;
@property(nonatomic, readonly, getter=isFromKeyword) BOOL fromKeyword;
@property(nonatomic, readonly, getter=isFromPrevious) BOOL fromPrevious;
// Chromium's additional info, such as "typed count" and "visit count".
@property(nonatomic, readonly)
    NSDictionary<NSString*, NSString*>* additionalInfo;
- (instancetype)init NS_UNAVAILABLE;
@end

// As ArcCore's ArcAutocompleteResult.
@interface OAAutocompleteResult : NSObject
// Chromium's combined result, in its order; it holds at most 8 matches.
@property(nonatomic, readonly) NSArray<OAAutocompleteMatch*>* combinedMatches;
// Every provider's own matches, provider by provider.
@property(nonatomic, readonly)
    NSArray<OAAutocompleteMatch*>* perProviderMatches;
- (instancetype)init NS_UNAVAILABLE;
@end

// Chromium's omnibox in one profile, as ArcCore's ArcBrowser runs it.
@interface OAAutocomplete : NSObject
- (instancetype)init NS_UNAVAILABLE;
// Replaces a running query; before the profile has loaded, the last start
// waits for it. `cursorPosition` is in UTF-16 code units. `completion` runs at
// least once and again as providers answer, until the next start.
- (void)startWithText:(NSString*)text
               cursorPosition:(NSUInteger)cursorPosition
    preventInlineAutocomplete:(BOOL)preventInlineAutocomplete
                   startFresh:(BOOL)startFresh
                      keyword:(nullable NSString*)keyword
                   currentURL:(nullable NSURL*)currentURL
                   completion:(void (^)(OAAutocompleteResult* result,
                                        BOOL done))completion;
- (void)stop;
- (void)deleteMatch:(OAAutocompleteMatch*)match;
@end

// An installed extension, as ArcCore's ArcExtensionInfo.
@interface OAExtension : NSObject
@property(nonatomic, readonly) NSString* identifier;
@property(nonatomic, readonly) NSString* name;
@property(nonatomic, readonly) NSString* extensionDescription;
@property(nonatomic, readonly) NSString* version;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property(nonatomic, readonly) BOOL hasAction;
@property(nonatomic, readonly, getter=isFromWebstore) BOOL fromWebstore;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol OAExtensionsDelegate <NSObject>
// Once, when the profile's extension system is ready.
- (void)extensionsDidInitialize:(NSArray<OAExtension*>*)extensions;
// Also for an update, which replaces the one with its identifier.
- (void)extensionWasInstalled:(OAExtension*)extension;
- (void)extensionWasUninstalledWithIdentifier:(NSString*)identifier;
- (void)extensionWasEnabled:(OAExtension*)extension;
- (void)extensionWasDisabled:(OAExtension*)extension;
@end

// A profile's extensions, as ArcCore's ArcBrowserContextExtensions.
@interface OAExtensions : NSObject
// Setting it the first time loads the profile and starts the events.
@property(nonatomic, weak, nullable) id<OAExtensionsDelegate> delegate;
- (instancetype)init NS_UNAVAILABLE;
- (void)setExtensionWithIdentifier:(NSString*)identifier enabled:(BOOL)enabled;
// Without asking; Chromium's own removal paths ask through the page.
- (void)uninstallExtensionWithIdentifier:(NSString*)identifier;
@end

// An extension's toolbar action for a window's active page, as ArcCore's
// ArcExtensionToolbarAction.
@interface OAExtensionToolbarAction : NSObject
@property(nonatomic, readonly) NSString* identifier;
@property(nonatomic, readonly) NSString* accessibleName;
@property(nonatomic, readonly) NSString* tooltip;
// With the badge drawn in.
@property(nonatomic, readonly, nullable) NSImage* icon;
@property(nonatomic, readonly, getter=isEnabled) BOOL enabled;
// Among Chrome's pinned extensions; -1 when it isn't pinned.
@property(nonatomic, readonly) NSInteger pinnedPosition;
- (instancetype)init NS_UNAVAILABLE;
@end

@class OABrowser;

@protocol OABrowserDelegate <NSObject>
// The whole list, after any of it changed and when the active page did.
- (void)browser:(OABrowser*)browser
    didUpdateExtensionToolbarActions:
        (NSArray<OAExtensionToolbarAction*>*)actions;
// An action's popup page has loaded. The engine keeps `view` until the popup
// closes; one popup shows at a time.
- (void)browser:(OABrowser*)browser
    didOpenExtensionPopup:(NSString*)extensionIdentifier
                     view:(NSView*)view
                     size:(NSSize)size;
- (void)browser:(OABrowser*)browser didResizeExtensionPopup:(NSSize)size;
- (void)browserDidCloseExtensionPopup:(OABrowser*)browser;
// Chromium put `page` in the window itself, as an extension's
// chrome.tabs.create does. It has no delegate yet; releasing it drops it.
- (void)browser:(OABrowser*)browser
    didOpenPage:(OAPage*)page
         active:(BOOL)active;
@end

// One window's side in one profile, as ArcCore's ArcBrowser.
@interface OABrowser : NSObject
- (instancetype)init NS_UNAVAILABLE;
// As a click on its toolbar button, for the window's active page.
- (void)executeExtensionAction:(NSString*)identifier;
- (void)setExtension:(NSString*)identifier pinned:(BOOL)pinned;
// Chrome's menu for the action, at the mouse.
- (void)showExtensionContextMenu:(NSString*)identifier;
- (void)focusExtensionPopup;
- (void)closeExtensionPopup;
@end

@interface OAProfile : NSObject
@property(nonatomic, readonly) OADownloads* downloads;
@property(nonatomic, readonly) OAPreferences* preferences;
@property(nonatomic, readonly) OAExtensions* extensions;
- (instancetype)init NS_UNAVAILABLE;
// Nil until the profile has loaded.
- (nullable NSArray<OASiteSetting*>*)changedSiteSettingsForURL:(NSURL*)url;
- (void)setSiteSetting:(NSInteger)type to:(NSInteger)value forURL:(NSURL*)url;
// Loads the profile if needed. ArcCore keeps one per window.
- (OAAutocomplete*)makeAutocomplete;
// Loads the profile if needed and reports to `delegate`, held weakly, until
// the result is released. The app keeps one per window and profile.
- (OABrowser*)browserInWindow:(NSString*)windowIdentifier
                     delegate:(id<OABrowserDelegate>)delegate;
// Creates a page in the window's Browser for this profile, loading the profile
// first if needed. The page starts in the background with nothing loaded, or
// with the history of a closed page's `sessionID` (not -1) and `restored`;
// `completion` gets nil if it can't be created.
- (void)createPageInWindow:(NSString*)windowIdentifier
        restoringSessionID:(int32_t)sessionID
                  delegate:(nullable id<OAPageDelegate>)delegate
                completion:
                    (void (^)(OAPage* _Nullable page, BOOL restored))completion;
@end

@interface OAEngine : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (OAProfile*)profileWithIdentifier:(NSString*)identifier;
// Binds the window once; a later call for the same identifier is ignored.
- (void)attachWindow:(NSWindow*)window withIdentifier:(NSString*)identifier;
// Drops the window's pages; its Browsers then close.
- (void)closeWindowWithIdentifier:(NSString*)identifier;
// Asks each page's beforeunload handler in tab strip order; every page stays.
- (void)askToLeaveWindowWithIdentifier:(NSString*)identifier
                            completion:(void (^)(BOOL leave))completion;
- (void)quit;
@end

NS_ASSUME_NONNULL_END

typedef void (*OACoreReadyCallback)(void* _Nullable context,
                                    void* _Nonnull engine);

extern "C" __attribute__((visibility("default"))) int OACoreMain(
    int argc,
    const char* _Nullable* _Nonnull argv,
    OACoreReadyCallback _Nonnull ready,
    void* _Nullable context);

#endif  // OA_OBJC_OACORE_H_
