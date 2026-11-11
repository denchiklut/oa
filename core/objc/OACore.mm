#import "oa/objc/OACore.h"

#include <memory>
#include <optional>
#include <string>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "oa/public/engine.h"
#include "oa/public/page.h"

@interface OAPage ()
- (instancetype)initWithDelegate:(nullable id<OAPageDelegate>)delegate;
- (oa::Page::Observer*)observer;
- (void)pageDialog:(const oa::Dialog&)dialog reply:(oa::Page::DialogReply)reply;
- (void)pageDialogDismissed:(const oa::Dialog&)dialog;
- (void)pagePermissionRequest:(const oa::PermissionRequest&)request
                        reply:(oa::Page::PermissionReply)reply;
- (void)pagePermissionRequestClosed:(const oa::PermissionRequest&)request;
- (void)pageCloseCancelled;
- (void)setPage:(std::unique_ptr<oa::Page>)page;
- (void)pageStateChanged;
- (void)pageOpenedPage:(std::unique_ptr<oa::Page>)page
             targetURL:(const std::string&)url
           disposition:(oa::OpenDisposition)disposition;
- (void)pageWantsActivation;
- (void)pageRendererGone:(oa::RendererExit)exit;
- (void)pageRendererReady;
- (void)pageClosedWithSessionID:(int32_t)sessionID;
@end

@interface OAProfile ()
- (instancetype)initWithIdentifier:(NSString*)identifier;
@end

@interface OAEngine ()
+ (OAEngine*)sharedEngine;
@end

namespace {

NSString* ToNSString(const std::string& string) {
  return [[NSString alloc] initWithBytes:string.data()
                                  length:string.size()
                                encoding:NSUTF8StringEncoding]
             ?: @"";
}

OAPageOpenDisposition ToDisposition(oa::OpenDisposition disposition) {
  switch (disposition) {
    case oa::OpenDisposition::kForegroundTab:
      return OAPageOpenDispositionForegroundTab;
    case oa::OpenDisposition::kBackgroundTab:
      return OAPageOpenDispositionBackgroundTab;
    case oa::OpenDisposition::kNewWindow:
      return OAPageOpenDispositionNewWindow;
    case oa::OpenDisposition::kPopup:
      return OAPageOpenDispositionPopup;
  }
}

OAPageSecurityLevel ToSecurityLevel(oa::SecurityLevel level) {
  switch (level) {
    case oa::SecurityLevel::kNeutral:
      return OAPageSecurityLevelNeutral;
    case oa::SecurityLevel::kSecure:
      return OAPageSecurityLevelSecure;
    case oa::SecurityLevel::kWarning:
      return OAPageSecurityLevelWarning;
    case oa::SecurityLevel::kDangerous:
      return OAPageSecurityLevelDangerous;
  }
}

OAPageNavigationResult ToNavigationResult(oa::NavigationResult result) {
  switch (result) {
    case oa::NavigationResult::kNone:
      return OAPageNavigationResultNone;
    case oa::NavigationResult::kLoaded:
      return OAPageNavigationResultLoaded;
    case oa::NavigationResult::kFailed:
      return OAPageNavigationResultFailed;
  }
}

OAPageRendererExit ToRendererExit(oa::RendererExit exit) {
  switch (exit) {
    case oa::RendererExit::kNormal:
      return OAPageRendererExitNormal;
    case oa::RendererExit::kAbnormal:
      return OAPageRendererExitAbnormal;
    case oa::RendererExit::kKilled:
      return OAPageRendererExitKilled;
    case oa::RendererExit::kCrashed:
      return OAPageRendererExitCrashed;
    case oa::RendererExit::kStillRunning:
      return OAPageRendererExitStillRunning;
    case oa::RendererExit::kLaunchFailed:
      return OAPageRendererExitLaunchFailed;
    case oa::RendererExit::kOutOfMemory:
      return OAPageRendererExitOutOfMemory;
    case oa::RendererExit::kEvictedForMemory:
      return OAPageRendererExitEvictedForMemory;
  }
}

class PageObserverBridge : public oa::Page::Observer {
 public:
  explicit PageObserverBridge(OAPage* page) : page_(page) {}
  void OnPageStateChanged() override { [page_ pageStateChanged]; }
  void OnPageOpenedPage(std::unique_ptr<oa::Page> page,
                        const std::string& target_url,
                        oa::OpenDisposition disposition) override {
    [page_ pageOpenedPage:std::move(page)
                targetURL:target_url
              disposition:disposition];
  }
  void OnPageWantsActivation() override { [page_ pageWantsActivation]; }
  void OnPageRendererGone(oa::RendererExit exit) override {
    [page_ pageRendererGone:exit];
  }
  void OnPageRendererReady() override { [page_ pageRendererReady]; }
  void OnPageDialog(const oa::Dialog& dialog,
                    oa::Page::DialogReply reply) override {
    [page_ pageDialog:dialog reply:std::move(reply)];
  }
  void OnPageDialogDismissed(const oa::Dialog& dialog) override {
    [page_ pageDialogDismissed:dialog];
  }
  void OnPagePermissionRequest(const oa::PermissionRequest& request,
                               oa::Page::PermissionReply reply) override {
    [page_ pagePermissionRequest:request reply:std::move(reply)];
  }
  void OnPagePermissionRequestClosed(
      const oa::PermissionRequest& request) override {
    [page_ pagePermissionRequestClosed:request];
  }
  void OnPageCloseCancelled() override { [page_ pageCloseCancelled]; }
  void OnPageClosed(std::optional<int32_t> session_id) override {
    [page_ pageClosedWithSessionID:session_id.value_or(-1)];
  }

