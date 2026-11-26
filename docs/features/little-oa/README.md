# Little Oa

Little Oa is Arc's Little Arc: a small window for one link or a quick search,
apart from the Spaces. It is a window style of the ordinary window, as in Arc,
with a sidebar container of its own that holds its pages and never shows.

## Opening one

- **File ▸ New Little Oa Window** (⌥⌘N) opens the command bar alone, 490 × 329
  at the top right of the pointer's screen. Return grows that window into the
  page window about the bar's centre; Escape closes it, and so does losing the
  keyboard to any other window or app, as in Arc.
- The same shortcut works **from any app** while Settings ▸ Links ▸ "Open Little
  Oa when I press ⌥⌘N in any app" is on. It is a Carbon hot key, as Arc's, and
  follows the shortcut New Little Oa Window has in Settings ▸ Shortcuts.
- **Open Link in Little Oa** in the page's link menu, fourth as in Arc.
- **⌘⌥-click** on a link, while its switch in Settings ▸ Links is on. With the
  switch off the click opens a split, as in Arc.
- **Links from other apps**, while "Links from other apps open in Little Oa" is
  on, which is Arc's default. A route in Air Traffic Control wins over the
  switch, and a route or the default can name Little Oa itself.

A window opened on a link is the last Little window's size (1185 × 832 until one
has been moved or resized) and sits 30 pt right and down of the newest other
Little window, or about the pointer when there is none, always 20 pt inside the
screen. The frame is saved when a page window is moved or its resize ends.

A link's window opens and closes as Arc's does. It first covers its whole
screen, clear and without a shadow, while its card grows out of a 20 pt
rectangle at the pointer on Peek's expansion spring, so the card is never cut
to the frame it ends in; then the window takes that frame. Closing it, by ⌘W,
the red button or Open in, covers the screen again, floats the window if it is
key, and sends the card back towards the point it came from on the collapse
spring, fading on the way. A click that misses the card meanwhile is kept, not
passed to the window behind. With Reduce Motion the card fades where it is. A
window from the menu or the hot key does neither: it is at its frame at once
and just goes.

## Showing one

Every Little window is shown the way Arc shows one. If a window covers the
screen it opens on, another app's in full screen or one of Oa's own, the
Little window is a panel on that Space that doesn't activate Oa: the other app
stays in front with its menus, and the bar still takes typing. Anywhere else
it is an ordinary window and Oa comes forward a turn later. Either way it
comes to the Space in view, and as it takes the keyboard it is above every
app's windows for a moment before settling at the normal level. Entering full
screen makes it an ordinary window again, and it stays one afterwards.

A link goes into an open Little window instead of a new one only when that
window was opened on the very same address, still shows a page of that host and
that page can't go back. It becomes a new page in front.

The profile is the one of the last key window that is neither incognito nor
Little. A link from another app opens in the profile its host was last
switched to in a Little window.

## The window

A 47 pt bar over the page, in the default theme whatever the profile, as Arc's:
close and minimize, a green button that moves the page out as Open in does, back
when the page can go back, the URL field with the profile chip and Copy URL, and
**Open in ‹Space›** with a chevron. The field opens the command bar, which is
narrower here and offers no tabs. Full screen is ⌃⌘F or a page's own video.

Pages stay inside: `target=_blank`, `window.open`, ⇧⌘-click and ⌘T add a page
in front, and ⌃⇥ switches between the window's pages. ⌘-click and middle click
load in the shown page, as in Arc. ⇧-click opens a standard window, and ⌘⌥-click
another Little window. There is no Peek and no split.

**Open in** (⌘O, the button, the green button, or a Space from the chevron's
list with ⇧⌘O) moves the shown page live to the top of the Space, selected, in
the front-most standard window that shows it, else the front-most standard
window, which switches to it. The button names the Space the front-most
standard window of the profile shows, else the profile's first, worked out when
the window opens and each time it becomes key. A Space of another profile asks
first and loads the page again there. The Little window then closes, as in
Arc, and any other page it has goes to the Archive.

The chevron's list is a clear window of its own over the Little window, as
Arc's, drawn over the button. It has the keyboard while it is open: typing
searches the Spaces, ↑ and ↓ move the one lit row, Return moves the page to
it, and Escape, a click elsewhere or losing the keyboard closes it. The row
lit at first is the button's Space; after that it is the last one the pointer
or an arrow reached, and the first match once the search changes.

The profile chip lists the profiles that have a Space, and shows only in a
window made while more than one profile was in use, as Arc's. Switching asks
and makes the shown page again in that profile. As in Arc, the window's other
pages go on running in the profile they were made in, with their own Browser,
and show as they are when they are next shown; a link from one stays in its
profile. A window opened on a link also remembers the profile for the link's
host. Choosing the profile the window has does nothing. Open in tells another
profile by the window's profile, not the page's. So a page left in the old
profile, moved to a Space of the new one, isn't asked about and, as in Arc, is
lost: it shows in the standard window for a moment, closes with the Little
window and is archived from that Space, after the window's other pages. Doing
this Oa's own way is [#169](https://github.com/denchiklut/oa/issues/169).

⌘W closes one page into the Archive and the window goes with its last one; the
red button archives them all. Restore Last Closed Tab has nothing to bring back
here, as in Arc. A Little window whose pages have all been inactive for the time
in Settings ▸ Links ▸ "Archive Little Oas after" (1, 6 or 12 hours) is archived
by a sweep every five minutes, unless a page plays or records. A page that is
shown in a visible window counts as active.

