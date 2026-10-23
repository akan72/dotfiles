#!/bin/bash
# Scan tracked worktree source without executing project/install code.
set -euo pipefail
script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$script_dir/scan-source.py" "$@"
