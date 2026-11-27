#!/usr/bin/env bash
# Copy a notes directory into a dated backup under the backup root.
set -euo pipefail

. "$(dirname "$0")/../lib/paths.sh"
. "$(dirname "$0")/../lib/rotate.sh"

SRC=$1
ROOT=$2
DEST=$(backup_dir "$ROOT")

cp -R "$SRC" "$DEST"
rotate_backups "$ROOT" 5
