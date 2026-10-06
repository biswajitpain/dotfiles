#!/usr/bin/env bash
#
# bootstrap.sh — bring a brand-new macOS or Linux machine to a working state.
#
#   Fresh machine, one line:
#     bash -c "$(curl -fsSL https://raw.githubusercontent.com/biswajitpain/dotfiles/main/bootstrap.sh)"
#
#   Already cloned:
#     ./bootstrap.sh
#
# Design rules this script exists to enforce:
#
#   1. The git repo holds TEMPLATES ONLY. Every file that could carry a
#      credential or an environment trace (account IDs, role ARNs, cluster
#      endpoints, identities) is rendered at bootstrap time into
#      $DOTFILES_LOCAL_DIR, which lives OUTSIDE the repo. Being outside the repo
#      is the point: a .gitignore mistake or a `git add -f` cannot leak it.
#
#   2. It is interactive, but every prompt has a default and can be skipped with
#      Enter. `--yes` takes all defaults and asks nothing.
#
#   3. It is idempotent. Re-running is safe and is the intended way to repair a
#      machine or fill in values you skipped.
#
# Written for bash 3.2 — the version macOS still ships. No associative arrays,
# no mapfile, no ${var^^}.

set -uo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/biswajitpain/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
# Rendered, credential-bearing output. Deliberately not inside DOTFILES_DIR.
DOTFILES_LOCAL_DIR="${DOTFILES_LOCAL_DIR:-$HOME/.dotfiles-local}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

log()   { printf "${GREEN}[LOG]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }
die()   { err "$1"; exit 1; }
step()  { printf "\n${BLUE}==>${NC} ${BLUE}%s${NC}\n" "$1"; }

# ── Options ──────────────────────────────────────────────────────────────────
ASSUME_YES=false
DO_PACKAGES=true
DO_CASKS=false
DO_LINK=true
DO_IDENTITY=true
DO_CLOUD=true
DO_NODE=true
USE_LOCAL=false
ONLY=""

show_help() {
    cat <<'EOF'
Usage: ./bootstrap.sh [options]

Bring a new macOS or Linux machine to a working state: install binaries, link
dotfiles, and render credential-bearing configs OUTSIDE the git repo.

Options:
  -y, --yes           Accept every default; ask nothing. Skips prompts that have
                      no safe default (cloud account IDs are left as placeholders).
      --local         Do not clone or pull; use the checkout as-is.
      --no-packages   Skip binary/package installation.
      --casks         Also install GUI apps from packages/brew-cask.txt (macOS).
      --only <stage>  Run one stage only. One of:
                        packages, link, identity, cloud, node, verify
      --cloud         Shorthand for --only cloud (re-run cloud config rendering).
  -h, --help          Show this help.

Stages, in order:
  packages   detect the package manager, install it if missing, install manifests
  link       run install.sh (symlinks, Oh My Zsh)
  identity   git name/email, SSH key, commit signing
  cloud      render aws/kube/azure configs from templates into local dir
  node       install nvm + Node LTS
  verify     audit the repo for leaked credentials and report the final state

Paths:
  repo         $HOME/.dotfiles           (templates, tracked in git)
  rendered     $HOME/.dotfiles-local     (real configs, NEVER in git)
Override with DOTFILES_DIR / DOTFILES_LOCAL_DIR.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        -y|--yes)      ASSUME_YES=true; shift ;;
        --local)       USE_LOCAL=true; shift ;;
        --no-packages) DO_PACKAGES=false; shift ;;
        --casks)       DO_CASKS=true; shift ;;
        --cloud)       ONLY="cloud"; shift ;;
        --only)        ONLY="${2:-}"; [ -n "$ONLY" ] || die "--only needs a stage"; shift 2 ;;
        -h|--help)     show_help; exit 0 ;;
        *)             err "unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ -n "$ONLY" ]; then
    DO_PACKAGES=false; DO_LINK=false; DO_IDENTITY=false; DO_CLOUD=false; DO_NODE=false
    case "$ONLY" in
        packages) DO_PACKAGES=true ;;
        link)     DO_LINK=true ;;
        identity) DO_IDENTITY=true ;;
        cloud)    DO_CLOUD=true ;;
        node)     DO_NODE=true ;;
        verify)   : ;;
        *)        die "unknown stage: $ONLY" ;;
    esac
fi

# ── Interaction helpers ──────────────────────────────────────────────────────
# Read from /dev/tty, not stdin: when this script is piped from curl, stdin is
# the script itself and `read` would silently consume it.
TTY="/dev/tty"
have_tty() { [ -r "$TTY" ] && [ -w "$TTY" ]; }

# ask <prompt> <default> -> echoes the answer
ask() {
    local prompt="$1" default="${2:-}" reply=""
    if [ "$ASSUME_YES" = true ] || ! have_tty; then
        printf '%s' "$default"; return 0
    fi
    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default" >"$TTY"
    else
        printf "%s (Enter to skip): " "$prompt" >"$TTY"
    fi
    IFS= read -r reply <"$TTY" || reply=""
    [ -n "$reply" ] || reply="$default"
    printf '%s' "$reply"
}

# confirm <prompt> <default y|n> -> returns 0 for yes
confirm() {
    local prompt="$1" default="${2:-y}" reply=""
    if [ "$ASSUME_YES" = true ] || ! have_tty; then
        [ "$default" = "y" ]; return $?
    fi
    local hint="[y/N]"; [ "$default" = "y" ] && hint="[Y/n]"
    printf "%s %s: " "$prompt" "$hint" >"$TTY"
    IFS= read -r reply <"$TTY" || reply=""
    [ -n "$reply" ] || reply="$default"
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# ── Platform detection ───────────────────────────────────────────────────────
OS=""; PKG=""
detect_platform() {
    case "$(uname)" in
        Darwin) OS="macos"; PKG="brew" ;;
        Linux)
            OS="linux"
            if   command -v apt-get >/dev/null 2>&1; then PKG="apt"
            elif command -v dnf     >/dev/null 2>&1; then PKG="dnf"
            elif command -v pacman  >/dev/null 2>&1; then PKG="pacman"
            elif command -v zypper  >/dev/null 2>&1; then PKG="zypper"
            else PKG="" ; fi
            ;;
        *) die "unsupported OS: $(uname)" ;;
    esac
    log "platform: $OS, package manager: ${PKG:-none detected}"
}

