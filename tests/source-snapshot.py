#!/usr/bin/env python3
"""HEAD exporter and path-policy regressions; no real credential contents or network."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('snapshot', ROOT/'scripts/security/source-snapshot.py')
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)
SENSITIVE = ['.env', '.env.local', '.ENV.production', '.npmrc', 'nested/.npmrc',
             '.yarnrc.yml', '.pypirc', '.netrc', 'pip.conf', 'pip.ini',
             '.aws/config', '.ssh/config', '.azure/settings.json', '.gnupg/data',
             '.kube/config', '.docker/config.json', '.config/gcloud/config.db',
             '.config/gh/hosts.yml', 'keys/server.pem', 'keys/server.key',
             'keys/id_rsa', 'keys/id_ed25519', 'keys/store.p12', 'keys/store.pfx',
             'keys/store.jks', 'keys/server.pem.bak', 'keys/server.key.old', 'keys/id_ed25519.backup',
             'config.tfvars', 'config.tfvars.json', '.envrc', 'nested/credentials/config',
             'nested/auth/settings.json', 'nested/private-key/config', 'nested/access_token/config',
             'nested/mytoken.txt', 'nested/auth.json', '.git-credentials', '.gitconfig.local']
UNSAFE = ['../outside', '/absolute', '.git/config', '.GIT/config', './source.txt', 'bad\nname']


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='snapshot-policy-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo, self.out = self.root/'repo', self.root/'out'
        self.repo.mkdir()
        self.git('init', '-q')
        (self.repo/'source.txt').write_text('safe fixture\n')
        (self.repo/'run.sh').write_text('#!/bin/sh\n# $Format:%H$\n')
        (self.repo/'run.sh').chmod(0o755)
        (self.repo/'.gitattributes').write_text('run.sh export-ignore export-subst\nsource.txt filter=inert\n')
        self.commit('source.txt', 'run.sh', '.gitattributes')
        self.git('config', 'filter.inert.smudge', 'tr a-z A-Z')  # Would visibly change exported bytes.

    def git(self, *args):
        return subprocess.check_output(['git', '-c', 'core.fsmonitor=false', '-c',
            'core.hooksPath=/dev/null', '-C', str(self.repo), *args], stderr=subprocess.PIPE)

    def commit(self, *paths):
        self.git('add', '--', *paths)
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                 '-c', 'commit.gpgsign=false', 'commit', '-qm', 'fixture')

    def invoke(self, *args):
        with mock.patch.object(sys, 'argv', ['snapshot', *args]):
            snapshot.main()

    def git_state(self):
        objects = sorted(str(path) for path in (self.repo/'.git/objects').rglob('*'))
        return (self.repo/'.git/index').read_bytes(), objects

    def test_head_export_ignores_worktree_and_keeps_git_state(self):
        (self.repo/'.gitignore').write_text('ignored\n')
        self.commit('.gitignore')
        (self.repo/'source.txt').write_text('dirty worktree edit\n')
        (self.repo/'staged.txt').write_text('staged only\n')
        self.git('add', 'staged.txt')
        for name in ['ignored', 'untracked.txt', 'credentials.json']:
            (self.repo/name).write_text('inert local fixture\n')
        (self.repo/'run.sh').touch()  # A refreshing Git command would rewrite cached stat data.
        before = self.git_state()
        self.invoke('--repo', str(self.repo), '--output', str(self.out))
        self.assertEqual(self.git_state(), before)
        self.assertEqual(sorted(path.name for path in self.out.iterdir()),
                         ['.dotfiles-source-manifest.json', '.gitattributes', '.gitignore', 'run.sh', 'source.txt'])
        self.assertEqual((self.out/'source.txt').read_text(), 'safe fixture\n')
        # Export attributes and filters cannot omit or transform committed bytes.
        self.assertEqual((self.out/'run.sh').read_text(), '#!/bin/sh\n# $Format:%H$\n')
        self.assertEqual((self.out/'run.sh').stat().st_mode & 0o777, 0o755)
        self.assertEqual((self.out/'source.txt').stat().st_mode & 0o777, 0o644)
        manifest = json.loads((self.out/'.dotfiles-source-manifest.json').read_text())
        self.assertEqual((manifest['head'], manifest['executables']),
                         (self.git('rev-parse', 'HEAD').decode().strip(), ['run.sh']))

    def test_sensitive_and_unsafe_names_refused_before_content_is_read(self):
        for names, message in [(SENSITIVE, 'sensitive-named source path refused'), (UNSAFE, 'unsafe source path')]:
            for name in names:
                tree = ('100644 blob ' + '0' * 40 + '\t' + name + '\0').encode()
                def fake_git(repo, *args, data=None):
                    if args[0] == 'cat-file':
                        raise AssertionError('content read before names were refused')
                    return tree if args[0] == 'ls-tree' else b'0' * 40 + b'\n'
                with self.subTest(name=name), mock.patch.object(snapshot, 'git', fake_git):
                    with self.assertRaisesRegex(SystemExit, message):
                        snapshot.export(self.repo, self.out)
        self.assertFalse(self.out.exists())
        (self.repo/'.env').write_text('INERT_FIXTURE=fictional\n')
        self.commit('.env')
        with self.assertRaisesRegex(SystemExit, 'sensitive-named source path refused: .env'):
            self.invoke('--repo', str(self.repo), '--output', str(self.out))
        self.assertFalse(self.out.exists())

    def test_symlink_and_submodule_entries_refused(self):
        (self.repo/'link.txt').symlink_to('source.txt')
        self.commit('link.txt')
        with self.assertRaisesRegex(SystemExit, 'regular source file: link.txt'):
            snapshot.export(self.repo, self.out)
        self.git('rm', '-q', '--cached', 'link.txt')
        head = self.git('rev-parse', 'HEAD').decode().strip()
        self.git('update-index', '--add', '--cacheinfo', '160000,' + head + ',module')
        self.commit('.gitattributes')
        with self.assertRaisesRegex(SystemExit, 'regular source file: module'):
            snapshot.export(self.repo, self.out)
        self.assertFalse(self.out.exists())

    def test_verify_detects_each_change(self):
        (self.repo/'nested').mkdir()
        (self.repo/'nested/tool.py').write_text('# inert\n')
        self.commit('nested/tool.py')
        self.invoke('--repo', str(self.repo), '--output', str(self.out))
        self.invoke('--verify', str(self.out))
        changes = {'changed byte': lambda out: (out/'source.txt').write_text('safe fixturE\n'),
                   'extra file': lambda out: (out/'nested/extra.py').write_text('# extra\n'),
                   'missing file': lambda out: (out/'nested/tool.py').unlink(),
                   'flipped executable bit': lambda out: (out/'run.sh').chmod(0o644),
                   'symlink': lambda out: (out/'link.txt').symlink_to('source.txt'),
                   'missing manifest': lambda out: (out/'.dotfiles-source-manifest.json').unlink(),
                   'sensitive name': lambda out: (out/'.secret-cache').write_text('inert\n')}
        for label, change in changes.items():
            with self.subTest(change=label):
                copy = self.root/label
                shutil.copytree(self.out, copy, symlinks=True)
                change(copy)
                with self.assertRaisesRegex(SystemExit, 'source archive changed|regular source file|sensitive-named'):
                    snapshot.verify(copy)


if __name__ == '__main__':
    unittest.main()
