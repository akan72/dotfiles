#!/usr/bin/env python3
"""Private tracked-source security checks. No installers, resolution or network."""
import argparse
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import tempfile
import time

export = runpy.run_path(str(Path(__file__).with_name("source-snapshot.py")))["export"]
LOCK_NAMES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock",
              "bun.lock", "bun.lockb", "uv.lock", "poetry.lock", "Cargo.lock", "go.sum",
              "Gemfile.lock", "composer.lock", "packages.lock.json"}


def run(command, environment=None, cwd=None):
    try:
        return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, env=environment, cwd=cwd)
    except OSError:
        return subprocess.CompletedProcess(command, 127, stdout=b"", stderr=b"Cannot execute tool")


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
    selected, omitted = export(repo, snap, working=True, scan=True)
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

    def record(name, state, note, code=None):
        checks.append({"name": name, "state": state, "note": note, "exit_code": code})

    def check(name, command, finding_codes=(1,), version=True):
        binary = shutil.which(command[0])
        if not binary:
            record(name, "incomplete", "Required scanner is not installed")
            return
        if version:
            result = run([binary, "version" if name == "gitleaks" else "--version"], scanner_environment, snap)
            expected = versions[name]
            if result.returncode or not re.search(r"(?<![\d.])" + re.escape(expected) + r"(?![\d.])", (result.stdout + result.stderr).decode(errors="replace")):
                record(name, "incomplete", "Scanner version differs from reviewed lock: " + expected)
                return
        result = run([binary, *command[1:]], scanner_environment, snap)
        state = "pass" if result.returncode == 0 else "findings" if result.returncode in finding_codes else "tool-error"
        report_name = "gitleaks-redacted.json" if name == "gitleaks" else f"{name}-{len(checks) + 1}.log"
        record(name, state, "See " + report_name, result.returncode)
        # Never print scanner diagnostics or retain unredacted Gitleaks process output.
        if name != "gitleaks":
            (out / report_name).write_bytes(result.stdout + result.stderr)

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
        check("zsh", ["/bin/zsh", "-f", "-n", str(snap / name)], version=False)
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
                scanner_environment["OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY"] = str(args.osv_db.absolute())
                check("osv-scanner", command)
    else:
        record("osv-scanner", "pass", "Not applicable: no supported dependency files in tracked-source scope")
    report = {"schema_version": 2, "repository": str(repo), "selected": selected,
              "omitted": omitted, "checks": checks}
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    counts = {state: sum(c["state"] == state for c in checks) for state in ["pass", "findings", "incomplete", "tool-error"]}
    print(json.dumps({"output": str(out), "states": counts}))
    return 0 if all(check["state"] == "pass" for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
