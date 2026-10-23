#!/bin/bash
# All scanner processes here are inert stubs; no dependencies are installed.
set -euo pipefail
test_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 - "$test_dir/../scripts/security/scan-source.py" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
from unittest import mock
import shutil
import subprocess
import sys
import tempfile

scanner = Path(sys.argv[1]).resolve()
spec = importlib.util.spec_from_file_location('scan_source', scanner)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
versions = {t['name']: t['version'] for t in json.loads(scanner.with_name('scanners.lock.json').read_text())['tools']}
# Filename checks precede all filesystem reads, even for tracked sensitive paths.
with tempfile.TemporaryDirectory(prefix='sensitive-path-fixture-') as directory:
    root = Path(directory)
    names = ['.aws/config', '.ssh/config', '.config/gh/hosts.yml',
             'nested/auth/settings.json', '.azure/settings.json',
             'keys/server.pem.bak', 'keys/id_ed25519.backup',
             '.yarnrc.yml', 'pip.ini', 'nested/mytoken.txt']
    with mock.patch.object(module, 'source_paths', return_value=names), \
         mock.patch.object(module, 'read_regular', side_effect=AssertionError('sensitive read')):
        selected, omitted = module.snapshot(root, root / 'snapshot')
    assert not selected and len(omitted) == len(names), (selected, omitted)
    assert all(item['reason'] == 'authentication filename' for item in omitted), omitted
with tempfile.TemporaryDirectory(prefix='security-fixture-') as directory:
    base = Path(directory)
    repo = base / 'repo with spaces'
    repo.mkdir()
    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
    (repo / 'hello.py').write_text('print("tracked original")\n')
    (repo / 'credentials.json').write_text('SYNTHETIC_AUTH_DO_NOT_COPY')
    (repo / '.npmrc').write_text('SYNTHETIC_AUTH_DO_NOT_COPY')
    (repo / 'deleted.py').write_text('deleted later')
    subprocess.run(['git', '-C', str(repo), 'add', '--', 'hello.py', 'credentials.json', '.npmrc', 'deleted.py'], check=True)
    (repo / 'hello.py').write_text('print("dirty current worktree")\n')
    (repo / 'deleted.py').unlink()
    (repo / 'untracked.py').write_text('MUST_NOT_COPY')
    outside = base / 'outside'
    outside.mkdir()
    (outside / 'private.py').write_text('MUST_NOT_READ')
    (repo / 'link.py').symlink_to(outside / 'private.py')
    subprocess.run(['git', '-C', str(repo), 'add', '--', 'link.py'], check=True)
    (repo / 'nested').mkdir()
    (repo / 'nested/private.py').write_text('was source')
    subprocess.run(['git', '-C', str(repo), 'add', '--', 'nested/private.py'], check=True)
    (repo / 'nested/private.py').unlink()
    (repo / 'nested').rmdir()
    (repo / 'nested').symlink_to(outside)
    snap = base / 'snapshot'
    snap.mkdir()
    selected, omitted = module.snapshot(repo, snap)
    assert [entry['path'] for entry in selected] == ['hello.py'], selected
    assert 'dirty current worktree' in (snap / 'hello.py').read_text()
    assert not (snap / 'credentials.json').exists()
    assert not (snap / '.npmrc').exists()
    assert not (snap / 'untracked.py').exists()
    assert not (snap / 'link.py').exists()
    assert len(omitted) == 5, omitted
    # Remove deliberately partial sources before testing successful orchestration.
    subprocess.run(['git', '-C', str(repo), 'update-index', '--force-remove', '--', 'link.py', 'deleted.py', 'nested/private.py'], check=True)
    (repo / '.github/workflows').mkdir(parents=True)
    (repo / '.github/workflows/test.yml').write_text('name: inert\non: push\njobs: {}\n')
    (repo / 'example.sh').write_text('#!/bin/bash\nprintf "%s\\n" fixture\n')
    subprocess.run(['git', '-C', str(repo), 'add', '--', '.github/workflows/test.yml', 'example.sh'], check=True)
    tools = base / 'tools'
    tools.mkdir()
    for name in ['git', 'python3']:
        (tools / name).symlink_to(shutil.which(name))
    for name in ['gitleaks', 'shellcheck', 'zizmor', 'osv-scanner']:
        tool = tools / name
        tool.write_text('#!' + sys.executable + '\n'
                        'import os,sys\n'
                        f'name={name!r}\nversion={versions[name]!r}\n'
                        'if sys.argv[1:] in (["--version"],["version"]):\n print(version);sys.exit(0)\n'
                        'with open(os.environ["TEST_LOG"],"a") as f: f.write(name+"\\n")\n'
                        'print("SYNTHETIC_VALUE_MUST_NOT_APPEAR_IN_SUMMARY")\n'
                        'sys.exit(int(os.environ.get("TEST_"+name.upper().replace("-","_"),"0")))\n')
        tool.chmod(0o700)
    environment = os.environ.copy()
    environment['PATH'] = str(tools)
    environment['TEST_LOG'] = str(base / 'calls')

    def invoke(label, **variables):
        env = dict(environment, **variables)
        output = base / label
        result = subprocess.run([sys.executable, str(scanner), str(repo), '--output', str(output)], env=env, text=True, capture_output=True)
        assert 'SYNTHETIC_VALUE' not in result.stdout + result.stderr
        assert output.stat().st_mode & 0o077 == 0
        return result, json.loads((output / 'summary.json').read_text())

    result, summary = invoke('pass')
    assert result.returncode == 0, (result.stderr, summary)
    assert all(check['state'] == 'pass' for check in summary['checks'])
    result, summary = invoke('finding', TEST_GITLEAKS='1', TEST_ZIZMOR='12')
    assert result.returncode != 0
    assert sum(c['state'] == 'findings' for c in summary['checks']) == 2
    assert any(c['name'] == 'shellcheck' for c in summary['checks'])
    result, summary = invoke('tool-error', TEST_GITLEAKS='2')
    assert any(c['name'] == 'gitleaks' and c['state'] == 'tool-error' for c in summary['checks'])
    gitleaks_stub = tools / 'gitleaks'
    original_stub = gitleaks_stub.read_text()
    gitleaks_stub.write_text(original_stub.replace(versions['gitleaks'], '0.0.0'))
    result, summary = invoke('wrong-version')
    assert any(c['name'] == 'gitleaks' and c['state'] == 'incomplete' for c in summary['checks'])
    gitleaks_stub.write_text(original_stub)
    (tools / 'shellcheck').unlink()
    result, summary = invoke('missing')
    assert result.returncode != 0
    assert any(c['name'] == 'shellcheck' and c['state'] == 'incomplete' for c in summary['checks'])
    (repo / 'requirements.txt').write_text('example==1.0\n')
    subprocess.run([str(tools / 'git'), '-C', str(repo), 'add', '--', 'requirements.txt'], check=True)
    result, summary = invoke('no-database')
    assert any(c['name'] == 'osv-scanner' and c['state'] == 'incomplete' for c in summary['checks'])
    database = base / 'stale-db'
    database.mkdir()
    (database / 'refreshed-at.json').write_text('{"completed_unix":0}')
    result = subprocess.run([sys.executable, str(scanner), str(repo), '--output', str(base / 'stale'), '--osv-db', str(database)], env=environment, text=True, capture_output=True)
    summary = json.loads((base / 'stale/summary.json').read_text())
    assert any(c['name'] == 'osv-scanner' and c['state'] == 'incomplete' for c in summary['checks'])
