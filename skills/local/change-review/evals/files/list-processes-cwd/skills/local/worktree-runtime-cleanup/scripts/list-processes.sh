#!/usr/bin/env bash
# List the current user's processes tied to a worktree, or left behind by removed directories.
#
# Usage:
#   list-processes.sh [PATH]   Processes whose cwd, or whose --cwd argument, is
#                              PATH or below it. PATH defaults to the current
#                              git worktree root.
#   list-processes.sh --stale  Processes whose cwd, or whose --cwd argument,
#                              points to a directory that no longer exists.
#
# Output: one tab-separated line per process:
#   <pid> <ppid> <tty> <started> <cwd> <reason> <command>
# <tty> is "?" for processes without a controlling terminal, such as detached
# brokers and daemons. <started> lets callers detect PID reuse before stopping.
# The script and its ancestors are never listed. It only reads process state;
# it never sends signals.
set -euo pipefail

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

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

# pid<TAB>cwd for every process of the current user.
list_cwds() {
  local dir pid cwd
  if [[ -d /proc/self ]]; then
    for dir in /proc/[0-9]*; do
      [[ -O "${dir}" ]] || continue
      pid="${dir#/proc/}"
      cwd="$(readlink "${dir}/cwd" 2>/dev/null)" || continue
      printf '%s\t%s\n' "${pid}" "${cwd}"
    done
  elif command -v lsof >/dev/null 2>&1; then
    lsof -a -u "$(id -u)" -d cwd -Fpn 2>/dev/null |
      awk '/^p/ { pid = substr($0, 2) } /^n/ { printf "%s\t%s\n", pid, substr($0, 2) }'
  else
    echo "Neither /proc nor lsof is available" >&2
    exit 1
  fi
}

# Prints the value of a --cwd argument, if any.
cwd_argument() {
  local pid="$1" prev="" arg
  if [[ -r "/proc/${pid}/cmdline" ]]; then
    while IFS= read -r -d '' arg; do
      case "${arg}" in
        --cwd=*)
          printf '%s\n' "${arg#--cwd=}"
          return
          ;;
      esac
      if [[ "${prev}" == "--cwd" ]]; then
        printf '%s\n' "${arg}"
        return
      fi
      prev="${arg}"
    done <"/proc/${pid}/cmdline"
  else
    ps -ww -o args= -p "${pid}" 2>/dev/null |
      awk '{ for (i = 1; i <= NF; i++) {
        if ($i ~ /^--cwd=/) { sub(/^--cwd=/, "", $i); print $i; exit }
        if ($i == "--cwd" && i < NF) { print $(i + 1); exit }
      } }'
  fi
}

# Linux marks a removed cwd with a " (deleted)" suffix.
is_missing() {
  [[ "$1" == *" (deleted)" || ! -d "$1" ]]
}

under_target() {
  local dir="${1% (deleted)}"
  [[ "${dir}" == "${target}" || "${dir}" == "${target}/"* ]]
}

# The caller's shell usually runs inside the target; never list it.
ancestors=" "
pid=$$
while [[ -n "${pid}" && "${pid}" != "0" ]]; do
  ancestors+="${pid} "
  [[ "${pid}" == "1" ]] && break
  pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')"
done

while IFS=$'\t' read -r pid cwd; do
  [[ -z "${pid}" || "${ancestors}" == *" ${pid} "* ]] && continue
  arg_cwd="$(cwd_argument "${pid}")"
  reason=""
  case "${mode}" in
    path)
      if under_target "${cwd}"; then
        reason="cwd under target"
      elif [[ -n "${arg_cwd}" ]] && under_target "${arg_cwd}"; then
        reason="--cwd under target"
      fi
      ;;
    stale)
      if is_missing "${cwd}"; then
        reason="cwd missing"
      elif [[ -n "${arg_cwd}" ]] && is_missing "${arg_cwd}"; then
        reason="--cwd missing"
      fi
      ;;
  esac
  [[ -z "${reason}" ]] && continue

  ppid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')" || continue
  [[ -z "${ppid}" ]] && continue
  tty="$(ps -o tty= -p "${pid}" 2>/dev/null | tr -d ' ')"
  [[ -z "${tty}" || "${tty}" == "??" ]] && tty="?"
  started="$(ps -o lstart= -p "${pid}" 2>/dev/null | sed 's/^ *//')"
  command="$(ps -ww -o args= -p "${pid}" 2>/dev/null | cut -c1-200)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${pid}" "${ppid}" "${tty}" "${started}" "${cwd}" "${reason}" "${command}"
done < <(list_cwds)
