#!/bin/sh
# markdown-preview.nvim server on the pinned Node with locked dependencies
# from nvim/markdown-preview. The plugin runs: <this> --path <plugin>/app/server.js
set -eu
[ "$#" -eq 2 ] && [ "$1" = --path ] || { echo 'usage: --path APP/server.js' >&2; exit 2; }
home="$HOME/.local/share/dotfiles-markdown-preview"
# harden.js restricts the server to same-origin localhost use; see that file.
NODE_PATH="$home/node_modules" exec "$HOME/.local/bin/node" --require "$home/harden.js" "$(dirname -- "$2")/index.js" "$@"
