#!/usr/bin/env bash
# Manage the Chromium patch series: apply it to the checkout, or export the checkout's commits to chromium/patches.
set -euo pipefail
# shellcheck source=lib/chromium.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/chromium.sh"

usage() {
  cat <<'HELP'
Usage: scripts/patches.sh <apply|export|status>

apply    Link core/ as src/oa and rebuild the oa-patches branches from chromium/patches on the pinned tag, and from
         chromium/patches/devtools-frontend on the DevTools frontend that tag's DEPS pins.
export   Write one NNNN-subject.patch per commit on each oa-patches branch into its directory.
status   Show whether the checkout matches chromium/patches.
HELP
}

# export_series <repository> <patch directory> <pinned base>
export_series() {
  local repo="$1" dir="$2" pinned="$3" base staging
  cd "$repo"
  git rev-parse --verify --quiet "refs/heads/$patch_branch" > /dev/null ||
    die "no $patch_branch branch in $repo; run scripts/patches.sh apply"
  base="$(git rev-parse --verify --quiet "$patch_base_ref")" || die "$patch_base_ref is missing; run scripts/patches.sh apply"
  [[ "$base" == "$pinned" ]] || die "$patch_branch in $repo is based on another revision than $version pins; run scripts/patches.sh apply"
  require_clean_tree "$repo"
  staging="$(mktemp -d)"
  # Expanded now: the function's local is gone by the time the trap runs.
  # shellcheck disable=SC2064
  trap "rm -rf '$staging'" EXIT
  git -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.relative=false \
    format-patch --quiet --zero-commit --no-signature --no-numbered --full-index \
    --output-directory "$staging" "$base..$patch_branch"
  mkdir -p "$dir"
  rm -f "$dir"/*.patch
  shopt -s nullglob
  local new=("$staging"/*.patch)
  shopt -u nullglob
  ((${#new[@]})) && cp "${new[@]}" "$dir/"
  rm -rf "$staging"
  log "exported ${#new[@]} patch(es) to ${dir#"$repo_root"/}"
}

# status_series <repository> <patch directory> <pinned base> <name>
status_series() {
  local repo="$1" dir="$2" pinned="$3" name="$4" branch
  cd "$repo"
  branch="$(git symbolic-ref --quiet --short HEAD || echo detached)"
  echo "$name: $branch at $(git rev-parse --short HEAD), pinned $version at $(git rev-parse --short "$pinned")"
  if [[ "$branch" == "$patch_branch" ]] && git rev-parse --verify --quiet "$patch_base_ref" > /dev/null; then
    if [[ "$(range_patch_ids "$patch_base_ref..HEAD" "$repo")" == "$(series_patch_ids "$dir")" ]]; then
      echo "$name patches: in step with ${dir#"$repo_root"/}"
    else
      echo "$name patches: branch differs from ${dir#"$repo_root"/} (run scripts/patches.sh export)"
    fi
  fi
}

require_checkout
case "${1:-}" in
  apply)
    link_core
    apply_patches
    ;;
  export)
    export_series "$chromium_src" "$patches_dir" "$(pinned_commit)"
    export_series "$frontend_src" "$frontend_patches_dir" "$(frontend_pinned_commit)"
    git -C "$repo_root" status --short -- chromium/patches
    ;;
  status)
    status_series "$chromium_src" "$patches_dir" "$(pinned_commit)" checkout
    status_series "$frontend_src" "$frontend_patches_dir" "$(frontend_pinned_commit)" "devtools frontend"
    ;;
  *)
    usage
    exit 1
    ;;
esac