# A fresh cloud VM runs unattended-upgrades on first boot and holds the dpkg
# lock for minutes; without a timeout every apt call fails instantly.
APT_LOCK="-o DPkg::Lock::Timeout=900"

# sudo that explains itself before prompting, and fails clearly if unavailable.
SUDO=""
need_sudo() {
    [ "$(id -u)" -eq 0 ] && { SUDO=""; return 0; }
    command -v sudo >/dev/null 2>&1 || die "sudo not found and not running as root"
    if ! sudo -n true 2>/dev/null; then
        warn "sudo password required for package installation."
    fi
    SUDO="sudo"
}

# Resolve this machine's canonical key. MACHINE_TYPE is forced empty so the
# detector computes the key instead of echoing an inherited value.
detect_machine_key() {
    MACHINE_TYPE="" sh "$DOTFILES_DIR/scripts/detect-machine.sh" 2>/dev/null
}

# ── Stage: repo ──────────────────────────────────────────────────────────────
stage_repo() {
    if [ "$USE_LOCAL" = true ]; then
        log "using local checkout, skipping clone/pull"
        return 0
    fi
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
        step "Cloning dotfiles"
        command -v git >/dev/null 2>&1 || bootstrap_git
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR" || die "clone failed"
    else
        step "Updating dotfiles"
        git -C "$DOTFILES_DIR" pull --rebase=false --ff-only 2>/dev/null \
            || warn "pull skipped (local changes or diverged branch) — continuing"
    fi
}

# git is needed before anything else can happen.
bootstrap_git() {
    case "$PKG" in
        brew)   install_homebrew && brew install git ;;
        apt)    need_sudo; $SUDO apt-get $APT_LOCK update -qq && $SUDO apt-get $APT_LOCK install -y git ;;
        dnf)    need_sudo; $SUDO dnf install -y git ;;
        pacman) need_sudo; $SUDO pacman -S --needed --noconfirm git ;;
        zypper) need_sudo; $SUDO zypper install -y git ;;
        *)      die "cannot install git automatically; install it and re-run" ;;
    esac
}

# ── Stage: packages ──────────────────────────────────────────────────────────
install_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        log "Homebrew already installed"
    else
        step "Installing Homebrew"
        have_tty || warn "no tty: the Homebrew installer may not be able to prompt"
        NONINTERACTIVE=1 /bin/bash -c \
            "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
            || die "Homebrew install failed"
    fi
    # Apple silicon puts brew in /opt/homebrew, Intel in /usr/local.
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$candidate" ] && eval "$("$candidate" shellenv)" && break
    done
    command -v brew >/dev/null 2>&1 || die "brew not on PATH after install"
}

# Strip comments/blank lines and inline trailing comments from a manifest.
read_manifest() {
    local file="$1"
    [ -f "$file" ] || return 0
    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$file" | grep -v '^[[:space:]]*$'
}

stage_packages() {
    step "Installing packages"
    detect_platform

    case "$PKG" in
        brew)
            install_homebrew
            local formulae; formulae=$(read_manifest "$DOTFILES_DIR/packages/brew.txt")
            if [ -n "$formulae" ]; then
                # One brew call: much faster than looping, and brew skips
                # already-installed formulae itself.
                log "installing $(printf '%s\n' "$formulae" | wc -l | tr -d ' ') formulae"
                # shellcheck disable=SC2086
                brew install $formulae || warn "some formulae failed; continuing"
            fi

            # CLI tooling that Homebrew only ships as casks (JDK, gcloud bundle).
            # Always installed — these are not GUI apps.
            local cli_casks; cli_casks=$(read_manifest "$DOTFILES_DIR/packages/brew-cask-cli.txt")
            if [ -n "$cli_casks" ]; then
                log "installing CLI casks: $(printf '%s' "$cli_casks" | tr '\n' ' ')"
                # shellcheck disable=SC2086
                # A cask wrapping a .pkg (Corretto) needs an interactive sudo
                # password, so this legitimately fails unattended.
                brew install --cask $cli_casks || warn "some CLI casks failed; continuing"
                java_hint
            fi

            # terraform left homebrew-core when it moved to the BUSL license.
            if ! command -v terraform >/dev/null 2>&1; then
                log "installing terraform from hashicorp/tap"
                brew tap hashicorp/tap >/dev/null 2>&1 \
                    && brew install hashicorp/tap/terraform \
                    || warn "terraform install failed (opentofu is a core-formula alternative)"
            fi

            if [ "$DO_CASKS" = true ] || confirm "Install GUI apps (iterm2, vscode, docker...)?" n; then
                local casks; casks=$(read_manifest "$DOTFILES_DIR/packages/brew-cask.txt")
                # shellcheck disable=SC2086
                if [ -n "$casks" ]; then
                    # shellcheck disable=SC2086
                    brew install --cask $casks || warn "some casks failed; continuing"
                fi
            fi
            ;;
        apt)
            need_sudo
            local pkgs; pkgs=$(read_manifest "$DOTFILES_DIR/packages/apt.txt")
            $SUDO apt-get $APT_LOCK update -qq || warn "apt update failed"
            # shellcheck disable=SC2086
            if [ -n "$pkgs" ]; then
                # shellcheck disable=SC2086
                # One bulk call is fast, but apt aborts the WHOLE batch if a
                # single name is unknown (newer tools such as eza or lazygit are
                # missing on older Debian/Ubuntu). On failure, retry one by one
                # so one absent package cannot cost every other.
                if ! $SUDO apt-get $APT_LOCK install -y $pkgs; then
                    warn "bulk apt install failed; retrying packages individually"
                    local p
                    for p in $pkgs; do
                        $SUDO apt-get $APT_LOCK install -y "$p" >/dev/null 2>&1 || warn "apt: $p failed"
                    done
                fi
            fi
            install_linux_languages
            install_linux_cloud_tools
            install_linux_extras
            ;;
        dnf)
            need_sudo
            local pkgs; pkgs=$(read_manifest "$DOTFILES_DIR/packages/dnf.txt")
            # shellcheck disable=SC2086
            if [ -n "$pkgs" ]; then
                # shellcheck disable=SC2086
                $SUDO dnf install -y $pkgs || warn "some packages failed; continuing"
            fi
            install_linux_languages
            install_linux_cloud_tools
            install_linux_extras
            ;;
        pacman)
            need_sudo
            local pkgs; pkgs=$(read_manifest "$DOTFILES_DIR/packages/pacman.txt")
            # shellcheck disable=SC2086
            if [ -n "$pkgs" ]; then
                # shellcheck disable=SC2086
                $SUDO pacman -S --needed --noconfirm $pkgs || warn "some packages failed; continuing"
            fi
            install_linux_languages
            install_linux_cloud_tools
            install_linux_extras
            ;;
        *)
            warn "no supported package manager detected — skipping package install"
            ;;
    esac
}

