// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_UI_SAD_TAB_IMPL_H_
#define OA_BROWSER_UI_SAD_TAB_IMPL_H_

#include <memory>

#include "chrome/browser/ui/sad_tab.h"

namespace content {
class WebContents;
}

namespace oa {

// The sad tab of a page whose renderer is gone, in place of Chrome's, which
// needs a BrowserView. It draws nothing: the app shows its own crashed page
// from the page's renderer events, as Arc's does.
class SadTabImpl : public SadTab {
 public:
  // Makes SadTab::Create() return a SadTabImpl for every crashed tab. Call
  // before the browser starts.
  static void InstallFactory();

  SadTabImpl(content::WebContents* web_contents, SadTabKind kind);
  SadTabImpl(const SadTabImpl&) = delete;
  SadTabImpl& operator=(const SadTabImpl&) = delete;
  ~SadTabImpl() override;

 private:
  static std::unique_ptr<SadTab> Create(content::WebContents* web_contents,
                                        SadTabKind kind);
};

}  // namespace oa

#endif  // OA_BROWSER_UI_SAD_TAB_IMPL_H_
