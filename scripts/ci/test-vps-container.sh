#!/usr/bin/env bash

set -euo pipefail

runner="scripts/ci/run-vps-container.sh"

test -x "$runner"
test "$("$runner" image ubuntu)" = "ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea"
test "$("$runner" image amazon-linux)" = "amazonlinux:2023@sha256:694092ae18877ed4e3cb9b643759ba95df1f12af12528fefa18f60f79d4c1568"

if "$runner" image alpine >/dev/null 2>&1; then
  echo "unsupported VPS target unexpectedly succeeded" >&2
  exit 1
fi
