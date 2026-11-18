# Checklist

> **Most setup is automated by [`assimilate.sh`](./assimilate.sh).** It symlinks
> all dotfiles and installs every pinned tool listed in the
> [dependency inventory](docs/dependency-signoff.md): SHA-256-pinned downloads,
> commit-pinned checkouts, and tmux, mosh and PostgreSQL built from pinned source.
> Homebrew is not used. The steps below are manual steps not automated by setup.

## Initial setup

- Clone this repository into `~/dotfiles`, then follow the [installation instructions](README.md#installation).
- Set up GitHub access and commit signing using the [authentication guide](docs/github-auth.md); review its unattended-Mac choices for laptop use.

## Mac settings

- General: Automatically Hide and Show the Menu Bar -> True
- Dock: Position -> Bottom; size -> 20% of the slider.
- Battery: Show percentage -> On
- Keyboard: Remap Caps Lock -> Escape
- Keyboard: Brightness -> 0
- Keyboard: Key Repeat -> Fast
- Keyboard: Delay Until Repeat -> Short
- Trackpad: Tracking Speed -> 4th tick
- Trackpad: Click -> Light
- Trackpad: Swipe between pages -> Off
- Keyboard shortcuts: Copy picture of selected area to the clipboard -> `shift + cmd + 4`
- Mission Control: Automatically rearrange Spaces based on most recent use -> Off
- Lock Screen: Require password after screen saver begins or display is turned off -> Immediately
- Pair Bluetooth devices.

## Logitech mouse

- Install Logi Options and configure the mouse.
- Middle button -> Mission Control
- Scroll wheel speed -> 57%; natural scrolling -> On
- Pointer speed -> 66%

## Development tools

- Install Alfred 5.
- Install f.lux.
- Spotlight: Set default shortcut to `cmd + shift + space`
- Alfred: Set the default shortcut to `cmd + space`
- Alfred Clipboard history: enable text + image + file lists
- Install Docker Desktop.
- Install Postman.
- Install pgAdmin.
- Follow the [reviewed bootstrap policy](README.md#installation), including the verified standalone uv bootstrap.
- Install [Ghostty](https://ghostty.org/) (terminal; config is symlinked from `ghostty/`)
- Install [Zed](https://zed.dev/) (editor; `settings.json` + `keymap.json` symlinked from `zed/`)
- Install Apple's Command Line Tools (`xcode-select --install`): they provide git and the compilers for the source builds.
- Install a reviewed exact [Claude Code](https://docs.anthropic.com/en/docs/claude-code) release through the approved package policy; verify native updater settings separately.
- tmux-powerline comes from the pinned bootstrap; TPM is not used.

> The Hack Nerd Font, oh-my-zsh, the zsh plugins, tmux-powerline and the Neovim
> plugins are all installed and pinned by `assimilate.sh`. For Markdown preview,
> use Zed's built-in `markdown: open preview`.
