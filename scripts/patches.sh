#!/usr/bin/env bash
# Manage the Chromium patch series: apply it to the checkout, or export the checkout's commits to chromium/patches.
set -euo pipefail
# shellcheck source=lib/chromium.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/chromium.sh"

usage() {
  cat <<'HELP'
Usage: scripts/patches.sh <apply|export|status>

apply    Link core/ as src/oa and rebuild the oa-patches branch from chromium/patches on the pinned tag.
export   Write one NNNN-subject.patch per commit on oa-patches into chromium/patches.
status   Show whether the checkout matches chromium/patches.
HELP
}

require_checkout
case "${1:-}" in
  apply)
    link_core
    apply_patches
    ;;
  export)
    cd "$chromium_src"
    git rev-parse --verify --quiet "refs/heads/$patch_branch" > /dev/null || die "no $patch_branch branch; run scripts/patches.sh apply"
    base="$(git rev-parse --verify --quiet "$patch_base_ref")" || die "$patch_base_ref is missing; run scripts/patches.sh apply"
    [[ "$base" == "$(pinned_commit)" ]] || die "$patch_branch is based on another Chromium than $version; run scripts/patches.sh apply"
    require_clean_tree
    staging="$(mktemp -d)"
    trap 'rm -rf "$staging"' EXIT
    git -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.relative=false \
      format-patch --quiet --zero-commit --no-signature --no-numbered --full-index \
      --output-directory "$staging" "$base..$patch_branch"
    rm -f "$patches_dir"/*.patch
    shopt -s nullglob
    new=("$staging"/*.patch)
    ((${#new[@]})) && cp "${new[@]}" "$patches_dir/"
    log "exported ${#new[@]} patch(es) to chromium/patches"
    git -C "$repo_root" status --short -- chromium/patches
    ;;
  status)
    cd "$chromium_src"
    branch="$(git symbolic-ref --quiet --short HEAD || echo detached)"
    echo "checkout: $branch at $(git rev-parse --short HEAD), pinned $version at $(git rev-parse --short "$(pinned_commit)")"
    if [[ "$branch" == "$patch_branch" ]] && git rev-parse --verify --quiet "$patch_base_ref" > /dev/null; then
      if [[ "$(range_patch_ids "$patch_base_ref..HEAD")" == "$(series_patch_ids)" ]]; then
        echo "patches: in step with chromium/patches"
      else
        echo "patches: branch differs from chromium/patches (run scripts/patches.sh export)"
      fi
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
