# Oa

Architecture documentation for an independent native macOS browser over Chromium.

Start with the [architecture](docs/architecture/README.md). The
current chapters document Chromium and Core, the native integration layer.
App/UI and ADK have scope notes ready for expansion.

## Documentation site

[Docusaurus](docs/docusaurus) builds the site from the Markdown chapters in
`docs/architecture` and the [features](docs/features/README.md)
in `docs/features`. GitHub Actions automatically publishes it to GitHub Pages
when changes to either documentation folder or the site configuration are pushed
to `main`. The `Deploy docs` workflow can also be run manually.

To preview locally with the Bun version specified in `docs/docusaurus/package.json`:

```sh
cd docs/docusaurus
bun install --frozen-lockfile
bun run start
```

Run `bun run build` from the same directory to generate the static site.
