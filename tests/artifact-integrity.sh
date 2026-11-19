#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/artifact-integrity.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/helper" "$work/bin"
cp "$root/scripts/security/install-artifact.sh" "$root/scripts/security/install-artifact.py" "$work/helper/"
cat > "$work/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${FIXTURE_CURL_CALLS:-}" ]; then printf 'curl called\n' >> "$FIXTURE_CURL_CALLS"; fi
if [ "${FIXTURE_CURL_DELAY:-0}" != 0 ]; then sleep "$FIXTURE_CURL_DELAY"; fi
[[ " $* " = *" --proto =https "* ]] && [[ " $* " = *" --proto-redir =https "* ]] || exit 9
[ "${FIXTURE_CURL_FAIL:-0}" = 0 ] || exit 22
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then cp "$FIXTURE_ARCHIVE" "$2"; exit; fi
  shift
done
exit 9
STUB
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH" FIXTURE_ARCHIVE="$work/archive.tar.gz" FIXTURE_MARKER="$work/executed"
python3 - "$work" <<'PY'
import io,tarfile,pathlib,sys
w=pathlib.Path(sys.argv[1])
for kind in ('normal','traversal','link','chain','device','wrong-layout'):
 with tarfile.open(w/(kind+'.tar.gz'),'w:gz') as tf:
  name={'traversal':'../escape','wrong-layout':'unexpected/delta'}.get(kind,'fixture/delta')
  m=tarfile.TarInfo(name)
  if kind=='link':m.type=tarfile.SYMTYPE;m.linkname='../../escape';tf.addfile(m)
  elif kind=='device':m.type=tarfile.CHRTYPE;tf.addfile(m)
  else:
   content=b'#!/bin/sh\ntouch "$FIXTURE_MARKER"\n';m.size=len(content);m.mode=0o755;tf.addfile(m,io.BytesIO(content))
  if kind=='chain':
   for path,target in [('fixture/a','.'),('fixture/b','a/../outside')]:
    m=tarfile.TarInfo(path);m.type=tarfile.SYMTYPE;m.linkname=target;tf.addfile(m)
