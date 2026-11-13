#import "oa/objc/OACore.h"

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>

#include "base/memory/raw_ptr.h"
#include "oa/public/autocomplete.h"
#include "oa/public/browser.h"
#include "oa/public/downloads.h"
#include "oa/public/engine.h"
#include "oa/public/extensions.h"
#include "oa/public/page.h"
#include "oa/public/preferences.h"
#include "oa/public/site_settings.h"

@interface OAPage ()
- (instancetype)initWithDelegate:(nullable id<OAPageDelegate>)delegate;
- (oa::Page::Observer*)observer;
- (void)pageDialog:(const oa::Dialog&)dialog reply:(oa::Page::DialogReply)reply;
- (void)pageDialogDismissed:(const oa::Dialog&)dialog;
- (void)pagePermissionRequest:(const oa::PermissionRequest&)request
                        reply:(oa::Page::PermissionReply)reply;
- (void)pagePermissionRequestClosed:(const oa::PermissionRequest&)request;
- (void)pageExtensionRequest:(const oa::ExtensionRequest&)request
                       reply:(oa::Page::ExtensionReply)reply;
- (void)pageExtensionRequestClosed:(const oa::ExtensionRequest&)request;
- (void)pageCloseCancelled;
- (void)setPage:(std::unique_ptr<oa::Page>)page;
- (void)pageStateChanged;
- (void)pageOpenedPage:(std::unique_ptr<oa::Page>)page
             targetURL:(const std::string&)url
           disposition:(oa::OpenDisposition)disposition
                byPage:(BOOL)byPage;
- (void)pageWantsActivation;
- (void)pageRendererGone:(oa::RendererExit)exit;
- (void)pageRendererReady;
- (void)pageClosedWithSessionID:(int32_t)sessionID;
@end

@interface OASiteSetting ()
- (instancetype)initWithSetting:(const oa::SiteSetting&)setting;
@end

@interface OADownload ()
- (instancetype)initWithDownload:(const oa::Download&)download
                            page:(nullable OAPage*)page;
@end

@interface OASearchEngine ()
- (instancetype)initWithEngine:(const oa::SearchEngine&)engine;
@end

@interface OAPreferences ()
- (instancetype)initWithProfileIdentifier:(NSString*)identifier;
- (void)preferencesChanged;
@end

@interface OADownloads ()
- (instancetype)initWithProfileIdentifier:(NSString*)identifier;
- (void)downloadsInitialized:(const std::vector<oa::Download>&)downloads;
- (void)downloadCreated:(const oa::Download&)download page:(oa::Page*)page;
- (void)downloadUpdated:(const oa::Download&)download page:(oa::Page*)page;
- (void)downloadRemoved:(const std::string&)identifier;
@end

@interface OAExtension ()
- (instancetype)initWithExtension:(const oa::Extension&)extension;
@end

@interface OAExtensions ()
- (instancetype)initWithProfileIdentifier:(NSString*)identifier;
- (id<OAExtensionsDelegate>)target;
@end

@interface OAExtensionToolbarAction ()
- (instancetype)initWithAction:(const oa::ExtensionToolbarAction&)action;
@end

@interface OABrowser ()
- (instancetype)initWithWindowIdentifier:(NSString*)windowIdentifier
                       profileIdentifier:(NSString*)profileIdentifier
                                delegate:(id<OABrowserDelegate>)delegate;
- (id<OABrowserDelegate>)target;
@end

@interface OAAutocompleteMatch ()
- (instancetype)initWithMatch:(const oa::AutocompleteMatch&)match;
- (const oa::AutocompleteMatch&)match;
@end

@interface OAAutocompleteResult ()
- (instancetype)initWithResult:(const oa::AutocompleteResult&)result;
@end

@interface OAAutocomplete ()
- (instancetype)initWithProfileIdentifier:(NSString*)identifier;
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