# Language toolchains on Linux. Distro packages are either far behind (go) or
# absent (corretto), so these come from vendor sources. Each is guarded.
install_linux_languages() {
    local arch; arch=$(uname -m)
    local garch="amd64"; [ "$arch" = "aarch64" ] && garch="arm64"

    # ── Go ───────────────────────────────────────────────────────────────────
    if ! command -v go >/dev/null 2>&1 && [ ! -x /usr/local/go/bin/go ]; then
        local gover
        gover=$(curl -fsSL https://go.dev/VERSION?m=text 2>/dev/null | head -1)
        if [ -n "$gover" ]; then
            log "installing Go $gover"
            if curl -fsSL "https://go.dev/dl/${gover}.linux-${garch}.tar.gz" -o /tmp/go.tgz; then
                $SUDO rm -rf /usr/local/go
                $SUDO tar -C /usr/local -xzf /tmp/go.tgz || warn "go extract failed"
                rm -f /tmp/go.tgz
                log "Go installed to /usr/local/go (PATH set by languages.zsh)"
            else
                warn "go download failed"
            fi
        else
            warn "could not determine latest Go version"
        fi
    else
        log "Go already installed"
    fi

    # ── Java: Amazon Corretto 21 ─────────────────────────────────────────────
    if ! command -v java >/dev/null 2>&1; then
        log "installing Amazon Corretto 21"
        case "$PKG" in
            apt)
                # Amazon's apt repo, keyring in the modern signed-by location.
                if curl -fsSL https://apt.corretto.aws/corretto.key \
                        | $SUDO gpg --dearmor -o /usr/share/keyrings/corretto.gpg 2>/dev/null; then
                    echo "deb [signed-by=/usr/share/keyrings/corretto.gpg] https://apt.corretto.aws stable main" \
                        | $SUDO tee /etc/apt/sources.list.d/corretto.list >/dev/null
                    $SUDO apt-get $APT_LOCK update -qq \
                        && $SUDO apt-get $APT_LOCK install -y java-21-amazon-corretto-jdk \
                        || warn "corretto install failed"
                else
                    warn "could not add corretto apt key"
                fi
                ;;
            dnf)
                $SUDO rpm --import https://yum.corretto.aws/corretto.key 2>/dev/null
                $SUDO curl -fsSL -o /etc/yum.repos.d/corretto.repo https://yum.corretto.aws/corretto.repo 2>/dev/null \
                    && $SUDO dnf install -y java-21-amazon-corretto-devel \
                    || warn "corretto install failed"
                ;;
            pacman)
                warn "Corretto is not in the Arch repos — install jdk21-openjdk or the AUR corretto package"
                ;;
            *)
                warn "no Corretto recipe for $PKG"
                ;;
        esac
    else
        log "java already installed: $(java -version 2>&1 | head -1)"
    fi
}

# Distro packages for cloud CLIs lag badly, so take them from vendor sources.
# Each is guarded: already-present tools are left alone.
install_linux_cloud_tools() {
    local arch; arch=$(uname -m)

    if ! command -v aws >/dev/null 2>&1; then
        log "installing AWS CLI v2"
        local awsarch="x86_64"; [ "$arch" = "aarch64" ] && awsarch="aarch64"
        local tmp; tmp=$(mktemp -d)
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${awsarch}.zip" -o "$tmp/aws.zip" \
           && unzip -q "$tmp/aws.zip" -d "$tmp"; then
            $SUDO "$tmp/aws/install" --update >/dev/null || warn "aws cli install failed"
        else
            warn "aws cli download failed"
        fi
        rm -rf "$tmp"
    fi

    if ! command -v kubectl >/dev/null 2>&1; then
        log "installing kubectl"
        local karch="amd64"; [ "$arch" = "aarch64" ] && karch="arm64"
        local ver; ver=$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null)
        if [ -n "$ver" ] && curl -fsSL "https://dl.k8s.io/release/${ver}/bin/linux/${karch}/kubectl" -o /tmp/kubectl; then
            $SUDO install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl || warn "kubectl install failed"
            rm -f /tmp/kubectl
        else
            warn "kubectl download failed"
        fi
    fi

    if ! command -v helm >/dev/null 2>&1; then
        log "installing helm"
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | $SUDO bash >/dev/null 2>&1 \
            || warn "helm install failed"
    fi

    if ! command -v az >/dev/null 2>&1; then
        log "installing Azure CLI"
        case "$PKG" in
            apt) curl -fsSL https://aka.ms/InstallAzureCLIDeb | $SUDO bash >/dev/null 2>&1 \
                     || warn "azure cli install failed" ;;
            dnf) $SUDO rpm --import https://packages.microsoft.com/keys/microsoft.asc 2>/dev/null
                 $SUDO dnf install -y azure-cli || warn "azure cli install failed" ;;
            *)   warn "no Azure CLI recipe for $PKG" ;;
        esac
    fi

    # ── Google Cloud SDK ─────────────────────────────────────────────────────
    if ! command -v gcloud >/dev/null 2>&1; then
        log "installing Google Cloud SDK"
        case "$PKG" in
            apt)
                if curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
                        | $SUDO gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg 2>/dev/null; then
                    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
                        | $SUDO tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
                    $SUDO apt-get $APT_LOCK update -qq \
                        && $SUDO apt-get $APT_LOCK install -y google-cloud-cli \
                        || warn "gcloud install failed"
                else
                    warn "could not add google cloud apt key"
                fi
                ;;
            dnf)
                $SUDO tee /etc/yum.repos.d/google-cloud-sdk.repo >/dev/null <<'REPO'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el9-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
