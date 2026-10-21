#!/usr/bin/env bash
# Install reviewed Socket Firewall Free without executing it, root or shell hooks.
set -euo pipefail
security_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
/usr/bin/python3 -I -S - "$security_dir/socket-artifacts.json" "$@" <<'PY'
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import struct
import subprocess
import sys
import tempfile


def no_links(path):
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError('Symlinked installation parent refused')


def identity(info):
    return tuple(getattr(info, name) for name in ('st_dev','st_ino','st_size','st_mtime_ns','st_ctime_ns','st_uid','st_mode'))


def read_regular(path):
    no_links(path)
    directory = open_directory(path.parent)
    try:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
    finally:
        os.close(directory)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode):
            raise ValueError('Expected a regular file')
        data = stream.read()
        if identity(os.fstat(stream.fileno())) != identity(before):
            raise ValueError('File changed while reading')
        return data


def open_directory(path, create=False):
    descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for name in path.absolute().parts[1:]:
            if create:
                try:
                    os.mkdir(name, mode=0o700, dir_fd=descriptor)
                except FileExistsError:
                    pass
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        if os.fstat(descriptor).st_uid != os.getuid():
            raise ValueError('Installation directory must be owned by this user')
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def validate_manifest(manifest, architecture, now):
    version = manifest['version']
    if version != '1.15.4' or manifest['minimum_age_days'] != 7:
        raise ValueError('Only the reviewed version and minimum age are accepted')
    published = datetime.datetime.fromisoformat(manifest['published_at'].replace('Z', '+00:00'))
    if (now - published).total_seconds() < 7 * 86400:
        raise ValueError('Release is younger than seven days')
    record = manifest['artifacts'][architecture]
    expected_url = 'https://github.com/SocketDev/sfw-free/releases/download/v1.15.4/sfw-free-macos-' + architecture
    if record['url'] != expected_url or not re.fullmatch('[0-9a-f]{64}', record['sha256']):
        raise ValueError('Unreviewed URL or malformed SHA256')
    return record


def verify(data, record, architecture):
    if hashlib.sha256(data).hexdigest() != record['sha256']:
        raise ValueError('Socket artifact SHA256 mismatch')
    cpu = {'arm64': 0x0100000c, 'x86_64': 0x01000007}[architecture]
    if len(data) < 8 or struct.unpack('<II', data[:8]) != (0xfeedfacf, cpu):
        raise ValueError('Expected the matching 64-bit macOS executable')


def load_ca_bundle(manifest):
    for name in ('/opt/homebrew/etc/ca-certificates/cert.pem', '/usr/local/etc/ca-certificates/cert.pem'):
        path = Path(name)
        if path.exists():
            data = read_regular(path)
            if hashlib.sha256(data).hexdigest() == manifest['ca_sha256']:
                return data
    raise ValueError('Reviewed patched Homebrew CA bundle unavailable; update Homebrew CA data first')


def guard_source(destination, ca, empty, digest, ca_digest):
    return ('''import hashlib,os,stat,sys
from pathlib import Path
BINARY = %r
CA = %r
EMPTY = %r
EXPECTED = %r
EXPECTED_CA = %r
def identity(info):
    return tuple(getattr(info,name) for name in ('st_dev','st_ino','st_size','st_mtime_ns','st_ctime_ns','st_uid','st_mode'))
for path,expected,mode in ((Path(BINARY),EXPECTED,0o755),(Path(CA),EXPECTED_CA,0o644)):
    parent=os.open('/',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    try:
        for component in path.parts[1:-1]:
            child=os.open(component,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=parent)
            os.close(parent);parent=child
        fd=os.open(path.name,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK,dir_fd=parent)
    finally:os.close(parent)
    with os.fdopen(fd,'rb') as stream:
        before=os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_uid!=os.getuid() or stat.S_IMODE(before.st_mode)!=mode:sys.exit('Socket trust file type/owner/mode changed')
        if hashlib.sha256(stream.read()).hexdigest()!=expected or identity(os.fstat(stream.fileno()))!=identity(before):sys.exit('Socket trust file SHA256 changed')
folder=Path(EMPTY)
if folder.is_symlink() or not folder.is_dir() or folder.stat().st_uid!=os.getuid() or stat.S_IMODE(folder.stat().st_mode)!=0o700 or any(folder.iterdir()):sys.exit('Socket empty CA directory changed')
env=dict(os.environ)
env.update(NODE_OPTIONS='--use-openssl-ca',NODE_EXTRA_CA_CERTS=CA,SSL_CERT_FILE=CA,SSL_CERT_DIR=EMPTY,NODE_TLS_REJECT_UNAUTHORIZED='1')
os.execve(BINARY,[BINARY,*sys.argv[1:]],env)
''' % (str(destination),str(ca),str(empty),digest,ca_digest)).encode()


