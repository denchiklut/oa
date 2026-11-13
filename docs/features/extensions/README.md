# Extensions

Oa implementation notes. The [Chromium chapter](../../architecture/chromium/README.md)
describes the broader intended responsibilities.

Chrome extensions install from the Chrome Web Store and run in Oa as they do
in Arc: Chromium's extension system is untouched, and the app draws the parts
Chrome would draw with its own views. Core gives each window's `Browser` an
extensions container of its own, as ArcCore does, and patch 0010 lets Core
answer for Chrome's install and uninstall dialogs, both of which ArcCore
replaces.

## Installing and removing

The store's own button starts the install. Chrome then asks before it goes on,
and the question reaches the app through the page that asked: a panel 450 pt
wide over the dimmed window, with Oa's icon, the extension's, "Add the
“‹name›” extension to Oa?" and Chrome's permission warnings under "It can:",
or "This extension requires no special permissions." Return adds the
extension and Esc cancels. Nothing is shown once the install ends, as in Arc.
A new install is pinned, which is Chromium's own doing in this version.

Removing asks the same way, "Remove “‹name›” extension from Oa?", whichever
path started it: the extension's menu, the store's button or Chrome's
extensions page. A request the app lets go of unanswered, as when its page
closes, is declined.

The panel is drawn in the window, as Oa's other dialogs are; Arc uses a child
window. It stays with its page while another tab is shown. Chrome's prompts to
re-enable an extension or grant it more permissions are declined for now.

## Where extensions show

- **Extensions menu.** The profile's extensions by name, each running its
  action; a disabled blank item when there are none, as Arc has; then Add
  Extension…, which opens the store's extensions page in a new tab, and Manage
  Extensions…, which opens `chrome://extensions`.
- **Site Controls.** An Extensions section as Arc's: 48×32 tiles four to a
  row, then "+" for the store. A click runs the action. A pinned extension
  carries a pin badge on its tile's corner; one that isn't shows a pale badge
  only while its tile is under the pointer, and a click on either toggles the
  pin. While the pointer is over the section, "Manage" shows at the end of its
  header line and opens `chrome://extensions`. The "…" menu has Manage
  Extensions… and Add Extension… too.
- **The extension's menu.** A right-click on a tile shows Chrome's own menu
  for the action as a native menu, with Arc's wording and order for the
  removal and the pin: Remove from Oa, then Pin or Unpin.

Pinned extensions have no place in the toolbar yet, so a pin only shows as the
badge.

## Popups

An action's popup page opens in a titled window with no title, 50 pt in from
the browser window's right edge and 10 pt below its top, sized by the page
within Chrome's limits (25×25 to 800×600), and closes when it stops being the
key window, as Arc's does. Core keeps the popup's host where Chrome would
build its bubble and hands the app the page's view and size. One popup shows
at a time.

## Pages an extension opens

A tab Chromium puts in a window itself, as `chrome.tabs.create`, a link in a
popup and the menu's Manage Extension do, becomes a tab at the top of the
Space, selected when Chromium made it the active one. Arc adopts these the
same way; where it puts them is unknown, so the place is Oa's own.

## Layers

| Layer | Holds |
| --- | --- |
| UI | The Extensions menu, the Site Controls section, the consent panel and the popup window |
| DevKit | `Extensions` per profile, `Browser` per window and profile (toolbar actions, popup, engine-opened pages) and the page's extension request |
| Core | An observer of the profile's extension registry, the extensions container with the popup host and Chrome's menu, and the bridge from Chrome's two dialogs to the page |
| Chromium | Patch 0010 |

The stub engine has a small catalog: its pages have an "Add an extension"
link, and its actions open a placeholder popup that can grow, open a tab and
close itself.

Not done yet: pinned extensions in the toolbar, side panels, tab groups,
omnibox keywords, extension commands and their shortcuts, windows an
extension creates, the re-enable and permissions prompts, install errors and
unpacked extensions.

Return to the [feature inventory](../README.md).
