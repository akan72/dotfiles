#!/usr/bin/env python3
"""Native Bun discovery/age regression using inert loopback metadata and JSON-only tarballs."""
import argparse
import base64
import datetime as dt
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import tarfile
import tempfile
import threading
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
NAME = 'dotfiles-inert-age-fixture'


def limits():
    resource.setrlimit(resource.RLIMIT_CPU, (15, 15))
    resource.setrlimit(resource.RLIMIT_FSIZE, (8 * 1024 * 1024, 8 * 1024 * 1024))
    resource.setrlimit(resource.RLIMIT_NOFILE, (128, 128))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bun', default=shutil.which('bun'))
    args = parser.parse_args()
    if not args.bun:
        parser.error('Bun is required; use an already reviewed installation')
    bun = str(Path(args.bun).resolve(strict=True))
    packages = {}
    for version in ['1.0.0', '1.1.0']:
        data = json.dumps({'name': NAME, 'version': version}).encode()
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode='w:gz') as archive:
            entry = tarfile.TarInfo('package/package.json')
            entry.mode = 0o644
            entry.size = len(data)
            archive.addfile(entry, io.BytesIO(data))
        packages[version] = output.getvalue()
    now = dt.datetime.now(dt.timezone.utc)
    requests = []

    class Registry(BaseHTTPRequestHandler):
        def log_message(self, *arguments):
            pass

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            requests.append(path)
            if path == '/' + NAME:
                base = 'http://127.0.0.1:' + str(self.server.server_port)
                versions = {v: {'name': NAME, 'version': v, 'dist': {
                    'tarball': base + '/fixture-' + v + '.tgz',
                    'integrity': 'sha512-' + base64.b64encode(hashlib.sha512(data).digest()).decode(),
                    'shasum': hashlib.sha1(data).hexdigest()}} for v, data in packages.items()}
                data = json.dumps({'name': NAME, 'dist-tags': {'latest': '1.1.0'},
                    'versions': versions, 'time': {
                        '1.0.0': (now - dt.timedelta(days=30)).isoformat(),
                        '1.1.0': (now - dt.timedelta(hours=1)).isoformat()}}).encode()
                content_type = 'application/json'
            elif path in ['/fixture-' + v + '.tgz' for v in packages]:
                data = packages[path.removeprefix('/fixture-').removesuffix('.tgz')]
                content_type = 'application/octet-stream'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = ThreadingHTTPServer(('127.0.0.1', 0), Registry)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix='bun-age-') as directory:
            root = Path(directory).resolve()
            for label, xdg, link, expected in [('home-only-with-xdg', True, False, '1.1.0'),
                    ('xdg-policy', True, True, '1.0.0'), ('home-fallback', False, False, '1.0.0')]:
                case = root / label
                home, project = case / 'home', case / 'project'
                for p in [home / '.config', project, case / 'tmp', case / 'cache']:
                    p.mkdir(parents=True, exist_ok=True)
                # The policy copy is public source; the test never opens live HOME configs.
                policy = case / 'policy.toml'
                policy.write_bytes((ROOT / '.bunfig.toml').read_bytes())
                (home / '.bunfig.toml').symlink_to(policy)
                if link:
                    (home / '.config/.bunfig.toml').symlink_to(policy)
                (project / 'package.json').write_text(json.dumps({'private': True,
                    'dependencies': {NAME: '*'}}))
                env = {'HOME': str(home), 'PATH': '/usr/bin:/bin', 'TMPDIR': str(case / 'tmp'),
                    'BUN_INSTALL_CACHE_DIR': str(case / 'cache'), 'NO_COLOR': '1'}
                if xdg:
                    env['XDG_CONFIG_HOME'] = str(home / '.config')
                command = [bun, 'install', '--ignore-scripts', '--no-progress', '--no-cache',
                    '--registry', 'http://127.0.0.1:' + str(server.server_port)]
                if os.uname().sysname == 'Darwin':
                    # No host writes or external network; expose only this inert fixture and Bun.
                    quote = lambda value: json.dumps(str(value))
                    profile = '(version 1)(allow default)(deny file-write*)' \
                        '(allow file-write* (subpath ' + quote(root) + ') (literal "/dev/null"))' \
                        '(deny file-read* (subpath ' + quote(Path.home()) + '))' \
                        '(allow file-read* (literal ' + quote(bun) + ') (subpath ' + quote(root) + '))' \
                        '(deny network*)(allow network-outbound (remote tcp "localhost:' + str(server.server_port) + '"))'
                    command = ['/usr/bin/sandbox-exec', '-p', profile, *command]
                result = subprocess.run(command, cwd=project, env=env, stdin=subprocess.DEVNULL,
                    capture_output=True, text=True, timeout=30, preexec_fn=limits)
                if result.returncode:
                    raise AssertionError(label + ': ' + result.stdout[-3000:] + result.stderr[-3000:])
                actual = json.loads((project / 'node_modules' / NAME / 'package.json').read_text())['version']
                assert actual == expected, (label, actual, expected)
                assert not (project / 'bunfig.toml').exists()
                print('PASS:', label, 'selected', actual, flush=True)
            assert '/' + NAME in requests and '/fixture-1.0.0.tgz' in requests and '/fixture-1.1.0.tgz' in requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    print('Bun discovery and seven-day filtering passed; no public registry or executable package content used.')


if __name__ == '__main__':
    main()
