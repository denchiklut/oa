# Chromium

Chromium supplies the browser engine and browser infrastructure. The reference
browser retains that infrastructure, replaces Chrome's visible browser shell,
and adds engine capabilities that the native integration layer can control.

**Scope:** this chapter explains the Chromium side. ArcCore is mentioned as the
adjacent caller or event receiver. Its native wrapper implementation, ADK's
Swift translation and the app's product policy have their own chapters.

## Read in this order

1. [Engine foundation](engine-foundation.md): what was retained and how a native
   browser can use Chrome's browser machinery.
2. [Embedding hooks and customizations](embedding-hooks-and-customizations.md):
   where integration code attaches, and which interfaces were extended.
3. [Renderer capabilities](renderer-capabilities.md): cross-process controls,
   page effects, ad blocking and page-color reporting.
4. [Processes and configuration](processes-and-configuration.md): startup,
   profile services, utility work, feature settings and security integration.
5. [Sources and open questions](sources-and-open-questions.md): evidence limits
   and the separation between reference findings and OA decisions.

## What changed, at a glance

| Kind of work | Purpose | Examples |
| --- | --- | --- |
| Retained upstream machinery | Keep browser behavior and services | Profiles, pages, tab helpers, networking, rendering, extensions |
| Integration on existing hooks | Attach native-browser behavior | Browser/renderer clients, navigation delegates, keyed services, UI factories |
| Added engine capabilities | Make new operations available to the integration layer | Renderer agents, page effects, ad blocking, utility services |
| Changes to shared interfaces | Carry behavior upstream interfaces did not represent | Extra notifications, extension hooks and opening dispositions |
| Build and configuration changes | Select features and process behavior | Feature overrides, helper switches, sandbox policies, media integration |

The rationale inferred from this structure is to reuse Chromium's browser
services while allowing the native app to control its product experience.
The original team's internal decision process was not recovered.

**OpenArch direction:** use native UI over Chromium's `//chrome` browser
infrastructure, reached through a native bridge, with a small patch series.
Reference features in this chapter are not a list of implemented OA features or
requirements to reproduce every Arc extension.

Return to the [four-layer overview](../README.md).
