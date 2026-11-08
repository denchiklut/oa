# DevKit

DevKit will be Oa's Swift engine layer between
[App/UI](../app/README.md) and [Core](../core/README.md). It will present
browser objects, commands, state and requests in the form the app uses. Core
will connect those interfaces to the native engine; the app will choose product
behavior and presentation.

This chapter describes the intended architecture, not an implemented API or a
claim that every callback, lifecycle state and error path has been settled.
DevKit is a logical boundary: where its code is packaged will not change which
layer owns engine integration or product decisions.

The architecture has three parts.

## 1. Give the app one Swift engine interface

The app will talk to DevKit rather than import native engine adapters or
Chromium types. DevKit will translate native values, errors and events into
Swift contracts, while keeping engine-specific implementation details below the
boundary.

| Interface | Responsibility in DevKit |
| --- | --- |
| Browser application | Expose engine startup and shutdown, context management and application-wide events. |
| Browser context | Present a profile's engine settings and services, page creation and regular or private context selection. |
| Web content | Present a page's commands, observable state, lifecycle, native view and page-scoped events. |
| View and host connection | Express attachment, visibility, focus and movement between native hosts without making window presentation an engine responsibility. |
| Feature adapters | Present navigation decisions, downloads, dialogs, permissions, extension events and other engine operations through typed requests and results. |

The Swift interface will have a live adapter over Core and a stub adapter for
app development without a Chromium build. Application composition will select
the adapter and supply it to consumers. Features will depend on the interface;
they will not choose or construct their own native engine implementation.
The stub's capabilities and limitations will be explicit, so a successful stub
interaction is not mistaken for verified engine behavior.

Configuration will travel from the app through DevKit to the engine owner. Each
value will have a defined application, context or page scope, and an explicit
relationship between its initial value and later updates. Translating a
per-profile setting into a native call will not make an engine-global setting
profile-local. Product preferences and their saved representation will remain
in App/UI; the underlying engine service will remain in Core or Chromium.

DevKit's feature surface will also include operations that need services or
renderer support. The app will use a Swift operation and receive a result or
event; Core and Chromium will own the native dispatch and process transport.
DevKit will not reproduce those mechanisms or expose their transport types to
product code.

## 2. Keep page identity, state and ownership explicit

A product tab, a Swift page handle, a native adapter, an engine page and an
attached view are different things. DevKit will define what its caller-visible
identity refers to, which operations remain valid and which changes the app
must observe. A retained Swift handle will not imply that its native engine
object is unchanged or still usable.

| Transition | Contract DevKit must expose |
| --- | --- |
| Create or adopt a page | The context and source of the page, how the app accepts ownership, and what happens if it is not accepted. |
| Attach, detach or move a view | Which page identity survives, which host relationship changes and how focus and visibility are updated. |
| Discard, replace or revive engine contents | Which handles remain valid, what state becomes unavailable and how observations reconnect to the current engine object. |
| Close or release a page | When commands stop being valid, how pending requests end and when subscriptions and captured resources are released. |
| Restore a product tab | How saved app identity is associated with a new live page, separately from any engine session identity. |

State will cross the boundary as typed Swift values with defined meanings.
The lifecycle contract must cover unavailable and terminal states as well as
normal transitions. Exact case names, conversions and permitted operations
remain to be specified; native numeric values will not become public Swift
states without that definition.

Observation needs its own lifetime. Each subscription will identify the page
or context it follows, the state it reports and the owner responsible for
ending it. Replacing the underlying engine object will require an explicit
update or reconnection path. Reading a new value once will not establish that
subsequent changes are observed.

The same distinction applies to callback ownership. A closure's existence
will not establish which page or app instance it reaches. Installation,
replacement, captured context and teardown will be part of the adapter's
contract. Core will own native object relationships; DevKit will own the Swift
handles, subscriptions and translations it introduces; App/UI will own the
product state and presentation that consume them.

## 3. Separate events, decisions and operation results

An event reporting a changed title differs from a navigation decision that
needs an immediate answer, and both differ from a permission prompt that can
remain open. DevKit will preserve those differences rather than present every
interaction as an interchangeable callback.

| Interaction | Responsibility in DevKit |
| --- | --- |
| Commands and state queries | Address the intended live object and translate success, failure or an unavailable target. |
| State notifications | Carry source identity and updated state to the appropriate consumer, with explicit subscription and delivery rules. |
| Immediate decisions | Expose the inputs, allowed answer and fallback, including whether an answer must arrive before the call returns. |
| Deferred decisions | Keep the request and its reply associated while the app presents UI, then handle answer, dismissal or invalidation. |
| Asynchronous operations | Correlate completion with the originating operation and distinguish failure, cancellation and loss of the target. |

For example, a navigation decision will follow this path:

1. Core reports a request with its source page, context, destination and
   available navigation information.
2. DevKit translates it into the Swift decision contract for that request.
3. The app applies its routing rules and returns an allowed decision.
4. DevKit delivers the answer to the same native request, or follows the defined
   fallback when an answer cannot be used.

The app will own routing policy and the choice of tab, split, popup or other
presentation. DevKit will own request translation and reply delivery. A
referrer, destination URL and current source-page URL will retain their distinct
meanings; the decision contract must specify which inputs a policy can rely on.

Fallbacks will be defined per interaction. An absent consumer, an unanswered
immediate request, a dismissed prompt and a cancelled operation need not have
the same outcome. An immediate decision cannot silently depend on later UI
work; a deferred reply needs an owner while it is outstanding. Replies must
remain associated with their originating request, including when a page moves,
closes or is replaced.

Feature adapters will preserve these contracts at the App/UI boundary:

| Adapter family | Boundary to define |
| --- | --- |
| Downloads | Filename or destination decisions, the consumer that answers them, and behavior when the request expires or its owner disappears. |
| Dialogs, permissions and certificates | Request context, presentation handoff, allowed answers and dismissal or invalidation behavior. |
| Engine-created pages and extension popups | Adoption, opener and context information, presentation ownership and the path back to close or release the page. |
| Ad blocking and page effects | Translation of selected settings and rule values, their actual engine scope and how later changes reach that owner. |
| Media, fullscreen and picture-in-picture | Page capability events, host changes and completion or teardown of the corresponding transition. |

Each interaction will need explicit execution and delivery rules, reply
cardinality, error behavior and teardown. Scheduled delivery is different from
immediate execution. Ending a subscription, releasing a callback and cancelling
engine work are separate actions. Where a deadline exists, the contract must
identify who enforces it and resolves the request.

Return to the [four-layer overview](../README.md).
