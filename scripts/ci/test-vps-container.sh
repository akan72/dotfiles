#!/usr/bin/env bash

set -euo pipefail

runner="scripts/ci/run-vps-container.sh"

test -x "$runner"
test "$("$runner" image ubuntu)" = "ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea"
test "$("$runner" image amazon-linux)" = "amazonlinux:2023@sha256:694092ae18877ed4e3cb9b643759ba95df1f12af12528fefa18f60f79d4c1568"
grep -Fq -- '--interactive' "$runner"
grep -Fq 'curl-minimal' "$runner"

grep -Fq 'scripts/security/install-artifact.sh' assimilate.sh
grep -Fq 'scripts/security/check-clone.sh' assimilate.sh
# shellcheck disable=SC2016 # Match literal installer source.
grep -Fq 'brew bundle check --quiet --no-upgrade --file="$DOTFILES/Brewfile"' assimilate.sh
grep -Fq 'ASSIMILATE_SKIP_PLUGIN_SYNC' assimilate.sh
grep -Fq 'ASSIMILATE_SKIP_PLUGIN_SYNC=1 ./assimilate.sh' "$runner"
grep -Fq 'ASSIMILATE_SKIP_PLUGIN_SYNC=1 scripts/ci/anonymous-github.sh ./assimilate.sh' .github/workflows/ci.yml
grep -Fq 'scripts/ci/anonymous-github.sh bash' "$runner"
grep -Fq 'ASSIMILATE_SOURCE_MODE=archive' "$runner"
grep -Fq 'source-snapshot.py' "$runner"
if grep -Fq -- '--norc' scripts/ci/verify-assimilate.sh; then
  echo "VPS shell verification must not disable .bashrc" >&2
  exit 1
fi

if "$runner" image alpine >/dev/null 2>&1; then
  echo "unsupported VPS target unexpectedly succeeded" >&2
  exit 1
fi
