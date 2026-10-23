#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 image|run ubuntu|amazon-linux [--working [--include REVIEWED_PATH]...]" >&2
  exit 2
}

image_for() {
  case "$1" in
    ubuntu)
      echo "ubuntu:24.04@sha256:561618e2c15bf2397621dd04f96926663a3b5616c189cf7e38db7e82f5c538ea"
      ;;
    amazon-linux)
      echo "amazonlinux:2023@sha256:694092ae18877ed4e3cb9b643759ba95df1f12af12528fefa18f60f79d4c1568"
      ;;
    *)
      echo "unsupported VPS target: $1" >&2
      return 2
      ;;
  esac
}

command="${1:-}"
target="${2:-}"
[ "$#" -ge 2 ] || usage
shift 2
snapshot_args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --working) snapshot_args+=(--working); shift ;;
    --include) [ "$#" -ge 2 ] || usage; snapshot_args+=(--include "$2"); shift 2 ;;
    *) usage ;;
  esac
done

image="$(image_for "$target")"

if [ "$command" = image ]; then
  echo "$image"
  exit 0
fi

[ "$command" = run ] || usage

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
context=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-vps-context.XXXXXX")
trap 'rm -rf "$context"' EXIT HUP INT TERM
python3 "$repo_root/scripts/security/source-snapshot.py" --repo "$repo_root" --output "$context/source" ${snapshot_args[@]+"${snapshot_args[@]}"}


docker run --rm --interactive \
  --platform linux/amd64 \
  --env VPS_TARGET="$target" \
  --volume "$context/source:/workspace:ro" \
  "$image" \
  bash -s <<'CONTAINER'
set -euxo pipefail

case "$VPS_TARGET" in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --yes ca-certificates curl findutils git gzip passwd tar zsh jq python3
    ;;
  amazon-linux)
    dnf install --assumeyes ca-certificates curl-minimal findutils git gzip shadow-utils tar util-linux zsh jq python3
    ;;
  *)
    echo "unsupported VPS target: $VPS_TARGET" >&2
    exit 2
    ;;
esac

useradd --create-home --shell /bin/bash dotfiles
cp -a /workspace /home/dotfiles/dotfiles
chown -R dotfiles:dotfiles /home/dotfiles/dotfiles

runuser --user dotfiles -- env \
  HOME=/home/dotfiles \
  ASSIMILATE_SOURCE_MODE=archive \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  DOTFILES_DISPOSABLE_CI=1 \
  /home/dotfiles/dotfiles/scripts/ci/anonymous-github.sh bash -c '
    set -euo pipefail
    cd "$HOME/dotfiles"

    first_started=$SECONDS
    ./assimilate.sh
    DOTFILES="$HOME/dotfiles" scripts/ci/verify-assimilate.sh
    first_seconds=$((SECONDS - first_started))
    backup_count="$(find "$HOME/backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d " ")"

    second_started=$SECONDS
    ASSIMILATE_SKIP_PLUGIN_SYNC=1 ./assimilate.sh
    DOTFILES="$HOME/dotfiles" scripts/ci/verify-assimilate.sh
    second_seconds=$((SECONDS - second_started))
    test "$(find "$HOME/backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d " ")" = "$backup_count"

    echo "> Install timing: clean=${first_seconds}s idempotency=${second_seconds}s"
  '
CONTAINER

# Confirm the tested tracked bytes and selected source HEAD did not change.
python3 "$repo_root/scripts/security/source-snapshot.py" --repo "$repo_root" --output "$context/after" ${snapshot_args[@]+"${snapshot_args[@]}"}
cmp "$context/source/.dotfiles-source-manifest.json" "$context/after/.dotfiles-source-manifest.json"
