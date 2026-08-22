Dotfiles
==============================

## Description

### Config

For my development setup, I use [Neovim](https://neovim.io/) as a text editor, [iTerm2](https://www.iterm2.com/index.html)
as a terminal replacement (with [tmux](https://github.com/tmux/tmux/wiki), and [Oh My Zsh](https://ohmyz.sh/) as my shell.

I'm also a fan of [Nerd-Fonts](https://github.com/ryanoasis/nerd-fonts) and am currently using [Hack](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/Hack).
For my plugin manager I use [vim-plug](https://github.com/junegunn/vim-plug).

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

This is a fairly minimalistic approach to tracking dotfiles, and enables easy reproduction on other machines.

Simply clone the repository:

```shell
git clone https://github.com/akan72/dotfiles.git
```

cd into the `dotfiles` directory, and then run:
```shell
./assimilate.sh
```

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

### Tmux Plugin Manager
- Install Tmux Plugin Manager ([Github](https://github.com/tmux-plugins/tpm#tmux-plugin-manager))
- Install tmux packages with `prefix + I`
