#ifndef OA_BROWSER_WINDOW_BROWSER_H_
#define OA_BROWSER_WINDOW_BROWSER_H_

#include <functional>
#include <memory>
#include <string>
#include <vector>

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
  // The window's Browsers are Chrome's popups from here on, as ArcCore's for a
  // little window. Told before any of them is made.
  static void MarkPopup(const std::string& window_id);
  static void AttachWindow(const std::string& window_id, void* ns_window);
  static void CloseWindow(const std::string& window_id);
  static void AskToLeave(const std::string& window_id,
                         std::function<void(bool leave)> completion);
  static void CloseAll();
  // As ArcCore's quit: every page with a beforeunload or unload handler runs
  // its unload handler and closes, one at a time in each Browser.
  static void UnloadForQuit();
  // Closes each Browser Chrome restored for a window the app hasn't attached.
  static void CloseUnclaimed();
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
  bool closing() const { return closing_; }
  // As ArcCore's Browser, which stays with no tabs until its window goes:
  // while the app holds the window's handle, an emptied strip doesn't close
  // it.
  bool StaysOpenEmpty() const;
  // Closes it once the app let go of it, if it has no tabs.
  void CloseIfEmpty();
  // Takes the tabs parked while a session restore was awaited. The restored
  // ones come back as pages; any other goes to `observer` as a page Chrome
  // opened.
  std::vector<RestoredPage> AdoptParked(Browser::Observer* observer);

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
  std::vector<base::WeakPtr<content::WebContents>> parked_;
  bool closing_ = false;
  bool close_requested_ = false;
  bool activating_ = false;
  base::WeakPtrFactory<WindowBrowser> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_WINDOW_BROWSER_H_