REPO
                $SUDO dnf install -y google-cloud-cli || warn "gcloud install failed"
                ;;
            *)
                warn "no gcloud recipe for $PKG — see https://cloud.google.com/sdk/docs/install"
                ;;
        esac
    fi

    # ── kubectx/kubens, if the distro did not provide them ───────────────────
    if ! command -v kubectx >/dev/null 2>&1; then
        log "installing kubectx/kubens"
        $SUDO curl -fsSL -o /usr/local/bin/kubectx \
            https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx 2>/dev/null \
            && $SUDO curl -fsSL -o /usr/local/bin/kubens \
                https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens 2>/dev/null \
            && $SUDO chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens \
            || warn "kubectx install failed"
    fi

    # ── GitHub CLI ───────────────────────────────────────────────────────────
    # Not in Debian's repos (and lags in others), so use GitHub's own apt/dnf
    # repository. It is in brew.txt on macOS and pacman.txt on Arch.
    if ! command -v gh >/dev/null 2>&1; then
        log "installing GitHub CLI"
        case "$PKG" in
            apt)
                if curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                        | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none; then
                    $SUDO chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
                    $SUDO apt-get $APT_LOCK update -qq && $SUDO apt-get $APT_LOCK install -y gh \
                        || warn "gh install failed"
                else
                    warn "could not add the GitHub CLI apt key"
                fi
                ;;
            dnf)
                $SUDO dnf install -y 'dnf-command(config-manager)' >/dev/null 2>&1
                $SUDO dnf config-manager addrepo --from-repofile=https://cli.github.com/packages/rpm/gh-cli.repo >/dev/null 2>&1 \
                    || $SUDO dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo >/dev/null 2>&1
                $SUDO dnf install -y gh --repo gh-cli || $SUDO dnf install -y gh || warn "gh install failed"
                ;;
            *)  warn "no GitHub CLI recipe for $PKG — see https://github.com/cli/cli#installation" ;;
        esac
    fi

    # ── terragrunt ───────────────────────────────────────────────────────────
    # Not packaged by apt/dnf/pacman. It is a single static Go binary, so take the
    # release asset directly. Pinned to the API's "latest" tag rather than a
    # hardcoded version so it does not silently rot.
    if ! command -v terragrunt >/dev/null 2>&1; then
        log "installing terragrunt"
        local tgarch="amd64"; [ "$(uname -m)" = "aarch64" ] && tgarch="arm64"
        local tgver
        tgver=$(curl -fsSL https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest 2>/dev/null \
                | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        if [ -n "$tgver" ]; then
            if curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/${tgver}/terragrunt_linux_${tgarch}" \
                    -o /tmp/terragrunt; then
                $SUDO install -m 0755 /tmp/terragrunt /usr/local/bin/terragrunt \
                    || warn "terragrunt install failed"
                rm -f /tmp/terragrunt
            else
                warn "terragrunt download failed"
            fi
        else
            warn "could not determine latest terragrunt version"
        fi
    fi

    # ── terraform ────────────────────────────────────────────────────────────
    if ! command -v terraform >/dev/null 2>&1; then
        case "$PKG" in
            apt)
                # lsb_release is not installed on minimal Debian images; fall
                # back to /etc/os-release, which always exists on systemd distros.
                local codename=""
                if command -v lsb_release >/dev/null 2>&1; then
                    codename=$(lsb_release -cs 2>/dev/null)
                fi
                if [ -z "$codename" ] && [ -r /etc/os-release ]; then
                    codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}")
                fi
                if [ -z "$codename" ]; then
                    warn "could not determine distro codename — skipping terraform apt repo"
                    return 0
                fi
                if curl -fsSL https://apt.releases.hashicorp.com/gpg \
                        | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg 2>/dev/null; then
                    echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $codename main" \
                        | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
                    $SUDO apt-get $APT_LOCK update -qq && $SUDO apt-get $APT_LOCK install -y terraform \
                        || warn "terraform install failed"
                fi
                ;;
            *) warn "no terraform recipe for $PKG — see https://developer.hashicorp.com/terraform/install" ;;
        esac
    fi
}

