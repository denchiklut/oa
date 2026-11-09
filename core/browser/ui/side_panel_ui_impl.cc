// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/side_panel_ui_impl.h"

#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"

namespace oa {

SidePanelUIImpl::SidePanelUIImpl(BrowserWindowInterface* browser)
    : scoped_unowned_user_data_(browser->GetUnownedUserDataHost(), *this) {}

SidePanelUIImpl::~SidePanelUIImpl() = default;

void SidePanelUIImpl::Show(SidePanelEntryId entry_id,
                           std::optional<SidePanelOpenTrigger> open_trigger,
                           bool suppress_animations) {}

void SidePanelUIImpl::Show(SidePanelEntryKey entry_key,
                           std::optional<SidePanelOpenTrigger> open_trigger,
                           bool suppress_animations) {}

void SidePanelUIImpl::ShowFrom(
    SidePanelEntryKey entry_key,
    gfx::Rect starting_bounds_in_browser_coordinates) {}

void SidePanelUIImpl::Close(SidePanelEntryHideReason hide_reason,
                            bool suppress_animations) {}

void SidePanelUIImpl::Toggle(SidePanelEntryKey key,
                             SidePanelOpenTrigger open_trigger) {}

std::optional<SidePanelEntryId> SidePanelUIImpl::GetCurrentEntryId() const {
  return std::nullopt;
}

int SidePanelUIImpl::GetCurrentEntryDefaultContentWidth() const {
  return 0;
}

bool SidePanelUIImpl::IsSidePanelShowing() const {
  return false;
}

bool SidePanelUIImpl::IsSidePanelEntryShowing(
    const SidePanelEntryKey& entry_key) const {
  return false;
}

bool SidePanelUIImpl::IsSidePanelEntryShowing(
    const SidePanelEntryKey& entry_key,
    bool for_tab) const {
  return false;
}

base::CallbackListSubscription SidePanelUIImpl::RegisterSidePanelShown(
    ShownCallback callback) {
  return shown_callbacks_.Add(std::move(callback));
}

void SidePanelUIImpl::OnActiveTabChanged(content::WebContents* old_contents,
                                         content::WebContents* new_contents,
                                         bool tab_removed_for_deletion) {}

content::WebContents* SidePanelUIImpl::GetWebContentsForTest(
    SidePanelEntryId id) {
  return nullptr;
}

void SidePanelUIImpl::DisableAnimationsForTesting() {}

void SidePanelUIImpl::SetNoDelaysForTesting(bool no_delays_for_testing) {}

}  // namespace oa
