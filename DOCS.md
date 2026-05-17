# Dotfiles Reference Documentation

A complete reference for Biswajit's personal dotfiles — a cross-machine shell environment and command library for macOS and Linux.

---

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
  - [Fresh Install](#fresh-install)
  - [Reinstall (Local)](#reinstall-local)
  - [Manual Machine Name](#manual-machine-name)
- [Architecture](#architecture)
  - [Machine Detection](#machine-detection)
  - [Config Load Order](#config-load-order)
  - [Symlinks](#symlinks)
  - [Auto-Update](#auto-update)
- [Alias Reference](#alias-reference)
  - [Navigation](#navigation)
  - [File Operations](#file-operations)
  - [System](#system)
  - [Process Management](#process-management)
  - [Network](#network)
  - [Git](#git)
  - [Docker](#docker)
  - [Kubernetes](#kubernetes)
  - [Editor Shortcuts](#editor-shortcuts)
  - [Misc](#misc)
- [Function Reference](#function-reference)
  - [mkd](#mkd)
  - [gmsg](#gmsg)
  - [ff](#ff)
  - [fh](#fh)
  - [server](#server)
  - [weather](#weather)
  - [extract](#extract)
  - [tmpd](#tmpd)
  - [targz](#targz)
  - [fs](#fs)
  - [dataurl](#dataurl)
  - [getcertnames](#getcertnames)
  - [DNS Utilities](#dns-utilities)
- [Machine Configuration](#machine-configuration)
  - [Adding a New Machine](#adding-a-new-machine)
  - [Git Identity per Machine](#git-identity-per-machine)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository is Biswajit's personal dotfiles for all his computers. It has two purposes:

1. **Environment sync** — keeps zsh, vim, tmux, and git config consistent across macOS and Linux machines via symlinks.
2. **Command library** — a curated collection of aliases and utility functions available in every shell session.

**Supported platforms:** macOS, Linux

---

## Installation

### Fresh Install

Run this on any new machine. It clones the repo to `~/.dotfiles`, installs Oh My Zsh if missing, and creates all symlinks.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/install.sh)"
```

**What it does:**
1. Detects the machine name automatically (`scutil --get ComputerName` on macOS, `hostname -s` on Linux)
2. Checks and installs dependencies: `git`, `curl`, `zsh`, `vim`, `tmux`
3. Installs Oh My Zsh (if not already present)
4. Backs up any existing dotfiles to `~/.dotfiles_backup/<timestamp>/`
5. Creates symlinks (see [Symlinks](#symlinks))
6. Sets up machine-specific git identity

---

### Reinstall (Local)

Use this when the repo is already cloned and you want to reapply symlinks without re-cloning.

```bash
cd ~/.dotfiles
./install.sh local
```

Also useful after pulling changes to re-link updated files.

---

### Manual Machine Name

Override automatic machine detection:

```bash
./install.sh machine <machine-name>
```

| Parameter | Type | Description |
|---|---|---|
| `machine-name` | `string` | Must match a file in `zsh/machines/<machine-name>.zsh` |

**Example:**
```bash
./install.sh machine office-mac1
```

---

### Install a Package

Install a system package (via Homebrew on macOS, apt/yum on Linux):

```bash
./install.sh package <package-name>
```

**Example:**
```bash
./install.sh package neovim
```

---

### Apply Changes Without Reinstalling

Reload the zsh config in the current shell session:

```bash
source ~/.zshrc
# or use the alias:
reload
```

---

## Architecture

### Machine Detection

Machine identity is resolved **at shell startup, every time** — there is no stored machine type file. The logic in `.zshrc`:

```
macOS  →  scutil --get ComputerName
Linux  →  hostname -s
```

The result is exported as `$MACHINE_TYPE` and used to load the matching file:

```
zsh/machines/$MACHINE_TYPE.zsh
```

If no matching file exists, it is silently skipped — no errors.

> To find your machine name on macOS: `scutil --get ComputerName`  
> To find your machine name on Linux: `hostname -s`

---

### Config Load Order

Every interactive shell loads files in this sequence:

| Order | File | Purpose |
|---|---|---|
| 1 | Oh My Zsh (`bira` theme) | Base shell framework |
| 2 | `zsh/common/aliases/general.zsh` | Cross-machine aliases |
| 3 | `zsh/common/functions/utils.zsh` | Cross-machine utility functions |
| 4 | `zsh/common/functions/check_dotfiles_update.zsh` | Weekly auto-update check |
| 5 | `zsh/os/macos/` or `zsh/os/linux/` | OS-specific aliases and functions |
| 6 | `zsh/machines/$MACHINE_TYPE.zsh` | Machine-specific overrides |

Each file is loaded only if it exists. Later files can override anything from earlier ones.

---

### Symlinks

`install.sh` creates these symlinks. Existing files are backed up before linking.

| Symlink in `$HOME` | Source in `~/.dotfiles` |
|---|---|
| `~/.zshrc` | `zsh/.zshrc` |
| `~/.vimrc` | `vim/.vimrc` |
| `~/.tmux.conf` | `tmux/.tmux.conf` |
| `~/.gitconfig` | `git/.gitconfig.<machine-name>` |

Backups are saved to: `~/.dotfiles_backup/<timestamp>/`

---

### Auto-Update

`check_dotfiles_update` runs silently in the background on every interactive shell session. It:

1. Reads `~/.dotfiles/.last_update` (a unix timestamp, gitignored)
2. If more than 7 days have passed, fetches from `origin/main`
3. If the local branch is behind, pulls and re-runs `install.sh`
4. Writes the current timestamp back to `.last_update`

To force an immediate update check:
```bash
check_dotfiles_update
```

---

## Alias Reference

### Navigation

| Alias | Expands To | Description |
|---|---|---|
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `....` | `cd ../../..` | Go up three directories |
| `.....` | `cd ../../../..` | Go up four directories |
| `~` | `cd ~` | Go to home directory |
| `-` | `cd -` | Go to previous directory |

---

### File Operations

| Alias | Expands To | Description |
|---|---|---|
| `ls` | `ls -G` | Colorized listing |
| `ll` | `ls -lh` | Long listing, human-readable sizes |
| `la` | `ls -lah` | Long listing including hidden files |
| `l` | `ls -CF` | Compact listing with indicators |
| `lsd` | `ls -l \| grep "^d"` | List only directories |
| `cp` | `cp -iv` | Copy with confirmation and verbose |
| `mv` | `mv -iv` | Move with confirmation and verbose |
| `rm` | `rm -iv` | Remove with confirmation and verbose |
| `mkdir` | `mkdir -pv` | Create directories recursively, verbose |

---

### System

| Alias | Expands To | Description |
|---|---|---|
| `df` | `df -h` | Disk usage, human-readable |
| `du` | `du -h` | Directory size, human-readable |
| `free` | `free -m` | Memory usage in MB |
| `meminfo` | `free -m -l -t` | Detailed memory breakdown |

---

### Process Management

| Alias | Expands To | Description |
|---|---|---|
| `psa` | `ps aux` | All running processes |
| `psg` | `ps aux \| grep -v grep \| grep` | Search processes (pass a pattern) |
| `psr` | `ps aux \| grep ruby` | All Ruby processes |

**Example:**
```bash
psg nginx      # find nginx processes
```

---

### Network

| Alias | Expands To | Description |
|---|---|---|
| `ping` | `ping -c 5` | Ping 5 times |
| `fastping` | `ping -c 100 -s.2` | Fast ping burst |
| `ports` | `netstat -tulanp` | Show all open ports |
| `ipinfo` | `curl ipinfo.io` | Get public IP and geolocation |

---

### Git

> These supplement the Oh My Zsh `git` plugin aliases.

| Alias | Expands To | Description |
|---|---|---|
| `g` | `git` | Short git |
| `gs` | `git status` | Status |
| `gd` | `git diff` | Diff |
| `gc` | `git commit` | Commit |
| `gca` | `git commit -a` | Commit all tracked changes |
| `gco` | `git checkout` | Checkout |
| `gb` | `git branch` | List branches |
| `gl` | `git log --graph ...` | Pretty graph log |
| `grh` | `git reset --hard` | Hard reset |
| `grhh` | `git reset --hard HEAD` | Hard reset to HEAD |

---

### Docker

| Alias | Expands To | Description |
|---|---|---|
| `d` | `docker` | Short docker |
| `dc` | `docker-compose` | Short docker-compose |
| `dps` | `docker ps` | Running containers |
| `dpsa` | `docker ps -a` | All containers |

---

### Kubernetes

| Alias | Expands To | Description |
|---|---|---|
| `k` | `kubectl` | Short kubectl |
| `kgp` | `kubectl get pods` | List pods |
| `kgs` | `kubectl get services` | List services |
| `kgd` | `kubectl get deployments` | List deployments |

---

### Editor Shortcuts

| Alias | Opens | Description |
|---|---|---|
| `zshrc` | `~/.zshrc` | Edit zsh config |
| `bashrc` | `~/.bashrc` | Edit bash config |
| `vimrc` | `~/.vimrc` | Edit vim config |
| `tmuxconf` | `~/.tmux.conf` | Edit tmux config |

---

### Misc

| Alias | Description |
|---|---|
| `now` | Print current time (`HH:MM:SS`) |
| `nowdate` | Print current date (`DD-MM-YYYY`) |
| `h` | Command history |
| `j` | List background jobs |
| `path` | Print `$PATH`, one entry per line |
| `reload` | Reload `~/.zshrc` in current shell |

---

## Function Reference

### mkd

Create a directory and immediately `cd` into it.

```
mkd <directory_name>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `directory_name` | `string` | yes | Path of the directory to create |

**Example:**
```bash
mkd projects/new-app
# equivalent to: mkdir -p projects/new-app && cd projects/new-app
```

---

### gmsg

Git commit with an auto-generated message if none is provided.

```
gmsg [commit_message]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `commit_message` | `string` | no | Custom commit message. Defaults to `New git commit from <user> on <timestamp>` |

**Errors:**
- Not inside a git repository → exits with error
- No staged changes → exits with error

**Example:**
```bash
git add .
gmsg "add login page"
gmsg               # uses auto-generated message
```

---

### ff

Find a file or directory by name, searching from filesystem root.

```
ff <filename>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `filename` | `string` | yes | Name (or glob) to search for |

**Example:**
```bash
ff ".env"
ff "*.log"
```

---

### fh

Find a file or directory by name, searching from home directory.

```
fh <filename>
```

Faster than `ff` for personal files.

**Example:**
```bash
fh "config.json"
```

---

### server

Start a local HTTP server in the current directory.

```
server [port]
```

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `port` | `integer` | no | `8000` | Port to listen on |

Uses `python3 -m http.server`. Falls back to `python -m SimpleHTTPServer` if python3 is unavailable.

**Example:**
```bash
server          # starts on port 8000
server 3000     # starts on port 3000
```

---

### weather

Fetch weather for any location.

```
weather [location]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `location` | `string` | no | City name, airport code, or coordinates. Defaults to auto-detected location. |

**Example:**
```bash
weather
weather "San Francisco"
weather "48.8566,2.3522"    # Paris by coordinates
```

---

### extract

Extract any archive format automatically.

```
extract <archive_file>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `archive_file` | `string` | yes | Path to the archive file |

**Supported formats:**

| Extension | Tool Used |
|---|---|
| `.tar.gz`, `.tgz` | `tar xzf` |
| `.tar.bz2`, `.tbz2` | `tar xjf` |
| `.tar` | `tar xf` |
| `.gz` | `gunzip` |
| `.bz2` | `bunzip2` |
| `.zip` | `unzip` |
| `.rar` | `unrar` |
| `.7z` | `7z` |
| `.Z` | `uncompress` |

**Example:**
```bash
extract archive.tar.gz
extract data.zip
```

---

### tmpd

Create a temporary directory and `cd` into it.

```
tmpd [prefix]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `prefix` | `string` | no | Optional name prefix for the temp directory |

**Example:**
```bash
tmpd            # creates /tmp/tmp.XXXXXXXX
tmpd debug      # creates /tmp/debug.XXXXXXXXXX
```

---

### targz

Create a `.tar.gz` archive of a directory, excluding `.DS_Store` files.

```
targz <directory>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `directory` | `string` | yes | Directory to archive |

**Output:** `<directory>.tar.gz` in the current working directory.

**Example:**
```bash
targz my-project
# creates: my-project.tar.gz
```

---

### fs

Show the size of a file or the total size of a directory.

```
fs [path ...]
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `path` | `string` | no | File or directory. Defaults to all items in current directory. |

**Example:**
```bash
fs                  # size of everything in current directory
fs ~/Downloads      # size of Downloads folder
fs file.log         # size of a single file
```

---

### dataurl

Convert a file into a base64 data URL.

```
dataurl <file>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `file` | `string` | yes | Path to any file (image, font, text, etc.) |

**Output:** Prints `data:<mime-type>;base64,<encoded-content>` to stdout.

**Example:**
```bash
dataurl logo.png
dataurl font.woff2
```

---

### getcertnames

Show the SSL certificate domains (CN + SANs) for any HTTPS domain.

```
getcertnames <domain>
```

| Parameter | Type | Required | Description |
|---|---|---|---|
| `domain` | `string` | yes | Domain to inspect (no `https://` prefix) |

**Example:**
```bash
getcertnames google.com
# output:
# *.google.com
# google.com
# ...
```

---

### DNS Utilities

A suite of `dig` wrappers for common DNS lookups.

| Function | Usage | Description |
|---|---|---|
| `digs` | `digs <domain>` | Short lookup — returns only the IP |
| `digx` | `digx <ip>` | Reverse lookup — IP to domain |
| `digmx` | `digmx <domain>` | MX (mail) records |
| `digns` | `digns <domain>` | NS (nameserver) records |
| `diga` | `diga <domain>` | A (IPv4) records |
| `digaaaa` | `digaaaa <domain>` | AAAA (IPv6) records |
| `digtxt` | `digtxt <domain>` | TXT records |
| `digtrace` | `digtrace <domain>` | Trace full DNS resolution path |
| `digga` | `digga <domain>` | All records, formatted |
| `digprop` | `digprop <domain>` | Check propagation (queries Google, Cloudflare, OpenDNS) |
| `digns_server` | `digns_server <domain> <ns>` | Query a specific nameserver |

**Examples:**
```bash
digs github.com                          # → 140.82.121.4
digx 8.8.8.8                            # → dns.google
digmx gmail.com                         # → mail servers
digprop mysite.com                       # check propagation across 3 resolvers
digns_server mysite.com 1.1.1.1         # query Cloudflare specifically
```

---

## Machine Configuration

### Adding a New Machine

1. Find your machine name:
   ```bash
   scutil --get ComputerName   # macOS
   hostname -s                 # Linux
   ```

2. Create the machine config file using `dummy-machine.zsh` as a template:
   ```bash
   cp zsh/machines/dummy-machine.zsh zsh/machines/<your-machine-name>.zsh
   ```

3. Add any machine-specific env vars, aliases, or PATH entries to that file.

4. Create a git identity file (see below).

5. Run the installer:
   ```bash
   ./install.sh local
   ```

No other files need to be modified. The machine file is loaded automatically.

---

### Git Identity per Machine

Each machine has its own git config file in `git/`.

**Filename format:** `git/.gitconfig.<machine-name>`

**Minimum required content:**
```ini
[user]
    name = Your Name
    email = you@example.com
[core]
    editor = vim
[color]
    ui = auto
```

If the file doesn't exist when `install.sh` runs, it will prompt you to enter your name and email and create it automatically.

The file is then symlinked to `~/.gitconfig`.

---

## Troubleshooting

| Problem | Diagnosis | Fix |
|---|---|---|
| Machine-specific config not loading | `echo $MACHINE_TYPE` — check the value | Ensure `zsh/machines/$MACHINE_TYPE.zsh` exists with that exact name |
| Wrong git identity | `git config user.email` | Check `git/.gitconfig.<machine-name>` and re-run `./install.sh local` |
| zsh not default shell | `echo $SHELL` — not `/bin/zsh` | Run `chsh -s $(which zsh)` then log out and back in |
| Symlink broken / pointing nowhere | `ls -la ~/.zshrc` | Re-run `./install.sh local` — it will back up and relink |
| Auto-update not running | `.last_update` may be recent | Delete `~/.dotfiles/.last_update` and open a new shell |
| Oh My Zsh not found | Shell errors on startup | Run `./install.sh local` — it installs Oh My Zsh if missing |
