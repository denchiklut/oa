# Core

Core will be Oa's native integration layer between [DevKit](../devkit/README.md)
and [Chromium](../chromium/README.md). It will turn engine objects, commands and
events into native interfaces that DevKit can expose to Swift. Chromium C++
types and engine-specific lifetime rules will stay behind that boundary; the app
will talk to DevKit rather than Core directly.

This chapter describes the intended integration architecture, not an implemented
API or a claim that every lifetime and failure path has been settled. Core is a
logical responsibility: packaging it with Chromium in one framework will not
make rendering, networking or all browser services part of Core.

The architecture has three parts.

## 1. Expose native application, context and page interfaces

Core will adapt Chromium's browser infrastructure rather than duplicate it.
The native interface will give DevKit a small set of objects with explicit
ownership, commands, state and events.

| Interface | Responsibility in Core |
| --- | --- |
| Browser application | Start and shut down the engine, connect application-wide services and forward lifecycle events. |
| Browser context | Connect a profile to its settings, storage and browser services; distinguish regular and private contexts. |
| Web content | Expose a page's navigation commands, state, engine events and native view. |
| Native view and host | Connect page views to native hosts and forward attachment, visibility, focus and window-related operations. |
| Requests and service adapters | Translate engine requests and results, retaining the context and completion state needed to finish or abandon an operation. |

Objective-C and Objective-C++ adapters will form the native boundary to the C++
engine. DevKit will own Swift-facing types and error/event translation; Core
will own the connection to the native engine object. Product tab placement,
window presentation and saved app state will remain above both layers.

Configuration will follow the same separation. The app will choose product
settings, DevKit will translate them, and Core will pass them to the appropriate
engine owner. Each setting needs an explicit scope: application-wide, profile,
page or renderer. A per-profile app model alone will not make an engine-global
setting profile-local. A copied setting will also need a defined update path;
installation of an initial value is not ongoing observation.

## 2. Keep identity, ownership and view attachment separate

A visible tab is not a single engine object. The app's tab identity, DevKit
page, Core adapter, Chromium `WebContents`, browser context and native view each
have their own lifetime. Core's contracts will describe which objects an adapter
owns, which it observes and what remains valid after a change.

| Transition | Contract Core must define |
| --- | --- |
| Create or adopt a page | Which browser context owns the page, who retains it and how opener and destination information are carried upward. |
| Move or reattach a view | Whether the engine page stays the same, which host changes and how old focus, visibility and observer relationships are removed. |
| Transfer between contexts | Whether transfer is supported, what is validated before adoption and what remains owned by the source if it fails. |
| Discard and revive | Which public identities survive, whether the underlying engine object is replaced and how views, observers and state are rebound. |
| Close or destroy | When new requests stop, how pending work is resolved and when native and engine ownership is released. |

Moving a view between windows must not be treated as destroying its page.
Conversely, retaining a page adapter must not imply that the underlying engine
page can never change. Live state getters, subscriptions and saved app bindings
will need separate refresh rules when the engine object is replaced. DevKit will
translate engine lifecycle states into its own explicit state model rather than
expose untyped native values as Swift states.

Picture-in-picture, fullscreen and extension popup hosts will use the same
separation of page, view and host ownership, while retaining their own transfer
and completion contracts. A local detach or close callback will not by itself
establish that every host, view and pending request has been destroyed.

Private-context cleanup and application shutdown will also need explicit
ordering between host detachment, observer removal, pending tasks and native
profile release. Dropping a wrapper or invalidating a weak reference will not
substitute for cancelling work or releasing the engine's last owner.

## 3. Translate commands, events and decisions without losing their lifetime

Not every upward call has the same meaning. Some report state, some ask the app
for a decision, and others return the result of an asynchronous operation.
Core and DevKit will preserve those distinctions.

| Interaction | Core's integration responsibility |
| --- | --- |
| Commands and state queries | Target the current engine object and return a result or report that the target is no longer available. |
| State events and observations | Identify the source object, manage subscriptions and define whether delivery is immediate or scheduled. |
| Navigation and new-page decisions | Carry the source page, context, opener and requested destination upward; return the decision to the original engine request. |
| Dialogs, permissions and certificates | Retain the request while native UI is presented, then translate an answer, dismissal or cancellation without treating them as interchangeable. |
| Resource and utility operations | Connect loaders, filename requests, conversion or import work to their result, error, disconnect and teardown paths. |
| Diagnostics and service callbacks | Connect engine reports to native consumers without moving product reporting policy into the engine. |

For example, a permission request will follow this path:

1. Chromium creates a request for a particular page and browser context.
2. Core retains the native request state and forwards it through DevKit.
3. The app presents the decision and returns an answer through DevKit.
4. Core checks that the request is still valid and delivers the answer to the
   engine, or follows the defined invalidation path.
5. Core releases the request's completion state and associated observation.

The contract must also cover the page closing before the user answers, a caller
disappearing, and a reply arriving after invalidation. Where an answer changes a
stored permission, the selected engine provider and persistence behavior need
their own contract; returning the UI decision alone will not prove it was saved.

Each operation needs a defined delivery runner, reply cardinality, default or
error result, and shutdown behavior. A timeout value is not an enforced deadline
unless something owns the timer and resolves the request. Removing a completion
from a registry, releasing its captures and cancelling backend work are separate
actions. The interface must say which ones happen on each terminal path.

Operations needing renderer or utility-process support will pass through the
engine's process interfaces, described in the [Chromium chapter](../chromium/README.md#3-connect-browser-side-commands-to-renderer-processes).
Core will correlate the native caller with the engine request; the engine will
own the process transport. Sending a message will not count as receiving a reply
or successfully applying the operation.

Return to the [four-layer overview](../README.md).