// A download names its page by the engine's object.
std::map<oa::Page*, __weak OAPage*>& PagesByCore() {
  static auto* pages = new std::map<oa::Page*, __weak OAPage*>();
  return *pages;
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
                        oa::OpenDisposition disposition,
                        bool by_page) override {
    [page_ pageOpenedPage:std::move(page)
                targetURL:target_url
              disposition:disposition
                   byPage:by_page];
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
  void OnPageExtensionRequest(const oa::ExtensionRequest& request,
                              oa::Page::ExtensionReply reply) override {
    [page_ pageExtensionRequest:request reply:std::move(reply)];
  }
  void OnPageExtensionRequestClosed(
      const oa::ExtensionRequest& request) override {
    [page_ pageExtensionRequestClosed:request];
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

@interface OAPageExtensionRequest ()
- (instancetype)initWithRequest:(const oa::ExtensionRequest&)request
                          reply:(oa::Page::ExtensionReply)reply;
@end

@implementation OAPageExtensionRequest {
  oa::Page::ExtensionReply _reply;
}

@synthesize kind = _kind;
@synthesize extensionIdentifier = _extensionIdentifier;
@synthesize name = _name;
@synthesize icon = _icon;
@synthesize permissions = _permissions;

- (instancetype)initWithRequest:(const oa::ExtensionRequest&)request
                          reply:(oa::Page::ExtensionReply)reply {
  if ((self = [super init])) {
    _kind = request.kind == oa::ExtensionRequest::Kind::kInstall
                ? OAPageExtensionRequestKindInstall
                : OAPageExtensionRequestKindUninstall;
    _extensionIdentifier = ToNSString(request.extension_id);
    _name = ToNSString(request.name);
    _icon = (__bridge NSImage*)request.icon.get();
    NSMutableArray<NSString*>* permissions = [NSMutableArray array];
    for (const std::string& permission : request.permissions) {
      [permissions addObject:ToNSString(permission)];
    }
    _permissions = permissions;
    _reply = std::move(reply);
  }
  return self;
}

- (void)respond:(BOOL)accepted {
  if (oa::Page::ExtensionReply reply = std::exchange(_reply, nullptr)) {
    reply(accepted);
  }
}

@end

@implementation OAPage {
  std::unique_ptr<PageObserverBridge> _observer;
  std::unique_ptr<oa::Page> _page;
  NSMutableDictionary<NSNumber*, OAPageDialog*>* _dialogs;
  NSMutableDictionary<NSNumber*, OAPagePermissionRequest*>* _permissionRequests;
  NSMapTable<NSNumber*, OAPageExtensionRequest*>* _extensionRequests;
  BOOL _keepsAddress;
}

@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(nullable id<OAPageDelegate>)delegate {
  if ((self = [super init])) {
    _delegate = delegate;
    _observer = std::make_unique<PageObserverBridge>(self);
    _dialogs = [[NSMutableDictionary alloc] init];
    _permissionRequests = [[NSMutableDictionary alloc] init];
    // Weakly: a request the app let go of is declined.
    _extensionRequests = [NSMapTable strongToWeakObjectsMapTable];
  }
  return self;
}

- (void)dealloc {
  PagesByCore().erase(_page.get());
  _page.reset();
}

- (oa::Page::Observer*)observer {
  return _observer.get();
}

- (void)setPage:(std::unique_ptr<oa::Page>)page {
  _page = std::move(page);
  PagesByCore()[_page.get()] = self;
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
           disposition:(oa::OpenDisposition)disposition
                byPage:(BOOL)byPage {
  OAPage* opened = [[OAPage alloc] initWithDelegate:nil];
  [opened setPage:std::move(page)];
  [self.delegate page:self
          didOpenPage:opened
            targetURL:url.empty() ? nil : [NSURL URLWithString:ToNSString(url)]
          disposition:ToDisposition(disposition)
               byPage:byPage];
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

- (void)pageExtensionRequest:(const oa::ExtensionRequest&)request
                       reply:(oa::Page::ExtensionReply)reply {
  OAPageExtensionRequest* shown =
      [[OAPageExtensionRequest alloc] initWithRequest:request
                                                reply:std::move(reply)];
  [_extensionRequests setObject:shown forKey:@(request.id)];
  [self.delegate page:self didRequestExtension:shown];
}

- (void)pageExtensionRequestClosed:(const oa::ExtensionRequest&)request {
  if (OAPageExtensionRequest* shown =
          [_extensionRequests objectForKey:@(request.id)]) {
    [self.delegate page:self didCloseExtensionRequest:shown];
  }
}

- (void)pageCloseCancelled {
  [self.delegate pageDidCancelClose:self];
}

- (void)pageClosedWithSessionID:(int32_t)sessionID {
  [self.delegate page:self didCloseWithSessionID:sessionID];
}

@end

@implementation OASiteSetting

@synthesize type = _type;
@synthesize value = _value;

- (instancetype)initWithSetting:(const oa::SiteSetting&)setting {
  if ((self = [super init])) {
    _type = static_cast<NSInteger>(setting.type);
    _value = static_cast<NSInteger>(setting.value);
  }
  return self;
}

@end

namespace {

OADownloadState ToDownloadState(oa::DownloadState state) {
  switch (state) {
    case oa::DownloadState::kInProgress:
      return OADownloadStateInProgress;
    case oa::DownloadState::kComplete:
      return OADownloadStateComplete;
    case oa::DownloadState::kCancelled:
      return OADownloadStateCancelled;
    case oa::DownloadState::kInterrupted:
      return OADownloadStateInterrupted;
  }
}

class DownloadsObserverBridge : public oa::Downloads::Observer {
 public:
  explicit DownloadsObserverBridge(OADownloads* downloads)
      : downloads_(downloads) {}
  void OnDownloadsInitialized(
      const std::vector<oa::Download>& downloads) override {
    [downloads_ downloadsInitialized:downloads];
  }
  void OnDownloadCreated(const oa::Download& download,
                         oa::Page* page) override {
    [downloads_ downloadCreated:download page:page];
  }
  void OnDownloadUpdated(const oa::Download& download,
                         oa::Page* page) override {
    [downloads_ downloadUpdated:download page:page];
  }
  void OnDownloadRemoved(const std::string& id) override {
    [downloads_ downloadRemoved:id];
  }

 private:
  __weak OADownloads* downloads_;
};

}  // namespace

@implementation OADownload

@synthesize identifier = _identifier;
@synthesize state = _state;
@synthesize receivedBytes = _receivedBytes;
@synthesize totalBytes = _totalBytes;
@synthesize bytesPerSecond = _bytesPerSecond;
@synthesize remainingSeconds = _remainingSeconds;
@synthesize targetFileURL = _targetFileURL;
@synthesize sourceURL = _sourceURL;
@synthesize startTime = _startTime;
@synthesize paused = _paused;
@synthesize done = _done;
@synthesize canResume = _canResume;
@synthesize page = _page;

- (instancetype)initWithDownload:(const oa::Download&)download
                            page:(nullable OAPage*)page {
  if ((self = [super init])) {
    _page = page;
    _identifier = ToNSString(download.id);
    _state = ToDownloadState(download.state);
    _receivedBytes = download.received_bytes;
    _totalBytes = download.total_bytes;
    _bytesPerSecond = download.bytes_per_second;
    _remainingSeconds = download.remaining_seconds;
    _targetFileURL =
        download.target_path.empty()
            ? nil
            : [NSURL fileURLWithPath:ToNSString(download.target_path)];
    _sourceURL = download.source_url.empty()
                     ? nil
                     : [NSURL URLWithString:ToNSString(download.source_url)];
    _startTime = [NSDate dateWithTimeIntervalSince1970:download.start_time];
    _paused = download.is_paused;
    _done = download.is_done;
    _canResume = download.can_resume;
  }
  return self;
}

@end

@implementation OADownloads {
  NSString* _profileIdentifier;
  std::unique_ptr<DownloadsObserverBridge> _observer;
  std::unique_ptr<oa::Downloads> _downloads;
}

@synthesize delegate = _delegate;

- (instancetype)initWithProfileIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    _profileIdentifier = [identifier copy];
    _observer = std::make_unique<DownloadsObserverBridge>(self);
  }
  return self;
}

- (void)setDelegate:(nullable id<OADownloadsDelegate>)delegate {
  _delegate = delegate;
  if (delegate && !_downloads) {
    _downloads = oa::ObserveDownloads(_profileIdentifier.UTF8String ?: "",
                                      _observer.get());
  }
}

- (void)pauseDownloadWithIdentifier:(NSString*)identifier {
  if (_downloads) {
    _downloads->Pause(identifier.UTF8String ?: "");
  }
}

- (void)resumeDownloadWithIdentifier:(NSString*)identifier {
  if (_downloads) {
    _downloads->Resume(identifier.UTF8String ?: "");
  }
}

- (void)cancelDownloadWithIdentifier:(NSString*)identifier {
  if (_downloads) {
    _downloads->Cancel(identifier.UTF8String ?: "");
  }
}

- (void)removeDownloadWithIdentifier:(NSString*)identifier {
  if (_downloads) {
    _downloads->Remove(identifier.UTF8String ?: "");
  }
}

- (void)downloadsInitialized:(const std::vector<oa::Download>&)downloads {
  NSMutableArray<OADownload*>* items = [NSMutableArray array];
  for (const oa::Download& download : downloads) {
    [items addObject:[[OADownload alloc] initWithDownload:download page:nil]];
  }
  [self.delegate downloadsDidInitialize:items];
}

- (OADownload*)download:(const oa::Download&)download page:(oa::Page*)page {
  auto found = PagesByCore().find(page);
  return [[OADownload alloc]
      initWithDownload:download
                  page:found == PagesByCore().end() ? nil : found->second];
}

- (void)downloadCreated:(const oa::Download&)download page:(oa::Page*)page {
  [self.delegate downloadWasCreated:[self download:download page:page]];
}

- (void)downloadUpdated:(const oa::Download&)download page:(oa::Page*)page {
  [self.delegate downloadWasUpdated:[self download:download page:page]];
}

- (void)downloadRemoved:(const std::string&)identifier {
  [self.delegate downloadWasRemovedWithIdentifier:ToNSString(identifier)];
}

@end

namespace {

class PreferencesObserverBridge : public oa::Preferences::Observer {
 public:
  explicit PreferencesObserverBridge(OAPreferences* preferences)
      : preferences_(preferences) {}
  void OnDownloadLocationChanged() override {
    [preferences_ preferencesChanged];
  }
  void OnSearchEnginesChanged() override { [preferences_ preferencesChanged]; }
  void OnSearchSuggestEnabledChanged() override {
    [preferences_ preferencesChanged];
  }

 private:
  __weak OAPreferences* preferences_;
};

}  // namespace

@implementation OASearchEngine

@synthesize name = _name;
@synthesize keyword = _keyword;
@synthesize url = _url;
@synthesize faviconURL = _faviconURL;
@synthesize prepopulated = _prepopulated;

- (instancetype)initWithEngine:(const oa::SearchEngine&)engine {
  if ((self = [super init])) {
    _name = ToNSString(engine.name);
    _keyword = ToNSString(engine.keyword);
    _url = ToNSString(engine.url);
    _faviconURL = engine.favicon_url.empty()
                      ? nil
                      : [NSURL URLWithString:ToNSString(engine.favicon_url)];
    _prepopulated = engine.is_prepopulated;
  }
  return self;
}

@end

@implementation OAPreferences {
  NSString* _profileIdentifier;
  std::unique_ptr<PreferencesObserverBridge> _observer;
  std::unique_ptr<oa::Preferences> _preferences;
}

@synthesize delegate = _delegate;

- (instancetype)initWithProfileIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    _profileIdentifier = [identifier copy];
    _observer = std::make_unique<PreferencesObserverBridge>(self);
  }
  return self;
}

