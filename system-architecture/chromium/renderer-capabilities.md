# Renderer capabilities

The browser process coordinates pages; renderer processes execute web content.
The reference adds renderer-side modules and uses Mojo, Chromium's interprocess
messaging system, to reach them from browser-side integration.

## Added renderer interfaces

| Interface | Capability | How browser-side ArcCore integration uses it |
| --- | --- | --- |
| Render-process agent | Obtains an interface targeting a selected frame | Establishes a route for page-specific operations |
| Render-frame agent | Stylesheet insertion/removal, color filter/scheme controls, PiP controls and an unload-handler query | Turns native page commands into renderer work |
| Effects agent | Receives an effects configuration snapshot | Distributes configuration used by renderer-side effects |
| Ad-blocker agent | Receives URL/cosmetic rules, exclusions and resets; answers diagnostics | Keeps renderer filtering state aligned with browser-side configuration |

The reference's frame-agent connection is an ordinary message pipe. Targeting a
frame does not make the agent a permanently owned frame observer or make every
operation's state frame-local. In particular, the two PiP controls write
renderer-process globals.

## Example: applying a stylesheet

1. A native caller requests a stylesheet operation through the upper layers.
2. Browser-side integration identifies the target frame and sends a message.
3. The renderer agent resolves the frame and applies the operation to its
   document.

The Chromium responsibility is frame resolution and document mutation. Native
object adaptation belongs to ArcCore, the Swift interface to ADK, and the reason
for choosing that stylesheet to App/UI.

Sending a one-way message is not an acknowledgment that it was applied.
Disconnection, frame disappearance and renderer replacement must be considered
separately. Automatic replay is established for particular configurations, not
for every page command.

## Ad blocking

The reference adds a blocking pipeline alongside Chromium's request machinery:

1. Native integration accepts rule-list contents and exclusions.
2. Browser-side conversion builds rule data in a global in-memory store.
3. Profile services distribute read-only rule data to renderer agents, including
   newly created renderers.
4. Browser-side and renderer-side throttles evaluate requests.
5. Renderer code also generates cosmetic styles that hide matching elements,
   including at document start.

The mapped pipeline skips malformed rules and fails open when no ruleset is
available. Browser and renderer filtering have different predicates; their
actual division of live traffic was not observed. The app's reconciliation of
per-profile inputs into the global engine input remains a separate dependency.

## Effects and page feedback

The profile effects machinery holds host-pattern configuration for stylesheets,
scripts, filters, color schemes and zoom. It builds snapshots for renderer-side
consumption. It is distinct from issuing one immediate frame command.

A separate top-band color tracker lives in rendering code. Its sampled result
travels upward through a typed engine message to a native callback. Choosing how
the app uses that color is outside Chromium's responsibility.

## OpenArch direction

These are reference capabilities, not established OA features. Any OA capability
needs its own interface and implementation justified from public sources.
Renderer and Mojo types should stay below the native bridge, so app features
continue to use ADK.


Return to the [Chromium chapter](README.md).
