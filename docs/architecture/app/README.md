# App / UI

**Status: scope only.** The detailed reference-architecture chapter has not been
written. The Chromium, Core and DevKit chapters cover the engine, native
integration and Swift interface.

This layer owns product state and presentation: Spaces, sidebar items, native
windows, settings, routing decisions and saved application state. It consumes
the Swift engine interface exposed by DevKit.

Future chapters belong here when they explain how a user action becomes a
product decision, how the app presents engine requests, or how app state survives
relaunch. Chromium internals and native engine adapters belong below this layer.

For Oa, the intended rule is that the app owns product state and talks to the
engine through DevKit. Detailed state, persistence and presentation decisions
are documented in this chapter as they are made.

## Sidebar state

`SidebarState` is the app's source of truth: profiles, Spaces and an item tree.
A profile owns a favorites root; a Space owns a pinned root and an unpinned
root. Tree nodes are containers, tabs, folders and split views; only containers
and tabs are implemented. A tab entry takes its tab's ID, so pinning is a move
to the end of the other section and the entry keeps its identity. A tab record
saves a title and a URL. A live page writes both back; a pinned tab or a
Favorite keeps its address and takes the title only while the page is at it.
While the page is elsewhere a pinned row reads "/ live title", as in Arc, and
goes back to the pinned title once the page is gone.

One `SidebarStore` holds the state and the open windows. Every change goes
through `edit`, after which each window reconciles its selection and drops pages
of tabs or Spaces that are gone, and a save follows 2.8 s later. Write-backs of
title and URL change the state without scheduling a save; they ride on the next
one, and on the save at quit.

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
detached, so the engine sees them as hidden. Window close and quit drop pages
without unload handlers; the records stay.

Close Tab ⌘W reads "Archive Tab" on an unpinned tab, as in Arc: the record
leaves the tree for the Archive with the time, its Space, how it was closed and
its index, and the page, wherever it lives, closes as the user would. The window
returns to the previous tab if its page is live, else the tab above, else below;
another window that had the tab selected is left with no selection. On a pinned
tab the item reads "Close Tab", the entry stays and the page is dropped; the
window returns to the previous live tab, else shows nothing. A page the engine
closes on its own is archived the same way. Pin Tab ⌘D toggles the section.
Spaces have New, Rename and Delete without shortcuts; the last Space can't be
deleted, and deleting one archives its tabs, pinned too, after a confirmation
when it has any. Its Archive entries stay.

The Archive is a sidebar mode, as in Arc: Archive ▸ View Archive… replaces the
sidebar with one list across Spaces, grouped by day and newest first, each row
with the favicon, the title and the scheme-less URL, Restore and Delete on hover and in a
context menu, and the page stays live beside it. Restore puts the tab back at the
top of its Space's unpinned section, not selected, with its page made on first
selection from the saved URL and no history; a tab whose Space is gone returns to
the window's Space. Clicking the row itself shows the page in a Peek over the
list, below. File ▸ Restore Last Closed Tab ⇧⌘T brings the newest entry
back at its old index, selected, switching the window to its Space. Archive ▸
Clear Archive empties it after a confirmation. Each tab carries the time a
window last selected it; a sweep at launch and every 15 minutes archives
unpinned tabs idle for 12 hours, Arc's default, unless a window has them
selected, and there is no setting to turn it off. Arc keeps a separate
session-only ⇧⌘T stack with engine history and asks before archiving a page whose
`beforeunload` wants to stay; both are follow-ups.

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
and a Shift-click from any tab go to a Peek instead, below. Arc hosts sized popups as plain
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

## Peek

A Peek shows a page over the window as part of the tab it was opened from, as
Arc does: a pinned tab's cross-origin link clicks, `target=_blank` links,
`window.open` calls and sized popups, and a Shift-click on a link in any tab,
which Chromium reports as a new-window open. Same-host links navigate the
pinned tab in place. The pinned tab's page is marked as keeping its address
through DevKit, and Core does what Arc does: it sets Chromium's renderer
preference that hands every top-level navigation to the browser, so the
navigation reaches the page's `OpenURLFromTab`, where one to another host
becomes a new page, reported like any opened page, and the rest navigate in
place. Hosts, not origins: Arc peeks `example.com` → `www.example.com` and
navigates an http → https change in place. Script navigations without a
gesture peek too, as Arc's do; a server redirect to another host follows in
place, since the decision is made once at the start. Form submissions, client
redirects such as `location.replace` and blank loads never leave the renderer:
Chromium's own check hands all of them over, and patch 0006 adds the
exclusions Arc's renderer has. The port and Arc's exclusions for meeting-join
links are untested.

