# Azure CLI subscription switch helpers (dotfiles)
#
# Usage:
#   az-prod        # switch to prod subscription (AZ_SUB_PROD)
#   az-shared      # switch to shared subscription (AZ_SUB_SHARED)
#   az-sub <key>   # switch using AZ_SUB_<KEY>
#   az-config      # show where Azure CLI config + subscription mapping live
#
# Defaults:
#   - Azure CLI state:        ~/.dotfiles/config/azure  (AZURE_CONFIG_DIR)
#   - Subscription mappings:  ~/.dotfiles/config/azure-subscriptions.env
#
# Override (optional):
#   export BIGLY_AZ_CONFIG_DIR=...
#   export BIGLY_AZ_SUBSCRIPTIONS_FILE=...

# Resolve dotfiles root even when sourced from zsh or bash.
_az_aliases__source_file=""
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _az_aliases__source_file="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _az_aliases__source_file="${(%):-%N}"
else
  _az_aliases__source_file="$0"
fi

_az_aliases__script_dir="$(CDPATH= cd -- "$(dirname -- "$_az_aliases__source_file")" 2>/dev/null && pwd)"
_az_aliases__dotfiles_root="$(CDPATH= cd -- "${_az_aliases__script_dir}/.." 2>/dev/null && pwd)"

# Keep Azure CLI state under dotfiles config by default.
: "${BIGLY_AZ_CONFIG_DIR:=${_az_aliases__dotfiles_root}/config/azure}"
: "${BIGLY_AZ_SUBSCRIPTIONS_FILE:=${_az_aliases__dotfiles_root}/config/azure-subscriptions.env}"

export AZURE_CONFIG_DIR="$BIGLY_AZ_CONFIG_DIR"

mkdir -p "$AZURE_CONFIG_DIR" 2>/dev/null || true

# Load subscription mapping if present.
if [ -f "$BIGLY_AZ_SUBSCRIPTIONS_FILE" ]; then
  # shellcheck disable=SC1090
  . "$BIGLY_AZ_SUBSCRIPTIONS_FILE"
fi

_az_aliases__upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

_az_aliases__normalize_key() {
  # Uppercase and replace non-alnum with underscores so keys like 'data-prod' work.
  _az_aliases__upper "$1" | sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//'
}

_az_aliases__sub_for_key() {
  key_norm="$(_az_aliases__normalize_key "$1")"
  var="AZ_SUB_${key_norm}"

  # Indirect var lookup: zsh supports ${(P)var}, bash uses eval fallback.
  if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2296
    printf '%s' "${(P)var}"
  else
    eval "printf '%s' "\${$var:-}""
  fi
}

az-config() {
  echo "AZURE_CONFIG_DIR=$AZURE_CONFIG_DIR"
  echo "subscriptions_file=$BIGLY_AZ_SUBSCRIPTIONS_FILE"
  if [ -f "$BIGLY_AZ_SUBSCRIPTIONS_FILE" ]; then
    echo "subscriptions_file_status=present"
  else
    echo "subscriptions_file_status=missing (copy template -> ~/.dotfiles/config/azure-subscriptions.env)"
  fi
}

az-sub() {
  key="${1:-}"
  if [ -z "$key" ]; then
    echo "usage: az-sub <key|subscription-id|subscription-name>" >&2
    return 2
  fi

  sub="$(_az_aliases__sub_for_key "$key")"
  if [ -z "$sub" ]; then
    sub="$key"
  fi

  if ! command -v az >/dev/null 2>&1; then
    echo "az not found in PATH" >&2
    return 127
  fi

  az account set --subscription "$sub" || return $?
  az account show --query '{name:name,id:id,tenantId:tenantId,user:user.name}' -o table
}

az-login() {
  if ! command -v az >/dev/null 2>&1; then
    echo "az not found in PATH" >&2
    return 127
  fi

  if [ -n "${AZ_TENANT_ID:-}" ]; then
    az login --tenant "$AZ_TENANT_ID"
  else
    az login
  fi
}

az-whoami() {
  if ! command -v az >/dev/null 2>&1; then
    echo "az not found in PATH" >&2
    return 127
  fi
  az account show --query '{name:name,id:id,tenantId:tenantId,user:user.name}' -o table
}

az-prod()        { az-sub prod; }
az-shared()      { az-sub shared; }
az-stage()       { az-sub stage; }
az-dev()         { az-sub dev; }
az-bootstrap()   { az-sub bootstrap; }
az-connectivity(){ az-sub connectivity; }
az-identity()    { az-sub identity; }
az-management()  { az-sub management; }
az-data-prod()   { az-sub data-prod; }
az-data-staging(){ az-sub data-staging; }
