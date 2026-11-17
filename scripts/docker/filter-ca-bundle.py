#!/usr/bin/env python3
"""Check a public CA PEM bundle for distrusted roots; never edits the bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

# Homebrew's incident-patched formula excludes these root public keys:
# https://github.com/Homebrew/homebrew-core/blob/d02b8762f4a29859c47a635a0d2683223fea9812/Formula/c/ca-certificates.rb
EXCLUDED = {
    "bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3",
    "c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9",
    "8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782",
}
CERT = re.compile(rb"-----BEGIN CERTIFICATE-----\s+.*?-----END CERTIFICATE-----", re.S)


def command(openssl, args, data):
    return subprocess.run([openssl] + args, input=data, capture_output=True, check=True).stdout


def inspect_bundle(path, openssl):
    data = path.read_bytes()
    certs = CERT.findall(data)
    if not certs or len(certs) != data.count(b"-----BEGIN CERTIFICATE-----"):
        raise ValueError("Empty or malformed certificate bundle: " + str(path))
    removed = []
    for cert in certs:
        pub = command(openssl, ["x509", "-pubkey", "-noout"], cert)
        der = command(openssl, ["pkey", "-pubin", "-outform", "DER"], pub)
        digest = hashlib.sha256(der).hexdigest()
        if digest in EXCLUDED:
            subject = command(openssl, ["x509", "-subject", "-noout"], cert).decode().strip()
            removed.append({"spki_sha256": digest, "subject": subject})
    if len(removed) == len(certs):
        raise ValueError("Refusing to produce an empty trust bundle")
    return len(certs) - len(removed), removed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--openssl", default="/usr/bin/openssl")
    parser.add_argument("--check", action="store_true", required=True, help="exit 1 if excluded roots are present")
    args = parser.parse_args()
    kept, removed = inspect_bundle(args.input, args.openssl)
    print(json.dumps({"input": str(args.input), "kept": kept, "removed": removed}, indent=2))
    return 1 if removed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print("Bundle check failed: " + str(error), file=sys.stderr)
        sys.exit(2)