- (void)setDelegate:(nullable id<OAPreferencesDelegate>)delegate {
  _delegate = delegate;
  [self start];
}

- (void)start {
  if (!_preferences) {
    _preferences = oa::ObservePreferences(_profileIdentifier.UTF8String ?: "",
                                          _observer.get());
  }
}

- (nullable NSURL*)downloadDirectory {
  std::optional<oa::DownloadLocation> location =
      _preferences ? _preferences->GetDownloadLocation() : std::nullopt;
  return location ? [NSURL fileURLWithPath:ToNSString(location->directory)
                               isDirectory:YES]
                  : nil;
}

- (void)setDownloadDirectory:(nullable NSURL*)directory {
  [self start];
  if (directory.path) {
    _preferences->SetDownloadDirectory(directory.path.UTF8String);
  }
}

- (BOOL)asksWhereToSaveDownloads {
  std::optional<oa::DownloadLocation> location =
      _preferences ? _preferences->GetDownloadLocation() : std::nullopt;
  return location && location->asks_each_time;
}

- (void)setAsksWhereToSaveDownloads:(BOOL)asks {
  [self start];
  _preferences->SetAsksWhereToSaveDownloads(asks);
}

- (nullable NSArray<OASearchEngine*>*)searchEngines {
  std::optional<std::vector<oa::SearchEngine>> engines =
      _preferences ? _preferences->GetSearchEngines() : std::nullopt;
  if (!engines) {
    return nil;
  }
  NSMutableArray<OASearchEngine*>* result = [NSMutableArray array];
  for (const oa::SearchEngine& engine : *engines) {
    [result addObject:[[OASearchEngine alloc] initWithEngine:engine]];
  }
  return result;
}

