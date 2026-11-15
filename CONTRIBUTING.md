# Contributing

The app, DevKit, Core and the Chromium build live in this repository. UI work
runs on the stub engine and needs no Chromium checkout.

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
   tools and pinned Chromium source, links `core/` into the checkout as
   `src/oa`, applies `chromium/patches` on the `oa-patches` branch, then compiles.

   **Later builds are incremental:** they reuse the downloaded source and existing
   build output. Small rebuilds can take seconds; larger changes, clean builds and
   Chromium updates can take longer.

3. Run:

   ```sh
   scripts/run.sh
   ```

   This builds the Swift app, assembles `.build/native/Oa.app` around the
   Chromium build and opens it. You should see a native window with a page in it.
   Run the build command again after changing `core/` or the patches. Use
   `OA_DATA_DIRECTORY=/tmp/oa-dev scripts/run.sh` for a separate data directory.

   Without a Chromium build, `scripts/run.sh --stub` runs the app on placeholder
   pages, which is enough for most UI work.

The checkout, build output and separate development profile live in
`.local/chromium/` inside your Oa checkout. Each project keeps its own
Chromium build, so your existing `~/chromium` setup is unaffected.

`scripts/build.sh --check` checks prerequisites without downloading or building.
The Chromium version and build flags are in `chromium/`.

## Change Chromium

Code goes in `core/` (`//oa`) whenever it can. A change to Chromium itself is a
commit on the `oa-patches` branch in `.local/chromium/src`, exported with
`scripts/patches.sh export` into `chromium/patches/`, which you commit here.
`scripts/patches.sh status` shows whether the checkout matches the series. After
a Chromium update, rerun `scripts/generate_forwarding_delegate.py`.

Swift is formatted with `swift format --in-place --recursive ui devkit`; C++ in
`core/` follows Chromium style (`git cl format` in the checkout).

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
