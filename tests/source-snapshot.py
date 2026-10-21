#!/usr/bin/env python3
"""Inert path-policy regressions; no real credential contents or network."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('snapshot', ROOT/'scripts/security/source-snapshot.py')
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='snapshot-policy-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root/'repo'
        self.repo.mkdir()
        self.git('init', '-q')
        (self.repo/'source.txt').write_text('safe fixture\n')
        self.git('add', 'source.txt')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'core.fsmonitor=false', '-c',
            'core.hooksPath=/dev/null', '-C', str(self.repo), *args], stderr=subprocess.PIPE)

    def invoke(self, *args):
        with mock.patch.object(sys, 'argv', ['snapshot', '--repo', str(self.repo),
                '--output', str(self.root/'out'), *args]):
            snapshot.main()

    def test_head_export_excludes_untracked_and_ignored_state(self):
        (self.repo/'.gitignore').write_text('ignored\n')
        self.git('add', '.gitignore')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-qm', 'ignore fixture')
        for name in ['ignored', 'credential-example.txt']:
            (self.repo/name).write_text('inert local fixture\n')
        self.invoke()
        out = self.root/'out'
        self.assertFalse((out/'.git').exists())
        self.assertFalse((out/'ignored').exists())
        self.assertFalse((out/'credential-example.txt').exists())
        snapshot.verify(out)
        (out/'source.txt').write_text('tampered\n')
        with self.assertRaisesRegex(SystemExit, 'source archive changed'):
            snapshot.verify(out)

    def test_dirty_head_requires_explicit_working_export(self):
        (self.repo/'source.txt').write_text('changed source\n')
        with self.assertRaisesRegex(SystemExit, 'tracked changes exist'):
            self.invoke()
        self.invoke('--working')
        self.assertEqual((self.root/'out/source.txt').read_text(), 'changed source\n')


    def test_sensitive_includes_refused_before_any_file_bytes_are_read(self):
        names = ['.env', '.env.local', '.ENV.production', '.npmrc', 'nested/.npmrc',
                 '.yarnrc.yml', '.pypirc', '.netrc', 'pip.conf', 'pip.ini',
                 '.aws/config', '.ssh/config', '.azure/settings.json', '.gnupg/data',
                 '.kube/config', '.docker/config.json', '.config/gcloud/config.db',
                 '.config/gh/hosts.yml', 'keys/server.pem', 'keys/server.key',
                 'keys/id_rsa', 'keys/id_ed25519', 'keys/store.p12', 'keys/store.pfx',
                 'keys/store.jks', 'keys/server.pem.bak', 'keys/server.key.old', 'keys/id_ed25519.backup', 'config.tfvars', 'config.tfvars.json', '.envrc', 'nested/credentials/config',
                 'nested/auth/settings.json', 'nested/private-key/config',
                 'nested/access_token/config', 'nested/mytoken.txt', 'nested/auth.json', '.git-credentials', '.gitconfig.local']
        for name in names:
            with self.subTest(name=name), mock.patch.object(snapshot, 'read_source',
                    side_effect=AssertionError('must reject names before reading bytes')):
                with self.assertRaisesRegex(SystemExit, 'sensitive-named source path refused'):
                    self.invoke('--working', '--include', name)
        self.assertFalse((self.root/'out').exists())

    def test_tracked_sensitive_paths_refused_in_head_and_working_modes(self):
        (self.repo/'.env').write_text('INERT_FIXTURE=fictional\n')
        self.git('add', '.env')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-qm', 'inert filename fixture')
        for args in [[], ['--working']]:
            with self.assertRaisesRegex(SystemExit, 'sensitive-named source path refused'):
                self.invoke(*args)

    def test_safe_sources_with_spaces_export_without_index_changes(self):
        before = self.git('status', '--porcelain=v1')
        (self.repo/'new source.py').write_text('# inert\n')
        (self.repo/'gh-auth-refresh.sh').write_text('# public source fixture\n')
        self.invoke('--working', '--include', 'new source.py', '--include', 'gh-auth-refresh.sh')
        self.assertEqual((self.root/'out/new source.py').read_text(), '# inert\n')
        self.assertEqual(self.git('diff', '--cached'), b'')
        self.assertEqual(before, b'')

    def test_unsafe_names_and_symlink_parents_refused(self):
        for name in ['../outside', '/absolute', '.git/config', '.GIT/config', './source.txt', 'bad\nname']:
            with self.assertRaisesRegex(SystemExit, 'unsafe source path'):
                snapshot.validate_source_path(name)
        outside = self.root/'outside'
        outside.mkdir()
        (outside/'source.py').write_text('# outside inert fixture\n')
        (self.repo/'linked').symlink_to(outside)
        with self.assertRaisesRegex(SystemExit, 'regular source file'):
            self.invoke('--working', '--include', 'linked/source.py')
        with self.assertRaises(OSError):
            snapshot.read_source(self.repo, ('linked', 'source.py'))


if __name__ == '__main__':
    unittest.main()
