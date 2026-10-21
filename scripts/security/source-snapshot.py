#!/usr/bin/env python3
"""Export tracked bytes only. --working uses a temporary index/object database, no commit.
Explicit new paths are a reviewed allowlist; no automatic untracked-file discovery.
"""
import argparse, hashlib, io, json, os, pathlib, re, shutil, stat, subprocess, tarfile, tempfile


SENSITIVE_COMPONENT = re.compile(r'(token|credential|secret|private[-_]?key|auth[.](json|toml|ya?ml|ini))', re.I)
SENSITIVE_DIRS = {'.ssh', '.aws', '.azure', '.gnupg', '.kube', '.docker', '.npm',
                  '.password-store', 'gcloud', 'gh', 'hub', 'keychains', 'auth', 'authentication', 'oauth'}
SENSITIVE_NAMES = {'.npmrc', 'npmrc', '.yarnrc', '.yarnrc.yml', '.pypirc', '.netrc',
                   '_netrc', '.s3cfg', '.boto', 'nuget.config', 'pip.conf', 'pip.ini', '.git-credentials', '.gitconfig.local',
                   'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519', 'authorized_keys'}


def validate_source_path(name):
    rel = pathlib.PurePosixPath(name)
    if (not rel.parts or rel.is_absolute() or '..' in rel.parts or any(part.lower() == '.git' for part in rel.parts)
            or str(rel) != name or any(ord(c) < 32 or ord(c) == 127 for c in name)):
        raise SystemExit('unsafe source path')
    for part in rel.parts:
        lower = part.lower()
        if (lower.startswith('.env') or lower in SENSITIVE_DIRS or lower in SENSITIVE_NAMES
                or SENSITIVE_COMPONENT.search(part) or lower.endswith('.tfvars.json')
                or any(lower.startswith(key + '.') for key in ('id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519'))
                or set(pathlib.PurePosixPath(lower).suffixes) & {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.tfvars'}):
            raise SystemExit('sensitive-named source path refused: ' + name)
    return rel


def run(repo, *args, env=None, data=None):
    return subprocess.check_output(['git', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args], env=env, input=data)


def read_source(repo, parts):
    # Hold each directory while walking: replacements cannot redirect reads through symlinks.
    directory = os.open(repo, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = nxt
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(fd, 'rb') as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise SystemExit('expected a regular source file')
            return stream.read()
    finally:
        os.close(directory)


def entries(root):
    result = {}
    for p in sorted(root.rglob('*')):
        rel = p.relative_to(root).as_posix()
        if rel == '.dotfiles-source-manifest.json':
            continue
        validate_source_path(rel)
        if p.is_symlink():
            raise SystemExit('snapshot symlinks are refused: ' + rel)
        if p.is_file():
            result[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def verify(root):
    manifest = root / '.dotfiles-source-manifest.json'
    if not manifest.is_file() or manifest.is_symlink():
        raise SystemExit('source archive manifest missing')
    data = json.loads(manifest.read_text())
    if data.get('schema') != 1 or data.get('files') != entries(root):
        raise SystemExit('source archive changed or contains unexpected files')
    if (root / '.git').exists():
        raise SystemExit('source archive contains .git')
    print('verified source snapshot: ' + data['tree'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=pathlib.Path)
    parser.add_argument('--repo', type=pathlib.Path, default=pathlib.Path.cwd())
    parser.add_argument('--output', type=pathlib.Path)
    parser.add_argument('--working', action='store_true')
    parser.add_argument('--include', action='append', default=[])
    args = parser.parse_args()
    if args.verify:
        verify(args.verify)
        return
    if args.output is None:
        parser.error('--output is required')
    repo = args.repo.resolve()
    if pathlib.Path(run(repo, 'rev-parse', '--show-toplevel').decode().strip()).resolve() != repo:
        raise SystemExit('--repo must be the repository root')
    if args.output.exists():
        raise SystemExit('snapshot destination already exists')
    if args.include and not args.working:
        raise SystemExit('--include requires --working')
    # Validate every selected name before reading any working-tree bytes or exporting HEAD.
    tracked = run(repo, 'ls-files', '-z').decode().split('\0')[:-1]
    paths = sorted(set(tracked + args.include))
    for name in paths:
        validate_source_path(name)
    if not args.working and run(repo, 'status', '--porcelain=v1', '--untracked-files=no'):
        raise SystemExit('tracked changes exist; use explicit --working and reviewed --include paths')
    with tempfile.TemporaryDirectory(prefix='dotfiles-source-index-') as tmp:
        tmp = pathlib.Path(tmp)
        env = os.environ.copy()
        env['GIT_INDEX_FILE'] = str(tmp / 'index')
        objects = pathlib.Path(run(repo, 'rev-parse', '--git-path', 'objects').decode().strip())
        if not objects.is_absolute():
            objects = repo / objects
        env['GIT_OBJECT_DIRECTORY'] = str(tmp / 'objects')
        env['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = str(objects.resolve())
        (tmp / 'objects').mkdir()
        run(repo, 'read-tree', 'HEAD', env=env)
        if args.working:
            for name in paths:
                rel = validate_source_path(name)
                path = repo / rel
                if path.is_symlink():
                    raise SystemExit('snapshot symlinks are refused: ' + name)
                if not path.exists():
                    if name not in tracked:
                        raise SystemExit('included path missing: ' + name)
                    run(repo, 'update-index', '--force-remove', '--', name, env=env)
                    continue
                if not path.is_file() or any(parent.is_symlink() for parent in path.parents if parent != repo.parent):
                    raise SystemExit('expected a regular source file: ' + name)
                blob = run(repo, 'hash-object', '--no-filters', '-w', '--stdin', env=env, data=read_source(repo, rel.parts)).decode().strip()
                mode = '100755' if path.stat().st_mode & 0o111 else '100644'
                run(repo, 'update-index', '--add', '--cacheinfo', mode + ',' + blob + ',' + name, env=env)
        tree = run(repo, 'write-tree', env=env).decode().strip()
        for name in run(repo, 'ls-tree', '-r', '--name-only', '-z', tree, env=env).decode().split('\0')[:-1]:
            validate_source_path(name)
        archive = run(repo, 'archive', '--format=tar', tree, env=env)
        args.output.mkdir(mode=0o700, parents=True)
        try:
            with tarfile.open(fileobj=io.BytesIO(archive)) as tf:
                for member in tf.getmembers():
                    rel = pathlib.PurePosixPath(member.name)
                    if rel.is_absolute() or '..' in rel.parts or any(part.lower() == '.git' for part in rel.parts):
                        raise SystemExit('unsafe archive path')
                    target = args.output.joinpath(*rel.parts)
                    if member.isdir():
                        target.mkdir(parents=True, exist_ok=True)
                    elif member.isfile():
                        target.parent.mkdir(parents=True, exist_ok=True)
                        with tf.extractfile(member) as src, target.open('xb') as dst:
                            shutil.copyfileobj(src, dst)
                        target.chmod(0o755 if member.mode & 0o111 else 0o644)
                    else:
                        raise SystemExit('only regular source files are exported')
            manifest = {'schema': 1, 'tree': tree, 'head': run(repo, 'rev-parse', 'HEAD').decode().strip(), 'mode': 'working' if args.working else 'HEAD', 'files': entries(args.output)}
            (args.output / '.dotfiles-source-manifest.json').write_text(json.dumps(manifest, sort_keys=True, indent=2) + '\n')
            verify(args.output)
        except BaseException:
            shutil.rmtree(args.output)
            raise


if __name__ == '__main__':
    main()
