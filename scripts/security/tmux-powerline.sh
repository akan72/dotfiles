#!/usr/bin/env bash
# No TPM or main.tmux execution: retain the guarded status commands in tmux.conf.
set -euo pipefail
case "${1:-}" in left|right) ;; *) printf 'powerline unverified'; exit 1 ;; esac
security="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/security/pins.sh disable=SC1091 # Checked as its own input.
source "$security/pins.sh"
plugin="$HOME/.tmux/plugins/tmux-powerline"
if ! bash "$security/check-clone.sh" --allow-userinfo "$plugin" "$POWERLINE_ORIGIN" "$POWERLINE_COMMIT" >/dev/null 2>&1; then
  printf 'powerline unverified'
  exit 1
fi
exec bash "$plugin/powerline.sh" "$1"