def publish(path, data, mode):
    no_links(path)
    directory=open_directory(path.parent,create=True)
    try:
        try:
            fd=os.open(path.name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode,dir_fd=directory)
        except FileExistsError:
            if read_regular(path)!=data or stat.S_IMODE(path.stat().st_mode)!=mode or path.stat().st_uid!=os.getuid():
                raise ValueError('Existing Socket installation file changed: '+path.name)
            return
        with os.fdopen(fd,'wb') as stream:
            stream.write(data);stream.flush();os.fchmod(stream.fileno(),mode);os.fsync(stream.fileno())
    finally:
        os.close(directory)


def install(manifest, architecture, home, download, ca_loader=load_ca_bundle):
    record=validate_manifest(manifest,architecture,datetime.datetime.now(datetime.timezone.utc))
    if not re.fullmatch('[0-9a-f]{64}',manifest['ca_sha256']):
        raise ValueError('Reviewed public CA digest required')
    home=home.absolute()
    if home!=home.resolve() or '..' in home.parts:
        raise ValueError('Canonical home directory required')
    root=home/'.local/share/socket-firewall/1.15.4'
    destination,ca,empty,guard=root/'sfw',root/'ca-certificates.pem',root/'empty-ca',root/'launch.py'
    launcher=home/'.local/bin/sfw'
    guard_data=guard_source(destination,ca,empty,record['sha256'],manifest['ca_sha256'])
    launcher_data=('#!/bin/sh\nexec /usr/bin/python3 -I -S '+shlex.quote(str(guard))+' "$@"\n').encode()
    for path in (destination,ca,empty,guard,launcher):
        no_links(path)
    if os.path.lexists(launcher) and read_regular(launcher)!=launcher_data:
        raise ValueError('Existing sfw command must be migrated explicitly')
    if os.path.lexists(destination):
        verify(read_regular(destination),record,architecture)
    ca_data=read_regular(ca) if os.path.lexists(ca) else ca_loader(manifest)
    if hashlib.sha256(ca_data).hexdigest()!=manifest['ca_sha256']:
        raise ValueError('Socket public CA bundle digest mismatch')
    if os.path.lexists(destination):
        binary_data=read_regular(destination)
    else:
        binary_data=download(record['url'])
        verify(binary_data,record,architecture)
    publish(destination,binary_data,0o755)
    publish(ca,ca_data,0o644)
    descriptor=open_directory(empty,create=True)
    os.close(descriptor)
    if any(empty.iterdir()):
        raise ValueError('Socket empty CA directory is not empty')
    publish(guard,guard_data,0o600)
    publish(launcher,launcher_data,0o755)
    return {'status':'installed-and-hash-verified','version':manifest['version'],'sha256':record['sha256'],
            'ca_sha256':manifest['ca_sha256'],'destination':str(destination),'launcher':str(launcher),
            'executed':False,'shell_configuration_changed':False,'guarded_tls':True,'embedded_node':'24.21.0'}


def download(url):
    with tempfile.TemporaryDirectory(prefix='socket-download-') as folder:
        target = Path(folder).resolve() / 'sfw'
        subprocess.run(['/usr/bin/curl', '--fail', '--silent', '--show-error', '--location',
                        '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2',
                        '--connect-timeout', '20', '--max-time', '180', url, '-o', str(target)], check=True)
        return read_regular(target)


def main():
    os.umask(0o077)
    if os.getuid() == 0:
        raise ValueError('Install as the owning user, without sudo')
    if sys.platform != 'darwin' or os.uname().machine not in ('arm64', 'x86_64'):
        raise ValueError('This reviewed installer supports Apple Silicon and Intel macOS')
    if len(sys.argv) != 2:
        raise ValueError('No version, URL, digest, HOME or quarantine overrides are accepted')
    manifest = json.loads(read_regular(Path(sys.argv[1]).absolute()))
    print(json.dumps(install(manifest, os.uname().machine, Path.home(), download), indent=2))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print('Socket installation refused: ' + str(error), file=sys.stderr)
        sys.exit(1)
PY
