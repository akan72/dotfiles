#!/usr/bin/env bash
# harden.js must refuse cross-origin, rebinding and file-reading requests while
# serving same-origin localhost requests. Needs only Node and curl.
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/preview-harden.XXXXXX")
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -rf "$work"' EXIT
node --require "$root/nvim/markdown-preview/harden.js" -e '
  const server = require("http").createServer((req, res) => res.end("ok"))
  // Stand-in for engine.io, which attaches its own request/upgrade listeners.
  server.on("upgrade", (req, socket) => socket.end("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"))
  server.listen(0, "127.0.0.1", () => require("fs").writeFileSync(process.argv[1], String(server.address().port)))
' "$work/port" & pid=$!
for _ in $(seq 50); do [ -s "$work/port" ] && break; sleep 0.1; done
base="http://127.0.0.1:$(cat "$work/port")"
expect() {
  local want=$1 got; shift
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  [ "$got" = "$want" ] || { echo "expected $want, got $got: $*" >&2; exit 1; }
}
expect 200 "$base/page/1"
expect 200 -H "Origin: $base" -H "Referer: $base/page/1" "$base/_local_image_img.png"
expect 403 -H 'Host: evil.example' "$base/page/1"
expect 403 -H 'Origin: http://evil.example' "$base/page/1"
expect 403 -H 'Referer: http://evil.example/' "$base/page/1"
expect 403 "$base/_local_image_$HOME/.ssh/config"
expect 403 "$base/_local_image_img.svg"
expect 403 -H 'Sec-Fetch-Site: cross-site' "$base/page/1"
sio="$base/socket.io/?EIO=3&transport=polling&bufnr=1"
expect 200 -H "Referer: $base/page/1" "$sio"
expect 200 -H "Origin: $base" "$sio&sid=abc"
expect 403 "$sio"
expect 403 "$sio&sid=abc"
expect 403 -H "Referer: $base/page/1" "$sio&j=0"
# Any 16 bytes, base64-encoded, form a valid client key.
ws_key=$(printf 'dotfiles-fixture' | base64)
ws=(-H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H "Sec-WebSocket-Key: $ws_key")
expect 204 "${ws[@]}" -H "Origin: $base" "$base/socket.io/?EIO=3&transport=websocket"
expect 403 "${ws[@]}" -H 'Origin: http://evil.example' "$base/socket.io/?EIO=3&transport=websocket"
expect 403 "${ws[@]}" "$base/socket.io/?EIO=3&transport=websocket"
curl -s -D - -o /dev/null -H "Referer: $base/page/1" "$base/_local_image_img.svg" | grep -qi "^content-security-policy: sandbox" \
  || { echo 'local images must carry a sandbox CSP' >&2; exit 1; }
expect 403 --path-as-is "$base/_next/../../etc/hosts"
expect 403 "$base/_static/%252e%252e/package.json"
echo 'markdown preview hardening: same-origin allowed; foreign host, origin, referer, cross-site, JSONP and unidentified socket.io requests and file reads refused; images sandboxed'
