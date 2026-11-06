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
# a backslash. PATH mode lists it as "cwd ambiguous" when any name that lsof
# could have printed this way is PATH or below it; otherwise a --cwd argument
# under PATH may still list it as "--cwd under target". --stale lists every
# ambiguous cwd as "cwd ambiguous" instead of calling it missing. A
# "cwd ambiguous" row never establishes ownership.
# The script and its ancestors are never listed. It only reads process state;
# it never sends signals.
set -euo pipefail

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
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

# pid<TAB>cwd<NUL>raw<NUL> for every process of the current user, so a cwd
# may contain any byte but NUL. raw is set only for an ambiguous lsof name;
# see lsof_name.
list_cwds() {
  local dir pid cwd field decoded raw
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
            printf '%s\t%s\0%s\0' "${pid}" "${decoded}" "${raw}"
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
# byte, and "raw" keeps the whole name as lsof printed it for maybe_under_target;
# "raw" is empty when the name has no "^X". Each "^X" may be either, so no
# reading names the directory reliably. Any other sequence, such as "^@" or
# "\x41", stays as it is, so no character is dropped and NUL is never produced.
lsof_name() {
  local LC_ALL=C name="$1" c next hex byte ambiguous=""
  decoded=""
  raw=""
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
        decoded+="${byte}"
        name="${name:2}"
        ambiguous=1
        continue
        ;;
    esac
    if [[ -n "${byte}" ]]; then
      decoded+="${byte}"
      name="${name:2}"
    else
      decoded+="${c}"
      name="${name:1}"
    fi
  done
  [[ -z "${ambiguous}" ]] || raw="$1"
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

# Sets tok_lens and tok_codes to the tokens that can start at index $2 of the
# lsof name $1: the length of each and the byte it stands for. lsof escapes
# every backslash, so a "\" that starts no escape starts no token; a "^" may be
# a literal "^" or start caret notation.
lsof_tokens() {
  local LC_ALL=C name="$1" i="$2" c next hex code
  c="${name:i:1}"
  next="${name:i+1:1}"
  tok_lens=()
  tok_codes=()
  case "${c}" in
    '') ;;
    \\)
      case "${next}" in
        \\) tok_lens=(2) tok_codes=(92) ;;
        n) tok_lens=(2) tok_codes=(10) ;;
        t) tok_lens=(2) tok_codes=(9) ;;
        r) tok_lens=(2) tok_codes=(13) ;;
        b) tok_lens=(2) tok_codes=(8) ;;
        f) tok_lens=(2) tok_codes=(12) ;;
        x)
          hex="${name:i+2:2}"
          if [[ "${hex}" == [01][0-9a-fA-F] && "${hex}" != 00 ||
            "${hex}" == 7[fF] || "${hex}" == [89a-fA-F][0-9a-fA-F] ]]; then
            tok_lens=(4)
            tok_codes=($((16#${hex})))
          fi
          ;;
      esac
      ;;
    ^)
      tok_lens=(1)
      tok_codes=(94)
      case "${next}" in
        [A-Z\[\\\]^_])
          printf -v code '%d' "'${next}"
          tok_lens+=(2)
          tok_codes+=($((code - 64)))
          ;;
      esac
      ;;
    *)
      printf -v code '%d' "'${c}"
      tok_lens=(1)
      tok_codes=("${code}")
      ;;
  esac
}

# True when some name that lsof could have printed as the ambiguous name $1 is
# the target or below it. It follows every split of $1 into lsof tokens at once,
# keeping the set of indexes reachable after each byte of the target.
maybe_under_target() {
  local LC_ALL=C name="$1" n i j k p code
  local -a whole=() states=(0) next_states=()
  # Byte length: LC_ALL=C applies only after the local above.
  n="${#name}"
  # whole[i] is set when the name from index i on splits into tokens.
  whole[n]=1
  for ((i = n - 1; i >= 0; i--)); do
    lsof_tokens "${name}" "${i}"
    for k in "${!tok_lens[@]}"; do
      if [[ -n "${whole[i + tok_lens[k]]:-}" ]]; then
        whole[i]=1
        break
      fi
    done
  done
  for ((j = 0; j < ${#target}; j++)); do
    printf -v code '%d' "'${target:j:1}"
    next_states=()
    for p in "${states[@]}"; do
      lsof_tokens "${name}" "${p}"
      for k in "${!tok_lens[@]}"; do
        ((tok_codes[k] == code)) && next_states[p + tok_lens[k]]=1
      done
    done
    states=("${!next_states[@]}")
    ((${#states[@]} > 0)) || return 1
  done
  for p in "${states[@]}"; do
    [[ -n "${whole[p]:-}" ]] || continue
    [[ "${p}" -eq "${n}" || "${name:p:1}" == / ]] && return 0
  done
  return 1
}

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
  IFS= read -r -d '' raw || break
  [[ -z "${pid}" || "${ancestors}" == *" ${pid} "* ]] && continue
  # A process that exits mid-listing is skipped rather than ending the list:
  # each lookup below fails for it, and set -e would otherwise stop the script.
  arg_cwd="$(cwd_argument "${pid}")" || continue
  reason=""
  case "${mode}" in
    path)
      if [[ -n "${raw}" ]]; then
        if maybe_under_target "${raw}"; then
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
      if [[ -n "${raw}" ]]; then
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