PY
manifest() {
  python3 - "$work" "${1:-normal}" "${2:-https}" <<'PY'
import json,hashlib,pathlib,sys
w=pathlib.Path(sys.argv[1]);kind=sys.argv[2];scheme=sys.argv[3]
archive=w/(kind+'.tar.gz');(w/'archive.tar.gz').write_bytes(archive.read_bytes())
r={'version':'1','url':scheme+'://github.com/dandavison/delta/releases/download/1/fixture.tar.gz','sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'kind':'file-tar','destination':'.local/bin/delta','archive_root':'fixture'}
(w/'helper/artifacts.json').write_text(json.dumps({'artifacts':{'delta/1/Fixture':r}}))
PY
}
run() { HOME="$work/home-$case_name" bash "$work/helper/install-artifact.sh" delta 1 Fixture; }
reject() { if run >/dev/null 2>&1; then echo "unsafe fixture accepted: $case_name" >&2; exit 1; fi; test ! -e "$FIXTURE_MARKER"; }
manifest normal
export FIXTURE_CURL_CALLS="$work/curl-calls"
# Missing destinations pass offline without creating a HOME or temporary directory.
HOME="$work/home-absent" TMPDIR="$work/does-not-exist" FIXTURE_CURL_FAIL=1   bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >"$work/check-missing.log"
grep -Fq 'ready to install reviewed artifact' "$work/check-missing.log"
test ! -e "$work/home-absent"
# User Python startup hooks must not execute during the read-only checks.
mkdir "$work/python-hooks"
printf 'import pathlib; pathlib.Path(%s).touch()\n' "'${FIXTURE_MARKER}'" > "$work/python-hooks/sitecustomize.py"
HOME="$work/home-absent" PYTHONPATH="$work/python-hooks" FIXTURE_CURL_FAIL=1 \
  bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >/dev/null
test ! -e "$FIXTURE_MARKER"
test ! -e "$FIXTURE_CURL_CALLS"
# Existing unreceipted file and tree installs remain untouched and never download.
mkdir -p "$work/home-unmanaged/.local/bin" "$work/home-unmanaged/.local/share/google-cloud-sdk"
printf 'existing delta\n' > "$work/home-unmanaged/.local/bin/delta"
for mode in check install; do
  set --; if [ "$mode" = check ]; then set -- --check; fi
  if HOME="$work/home-unmanaged" bash "$work/helper/install-artifact.sh" "$@" delta 1 Fixture >"$work/unmanaged.log" 2>&1; then exit 1; fi
  grep -Fq 'unmanaged installation:' "$work/unmanaged.log"
  grep -Fq 'Next: review and back up/move' "$work/unmanaged.log"
  test "$(cat "$work/home-unmanaged/.local/bin/delta")" = 'existing delta'
  test ! -e "$FIXTURE_CURL_CALLS"
done
python3 - "$work/helper/artifacts.json" <<'PYGCLOUD'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());r=dict(d['artifacts']['delta/1/Fixture'])
r.update(url='https://storage.googleapis.com/cloud-sdk-release/fixture.tar.gz',kind='tree-tar',destination='.local/share/google-cloud-sdk')
d['artifacts']['gcloud/1/Fixture']=r;p.write_text(json.dumps(d))
PYGCLOUD
if HOME="$work/home-unmanaged" bash "$work/helper/install-artifact.sh" --check gcloud 1 Fixture >"$work/gcloud.log" 2>&1; then exit 1; fi
grep -Fq 'unmanaged installation:' "$work/gcloud.log"
test ! -e "$FIXTURE_CURL_CALLS"
# Parent redirection and stale install locks are rejected during read-only preflight.
mkdir -p "$work/home-symlink" "$work/redirect"
ln -s "$work/redirect" "$work/home-symlink/.local"
if HOME="$work/home-symlink" bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >/dev/null 2>&1; then exit 1; fi
mkdir -p "$work/home-lock/.local/bin/.delta.install-lock"
if HOME="$work/home-lock" bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >/dev/null 2>&1; then exit 1; fi
test ! -e "$FIXTURE_CURL_CALLS"
case_name=valid; run >/dev/null
test -x "$work/home-valid/.local/bin/delta"
# Verified installed content works offline; installed byte tampering is rejected.
FIXTURE_CURL_FAIL=1 run >/dev/null
HOME="$work/home-valid" FIXTURE_CURL_FAIL=1 bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >/dev/null
# A modified receipt also fails without contacting a publisher.
receipt="$work/home-valid/.local/state/dotfiles-security/artifacts/delta_1_Fixture.json"
cp "$receipt" "$work/receipt.before"
python3 - "$receipt" <<'RECEIPT'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);data=json.loads(p.read_text());data['archive_sha256']='0'*64;p.write_text(json.dumps(data))
RECEIPT
if HOME="$work/home-valid" FIXTURE_CURL_FAIL=1 bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >/dev/null 2>&1; then exit 1; fi
cp "$work/receipt.before" "$receipt"
printf 'changed\n' >> "$work/home-valid/.local/bin/delta"; reject
if HOME="$work/home-valid" bash "$work/helper/install-artifact.sh" --check delta 1 Fixture >/dev/null 2>&1; then exit 1; fi
# Live status goes to the caller's descriptor even when detailed stdout is captured.
case_name=progress
FIXTURE_CURL_DELAY=11 DOTFILES_ARTIFACT_PROGRESS_FD=3 run 3>"$work/progress.log" >"$work/detail.log"
grep -Eq 'Still downloading delta/1/Fixture \([1-9][0-9]*s elapsed\)\.\.\.' "$work/progress.log"
grep -Fq 'installed and receipt saved.' "$work/progress.log"
if grep -Fq 'Still downloading' "$work/detail.log"; then exit 1; fi
case_name=network-failure
set +e
FIXTURE_CURL_FAIL=1 run >"$work/network-failure.log" 2>&1
network_status=$?
set -e
test "$network_status" = 22
grep -Fq 'Download failed: delta/1/Fixture (curl exit 22)' "$work/network-failure.log"
test ! -e "$work/home-network-failure/.local/bin/delta"
for kind in traversal link chain device wrong-layout; do manifest "$kind"; case_name=$kind; reject; done
manifest normal
case_name=changed-byte; printf 'changed' >> "$FIXTURE_ARCHIVE"; reject
manifest normal http; case_name=plaintext; reject
manifest normal
case_name=missing-digest
python3 - "$work/helper/artifacts.json" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);d=json.loads(p.read_text());d['artifacts']['delta/1/Fixture']['sha256']='';p.write_text(json.dumps(d))
PY
reject
if HOME="$work/home-platform" bash "$work/helper/install-artifact.sh" delta 1 Wrong >/dev/null 2>&1; then exit 1; fi
# Tree installs refuse missing executables and pre-existing launchers, and verify
# the launcher again during offline idempotency checks.
manifest normal
python3 - "$work" <<'PYTREE'
import json,pathlib,sys
w=pathlib.Path(sys.argv[1]);p=w/'helper/artifacts.json';d=json.loads(p.read_text());r=d['artifacts'].pop('delta/1/Fixture');r.update(url='https://github.com/neovim/neovim/releases/download/v1/fixture.tar.gz',kind='tree-tar',destination='.local/share/nvim-fixture');d['artifacts']['nvim/1/Fixture']=r;p.write_text(json.dumps(d))
PYTREE
if HOME="$work/home-missing-bin" bash "$work/helper/install-artifact.sh" nvim 1 Fixture >/dev/null 2>&1; then exit 1; fi
python3 - "$work" <<'PYTREE'
import hashlib,io,json,pathlib,sys,tarfile
w=pathlib.Path(sys.argv[1])
with tarfile.open(w/'archive.tar.gz','w:gz') as tf:
 m=tarfile.TarInfo('fixture/bin/nvim');data=b'#!/bin/sh\ntouch "$FIXTURE_MARKER"\n';m.size=len(data);m.mode=0o755;tf.addfile(m,io.BytesIO(data))
