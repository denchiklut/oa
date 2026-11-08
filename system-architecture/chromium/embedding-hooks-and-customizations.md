# Embedding hooks and customizations

The reference attaches behavior in two ways: implementations of existing
Chromium interfaces, and extensions to interfaces or values shared with
Chromium. An added override is not automatically a patch to that interface.

## Existing integration points

| Chromium interface or mechanism | Reference use | Role of the ArcCore logical layer |
| --- | --- | --- |
| Browser main extra parts | Register startup work, services and observers | Supply configuration and receive lifecycle events |
| `ContentBrowserClient` | Customize browser-side policy, child setup and navigation throttles | Connect browser behavior to native configuration and requests |
| `ContentRendererClient` and renderer observers | Install renderer interfaces, document-start behavior and request filtering | Reach these capabilities through browser-side operations |
| Profile-keyed services | Integrate history, settings, blocking and extension-related work | Expose profile operations and notifications |
| `WebContentsDelegate` | Intercept navigation and new-page requests | Forward the decision request and manage the native integration |
| Browser-window and UI integration points | Connect engine features to a native host | Supply adapters and forward requests toward app presentation |

The retained research corrected an earlier claim: the renderer client does not
gain the previously alleged pair of new base methods. Renderer-observer
inheritance explains those table entries. Its custom renderer behavior still
exists through overrides and observer registration.

## Extensions to shared interfaces and values

| Extension found in the reference | Purpose and consumer |
| --- | --- |
| Additional browser-client hooks | Includes an artifact-page drag restriction; two other hooks have no recovered behavior in the studied build |
| Page-observer notifications and a page hook | Expose blocked-popup changes; a separate visible-capture notification has no identified consumer in the studied build |
| Extension browser-client hooks | Support custom resources, native-window installation prompting, bundled components and specific allowlist handling |
| Additional window interface entry | Used by host initialization as an identity accessor in the mapped path; the full class family remains partial |
| Additional opening dispositions | Carry destinations mapped to Split View and Little Arc toward native product routing |
| Content-blocker network error | Distinguish cancellation by the added ad blocker |
| Arc-specific freezing reason | Represent an embedder opt-out in Chromium's freezing policy |

These are artifact-level findings. They do not reveal the original source diff
or whether each replacement was achieved by a source edit or link-time wiring.

## Navigation: mechanics below, product decision above

The engine forwards a request containing the destination, referrer, navigation
type and disposition. It also has routing configuration that brings eligible
top-level requests to browser-side handling; extension-popup mode differs.

The native layer forwards the request toward ADK/App policy. The inspected
engine paths do not contain a generic deciding source/target-host comparison.
Exactly how the app chooses Peek versus another destination belongs to the
App/ADK chapters and remains a separate research question.

## OpenArch direction

OA should put integration code in its native layer and keep a separate,
small patch series for changes that cannot use existing Chromium hooks. Each
patch creates an obligation at Chromium upgrades. The reference's interface
additions explain capabilities; OA needs to design and justify its own changes.


Return to the [Chromium chapter](README.md).
