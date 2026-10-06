# macOS-only shell functions and startup hooks.

# ── SSH agent: load keychain-stored keys once per login ─────────────────────
# AddKeysToAgent only adds a key when it is first USED from this Mac. Agent
# forwarding (Host devdesktop in ~/.ssh/config.local) needs the keys already in
# the agent, or GitHub auth and commit signing on the remote fail after every
# reboot. `ssh-add -l` exits 1 when the agent is empty, so after the first shell
# this costs one fast agent query.
if [ -n "${SSH_AUTH_SOCK:-}" ] && ! ssh-add -l >/dev/null 2>&1; then
    ssh-add --apple-load-keychain >/dev/null 2>&1
fi
