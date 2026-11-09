# App / UI

**Status: scope only.** The detailed reference-architecture chapter has not been
written. The Chromium, Core and DevKit chapters cover the engine, native
integration and Swift interface.

This layer owns product state and presentation: Spaces, sidebar items, native
windows, settings, routing decisions and saved application state. It consumes
the Swift engine interface exposed by DevKit.

Future chapters belong here when they explain how a user action becomes a
product decision, how the app presents engine requests, or how app state survives
relaunch. Chromium internals and native engine adapters belong below this layer.

For Oa, the intended rule is that the app owns product state and talks to the
engine through DevKit. Detailed state, persistence and presentation decisions
are documented in this chapter as they are made.

## Sidebar state

`SidebarState` is the app's source of truth: profiles, Spaces and an item tree.
A profile owns a favorites root; a Space owns a pinned root and an unpinned
root. Tree nodes are containers, tabs, folders and split views; only containers
and tabs are implemented. A tab entry takes its tab's ID, so pinning is a move
to the end of the other section and the entry keeps its identity. A tab record
saves a title and a URL. A live page writes both back; a pinned tab keeps its
address and takes the title only.

One `SidebarStore` holds the state and the open windows. Every change goes
through `edit`, after which each window reconciles its selection and drops pages
of tabs or Spaces that are gone, and a save follows 2.8 s later. Write-backs of
title and URL change the state without scheduling a save; they ride on the next
one, and on the save at quit.

A `WindowModel` holds the window's selected Space, a selected tab per Space, a
one-step previous tab, and the pages it created. A page exists only once its tab
was shown in that window, and one live page exists per tab across windows: a
window that shows a tab held by another window takes it over, the other window
drops its page and shows an empty area until the page moves with a snapshot (an
engine follow-up). Pages of Spaces not shown stay alive with their views
detached, so the engine sees them as hidden. Window close and quit drop pages
without unload handlers; the records stay.

Close Tab ⌘W on an unpinned tab removes the record and closes the page as the
user would; the window returns to the previous tab if its page is live, else the
tab above, else below. On a pinned tab the entry stays and the page is dropped;
the window returns to the previous live tab, else shows nothing. A page the
engine closes on its own is treated the same way. Pin Tab ⌘D toggles the
section. Spaces have New, Rename and Delete without shortcuts; the last Space
can't be deleted.

Only the only window selects a tab when it opens: the first unpinned, else the
first pinned. A further window opens on the key window's Space with nothing
selected and the address field focused. Product decision until the Arc research
lands: a selected tab without a page shows the window background, and an
unloaded tab's row is dimmed.

### Files

`sidebar.json` and `windows.json` live in the data directory beside Chromium's
folder, as sorted pretty JSON written atomically into a `0700` directory; a save
with unchanged bytes is skipped.

`sidebar.json` carries `version`, `profiles`, `spaces` and `tree`, where `tree`
lists `rootIDs` and `items` in display order. Each item has `id`, optional
`parentID` and `childIDs`, a `type` of `container`, `tab`, `folder` or
`splitView`, and for a container its `container` kind, for a tab its `title` and
`url`. Loading validates the tree: roots are containers, parents and children
agree, every item is reachable, and each profile and Space points at roots of
the right kind.

`windows.json` carries `version` and `windows`, each with `id`,
`selectedSpaceID` and `selectedTabIDs` keyed by Space. Saved selections that no
longer exist are pruned on restore. Window frames are not saved.

A file that can't be read or has a newer `version` is kept as it is and not
written for the rest of the launch; the app runs on the default state in memory.
Backups and recovery copies are deferred.

Return to the [system overview](../README.md).
