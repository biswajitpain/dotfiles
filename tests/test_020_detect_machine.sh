#!/usr/bin/env bash
# scripts/detect-machine.sh is the single source of truth for the machine key:
# .zshrc and install.sh both call it, and every zsh/machines/<key>.zsh file is
# named after its output. If this drifts, machines silently lose their config.
. "$(dirname "$0")/lib/harness.sh"
t_begin "detect-machine — the machine key contract"

DETECT="$REPO_ROOT/scripts/detect-machine.sh"

# ── The key scheme itself ────────────────────────────────────────────────────
# SALT and KEY_LEN define every committed filename in zsh/machines/. Changing
# either silently orphans every machine's config on every machine. This is a
# deliberate tripwire: if you change these, you must migrate the files and
# update this test, which is exactly the moment to notice.
salt=$(grep -E "^SALT=" "$DETECT" | cut -d"'" -f2)
keylen=$(grep -E '^KEY_LEN=' "$DETECT" | cut -d= -f2)
assert_eq "dotfiles-machine-v1" "$salt"  "SALT unchanged (changing it orphans every machine config)"
assert_eq "12" "$keylen"                 "KEY_LEN unchanged (ditto)"

# ── Output shape ─────────────────────────────────────────────────────────────
key=$(MACHINE_TYPE= "$DETECT")
assert_ne "" "$key" "canonical key is non-empty"
# Filesystem-safe: this becomes a filename. ComputerName is not safe, which is
# the whole reason this script exists.
assert_match "$key" '^[a-z0-9][a-z0-9-]*$' "canonical key is filename-safe (lowercase, no spaces)"
assert_no_match "$key" "[[:upper:][:space:]'\"/]"  "canonical key has no uppercase, space, quote or slash"

slug=$(MACHINE_TYPE= "$DETECT" --slug)
assert_ne "" "$slug" "--slug is non-empty"
assert_match "$slug" '^[a-z0-9][a-z0-9-]*$' "--slug is filename-safe"

hash=$(MACHINE_TYPE= "$DETECT" --hash)
if [ -n "$hash" ]; then
    assert_match "$hash" '^[0-9a-f]{12}$' "--hash is 12 lowercase hex chars"
    assert_eq "$slug-$hash" "$key" "canonical key is <slug>-<hash>"
else
    skip "--hash empty on this host (no serial/sha tool) — canonical key falls back to slug"
    assert_eq "$slug" "$key" "fallback key is the slug alone"
fi

# ── Determinism ──────────────────────────────────────────────────────────────
# Called on every interactive shell; a key that wobbles means config that
# randomly fails to load.
a=$(MACHINE_TYPE= "$DETECT"); b=$(MACHINE_TYPE= "$DETECT")
assert_eq "$a" "$b" "key is stable across invocations"

# ── The hash really is the salted SHA-256 of the hardware id ─────────────────
hw=$(MACHINE_TYPE= "$DETECT" --explain | sed -n 's/^hardware id   : //p')
if [ -n "$hw" ] && [ "$hw" != "(unavailable)" ] && [ -n "$hash" ]; then
    if have shasum;   then expect=$(printf '%s' "dotfiles-machine-v1:$hw" | shasum -a 256 | cut -c1-12)
    elif have sha256sum; then expect=$(printf '%s' "dotfiles-machine-v1:$hw" | sha256sum | cut -c1-12)
    else expect=""; fi
    if [ -n "$expect" ]; then
        assert_eq "$expect" "$hash" "--hash is sha256(SALT:hardware-id) truncated to 12"
    else skip "no sha256 tool to verify the hash independently"; fi
else
    skip "no hardware id on this host — cannot verify the hash derivation"
fi

# ── MACHINE_TYPE overrides everything ────────────────────────────────────────
# Documented escape hatch; .zshrc relies on it and so do these tests.
assert_eq "forced-key" "$(MACHINE_TYPE=forced-key "$DETECT")" "MACHINE_TYPE overrides the detected key"

# ── Flags ────────────────────────────────────────────────────────────────────
assert_fails "an unknown flag exits non-zero" "$DETECT" --nonsense
usage=$("$DETECT" --nonsense 2>&1 >/dev/null)
assert_match "$usage" 'usage:' "an unknown flag prints usage on stderr"
rc=0; "$DETECT" --nonsense >/dev/null 2>&1 || rc=$?
assert_eq "2" "$rc" "an unknown flag exits 2"

explain=$(MACHINE_TYPE= "$DETECT" --explain)
for line in 'os' 'hardware id' 'hostname slug' 'stable hash' 'canonical key' 'legacy names' 'machine file'; do
    assert_match "$explain" "^$line" "--explain reports '$line'"
done

# --legacy must never emit a blank line: .zshrc feeds each line straight into a
# filename, and a blank one would test for "zsh/machines/.zsh".
legacy=$(MACHINE_TYPE= "$DETECT" --legacy)
assert_no_match "$legacy" '^$' "--legacy emits no blank lines"

# ── slugify: the specific inputs this script was written to survive ──────────
# Sourcing also runs the trailing case statement; --slug is the harmless branch.
# shellcheck disable=SC1090
( . "$DETECT" --slug >/dev/null 2>&1
  printf '%s\n' "$(slugify "Biswajit’s MacBook Pro")" ) > "${TMPDIR:-/tmp}/slug.$$" 2>/dev/null
got=$(cat "${TMPDIR:-/tmp}/slug.$$" 2>/dev/null); rm -f "${TMPDIR:-/tmp}/slug.$$"
assert_eq "biswajit-s-macbook-pro" "$got" "slugify flattens the curly apostrophe and spaces in ComputerName"

t_end
