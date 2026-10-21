#!/usr/bin/env bash
# No TPM or main.tmux execution: retain the guarded status commands in tmux.conf.
set -euo pipefail
case "${1:-}" in left|right) ;; *) printf 'powerline unverified'; exit 1 ;; esac
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
plugin="$HOME/.tmux/plugins/tmux-powerline"
if ! bash "$repo_root/scripts/security/check-clone.sh" --allow-userinfo "$plugin" \
  https://github.com/erikw/tmux-powerline 6079ace8d534a01d4d964b8b854b223f72edaf4b >/dev/null 2>&1; then
  printf 'powerline unverified'
  exit 1
fi
exec bash "$plugin/powerline.sh" "$1"
