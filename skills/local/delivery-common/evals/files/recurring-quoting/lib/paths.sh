# Path helpers for sync-notes.

backup_dir() {
  local root=$1
  local name
  name=$(date +%Y%m%d-%H%M%S)
  mkdir -p $root/$name
  printf '%s\n' "$root/$name"
}