 private:
  __weak OAPage* page_;
};

OAPageDialogKind ToDialogKind(oa::Dialog::Kind kind) {
  switch (kind) {
    case oa::Dialog::Kind::kAlert:
      return OAPageDialogKindAlert;
    case oa::Dialog::Kind::kConfirm:
      return OAPageDialogKindConfirm;
    case oa::Dialog::Kind::kPrompt:
      return OAPageDialogKindPrompt;
    case oa::Dialog::Kind::kBeforeUnload:
      return OAPageDialogKindBeforeUnload;
  }
}

}  // namespace

@interface OAPageDialog ()
- (instancetype)initWithDialog:(const oa::Dialog&)dialog
                         reply:(oa::Page::DialogReply)reply;
@end

@implementation OAPageDialog {
  oa::Page::DialogReply _reply;
}

@synthesize kind = _kind;
@synthesize title = _title;
@synthesize message = _message;
@synthesize defaultText = _defaultText;
@synthesize reload = _reload;
@synthesize offersSuppression = _offersSuppression;

- (instancetype)initWithDialog:(const oa::Dialog&)dialog
                         reply:(oa::Page::DialogReply)reply {
  if ((self = [super init])) {
    _kind = ToDialogKind(dialog.kind);
    _title = ToNSString(dialog.title);
    _message = ToNSString(dialog.message);
    _defaultText = ToNSString(dialog.default_text);
    _reload = dialog.is_reload;
    _offersSuppression = dialog.offers_suppression;
    _reply = std::move(reply);
  }
  return self;
}

- (void)acceptWithText:(nullable NSString*)text suppress:(BOOL)suppress {
  if (oa::Page::DialogReply reply = std::exchange(_reply, nullptr)) {
    reply(true, text.UTF8String ?: "", suppress);
  }
}

- (void)cancelWithSuppress:(BOOL)suppress {
  if (oa::Page::DialogReply reply = std::exchange(_reply, nullptr)) {
    reply(false, std::string(), suppress);
  }
}

@end

@interface OAPagePermissionRequest ()
- (instancetype)initWithRequest:(const oa::PermissionRequest&)request
                          reply:(oa::Page::PermissionReply)reply;
@end

@implementation OAPagePermissionRequest {
  oa::Page::PermissionReply _reply;
}

@synthesize nameOrOrigin = _nameOrOrigin;
@synthesize nameIsOrigin = _nameIsOrigin;
@synthesize kinds = _kinds;

- (instancetype)initWithRequest:(const oa::PermissionRequest&)request
                          reply:(oa::Page::PermissionReply)reply {
  if ((self = [super init])) {
    _nameOrOrigin = ToNSString(request.name_or_origin);
    _nameIsOrigin = request.is_origin;
    NSMutableArray<NSNumber*>* kinds = [NSMutableArray array];
    for (oa::PermissionKind kind : request.kinds) {
      [kinds addObject:@(static_cast<NSInteger>(kind))];
    }
    _kinds = kinds;
    _reply = std::move(reply);
  }
  return self;
}

- (void)respond:(OAPagePermissionResponse)response {
  oa::Page::PermissionReply reply = std::exchange(_reply, nullptr);
  if (!reply) {
    return;
  }
  switch (response) {
    case OAPagePermissionResponseAllow:
      return reply(oa::PermissionResponse::kAllow);
    case OAPagePermissionResponseAllowThisTime:
      return reply(oa::PermissionResponse::kAllowThisTime);
    case OAPagePermissionResponseDeny:
      return reply(oa::PermissionResponse::kDeny);
    case OAPagePermissionResponseDismiss:
      return reply(oa::PermissionResponse::kDismiss);
  }
}

@end

