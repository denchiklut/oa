# Saved state and recovery

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

## Files

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

Related: [Sidebar state](../sidebar/README.md) · [Peek](../peek/README.md) · [Favorites](../favorites/README.md).

Return to the [feature inventory](../README.md).
