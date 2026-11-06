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
# Without /proc, lsof prints a control byte and a literal "^A" to "^_" alike.
# Such a cwd is ambiguous: <cwd> shows each as a control byte, so it always has
# a backslash, and <reason> is "cwd ambiguous". PATH mode lists it when any
# reading is PATH or below it, and --stale lists every ambiguous cwd instead of
# calling it missing. A "cwd ambiguous" row never establishes ownership.
# The script and its ancestors are never listed. It only reads process state;
# it never sends signals.
set -euo pipefail

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
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

# pid<TAB>cwd<NUL>literal<NUL> for every process of the current user, so a cwd
# may contain any byte but NUL. literal is set only for an ambiguous lsof name;
# see lsof_name.
list_cwds() {
  local dir pid cwd field decoded literal
  if [[ -d /proc/self ]]; then
    for dir in /proc/[0-9]*; do
      [[ -O "${dir}" ]] || continue
      pid="${dir#/proc/}"
      # The sentinel keeps trailing newlines of the name through $(...).
      cwd="$(readlink "${dir}/cwd" 2>/dev/null && printf x)" || continue
      cwd="${cwd%$'\n'x}"
      printf '%s\t%s\0\0' "${pid}" "${cwd}"
    done
  elif command -v lsof >/dev/null 2>&1; then
    lsof -w -a -u "$(id -u)" -d cwd -F0pn 2>/dev/null |
      while IFS= read -r -d '' field; do
        field="${field#$'\n'}"
        case "${field}" in
          p*) pid="${field#p}" ;;
          n*)
            lsof_name "${field#n}"
            printf '%s\t%s\0%s\0' "${pid}" "${decoded}" "${literal}"
            ;;
        esac
      done
  else
    echo "Neither /proc nor lsof is available" >&2
    exit 1
  fi
}

# Sets "decoded" to lsof's escaped name with its escapes of non-printable bytes
# (\n, \t, \r, \b, \f, \\, \xHH, ^A to ^_) turned back into those bytes. lsof
# leaves "^" unescaped, so "^X" is ambiguous: "decoded" reads it as a control
# byte, and "literal" keeps it as written; "literal" is empty when the name has
# no "^X". Each "^X" may be either, so no reading names the directory reliably.
# Any other sequence, such as "^@" or "\x41", stays as it is, so no character is
# dropped and NUL is never produced.
lsof_name() {
  local LC_ALL=C name="$1" c next hex byte ambiguous=""
  decoded=""
  literal=""
  if [[ "${name}" != *[\\^]* ]]; then
    decoded="${name}"
    return
  fi
  while [[ -n "${name}" ]]; do
    c="${name:0:1}"
    next="${name:1:1}"
    byte=""
    case "${c}${next}" in
      '\\') byte='\' ;;
      '\n') byte=$'\n' ;;
      '\t') byte=$'\t' ;;
      '\r') byte=$'\r' ;;
      '\b') byte=$'\b' ;;
      '\f') byte=$'\f' ;;
      '\x')
        hex="${name:2:2}"
        if [[ "${hex}" == [01][0-9a-fA-F] && "${hex}" != 00 ||
          "${hex}" == 7[fF] || "${hex}" == [89a-fA-F][0-9a-fA-F] ]]; then
          printf -v byte "\\x${hex}"
          name="${name:2}"
        fi
        ;;
      ^[A-Z\[\\\]^_])
        printf -v byte '\\x%02x' "$(($(printf '%d' "'${next}") - 64))"
        printf -v byte '%b' "${byte}"
        literal+="${c}${next}"
        decoded+="${byte}"
        name="${name:2}"
        ambiguous=1
        continue
        ;;
    esac
    if [[ -n "${byte}" ]]; then
      literal+="${byte}"
      decoded+="${byte}"
      name="${name:2}"
    else
      literal+="${c}"
      decoded+="${c}"
      name="${name:1}"
    fi
  done
  [[ -n "${ambiguous}" ]] || literal=""
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

# Prints PATH as lsof's literal reading would show it: control bytes that lsof
# prints as "^X" become those two characters.
caret_form() {
  local LC_ALL=C path="$1" out="" c i ch
  for ((i = 0; i < ${#path}; i++)); do
    c="${path:i:1}"
    case "${c}" in
      $'\n' | $'\t' | $'\r' | $'\b' | $'\f' | $'\x7f') out+="${c}" ;;
      [[:cntrl:]])
        printf -v ch '\\x%02x' "$(($(printf '%d' "'${c}") + 64))"
        printf -v ch '%b' "${ch}"
        out+="^${ch}"
        ;;
      *) out+="${c}" ;;
    esac
  done
  printf '%s' "${out}"
}

# True when some reading of an ambiguous name is the target or below it. Every
# reading has the same caret form, so comparing caret forms covers them all.
maybe_under_target() {
  [[ "$1" == "${caret_target}" || "$1" == "${caret_target}/"* ]]
}

caret_target=""
if [[ "${mode}" == "path" ]]; then
  caret_target="$(caret_form "${target}" && printf x)"
  caret_target="${caret_target%x}"
fi

# The caller's shell usually runs inside the target; never list it.
ancestors=" "
pid=$$
while [[ -n "${pid}" && "${pid}" != "0" ]]; do
  ancestors+="${pid} "
  [[ "${pid}" == "1" ]] && break
  pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')" || break
done

while IFS= read -r -d '' record; do
  pid="${record%%$'\t'*}"
  cwd="${record#*$'\t'}"
  IFS= read -r -d '' literal || break
  [[ -z "${pid}" || "${ancestors}" == *" ${pid} "* ]] && continue
  # A process that exits mid-listing is skipped rather than ending the list:
  # each lookup below fails for it, and set -e would otherwise stop the script.
  arg_cwd="$(cwd_argument "${pid}")" || continue
  reason=""
  case "${mode}" in
    path)
      if [[ -n "${literal}" ]]; then
        if maybe_under_target "${literal}"; then
          reason="cwd ambiguous"
        fi
      elif under_target "${cwd}"; then
        reason="cwd under target"
      fi
      if [[ -z "${reason}" && -n "${arg_cwd}" ]] && under_target "${arg_cwd}"; then
        reason="--cwd under target"
      fi
      ;;
    stale)
      if [[ -n "${literal}" ]]; then
        reason="cwd ambiguous"
      elif is_missing "${cwd}"; then
        reason="cwd missing"
      elif [[ -n "${arg_cwd}" ]] && is_missing "${arg_cwd}"; then
        reason="--cwd missing"
      fi
      ;;
  esac
  [[ -z "${reason}" ]] && continue

  ppid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')" || continue
  [[ -z "${ppid}" ]] && continue
  tty="$(ps -o tty= -p "${pid}" 2>/dev/null | tr -d ' ')" || continue
  [[ -z "${tty}" || "${tty}" == "??" ]] && tty="?"
  started="$(ps -o lstart= -p "${pid}" 2>/dev/null | sed 's/^ *//')" || continue
  command="$(ps -ww -o args= -p "${pid}" 2>/dev/null | cut -c1-200)" || continue
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${pid}" "${ppid}" "${tty}" "${started}" "$(encode_cwd "${cwd}")" "${reason}" "${command}"
done < <(list_cwds)