# gh_latest_tag <owner/repo> -> echoes the latest release tag, e.g. v1.2.3
gh_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Dev tools the Mac gets from Homebrew (brew.txt) that have no usable distro
# package on Linux. Static release binaries from upstream, each guarded so a
# re-run is a no-op. yq here is mikefarah/yq (Go) — Debian's "yq" package is an
# unrelated Python jq wrapper with different syntax, so it is deliberately not
# in apt.txt.
install_linux_extras() {
    local garch="amd64"; [ "$(uname -m)" = "aarch64" ] && garch="arm64"
    local tmp tag

    if ! command -v yq >/dev/null 2>&1 || ! yq --version 2>&1 | grep -q mikefarah; then
        log "installing yq (mikefarah)"
        curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${garch}" -o /tmp/yq \
            && $SUDO install -m 0755 /tmp/yq /usr/local/bin/yq || warn "yq install failed"
        rm -f /tmp/yq
    fi

    if ! command -v k9s >/dev/null 2>&1; then
        log "installing k9s"
        tmp=$(mktemp -d)
        curl -fsSL "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${garch}.tar.gz" \
            | tar -xz -C "$tmp" k9s && $SUDO install -m 0755 "$tmp/k9s" /usr/local/bin/k9s \
            || warn "k9s install failed"
        rm -rf "$tmp"
    fi

    if ! command -v stern >/dev/null 2>&1; then
        tag=$(gh_latest_tag stern/stern)
        if [ -n "$tag" ]; then
            log "installing stern $tag"
            tmp=$(mktemp -d)
            curl -fsSL "https://github.com/stern/stern/releases/download/${tag}/stern_${tag#v}_linux_${garch}.tar.gz" \
                | tar -xz -C "$tmp" stern && $SUDO install -m 0755 "$tmp/stern" /usr/local/bin/stern \
                || warn "stern install failed"
            rm -rf "$tmp"
        else
            warn "could not determine latest stern version"
        fi
    fi

    if ! command -v dive >/dev/null 2>&1; then
        tag=$(gh_latest_tag wagoodman/dive)
        if [ -n "$tag" ]; then
            log "installing dive $tag"
            tmp=$(mktemp -d)
            curl -fsSL "https://github.com/wagoodman/dive/releases/download/${tag}/dive_${tag#v}_linux_${garch}.tar.gz" \
                | tar -xz -C "$tmp" dive && $SUDO install -m 0755 "$tmp/dive" /usr/local/bin/dive \
                || warn "dive install failed"
            rm -rf "$tmp"
        else
            warn "could not determine latest dive version"
        fi
    fi

    if ! command -v sops >/dev/null 2>&1; then
        tag=$(gh_latest_tag getsops/sops)
        if [ -n "$tag" ]; then
            log "installing sops $tag"
            curl -fsSL "https://github.com/getsops/sops/releases/download/${tag}/sops-${tag}.linux.${garch}" -o /tmp/sops \
                && $SUDO install -m 0755 /tmp/sops /usr/local/bin/sops || warn "sops install failed"
            rm -f /tmp/sops
        else
            warn "could not determine latest sops version"
        fi
    fi

    if ! command -v cloudflared >/dev/null 2>&1; then
        log "installing cloudflared"
        curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${garch}" -o /tmp/cloudflared \
            && $SUDO install -m 0755 /tmp/cloudflared /usr/local/bin/cloudflared || warn "cloudflared install failed"
        rm -f /tmp/cloudflared
    fi

    # Azure kubelogin (AKS exec credential plugin) — brew: azure/kubelogin/kubelogin
    if ! command -v kubelogin >/dev/null 2>&1; then
        log "installing kubelogin (Azure)"
        tmp=$(mktemp -d)
        if curl -fsSL "https://github.com/Azure/kubelogin/releases/latest/download/kubelogin-linux-${garch}.zip" -o "$tmp/k.zip" \
                && unzip -q "$tmp/k.zip" -d "$tmp"; then
            $SUDO install -m 0755 "$tmp/bin/linux_${garch}/kubelogin" /usr/local/bin/kubelogin \
                || warn "kubelogin install failed"
        else
            warn "kubelogin download failed"
        fi
        rm -rf "$tmp"
    fi

    # uv — Astral's installer drops uv/uvx into ~/.local/bin (on PATH via
    # languages.zsh). INSTALLER_NO_MODIFY_PATH: PATH is the dotfiles' job.
    if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
        log "installing uv"
        curl -LsSf https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh >/dev/null 2>&1 \
            || warn "uv install failed"
    fi

    # Claude Code — native installer, also into ~/.local/bin.
    if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
        log "installing Claude Code"
        curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1 || warn "claude code install failed"
    fi
}

# ── Stage: link ──────────────────────────────────────────────────────────────
stage_link() {
    step "Linking dotfiles"
    [ -f "$DOTFILES_DIR/install.sh" ] || die "install.sh not found in $DOTFILES_DIR"
    # install.sh owns symlinks and Oh My Zsh. --local because bootstrap already
    # handled the clone/pull.
    bash "$DOTFILES_DIR/install.sh" local || warn "install.sh reported problems"
}

# ── Template rendering ───────────────────────────────────────────────────────
ensure_local_dir() {
    mkdir -p "$DOTFILES_LOCAL_DIR"/{aws,kube,git,config}
    chmod 700 "$DOTFILES_LOCAL_DIR"
}

# Escape a value for safe use as a sed replacement with '|' as delimiter.
sed_escape() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# render [--strip-unresolved] <template> <output> KEY=VALUE ...
#
# With --strip-unresolved, any line still holding a {{PLACEHOLDER}} is deleted.
# Use it for files where a literal placeholder is actively harmful — a gitconfig
# with `email = {{GIT_EMAIL}}` makes git author commits with that string, whereas
# omitting the line makes git stop and ask for an identity.
#
# Stripping happens BEFORE the comparison below, so a re-run produces a byte
# identical file and does not write a redundant .bak.
render() {
    local strip=false
    if [ "${1:-}" = "--strip-unresolved" ]; then strip=true; shift; fi
    local tpl="$1" out="$2"; shift 2
    [ -f "$tpl" ] || { warn "template missing: $tpl"; return 1; }

    local tmp; tmp=$(mktemp)
    cp "$tpl" "$tmp"
    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        [ -n "$value" ] || continue
        sed -i.bak -e "s|{{${key}}}|$(sed_escape "$value")|g" "$tmp" && rm -f "$tmp.bak"
    done

    if [ "$strip" = true ] && grep -q '{{[A-Z_]*}}' "$tmp" 2>/dev/null; then
        sed -i.bak '/{{[A-Z_]*}}/d' "$tmp" && rm -f "$tmp.bak"
    fi

    if [ -f "$out" ] && ! cmp -s "$tmp" "$out"; then
        local backup
        backup="$out.bak.$(date +%Y%m%d%H%M%S)"
        cp "$out" "$backup"
        log "existing $out backed up to $backup"
    fi
    mv "$tmp" "$out"
    chmod 600 "$out"
    log "rendered $out"

    local left; left=$(grep -o '{{[A-Z_]*}}' "$out" 2>/dev/null | sort -u | tr '\n' ' ')
    [ -n "$left" ] && warn "unfilled placeholders in $out: $left"
    return 0
}

