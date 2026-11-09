#!/usr/bin/env bash
# Build the app and run it: on Chromium (default), on the stub engine (--stub), or launch bare Chromium (--chromium).
#
# Environment:
#   OA_DATA_DIRECTORY  Run against a separate data directory; Chromium's profile goes in its Chromium/ folder.
#   OA_ASSEMBLE_ONLY=1 Assemble the bundle without launching it.
set -euo pipefail
# shellcheck source=lib/chromium.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/chromium.sh"

mode=live
case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Usage: scripts/run.sh [--stub|--chromium] [Chromium arguments]

Default: build the Swift app, assemble .build/native/Oa.app around the Chromium build and open it.
--stub      Build and open the app on the stub engine; needs no Chromium build.
--chromium  Open the bare Chromium build, for comparison.
HELP
    exit 0
    ;;
  --stub) mode=stub; shift ;;
  --chromium) mode=chromium; shift ;;
esac

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || die "this setup currently supports Apple silicon Macs"
chromium_app="$chromium_src/$chromium_out/Chromium.app"

if [[ "$mode" == chromium ]]; then
  [[ -x "$chromium_app/Contents/MacOS/Chromium" ]] || die "Chromium has not been built here. Run scripts/build.sh first"
  exec open -n "$chromium_app" --args --user-data-dir="$chromium_root/user-data" --use-mock-keychain "$@"
fi

output="$repo_root/.build/native"
bundle="$output/Oa.app"
log "building the app"
swift build --package-path "$repo_root/ui" --scratch-path "$repo_root/.build/swift"
executable="$repo_root/.build/swift/debug/Oa"
[[ -x "$executable" ]] || executable="$(find "$repo_root/.build/swift" -type f -perm -u+x -name Oa -path '*Debug*' | head -1)"
[[ -x "$executable" ]] || die "swift build produced no Oa executable"

rm -rf "$bundle"
if [[ "$mode" == live ]]; then
  [[ -d "$chromium_app" ]] || die "no $chromium_app; run scripts/build.sh"
  framework="$chromium_app/Contents/Frameworks/Chromium Framework.framework/Chromium Framework"
  nm -gU "$framework" | grep -q " _OACoreMain$" || die "the Chromium framework has no OACoreMain; run scripts/build.sh"
  log "assembling $bundle around $chromium_app"
  ditto "$chromium_app" "$bundle"
  rm -f "$bundle/Contents/MacOS/Chromium"
  cp "$executable" "$bundle/Contents/MacOS/Oa"
  plist="$bundle/Contents/Info.plist"
  plutil -replace CFBundleExecutable -string Oa "$plist"
  plutil -replace CFBundleIdentifier -string org.oa.Oa "$plist"
  plutil -replace CFBundleName -string Oa "$plist"
  plutil -replace CFBundleDisplayName -string Oa "$plist"
else
  log "assembling $bundle on the stub engine"
  mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
  cp "$executable" "$bundle/Contents/MacOS/Oa"
  cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>org.oa.Oa.stub</string>
  <key>CFBundleName</key><string>Oa</string>
  <key>CFBundleDisplayName</key><string>Oa</string>
  <key>CFBundleExecutable</key><string>Oa</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
fi
codesign --force --sign - "$bundle"

[[ "${OA_ASSEMBLE_ONLY:-0}" == "1" ]] && exit 0
if [[ -n "${OA_DATA_DIRECTORY:-}" ]]; then
  open -n --env "OA_DATA_DIRECTORY=$OA_DATA_DIRECTORY" "$bundle" --args -ApplePersistenceIgnoreState YES "$@"
else
  open "$bundle" --args "$@"
fi
