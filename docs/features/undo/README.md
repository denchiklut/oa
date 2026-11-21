# Undo and redo

Oa implementation notes. The [UI architecture](../../architecture/ui/README.md)
describes the broader intended responsibilities.

Edit ▸ Undo ⌘Z and Redo ⇧⌘Z take back what was done in the sidebar, as in Arc.
Each window has its own steps, on its own AppKit undo manager, and they go
with the window.

## What can be undone

| Action | Edit ▸ Undo reads | Comes back |
| --- | --- | --- |
| Archive a tab: ⌘W, a row's ✕, Remove Favorite | Archive Tab | The tab where it was. The one the window was showing is shown again, with its history; any other is a row without a page |
| Clear, Archive Tabs Below | Clear Tab, Clear Tabs | Every tab the close took, at once |
| Close a Peek | Close Peek | The Peek, over its tab |
| A change in the [theme editor](../space-theme/README.md) | Update Theme | The Space's theme before it; an open editor starts over from it |

The names are Arc's. Arc undoes more: a move (pin, unpin, a drag), a new,
deleted or moved Space, a Space's icon and the app's appearance. Oa doesn't
yet. Opening a tab is no step in Arc either.

A step is a name and the action that takes it back, which the window replays.
The replayed action registers its own while the undo runs, which is what
makes Redo: AppKit files a step registered during an undo on the redo side.

- **Redo** closes the same tabs again. Nothing is selected in place of a tab
  that was showing, as in Arc.
- **⌘Z and ⇧⌘T are one record.** A close is a group in the window's
  [closed tabs](../sidebar/README.md), and the undo step only names the group.
  ⌘Z brings the whole group back; ⇧⌘T one tab at a time, and the press that
  takes the last one removes the undo step. An undone close is gone from ⇧⌘T.
- **Ten closes.** The window keeps its last ten. An older close still has its
  step, and that press does nothing, as in Arc.
- **Typing in the command bar** has its own steps, as Arc's bar has, so ⌘Z
  there never reaches the sidebar's.

Oa's own: a redone close, of tabs or of a Peek, is on the window's ten before
its pages have closed, so its step is filed while the redo runs and the redos
after it stay. Arc files it once they have, and a redone close of a loaded tab
leaves a second step that does nothing.

## The toast

Clear and Archive Tabs Below show "Cleared Tabs! Use ⌘Z to undo." at the
window's top right for five seconds, as Arc's. An undo shows none, nor does a
redo of a Clear. A single archive and a closed Peek show none.

## A page and ⌘Z

While a page has the keyboard, ⌘Z is the page's first, as in Arc:

- typing in a page's field is undone a step per press, and the press after the
  last one undoes the sidebar's step;
- a field with nothing to undo, or no field, lets the press through at once;
- a page that cancels the key keeps it, and nothing is undone. Edit ▸ Undo
  from the menu still works;
- ⇧⌘Z goes the same way: the page's redo first.

The engine does this, by [patch 0018](../../../chromium/patches/README.md): the
page's view sends Undo or Redo to the focused frame with a reply, and when the
frame did nothing, the first undo manager up the responder chain that can undo
does, which is the window's. ArcCore's view does the same.

As in Arc, the menu doesn't follow while a page has the keyboard: Undo and
Redo stay enabled and keep the title they last had, because the page's view
answers for them. Choosing Undo then undoes the real last step.
