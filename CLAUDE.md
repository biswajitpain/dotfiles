# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Biswajit's personal dotfiles for all his computers (macOS and Linux). It serves two purposes: syncing shell environment across machines (zsh, vim, tmux, git via symlinks from `~/.dotfiles` into `$HOME`), and acting as a curated library of aliases, commands, and utility functions he uses daily. The install script handles cloning, symlinking, and Oh My Zsh setup.

## Install / Apply Changes

```bash
# Fresh install on a new machine
bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/install.sh)"

# Reinstall using local files (skip re-cloning)
./install.sh local

# Manually specify machine name
./install.sh machine <machine-name>

# Reload zsh config in current shell
source ~/.zshrc
```

## How Machine Detection Works

This is the core architectural concept. There is **no static machine type file** — the machine name is resolved at shell startup every time:

- **macOS**: `scutil --get ComputerName`
- **Linux**: `hostname -s`

`$MACHINE_TYPE` is exported and used to load `zsh/machines/$MACHINE_TYPE.zsh`. If no matching file exists, it silently skips. This means adding a new machine requires only creating the right file — no changes to `install.sh` or `.zshrc`.

## Config Load Order in `.zshrc`

1. Oh My Zsh (`bira` theme, plugins: `git aws docker kubectl`)
2. `zsh/common/aliases/general.zsh`
3. `zsh/common/functions/utils.zsh`
4. `zsh/common/functions/check_dotfiles_update.zsh`
5. OS-specific: `zsh/os/macos/` or `zsh/os/linux/`
6. Machine-specific: `zsh/machines/$MACHINE_TYPE.zsh`

## Adding a New Machine

1. Create `zsh/machines/<ComputerName-or-hostname>.zsh` — use `dummy-machine.zsh` as a template
2. Create `git/.gitconfig.<machine-name>` for machine-specific git identity
3. The install script will prompt to link the git config when run on that machine

## Auto-Update Mechanism

`check_dotfiles_update` runs in the background on every interactive shell. It checks `~/.dotfiles/.last_update` (ignored by git) and fetches from `origin/main` weekly. If behind, it pulls and re-runs `install.sh`.

## Gitignored Files

`.last_update` — timestamp for weekly update check  
`.machine_type` — legacy file, no longer used  
`.claude/` — local Claude Code settings

## Symlinks Created by install.sh

| Symlink | Source |
|---|---|
| `~/.zshrc` | `dotfiles/zsh/.zshrc` |
| `~/.vimrc` | `dotfiles/vim/.vimrc` |
| `~/.tmux.conf` | `dotfiles/tmux/.tmux.conf` |
| `~/.gitconfig` | `dotfiles/git/.gitconfig.<machine-name>` |
| `~/.ssh/config` | `dotfiles/ssh/config` |
| `~/.aws/config` | `dotfiles/aws/config` |
| `~/.kube/config` | `dotfiles/kube/config` |

Before linking, existing files are backed up to `~/.dotfiles_backup/<timestamp>/`.
