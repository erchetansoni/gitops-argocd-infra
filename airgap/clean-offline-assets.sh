#!/usr/bin/env bash

# ==============================================================================
# Script: clean-offline-assets.sh
# Purpose: Delete bundled offline image tarballs and Helm charts in airgap
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Invoke root cleanup script targeting airgap directory by default if no arguments supplied
has_dir=false
for arg in "$@"; do
  if [[ -d "$arg" ]]; then
    has_dir=true
    break
  fi
done

if [[ "$has_dir" == "false" ]]; then
  exec "${ROOT_DIR}/clean-images.sh" "$@" "${SCRIPT_DIR}"
else
  exec "${ROOT_DIR}/clean-images.sh" "$@"
fi

