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

# Run the test suite (no dependencies; never touches the real $HOME)
./tests/run-tests.sh
./tests/run-tests.sh install hook   # only files matching these substrings

# Reload zsh config in current shell
source ~/.zshrc
```

## Tests

`tests/` holds a dependency-free suite — no bats, no shunit2 — because it has to
run on a freshly imaged machine, before `bootstrap.sh` has installed anything.
Its job includes verifying the installer, so it cannot depend on the installer.
CI runs it on macOS and Linux (`.github/workflows/test.yml`). See `tests/README.md`.

**The safety rule: no test ever touches the real `$HOME`.** Anything that writes
runs in a sandbox from `sandbox_new`, which repoints `HOME`, `DOTFILES_DIR` and
`DOTFILES_LOCAL_DIR` into a temp dir. Every write helper calls `assert_sandboxed`,
which aborts the run if `HOME` escapes. Tests use `zsh -c`, not `zsh -i`, so the
background update check never fires and nothing hits the network.

Changing behaviour means changing a test. In particular:

- **Adding an alias or function**: add it to `tests/contract/core-features.txt`.
  That file is the deliberate half of the contract — `test_040` separately proves
  that everything the repo *declares* survives a shell load, but only the contract
  file makes a *deletion* fail the build.
- **Changing `SALT` or `KEY_LEN`** in `detect-machine.sh`: `test_020` fails on
  purpose. Both define every filename in `zsh/machines/`, so changing either
  orphans every machine's config on every machine. The failing test is the moment
  to notice, not afterwards.
- **Adding a credential-bearing config**: add the real path to the hook's
  `FORBIDDEN_PATHS`, to the audit's forbidden list, *and* to `test_060`/`test_070`.
  A scanner rule with no test is a rule that can silently stop matching — that is
  exactly how rule 3 of the hook came to match nothing but `AZ_SUB_*`.
- **Touching `install.sh` link/backup logic**: `test_050` covers the two ways it
  has gone wrong — a dangling symlink aborting the whole run under `set -e`, and
  two runs inside the same second sharing a timestamped backup directory and
  destroying the user's original file.

A green suite proves nothing unless it goes red when the code breaks. Check that
by mutation: copy the repo to a scratch dir, break one thing, confirm the right
file fails.

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

Four layers enforce this:

1. **`.gitignore`** denies `aws/*`, `kube/*`, `config/*`, `git/.gitconfig.*` and
   re-includes only `*.template`. Never add a `!aws/config`-style exception.
2. **`git/hooks/pre-commit`** blocks forbidden paths and cloud identifiers
   (AKIA keys, role ARNs, `external_id`, kube CA data, cluster endpoints).
3. **`scripts/audit-repo.sh`** is the backstop; `--history` scans every blob.
4. **`tests/`** proves layers 1–3 still work, from both sides: the bad thing is
   blocked *and* the legitimate lookalike still goes through. A scanner that
   cries wolf gets bypassed with `--no-verify`, which is the same as not having
   one.

A corollary that is easy to lose: nothing credential-bearing may be *sited*
inside the repo, even untracked. `scripts/az-aliases.sh` once defaulted
`AZURE_CONFIG_DIR` to `config/azure` in the repo, which put `msal_token_cache.json`
— live OAuth tokens — in a public checkout behind nothing but a `.gitignore`
line. It now defaults into `$DOTFILES_LOCAL_DIR/azure`, and `test_080` enforces
that.

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

Split in two halves, and **nothing is automatic**.

`dotfiles_update_notice` runs synchronously at shell start: it just prints
whatever `.update_notice` holds. One file read, no network, so it cannot arrive
after the prompt has been drawn and garble the terminal.

`check_dotfiles_update` is backgrounded (`&!` — background *and* disown, so zsh
prints neither the start nor the completion notice). At most once a week, gated
by `.last_update`, it does a read-only `git fetch` and records whether the
checkout is behind. It prints nothing, **never pulls, and never runs
`install.sh`** — an earlier version did both unattended on every interactive
shell, which is remote code execution on a schedule.

Applying an update is an explicit human action: `dotfiles-update` shows what is
incoming, asks, then pulls with `--ff-only` and re-links. `--ff-only` is load-
bearing: when upstream history has been rewritten it fails loudly instead of
merging two unrelated histories. `test_090` covers all of this.

## Gitignored Files

`.last_update` — timestamp for weekly update check  
`.update_notice` — pending-update message shown at next shell start  
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
