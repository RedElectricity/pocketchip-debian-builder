#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Stage the official CHIP-tools flash scripts at a pinned commit and apply the
# PocketCHIP SLC-mode patch. The patched tree is disposable: re-running this
# script resets it and applies the patch again.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chip_tools_dir="${CHIP_TOOLS_DIR:-$repo_root/build/CHIP-tools}"
chip_tools_repo="https://github.com/Project-chip-crumbs/CHIP-tools.git"
chip_tools_branch="chip/stable"
chip_tools_commit="22a800e5ce9fb39cd3d23cf97b1305e543a6adc2"
patch_file="$repo_root/tools/chip-tools-pocketchip.patch"

if [[ ! -f "$patch_file" ]]; then
  printf 'error: missing %s\n' "$patch_file" >&2
  exit 1
fi

if [[ -d "$chip_tools_dir/.git" ]]; then
  git -C "$chip_tools_dir" fetch --quiet origin
else
  rm -rf "$chip_tools_dir"
  git clone --quiet --branch "$chip_tools_branch" "$chip_tools_repo" "$chip_tools_dir"
fi

git -C "$chip_tools_dir" checkout --quiet --force "$chip_tools_commit"
git -C "$chip_tools_dir" clean --quiet -fd
git -C "$chip_tools_dir" apply --check "$patch_file"
git -C "$chip_tools_dir" apply "$patch_file"

printf 'CHIP-tools %s staged in %s\n' "$chip_tools_commit" "$chip_tools_dir"
