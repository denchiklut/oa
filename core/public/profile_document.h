// Copyright 2026 The Oa Authors
#ifndef OA_PUBLIC_PROFILE_DOCUMENT_H_
#define OA_PUBLIC_PROFILE_DOCUMENT_H_

#include <functional>
#include <optional>
#include <string>

#include "oa/public/profiles.h"

namespace oa {

void LoadProfileDocument(
    const std::string& profile_id,
    BrowserContextType type,
    const std::string& url,
    std::function<void(std::string, int, std::optional<std::string>)> done);

}  // namespace oa

#endif
