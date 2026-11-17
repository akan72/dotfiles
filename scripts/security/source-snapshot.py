#!/usr/bin/env python3
"""Export committed HEAD (never the worktree) for container tests, or verify an export."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess

SENSITIVE_COMPONENT = re.compile(r'(token|credential|secret|private[-_]?key|auth[.](json|toml|ya?ml|ini))', re.I)
SENSITIVE_DIRS = {'.ssh', '.aws', '.azure', '.gnupg', '.kube', '.docker', '.npm',
                  '.password-store', 'gcloud', 'gh', 'hub', 'keychains', 'auth', 'authentication', 'oauth'}
SENSITIVE_NAMES = {'.npmrc', 'npmrc', '.yarnrc', '.yarnrc.yml', '.pypirc', '.netrc',
                   '_netrc', '.s3cfg', '.boto', 'nuget.config', 'pip.conf', 'pip.ini', '.git-credentials', '.gitconfig.local',
                   'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519', 'authorized_keys'}
MANIFEST = '.dotfiles-source-manifest.json'


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


def git(repo, *args, data=None):
    return subprocess.run(['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
                           '-C', str(repo), *args], input=data, capture_output=True, check=True).stdout


def export(repo, target):
    head = git(repo, 'rev-parse', '--verify', 'HEAD^{commit}').decode().strip()
    entries = [(os.fsdecode(name), *meta.decode().split()) for meta, name in
               (line.split(b'\t', 1) for line in git(repo, 'ls-tree', '-rz', '--full-tree', head).split(b'\0')[:-1])]
    for name, mode, kind, _ in entries:  # Refuse every unsafe name or entry before reading any content.
        validate_source_path(name)
        if kind != 'blob' or mode not in {'100644', '100755'}:
            raise SystemExit('expected a regular source file: ' + name)
    # One process; --batch applies no textconv, clean/smudge or export-subst/export-ignore transforms.
    batch = git(repo, 'cat-file', '--batch', data=b''.join(oid.encode() + b'\n' for *_, oid in entries))
    files, offset = {}, 0
    target.mkdir(mode=0o700, parents=True)
    for name, mode, _, _ in entries:  # Case-folding collisions fail the verify() that follows every export.
        end = batch.index(b'\n', offset)
        size = int(batch[offset:end].split()[2])
        data, offset = batch[end + 1:end + 1 + size], end + 2 + size
        (target / name).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        (target / name).write_bytes(data)
        (target / name).chmod(0o755 if mode == '100755' else 0o644)
        files[name] = hashlib.sha256(data).hexdigest()
    executables = sorted(name for name, mode, *_ in entries if mode == '100755')
    manifest = {'schema': 2, 'head': head, 'mode': 'HEAD', 'executables': executables, 'files': files}
    (target / MANIFEST).write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')


def verify(root):
    files, executables = {}, []
    for path in root.rglob('*'):
        rel, mode = path.relative_to(root).as_posix(), path.lstat().st_mode
        validate_source_path(rel)
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise SystemExit('expected a regular source file: ' + rel)
        if stat.S_ISREG(mode) and rel != MANIFEST:
            files[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
            executables += [rel] if mode & 0o111 else []
    manifest = root / MANIFEST  # The loop above already refused a symlinked or nonregular manifest.
    expected = json.loads(manifest.read_text()) if manifest.is_file() else {}
    if [expected.get(key) for key in ('schema', 'files', 'executables')] != [2, files, sorted(executables)]:
        raise SystemExit('source archive changed or contains unexpected files')
    print('verified source snapshot')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--output', type=Path, metavar='DIR', help='new directory for the HEAD export')
    action.add_argument('--verify', type=Path, metavar='DIR', help='check an export against its manifest')
    parser.add_argument('--repo', type=Path, default=Path.cwd())
    args = parser.parse_args()
    if args.output:
        export(args.repo, args.output)
    verify(args.output or args.verify)


if __name__ == '__main__':
    main()
