// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/context_menu_impl.h"

#include <optional>
#include <string>

#include "base/containers/fixed_flat_set.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/renderer_context_menu/render_view_context_menu.h"
#include "content/public/browser/context_menu_params.h"
#include "ui/menus/simple_menu_model.h"

namespace oa {
namespace {

constexpr auto kHiddenCommands = base::MakeFixedFlatSet<int>({
    IDC_PRINT,
    IDC_ROUTE_MEDIA,
    IDC_SEND_TAB_TO_SELF,
    IDC_LIVE_CAPTION,
    IDC_CONTEXT_COMPOSE,
    IDC_CONTENT_CONTEXT_OPENLINKOFFTHERECORD,
    IDC_CONTENT_CONTEXT_OPENLINK_ISOLATED,
    IDC_CONTENT_CONTEXT_OPENLINKINPROFILE,
    IDC_CONTENT_CONTEXT_OPENLINKBOOKMARKAPP,
    IDC_CONTENT_CONTEXT_OPENLINKSPLITVIEW,
    IDC_CONTENT_CONTEXT_ADD_LINK_TO_READING_LIST,
    IDC_CONTENT_CONTEXT_INSPECTELEMENT,
    IDC_CONTENT_CONTEXT_TRANSLATE,
    IDC_CONTENT_CONTEXT_PARTIAL_TRANSLATE,
    IDC_CONTENT_CONTEXT_PICTUREINPICTURE,
    IDC_CONTENT_CONTEXT_DICTATION,
    IDC_CONTENT_CONTEXT_SPELLING_TOGGLE,
    IDC_CONTENT_CONTEXT_EXIT_FULLSCREEN,
    IDC_CONTENT_CONTEXT_GENERATE_QR_CODE,
    IDC_CONTENT_CONTEXT_SHARING_SUBMENU,
    IDC_CONTENT_CONTEXT_OPEN_IN_READING_MODE,
    IDC_CONTENT_CONTEXT_LISTEN_TO_THIS_PAGE,
    IDC_CONTENT_CONTEXT_LENS_REGION_SEARCH,
    IDC_CONTENT_CONTEXT_WEB_REGION_SEARCH,
    IDC_CONTENT_CONTEXT_LENS_OVERLAY,
    IDC_CONTENT_CONTEXT_SEARCHLENSFORIMAGE,
    IDC_CONTENT_CONTEXT_SEARCHLENSFORVIDEOFRAME,
    IDC_CONTENT_CONTEXT_GLIC,
    IDC_CONTENT_CONTEXT_GLICSHAREIMAGE,
    IDC_CONTENT_CONTEXT_GLIC_SMART_SUGGESTION,
    IDC_CONTENT_CONTEXT_ARCHIVE_GLIC,
    IDC_CONTENT_CONTEXT_RELOAD_GLIC,
    IDC_CONTENT_CONTEXT_ASK_GOOGLE_ABOUT_THIS_PAGE,
    IDC_CONTENT_CONTEXT_CONTEXTUAL_TASKS_SUBMENU,
    IDC_CONTENT_CONTEXT_SAVE_TO_MEMORY_BANKS,
    IDC_CONTENT_CONTEXT_ACCESSIBILITY_LABELS,
    IDC_CONTENT_CONTEXT_ACCESSIBILITY_LABELS_TOGGLE,
    IDC_CONTENT_CONTEXT_ACCESSIBILITY_LABELS_TOGGLE_ONCE,
    IDC_CONTENT_CONTEXT_AUTOFILL_FALLBACK_AT_MEMORY,
    IDC_CONTENT_CONTEXT_AUTOFILL_FALLBACK_PASSWORDS_IMPORT_PASSWORDS,
    IDC_CONTENT_CONTEXT_AUTOFILL_FALLBACK_PASSWORDS_SELECT_PASSWORD,
    IDC_CONTENT_CONTEXT_AUTOFILL_FALLBACK_PASSWORDS_SUGGEST_PASSWORD,
    IDC_CONTENT_CONTEXT_AUTOFILL_FALLBACK_PASSWORDS_USE_PASSKEY_FROM_ANOTHER_DEVICE,
    IDC_CONTENT_CONTEXT_AUTOFILL_FEEDBACK,
    IDC_CONTENT_CONTEXT_SHOWALLSAVEDPASSWORDS,
    IDC_CONTENT_CONTEXT_GENERATEPASSWORD,
    IDC_CONTENT_CONTEXT_USE_PASSKEY_FROM_ANOTHER_DEVICE,
});

// Chrome keeps the end of the range to its menu code
// (render_view_context_menu.cc).
constexpr int kOpenLinkInProfileLast = IDC_OPEN_LINK_IN_PROFILE_FIRST + 99;

bool IsHidden(int command_id) {
  return kHiddenCommands.contains(command_id) ||
         (command_id >= IDC_OPEN_LINK_IN_PROFILE_FIRST &&
          command_id <= kOpenLinkInProfileLast);
}

// Items are removed, not hidden: Chrome's Cocoa menu keeps the separators
// around a hidden item.
void EditModel(const content::ContextMenuParams& params,
               ui::SimpleMenuModel* model) {
  for (size_t index = model->GetItemCount(); index-- > 0;) {
    if (model->GetTypeAt(index) != ui::MenuModel::TYPE_SEPARATOR &&
        IsHidden(model->GetCommandIdAt(index))) {
      model->RemoveItemAt(index);
    }
  }
  // As Arc: the search for selected text leads the menu, ahead of Copy and
  // of spelling suggestions; on a link it stays where Chrome puts it.
  if (params.selection_text.empty() || !params.link_url.is_empty()) {
    return;
  }
  const std::optional<size_t> search =
      model->GetIndexOfCommandId(IDC_CONTENT_CONTEXT_SEARCHWEBFOR);
  if (search && *search > 0) {
    const std::u16string label = model->GetLabelAt(*search);
    model->RemoveItemAt(*search);
    model->InsertItemAt(0, IDC_CONTENT_CONTEXT_SEARCHWEBFOR, label);
  }
}

}  // namespace

void InstallContextMenuEditor() {
  RenderViewContextMenu::SetModelEditorForEmbedder(&EditModel);
}

}  // namespace oa
