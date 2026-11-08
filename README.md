# Oa

Oa is an independent native macOS browser project built around Chromium.
This repository currently contains the architecture, feature documentation and
Chromium build setup. The native app and Core integration will be added separately.

Start with the [architecture](docs/architecture/README.md). The
current chapters document Chromium, Core's native integration and DevKit's Swift
engine interface. App/UI has scope notes ready for expansion.

## Documentation site

[Docusaurus](docs/docusaurus) builds the site from the Markdown chapters in
`docs/architecture` and the [features](docs/features/README.md)
in `docs/features`. GitHub Actions automatically publishes it to GitHub Pages
when changes to either documentation folder or the site configuration are pushed
to `main`. The `Deploy docs` workflow can also be run manually.

## Build and run

On an Apple silicon Mac with Xcode installed:

```sh
scripts/build.sh
scripts/run.sh
```

The first command prepares and builds upstream Chromium. The first build takes
about **3 hours** and downloads roughly **100 GB**. Later builds are
incremental: small rebuilds can take seconds, while larger changes take longer.
The second command launches the existing build.

See [Contributing](CONTRIBUTING.md) for prerequisites and the separate
documentation preview steps.
