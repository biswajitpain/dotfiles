#!/usr/bin/env bash
# install.sh — the symlink layer. Runs against a sandbox HOME, never yours.
#
# The guarantee that matters most here is negative: install.sh must NEVER create
# or publish a credential-bearing file. It links ~/.gitconfig, ~/.aws/config and
# ~/.kube/config only when bootstrap.sh has already rendered them OUTSIDE the
# repo. If that ever regresses, real account IDs land back in a public repo.
. "$(dirname "$0")/lib/harness.sh"
t_begin "install.sh — symlinks, backups, idempotence"

for dep in git curl zsh vim tmux; do
    have "$dep" || { skip "install.sh needs $dep (it would try to sudo-install it)"; t_end; }
done

sandbox_new --with-repo
assert_sandboxed
INSTALL="$DOTFILES_DIR/install.sh"

# ── CLI ──────────────────────────────────────────────────────────────────────
assert_ok    "--help exits 0"            bash "$INSTALL" --help
help=$(bash "$INSTALL" --help 2>&1)
assert_match "$help" 'Usage:'            "--help prints usage"
assert_fails "an unknown argument fails" bash "$INSTALL" --no-such-flag

# ── Files that already exist are backed up, not destroyed ────────────────────
printf 'PRE-EXISTING ZSHRC\n'   > "$HOME/.zshrc"
printf 'PRE-EXISTING VIMRC\n'   > "$HOME/.vimrc"
printf 'PRE-EXISTING TMUX\n'    > "$HOME/.tmux.conf"

out=$(cd "$DOTFILES_DIR" && bash "$INSTALL" local 2>&1)
rc=$?
assert_eq "0" "$rc" "install.sh local exits 0 on a fresh machine" 

backup=$(find "$HOME/.dotfiles_backup" -name '.zshrc' 2>/dev/null | head -1)
if [ -n "$backup" ] && grep -q 'PRE-EXISTING ZSHRC' "$backup"; then
    pass "an existing ~/.zshrc is backed up with its contents intact"
else
    fail "existing ~/.zshrc was not backed up" "looked under $HOME/.dotfiles_backup"
fi

# ── The core symlinks ────────────────────────────────────────────────────────
assert_symlink_to "$HOME/.zshrc"      "$DOTFILES_DIR/zsh/.zshrc"      "~/.zshrc -> repo"
assert_symlink_to "$HOME/.vimrc"      "$DOTFILES_DIR/vim/.vimrc"      "~/.vimrc -> repo"
assert_symlink_to "$HOME/.tmux.conf"  "$DOTFILES_DIR/tmux/.tmux.conf" "~/.tmux.conf -> repo"
assert_symlink_to "$HOME/.ssh/config" "$DOTFILES_DIR/ssh/config"      "~/.ssh/config -> repo"
assert_mode "$HOME/.ssh" 700          "~/.ssh is mode 700"
assert_mode "$DOTFILES_DIR/ssh/config" 600 "ssh/config is mode 600"

# ── The negative guarantee: no rendered config, no link ──────────────────────
for f in "$HOME/.gitconfig" "$HOME/.aws/config" "$HOME/.kube/config"; do
    if [ -e "$f" ]; then fail "$f must NOT be created without a rendered source" "found: $(ls -l "$f")"
    else pass "$(basename "$(dirname "$f")")/$(basename "$f") is not linked when nothing is rendered"; fi
done
assert_match "$out" 'bootstrap.sh --only cloud'    "it points the user at bootstrap for cloud configs"
assert_match "$out" 'bootstrap.sh --only identity' "it points the user at bootstrap for git identity"

# ── The pre-commit scanner is installed ──────────────────────────────────────
assert_file "$DOTFILES_DIR/.git/hooks/pre-commit" "pre-commit secret scanner installed into .git/hooks"

# ── Idempotence: running it again must not break anything ────────────────────
# `dotfiles-update` and the weekly auto-update both re-run this.
out2=$(cd "$DOTFILES_DIR" && bash "$INSTALL" local 2>&1); rc=$?
assert_eq "0" "$rc" "a second install.sh run exits 0"
assert_symlink_to "$HOME/.zshrc" "$DOTFILES_DIR/zsh/.zshrc" "~/.zshrc is still the right symlink after re-running"
assert_match "$out2" 'already links to' "a re-run leaves correct links alone instead of re-making them"

# The re-run must not leave a dangling link: the thing it points at has to exist.
if [ -L "$HOME/.zshrc" ] && [ -e "$HOME/.zshrc" ]; then
    pass "~/.zshrc is a live symlink after a re-run, not a dangling one"
else
    fail "~/.zshrc is dangling or missing after a re-run"
fi

# The user's ORIGINAL file must survive every re-run, not be overwritten by a
# backup of the symlink that replaced it.
if grep -rq 'PRE-EXISTING ZSHRC' "$HOME/.dotfiles_backup" 2>/dev/null; then
    pass "the original pre-install ~/.zshrc content is still recoverable from backups"
else
    fail "a re-run destroyed the backup of the user's original ~/.zshrc"
fi

