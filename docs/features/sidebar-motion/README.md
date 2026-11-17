# Sidebar motion

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

How the sidebar is shown and how it moves: docked or hidden, the floating panel
of a hidden one, resizing, the swipe between Spaces, and the Library with its
page of Space cards. All of it is in the app. DevKit, Core and Chromium take no
part. The numbers are Arc's, measured frame by frame on Arc 1.173.1 and read
from its code. Where the two disagreed the measurement was used, and the cases
are named below.

## The window's layout

`WindowLayoutController` is the window's content view controller, as Arc's is.
It hosts the window's view, owns the pager and the hover tracker, and holds
what the layout is made from: the window's size, how the sidebar is shown, the
width a resize drag is at, and where the pager is. The views read those and
place themselves. Nothing else decides a position.

The sidebar is one view in every mode. Docked, it is a column on the window's
surface. Hidden, the same view sits in a panel that floats over the page, so
its rows, scroll positions and hover states carry over.

## Docked and hidden

A window's sidebar has a mode, `anchored` or `noChrome`, as Arc names them. It
is the window's own and is saved with it in `windows.json`. A change also
becomes the default a new window takes (`sidebarViewPreferences`), as seen in
Arc. The header's toggle at x 77, View ▸ Hide Sidebar / Show Sidebar and ⌘S
flip it. The menu action is `toggleSidebarMode:`, not `toggleSidebar:`, which
AppKit's own responders answer first.

Docked, the page card starts at the sidebar's width. Hidden, it is 10 pt in
from every edge and the sidebar is past the window's left edge by its width and
10 pt more. Both move together over 0.08 s on Arc's curve (0.25, 0.46, 0.45,
0.94), and the page is resized on the way, as Arc's is. Recorded, the card's
edge lands on Arc's frames on hide and on the second half of show.

## The floating panel

A hidden sidebar comes out as a panel 5 pt in from the window's left, top and
bottom, at the sidebar's width: the theme over a blur of what the window shows
under it, 12 pt corners (Arc's code for macOS 26; side by side with Arc's
capture it matches), a 1 pt rim of white at 30% and a shadow fitted to Arc's
over a white page (black 16%, radius 4, 1 pt down). Its colours are the part of
the window's gradient that lies under it, as Arc's captures read, where Arc's
code pins its theme view to the panel. The page keeps its full width under it.
The header moves with it, so the window buttons are at 17, 21 and the toggle
reads "Lock sidebar", which docks it: the panel reshapes into the column over
the same 0.08 s.

`WindowHoverTracker` decides when it comes and goes, with Arc's regions, in
points from the window's top left for its 10 pt inset:

| Region | Where | Linger |
| --- | --- | --- |
| Inner left edge | x 0–6; once the pointer is in it, or is outside the window, x −20–15 | 0.15 s |
| Outer left edge | x −250–0 while the pointer is over the window or in the region, else x −50–0 | 0.16 s |
| Inner top left edge | x 0–40, y −15–20 with the pointer over the window | 0.15 s |
| Above the window | x −50–90, up to 50 pt above the window, never into the menu bar | 0.15 s |
| Sidebar | the sidebar's width docked, 80 pt more while floating, nothing while hidden | 0.15 s |

