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

`assimilate.sh` uses Codex's documented app-server configuration API to apply
the portable root settings from `codex/config.managed.toml` to
`~/.codex/config.toml`. Codex parses and validates the managed TOML itself, and
`config/batchWrite` preserves settings that are not managed by this repository.
The checked-in settings enable turn notifications, automatic review, low
verbosity, concise reasoning summaries, and the pragmatic personality. Codex
uses `AGENTS.md` natively and falls back to `CLAUDE.md` when it is absent.

The same sync detects and imports Claude Code instructions, configuration,
skills, commands, subagents, hooks, plugins, MCP servers, and memory through
Codex's external-agent import API. Session detection is disabled and any
`SESSIONS` items are explicitly excluded. This is a supported, one-shot import
each time assimilation runs; optional continuous import can still be enabled
once in the Codex UI with session imports left disabled.

Desktop-only preferences such as the Git branch prefix, PR and commit
instructions, appearance, editor target, and queue behavior remain local. Codex
currently treats the `[desktop]` table as opaque app state, so it is deliberately
not checked in. Generated and machine-specific state such as local paths,
installed plugins, connector authentication, caches, session history, and
per-project trust also remains local. Never check in
`.codex-global-state.json`, Codex session databases, or the complete live
`config.toml`.

### Tmux Plugin Manager
- Install Tmux Plugin Manager ([Github](https://github.com/tmux-plugins/tpm#tmux-plugin-manager))
- Install tmux packages with `prefix + I`
