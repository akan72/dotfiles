#!/usr/bin/env python3
"""Private tracked-source security checks. No installers, resolution or network."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import stat
import subprocess
import tempfile
import time

SOURCE_SUFFIXES = {".sh", ".bash", ".zsh", ".py", ".lua", ".toml", ".yaml", ".yml",
                   ".json", ".jsonc", ".md", ".txt", ".vim", ".conf", ".ini", ".js",
                   ".ts", ".tsx", ".jsx", ".go", ".rs", ".lock"}
SOURCE_NAMES = {"assimilate.sh", "bashrc", "bash_profile", "zshrc", "zprofile", "shared.sh",
                "Brewfile", "Dockerfile", "Makefile", "gitconfig", ".gitignore", ".npmrc",
                "go.sum", "go.mod", "config"}
validate_source_path = runpy.run_path(str(Path(__file__).with_name("source-paths.py")))["validate_source_path"]
LOCK_NAMES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock",
              "bun.lock", "bun.lockb", "uv.lock", "poetry.lock", "Cargo.lock", "go.sum",
              "Gemfile.lock", "composer.lock", "packages.lock.json"}


def run(command, environment=None, cwd=None):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, env=environment, cwd=cwd)


def read_regular(repo, parts):
    """Walk with directory descriptors, rejecting symlinks even during replacement races."""
    directory = os.open(repo, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in parts[:-1]:
            next_directory = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=directory)
            os.close(directory)
            directory = next_directory
        fd = os.open(parts[-1], os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        with os.fdopen(fd, "rb") as stream:
            if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
                raise ValueError("nonregular file")
            return stream.read()
    finally:
        os.close(directory)


def source_paths(repo):
    result = run(["git", "-c", "core.fsmonitor=false", "-C", str(repo), "ls-files", "-z"])
    if result.returncode:
        raise ValueError("Cannot enumerate tracked paths")
    return [os.fsdecode(p) for p in result.stdout.split(b"\0") if p]


def snapshot(repo, target):
    selected, omitted = [], []
    for name in source_paths(repo):
        # Use exactly the export policy, before stat/open of any selected file.
        try:
            part = validate_source_path(name)
        except SystemExit as error:
            reason = "unsafe path" if str(error) == "unsafe source path" else "authentication filename"
            omitted.append({"path": name, "reason": reason})
            continue
        if part.suffix not in SOURCE_SUFFIXES and part.name not in SOURCE_NAMES and not part.name.startswith("Dockerfile"):
            omitted.append({"path": name, "reason": "outside source allowlist"})
            continue
        candidate = repo
        try:
            for segment in part.parts:
                candidate = candidate / segment
                mode = candidate.lstat().st_mode
                if stat.S_ISLNK(mode):
                    raise ValueError("symlink")
            if not stat.S_ISREG(mode):
                raise ValueError("nonregular file")
            data = read_regular(repo, part.parts)
        except (OSError, ValueError):
            omitted.append({"path": name, "reason": "missing, symlink or nonregular file"})
            continue
        output = target / name
        output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        output.write_bytes(data)
        output.chmod(0o600)
        selected.append({"path": name, "sha256": hashlib.sha256(data).hexdigest()})
    return selected, omitted


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--osv-db", type=Path, help="Previously refreshed OSV offline database; never downloaded here")
    parser.add_argument("--max-db-age-hours", type=int, default=168)
    args = parser.parse_args()
    os.umask(0o077)
    result = run(["git", "-c", "core.fsmonitor=false", "-C", str(args.repository), "rev-parse", "--show-toplevel"])
    if result.returncode:
        parser.error("repository must be an existing Git worktree")
    repo = Path(os.fsdecode(result.stdout).strip()).resolve()
    if args.output:
        out = args.output.absolute()
        out.mkdir(mode=0o700, parents=True, exist_ok=False)
    else:
        out = Path(tempfile.mkdtemp(prefix="dotfiles-security-"))
    snap = out / "source"
    snap.mkdir(mode=0o700)
    selected, omitted = snapshot(repo, snap)
    private_home = out / "scanner-home"
    private_home.mkdir(mode=0o700)
    scanner_environment = os.environ.copy()
    for key in ("GITLEAKS_CONFIG", "GITLEAKS_CONFIG_TOML", "ZIZMOR_CONFIG", "SHELLCHECK_OPTS"):
        scanner_environment.pop(key, None)
    scanner_environment["HOME"] = str(private_home)
    scanner_environment["XDG_CONFIG_HOME"] = str(private_home / "config")
    scanner_environment["XDG_CACHE_HOME"] = str(private_home / "cache")
    paths = [entry["path"] for entry in selected]
    checks = []
    locks = json.loads(Path(__file__).with_name("scanners.lock.json").read_text())
    versions = {entry["name"]: entry["version"] for entry in locks["tools"]}

    def record(name, state, note, command=None, code=None, version=None):
        checks.append({"name": name, "state": state, "note": note, "command": command,
                       "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                       "exit_code": code, "version": version})

    def check(name, command, finding_codes=(1,), environment=None):
        binary = shutil.which(command[0])
        if not binary:
            record(name, "incomplete", "Required scanner is not installed", command)
            return
        version_result = run([binary, "version"] if name == "gitleaks" else [binary, "--version"], scanner_environment, snap)
        version_text = (version_result.stdout + version_result.stderr).decode(errors="replace")
        expected = versions.get(name)
        if version_result.returncode or not expected or not re.search(r"(?<![\d.])" + re.escape(expected) + r"(?![\d.])", version_text):
            record(name, "incomplete", "Scanner version differs from reviewed lock", command)
            return
        execution = run(command, environment or scanner_environment, snap)
        code = execution.returncode
        # Never echo scanner stdout/stderr: diagnostics can contain source/secret values.
        state = "pass" if code == 0 else "findings" if code in finding_codes else "tool-error"
        record(name, state, "Output suppressed; source and reports stay private", command, code, expected)
        if name != "gitleaks" and execution.stdout:
            try:
                diagnostic = json.loads(execution.stdout)
            except (ValueError, UnicodeDecodeError):
                pass
            else:
                report_name = f"{name}-{len(checks)}.json"
                (out / report_name).write_text(json.dumps(diagnostic, indent=2) + "\n")
                checks[-1]["private_diagnostics"] = report_name

    partial = any(entry["reason"] == "missing, symlink or nonregular file" or entry["reason"] == "unsafe path" for entry in omitted)
    record("scope", "incomplete" if partial else "pass", "Current tracked allowlisted source only; no untracked files or Git history")
    gitleaks_config = out / "gitleaks.toml"
    gitleaks_config.write_text("[extend]\nuseDefault = true\n")
    gitleaks_ignore = out / ".gitleaksignore"
    gitleaks_ignore.write_text("")
    check("gitleaks", ["gitleaks", "dir", "--redact=100", "--no-banner", "--no-color",
                        "--config", str(gitleaks_config), "--gitleaks-ignore-path", str(gitleaks_ignore),
                        "--ignore-gitleaks-allow",
                        "--report-format", "json", "--report-path", str(out / "gitleaks-redacted.json"), str(snap)])
    if any(path.startswith(".github/workflows/") for path in paths):
        check("zizmor", ["zizmor", "--offline", "--strict-collection", "--no-config", "--no-ignores", "--no-progress", "--format", "json", str(snap)], finding_codes=(11, 12, 13, 14))
    else:
        record("zizmor", "pass", "Not applicable: no tracked workflows")
    shell, zsh = [], []
    for name in paths:
        data = (snap / name).read_bytes()
        first = data.split(b"\n", 1)[0].decode(errors="replace")
        if name in {"zshrc", "zprofile"} or name.endswith(".zsh") or re.search(r"^#!.*\bzsh\b", first):
            zsh.append(name)
        elif name in {"bashrc", "bash_profile", "shared.sh"} or re.search(r"^#!.*\b(ba)?sh\b", first):
            shell.append(name)
    if shell:
        # Per-file calls avoid ARG_MAX and preserve independent errors.
        for name in shell:
            check("shellcheck", ["shellcheck", "--norc", "--format=json", str(snap / name)])
    else:
        record("shellcheck", "pass", "No recognized sh/bash sources")
    for name in zsh:
        if not Path("/bin/zsh").exists():
            record("zsh", "incomplete", "zsh is unavailable")
        else:
            execution = run(["/bin/zsh", "-f", "-n", str(snap / name)], scanner_environment, snap)
            record("zsh", "pass" if execution.returncode == 0 else "findings", "Syntax only; source is never loaded", ["/bin/zsh", "-f", "-n", name], execution.returncode)
    dependency_files = [name for name in paths if Path(name).name in LOCK_NAMES or re.fullmatch(r"requirements[^/]*\.txt", Path(name).name)]
    manifests = [name for name in paths if Path(name).name in {"package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile", "composer.json"}]
    unlocked = [name for name in manifests if not any(Path(dependency).parent == Path(name).parent for dependency in dependency_files)]
    if unlocked:
        record("dependency-scope", "incomplete", "Tracked dependency manifests lack a supported lockfile in their directory; no resolution was attempted")
    if dependency_files:
        marker = args.osv_db / "refreshed-at.json" if args.osv_db else None
        if not marker or not marker.is_file():
            record("osv-scanner", "incomplete", "Offline database and explicit freshness receipt required; scan never downloads databases")
        else:
            try:
                receipt = json.loads(marker.read_text())
                age = time.time() - float(receipt["completed_unix"])
                fresh = 0 <= age <= args.max_db_age_hours * 3600
            except (ValueError, KeyError, TypeError):
                fresh = False
            if not fresh:
                record("osv-scanner", "incomplete", "Offline database receipt is invalid or stale")
            else:
                config_path = out / "osv-config.toml"
                config_path.write_text("# No project vulnerability suppressions.\n")
                command = ["osv-scanner", "scan", "source", "--offline", "--format=json",
                           "--no-resolve", "--no-call-analysis=go", "--no-call-analysis=rust",
                           "--config", str(config_path)]
                for name in dependency_files:
                    command += ["--lockfile", str(snap / name)]
                environment = scanner_environment.copy()
                environment["OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY"] = str(args.osv_db.absolute())
                check("osv-scanner", command, environment=environment)
    else:
        record("osv-scanner", "pass", "Not applicable: no supported dependency files in tracked-source scope")
    report = {"schema_version": 1, "created_at": dt.datetime.now(dt.timezone.utc).isoformat(),
              "repository": str(repo), "selected": selected, "omitted": omitted, "checks": checks,
              "limitations": ["No history/untracked files/authentication files", "No install, build, dependency resolution or autofix",
                              "Local static checks do not prove absence of malware", "uv audit is a separate explicitly online operation"]}
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    counts = {state: sum(c["state"] == state for c in checks) for state in ["pass", "findings", "incomplete", "tool-error"]}
    print(json.dumps({"output": str(out), "states": counts}))
    return 0 if all(check["state"] == "pass" for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
