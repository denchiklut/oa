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
- **From a link.** The page menu's Open Link in Split View opens the link in a
  pane on the right of its page, focused. A Peek's third control does the same
  with the Peek's page. So does an ⌥-click on a link, also on an image link or a
  `download` one: Blink makes it a save, which every page hands to the browser
  at once (patch 0020), Core passes it on as a background page, and the window
  puts a background page in a split while ⌥ alone is held, as Arc's does. Any
  open of a page in a new foreground tab while the click had ⌥, as a
  `target=_blank` link or a `window.open`, is a split too, by ADK's rule. An
  ⌥-click inside a frame is a download, as in Arc.
- **Dropping a tab on the page.** A sidebar tab dragged over the page shows
  where it would go. On a lone page an edge makes a split with it: the outer
  40 % at the sides, 50 pt at the top and 40 pt at the bottom, and the top and
  bottom make a stacked one. The page moves aside without being resized, over
  0.2 s, and an outlined pane takes the other half; an edge once entered holds
  over that half. The page's middle only outlines it, and a drop there selects
  the tab. In a split, an edge of a pane inserts the tab there while there is
  room, and the rest of the pane replaces its tab, which is a plain tab again
  right after the split. The dropped tab takes the focus. While the tab is over
  the page the window shows what it showed before the press.
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
  pane is resized or one is added, 10 pt apart and none under 220 pt, so panes
  that don't fit run past the window's edge. Each has a 32 pt bar in its page's
  colour: back and forward, copy link while it is wide enough, Arc's "Site is
  not secure" mark on a page that isn't, the host, and a ✕ that closes its tab.
  The focused pane also has reload and Site Controls while it is wide enough,
  and the Split View menu. A split has no window toolbar, and Show Toolbar is
  off while one is shown. In a split the sidebar's address field has Share
  Split View… in Site Controls' place, and shows the search prompt while an
  empty pane waits.
- **Focus.** The focused pane is the window's selected tab. It has a 2 pt
  outline inside its edge and a glow into the gaps beside it. A click on a
  pane's page reaches the page and focuses the pane: the engine reports which
  page has the keyboard, as ArcCore's `hasFocus`, and the window follows it. A
  click on a pane's bar focuses it too.
- **Sidebar cell.** One card for the split with a small card for each tab. A
  press selects the split with the pane the window focused in it last, and on
  the selected split the tab pressed. Under the pointer the selected split
  shows a ✕ for each tab, and one that isn't selected a single ✕ that archives
  all its tabs; Edit ▸ Undo, "Undo Archive Tabs", brings the split back whole,
  with its ID, where it was. Its menu has Share Split View…, Separate All Tabs,
  Add Tab…, Convert, and for each tab Separate from Split View and Archive Item.
- **Dragging a split.** A press anywhere on its cell, selected or not, drags
  the whole split, which stays selected. The copy is the cell as it looks
  selected and under the pointer, at 0.9. The list, the pinned section and the
  Favorites grid take the split whole; over the grid the copy turns into its
  tile, and a Favorite split's tile dragged out turns back into the cell. A
  split is never dropped on the page: the one under the drag is itself.
- **Dropping on a row.** A tab held on the middle half of another row for
  0.2 s from entering it turns that row into the split it would make, the held
  tab first and lit; the drop makes it there, a pinned row's in the pinned
  section, and the held tab takes the focus. Held on a split's cell, the cell
  lights up and the tab joins it first, or last from the cell's right half; a
  full split lights up and takes nothing. On a row's edges the line comes back.
  A split's cell and the Favorites never combine.
- **Change Icon….** The cell's and the tile's Change Icon… open the icon picker
  below the cell; a pick applies at once and the picker stays. A split with an
  icon is drawn as a row: the icon where a row's favicon is, then its title or
  "N Tabs"; a titled one's icon takes the count badge's place, and a Favorite
  split's tile shows only the icon. Reset Name and Icon, in the menu once
  either is set, clears both and brings the tabs back. Stored as the split's
  `customInfo` icon.
- **Duplicate.** The cell's and the tile's Duplicate put a copy right after the
  split, with new tabs at the same addresses and its title, layout and sizes.
  The copy isn't selected, and its pages load at once in the background.
- **Move to.** The cell's and the tile's Move to ▸ list every Space in the
  dock's order, then New Space…. The split goes whole, with its pages, to the
  top of that Space's list; a selected split takes the window to that Space,
  one that isn't leaves the window where it is. New Space… opens Create a Space
  and moves the split into the Space once it is made.
- **Dropping a link.** A link dragged from a page onto the list opens a tab at
  the line, loaded in the background; onto a split's cell it joins the split,
  loaded in the background, and the split isn't selected.
