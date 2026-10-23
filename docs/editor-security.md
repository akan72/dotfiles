# Reviewed editor and notebook tooling

Opening Neovim or tmux does not install or update software. Updates are separate,
reviewed changes to commits, release hashes and dependency locks. A matching pin
prevents unexpected movement; it is not proof that the pinned source is benign.

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

TPM's runtime loader/update bindings are removed. Both powerline status commands
call `scripts/security/tmux-powerline.sh`, which uses the shared read-only checkout
verifier against `https://github.com/erikw/tmux-powerline` at
`6079ace8d534a01d4d964b8b854b223f72edaf4b` before executing `powerline.sh` with an
allowlisted `left`/`right` argument. It never invokes `main.tmux`, which would
replace the guarded status commands. Failed verification renders `powerline
unverified` and executes no plugin. The default deployment path is `$HOME/dotfiles`;
change both status command paths deliberately if you keep this repo elsewhere.

```sh
bash "$HOME/dotfiles/tests/tmux-policy.sh"
bash "$HOME/dotfiles/scripts/security/tmux-powerline.sh" left
bash "$HOME/dotfiles/scripts/security/tmux-powerline.sh" right
```

Oh My Zsh's automatic update and update prompt are explicitly disabled; the
bootstrap's reviewed commit remains the update boundary. Review/install new pins
periodically and make explicit urgent security exceptions rather than freezing
software indefinitely. Git checks at every status render favor drift detection
and may add a small cost; they do not isolate hostile same-user processes.

## Notebook helper

The optional helper stays unstarted until explicitly built. Its host port is
`127.0.0.1:8888`, it runs as UID 1000 with no extra capabilities, and Jupyter token
authentication remains enabled. Only this helper directory is bind-mounted; never
add home, SSH/auth directories or the Docker socket. Docker Desktop's filesystem
ownership mapping differs from native Linux; verify write ownership per host.

The base is the official multiarch Python 3.12.15 slim-bookworm image, immutable
index digest `sha256:6a0e06f5ba0b373d051aabd3fffb9b873f27f9a2a3a14bcbe37dee6f0e3bbc70`.
Registry platform manifests are:

- Linux amd64: `sha256:57d96f71de145a98e7ceca18ee4ade77bba4103a33a72dfaea026b23625c6bf0`.
- Linux arm64/v8: `sha256:c3729439afc4ec3f3e159e0c86aeabfadac8030ef46838a0256383d0511c5f5e`.

The Dockerfile installs the exact signed Debian security package
`ca-certificates=20250419~deb12u2`, then checks both system and pinned certifi bundles
for the three distrusted SPKI hashes using `filter-ca-bundle.py`. A missing patched
package or remaining key makes the build fail. The helper is an exact copy of the
portable Mac incident helper (SHA-256
`14821de1e90f83a354160627da0a422a01480b0ffac35664aa9aee273b2ca1d2`).
[Debian's live tracker](https://security-tracker.debian.org/tracker/source-package/ca-certificates)
confirms the bookworm security version. This urgent trust repair and certifi
2026.10.19 are explicit exceptions to the ordinary seven-day age window.

`requirements.txt` locks 93 packages with SHA-256 hashes. pip accepts only wheels
and requires every hash. The two Linux architecture resolutions matched exactly.
The reviewed direct versions are Notebook 7.6.3, pandas 3.0.6 and certifi 2026.10.19;
the old pandas 2.0.1 helper was upgraded, so existing notebooks still need their
own functional check. uv's generated dependency audit covered 96 universal
packages and returned zero known vulnerabilities/adverse statuses on 2026-10-21.
This is not a claim that scanners can rule out unknown malware.

To refresh, first review supported direct versions and the official image digest.
Use the verified uv installation. These were the exact resolution flags; both
commands access public package metadata and execute no source builds:

```sh
cd "$HOME/dotfiles"
uv --no-config pip compile scripts/docker/requirements.in --generate-hashes --only-binary=:all: --python-version 3.12 --python-platform x86_64-unknown-linux-gnu --exclude-newer 2026-10-14T00:00:00Z --exclude-newer-package certifi=2026-10-21T23:59:59Z --output-file /private/tmp/notebook-amd64.txt
uv --no-config pip compile scripts/docker/requirements.in --generate-hashes --only-binary=:all: --python-version 3.12 --python-platform aarch64-unknown-linux-gnu --exclude-newer 2026-10-14T00:00:00Z --exclude-newer-package certifi=2026-10-21T23:59:59Z --output-file /private/tmp/notebook-arm64.txt
diff -u <(tail -n +3 /private/tmp/notebook-amd64.txt) <(tail -n +3 /private/tmp/notebook-arm64.txt)
```

Do not silently refresh these dates/versions or replace the committed lock during
ordinary deployment. A future release review updates cutoff dates and checks any
necessary security exception by exact package/version. The signed Debian package
can eventually leave a live mirror; review its successor rather than bypassing
APT signature checks or the SPKI gate.

To validate/build deliberately after the Mac trust repair, without launching a
service or mounting personal notebooks:

```sh
cd "$HOME/dotfiles/scripts/docker"
docker compose config --quiet
docker buildx build --platform linux/arm64 --load -f Dockerfile.notebook -t dotfiles-notebook:reviewed .
docker run --rm --network none --entrypoint id dotfiles-notebook:reviewed -u
```

Intel laptops use `--platform linux/amd64`. A cross-platform metadata/wheel check
is not evidence that the other CPU's image was built or run. To launch only when
needed, `docker compose up --build` retains generated token authentication; do not
capture tokens in audit logs or disable auth. Check Docker's published binding
with an inspection format that prints only port bindings, and stop with
`docker compose down` afterward. Docker Desktop/Engine itself must be supported
and updated; old Engine releases have localhost publication caveats.

## Host settings

Keep laptop FileVault enabled and automatic login disabled. A headless Mac Mini
availability exception must stay an explicit separate decision. Tailscale cannot
unlock the same host's encrypted startup volume. Apple Silicon/macOS 26+ supports
an SSH FileVault unlock path using macOS Remote Login plus independent networking;
that differs from a Tailscale-only profile with Remote Login disabled. Test any
independent recovery path before a remote reboot.