- (nullable OASearchEngine*)defaultSearchEngine {
  std::optional<oa::SearchEngine> engine =
      _preferences ? _preferences->GetDefaultSearchEngine() : std::nullopt;
  return engine ? [[OASearchEngine alloc] initWithEngine:*engine] : nil;
}

- (void)setDefaultSearchEngineWithKeyword:(NSString*)keyword {
  [self start];
  _preferences->SetDefaultSearchEngine(keyword.UTF8String ?: "");
}

- (BOOL)searchSuggestEnabled {
  std::optional<bool> enabled =
      _preferences ? _preferences->GetSearchSuggestEnabled() : std::nullopt;
  return enabled.value_or(true);
}

- (void)setSearchSuggestEnabled:(BOOL)enabled {
  [self start];
  _preferences->SetSearchSuggestEnabled(enabled);
}

- (void)preferencesChanged {
  [self.delegate preferencesDidChange:self];
}

@end

@implementation OAAutocompleteMatch {
  oa::AutocompleteMatch _match;
}

@synthesize type = _type;
@synthesize provider = _provider;
@synthesize contents = _contents;
@synthesize matchDescription = _matchDescription;
@synthesize destinationURL = _destinationURL;
@synthesize fillIntoEdit = _fillIntoEdit;
@synthesize inlineAutocompletion = _inlineAutocompletion;
@synthesize keyword = _keyword;
@synthesize additionalInfo = _additionalInfo;

