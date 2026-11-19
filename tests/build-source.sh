#!/usr/bin/env bash
# build-source.sh: digest gate, safe extraction, receipts, offline --check and
# refusal of unmanaged or changed installations. A stub curl serves a tiny
# autotools-shaped fixture, so nothing is downloaded or compiled.
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/build-source.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/helper" "$work/bin" "$work/home"
cp "$root/scripts/security/build-source.sh" "$work/helper/"
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[[ " $* " = *" --proto =https "* ]] || exit 9
while [ "$#" -gt 0 ]; do if [ "$1" = -o ]; then cp "$FIXTURE_ARCHIVE" "$2"; exit; fi; shift; done
exit 9
STUB
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH" FIXTURE_ARCHIVE="$work/source.tar.gz"
fixture() {
  python3 - "$work" "$1" <<'PY'
import hashlib,io,json,pathlib,sys,tarfile
w=pathlib.Path(sys.argv[1]);case=sys.argv[2]
configure=(b"#!/bin/sh\nprefix=${1#--prefix=}\ncat > Makefile <<'EOF'\nall:\n\ttrue\ninstall:\n\tmkdir -p $(DESTDIR)PREFIX/lib\n"
           b"\tprintf lib > $(DESTDIR)PREFIX/lib/libevent.a\nEOF\nsed -i.bak \"s|PREFIX|$prefix|g\" Makefile\n")
with tarfile.open(w/'source.tar.gz','w:gz') as tf:
    for name,data,mode in [('fixture-1/configure',configure,0o755)]+([('../escape',b'x',0o644)] if case=='traversal' else []):
        m=tarfile.TarInfo(name);m.size=len(data);m.mode=mode;tf.addfile(m,io.BytesIO(data))
    if case=='link':
        m=tarfile.TarInfo('fixture-1/out');m.type=tarfile.SYMTYPE;m.linkname='../../escape';tf.addfile(m)
digest=hashlib.sha256((w/'source.tar.gz').read_bytes()).hexdigest()
if case=='digest':digest='0'*64
(w/'helper/sources.json').write_text(json.dumps({'sources':{'libevent':{'version':'1','url':'https://example.invalid/fixture.tar.gz','sha256':digest,'root':'fixture-1'}}}))
PY
}
build() { HOME="$work/home" bash "$work/helper/build-source.sh" "$@"; }
prefix="$work/home/.local/share/dotfiles-src/libevent-1"
fixture normal
build --check libevent | grep -Fq 'ready to build reviewed source'
test ! -e "$prefix"
build libevent >/dev/null
test "$(cat "$prefix/lib/libevent.a")" = lib
build --check libevent | grep -Fq 'verified source build'
build libevent | grep -Fq 'verified source build'
# Any change to the installed files, or to the receipt, is refused, and never rebuilt over.
printf changed >> "$prefix/lib/libevent.a"
if build --check libevent >/dev/null 2>&1; then echo 'changed source build accepted' >&2; exit 1; fi
if build libevent >/dev/null 2>&1; then echo 'rebuilt over a changed installation' >&2; exit 1; fi
test "$(cat "$prefix/lib/libevent.a")" = libchanged
# An installation without a receipt is unmanaged and left untouched.
rm "$work/home/.local/state/dotfiles-security/sources/libevent-1.json"
if build --check libevent >/dev/null 2>&1; then echo 'unmanaged source build accepted' >&2; exit 1; fi
rm -rf "$prefix"
for case in digest traversal link; do
  fixture "$case"
  if build libevent >/dev/null 2>&1; then echo "unsafe source fixture accepted: $case" >&2; exit 1; fi
  test ! -e "$prefix"
done
test ! -e "$work/escape" && test ! -e "$work/helper/escape"
echo 'build-source: digest gate, safe extraction, receipts, offline check, changed and unmanaged installs refused'
