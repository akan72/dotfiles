#!/usr/bin/env python3
"""One sensitive-source filename policy shared by exports and private scans."""
import pathlib
import re

SENSITIVE_COMPONENT = re.compile(r'(token|credential|secret|private[-_]?key|auth[.](json|toml|ya?ml|ini))', re.I)
SENSITIVE_DIRS = {'.ssh', '.aws', '.azure', '.gnupg', '.kube', '.docker', '.npm',
                  '.password-store', 'gcloud', 'gh', 'hub', 'keychains', 'auth', 'authentication', 'oauth'}
SENSITIVE_NAMES = {'.npmrc', 'npmrc', '.yarnrc', '.yarnrc.yml', '.pypirc', '.netrc',
                   '_netrc', '.s3cfg', '.boto', 'nuget.config', 'pip.conf', 'pip.ini', '.git-credentials', '.gitconfig.local',
                   'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519', 'authorized_keys'}


def validate_source_path(name):
    rel = pathlib.PurePosixPath(name)
    if (not rel.parts or rel.is_absolute() or '..' in rel.parts or any(part.lower() == '.git' for part in rel.parts)
            or str(rel) != name or any(ord(c) < 32 or ord(c) == 127 for c in name)):
        raise SystemExit('unsafe source path')
    for part in rel.parts:
        lower = part.lower()
        if (lower.startswith('.env') or lower in SENSITIVE_DIRS or lower in SENSITIVE_NAMES
                or SENSITIVE_COMPONENT.search(part) or lower.endswith('.tfvars.json')
                or any(lower.startswith(key + '.') for key in ('id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519'))
                or set(pathlib.PurePosixPath(lower).suffixes) & {'.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.tfvars'}):
            raise SystemExit('sensitive-named source path refused: ' + name)
    return rel
