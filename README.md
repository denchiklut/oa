# Oa

Oa is an independent native macOS browser project built around Chromium.
This repository contains the architecture and feature documentation, the Chromium
build setup, and the first vertical slices through all four layers: native windows
over a saved sidebar of Spaces with pinned and unpinned tabs, each a Chromium page
created when first shown and moved to whichever window shows it, its favicon in
its row, a command bar for every address and search,
back, forward, reload and stop, an Archive that closed tabs go to and come back
from, dated copies of the sidebar that Help ▸ Restore Data brings back, and
pages a page opens, kept as the engine made them and placed below their opener,
which come forward when they ask to be shown, Peeks: a pinned tab's
cross-origin links and any Shift-clicked link open over the window, to be
expanded into a tab or closed into the Archive, and Favorites: a profile's grid
of tiles at the top of the sidebar in every one of its Spaces, which keep their
address and peek like pinned tabs, and JavaScript dialogs: `alert`, `confirm`,
`prompt` and "Leave site?" shown over the window as Arc shows them, with
archiving, a Peek's close and a Space's deletion waiting for the page's answer,
and downloads: a Library in the window that lists every profile's downloads with
their progress, a ring on its button and a flyout of the recent ones, and a
download location for each profile, and the page context menu: Chrome's own,
shown natively as Arc shows it, with its new tabs placed below their opener and
its new window opened on the same Space, and the command bar: one card for ⌘T,
⌘L and the URL, ranking Chromium's matches and the Space's open tabs with Arc's
own scorer, a search engine for each profile, and ⌘Y for history.

Start with the [architecture](docs/architecture/README.md). The
chapters cover UI product state and native presentation, DevKit's Swift
engine interface, Core's native integration and Chromium. The UI chapter
also records the current product slices.

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
