# Security and maintenance

This is the shared policy for bootstrap, package installs, local scans and
editors. Pins fix bytes; they do not prove that upstream code is benign. Updates
require an explicit review of versions, age, hashes and any available
provenance. One-time host repairs and Python/Packer migrations live in the
separate Mac replication playbook, not the recurring dotfiles installer.

## Bootstrap and release policy

Install Apple's Command Line Tools and a checksum-verified standalone uv first;
the Command Line Tools provide git, `python3`, `curl` and the compilers for the
source builds. Setup never uses Homebrew; only the optional local secret scanners (gitleaks, ShellCheck, OSV-Scanner) still come from it.
Never stream mutable installers into a shell.
Use uv for personal Python projects and tools.

`artifacts.json` under `scripts/security` pins every downloaded tool (see the
[dependency inventory](dependency-signoff.md)) for its explicitly listed platforms. `install-artifact.sh --check TOOL VERSION OS-arch` checks metadata, destinations, receipts and installed hashes
without writing or downloading. Normal installation verifies HTTPS and SHA-256,
rejects unsafe archive paths/links and refuses unmanaged destinations. Missing
platform artifacts have no unchecked fallback. Existing rustup is retained: review its installed
version and the Mac playbook's Rust update commands separately. Pinning rustup-init
does not pin the downstream toolchain downloads.

tmux, mosh and PostgreSQL have no official macOS binaries, so `build-source.sh`
builds them from tarballs pinned by SHA-256 in `sources.json`, with libevent
and protobuf linked in statically and OpenSSL from its own pinned prefix. It keeps the same per-file receipts as
downloaded artifacts. Upgrading any tool means changing its pin.

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
any other version. It is not an installer: on a Mac, install gitleaks, ShellCheck
and OSV-Scanner from Homebrew yourself. Setup does not install them.
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

Before loading any downloaded plugin, `config.trusted-bootstrap` verifies every
active entry in `nvim/lazy-lock.json`: canonical HTTPS origin from
`nvim/plugin-origins.json` (an entry without one is refused), full commit, normal
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
download channels and update checking. Neovim **0.12 or newer** is required.
markdown-preview.nvim is removed: its Node server needed a large npm graph and
localhost-origin hardening. Use Zed's built-in `markdown: open preview` instead.

### Treesitter

Treesitter uses only the parsers and queries bundled with Neovim: C, Lua, Markdown,
query, Vimscript and Vim help. Neovim's ftplugins start highlighting for Lua, Markdown,
help and query; `settings.lua` starts it for C and Vimscript. Other languages keep
Vim's regex syntax. Nothing downloads, compiles or installs a parser.

The nvim-treesitter plugin is removed. Its pin was the archived `master` branch's last
commit, mislabeled `main` in the lock. On 0.12 its Markdown injection query and directive
override the bundled ones and fail, so Markdown code fences and LSP hovers raised
`conceal_line` errors and showed raw fences. The `main` rewrite would download parser
tarballs without checksums and compile native code into `stdpath('data')/site`, outside
every verified checkout, using the `tree-sitter` CLI and a C compiler. The clean-checkout
gate had already kept the old plugin's `parser/` directory empty, so no language loses
Treesitter highlighting. Its downloaded checkout is inactive rollback material.

`tests/editor-startup.lua` asserts that every `parser/*` and `queries/*/*.scm` file on
the runtime path belongs to the Neovim installation. Adding a parser is a reviewed
change: pin its source by SHA-256 in `artifacts.json`, build it outside Neovim, install
it to a dedicated runtime path directory and update that assertion.

### Native LSP, completion and snippets

`nvim-lspconfig` supplies server definitions; native `vim.lsp.config`/`enable`,
`vim.lsp.completion` and `vim.snippet` provide the editor behavior. The six former
LSP/completion/installation wrappers are absent from the active specs, lock and
origin maps. Every remaining active plugin keeps the same reviewed full commit.
Retired downloaded directories are inactive rollback material, not runtime paths.

Only ty, Ruff, Lua, TypeScript and Rust Analyzer are deliberately configured.
Each starts only from its hash-pinned install under `~/.local/share/dotfiles-lsp`,
never from `PATH`, so Mason, Homebrew and rustup copies cannot stand in. A missing
optional tool produces one local notice; `:LspSetupStatus` shows the exact commands
and setup guidance. Opening a buffer never repairs a missing tool by installing it.

TypeScript's automatic typings acquisition is disabled. Its fallback tsserver is
locked TypeScript 5.9.3; an existing trusted project's JavaScript tsserver is honored.
The server executable itself stays the pinned one. Ruff's hover is left to ty. Lua LS
writes its logs and generated definitions to Neovim's cache, so its verified tree
stays unchanged. Rust workspace metadata is queried with `cargo --offline`, rustup automatic
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
contain unrelated data. Every server is pinned by hash: ty and Ruff by the uv lock
(SHA-256 per wheel), TypeScript LS by the npm lock (SHA-512 integrity), and Lua LS
and rust-analyzer by `artifacts.json` (SHA-256). The locks are public source;
installed environments stay outside the checkout. Neither package command installs
a new Python runtime or runs package source builds/lifecycle scripts.

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

