Dotfiles
==============================

My dotfiles! Based upon this [guide](https://www.atlassian.com/git/tutorials/dotfiles) from Atlassian.

## Description

For my development setup, I use [Neovim](https://neovim.io/) as my text editor, [iTerm2](https://www.iterm2.com/index.html)
as a terminal replacement (with [tmux](https://github.com/tmux/tmux/wiki), and [Oh My Zsh](https://ohmyz.sh/) as my shell.
I'm also a fan of [Nerd-Fonts](https://github.com/ryanoasis/nerd-fonts) and am currently using [Hack](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/Hack).

This is a fairly minimalistic approach to tracking dotfiles, and enables easy reproduction on other machines.

I've created a bare repository in `$HOME/.cfg` aliased to `config` that tracks only the files of interest (the dotfiles) This is done by running:

```shell
git init --bare $HOME/.cfg
alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
config config --local status.showUntrackedFiles no
echo "alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'" >> $HOME/<shell_config_file>
```

Where `<shell_config_file>` is `.bashrc` or `.zshrc` etc.

## Installation

Make sure that your shell is configured for the correct alias by running:

```shell
echo "alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'" >> $HOME/<shell_config_file>
```

Initialize the bare repository in the new `$HOME` directory after ensuring that the current folder is being ignored (to avoid weird recursive issues):

```shell
echo ".cfg" >> .gitignore
git clone --bare <git-repo-url> $HOME/.cfg
```

Define the `config` alias within the current shell, `checkout` the dotfiles from the cloned bare repository, and then prevent the repo from showing untracked files:

```shell
alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'
config checkout
config config --local status.showUntrackedFiles no
```

An error may occur when calling `config checkout` if local dotfiles are being overwritten; to prevent this make sure to delete the original files or back them up in a temporary directory.

