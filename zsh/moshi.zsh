_tmux_moshi_usage() {
  print -r -- "Usage:"
  print -r -- "  tmux-moshi list"
  print -r -- "  tmux-moshi new [SESSION_NAME] [DIR]"
  print -r -- "  tmux-moshi attach SESSION_NAME"
  print -r -- "  tmux-moshi delete SESSION_NAME"
  print -r -- "  tmux-moshi help"
}

_tmux_moshi_require_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    print -u2 -- "tmux-moshi: tmux is not available"
    return 1
  fi
}

_tmux_moshi_next_session_name() {
  local index=1
  local session_name

  while true; do
    session_name="moshi-${index}"
    if ! command tmux has-session -t "${session_name}" 2>/dev/null; then
      print -r -- "${session_name}"
      return 0
    fi

    (( index++ ))
  done
}

_tmux_moshi_marked_session() {
  local session_name="$1"
  local marker

  marker="$(command tmux show-option -qv -t "${session_name}" @tmux-moshi-session 2>/dev/null)" || return 1
  [[ "${marker}" == "1" ]]
}

_tmux_moshi_apply_options() {
  local session_name="$1"
  local window_ids
  local window_id

  command tmux set-option -t "${session_name}" -q @tmux-moshi-session 1 || return
  command tmux set-option -t "${session_name}" -q prefix2 C-b || return
  command tmux set-environment -t "${session_name}" TMUX_MOSHI_SESSION 1 || return
  command tmux set-option -t "${session_name}" -q status-left "" || return
  command tmux set-option -t "${session_name}" -q status-right "" || return
  command tmux set-option -t "${session_name}" -q set-titles on || return
  command tmux set-option -t "${session_name}" -q set-titles-string "#I: #T" || return

  window_ids="$(command tmux list-windows -t "${session_name}" -F '#{window_id}')" || return
  for window_id in ${(f)window_ids}; do
    command tmux set-window-option -t "${window_id}" -q window-status-format "#I #W" || return
    command tmux set-window-option -t "${window_id}" -q window-status-current-format "#I #W" || return
  done

  command tmux set-option -t "${session_name}" -q mouse on
}

_tmux_moshi_open_session() {
  local session_name="$1"

  if [[ -n "${TMUX:-}" ]]; then
    command tmux switch-client -t "${session_name}"
  else
    command tmux attach-session -t "${session_name}"
  fi
}

_tmux_moshi_list() {
  local sessions
  local line
  local session_name
  local marker

  sessions="$(command tmux list-sessions -F $'#{session_name}\t#{@tmux-moshi-session}' 2>/dev/null)" || return 0

  for line in ${(f)sessions}; do
    session_name="${line%%$'\t'*}"
    marker="${line#*$'\t'}"

    if [[ "${marker}" == "1" ]]; then
      print -r -- "${session_name}"
    fi
  done
}

_tmux_moshi_new() {
  local session_name="${1:-}"
  local session_dir="${2:-$HOME}"

  if [[ -z "${session_name}" ]]; then
    session_name="$(_tmux_moshi_next_session_name)"
  elif command tmux has-session -t "${session_name}" 2>/dev/null; then
    print -u2 -- "tmux-moshi: session already exists: ${session_name}"
    return 1
  fi

  if [[ ! -d "${session_dir}" ]]; then
    print -u2 -- "tmux-moshi: directory not found: ${session_dir}"
    return 1
  fi

  command tmux new-session -d -s "${session_name}" -n shell -c "${session_dir}" || return
  command tmux new-window -t "${session_name}:" -n agent -c "${session_dir}" || return
  command tmux new-window -t "${session_name}:" -n test -c "${session_dir}" || return
  command tmux select-window -t "${session_name}:agent" || return
  _tmux_moshi_apply_options "${session_name}" || return
  _tmux_moshi_open_session "${session_name}"
}

_tmux_moshi_attach() {
  local session_name="$1"

  if [[ -z "${session_name}" ]]; then
    print -u2 -- "tmux-moshi: attach requires a session name"
    return 1
  fi

  _tmux_moshi_open_session "${session_name}"
}

_tmux_moshi_delete() {
  local session_name="$1"
  local reply

  if [[ -z "${session_name}" ]]; then
    print -u2 -- "tmux-moshi: delete requires a session name"
    return 1
  fi

  if ! _tmux_moshi_marked_session "${session_name}"; then
    print -u2 -- "tmux-moshi: not a tmux-moshi session: ${session_name}"
    return 1
  fi

  printf "Delete tmux-moshi session '%s'? [y/N] " "${session_name}"
  read -r reply

  case "${reply}" in
    y|Y|yes|YES)
      command tmux kill-session -t "${session_name}"
      ;;
    *)
      print -r -- "Aborted"
      return 1
      ;;
  esac
}

tmux-moshi() {
  local command_name="${1:-help}"

  case "${command_name}" in
    list)
      _tmux_moshi_require_tmux || return
      shift
      _tmux_moshi_list "$@"
      ;;
    new)
      _tmux_moshi_require_tmux || return
      shift
      _tmux_moshi_new "$@"
      ;;
    attach)
      _tmux_moshi_require_tmux || return
      shift
      _tmux_moshi_attach "$@"
      ;;
    delete)
      _tmux_moshi_require_tmux || return
      shift
      _tmux_moshi_delete "$@"
      ;;
    help|-h|--help)
      _tmux_moshi_usage
      ;;
    *)
      print -u2 -- "tmux-moshi: unknown command: ${command_name}"
      _tmux_moshi_usage >&2
      return 1
      ;;
  esac
}
