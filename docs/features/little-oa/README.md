# Little Oa

Little Oa is Arc's Little Arc: a small window for one link or a quick search,
apart from the Spaces. It is a window style of the ordinary window, as in Arc,
with a sidebar container of its own that holds its pages and never shows.

## Opening one

- **File ▸ New Little Oa Window** (⌥⌘N) opens the command bar alone, 490 × 329
  at the top right of the pointer's screen. Return grows that window into the
  page window about the bar's centre; Escape closes it.
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
screen. It grows out of the pointer on Peek's spring. The frame is saved when a
page window is moved or its resize ends.

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
first and loads the page again there. A Little window left without pages fades
away.

The profile chip lists the profiles that have a Space. Switching asks, loads the
shown page again in that profile, and remembers the profile for the page's host.

⌘W closes one page into the Archive and the window goes with its last one; the
red button archives them all. Restore Last Closed Tab has nothing to bring back
here, as in Arc. A Little window whose pages have all been inactive for the time
in Settings ▸ Links ▸ "Archive Little Oas after" (1, 6 or 12 hours) is archived
by a sweep every five minutes, unless a page plays or records. A page that is
shown in a visible window counts as active.

A permission request is a card under the bar with Not Now and Allow, ended only
by its buttons. Developer Tools open in their own window. The first two windows
opened by the File menu or a link from another app carry a tip.

## Engine

A Little window's Browser is Chromium's popup type. Patches 0026 to 0029 give
the app's split view and Little window dispositions of their own, add the menu
command, keep a popup's new tabs in its own strip and keep a popup from asking
for the last session. The menu's open comes to the app as an address, which
opens its own window. Blink's ⌘⌥-click reaches the app as a background page.

## Oa's own

- Little windows never come back after a quit: Arc brings them back only after
  an update's relaunch, which Oa hasn't. Their pages go to the Archive at a
  quit.
- Escape keeps a page window; what Arc's does wasn't seen.
- A ⌘⌥-click's page is the engine's, moved to the Little window on the opener's
  profile; who makes it in Arc is unknown.
- After a profile switch the window's hidden pages follow when next shown,
  where Arc's keep running in the old profile.
- With no standard window open, Open in opens one on the Space; Arc's code
  makes none.
- Open Link in Little Oa inside a Little window opens another.
- The Library and Downloads menu items are off in a Little window.
- A link inside the app that Air Traffic Control routes to Little Oa opens
  where Most Recent Space would.

## Not here

The Archive's Little Arc filter, the downloads tray card, extensions in the bar,
the Dock menu's rows, a menu-bar launcher, Arc's panel over another app's full
screen, and back with no history closing a page to its opener, which is Arc's
rule in every window.
