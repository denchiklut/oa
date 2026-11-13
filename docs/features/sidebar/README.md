# Sidebar state

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

The current app uses an observable `SidebarStore` for shared data and a
`WindowModel` for each window, composed by `ApplicationDelegate`. `AppEngine`
selects the live or stub DevKit implementation. These notes describe existing
slices; folders, split views, undo, sync and the full feature surface are not
implied to be implemented.

## Shared model and window selection

`SidebarState` is the app's source of truth: profiles, Spaces and an item tree.
A profile owns a favorites root; a Space owns a pinned root and an unpinned
root. Tree nodes are containers, tabs, folders and split views; only containers
and tabs are implemented. A tab entry takes its tab's ID, so pinning is a move
to the end of the other section and the entry keeps its identity. A tab's live
page has an ID of its own, a fresh one per page as Arc gives its contents, so
two pages for one entry stay two. A tab record
saves a title and a URL. A live page writes both back; a pinned tab or a
Favorite keeps its address and takes the title only while the page is at it.
While the page is elsewhere a pinned row reads "/ live title", as in Arc, and
goes back to the pinned title once the page is gone.

One `SidebarStore` holds the state and the open windows. Every change goes
through `edit`, after which each window reconciles its selection and drops pages
of tabs or Spaces that are gone, and a save follows 2.8 s later. Write-backs of
title and URL change the state without scheduling a save; they ride on the next
one, and on the save at quit. SIGTERM, as from `kill` or launchd, ends the
process without that save, so changes from the last 2.8 s are lost, as Arc
loses those younger than its 3 s delay. SIGINT and SIGHUP quit as the Dock does.

A `WindowModel` holds the window's selected Space, a selected tab per Space, a
one-step previous tab, and the pages it holds. A page exists only once its tab
was shown in some window, and one live page exists per tab across windows. The
page lives in the window that last showed its tab, as in Arc: a window that
selects a tab held by another window takes the page over through DevKit's
`move(toWindow:)`, which Core implements by detaching the tab from one Browser's
strip and inserting it into the other's, without unload handlers or a closed-tab
record. Before the page leaves, the window it leaves asks for its last frame
(`snapshot()`, a copy of the compositor surface, possible only while the page
draws there) and, while its sidebar still marks the tab selected, shows that
frame frozen and dimmed to 0.57 over the window background with an empty toolbar
strip. The page also moves to a window that shows its tab when the holding
window selects another tab, when the showing window becomes key, and when the
holding window closes. Pages of Spaces not shown stay alive with their views
detached, so the engine sees them as hidden. A closing window that isn't the
last hands every page it holds, shown or hidden and with its Peek, to another
window, preferring one that shows its tab, with no prompt, as Arc does. ⌘Q and
Quit first show Arc's "Quit Oa?" with Quit, Cancel and "Quit, and don't ask
again", which turns the warning off; Settings ▸ General ▸ "Warn before quitting"
turns it back on. It is on by default, LIKELY as in Arc, and a quit from the
Dock or at logout doesn't ask. Then the last window and quit ask each page's
`beforeunload` handler without closing it, window by window in the order each
window got its pages, as Chrome's shutdown pass in Arc does; a page that asks
comes forward with "Leave site?", and a Cancel ends the pass and keeps the
window or the app running. Then the pages are dropped and the records stay.

