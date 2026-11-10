# Favorites

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

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

Related: [Sidebar state](../sidebar/README.md) · [Peek](../peek/README.md) · [Saved state and recovery](../saved-state/README.md).

Return to the [feature inventory](../README.md).
