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
# <command> is the ps argument line under the caller's locale, cut to 200
# bytes, so it may end inside a multibyte character. It never establishes
# ownership. A row can contain invalid UTF-8. Run this script under the
# caller's locale, check its exit status, and only then apply LC_ALL=C to the
# tool that reads its saved output, as in:
#   list="$(mktemp)" && list-processes.sh <path> >"$list" && LC_ALL=C cut -f1 "$list"
# <cwd> is escaped so every process stays on one line: newline as \n, tab as
# \t, backslash as \\, and other control bytes as \xNN; other bytes are as-is.
# Without /proc, lsof prints a control byte and a literal "^A" to "^_" alike.
# Such a cwd is ambiguous: <cwd> shows each as a control byte, so it always has
# a backslash. PATH mode lists it as "cwd ambiguous" when any name that lsof
# could have printed this way is PATH or below it; otherwise a --cwd argument
# under PATH may still list it as "--cwd under target". --stale lists every
# ambiguous cwd as "cwd ambiguous" instead of calling it missing. A
# "cwd ambiguous" row never establishes ownership.
# A --cwd argument is read exactly from /proc. Without /proc, ps joins the
# arguments with spaces, so the value after the first --cwd may end at any
# later space: each such reading is a candidate. ps prints a control byte as
# "^X", "\ooo", or "?" but a literal "^", "\", or "?" as is, so a candidate is
# read only up to its first "\", "^", "?", or "M-". Under LC_ALL=C, ps prints
# a byte >= 0x80 as "M-x", "M^x", or "\240". When a UTF-8 locale exists, a
# second ps reading under it gives such bytes as they are, but only within
# valid UTF-8 that both readings agree on; the line ends where they first
# disagree, since that ps may print a character as text that names other
# bytes. Such bytes are read only when a third ps reading under LC_ALL=C
# equals the first, so argv changed once between the readings is never read
# as a mix of two values; argv a process rewrites more than once between
# them can still be, but such a process could put any --cwd in its argv. A
# line the readings differ on is cut at its first byte >= 0x80 past 4096
# bytes, and a --cwd value that starts past where the line is cut is
# unreadable. PATH mode lists
# "--cwd under target" when every candidate is PATH or below it, and
# "--cwd ambiguous" when only some may be; such a row never establishes
# ownership. --stale lists "--cwd missing" only when every candidate, read in
# full, is missing.
# The script and its ancestors are never listed. It only reads process state;
# it never sends signals. It checks whether a process still exists with
# "kill -0", which sends none.
#
# Exit status: 0 with no output when no process matches. When processes cannot
# be listed, because there is neither /proc nor lsof or lsof does not report
# this script's own process, it prints nothing on stdout, a message on stderr,
# and exits 1: the listing is unavailable, never empty. lsof output cut short
# after this script's own process goes undetected. A ps lookup that decides or
# fills a row (its --cwd argument, ppid, tty, lstart, or args) may fail, or
# give no ppid, because the process exited meanwhile: such a process is
# skipped with nothing on stderr. When it fails for a process that still
# exists, or "kill -0" cannot tell whether the process exited, the listing is
# unavailable in the same way.
set -euo pipefail

usage() {
  sed -n '2,63p' "$0" | sed 's/^# \{0,1\}//'
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

# Ends a complete listing; a record always starts with a decimal pid.
listing_end="end"

# pid<TAB>cwd<NUL>raw<NUL> for every process of the current user, so a cwd
# may contain any byte but NUL. raw is set only for an ambiguous lsof name;
# see lsof_name. Only a complete listing ends with the listing_end record.
# lsof's exit status is not trusted, as it may exit 1 with usable rows: the
# listing is complete when it reports the cwd of this script's own process.
list_cwds() {
  local dir pid cwd field decoded raw seen
  if [[ -d /proc/self ]]; then
    for dir in /proc/[0-9]*; do
      [[ -O "${dir}" ]] || continue
      pid="${dir#/proc/}"
      # The sentinel keeps trailing newlines of the name through $(...).
      cwd="$(readlink "${dir}/cwd" 2>/dev/null && printf x)" || continue
      cwd="${cwd%$'\n'x}"
      printf '%s\t%s\0\0' "${pid}" "${cwd}"
    done
    printf '%s\0\0' "${listing_end}"
  elif command -v lsof >/dev/null 2>&1; then
    lsof -w -a -u "$(id -u)" -d cwd -F0pn 2>/dev/null | {
      seen=""
      while IFS= read -r -d '' field; do
        field="${field#$'\n'}"
        case "${field}" in
          p*) pid="${field#p}" ;;
          n*)
            lsof_name "${field#n}"
            printf '%s\t%s\0%s\0' "${pid}" "${decoded}" "${raw}"
            [[ "${pid}" != "$$" || -z "${field#n}" ]] || seen=1
            ;;
        esac
      done
      if [[ -n "${seen}" ]]; then
        printf '%s\0\0' "${listing_end}"
      else
        echo "lsof did not report the cwd of this process; processes cannot be listed" >&2
      fi
    }
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