# ── Regression: a dangling symlink must not abort the install ────────────────
# If the dotfiles directory is ever moved or restored to a different path, every
# ~/ symlink dangles. install.sh is the tool that repairs that, so it has to
# survive it: `-e` is false for a dangling link, so an un-guarded `ln -s` fails
# with "File exists" and `set -e` kills the run before anything else is linked.
sandbox_rm; sandbox_new --with-repo; assert_sandboxed
INSTALL="$DOTFILES_DIR/install.sh"
ln -s /nonexistent/gone-away "$HOME/.zshrc"
out=$(cd "$DOTFILES_DIR" && bash "$INSTALL" local 2>&1); rc=$?
assert_eq "0" "$rc" "a dangling ~/.zshrc does not abort install.sh"
assert_symlink_to "$HOME/.zshrc" "$DOTFILES_DIR/zsh/.zshrc" "a dangling ~/.zshrc is repaired"
assert_symlink_to "$HOME/.vimrc" "$DOTFILES_DIR/vim/.vimrc" "links after the dangling one still get made"

# ── Regression: two runs in the same second must not eat the backup ──────────
# $BACKUP_DIR is timestamped to the second, so a quick re-run shares it. The
# user's real file must not be overwritten by the symlink that replaced it.
sandbox_rm; sandbox_new --with-repo; assert_sandboxed
INSTALL="$DOTFILES_DIR/install.sh"
printf 'IRREPLACEABLE USER CONTENT\n' > "$HOME/.zshrc"
( cd "$DOTFILES_DIR" && bash "$INSTALL" local >/dev/null 2>&1
  bash "$INSTALL" local >/dev/null 2>&1
  bash "$INSTALL" local >/dev/null 2>&1 )
if grep -rq 'IRREPLACEABLE USER CONTENT' "$HOME/.dotfiles_backup" 2>/dev/null; then
    pass "three same-second runs still preserve the user's original file"
else
    fail "a same-second re-run destroyed the backup of the user's original file"
fi

# ── Regression: a stale link into our own tree is repointed, not abandoned ───
sandbox_rm; sandbox_new --with-repo; assert_sandboxed
INSTALL="$DOTFILES_DIR/install.sh"
ln -s "$DOTFILES_DIR/zsh/machines/dummy-machine.zsh" "$HOME/.zshrc"
cd "$DOTFILES_DIR" && bash "$INSTALL" local >/dev/null 2>&1
assert_symlink_to "$HOME/.zshrc" "$DOTFILES_DIR/zsh/.zshrc" "a link pointing at the wrong file in our tree is repointed"

# ── With rendered configs present, they ARE linked ───────────────────────────
sandbox_rm; sandbox_new --with-repo; assert_sandboxed
INSTALL="$DOTFILES_DIR/install.sh"   # the old sandbox is gone; repoint
mkdir -p "$DOTFILES_LOCAL_DIR/aws" "$DOTFILES_LOCAL_DIR/kube" "$DOTFILES_LOCAL_DIR/git"
printf '[default]\nregion = us-east-1\n' > "$DOTFILES_LOCAL_DIR/aws/config"
printf 'apiVersion: v1\n'                > "$DOTFILES_LOCAL_DIR/kube/config"
printf '[user]\n\tname = Test\n'         > "$DOTFILES_LOCAL_DIR/git/gitconfig"

out3=$(cd "$DOTFILES_DIR" && bash "$INSTALL" local 2>&1)
assert_eq "0" "$?" "install.sh exits 0 when rendered configs are present"
assert_symlink_to "$HOME/.aws/config"  "$DOTFILES_LOCAL_DIR/aws/config"  "~/.aws/config -> rendered file outside the repo"
assert_symlink_to "$HOME/.kube/config" "$DOTFILES_LOCAL_DIR/kube/config" "~/.kube/config -> rendered file outside the repo"
assert_symlink_to "$HOME/.gitconfig"   "$DOTFILES_LOCAL_DIR/git/gitconfig" "~/.gitconfig -> rendered file outside the repo"

# ── install.sh must leave nothing committable behind ─────────────────────────
# It seeds the azure subscriptions file from the template. Once filled in that
# file holds subscription and tenant GUIDs, so it belongs outside the repo —
# where az-aliases.sh also reads it from.
AZ_OUT="$DOTFILES_LOCAL_DIR/config/azure-subscriptions.env"
assert_file "$AZ_OUT" "install.sh seeds the azure subscriptions file"
assert_mode "$AZ_OUT" 600 "the azure subscriptions file is mode 600"
case "$AZ_OUT" in
    "$DOTFILES_DIR"/*) fail "the azure subscriptions file was written INSIDE the repo" ;;
    *)                 pass "the azure subscriptions file is written outside the repo" ;;
esac
if [ -e "$DOTFILES_DIR/config/azure-subscriptions.env" ]; then
    fail "install.sh still writes an in-repo copy of the azure subscriptions file"
else
    pass "install.sh leaves no in-repo copy of the azure subscriptions file"
fi

# Whatever install.sh touched, the repo must still have nothing committable in
# the credential-bearing directories.
leftovers=$(cd "$DOTFILES_DIR" && git -c core.excludesFile=/dev/null status --porcelain 2>/dev/null \
            | awk '{print $2}' | grep -E '^(aws|kube|config)/' | grep -v '\.template$' || true)
if [ -z "$leftovers" ]; then
    pass "install.sh leaves nothing new under aws/, kube/ or config/"
else
    fail "install.sh left files in credential directories" "$leftovers"
fi

t_end
