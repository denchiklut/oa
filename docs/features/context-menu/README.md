# Page context menu

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

A right-click in a page shows Chrome's own menu as a native macOS menu, as it
does in Arc: Chromium builds the model for what was clicked, runs it through
its Cocoa menu controller over the page's view, and executes the chosen item as
a Chrome command. The app draws nothing and adds nothing, which is Arc's shape
too: Arc's app is asked once per menu and always declines to take it. A page
that calls `preventDefault()` on `contextmenu` gets no menu, and the menu takes
the page view's appearance. AppKit adds its own rows to it, Services, Writing
Tools and AutoFill, as it does in Arc.

Core no longer swallows the request, so it reaches the view delegate Chrome
makes for every page. That delegate reads the clipboard first, which is why
Paste and Paste and Match Style are enabled only with something to paste, then
builds the menu and shows it. Chrome's Cocoa menu expects the page to sit in
one of its own windows and showed nothing in Oa's. Patch 0009 lets it show
without one, as ArcCore's patched menu does, and adds a hook Core uses to edit
the model before it is shown.

## Items

The order, labels and separators are Chrome's. Core's hook makes two kinds of
change:

- **The search leads.** With text selected off a link, "Search ‹engine› for
  “…”" moves to the top, ahead of Copy and of spelling suggestions, with Look
  Up above it, as in Arc. On a link it stays where Chrome puts it.
- **Items Oa can't back yet are removed**, not hidden, since Chrome's Cocoa menu
  keeps the separators around a hidden item; the hook's caller collapses the
  separators left over.

| Context | Items |
| --- | --- |
| Page | Back · Forward · Reload \| Save As… \| View Page Source |
| Link | Open Link in New Tab · Open Link in New Window \| Save Link As… · Copy Link Address \| Copy · Copy Link to Highlight · Search ‹engine› for “…” |
| Image | Open Image in New Tab · Save Image As… · Copy Image · Copy Image Address · Search Image with ‹engine› |
| Selected text | Look Up “…” \| Search ‹engine› for “…” · Copy · Copy Link to Highlight \| Speech ▸ |
| Editable field | Look Up “…” \| Search ‹engine› for “…” · Emoji & Symbols \| Undo · Redo \| Cut · Copy · Paste · Paste and Match Style · Select All \| Language Settings · Writing Direction ▸ |
| Misspelled word | Search ‹engine› for “…” · suggestions \| Add to Dictionary \| Look Up “…” \| Undo · Redo \| Cut · Copy · Paste |
| Video and audio | Loop · Show All Controls \| Open in New Tab · Save As… · Copy Address, and for video Save Video Frame As… · Copy Video Frame |
| Frame | the page's items, with View Frame Source · Reload Frame |
| PDF | Back · Forward · Reload \| Save As… \| Rotate Clockwise · Rotate Counterclockwise |

Removed until Oa has the feature behind them: Open Link in Split View, Open
Link in Incognito Window, Inspect, Print…, Cast…, Translate and Picture in
Picture. Arc also has Open Link in Little Arc and Capture Image…, which are its
own additions to Chrome's model and aren't added. Removed as Arc removes them:
Create QR Code, Send to Your Devices and Open Link as ‹profile›, along with
Chrome's Lens, reading mode, Glic and password items, and Dictation, which
Arc's menus don't have. Use Enhanced Spell Check is removed too, Oa's own
choice: Arc keeps it, and in Oa Chrome's confirmation opens as a window of its
own with its heading cut off.

Two labels differ from Arc's. Arc says "Search Google for Image", where this
Chromium says "Search Image with Google". Copy Link to Highlight copies
Chrome's text-fragment link (`#:~:text=`), Oa's own choice for now: Arc's app
takes the link and copies a Shared Quote with a toast.

## Opened pages

Every item that opens a page goes through the path a link takes, so the new
page keeps its opener and is placed as Arc places it:

- **Open Link in New Tab**, **Open Image in New Tab** and the media ones make a
  background tab after the opener's earlier children; from a pinned tab with
  none, at the top of the unpinned section; from a [Peek](../peek/README.md),
  after its tab's children with the Peek left up.
- **View Page Source**, **View Frame Source**, **Search ‹engine› for “…”**, the
  image search and Language Settings make a selected tab in the same place.
- **Open Link in New Window** opens a new window beside the first, on the same
  Space, with the link as its selected tab. The tab is an ordinary one, placed
  as the others, and stays in the Space when that window closes.

A Shift-click also reaches the app as a new-window open, and still makes a
Peek. Core tells the two apart by who asked: an open is the page's own when
its renderer started it or made the page, as a link, a Shift-click and
`window.open` do, and the browser's when Chrome started it for the user, as the
menu does. DevKit carries that on the opened-page event, and the app makes a
Peek only for the page's own. In Arc the Shift-click never arrives as a
new-window open; its app decides the Peek from the page's navigation.

An incognito open is no longer mapped to a new window, which would have opened
it in the same profile; it is refused until Oa has incognito, and its menu item
is removed.

The stub engine's pages have a short menu of their own, Back, Forward, Reload,
Open Link in New Tab and Open Link in New Window, so the app's side can be
tried without Chromium.

Not checked in Arc, so not decided here: the menu on a Favorite, in an
incognito window and on `chrome://` pages, and what a pinned tab's Search and
View Page Source do. In Oa a pinned tab's foreground opens go to a Peek, these
included.

Related: [Sidebar state](../sidebar/README.md) · [Peek](../peek/README.md) · [Downloads](../downloads/README.md).

Return to the [feature inventory](../README.md).
