# First-order dependency sign-off (2026-11-17)

Mark each row **K** (keep) or **D** (drop). "Suggest" is a first-pass opinion only.
Scope: everything `assimilate.sh` installs, plus what is live on this Mac for
Claude Code, Codex, Zed, VS Code and Cursor (these are not managed by the repo).

## 1. Installed by `assimilate.sh`

### Homebrew (`Brewfile`)

| Package | Used by | Suggest | K/D |
|---|---|---|---|
| coreutils | GNU tools | D unless you need GNU flags | |
| curl | macOS ships curl | D | |
| duckdb | ad-hoc analytics | K if used | |
| git | core | K | |
| gh | PR workflow | K | |
| hashicorp/tap/terraform (+ `tap "hashicorp/tap"`, `trusted: true`) | infra | K if used; third-party tap | |
| htop | monitoring | D (Activity Monitor/`top`) | |
| jq | `assimilate.sh`, Claude sync | K (required) | |
| lsd | `ls` alias | D (cosmetic) | |
| lua | standalone interpreter | D (Neovim embeds LuaJIT) | |
| neovim | editor | K | |
| mosh | remote shells | K if used with Tailscale/devbox | |
| postgresql@17 | psql, PATH in `shared.sh` | K if used | |
| pre-commit | gitleaks hook | K | |
| tmux | terminal | K | |
| tree | dir listing | D (`lsd --tree` / `find`) | |
| wget | downloads | D (curl covers it) | |
| yq | Codex config sync | K (required) | |
| zsh-autosuggestions | zsh | K/D (taste) | |
| zsh-syntax-highlighting | zsh | K/D (taste) | |
| cask font-hack-nerd-font | icons in nvim/tmux | D if devicons dropped | |

### Pinned git checkouts

| Checkout | Pin | Suggest | K/D |
|---|---|---|---|
| ohmyzsh/ohmyzsh | e7aa0c5 | D — `plugins=()`, only gives theme + completion; replace with ~20 lines of zsh | |
| tmux-plugins/tpm | v3.1.0 | **D — cloned but never run** (`tmux.conf:35`) | |
| erikw/tmux-powerline | v3.2.0 | K/D (cosmetic status bar) | |

### Verified binary artifacts (`scripts/security/artifacts.json`)

| Artifact | Version | Suggest | K/D |
|---|---|---|---|
| rustup-init | 1.29.2 | K if you write Rust | |
| delta | 0.19.2 | K/D (git pager, cosmetic) | |
| gcloud | 577.0.0 | K if you use GCP; very large surface | |
| nvim (Linux only) | 0.12.4 | K | |
| Socket Firewall `sfw-free` | 1.15.4 | K (it is a defence); note mandatory telemetry | |

### Other runtime installs

| Item | Suggest | K/D |
|---|---|---|
| `uv python install` (Python toolchain) | K | |
| pre-commit hook: gitleaks v8.30.1 | K | |

## 2. Neovim

### Plugins (`nvim/lazy-lock.json`)

| Plugin | Purpose | Suggest | K/D |
|---|---|---|---|
| folke/lazy.nvim | plugin manager | K, or D with native `vim.pack` (0.12) | |
| neovim/nvim-lspconfig | server definitions | D possible — you already pass explicit `cmd`; inline configs in `lsp.lua` | |
| nvim-treesitter/nvim-treesitter | highlighting | K/D — `ensure_installed = {}`; 0.12 bundles core parsers | |
| nvim-telescope/telescope.nvim | fuzzy finder | K (or replace with `:find` + fzf) | |
| nvim-lua/plenary.nvim | telescope dep only | follows telescope | |
| nvim-tree/nvim-tree.lua | file tree | D (netrw/`:Ex`) | |
| nvim-tree/nvim-web-devicons | icons | D (cosmetic; needed by tree/lualine/bufferline) | |
| nvim-lualine/lualine.nvim | statusline | D (cosmetic) | |
| akinsho/bufferline.nvim | tab bar | D (cosmetic) | |
| ellisonleao/gruvbox.nvim | colorscheme | D — Neovim ships `colorscheme retrobox` (gruvbox-like) | |
| airblade/vim-gitgutter | git signs | K/D | |
| tpope/vim-fugitive | git UI | K/D | |
| lukas-reineke/indent-blankline.nvim | indent guides | **D — no `require("ibl").setup()`, so it does nothing** | |
| numToStr/Comment.nvim | commenting | **D — built in since 0.10 (`gc`)**; also no `commit` in `plugins.lua` | |
| iamcco/markdown-preview.nvim | md preview | **D — already `enabled = false`; still in lock** | |