# link_into_home <source> <target>
link_into_home() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -L "$dst" ]; then
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        local backup
        backup="$dst.bak.$(date +%Y%m%d%H%M%S)"
        mv "$dst" "$backup"
        log "existing $dst backed up to $backup"
    fi
    ln -s "$src" "$dst"
    log "linked $dst -> $src"
}

# ask_valid <prompt> <default> <regex> <description>
#
# Like ask(), but refuses input that cannot possibly be right and re-prompts.
# Without this, a mistyped or shifted answer is accepted silently and written
# straight into a config: an email of "Test User", or a role ARN built from
# region = y. Those failures surface much later, as confusing AWS or git errors.
#
# Diagnostics go to stderr, because callers capture stdout as the answer.
# An empty reply means "skipped" and is always allowed — the placeholder stays and
# render() warns about it.
ask_valid() {
    local prompt="$1" default="$2" regex="$3" what="$4" reply="" tries=0
    while :; do
        reply=$(ask "$prompt" "$default")
        [ -n "$reply" ] || return 0
        if printf '%s' "$reply" | grep -qE "$regex"; then
            printf '%s' "$reply"
            return 0
        fi
        printf "${YELLOW}  not a valid %s: '%s'${NC}\n" "$what" "$reply" >&2
        tries=$((tries + 1))
        # Non-interactive, or the user keeps missing: skip rather than loop forever
        # or write something invalid.
        if [ "$ASSUME_YES" = true ] || ! have_tty || [ "$tries" -ge 3 ]; then
            printf "${YELLOW}  leaving %s unset${NC}\n" "$what" >&2
            return 0
        fi
    done
}

# Shapes used below. Deliberately loose — enough to catch a wrong *kind* of value,
# not to second-guess valid ones.
RE_EMAIL='^[^[:space:]@]+@[^[:space:]@]+\.[A-Za-z]{2,}$'
RE_ACCOUNT='^[0-9]{12}$'
RE_REGION='^[a-z]{2}(-[a-z]+)+-[0-9]+$'
RE_EXTID='^[A-Za-z0-9._:/+=@-]{2,}$'
RE_NAME='^[^@]+$'

# ── Stage: identity ──────────────────────────────────────────────────────────
stage_identity() {
    step "Git identity and SSH"
    ensure_local_dir

    local machine_key
    machine_key=$(detect_machine_key)
    [ -n "$machine_key" ] || machine_key="default"
    log "machine key: $machine_key"

    local cur_name cur_email
    cur_name=$(git config --global --get user.name 2>/dev/null || true)
    cur_email=$(git config --global --get user.email 2>/dev/null || true)

    local git_name git_email
    git_name=$(ask_valid "Git author name" "${cur_name:-$(id -un)}" "$RE_NAME" "name (an '@' suggests you typed the email here)")
    git_email=$(ask_valid "Git author email" "${cur_email:-}" "$RE_EMAIL" "email address")

    # SSH key, named per machine so a lost laptop is revocable on its own.
    local key_path="$HOME/.ssh/id_${machine_key}"
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

    if [ ! -f "$key_path" ]; then
        if confirm "Generate a new ed25519 SSH key at $key_path?" y; then
            ssh-keygen -t ed25519 -C "${git_email:-$(id -un)@$machine_key}" -f "$key_path" -N "" \
                && log "SSH key generated" \
                || warn "ssh-keygen failed"
        fi
    else
        log "SSH key already present: $key_path"
    fi

    local signing_key="" gpgsign="false"
    local allowed_signers="$HOME/.ssh/allowed_signers"
    if [ -f "$key_path.pub" ]; then
        if confirm "Enable SSH commit signing with this key?" y; then
            signing_key="$key_path.pub"
            gpgsign="true"
            # allowed_signers lets *you* verify your own signatures locally;
            # without it `git log --show-signature` cannot validate anything.
            if [ -n "$git_email" ]; then
                local line
                line="$git_email namespaces=\"git\" $(cat "$key_path.pub")"
                if [ ! -f "$allowed_signers" ] || ! grep -qF "$(cat "$key_path.pub")" "$allowed_signers" 2>/dev/null; then
                    printf '%s\n' "$line" >>"$allowed_signers"
                    chmod 600 "$allowed_signers"
                    log "added this key to $allowed_signers"
                fi
            else
                warn "no email given — skipping allowed_signers entry"
            fi
        fi
    else
        warn "no public key at $key_path.pub — commit signing left disabled"
    fi

    render --strip-unresolved \
           "$DOTFILES_DIR/templates/git/gitconfig.template" \
           "$DOTFILES_LOCAL_DIR/git/gitconfig" \
           "GIT_NAME=$git_name" \
           "GIT_EMAIL=$git_email" \
           "GIT_SIGNING_KEY=$signing_key" \
           "GIT_GPGSIGN=$gpgsign" \
           "GIT_ALLOWED_SIGNERS=$allowed_signers" \
           "DOTFILES_DIR=$DOTFILES_DIR"

    # render --strip-unresolved above dropped any line whose value was skipped, so
    # an unset email or signing key is absent rather than literal.
    if ! grep -q '^[[:space:]]*email[[:space:]]*=' "$DOTFILES_LOCAL_DIR/git/gitconfig" 2>/dev/null; then
        warn "git email not set — commits will be refused until: ./bootstrap.sh --only identity"
    fi

    link_into_home "$DOTFILES_LOCAL_DIR/git/gitconfig" "$HOME/.gitconfig"

    write_ssh_config_local "$machine_key" "$key_path"

    if [ -f "$key_path.pub" ]; then
        printf "\n${YELLOW}Add this public key to GitHub (Settings → SSH and GPG keys):${NC}\n"
        printf "  as an %s key AND as a %s key (both — signing verification needs the second)\n" "Authentication" "Signing"
        printf "  %s\n\n" "$(cat "$key_path.pub")"
    fi
}