p=w/'helper/artifacts.json';d=json.loads(p.read_text());d['artifacts']['nvim/1/Fixture']['sha256']=hashlib.sha256((w/'archive.tar.gz').read_bytes()).hexdigest();p.write_text(json.dumps(d))
PYTREE
mkdir -p "$work/home-conflict/.local/bin"
printf 'existing launcher\n' > "$work/home-conflict/.local/bin/nvim"
if HOME="$work/home-conflict" bash "$work/helper/install-artifact.sh" nvim 1 Fixture >/dev/null 2>&1; then exit 1; fi
test ! -e "$work/home-conflict/.local/share/nvim-fixture"
if HOME="$work/home-conflict" bash "$work/helper/install-artifact.sh" --check nvim 1 Fixture >/dev/null 2>&1; then exit 1; fi
HOME="$work/home-tree" bash "$work/helper/install-artifact.sh" nvim 1 Fixture >/dev/null
HOME="$work/home-tree" FIXTURE_CURL_FAIL=1 bash "$work/helper/install-artifact.sh" nvim 1 Fixture >/dev/null
rm "$work/home-tree/.local/bin/nvim"
if HOME="$work/home-tree" bash "$work/helper/install-artifact.sh" --check nvim 1 Fixture >/dev/null 2>&1; then exit 1; fi
if HOME="$work/home-tree" bash "$work/helper/install-artifact.sh" nvim 1 Fixture >/dev/null 2>&1; then exit 1; fi
# Language servers: a tree with no top-level directory (Lua LS) and a single
# gzipped executable (rust-analyzer). Both keep the digest, layout and offline
# integrity gates.
server() {
  python3 - "$work" "$@" <<'PYSERVER'
import gzip,hashlib,io,json,pathlib,sys,tarfile
w=pathlib.Path(sys.argv[1]);kind=sys.argv[2];case=sys.argv[3]
script=b'#!/bin/sh\ntouch "$FIXTURE_MARKER"\n'
archive=w/'archive.tar.gz'
if kind=='file-gz':
 archive.write_bytes(gzip.compress(script) if case!='corrupt' else b'not gzip')
 r={'url':'https://github.com/rust-lang/rust-analyzer/releases/download/1/fixture.gz','destination':'.local/share/dotfiles-lsp/rust-analyzer'}
else:
 with tarfile.open(archive,'w:gz') as tf:
  names={'normal':['bin/lua-language-server','main.lua'],'no-executable':['main.lua'],'traversal':['../escape']}.get(case,['bin/lua-language-server'])
  for name in names:
   m=tarfile.TarInfo(name);m.size=len(script);m.mode=0o755;tf.addfile(m,io.BytesIO(script))
  if case=='link':
   m=tarfile.TarInfo('meta');m.type=tarfile.SYMTYPE;m.linkname='../escape';tf.addfile(m)
 r={'url':'https://github.com/LuaLS/lua-language-server/releases/download/1/fixture.tar.gz','destination':'.local/share/dotfiles-lsp/lua-language-server','archive_root':'nested/root' if case=='bad-root' else ''}
tool={'file-gz':'rust-analyzer'}.get(kind,'lua-language-server')
r.update(version='1',kind=kind if case!='wrong-kind' else 'file-tar',sha256=hashlib.sha256(archive.read_bytes()).hexdigest())
(w/'helper/artifacts.json').write_text(json.dumps({'artifacts':{tool+'/1/Fixture':r}}))
PYSERVER
}
server tree-tar normal
HOME="$work/home-lua" bash "$work/helper/install-artifact.sh" lua-language-server 1 Fixture >/dev/null
test -x "$work/home-lua/.local/share/dotfiles-lsp/lua-language-server/bin/lua-language-server"
HOME="$work/home-lua" FIXTURE_CURL_FAIL=1 bash "$work/helper/install-artifact.sh" --check lua-language-server 1 Fixture >/dev/null
# A server writing into its own tree (Lua LS's default log/meta paths) is detected.
mkdir "$work/home-lua/.local/share/dotfiles-lsp/lua-language-server/log"
if HOME="$work/home-lua" bash "$work/helper/install-artifact.sh" --check lua-language-server 1 Fixture >/dev/null 2>&1; then exit 1; fi
for case in no-executable traversal link bad-root; do
  server tree-tar "$case"
  if HOME="$work/home-lua-$case" bash "$work/helper/install-artifact.sh" lua-language-server 1 Fixture >/dev/null 2>&1; then
    echo "unsafe server fixture accepted: $case" >&2; exit 1
  fi
  test ! -e "$work/home-lua-$case/.local/share/dotfiles-lsp/lua-language-server"
