# Checklist

> **Most setup is automated by [`assimilate.sh`](./assimilate.sh).** It symlinks
> all dotfiles and installs oh-my-zsh, Homebrew packages (`brew bundle`), Rust,
> git-delta, tmux plugin manager + plugins, and bootstraps the Neovim plugin
> manager. The steps below are the manual bits that can't be scripted.

# Mac settings
- General: Automatically Hide and Show the Menu Bar -> True
- Keyboard: Key Repeat -> Fast
- Keyboard: Delay Until Repeat -> Short
- Trackpad: Tracking Speed -> 4th tick
- Trackpad: Click -> Light

# Applications
- Chrome: Settings -> Manage Passwords -> Disable offer to manage passwords
- Spotlight: Set default shortcut to `cmd + shift + space`
- Alfred: Set the default shortcut to `cmd + space`
- Alfred Clipboard history: enable text + image + file lists
- Follow the [reviewed bootstrap policy](README.md#installation), including the verified standalone uv bootstrap.
- Install [Ghostty](https://ghostty.org/) (terminal; config is symlinked from `ghostty/`)
- Install [Zed](https://zed.dev/) (editor; `settings.json` + `keymap.json` symlinked from `zed/`)
- Install a reviewed exact [Claude Code](https://docs.anthropic.com/en/docs/claude-code) release through the approved package policy; verify native updater settings separately.
- Review and install tmux plugins through the pinned bootstrap; do not use independent TPM install/update shortcuts.

> The Hack Nerd Font is installed automatically via `brew bundle`
> (`cask "font-hack-nerd-font"`) ; it remains a separately trusted rolling channel.
> oh-my-zsh, zsh plugins, tmux plugin manager (tpm), and the Neovim plugin
> manager are all handled by `assimilate.sh`.
