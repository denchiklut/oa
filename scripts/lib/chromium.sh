# shellcheck shell=bash
# Shared setup for scripts/*.sh. Source it; don't run it.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
chromium_root="$repo_root/.local/chromium"
chromium_src="$chromium_root/src"
chromium_out="${CHROMIUM_OUT:-out/Release}"
patches_dir="$repo_root/chromium/patches"
version="$(tr -d '[:space:]' < "$repo_root/chromium/VERSION")"

patch_branch="oa-patches"
patch_base_ref="refs/oa/base"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$chromium_root/depot_tools:$PATH"
export DEPOT_TOOLS_METRICS=0

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid chromium/VERSION"

require_checkout() {
  [[ -d "$chromium_src/.git" ]] || die "no Chromium checkout at $chromium_src; run scripts/build.sh"
}

pinned_commit() {
  git -C "$chromium_src" rev-parse --verify --quiet "refs/tags/$version^{commit}"
}

require_clean_tree() {
  [[ -z "$(git -C "$chromium_src" status --porcelain --untracked-files=no)" ]] ||
    die "$chromium_src has uncommitted changes. Commit them on $patch_branch and run scripts/patches.sh export, or discard them"
}

range_patch_ids() {
  git -C "$chromium_src" log --reverse -p --format='commit %H' "$1" | git patch-id --stable | cut -d' ' -f1
}

series_patch_ids() {
  local patch
  for patch in "$patches_dir"/*.patch; do
    [[ -e "$patch" ]] || continue
    git patch-id --stable < "$patch" | cut -d' ' -f1
  done
}

link_core() {
  local link="$chromium_src/oa"
  if [[ -e "$link" && ! -L "$link" ]]; then
    die "$link exists and is not a symlink; move it away"
  fi
  ln -sfn "$repo_root/core" "$link"
  local exclude
  exclude="$(git -C "$chromium_src" rev-parse --git-path info/exclude)"
  mkdir -p "$(dirname "$exclude")"
  grep -qxF "/oa" "$exclude" 2>/dev/null || printf '/oa\n' >> "$exclude"
}

apply_patches() {
  local base
  base="$(pinned_commit)" || die "tag $version is missing from the checkout"
  cd "$chromium_src"
  [[ ! -d "$(git rev-parse --git-path rebase-apply)" ]] ||
    die "a git am is in progress in $chromium_src; finish it (git am --continue) or abort it (git am --abort)"
  require_clean_tree
  local series_ids
  series_ids="$(series_patch_ids)"
  if git rev-parse --verify --quiet "refs/heads/$patch_branch" > /dev/null; then
    local old_base branch_ids="unknown base"
    old_base="$(git rev-parse --verify --quiet "$patch_base_ref" || true)"
    [[ -z "$old_base" ]] || branch_ids="$(range_patch_ids "$old_base..$patch_branch")"
    if [[ "$old_base" == "$base" && "$branch_ids" == "$series_ids" ]]; then
      git checkout --quiet "$patch_branch"
      return 0
    fi
    local unsaved="$branch_ids"
    [[ -z "$old_base" ]] || unsaved="$(comm -23 <(sort <<< "$branch_ids") <(sort <<< "$series_ids"))"
    if [[ -n "$unsaved" && "${FORCE:-0}" != "1" ]]; then
      die "$patch_branch has commits that are not in chromium/patches. Run scripts/patches.sh export to keep them, or rerun with FORCE=1 to drop them"
    fi
  fi
  log "rebuilding $patch_branch on Chromium $version"
  git update-ref "$patch_base_ref" "$base"
  git checkout --quiet -B "$patch_branch" "$base"
  shopt -s nullglob
  local patches=("$patches_dir"/*.patch)
  shopt -u nullglob
  ((${#patches[@]})) || return 0
  git am --quiet --3way "${patches[@]}" ||
    die "a patch did not apply. Resolve it in $chromium_src, run git am --continue, then scripts/patches.sh export"
  log "applied ${#patches[@]} patch(es)"
}
