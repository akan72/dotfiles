#!/usr/bin/env bash
# Build a reviewed source release from scripts/security/sources.json into
# ~/.local/share/dotfiles-src/NAME-VERSION. The tarball SHA-256 is verified before
# unpacking; a receipt records the SHA-256 of every installed file, and --check
# (also run before any rebuild) refuses an installation that no longer matches.
# libevent and protobuf are built static; OpenSSL is shared but lives in its own
# pinned prefix. Nothing here depends on Homebrew or a system package manager.
# usage: build-source.sh [--check] NAME
set -euo pipefail
check=0
if [ "${1:-}" = --check ]; then check=1; shift; fi
[ "$#" = 1 ] || { echo 'usage: build-source.sh [--check] NAME' >&2; exit 2; }
name=$1
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
manifest="$here/sources.json"
field() { jq -er --arg n "$name" ".sources[\$n].$1" "$manifest"; }
version=$(field version) || { echo "no reviewed source for $name" >&2; exit 1; }
url=$(field url); sha=$(field sha256); top=$(field root)
[[ "$sha" =~ ^[0-9a-f]{64}$ && "$url" == https://* && "$top" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo 'invalid source metadata' >&2; exit 1; }
root="$HOME/.local/share/dotfiles-src"
prefix="$root/$name-$version"
state="$HOME/.local/state/dotfiles-security/sources"
receipt="$state/$name-$version.json"

inventory() { (cd "$prefix" && find . \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
  if [ -L "$f" ]; then printf 'link:%s %s\n' "$(readlink "$f")" "$f"; else printf '%s %s\n' "$(shasum -a 256 "$f" | cut -c1-64)" "$f"; fi; done); }
verify() {
  [ -f "$receipt" ] || { echo "unmanaged installation: $prefix (no receipt); move it aside and rerun" >&2; return 1; }
  [ "$(jq -r .sha256 "$receipt")" = "$sha" ] || { echo "receipt is for another source tarball: $prefix" >&2; return 1; }
  [ "$(jq -r .files "$receipt")" = "$(inventory)" ] || { echo "installed source build changed: $prefix" >&2; return 1; }
}

if [ -e "$prefix" ]; then verify && { echo "verified source build: $name $version"; exit 0; }; exit 1; fi
if [ "$check" = 1 ]; then echo "ready to build reviewed source: $name $version"; exit 0; fi

# Dependencies are reviewed sources too; build (or verify) them first.
case "$name" in
  tmux) deps=(libevent) ;;
  mosh) deps=(protobuf); [ "$(uname -s)" = Darwin ] || deps+=(openssl) ;;
  postgresql) deps=(openssl) ;;
  *) deps=() ;;
esac
for dep in ${deps[@]+"${deps[@]}"}; do "$0" "$dep"; done
dep_prefix() { printf '%s/%s-%s' "$root" "$1" "$(jq -er --arg n "$1" '.sources[$n].version' "$manifest")"; }

umask 022
work=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-src-$name.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
echo "Downloading $name $version"
curl -fsSL --proto =https --proto-redir =https -o "$work/source" "$url"
[ "$(shasum -a 256 "$work/source" | cut -c1-64)" = "$sha" ] || { echo "source SHA-256 mismatch: $name" >&2; exit 1; }
mkdir "$work/src"; tar -xf "$work/source" -C "$work/src"
[ -d "$work/src/$top" ] || { echo "unexpected source layout: $name" >&2; exit 1; }
cd "$work/src/$top"
jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
# A partially updated Command Line Tools install can ship an SDK newer than its
# linker understands. Use the default SDK when it links, else the newest one that does.
if [ "$(uname -s)" = Darwin ] && [ -z "${SDKROOT:-}" ]; then
  printf 'int main(void){return 0;}\n' > "$work/probe.c"
  if ! cc "$work/probe.c" -o "$work/probe" 2>/dev/null; then
    for sdk in $(ls -d "$(xcode-select -p)"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -t X -k 3 -V -r); do
      if SDKROOT="$sdk" cc "$work/probe.c" -o "$work/probe" 2>/dev/null; then
        export SDKROOT="$sdk"
        echo "NOTE: default macOS SDK does not link with this linker; using ${sdk##*/}. Update the Command Line Tools." >&2
        break
      fi
    done
    [ -n "${SDKROOT:-}" ] || { echo 'no macOS SDK links with the installed Command Line Tools' >&2; exit 1; }
  fi
fi
stage="$work/stage"
echo "Building $name $version"
case "$name" in
  openssl)
    # Shared as well as static: PostgreSQL's libpq refuses a static OpenSSL
    # because OpenSSL registers an atexit handler.
    ./Configure --prefix="$prefix" --openssldir="$prefix/ssl" --libdir=lib no-tests no-docs
    make -j"$jobs"; make DESTDIR="$stage" install_sw install_ssldirs ;;
  libevent)
    ./configure --prefix="$prefix" --disable-shared --disable-openssl --disable-samples --disable-libevent-regress --disable-debug-mode
    make -j"$jobs"; make DESTDIR="$stage" install ;;
  protobuf)
    ./configure --prefix="$prefix" --disable-shared
    make -j"$jobs"; make DESTDIR="$stage" install ;;
  tmux)
    ev=$(dep_prefix libevent)
    ./configure --prefix="$prefix" --disable-utf8proc --disable-jemalloc \
      LIBEVENT_CORE_CFLAGS="-I$ev/include" LIBEVENT_CORE_LIBS="$ev/lib/libevent_core.a" \
      LIBEVENT_CFLAGS="-I$ev/include" LIBEVENT_LIBS="$ev/lib/libevent.a"
    make -j"$jobs"; make DESTDIR="$stage" install ;;
  mosh)
    pb=$(dep_prefix protobuf)
    crypto=(--with-crypto-library=apple-common-crypto)
    if [ "$(uname -s)" != Darwin ]; then
      ssl=$(dep_prefix openssl)
      crypto=(--with-crypto-library=openssl OPENSSL_CFLAGS="-I$ssl/include" OPENSSL_LIBS="$ssl/lib/libcrypto.a")
    fi
    ./configure --prefix="$prefix" "${crypto[@]}" PROTOC="$pb/bin/protoc" \
      protobuf_CFLAGS="-I$pb/include" protobuf_LIBS="$pb/lib/libprotobuf.a" \
      ZLIB_CFLAGS=" " ZLIB_LIBS="-lz" CXXFLAGS="-O2 -std=c++17"
    make -j"$jobs"; make DESTDIR="$stage" install ;;
  postgresql)
    ssl=$(dep_prefix openssl)
    readline=(--with-libedit-preferred); [ "$(uname -s)" = Darwin ] || readline=(--without-readline)
    ./configure --prefix="$prefix" --with-openssl --without-icu "${readline[@]}" \
      CPPFLAGS="-I$ssl/include" LDFLAGS="-L$ssl/lib"
    make -j"$jobs"; make DESTDIR="$stage" install ;;
  *) echo "no build recipe for $name" >&2; exit 1 ;;
esac
[ -d "$stage$prefix" ] || { echo "build produced no installation: $name" >&2; exit 1; }
mkdir -p "$root" "$state"; chmod 700 "$state"
mv "$stage$prefix" "$prefix"
jq -n --arg id "$name-$version" --arg sha "$sha" --arg files "$(inventory)" '{id: $id, sha256: $sha, files: $files}' > "$receipt.tmp"
chmod 600 "$receipt.tmp"; mv "$receipt.tmp" "$receipt"
echo "installed source build: $name $version"
