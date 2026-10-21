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

Startup disables missing-plugin installation,
project-local lazy specs, package/rock download channels, update checking, Mason
registry refresh and language-server installation, and Treesitter parser installs.
The existing Treesitter release uses `nvim-treesitter.configs.setup`; highlighting
remains enabled for existing parsers. Mason's `automatic_enable` allowlist only
starts the five previously configured server types that are already installed.
Mason receipt versions are inventory, not a complete transitive hash lock.
Markdown preview is disabled because its separate binary installer does not verify
reviewed asset hashes. Use another already trusted Markdown preview meanwhile.

The reviewed bootstrap now explicitly checks out active lock entries. It does not
launch Neovim to download or build software. Inspect the proposed pin changes and
Git credential routing before running it; retain normal machine-local credential
helpers and never print their contents. Do not use `:Lazy update`, `:MasonUpdate`
or `:TSUpdate` as a routine startup/recovery fix. Language server and parser updates
need their own artifact/package review before an explicit install window.

After deployment, use the existing uv-managed Python without downloading a runtime:

```sh
uv run --no-project --offline --no-python-downloads python "$HOME/dotfiles/scripts/security/check-editor-state.py"
bash "$HOME/dotfiles/tests/editor-policy.sh"
DOTFILES="$HOME/dotfiles" nvim --headless -i NONE -c 'lua dofile(vim.env.DOTFILES .. "/tests/editor-startup.lua")'
```

The first check starts Neovim with `-u NONE --noplugin`, loads only the local verification
module, and does not source the normal init or plugins. The final command sources the real init and asserts a loaded Gruvbox theme, LSP
setup and disabled startup download channels; a zero exit code alone is insufficient.
To check an already installed Python server, also set
`DOTFILES_EDITOR_EXPECT_PYTHON_LSP=1` and `DOTFILES_EDITOR_TEST_FILE` to a new,
absolute temporary `.py` path. It never installs a server. A fresh machine without
optional tooling must run the reviewed explicit install step; startup will not
repair itself by fetching code.

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
