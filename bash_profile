# shellcheck shell=bash
if [ -f "$HOME/.bashrc" ]; then
    # Assimilation supplies this trusted user startup file; do not inspect live HOME during lint.
    # shellcheck source=/dev/null
    source "$HOME/.bashrc"
fi
