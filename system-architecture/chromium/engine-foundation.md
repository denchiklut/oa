# Engine foundation

## Reference architecture

The reference browser uses Chrome's browser infrastructure together with its own
native interface. Chromium supplies more than a renderer: its browser process
coordinates profiles, pages, tab services, extensions, network policy and child
processes.

| Chromium concept | What it supplies | What the native layer needs from it |
| --- | --- | --- |
| `Profile` / browser context | Profile-scoped storage and browser services | Create or select a context and access its services |
| `Browser` and tab infrastructure | Browser ownership, tab membership and integration with Chrome features | Attach pages to browser machinery while supplying a native host |
| `WebContents` | One page's navigation, content state and renderer connection | Commands, observable state, a hosted view and page requests |
| Tab helpers and features | Services associated with a Chrome tab | Reuse browser behavior rather than rebuilding each attachment |
| Renderer, GPU and utility processes | Web execution, graphics and isolated work | Dispatch operations and handle results or process loss |

These are related identities, not interchangeable names for one object. A saved
sidebar item, Swift page handle and native `WebContents` can have different
lifetimes. Mapping those identities is work for the layers above Chromium.

## Replacing the shell

Chrome normally combines browser machinery with its own windows and controls.
The reference integrates a different native host and substitutes or forwards UI
entry points. Permission requests, dialogs and extension presentation can then
reach the native app through the integration layer.

Replacing the visible shell does not remove Chromium's tab infrastructure.
Keeping pages connected to it gives browser features the context they expect.
It also creates integration obligations: a subsystem can request UI, create a
page or change tab state independently of a sidebar action.

## A page created by web content

1. Chromium encounters an operation that opens another page.
2. Navigation and new-content hooks expose the request to native integration.
3. The upper layers make or translate the product decision about placement.
4. Chromium's new page must be adopted into a valid owner, or released.

Selected adoption, deferred-fullscreen and PiP paths are mapped. A universal
sender type and every ownership transfer are not established. The Chromium
chapter therefore does not promise that all new pages take one route.

## OpenArch direction

OA's intended approach is to use real Chrome tabs without Chrome's visible
window controls, while the app's sidebar remains the product model. The native
layer must reconcile engine-originated page changes with app commands. Exact
ownership and synchronization contracts need their own design; the reference
architecture does not supply those contracts automatically.


Return to the [Chromium chapter](README.md).
