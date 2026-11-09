#import "oa/objc/OACore.h"

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "oa/public/engine.h"
#include "oa/public/page.h"

@interface OAPage ()
- (instancetype)initWithDelegate:(nullable id<OAPageDelegate>)delegate;
- (oa::Page::Observer*)observer;
- (void)setPage:(std::unique_ptr<oa::Page>)page;
- (void)pageStateChanged;
- (void)pageOpenedPage:(std::unique_ptr<oa::Page>)page
             targetURL:(const std::string&)url
           disposition:(oa::OpenDisposition)disposition;
- (void)pageWantsActivation;
- (void)pageClosed;
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
  void OnPageClosed() override { [page_ pageClosed]; }

 private:
  __weak OAPage* page_;
};

}  // namespace

@implementation OAPage {
  std::unique_ptr<PageObserverBridge> _observer;
  std::unique_ptr<oa::Page> _page;
  BOOL _keepsAddress;
}

@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(nullable id<OAPageDelegate>)delegate {
  if ((self = [super init])) {
    _delegate = delegate;
    _observer = std::make_unique<PageObserverBridge>(self);
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

- (void)pageClosed {
  [self.delegate pageDidClose:self];
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
                  delegate:(nullable id<OAPageDelegate>)delegate
                completion:(void (^)(OAPage* _Nullable))completion {
  OAPage* page = [[OAPage alloc] initWithDelegate:delegate];
  void (^handler)(OAPage* _Nullable) = [completion copy];
  oa::CreatePage(windowIdentifier.UTF8String ?: "",
                 _identifier.UTF8String ?: "", page.observer,
                 [page, handler](std::unique_ptr<oa::Page> created) {
                   if (!created) {
                     handler(nil);
                     return;
                   }
                   [page setPage:std::move(created)];
                   handler(page);
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
