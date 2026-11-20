# Shortcuts over a page

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

While a page has the keyboard, the page gets a key before the app does, and
the main menu only the keys the page leaves. A page that cancels every key
press would so keep ⌘T or ⌘W from doing anything. As in Arc, some shortcuts
never reach the page.

## Priority

Each of Arc's menu items with a shortcut carries a priority, and Oa's menu
gives its items the one they have in Arc:

| Priority | Who gets the key | In Oa |
| --- | --- | --- |
| `overrideWebView` | The menu. The page never sees it. | As in Arc. |
| `promptAfterConsumedByWebView` | The page, and Arc prompts when the page consumed it. | Not built: the page first, with no prompt. |
| `low`, or none | The page, and the menu what the page leaves. | As in Arc. |

The shortcuts that override the page:

| Shortcut | Item |
| --- | --- |
| ⌘T, ⇧⌘T | New Tab, Restore Last Closed Tab |
| ⌘N | New Window |
| ⌘L | Open Location… |
| ⌘W, ⇧⌘W | Close Tab, Close Window |
| ⌘[, ⌘] | Back, Forward |
| ⌥⌘↓, ⌥⌘↑ | Next Tab, Previous Tab |
| ⌘H, ⌘M, ⌘Q | Hide, Minimize, Quit |

Everything else is the page's first, as it was: ⌘R, ⌘1 to ⌘9, ⇧⌘] and ⇧⌘[,
⌘S, ⌘D, ⌘Y and the rest. Arc has ⌘S, ⌘D, ⇧⌘D and ⌘O in its prompting group.

## How

The seam is in the app, as Arc's is, and the engine is not involved. The
browser window's content sits in a `KeyboardShortcutInterceptionView`. AppKit
offers a key press with Command or Control to the window's views before the
main menu, which is how the page takes it. For a shortcut that overrides the
page this view answers no without asking the views inside it, so AppKit goes on
to the menu.

The set is filled as the main menu is built. A key press is matched as Arc
matches one: its key in lower case with its four modifiers, and with Command
alone the key as typed, so a layout that turns Latin under Command still
matches.

A shortcut whose menu item is disabled at that moment is not taken by the
menu, and AppKit then gives the key to the page: ⌘[ on a tab with nowhere to go
back to, for one.

## Not here

- Arc's prompt for a shortcut a page consumed, and its setting for which side
  wins.
- Arc's fallback from a key's code to its character. On a layout that stays
  non-Latin under Command, an overriding shortcut is the page's first, as
  every shortcut was before.
- Windows other than the browser window that hold a page: picture-in-picture
  and an extension's popup. Arc's view is in its browser window's content
  only.

| Layer | Holds |
| --- | --- |
| UI | `KeyBindings/`: the priority, the shortcut read from an event, the view; the priorities in `MainMenu` |
