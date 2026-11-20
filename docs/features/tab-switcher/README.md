# Recent-tab switcher

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

⌃⇥ and ⌃⇧⇥ switch between a window's recent tabs, as Arc's switcher does. A
quick tap goes straight to the previous tab; holding Control shows a row of up
to five cards to pick from.

## The list

The list is the window's own, built when the shortcut is pressed from the dates
the window already keeps (`lastActiveDates`, else `createdDates`, as Arc's
`itemLastActiveDates` and `itemCreatedDates`): the tabs this window showed or
made, newest first, with the tab it shows moved to the front. It holds tabs of
the window's profile only, from every Space of that profile, Favorites and
pinned tabs among them. A tab enters as soon as it is selected, with no dwell
time, and leaves when it is closed or archived. Five cards are shown; a sixth
is kept out of sight so the row refills when a card's tab is closed. A window
that has shown nothing in the profile has no switcher.

## Keys

The two shortcuts are hidden items of the Tabs menu, as in Arc's. They close the
command bar first. ⌃⇥ starts on the second card, which is the previous tab, or
on the first when the window shows no tab; ⌃⇧⇥ starts on the last card.

If Control is already up when the shortcut is handled, the tab is selected at
once and nothing is drawn. Otherwise a local event monitor takes every key
until the switcher goes, and the panel appears 0.1 s after the shortcut:

| Key | Does |
| --- | --- |
| Tab, → | next card, wrapping |
| ⇧Tab, ←, ⌃\` | previous card, wrapping |
| W | closes the highlighted card's tab as ⌘W would |
| Escape | closes the switcher, the tab stays |
| anything else | nothing, Return and ↑ ↓ included |

Releasing Control selects the highlighted tab the way a click on it would, and
switches Space when the tab is in another. Releasing only Shift keeps the
switcher. Moving the pointer over a card highlights it and a click selects it.
The app losing focus, or the window changing Space, closes the switcher with
nothing selected. So does the window giving up the keyboard to another window,
which is Oa's own: what Arc does then is unknown.

As in Arc, the cards follow the pointer's moves, so a card that comes up under
a pointer at rest isn't highlighted, and after a close the highlight keeps its
place in the row, which is the card that took the closed one's place. Oa's own:
a tab closed from its card stays out of the row until the switcher goes, a
pinned tab or a Favorite too.

## The panel

A borderless child window of the browser window, centred on its frame, that
never takes the keyboard. The sizes and colours are Arc's as measured: a 190 pt
strip, 32 + 181.75 pt a card wide, with 24 pt corners; each card a 157.5 × 105
picture of the page, its favicon and a one-line title; the highlight a rounded
rectangle in the Space palette's `hover` in dark and its `focus` at half
strength in light, as Arc's. Nothing animates.

The shown page's picture is asked for when the shortcut is pressed. Every other
tab has the picture taken when its page was last hidden in a window, kept in
memory by DevKit's `ContentSnapshotClient`, named after Arc's cache. Like
Arc's it holds 20 pages and drops the one stored or shown longest ago. A tab
with no page, or whose picture was dropped, has a blank card.

Arc fills its cache differently: its engine makes tab thumbnails (Chromium's
`ThumbnailTabHelper` behind ArcCore's thumbnails generator) and the app stores
each one it is handed. Oa's Core reports such thumbnails too, and so far only
the toolbar's colour uses them. The switcher doesn't yet: the UI asks for the
page's `snapshot` as it hides the page and keeps it at up to 600 pixels across.
So a card shows its tab as it was left, where Arc's shows it as it was after
its last load, URL change or return.

## What is left out

- A Peek isn't drawn on its tab's card.
- The shortcuts can't be rebound; Arc's Settings ▸ Shortcuts can.
- Arc's flag-gated Cycle Tab Forward and Backward, which walk a per-Space
  history with no panel.
- A page that cancels every key press also keeps ⌃⇥ from the menu, as it does
  any of Oa's shortcuts: the page gets a key first and the menu only what it
  leaves.

| Layer | Holds |
| --- | --- |
| UI | `ModalItemSwitcher/`: the cards' state, the window controller with the key monitor, the panel view; the list, commit and close in `WindowModel` |
| DevKit | `ContentSnapshotClient`: a page's last picture, taken through its `snapshot` |
