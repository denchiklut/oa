// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_BROWSER_BROWSER_IMPL_H_
#define OA_BROWSER_BROWSER_IMPL_H_

#include <string>

#include "oa/public/browser.h"

class Profile;

namespace oa {

// The app's observer of `window_id`'s Browser in `profile`, if it has one.
Browser::Observer* FindBrowserObserver(const std::string& window_id,
                                       Profile* profile);

}  // namespace oa

#endif  // OA_BROWSER_BROWSER_IMPL_H_
