# UI

UI will own Oa's product model, native windows and presentation. It will
turn user input and engine events into product decisions, keep shared data
consistent across windows, and save the application state needed at relaunch.
It will use [DevKit](../devkit/README.md) for pages and engine services;
[Core](../core/README.md) and [Chromium](../chromium/README.md) will own native
engine integration and browser infrastructure.

The architecture below describes the intended responsibilities and contracts.
It does not establish that every feature is implemented. The
[feature notes](#current-implementation) describe existing slices and their
product choices.

The architecture has three parts.

## 1. Own shared product data and each window's decisions

The app's model will decide which profiles, Spaces and sidebar items exist,
where they appear, and what a window has selected. An engine page will be a
resource associated with that model, with its own creation and release rules.
A saved tab can exist without a live page.

| Owner | Responsibility in UI |
| --- | --- |
| Application composition | Select the live or stub DevKit adapter, construct shared services, install menus and coordinate launch, restoration and quit. |
| Shared product data | Hold profiles, Spaces, Favorites, sidebar entries, folders, splits and Archive records with stable identities and valid relationships. |
| Window state | Hold the selected Space, remembered selection, pane or overlay presentation, transient input and references to the pages the window owns. |
| Product operations | Apply insertion, move, pin, close, archive and restore rules; reconcile affected windows and record an inverse where undo is supported. |
| Feature state and services | Own settings, search UI, prompts and other product flows, using DevKit for the underlying engine capability. |

A shared edit will have one authoritative result. Windows will derive their
presentation from that result and reconcile selections or pages whose items
have moved or disappeared. A window's selection, hover or unfinished gesture
will have a defined local owner; changing it will not implicitly edit the
shared sidebar or persist a transient animation. Undo needs a model inverse
and a defined window scope.

Input and engine events will reach the state that owns the decision. A tab
selection, for example, will follow this path:

1. The window resolves the selected item in the current shared model.
2. It updates its selected Space, tab and pane presentation as appropriate.
3. It reuses a page it already owns, takes over an existing page where that is
   supported, or asks DevKit to create a page for that tab's context.
4. It associates the result with the still-current item and window, and connects
   the page's events and native view.
5. It loads the saved destination when creation requires an initial load, and
   reconciles later engine state with the product record.

Creation can complete after the selection changes or the window closes. The
operation needs an identity and an owner so the app can accept a valid result
or release one it no longer needs. Title, address and favicon events must reach
the item associated with the reporting page, even when another tab is selected.

## 2. Compose native presentation and manage page hosts

AppKit and SwiftUI will compose the window, sidebar, toolbar, panes and
transient surfaces around DevKit's page view. Controllers and views will have
explicit owners and state inputs, so a layout update, a page transition and
an engine command can be understood separately.

| Surface | Presentation responsibility |
| --- | --- |
| Sidebar | Lay out Favorites, Space sections, tab and folder rows, selection, hover, drag targets and reveal modes. |
| Window content | Host pages, placeholders, split panes and toolbars; coordinate pane changes, resizing and view attachment. |
| Space overview and editor | Present Space selection, creation and theme editing; connect model changes to the selected background renderer. |
| Command and search UI | Own text, suggestions, selection and dismissal; route the chosen command or destination to the relevant window. |
| Overlays and auxiliary windows | Define the source page or item, presenter, retained page and close or return path for Peek and other supported surfaces. |
| Themes and animation | Turn explicit appearance and transition state into layout, colors and rendering inputs, with a defined end or cancellation path. |

Each input route will distinguish a transient update from a committed product
change. Keyboard and menu commands need a target window and command context;
text input needs responder and input-method handling; pointer, drag and scroll
events need acceptance rules and a clear handoff to the owning feature. A Space
gesture can update intermediate presentation before it commits a selected
Space. Cancelling or interrupting it must leave a valid selection and layout.

Page hosting will preserve several separate states: selected item, focused
pane, key or main window, AppKit first responder, attached view, engine
visibility and engine tab activation. Making a pane visible will not by itself
define keyboard focus. The app will request the appropriate focus and hosting
operations through DevKit and handle a view that is not ready or no longer
available.

Moving a page between windows must update its owner, event destination and
presentation together.

Closing a tab, hiding a Peek, detaching a view, unloading a page and closing a
window are different product operations. Each needs a defined treatment of
pending creation, event subscriptions, snapshots, overlays and retained pages.
A close that the page rejects must leave or restore a usable presentation;
removing one registry entry will not establish that all page owners are gone.

## 3. Coordinate engine decisions, saved state and feature services

The app will choose product behavior for engine requests and return answers
through DevKit's request contracts. Immediate navigation policy will use the
request's defined inputs and fallback. A prompt that waits for a user will
retain its request while the UI is open and end it on answer, dismissal or
invalidation. Scheduled UI work cannot supply an answer after an immediate
decision's deadline.

| Product flow | Contract UI must define |
| --- | --- |
| Navigation and new pages | Resolve the source and destination, choose tab or overlay placement, preserve opener information and answer the original decision. |
| Permissions, dialogs and downloads | Select the presenter and allowed answers, keep the request associated with its page or context, and handle cancellation or expiry. |
| Extensions, side panels and media | Choose presentation and focus behavior while DevKit manages the engine operation and reports its result. |
| Preferences and page effects | Store the product setting, apply it at the engine's supported scope and propagate later changes to the relevant live objects. |
| Search, history, bookmarks and import/export | Own the interaction and progress state, correlate service results, and distinguish cancellation, partial results and failure. |
| Sync and account UI | Coordinate client bootstrap, local model reconciliation, conflicts and sign-out; define the service contract separately. |
| Updates and diagnostics | Own relaunch and reporting policy, user-visible progress or errors, and the lifetime of any pending operation. |

Persistence will save an explicit projection of the product model and the
chosen window records. The projection must say which identities, selection,
settings and transient surfaces survive a relaunch. Loading needs version and
validation rules, defaults for absent data, and a recovery path for unreadable
or newer data. Backups, retention and restoring a snapshot are part of that
contract, including what may still write after restore begins.

Ordinary saves and the final save at quit need separate ordering and
cancellation rules. Startup must establish shared state and dependencies before
restored windows consume them; shutdown must stop producers and resolve or
cancel pending work before releasing the engine. Sync, when added, will
reconcile with the same authoritative product model rather than establish a
second unrelated source of truth. Atomic file replacement alone will not settle
concurrent-writer or crash-recovery behavior.

## Current implementation

Implementation details live with their features:

- <a id="sidebar-state"></a>[Sidebar state](../../features/sidebar/README.md): shared data, window selection,
  Archive, opened pages and page recovery.
- <a id="peek"></a>[Peek](../../features/peek/README.md): routing, presentation and page lifetime.
- <a id="favorites"></a>[Favorites](../../features/favorites/README.md): profile-scoped tiles, selection and placement.
- <a id="files"></a>[Saved state and recovery](../../features/saved-state/README.md): file formats, favicons,
  backups and Restore Data.
- <a id="downloads"></a>[Downloads](../../features/downloads/README.md): the Library, its button and flyout,
  quitting with downloads running and the download location.
- <a id="context-menu"></a>[Page context menu](../../features/context-menu/README.md): Chrome's menu on every
  page, the items kept and where the pages it opens go.

The [feature inventory](../../features/README.md) tracks candidate capabilities
separately; its unchecked entries have not been assessed for implementation.

Return to the [four-layer overview](../README.md).
