// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include "oa/browser/ui/sad_tab_impl.h"

#include "oa/browser/page_impl.h"

namespace oa {

namespace {

Crash ToCrash(SadTabKind kind) {
  switch (kind) {
    case SAD_TAB_KIND_OOM:
      return Crash::kOutOfMemory;
    case SAD_TAB_KIND_KILLED:
      return Crash::kKilled;
    default:
      return Crash::kCrashed;
  }
}

}  // namespace

// static
void SadTabImpl::InstallFactory() {
  SadTab::SetFactoryForEmbedder(&SadTabImpl::Create);
}

// static
std::unique_ptr<SadTab> SadTabImpl::Create(content::WebContents* web_contents,
                                           SadTabKind kind) {
  return std::make_unique<SadTabImpl>(web_contents, kind);
}

SadTabImpl::SadTabImpl(content::WebContents* web_contents, SadTabKind kind)
    : SadTab(web_contents, kind) {
  if (PageImpl* page = PageImpl::FromWebContents(web_contents)) {
    page->SetCrash(ToCrash(kind));
  }
}

SadTabImpl::~SadTabImpl() = default;

}  // namespace oa
