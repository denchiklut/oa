# ADK

**Status: scope only.** The detailed reference-architecture chapter has not been
written. The current documentation work concentrates on Chromium.

This layer presents the engine to Swift callers. It translates native objects,
identities, events, errors and replies into the interface used by the app.

Future chapters should explain the application/context/page interfaces, event
delivery and the meaning of caller-visible identities and lifetimes. Swift
translation belongs here; the underlying native object's ownership belongs in
Core; product presentation belongs in App/UI.

For Oa, the intended split is a Swift engine interface with both a stub
adapter and a live adapter over Core. App/UI work should be possible
without building Chromium. Exact contracts remain work for this chapter.

Return to the [system overview](../README.md).
