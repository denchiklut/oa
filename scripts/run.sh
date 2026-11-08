#!/usr/bin/env bash
# Launch the existing Chromium build; never fetch or build as a side effect.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Usage: scripts/run.sh [Chromium arguments or URLs]

Launch the existing build without downloading or compiling anything.
The checkout and build output are stored in .local/chromium inside this repository.
A separate development profile is stored in that directory.
HELP
    exit 0
    ;;
esac

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  printf '%s\n' 'error: this setup currently supports Apple silicon Macs' >&2
  exit 1
}
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
chromium_root="$repo_root/.local/chromium"
app="$chromium_root/src/out/Release/Chromium.app"
[[ -x "$app/Contents/MacOS/Chromium" ]] || {
  printf '%s\n' 'error: Chromium has not been built here. Run scripts/build.sh first.' >&2
  exit 1
}
open -n "$app" --args --user-data-dir="$chromium_root/user-data" --use-mock-keychain "$@"
