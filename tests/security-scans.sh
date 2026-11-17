#!/bin/bash
# All scanner processes here are inert stubs; no dependencies are installed.
set -euo pipefail
test_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 -I -S -B - "$test_dir/../scripts/security/scan-source.py" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

scanner = Path(sys.argv[1]).resolve()
versions = {t['name']: t['version'] for t in json.loads(scanner.with_name('scanners.lock.json').read_text())['tools']}
MARKER = 'SYNTHETIC_AUTH_DO_NOT_COPY'


def git(repo, *args):
    subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                    '-c', 'commit.gpgsign=false', *args], check=True, capture_output=True)


def states(summary, name):
    return {c['state'] for c in summary['checks'] if c['name'] == name}


with tempfile.TemporaryDirectory(prefix='security-fixture-') as directory:
    base = Path(directory)
    repo = base / 'repo with spaces'
    repo.mkdir()
    repo = repo.resolve()
    git(repo, 'init', '-q')
    (repo / 'hello.py').write_text('print("tracked original")\n')
    (repo / '.github/workflows').mkdir(parents=True)
    (repo / '.github/workflows/test.yml').write_text('name: inert\non: push\njobs: {}\n')
    (repo / 'example.sh').write_text('#!/bin/bash\nprintf "%s\\n" fixture\n')
    git(repo, 'add', '--', 'hello.py', '.github/workflows/test.yml', 'example.sh')
    (repo / 'hello.py').write_text('print("dirty current worktree")\n')
    # Untracked files are never read or handed to a scanner, whatever their names.
    (repo / 'untracked.sh').write_text('#!/bin/bash\n' + MARKER + '\n')
    (repo / '.github/workflows/untracked.yml').write_text(MARKER)
    (repo / 'untracked-credentials.json').write_text(MARKER)
    tools = base / 'tools'
    tools.mkdir()
    # scan-history.sh, which runs Gitleaks, also needs these standard tools.
    for name in ['git', 'python3', 'bash', 'env', 'mktemp', 'mkdir', 'rm']:
        (tools / name).symlink_to(shutil.which(name))
    for name in ['gitleaks', 'shellcheck', 'zizmor', 'osv-scanner']:
        tool = tools / name
        tool.write_text('#!' + sys.executable + '\n'
                        'import json,os,sys\n'
                        f'name={name!r}\nversion={versions[name]!r}\n'
                        'if sys.argv[1:] in (["--version"],["version"]):\n print(version);sys.exit(0)\n'
                        'with open(os.environ["TEST_LOG"],"a") as f: f.write(json.dumps([name,*sys.argv[1:]])+"\\n")\n'
                        'print("SYNTHETIC_VALUE_MUST_NOT_APPEAR_IN_SUMMARY")\n'
                        'sys.exit(int(os.environ.get("TEST_"+name.upper().replace("-","_"),"0")))\n')
        tool.chmod(0o700)
    environment = os.environ.copy()
    environment['PATH'] = str(tools)
    environment['TEST_LOG'] = str(base / 'calls')

    def invoke(label, *extra, **variables):
        output = base / label
        Path(environment['TEST_LOG']).write_text('')
        result = subprocess.run([sys.executable, str(scanner), str(repo), '--output', str(output), *extra],
                                env=dict(environment, **variables), text=True, capture_output=True)
        assert 'SYNTHETIC' not in result.stdout + result.stderr
        assert output.stat().st_mode & 0o077 == 0
        for path in output.rglob('*'):
            assert path.stat().st_mode & 0o077 == 0, path
            assert path.is_dir() or MARKER.encode() not in path.read_bytes(), path
        calls = [json.loads(line) for line in Path(environment['TEST_LOG']).read_text().splitlines()]
        assert not any(word in arg for call in calls for arg in call for word in ['untracked', 'credentials', '.npmrc', 'outside']), calls
        return result, json.loads((output / 'summary.json').read_text()), calls

    result, summary, calls = invoke('pass')
    assert result.returncode == 0, (result.stderr, summary)
    assert all(check['state'] == 'pass' for check in summary['checks'])
    assert summary['schema_version'] == 3
    assert summary['selected'] == ['.github/workflows/test.yml', 'example.sh', 'hello.py'], summary['selected']
    gitleaks_calls = [call for call in calls if call[0] == 'gitleaks']
    assert sorted(call[2].split('=')[0] for call in gitleaks_calls) == ['--log-opts', '--pre-commit', '--staged'], gitleaks_calls
    assert all({'--ignore-gitleaks-allow', '--redact=100'} <= set(call) and call[-1] != str(repo) for call in gitleaks_calls)
    assert ['zizmor', str(repo / '.github/workflows/test.yml')] == [calls[3][0], calls[3][-1]], calls
    assert any(call[0] == 'shellcheck' and call[-1] == str(repo / 'example.sh') for call in calls)

    (repo / 'credentials.json').write_text(MARKER)
    (repo / '.npmrc').write_text(MARKER)
    git(repo, 'add', '--', 'credentials.json', '.npmrc')
    result, summary, calls = invoke('sensitive')
    assert result.returncode != 0 and states(summary, 'sensitive-path') == {'findings'}
    assert next(c['paths'] for c in summary['checks'] if c['name'] == 'sensitive-path') == ['.npmrc', 'credentials.json']
    assert states(summary, 'scope') == {'pass'}
    git(repo, 'rm', '-q', '--cached', '--', 'credentials.json', '.npmrc')

    outside = base / 'outside'
    outside.mkdir()
    (outside / 'source.py').write_text('# outside the repository\n')
    (repo / 'nested').mkdir()
    (repo / 'nested/source.py').write_text('# replaced parent\n')
    (repo / 'missing.py').write_text('# inert missing source\n')
    (repo / 'link.sh').symlink_to('example.sh')
    git(repo, 'add', '--', 'nested/source.py', 'missing.py', 'link.sh')
    shutil.rmtree(repo / 'nested')
    (repo / 'nested').symlink_to(outside)
    (repo / 'missing.py').unlink()
    git(repo, 'update-index', '--assume-unchanged', '--', 'hello.py')
    result, summary, calls = invoke('partial-scope')
    assert result.returncode != 0 and states(summary, 'scope') == {'incomplete'}
    assert sorted(entry['path'] for entry in summary['omitted']) == ['hello.py', 'link.sh', 'missing.py', 'nested/source.py'], summary
    git(repo, 'update-index', '--no-assume-unchanged', '--', 'hello.py')
    git(repo, 'update-index', '--force-remove', '--', 'nested/source.py', 'missing.py', 'link.sh')

    result, summary, calls = invoke('finding', TEST_GITLEAKS='1', TEST_ZIZMOR='12')
    assert result.returncode != 0
    assert sum(c['state'] == 'findings' for c in summary['checks']) == 4, summary
    result, summary, calls = invoke('tool-error', TEST_GITLEAKS='2')
    assert all(states(summary, 'gitleaks-' + mode) == {'tool-error'} for mode in ['history', 'staged', 'unstaged'])
    gitleaks_stub = tools / 'gitleaks'
    original_stub = gitleaks_stub.read_text()
    gitleaks_stub.write_text(original_stub.replace(versions['gitleaks'], '0.0.0'))
    result, summary, calls = invoke('wrong-version')
    assert all(states(summary, 'gitleaks-' + mode) == {'incomplete'} for mode in ['history', 'staged', 'unstaged'])
    assert not any(call[0] == 'gitleaks' for call in calls)
    gitleaks_stub.write_text(original_stub)
    shellcheck_stub = tools / 'shellcheck'
    shellcheck_stub.write_text('#!/nonexistent/inert-interpreter\n')
    result, summary, calls = invoke('unexecutable')
    assert result.returncode != 0
    assert 'pass' not in states(summary, 'shellcheck') and states(summary, 'zizmor') == {'pass'}
    (tools / 'shellcheck').unlink()
    result, summary, calls = invoke('missing')
    assert result.returncode != 0 and states(summary, 'shellcheck') == {'incomplete'}
    (repo / 'requirements.txt').write_text('example==1.0\n')
    git(repo, 'add', '--', 'requirements.txt')
    result, summary, calls = invoke('no-database')
    assert states(summary, 'osv-scanner') == {'incomplete'}
    database = base / 'osv-db'
    database.mkdir()
    for label, receipt in [('stale', {'completed_unix': 0}), ('fresh', {'completed_unix': time.time()}),
                           ('future', {'completed_unix': time.time() + 86400}), ('invalid', {})]:
        (database / 'refreshed-at.json').write_text(json.dumps(receipt))
        result, summary, calls = invoke(label, '--osv-db', str(database))
        assert states(summary, 'osv-scanner') == {'pass' if label == 'fresh' else 'incomplete'}, (label, summary)
        assert (label == 'fresh') == (['--lockfile', str(repo / 'requirements.txt')] == calls[-1][-2:]), calls
    (repo / 'unlocked').mkdir()
    (repo / 'unlocked/pyproject.toml').write_text('[project]\nname="inert"\nversion="1.0"\n')
    git(repo, 'add', '--', 'unlocked/pyproject.toml')
    result, summary, calls = invoke('unlocked')
    assert result.returncode != 0 and states(summary, 'dependency-scope') == {'incomplete'}