@implementation OAPage {
  std::unique_ptr<PageObserverBridge> _observer;
  std::unique_ptr<oa::Page> _page;
  NSMutableDictionary<NSNumber*, OAPageDialog*>* _dialogs;
  NSMutableDictionary<NSNumber*, OAPagePermissionRequest*>* _permissionRequests;
  BOOL _keepsAddress;
}

@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(nullable id<OAPageDelegate>)delegate {
  if ((self = [super init])) {
    _delegate = delegate;
    _observer = std::make_unique<PageObserverBridge>(self);
    _dialogs = [[NSMutableDictionary alloc] init];
    _permissionRequests = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)dealloc {
  _page.reset();
}

- (oa::Page::Observer*)observer {
  return _observer.get();
}

- (void)setPage:(std::unique_ptr<oa::Page>)page {
  _page = std::move(page);
  _page->SetObserver(_observer.get());
  _page->SetKeepsAddress(_keepsAddress);
}

- (BOOL)keepsAddress {
  return _keepsAddress;
}

- (void)setKeepsAddress:(BOOL)keepsAddress {
  _keepsAddress = keepsAddress;
  if (_page) {
    _page->SetKeepsAddress(keepsAddress);
  }
}

- (nullable NSView*)view {
  void* view = _page ? _page->NativeView() : nullptr;
  return view ? (__bridge NSView*)view : nil;
}

- (nullable NSURL*)url {
  if (!_page) {
    return nil;
  }
  std::string url = _page->VisibleURL();
  return url.empty() ? nil : [NSURL URLWithString:ToNSString(url)];
}

- (NSString*)title {
  return _page ? ToNSString(_page->Title()) : @"";
}

- (BOOL)isLoading {
  return _page && _page->IsLoading();
}

- (double)loadProgress {
  return _page ? _page->LoadProgress() : 0;
}

- (BOOL)canGoBack {
  return _page && _page->CanGoBack();
}

- (BOOL)canGoForward {
  return _page && _page->CanGoForward();
}

- (nullable NSImage*)favicon {
  void* image = _page ? _page->Favicon() : nullptr;
  return image ? (__bridge NSImage*)image : nil;
}

- (OAPageSecurityLevel)securityLevel {
  return _page ? ToSecurityLevel(_page->GetSecurityLevel())
               : OAPageSecurityLevelNeutral;
}

- (OAPageNavigationResult)navigationResult {
  return _page ? ToNavigationResult(_page->GetNavigationResult())
               : OAPageNavigationResultNone;
}

- (BOOL)isCameraOn {
  return _page && _page->IsCameraOn();
}

- (BOOL)isMicrophoneOn {
  return _page && _page->IsMicrophoneOn();
}

- (void)loadURL:(NSURL*)url {
  if (_page) {
    _page->Load(url.absoluteString.UTF8String ?: "");
  }
}

- (void)goBack {
  if (_page) {
    _page->GoBack();
  }
}

- (void)goForward {
  if (_page) {
    _page->GoForward();
  }
}

- (void)reload {
  if (_page) {
    _page->Reload();
  }
}

- (void)stopLoading {
  if (_page) {
    _page->Stop();
  }
}

- (void)activate {
  if (_page) {
    _page->Activate();
  }
}

- (void)moveToWindowWithIdentifier:(NSString*)identifier {
  if (_page) {
    _page->MoveToWindow(identifier.UTF8String ?: "");
  }
}

- (void)snapshotWithCompletion:(void (^)(NSImage* _Nullable))completion {
  if (!_page) {
    completion(nil);
    return;
  }
  void (^handler)(NSImage* _Nullable) = [completion copy];
  _page->Snapshot(
      [handler](void* image) { handler((__bridge NSImage*)image); });
}

- (void)close {
  if (_page) {
    _page->Close();
  }
}

- (void)drop {
  if (_page) {
    _page->Drop();
  }
}

- (void)pageStateChanged {
  [self.delegate pageDidChangeState:self];
}

- (void)pageOpenedPage:(std::unique_ptr<oa::Page>)page
             targetURL:(const std::string&)url
           disposition:(oa::OpenDisposition)disposition {
  OAPage* opened = [[OAPage alloc] initWithDelegate:nil];
  [opened setPage:std::move(page)];
  [self.delegate page:self
          didOpenPage:opened
            targetURL:url.empty() ? nil : [NSURL URLWithString:ToNSString(url)]
          disposition:ToDisposition(disposition)];
}

- (void)pageWantsActivation {
  [self.delegate pageWantsActivation:self];
}

- (void)pageRendererGone:(oa::RendererExit)exit {
  [self.delegate page:self rendererGone:ToRendererExit(exit)];
}

- (void)pageRendererReady {
  [self.delegate pageRendererReady:self];
}

- (void)pageDialog:(const oa::Dialog&)dialog
             reply:(oa::Page::DialogReply)reply {
  NSNumber* key = @(dialog.id);
  __weak OAPage* weakSelf = self;
  OAPageDialog* shown = [[OAPageDialog alloc]
      initWithDialog:dialog
               reply:[weakSelf, key, reply = std::move(reply)](
                         bool accepted, const std::string& text,
                         bool suppress) {
                 if (OAPage* page = weakSelf) {
                   [page->_dialogs removeObjectForKey:key];
                 }
                 reply(accepted, text, suppress);
               }];
  _dialogs[key] = shown;
  [self.delegate page:self didRequestDialog:shown];
}

- (void)pageDialogDismissed:(const oa::Dialog&)dialog {
  NSNumber* key = @(dialog.id);
  OAPageDialog* shown = _dialogs[key];
  if (!shown) {
    return;
  }
  [_dialogs removeObjectForKey:key];
  [self.delegate page:self didDismissDialog:shown];
}

- (void)pagePermissionRequest:(const oa::PermissionRequest&)request
                        reply:(oa::Page::PermissionReply)reply {
  OAPagePermissionRequest* shown =
      [[OAPagePermissionRequest alloc] initWithRequest:request
                                                 reply:std::move(reply)];
  _permissionRequests[@(request.id)] = shown;
  [self.delegate page:self didRequestPermission:shown];
}

- (void)pagePermissionRequestClosed:(const oa::PermissionRequest&)request {
  NSNumber* key = @(request.id);
  OAPagePermissionRequest* shown = _permissionRequests[key];
  if (!shown) {
    return;
  }
  [_permissionRequests removeObjectForKey:key];
  [self.delegate page:self didClosePermissionRequest:shown];
}

- (void)pageCloseCancelled {
  [self.delegate pageDidCancelClose:self];
}

- (void)pageClosedWithSessionID:(int32_t)sessionID {
  [self.delegate page:self didCloseWithSessionID:sessionID];
}

@end

@implementation OAProfile {
  NSString* _identifier;
}

- (instancetype)initWithIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    _identifier = [identifier copy];
  }
  return self;
}

