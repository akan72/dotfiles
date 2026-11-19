"""Verify a hash-locked virtual environment offline: exactly the locked packages
are installed, and every file their RECORD lists still has its recorded SHA-256.
usage: verify-venv.py VENV LOCK"""
import base64, csv, hashlib, re, sys
from pathlib import Path


def normal(name):
    return re.sub(r'[-_.]+', '-', name).lower()


def main():
    venv, lock = Path(sys.argv[1]), Path(sys.argv[2])
    wanted = {normal(m.group(1)): m.group(2) for m in
              (re.match(r'^([A-Za-z0-9_.-]+)==([^\s;\\]+)', line) for line in lock.read_text().splitlines()) if m}
    sites = list(venv.glob('lib/python*/site-packages'))
    if len(sites) != 1:
        sys.exit('unexpected venv layout: ' + str(venv))
    site, found = sites[0], {}
    for dist in site.glob('*.dist-info'):
        meta = dict(line.split(': ', 1) for line in (dist / 'METADATA').read_text().splitlines()
                    if ': ' in line and line.split(': ', 1)[0] in ('Name', 'Version'))
        found[normal(meta['Name'])] = meta['Version']
        with (dist / 'RECORD').open(newline='') as record:
            for path, digest, _ in csv.reader(record):
                if not digest:
                    continue  # RECORD itself and generated files carry no hash
                algorithm, value = digest.split('=', 1)
                target = (site / path).resolve()
                if algorithm != 'sha256' or not target.is_relative_to(venv.resolve()):
                    sys.exit('unexpected RECORD entry: ' + path)
                actual = base64.urlsafe_b64encode(hashlib.sha256(target.read_bytes()).digest()).rstrip(b'=').decode()
                if actual != value:
                    sys.exit('installed file changed: ' + path)
    if found != wanted:
        sys.exit('installed packages differ from the lock: ' + str(sorted(set(found.items()) ^ set(wanted.items()))))
    print('verified locked environment: ' + str(venv))


if __name__ == '__main__':
    try:
        main()
    except (OSError, KeyError, ValueError) as error:
        sys.exit(str(error))
