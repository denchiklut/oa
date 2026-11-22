# Shortcuts

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

Every shortcut is a main menu item's, as in Arc, and each can be changed in
Settings ▸ Shortcuts. While a page has the keyboard, the page gets a key before
the app does, and the menu only the keys the page leaves; a binding's priority
says which shortcuts are the exception.

## Bindings

A menu item that carries one of Arc's binding IDs is a bindable action: its
title is the action's name and its key and priority the defaults. At launch
`KeyBindingMenuManager` registers them with `KeyBindingsClient`, which then
reads the user's overrides, and from then on each item's key follows its
binding, a tenth of a second after a change as Arc's.

| | As Arc |
| --- | --- |
| A binding | `valid` with a shortcut, in `conflict` with the actions that share it, or `unset` |
| A conflict | Not refused. Every action on the shortcut loses its menu key until one is changed |
| An override | A binding whose shortcut or priority is not its default. Set back by hand, it is the default again |
| Never a user's | ⌘Z, ⇧⌘Z, ⌘X, ⌘V, ⌘A, ⌘I, ⌘B, ⌘U and ⌥⇥ |
| The file | `StorableKeyBindings.json` in the data directory: `{version, userOverrides}` in Arc's coding, the overrides only |

The IDs are Arc's where the action is: `newTab`, `archiveTab`, `showSidebar`,
`pinTab`, `cycleNextTab`, `item1` to `item9` and so on. An action Oa has under
another name keeps Oa's menu title.

A shortcut is a key as a character and the four modifiers. A key press is read
as Arc reads one: under Command without Control or Option the key as typed,
whatever Shift does, so a layout that turns Latin under Command still matches;
otherwise the key without its modifiers; a special key under one spelling (Tab
is "⇥" whether the event says tab or back-tab); and the key code's character
when the event has none. That last table is Arc's: the US character of each
key, a glyph for a special key, AppKit's code point for a function key.

## Priority

| Priority | In Settings | Who gets the key |
| --- | --- | --- |
| `overrideWebView` | Prefer Oa | The menu. The page never sees it. |
| `promptAfterConsumedByWebView` | Use Both | The page. If it consumes the key, Oa asks, and a second press runs the action. |
| `low` | Prefer Websites | The page, and the menu what the page leaves. |

The defaults are the items' in Arc's menu. Overriding: ⌘T, ⇧⌘T, ⌘N, ⌘L, ⌘W,
⇧⌘W, ⌘[, ⌘], ⌥⌘↓, ⌥⌘↑, ⌃⇥, ⌃⇧⇥, ⌘H, ⌘M and ⌘Q. Prompting: ⌘S, ⌘D, ⇧⌘D and
⌘O. Everything else is the page's first.

The browser window's content sits in a `KeyboardShortcutInterceptionView`.
AppKit offers a key press to the window's views before the main menu, which is
how the page takes it. For a shortcut that overrides the page this view answers
no without asking the views inside it, so AppKit goes on to the menu. It reads
the live bindings, so a rebound action's new key is kept from the page and its
old one no longer is.

A shortcut whose menu item is disabled at that moment is not taken by the
menu, and AppKit then gives the key to the page: ⌘[ on a tab with nowhere to go
back to, for one.

## The prompt

When a page consumes a key down that is a prompting binding's shortcut, a
toast comes over the page: the key caps, "again to" and the menu item's title
at that moment, with "Edit the shortcut" under it.

- The same shortcut again while the toast is up runs the menu item. The page
  has had that key too.
- The menu item is the first that has the shortcut, as Arc's lookup. An
  action moved to a key an earlier item that is no binding holds, ⌘C and
  Copy, asks for and runs that item.
- The toast stays its 5 seconds whatever is pressed, and once it is gone the
  next press asks again.
- Another prompting shortcut takes the toast's place and the wait with it.
- "Edit the shortcut" closes the toast and opens Settings ▸ Shortcuts on the
  binding.
- A key consumed in a frame of another site, which has a process of its own,
  asks nothing, as in Arc. A frame of the page's own site does.

The engine reports a consumed key from the page's main widget: the key's code
and modifiers of a raw key down the page acked as consumed. Chromium's own
input observer gives it; where ArcCore takes its report from isn't known, so
the hook is Oa's choice and the behaviour Arc's. The shortcut is looked up by
the key's code through Arc's table, so by the key and not by what the layout
types with it.

The toast is drawn as Arc draws its own with the new toast background off,
which is how Arc ships: the Space theme's colour, or the mean of its
gradient's, at 0.8 over a light material, a sheen of white or black by the
colour's lightness, black or white text to match. It sits 8 pt in from the
page's top and right, a Peek's page too, and comes and goes on one spring.
Arc's is a child window; Oa's is in the window's own view tree, where a page
can be drawn over.

## Settings ▸ Shortcuts

Arc's pane at its measures, for the actions Oa has.

- “Learn the Essential Shortcuts” opens Oa’s guide to six common actions. It
  shows their current bindings, including conflicts and unassigned shortcuts.
- The list is sorted by name under "Customized Shortcuts" and "Default
  Shortcuts". The search field matches names, and shortcuts written as words,
  symbols or joined by "+" ("cmd+t", "⌘T", "ctrl tab").
- A row's key caps are its recorder. A shortcut needs Control, Option or
  Command, or a function key. Delete unsets, Escape and Tab leave it as it was,
  and a shortcut a user may not set is refused.
- A conflict shows a red badge on each row, whose card names the other action,
  and the menus offer Remove Conflicting Shortcut.
- The detail side has the selected binding's caps, Arc's description of it, the
  priority while it has a shortcut, and Reset Shortcut to Default. With nothing
  selected it offers Reset All Shortcuts. Extension Shortcuts… opens the
  engine's page for them.

## Not here

- Arc's note on a shortcut the system also holds, a binding for each Space,
  and the switches of features Oa lacks
  (Capture, Little Arc, the ninth sidebar item).
- Arc’s dark colours for the toast and the pane’s conflict and selection states.
  The dark reference shows the pane with no action selected.
- Arc's second lookup table for a key from a string, whose contents weren't
  read; a shifted symbol such as ⌘} is kept as written.
- Arc's flag-gated Cycle Tab Forward and Backward. The flag is off in Arc as it
  ships, where the two have no key and no row in Settings.
- Windows other than the browser window that hold a page: picture-in-picture
  and an extension's popup. Arc's view is in its browser window's content
  only.

| Layer | Holds |
| --- | --- |
| UI | `KeyBindings/`: the shortcut and Arc's key table, the binding model, the client with its file, the menu manager, the interception view. `PreferencesFeature/`: the Shortcuts pane and its recorder. `Toasts/`: the toast. The queued menu item and the consumed-key answer in `WindowModel`; the IDs and priorities in `MainMenu` |
| DevKit | A page's `consumedKey` event; the stub page's "Consume shortcuts" |
| Core | A page's consumed raw key downs, from its main widget's input acks |
