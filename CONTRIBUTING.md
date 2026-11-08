# Contributing

Start with the Chromium engine. These scripts currently build upstream Chromium;
Oa’s native app and Core integration will be added separately.

## Build and run

You need an Apple silicon Mac and [Xcode 27 or newer](https://developer.apple.com/xcode/)
at `/Applications/Xcode.app`. Open Xcode once to finish its setup.

1. Clone the repository:

   ```sh
   git clone https://github.com/denchiklut/oa.git
   cd oa
   ```

2. Build:

   ```sh
   scripts/build.sh
   ```

   The first build takes about **3 hours** and downloads roughly **100 GB**.
   The exact time depends on your Mac and connection. The script downloads the
   tools and pinned Chromium source, then compiles it.

   **Later builds are incremental:** they reuse the downloaded source and existing
   build output. Small rebuilds can take seconds; larger changes, clean builds and
   Chromium updates can take longer.

3. Run:

   ```sh
   scripts/run.sh
   ```

   You should see a Chromium browser window. Running does not rebuild anything.
   Run the build command again after changing engine code or build configuration.

The checkout, build output and separate development profile live in
`.local/chromium/` inside your Oa checkout. Each project keeps its own
Chromium build, so your existing `~/chromium` setup is unaffected.

`scripts/build.sh --check` checks prerequisites without downloading or building.
The Chromium version and build flags are in `chromium/`.

## Edit the documentation

With [Node.js 24](https://nodejs.org/en/download) and
[Bun 1.4.4](https://bun.com/docs/installation#installing-a-specific-version)
installed, run from your Oa checkout:

```sh
cd docs/docusaurus
bun install --frozen-lockfile
bun run start
```

Open <http://localhost:3000/oa/>. Edit pages in `docs/architecture/` or
`docs/features/`; the preview refreshes automatically. Press `Ctrl+C` to stop it.
Run `bun run build` from the same directory before opening a pull request.
Keep each pull request focused and briefly explain what changed and why.
