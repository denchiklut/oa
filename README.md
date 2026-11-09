# Oa

Oa is an independent native macOS browser project built around Chromium.
This repository contains the architecture and feature documentation, the Chromium
build setup, and the first vertical slices through all four layers: a native window
with a sidebar of tabs, each a Chromium page, with a URL field, back, forward,
reload and stop.

Start with the [architecture](docs/architecture/README.md). The
current chapters document Chromium, Core's native integration and DevKit's Swift
engine interface. App/UI has scope notes ready for expansion.

## Documentation site

[Docusaurus](docs/docusaurus) builds the site from the Markdown chapters in
`docs/architecture` and the [features](docs/features/README.md)
in `docs/features`. GitHub Actions automatically publishes it to GitHub Pages
when changes to either documentation folder or the site configuration are pushed
to `main`. The `Deploy docs` workflow can also be run manually.

## Layout

```
ui/        The app: a SwiftPM package, SwiftUI and AppKit. Talks to the engine through DevKit only
devkit/    DevKit: the Swift engine protocols, a stub engine, and the live Chromium adapter
core/      Core and the Chromium-side engine code, built inside the Chromium tree as //oa
chromium/  Pinned Chromium version, build flags and the patch series
scripts/   build.sh (Chromium with //oa), run.sh (the app), patches.sh
```

## Build and run

On an Apple silicon Mac with Xcode installed:

```sh
scripts/build.sh          # Chromium with //oa linked in; the first build takes hours and ~100 GB
scripts/run.sh            # the app on Chromium
scripts/run.sh --stub     # the app on the stub engine; needs no Chromium build
```

The first build downloads and compiles Chromium. Later builds are incremental:
a change to `core/` rebuilds in about a minute. Changing only `ui/` or `devkit/`
needs no Chromium rebuild.

See [Contributing](CONTRIBUTING.md) for prerequisites and the separate
documentation preview steps.
