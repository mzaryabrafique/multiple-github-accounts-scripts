#!/usr/bin/env bash
# Shared helpers for switching the machine-wide GitHub identity and HTTPS auth.
# Tokens are stored in ~/.config/github-account-switcher (mode 600), never printed.

set -euo pipefail

CONFIG_DIR="${HOME}/.config/github-account-switcher"
ACTIVE_FILE="${CONFIG_DIR}/active"

# Force git HTTPS so SSH remotes also use the active PAT.
FORCE_HTTPS="${FORCE_GITHUB_HTTPS:-1}"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
err()   { printf '\033[1;31m==>\033[0m %s\n' "$*" >&2; }

require_tty() {
  if [[ ! -t 0 ]]; then
    err "This script needs an interactive terminal to collect credentials."
    exit 1
  fi
}

ensure_config_dir() {
  mkdir -p "${CONFIG_DIR}"
  chmod 700 "${CONFIG_DIR}"
}

profile_file() {
  local profile="$1"
  printf '%s/%s.env' "${CONFIG_DIR}" "${profile}"
}

validate_email() {
  [[ "$1" == ?*@?*.?* ]]
}

validate_token() {
  # Classic PATs: ghp_...  Fine-grained: github_pat_...
  [[ "$1" == ghp_* || "$1" == github_pat_* ]]
}

prompt_nonempty() {
  local label="$1"
  local default="${2:-}"
  local value=""

  if [[ -n "${default}" ]]; then
    read -r -p "${label} [${default}]: " value
    value="${value:-${default}}"
  else
    read -r -p "${label}: " value
  fi

  if [[ -z "${value}" ]]; then
    err "${label} cannot be empty."
    exit 1
  fi
  printf '%s' "${value}"
}

save_profile() {
  local profile="$1"
  local name="$2"
  local email="$3"
  local username="$4"
  local token="$5"
  local file

  file="$(profile_file "${profile}")"
  umask 077
  {
    printf 'GITHUB_NAME=%q\n' "${name}"
    printf 'GITHUB_EMAIL=%q\n' "${email}"
    printf 'GITHUB_USERNAME=%q\n' "${username}"
    printf 'GITHUB_TOKEN=%q\n' "${token}"
  } > "${file}"
  chmod 600 "${file}"
}

load_profile() {
  local profile="$1"
  local file
  file="$(profile_file "${profile}")"

  if [[ ! -f "${file}" ]]; then
    return 1
  fi

  # shellcheck disable=SC1090
  source "${file}"

  if [[ -z "${GITHUB_NAME:-}" || -z "${GITHUB_EMAIL:-}" || -z "${GITHUB_USERNAME:-}" || -z "${GITHUB_TOKEN:-}" ]]; then
    err "Profile file is incomplete: ${file}"
    err "Re-run with --setup"
    exit 1
  fi
}

setup_profile() {
  local profile="$1"
  local default_name default_email default_user
  local name email username token

  require_tty
  ensure_config_dir

  default_name="$(git config --global user.name 2>/dev/null || true)"
  default_email="$(git config --global user.email 2>/dev/null || true)"
  default_user="${default_name}"

  info "First-time setup for the '${profile}' GitHub profile."
  echo "Use a classic PAT (ghp_...) with repo, workflow, and gist scopes as needed."
  echo

  name="$(prompt_nonempty "Git commit name" "${default_name}")"
  email="$(prompt_nonempty "Git commit email" "${default_email}")"
  username="$(prompt_nonempty "GitHub username" "${default_user}")"

  if ! validate_email "${email}"; then
    err "That does not look like a valid email: ${email}"
    exit 1
  fi

  read -r -s -p "Classic Personal Access Token: " token
  echo
  if ! validate_token "${token}"; then
    err "Token must start with ghp_ (classic) or github_pat_ (fine-grained)."
    exit 1
  fi

  save_profile "${profile}" "${name}" "${email}" "${username}" "${token}"
  ok "Saved ${profile} credentials to $(profile_file "${profile}")"
}

erase_github_https_creds() {
  # git credential uses the configured helper (osxkeychain on macOS).
  printf 'protocol=https\nhost=github.com\n\n' | git credential reject >/dev/null 2>&1 || true
  printf 'protocol=https\nhost=gist.github.com\n\n' | git credential reject >/dev/null 2>&1 || true
  printf 'protocol=http\nhost=github.com\n\n' | git credential reject >/dev/null 2>&1 || true
}

