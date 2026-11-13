// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_EXTENSION_DIALOGS_IMPL_H_
#define OA_BROWSER_UI_EXTENSION_DIALOGS_IMPL_H_

namespace oa {

// Makes Chrome ask the app, through the page, before it installs or removes
// an extension, as ArcCore's replacements for Chrome's two dialogs do, and
// keeps Chrome from showing anything once an install ends. Call before the
// browser starts.
void InstallExtensionDialogs();

}  // namespace oa

#endif  // OA_BROWSER_UI_EXTENSION_DIALOGS_IMPL_H_
