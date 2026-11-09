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

class PageObserverBridge : public oa::Page::Observer {
 public:
  explicit PageObserverBridge(OAPage* page) : page_(page) {}
  void OnPageStateChanged() override { [page_ pageStateChanged]; }
  void OnPageClosed() override { [page_ pageClosed]; }

 private:
  __weak OAPage* page_;
};

}  // namespace

@implementation OAPage {
  std::unique_ptr<PageObserverBridge> _observer;
  std::unique_ptr<oa::Page> _page;
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
