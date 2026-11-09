#include "oa/public/engine.h"

#import <AppKit/AppKit.h>
#import <objc/message.h>

#include <memory>
#include <string>
#include <utility>
#include <variant>

#include "base/base_switches.h"
#include "base/command_line.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/memory/raw_ptr.h"
#include "base/no_destructor.h"
#include "base/sampling_heap_profiler/poisson_allocation_sampler.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "chrome/app/chrome_main_delegate.h"
#include "chrome/app/chrome_main_mac.h"
#include "chrome/app/startup_timestamps.h"
#include "chrome/browser/chrome_browser_application_mac.h"
#include "chrome/browser/chrome_browser_main_mac.h"
#include "chrome/browser/devtools/chrome_devtools_manager_delegate.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/ui/startup/startup_browser_creator.h"
#include "chrome/browser/ui/toasts/toast_features.h"
#include "chrome/common/chrome_constants.h"
#include "chrome/common/chrome_switches.h"
#include "components/keep_alive_registry/keep_alive_types.h"
#include "components/keep_alive_registry/scoped_keep_alive.h"
#include "components/lens/lens_features.h"
#include "components/security_interstitials/core/features.h"
#include "content/public/app/content_main.h"
#include "content/public/browser/browser_main_runner.h"
#include "content/public/common/main_function_params.h"
#include "oa/browser/page_impl.h"
#include "oa/browser/profile_services.h"
#include "oa/browser/ui/browser_window_impl.h"
#include "oa/browser/ui/permission_prompt_impl.h"
#include "oa/browser/window_browser.h"

// The app's NSApplication: Chrome's event handling without its AppController.
@interface OAApplication : BrowserCrApplication
@end

@implementation OAApplication

- (void)terminate:(id)sender {
  struct objc_super target = {self, [NSApplication class]};
  ((void (*)(struct objc_super*, SEL, id))objc_msgSendSuper)(&target, _cmd,
                                                             sender);
}

- (void)cancelTerminate:(id)sender {
}

@end

namespace oa {
namespace {

struct EngineState {
  ReadyCallback ready = nullptr;
  raw_ptr<void> ready_context = nullptr;
  bool running = false;
  std::unique_ptr<ScopedKeepAlive> keep_alive;
};

EngineState& State() {
  static base::NoDestructor<EngineState> state;
  return *state;
}

void DisableFeature(base::CommandLine& command_line,
                    const base::Feature& feature) {
  std::string disabled =
      command_line.GetSwitchValueASCII(switches::kDisableFeatures);
  if (!disabled.empty()) {
    disabled += ",";
  }
  command_line.AppendSwitchASCII(switches::kDisableFeatures,
                                 disabled + feature.name);
}

class MainDelegate : public ChromeMainDelegate {
 public:
  using ChromeMainDelegate::ChromeMainDelegate;

 protected:
  std::variant<int, content::MainFunctionParams> RunProcess(
      const std::string& process_type,
      content::MainFunctionParams main_function_params) override {
    if (!process_type.empty()) {
      return ChromeMainDelegate::RunProcess(process_type,
                                            std::move(main_function_params));
    }
    State().keep_alive = std::make_unique<ScopedKeepAlive>(
        KeepAliveOrigin::APP_CONTROLLER, KeepAliveRestartOption::DISABLED);
    std::unique_ptr<content::BrowserMainRunner> runner =
        content::BrowserMainRunner::Create();
    int exit_code = runner->Initialize(std::move(main_function_params));
    if (exit_code >= 0) {
      State().keep_alive.reset();
      return exit_code;
    }
    State().running = true;
    if (State().ready) {
      State().ready(State().ready_context.get());
    }
    exit_code = runner->Run();
    State().running = false;
    PageImpl::CloseAll();
    WindowBrowser::CloseAll();
    runner->Shutdown();
    return exit_code;
  }
};

}  // namespace

int RunEngine(int argc, const char** argv, ReadyCallback ready, void* context) {
  State().ready = ready;
  State().ready_context = context;
  StartupTimestamps timestamps{.exe_entry_point_ticks = base::TimeTicks::Now()};

  base::CommandLine::Init(argc, argv);
  base::CommandLine& command_line = *base::CommandLine::ForCurrentProcess();
  // Startup loads only Chrome's initial profile; the app's profiles load on
  // demand (profile_services).
  if (!command_line.HasSwitch(switches::kProfileDirectory)) {
    command_line.AppendSwitchASCII(switches::kProfileDirectory,
                                   chrome::kInitialProfile);
  }
  // Chrome UI that CHECKs without a BrowserView.
  DisableFeature(command_line,
                 security_interstitials::features::kHttpsFirstDialogUi);
  for (const base::Feature* toast :
       {&toast_features::kLinkCopiedToast, &toast_features::kImageCopiedToast,
        &toast_features::kVideoFrameCopiedToast,
        &toast_features::kLinkToHighlightCopiedToast,
        &toast_features::kReadingListToast, &toast_features::kTranslateToast}) {
    DisableFeature(command_line, *toast);
  }
  DisableFeature(command_line, lens::features::kLensStandalone);
  DisableFeature(command_line, lens::features::kLensOverlay);

  ChromeBrowserMainPartsMac::DisableAppControllerForEmbedder();
  StartupBrowserCreator::SetLoadProfileWithoutWindowForEmbedder();
  BrowserWindowImpl::InstallFactory();
  PermissionPromptImpl::InstallFactory();

  [OAApplication sharedApplication];
  SetUpBundleOverrides();
  base::PoissonAllocationSampler::Init();

  MainDelegate delegate(timestamps);
  content::ContentMainParams params(&delegate);
  params.argc = argc;
  params.argv = argv;
  return content::ContentMain(std::move(params));
}

void CreatePage(const std::string& window_id,
                const std::string& profile_id,
                Page::Observer* observer,
                std::function<void(std::unique_ptr<Page>)> completion) {
  if (!State().running) {
    completion(nullptr);
    return;
  }
  LoadBrowserProfile(
      profile_id,
      base::BindOnce(
          [](std::string window_id, Page::Observer* observer,
             std::function<void(std::unique_ptr<Page>)> completion,
             Profile* profile) {
            if (!State().running || !profile) {
              completion(nullptr);
              return;
            }
            WindowBrowser* browser =
                WindowBrowser::GetOrCreate(window_id, profile);
            if (!browser) {
              completion(nullptr);
              return;
            }
            completion(PageImpl::Create(browser, observer));
          },
          window_id, base::Unretained(observer), std::move(completion)));
}

void AttachWindow(const std::string& window_id, void* ns_window) {
  WindowBrowser::AttachWindow(window_id, ns_window);
}

void CloseWindow(const std::string& window_id) {
  WindowBrowser::CloseWindow(window_id);
}

void QuitEngine() {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce([] {
        browser_shutdown::SetTryingToQuit(true);
        ChromeDevToolsManagerDelegate::AllowBrowserToClose();
        WindowBrowser::CloseAll();
        State().keep_alive.reset();
      }));
}

}  // namespace oa
