# System architecture

This documentation explains the browser architecture that informs OpenArch (OA):
what each layer owns, how the layers communicate, and which decisions OA still
needs to make. It starts with the Chromium layer and grows one layer at a time.

## Four layers

| Layer | Responsibility | Chapter status |
| --- | --- | --- |
| [App/UI](app/README.md) | Product model, native presentation, windows and user decisions | Scope only |
| [ADK](adk/README.md) | Swift engine interface and translation between app and native engine | Scope only |
| [ArcCore / OpenArchCore](arccore/README.md) | Native adapters, ownership and integration with Chromium | Scope only |
| [Chromium](chromium/README.md) | Browser infrastructure, rendering, networking, services and engine extensions | Initial architecture chapter |

Calls and configuration generally travel downward; events and requests for a
decision travel upward. A reply travels back to the requester. Every feature
does not necessarily cross all four layers.

These are logical responsibilities. ArcCore.framework packages Chromium together
with integration code; packaging does not decide which logical layer owns a
mechanism. ArcCore names the reference implementation; OpenArchCore names OA's
independent native integration layer.

## How to read this documentation

- **Reference architecture** explains the architecture inferred from the studied
  Arc release, in our own words. It describes capabilities and selected static
  paths, not a record of observed execution or the original team's design intent.
- **OpenArch direction** describes the architecture OA intends to follow.
  A documented direction does not establish that it is implemented in this repo.
- **Unknown** identifies an unresolved detail or an outstanding design choice.

The reference baseline is Arc 1.172.1 with ArcCore / Chromium 157.0.8103.39,
arm64. This documentation was assembled on November 8, 2026. Findings about that
release should not be assumed to describe later versions.

## Keeping the split useful

Write each mechanism in its owning layer. Describe adjacent layers only far
enough to explain the input, output or decision at their interface. For example,
Chromium detects a navigation; ArcCore forwards a request; ADK translates it;
the app decides its product destination. Those are four separate responsibilities.

Add topic files inside each layer as its chapter grows. Prefer explanations of
purpose, structure and representative flows over implementation catalogs.

This is architecture documentation, not a reconstruction of Arc's source code.
The repository contains no decompiled code, raw binary evidence or extracted
assets. OA implementation work should use Chromium and Apple public sources and
make its own choices for interfaces, configuration and product behavior.