A region counts once the pointer has been in it for its linger, or has paused
in it for 0.08 s (the edges only). Once the sidebar is out, being in any of
them keeps it, so it stays until the pointer is 80 pt past it. The two upper
regions are off while the toolbar is shown and nothing is selected, as in Arc.
Only the key window of the active app tracks. The slide is a spring of response
0.17 s and damping 0.8 as measured (Arc's code reads a period of 0.18 s).
Recorded: first movement 128–138 ms after the pointer rests at x 4 (Arc
113–136 ms), the same points reveal and don't as in Arc's table, and the panel
leaves 28–40 ms after the pointer passes x 320 (Arc 33 ms).

The presentation is derived in Arc's order: a docked sidebar is `locked`; under
the Library a hidden one is `hidden`; it is `floating` while the pointer is in a
region, while no tab is selected, and while a permission prompt needs the
address field it hangs from; and a floating one stays while one of its menus is
open, a row is dragged, or Site Controls hangs from its field.

## Resizing

An 8 pt region across the sidebar's trailing edge, 11 pt short of the window's
top and bottom, resizes it, with Arc's limits: 164 to 500 pt. A docked sidebar
dragged below 82 pt shows as hidden, and let go there it hides, keeping the
width it had before the drag. A double-click resets it to 228 pt, and a slow
drag within 14 pt of 228 snaps to it with a tap. The band, the 50 pt/s and the
0.5 s between taps are Arc's constants; how Arc combines them was not decoded,
so that reading is Oa's own. The width is the window's, saved with it, with the
same default for new windows, 241 pt to start as Arc's was measured. Favorites
keep tiles at least 47 pt wide, so the narrowest sidebar has two to a row. Back,
forward and reload end 6 pt from the sidebar's edge, as measured at 241 pt, and
a sidebar under 215 pt, too narrow for them beside the toggle, drops them: Oa's
own, as what Arc's header drops is unknown.

## Swiping between Spaces

`PageSwipeController` is Arc's pager: pages side by side along one position in
points. The window's pages are the Library, 417 pt of travel, then one per
Space, each the sidebar's width.

- **Input.** A two-finger horizontal swipe that starts over the sidebar. Scroll
  views send the start of a swipe they have no use for up the responder chain
  (`wantsForwardedScrollEvents(for:)`), and the pager reads the rest from the
  window itself, as Arc's does. A wheel's ticks have no phases and a scroll
  view keeps those, so they reach the pager through the window's event
  monitor.
- **Following.** The position moves half the fingers' distance. The first
  event of a gesture moves nothing, as in Arc.
- **Release.** With any speed over the last 100 ms (5 pt/s, which two events in
  that window give) the pager goes one page that way; held still, to the
  nearest page. One gesture moves one page at most. The Space is selected at
  lift, before the settle, so the page card changes then.
- **Settle.** A spring of response 0.22 s and damping 0.93, inside what was
  measured (Arc's code reads 0.4 and 1). Its clock starts with its first frame
  and never jumps a long frame, so selecting the Space delays it rather than
  cutting into it.
- **Ends.** Past the last Space the pages give by Arc's rubber band, about 15%
  of the pull at first.
- **Wheel.** A unit of horizontal travel flips one page, then the wheel is
  ignored for 0.25 s.

Only the Space's page moves: its pinned tabs, divider and unpinned tabs, each
with its own scroll position. The header, the URL field and the dock stay.
Docked, the pages are cut at the sidebar's edges, under the card's shadow;
floating, at the panel's. Favorites belong to a profile: between two
neighbouring Spaces of one profile they stay put, and between Spaces of
different profiles they slide with the page.

The dock shows a dot for each Space, 8 pt and 26 pt apart, closer once they
don't fit and 4 pt for the others below an 18 pt pitch (Arc's are 4 pt at ten
Spaces; where exactly they shrink is Oa's own). The current Space's dot is
darker and nothing else, and during a swipe the two Spaces' dots cross-fade
with it. A dot's tooltip is the Space's name, and its menu has Rename, Set
Profile and Delete. Arc's icons wait for Spaces to have them.

Recorded against Arc's captures: the page follows each event at 0.5; held at 48
and 98 pt it returns, at 148 pt it commits; flicks of 1 and 3 pt commit; one
event in the last 100 ms does not; the settle back runs a frame ahead of
Arc's.

## The Library

The Library is the pager's first page, before the first Space. One progress
value, 0 among the Spaces and 1 with the Library open, places everything:

| Part | By progress p |
| --- | --- |
| Library | at its full width L, moved left by L·(1 − p) |
| Page card | its leading edge at s + (L − s)·p, where s is the sidebar's width docked and 10 pt hidden; it keeps its width and runs off the window's trailing edge |
| Docked sidebar | in place, shrinking by a tenth toward a point 26 pt to its right, gone at p 0.08 |
| Floating panel | moved left by its width and 10 pt, times p |

L is `max(417, min(window − 56, what the section asks))`: 417 pt for Downloads
and Archived Tabs, and 264 pt per Space plus 216 for Spaces. The sidebar's fade
is the measured one; Arc's code reads gone at p 0.5.

A swipe right from the first Space drags the Library in over 417 pt of travel,
and held at 220 pt the card is where Arc's was (786 against 785). Its release
follows the Space rules. The buttons (the dock's Library button, the rail's
arrow, the menu items) run the same position on a critically damped spring of
0.205 s; recorded, the close is Arc's curve. Arc's open stalls 180–250 ms
before it draws. Oa's doesn't: the theme's bitmap is computed once for the
cards.

From any Space the Library opens straight in: the pager counts its Space pages
from the window's Space while the Library is involved, as Arc's does, and from
the first Space otherwise. So only a swipe from the first Space reaches the
Library; from the others a swipe right goes to the Space before.

With the Library in view a swipe may start anywhere in the window. A hidden
sidebar is hidden under the Library. A tab's Peek is over its page, so it goes
where the card goes, Oa's own: Arc's wasn't looked at there. Moving between sections of different
widths animates on the same spring, Oa's own: Arc's was not measured.

## Library ▸ Spaces

The rail has Downloads, Spaces and Archived Tabs, in Arc's order, and its own
window buttons at 16, 21. The Spaces page is a row of cards that scrolls
sideways: each 240 pt wide and 96 pt shorter than the row, 24 pt apart and
24 pt in, then a 48 pt item with a 30 pt plus that adds a Space. A row that
fits is centred, so with four Spaces at 1400 pt the first card is at x 140 and
the page card at 1272, as in Arc. Scrolling the cards from either end carries on
into the window's swipe, by the same forwarding as in the sidebar.

A card shows the Space's name and its tabs, pinned over unpinned, with the
window's selection in that Space marked. Arc's card holds the Space's live
sidebar view. Oa's own until rows are shared with it: a click on a row goes to
that Space and tab, and a row has no other actions there. The plus asks for a
name with the existing prompt until the Create a Space panel is here.

At rest the row is cut at the page card's edge, as Arc's is, which can be
mid-card. While the Library comes in or leaves, Arc cuts the row at the
Library's own moving edge, mid-card and short of the page card. Oa's own, by
the author's decision, after open-arch: the cut follows the page card's edge,
and the one card the settled edge will cut is moved in whole and slides under
the edge as the Library settles. A settled edge in a gap moves nothing.

## Not there yet

Per-Space themes and icons, so nothing blends during a swipe. The pull past the
last Space that creates one, and the Create a Space panel. Reordering cards.
Full screen: the window's own buttons show there as Arc's do, and the rest is
as outside it. Arc's other shortcuts for Spaces and the sidebar. Reduce Motion.
