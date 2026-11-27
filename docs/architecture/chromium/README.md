# Chromium

Oa will use a customized Chromium build as the engine behind its native macOS
app. Core will connect that engine to Swift, exposing browser objects,
commands and callbacks. Chromium will handle navigation, rendering, networking,
storage and browser services; the app will own the user experience.

This chapter describes the Chromium layer: the browser infrastructure Oa will
use, the engine capabilities it will expose, and the integration points Core
will connect to. Native adapters and their ownership belong in the
[Core chapter](../core/README.md).

The architecture has three parts.

## 1. Keep Chromium's browser infrastructure behind a native interface

Oa will use Chromium's `Browser`, `Profile`, `WebContents` and tab infrastructure.
That gives pages the browser context and services needed for navigation,
extensions, history and tab helpers.

Core will connect those objects to the native app:

| Integration | How Core will use it |
| --- | --- |
| Browser application | Start Chromium, configure services and forward engine lifecycle events. |
| Browser context | Expose profiles and their history, settings, downloads, extensions and preferences. |
| Web content | Expose a page's navigation commands, state, native view and events. |
| Browser window and UI | Connect Chromium's browser/window machinery to Oa's native windows and presentation. |
| Dialogs and permissions | Forward requests upward so the app can present UI and return an answer. |

A native tab view will display a real Chromium page. Oa will supply the toolbar,
sidebar and window controls rather than display Chrome's browser shell.

## 2. Expose engine capabilities through Core

The engine will provide mechanisms; the layers above it will choose product
behavior and presentation.

| Capability | Responsibility in the engine |
| --- | --- |
| Navigation interception | Report the target URL, referrer, navigation type and requested destination for a policy decision. Host-based routing rules belong above the engine. |
| Page creation and placement | Report engine-created pages and preserve their opener and browser context while the app chooses a tab, split, compact window or other presentation. |
| Page effects | Support stylesheet insertion/removal, color filters and color-scheme overrides. Host-based effect configuration can also cover scripts and zoom. |
| Picture-in-picture | Expose page capabilities and lifecycle events. Any override of normal page restrictions needs an explicit Oa policy. |
| Ad blocking | Accept rules and exclusions, distribute filtering state, cancel matching requests and apply cosmetic hiding styles. |
| Page-color reporting | Sample a page's top-band color and report it upward as an input for native UI. |
| Extensions | Connect extension resources, installation requests and engine-created pages to native integration. |
| Utility work | Provide a place for work such as content conversion, image decoding and profile import. The service inventory remains a design decision. |
| Lifecycle events | Report page discard/revival, view attachment, process failures and diagnostics through the native interface. |

Use existing Chromium hooks where they provide the required behavior. Keep
engine changes that require patches separate from Core integration code,
so each Chromium upgrade has a clear set of changes to maintain.

## 3. Connect browser-side commands to renderer processes

A page's renderer runs in another process. A native method call in Core
therefore needs a process boundary to reach renderer-side state.

Oa will use Mojo, Chromium's interprocess messaging system, for operations that
need renderer support. The interfaces will cover these roles:

- **Frame access:** identify and target the frame that should receive an operation.
- **Page operations:** apply styles or effects and answer page-state queries.
- **Effects configuration:** distribute settings used by renderer-side effects.
- **Ad blocking:** distribute rules and exclusions, reset state and request
  diagnostics.

Swift can read a page's `frameIDs` and call `insertStyleSheet(_:in:)` on one of
those documents. Core resolves the handle within the current page and sends
the CSS and Chromium's document embedding token over the target frame's
`PageOperations` Mojo endpoint. The renderer checks the token again before
inserting an author stylesheet. Each call adds a separate sheet.

The Swift call returns `inserted` after the renderer acknowledges insertion.
A missing or replaced document returns `frameGone`. An abnormal exit of the
target renderer during a request returns `rendererCrashed`, including for a
cross-site child frame. Oa allows five seconds for a reply or process exit
notification. At the deadline a closed pipe returns `disconnected` and an open
pipe returns `timedOut`. Either leaves insertion unconfirmed. The stub exposes
no live frames and returns `unsupported`.

Return to the [four-layer overview](../README.md).