### Language servers

| Server | Source | Suggest | K/D |
|---|---|---|---|
| jedi-language-server 0.47.0 | `nvim/lsp/python` (uv) | K | |
| typescript 5.9.3 + typescript-language-server 6.0.2 | `nvim/lsp/node` (npm) | K if you write TS | |
| eslint 10.12.0 | `nvim/lsp/node` | D — large npm tree; projects carry their own | |
| vscode-langservers-extracted 4.10.0 | `nvim/lsp/node` (only eslint server used) | D with eslint | |
| lua-language-server | external, not installed by repo | K/D | |
| rust-analyzer | rustup component | K if Rust | |

## 3. Claude Code (live in `~/.claude`)

### Plugins

| Plugin | Marketplace | Suggest | K/D |
|---|---|---|---|
| github | claude-plugins-official | K (currently failing auth) | |
| code-review | claude-plugins-official | K | |
| pr-review-toolkit | claude-plugins-official | K/D (overlaps code-review) | |
| security-guidance | claude-plugins-official | K | |
| frontend-design | claude-plugins-official | K/D | |
| skill-creator | claude-plugins-official | K/D | |
| playwright | claude-plugins-official | K/D (overlaps chrome-devtools MCP + built-in browser) | |
| pyright-lsp | claude-plugins-official | K/D | |
| typescript-lsp | claude-plugins-official | K/D | |
| rust-analyzer-lsp | claude-plugins-official | K/D | |
| lua-lsp | claude-plugins-official | K/D | |
| telegram | claude-plugins-official | D unless used | |
| posthog | claude-plugins-official | K if used; very large skill set | |
| planetscale | planetscale/claude-plugin | K if used | |
| ralph-wiggum | enabled in settings, **not installed** | D (remove stale entry) | |

Marketplaces: `anthropics/claude-plugins-official`, `planetscale/claude-plugin`,
`Artemis-xyz/artemis-skills` (registered, no plugins installed → D?).

### MCP servers (`~/.claude.json`)

| Server | Transport | Suggest | K/D |
|---|---|---|---|
| chrome-devtools | `npx chrome-devtools-mcp@latest` | **unpinned `@latest`** — pin or D | |
| x402 | `npx -y @x402scan/mcp@latest` | **unpinned; wallet** — D unless used | |
| agentcash | `npx -y agentcash@latest` | **unpinned; wallet** — D unless used | |
| artemis-tools | local venv binary | K (work) | |
| datadog-mcp | HTTP (deprecated endpoint) | K, move to `/v1/mcp` | |
| openrouter | HTTP (unauthenticated) | D unless used | |
| huntress | HTTP (railway.app) | K (work) | |
| cloudflare-api | HTTP | K/D | |

### Hooks (`settings.json`)

| Hook | Command | Suggest | K/D |
|---|---|---|---|
| PreToolUse | `~/.claude/hooks/pretooluse-permissions.sh` | K | |
| SessionStart | `rex __internal session-start` | K if using Rex | |
| Stop | `afplay` sound + `osascript` notification | K | |

### Skills (`~/.claude/skills`, 54 + `_shared`)

Mostly from claudefather. `~/.agents/skills/` (read by Codex and Cursor) holds a
second copy (~86 entries, incl. Cursor-style `create-rule`, `update-cursor-settings`).
`~/.claude/skills/synced/` is the Claude app's own skill sync, not a duplicate.
`agentcash` was removed from both on 2026-11-17.

