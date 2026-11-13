// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_IMAGE_HANDLE_H_
#define OA_BROWSER_IMAGE_HANDLE_H_

#import <AppKit/AppKit.h>

#include <memory>

namespace oa {

// An NSImage for a public struct, which can't name one: retained until the
// last copy goes.
inline std::shared_ptr<void> ToImageHandle(NSImage* image) {
  if (!image) {
    return nullptr;
  }
  return std::shared_ptr<void>((__bridge_retained void*)image,
                               [](void* retained) { CFRelease(retained); });
}

}  // namespace oa

#endif  // OA_BROWSER_IMAGE_HANDLE_H_
