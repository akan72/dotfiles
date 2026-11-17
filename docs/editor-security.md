# Security and maintenance

This is the shared policy for bootstrap, package installs, local scans and
editors. Pins fix bytes; they do not prove that upstream code is benign. Updates
require an explicit review of versions, age, hashes and any available
provenance. One-time host repairs and Python/Packer migrations live in the
separate Mac replication playbook, not the recurring dotfiles installer.

## Bootstrap and release policy

Install Apple's Command Line Tools, a reviewed official Homebrew release and a
checksum-verified standalone uv first; preflight also needs `jq`, `python3` and `curl`.
Never stream mutable installers into a shell. Use uv for personal Python projects/tools; retain Apple's Python and
Homebrew Python required by formula dependencies.

`artifacts.json` under `scripts/security` pins delta, gcloud, Linux Neovim and
rustup-init for its explicitly listed platforms. `install-artifact.sh --check TOOL VERSION OS-arch` checks metadata, destinations, receipts and installed hashes
without writing or downloading. Normal installation verifies HTTPS and SHA-256,
rejects unsafe archive paths/links and refuses unmanaged destinations. Missing
platform artifacts have no unchecked fallback; Intel delta uses a separately
reviewed Homebrew install. Existing rustup is retained: review its installed
version and the Mac playbook's Rust update commands separately. Pinning rustup-init
does not pin the downstream toolchain downloads.

Homebrew is a trusted rolling distribution. Setup disables automatic updates,
dependent upgrades and cleanup for its bundle commands. `brew bundle --no-upgrade`
does not lock first installs or patch existing packages. Review `brew outdated --json=v2` and upgrade selected packages separately. The Brewfile's Terraform
exception trusts only that named formula; it does not install uv.

Plugin checkouts require their approved origin, full commit, exact repository
root and no tracked, untracked or ignored changes. GitHub's optional `.git` suffix
is accepted. A valid checkout works offline; other state is left for explicit
backup/review. OMZ caches belong outside its checkout at
`${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh`. Powerline alone permits machine-local
HTTPS userinfo while preserving exact repository identity; routing is never
rewritten. Pinned repositories are public, so bootstrap fetches them anonymously:
the fetch ignores this machine's Git config, and no credential helper, URL rewrite
or prompt takes part. Checkout pins live in `scripts/security/pins.sh`, and
Neovim plugin origins in `nvim/plugin-origins.json`, each used by every check.

## Package policy and Socket

Keep the committed seven-day uv/Bun cooldowns. npm >=11.19 is required;
`scripts/security/npm-age.sh` checks the effective setting and preserves stricter
numeric values. Project/environment settings can override these defaults, so
check each installation context. Bun config is linked at both
`~/.config/.bunfig.toml` and `~/.bunfig.toml`; `python3 -I -S tests/bun-age.py` tests
its native resolution using inert loopback releases. Lockfiles, Git dependencies,
Homebrew and native updaters do not inherit registry cooldowns. Review independent
updaters separately. For urgent fixes, verify the exact artifact/advisory and use
a temporary version-specific exception, then restore the cooldown.

For reviewed npm projects, begin with `npm ci --ignore-scripts`; approve required
build scripts explicitly. For already locked uv projects, these checks are online
and send dependency identifiers to OSV, but do not upload source:

```sh
uv audit --locked --no-build --no-python-downloads --project /absolute/reviewed/project
uv tool audit --all --no-python-downloads
```

Audit support is preview functionality in the reviewed uv. Missing tool lock
metadata is incomplete coverage. `UV_MALWARE_CHECK=1` covers supported uv sync
operations; it does not protect every package manager or detect unknown malware.

Socket installation is explicit via `scripts/security/install-socket.sh`, not
part of assimilation. The reviewed Free binary is unsigned and requires telemetry.
When its guarded `~/.local/bin/sfw` exists, shared Bash/Zsh settings automatically
wrap interactive npm, Bun and uv. Scripts/absolute paths bypass aliases;
private/custom registries are unsupported and unknown/unscanned/cached releases
have gaps. Bun passed local fixtures but lacks Socket Free's guaranteed support.
The guard checks the pinned binary and repaired CA bundle, enforces TLS validation
and discards inherited Node preload options. Keep this guard while the embedded
runtime still contains the distrusted roots; cooldowns and script restrictions
remain necessary. Never migrate CLI authentication or generated editor code into
this repository; copy application settings only by reviewed app name, with apps closed.

## Local scans

Run from a reviewed checkout; the scanner itself executes as your user:

```sh
scripts/security/scan-local.sh "$HOME/dotfiles" --osv-db /absolute/private/osv-db
```

The final line gives a private output directory and counts; `summary.json` lists
each check and the selected and omitted paths. Exit 0 requires every applicable
check to pass; findings, missing or changed scanners, incomplete scope, stale or
missing databases and tool errors return nonzero. Reports stay private (0700/0600):
Gitleaks JSON is fully redacted, but other tools' `.log` files can contain source,
so never publish them and remove the output when done.

The scan reads tracked files in place and never reads untracked or ignored files.
A tracked file with a credential-like name fails the scan, without its contents
being read; symlinks, nonregular files and unsafe names make the scope incomplete.
Checks are Gitleaks, offline zizmor, ShellCheck without external sources, `zsh -n`
and offline OSV for supported dependency locks. No install, build, resolution,
autofix, project execution or network scan occurs, and repository or user scanner
configuration is ignored.