Close Tab ⌘W reads "Archive Tab" on an unpinned tab, as in Arc: the page,
wherever it lives, closes as the user would, and once it reports closed the
record leaves the tree for the Archive with the time, its Space, how it was
closed and its index. A page whose `beforeunload` handler wants to stay asks
first with "Leave site?" and a Cancel keeps page, row and selection, as Arc
does; the row's hover ✕ on another tab brings that tab forward while it asks,
as Arc selects it first. A tab without a live page is archived at once. The
window returns to the previous tab if its page is live, else the tab above, else
below; another window that had the tab selected is left with no selection. On a
pinned tab the item reads "Close Tab", the entry stays and the page is dropped
without unload handlers, Oa's own choice. A page the engine closes on its own is
archived the same way. Pin Tab ⌘D toggles the section. Spaces have New, Rename
and Delete without shortcuts; the last Space can't be deleted. Deleting one asks
"Delete your Space?" when it has tabs, then closes all its live pages at once as
the user would, as Arc does: pages without a handler go at once,
the ones that ask come forward with "Leave site?" one after another, and every
one is asked even after a Cancel. Any Cancel keeps the Space with every row,
with the pages already closed staying closed. When every page is gone the tabs
are archived, pinned too, and the window moves to the neighbor Space. Its
Archive entries stay. Its Peeks go without asking and leave no entry, as in Arc,
which runs their handlers and unloads them; Oa drops them.

The Archive is a sidebar mode, as in Arc: Archive ▸ View Archive… replaces the
sidebar with one list across Spaces, grouped by day and newest first, each row
with the favicon, the title and the scheme-less URL, Restore and Delete on hover and in a
context menu, and the page stays live beside it. Restore puts the tab back at the
top of its Space's unpinned section, not selected, with its page made on first
selection from the saved URL and no history; a tab whose Space is gone returns to
the window's Space. Clicking the row itself shows the page in a Peek over the
list; see [Peek](../peek/README.md). Archive ▸
Clear Archive empties it after a confirmation. Each tab carries the time a
window last selected it; a sweep at launch and every 15 minutes archives
unpinned tabs idle for 12 hours, Arc's default, unless a window has them
selected, and there is no setting to turn it off. A due tab with a live page is
closed as the user would, so a `beforeunload` handler can keep it; a kept tab
counts as viewed now and is not asked again for another 12 hours, Oa's own rule,
after Arc's idle unload, which never prompts.

File ▸ Restore Last Closed Tab ⇧⌘T walks the window's own closed tabs, not the
Archive, as Arc's does. Each window keeps the last ten closes the user made
from it, in memory: ⌘W, a row's ✕, Remove Favorite and a closed Peek, whichever
window held the page. The list goes with the window and at quit. A page that
closes itself and a deleted Space's tabs are not in it, as in Arc; neither are
auto-archived tabs, Oa's own choice, Arc's being unknown. The item is enabled
only while the window has something to bring back. A press takes the newest. A
tab that is open again, restored from the Archive or expanded from a Peek, is
selected, switching the window to its Space. One that is gone returns where it
was, selected, even after its Archive entry was deleted, and leaves the
Archive; when its Space is gone it lands at the top of the shown Space. It
comes back with its back and forward history and the page from Chromium's
cache while Chromium still keeps the closed tab. That holds whichever window
held the page, Oa's own choice: Arc keeps the session ID in the window that
held the page, so a tab closed from another window loads fresh there. Arc also
selects a pinned tab again when its ⌘W left nothing selected; Oa doesn't yet.

A page a page opens, with a `target=_blank` link, `window.open` or a ⌘-click,
keeps the page the engine made for it, so `window.opener`, session storage and a
POST's data survive: Core inserts it into the opener's Browser in the background
and DevKit reports it on the opener's page as an event carrying a ready handle,
the target URL and the disposition. The app makes a tab for it that takes the
page's ID and records the opener, and places it as Arc does: after the opener's
last descendant in the unpinned section, where a pinned opener's group sits at
the top. A foreground open, every
`window.open` and a popup that asked for a size included, selects the tab when
the opener's Space is the one shown; a ⌘-click or middle click leaves the
selection and the page loads in the background. A pinned tab's foreground opens
and a Shift-click from any tab go to a [Peek](../peek/README.md) instead. Arc hosts sized popups as plain
tabs too, so there is no popup window. A page that closes itself, as after an
OAuth sign-in, is archived like a ⌘W, and the next selection follows the opener
as in Arc: the next tab below with the same opener, else the one above, else the
opener, before the previous tab. The row shows Chromium's URL-derived title until
the page has one, and the address field the URL at once. Chromium's popup blocker
stays on with its default setting and no indicator; Arc lets no-gesture opens
through from the visible page, which isn't copied.

