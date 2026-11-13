#ifndef OA_BROWSER_WINDOW_BROWSER_H_
#define OA_BROWSER_WINDOW_BROWSER_H_

#include <functional>
#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "oa/public/browser.h"
#include "ui/gfx/native_ui_types.h"

class BrowserWindowInterface;
class Profile;

namespace content {
class WebContents;
}

namespace tabs {
class TabModel;
}

namespace oa {

class ExtensionsContainerImpl;
class PageImpl;

// One Oa window's //chrome Browser in one profile. Owned by its
// BrowserWindowImpl, so it lives exactly as long as the Browser.
class WindowBrowser : public TabStripModelObserver {
 public:
  static WindowBrowser* GetOrCreate(const std::string& window_id,
                                    Profile* profile);
  static WindowBrowser* Find(const std::string& window_id, Profile* profile);
  static void AttachWindow(const std::string& window_id, void* ns_window);
  static void CloseWindow(const std::string& window_id);
  static void AskToLeave(const std::string& window_id,
                         std::function<void(bool leave)> completion);
  static void CloseAll();
  // The active page of the Browser the app's `window` has for `profile`; of
  // the key window's when `window` is null.
  static PageImpl* ActivePage(gfx::NativeWindow window, Profile* profile);

  explicit WindowBrowser(BrowserWindowInterface* browser);
  WindowBrowser(const WindowBrowser&) = delete;
  WindowBrowser& operator=(const WindowBrowser&) = delete;
  ~WindowBrowser() override;

  BrowserWindowInterface* browser() const { return browser_; }
  const std::string& window_id() const { return window_id_; }
  gfx::NativeWindow GetNativeWindow() const;
  ExtensionsContainerImpl* extensions_container() const {
    return extensions_container_.get();
  }
  // The app's observer for this window and profile, if it has one now.
  Browser::Observer* observer() const;

  bool Insert(std::unique_ptr<content::WebContents> contents);
  std::unique_ptr<tabs::TabModel> Detach(content::WebContents* contents);
  bool InsertDetached(std::unique_ptr<tabs::TabModel> tab);
  void Activate(content::WebContents* contents);
  bool Close(content::WebContents* contents);
  void Remove(content::WebContents* contents);
  void OnWindowClosing();

  base::WeakPtr<WindowBrowser> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  // TabStripModelObserver:
  void OnTabStripModelChanged(
      TabStripModel* tab_strip_model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override;

 private:
  // Hands a tab Chrome put in the strip itself to the app, as ArcCore's
  // browser delegate hears of one.
  void AdoptInserted(base::WeakPtr<content::WebContents> contents);

  const raw_ptr<BrowserWindowInterface> browser_;
  std::unique_ptr<ExtensionsContainerImpl> extensions_container_;
  std::string window_id_;
  bool closing_ = false;
  bool activating_ = false;
  base::WeakPtrFactory<WindowBrowser> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_WINDOW_BROWSER_H_
