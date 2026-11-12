// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_CONTEXT_MENU_IMPL_H_
#define OA_BROWSER_UI_CONTEXT_MENU_IMPL_H_

namespace oa {

// Makes every page's context menu Chrome's own, as Arc's is, without the
// items that need Chrome's views or a feature the app doesn't have yet. Call
// before the browser starts.
void InstallContextMenuEditor();

}  // namespace oa

#endif  // OA_BROWSER_UI_CONTEXT_MENU_IMPL_H_
