# Split View

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

A split shows two to four tabs side by side or stacked in the page's place, as
Arc's does. It is one entry of the sidebar whose children are its tabs in pane
order, and each pane is an ordinary tab with its own page.

- **Making one.** A row's menu ▸ Open in Split View puts that tab on the right
  of the selected one, or adds it as the last pane of the selected split. ⌥Return
  in the ⌘T bar opens the address in a new tab on the right of the current one.
  The new pane takes the focus. A split holds four panes at most, Arc's limit.
- **Add Split View.** View ▸ Add Split View ⌃⇧=, New Split in the dock's "+", Add
  Split View in the selected row's menu and Add Tab… in a split's open an empty
  pane at the end with the command bar. Return opens the row in a new tab in
  that pane, Switch to Tab moves that tab into it, and Escape or the pane's ✕
  takes the pane away. Nothing is stored until the pane is filled, and no pane is
  outlined meanwhile. The binding is Arc's `addSplitView`, which a page sees
  first; it can be changed in [Settings ▸ Shortcuts](../key-bindings/README.md).
- **The pane's menu.** The focused pane's bar has Arc's Split View menu before
  its ✕: Move Left and Move Right, Add Right Split and Add Left Split, which
  open the empty pane beside this one, Separate Tab from Split, and Convert to
  Vertical Split View. In a stacked split they read Up, Down, Top, Bottom and
  Horizontal. A pane at an end can't move past it, and a full split takes no
  pane.
- **Stacked splits.** Convert turns every pane and keeps the factors. A stacked
  pane's bar shows the whole address after its scheme.
- **Resizing.** The gap between two panes is the handle, with a 2 × 24 pt grip
  and the resize cursor. A drag moves the edge with the pointer, with no
  snapping, and neither pane beside it goes under 220 pt. A double click gives
  the two panes equal parts over about 0.19 s. The window keeps its own sizes
  for the split it shows, and the split's stored factors take them when the
  resize ends, so another window and a later selection start from those.
- **Panes.** They share the page's area by the split's factors, equal until a
  pane is resized or one is added, 10 pt apart and none under 220 pt, so panes that don't fit
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
- The panes are equal while one is empty; Arc's sizes with an empty pane beside
  resized ones weren't seen. The menu's icons are near Arc's, not its own.
- From the empty pane, Switch to Tab on a tab that can't be in a split, as a
  pinned one, switches to it.
- Reload leaves a pane's bar under 300 pt. Arc's had none at 278 pt and one at
  421 pt.
- The focus outline is the theme palette's shaded entry in dark and its darkest
  in light, which gives Arc's blues on the default theme; other themes weren't
  measured.
- Closing a split from its ✕ comes back with ⇧⌘T a tab at a time, as plain
  tabs. Arc's undo brings the split back.

A permission prompt shows once its pane is the focused one, as Arc's waits for
that. Arc's then closes by itself, unanswered; Oa's stays until it is answered.

Not there yet: Arc's pane shortcuts, Share Split View…, Site Controls and the
link and lock on a pane's bar, Open Link in Split View, the Peek's split button,
dropping a tab on the page, pinned and Favorite splits, a split's title, its
card in the tab switcher and its row in the command bar.
