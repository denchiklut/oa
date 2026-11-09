// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_SIDE_PANEL_UI_IMPL_H_
#define OA_BROWSER_UI_SIDE_PANEL_UI_IMPL_H_

#include <optional>

#include "base/callback_list.h"
#include "chrome/browser/ui/side_panel/side_panel_ui.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class BrowserWindowInterface;

namespace oa {

// The side panel Chrome's tab features expect every Browser to have. Chrome's
// own comes with its views, and some tab features CHECK for one, for example
// when the active tab leaves its strip. The app has no Chrome side panel, so
// this one never shows anything.
class SidePanelUIImpl : public SidePanelUI {
 public:
  // Registers itself as `browser`'s side panel while it lives.
  explicit SidePanelUIImpl(BrowserWindowInterface* browser);
  SidePanelUIImpl(const SidePanelUIImpl&) = delete;
  SidePanelUIImpl& operator=(const SidePanelUIImpl&) = delete;
  ~SidePanelUIImpl() override;

  // SidePanelUI:
  void Show(SidePanelEntryId entry_id,
            std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override;
  void Show(SidePanelEntryKey entry_key,
            std::optional<SidePanelOpenTrigger> open_trigger,
            bool suppress_animations) override;
  void ShowFrom(SidePanelEntryKey entry_key,
                gfx::Rect starting_bounds_in_browser_coordinates) override;
  void Close(SidePanelEntryHideReason hide_reason,
             bool suppress_animations) override;
  void Toggle(SidePanelEntryKey key,
              SidePanelOpenTrigger open_trigger) override;
  std::optional<SidePanelEntryId> GetCurrentEntryId() const override;
  int GetCurrentEntryDefaultContentWidth() const override;
  bool IsSidePanelShowing() const override;
  bool IsSidePanelEntryShowing(
      const SidePanelEntryKey& entry_key) const override;
  bool IsSidePanelEntryShowing(const SidePanelEntryKey& entry_key,
                               bool for_tab) const override;
  base::CallbackListSubscription RegisterSidePanelShown(
      ShownCallback callback) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          bool tab_removed_for_deletion) override;
  content::WebContents* GetWebContentsForTest(SidePanelEntryId id) override;
  void DisableAnimationsForTesting() override;
  void SetNoDelaysForTesting(bool no_delays_for_testing) override;

 private:
  base::RepeatingCallbackList<void()> shown_callbacks_;
  ui::ScopedUnownedUserData<SidePanelUI> scoped_unowned_user_data_;
};

}  // namespace oa

#endif  // OA_BROWSER_UI_SIDE_PANEL_UI_IMPL_H_
