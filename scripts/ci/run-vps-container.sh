#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "usage: $0 image|run ubuntu|amazon-linux" >&2
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
[ "$#" -eq 2 ] || usage

image="$(image_for "$target")"

if [ "$command" = image ]; then
  echo "$image"
  exit 0
fi

[ "$command" = run ] || usage

repo_root="$(git rev-parse --show-toplevel)"

docker run --rm --interactive \
  --platform linux/amd64 \
  --env VPS_TARGET="$target" \
  --volume "$repo_root:/workspace:ro" \
  "$image" \
  bash -s <<'CONTAINER'
set -euxo pipefail

case "$VPS_TARGET" in
  ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install --yes ca-certificates curl findutils git gzip passwd tar zsh
    ;;
  amazon-linux)
    dnf install --assumeyes ca-certificates curl findutils git gzip shadow-utils tar util-linux zsh
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
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  bash -c '
    set -euo pipefail
    cd "$HOME/dotfiles"

    ./assimilate.sh
    DOTFILES="$HOME/dotfiles" scripts/ci/verify-assimilate.sh
    backup_count="$(find "$HOME/backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d " ")"

    ./assimilate.sh
    DOTFILES="$HOME/dotfiles" scripts/ci/verify-assimilate.sh
    test "$(find "$HOME/backups" -mindepth 1 -maxdepth 1 | wc -l | tr -d " ")" = "$backup_count"
  '
CONTAINER
