# Dotfiles

Shell environment for macOS and Linux — zsh, vim, tmux, git — plus a single
command that takes a brand-new machine from nothing to fully configured.

**The one rule that shapes everything here: this repository is public, so it
contains templates only.** No credential, no account ID, no cluster endpoint and
no identity is tracked in git. Real configs are generated on each machine into a
directory *outside* the repo. If you read only one section, read
[How secrets are kept out of git](#how-secrets-are-kept-out-of-git).

---

## Contents

- [What this is](#what-this-is)
- [The three problems it solves](#the-three-problems-it-solves)
- [Quick start](#quick-start)
- [What `bootstrap.sh` actually does](#what-bootstrapsh-actually-does)
- [Command reference](#command-reference)
- [How secrets are kept out of git](#how-secrets-are-kept-out-of-git)
- [How a machine identifies itself](#how-a-machine-identifies-itself)
- [Local overrides](#local-overrides)
- [What gets installed](#what-gets-installed)
- [Shell config load order](#shell-config-load-order)
- [File map](#file-map)
- [Symlinks](#symlinks)
- [Common tasks](#common-tasks)
- [Updating](#updating)
- [SSH configuration](#ssh-configuration)
- [Troubleshooting](#troubleshooting)
- [If something leaks](#if-something-leaks)
- [FAQ](#faq)

---

## What this is

Three things in one repository:

1. **A shell environment** — zsh (via Oh My Zsh), vim, tmux and git config,
   symlinked from this repo into `$HOME`, so every machine behaves the same.
2. **A machine initializer** — `bootstrap.sh`, which installs a full toolchain
   (languages, cloud CLIs, Kubernetes tools) and wires up identity and cloud
   credentials interactively.
3. **A guardrail system** — a `.gitignore` that denies by default, a pre-commit
   secret scanner, and an audit script, so sensitive values cannot reach GitHub
   even by accident.

Supported on macOS and Linux. Written for **bash 3.2** (the version macOS still
ships), and every shell script passes `shellcheck` with zero errors and zero
warnings.

---

## The three problems it solves

Understanding these makes the rest of the design obvious.

**Problem 1: a public dotfiles repo is a leak waiting to happen.** The natural
thing is to commit `~/.aws/config` and `~/.kube/config` so they sync across
machines. But those files hold AWS account IDs, role ARNs, role `external_id`
values and cluster API endpoints. Once pushed to a public repo they are permanent
— `git rm` does not remove them from history. So: **the repo stores templates,
and the real files are generated outside it.**

**Problem 2: machines need stable names, and hostnames are not stable.**
`scutil --get ComputerName` on macOS is user-editable, disagrees with
`LocalHostName`, and commonly contains spaces and a curly apostrophe (`Alex's
MacBook Pro`) — a terrible filename. So: **machine identity comes from a hash of
the hardware serial**, which never changes and is always filesystem-safe.

**Problem 3: setting up a new machine by hand is slow and drifts.** Fifty
`brew install` lines that differ per machine, a forgotten `JAVA_HOME`, an SSH key
that was never generated. So: **package lists are declarative manifests**, and
`bootstrap.sh` is idempotent — re-running it repairs a machine rather than
breaking it.

---

## Quick start

### Brand-new machine

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/bootstrap.sh)"
```

That clones the repo to `~/.dotfiles`, installs the package manager if missing,
installs the toolchain, links the dotfiles, and then asks you a short series of
questions (git name and email, whether to generate an SSH key, cloud account IDs).

**Every prompt has a default — press Enter to accept or skip it.** Nothing is
mandatory; you can fill anything in later by re-running a single stage.

Expect it to take 10–20 minutes on a fresh machine, mostly downloading packages.
You will be asked for your password once or twice (Homebrew on macOS, `sudo` for
packages on Linux).

### Machine that already has the repo

```bash
cd ~/.dotfiles
./bootstrap.sh
```

### Just one part

```bash
./bootstrap.sh --only packages    # install/refresh binaries
./bootstrap.sh --only identity    # git identity, SSH key, commit signing
./bootstrap.sh --only cloud       # regenerate AWS/kube/Azure configs
./bootstrap.sh --only link        # re-create symlinks only
./bootstrap.sh --only verify      # audit + report current state
```

### Unattended

```bash
./bootstrap.sh --yes
```

Takes every default and asks nothing. Prompts with no safe default — cloud account
IDs — are left as `{{PLACEHOLDER}}` markers for you to fill in later with
`./bootstrap.sh --only cloud`.

---

## What `bootstrap.sh` actually does

Six stages, in order. Each is independently runnable with `--only <stage>`.

| Stage | What happens |
|---|---|
| `packages` | Detects the OS and package manager. Installs Homebrew if missing on macOS. Reads the matching `packages/*.txt` manifest and installs it. On Linux, additionally installs Go, Corretto 21 and the cloud CLIs from vendor sources, because distro packages are too old or absent. |
| `link` | Runs `install.sh`, which installs Oh My Zsh if needed, backs up any existing dotfiles to `~/.dotfiles_backup/<timestamp>/`, and creates the symlinks. |
| `identity` | Asks for git name and email. Offers to generate an `ed25519` SSH key named after the machine key. Offers to enable SSH commit signing, and writes `~/.ssh/allowed_signers` so you can verify your own signatures. Renders `~/.dotfiles-local/git/gitconfig` and writes `~/.ssh/config.local`. Prints the public key for you to paste into GitHub. |
| `cloud` | Asks for AWS regions, account IDs and the DR `external_id`. Renders `~/.dotfiles-local/aws/config` and links `~/.aws/config` to it. Optionally creates a kubeconfig placeholder and copies the Azure subscription template. |
| `node` | Installs nvm if missing, then Node LTS, sets it as the default, and appends the nvm init lines to this machine's `zsh/machines/<key>.zsh`. |
| `verify` | Runs `scripts/audit-repo.sh`, then prints the machine key, every symlink and its target, and every expected binary with its path or `(not installed)`. |

Everything is guarded. Already have Node? It says so and moves on. Already have a
`~/.gitconfig` you wrote by hand? It backs it up first. Ran out of patience and
skipped the cloud prompts? Re-run `--only cloud` later.

---

## Command reference

### Scripts

| Command | Purpose |
|---|---|
| `./bootstrap.sh` | Full machine setup. See flags above. |
| `./install.sh local` | Symlinks and Oh My Zsh only. Safe to re-run; never overwrites your identity. |
| `./scripts/audit-repo.sh` | Scan tracked files for credentials and infrastructure identifiers. Exit 0 = clean. Safe for CI. |
| `./scripts/audit-repo.sh --history` | Also scan every blob in git history. Slow, but this is what catches things already pushed. |
| `./scripts/detect-machine.sh` | Print this machine's canonical key. |
| `./scripts/detect-machine.sh --explain` | Show the serial, the key, legacy names and which filenames they map to. |

### Shell functions (available in any interactive shell)

| Function | Purpose |
|---|---|
| `machine-info` | How this machine is identified, which config file actually loaded, and — for a genuinely stale filename — the exact `mv` to migrate it. |
| `langs` | Which language toolchains and cloud CLIs this machine actually has, with paths. |
| `dotfiles-update` | Show incoming commits and a diffstat, ask for confirmation, then pull and re-link. **The only way updates are applied.** |

---

## How secrets are kept out of git

Real configs are rendered into **`$DOTFILES_LOCAL_DIR`** — default
`~/.dotfiles-local`, directory mode `700`, files mode `600`.

That directory is deliberately **outside the repository**. A `.gitignore` entry
would be enough in theory, but being outside the repo means no `.gitignore`
mistake, no `git add -f`, and no future refactor can publish these files. It is a
structural guarantee rather than a rule someone has to remember.

```
~/.dotfiles/                 (git repo — templates, safe to publish)
   templates/aws/config.template          ← {{AWS_ACCOUNT_PROD}} placeholders
              ↓  rendered by bootstrap.sh
~/.dotfiles-local/           (NOT a git repo — real values, mode 700)
   aws/config                             ← real account IDs
              ↑  symlinked from
~/.aws/config                (what the AWS CLI actually reads)
```

| | Template (tracked) | Rendered (never tracked) |
|---|---|---|
| AWS CLI | `templates/aws/config.template` | `~/.dotfiles-local/aws/config` |
| kubeconfig | `templates/kube/config.template` | `~/.dotfiles-local/kube/config` |
| Git identity | `templates/git/gitconfig.template` | `~/.dotfiles-local/git/gitconfig` |
| Shell overrides | `templates/zsh/local.zsh.template` | `~/.dotfiles-local/zsh/local.zsh` |
| Azure subs | `config/azure-subscriptions.env.template` | `~/.dotfiles-local/config/azure-subscriptions.env` |
| SSH local | generated by bootstrap | `~/.ssh/config.local` |

### Three enforcement layers

**1. `.gitignore` denies by default.** `aws/*`, `kube/*`, `config/*` and
`git/.gitconfig.*` are ignored, and only `*.template` is re-included. Never add a
`!aws/config`-style exception — the audit script fails the build if one reappears.

**2. `git/hooks/pre-commit` blocks the content.** Installed globally through
`core.hooksPath`, so it guards every repo on the machine, not just this one. It
refuses commits containing:

- forbidden paths (`aws/config`, `kube/config`, per-machine gitconfigs)
- `AKIA…` access key IDs and `aws_secret_access_key`
- role ARNs containing a 12-digit account ID
- `external_id = …`
- kubeconfig `certificate-authority-data`, `client-key-data`, `server: https://…`
- `-----BEGIN … PRIVATE KEY-----`
- generic `SECRET`/`PASSWORD`/`API_KEY`/`TOKEN` assignments
- real-looking UUIDs inside `*.template` files

Templates, docs and the audit script itself are exempt, since they legitimately
show these shapes.

**3. `scripts/audit-repo.sh` is the backstop.** It catches what is already
committed and anything the hook's patterns miss. Run it before you push.

### Adding a new credential-bearing config

1. Commit a `*.template` with `{{PLACEHOLDER}}` markers.
2. Render it in `bootstrap.sh` (`stage_cloud` or `stage_identity`).
3. Add the real path to `FORBIDDEN_PATHS` in the hook and to the forbidden list in
   `scripts/audit-repo.sh`.

> **Why kubeconfigs are not templated with real values:** a kubeconfig is
> generated by your cloud CLI, and its endpoints and CA data are traces. The repo
> ships the regeneration recipe instead — `aws eks update-kubeconfig`,
> `az aks get-credentials`, `gcloud container clusters get-credentials`.

---

## How a machine identifies itself

`scripts/detect-machine.sh` is the single source of truth. Both `.zshrc` and
`install.sh` call it, so they cannot drift apart.

```
macOS  →  ioreg -c IOPlatformExpertDevice        (serial; ~4ms)
Linux  →  /sys/class/dmi/id/product_serial, else /etc/machine-id
          ↓
    sha256("<salt>:<serial>")  →  first 12 hex  →  78827b30ddc1
          ↓
    prefix with the hostname                  →  pro-78827b30ddc1
```

That key names the machine's files: `zsh/machines/pro-78827b30ddc1.zsh`.

**The prefix is a label; the hash is the identity.** Lookup matches on the hash
*suffix*, so any prefix resolves — rename `pro-<hash>.zsh` to `laptop-<hash>.zsh`,
or rename the host itself, and the file is still found. That is what makes the
readable name safe: the hostname is back in the filename for your benefit, but
nothing depends on it. `machine-info` reports a drifted prefix as informational,
not as a problem.

The prefix comes from `LocalHostName` on macOS (System Settings guarantees it is
DNS-safe) or `hostname -s` on Linux — never `ComputerName`, which can contain
spaces and a curly apostrophe.

**Why `ioreg` and not `system_profiler`?** This runs on every interactive shell.
`ioreg` costs about 4ms; `system_profiler SPHardwareDataType` costs about 75ms.
Total detection overhead is roughly 13ms, so no caching is needed.

**Why hash the serial instead of using it directly?** This repo is public, and a
serial number is a permanent identifier you cannot rotate — useful for
social-engineering a vendor's support desk, and it reveals the exact model. The
salt lives in the script, so it is **not a secret**; it only stops the key being a
bare hash that a generic precomputed table would resolve. Treat the key as "the
serial is not published in plaintext", not as cryptographically secret.

**Resolution order.** `.zshrc` tries, in turn:

1. `<slug>-<hash>.zsh` — canonical
2. `*-<hash>.zsh` — any prefix, matched on the hash suffix
3. `<hash>.zsh` — the earlier bare-hash scheme
4. legacy names (`ComputerName`, then `hostname -s`)

So a machine that has not been migrated keeps working instead of silently losing
its config. `$MACHINE_CONFIG` records which name won. `machine-info` treats a
different prefix as informational and only prints an `mv` for cases 3 and 4.

**Override.** Setting `MACHINE_TYPE` in the environment beats all of the above.

---

## Local overrides

Anything host-specific — internal hostnames, jump hosts, employer directory
layouts, one-off aliases — belongs in a file the repo never sees:

```bash
mkdir -p ~/.dotfiles-local/zsh
cp templates/zsh/local.zsh.template ~/.dotfiles-local/zsh/local.zsh
$EDITOR ~/.dotfiles-local/zsh/local.zsh
```

`.zshrc` sources it **last**, so it can override anything above it. Matching SSH
`Host` blocks go in `~/.ssh/config.local`, which is also untracked.

This is the escape hatch that keeps the tracked machine files clean. If you find
yourself wanting to commit a hostname, put it here instead.

---

## What gets installed

Edit `packages/*.txt` rather than the script. One entry per line; `#` comments and
inline comments are stripped.

| Manifest | Used on |
|---|---|
| `packages/brew.txt` | macOS — Homebrew formulae |
| `packages/brew-cask-cli.txt` | macOS — CLI tools Homebrew only ships as casks (Corretto 21, gcloud). **Always installed.** |
| `packages/brew-cask.txt` | macOS — GUI apps (iTerm2, VS Code, Docker). Behind a prompt, or `--casks`. |
| `packages/apt.txt` | Debian, Ubuntu |
| `packages/dnf.txt` | Fedora, RHEL |
| `packages/pacman.txt` | Arch |

**Languages** — Node (via nvm, so versions are switchable), Python 3.12 + pipx,
Amazon Corretto 21, Go

**Cloud** — AWS CLI v2, Azure CLI, Google Cloud SDK

**Kubernetes** — kubectl, kubectx/kubens, helm, kustomize, stern, k9s

**Tools** — jq, yq, ripgrep, fd, bat, fzf, eza, gh, git-delta, lazygit, direnv,
zoxide, sops, age, dive, httpie, tldr, htop, tree

### Things that deliberately bypass the package manager

| Tool | Why |
|---|---|
| Node | nvm instead, so versions are switchable per project |
| Go on Linux | vendor tarball — distro packages lag badly |
| Cloud CLIs on Linux | vendor repos, same reason |
| Corretto 21 on Linux | Amazon's own apt/yum repo; not in distro repos |
| Terraform | left homebrew-core when it moved to the BUSL license, so it comes from `hashicorp/tap`. `opentofu` is in core if you prefer it. |

Run `langs` to see what a machine actually has.

### Platform coverage

| | macOS | Debian/Ubuntu | Fedora/RHEL | Arch |
|---|---|---|---|---|
| Shell config | ✅ | ✅ | ✅ | ✅ |
| Core tools | ✅ | ✅ | ✅ | ✅ |
| Java (Corretto 21) | cask | Amazon apt repo | Amazon yum repo | manual (AUR) |
| gcloud | cask | Google apt repo | Google yum repo | manual |
| Terraform | `hashicorp/tap` | HashiCorp apt repo | manual | manual |

---

## Shell config load order

Every interactive shell loads these in order. Later files override earlier ones,
and each is loaded only if it exists.

| # | File | Purpose |
|---|---|---|
| 1 | Oh My Zsh | `bira` theme; plugins `git aws docker kubectl` |
| 2 | `zsh/common/aliases/general.zsh` | cross-machine aliases |
| 3 | `zsh/common/functions/utils.zsh` | utility functions, `machine-info` |
| 4 | `zsh/common/functions/codesign.zsh` | code signing helpers |
| 5 | `zsh/common/functions/languages.zsh` | `JAVA_HOME`, Go, Python, direnv/zoxide/gcloud shims, `langs` |
| 6 | `zsh/common/functions/check_dotfiles_update.zsh` | update notice, `dotfiles-update` |
| 7 | `scripts/az-aliases.sh` | Azure subscription switching |
| 8 | `zsh/os/macos/` or `zsh/os/linux/` | OS-specific config |
| 9 | `zsh/machines/$MACHINE_TYPE.zsh` | machine-specific config (hash-suffix match, then legacy names) |
| 10 | `~/.dotfiles-local/zsh/local.zsh` | **local, untracked overrides — always last** |

`PATH` additions are guarded, so re-running `source ~/.zshrc` does not grow `PATH`.

---

## File map

```
bootstrap.sh                    interactive from-scratch initializer
install.sh                      symlinks + Oh My Zsh (called by bootstrap)

packages/                       declarative package manifests, one per manager
templates/                      templates for everything credential-bearing
  aws/config.template
  kube/config.template
  git/gitconfig.template
  zsh/local.zsh.template

scripts/
  detect-machine.sh             machine key resolution (single source of truth)
  audit-repo.sh                 credential and trace audit
  az-aliases.sh                 Azure subscription helpers

git/hooks/pre-commit            secret scanner, installed globally

zsh/
  .zshrc                        entry point
  common/aliases/               cross-machine aliases
  common/functions/             cross-machine functions
  os/macos/, os/linux/          OS-specific config
  machines/<key>.zsh            machine-specific config

ssh/config                      safe SSH defaults (Includes ~/.ssh/config.local)
vim/.vimrc  tmux/.tmux.conf
config/azure-subscriptions.env.template

CLAUDE.md                       notes for AI assistants working in this repo
DOCS.md                         long-form reference and runbooks
```

---

## Symlinks

| Symlink | Points to | In git? |
|---|---|---|
| `~/.zshrc` | `~/.dotfiles/zsh/.zshrc` | yes |
| `~/.vimrc` | `~/.dotfiles/vim/.vimrc` | yes |
| `~/.tmux.conf` | `~/.dotfiles/tmux/.tmux.conf` | yes |
| `~/.ssh/config` | `~/.dotfiles/ssh/config` | yes |
| `~/.gitconfig` | `~/.dotfiles-local/git/gitconfig` | **no** |
| `~/.aws/config` | `~/.dotfiles-local/aws/config` | **no** |
| `~/.kube/config` | `~/.dotfiles-local/kube/config` | **no** |

Existing files are moved to `~/.dotfiles_backup/<timestamp>/` before linking.

---

## Common tasks

**Set up a new machine**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/bootstrap.sh)"
```

**Add a tool to every machine**

```bash
echo 'ripgrep-all' >> packages/brew.txt      # and the other manifests
./bootstrap.sh --only packages
```

**Add config for one machine only**

```bash
machine-info                                  # get the key, e.g. pro-78827b30ddc1
$EDITOR zsh/machines/<key>.zsh                # commit this
```

The filename already names the host, so an identifying comment is optional.
**Do not record the serial.**

**Add something that must not be committed**

```bash
cp templates/zsh/local.zsh.template ~/.dotfiles-local/zsh/local.zsh
$EDITOR ~/.dotfiles-local/zsh/local.zsh
```

**Change your git identity or rotate your SSH key**

```bash
./bootstrap.sh --only identity
```

**Fill in cloud account IDs you skipped**

```bash
./bootstrap.sh --only cloud
```

**Check before pushing**

```bash
./scripts/audit-repo.sh
```

**Move a machine onto the serial-hash key**

```bash
machine-info        # prints the exact mv command when a legacy name was used
```

---

## Updating

Updates are **never applied automatically.** A background check runs at most once
a week, fetches read-only, and writes a one-line notice that the *next* shell
displays:

```
dotfiles: 3 commit(s) behind origin/main. Run: dotfiles-update
```

```bash
dotfiles-update     # review the incoming diff, confirm, pull, re-link
```

### Why it works this way

An earlier version pulled `origin/main` and then executed `install.sh`, unattended,
in a background job on every interactive shell. That is remote code execution on a
schedule: anything reaching `origin/main` — a compromised account, a bad merge, a
force-push — would run on every machine with no review and no signature check. It
now only ever fetches.

The check is also split in two so a login shell stays quiet and fast: displaying
the notice is a synchronous file read, while the network fetch is backgrounded
with zsh's `&!` (background *and* disown). Plain `&` under job control prints a
`[3] 56005` job line on every login, and merely setting `no_monitor` still lets
the `[2] + done …` completion notice through.

---

## SSH configuration

`ssh/config` is tracked and holds safe defaults only. Anything local or
host-specific belongs in `~/.ssh/config.local`, which bootstrap generates and git
never sees.

Three settings were removed deliberately. Read this before putting them back:

| Removed | Why it was a problem |
|---|---|
| `StrictHostKeyChecking no` | Accepted **any** host key without prompting, silently defeating SSH's only protection against man-in-the-middle. Now `accept-new`: still no prompt on first contact, but it refuses to connect if a known host's key ever changes — the case that actually matters. |
| `ForwardAgent yes` under `Host *` | Forwarding your agent to *every* host lets root on any box you connect to use your keys to authenticate onward as you. Now off globally; enable it per-host, or use `ProxyJump`, which needs no forwarding at all. |
| `HostkeyAlgorithms +ssh-rsa` and `PubkeyAcceptedAlgorithms +ssh-rsa` | That is RSA with SHA-1, disabled by default in OpenSSH 8.8 because collisions are practical. Re-enabling globally weakened every connection for the sake of a few legacy servers. Scope the exception to the one host that needs it. |

Also added: `IdentitiesOnly yes` (stops offering every key in your agent to every
server), `HashKnownHosts`, and connection multiplexing.

`UseKeychain` is macOS-only — older OpenSSH on Linux treats an unknown keyword as
fatal — so bootstrap writes it into `config.local` on macOS only. Because
`IdentitiesOnly yes` means only listed keys are offered, `config.local` also names
your per-machine key; without it, git over SSH would stop working.

Check your config parses with:

```bash
ssh -G github.com >/dev/null && echo ok
```

---

## Troubleshooting

| Symptom | Diagnose with | Fix |
|---|---|---|
| Machine config not loading | `machine-info` — compare `canonical key` with `config loaded` | Create `zsh/machines/<key>.zsh`; `machine-info` prints the `mv` to migrate |
| Wrong git identity | `git config user.email` | `./bootstrap.sh --only identity` |
| A tool is missing | `langs` | `./bootstrap.sh --only packages` |
| `~/.aws/config` missing or empty | `ls -la ~/.aws/config` | `./bootstrap.sh --only cloud` |
| Unfilled `{{PLACEHOLDER}}` in a config | `grep -r '{{' ~/.dotfiles-local` | `./bootstrap.sh --only cloud` |
| Commit signing fails | `ssh-add -l`; check `~/.ssh/allowed_signers` | Add the key to GitHub as **both** an Authentication key and a Signing key |
| `[3] 56005` on login | — | Already fixed; make sure `~/.zshrc` is the current symlink |
| Update notice will not clear | `cat ~/.dotfiles/.update_notice` | `rm ~/.dotfiles/.update_notice`, or run `dotfiles-update` |
| zsh not the default shell | `echo $SHELL` | `chsh -s $(which zsh)`, then log out and back in |
| Broken or missing symlink | `ls -la ~/.zshrc` | `./install.sh local` |
| SSH rejects the config | `ssh -G github.com` | Check `~/.ssh/config.local` |
| `PATH` has duplicates | `echo $PATH \| tr : '\n' \| sort \| uniq -d` | Open a new shell; additions are guarded |

More detail, including runbooks, is in [DOCS.md](DOCS.md).

---

## If something leaks

`git rm --cached` removes a file from the *current* commit only. Every earlier
commit still has it, and on a public repo it stays fetchable — including from
forks and cached views. **Untracking is necessary but not sufficient.**

Order matters:

1. **Rotate first.** Rotation is what ends the exposure. A history rewrite takes
   time and can be undone by anyone holding an old clone.
   - AWS `external_id` → generate a new one, update the trust policy on both sides
   - Account IDs and role ARNs → cannot be rotated. Confirm every trust policy
     requires an ExternalId or a specific principal, and that nothing is
     assumable by `*`
   - Kubeconfig CA data → not secret alone, but confirm the API endpoints are not
     publicly reachable
2. **Then rewrite**, with `git filter-repo` (not the deprecated `filter-branch`).
3. **Then verify** with `./scripts/audit-repo.sh --history`.

Full runbook, including what a rewrite does *not* fix: [DOCS.md](DOCS.md) →
"Purging a leaked file from history".

---

## FAQ

**Do I have to answer every prompt?**
No. Every prompt has a default, and Enter skips it. Anything skipped can be filled
in later with `./bootstrap.sh --only <stage>`.

**Is it safe to run `bootstrap.sh` twice?**
Yes — that is the intended way to repair a machine or add something you skipped.
It is idempotent: existing tools are detected and skipped, and existing configs
are backed up before being replaced.

**Can I use this repo as-is?**
Fork it, then replace the identity-specific parts: `DOTFILES_REPO` in
`bootstrap.sh` and `install.sh`, the salt in `scripts/detect-machine.sh` (pick
your own), the package manifests, and the AWS profile names in
`templates/aws/config.template`.

**Why is my machine's config file named `pro-78827b30ddc1.zsh`?**
`pro` is the hostname, for readability; `78827b30ddc1` is the salted hash of the
hardware serial, and is the part that actually identifies the machine. You can
rename the prefix to anything — lookup matches the hash suffix. Just don't put the
serial in the filename or the file.

**Where did `~/.aws/config` go?**
It is now `~/.dotfiles-local/aws/config`, with `~/.aws/config` symlinked to it. It
left the repo because it contained account IDs, role ARNs and an `external_id`.

**How do I keep something machine-specific out of git?**
`~/.dotfiles-local/zsh/local.zsh` for shell config, `~/.ssh/config.local` for SSH
hosts. Both are sourced automatically and neither is tracked.

**The pre-commit hook is blocking a legitimate commit.**
Check it is genuinely a false positive, then `git commit --no-verify`. If the
pattern is wrong, fix it in `git/hooks/pre-commit` so the next person is not
blocked too.

**Why zero errors from shellcheck but 19 info-level notes?**
The remaining notes are stylistic (`printf` format strings built from colour
constants, intentionally unexpanded single quotes, unfollowable dynamic `source`
paths). Errors and warnings are what matter, and there are none.

---

## Contributing

Issues and pull requests welcome — see
[Issues](https://github.com/biswajitpain/dotfiles/issues).

Before committing, run `./scripts/audit-repo.sh`. The pre-commit hook will refuse
anything resembling a credential or an infrastructure identifier.

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgments

- [Oh My Zsh](https://ohmyz.sh/) for the zsh framework
- The open-source community

## Contact

GitHub: [@biswajitpain](https://github.com/biswajitpain)