done
server file-gz normal
HOME="$work/home-ra" bash "$work/helper/install-artifact.sh" rust-analyzer 1 Fixture >/dev/null
test -x "$work/home-ra/.local/share/dotfiles-lsp/rust-analyzer"
HOME="$work/home-ra" FIXTURE_CURL_FAIL=1 bash "$work/helper/install-artifact.sh" --check rust-analyzer 1 Fixture >/dev/null
printf 'changed\n' >> "$work/home-ra/.local/share/dotfiles-lsp/rust-analyzer"
if HOME="$work/home-ra" bash "$work/helper/install-artifact.sh" --check rust-analyzer 1 Fixture >/dev/null 2>&1; then exit 1; fi
for case in corrupt wrong-kind; do
  server file-gz "$case"
  if HOME="$work/home-ra-$case" bash "$work/helper/install-artifact.sh" rust-analyzer 1 Fixture >/dev/null 2>&1; then
    echo "unsafe server fixture accepted: $case" >&2; exit 1
  fi
  test ! -e "$work/home-ra-$case/.local/share/dotfiles-lsp/rust-analyzer"
done
server file-gz normal; printf 'changed' >> "$FIXTURE_ARCHIVE"
if HOME="$work/home-ra-digest" bash "$work/helper/install-artifact.sh" rust-analyzer 1 Fixture >/dev/null 2>&1; then exit 1; fi
test ! -e "$FIXTURE_MARKER"
# Zip archives, bare executables, data files/trees and per-platform member names
# keep the same digest, layout, safe-extraction and offline integrity gates.
kinds() {
  python3 - "$work" "$@" <<'PYKINDS'
import hashlib,io,json,pathlib,sys,tarfile,zipfile
w=pathlib.Path(sys.argv[1]);tool=sys.argv[2];case=sys.argv[3]
script=b'#!/bin/sh\ntouch "$FIXTURE_MARKER"\n'
archive=w/'archive.tar.gz'
def zipped(entries,links=()):
 buf=io.BytesIO()
 with zipfile.ZipFile(buf,'w') as z:
  for name,data,mode in entries:
   info=zipfile.ZipInfo(name);info.external_attr=(0o100000|mode)<<16;z.writestr(info,data)
  for name,target in links:
   info=zipfile.ZipInfo(name);info.external_attr=(0o120000|0o777)<<16;z.writestr(info,target)
 return buf.getvalue()
if tool=='terraform':
 names={'traversal':'../escape','absolute':'/escape','wrong-layout':'other'}.get(case,'terraform')
 archive.write_bytes(zipped([(names,script,0o755)],[('meta','../../escape')] if case=='link' else []))
 r={'url':'https://releases.hashicorp.com/terraform/1/fixture.zip','kind':'file-zip','destination':'.local/bin/terraform','archive_root':''}
elif tool=='hack-nerd-font':
 archive.write_bytes(zipped([('HackNerdFontMono-Regular.ttf',b'font',0o644),('README.md',b'readme',0o644)]))
 r={'url':'https://github.com/ryanoasis/nerd-fonts/releases/download/1/Hack.zip','kind':'tree-zip','destination':'.local/share/fonts/hack-nerd-font','archive_root':''}
elif tool in ('jq','ca-bundle'):
 archive.write_bytes(script if tool=='jq' else b'-----BEGIN CERTIFICATE-----\n')
 r={'url':{'jq':'https://github.com/jqlang/jq/releases/download/1/jq','ca-bundle':'https://curl.se/ca/cacert.pem'}[tool],'kind':'file',
    'destination':{'jq':'.local/bin/jq','ca-bundle':'.local/share/dotfiles-ca/cacert.pem'}[tool]}
else:
 with tarfile.open(archive,'w:gz') as tf:
  m=tarfile.TarInfo('./yq_fixture');m.size=len(script);m.mode=0o755;tf.addfile(m,io.BytesIO(script))
 r={'url':'https://github.com/mikefarah/yq/releases/download/1/yq.tar.gz','kind':'file-tar','destination':'.local/bin/yq','archive_root':''}
 if case!='no-member':r['member']={'bad-member':'../yq_fixture'}.get(case,'yq_fixture')
r.update(version='1',sha256=hashlib.sha256(archive.read_bytes()).hexdigest())
(w/'helper/artifacts.json').write_text(json.dumps({'artifacts':{tool+'/1/Fixture':r}}))
PYKINDS
}
install_kind() { HOME="$work/home-kind-$1-$2" bash "$work/helper/install-artifact.sh" "$1" 1 Fixture >/dev/null 2>&1; }
check_kind() { HOME="$work/home-kind-$1-$2" FIXTURE_CURL_FAIL=1 bash "$work/helper/install-artifact.sh" --check "$1" 1 Fixture >/dev/null 2>&1; }
kinds terraform normal; install_kind terraform normal
test -x "$work/home-kind-terraform-normal/.local/bin/terraform"; check_kind terraform normal
printf 'changed\n' >> "$work/home-kind-terraform-normal/.local/bin/terraform"
if check_kind terraform normal; then echo 'tampered zip install accepted' >&2; exit 1; fi
for case in traversal absolute link wrong-layout; do
  kinds terraform "$case"
  if install_kind terraform "$case"; then echo "unsafe zip fixture accepted: $case" >&2; exit 1; fi
  test ! -e "$work/home-kind-terraform-$case/.local/bin/terraform"