# The UTF-8 locale of the second ps reading in cwd_argument: "" until probed,
# "C" when there is none.
ps_utf8=""

# Sets ps_utf8 to the first of C.UTF-8 and en_US.UTF-8 whose charmap is UTF-8.
probe_utf8_locale() {
  local loc
  ps_utf8="C"
  for loc in C.UTF-8 en_US.UTF-8; do
    if [[ "$(LC_ALL="${loc}" locale charmap 2>/dev/null)" == "UTF-8" ]]; then
      ps_utf8="${loc}"
      return 0
    fi
  done
}

# Sets ps_line to the ps line $1, read under a UTF-8 locale, up to where it
# agrees with $2, read under LC_ALL=C, followed by "?" when they disagree
# before either ends, ps_line_cut when it adds that "?", and ps_line_raw
# when it keeps a byte >= 0x80. An ASCII byte agrees when $2 has the same
# byte. A byte >= 0x80 agrees only within a valid UTF-8 sequence of $1 whose
# bytes $2 prints as "M-x", "M^x", "M^?", or "\240" each. The "?" makes readable_prefix cut the line there. A byte >=
# 0x80 after the first ps_line_max bytes of a differing $1 is not read.
ps_line_max=4096
confirmed_reading() {
  local LC_ALL=C u="$1" c="$2" out="" head n k code lo hi enc ch rest_u rest_c
  ps_line_raw=""
  ps_line_cut=""
  if [[ "${u}" == "${c}" ]]; then
    ps_line="${u}"
    if [[ "${u}" == *[$'\x80'-$'\xff']* ]]; then ps_line_raw=1; fi
    return 0
  fi
  # Each step copies what is left of u and c, so the steps that may read a
  # byte >= 0x80 run on a window: the first ps_line_max + 3 bytes of $1 hold
  # every byte they may read, and $2 prints each byte in at most 4 bytes. The
  # rest joins only once the window is used up, when just an ASCII run can
  # still agree.
  rest_u="${u:ps_line_max + 3}"
  rest_c="${c:4 * (ps_line_max + 3)}"
  u="${u:0:ps_line_max + 3}"
  c="${c:0:4 * (ps_line_max + 3)}"
  while :; do
    if [[ -z "${u}" ]]; then
      [[ -n "${rest_u}" ]] || break
      u="${rest_u}"
      c+="${rest_c}"
      rest_u=""
      rest_c=""
    fi
    # Compare the ASCII run up to the next byte >= 0x80 at once, keeping the
    # longest common prefix, found by bisection, when it differs.
    head="${u%%[$'\x80'-$'\xff']*}"
    if [[ -n "${head}" ]]; then
      if [[ "${c:0:${#head}}" != "${head}" ]]; then
        lo=0
        hi=${#head}
        while ((lo < hi)); do
          k=$(((lo + hi + 1) / 2))
          if [[ "${c:0:k}" == "${head:0:k}" ]]; then lo=${k}; else hi=$((k - 1)); fi
        done
        out+="${head:0:lo}"
        u="${u:lo}"
        break
      fi
      out+="${head}"
      u="${u:${#head}}"
      c="${c:${#head}}"
      continue
    fi
    ((${#out} < ps_line_max)) || break
    printf -v code '%d' "'${u:0:1}"
    # Bash 3.2 may print a byte >= 0x80 as negative; codes are 0 to 255.
    code=$((code & 255))
    # n is the length of the UTF-8 sequence, and lo to hi the range of its
    # second byte, which excludes overlong forms and surrogates.
    n=0 lo=128 hi=191
    if ((code >= 0xc2 && code <= 0xdf)); then
      n=2
    elif ((code >= 0xe0 && code <= 0xef)); then
      n=3
      if ((code == 0xe0)); then lo=160; fi
      if ((code == 0xed)); then hi=159; fi
    elif ((code >= 0xf0 && code <= 0xf4)); then
      n=4
      if ((code == 0xf0)); then lo=144; fi
      if ((code == 0xf4)); then hi=143; fi
    fi
    ((n > 0 && n <= ${#u})) || break
    enc=""
    for ((k = 0; k < n; k++)); do
      printf -v code '%d' "'${u:k:1}"
      code=$((code & 255))
      if ((k == 1 && (code < lo || code > hi) || k > 1 && (code < 128 || code > 191))); then
        enc=""
        break
      fi
      if ((code == 255)); then
        enc+="M^?"
      elif ((code == 160)); then
        enc+='\240'
      elif ((code < 160)); then
        printf -v ch '\\x%02x' $((code - 64))
        printf -v ch '%b' "${ch}"
        enc+="M^${ch}"
      else
        printf -v ch '\\x%02x' $((code - 128))
        printf -v ch '%b' "${ch}"
        enc+="M-${ch}"
      fi
    done
    [[ -n "${enc}" && "${c:0:${#enc}}" == "${enc}" ]] || break
    out+="${u:0:n}"
    ps_line_raw=1
    u="${u:n}"
    c="${c:${#enc}}"
  done
  if [[ -n "${u}${c}${rest_u}${rest_c}" ]]; then
    ps_line="${out}?"
    ps_line_cut=1
  else
    ps_line="${out}"
  fi
}

# Sets ps_line to the ps line $1 up to its first byte >= 0x80, followed by "?".
ascii_prefix() {
  local LC_ALL=C line
  # Byte matching: LC_ALL=C applies only after the local above.
  line="${1%%[$'\x80'-$'\xff']*}"
  ps_line="${line}?"
  ps_line_cut=1
}

# Sets value to the text after the first " --cwd=" or " --cwd " in the ps
# line $1, or to "" when there is none.
ps_cwd_value() {
  local text="$1"
  value=""
  while [[ "${text}" == *" --cwd"* ]]; do
    text="${text#*" --cwd"}"
    case "${text}" in
      =*)
        value="${text#=}"
        break
        ;;
      " "?*)
        value="${text# }"
        break
        ;;
    esac
  done
}

# Sets arg_cwds to the candidate values of the first --cwd argument, and
# arg_from_ps when they come from ps; see the header. arg_cwds is empty
# without a --cwd. A ps candidate may be empty, as for "--cwd= --watch" or an
# empty argument before "--watch": that reading has no --cwd, so it is never
# under the target or missing. A cmdline that cannot be opened or read, as when the process
# exits meanwhile, counts as no --cwd and prints nothing on stderr. A ps
# reading that fails sets arg_failed instead, for the caller to check with
# skip_if_exited.
cwd_argument() {
  local pid="$1" prev="" arg text utf8_text recheck value="" prefix=""
  arg_cwds=()
  arg_from_ps=""
  arg_failed=""
  if [[ -r "/proc/${pid}/cmdline" ]]; then
    while IFS= read -r -d '' arg; do
      case "${arg}" in
        --cwd=*)
          [[ -n "${arg#--cwd=}" ]] && arg_cwds=("${arg#--cwd=}")
          return 0
          ;;
      esac
      if [[ "${prev}" == "--cwd" ]]; then
        [[ -n "${arg}" ]] && arg_cwds=("${arg}")
        return 0
      fi
      prev="${arg}"
    done 2>/dev/null <"/proc/${pid}/cmdline" || true
    return 0
  fi
  arg_from_ps=1
  # LC_ALL=C keeps ps from printing bytes as they are in a multibyte locale;
  # the UTF-8 reading supplies them only where confirmed_reading agrees.
  text=" $(LC_ALL=C ps -ww -o args= -p "${pid}" 2>/dev/null)" || {
    arg_failed=1
    return 0
  }
  [[ "${text}" == *" --cwd"* ]] || return 0
  [[ -n "${ps_utf8}" ]] || probe_utf8_locale
  if [[ "${ps_utf8}" != "C" ]]; then
    utf8_text=" $(LC_ALL="${ps_utf8}" ps -ww -o args= -p "${pid}" 2>/dev/null)" || {
      arg_failed=1
      return 0
    }
    confirmed_reading "${utf8_text}" "${text}"
    # argv may change between the readings; see the header.
    if [[ -n "${ps_line_raw}" ]]; then
      recheck=" $(LC_ALL=C ps -ww -o args= -p "${pid}" 2>/dev/null)" || {
        arg_failed=1
        return 0
      }
      [[ "${recheck}" == "${text}" ]] || ascii_prefix "${ps_line}"
    fi
    ps_cwd_value "${ps_line}"
  fi
  # A --cwd past where the UTF-8 reading is cut is unreadable; see the header.
  [[ "${ps_utf8}" == "C" || -n "${value}" || -z "${ps_line_cut}" ]] || value="?"
  [[ "${ps_utf8}" != "C" ]] || ps_cwd_value "${text}"
  [[ -n "${value}" ]] || return 0
  while [[ "${value}" == *" "* ]]; do
    prefix+="${value%%" "*}"
    arg_cwds+=("${prefix}")
    prefix+=" "
    value="${value#*" "}"
  done
  arg_cwds+=("${prefix}${value}")
}

# Prints the part of a ps candidate before its first "\", "^", "?", or "M-", or
# the whole candidate when it has none.
readable_prefix() {
  local LC_ALL=C cut
  # Byte matching: LC_ALL=C applies only after the local above.
  cut="${1%%[\\^?]*}"
  [[ "${cut}" == *M-* ]] && cut="${cut%%M-*}"
  printf '%s' "${cut}"
}

# Sets arg_under to "all", "some", or "" for the --cwd candidates in PATH mode.
# A candidate cut short by readable_prefix is under the target when its
# readable part already is; it may be when the target extends that part.
classify_arg_under() {
  local LC_ALL=C i cand cut under=0 maybe=0
  arg_under=""
  for ((i = 0; i < ${#arg_cwds[@]}; i++)); do
    cand="${arg_cwds[i]}"
    cut="${cand}"
    [[ -n "${arg_from_ps}" ]] && cut="$(readable_prefix "${cand}")"
    if [[ "${cut}" == "${cand}" ]]; then
      if under_target "${cand}"; then
        under=$((under + 1))
      fi
    elif [[ "${cut}" == "${target}/"* ]]; then
      under=$((under + 1))
    elif [[ "${#cut}" -lt "${#target}" && "${target}" == "${cut}"* ]]; then
      maybe=$((maybe + 1))
    fi
  done
  if ((${#arg_cwds[@]} > 0 && under == ${#arg_cwds[@]})); then
    arg_under="all"
  elif ((under + maybe > 0)); then
    arg_under="some"
  fi
}

# True when every --cwd candidate is missing; an empty candidate, or one cut
# short by readable_prefix, is never known to be missing.
all_args_missing() {
  local i cand
  ((${#arg_cwds[@]} > 0)) || return 1
  for ((i = 0; i < ${#arg_cwds[@]}; i++)); do
    cand="${arg_cwds[i]}"
    [[ -n "${cand}" ]] || return 1
    if [[ -n "${arg_from_ps}" && "$(readable_prefix "${cand}")" != "${cand}" ]]; then
      return 1
    fi
    is_missing "${cand}" || return 1
  done
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
          tok_codes+=($(((code & 255) - 64)))
          ;;
      esac
      ;;
    *)
      printf -v code '%d' "'${c}"
      tok_lens=(1)
      # Bash 3.2 may print a byte >= 0x80 as negative; codes are 0 to 255.
      tok_codes=($((code & 255)))
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
    # Bash 3.2 may print a byte >= 0x80 as negative; codes are 0 to 255.
    code=$((code & 255))
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

# Returns when process $1 no longer exists, after its ps lookup $2 failed;
# otherwise the listing is unavailable. kill -0 sends no signal. It fails alike
# for a process that is gone and one it may not signal, as under a sandbox, so
# only its "No such process" message, read under LC_ALL=C, means gone.
skip_if_exited() {
  local LC_ALL=C pid="$1" lookup="$2" err
  if err="$(kill -0 "${pid}" 2>&1)"; then
    echo "ps could not read the ${lookup} of live process ${pid}; processes cannot be listed" >&2
    exit 1
  fi
  [[ "${err}" == *"No such process"* ]] && return 0
  echo "Cannot tell whether process ${pid} exited after its ${lookup} lookup failed; processes cannot be listed" >&2
  exit 1
}

# The caller's shell usually runs inside the target; never list it.
ancestors=" "
pid=$$
while [[ -n "${pid}" && "${pid}" != "0" ]]; do
  ancestors+="${pid} "
  [[ "${pid}" == "1" ]] && break
  pid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')" || break
done

# Read the whole listing before printing any row, so a listing that fails
# part way prints nothing.
records=()
raws=()
complete=""
while IFS= read -r -d '' record; do
  IFS= read -r -d '' raw || break
  if [[ "${record}" == "${listing_end}" ]]; then
    complete=1
    break
  fi
  records+=("${record}")
  raws+=("${raw}")
done < <(list_cwds)
if [[ -z "${complete}" ]]; then
  echo "The process listing is incomplete; nothing is listed" >&2
  exit 1
fi

# Rows are printed only once every one is read, so a listing that turns out
# unavailable part way prints nothing on stdout.
rows=()
for ((i = 0; i < ${#records[@]}; i++)); do
  record="${records[i]}"
  raw="${raws[i]}"
  pid="${record%%$'\t'*}"
  cwd="${record#*$'\t'}"
  [[ -z "${pid}" || "${ancestors}" == *" ${pid} "* ]] && continue
  # A ps lookup fails for a process that exits mid-listing. skip_if_exited
  # skips it rather than ending the list, and ends the list when it still
  # exists; see the header. The --cwd argument is read only when it decides
  # the row, so a failure that could not change the listing never ends it.
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
      if [[ -z "${reason}" ]]; then
        cwd_argument "${pid}"
        if [[ -n "${arg_failed}" ]]; then
          skip_if_exited "${pid}" "--cwd argument"
          continue
        fi
        classify_arg_under
        case "${arg_under}" in
          all) reason="--cwd under target" ;;
          some) reason="--cwd ambiguous" ;;
        esac
      fi
      ;;
    stale)
      if [[ -n "${raw}" ]]; then
        reason="cwd ambiguous"
      elif is_missing "${cwd}"; then
        reason="cwd missing"
      else
        cwd_argument "${pid}"
        if [[ -n "${arg_failed}" ]]; then
          skip_if_exited "${pid}" "--cwd argument"
          continue
        fi
        if all_args_missing; then
          reason="--cwd missing"
        fi
      fi
      ;;
  esac
  [[ -z "${reason}" ]] && continue

  # ps gives no ppid only for a process that is gone, so an empty one counts
  # as a failed lookup.
  if ! ppid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ')" || [[ -z "${ppid}" ]]; then
    skip_if_exited "${pid}" ppid
    continue
  fi
  if ! tty="$(ps -o tty= -p "${pid}" 2>/dev/null | tr -d ' ')"; then
    skip_if_exited "${pid}" tty
    continue
  fi
  [[ -z "${tty}" || "${tty}" == "??" ]] && tty="?"
  if ! started="$(ps -o lstart= -p "${pid}" 2>/dev/null | sed 's/^ *//')"; then
    skip_if_exited "${pid}" lstart
    continue
  fi
  # ps keeps the caller's locale so it prints text as is; cut in a multibyte
  # locale rejects an invalid byte, so it runs under LC_ALL=C. A row never
  # depends on cut, and cut stays off stderr, since check-cleanup-targets.mjs
  # calls a listing with any stderr unavailable.
  if ! args="$(ps -ww -o args= -p "${pid}" 2>/dev/null)"; then
    skip_if_exited "${pid}" args
    continue
  fi
  command="$({ printf '%s\n' "${args}" | LC_ALL=C cut -b1-200; } 2>/dev/null)" || command=""
  printf -v row '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${pid}" "${ppid}" "${tty}" "${started}" "$(encode_cwd "${cwd}")" "${reason}" "${command}"
  rows+=("${row}")
done
((${#rows[@]} == 0)) || printf '%s\n' "${rows[@]}"