- (instancetype)initWithMatch:(const oa::AutocompleteMatch&)match {
  if ((self = [super init])) {
    _match = match;
    _type = ToNSString(match.type);
    _provider = ToNSString(match.provider);
    _contents = ToNSString(match.contents);
    _matchDescription = ToNSString(match.description);
    _destinationURL =
        match.destination_url.empty()
            ? nil
            : [NSURL URLWithString:ToNSString(match.destination_url)];
    _fillIntoEdit = ToNSString(match.fill_into_edit);
    _inlineAutocompletion = ToNSString(match.inline_autocompletion);
    _keyword = ToNSString(match.keyword);
    NSMutableDictionary<NSString*, NSString*>* info =
        [NSMutableDictionary dictionary];
    for (const auto& [key, value] : match.additional_info) {
      info[ToNSString(key)] = ToNSString(value);
    }
    _additionalInfo = info;
  }
  return self;
}

- (const oa::AutocompleteMatch&)match {
  return _match;
}

- (NSInteger)relevance {
  return _match.relevance;
}

- (BOOL)allowedToBeDefault {
  return _match.allowed_to_be_default;
}

- (BOOL)isDeletable {
  return _match.deletable;
}

- (BOOL)swapsContentsAndDescription {
  return _match.swap_contents_and_description;
}

