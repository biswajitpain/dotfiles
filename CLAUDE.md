# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Biswajit's personal dotfiles for all his computers (macOS and Linux). It serves two purposes: syncing shell environment across machines (zsh, vim, tmux, git via symlinks from `~/.dotfiles` into `$HOME`), and acting as a curated library of aliases, commands, and utility functions he uses daily. The install script handles cloning, symlinking, and Oh My Zsh setup.

## Install / Apply Changes

`bootstrap.sh` is the entry point for a new machine: it installs binaries, links
dotfiles (by calling `install.sh`), and renders credential-bearing configs.
`install.sh` remains the symlink/Oh-My-Zsh layer and is safe to run on its own.

```bash
# Brand-new macOS or Linux machine — installs everything, interactively
bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/bootstrap.sh)"

# Already cloned
./bootstrap.sh                  # full run
./bootstrap.sh --yes            # accept all defaults, no prompts
./bootstrap.sh --only cloud     # re-render aws/kube/azure configs
./bootstrap.sh --only identity  # git name/email, SSH key, signing
./bootstrap.sh --no-packages    # skip binary installation

# Symlinks / Oh My Zsh only
./install.sh local

# Verify nothing sensitive is in the repo
./scripts/audit-repo.sh
./scripts/audit-repo.sh --history

# Reload zsh config in current shell
source ~/.zshrc
```

## Secrets Architecture — The Rule

**The repo holds templates only.** Anything that could carry a credential or an
environment trace is rendered at bootstrap time into `$DOTFILES_LOCAL_DIR`
(default `~/.dotfiles-local`), which is **outside the repo**. That location is
the whole point: a `.gitignore` mistake or a `git add -f` cannot leak it.

| Kind | Template (tracked) | Rendered (never tracked) |
|---|---|---|
| AWS CLI | `templates/aws/config.template` | `~/.dotfiles-local/aws/config` |
| kubeconfig | `templates/kube/config.template` | `~/.dotfiles-local/kube/config` |
| Git identity | `templates/git/gitconfig.template` | `~/.dotfiles-local/git/gitconfig` |
| Azure subs | `config/azure-subscriptions.env.template` | `~/.dotfiles-local/config/azure-subscriptions.env` |

`$HOME` symlinks point at the rendered files (`~/.aws/config`, `~/.kube/config`,
`~/.gitconfig`), so tools see them normally.

Three layers enforce this:

1. **`.gitignore`** denies `aws/*`, `kube/*`, `config/*`, `git/.gitconfig.*` and
   re-includes only `*.template`. Never add a `!aws/config`-style exception.
2. **`git/hooks/pre-commit`** blocks forbidden paths and cloud identifiers
   (AKIA keys, role ARNs, `external_id`, kube CA data, cluster endpoints).
3. **`scripts/audit-repo.sh`** is the backstop; `--history` scans every blob.

Adding a new credential-bearing config: commit a `*.template` with `{{PLACEHOLDER}}`
markers, render it in `bootstrap.sh`'s `stage_cloud`/`stage_identity`, and add the
real path to the hook's `FORBIDDEN_PATHS` and the audit's forbidden list.

## Package Manifests

`packages/brew.txt`, `brew-cask.txt`, `apt.txt`, `dnf.txt` — one package per line,
`#` comments ignored. Edit these rather than editing `bootstrap.sh`. Cloud CLIs on
Linux come from vendor sources (`install_linux_cloud_tools`) because distro
packages lag; Node always comes from nvm, never a package manager.

## How Machine Detection Works

This is the core architectural concept. There is **no static machine type file** — the machine key is resolved at shell startup every time by `scripts/detect-machine.sh`, which is the single source of truth (both `.zshrc` and `install.sh` call it, so they cannot drift apart).

The canonical key is `<hostname-slug>-<salted-hash-of-hardware-serial>`, e.g. `pro-78827b30ddc1`. The 12-hex hash is the actual identity; the hostname prefix exists purely to make filenames readable:

- **macOS**: serial via `ioreg -c IOPlatformExpertDevice` — deliberately not `system_profiler SPHardwareDataType`, which costs ~75ms vs ~4ms and this runs on every interactive shell
- **Linux**: `/sys/class/dmi/id/product_serial` if readable, else `/etc/machine-id`
- **Fallback**: slugified short hostname, if there is no serial and no SHA-256 tool