store_github_https_creds() {
  local username="$1"
  local token="$2"

  printf 'protocol=https\nhost=github.com\nusername=%s\npassword=%s\n\n' \
    "${username}" "${token}" | git credential approve
  printf 'protocol=https\nhost=gist.github.com\nusername=%s\npassword=%s\n\n' \
    "${username}" "${token}" | git credential approve
}

configure_https_rewrite() {
  if [[ "${FORCE_HTTPS}" == "1" ]]; then
    git config --global url."https://github.com/".insteadOf "git@github.com:"
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  fi
}

update_netrc() {
  local username="$1"
  local token="$2"
  local netrc="${HOME}/.netrc"
  local tmp

  tmp="$(mktemp)"
  if [[ -f "${netrc}" ]]; then
    # Drop previous github.com / gist.github.com blocks, keep everything else.
    awk '
      BEGIN { skip=0 }
      $1=="machine" && ($2=="github.com" || $2=="api.github.com" || $2=="gist.github.com") { skip=1; next }
      $1=="machine" { skip=0 }
      skip==0 { print }
    ' "${netrc}" > "${tmp}"
  fi

  {
    cat "${tmp}"
    printf '\nmachine github.com\n  login %s\n  password %s\n' "${username}" "${token}"
    printf 'machine gist.github.com\n  login %s\n  password %s\n' "${username}" "${token}"
    printf 'machine api.github.com\n  login %s\n  password %s\n' "${username}" "${token}"
  } > "${netrc}"

  rm -f "${tmp}"
  chmod 600 "${netrc}"
}

login_gh_cli() {
  local token="$1"

  if ! command -v gh >/dev/null 2>&1; then
    warn "GitHub CLI (gh) is not installed; skipped gh auth login."
    warn "Git HTTPS + PAT is enough for clone/push/pull. Install gh later if you want it."
    return 0
  fi

  if echo "${token}" | gh auth login --hostname github.com --with-token --git-protocol https >/dev/null; then
    ok "GitHub CLI is now authenticated as this profile."
  else
    warn "gh auth login failed. Git HTTPS credentials were still updated."
  fi
}

apply_git_identity() {
  local name="$1"
  local email="$2"
  local username="$3"

  git config --global user.name "${name}"
  git config --global user.email "${email}"
  git config --global github.user "${username}"
}

show_status() {
  local profile="$1"

  echo
  ok "Active GitHub profile: ${profile}"
  echo "    user.name     : $(git config --global user.name)"
  echo "    user.email    : $(git config --global user.email)"
  echo "    github.user   : $(git config --global github.user)"
  echo "    HTTPS auth    : github.com → ${GITHUB_USERNAME} (PAT stored in keychain/helper)"
  if command -v gh >/dev/null 2>&1; then
    echo
    gh auth status --hostname github.com 2>&1 | sed 's/^/    /' || true
  fi
}

switch_to_profile() {
  local profile="$1"
  local file
  file="$(profile_file "${profile}")"

  ensure_config_dir

  if [[ "${2:-}" == "--setup" ]] || [[ ! -f "${file}" ]]; then
    setup_profile "${profile}"
  fi

  load_profile "${profile}"

  info "Switching GitHub identity and credentials to '${profile}'..."

  # Prefer macOS Keychain; fall back to encrypted store if helper is unset.
  if [[ -z "$(git config --global credential.helper || true)" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then
      git config --global credential.helper osxkeychain
    else
      git config --global credential.helper store
    fi
  fi

  erase_github_https_creds
  store_github_https_creds "${GITHUB_USERNAME}" "${GITHUB_TOKEN}"
  apply_git_identity "${GITHUB_NAME}" "${GITHUB_EMAIL}" "${GITHUB_USERNAME}"
  configure_https_rewrite
  update_netrc "${GITHUB_USERNAME}" "${GITHUB_TOKEN}"
  login_gh_cli "${GITHUB_TOKEN}"

  printf '%s\n' "${profile}" > "${ACTIVE_FILE}"
  chmod 600 "${ACTIVE_FILE}"

  show_status "${profile}"
}
