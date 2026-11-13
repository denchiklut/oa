// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#ifndef OA_PUBLIC_EXTENSIONS_H_
#define OA_PUBLIC_EXTENSIONS_H_

#include <memory>
#include <string>
#include <vector>

// A profile's extensions as Chromium installs and runs them, in the shape of
// ArcCore's browser context extensions and its extension info. No Chromium
// headers here.

namespace oa {

struct Extension {
  std::string id;
  std::string name;
  std::string description;
  std::string version;
  bool enabled = false;
  bool has_action = false;
  bool from_webstore = false;
};

class Extensions {
 public:
  // Every call is posted, as ArcCore posts its delegate's.
  class Observer {
   public:
    // Once, when the profile's extension system is ready.
    virtual void OnExtensionsInitialized(
        const std::vector<Extension>& extensions) = 0;
    // Also for an update, which replaces the one with its id.
    virtual void OnExtensionInstalled(const Extension& extension) = 0;
    virtual void OnExtensionUninstalled(const std::string& id) = 0;
    virtual void OnExtensionEnabled(const Extension& extension) = 0;
    virtual void OnExtensionDisabled(const Extension& extension) = 0;

   protected:
    virtual ~Observer() = default;
  };

  virtual ~Extensions() = default;

  virtual void SetEnabled(const std::string& id, bool enabled) = 0;
  // Without asking; Chromium's own removal paths ask through the page.
  virtual void Uninstall(const std::string& id) = 0;
};

// Loads the app profile `profile_id` if needed, then reports its extensions to
// `observer` until the result is destroyed.
std::unique_ptr<Extensions> ObserveExtensions(const std::string& profile_id,
                                              Extensions::Observer* observer);

}  // namespace oa

#endif  // OA_PUBLIC_EXTENSIONS_H_