- (BOOL)isFromKeyword {
  return _match.from_keyword;
}

- (BOOL)isFromPrevious {
  return _match.from_previous;
}

@end

namespace {

NSArray<OAAutocompleteMatch*>* ToNSArray(
    const std::vector<oa::AutocompleteMatch>& matches) {
  NSMutableArray<OAAutocompleteMatch*>* result = [NSMutableArray array];
  for (const oa::AutocompleteMatch& match : matches) {
    [result addObject:[[OAAutocompleteMatch alloc] initWithMatch:match]];
  }
  return result;
}

}  // namespace

@implementation OAAutocompleteResult

@synthesize combinedMatches = _combinedMatches;
@synthesize perProviderMatches = _perProviderMatches;

- (instancetype)initWithResult:(const oa::AutocompleteResult&)result {
  if ((self = [super init])) {
    _combinedMatches = ToNSArray(result.combined_matches);
    _perProviderMatches = ToNSArray(result.per_provider_matches);
  }
  return self;
}

@end

@implementation OAAutocomplete {
  std::unique_ptr<oa::Autocomplete> _autocomplete;
}

- (instancetype)initWithProfileIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    _autocomplete = oa::CreateAutocomplete(identifier.UTF8String ?: "");
  }
  return self;
}

- (void)startWithText:(NSString*)text
               cursorPosition:(NSUInteger)cursorPosition
    preventInlineAutocomplete:(BOOL)preventInlineAutocomplete
                   startFresh:(BOOL)startFresh
                      keyword:(nullable NSString*)keyword
                   currentURL:(nullable NSURL*)currentURL
                   completion:
                       (void (^)(OAAutocompleteResult*, BOOL))completion {
  oa::AutocompleteInput input;
  input.text = text.UTF8String ?: "";
  input.cursor_position = cursorPosition;
  input.prevent_inline_autocomplete = preventInlineAutocomplete;
  input.start_fresh = startFresh;
  input.keyword = keyword.UTF8String ?: "";
  input.current_url = currentURL.absoluteString.UTF8String ?: "";
  void (^handler)(OAAutocompleteResult*, BOOL) = [completion copy];
  _autocomplete->Start(
      input, [handler](const oa::AutocompleteResult& result, bool done) {
        handler([[OAAutocompleteResult alloc] initWithResult:result], done);
      });
}

- (void)stop {
  _autocomplete->Stop();
}

- (void)deleteMatch:(OAAutocompleteMatch*)match {
  _autocomplete->DeleteMatch(match.match);
}

@end

@implementation OAExtension

@synthesize identifier = _identifier;
@synthesize name = _name;
@synthesize extensionDescription = _extensionDescription;
@synthesize version = _version;
@synthesize enabled = _enabled;
@synthesize hasAction = _hasAction;
@synthesize fromWebstore = _fromWebstore;

- (instancetype)initWithExtension:(const oa::Extension&)extension {
  if ((self = [super init])) {
    _identifier = ToNSString(extension.id);
    _name = ToNSString(extension.name);
    _extensionDescription = ToNSString(extension.description);
    _version = ToNSString(extension.version);
    _enabled = extension.enabled;
    _hasAction = extension.has_action;
    _fromWebstore = extension.from_webstore;
  }
  return self;
}

@end