A page that asks to be shown, with `window.focus()` from its opener or by a
`window.open` that reuses it as a named target, is reported by DevKit as an
event on that page. The window holding the page selects its tab, switching to
the tab's Space when another is shown, and comes to the front, as Arc does: it
switches Spaces for both calls and raises the window that already shows a
reused named tab rather than showing the page twice. Arc does nothing for a
`window.focus()` on a tab already shown; the engine reports both calls the
same way, so Oa raises the window for that too. Chromium grants the request
only to a caller with a recent gesture or to the page's opener, so a page
can't pull the selection to itself from the background.

## Page presentation and recovery

Only the only window selects a tab when it opens: the first unpinned, else the
first pinned. A further window opens on the key window's Space with nothing
selected and the address field focused. A restored window comes back the same
way, on its saved Space with nothing selected and no page, as Arc does. A
selected tab without a page shows the window background and its saved URL in
the address field; Arc shows Chromium's blank view and `about:blank` there,
which isn't worth copying. A sidebar row looks the same whether its page exists
or not, as in Arc, and a tab with no title yet reads "Untitled". The row starts
with the favicon Chromium's favicon driver chose for the live page, wherever
the page lives, else the favicon the tab's page last showed, kept beside the
sidebar file as Arc shows it after a relaunch, else an empty tile. The page also carries Chromium's
security level for its visible URL, neutral, secure, warning or dangerous,
which nothing shows yet.

A page whose renderer has died, crashed, killed or out of memory, shows a
native crashed page with a Reload button in place of the engine's view, in the
window and in a Peek, until a reload starts a new renderer. Arc replaces
Chrome's sad tab in its engine, which reports only that the renderer is gone and
later that a new one is ready; its app keeps the crashed state and draws its own
page. Oa does the same: Core reports both events, DevKit keeps the state, and a
Chromium seam like the one for permission prompts stands in for Chrome's sad
tab, which wants a BrowserView and aborts without one. The words on the page
are Oa's own.

A page's `alert`, `confirm`, `prompt` and "Leave site?" show as Arc shows them:
one panel centred on the window over a scrim that covers sidebar, toolbar and
page alike, with Chrome's words, "host says" above the message, OK and Cancel, a
prompt field with its default text selected, and "Reload site?" for a reload.
Enter accepts and Esc cancels; Esc does nothing to an alert. The window's own
commands wait while the panel is up, other windows and quit stay usable. Chrome's
dialog managers keep their policy: an `alert` from a page that is hidden or in a
window that is not key returns at once and its panel waits until the page is
shown in a key window, a hidden `confirm` or `prompt` is cancelled at once, a
navigation or a tab switch under a dialog dismisses it, and a page that is the
Browser's active tab behind a tab with no page keeps its alert waiting, an Oa
quirk. From a page's seventh dialog on the panel offers "Don't show this again",
which answers that page's later dialogs unasked for the rest of its life, as
Arc's does. Arc replaces Chrome's two dialog views in its engine and draws the
panel in its app; Oa does the same through `SetNativeDialogFactory` for the
app-modal view and patch 0008 for the tab-modal one, both reaching the page's
observer with a reply to call once and a dismissal when the engine closes the
dialog. The panel's colours follow the system appearance, Oa's own; Arc's is dark.

The engine is built without DCHECKs, as Arc ships. A Blink assertion that is
wrong for a valid layout killed renderers on real pages, and Chromium has
thousands more like it; `chromium/args.gn` turns them off and keeps the
dangling-pointer detector on explicitly, since its default follows DCHECKs.

Related: [Peek](../peek/README.md) · [Favorites](../favorites/README.md) · [Saved state and recovery](../saved-state/README.md).

Return to the [feature inventory](../README.md).
