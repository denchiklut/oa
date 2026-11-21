# Split View

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

A split shows two to four tabs side by side in the page's place, as Arc's
does. It is one entry of the sidebar whose children are its tabs in pane
order, and each pane is an ordinary tab with its own page.

- **Making one.** A row's menu ▸ Open in Split View puts that tab on the right
  of the selected one, or adds it as the last pane of the selected split. ⌥Return
  in the ⌘T bar opens the address in a new tab on the right of the current one.
  The new pane takes the focus. A split holds four panes at most, Arc's limit.
- **Panes.** They share the page's area by the split's factors, equal until a
  pane is resized, 10 pt apart and none under 220 pt, so panes that don't fit
  run past the window's edge. Each has a 32 pt bar in its page's colour: back
  and forward, the host, and a ✕ that closes its tab; reload shows on the
  focused pane while it is wide enough. A split has no window toolbar, and
  Show Toolbar is off while one is shown.
- **Focus.** The focused pane is the window's selected tab. It has a 2 pt
  outline inside its edge and a glow into the gaps beside it. A click on a
  pane's page reaches the page and focuses the pane: the engine reports which
  page has the keyboard, as ArcCore's `hasFocus`, and the window follows it. A
  click on a pane's bar focuses it too.
- **Sidebar cell.** One card for the split with a small card for each tab. A
  click selects the split with the pane the window focused in it last, and on
  the selected split the tab clicked. Under the pointer the selected split
  shows a ✕ for each tab, and one that isn't selected a single ✕ that archives
  all its tabs. Its menu has Separate All Tabs, and for each tab Separate from
  Split View and Archive Item.
- **Closing and separating.** ⌘W and a pane's ✕ close that pane's tab, and the
  next pane takes the focus. A split left with one tab is that tab again, where
  the split was. A separated tab is selected, alone, right after the split.
- **Windows.** A split's pages are in the window that showed it last, all of
  them. Another window on the same split keeps its panes and its own focused
  pane, with each page's last picture, and takes the pages when it becomes key.
- **Storage.** The entry is saved as `splitView` with Arc's
  `SidebarSplitViewData` fields: `itemWidthFactors` as Arc's flat list of an ID
  and its factor, and `layoutOrientation`.

Oa's own:

- After a split is selected again, the outline and the keyboard are both on the
  pane the window focused last. Arc draws the outline there and sends typing to
  the last pane.
- Only unpinned tabs of one Space can be in a split for now, and Pin Tab and
  Favorite Tab are off on a split's tab. Arc pins a split whole and files one
  under Favorites.
- A permission prompt shows while its pane is the focused one, as for any tab
  that isn't selected. What Arc does for an unfocused pane wasn't seen.
- Reload leaves a pane's bar under 300 pt. Arc's had none at 278 pt and one at
  421 pt.
- The focus outline is the theme palette's shaded entry in dark and its darkest
  in light, which gives Arc's blues on the default theme; other themes weren't
  measured.
- Closing a split from its ✕ comes back with ⇧⌘T a tab at a time, as plain
  tabs. Arc's undo brings the split back.

Not there yet: Add Split View with its empty pane, the pane's Split View menu,
stacked splits, resizing, Arc's pane shortcuts, Open Link in Split View, the
Peek's split button, dropping a tab on the page, pinned and Favorite splits, a
split's title, its card in the tab switcher and its row in the command bar.
