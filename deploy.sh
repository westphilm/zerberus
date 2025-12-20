#!/usr/bin/env bash
set -euo pipefail

# Deploy: mirror ./src/ -> /
# - creates backups for files that would be overwritten
# - supports --dry-run and optional --systemd-reload

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${ROOT_DIR}/src/system"

BACKUPS_ROOT="${ROOT_DIR}/backups"

DRY_RUN=0
SYSTEMD_RELOAD=0

usage() {
  cat <<'EOF'
Usage:
  sudo ./deploy.sh [--dry-run] [--systemd-reload]

Behavior:
  - Mirrors ./src/system/ to /
  - Creates backups for overwritten files under ./backups/<timestamp>/
  - Idempotent (re-run safe)

Options:
  --dry-run         Show what would change, don't write anything
  --systemd-reload  Run 'systemctl daemon-reload' after deploy (explicit)
EOF
}

for arg in "${@:-}"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --systemd-reload) SYSTEMD_RELOAD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: Unknown arg: $arg" >&2; usage; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (use sudo)" >&2
  exit 1
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: system src dir not found: $SRC_DIR" >&2
  exit 1
fi

command -v rsync >/dev/null || { echo "ERROR: rsync not installed" >&2; exit 1; }

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUPS_ROOT}/${TS}"

RSYNC_COMMON=(
  --archive
  --human-readable
  --itemize-changes
  --delete-delay
  --no-inc-recursive
  --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r
)

# 1) Determine which files would change (dry-run probe)
echo "==> Scanning changes (src -> /) ..."
mapfile -t CHANGES < <(
  rsync "${RSYNC_COMMON[@]}" --dry-run "${SRC_DIR}/" / \
  | awk '/^\>|^\*deleting/ {print}'
)

if [[ ${#CHANGES[@]} -eq 0 ]]; then
  echo "==> No changes. Done."
  exit 0
fi

echo "==> Planned changes:"
printf '  %s\n' "${CHANGES[@]}"

# 2) Backup only files that will be overwritten (not new files, not deletions)
# rsync itemize format includes target path at the end; for file transfers it's usually last column.
# We focus on lines beginning with ">f" (file transfer)
mapfile -t OVERWRITE_PATHS < <(
  printf '%s\n' "${CHANGES[@]}" \
  | awk '
      $1 ~ /^>f/ {
        # rsync prints path as last field
        print $NF
      }' \
  | sed 's#^/#/#' \
  | sort -u
)

if [[ ${#OVERWRITE_PATHS[@]} -gt 0 ]]; then
  echo "==> Creating backups in: ${BACKUP_DIR}"
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "${BACKUP_DIR}"
    for p in "${OVERWRITE_PATHS[@]}"; do
      # Only back up if file exists on target
      if [[ -f "$p" ]]; then
        mkdir -p "${BACKUP_DIR}$(dirname "$p")"
        cp -a -- "$p" "${BACKUP_DIR}${p}"
      fi
    done
  else
    echo "==> (dry-run) Backups would be created in: ${BACKUP_DIR}"
  fi
else
  echo "==> No overwrites detected (only new files / deletions)."
fi

# 3) Apply rsync for real (or dry-run)
echo "==> Deploying ..."
if [[ $DRY_RUN -eq 1 ]]; then
  echo "==> (dry-run) rsync not executed."
else
  rsync "${RSYNC_COMMON[@]}" "${SRC_DIR}/" /
fi

# 4) Optional systemd daemon-reload (explicit)
if [[ $SYSTEMD_RELOAD -eq 1 ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "==> (dry-run) Would run: systemctl daemon-reload"
  else
    echo "==> Running: systemctl daemon-reload"
    systemctl daemon-reload
  fi
fi

echo "==> Done."
if [[ $DRY_RUN -eq 0 ]]; then
  echo "==> Backup folder (if any overwrites): ${BACKUP_DIR}"
fi
