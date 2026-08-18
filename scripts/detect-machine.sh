#!/bin/sh
# Resolve a stable, filesystem-safe machine key.
#
# Why not the hostname? `scutil --get ComputerName` returns things like
# "Biswajit’s MacBook Pro" — spaces plus a curly apostrophe (U+2019). That makes
# a miserable filename, it is user-editable in System Settings, and it disagrees
# with LocalHostName. So the canonical key is derived from the hardware serial:
# stable for the life of the machine, unique, and safe in a path.
#
# The serial itself is NOT the key, because this repo is public and a serial is a
# permanent identifier you cannot rotate. Instead the key is a salted SHA-256
# prefix. The salt below is not a secret (it is committed here); it exists so the
# key is not a bare hash that a generic precomputed table would resolve. Someone
# with this repo who already suspects a specific serial can still confirm it —
# treat the key as "not published in plaintext", not as cryptographically secret.
#
# Usage:
#   detect-machine.sh              canonical key, e.g. 78827b30ddc1
#   detect-machine.sh --hash       just the stable hash half (for suffix matching)
#   detect-machine.sh --slug       just the hostname prefix
#   detect-machine.sh --legacy     older candidate names, newline separated
#   detect-machine.sh --explain    human-readable breakdown (prints the serial)
#
# $MACHINE_TYPE in the environment overrides everything.

set -u

SALT='dotfiles-machine-v1'
KEY_LEN=12

# Lowercase, collapse anything not [a-z0-9] into single dashes, trim the ends.
slugify() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
}

sha256_hex() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | cut -d' ' -f1
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum | cut -d' ' -f1
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 | sed 's/.*= *//'
    else
        return 1
    fi
}

# A hardware identifier that survives OS reinstalls and renames.
# macOS: ioreg is used rather than `system_profiler SPHardwareDataType` because
# this runs on every interactive shell — ioreg is ~4ms, system_profiler ~75ms.
hardware_id() {
    case "$(uname)" in
        Darwin)
            ioreg -c IOPlatformExpertDevice -d 2 2>/dev/null \
                | awk -F'"' '/IOPlatformSerialNumber/{print $4; exit}'
            ;;
        Linux)
            # product_serial is usually root-only; machine-id is world-readable
            # and stable per install, which is good enough for VMs.
            if [ -r /sys/class/dmi/id/product_serial ]; then
                serial=$(tr -d '[:space:]' < /sys/class/dmi/id/product_serial 2>/dev/null)
                case "$serial" in
                    ''|None|To\ be\ filled*|Default\ string|0123456789) ;;
                    *) printf '%s' "$serial"; return 0 ;;
                esac
            fi
            [ -r /etc/machine-id ] && tr -d '[:space:]' < /etc/machine-id
            ;;
    esac
}

# Names this machine may have used before the serial-hash scheme. Kept so an
# unmigrated machine still loads its config instead of silently losing it.
legacy_names() {
    case "$(uname)" in
        Darwin) scutil --get ComputerName 2>/dev/null ;;
    esac
    hostname -s 2>/dev/null || hostname 2>/dev/null
}

# Human-readable prefix for the key, so a filename says which machine it is
# instead of being opaque hex.
#
# LocalHostName is preferred on macOS because System Settings guarantees it is
# DNS-safe; ComputerName is NOT — it can hold spaces and a curly apostrophe.
hostname_slug() {
    name=""
    case "$(uname)" in
        Darwin) name=$(scutil --get LocalHostName 2>/dev/null || true) ;;
    esac
    [ -n "${name:-}" ] || name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)
    slug=$(slugify "$name")
    [ -n "$slug" ] || slug=host
    printf '%s' "$slug"
}

# The stable half of the key: salted hash of the hardware serial. Fails (returns
# 1) when there is no serial or no SHA-256 tool.
hardware_hash() {
    hw=$(hardware_id 2>/dev/null || true)
    [ -n "${hw:-}" ] || return 1
    key=$(printf '%s' "${SALT}:${hw}" | sha256_hex 2>/dev/null) || return 1
    [ -n "$key" ] || return 1
    printf '%s' "$key" | cut -c "1-${KEY_LEN}"
}

# Canonical key: <hostname-slug>-<hash>, e.g. pro-78827b30ddc1.
#
# The hash is the identity; the prefix is only a human label. Lookup matches on
# the hash SUFFIX (see _load_machine_config in .zshrc), so renaming the prefix —
# or renaming the host — never orphans a machine's config. That keeps the
# readability win without reintroducing the hostname fragility the hash fixed.
canonical_key() {
    if h=$(hardware_hash); then
        printf '%s-%s' "$(hostname_slug)" "$h"
        return 0
    fi
    # No serial or no hashing tool: the slug alone, which is at least
    # filesystem-safe. Carries no stability guarantee.
    printf '%s' "$(hostname_slug)"
}

case "${1:-}" in
    --hash)
        # Just the stable half, for suffix matching.
        hardware_hash || printf ''
        ;;
    --slug)
        hostname_slug
        ;;
    --legacy)
        legacy_names | while IFS= read -r name; do
            [ -n "$name" ] && printf '%s\n' "$name"
        done
        ;;
    --explain)
        printf 'os            : %s\n' "$(uname)"
        printf 'hardware id   : %s\n' "$(hardware_id 2>/dev/null || echo '(unavailable)')"
        printf 'hostname slug : %s\n' "$(hostname_slug)"
        printf 'stable hash   : %s\n' "$(hardware_hash || echo '(unavailable)')"
        printf 'canonical key : %s\n' "$(canonical_key)"
        printf 'legacy names  : %s\n' "$(legacy_names | paste -sd',' - 2>/dev/null)"
        printf 'machine file  : zsh/machines/%s.zsh\n' "$(canonical_key)"
        printf 'git config    : git/.gitconfig.%s\n' "$(canonical_key)"
        ;;
    '')
        if [ -n "${MACHINE_TYPE:-}" ]; then
            printf '%s' "$MACHINE_TYPE"
        else
            canonical_key
        fi
        ;;
    *)
        printf 'usage: detect-machine.sh [--hash|--slug|--legacy|--explain]\n' >&2
        exit 2
        ;;
esac
