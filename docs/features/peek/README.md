# Peek

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

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
children, the same live page with no reload, and asks nothing. ✕, a click on
the backdrop and ⌘W close the page as the user would, so a `beforeunload`
handler can keep the Peek with "Leave site?" over it, as Arc does, and archive
it under the tab's Space once it is gone, as do archiving the opener, closing
the last window and quitting; a page that closes itself leaves no entry. When
another window takes the tab's page, on selection or because its window closed,
the Peek goes with it, as Arc's does. A tab has
one Peek: a new request while one is up closes the current one as ✕ would and
archives it at once, Oa's own choice. The entry has no position, so it restores at the top of the
unpinned section, also Oa's own: Arc's entries carry no visible position.
Nothing about a Peek is saved, so none survives a relaunch, as in Arc.

Clicking an Archive row shows the entry's page in a Peek over the list, made
from the saved URL with no history, centered over the whole window as Arc does
over its Library; the entry stays. Its Expand removes the entry and puts the
tab, selected, at the top of the unpinned section of the Space the window
shows, as Arc does. When another window has already brought the entry back,
Expand selects that tab instead of adding a second row, Oa's own choice after
Arc's ⇧⌘T, which selects a tab that is already open. Closing it, or leaving the Archive view, closes the
page and keeps the entry; leaving the view is Oa's own choice. A page such a Peek opens
has no tab to join, so it goes to the top of the shown Space, Oa's own choice.
Arc's Split View button and copy-link icon don't exist in Oa yet.

Related: [Sidebar state](../sidebar/README.md) · [Favorites](../favorites/README.md) · [Saved state and recovery](../saved-state/README.md).

Return to the [feature inventory](../README.md).
