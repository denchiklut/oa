#ifndef OA_PUBLIC_ENGINE_H_
#define OA_PUBLIC_ENGINE_H_

#include <functional>
#include <memory>
#include <string>

#include "oa/public/page.h"

namespace oa {

using ReadyCallback = void (*)(void* context);

// Runs the browser process until the app quits. `ready` runs once, between
// Chromium's initialization and its run loop.
int RunEngine(int argc, const char** argv, ReadyCallback ready, void* context);

// Loads the profile if needed, then creates a page in `window_id`'s Browser
// for it, in the background and without a load. `completion` gets null if the
// engine isn't running or the profile can't load.
void CreatePage(const std::string& window_id,
                const std::string& profile_id,
                Page::Observer* observer,
                std::function<void(std::unique_ptr<Page>)> completion);

// Binds the app's NSWindow to `window_id` once; a later call is ignored.
void AttachWindow(const std::string& window_id, void* ns_window);
// Drops every page of `window_id`'s Browsers, which then close.
void CloseWindow(const std::string& window_id);

void QuitEngine();

}  // namespace oa

#endif  // OA_PUBLIC_ENGINE_H_
