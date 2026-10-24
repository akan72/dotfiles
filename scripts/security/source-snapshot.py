#!/usr/bin/env python3
"""One source exporter for private scans and disposable container tests."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess

SENSITIVE_COMPONENT = re.compile(r'(token|credential|secret|private[-_]?key|auth[.](json|toml|ya?ml|ini))', re.I)
SENSITIVE_DIRS = {'.ssh', '.aws', '.azure', '.gnupg', '.kube', '.docker', '.npm',
                  '.password-store', 'gcloud', 'gh', 'hub', 'keychains', 'auth', 'authentication', 'oauth'}
SENSITIVE_NAMES = {'.npmrc', 'npmrc', '.yarnrc', '.yarnrc.yml', '.pypirc', '.netrc',
                   '_netrc', '.s3cfg', '.boto', 'nuget.config', 'pip.conf', 'pip.ini', '.git-credentials', '.gitconfig.local',
                   'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519', 'authorized_keys'}


def validate_source_path(name):
    rel = PurePosixPath(name)
    if (not rel.parts or rel.is_absolute() or '..' in rel.parts or any(part.lower() == '.git' for part in rel.parts)
            or str(rel) != name or any(ord(c) < 32 or ord(c) == 127 for c in name)):
        raise SystemExit('unsafe source path')
    for part in rel.parts:
        lower = part.lower()
        if (lower.startswith('.env') or lower in SENSITIVE_DIRS or lower in SENSITIVE_NAMES
                or SENSITIVE_COMPONENT.search(part) or lower.endswith('.tfvars.json')
                or any(lower.startswith(key + '.') for key in ('id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519'))
                or set(PurePosixPath(lower).suffixes) & {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.tfvars'}):
            raise SystemExit('sensitive-named source path refused: ' + name)
    return rel


SOURCE_SUFFIXES = {'.sh', '.bash', '.zsh', '.py', '.lua', '.toml', '.yaml', '.yml',
                   '.json', '.jsonc', '.md', '.txt', '.vim', '.conf', '.ini', '.js',
                   '.ts', '.tsx', '.jsx', '.go', '.rs', '.lock'}
SOURCE_NAMES = {'assimilate.sh', 'bashrc', 'bash_profile', 'zshrc', 'zprofile', 'shared.sh',
                'Brewfile', 'Dockerfile', 'Makefile', 'gitconfig', '.gitignore', 'go.sum', 'go.mod', 'config'}


def run(repo, *args):
    return subprocess.check_output(['git', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
                                    '-C', str(repo), *args], stderr=subprocess.PIPE)


def read_source(repo, parts):
    # Hold each directory; neither replacement races nor FIFOs can redirect/block reads.
    directory = os.open(repo, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = nxt
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(fd, 'rb') as stream:
            mode = os.fstat(stream.fileno()).st_mode
            if not stat.S_ISREG(mode):
                raise ValueError('expected a regular source file')
            return stream.read(), mode
    finally:
        os.close(directory)


def export(repo, target, *, working=False, include=(), scan=False):
    """Strict exports refuse unsafe state; scans omit it and report incomplete scope."""
    tracked = set(os.fsdecode(run(repo, 'ls-files', '-z')).split('\0')[:-1])
    head, blobs = None, {}
    if not working:
        head = run(repo, 'rev-parse', 'HEAD').decode().strip()
        for entry in run(repo, 'ls-tree', '-rz', head).split(b'\0')[:-1]:
            metadata, name = entry.split(b'\t', 1)
            blobs[os.fsdecode(name)] = metadata.decode().split()
    selected, omitted, paths, executables = [], [], [], []
    # Finish name validation before reading ANY selected file contents.
    for name in sorted(tracked | set(blobs) | set(include)):
        try:
            rel = validate_source_path(name)
        except SystemExit as error:
            if not scan:
                raise
            reason = 'unsafe path' if str(error) == 'unsafe source path' else 'authentication filename'
            omitted.append({'path': name, 'reason': reason})
            continue
        if scan and rel.suffix not in SOURCE_SUFFIXES and rel.name not in SOURCE_NAMES and not rel.name.startswith('Dockerfile'):
            omitted.append({'path': name, 'reason': 'outside source allowlist'})
        else:
            paths.append(rel)
    if not working and run(repo, 'status', '--porcelain=v1', '--untracked-files=no'):
        raise SystemExit('tracked changes exist; use explicit --working and reviewed --include paths')
    target.mkdir(mode=0o700, parents=True)
    try:
        for rel in paths:
            name = str(rel)
            try:
                if working:
                    data, mode = read_source(repo, rel.parts)
                else:
                    mode, kind, oid = blobs[name]
                    if mode not in {'100644', '100755'} or kind != 'blob':
                        raise ValueError('expected a regular source file')
                    data, mode = run(repo, 'cat-file', 'blob', oid), int(mode, 8)
            except (OSError, ValueError) as error:
                if scan:
                    omitted.append({'path': name, 'reason': 'missing, symlink or nonregular file'})
                    continue
                if isinstance(error, FileNotFoundError) and name in tracked and name not in include:
                    continue  # A tracked deletion in an explicit working export.
                raise SystemExit('expected a regular source file: ' + name) from error
            output = target / rel
            output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            output.write_bytes(data)
            output.chmod(0o600 if scan else 0o755 if mode & 0o111 else 0o644)
            selected.append({'path': name, 'sha256': hashlib.sha256(data).hexdigest()})
            if not scan and mode & 0o111:
                executables.append(name)
        if not scan:
            manifest = {'schema': 2, 'head': head or run(repo, 'rev-parse', 'HEAD').decode().strip(),
                        'mode': 'working' if working else 'HEAD', 'executables': executables,
                        'files': {entry['path']: entry['sha256'] for entry in selected}}
            (target / '.dotfiles-source-manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
        return selected, omitted
    except BaseException:
        shutil.rmtree(target)
        raise


def verify(root):
    manifest = root / '.dotfiles-source-manifest.json'
    if manifest.is_symlink() or not manifest.is_file():
        raise SystemExit('source archive manifest missing')
    data = json.loads(manifest.read_text())
    files, executables = {}, []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root).as_posix()
        validate_source_path(rel)
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise SystemExit('expected a regular source file: ' + rel)
        if path.is_file() and rel != manifest.name:
            payload, mode = read_source(root, Path(rel).parts)
            files[rel] = hashlib.sha256(payload).hexdigest()
            if mode & 0o111:
                executables.append(rel)
    if (data.get('schema') not in {1, 2} or data.get('files') != files
            or (data['schema'] == 2 and data.get('executables') != executables)):
        raise SystemExit('source archive changed or contains unexpected files')
    print('verified source snapshot')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=Path)
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    parser.add_argument('--output', type=Path)
    parser.add_argument('--working', action='store_true')
    parser.add_argument('--include', action='append', default=[])
    args = parser.parse_args()
    if args.verify:
        verify(args.verify)
        return
    if args.output is None or (args.include and not args.working):
        parser.error('--output is required; --include requires --working')
    repo = args.repo.resolve()
    if Path(os.fsdecode(run(repo, 'rev-parse', '--show-toplevel')).strip()).resolve() != repo:
        raise SystemExit('--repo must be the repository root')
    export(repo, args.output, working=args.working, include=args.include)
    verify(args.output)


if __name__ == '__main__':
    main()
