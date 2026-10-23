#!/usr/bin/env python3
"""Offline Socket installer fixtures; fixture executable is never run."""
import copy
import contextlib
import importlib.util
import runpy
import sys
import datetime
import hashlib
import json
import os
from pathlib import Path
import struct
import stat
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('socket_installer', ROOT / 'scripts/security/install-socket.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class Installer(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name).resolve()
        self.data = struct.pack('<II', 0xfeedfacf, 0x0100000c) + b'NOT EXECUTABLE FIXTURE'
        self.manifest = json.loads((ROOT / 'scripts/security/socket-artifacts.json').read_text())
        self.manifest['artifacts']['arm64']['sha256'] = hashlib.sha256(self.data).hexdigest()
        self.ca_data=b'PUBLIC FIXTURE CA BUNDLE'
        self.manifest['ca_sha256']=hashlib.sha256(self.ca_data).hexdigest()
        self.downloads = []

    def tearDown(self):
        self.temp.cleanup()

    def download(self, url):
        self.downloads.append(url)
        return self.data

    def run_install(self):
        return installer.install(self.manifest, 'arm64', self.home, self.download, lambda manifest:self.ca_data)

    def test_install_and_offline_replay(self):
        result = self.run_install()
        self.assertEqual(Path(result['destination']).read_bytes(), self.data)
        self.run_install()
        self.assertEqual(len(self.downloads), 1)

    def test_changed_installation_refused_offline(self):
        result = self.run_install()
        for path in [Path(result['destination']), Path(result['destination']).with_name('launch.py')]:
            with self.subTest(file=path.name):
                original = path.read_bytes()
                path.write_bytes(b'tampered')
                with self.assertRaises(ValueError):
                    self.run_install()
                path.write_bytes(original)
        self.assertEqual(len(self.downloads), 1)

    def test_bad_download_refused_before_destination(self):
        self.data += b'changed'
        with self.assertRaises(ValueError): self.run_install()
        self.assertFalse((self.home / '.local').exists())

    def test_existing_command_preserved(self):
        command = self.home / '.local/bin/sfw'
        command.parent.mkdir(parents=True)
        for symlink in (False, True):
            with self.subTest(symlink=symlink):
                command.symlink_to('/unrelated-target') if symlink else command.write_text('existing command')
                with self.assertRaises(ValueError):
                    self.run_install()
                self.assertEqual(os.readlink(command) if symlink else command.read_text(),
                                 '/unrelated-target' if symlink else 'existing command')
                command.unlink()
        self.assertEqual(self.downloads, [])

    def test_parent_symlink_does_not_write_outside(self):
        outside = self.home / 'outside'
        outside.mkdir()
        (self.home / '.local').symlink_to(outside)
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(self.downloads, [])

    def test_wrong_architecture_refused(self):
        self.data = struct.pack('<II', 0xfeedfacf, 0x01000007) + b'fixture'
        self.manifest['artifacts']['arm64']['sha256'] = hashlib.sha256(self.data).hexdigest()
        with self.assertRaises(ValueError): self.run_install()

    def test_unreviewed_metadata_refused_before_download(self):
        original = copy.deepcopy(self.manifest)
        for field in ('url', 'digest', 'release-age'):
            with self.subTest(field=field):
                self.manifest = copy.deepcopy(original)
                if field == 'release-age':
                    self.manifest['published_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                else:
                    self.manifest['artifacts']['arm64']['url' if field == 'url' else 'sha256'] = (
                        'https://example.com/sfw' if field == 'url' else '')
                with self.assertRaises(ValueError):
                    self.run_install()
                self.assertFalse((self.home / '.local').exists())
        self.assertEqual(self.downloads, [])

    def test_launcher_refuses_tampered_trust_before_execution(self):
        result = self.run_install()
        ca = Path(result['destination']).with_name('ca-certificates.pem')
        extra = ca.with_name('empty-ca') / 'unexpected.pem'
        for kind, message in [('ca', 'SHA256 changed'), ('extra-ca', 'empty CA directory changed')]:
            with self.subTest(kind=kind):
                original = ca.read_bytes()
                (ca if kind == 'ca' else extra).write_bytes(b'unapproved')
                process = subprocess.run([result['launcher'], '--version'], capture_output=True, text=True)
                self.assertNotEqual(process.returncode, 0)
                self.assertIn(message, process.stderr)
                ca.write_bytes(original)
                if extra.exists():
                    extra.unlink()

    def test_launcher_forces_reviewed_tls_environment(self):
        result = self.run_install()
        guard = Path(result['destination']).with_name('launch.py')
        with mock.patch.dict(os.environ, {'NODE_OPTIONS': '--require=/untrusted.js',
                                         'NODE_TLS_REJECT_UNAUTHORIZED': '0'}), \
             mock.patch.object(os, 'execve') as execute, mock.patch.object(sys, 'argv', ['launch.py', '--version']):
            runpy.run_path(str(guard))
        binary, arguments, environment = execute.call_args.args
        self.assertEqual((binary, arguments), (result['destination'], [result['destination'], '--version']))
        for name, value in {'NODE_OPTIONS': '--use-openssl-ca', 'NODE_TLS_REJECT_UNAUTHORIZED': '1',
                            'SSL_CERT_FILE': str(guard.with_name('ca-certificates.pem')),
                            'NODE_EXTRA_CA_CERTS': str(guard.with_name('ca-certificates.pem')),
                            'SSL_CERT_DIR': str(guard.with_name('empty-ca'))}.items():
            self.assertEqual(environment[name], value)

    def test_ca_loader_must_match_reviewed_digest(self):
        self.ca_data=b'tampered'
        with self.assertRaises(ValueError):self.run_install()
        self.assertEqual(self.downloads,[])

    def test_download_canonicalizes_system_temporary_directory_alias(self):
        physical=self.home/'physical-tmp'
        physical.mkdir()
        alias=self.home/'tmp-alias'
        alias.symlink_to(physical)
        def curl(arguments,check):
            target=Path(arguments[-1])
            self.assertEqual(target,target.resolve())
            target.write_bytes(self.data)
        with mock.patch.object(installer.tempfile,'TemporaryDirectory',return_value=contextlib.nullcontext(str(alias))):
            with mock.patch.object(installer.subprocess,'run',side_effect=curl):
                result=installer.download('https://github.com/SocketDev/sfw-free/releases/download/v1.15.4/sfw-free-macos-arm64')
        self.assertEqual(result,self.data)

    def test_access_time_change_is_not_treated_as_content_change(self):
        path=self.home/'public-artifact'
        path.write_bytes(self.data)
        original=installer.os.fstat
        tick=0
        def changed_access_time(fd):
            nonlocal tick
            tick+=1
            info=original(fd)
            names=('st_dev','st_ino','st_size','st_mtime_ns','st_ctime_ns','st_uid','st_mode')
            values={name:getattr(info,name) for name in names}
            values['st_atime_ns']=info.st_atime_ns+tick
            return types.SimpleNamespace(**values)
        with mock.patch.object(installer.os,'fstat',side_effect=changed_access_time):
            self.assertEqual(installer.read_regular(path),self.data)

    def test_mode_change_during_read_is_rejected(self):
        path=self.home/'public-artifact'
        path.write_bytes(self.data)
        path.chmod(0o600)
        original=installer.os.fstat
        reads=0
        def changed_mode(fd):
            nonlocal reads
            info=original(fd)
            if stat.S_ISREG(info.st_mode):
                reads+=1
                if reads==2:
                    path.chmod(0o644)
                    return original(fd)
            return info
        with mock.patch.object(installer.os,'fstat',side_effect=changed_mode):
            with self.assertRaises(ValueError):installer.read_regular(path)


class ShellAliases(unittest.TestCase):
    def test_interactive_routing_and_absent_socket(self):
        # Full shared config, inert launcher, no Socket/vendor binary or package request.
        with tempfile.TemporaryDirectory(prefix='socket aliases-') as directory:
            root = Path(directory).resolve()
            for present in (True, False):
                home = root / ('enabled' if present else 'absent')
                home.mkdir()
                if present:
                    launcher = home / '.local/bin/sfw'
                    launcher.parent.mkdir(parents=True)
                    launcher.write_text('#!/bin/sh\nprintf "%s\\0" "$@" > "$TEST_SOCKET_ARGV"\nexit 37\n')
                    launcher.chmod(0o700)
                for shell in ('bash', 'zsh'):
                    executable = shutil.which(shell)
                    self.assertIsNotNone(executable, 'Both Bash and Zsh are fixture prerequisites')
                    for manager in ('npm', 'bun', 'uv'):
                        with self.subTest(socket=present, shell=shell, manager=manager):
                            log = root / 'argv'
                            environment = {'HOME': str(home), 'PATH': '/usr/bin:/bin',
                                           'TEST_SOCKET_ARGV': str(log), 'MANAGER': manager,
                                           'PRESENT': 'yes' if present else 'no'}
                            script = '''brew() { printf '/inert-brew-prefix\\n'; }
. "$1"
. "$1"
if [ "$PRESENT" = no ]; then
    alias "$MANAGER" >/dev/null 2>&1 && exit 90
    exit 0
fi
eval "$MANAGER 'argument with spaces' '' '--value=literal'"
status_code=$?
[ "$status_code" = 37 ] || exit 91
'''
                            flags = ['--noprofile', '--norc', '-ic'] if shell == 'bash' else ['-f', '-ic']
                            result = subprocess.run([executable, *flags, script, 'fixture', str(ROOT / 'shared.sh')],
                                                    cwd=root, env=environment, capture_output=True, text=True, timeout=30)
                            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                            if present:
                                self.assertEqual(log.read_bytes().split(b'\0'),
                                                 [manager.encode(), b'argument with spaces', b'', b'--value=literal', b''])


if __name__ == '__main__':
    unittest.main()
