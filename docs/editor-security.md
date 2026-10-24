# Security and maintenance

This is the shared policy for bootstrap, package installs, local scans, editors
and the optional notebook. Pins fix bytes; they do not prove that upstream code
is benign. Updates require an explicit review of versions, age, hashes and any
available provenance. One-time host repairs and Python/Packer migrations live in
the separate Mac replication playbook, not the recurring dotfiles installer.

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
rewritten. Before network Git operations, check the selected helper and username
without reading credentials; missing HTTPS routing stops the operation.

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

The final line gives a private output directory and counts. `summary.json` lists
checks and selected/omitted paths. Exit 0 requires every applicable check to pass;
findings, missing/changed scanners, partial source, stale/missing databases and tool
errors return nonzero. Schema 2 removes per-check timestamps, version/command
copies and parsed diagnostic aggregation. Scanner-native reports stay private:
Gitleaks JSON is fully redacted; other tools' `.log` files can contain source.
Never publish raw reports. Directories/files are 0700/0600; remove the output
when no longer needed.

`source-snapshot.py` is the single exporter for scans and container tests. Scans
read current tracked, allowlisted source, including edits. They omit auth-named
paths before reading contents, plus untracked/ignored files, binaries and symlinks.
Missing/symlink/nonregular tracked source or unsafe paths make coverage incomplete.
Container exports instead refuse unsafe names/state, default to clean HEAD, and
require `--working` plus individual `--include` paths for proposed/new source.
Both use descriptor-relative reads without following links; neither modifies the
Git index/object database. Exports carry deterministic file hashes, executable flags and HEAD/mode
metadata; verification also accepts prior schema-1 snapshots. Git export filters
cannot omit or transform source. See [container commands](../README.md#container-installation-tests).

Checks are Gitleaks, offline zizmor, ShellCheck without external sources, `zsh -n`
and offline OSV for supported dependency locks. No install, build, resolution,
autofix, project execution or network scan occurs. Private scanner configuration
ignores repository/user suppressions; history is separate via
`scripts/security/scan-history.sh`. Gitleaks is maintenance-only and pattern-based;
static checks do not prove that software or this Mac is free of malware.

`scanners.lock.json` records reviewed versions and artifacts; the runner refuses
version drift. It is not a cross-platform installer. Homebrew's signed API and
bottle checksums trust Homebrew; upstream attestations were not verified. Other
platforms need matching artifact review. CI's pre-commit/zizmor wheel locks require
hashes, binary wheels and no dependency resolution; preserve the exact documented
virtualenv security exception. The portable Mac playbook has installation commands.
Review scanner pins monthly and scan weekly; nothing schedules automatic updates.

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

Before loading any downloaded plugin, `config.trusted-bootstrap` verifies every
active entry in `nvim/lazy-lock.json`: canonical HTTPS origin, full commit, normal
checkout root, and clean tracked, untracked and ignored files. The only generated
file exception is the exact non-executable regular `doc/tags` help index with a
non-symlink parent. Unknown Lua, symlink checkouts and other ignored changes fail
closed. Lazy itself must match the explicitly reviewed stage-zero commit
`85c7ff3711b730b4030d03144f6db6375044ae82` before it is required. This is a local
integrity/drift check, not a sandbox against another process running as your user.

Startup begins with native plugin loading disabled. After all plugin integrity and
Packer checks pass, it restricts `packpath` to the built-in runtime and enables
loading for lazy setup. The pinned lazy manager then disables automatic native
loading again while loading the verified plugins itself.

Startup disables missing-plugin installation, project-local lazy specs, package/rock
download channels, update checking and Treesitter parser installs. Neovim **0.12 or
newer** is required. The existing Treesitter release still uses
`nvim-treesitter.configs.setup`; highlighting remains enabled for existing parsers.
Markdown preview remains disabled until its separate binary artifacts are reviewed.

### Native LSP, completion and snippets

`nvim-lspconfig` supplies server definitions; native `vim.lsp.config`/`enable`,
`vim.lsp.completion` and `vim.snippet` provide the editor behavior. The six former
LSP/completion/installation wrappers are absent from the active specs, lock and
origin maps. Every remaining active plugin keeps the same reviewed full commit.
Retired downloaded directories are inactive rollback material, not runtime paths.

Only Jedi, Lua, TypeScript, ESLint and Rust Analyzer are deliberately configured.
External executables are resolved explicitly, with Mason paths and rustup's
runtime-downloading proxy refused. A missing optional tool produces one local
notice; `:LspSetupStatus` shows the exact commands and setup guidance. Opening a
buffer never repairs a missing tool by installing it.

TypeScript's automatic typings acquisition is disabled. Its fallback tsserver is
locked TypeScript 5.9.3; an existing trusted project's JavaScript tsserver is honored.
ESLint similarly honors an installed project ESLint library, with locked ESLint
10.12.0 as fallback. Their server executables remain external, and the implicit
`yarn exec` wrapper is disabled. ESLint still executes trusted project lint
configuration as part of its normal function; these settings are not a project-code
sandbox. Rust workspace metadata is queried with `cargo --offline`, rustup automatic
installation is disabled in server processes, and automatic build-script/procedural
macro execution and check-on-save builds are disabled. Those Rust analysis features
need a separately deliberate project policy if required.

Native completion uses server trigger characters and explicit **Ctrl-Space**;
it does not request completions after every letter. **Tab/Shift-Tab** select menu
items; outside a menu they indent/outdent. **Enter** accepts an explicitly selected
item; an unselected menu or no menu inserts a newline. Native LSP snippets use
**Ctrl-f/Ctrl-b** to move forward/backward through placeholders. **Ctrl-j/Ctrl-k**
scroll the native completion documentation popup, retaining normal key behavior
when no popup exists. The menu uses native styling with at most five visible items,
not the former bordered completion windows. Semantic highlighting stays disabled.

Definition/declaration/implementation/type-definition/references remain on
`gd/gD/gi/go/gr`; hover/signature/line diagnostics on `K/gs/gl`; rename/format/actions
on `F2/F3/F4`; diagnostics on `[d`/`]d`. Existing user mappings are preserved.
The commented leader-key examples in the old configuration were not active bindings.

### Explicit external server setup

Complete the Mac security playbook first, including patched Node/Rustup and the
existing uv-managed Python. Use these dedicated directories only; stop if they
contain unrelated data. The frozen uv lock and npm integrity lock are public source;
installed environments stay outside the checkout. Neither command installs a new
Python runtime or runs package source builds/lifecycle scripts.

```sh
export DOTFILES="$HOME/dotfiles"
export LSP_HOME="$HOME/.local/share/dotfiles-lsp"
(
  set -eu
  for path in "$HOME/.local" "$HOME/.local/share" "$LSP_HOME" "$LSP_HOME/python" "$LSP_HOME/node"; do
    test ! -L "$path" || { echo "Review symlinked setup path: $path" >&2; exit 1; }
  done
  uv python find --managed-python --no-python-downloads 3.12.15
  UV_MALWARE_CHECK=1 UV_PROJECT_ENVIRONMENT="$LSP_HOME/python" uv --no-config sync \
    --project "$DOTFILES/nvim/lsp/python" --frozen --no-build \
    --no-python-downloads --managed-python --python 3.12.15 \
    --default-index https://pypi.org/simple
)
```

The Node lock was resolved on 21 October 2026 with npm's seven-day minimum age,
using TypeScript LS 6.0.2, TypeScript 5.9.3, VSCode extracted servers 4.10.0 and
ESLint 10.12.0. It contains the complete 111-package dependency graph and integrity
hashes. No global npm packages are installed. Use the reviewed Node26.12.1 for this
recorded recipe; review a successor explicitly rather than downgrading an existing
newer patched runtime.

```sh
(
  set -eu
  test "$(node --version)" = v26.12.1
  test ! -L "$LSP_HOME/node"
  mkdir -p "$LSP_HOME/node"
  cp "$DOTFILES/nvim/lsp/node/package.json" "$DOTFILES/nvim/lsp/node/package-lock.json" "$LSP_HOME/node/"
  stage="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-lsp-npm.XXXXXX")"
  trap 'rm -rf "$stage"' EXIT
  touch "$stage/user.npmrc" "$stage/global.npmrc"
  export NPM_CONFIG_USERCONFIG="$stage/user.npmrc" NPM_CONFIG_GLOBALCONFIG="$stage/global.npmrc"
  export NPM_CONFIG_REGISTRY=https://registry.npmjs.org/ NPM_CONFIG_MIN_RELEASE_AGE=7 NPM_CONFIG_IGNORE_SCRIPTS=true
  bash "$DOTFILES/scripts/security/npm-age.sh"
  npm ci --prefix "$LSP_HOME/node" --ignore-scripts --min-release-age=7 --no-audit --no-fund
  npm audit --prefix "$LSP_HOME/node" --omit=dev
)
```

Lua uses the explicitly trusted Homebrew rolling-distribution boundary and a
bottle-only install. The reviewed Apple Silicon bottle was LuaLS3.19.2. The current
formula has no Intel macOS bottle; do not silently source-build on Intel. Leave Lua
optional there until a matching official artifact is reviewed. The Rust component
uses the already installed toolchain's manifest without `rustup update`; it does
not replace project environments or install a second compiler. The audited Mac
uses stable1.91.1; the existing bootstrap's reviewed fresh-toolchain target is1.95.0.

```sh
(
  set -eu
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)
      HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 \
      HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1 \
        brew install --force-bottle lua-language-server ;;
    Darwin-x86_64) echo 'Lua LS optional: review an Intel artifact; no source-build fallback.' ;;
    *) echo 'Review the matching platform package before installing Lua LS.' ;;
  esac
  case "$(uname -m)" in
    arm64) toolchain=stable-aarch64-apple-darwin ;;
    x86_64) toolchain=stable-x86_64-apple-darwin ;;
    *) exit 2 ;;
  esac
  case "$(rustup --version 2>/dev/null)" in
    'rustup 1.29.2 '*) ;;
    *) echo 'Review/repair Rustup first using the security playbook.' >&2; exit 1 ;;
  esac
  case "$(RUSTUP_AUTO_INSTALL=0 rustup run "$toolchain" rustc --version)" in
    'rustc 1.91.1 '*|'rustc 1.95.0 '*) ;;
    *) echo 'Review this existing Rust toolchain before adding components.' >&2; exit 1 ;;
  esac
  RUSTUP_AUTO_INSTALL=0 rustup component add rust-analyzer rust-src --toolchain "$toolchain"
  analyzer="$(RUSTUP_AUTO_INSTALL=0 rustup which --toolchain "$toolchain" rust-analyzer)"
  mkdir -p "$HOME/.local/bin"
  link_lsp() {
    target="$1"; name="$2"; dest="$HOME/.local/bin/$name"
    test -f "$target" && test -x "$target"
    if test -L "$dest" && test "$(readlink "$dest")" = "$target"; then return; fi
    if test -e "$dest" || test -L "$dest"; then echo "Review existing launcher: $dest" >&2; return 1; fi
    ln -s "$target" "$dest"
  }
  link_lsp "$LSP_HOME/python/bin/jedi-language-server" jedi-language-server
  link_lsp "$LSP_HOME/node/node_modules/.bin/typescript-language-server" typescript-language-server
  link_lsp "$LSP_HOME/node/node_modules/.bin/vscode-eslint-language-server" vscode-eslint-language-server
  link_lsp "$analyzer" rust-analyzer
)
```

Updates are explicit lockfile/package changes followed by these same native package
manager operations and functional tests. Do not use `:Lazy update`, `:TSUpdate`,
unversioned `npx`, `uv run` or an installer wrapper to repair startup. The shared
bootstrap installs only reviewed plugin checkouts; it never launches Neovim to
fetch software.

### Functional and security validation

```sh
python3 -I -S "$DOTFILES/scripts/security/check-editor-state.py"
bash "$DOTFILES/tests/editor-policy.sh"
DOTFILES="$DOTFILES" nvim --headless -i NONE -c 'lua dofile(vim.env.DOTFILES .. "/tests/editor-startup.lua")'
DOTFILES="$DOTFILES" nvim --headless -i NONE -c 'lua dofile(vim.env.DOTFILES .. "/tests/editor-native-lsp.lua")'
```

The first check loads only the local integrity verifier (`-u NONE --noplugin`).
The next checks retain dirty/origin/commit/symlink/Packer gates. The two real-init
checks assert actual theme/native behavior, rather than a clean process exit.
Hosted/VPS acceptance runs the deterministic native UI test without requiring
optional external servers. To include all five installed servers, use a fresh
private fixture directory and deny network on macOS:

```sh
fixtures="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-lsp-tests.XXXXXX")"
DOTFILES="$DOTFILES" DOTFILES_LSP_REAL=1 DOTFILES_LSP_TEST_ROOT="$fixtures" \
  /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  nvim --headless -i NONE -c 'lua dofile(vim.env.DOTFILES .. "/tests/editor-native-lsp.lua")'
```

The test creates only inert public fixtures: no user project or authentication
configuration is read. It checks external commands, completion/hover/diagnostics,
Lua's `vim` global, multi-client completion, actual menu acceptance, snippet
navigation, documentation scrolling, key fallbacks and missing/Mason-only tools.
The last missing-server case intentionally prints an optional-tool notice.

## Existing legacy Packer state

Normal startup refuses a legacy Packer loader/start directory before plugin code
loads. The one-time quarantine/restore utility and its fixtures belong to the
separate Mac replication kit, not the dotfiles runtime. Close Neovim and follow
that kit's Packer migration section with an explicit `--repo` path; it plans
first, checks the reviewed loader hash, refuses custom entries and preserves
rollback data. Do not delete or execute an unknown generated loader to bypass
this guard.

## tmux and shell updates

TPM's runtime install/update bindings are removed. `tmux-powerline.sh` verifies the
reviewed checkout before running `powerline.sh left|right`; failures render
`powerline unverified` without executing the plugin. It never invokes `main.tmux`,
which would overwrite the guarded status commands. Both tmux paths assume
`$HOME/dotfiles`; change them deliberately for another location. OMZ updates/prompts
are disabled. Update pins explicitly and test with `bash tests/tmux-policy.sh`.
These local integrity checks detect drift; they do not isolate hostile processes
already running as your user.

## Notebook helper

The optional helper binds only `127.0.0.1:8888`, runs as UID 1000 without extra
capabilities, and retains Jupyter token authentication. Mount only the helper
directory, never home/auth directories or the Docker socket. Verify host write
ownership; Docker Desktop differs from native Linux.

The Dockerfile pins the multiarch Python image digest and signed Debian CA repair;
`filter-ca-bundle.py` rejects the three distrusted SPKIs in both system/certifi
bundles. Keep that gate even if a patched APT version leaves its live mirror:
review its successor instead of bypassing signatures. The CA package and certifi
2026.10.19 are documented urgent cooldown exceptions. The wheel-only, hash-required
lock covers 93 packages on both Linux architectures. The pandas 2-to-3 upgrade
still requires testing your own notebooks.

Refresh only after reviewing supported direct versions, the official image digest
and dated exceptions; ordinary deployment must not silently regenerate locks:

```sh
cd "$HOME/dotfiles"
uv --no-config pip compile scripts/docker/requirements.in --generate-hashes --only-binary=:all: --python-version 3.12 --python-platform x86_64-unknown-linux-gnu --exclude-newer 2026-10-14T00:00:00Z --exclude-newer-package certifi=2026-10-21T23:59:59Z --output-file /private/tmp/notebook-amd64.txt
uv --no-config pip compile scripts/docker/requirements.in --generate-hashes --only-binary=:all: --python-version 3.12 --python-platform aarch64-unknown-linux-gnu --exclude-newer 2026-10-14T00:00:00Z --exclude-newer-package certifi=2026-10-21T23:59:59Z --output-file /private/tmp/notebook-arm64.txt
diff -u <(tail -n +3 /private/tmp/notebook-amd64.txt) <(tail -n +3 /private/tmp/notebook-arm64.txt)
cd scripts/docker
docker compose config --quiet
docker buildx build --platform linux/arm64 --load -f Dockerfile.notebook -t dotfiles-notebook:reviewed .
docker run --rm --network none --entrypoint id dotfiles-notebook:reviewed -u
```

Intel uses `linux/amd64`; metadata/wheel checks do not prove another CPU's image
ran. Launch deliberately with `docker compose up --build`, inspect port bindings
without logging tokens, then stop with `docker compose down`. Keep Docker updated;
old engines have localhost-publication caveats.

## Host settings

Keep laptop FileVault on and automatic login off. The separate
[headless Mini availability exception](mac-mini-setup-guide.md#availability-and-security-trade-off)
weakens physical protection. Tailscale cannot unlock the same host's encrypted
startup disk; test an independent supported recovery path before remote reboots.
