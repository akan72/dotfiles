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

### Codex configuration

`assimilate.sh` syncs the portable settings from `codex/config.managed.toml`
into marked blocks in `~/.codex/config.toml`. The managed fragment
also owns the portable `[desktop]` preferences configured through the Codex UI,
including the Git branch prefix, PR and commit conventions, appearance, editor
target, notifications, queue behavior, worktree cleanup, and automatic imports
from Claude Code. It also lets Codex use `CLAUDE.md` when `AGENTS.md` is absent
and raises the project-instruction budget for larger repository guides. Changes
made in the UI should be mirrored back to the managed fragment before the next
assimilation.

Claude import category choices are stored by the desktop app outside
`config.toml`. After Homebrew installs `jq`, `codex/sync-import-preferences.sh`
surgically enables the detected Claude Code configuration, instructions,
skills, commands, subagents, hooks, plugins, and MCP imports while disabling
chat-session imports. The project-import choice is left unchanged. On a new
machine, configure Claude Code import once in Codex, then rerun assimilation so
the detected categories can be updated. Run assimilation with Codex closed so
the desktop app cannot overwrite the preference file while it is being updated.

Generated and machine-specific state outside the managed block, such as local
paths, installed plugins, connector authentication, caches, session history,
and per-project trust, remains local to each machine. Do not check in the full
`.codex-global-state.json` file or any Codex session database.

### Tmux Plugin Manager
- Install Tmux Plugin Manager ([Github](https://github.com/tmux-plugins/tpm#tmux-plugin-manager))
- Install tmux packages with `prefix + I`
