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

@protocol OAPageDelegate <NSObject>
- (void)pageDidChangeState:(OAPage*)page;
// `openedPage` has no delegate yet; releasing it drops the page.
- (void)page:(OAPage*)page
    didOpenPage:(OAPage*)openedPage
      targetURL:(nullable NSURL*)targetURL
    disposition:(OAPageOpenDisposition)disposition;
- (void)pageWantsActivation:(OAPage*)page;
- (void)pageDidClose:(OAPage*)page;
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
// Cross-origin link clicks open a new page instead of navigating this one.
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
- (void)close;
- (void)drop;
@end

@interface OAProfile : NSObject
- (instancetype)init NS_UNAVAILABLE;
// Creates a page in the window's Browser for this profile, loading the profile
// first if needed. The page starts in the background with nothing loaded;
// `completion` gets nil if it can't be created.
- (void)createPageInWindow:(NSString*)windowIdentifier
                  delegate:(nullable id<OAPageDelegate>)delegate
                completion:(void (^)(OAPage* _Nullable page))completion;
@end

@interface OAEngine : NSObject
- (instancetype)init NS_UNAVAILABLE;
- (OAProfile*)profileWithIdentifier:(NSString*)identifier;
// Binds the window once; a later call for the same identifier is ignored.
- (void)attachWindow:(NSWindow*)window withIdentifier:(NSString*)identifier;
// Drops the window's pages; its Browsers then close.
- (void)closeWindowWithIdentifier:(NSString*)identifier;
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