- **Pinned splits.** Pin Tab on a split's tab pins the whole split, Unpin Tab
  puts it back at the top of the list, children and sizes kept. A pinned split's
  tabs keep their pinned address, and its panes show no "/". On the selected
  pinned split the cell has one "—" under the pointer, and it and ⌘W unload all
  its pages and leave nothing selected, the split staying pinned; a pane's ✕
  archives that pane's tab and the other stays as a plain pinned tab. The ✕ of
  a pinned split that isn't selected archives its tabs.
- **Favorite splits.** Favorite Tab on a split's tab files the whole split under
  the profile's Favorites, as one tile in the grid: a 12 pt favicon on each
  pane's part; selected, one card with the panes' favicons' tint and ring, the
  ring also between the parts; not selected, a card for each part, 2 pt apart.
  A click selects the split with the pane focused last, ⌘W leaves nothing
  selected with its pages kept, and the tile's menu has Archive Item, which
  archives its tabs, and no Remove Favorite or Rename….
- **A pinned tab or a Favorite in a split.** Every way of making a split with
  one, as either tab, takes the tab's own item and page into a new split at the
  top of the list, and a copy keeps its place, its page loaded at once in the
  background at the address the page was at. Open Link in Split View from a
  pinned tab does the same, with no Peek.
- **A split's title.** Rename… in the cell's menu edits it in place, starting
  with "2 Tabs" selected. A titled split shows a 16 pt badge with its count
  where a row's favicon is and the title where a row's is, in place of its tabs.
- **Shortcuts.** As Arc's, and bindable in Settings ▸ Shortcuts: ⌃⇧1 to ⌃⇧4 focus
  a pane, ⌃⇧] and ⌃⇧[ the next and previous with wraparound, ⌃⇧- (View ▸ Close
  this Split Pane) closes the focused pane's tab, and View ▸ Separate Page from
  Split View has no key. The numbered ones are hidden menu items, as Arc's are.
- **Elsewhere.** The ⌃⇥ switcher shows a split as one card, its panes' pictures
  side by side in a white frame with a favicon under each, as Arc's. The command
  bar lists a split once, as Switch to Split View.
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
- Favorite Tab files a split under Favorites as well as a drag onto the grid,
  Arc's way. Unfavorite Tab puts it back at the top of the list. A tab dropped on the page of a pinned tab or a
  Favorite follows the copy rule, LIKELY as Arc's other ways in; Arc's wasn't
  tried.
- A titled split's badge is in the focus outline's colour, LIKELY Arc's (#2932E5
  and #2229DD measured on the default theme), and its corner radius is a guess.
  Clearing the title brings the tabs back; Arc's wasn't seen. With a title, a
  click selects the split, and the selected one has no ✕ under the pointer.
- The panes are equal while one is empty; Arc's sizes with an empty pane beside
  resized ones weren't seen. The menu's icons are near Arc's, not its own.
- Reload leaves a pane's bar under 300 pt. Arc's had none at 278 pt and one at
  421 pt.
- The focus outline is the theme palette's shaded entry in dark and its darkest
  in light, which gives Arc's blues on the default theme; other themes weren't
  measured.
- ⇧⌘T after a split's ✕ brings its tabs back one at a time, as plain tabs;
  only Edit ▸ Undo rebuilds the split. A pane's tab closed by its ✕ or ⌘W comes
  back into its split while the split is there, else as a plain tab. Arc's
  result for both wasn't seen.
- Share Split View… is there but off: Oa has no sharing.
- Change Icon… uses Oa's Space icon picker, SF Symbols and a short emoji list,
  where Arc's has its Ionicons and every emoji with a search; the icon is kept
  as a Space's is, a symbol's name or the emoji, not Arc's `iconType` shape.
  The icon's grey is the theme's secondary glyph, near Arc's measured #94939C,
  and a Favorite split's tile with an icon, selected, is a plain selected tile.
- Move to ▸ greys out the Spaces of other profiles, as Oa's pages can't change
  profile; Arc lists them, and its move there wasn't tried. Where New Space…
  puts the Space, after the window's, wasn't seen in Arc.
- A link held on a plain row opens at the line. Arc's goes into that tab's
  item, out of sight, which looks like a bug. A link dropped on a pane isn't
  handled by the app; Arc's opens as a tab after the split.
- ⌘⌥ on a link opens a background page; Arc opens Little Arc, which Oa doesn't
  have.
- A split's row in the command bar takes its focused pane's title; Arc's row
  title wasn't recorded. Picking it from an empty pane switches to the split;
  Arc's rule there wasn't made out.
- A split's drop edges are Arc's other zone sizes, a third of the pane up to
  80 pt at the sides and 50 pt at the ends, with no hold; Arc's weren't measured
  in a split. The page comes back when the dragged tab reaches the page, where
  Arc's comes back as the drag begins. Only a tab that can be in a split can be
  dropped, and the dragged copy stays a row.

A permission prompt shows once its pane is the focused one, as Arc's waits for
that. Arc's then closes by itself, unanswered; Oa's stays until it is answered.
