#!/usr/bin/env python3
"""Offline Socket installer fixtures; fixture executable is never run."""
import copy
import contextlib
import datetime
import hashlib
import json
import os
from pathlib import Path
import struct
import stat
import subprocess
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'scripts/security/install-socket.sh').read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
installer = types.ModuleType('socket_installer')
exec(compile(source, 'install-socket.sh embedded Python', 'exec'), installer.__dict__)


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
        self.assertFalse(result['executed'])
        self.assertEqual(Path(result['destination']).read_bytes(), self.data)
        self.assertFalse(Path(result['launcher']).is_symlink())
        self.assertIn('/usr/bin/python3 -I -S',Path(result['launcher']).read_text())
        guard=Path(result['destination']).with_name('launch.py').read_text()
        self.assertIn("NODE_OPTIONS='--use-openssl-ca'",guard)
        self.assertIn("NODE_TLS_REJECT_UNAUTHORIZED='1'",guard)
        self.run_install()
        self.assertEqual(len(self.downloads), 1)

    def test_changed_installed_bytes_refused(self):
        result = self.run_install()
        Path(result['destination']).write_bytes(b'tampered')
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(len(self.downloads), 1)

    def test_bad_download_refused_before_destination(self):
        self.data += b'changed'
        with self.assertRaises(ValueError): self.run_install()
        self.assertFalse((self.home / '.local').exists())

    def test_existing_command_preserved(self):
        command = self.home / '.local/bin/sfw'
        command.parent.mkdir(parents=True)
        command.write_text('existing command')
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(command.read_text(), 'existing command')
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

    def test_unreviewed_url_refused_before_download(self):
        self.manifest['artifacts']['arm64']['url'] = 'https://example.com/sfw'
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(self.downloads, [])

    def test_young_release_refused(self):
        now = datetime.datetime.now(datetime.timezone.utc)
        self.manifest['published_at'] = now.isoformat()
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(self.downloads, [])

    def test_launcher_symlink_conflict_preserved(self):
        command = self.home / '.local/bin/sfw'
        command.parent.mkdir(parents=True)
        command.symlink_to('/unrelated-target')
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(os.readlink(command), '/unrelated-target')

    def test_manifest_digest_is_required(self):
        self.manifest['artifacts']['arm64']['sha256'] = ''
        with self.assertRaises(ValueError): self.run_install()
        self.assertEqual(self.downloads, [])

    def test_launcher_blocks_tampered_ca_before_executable(self):
        result=self.run_install()
        Path(result['destination']).with_name('ca-certificates.pem').write_bytes(b'tampered')
        process=subprocess.run([result['launcher'],'--version'],capture_output=True,text=True)
        self.assertNotEqual(process.returncode,0)
        self.assertIn('SHA256 changed',process.stderr)

    def test_launcher_blocks_nonempty_ca_directory(self):
        result=self.run_install()
        folder=Path(result['destination']).with_name('empty-ca')
        (folder/'unexpected.pem').write_bytes(b'unapproved')
        process=subprocess.run([result['launcher'],'--version'],capture_output=True,text=True)
        self.assertNotEqual(process.returncode,0)
        self.assertIn('empty CA directory changed',process.stderr)

    def test_ca_loader_must_match_reviewed_digest(self):
        self.ca_data=b'tampered'
        with self.assertRaises(ValueError):self.run_install()
        self.assertEqual(self.downloads,[])

    def test_changed_guard_refused_on_replay(self):
        result=self.run_install()
        Path(result['destination']).with_name('launch.py').write_text('changed')
        with self.assertRaises(ValueError):self.run_install()


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



if __name__ == '__main__':
    unittest.main()
