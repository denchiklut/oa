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
| 0016 | Makes a tab's thumbnail ready by ArcCore's rule: a navigation inside the document takes a new thumbnail when it finishes, where upstream ignores it, and a new document is ready only at its load event, so nothing is captured while it loads |
| 0017 | Copies a tab's whole view for the thumbnail Chrome makes as the tab stops being active, as ArcCore's does; upstream leaves out the strips where a scrollbar would be |
| 0018 | Makes ⌘Z and ⇧⌘Z the page's first and the window's after, as ArcCore does: `RenderWidgetHostViewCocoa`'s `undo:` and `redo:` send the command to the focused frame with a reply, through a new `ExecuteEditCommandWithResult` on the view's host and on the frame's input handler, and when the frame ran nothing, the first undo manager up the responder chain that can undo or redo does. Upstream sends the command with no reply, so the app's own steps were never reached while a page had the keyboard |
| 0019 | Runs the page menu's Open Link in Split View, for an embedder that edits the menu, as an open with Chromium's `NEW_SPLIT_VIEW` disposition through the page's delegate, as ArcCore's item goes to the app with its own disposition; upstream joins the link's tab to the active one in the tab strip |
| 0020 | Sends a top-level link click whose policy is a download, as Blink makes an ⌥-click, to the browser at once when the browser handles top-level requests, as Arc's arrives in about 0.1 s; upstream waits out the double-click time first. A subframe's keeps upstream's wait and download |
| 0021 | Lets an embedder's switch decide about the last session, as ArcCore's does: the profile's first browser of a launch restores it with the switch on, each saved window into the browser the embedder titled with the same ID and any other into a new browser that keeps the title, where upstream puts the first window into the existing browser. A hook reports each restored tab with the session ID it had, restored background tabs wait to be shown, the last session keeps only normal windows (none with the switch off), and the startup preference defaults to continuing it, so session storage is kept for the restore |
| 0022 | Makes Edit ▸ Paste and Match Style work over a page, as ArcCore does: `RenderWidgetHostViewCocoa` answers and enables `pasteAsPlainText:`, the selector of AppKit's item, with the same `PasteAndMatchStyle` as its `pasteAndMatchStyle:`. Upstream has no such method, so the item was disabled over a page |
| 0023 | Lets `//oa` show Chrome's constrained WebUI dialogs, print preview among them, as ArcCore does: the embedder's dialog takes the dialog's WebContents and the app shows it as a sheet over the page; Chrome's Views dialog needs a `BrowserView` |

Don't edit these files by hand. Commit on the `oa-patches` branch in `.local/chromium/src`, then run
`scripts/patches.sh export`. `scripts/build.sh` applies the series before building.
