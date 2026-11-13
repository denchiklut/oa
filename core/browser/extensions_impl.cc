// Copyright 2026 The Oa Authors
// Use of this source code is governed by the license in the LICENSE file.

#include <utility>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/one_shot_event.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/profiles/profile.h"
#include "extensions/browser/disable_reason.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_registrar.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_system.h"
#include "extensions/browser/ui_util.h"
#include "extensions/browser/uninstall_reason.h"
#include "extensions/common/extension.h"
#include "extensions/common/extension_set.h"
#include "extensions/common/manifest_handlers/description_info.h"
#include "oa/browser/profile_services.h"
#include "oa/public/extensions.h"

namespace oa {
namespace {

// Oa's own: what chrome://extensions lists. Arc's filter isn't traced; its
// menu leaves out the component extensions, as this does.
bool IsListed(const extensions::Extension* extension) {
  return extensions::ui_util::ShouldDisplayInExtensionSettings(*extension);
}

Extension ToExtension(Profile* profile,
                      const extensions::Extension* extension,
                      bool enabled) {
  Extension result;
  result.id = extension->id();
  result.name = extension->name();
  result.description = extensions::DescriptionInfo::GetDescription(*extension);
  result.version = extension->VersionString();
  result.enabled = enabled;
  result.has_action =
      extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(
          *extension) != nullptr;
  result.from_webstore = extension->from_webstore();
  return result;
}

// As ArcCore's: an observer of the profile's ExtensionRegistry, beside
// Chrome's own extension service.
class ExtensionsImpl : public Extensions,
                       public extensions::ExtensionRegistryObserver {
 public:
  ExtensionsImpl(const std::string& profile_id, Extensions::Observer* observer)
      : observer_(observer) {
    LoadBrowserProfile(profile_id, base::BindOnce(&ExtensionsImpl::Start,
                                                  weak_factory_.GetWeakPtr()));
  }

  // Extensions:
  void SetEnabled(const std::string& id, bool enabled) override {
    if (!profile_) {
      return;
    }
    extensions::ExtensionRegistrar* registrar =
        extensions::ExtensionRegistrar::Get(profile_.get());
    if (enabled) {
      registrar->EnableExtension(id);
    } else {
      registrar->DisableExtension(
          id, {extensions::disable_reason::DISABLE_USER_ACTION});
    }
  }
  void Uninstall(const std::string& id) override {
    if (profile_) {
      extensions::ExtensionRegistrar::Get(profile_.get())
          ->UninstallExtension(id, extensions::UNINSTALL_REASON_USER_INITIATED,
                               nullptr);
    }
  }

  // extensions::ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext* browser_context,
                         const extensions::Extension* extension) override {
    PostExtension(extension, true, &Extensions::Observer::OnExtensionEnabled);
  }
  void OnExtensionUnloaded(
      content::BrowserContext* browser_context,
      const extensions::Extension* extension,
      extensions::UnloadedExtensionReason reason) override {
    PostExtension(extension, false, &Extensions::Observer::OnExtensionDisabled);
  }
  void OnExtensionInstalled(content::BrowserContext* browser_context,
                            const extensions::Extension* extension,
                            bool is_update) override {
    PostExtension(extension, IsEnabled(extension->id()),
                  &Extensions::Observer::OnExtensionInstalled);
  }
  void OnExtensionUninstalled(content::BrowserContext* browser_context,
                              const extensions::Extension* extension,
                              extensions::UninstallReason reason) override {
    if (!IsListed(extension)) {
      return;
    }
    Post(base::BindOnce(
        [](std::string id, Extensions::Observer* observer) {
          observer->OnExtensionUninstalled(id);
        },
        extension->id()));
  }
  void OnShutdown(extensions::ExtensionRegistry* registry) override {
    observation_.Reset();
  }

 private:
  void Start(Profile* profile) {
    if (!profile) {
      return;
    }
    profile_ = profile->GetWeakPtr();
    extensions::ExtensionSystem::Get(profile)->ready().Post(
        FROM_HERE,
        base::BindOnce(&ExtensionsImpl::OnReady, weak_factory_.GetWeakPtr()));
  }

  void OnReady() {
    if (!profile_) {
      return;
    }
    extensions::ExtensionRegistry* registry =
        extensions::ExtensionRegistry::Get(profile_.get());
    observation_.Observe(registry);
    std::vector<Extension> result;
    for (const auto& extension : registry->GenerateInstalledExtensionsSet()) {
      if (IsListed(extension.get())) {
        result.push_back(ToExtension(profile_.get(), extension.get(),
                                     IsEnabled(extension->id())));
      }
    }
    Post(base::BindOnce(
        [](std::vector<Extension> extensions, Extensions::Observer* observer) {
          observer->OnExtensionsInitialized(extensions);
        },
        std::move(result)));
  }

  bool IsEnabled(const std::string& id) {
    return extensions::ExtensionRegistry::Get(profile_.get())
        ->enabled_extensions()
        .Contains(id);
  }

  void PostExtension(const extensions::Extension* extension,
                     bool enabled,
                     void (Extensions::Observer::*event)(const Extension&)) {
    if (!profile_ || !IsListed(extension)) {
      return;
    }
    Post(base::BindOnce(
        [](Extension extension,
           void (Extensions::Observer::*event)(const Extension&),
           Extensions::Observer* observer) { (observer->*event)(extension); },
        ToExtension(profile_.get(), extension, enabled), event));
  }

  void Post(base::OnceCallback<void(Extensions::Observer*)> call) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE,
        base::BindOnce(
            [](base::WeakPtr<ExtensionsImpl> self,
               base::OnceCallback<void(Extensions::Observer*)> call) {
              if (self) {
                std::move(call).Run(self->observer_);
              }
            },
            weak_factory_.GetWeakPtr(), std::move(call)));
  }

  raw_ptr<Extensions::Observer> observer_;
  base::WeakPtr<Profile> profile_;
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      observation_{this};
  base::WeakPtrFactory<ExtensionsImpl> weak_factory_{this};
};

}  // namespace

std::unique_ptr<Extensions> ObserveExtensions(const std::string& profile_id,
                                              Extensions::Observer* observer) {
  return std::make_unique<ExtensionsImpl>(profile_id, observer);
}

}  // namespace oa
