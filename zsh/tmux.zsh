unalias tmux 2>/dev/null || true
unalias tl 2>/dev/null || true
unfunction tla 2>/dev/null || true

_tmux_server_rows() {
  command ps -u "$(command id -u)" -o pid=,comm=,args= 2>/dev/null |
    command awk '
      $2 == "tmux:" && $3 == "server" {
        args = $4
        for (field = 5; field <= NF; field++) {
          args = args " " $field
        }
        print $1 "\t" args
      }
    '
}

_tmux_server_scope() {
  local server_args="$1"
  local -a server_words
  local index word

  server_words=(${(z)server_args})
  for (( index = 1; index <= ${#server_words}; index++ )); do
    word="${server_words[index]}"
    case "${word}" in
      -L)
        print -r -- "name:${server_words[index + 1]:-unknown}"
        return
        ;;
      -L?*)
        print -r -- "name:${word#-L}"
        return
        ;;
      -S)
        print -r -- "path:${server_words[index + 1]:-unknown}"
        return
        ;;
      -S?*)
        print -r -- "path:${word#-S}"
        return
        ;;
    esac
  done

  print -r -- default
}

_tmux_has_unreachable_default_server() {
  local process_row server_args

  for process_row in "${(@f)$(_tmux_server_rows)}"; do
    [[ -n "${process_row}" ]] || continue
    server_args="${process_row#*$'\t'}"
    [[ "$(_tmux_server_scope "${server_args}")" == default ]] && return 0
  done

  return 1
}

tm() {
  if [[ -z "${TMUX:-}" ]] &&
     ! command tmux list-sessions >/dev/null 2>&1 &&
     _tmux_has_unreachable_default_server; then
    print -u2 -r -- "tm: default socket is unavailable, but a default tmux server process is still running."
    print -u2 -r -- "tm: refusing to create a replacement server; run 'tl -a' to inspect it."
    return 1
  fi

  command tmux new -As "${1:-main}"
}

tl() {
  case "${1:-}" in
    -a|--all)
      shift
      _tmux_list_all "$@"
      ;;
    *)
      command tmux list-sessions "$@"
      ;;
  esac
}

alias ta='command tmux attach -t'
alias tad='command tmux attach -d -t'
alias ts='command tmux new-session -s'
alias tkss='command tmux kill-session -t'

_tmux_list_all_usage() {
  print -r -- "usage: tl -a [--processes|-p]"
}

_tmux_list_all() {
  local include_processes=0
  local socket_dir="${TMUX_TMPDIR:-/tmp}/tmux-$(command id -u)"
  local socket_path session_rows session_row server_pid
  local process_rows process_row server_args server_scope server_state
  local -a server_pids
  typeset -A reachable_pids

  case "${1:-}" in
    '') ;;
    --processes|-p) include_processes=1 ;;
    --help|-h)
      _tmux_list_all_usage
      return 0
      ;;
    *)
      _tmux_list_all_usage >&2
      return 2
      ;;
  esac

  if (( $# > 1 )); then
    _tmux_list_all_usage >&2
    return 2
  fi

  print -r -- $'SOCKET\tSTATUS\tPID\tSESSION\tATTACHED\tWINDOWS'
  for socket_path in "${socket_dir}"/*(N); do
    [[ -S "${socket_path}" ]] || continue

    if session_rows="$(command tmux -S "${socket_path}" list-sessions \
      -F $'#{pid}\t#{session_name}\t#{session_attached}\t#{session_windows}' 2>/dev/null)"; then
      if [[ -n "${session_rows}" ]]; then
        for session_row in "${(@f)session_rows}"; do
          server_pid="${session_row%%$'\t'*}"
          reachable_pids[${server_pid}]=1
          print -r -- "${socket_path}"$'\t'reachable$'\t'"${session_row}"
        done
      else
        print -r -- "${socket_path}"$'\t'reachable-empty$'\t-\t-\t-\t-'
      fi
    else
      print -r -- "${socket_path}"$'\t'unreachable$'\t-\t-\t-\t-'
    fi
  done

  process_rows="$(_tmux_server_rows)"
  print
  print -r -- $'PID\tSCOPE\tSTATE'
  for process_row in "${(@f)process_rows}"; do
    [[ -n "${process_row}" ]] || continue
    server_pid="${process_row%%$'\t'*}"
    server_args="${process_row#*$'\t'}"
    server_scope="$(_tmux_server_scope "${server_args}")"
    server_state=unlinked-or-empty
    [[ -n "${reachable_pids[${server_pid}]-}" ]] && server_state=reachable
    server_pids+=("${server_pid}")
    print -r -- "${server_pid}"$'\t'"${server_scope}"$'\t'"${server_state}"
  done

  if (( include_processes )); then
    print
    print -r -- "PROCESS TREES"
    if (( ! ${+commands[pstree]} )); then
      print -u2 -r -- "tl: pstree is not available"
      return 1
    fi
    for server_pid in "${server_pids[@]}"; do
      command pstree -p "${server_pid}"
    done
  fi
}