if os.environ.get('SECURITY_TEST_REAL_GITLEAKS') == '1':
    actual = shutil.which('gitleaks')
    assert actual, 'Requested real Gitleaks acceptance test but binary is absent'
    with tempfile.TemporaryDirectory(prefix='gitleaks-suppression-fixture-') as directory:
        base = Path(directory)
        repo = base / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        # Deliberately fictional high-entropy value, never a service credential.
        fictional = ''.join(('vKfAq7H2L8mN5rP9', 'sW3xY6zB0cD4eF1g'))
        (repo / 'example.py').write_text('api_key = "' + fictional + '" # gitleaks:allow\n')
        (repo / '.gitleaks.toml').write_text('[extend]\nuseDefault = true\n[allowlist]\nregexes = [".*"]\n')
        subprocess.run(['git', '-C', str(repo), 'add', '--', 'example.py', '.gitleaks.toml'], check=True)
        unhardened = subprocess.run([actual, 'dir', '--no-banner', '--redact=100', str(repo)], cwd=repo, capture_output=True)
        assert unhardened.returncode == 0, 'Control should demonstrate repository/inline suppression'
        hardened = subprocess.run([sys.executable, str(scanner), str(repo), '--output', str(base / 'result')], capture_output=True)
        summary = json.loads((base / 'result/summary.json').read_text())
        assert hardened.returncode != 0
        assert any(c['name'] == 'gitleaks' and c['state'] == 'findings' for c in summary['checks'])
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
                        'commit', '-qm', 'inert suppression fixture'], check=True)
        history = scanner.with_name('scan-history.sh')
        result = subprocess.run(['bash', str(history), str(repo)], capture_output=True)
        assert result.returncode == 1, 'History scanner must detect the fictional value despite repository and inline allows'
    print('PASS: actual source/history Gitleaks cannot suppress fixture using repository config or inline allow comment')
print('PASS: private scope, dirty source, authentication/untracked exclusion, symlinks, independent checks, findings, errors and missing scanners/database')
PY