The Peek is a view in the window, not a window of its own, with Arc's measured
geometry: its page is 80% of the content area's width by the height minus
56 pt, under a 33 pt toolbar with back, forward, reload or stop and the
scheme-less URL with the host in bold, centered 11 pt from the top, with
rounded corners and a shadow, over a dim of about a fifth. ✕ and Expand sit
outside its top-right corner. The sidebar stays live under the dim, the opener's
row carries the Peek page's favicon as a badge, the window title reads the Space
name while a Peek shows, and keyboard focus goes to the Peek page. Selecting
another tab or Space hides the Peek and keeps its page alive; reselecting the
opener shows it again. The page's history is its own. Back, Forward, Reload and
Stop act on the Peek while it shows; ⌘W closes it and Tabs ▸ Expand Peek ⌘O
expands it, Arc's two shortcuts for it; Esc does nothing, as in Arc. ⌘L,
New Tab, Pin Tab and tab switching keep acting on the window beneath, Oa's own
choice: Arc's ⌘L opens its command bar prefilled with the Peek's URL, which Oa
doesn't have.

Inside a Peek, plain links navigate the Peek. `target=_blank` and `window.open`
make a selected tab after the opener's earlier children, which hides the Peek
until the opener is reselected; a ⌘-click makes a background tab there and
leaves the Peek up. A Shift-click inside a Peek makes a tab too, Oa's own
choice. Expand makes the Peek's page a selected tab after the opener's earlier
children, the same live page with no reload. ✕, a click on the backdrop and ⌘W
archive the page under the tab's Space, as do archiving the opener, closing
the window and quitting; a page that closes itself leaves no entry. A tab has
one Peek: a new request while one is up closes the current one as ✕ would,
Oa's own choice. The entry has no position, so it restores at the top of the
unpinned section, also Oa's own: Arc's entries carry no visible position.
Nothing about a Peek is saved, so none survives a relaunch, as in Arc.

Clicking an Archive row shows the entry's page in a Peek over the list, made
from the saved URL with no history, centered over the whole window as Arc does
over its Library; the entry stays. Its Expand removes the entry and puts the
tab, selected, at the top of the unpinned section of the Space the window
shows, as Arc does. Closing it, or leaving the Archive view, closes the page and
keeps the entry; leaving the view is Oa's own choice. A page such a Peek opens
has no tab to join, so it goes to the top of the shown Space, Oa's own choice.
Arc's Split View button and copy-link icon don't exist in Oa yet.

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

## Favorites

A profile's Favorites are tabs in its favorites root, shown as a grid of tiles
at the top of the sidebar in every Space of the profile, as Arc does. The grid
has Arc's measured shape: 47 pt tiles with 8 pt gaps filling the row, the
column count from the tile count (⌈n / 4⌉ rows, ⌈n / rows⌉ columns), the last
row left-aligned, and each tile a favicon and nothing else, no title and no
tooltip. A tile whose tab has no page shows its saved favicon, as in Arc, and
the first letter of its host when its page never showed one, Oa's own. The
selected tile has a lighter fill; Arc tints it from the favicon, which
isn't copied. While the Favorite's Peek shows, the tile carries the Peek page's
favicon on its top-right corner. With no Favorites the grid is one dashed empty
tile to drop on, Oa's own; Arc's empty grid wasn't observed.

A tab becomes a Favorite by dragging its row into the grid, where it lands
before the tile it is dropped on or at the end when dropped beside the tiles,
as Arc inserts at the drop position, or by Tabs ▸ Favorite Tab, which appends,
standing in for Arc's command-bar command; Arc's row menu has no such item and
neither has Oa. Tiles move by the same drag. The tile's Remove Favorite
archives the tab under no Space with its page closed and leaves nothing
selected, as Arc does. Tabs ▸ Unfavorite Tab, the tile's Unfavorite and a tile
dropped on the tab list make it a tab of the shown Space at the top of the
unpinned section; Arc has the command, the tile item, the drop and the position
are Oa's own. Favorites are never auto-archived, and deleting a Space leaves
them.

