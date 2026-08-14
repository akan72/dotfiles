#!/usr/bin/env bash

set -euo pipefail

runner="scripts/ci/run-vps-container.sh"

test -x "$runner"
test "$("$runner" image ubuntu)" = "ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea"
test "$("$runner" image amazon-linux)" = "amazonlinux:2023@sha256:694092ae18877ed4e3cb9b643759ba95df1f12af12528fefa18f60f79d4c1568"
grep -Fq -- '--interactive' "$runner"
grep -Fq 'curl-minimal' "$runner"

grep -Fq 'set -euxo pipefail' assimilate.sh
grep -Fq '28d1352dbcb436d3111c3594b9e1588e94950464' assimilate.sh
grep -Fq 'NVIM_VERSION=0.12.4' assimilate.sh
grep -Fq 'set -euxo pipefail' scripts/ci/verify-assimilate.sh
grep -Fq 'bash --noprofile -ic' scripts/ci/verify-assimilate.sh
grep -Fq "zsh -ic 'printf" scripts/ci/verify-assimilate.sh
if grep -Fq -- '--norc' scripts/ci/verify-assimilate.sh; then
  echo "VPS shell verification must not disable .bashrc" >&2
  exit 1
fi

if "$runner" image alpine >/dev/null 2>&1; then
  echo "unsupported VPS target unexpectedly succeeded" >&2
  exit 1
fi
