#!/usr/bin/env zsh
#
# Weekly dotfiles update check, in two halves.
#
# SECURITY: nothing here pulls, and nothing here executes install.sh.
#
# The original version ran `git pull origin main` and then `./install.sh`
# unattended, in a background job, on every interactive shell. That is remote code
# execution on a schedule: anything reaching origin/main — a compromised account,
# a bad merge, a force-push — would run on every machine with no review. The
# nested `./install.sh` (no `local` argument) also pulled a second time. Applying
# an update is now an explicit human action: `dotfiles-update`.
#
# Split into two halves because a login shell must stay quiet and fast:
#
#   dotfiles_update_notice   synchronous, file read only, instant
#   check_dotfiles_update    backgrounded, does the network fetch, prints nothing
#
# The background half writes a notice file; the next shell displays it. That
# avoids output landing after the prompt has been drawn, which is what makes
# backgrounded messages garble a terminal.

_dotfiles_dir()    { print -r -- "${DOTFILES_DIR:-$HOME/.dotfiles}"; }
_dotfiles_notice() { print -r -- "$(_dotfiles_dir)/.update_notice"; }

# dotfiles_update_notice: print the pending-update notice, if any
# Usage: dotfiles_update_notice
# Description: Displays whatever the last background check found. Reads one small
# file; performs no network I/O. Called synchronously from .zshrc.
dotfiles_update_notice() {
    local f
    f=$(_dotfiles_notice)
    [[ -s "$f" ]] && cat -- "$f"
    return 0
}

# check_dotfiles_update: refresh the pending-update notice
# Usage: check_dotfiles_update
# Description: Fetches (read-only) at most once a week and records whether this
# checkout is behind origin/main. Prints nothing — meant to be backgrounded.
function check_dotfiles_update() {
    local dotfiles_dir notice stamp interval=604800
    dotfiles_dir=$(_dotfiles_dir)
    notice=$(_dotfiles_notice)
    stamp="$dotfiles_dir/.last_update"

    [[ -d "$dotfiles_dir/.git" ]] || return 0

    if [[ -f "$stamp" ]]; then
        local last current
        last=$(<"$stamp")
        current=$(date +%s)
        # Guard a corrupt stamp: a non-numeric value would break the arithmetic
        # and, in the original, wedge the check permanently.
        if [[ "$last" == <-> ]] && (( current - last < interval )); then
            return 0
        fi
    fi

    # Stamp before network I/O, so a hanging or failing fetch cannot cause a fetch
    # attempt on every single shell startup.
    date +%s >|"$stamp" 2>/dev/null

    git -C "$dotfiles_dir" fetch origin main --quiet 2>/dev/null || return 0

    local behind
    behind=$(git -C "$dotfiles_dir" rev-list --count HEAD..origin/main 2>/dev/null) || return 0

    if [[ "$behind" == <-> ]] && (( behind > 0 )); then
        print -r -- "dotfiles: $behind commit(s) behind origin/main. Run: dotfiles-update" >|"$notice"
    else
        rm -f -- "$notice" 2>/dev/null
    fi
    return 0
}

# dotfiles-update: review and apply pending dotfiles changes
# Usage: dotfiles-update
# Description: Shows what is incoming, asks for confirmation, then pulls and
# re-links. This is the only path that applies an update; nothing is automatic.
dotfiles-update() {
    local dotfiles_dir
    dotfiles_dir=$(_dotfiles_dir)

    git -C "$dotfiles_dir" fetch origin main --quiet || { print -u2 -- "fetch failed"; return 1; }

    local behind
    behind=$(git -C "$dotfiles_dir" rev-list --count HEAD..origin/main 2>/dev/null)
    if [[ "$behind" != <-> ]] || (( behind == 0 )); then
        print -r -- "dotfiles: already up to date."
        rm -f -- "$(_dotfiles_notice)" 2>/dev/null
        return 0
    fi

    print -r -- "Incoming ($behind commit(s)):"
    git -C "$dotfiles_dir" log --oneline --no-decorate HEAD..origin/main
    print -r -- ""
    git -C "$dotfiles_dir" diff --stat HEAD..origin/main
    print -r -- ""

    local reply
    read -r "reply?Pull and re-link? [y/N] "
    case "$reply" in
        [Yy]*)
            # --ff-only: never create a merge commit unattended, and fail loudly
            # if upstream history was rewritten.
            git -C "$dotfiles_dir" pull --ff-only origin main \
                || { print -u2 -- "pull failed (diverged or rewritten history) — resolve manually"; return 1; }
            "$dotfiles_dir/install.sh" local
            rm -f -- "$(_dotfiles_notice)" 2>/dev/null
            print -r -- "Done. Open a new shell."
            ;;
        *) print -r -- "Skipped." ;;
    esac
}