| Group | Skills | K/D |
|---|---|---|
| Review/quality | review-changes, review-pr, security-audit, tech-debt, docs-review, access-path-audit, data-model-audit, design-review, frontend-performance-audit, visual-crawl, cache-audit, verify-completion | |
| Workflow | commit-push-pr, quick-commit, worktree, implement-plan, weigh-development-paths, development-retro, file-github-issue, github-pr-video-evidence, init-project, repo-health | |
| Session | context-resume, session-handoff, name-session, notes, lessons, notifications | |
| Product | product-enhance, product-vision, investigate-app | |
| Infra: Modal | modal-deploy, modal-logs, modal-status | |
| Infra: Railway | railway-deploy, railway-logs, railway-status | |
| Infra: Vercel | vercel-deploy, vercel-logs, vercel-status | |
| Data: Neon | neon-branch, neon-info, neon-query | |
| Data: Snowflake/dbt | snowflake-query, snowflake-cutover, dbt, validate-postgres-optimization | |
| Meta | claudefather-migrate, heist, find-skills | |
| Other | agentcash, rex | |

Commands (`~/.claude/commands`, 13): artemis-skills-setup, claudefather-sync,
context-resume, freeze, name-session, private, reconcile, session-checkpoint,
session-handoff, session-name, session-resume, unfreeze, unprivate.

Agents (`~/.claude/agents`, 8): code-reviewer, dbt-engineer, modal-ops,
neon-analyst, railway-ops, snowflake-analyst, spec-reviewer, vercel-ops.

## 4. Codex (live in `~/.codex/config.toml`)

### Plugins

| Plugin | Marketplace | Suggest | K/D |
|---|---|---|---|
| visualize, browser, chrome, computer-use, unified-computer-use, codex-app-tools | openai-bundled | K (first party) | |
| documents, pdf, spreadsheets, presentations, template-creator | openai-primary-runtime | K/D | |
| google-calendar, slack | openai-curated | D unless used | |
| code-review, frontend-design, github, playwright, posthog, pr-review-toolkit, security-guidance, skill-creator, typescript-lsp | claude-plugins-official | mirror Claude decisions | |
| planetscale | planetscale | mirror Claude decision | |

Git marketplaces: claude-plugins-official, planetscale, artemis-skills (unused → D?).

### MCP servers

| Server | Transport | Suggest | K/D |
|---|---|---|---|
| node_repl | ChatGPT.app bundled | K | |
| computer-use | bundled, `enabled = false` | D | |
| openaiDeveloperDocs | HTTP | K | |
| agentcash, x402, chrome-devtools | `npx …@latest` | **unpinned** — same as Claude | |
| artemis-tools | local venv | K | |
| datadog **and** datadog-mcp | HTTP | D one (keep `/v1/mcp`) | |
| openrouter, huntress | HTTP | mirror Claude | |
| raindrop, sentry, slack | HTTP | D unless used | |

### Skills and hooks

- `~/.codex/skills`: github-pr-video-evidence, hatch-pet
- `~/.codex/skills/.system` (bundled): imagegen, openai-docs, review-agent, skill-creator, skill-installer
- Hooks: same three as Claude (pretooluse-permissions, rex session-start, Stop sound/notification)

## 5. Editors

| Editor | Installed extensions | Notes | K/D |
|---|---|---|---|
| Zed | catppuccin-icons, html, sql | Python uses built-in `ty` | |
| VS Code | **none installed** | `vscode/vscode_extensions.txt` lists 23 stale names → D the file | |
| Cursor | anysphere.remote-containers, anysphere.remote-ssh | `code` on PATH is Cursor's CLI | |

## 6. Repo-only tooling (not installed by `assimilate.sh`)

CI/security scanners pinned in `scripts/security/`: gitleaks, shellcheck,
osv-scanner, zizmor 1.29.0; pre-commit Linux lock (cfgv, distlib, filelock,
identify, nodeenv, packaging, platformdirs, pre-commit, python-discovery,
pyyaml, virtualenv); GitHub Action `actions/checkout` v7.0.1 (SHA-pinned);
`scripts/docker/requirements.in`: notebook, pandas, certifi.