A click selects the Favorite and shows its one live page, made from the saved
URL on the first selection as for any tab; the page serves every Space of the
profile and every window, moving as other pages do. Selection is per Space, as
in Arc: each Space remembers which Favorite it showed, and a Space switch shows
the other Space's own selection or nothing. A Favorite keeps its address like a
pinned tab: same-host links navigate it in place and it stays at the new
address across selections, while the window title and the address field read
the live page. Cross-host links and the rest open a Peek, which hides and
returns with the Favorite across a Space switch, and whose ✕, ⌘W, backdrop
click and the window's close archive it under no Space, as Arc files a
Favorite's Peek under no Space chip; its Expand and its `target=_blank` tabs go
to the top of the shown Space's unpinned section, after earlier children. Close
Tab ⌘W on a Favorite only deselects it, returning to the previous live tab, and
when the page has left the saved URL it first reloads that URL in the
background, as Arc does; the page stays alive. A page that ends on its own
leaves the tile without one. Closing a Space's last tab falls back to the first
Favorite when no earlier tab is live, Oa's own. New windows and new Spaces start
with nothing selected, as in Arc. ⌘1–⌘9 count Favorites first, then pinned,
then unpinned, as Arc does, and Next and Previous Tab cycle through the same
list. Whether Arc reopens a navigated Favorite at its saved URL
after a relaunch is unknown; Oa saves only the Favorite's address, so it does.

### Files

`sidebar.json` and `windows.json` live in the data directory beside Chromium's
folder, as sorted pretty JSON written atomically into a `0700` directory; a save
with unchanged bytes is skipped.

`sidebar.json` carries `version`, `profiles`, `spaces`, `tree` and `archive`,
where `tree` lists `rootIDs` and `items` in display order. Each item has `id`,
optional `parentID` and `childIDs`, a `type` of `container`, `tab`, `folder` or
`splitView`, and for a container its `container` kind, for a tab its `title`,
`url`, `viewedAt` and `openerID`, the tab whose page opened it. Each `archive` entry has `id`, `title`, `url`, `spaceID`,
absent for a Favorite and a Favorite's Peek, `archivedAt`, a `reason` of
`manual` or `auto`, and `position`. Dates are ISO
8601. A file without `archive`, `viewedAt` or `openerID` reads as an empty Archive, no
stamps and no openers. Loading validates the tree: roots are containers, parents and children
agree, every item is reachable, each profile and Space points at roots of the
right kind, and no archived tab is also in the tree.

`windows.json` carries `version` and `windows`, each with `id` and
`selectedSpaceID`. A saved Space that no longer exists falls back to the first.
Window frames are not saved.

The last favicon each tab's page showed is a PNG at `favicons/<id>.png` beside
the files, written when the page shows a new one, read when a row, tile or
Archive entry has no page, and removed at a save once the tab is in neither the
tree nor the Archive. Arc keeps such caches apart from its sidebar store too,
one for sidebar items and one for archived ones, under hashed names; Oa keeps
one directory named by tab ID, its own choice. A restored copy of the sidebar
shares the IDs, so its tabs find their icons.

`version` is a format number, as Arc's own stores carry at their top level.
Adding a key with a default, as `archive`, `viewedAt` and `openerID` were,
doesn't bump it;
a change an older reader would misread does. A file that can't be read or has a
newer `version` is kept as it is and not written for the rest of the launch; the
app runs on the default state in memory.

Before the first overwrite of `sidebar.json` each launch, the bytes the launch
started from go to a dated copy beside it, `sidebar.YYYY-MM-DD-HH-MM-SS-mmm.json`,
stamped in local time with the save time they hold, as Arc names its copies; the
same bytes found again at a later launch add nothing. Arc copies at quit instead,
which holds the same state after a clean quit and nothing after a crash. The
copies are pruned to Arc's documented tiers: the newest 10 of today, one a day
for the 10 days before, one a week for the month before that, one a month for
the year before that. `windows.json` has no copies, as Arc's Restore Data offers
only the sidebar.

Help ▸ Restore Data… lists the copies newest first, each with its date and time to
the second and its tab and Space counts, and once one is chosen whether it can
be read and a preview of its Spaces and tabs; Arc's rows carry only a short date
and time, and its preview is one flat list of URLs. Restore asks for a
confirmation that names the copy and the current sidebar; Arc asks nothing.
Then, as Arc does, the current state is saved and kept as a copy, so the restore
is undoable from the same list, the copy's bytes replace `sidebar.json`, nothing
is saved after, and the app quits and opens itself again on the restored file.
Windows come back as after any relaunch, on their Spaces with nothing selected;
Arc comes back with one fresh window. A file that couldn't be read at launch is
recovered the same way.

Return to the [system overview](../README.md).