Gitleaks runs through `scripts/security/scan-history.sh`, which CI also runs: all
history, then staged and unstaged edits. Nothing in the repository can hide a
finding: its Gitleaks config, `.gitleaksignore`, inline allows and diff attributes
are ignored, and merge-only or type-changed content is scanned. It reads diffs,
so a secret split across separate commits may be missed. Gitleaks is
pattern-based; static checks do not prove that software or this Mac is free of malware.

`scanners.lock.json` records the reviewed scanner versions; the runner refuses
any other version. It is not an installer: Homebrew supplies the Mac scanners.
CI's pre-commit and zizmor wheel locks require hashes and binary wheels and do not
resolve dependencies. CI's Pre-commit job is a required check, but its Gitleaks
hook only scans staged changes; the Secret history job scans every commit. Review
scanner pins monthly and scan weekly; nothing schedules automatic updates.

Refresh OSV separately: this downloads public databases, never source or a project
dependency list. Include every required ecosystem; this repo uses PyPI and npm.
Only write a freshness receipt after every archive has downloaded and validated:

```sh
(
  set -eu
  umask 077
  db="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-security/osv-db"
  for ecosystem in PyPI npm; do
    mkdir -p "$db/osv-scalibr/$ecosystem"
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
      "https://osv-vulnerabilities.storage.googleapis.com/$ecosystem/all.zip" -o "$db/osv-scalibr/$ecosystem/all.zip.pending"
  done
  python3 -I -S - "$db" <<'PY'
import hashlib, json, os, pathlib, sys, time, zipfile
root = pathlib.Path(sys.argv[1])
pending = {name: root / 'osv-scalibr' / name / 'all.zip.pending' for name in ['PyPI', 'npm']}
for path in pending.values():
    with zipfile.ZipFile(path) as archive:
        if not archive.namelist() or archive.testzip() is not None:
            raise SystemExit('Invalid database archive; freshness was not updated')
hashes = {}
for name, path in pending.items():
    target = path.with_suffix('')
    os.replace(path, target)
    hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
(root / 'refreshed-at.json').write_text(json.dumps({'completed_unix': time.time(), 'ecosystems': list(pending), 'sha256': hashes}) + '\n')
PY
  scripts/security/scan-local.sh "$HOME/dotfiles" --osv-db "$db"
)
```

The receipt must be at most seven days old; use `--max-db-age-hours 24` during an
incident. This is a completed-download record, not an upstream signature. Missing
ecosystems fail in OSV. `--offline-vulnerabilities` is insufficient because other
features may access the network; the runner uses `--offline`.

## Neovim

Startup verifies every active lock entry before loading plugins: origin (from
`nvim/plugin-origins.json`), commit, clean checkout and the reviewed stage-zero
lazy commit. A lock entry without a reviewed origin is refused. Only a regular,
non-executable generated `doc/tags` with non-symlink parents is allowed. Packer's
legacy loader/start directory is refused; use the separate playbook's reversible
migration rather than deleting/executing an unknown loader.

Native plugin loading starts disabled; after verification, `packpath` is limited
to the built-in runtime for lazy setup. Missing-plugin installs, project-local
specs, rock/package channels, update checking, Mason refresh/server installs and
Treesitter parser installs stay disabled. Existing parsers/highlighting remain.
Mason starts only the five configured, already installed server types; receipts
are inventory, not a complete dependency hash lock. Markdown preview's unverified
binary installer stays disabled. Review external servers/parsers separately;
`:Lazy update`, `:MasonUpdate` and `:TSUpdate` are not startup repairs.

```sh
python3 -I -S "$HOME/dotfiles/scripts/security/check-editor-state.py"
bash "$HOME/dotfiles/tests/editor-policy.sh"
DOTFILES="$HOME/dotfiles" nvim --headless -i NONE -c 'lua dofile(vim.env.DOTFILES .. "/tests/editor-startup.lua")'
```

The first command loads only the verifier with `-u NONE --noplugin`; the last
loads the real init and asserts theme/LSP behavior and disabled download channels.
To test an existing Python server, set `DOTFILES_EDITOR_EXPECT_PYTHON_LSP=1` and
`DOTFILES_EDITOR_TEST_FILE` to a fresh absolute temporary `.py` path. No server is installed.

## tmux and shell updates

TPM is no longer installed or loaded. `tmux-powerline.sh` verifies the
reviewed checkout before running `powerline.sh left|right`; failures render
`powerline unverified` without executing the plugin. It never invokes `main.tmux`,
which would overwrite the guarded status commands. Both tmux paths assume
`$HOME/dotfiles`; change them deliberately for another location. OMZ updates/prompts
are disabled. Update pins explicitly and test with `bash tests/tmux-policy.sh`.
These local integrity checks detect drift; they do not isolate hostile processes
already running as your user.

## Host settings

Keep laptop FileVault on and automatic login off. The separate
[headless Mini availability exception](mac-mini-setup-guide.md#availability-and-security-trade-off)
weakens physical protection. Tailscale cannot unlock the same host's encrypted
startup disk; test an independent supported recovery path before remote reboots.
