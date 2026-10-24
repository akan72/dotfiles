Dotfiles
==============================

## Description

### Config

For my development setup, I use [Neovim](https://neovim.io/) as a text editor, [iTerm2](https://www.iterm2.com/index.html)
as a terminal replacement (with [tmux](https://github.com/tmux/tmux/wiki), and [Oh My Zsh](https://ohmyz.sh/) as my shell.

I'm also a fan of [Nerd-Fonts](https://github.com/ryanoasis/nerd-fonts) and am currently using [Hack](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/Hack).
For my plugin manager I use [lazy.nvim](https://github.com/folke/lazy.nvim).

[VSCode](https://code.visualstudio.com/) is my main editor/IDE.

### Productivity

I also use [Hammerspoon](https://www.hammerspoon.org/) to enable focus switching
between applications via hotkeys, where the `Hyper` key is mapped to the result of the long press mentioned previously.

Examples usage of focus switching with `Hyper + <key>`:

`C` : Chrome
`V` : VSCode
`W` : Word
`M` : Messages
`Q` : Quip

`1` : `open ~/`
`2` : `open ~/Documents`
`3` : `open ~/Dropbox/projects`

## Installation

Review this checkout and the release manifest before running the setup entry point:

```sh
cd "$HOME/dotfiles"
git status --short
bash ./assimilate.sh
```

Setup prints nine named stages and stores detailed command output in private
`~/.local/state/dotfiles-security/assimilate/run.*/` logs. A failure shows its stage,
exit status, diagnostic tail and exact log path; `--verbose` prints each stage's
full captured output. CLI downloads show live tool/version status, ten-second
elapsed-time updates and checksum/install milestones. Run
`bash ./assimilate.sh --check` to validate existing checkouts and CLI installations first; this creates logs but changes no configuration or packages.
Preflight checks pinned artifact metadata, existing installation receipts and hashes,
destination/launcher conflicts and checkout integrity before linking files or
invoking Homebrew. Unmanaged delta/gcloud copies are reported together and left
untouched; missing destinations are ready for later installation. Existing rustup
is retained under the separate playbook update policy. Homebrew automatic
updates, dependent upgrades and install cleanup are disabled for the setup's
bundle commands; first installs still use the reviewed distribution boundary.

### Reviewed release policy

Read the shared [security and maintenance guide](docs/editor-security.md) before
installing or updating tools. It covers prerequisites, pinned artifacts, checkout
integrity, Homebrew's rolling-distribution boundary, package cooldowns, Socket,
local scans and reviewed editor/notebook updates. Use uv for personal Python;
retain Apple/Homebrew runtimes required by the system and formula dependencies.

### Container installation tests

Default tests export clean tracked HEAD only, never the live checkout or `.git`:

```sh
scripts/ci/run-vps-container.sh run ubuntu
```

For proposed changes, explicitly select the working tracked bytes and each new
reviewed source file. No commit is created, and untracked files are excluded unless
named. Sensitive-named new files and symlinks are refused:

```sh
scripts/ci/run-vps-container.sh run ubuntu --working --include tests/new-check.sh
```

The shared exporter copies source into a private snapshot without changing the
Git index/object database. The container verifies its file-hash manifest; host
tracked content and HEAD are checked again after execution. Registry access and package installs occur only inside the disposable
container. A readonly mount alone is not a confidentiality control.

The installer shares `agent-instructions.md` with Claude Code and Codex by
linking it to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

### Codex configuration

`assimilate.sh` uses `yq` to structurally merge the portable root settings from
`codex/config.managed.toml` into `~/.codex/config.toml`. It validates the merged
file with Codex's strict config loader before replacing the live config
atomically. Settings outside the managed fragment are preserved, and the first
existing config is retained as `~/.codex/config.toml.dotfiles-backup`.

The checked-in settings enable turn notifications, automatic review, low
verbosity, concise reasoning summaries, and the pragmatic personality. Codex
uses `AGENTS.md` natively and falls back to `CLAUDE.md` when it is absent.

Enable continuous Claude Code import once in the Codex UI and leave session
imports disabled. Those choices are desktop-local state and are deliberately
not automated through internal state files or JSON-RPC APIs.

The portable Git preferences—branch prefix, squash merge method, and PR and
commit instructions—are managed in the schema-supported `[desktop]` table.
Other desktop preferences such as appearance, editor target, and queue behavior
remain local. Generated and machine-specific state such as local paths,
installed plugins, connector authentication, caches, session history, and
per-project trust also remains local. Never check in
`.codex-global-state.json`, Codex session databases, or the complete live
`config.toml`.

### Claude Code configuration

`assimilate.sh` uses `jq` to structurally merge the portable settings from
`claude/settings.managed.json` into `~/.claude/settings.json`. Local settings
such as permissions, hooks, plugins, and model selection are preserved. The
managed fragment enables concise output, configures the checked-in statusline,
and disables commit attribution, PR attribution, and cloud or Remote Control
session links. The first existing settings file is retained as
`~/.claude/settings.json.dotfiles-backup`.

### Tmux plugins

Assimilation installs only reviewed full commits. Runtime TPM installation/update
shortcuts are disabled; powerline uses guarded local rendering. Review changed
commits before changing pins and rerunning bootstrap. See
[editor security and reversible legacy migration](docs/editor-security.md).

## Headless Mac mini

- [Setup and restart verification](docs/mac-mini-setup-guide.md)
- [Tailscale SSH architecture](docs/tailscale-ssh.md)
- [Personal/work GitHub authentication](docs/github-auth.md)
