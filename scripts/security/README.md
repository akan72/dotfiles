# Local security checks

Run from a reviewed checkout; the scanner scripts themselves execute as your user:

```sh
scripts/security/scan-local.sh "$HOME/dotfiles"
```

The final line gives a private output directory and state counts. Exit 0 means all applicable checks passed. Any finding, missing/changed scanner, missing/stale OSV database or tool error returns nonzero. Read `summary.json` for per-check status and coverage. Scanner diagnostic text is never printed by the wrapper; Gitleaks uses a private configuration extending built-in rules, an empty private ignore file, and disables inline allow comments; its JSON report uses full redaction; other scanners' JSON diagnostics stay private and may contain source context. Do not publish those raw reports. Reports and the temporary source snapshot remain mode 0700/0600; delete the output directory after review if you do not need it.

This command reads current **tracked source**, including tracked edits. It excludes untracked/ignored files, Git history, filenames associated with credentials, `.npmrc`, `.env*`, private keys, binary formats and symlinks. The private snapshot is never sourced, built or installed. A skipped symlink/deleted tracked source is marked incomplete. Other omissions are recorded by path and reason. An authentication filename exclusion can also omit source such as `gh-auth-refresh.sh`; review that code separately without reading its credential files. A source allowlist is a scope boundary, not a complete filesystem or malware audit.

Checks run independently: Gitleaks for secret patterns; zizmor offline with configuration and inline suppressions disabled for Actions; ShellCheck without external sources or user configuration for recognized sh/bash sources; `zsh -n` for zsh; OSV offline for supported tracked lockfiles and requirements. No dependency installation, project build, plugin load, package resolution, Git fetch, fix or online scanner request is performed. ShellCheck does not understand zsh. zizmor online audits and Git history are outside this command's scope. Gitleaks' maintenance-only status and pattern coverage do not make it a malware detector.

## Reviewed tool installation

`scanners.lock.json` records tested versions and the actual Apple Silicon/macOS bottle digests. Homebrew core's signed API is an explicitly trusted distribution path; its bottle checksum is not upstream provenance verification. This manifest is a review record and version check, not a universal installer: other platforms must review the matching bottle before installation. Do not silently accept a changed version or claim `brew pin` locks every download. Review release age (normally seven days), publisher, hashes and available attestations when updating it. The combined portable Mac playbook contains the installation commands and verified zizmor wheel URLs for both Mac architectures.

The baseline uses Gitleaks 8.30.1, ShellCheck 0.11.0, OSV-Scanner 2.7.0 and zizmor 1.29.0. zizmor's three approved wheel hashes are recorded; its release metadata declares no Python dependencies. Use uv with an existing managed Python, `--no-python-downloads --no-build --no-index --no-deps`, and the locally SHA-256-verified wheel. Do not bootstrap scanners using unversioned `npx`, `pipx run`, curl-to-shell or quarantine deletion. Socket is optional; its Free Mac binary is unsigned, telemetry is mandatory, and unknown/unscanned/cached releases have gaps. It is not installed automatically.

CI installs pre-commit in an isolated environment from `requirements-pre-commit-linux-py312.txt`, a complete eleven-package wheel hash lock for Ubuntu 24.04 x86_64/Python 3.12. Corresponding official PyPI publication times, filenames and hashes are in the metadata JSON. Every artifact was older than seven days when reviewed on 2026-10-21. `--require-hashes --only-binary=:all: --no-deps` prevents fallback source builds and unlisted dependency resolution; `pip check` verifies the installed dependency graph. CI's separate zizmor wheel lock also uses hash enforcement. Updating a top-level version alone is insufficient. Existing full checkout action pins, read-only job permissions and disabled persisted Git credentials are retained.

## Offline vulnerability database

OSV database refresh is a separate, explicitly online operation. It downloads public ecosystem databases, not your source or dependency list. This repository's Python and Node locks require both PyPI and npm. Add ecosystems for other projects rather than stamping a partial database complete:

```sh
(
  set -eu
  umask 077
  db="$HOME/.cache/dotfiles-osv"
  for ecosystem in PyPI npm; do
    mkdir -p "$db/osv-scalibr/$ecosystem"
    curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
      "https://osv-vulnerabilities.storage.googleapis.com/$ecosystem/all.zip" \
      --output "$db/osv-scalibr/$ecosystem/all.zip.new"
  done
  python3 -I -S - "$db" <<'OSV_REFRESH'
import hashlib, json, os, pathlib, sys, time, zipfile
root = pathlib.Path(sys.argv[1])
pending = {name: root / 'osv-scalibr' / name / 'all.zip.new' for name in ['PyPI', 'npm']}
for path in pending.values():
    with zipfile.ZipFile(path) as archive:
        if not archive.namelist() or archive.testzip() is not None:
            raise SystemExit('Invalid database archive; freshness was not updated')
hashes = {}
for name, path in pending.items():
    target = path.with_suffix('')
    os.replace(path, target)
    hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
receipt = {'completed_unix': time.time(), 'ecosystems': ['PyPI', 'npm'], 'sha256': hashes}
(root / 'refreshed-at.json').write_text(json.dumps(receipt) + '\n')
OSV_REFRESH
  scripts/security/scan-local.sh "$HOME/dotfiles" --osv-db "$db"
)
```

The wrapper accepts an explicit refresh receipt no older than seven days; use `--max-db-age-hours 24` during an incident. The receipt records a completed download, not an upstream signature or completeness guarantee. OSV itself returns an error if a necessary database is missing. The scan uses `--offline`, not `--offline-vulnerabilities`, because the latter can permit other online features. Known advisories do not identify all malicious new packages. Review full transitive lockfiles and package installation scripts as well.

## Python and package policy

For a trusted, already locked uv project, these are separate **online** checks that send dependency identifiers to OSV. They do not upload source; do not run against an unreviewed checkout:

```sh
uv audit --locked --no-build --no-python-downloads --project /absolute/reviewed/project
uv tool audit --all --no-python-downloads
```

Audit support is preview functionality in the reviewed uv version. Old tool environments lacking lock metadata are an incomplete check until deliberately reinstalled, not a clean result. Keep `UV_MALWARE_CHECK=1` for covered uv sync operations, but it is a known-malware lookup, not a universal pip/pipx/npm control. Keep npm/Bun/uv cooldowns and verify effective settings on each machine. For npm projects start with `npm ci --ignore-scripts`; run only reviewed package build scripts explicitly. Do not set a machine-wide lifecycle-script exception without reviewing the affected projects. A verified urgent security patch can justify an exact, documented, temporary release-age exception.

Run local checks weekly and review scanner/tool pins monthly. No scheduler installs or fixes packages automatically. Use container scanners only for actual container images; do not add overlapping products merely to increase tool count. Run `bash tests/security-scans.sh` after changing this wrapper: its processes are inert stubs testing scope/privacy, dirty tracked content, symlinks, status aggregation, missing tools, version mismatches and missing/stale databases. Static scanner success is not proof that this Mac or an installer is uncompromised.

## Scope of this directory

Keep ongoing scanner, artifact, package-policy, source-snapshot and editor/tmux
integrity checks here. One-time Python environment migration and Packer quarantine
utilities (and their dedicated fixtures) live in the separate Mac replication kit.
The superseded global-tool preservation workflow is retired; use uv's native
version selection and isolated tools rather than recreating legacy global graphs.

`tests/clone-pinned.sh` covers local checkout integrity and disposable CI routing.
`tests/source-snapshot.py` covers HEAD/working exports, omitted local state,
manifests and sensitive-path guards; there is no second snapshot fixture suite.
