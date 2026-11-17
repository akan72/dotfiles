#!/usr/bin/env python3
"""Private tracked-source security checks. No installers, resolution or network."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import runpy
import shutil
import stat
import subprocess
import tempfile
import time

validate_source_path = runpy.run_path(str(Path(__file__).with_name("source-snapshot.py")))["validate_source_path"]
SOURCE_SUFFIXES = {".sh", ".bash", ".zsh", ".py", ".lua", ".toml", ".yaml", ".yml",
                   ".json", ".jsonc", ".md", ".txt", ".vim", ".conf", ".ini", ".js",
                   ".ts", ".tsx", ".jsx", ".go", ".rs", ".lock"}
SOURCE_NAMES = {"assimilate.sh", "bashrc", "bash_profile", "zshrc", "zprofile", "shared.sh",
                "Brewfile", "Dockerfile", "Makefile", "gitconfig", ".gitignore", "go.sum", "go.mod", "config"}
LOCK_NAMES = {"package-lock.json", "npm-shrinkwrap.json", "pnpm-lock.yaml", "yarn.lock",
              "bun.lock", "bun.lockb", "uv.lock", "poetry.lock", "Cargo.lock", "go.sum",
              "Gemfile.lock", "composer.lock", "packages.lock.json"}
GIT = ["git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null"]
# Gitleaks runs through scan-history.sh, the same hardened invocation CI uses.
GITLEAKS_MODES = [("history", []), ("staged", ["--staged"]), ("unstaged", ["--pre-commit"])]


def run(command, environment=None, cwd=None):
    try:
        return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False, env=environment, cwd=cwd)
    except OSError:
        return subprocess.CompletedProcess(command, 127, stdout=b"", stderr=b"Cannot execute tool")


def regular_file(repo, rel):
    """Every parent must be a real directory and the file itself regular; no link is followed."""
    try:
        modes = [os.lstat(repo.joinpath(*rel.parts[:depth])).st_mode for depth in range(1, len(rel.parts) + 1)]
    except OSError:
        return False
    return all(map(stat.S_ISDIR, modes[:-1])) and stat.S_ISREG(modes[-1])


def select(repo):
    """Classify every tracked name before any file contents are read."""
    listing = run([*GIT, "-C", str(repo), "ls-files", "-z", "-v"], dict(os.environ, GIT_OPTIONAL_LOCKS="0"))
    if listing.returncode:
        raise SystemExit("git ls-files failed")
    tags = {os.fsdecode(entry[2:]): entry[:1].decode() for entry in listing.stdout.split(b"\0")[:-1]}
    selected, omitted, sensitive = [], [], []
    for name, tag in sorted(tags.items()):
        try:
            rel = validate_source_path(name)
        except SystemExit as error:
            if str(error) == "unsafe source path":
                omitted.append({"path": name, "reason": "unsafe path"})
            else:
                sensitive.append(name)
            continue
        if tag in "MS" or tag.islower():
            omitted.append({"path": name, "reason": "unmerged, skip-worktree or assume-unchanged entry"})
        elif rel.suffix not in SOURCE_SUFFIXES and rel.name not in SOURCE_NAMES and not rel.name.startswith("Dockerfile"):
            omitted.append({"path": name, "reason": "outside source allowlist"})
        elif not regular_file(repo, rel):
            omitted.append({"path": name, "reason": "missing, symlink or nonregular file"})
        else:
            selected.append(name)
    return selected, omitted, sensitive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repository", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--osv-db", type=Path, help="Previously refreshed OSV offline database; never downloaded here")
    parser.add_argument("--max-db-age-hours", type=int, default=168)
    args = parser.parse_args()
    os.umask(0o077)
    result = run([*GIT, "-C", str(args.repository), "rev-parse", "--show-toplevel"])
    if result.returncode:
        parser.error("repository must be an existing Git worktree")
    repo = Path(os.fsdecode(result.stdout).strip()).resolve()
    if args.output:
        out = args.output.absolute()
        out.mkdir(mode=0o700, parents=True, exist_ok=False)
    else:
        out = Path(tempfile.mkdtemp(prefix="dotfiles-security-"))
    selected, omitted, sensitive = select(repo)
    private_home = out / "scanner-home"
    private_home.mkdir(mode=0o700)
    scanner_environment = {key: value for key, value in os.environ.items()
                           if key not in {"GITLEAKS_CONFIG", "GITLEAKS_CONFIG_TOML", "ZIZMOR_CONFIG", "SHELLCHECK_OPTS"}}
    scanner_environment.update(HOME=str(private_home), XDG_CONFIG_HOME=str(private_home / "config"),
                               XDG_CACHE_HOME=str(private_home / "cache"))
    checks = []
    locks = json.loads(Path(__file__).with_name("scanners.lock.json").read_text())
    versions = {entry["name"]: entry["version"] for entry in locks["tools"]}
    reviewed = {}

    def record(name, state, note, code=None, **extra):
        checks.append({"name": name, "state": state, "note": note, "exit_code": code, **extra})

    def check(name, command, finding_codes=(1,), tool=None):
        tool = tool or command[0]
        binary = shutil.which(tool)
        if not binary:
            return record(name, "incomplete", "Required scanner is not installed")
        if tool in versions:
            if tool not in reviewed:
                result = run([binary, "version" if tool == "gitleaks" else "--version"], scanner_environment, out)
                output = (result.stdout + result.stderr).decode(errors="replace")
                reviewed[tool] = not result.returncode and re.search(r"(?<![\d.])" + re.escape(versions[tool]) + r"(?![\d.])", output)
            if not reviewed[tool]:
                return record(name, "incomplete", "Scanner version differs from reviewed lock: " + versions[tool])
        result = run([binary, *command[1:]] if command[0] == tool else command, scanner_environment, repo)
        state = "pass" if result.returncode == 0 else "findings" if result.returncode in finding_codes else "tool-error"
        report_name = f"{name}-redacted.json" if tool == "gitleaks" else f"{name}-{len(checks) + 1}.log"
        record(name, state, "See " + report_name, result.returncode)
        # Never print scanner diagnostics or retain unredacted Gitleaks process output.
        if tool != "gitleaks":
            (out / report_name).write_bytes(result.stdout + result.stderr)

    partial = any(entry["reason"] != "outside source allowlist" for entry in omitted)
    record("scope", "incomplete" if partial else "pass",
           "Tracked files only; untracked and ignored files are never read; Gitleaks also covers history and staged/unstaged edits")
    record("sensitive-path", "findings" if sensitive else "pass",
           "Tracked credential-like names; contents are never read or passed to other scanners", paths=sensitive)
    history = Path(__file__).with_name("scan-history.sh")
    for label, mode in GITLEAKS_MODES:
        check("gitleaks-" + label, ["bash", str(history), *mode, "--report", str(out / f"gitleaks-{label}-redacted.json"), str(repo)],
              tool="gitleaks")
    workflows = [name for name in selected if re.fullmatch(r"\.github/workflows/[^/]+\.ya?ml", name)
                 or PurePosixPath(name).name in {"action.yml", "action.yaml"}]
    if workflows:
        check("zizmor", ["zizmor", "--offline", "--strict-collection", "--no-config", "--no-ignores", "--no-progress",
                         "--format", "json", *(str(repo / name) for name in workflows)], finding_codes=(11, 12, 13, 14))
    else:
        record("zizmor", "pass", "Not applicable: no tracked workflows or actions")
    shell, zsh = [], []
    for name in selected:
        first = (repo / name).read_bytes().split(b"\n", 1)[0].decode(errors="replace")
        if name in {"zshrc", "zprofile"} or name.endswith(".zsh") or re.search(r"^#!.*\bzsh\b", first):
            zsh.append(name)
        elif name in {"bashrc", "bash_profile", "shared.sh"} or re.search(r"^#!.*\b(ba)?sh\b", first):
            shell.append(name)
    if shell:
        # Per-file calls avoid ARG_MAX and preserve independent errors.
        for name in shell:
            check("shellcheck", ["shellcheck", "--norc", "--format=json", str(repo / name)])
    else:
        record("shellcheck", "pass", "No recognized sh/bash sources")
    for name in zsh:
        check("zsh", ["/bin/zsh", "-f", "-n", str(repo / name)])
    dependency_files = [name for name in selected if Path(name).name in LOCK_NAMES or re.fullmatch(r"requirements[^/]*\.txt", Path(name).name)]
    manifests = [name for name in selected if Path(name).name in {"package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile", "composer.json"}]
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
                    command += ["--lockfile", str(repo / name)]
                scanner_environment["OSV_SCANNER_LOCAL_DB_CACHE_DIRECTORY"] = str(args.osv_db.absolute())
                check("osv-scanner", command)
    else:
        record("osv-scanner", "pass", "Not applicable: no supported dependency files in tracked-source scope")
    report = {"schema_version": 3, "repository": str(repo), "selected": selected,
              "omitted": omitted, "checks": checks}
    (out / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    counts = {state: sum(c["state"] == state for c in checks) for state in ["pass", "findings", "incomplete", "tool-error"]}
    print(json.dumps({"output": str(out), "states": counts}))
    return 0 if all(check["state"] == "pass" for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
