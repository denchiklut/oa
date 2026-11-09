# Chromium patches

The numbered series applied on top of the release in [`../VERSION`](../VERSION). A change goes here only when it
can't live in `//oa` (`core/`). Every patch is rebased at each Chromium update, so keep the series small.

| Patch | Why |
| --- | --- |
| 0001 | Links `//oa` into Chromium's framework and exports `OACoreMain`, the entry point the app calls instead of `ChromeMain` |
| 0002 | Lets the app replace Chrome's Mac `AppController` and main menu, so the app owns its delegate, menu and quit |
| 0003 | Lets `//oa` supply every `Browser`'s window, so Chrome's views are never built |
| 0004 | Lets `//oa` supply permission prompts; Chrome's Views prompts crash without a `BrowserView` |
| 0005 | Lets the embedder load the startup profile without a window, in place of `--no-startup-window` and its keep-alives |

Don't edit these files by hand. Commit on the `oa-patches` branch in `.local/chromium/src`, then run
`scripts/patches.sh export`. `scripts/build.sh` applies the series before building.
