# Dependency inventory

Everything the dotfiles install, and how each one is pinned. Last reviewed
2026-11-18. Versions follow a seven-day minimum release age.

How pins are enforced:

- **SHA-256 download:** `scripts/security/install-artifact.sh` checks the download
  against `scripts/security/artifacts.json` before unpacking. It records a hash of
  every installed file, and every `assimilate.sh` run (including `--check`) refuses
  a changed byte.
- **Source build:** `scripts/security/build-source.sh` checks the tarball against
  `scripts/security/sources.json` and builds with the Command Line Tools. Its
  libraries are pinned sources too. It keeps the same per-file receipt and check.
- **Commit:** `scripts/security/check-clone.sh` requires the exact reviewed commit,
  the reviewed origin and a clean checkout.
- **Lock file:** exact versions with integrity hashes, installed with hashes required.

Nothing re-checks a binary at launch; drift shows up on the next
`assimilate.sh --check`.

Not managed by setup: the local secret scanners (gitleaks, ShellCheck,
OSV-Scanner) still come from Homebrew, with versions checked by
`scanners.lock.json`.

## Command-line tools

| Tool | Version | Pinned by | Notes |
|---|---|---|---|
| Node (node, npm, npx) | 26.13.1 | SHA-256 download | the only Node; no nvm or Homebrew Node |
| Neovim | 0.12.6 (macOS), 0.12.4 (Linux x86_64) | SHA-256 download | |
| gh | 2.103.3 | SHA-256 download | |
| terraform | 1.17.1 | SHA-256 download | HashiCorp's SHA256SUMS |
| duckdb | 2.0.0 | SHA-256 download | |
| jq | 1.8.2 | SHA-256 download | used by `assimilate.sh` |
| yq | 4.54.3 | SHA-256 download | merges Codex settings in `codex/sync-config.sh` |
| lsd | 1.2.0 | SHA-256 download | `ls` and `tree` aliases |
| delta | 0.19.2 | SHA-256 download | macOS arm64 and Linux x86_64 |
| gcloud | 577.0.0 | SHA-256 download | |
| rustup-init | 1.29.2 | SHA-256 download | only when rustup is missing |
| lua-language-server | 3.19.2 | SHA-256 download | |
| rust-analyzer | 2026-11-02 | SHA-256 download | |
| Hack Nerd Font | 3.5.1 | SHA-256 download | macOS; copied into `~/Library/Fonts`, which `--check` compares with the pinned files and never overwrites |
| Socket Firewall (`sfw`) | 1.15.4 | SHA-256 download | wraps npm, bun and uv; sends telemetry; trusts only the pinned CA bundle |
| Mozilla CA bundle | 2026-11-05 | SHA-256 download | from curl.se; the one CA source for Socket, `SSL_CERT_FILE` and the pinned OpenSSL |
| tmux | 3.8 | source build | with libevent 2.1.13 |
| mosh | 1.4.0 | source build | with protobuf 21.12; Apple CommonCrypto on macOS |
| PostgreSQL | 17.12 | source build | with OpenSSL 3.5.9, which trusts the pinned CA bundle, for verified TLS |
| pre-commit | 4.6.2 | lock file | `scripts/security/requirements-pre-commit-py312.txt`; `--check` re-verifies every installed file against its RECORD hash |
| git | Apple Git | macOS | from the Command Line Tools |
| curl | macOS | macOS | |

## Shell, tmux and Neovim

| Item | Pin |
|---|---|
| oh-my-zsh | commit `e7aa0c5` |
| zsh-autosuggestions | v0.7.1, commit `e52ee8c` |
| zsh-syntax-highlighting | 0.8.0, commit `db085e4` |
| tmux-powerline | v3.2.0, commit `6079ace` |
| Neovim plugins | exact commits in `nvim/lazy-lock.json`: lazy.nvim, nvim-lspconfig, telescope.nvim, plenary.nvim, nvim-tree.lua, nvim-web-devicons, lualine.nvim, bufferline.nvim, gruvbox.nvim, vim-fugitive, vim-gitgutter |
| Neovim syntax | Neovim's bundled Treesitter parsers |
| Language servers | ty 0.0.99 and ruff 0.17.4 (`nvim/lsp/python/uv.lock`); typescript 5.9.3 and typescript-language-server 6.0.2 (`nvim/lsp/node/package-lock.json`); lua-language-server and rust-analyzer above |
| Commenting | Neovim's built-in `gc` (Ctrl-/) |

## Removed

| Removed | Replaced by |
|---|---|
| Homebrew (all packages, the font cask and the hashicorp tap) | the pins above |
| nvm, Homebrew Node | pinned Node |
| coreutils, htop, wget, tree, Homebrew curl, Homebrew git, lua | macOS tools and `lsd --tree` |
| tpm | tmux-powerline from its pinned checkout |
| Comment.nvim, indent-blankline.nvim, nvim-treesitter | Neovim built-ins |
| markdown-preview.nvim | Zed's built-in preview |
| jedi-language-server | ty and ruff |
| eslint, vscode-langservers-extracted | not needed |

## Agent and editor setup (machine-local, not managed by this repo)

| Tool | Current state on the laptop |
|---|---|
| Claude Code MCP | chrome-devtools (`chrome-devtools-mcp@1.12.0` on the pinned npx), datadog-mcp (`/v1/mcp`), cloudflare-api, openrouter |
| Codex MCP | chrome-devtools (same pin), datadog-mcp (`/v1/mcp`), node_repl, openaiDeveloperDocs, openrouter, raindrop, sentry, slack; computer-use disabled |
| Removed MCP | x402, agentcash, artemis-tools, huntress, Codex's duplicate `datadog` |
| Claude plugins | ralph-wiggum disabled; artemis-skills marketplace removed |
| Zed | catppuccin-icons only; `auto_install_extensions.html = false` |
| Skills | `~/.claude/skills` (Claude Code) and `~/.agents/skills` (Codex, Cursor) are separate copies; the Codex copy has broken `~/.Codex/` paths |
