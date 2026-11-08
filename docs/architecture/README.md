# Architecture

This documentation describes how Oa will work: what each layer owns, how the
layers communicate, and which design decisions remain open. The Chromium, Core
and DevKit chapters cover the engine, native integration and Swift interface;
App/UI has scope notes ready for expansion.

## Four layers

| Layer | Responsibility |
| --- | --- |
| [App/UI](app/README.md) | Product model, native presentation, windows and user decisions |
| [DevKit](devkit/README.md) | Swift engine interface and translation between app and native engine |
| [Core](core/README.md) | Native adapters, ownership and integration with Chromium |
| [Chromium](chromium/README.md) | Browser infrastructure, rendering, networking, services and engine extensions |

Calls and configuration generally travel downward; events and requests for a
decision travel upward. A reply travels back to the requester. Every feature
does not necessarily cross all four layers.

These are logical responsibilities. Packaging the engine and integration code
in one framework does not combine their architectural responsibilities.

## How to read this documentation

- **Intended architecture** describes the structure Oa will use. It does not
  establish that a feature is implemented.
- **Design decisions** explain the choices Oa has made and their consequences.
- **Open questions** identify choices or contracts still to be defined.
