#!/usr/bin/env bash

# ==============================================================================
# Script: clean-images.sh
# Purpose: Delete large image archives and chart packages (*.tar, *.tgz, *.tar.gz, *.tar.zst)
# ==============================================================================

set -euo pipefail

# Avoid path mangling in Git Bash on Windows
export MSYS_NO_PATHCONV=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}"
DRY_RUN=false
FORCE=false

print_usage() {
  echo "Usage: $(basename "$0") [OPTIONS] [DIRECTORY]"
  echo ""
  echo "Deletes image archives and package tarballs matching:"
  echo "  *.tar, *.tgz, *.tar.gz, *.tar.zst"
  echo ""
  echo "Arguments:"
  echo "  DIRECTORY            Directory to clean (default: repository root '${SCRIPT_DIR}')"
  echo ""
  echo "Options:"
  echo "  -d, --dry-run        List matching files and total size without deleting"
  echo "  -f, --force          Delete files without interactive confirmation prompt"
  echo "  -h, --help           Show this help message"
  echo ""
  echo "Examples:"
  echo "  ./clean-images.sh --dry-run"
  echo "  ./clean-images.sh --force"
  echo "  ./clean-images.sh ./airgap"
}

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    -*)
      echo "❌ Unknown option: $1"
      print_usage
      exit 1
      ;;
    *)
      if [[ -d "$1" ]]; then
        TARGET_DIR="$(cd "$1" && pwd)"
      else
        echo "❌ Directory not found: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

echo "================================================================="
echo " 🧹 Image & Archive Cleanup Tool"
echo "================================================================="
echo "🔍 Target directory: ${TARGET_DIR}"
echo "🎯 Patterns: *.tar, *.tgz, *.tar.gz, *.tar.zst (excluding .git)"
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "⚠️  MODE: DRY-RUN (no files will be deleted)"
fi
echo "================================================================="

# Find matching files, excluding .git
FILES=()
while IFS= read -r -d $'\0' file; do
  FILES+=("$file")
done < <(find "${TARGET_DIR}" -type f \( -name "*.tar" -o -name "*.tgz" -o -name "*.tar.gz" -o -name "*.tar.zst" \) ! -path "*/.git/*" -print0)

TOTAL_COUNT=${#FILES[@]}

if [[ ${TOTAL_COUNT} -eq 0 ]]; then
  echo "✨ No matching image or archive files found. Everything is clean!"
  exit 0
fi

echo ""
echo "Found ${TOTAL_COUNT} matching file(s):"
echo "-----------------------------------------------------------------"

TOTAL_BYTES=0

# Helper to humanize byte size
human_size() {
  local bytes=$1
  if (( bytes >= 1073741824 )); then
    awk "BEGIN {printf \"%.2f GiB\", ${bytes}/1073741824}"
  elif (( bytes >= 1048576 )); then
    awk "BEGIN {printf \"%.2f MiB\", ${bytes}/1048576}"
  elif (( bytes >= 1024 )); then
    awk "BEGIN {printf \"%.2f KiB\", ${bytes}/1024}"
  else
    echo "${bytes} B"
  fi
}

for file in "${FILES[@]}"; do
  file_size=0
  if [[ "$OSTYPE" == "darwin"* ]]; then
    file_size=$(stat -f%z "$file" 2>/dev/null || echo 0)
  else
    file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
  fi
  TOTAL_BYTES=$((TOTAL_BYTES + file_size))
  size_display=$(human_size "$file_size")
  rel_path="${file#"${TARGET_DIR}/"}"
  printf "  • %-60s [%s]\n" "${rel_path}" "${size_display}"
done

TOTAL_HUMAN=$(human_size "${TOTAL_BYTES}")
echo "-----------------------------------------------------------------"
echo "📊 Total size to reclaim: ${TOTAL_HUMAN} across ${TOTAL_COUNT} file(s)"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "ℹ️  Dry-run complete. Run without --dry-run to delete these files."
  exit 0
fi

# Confirmation prompt if --force is not set
if [[ "${FORCE}" != "true" ]]; then
  read -r -p "⚠️  Are you sure you want to permanently delete these ${TOTAL_COUNT} file(s)? [y/N]: " confirm
  case "${confirm}" in
    [yY][eE][sS]|[yY])
      echo "🗑️  Deleting files..."
      ;;
    *)
      echo "❌ Aborted by user. No files were deleted."
      exit 0
      ;;
  esac
fi

DELETED_COUNT=0
for file in "${FILES[@]}"; do
  if rm -f "$file"; then
    echo "  ✅ Deleted: ${file#"${TARGET_DIR}/"}"
    DELETED_COUNT=$((DELETED_COUNT + 1))
  else
    echo "  ❌ Failed to delete: $file"
  fi
done

echo ""
echo "================================================================="
echo "🎉 Cleanup completed: Successfully removed ${DELETED_COUNT}/${TOTAL_COUNT} files."
echo "💾 Reclaimed approximately ${TOTAL_HUMAN} of disk space."
echo "================================================================="
