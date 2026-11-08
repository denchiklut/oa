# App / UI

**Status: scope only.** The detailed reference-architecture chapter has not been
written. The Chromium, Core and DevKit chapters cover the engine, native
integration and Swift interface.

This layer owns product state and presentation: Spaces, sidebar items, native
windows, settings, routing decisions and saved application state. It consumes
the Swift engine interface exposed by DevKit.

Future chapters belong here when they explain how a user action becomes a
product decision, how the app presents engine requests, or how app state survives
relaunch. Chromium internals and native engine adapters belong below this layer.

For Oa, the intended rule is that the app owns product state and talks to the
engine through DevKit. Detailed state, persistence and presentation decisions
will be documented in this chapter as they are made.

Return to the [system overview](../README.md).
