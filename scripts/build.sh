#!/usr/bin/env bash
# Prepare the pinned upstream Chromium checkout and build it incrementally.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
chromium_root="$repo_root/.local/chromium"
check_only=false

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Usage: scripts/build.sh [--check]

Download Chromium and its tools on the first run, then build incrementally.
--check checks prerequisites without downloading, building or changing files.
The checkout and build output are stored in .local/chromium inside this repository.
HELP
    exit 0
    ;;
  --check) check_only=true ;;
  '') ;;
  *) die "unknown argument: $1; use --help" ;;
esac
[[ $# -le 1 ]] || die "too many arguments; use --help"

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] ||
  die "this setup currently supports Apple silicon Macs"
[[ "$chromium_root" != *[[:space:]]* ]] ||
  die "Chromium requires a checkout path without spaces"
version="$(tr -d '[:space:]' < "$repo_root/chromium/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid chromium/VERSION"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[[ -d "$DEVELOPER_DIR" ]] || die "install Xcode at /Applications/Xcode.app, or set DEVELOPER_DIR"
xcodebuild -version >/dev/null 2>&1 ||
  die "open Xcode and finish its first-launch setup, then retry"
xcrun --sdk macosx --show-sdk-path >/dev/null || die "Xcode's macOS SDK is missing"
git --version >/dev/null || die "Git is missing"

if [[ -e "$chromium_root" ]]; then
  [[ -d "$chromium_root" ]] || die "$chromium_root is not a directory"
  if [[ ! -f "$chromium_root/.oa-checkout" && -n "$(ls -A "$chromium_root")" ]]; then
    die "$chromium_root already contains files from another setup. Move that checkout aside before building with these scripts"
  fi
  if [[ -f "$chromium_root/.oa-checkout" ]]; then
    [[ "$(cat "$chromium_root/.oa-checkout")" == 'Oa Chromium developer checkout' ]] ||
      die "$chromium_root has an unrecognized checkout marker"
  fi
fi

if "$check_only"; then
  xcrun metal --version >/dev/null 2>&1 ||
    die "Metal tools are missing; scripts/build.sh will download them, or run: xcodebuild -downloadComponent MetalToolchain"
  log "Prerequisites ready for Chromium $version. Checkout: $chromium_root"
  exit 0
fi

mkdir -p "$chromium_root"
chromium_root="$(cd "$chromium_root" && pwd -P)"
mkdir "$chromium_root/.oa-build-lock" 2>/dev/null ||
  die "a build is already running, or an interrupted build left $chromium_root/.oa-build-lock"
trap 'rmdir "$chromium_root/.oa-build-lock"' EXIT
printf '%s\n' 'Oa Chromium developer checkout' > "$chromium_root/.oa-checkout"

if ! xcrun metal --version >/dev/null 2>&1; then
  log "Downloading Xcode's Metal tools"
  xcodebuild -downloadComponent MetalToolchain
  xcrun metal --version >/dev/null 2>&1 || die "Metal tools are still unavailable"
fi

if [[ ! -d "$chromium_root/depot_tools/.git" ]]; then
  log "Downloading Chromium's build tools"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$chromium_root/depot_tools"
fi
export PATH="$chromium_root/depot_tools:$PATH"
export DEPOT_TOOLS_METRICS=0
cd "$chromium_root"

saved_version=''
saved_commit=''
if [[ -f .oa-synced-revision ]]; then
  read -r saved_version saved_commit < .oa-synced-revision
fi
if [[ "$saved_version" != "$version" || ! -d src/.git ]]; then
  if [[ -d src/.git ]]; then
    [[ -z "$(git -C src status --porcelain --untracked-files=no)" ]] ||
      die "Chromium has local edits. Save them before changing or resuming the pinned checkout"
    if [[ -n "$saved_commit" ]]; then
      [[ "$(git -C src rev-parse HEAD)" == "$saved_commit" ]] ||
        die "Chromium has local commits. Preserve them before updating the pinned version"
    elif git -C src symbolic-ref --quiet HEAD >/dev/null; then
      die "Chromium is on a local branch; preserve it before resuming checkout setup"
    fi
  fi
  log "Downloading Chromium $version and its dependencies; the first download can take hours"
  gclient config --managed --name=src https://chromium.googlesource.com/chromium/src.git
  caffeinate -i gclient sync --no-history --revision "src@refs/tags/$version"
  saved_commit="$(git -C src rev-parse HEAD)"
  printf '%s %s\n' "$version" "$saved_commit" > .oa-synced-revision
fi

git -C src merge-base --is-ancestor "$saved_commit" HEAD ||
  die "this checkout is no longer based on the recorded Chromium revision"
cd src
mkdir -p out/Release
if ! cmp -s "$repo_root/chromium/args.gn" out/Release/args.gn || [[ ! -f out/Release/build.ninja ]]; then
  cp "$repo_root/chromium/args.gn" out/Release/args.gn
  log 'Generating build files'
  gn gen out/Release
fi
log 'Building Chromium at low CPU priority; later builds reuse this checkout and build output'
nice -n 19 caffeinate -i autoninja -C out/Release chrome
[[ -x out/Release/Chromium.app/Contents/MacOS/Chromium ]] || die "the build did not produce Chromium.app"
log "Build complete. Launch with: $repo_root/scripts/run.sh"
