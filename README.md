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

To aid in my productivity, I've re-mapped my `Caps Lock` key to `command+control+option` for a long press, and `esc` for a short press.
This is done using [Karabiner](https://karabiner-elements.pqrs.org/).

In conjunction with `Karabiner` I also use [Hammerspoon](https://www.hammerspoon.org/) to enable focus switching
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

This productivity setup is inspired by by this [blogpost](https://kevzheng.com/hammerspoon-karabiner).

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