done
kinds hack-nerd-font normal; install_kind hack-nerd-font normal
font="$work/home-kind-hack-nerd-font-normal/.local/share/fonts/hack-nerd-font/HackNerdFontMono-Regular.ttf"
test -f "$font" && test ! -x "$font"; check_kind hack-nerd-font normal
printf 'changed' >> "$font"
if check_kind hack-nerd-font normal; then echo 'tampered data tree accepted' >&2; exit 1; fi
kinds jq normal; install_kind jq normal
test -x "$work/home-kind-jq-normal/.local/bin/jq"; check_kind jq normal
kinds jq normal; printf 'changed' >> "$FIXTURE_ARCHIVE"
if install_kind jq digest; then echo 'bare executable with wrong digest accepted' >&2; exit 1; fi
kinds ca-bundle normal; install_kind ca-bundle normal
ca="$work/home-kind-ca-bundle-normal/.local/share/dotfiles-ca/cacert.pem"
test -f "$ca" && test ! -x "$ca"; check_kind ca-bundle normal
kinds yq normal; install_kind yq normal
test -x "$work/home-kind-yq-normal/.local/bin/yq"; check_kind yq normal
for case in no-member bad-member; do
  kinds yq "$case"
  if install_kind yq "$case"; then echo "invalid member metadata accepted: $case" >&2; exit 1; fi
done
test ! -e "$FIXTURE_MARKER"
echo 'artifact tests passed: read-only preflight, unmanaged file/tree, no writes/network, live download heartbeat, exact curl status, digest gate, offline integrity, malformed/missing/platform/HTTP/download/traversal/link/device/layout failures, rootless Lua LS tree, gzipped rust-analyzer, zip archives, bare executables, data files and trees, member names'