# ~/.ssh/config.local holds everything that must not be in a public repo or that
# is OS-specific. ssh/config Includes it.
#
# Two things force this file to exist:
#   1. UseKeychain is macOS-only. On Linux, older OpenSSH treats an unknown
#      keyword as a fatal error, so it cannot live in the shared config.
#   2. ssh/config sets `IdentitiesOnly yes`, which means only listed keys are
#      offered. The per-machine key must be named here or git-over-SSH breaks.
write_ssh_config_local() {
    local machine_key="$1" key_path="$2"
    local out="$HOME/.ssh/config.local"

    if [ -f "$out" ] && grep -q 'managed by bootstrap.sh' "$out" 2>/dev/null; then
        log "regenerating $out"
    elif [ -f "$out" ]; then
        log "$out exists and was not generated by bootstrap — leaving it alone"
        return 0
    fi

    {
        printf '# ~/.ssh/config.local — managed by bootstrap.sh\n'
        printf '#\n'
        printf '# Local and OS-specific SSH settings. NEVER committed: put internal\n'
        printf '# hostnames, jump hosts and usernames here, not in the dotfiles repo.\n'
        printf '# Regenerate with: ./bootstrap.sh --only identity\n\n'
        printf 'Host *\n'
        if [ "$OS" = "macos" ]; then
            printf '  # macOS only — loads the passphrase from the login keychain.\n'
            printf '  # Unknown keyword on Linux, which is why it is not in ssh/config.\n'
            printf '  UseKeychain yes\n'
        fi
        if [ -f "$key_path" ]; then
            printf '  # Per-machine key (%s), so one lost machine is revocable alone.\n' "$machine_key"
            printf '  IdentityFile %s\n' "$key_path"
        fi
        printf '\n# Example: scope an insecure legacy exception to ONE host, never globally.\n'
        printf '# Host legacy-box\n'
        printf '#   HostkeyAlgorithms +ssh-rsa\n'
        printf '#   PubkeyAcceptedAlgorithms +ssh-rsa\n'
        printf '\n# Example: agent forwarding for one trusted host only.\n'
        printf '# Host bastion\n'
        printf '#   ForwardAgent yes\n'
    } >"$out"

    chmod 600 "$out"
    log "wrote $out"

    # ControlPath needs its directory to exist, and ssh will not create it.
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

    if command -v ssh >/dev/null 2>&1; then
        if ssh -G github.com >/dev/null 2>&1; then
            log "ssh config parses cleanly"
        else
            warn "ssh rejected the config — check ~/.ssh/config and ~/.ssh/config.local"
        fi
    fi
}

# ── Stage: cloud ─────────────────────────────────────────────────────────────
stage_cloud() {
    step "Cloud configuration (rendered outside the repo)"
    ensure_local_dir

    printf "%s\n" "These values are infrastructure identifiers. They are written to"
    printf "%s\n" "  $DOTFILES_LOCAL_DIR"
    printf "%s\n\n" "which is outside the git repo. Press Enter to skip any prompt."

    if confirm "Configure AWS profiles?" y; then
        local region region_dr acct_prod acct_shared acct_staging acct_security acct_dr ext_id
        region=$(ask_valid        "  AWS primary region" "us-east-1" "$RE_REGION" "AWS region")
        region_dr=$(ask_valid     "  AWS DR region"      "us-west-2" "$RE_REGION" "AWS region")
        acct_prod=$(ask_valid     "  AWS account ID — prod"     "" "$RE_ACCOUNT" "12-digit AWS account ID")
        acct_shared=$(ask_valid   "  AWS account ID — shared"   "" "$RE_ACCOUNT" "12-digit AWS account ID")
        acct_staging=$(ask_valid  "  AWS account ID — staging"  "" "$RE_ACCOUNT" "12-digit AWS account ID")
        acct_security=$(ask_valid "  AWS account ID — security" "" "$RE_ACCOUNT" "12-digit AWS account ID")
        acct_dr=$(ask_valid       "  AWS account ID — dr"       "" "$RE_ACCOUNT" "12-digit AWS account ID")
        ext_id=$(ask_valid        "  AWS ExternalId for DR replication role" "" "$RE_EXTID" "ExternalId (no spaces)")

        render "$DOTFILES_DIR/templates/aws/config.template" \
               "$DOTFILES_LOCAL_DIR/aws/config" \
               "AWS_REGION=$region" \
               "AWS_REGION_DR=$region_dr" \
               "AWS_ACCOUNT_PROD=$acct_prod" \
               "AWS_ACCOUNT_SHARED=$acct_shared" \
               "AWS_ACCOUNT_STAGING=$acct_staging" \
               "AWS_ACCOUNT_SECURITY=$acct_security" \
               "AWS_ACCOUNT_DR=$acct_dr" \
               "AWS_EXTERNAL_ID_DR=$ext_id"

        link_into_home "$DOTFILES_LOCAL_DIR/aws/config" "$HOME/.aws/config"
        [ -n "$ext_id" ] && warn "ExternalId stored in $DOTFILES_LOCAL_DIR/aws/config (mode 600, outside git)"
    fi

    if confirm "Create a kubeconfig placeholder?" y; then
        if [ -s "$HOME/.kube/config" ] && ! [ -L "$HOME/.kube/config" ]; then
            log "existing ~/.kube/config left untouched (it is a real file, not a link)"
        else
            render "$DOTFILES_DIR/templates/kube/config.template" \
                   "$DOTFILES_LOCAL_DIR/kube/config" \
                   "AWS_REGION=${region:-us-east-1}"
            link_into_home "$DOTFILES_LOCAL_DIR/kube/config" "$HOME/.kube/config"
            printf "  Populate it with: aws eks update-kubeconfig --profile prod --name <cluster>\n"
        fi
    fi

    if confirm "Configure Azure subscription mapping?" n; then
        local tpl="$DOTFILES_DIR/config/azure-subscriptions.env.template"
        local out="$DOTFILES_LOCAL_DIR/config/azure-subscriptions.env"
        if [ ! -f "$out" ]; then
            cp "$tpl" "$out" 2>/dev/null && chmod 600 "$out" \
                && log "copied template to $out — edit it to add subscription IDs" \
                || warn "could not copy azure template"
        else
            log "$out already exists, leaving it alone"
        fi
    fi
}

