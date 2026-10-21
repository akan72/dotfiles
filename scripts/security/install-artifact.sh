#!/usr/bin/env bash
# Exact reviewed artifacts only. No URL/digest override or unverified fallback.
set -euo pipefail
umask 077
check_only=0
if [ "${1:-}" = --check ]; then check_only=1; shift; fi
[ "$#" -eq 3 ] || { echo "usage: $0 [--check] TOOL VERSION OS-arch" >&2; exit 2; }
# Assimilation supplies FD 3 for live status while detailed output stays in logs.
progress_fd="${DOTFILES_ARTIFACT_PROGRESS_FD:-1}"
[[ "$progress_fd" =~ ^[0-9]+$ ]] || { echo 'invalid artifact progress descriptor' >&2; exit 2; }
progress() { printf '  %s\n' "$*" >&"$progress_fd"; }
security_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
id="$1/$2/$3"
for required in jq python3; do command -v "$required" >/dev/null || { echo "missing required tool: $required" >&2; exit 1; }; done
record=$(jq -ce --arg id "$id" '.artifacts[$id] | select(type == "object")' "$security_dir/artifacts.json") || { echo "no reviewed artifact for $id" >&2; exit 1; }
url=$(printf '%s' "$record" | jq -er '.url')
digest=$(printf '%s' "$record" | jq -er '.sha256')
[[ "$digest" =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid reviewed digest' >&2; exit 1; }
# Exact record metadata and safe destination validation happen before network.
printf '%s' "$record" | python3 -I -S -c '
import json,sys,re,pathlib
r=json.load(sys.stdin); tool,version,platform=sys.argv[1:]
assert r["version"]==version
assert tool in ("delta","gcloud","nvim","rustup-init")
assert r["kind"] in ("file-tar","tree-tar","rustup-init")
assert (tool=="rustup-init")== (r["kind"]=="rustup-init")
assert not re.search(r"[\x00-\x20\x7f]",r["url"])
roots={"delta":"https://github.com/dandavison/delta/releases/download/", "gcloud":"https://storage.googleapis.com/cloud-sdk-release/", "nvim":"https://github.com/neovim/neovim/releases/download/", "rustup-init":"https://static.rust-lang.org/rustup/archive/"}
assert r["url"].startswith(roots[tool])
p=pathlib.PurePosixPath(r["destination"])
assert not p.is_absolute() and ".." not in p.parts and str(p).startswith(".local/")
' "$@"
if [ "$1" = rustup-init ]; then
  [ "${RUSTUP_UPDATE_ROOT:-https://static.rust-lang.org/rustup}" = https://static.rust-lang.org/rustup ] &&
  [ "${RUSTUP_DIST_SERVER:-https://static.rust-lang.org}" = https://static.rust-lang.org ] || { echo 'unreviewed Rust mirror override' >&2; exit 1; }
fi
# Shared read-only preflight: no temporary files, directories or network requests.
# Normal installs repeat this check immediately before download/install.
if python3 -I -S - "$record" "$id" <<'PY'
import hashlib,json,os,pathlib,stat,sys
r=json.loads(sys.argv[1]); ident=sys.argv[2]; home=pathlib.Path.home(); dest=home/r['destination']
state=home/'.local/state/dotfiles-security/artifacts'/ (ident.replace('/','_')+'.json')
def inventory(root):
 paths=[root] if not root.is_dir() or root.is_symlink() else sorted(root.rglob('*'))
 return {str(p.relative_to(root)) if p!=root else '.': ('link:'+os.readlink(p) if p.is_symlink() else 'dir' if p.is_dir() else hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths}
for path in (dest, state):
 for parent in (path, *path.parents):
  if parent == home.parent: break
  # The receipt and installation root must be real paths; tree-internal reviewed
  # symlinks remain part of the recorded inventory.
  if parent.is_symlink(): sys.exit('symlink in artifact destination or receipt: '+str(parent))
  if parent != path and parent.exists() and not parent.is_dir(): sys.exit('artifact parent is not a directory: '+str(parent))
lock=dest.parent/('.'+dest.name+'.install-lock')
if os.path.lexists(lock): sys.exit('another install or stale lock: '+str(lock)+'; inspect it before retrying')
if ident.startswith('nvim/'):
 link=home/'.local/bin/nvim'
 for parent in link.parents:
  if parent == home.parent: break
  if parent.is_symlink(): sys.exit('symlink in nvim launcher parent: '+str(parent))
 if not dest.exists() and os.path.lexists(link): sys.exit('nvim launcher already exists: '+str(link)+'; back it up and migrate explicitly')
if not dest.exists():
 print('ready to install reviewed artifact: '+ident)
 sys.exit(3)
if not state.is_file():
 sys.exit('unmanaged installation: '+str(dest)+'\n'
          '  No verified installation receipt. Existing files were left unchanged.\n'
          '  Next: review and back up/move this installation, then rerun assimilate.sh --check.\n'
          '  See the security playbook section 7b for exact migration commands.')
s=json.loads(state.read_text())
if s.get('id')!=ident or s.get('archive_sha256')!=r['sha256'] or s.get('files')!=inventory(dest): sys.exit('installed artifact changed: '+str(dest))
if ident.startswith('nvim/'):
 link=home/'.local/bin/nvim'
 if not link.is_symlink() or os.readlink(link)!=str(dest/'bin/nvim') or not link.is_file(): sys.exit('nvim launcher changed or missing')
print('verified installed artifact: '+ident)
PY
then
  if [ "$check_only" = 1 ]; then exit 0; fi
  progress "$id: already verified; skipping download."
  # A prior interrupted initializer may have left the verified artifact intact.
  if [ "$1" = rustup-init ] && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    destination=$(printf '%s' "$record" | jq -er '.destination')
    "$HOME/$destination" -y --no-modify-path --default-toolchain 1.95.0
  fi
  exit 0
else status=$?; [ "$status" -eq 3 ] || exit "$status"; fi
if [ "$check_only" = 1 ]; then exit 0; fi
command -v curl >/dev/null || { echo 'missing required tool: curl' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-artifact.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 -I -S - "$url" "$work/download" "$id" "$progress_fd" <<'DOWNLOAD'
import os, pathlib, signal, subprocess, sys, time
url, destination, ident = sys.argv[1:4]
with os.fdopen(os.dup(int(sys.argv[4])), 'w', buffering=1) as progress:
 def report(message): print('  '+message, file=progress, flush=True)
 report('Downloading '+ident+'...')
 started=time.monotonic()
 # Keep publisher errors in the detailed stage log; show bounded live heartbeats.
 with subprocess.Popen(['curl', '--fail', '--silent', '--show-error', '--location',
       '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2', url,
       '-o', destination]) as child:
  def stop(signum, frame):
   child.terminate()
   raise SystemExit(128+signum)
  signal.signal(signal.SIGINT, stop)
  signal.signal(signal.SIGTERM, stop)
  signal.signal(signal.SIGHUP, stop)
  while True:
   try:
    status=child.wait(timeout=10)
    break
   except subprocess.TimeoutExpired:
    report('Still downloading '+ident+' ('+str(int(time.monotonic()-started))+'s elapsed)...')
 if status:
  report('Download failed: '+ident+' (curl exit '+str(status)+'). See the stage log for details.')
  raise SystemExit(status if status > 0 else 128-status)
 report('Downloaded '+ident+' ('+format(pathlib.Path(destination).stat().st_size, ',')+' bytes); verifying SHA-256...')
DOWNLOAD
if command -v sha256sum >/dev/null 2>&1; then
  printf '%s  %s\n' "$digest" "$work/download" | sha256sum -c -
else
  printf '%s  %s\n' "$digest" "$work/download" | shasum -a 256 -c -
fi
progress "$id: SHA-256 verified; installing..."
python3 -I -S - "$record" "$id" "$work" <<'PY'
import hashlib,json,os,pathlib,shutil,stat,sys,tarfile,tempfile
r=json.loads(sys.argv[1]); ident=sys.argv[2]; work=pathlib.Path(sys.argv[3]); home=pathlib.Path.home(); dest=home/r['destination']
# Parents cannot redirect an install through a symlink.
for p in (dest,*dest.parents):
 if p==home.parent: break
 if p.is_symlink(): raise SystemExit('symlink in artifact destination: '+str(p))
dest.parent.mkdir(parents=True,exist_ok=True)
lock=dest.parent/('.'+dest.name+'.install-lock')
try: lock.mkdir()
except FileExistsError: raise SystemExit('another install or stale lock: '+str(lock))
adj=None
try:
 if dest.exists() or dest.is_symlink(): raise SystemExit('destination appeared during installation')
 if ident.startswith('nvim/'):
  launcher=home/'.local/bin/nvim'
  if launcher.exists() or launcher.is_symlink(): raise SystemExit('nvim launcher already exists; migrate explicitly')
 if r['kind']=='rustup-init': source=work/'download'
 else:
  stage=work/'extract';stage.mkdir(); root=r['archive_root']; seen=set(); links=[]
  with tarfile.open(work/'download','r:gz') as tf:
   for m in tf.getmembers():
    name=pathlib.PurePosixPath(m.name)
    if name.is_absolute() or '..' in name.parts or not name.parts or name.parts[0]!=root: raise SystemExit('unsafe archive path/layout')
    if str(name) in seen: raise SystemExit('duplicate archive entry')
    seen.add(str(name)); target=stage.joinpath(*name.parts)
    if m.isdir(): target.mkdir(parents=True,exist_ok=True)
    elif m.isfile():
     target.parent.mkdir(parents=True,exist_ok=True)
     with tf.extractfile(m) as src, target.open('xb') as out: shutil.copyfileobj(src,out)
     target.chmod(0o755 if m.mode & 0o111 else 0o644)
    elif m.issym():
     link=pathlib.PurePosixPath(m.linkname)
     resolved=pathlib.Path(os.path.normpath(str(target.parent/link)))
     if link.is_absolute() or not resolved.is_relative_to(stage/root): raise SystemExit('escaping archive symlink')
     links.append((target,m.linkname))
    else: raise SystemExit('archive hardlink/device/unsupported entry refused')
  for target,link in links:
   target.parent.mkdir(parents=True,exist_ok=True);target.symlink_to(link)
  source=stage/root/ 'delta' if r['kind']=='file-tar' else stage/root
  if source.is_symlink() or not source.exists(): raise SystemExit('expected archive payload absent')
  if r['kind']=='file-tar' and not source.is_file(): raise SystemExit('expected a regular artifact executable')
  if r['kind']=='tree-tar':
   executable=source/'bin'/ ('nvim' if ident.startswith('nvim/') else 'gcloud')
   if not executable.is_file() or executable.is_symlink() or not executable.stat().st_mode & 0o111: raise SystemExit('expected tree executable absent')
 adj=pathlib.Path(tempfile.mkdtemp(prefix='.'+dest.name+'.',dir=dest.parent)); payload=adj/'payload'
 if source.is_dir(): shutil.copytree(source,payload,symlinks=True)
 else: shutil.copy2(source,payload);payload.chmod(0o755)
 os.rename(payload,dest)
 state=home/'.local/state/dotfiles-security/artifacts';state.mkdir(parents=True,exist_ok=True,mode=0o700)
 paths=[dest] if not dest.is_dir() else sorted(dest.rglob('*'))
 files={str(p.relative_to(dest)) if p!=dest else '.': ('link:'+os.readlink(p) if p.is_symlink() else 'dir' if p.is_dir() else hashlib.sha256(p.read_bytes()).hexdigest()) for p in paths}
 data={'id':ident,'archive_sha256':r['sha256'],'files':files}
 tmp=state/(ident.replace('/','_')+'.tmp');tmp.write_text(json.dumps(data,sort_keys=True)+'\n');tmp.chmod(0o600);tmp.replace(state/(ident.replace('/','_')+'.json'))
 if ident.startswith('nvim/'):
  link=home/'.local/bin/nvim';link.parent.mkdir(parents=True,exist_ok=True)
  if link.exists() or link.is_symlink(): raise SystemExit('nvim launcher already exists; migrate explicitly')
  link.symlink_to(dest/'bin/nvim')
finally:
 if adj: shutil.rmtree(adj)
 lock.rmdir()
PY
if [ "$1" = rustup-init ]; then
  destination=$(printf '%s' "$record" | jq -er '.destination')
  "$HOME/$destination" -y --no-modify-path --default-toolchain 1.95.0
fi
progress "$id: installed and receipt saved."
