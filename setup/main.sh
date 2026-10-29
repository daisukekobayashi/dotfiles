#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${DOTFILES_ROOT}/lib/common.sh"
# shellcheck source=setup/versions.sh
source "${SCRIPT_DIR}/versions.sh"
# shellcheck source=setup/links.sh
source "${SCRIPT_DIR}/links.sh"
# shellcheck source=setup/skills.sh
source "${SCRIPT_DIR}/skills.sh"
# shellcheck source=setup/codex.sh
source "${SCRIPT_DIR}/codex.sh"
# shellcheck source=setup/claude.sh
source "${SCRIPT_DIR}/claude.sh"
# shellcheck source=setup/bootstrap.sh
source "${SCRIPT_DIR}/bootstrap.sh"
# shellcheck source=setup/tools.sh
source "${SCRIPT_DIR}/tools.sh"
# shellcheck source=setup/plugins.sh
source "${SCRIPT_DIR}/plugins.sh"
# shellcheck source=setup/steps.sh
source "${SCRIPT_DIR}/steps.sh"

usage() {
  cat <<'EOF'
Usage: ./setup.sh <subcommand> [args]

Subcommands:
  all         Run every phase in order: links -> bootstrap -> tools -> plugins
  links       Link and generate local config files
  bootstrap   Install OS packages and tool managers (apt, homebrew, sheldon, mise)
  tools       Install tools with those managers (mise-tools, uv-tools, claude,
              codex, tmux, luarocks)
  plugins     Install plugins on top of the tools (tpm)
  skills      Restore skills and wire agent skill directories
  codex       Generate a separate Codex environment
  claude      Create or refresh a separate Claude Code environment
  help        Show this help

all/links/bootstrap/tools/plugins args:
  --only <csv>   Run only selected steps (e.g. claude,codex)
  --skip <csv>   Skip selected steps (e.g. mise-tools,tpm)
  --dry-run      Print commands without executing side effects
  --reload-shell Exec a fresh login zsh after setup completes

codex args:
  --env <name>               Select an independent Codex home
  --provider azure|openai|chatgpt
                             Required for a new arbitrary environment name
  --base-url <url>           API base_url (required initially for Azure)
  --api-version <value>      Azure api-version; use none to remove a saved value
  --azure-base-url <url>     Azure-only alias for --base-url
  --azure-api-version <value>
                             Azure-only alias for --api-version
  --profile <name>           Set the selected home's default model profile
  --dry-run                  Preview generation without changing files

claude args:
  --env <name>               Create or refresh a named environment
  --base-url <url>           Save an Anthropic Messages endpoint in that env
  --model <id>               Save its default model
  --context-tokens <n>       Set the server's actual context window
  --auth-token-stdin         Read a gateway token from a pipe instead of hidden input
  --skill <name>             Check a required installed skill (legacy, repeatable)
                             All installed dotfiles user skills are shared
  --dry-run                  Preview setup without changing files

skills args:
  --scope user|project       Install user or project skills (default: user)
  --profile <csv>            Profile list, e.g. base,office or workbench
                             Required for project scope; defaults to base for user scope
  --agent <name>             Target agent, repeatable or comma-separated
                             Supported: codex, claude-code
  profile validate           Validate all skills/profiles/*.json files
  profile validate --profile <csv>
                             Validate selected profiles only

Environment:
  SETUP_HOME          Override target home directory (default: $HOME)
  SETUP_TMPDIR        Override temp directory (default: $TMPDIR or /tmp)
  SETUP_DOTFILES_ROOT Override dotfiles root path
  SETUP_DRY_RUN       Force dry-run mode (0 or 1)
  SETUP_EXEC_SHELL    Exec a fresh login zsh after setup completes (0 or 1)
  SETUP_STRICT        Stop at the first failed step instead of continuing (0 or 1)
EOF
}

init_setup_env() {
  SETUP_HOME="${SETUP_HOME:-${HOME}}"
  SETUP_TMPDIR="${SETUP_TMPDIR:-${TMPDIR:-/tmp}}"
  SETUP_DOTFILES_ROOT="${SETUP_DOTFILES_ROOT:-${DOTFILES_ROOT}}"
  SETUP_DRY_RUN="${SETUP_DRY_RUN:-0}"
  SETUP_EXEC_SHELL="${SETUP_EXEC_SHELL:-0}"
  SETUP_STRICT="${SETUP_STRICT:-0}"

  case "${SETUP_STRICT}" in
    0 | 1) ;;
    *)
      log_error "SETUP_STRICT must be 0 or 1: ${SETUP_STRICT}"
      return 1
      ;;
  esac

  case "${SETUP_DRY_RUN}" in
    0 | 1) ;;
    *)
      log_error "SETUP_DRY_RUN must be 0 or 1: ${SETUP_DRY_RUN}"
      return 1
      ;;
  esac

  case "${SETUP_EXEC_SHELL}" in
    0 | 1) ;;
    *)
      log_error "SETUP_EXEC_SHELL must be 0 or 1: ${SETUP_EXEC_SHELL}"
      return 1
      ;;
  esac
}

maybe_reload_shell() {
  if [ "${SETUP_DRY_RUN}" = "1" ]; then
    return 0
  fi

  if ! [ -t 0 ] || ! [ -t 1 ]; then
    return 0
  fi

  if ! command_exists zsh; then
    log_warn "zsh is not available; open a new shell manually to load the new config."
    return 0
  fi

  if [ "${SETUP_EXEC_SHELL}" = "1" ]; then
    log_info "Reloading into a fresh login zsh..."
    exec zsh -l
  fi

  log_info "Setup completed. Run 'exec zsh -l' to load zsh, sheldon, and mise in this terminal."
}

parse_step_args() {
  local subcommand="$1"
  shift
  STEPS_ONLY=""
  STEPS_SKIP=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --only)
        if [ "$#" -lt 2 ]; then
          log_error "--only requires a csv value"
          return 1
        fi
        STEPS_ONLY="$2"
        shift 2
        ;;
      --skip)
        if [ "$#" -lt 2 ]; then
          log_error "--skip requires a csv value"
          return 1
        fi
        STEPS_SKIP="$2"
        shift 2
        ;;
      --dry-run)
        SETUP_DRY_RUN=1
        shift
        ;;
      --reload-shell)
        SETUP_EXEC_SHELL=1
        shift
        ;;
      *)
        log_error "Unknown ${subcommand} argument: $1"
        return 1
        ;;
    esac
  done
}

run_step_subcommand() {
  local subcommand="$1"
  shift
  local -a steps=()

  parse_step_args "${subcommand}" "$@" || {
    usage
    return 1
  }

  local -a steps=()
  local step
  # macOS ships Bash 3.2, which has no mapfile.
  while IFS= read -r step; do
    steps+=("${step}")
  done < <(list_subcommand_steps "${subcommand}")
  log_info "Running ${subcommand} setup..."
  run_setup_steps "${STEPS_ONLY}" "${STEPS_SKIP}" "${steps[@]}" || return

  if [ "${subcommand}" != "links" ]; then
    maybe_reload_shell
  fi
}

main() {
  init_setup_env

  local subcommand
  if [ "$#" -eq 0 ]; then
    subcommand="all"
  else
    subcommand="$1"
    shift
  fi

  if [[ "${subcommand}" == --* ]]; then
    log_error "Flags are not supported. Use subcommands: all, links, bootstrap, tools, plugins, skills, codex, claude, help."
    usage
    return 1
  fi

  case "${subcommand}" in
    all | links | bootstrap | tools | plugins)
      run_step_subcommand "${subcommand}" "$@"
      ;;
    skills)
      if [ "$#" -ge 2 ] && [ "$1" = "profile" ] && [ "$2" = "validate" ]; then
        log_info "Validating skills profiles..."
      else
        log_info "Running skills setup..."
      fi
      setup_skills "$@"
      ;;
    codex)
      setup_codex "$@"
      ;;
    claude)
      setup_claude "$@"
      ;;
    help)
      usage
      ;;
    *)
      log_error "Unknown subcommand: ${subcommand}"
      usage
      return 1
      ;;
  esac
}

main "$@"