namespace {

class ExtensionsObserverBridge : public oa::Extensions::Observer {
 public:
  explicit ExtensionsObserverBridge(OAExtensions* extensions)
      : extensions_(extensions) {}
  void OnExtensionsInitialized(
      const std::vector<oa::Extension>& extensions) override {
    NSMutableArray<OAExtension*>* items = [NSMutableArray array];
    for (const oa::Extension& extension : extensions) {
      [items addObject:[[OAExtension alloc] initWithExtension:extension]];
    }
    [extensions_.target extensionsDidInitialize:items];
  }
  void OnExtensionInstalled(const oa::Extension& extension) override {
    [extensions_.target extensionWasInstalled:[[OAExtension alloc]
                                                  initWithExtension:extension]];
  }
  void OnExtensionUninstalled(const std::string& id) override {
    [extensions_.target extensionWasUninstalledWithIdentifier:ToNSString(id)];
  }
  void OnExtensionEnabled(const oa::Extension& extension) override {
    [extensions_.target
        extensionWasEnabled:[[OAExtension alloc] initWithExtension:extension]];
  }
  void OnExtensionDisabled(const oa::Extension& extension) override {
    [extensions_.target
        extensionWasDisabled:[[OAExtension alloc] initWithExtension:extension]];
  }

 private:
  __weak OAExtensions* extensions_;
};

}  // namespace

@implementation OAExtensions {
  NSString* _profileIdentifier;
  std::unique_ptr<ExtensionsObserverBridge> _observer;
  std::unique_ptr<oa::Extensions> _extensions;
}

@synthesize delegate = _delegate;

- (instancetype)initWithProfileIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    _profileIdentifier = [identifier copy];
    _observer = std::make_unique<ExtensionsObserverBridge>(self);
  }
  return self;
}

- (id<OAExtensionsDelegate>)target {
  return _delegate;
}

- (void)setDelegate:(nullable id<OAExtensionsDelegate>)delegate {
  _delegate = delegate;
  if (delegate && !_extensions) {
    _extensions = oa::ObserveExtensions(_profileIdentifier.UTF8String ?: "",
                                        _observer.get());
  }
}

- (void)setExtensionWithIdentifier:(NSString*)identifier enabled:(BOOL)enabled {
  if (_extensions) {
    _extensions->SetEnabled(identifier.UTF8String ?: "", enabled);
  }
}

- (void)uninstallExtensionWithIdentifier:(NSString*)identifier {
  if (_extensions) {
    _extensions->Uninstall(identifier.UTF8String ?: "");
  }
}

@end

@implementation OAExtensionToolbarAction

@synthesize identifier = _identifier;
@synthesize accessibleName = _accessibleName;
@synthesize tooltip = _tooltip;
@synthesize icon = _icon;
@synthesize enabled = _enabled;
@synthesize pinnedPosition = _pinnedPosition;

- (instancetype)initWithAction:(const oa::ExtensionToolbarAction&)action {
  if ((self = [super init])) {
    _identifier = ToNSString(action.id);
    _accessibleName = ToNSString(action.accessible_name);
    _tooltip = ToNSString(action.tooltip);
    _icon = (__bridge NSImage*)action.icon.get();
    _enabled = action.enabled;
    _pinnedPosition = action.pinned_position;
  }
  return self;
}

@end

namespace {

class BrowserObserverBridge : public oa::Browser::Observer {
 public:
  explicit BrowserObserverBridge(OABrowser* browser) : browser_(browser) {}
  void OnExtensionToolbarActionsChanged(
      const std::vector<oa::ExtensionToolbarAction>& actions) override {
    NSMutableArray<OAExtensionToolbarAction*>* items = [NSMutableArray array];
    for (const oa::ExtensionToolbarAction& action : actions) {
      [items
          addObject:[[OAExtensionToolbarAction alloc] initWithAction:action]];
    }
    OABrowser* browser = browser_;
    [browser.target browser:browser didUpdateExtensionToolbarActions:items];
  }
  void OnExtensionPopupOpened(const std::string& extension_id,
                              void* ns_view,
                              int width,
                              int height) override {
    OABrowser* browser = browser_;
    [browser.target browser:browser
        didOpenExtensionPopup:ToNSString(extension_id)
                         view:(__bridge NSView*)ns_view
                         size:NSMakeSize(width, height)];
  }
  void OnExtensionPopupResized(int width, int height) override {
    OABrowser* browser = browser_;
    [browser.target browser:browser
        didResizeExtensionPopup:NSMakeSize(width, height)];
  }
  void OnExtensionPopupClosed() override {
    OABrowser* browser = browser_;
    [browser.target browserDidCloseExtensionPopup:browser];
  }

