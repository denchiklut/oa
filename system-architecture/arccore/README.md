# ArcCore / OpenArchCore

**Status: scope only.** The detailed native-integration chapter has not been
written. The current documentation work concentrates on Chromium.

This logical layer joins native callers to Chromium: adapters, delegates,
observers, ownership and request/reply translation. It exposes native engine
objects without requiring Swift callers to work with Chromium C++ types.

ArcCore names the reference implementation. OpenArchCore names OA's independent
implementation. Packaging Chromium inside ArcCore.framework does not make all
Chromium behavior part of this logical layer.

Future chapters should explain native application/context/page adapters, how
native views join app windows, who owns requests and pages, and what happens
when callers, delegates or engine objects disappear. The Chromium chapter names
this layer only as the consumer or provider of an engine interface.

For OA, the intended native layer hides Chromium C++ types behind native
interfaces. It should concentrate engine integration and lifetime management
so those concerns do not spread into the app.

Return to the [system overview](../README.md).