A permission request is a card under the bar with Not Now and Allow, ended only
by its buttons. The first two windows opened by the File menu or a link from
another app carry a tip. The card, the tip, the bar and the list are drawn to
Arc's measures in both appearances.

Developer Tools open in a window of their own, at every open, because the
engine doesn't dock a popup browser's, as ArcCore doesn't. Their menu has no
Dock side. As in Arc, their own ⇧⌘D still docks them into the Little window's
page and changes the profile's dock side, and Open in closes their window as
it moves the page.

## Downloads

A Little window has its own downloads tray, as Arc's: a row of cards along the
bottom of the page, the oldest on the left. From the moment the window is made
it hears of every new download of its profile, whichever window starts it, and
of none that was there before or that an incognito window starts. Each window
keeps its own list. As in Arc, a profile switch doesn't move the tray: it goes
on with the downloads of the profile the window was made in.

A card is 250 × 56 with the file's icon, its name and the Library's line under
it; while the download runs the icon has a ring that fills clockwise. The row
is 20 pt in from the left and bottom, has no cap, and scrolls sideways when
the cards outgrow the window; a new card isn't scrolled into view. Only the
cards take clicks and scrolls: the strip around them leaves them to the page.
Nothing is animated. The tray doesn't show while the window is its bar alone,
and a download that started meanwhile has its card once the window is a page.

A click on a finished card opens the file; on any other card it does nothing.
A second click on the same card does nothing either until another card is
clicked or the row changes, as in Arc. The ✕, which shows with the hover
colour only under the pointer, removes the card and cancels the download
unless it finished or was already cancelled; a finished file stays. A card
never goes by itself.

As in Arc, the tray takes no failed or paused event, so such a card stays as
its last update left it. A download cancelled elsewhere reads "Cancelled · from
‹site›", and one removed from the Library leaves the tray. While the engine
asks where to save, there is no card, and cancelling there leaves none.
Several downloads from one page raise the permission card.

## Saved state

A Little window is a window style, as Arc's: its record in `windows.json` has
`style.little` where a standard window has `style.standard`, under Arc's keys.
It holds the session (id, entry point, preferred frame, start time), the
profile, whether to show the profile chip, whether the window is its bar or a
page, and the tray's downloads as Arc's `DownloadData`, the ones still running
as they last progressed. Its pages are in a `littleBrowser` container in `sidebar.json`. Both
files are saved together a few seconds after a change. The frame is not in the
record; the open Open in menu, the tip and the Open in target are rebuilt.

The entry point is coded as Arc codes it, the hot key's case included: Arc
writes it as a link with no address, which doesn't read back, so that record
reads as a standard window's. A paused download is written the same way.

At a quit nothing is closed or archived. A key Little window that is its bar
alone closes first when Quit is chosen; the others are written to the files as
they stand. At the next launch AppKit hands a Little window back and it is
refused: Arc restores one only on the relaunch after an automatic update, which
Oa hasn't. Its record goes at the first save. Its container and pages stay
until some window closes, then go without an Archive row. The idle sweep runs a
second after launch and takes such a container's pages into the Archive first
when they were all inactive for the set time.

## Engine

A Little window's Browser is Chromium's popup type. Patches 0026 to 0029 give
the app's split view and Little window dispositions of their own, add the menu
command, keep a popup's new tabs in its own strip and keep a popup from asking
for the last session. Patch 0030 tells a popup's DevTools frontend it can't
dock, which is upstream's rule and ArcCore's. The menu's open comes to the app as an address, which
opens its own window. Blink's ⌘⌥-click reaches the app as a background page.

## Oa's own

- The record's profile is Oa's profile ID, and its dates are in the file's
  date form, as everywhere in Oa's files.
- A card in a light window: its text and the ✕'s hover disc mirror the dark
  one, which is the only one seen in Arc.
- The icon of a download that still runs is drawn large in its circle, as
  seen in Arc, at a size and offset read off a capture.
- The pages the sweep archives from a window that didn't come back are filed
  under Little Arc; Arc's source for them is unknown.
- AppKit's saved state says only that the window is a Little one; Arc's also
  says minimised and full screen, for every window.
- Escape keeps a page window; what Arc's does wasn't seen.
- A ⌘⌥-click's page is the engine's, moved to the Little window on the opener's
  profile; who makes it in Arc is unknown.
- With no standard window open, Open in opens one on the Space; Arc's code
  makes none.
- Open Link in Little Oa inside a Little window opens another.
- The Library and Downloads menu items are off in a Little window.
- A link inside the app that Air Traffic Control routes to Little Oa opens
  where Most Recent Space would.
- The profile chip's glyph: Arc draws the profile's own icon, and Oa's
  profiles have none yet.
- The Open in list is never narrower than 244 pt; Arc's was only seen under a
  long Space name.
- How far the card's shadow spreads while the window covers the screen.
- Arc's window presents through the controller its Peek uses. Oa's Peek is a
  view inside its window, so the Little window has that controller to itself.
- The bar has no grain.

## Not here

Extensions in the bar, the Dock menu's rows, a menu-bar launcher, and back with no history closing a
page to its opener, which is Arc's rule in every window.
