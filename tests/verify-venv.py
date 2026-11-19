"""verify-venv.py accepts an untouched locked venv and refuses changed files,
missing or extra packages and RECORD paths outside the venv."""
import base64, hashlib, pathlib, subprocess, sys, tempfile
script = pathlib.Path(__file__).resolve().parent.parent / 'scripts/security/verify-venv.py'


def digest(data):
    return 'sha256=' + base64.urlsafe_b64encode(hashlib.sha256(data).digest()).rstrip(b'=').decode()


def venv(root, record_path='demo/__init__.py', extra=False):
    site = root / 'venv/lib/python3.12/site-packages'
    (site / 'demo').mkdir(parents=True)
    (site / 'demo/__init__.py').write_bytes(b'x = 1\n')
    for name, version in [('demo', '1.0')] + ([('extra', '2.0')] if extra else []):
        dist = site / f'{name}-{version}.dist-info'
        dist.mkdir()
        (dist / 'METADATA').write_text(f'Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n')
        (dist / 'RECORD').write_text(f'{record_path},{digest(b"x = 1" + chr(10).encode())},6\n{dist.name}/RECORD,,\n')
    (root / 'lock.txt').write_text('demo==1.0 \\\n    --hash=sha256:00\n')
    return root / 'venv', root / 'lock.txt'


def run(venv_path, lock):
    return subprocess.run([sys.executable, '-I', str(script), str(venv_path), str(lock)], capture_output=True).returncode


with tempfile.TemporaryDirectory() as d:
    v, lock = venv(pathlib.Path(d))
    assert run(v, lock) == 0, 'untouched venv refused'
    (v / 'lib/python3.12/site-packages/demo/__init__.py').write_bytes(b'x = 2\n')
    assert run(v, lock) != 0, 'changed file accepted'
for case in ({'extra': True}, {'record_path': '../../../../outside.py'}):
    with tempfile.TemporaryDirectory() as d:
        root = pathlib.Path(d)
        (root / 'outside.py').write_bytes(b'x = 1\n')
        v, lock = venv(root, **case)
        assert run(v, lock) != 0, 'unsafe venv accepted: ' + str(case)
with tempfile.TemporaryDirectory() as d:
    v, lock = venv(pathlib.Path(d))
    lock.write_text('demo==1.0\nmissing==3.0\n')
    assert run(v, lock) != 0, 'missing package accepted'
print('verify-venv: untouched venv accepted; changed files, extra/missing packages and escaping RECORD paths refused')
