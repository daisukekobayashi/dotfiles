# Keep only the newest backups under the backup root.

rotate_backups() {
  local root=$1 keep=$2
  local old
  for old in $(ls -1d "$root"/*/ | sort -r | tail -n +$((keep + 1))); do
    rm -rf $old
  done
}