- (void)createPageInWindow:(NSString*)windowIdentifier
        restoringSessionID:(int32_t)sessionID
                  delegate:(nullable id<OAPageDelegate>)delegate
                completion:(void (^)(OAPage* _Nullable, BOOL))completion {
  OAPage* page = [[OAPage alloc] initWithDelegate:delegate];
  void (^handler)(OAPage* _Nullable, BOOL) = [completion copy];
  oa::CreatePage(
      windowIdentifier.UTF8String ?: "", _identifier.UTF8String ?: "",
      sessionID < 0 ? std::nullopt : std::optional(sessionID), page.observer,
      [page, handler](std::unique_ptr<oa::Page> created, bool restored) {
        if (!created) {
          handler(nil, NO);
          return;
        }
        [page setPage:std::move(created)];
        handler(page, restored);
      });
}

@end

@implementation OAEngine {
  NSMutableDictionary<NSString*, OAProfile*>* _profiles;
}

+ (OAEngine*)sharedEngine {
  static OAEngine* engine = [[OAEngine alloc] initShared];
  return engine;
}

- (instancetype)initShared {
  if ((self = [super init])) {
    _profiles = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (OAProfile*)profileWithIdentifier:(NSString*)identifier {
  OAProfile* profile = _profiles[identifier];
  if (!profile) {
    profile = [[OAProfile alloc] initWithIdentifier:identifier];
    _profiles[identifier] = profile;
  }
  return profile;
}

- (void)attachWindow:(NSWindow*)window withIdentifier:(NSString*)identifier {
  oa::AttachWindow(identifier.UTF8String ?: "", (__bridge void*)window);
}

- (void)closeWindowWithIdentifier:(NSString*)identifier {
  oa::CloseWindow(identifier.UTF8String ?: "");
}

- (void)askToLeaveWindowWithIdentifier:(NSString*)identifier
                            completion:(void (^)(BOOL))completion {
  void (^handler)(BOOL) = [completion copy];
  oa::AskToLeaveWindow(identifier.UTF8String ?: "",
                       [handler](bool leave) { handler(leave); });
}

- (void)quit {
  oa::QuitEngine();
}

@end

namespace {

struct ReadyTarget {
  OACoreReadyCallback callback;
  raw_ptr<void> context;
};

void RunReady(void* target) {
  auto* ready = static_cast<ReadyTarget*>(target);
  ready->callback(ready->context.get(),
                  (__bridge void*)[OAEngine sharedEngine]);
}

}  // namespace

int OACoreMain(int argc,
               const char* _Nullable* _Nonnull argv,
               OACoreReadyCallback ready,
               void* _Nullable context) {
  ReadyTarget target{ready, context};
  return oa::RunEngine(argc, argv, &RunReady, &target);
}