if os.environ.get('SECURITY_TEST_REAL_GITLEAKS') == '1':
    actual = shutil.which('gitleaks')
    assert actual, 'Requested real Gitleaks acceptance test but binary is absent'
    with tempfile.TemporaryDirectory(prefix='gitleaks-suppression-fixture-') as directory:
        base = Path(directory)
        repo = base / 'repo'
        repo.mkdir()
        git(repo, 'init', '-q')
        # Deliberately fictional high-entropy values, never service credentials.
        values = {'history': 'vKfAq7H2L8mN5rP9' + 'sW3xY6zB0cD4eF1g', 'merge': 'qW8eR4tY2uI6oP0a' + 'sD3fG7hJ1kL5zX9c',
                  'staged': 'mN3bV7cX1zL5kJ9h' + 'gF2dS6aP0oI4uY8t', 'unstaged': 'zT6yU1iO5pA9sD3f' + 'Gh7jK2lQ4wE8rN0m',
                  'typechange': 'bH4nJ8mK2lP6oI0u' + 'yT5rE9wQ3aS7dF1g'}
        leak = {label: f'api_key = "{value}" # gitleaks:allow\n' for label, value in values.items()}
        # Repository-controlled suppressions: config allowlist, binary attributes and (below) fingerprints.
        (repo / '.gitleaks.toml').write_text('[extend]\nuseDefault = true\n[allowlist]\nregexes = [".*"]\n')
        (repo / '.gitattributes').write_text('* -diff\n')
        (repo / 'history.py').write_text('\0\n' + leak['history'])
        (repo / 'staged.py').write_text('# inert\n')
        (repo / 'unstaged.py').write_text('# inert\n')
        (repo / 'typechange.py').symlink_to('staged.py')
        git(repo, 'add', '--', '.gitleaks.toml', '.gitattributes', 'history.py', 'staged.py', 'unstaged.py', 'typechange.py')
        git(repo, 'commit', '-qm', 'inert suppression fixture')
        (repo / 'history.py').write_text('# removed\n')
        (repo / 'typechange.py').unlink()
        (repo / 'typechange.py').write_text(leak['typechange'])
        git(repo, 'commit', '-qam', 'value now only in history; symlink became a file')
        git(repo, 'checkout', '-qb', 'side')
        (repo / 'side.py').write_text('# side\n')
        git(repo, 'add', '--', 'side.py')
        git(repo, 'commit', '-qm', 'side')
        git(repo, 'checkout', '-q', '-')
        git(repo, 'merge', '-q', '--no-ff', '--no-commit', 'side')
        (repo / 'merge.py').write_text(leak['merge'])
        git(repo, 'add', '--', 'merge.py')
        git(repo, 'commit', '-qm', 'value introduced only by a merge')
        (repo / 'staged.py').write_text(leak['staged'])
        git(repo, 'add', '--', 'staged.py')
        (repo / 'unstaged.py').write_text(leak['unstaged'])
        expected = {'history': ['history.py', 'merge.py', 'typechange.py'], 'staged': ['staged.py'], 'unstaged': ['unstaged.py']}

        def hardened(label):
            output = base / label
            result = subprocess.run([sys.executable, str(scanner), str(repo), '--output', str(output)], capture_output=True)
            seen = result.stdout + result.stderr + b''.join(p.read_bytes() for p in output.rglob('*') if p.is_file())
            assert result.returncode != 0 and not any(value.encode() in seen for value in values.values())
            summary = json.loads((output / 'summary.json').read_text())
            reports = {mode: json.loads((output / f'gitleaks-{mode}-redacted.json').read_text()) for mode in expected}
            assert {mode: sorted(f['File'] for f in found) for mode, found in reports.items()} == expected, reports
            assert all(states(summary, 'gitleaks-' + mode) == {'findings'} for mode in expected)
            return [f['Fingerprint'] for found in reports.values() for f in found]

        (repo / '.gitleaksignore').write_text('\n'.join(hardened('before-ignore')) + '\n')
        private = base / 'private'
        private.mkdir()
        (private / 'gitleaks.toml').write_text('[extend]\nuseDefault = true\n')
        (private / 'ignore').write_text('')
        for mode in ['--log-opts=--all --diff-merges=first-parent', '--staged', '--pre-commit']:
            control = subprocess.run([actual, 'git', mode, '--no-banner', '--redact=100', '--ignore-gitleaks-allow',
                                      '--config', str(private / 'gitleaks.toml'), '--gitleaks-ignore-path', str(private / 'ignore'),
                                      str(repo)], cwd=repo, capture_output=True)
            assert control.returncode == 0, 'Control: repository .gitleaksignore/attributes hide values from flag-only hardening'
        hardened('after-ignore')
    print('PASS: real Gitleaks finds history, merge-only, type-changed, staged and unstaged values despite inline allows, repository config, .gitleaksignore and attributes')
print('PASS: private scope, tracked-only reads, sensitive names, symlinks, independent checks, findings, errors and missing scanners/database')
PY
