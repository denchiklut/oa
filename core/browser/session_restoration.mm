// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/session_restoration.h"

#include <memory>
#include <set>

#include "base/callback_list.h"
#include "base/functional/bind.h"
#include "base/no_destructor.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/sessions/session_restore.h"
#include "components/sessions/core/session_id.h"
#include "content/public/browser/web_contents.h"
#include "oa/browser/browser_impl.h"
#include "oa/browser/window_browser.h"

namespace oa {
namespace {

const void* const kLastSessionIDKey = &kLastSessionIDKey;

struct LastSessionIDData : public base::SupportsUserData::Data {
  explicit LastSessionIDData(int32_t id) : id(id) {}
  const int32_t id;
};

struct State {
  std::multiset<std::string> expecting;
  std::set<Profile*> restoring;
  std::set<Profile*> finished;
  bool windows_restored = false;
  bool hand_off_posted = false;
  base::CallbackListSubscription restored_subscription;
};

State& GetState() {
  static base::NoDestructor<State> state;
  return *state;
}

void HandOff() {
  State& state = GetState();
  state.hand_off_posted = false;
  if (SessionRestoration::IsWaiting()) {
    return;
  }
  HandOffRestoredPages();
  if (state.windows_restored) {
    WindowBrowser::CloseUnclaimed();
  }
}

// From a task: Chrome reports the restore from inside it.
void HandOffIfDone() {
  State& state = GetState();
  if (SessionRestoration::IsWaiting() || state.hand_off_posted) {
    return;
  }
  state.hand_off_posted = true;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&HandOff));
}

void OnTabRestored(content::WebContents* contents, SessionID id) {
  contents->SetUserData(kLastSessionIDKey,
                        std::make_unique<LastSessionIDData>(id.id()));
}

void OnSessionRestored(Profile* profile, int /*tab_count*/) {
  State& state = GetState();
  state.finished.insert(profile);
  state.restoring.erase(profile);
  HandOffIfDone();
}

}  // namespace

// static
void SessionRestoration::Install() {
  SessionRestore::SetRestoredTabCallbackForEmbedder(
      base::BindRepeating(&OnTabRestored));
  GetState().restored_subscription =
      SessionRestore::RegisterOnSessionRestoredCallback(
          base::BindRepeating(&OnSessionRestored));
}

// static
void SessionRestoration::Expect(const std::string& profile_id) {
  GetState().expecting.insert(profile_id);
}

// static
void SessionRestoration::Resolve(const std::string& profile_id,
                                 Profile* profile) {
  State& state = GetState();
  auto it = state.expecting.find(profile_id);
  if (it != state.expecting.end()) {
    state.expecting.erase(it);
  }
  // Chrome keeps a finished restore around for a moment.
  if (profile && !state.finished.contains(profile) &&
      SessionRestore::IsRestoring(profile)) {
    state.restoring.insert(profile);
  }
  HandOffIfDone();
}

// static
void SessionRestoration::OnBrowserGone() {
  State& state = GetState();
  std::erase_if(state.restoring, [](Profile* profile) {
    return !SessionRestore::IsRestoring(profile);
  });
  HandOffIfDone();
}

// static
bool SessionRestoration::IsWaiting() {
  const State& state = GetState();
  return !state.expecting.empty() || !state.restoring.empty();
}

// static
std::optional<int32_t> SessionRestoration::LastSessionID(
    content::WebContents* contents) {
  auto* data =
      static_cast<LastSessionIDData*>(contents->GetUserData(kLastSessionIDKey));
  return data ? std::optional(data->id) : std::nullopt;
}

// static
void SessionRestoration::FinishedRestoringWindows() {
  GetState().windows_restored = true;
  if (!IsWaiting()) {
    WindowBrowser::CloseUnclaimed();
  }
}

}  // namespace oa
