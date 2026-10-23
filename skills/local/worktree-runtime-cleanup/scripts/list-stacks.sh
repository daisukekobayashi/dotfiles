#!/usr/bin/env bash
# List Docker Compose projects tied to a worktree, or left behind by removed worktrees.
#
# Usage:
#   list-stacks.sh [PATH]   Projects whose working_dir is PATH or below it.
#                           PATH defaults to the current git worktree root.
#   list-stacks.sh --stale  Projects whose working_dir no longer exists or is
#                           not a registered git worktree, plus projects left
#                           with only volumes (working_dir shown as "-").
#
# Output: one tab-separated line per project:
#   <project> <running>/<total> <working_dir> <reason>
# In PATH mode the reason is "under target", plus "; explicit project name"
# when the project name is not derived from working_dir and may be shared.
# The script only reads Docker state; it never stops containers.
set -euo pipefail

usage() {
  sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found" >&2
  exit 1
fi

mode="path"
target=""

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --stale)
    mode="stale"
    ;;
  "")
    target="$(git rev-parse --show-toplevel 2>/dev/null)" || {
      echo "Not inside a git worktree; pass a PATH or --stale" >&2
      exit 1
    }
    ;;
  *)
    target="$(cd "$1" 2>/dev/null && pwd -P)" || target="${1%/}"
    ;;
esac

# project<TAB>working_dir<TAB>state, one line per container.
containers="$(
  docker ps -a \
    --filter label=com.docker.compose.project \
    --format '{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.project.working_dir"}}	{{.State}}'
)"

# Collapse to project<TAB>working_dir<TAB>running<TAB>total.
projects=""
if [[ -n "${containers}" ]]; then
  projects="$(
    printf '%s\n' "${containers}" |
      awk -F'\t' '{
        key = $1 FS $2
        total[key]++
        if ($3 == "running") running[key]++
      }
      END {
        for (k in total) printf "%s\t%d\t%d\n", k, running[k] + 0, total[k]
      }' |
      sort
  )"
fi

# Prints a reason when working_dir is stale; prints nothing when it is a live worktree.
stale_reason() {
  local dir="$1" top

  if [[ -z "${dir}" ]]; then
    echo "no working_dir label"
    return
  fi
  if [[ ! -d "${dir}" ]]; then
    echo "working_dir missing"
    return
  fi
  top="$(git -C "${dir}" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "not inside a git worktree"
    return
  }
  if ! git -C "${top}" worktree list --porcelain 2>/dev/null |
    grep -Fxq "worktree ${top}"; then
    echo "worktree not registered"
    return
  fi
  # A leftover worktree directory under an ignored path (such as .worktrees/)
  # resolves to the parent checkout once its .git file is gone.
  if [[ "${dir}" != "${top}" ]] && git -C "${top}" check-ignore -q "${dir}" 2>/dev/null; then
    echo "inside an ignored path of ${top}"
  fi
}

# Compose's default project name for a directory: lowercased basename with
# characters outside [a-z0-9_-] dropped and leading separators trimmed.
default_project_name() {
  local name
  name="$(basename "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  printf '%s\n' "${name#"${name%%[a-z0-9]*}"}"
}

while IFS=$'\t' read -r project dir running total; do
  [[ -z "${project}" ]] && continue
  case "${mode}" in
    path)
      if [[ "${dir}" == "${target}" || "${dir}" == "${target}/"* ]]; then
        reason="under target"
        if [[ "${project}" != "$(default_project_name "${dir}")" ]]; then
          reason="${reason}; explicit project name"
        fi
        printf '%s\t%s/%s\t%s\t%s\n' "${project}" "${running}" "${total}" "${dir}" "${reason}"
      fi
      ;;
    stale)
      reason="$(stale_reason "${dir}")"
      if [[ -n "${reason}" ]]; then
        printf '%s\t%s/%s\t%s\t%s\n' "${project}" "${running}" "${total}" "${dir}" "${reason}"
      fi
      ;;
  esac
done <<<"${projects}"

# Compose volumes carry no working_dir label, so a project left with only
# volumes cannot be matched to a path; --stale lists it for the user to judge.
if [[ "${mode}" == "stale" ]]; then
  container_projects="$(cut -f1 <<<"${projects}")"
  docker volume ls \
    --filter label=com.docker.compose.project \
    --format '{{.Label "com.docker.compose.project"}}' |
    sort | uniq -c |
    while read -r count project; do
      if ! grep -Fxq "${project}" <<<"${container_projects}"; then
        printf '%s\t0/0\t-\t%s\n' "${project}" "volume-only: ${count} volume(s), working_dir unknown"
      fi
    done
fi