 private:
  __weak OABrowser* browser_;
};

}  // namespace

@implementation OABrowser {
  __weak id<OABrowserDelegate> _delegate;
  std::unique_ptr<BrowserObserverBridge> _observer;
  std::unique_ptr<oa::Browser> _browser;
}

- (instancetype)initWithWindowIdentifier:(NSString*)windowIdentifier
                       profileIdentifier:(NSString*)profileIdentifier
                                delegate:(id<OABrowserDelegate>)delegate {
  if ((self = [super init])) {
    _delegate = delegate;
    _observer = std::make_unique<BrowserObserverBridge>(self);
    _browser =
        oa::ObserveBrowser(windowIdentifier.UTF8String ?: "",
                           profileIdentifier.UTF8String ?: "", _observer.get());
  }
  return self;
}

- (void)dealloc {
  // Before the observer it reports to.
  _browser.reset();
}

- (id<OABrowserDelegate>)target {
  return _delegate;
}

- (void)executeExtensionAction:(NSString*)identifier {
  _browser->ExecuteExtensionAction(identifier.UTF8String ?: "");
}

- (void)setExtension:(NSString*)identifier pinned:(BOOL)pinned {
  _browser->SetExtensionPinned(identifier.UTF8String ?: "", pinned);
}

- (void)showExtensionContextMenu:(NSString*)identifier {
  _browser->ShowExtensionContextMenu(identifier.UTF8String ?: "");
}

- (void)focusExtensionPopup {
  _browser->FocusExtensionPopup();
}

- (void)closeExtensionPopup {
  _browser->CloseExtensionPopup();
}

@end

@implementation OAProfile {
  NSString* _identifier;
}

@synthesize downloads = _downloads;
@synthesize preferences = _preferences;
@synthesize extensions = _extensions;

- (instancetype)initWithIdentifier:(NSString*)identifier {
  if ((self = [super init])) {
    _identifier = [identifier copy];
    _downloads = [[OADownloads alloc] initWithProfileIdentifier:identifier];
    _preferences = [[OAPreferences alloc] initWithProfileIdentifier:identifier];
    _extensions = [[OAExtensions alloc] initWithProfileIdentifier:identifier];
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

- (nullable NSArray<OASiteSetting*>*)changedSiteSettingsForURL:(NSURL*)url {
  std::optional<std::vector<oa::SiteSetting>> settings =
      oa::GetChangedSiteSettings(_identifier.UTF8String ?: "",
                                 url.absoluteString.UTF8String ?: "");
  if (!settings) {
    return nil;
  }
  NSMutableArray<OASiteSetting*>* result = [NSMutableArray array];
  for (const oa::SiteSetting& setting : *settings) {
    [result addObject:[[OASiteSetting alloc] initWithSetting:setting]];
  }
  return result;
}

- (OAAutocomplete*)makeAutocomplete {
  return [[OAAutocomplete alloc] initWithProfileIdentifier:_identifier];
}

- (OABrowser*)browserInWindow:(NSString*)windowIdentifier
                     delegate:(id<OABrowserDelegate>)delegate {
  return [[OABrowser alloc] initWithWindowIdentifier:windowIdentifier
                                   profileIdentifier:_identifier
                                            delegate:delegate];
}

- (void)setSiteSetting:(NSInteger)type to:(NSInteger)value forURL:(NSURL*)url {
  oa::SetSiteSetting(_identifier.UTF8String ?: "",
                     url.absoluteString.UTF8String ?: "",
                     static_cast<oa::SiteSettingType>(type),
                     static_cast<oa::SiteSettingValue>(value));
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
