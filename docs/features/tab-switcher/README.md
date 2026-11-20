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

The two shortcuts are hidden items of the Tabs menu, as in Arc's, and a page
never gets them ([Shortcuts over a page](../key-bindings/README.md)). They close the
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

## The pictures

A card's picture is the engine's thumbnail of its tab's page, as in Arc:
Chromium's own tab thumbnail, the page's whole view scaled down to about 512
pixels across. The app starts observing a page's thumbnails the first time a
window shows it, and keeps every one the engine makes in DevKit's
`ContentSnapshotClient`, named after Arc's cache. Like Arc's it holds 20 pages
in memory and drops the one stored or shown longest ago. The card draws the
picture across its width from the top.

The engine makes a thumbnail at these moments, and a card shows the newest:

| When | As in Arc? |
| --- | --- |
| just after a document's `load` event, shown or hidden | yes |
| just after a URL change inside the document (`pushState`, `replaceState`, a fragment), shown or hidden | yes |
| ⌃⇥ or ⌃⇧⇥ pressed, for the shown tab | yes |
| as the tab stops being the window's shown one | Arc asks for it then too, but gets it only when the tab is next shown |

So a card shows its tab as it was left. Arc's shows it as it was when it last
came back, loaded or changed its URL, since its copy of a leaving tab arrives
late; Oa keeps the picture the same request gives it at once. Nothing else
makes one: not time on screen, a repaint, a title change or a subframe's load.

A tab that was never shown has a blank card, as in Arc, and so does a tab
with no page or one whose picture was dropped. While a document loads, its tab
has no thumbnail. After a relaunch the cache starts empty.

Two Chromium patches carry ArcCore's changes to the thumbnail code: when a
thumbnail is ready (0016), and the whole view copied without the strips a
scrollbar would take (0017).

## What is left out

- A Peek isn't drawn on its tab's card.
- The shortcuts can't be rebound; Arc's Settings ▸ Shortcuts can.
- Arc's flag-gated Cycle Tab Forward and Backward, which walk a per-Space
  history with no panel.

| Layer | Holds |
| --- | --- |
| UI | `ModalItemSwitcher/`: the cards' state, the window controller with the key monitor, the panel view; the list, commit and close in `WindowModel` |
| DevKit | `ContentSnapshotClient`: a page's last thumbnail; a page's `startObservingThumbnails()`, `stopObservingThumbnails()` and `requestThumbnail()` |
| Core | Observing a page's thumbnails, which subscribes to Chrome's tab thumbnail; the request, through Chrome's own copy |
| Chromium | Patches 0016 and 0017: ArcCore's readiness rule and whole-view copy |
