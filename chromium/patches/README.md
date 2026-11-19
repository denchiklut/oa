# Chromium patches

The numbered series applied on top of the release in [`../VERSION`](../VERSION). A change goes here only when it
can't live in `//oa` (`core/`). Every patch is rebased at each Chromium update, so keep the series small.

| Patch | Why |
| --- | --- |
| 0001 | Links `//oa` into Chromium's framework and exports `OACoreMain`, the entry point the app calls instead of `ChromeMain` |
| 0002 | Lets the app replace Chrome's Mac `AppController` and main menu, so the app owns its delegate, menu and quit |
| 0003 | Lets `//oa` supply every `Browser`'s window, so Chrome's views are never built |
| 0004 | Lets `//oa` supply permission prompts; Chrome's Views prompts crash without a `BrowserView` |
| 0005 | Lets the embedder load the startup profile without a window, in place of `--no-startup-window` and its keep-alives |
| 0006 | Keeps form submissions, client redirects and blank loads in the renderer when `browser_handles_all_top_level_requests` is on, as Arc's renderer does, so only links reach the browser's routing |
| 0007 | Lets `//oa` supply the sad tab; Chrome's `SadTabController` asserts on the missing `BrowserView` the moment a renderer dies |
| 0008 | Lets `//oa` supply the tab-modal JavaScript dialog view; Chrome's is a web-modal dialog anchored to the `BrowserView`. The app-modal view needs no patch: `AppModalDialogManager::SetNativeDialogFactory` is public |
| 0009 | Lets Chrome's Cocoa page context menu show over a page that sits in the app's own window, where it found no `views::Widget` and returned, as ArcCore's patched menu does; and lets `//oa` edit the menu's model before it shows, to remove the items that need Chrome's views |
| 0010 | Lets `//oa` supply the extension install and uninstall dialogs; Chrome's are views dialogs modal to a views window or anchored to its extensions toolbar. ArcCore replaces both too |
| 0011 | Installs `//oa`'s renderer client in the macOS helpers, which enter `ChromeMainDelegate` and not `//oa`'s delegate |
| 0012 | Copies the top frame's origin from Blink's request onto `network::ResourceRequest`, where ArcCore appends the same field, so the ad blocker's renderer throttle knows a request's page on any thread |
| 0013 | Lets `//oa` see each page's compositor frame metadata, for its root background colour: `RenderWidgetHostViewMac` hands the metadata of a RenderViewHost's widget to an embedder hook before the frame activates, as ArcCore's patched view hands it to its page |
| 0014 | Brings back the spare-compositor pool upstream removed, as ArcCore does: a page's view that is shown takes the compositor the page just hidden gave up, so a tab switch never waits for a new compositor's first frame with nothing on screen; as in ArcCore, `AcceleratedWidgetMac` keeps its last CALayerParams across views, since viz won't resend unchanged ones, and a navigation's new widget builds a fresh compositor |
| 0015 | Stops `settings_utils::MaybeNotifySettingsCustomEvent` after its feature check, as ArcCore's does: upstream it CHECKs for a `BrowserView` element to send the settings journey event to, which crashed `chrome://settings` on activating a search engine or making one the default |

Don't edit these files by hand. Commit on the `oa-patches` branch in `.local/chromium/src`, then run
`scripts/patches.sh export`. `scripts/build.sh` applies the series before building.
