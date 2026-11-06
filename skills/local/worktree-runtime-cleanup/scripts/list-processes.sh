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
# <cwd> is escaped so every process stays on one line: newline as \n, tab as
# \t, backslash as \\, and other control bytes as \xNN; other bytes are as-is.
# The script and its ancestors are never listed. It only reads process state;
# it never sends signals.
set -euo pipefail

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
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

# pid<TAB>cwd for every process of the current user, each record ending in NUL
# so a cwd may contain any byte but NUL.
list_cwds() {
  local dir pid cwd field
  if [[ -d /proc/self ]]; then
    for dir in /proc/[0-9]*; do
      [[ -O "${dir}" ]] || continue
      pid="${dir#/proc/}"
      # The sentinel keeps trailing newlines of the name through $(...).
      cwd="$(readlink "${dir}/cwd" 2>/dev/null && printf x)" || continue
      cwd="${cwd%$'\n'x}"
      printf '%s\t%s\0' "${pid}" "${cwd}"
    done
  elif command -v lsof >/dev/null 2>&1; then
    lsof -w -a -u "$(id -u)" -d cwd -F0pn 2>/dev/null |
      while IFS= read -r -d '' field; do
        field="${field#$'\n'}"
        case "${field}" in
          p*) pid="${field#p}" ;;
          n*)
            cwd="$(lsof_name "${field#n}" && printf x)"
            printf '%s\t%s\0' "${pid}" "${cwd%x}"
            ;;
        esac
      done
  else
    echo "Neither /proc nor lsof is available" >&2
    exit 1
  fi
}

# Decodes lsof's escaped name (\n, \t, \r, \b, \f, \\, \xNN, ^X) to raw bytes.
# lsof leaves a literal "^" unescaped, so "^X" is always read as a control byte.
lsof_name() {
  local LC_ALL=C name="$1" out="" c next
  if [[ "${name}" != *[\\^]* ]]; then
    printf '%s' "${name}"
    return
  fi
  while [[ -n "${name}" ]]; do
    c="${name:0:1}"
    next="${name:1:1}"
    if [[ "${c}" == "^" && "${next}" == [@A-Z\[\\\]^_] ]]; then
      out+="$(printf '\\x%02x' "$(( $(printf '%d' "'${next}") - 64 ))")"
      name="${name:2}"
    else
      out+="${c}"
      name="${name:1}"
    fi
  done
  printf '%b' "${out}"
}

# Escapes a cwd for the one-line output; see the header.
encode_cwd() {
  local LC_ALL=C cwd="$1" out="" c i
  if [[ "${cwd}" != *[[:cntrl:]\\]* ]]; then
    printf '%s' "${cwd}"
    return
  fi
  for ((i = 0; i < ${#cwd}; i++)); do
    c="${cwd:i:1}"
    case "${c}" in
      $'\n') out+='\n' ;;
      $'\t') out+='\t' ;;
      \\) out+='\\' ;;
      [[:cntrl:]]) out+="$(printf '\\x%02x' "'${c}")" ;;
      *) out+="${c}" ;;
    esac
  done
  printf '%s' "${out}"
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

while IFS= read -r -d '' record; do
  pid="${record%%$'\t'*}"
  cwd="${record#*$'\t'}"
  [[ -z "${pid}" || "${ancestors}" == *" ${pid} "* ]] && continue
  # A process that exits mid-listing is skipped rather than ending the list.
  arg_cwd="$(cwd_argument "${pid}")" || continue
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
    "${pid}" "${ppid}" "${tty}" "${started}" "$(encode_cwd "${cwd}")" "${reason}" "${command}"
done < <(list_cwds)