The Python lock pins ty 0.0.99 and Ruff 0.17.4, Astral's type checker and linter
servers, resolved on 15 November 2026 with uv's seven-day cutoff (2026-11-08). Both
are prebuilt binary wheels with no dependencies.

The Node lock was resolved on 21 October 2026 with npm's seven-day minimum age,
using TypeScript LS 6.0.2 and TypeScript 5.9.3. ESLint and the VSCode extracted
servers were removed on 15 November 2026 without re-resolving, leaving the remaining
entries unchanged. It contains the complete two-package dependency graph and integrity
hashes. No global npm packages are installed. Node itself is the SHA-256-pinned
v26.13.1 release in `scripts/security/artifacts.json`, which `assimilate.sh`
installs under `~/.local/share/dotfiles-node` and links as `~/.local/bin/node`,
`npm` and `npx`. Neither nvm nor Homebrew Node is used.

```sh
(
  set -eu
  test "$(node --version)" = v26.13.1
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

Lua LS and rust-analyzer are upstream release artifacts installed by
`install-artifact.sh`, which verifies each archive's SHA-256 before unpacking and
keeps a receipt for `--check`. Lua LS 3.19.2 and rust-analyzer 2026-11-02 come from
their projects' GitHub releases; the reviewed digests match GitHub's published ones.
This rust-analyzer is the project's standalone build, the one editor extensions
ship. Rustup's component is not used: it links the toolchain's `librustc_driver`,
and `rustup update` replaces it in place, so it cannot hold a pin. rust-analyzer
still reads the standard library from the toolchain's `rust-src` component, added
from the already installed toolchain's manifest without `rustup update`. It loads
that library as a Cargo workspace, whose `Cargo.lock` pins about 40 crates.io
dependencies (such as `hashbrown` and `object`) that `rust-src` does not ship.
The editor runs Cargo offline, so `cargo fetch --locked` downloads them once here,
checking each against that lockfile's SHA-256; without them, standard-library
types show as `{unknown}` and std hovers are empty. `RUSTC_BOOTSTRAP=1` lets
stable Cargo read the library's manifest, as rust-analyzer itself does. These
crates are the one exception to the dedicated directories: they go to Cargo's
shared cache (`~/.cargo/registry` by default), because rust-analyzer reads project
dependencies from that same cache. Cargo checks each hash only when it downloads
the crate and trusts the unpacked sources afterwards, so the offline recheck below
confirms the crates are present, not that their bytes are unchanged. rust-analyzer
only reads them; their build scripts never run. Records cover Apple Silicon and
Intel Macs and x86_64/aarch64 Linux; other platforms stay optional.

```sh
(
  set -eu
  platform="$(uname -s)-$(uname -m)"
  "$DOTFILES/scripts/security/install-artifact.sh" lua-language-server 3.19.2 "$platform"
  "$DOTFILES/scripts/security/install-artifact.sh" rust-analyzer 2026-11-02 "$platform"
  case "$(rustup --version 2>/dev/null)" in
    'rustup 1.29.2 '*) ;;
    *) echo 'Review/repair Rustup first using the security playbook.' >&2; exit 1 ;;
  esac
  case "$(RUSTUP_AUTO_INSTALL=0 rustc --version)" in
    'rustc 1.91.1 '*|'rustc 1.95.0 '*) ;;
    *) echo 'Review this existing Rust toolchain before adding components.' >&2; exit 1 ;;
  esac
  RUSTUP_AUTO_INSTALL=0 rustup component add rust-src
  library="$(RUSTUP_AUTO_INSTALL=0 rustc --print sysroot)/lib/rustlib/src/rust/library"
  RUSTUP_AUTO_INSTALL=0 RUSTC_BOOTSTRAP=1 cargo fetch --locked --manifest-path "$library/Cargo.toml"
)
```

Later, `install-artifact.sh --check lua-language-server 3.19.2 "$platform"` (and the
same for rust-analyzer) re-verifies the installed bytes offline. Rerunning the
`cargo fetch` line with `--offline` confirms the standard library's crates are
still cached.

Updates are explicit lockfile/package or reviewed `artifacts.json` changes followed
by these same operations and functional tests. Do not use `:Lazy update`,
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
Lua's `vim` global, that every server runs from its pinned install and Lua LS leaves
its tree unchanged, multi-client completion, actual menu acceptance, snippet
navigation, documentation scrolling, key fallbacks, and that servers on `PATH` (here
Mason's) never stand in for missing installs.
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