**Why hashed, not the raw serial:** this repo is public, and a serial is a permanent identifier that cannot be rotated. The salt in `detect-machine.sh` is *not* secret (it is committed alongside); it only stops the key being a bare hash resolvable from a generic precomputed table. Treat the key as "the serial is not published in plaintext", not as cryptographically secret.

**Why not `ComputerName`:** it is user-editable in System Settings, disagrees with `LocalHostName`, and on the personal MacBook returns `Biswajit’s MacBook Pro` — two spaces plus a curly apostrophe (U+2019), which makes a miserable filename and produced stray untracked files.

`$MACHINE_TYPE` is exported and used to load `zsh/machines/$MACHINE_TYPE.zsh`. `_load_machine_config` in `.zshrc` resolves in this order:

1. `<slug>-<hash>.zsh` — canonical
2. `*-<hash>.zsh` — **hash-suffix glob**, so ANY human prefix resolves. This is what makes the readable prefix safe: renaming the prefix, or renaming the host, never orphans a machine's config
3. `<hash>.zsh` — the earlier bare-hash scheme
4. legacy names (`ComputerName`, then `hostname -s`)

`$MACHINE_CONFIG` records which name loaded. `machine-info` distinguishes a prefix rename (informational) from a genuinely stale filename (prints the `mv`).

The prefix comes from `LocalHostName` on macOS / `hostname -s` on Linux — never `ComputerName`, which is not filename-safe.

Setting `MACHINE_TYPE` in the environment overrides all of the above.

## Config Load Order in `.zshrc`

1. Oh My Zsh (`bira` theme, plugins: `git aws docker kubectl`)
2. `zsh/common/aliases/general.zsh`
3. `zsh/common/functions/utils.zsh`
4. `zsh/common/functions/check_dotfiles_update.zsh`
5. OS-specific: `zsh/os/macos/` or `zsh/os/linux/`
6. Machine-specific: `zsh/machines/$MACHINE_TYPE.zsh`, else a legacy-name fallback

## Adding a New Machine

1. On that machine, run `machine-info` (or `./scripts/detect-machine.sh`) to get its canonical key
2. Create `zsh/machines/<key>.zsh` — use `dummy-machine.zsh` as a template. Add a comment naming the machine in human terms, since the key itself is opaque; **do not record the serial** in the file
3. Do **not** create a `git/.gitconfig.<key>` in the repo — identities are no
   longer tracked. Run `./bootstrap.sh --only identity` on that machine and it
   renders `~/.dotfiles-local/git/gitconfig` from the template.

## Migrating a Machine to the Serial-Hash Key

Machines still using an old name keep working via the legacy fallback, so this is not urgent. To migrate one, run `machine-info` on it — when it loaded via a legacy name it prints the exact `mv` command. Then rename its `git/.gitconfig.<old>` to match and re-run `./install.sh local` to repoint `~/.gitconfig`.

Not yet migrated (they still carry pre-hash names): `mac-pro`, `office-mac1`, `office-mac2`, `linux-vm1`, `linux-vm2`. `office-mac1.zsh` is the only one with real content.

## Auto-Update Mechanism

`check_dotfiles_update` runs in the background on every interactive shell. It checks `~/.dotfiles/.last_update` (ignored by git) and fetches from `origin/main` weekly. If behind, it pulls and re-runs `install.sh`.

## Gitignored Files

`.last_update` — timestamp for weekly update check  
`.machine_type` — legacy file, no longer used  
`.claude/` — local Claude Code settings  
`aws/*`, `kube/*`, `config/*`, `git/.gitconfig.*` — denied by default; only
`*.template` is re-included. See **Secrets Architecture** above.

## Symlinks Created by install.sh

| Symlink | Source | Tracked in git? |
|---|---|---|
| `~/.zshrc` | `dotfiles/zsh/.zshrc` | yes |
| `~/.vimrc` | `dotfiles/vim/.vimrc` | yes |
| `~/.tmux.conf` | `dotfiles/tmux/.tmux.conf` | yes |
| `~/.ssh/config` | `dotfiles/ssh/config` | yes |
| `~/.gitconfig` | `~/.dotfiles-local/git/gitconfig` | **no** |
| `~/.aws/config` | `~/.dotfiles-local/aws/config` | **no** |
| `~/.kube/config` | `~/.dotfiles-local/kube/config` | **no** |

The bottom three are rendered from `templates/` by `bootstrap.sh`. `install.sh`
only links them if they already exist, so re-running it never clobbers them.

Before linking, existing files are backed up to `~/.dotfiles_backup/<timestamp>/`.