# ── Stage: node ──────────────────────────────────────────────────────────────
stage_node() {
    step "Node via nvm"
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        local nvm_ver="v0.40.6"
        log "installing nvm $nvm_ver"
        PROFILE=/dev/null curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_ver}/install.sh" | bash >/dev/null 2>&1 \
            || { warn "nvm install failed"; return 0; }
    else
        log "nvm already installed"
    fi
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    if command -v node >/dev/null 2>&1 && nvm ls default >/dev/null 2>&1; then
        log "node already installed: $(node -v)"
    else
        log "installing Node LTS"
        nvm install --lts >/dev/null 2>&1 && nvm alias default 'lts/*' >/dev/null 2>&1 \
            && log "node $(node -v) installed and set as default" \
            || warn "node install failed"
    fi
    # The nvm init lines belong in the machine-specific zsh file, which .zshrc
    # sources. See scripts/detect-machine.sh for how that filename is chosen.
    local machine_key mf
    machine_key=$(detect_machine_key)
    mf="$DOTFILES_DIR/zsh/machines/${machine_key}.zsh"
    # Match .zshrc's hash-suffix resolution: a machine file with a renamed human
    # prefix (e.g. devdesktop-<hash>.zsh) is still this machine's file, so do not
    # create a second, canonical-named one next to it.
    if [ -n "$machine_key" ] && [ ! -f "$mf" ]; then
        local hit
        for hit in "$DOTFILES_DIR"/zsh/machines/*-"${machine_key##*-}".zsh; do
            [ -f "$hit" ] && { mf="$hit"; break; }
        done
    fi
    if [ -n "$machine_key" ] && ! grep -q 'NVM_DIR' "$mf" 2>/dev/null; then
        {
            printf '\n# Node via nvm\n'
            printf 'export NVM_DIR="$HOME/.nvm"\n'
            printf '[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\n'
            printf '[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"\n'
        } >>"$mf"
        log "added nvm init to $mf"
    fi
}

# tool_works <name> -> 0 if the tool is present AND actually runs.
#
# `command -v java` is not enough on macOS: /usr/bin/java is a stub that exists
# even with no JDK installed and exits 1 with "Unable to locate a Java Runtime".
# Testing presence alone reported java as installed when it was unusable.
tool_works() {
    command -v "$1" >/dev/null 2>&1 || return 1
    case "$1" in
        java) java -version >/dev/null 2>&1 ;;
        *)    return 0 ;;
    esac
}

# Corretto is a macOS .pkg inside a cask, so its installer needs a sudo password
# and cannot complete unattended (including under --yes). Say so precisely rather
# than leaving "java missing" unexplained.
java_hint() {
    tool_works java && return 0
    [ "$OS" = "macos" ] || return 0
    printf "\n${YELLOW}Java (Corretto 21) needs an interactive sudo password:${NC}\n"
    printf "  brew install --cask corretto@21\n"
    printf "  Then open a new shell; languages.zsh sets JAVA_HOME automatically.\n"
}

# ── Stage: verify ────────────────────────────────────────────────────────────
stage_verify() {
    step "Verifying"

    if [ -x "$DOTFILES_DIR/scripts/audit-repo.sh" ]; then
        "$DOTFILES_DIR/scripts/audit-repo.sh" || warn "audit reported findings — see above"
    else
        warn "scripts/audit-repo.sh not found; skipping credential audit"
    fi

    printf "\n${BLUE}Final state${NC}\n"
    printf '  machine key   : %s\n' "$(detect_machine_key)"
    printf '  repo          : %s\n' "$DOTFILES_DIR"
    printf '  rendered      : %s\n' "$DOTFILES_LOCAL_DIR"
    local t label
    for t in "$HOME/.zshrc" "$HOME/.gitconfig" "$HOME/.ssh/config" \
             "$HOME/.aws/config" "$HOME/.kube/config"; do
        # Label with the path relative to $HOME: basename alone printed "config"
        # three times, for .ssh, .aws and .kube.
        # shellcheck disable=SC2088  # literal display label, not a path to expand
        label="~/${t#"$HOME"/}"
        if [ -L "$t" ]; then
            printf '  %-16s -> %s\n' "$label" "$(readlink "$t")"
        elif [ -e "$t" ]; then
            printf '  %-16s    (regular file, not a link)\n' "$label"
        else
            printf '  %-16s    (missing)\n' "$label"
        fi
    done
    printf "\n${BLUE}Toolchain${NC}\n"
    local b missing=0
    for b in git zsh vim tmux jq \
             node python3 java go \
             aws az gcloud \
             kubectl kubectx helm terraform terragrunt gh; do
        if tool_works "$b"; then
            printf '  %-10s %s\n' "$b" "$(command -v "$b")"
        elif command -v "$b" >/dev/null 2>&1; then
            printf "  %-10s ${YELLOW}%s${NC}\n" "$b" "present but not working: $(command -v "$b")"
            missing=$((missing + 1))
        else
            printf "  %-10s ${YELLOW}%s${NC}\n" "$b" "(not installed)"
            missing=$((missing + 1))
        fi
    done
    if [ "$missing" -gt 0 ]; then
        warn "$missing tool(s) missing or broken — re-run: ./bootstrap.sh --only packages"
        java_hint
    fi
    printf "\n${GREEN}Done.${NC} Open a new shell to pick everything up.\n"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    printf "${BLUE}dotfiles bootstrap${NC}\n"
    detect_platform
    stage_repo

    [ -d "$DOTFILES_DIR" ] || die "$DOTFILES_DIR missing after clone"

    [ "$DO_PACKAGES" = true ] && stage_packages
    [ "$DO_LINK"     = true ] && stage_link
    [ "$DO_IDENTITY" = true ] && stage_identity
    [ "$DO_CLOUD"    = true ] && stage_cloud
    [ "$DO_NODE"     = true ] && stage_node
    stage_verify
}

main "$@"
