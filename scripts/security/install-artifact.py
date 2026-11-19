#!/usr/bin/env python3
"""Install exact reviewed artifacts; --check is read-only and offline."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import subprocess
import sys
import tarfile
import zipfile
import tempfile
import time

ORIGINS = {
    'delta': 'https://github.com/dandavison/delta/releases/download/',
    'ca-bundle': 'https://curl.se/ca/',
    'duckdb': 'https://github.com/duckdb/duckdb/releases/download/',
    'gcloud': 'https://storage.googleapis.com/cloud-sdk-release/',
    'gh': 'https://github.com/cli/cli/releases/download/',
    'hack-nerd-font': 'https://github.com/ryanoasis/nerd-fonts/releases/download/',
    'jq': 'https://github.com/jqlang/jq/releases/download/',
    'lsd': 'https://github.com/lsd-rs/lsd/releases/download/',
    'lua-language-server': 'https://github.com/LuaLS/lua-language-server/releases/download/',
    'node': 'https://nodejs.org/dist/',
    'nvim': 'https://github.com/neovim/neovim/releases/download/',
    'rust-analyzer': 'https://github.com/rust-lang/rust-analyzer/releases/download/',
    'terraform': 'https://releases.hashicorp.com/terraform/',
    'yq': 'https://github.com/mikefarah/yq/releases/download/',
    'rustup-init': 'https://static.rust-lang.org/rustup/archive/',
}
# Each tar archive's executable, relative to its archive root: a file-tar
# installs only that file; a tree-tar installs the whole tree and requires it.
# A file-gz is one gzipped executable.
EXECUTABLES = {
    'delta': 'delta',
    'duckdb': 'duckdb',
    'gcloud': 'bin/gcloud',
    'gh': 'bin/gh',
    'hack-nerd-font': 'HackNerdFontMono-Regular.ttf',
    'lsd': 'lsd',
    'lua-language-server': 'bin/lua-language-server',
    'node': 'bin/node',
    'nvim': 'bin/nvim',
    'terraform': 'terraform',
    # None: the archive names the executable per platform; the record's 'member' gives it.
    'yq': None,
}


# file: one bare executable. file-gz: one gzipped executable. file-tar/file-zip:
# one executable from an archive. tree-tar/tree-zip: the whole archive tree.
KINDS = ('file', 'file-gz', 'file-tar', 'file-zip', 'tree-tar', 'tree-zip', 'rustup-init')
ARCHIVES = ('file-tar', 'file-zip', 'tree-tar', 'tree-zip')
# Data, not programs: a tree's named file need not be executable, and a single
# data file is installed read-only (0644) instead of executable.
DATA_TREES = ('hack-nerd-font', 'ca-bundle')


def entries(archive, kind):
    """Yield (name, type, mode, opener) for each archive entry; type is dir/file/link."""
    if kind.endswith('-zip'):
        with zipfile.ZipFile(archive) as source:
            for info in source.infolist():
                mode = info.external_attr >> 16
                if (mode & 0o170000) == 0o120000:
                    yield info.filename, 'link', mode, lambda info=info: source.read(info).decode()
                elif info.is_dir():
                    yield info.filename, 'dir', mode, None
                else:
                    yield info.filename, 'file', mode, lambda info=info: source.open(info)
        return
    with tarfile.open(archive, 'r:gz') as source:
        for member in source.getmembers():
            kind_of = 'dir' if member.isdir() else 'file' if member.isfile() else 'link' if member.issym() else 'other'
            opener = (lambda member=member: source.extractfile(member)) if kind_of == 'file' else (lambda member=member: member.linkname)
            yield member.name, kind_of, member.mode, opener


def file_hash(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def inventory(root):
    paths = sorted(root.rglob('*')) if root.is_dir() else [root]
    return {str(p.relative_to(root)) if p != root else '.':
            'link:' + os.readlink(p) if p.is_symlink() else 'dir' if p.is_dir() else file_hash(p)
            for p in paths}


def check_parents(path, home, allow_leaf_link=False):
    for parent in (path, *path.parents):
        if parent == home.parent:
            break
        if parent.is_symlink() and not (allow_leaf_link and parent == path):
            raise ValueError('symlink in artifact destination or receipt: ' + str(parent))
        if parent != path and parent.exists() and not parent.is_dir():
            raise ValueError('artifact parent is not a directory: ' + str(parent))


def reviewed_record(tool, version, platform):
    ident = '/'.join((tool, version, platform))
    records = json.loads(Path(__file__).with_name('artifacts.json').read_text())['artifacts']
    if ident not in records:
        raise ValueError('no reviewed artifact for ' + ident)
    record = records[ident]
    destination = PurePosixPath(record['destination'])
    if (record['version'] != version or tool not in ORIGINS
            or record['kind'] not in KINDS
            or (tool == 'rustup-init') != (record['kind'] == 'rustup-init')
            or (record['kind'] in ('file', 'file-gz')) == (tool in EXECUTABLES or tool == 'rustup-init')
            or not re.fullmatch('[0-9a-f]{64}', record['sha256'])
            or re.search(r'[\x00-\x20\x7f]', record['url'])
            or not record['url'].startswith(ORIGINS[tool])
            or destination.is_absolute() or '..' in destination.parts
            or not str(destination).startswith('.local/')
            # One plain directory name, or '' for archives with no top-level directory
            or (record['kind'] in ARCHIVES
                and not re.fullmatch(r'([A-Za-z0-9_+-][A-Za-z0-9._+-]*)?', record['archive_root']))
            or ((EXECUTABLES.get(tool, '') is None) != ('member' in record))
            or ('member' in record and not re.fullmatch(r'[A-Za-z0-9_+-][A-Za-z0-9._+-]*', record['member']))):
        raise ValueError('invalid reviewed artifact metadata')
    if tool == 'rustup-init' and (
            os.environ.get('RUSTUP_UPDATE_ROOT', 'https://static.rust-lang.org/rustup') != 'https://static.rust-lang.org/rustup'
            or os.environ.get('RUSTUP_DIST_SERVER', 'https://static.rust-lang.org') != 'https://static.rust-lang.org'):
        raise ValueError('unreviewed Rust mirror override')
    return ident, record


def preflight(home, ident, record):
    destination = home / record['destination']
    receipt = home / '.local/state/dotfiles-security/artifacts' / (ident.replace('/', '_') + '.json')
    for path in (destination, receipt):
        check_parents(path, home)
    lock = destination.parent / ('.' + destination.name + '.install-lock')
    if os.path.lexists(lock):
        raise ValueError('another install or stale lock: ' + str(lock) + '; inspect it before retrying')
    launcher = home / '.local/bin/nvim'
    if ident.startswith('nvim/'):
        check_parents(launcher, home, allow_leaf_link=True)
        if not destination.exists() and os.path.lexists(launcher):
            raise ValueError('nvim launcher already exists; back it up and migrate explicitly')
    if not destination.exists():
        return False
    if not receipt.is_file():
        raise ValueError('unmanaged installation: ' + str(destination) + '\n'
                         '  No verified installation receipt. Existing files were left unchanged.\n'
                         '  Next: review and back up/move this installation, then rerun assimilate.sh --check.\n'
                         '  See the security playbook section 7b for exact migration commands.')
    state = json.loads(receipt.read_text())
    if (state.get('id') != ident or state.get('archive_sha256') != record['sha256']
            or state.get('files') != inventory(destination)):
        raise ValueError('installed artifact changed: ' + str(destination))
    if ident.startswith('nvim/') and (not launcher.is_symlink()
            or os.readlink(launcher) != str(destination / 'bin/nvim') or not launcher.is_file()):
        raise ValueError('nvim launcher changed or missing')
    return True


def download(url, destination, ident, progress):
    progress('Downloading ' + ident + '...')
    started = time.monotonic()
    with subprocess.Popen(['curl', '--fail', '--silent', '--show-error', '--location',
                           '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2',
                           url, '-o', str(destination)]) as child:
        def stop(signum, frame):
            child.terminate()
            raise SystemExit(128 + signum)
        previous = {sig: signal.signal(sig, stop) for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)}
        try:
            while True:
                try:
                    status = child.wait(timeout=10)
                    break
                except subprocess.TimeoutExpired:
                    progress('Still downloading ' + ident + ' (' + str(int(time.monotonic() - started)) + 's elapsed)...')
        finally:
            for sig, handler in previous.items():
                signal.signal(sig, handler)
    if status:
        progress('Download failed: ' + ident + ' (curl exit ' + str(status) + '). See the stage log for details.')
        raise SystemExit(status if status > 0 else 128 - status)
    progress('Downloaded ' + ident + ' (' + format(destination.stat().st_size, ',') + ' bytes); verifying SHA-256...')


def extract(archive, stage, record, ident):
    root, seen, links = record['archive_root'], set(), []
    prefix = (root,) if root else ()
    base = stage / root if root else stage
    for raw, kind_of, mode, opener in entries(archive, record['kind']):
        name = PurePosixPath(raw)
        if (name.is_absolute() or '..' in name.parts or not name.parts
                or name.parts[:len(prefix)] != prefix):
            raise ValueError('unsafe archive path/layout')
        if str(name) in seen:
            raise ValueError('duplicate archive entry')
        seen.add(str(name))
        target = stage.joinpath(*name.parts)
        if kind_of == 'dir':
            target.mkdir(parents=True, exist_ok=True)
        elif kind_of == 'file':
            target.parent.mkdir(parents=True, exist_ok=True)
            with opener() as stream, target.open('xb') as output:
                shutil.copyfileobj(stream, output)
            target.chmod(0o755 if mode & 0o111 else 0o644)
        elif kind_of == 'link':
            linkname = opener()
            link = PurePosixPath(linkname)
            if link.is_absolute() or not Path(os.path.normpath(str(target.parent / link))).is_relative_to(base):
                raise ValueError('escaping archive symlink')
            links.append((target, linkname))
        else:
            raise ValueError('archive hardlink/device/unsupported entry refused')
    for target, link in links:
        if not target.parent.resolve().is_relative_to(base):
            raise ValueError('escaping archive symlink parent')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(link)
    if any(not target.resolve().is_relative_to(base) for target, _ in links):
        raise ValueError('escaping archive symlink chain')
    executable = record.get('member') or EXECUTABLES[ident.split('/')[0]]
    single = record['kind'].startswith('file-')
    payload = base / executable if single else base
    if payload.is_symlink() or not payload.exists():
        raise ValueError('expected archive payload absent')
    if single and not payload.is_file():
        raise ValueError('expected a regular artifact executable')
    if not single:
        executable = payload / executable
        data = ident.split('/')[0] in DATA_TREES
        if not executable.is_file() or executable.is_symlink() or not (data or executable.stat().st_mode & 0o111):
            raise ValueError('expected tree executable absent')
    return payload


def decompress(archive, stage):
    # The digest was verified first, so this is the reviewed executable.
    stage.mkdir()
    payload = stage / 'executable'
    with gzip.open(archive, 'rb') as source, payload.open('xb') as output:
        shutil.copyfileobj(source, output)
    return payload


def publish(home, ident, record, work):
    destination = home / record['destination']
    check_parents(destination, home)
    destination.parent.mkdir(parents=True, exist_ok=True)
    lock = destination.parent / ('.' + destination.name + '.install-lock')
    lock.mkdir()  # Exclusive: a concurrent installer must never replace this destination.
    try:
        if os.path.lexists(destination):
            raise ValueError('destination appeared during installation')
        launcher = home / '.local/bin/nvim'
        if ident.startswith('nvim/') and os.path.lexists(launcher):
            raise ValueError('nvim launcher already exists; migrate explicitly')
        payload = work / 'download'
        if record['kind'] == 'file-gz':
            payload = decompress(payload, work / 'extract')
        elif record['kind'] in ARCHIVES:
            payload = extract(payload, work / 'extract', record, ident)
        with tempfile.TemporaryDirectory(prefix='.' + destination.name + '.', dir=destination.parent) as directory:
            staged = Path(directory) / 'payload'
            if payload.is_dir():
                shutil.copytree(payload, staged, symlinks=True)
            else:
                shutil.copy2(payload, staged)
                staged.chmod(0o644 if ident.split('/')[0] in DATA_TREES else 0o755)
            os.rename(staged, destination)
        state = home / '.local/state/dotfiles-security/artifacts'
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        receipt = state / (ident.replace('/', '_') + '.json')
        pending = receipt.with_suffix('.tmp')
        pending.write_text(json.dumps({'id': ident, 'archive_sha256': record['sha256'],
                                       'files': inventory(destination)}, sort_keys=True) + '\n')
        pending.chmod(0o600)
        pending.replace(receipt)
        if ident.startswith('nvim/'):
            check_parents(launcher, home, allow_leaf_link=True)
            if os.path.lexists(launcher):
                raise ValueError('nvim launcher already exists; migrate explicitly')
            launcher.parent.mkdir(parents=True, exist_ok=True)
            launcher.symlink_to(destination / 'bin/nvim')
    finally:
        lock.rmdir()


def initialize_rust(home, ident, record):
    if ident.startswith('rustup-init/') and not os.access(home / '.cargo/bin/rustup', os.X_OK):
        subprocess.run([str(home / record['destination']), '-y', '--no-modify-path',
                        '--default-toolchain', '1.95.0'], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('tool', choices=ORIGINS)
    parser.add_argument('version')
    parser.add_argument('platform')
    args = parser.parse_args()
    os.umask(0o077)
    descriptor = os.environ.get('DOTFILES_ARTIFACT_PROGRESS_FD', '1')
    if not re.fullmatch('[0-9]+', descriptor):
        raise ValueError('invalid artifact progress descriptor')
    ident, record = reviewed_record(args.tool, args.version, args.platform)
    home = Path.home()
    installed = preflight(home, ident, record)
    print(('verified installed artifact: ' if installed else 'ready to install reviewed artifact: ') + ident)
    if args.check:
        return
    with os.fdopen(os.dup(int(descriptor)), 'w', buffering=1) as output:
        def progress(message):
            print('  ' + message, file=output, flush=True)
        if installed:
            progress(ident + ': already verified; skipping download.')
        else:
            with tempfile.TemporaryDirectory(prefix='dotfiles-artifact.') as directory:
                work = Path(directory).resolve()
                download(record['url'], work / 'download', ident, progress)
                if file_hash(work / 'download') != record['sha256']:
                    raise ValueError('artifact SHA-256 mismatch')
                progress(ident + ': SHA-256 verified; installing...')
                publish(home, ident, record, work)
            progress(ident + ': installed and receipt saved.')
        initialize_rust(home, ident, record)


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
    except (OSError, ValueError, KeyError, tarfile.TarError, zipfile.BadZipFile, EOFError, RuntimeError) as error:
        sys.exit(str(error))
