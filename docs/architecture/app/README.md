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
saves a title and a URL. A live page writes both back; a pinned tab keeps its
address and takes the title only while the page is at it. While the page is
elsewhere the row reads "/ live title", as in Arc, and goes back to the pinned
title once the page is gone.

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
with the title and the scheme-less URL, Restore and Delete on hover and in a
context menu, and the page stays live beside it. Restore puts the tab back at the
top of its Space's unpinned section, not selected, with its page made on first
selection from the saved URL and no history; a tab whose Space is gone returns to
the window's Space. File ▸ Restore Last Closed Tab ⇧⌘T brings the newest entry
back at its old index, selected, switching the window to its Space. Archive ▸
Clear Archive empties it after a confirmation. Each tab carries the time a
window last selected it; a sweep at launch and every 15 minutes archives
unpinned tabs idle for 12 hours, Arc's default, unless a window has them
selected, and there is no setting to turn it off. Arc keeps a separate
session-only ⇧⌘T stack with engine history and asks before archiving a page whose
`beforeunload` wants to stay; both are follow-ups.

Only the only window selects a tab when it opens: the first unpinned, else the
first pinned. A further window opens on the key window's Space with nothing
selected and the address field focused. A restored window comes back the same
way, on its saved Space with nothing selected and no page, as Arc does. A
selected tab without a page shows the window background and its saved URL in
the address field; Arc shows Chromium's blank view and `about:blank` there,
which isn't worth copying. A sidebar row looks the same whether its page exists
or not, as in Arc, and a tab with no title yet reads "Untitled".

### Files

`sidebar.json` and `windows.json` live in the data directory beside Chromium's
folder, as sorted pretty JSON written atomically into a `0700` directory; a save
with unchanged bytes is skipped.

`sidebar.json` carries `version`, `profiles`, `spaces`, `tree` and `archive`,
where `tree` lists `rootIDs` and `items` in display order. Each item has `id`,
optional `parentID` and `childIDs`, a `type` of `container`, `tab`, `folder` or
`splitView`, and for a container its `container` kind, for a tab its `title`,
`url` and `viewedAt`. Each `archive` entry has `id`, `title`, `url`, `spaceID`,
`archivedAt`, a `reason` of `manual` or `auto`, and `position`. Dates are ISO
8601. A file without `archive` or `viewedAt` reads as an empty Archive and no
stamps. Loading validates the tree: roots are containers, parents and children
agree, every item is reachable, each profile and Space points at roots of the
right kind, and no archived tab is also in the tree.

`windows.json` carries `version` and `windows`, each with `id` and
`selectedSpaceID`. A saved Space that no longer exists falls back to the first.
Window frames are not saved.

`version` is a format number, as Arc's own stores carry at their top level.
Adding a key with a default, as `archive` and `viewedAt` were, doesn't bump it;
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
