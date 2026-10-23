#!/bin/sh
# Stable command entry point; implementation is isolated Python.
set -eu
security_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec python3 -I -S "$security_dir/install-artifact.py" "$@"
