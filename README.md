# Oa

Architecture documentation for an independent native macOS browser over Chromium.

Start with the [system architecture](docs/system-architecture/README.md). The
current chapters document Chromium and Core, the native integration layer.
App/UI and ADK have scope notes ready for expansion.

## Documentation site

[Docusaurus](docs/docusaurus) builds the site from the Markdown chapters in
`docs/system-architecture`. GitHub Actions publishes it to GitHub Pages.

To preview locally with the Bun version specified in `docs/docusaurus/package.json`:

```sh
cd docs/docusaurus
bun install --frozen-lockfile
bun run start
```

Run `bun run build` from the same directory to generate the static site.
