#ifndef OA_BROWSER_WINDOW_BROWSER_H_
#define OA_BROWSER_WINDOW_BROWSER_H_

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
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

// One Oa window's //chrome Browser in one profile. Owned by its
// BrowserWindowImpl, so it lives exactly as long as the Browser.
class WindowBrowser : public TabStripModelObserver {
 public:
  static WindowBrowser* GetOrCreate(const std::string& window_id,
                                    Profile* profile);
  static WindowBrowser* Find(const std::string& window_id, Profile* profile);
  static void AttachWindow(const std::string& window_id, void* ns_window);
  static void CloseWindow(const std::string& window_id);
  static void CloseAll();

  explicit WindowBrowser(BrowserWindowInterface* browser);
  WindowBrowser(const WindowBrowser&) = delete;
  WindowBrowser& operator=(const WindowBrowser&) = delete;
  ~WindowBrowser() override;

  BrowserWindowInterface* browser() const { return browser_; }
  const std::string& window_id() const { return window_id_; }
  gfx::NativeWindow GetNativeWindow() const;

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
  const raw_ptr<BrowserWindowInterface> browser_;
  std::string window_id_;
  bool closing_ = false;
  bool activating_ = false;
  base::WeakPtrFactory<WindowBrowser> weak_factory_{this};
};

}  // namespace oa

#endif  // OA_BROWSER_WINDOW_BROWSER_H_
