#ifndef OA_PUBLIC_ENGINE_H_
#define OA_PUBLIC_ENGINE_H_

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "oa/public/page.h"

namespace oa {

using ReadyCallback = void (*)(void* context);

// Runs the browser process until the app quits. `ready` runs once, between
// Chromium's initialization and its run loop.
int RunEngine(int argc, const char** argv, ReadyCallback ready, void* context);

// Loads the profile if needed, then creates a page in `window_id`'s Browser
// for it, in the background and without a load, or with the history of the
// closed tab Chrome recorded under `restorable_session_id` and `restored`.
// `completion` gets null if the engine isn't running or the profile can't load.
void CreatePage(
    const std::string& window_id,
    const std::string& profile_id,
    std::optional<int32_t> restorable_session_id,
    Page::Observer* observer,
    std::function<void(std::unique_ptr<Page> page, bool restored)> completion);

// Binds the app's NSWindow to `window_id` once; a later call is ignored.
void AttachWindow(const std::string& window_id, void* ns_window);
// Drops every page of `window_id`'s Browsers, which then close.
void CloseWindow(const std::string& window_id);
// Runs the beforeunload handler of each page of `window_id`'s Browsers in tab
// strip order, as Chrome's shutdown does, and stops at the first that keeps its
// page. Every page stays.
void AskToLeaveWindow(const std::string& window_id,
                      std::function<void(bool leave)> completion);

void QuitEngine();

}  // namespace oa

#endif  // OA_PUBLIC_ENGINE_H_
