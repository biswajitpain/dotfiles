# tests/

A dependency-free test suite for these dotfiles. No bats, no shunit2, nothing to
install: the suite has to run on a machine that has *just* been imaged, before
`bootstrap.sh` has installed anything, because its job includes verifying the
installer.

```bash
./tests/run-tests.sh                  # everything
./tests/run-tests.sh detect install   # only files whose names match
VERBOSE=1 ./tests/run-tests.sh        # show passing assertions too
```

Exit 0 clean, 1 on any failure. CI runs it on macOS and Linux (`.github/workflows/test.yml`).

## The safety rule

**No test ever touches your real `$HOME`.** Anything that writes runs inside a
sandbox from `sandbox_new`, which repoints `HOME`, `DOTFILES_DIR` and
`DOTFILES_LOCAL_DIR` into a temp directory and stubs Oh My Zsh. Every write
helper calls `assert_sandboxed`, which aborts the whole run (exit 99) if `HOME`
ever escapes. Tests are also non-interactive and offline: `zsh -c` rather than
`zsh -i`, so the background update check never fires and nothing hits the network.

## What each file covers

| File | Covers |
|---|---|
| `test_010_syntax.sh` | every tracked shell file parses; executable bits |
| `test_020_detect_machine.sh` | the machine-key contract: shape, determinism, salt, flags, `slugify` |
| `test_030_machine_config.sh` | `_load_machine_config`'s four-rung ladder and its precedence |
| `test_040_shell_contract.sh` | every alias/function survives a shell load; clean, idempotent startup |
| `test_050_install.sh` | symlinks, backups, idempotence, and the no-credentials guarantee |
| `test_060_secrets_hook.sh` | the pre-commit scanner, from both sides |
| `test_070_audit.sh` | `audit-repo.sh`, from both sides, including `--history` |
| `test_080_architecture.sh` | templates, package manifests, `.gitignore`, where secrets may live |
| `test_090_update.sh` | the update mechanism, including a rewritten upstream |
| `test_100_bootstrap.sh` | `bootstrap.sh` CLI, stage selection, and the read-only verify stage |

## The two halves of "nothing breaks"

`test_040` checks the shell contract twice over, and the distinction matters:

- **Dynamically**, it extracts every alias and function the repo declares at
  column 0 and asserts each one is defined after `.zshrc` runs. This catches
  *silent* breakage — a stray quote that kills the rest of a file, a file
  dropped from the source list, a name collision.
- **Statically**, `contract/core-features.txt` lists the commands you actually
  type. The dynamic check would happily wave through someone *deleting* a
  declaration; this file is what makes a deletion fail the build.

Add a feature → add it to `core-features.txt`. Remove one deliberately → remove
it there in the same commit, so the removal is visible in review.

## Writing a test

```bash
#!/usr/bin/env bash
. "$(dirname "$0")/lib/harness.sh"
t_begin "what this file covers"

sandbox_new --with-repo      # --with-repo copies the tracked repo into the sandbox
assert_sandboxed

assert_eq "expected" "$actual" "message"
assert_match "$text" 'regex'   "message"
assert_ok "message" some command
assert_fails "message" some command
assert_symlink_to "$HOME/.zshrc" "$DOTFILES_DIR/zsh/.zshrc" "message"

t_end                         # prints the tally, exits non-zero on failure
```

Helpers: `assert_eq`, `assert_ne`, `assert_match`, `assert_no_match`,
`assert_ok`, `assert_fails`, `assert_file`, `assert_dir`, `assert_symlink_to`,
`assert_mode`, plus `pass`, `fail`, `skip` and `have <cmd>`.

`stub_detector <canonical> <hash> <legacy>` replaces `detect-machine.sh` inside
a `--with-repo` sandbox, so machine-resolution tests are deterministic on any
host rather than depending on the serial of whatever machine is running them.

## Is the suite actually load-bearing?

A green suite proves nothing unless it goes red when the code breaks. Check it
by mutation: copy the repo to a scratch directory, break one thing, confirm the
relevant file fails. Mutations that must be caught include deleting an alias
from `core-features.txt`, changing `SALT` in `detect-machine.sh`, removing
`--ff-only` from `dotfiles-update`, dropping a `FORBIDDEN_PATHS` entry from the
hook, and adding `!aws/config` to `.gitignore`.
