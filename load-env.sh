#!/usr/bin/env bash
# ==============================================================================
# Central Environment Loader (load-env.sh)
# Loads root .env (or .env.example) and local overrides with variable interpolation
# ==============================================================================

# Determine repository root based on this script's location
REPO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to safely source an env file with CRLF stripping and variable expansion
_source_env() {
  local env_path="$1"
  [[ ! -f "${env_path}" ]] && return 1

  # Automatically export all variables defined or evaluated
  set -a
  # Strip carriage returns and source via process substitution
  # shellcheck disable=SC1090
  source <(tr -d '\r' < "${env_path}")
  set +a
}

# 1. Load Root .env (or fallback to .env.example if .env not created yet)
if [[ -f "${REPO_ROOT_DIR}/.env" ]]; then
  _source_env "${REPO_ROOT_DIR}/.env"
elif [[ -f "${REPO_ROOT_DIR}/.env.example" ]]; then
  _source_env "${REPO_ROOT_DIR}/.env.example"
fi

# 2. Check if the script that sourced load-env.sh has a directory-local .env
if [[ -n "${BASH_SOURCE[1]:-}" ]]; then
  CALLING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
  if [[ "${CALLING_SCRIPT_DIR}" != "${REPO_ROOT_DIR}" && -f "${CALLING_SCRIPT_DIR}/.env" ]]; then
    _source_env "${CALLING_SCRIPT_DIR}/.env"
  fi
fi
