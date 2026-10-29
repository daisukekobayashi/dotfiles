#!/usr/bin/env bash

# Phases run in this order. Each step belongs to exactly one phase, and later
# phases depend on earlier ones: tools need the managers from bootstrap, and
# plugins need the tools they extend.
SETUP_PHASES=(links bootstrap tools plugins)

list_phase_steps() {
  case "$1" in
    links) printf '%s\n' links ;;
    bootstrap) printf '%s\n' apt homebrew sheldon mise ;;
    tools) printf '%s\n' mise-tools uv-tools claude codex tmux luarocks quarto nvtop ;;
    plugins) printf '%s\n' alacritty tpm themes ;;
    *) return 1 ;;
  esac
}

# Steps selected by a subcommand, in phase order. packages and post are
# deprecated aliases that keep their previous step sets.
list_subcommand_steps() {
  local subcommand="$1"
  local phase

  case "${subcommand}" in
    all)
      for phase in "${SETUP_PHASES[@]}"; do
        list_phase_steps "${phase}"
      done
      ;;
    links | bootstrap | tools | plugins)
      list_phase_steps "${subcommand}"
      ;;
    packages)
      list_phase_steps bootstrap
      list_phase_steps tools
      list_phase_steps plugins
      ;;
    post)
      printf '%s\n' mise-tools uv-tools tpm themes
      ;;
    *)
      return 1
      ;;
  esac
}

validate_step_csv() {
  local label="$1"
  local csv="$2"
  shift 2
  local -a steps=("$@")
  local -a raw=()
  local item

  [ -z "${csv}" ] && return 0

  IFS=',' read -r -a raw <<< "${csv}"
  for item in "${raw[@]}"; do
    item="$(trim_whitespace "${item}")"
    [ -z "${item}" ] && continue
    if ! printf '%s\n' "${steps[@]}" | grep -Fxq -- "${item}"; then
      log_error "Unknown step in --${label}: ${item}"
      log_error "Steps for this subcommand: $(IFS=','; printf '%s' "${steps[*]}")"
      return 1
    fi
  done
}

should_run_step() {
  local step="$1"
  local only_csv="$2"
  local skip_csv="$3"

  if [ -n "${only_csv}" ] && ! csv_contains "${only_csv}" "${step}"; then
    return 1
  fi

  if csv_contains "${skip_csv}" "${step}"; then
    return 1
  fi

  return 0
}

step_is_strict() {
  [ "${SETUP_STRICT}" = "1" ] && return 0
  # install_mise_tools reports partial failures as errors only in this mode.
  [ "$1" = "mise-tools" ] && [ "${SETUP_MISE_STRICT:-0}" = "1" ]
}

# Prints why a step does not apply and returns 1 when not on Linux.
require_linux_step() {
  local step="$1"

  if [ "$(uname)" != "Linux" ]; then
    log_info "Skipping ${step}: Linux only (macOS installs it from brew/Brewfile)."
    return 1
  fi
}

require_x86_64_step() {
  local step="$1"
  local archstr

  archstr="$(uname -m)"
  if [ "${archstr}" != "x86_64" ]; then
    log_warn "Skipping ${step} because architecture is not x86_64: ${archstr}"
    return 1
  fi
}

ensure_mise_on_path() {
  if ! command_exists mise && [ -x "${SETUP_HOME}/.local/bin/mise" ]; then
    PATH="${SETUP_HOME}/.local/bin:${PATH}"
  fi
}

run_setup_step() {
  local step="$1"

  case "${step}" in
    links)
      setup_links "${SETUP_DOTFILES_ROOT}" "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    apt)
      check_apt_packages "${SETUP_DOTFILES_ROOT}" "${SETUP_DRY_RUN}"
      ;;
    homebrew)
      if [ "$(uname)" != "Darwin" ]; then
        log_info "Skipping homebrew: macOS only."
        return 0
      fi
      install_homebrew_darwin "${SETUP_DRY_RUN}" || return
      activate_homebrew_darwin "${SETUP_DRY_RUN}" || return
      install_homebrew_bundle_darwin "${SETUP_DOTFILES_ROOT}" "${SETUP_DRY_RUN}"
      ;;
    sheldon)
      require_linux_step sheldon || return 0
      install_sheldon "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    mise)
      if [ "$(uname)" = "Linux" ]; then
        install_mise_linux "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      elif command_exists mise; then
        if [ "${SETUP_DRY_RUN}" = "1" ]; then
          log_info "DRY-RUN activate mise"
        else
          eval "$(mise activate bash)"
        fi
      fi
      ;;
    mise-tools)
      ensure_mise_on_path
      if ! command_exists mise; then
        log_warn "Skipping mise tool install because mise is not available."
        return 0
      fi
      install_mise_tools "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    uv-tools)
      install_uv_tools "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    claude)
      install_claude "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    codex)
      install_codex "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    tmux)
      require_linux_step tmux || return 0
      install_tmux "${SETUP_HOME}" "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}"
      ;;
    luarocks)
      require_linux_step luarocks || return 0
      install_luarocks "${SETUP_HOME}" "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}"
      ;;
    quarto)
      require_linux_step quarto || return 0
      require_x86_64_step quarto || return 0
      install_quarto_linux_amd64 "${SETUP_HOME}" "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}"
      ;;
    nvtop)
      require_linux_step nvtop || return 0
      require_x86_64_step nvtop || return 0
      install_nvtop_linux_amd64 "${SETUP_HOME}" "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}"
      ;;
    alacritty)
      require_linux_step alacritty || return 0
      setup_alacritty "${SETUP_DOTFILES_ROOT}" "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    tpm)
      install_tmux_plugins "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    themes)
      install_terminal_themes "${SETUP_HOME}" "${SETUP_DRY_RUN}"
      ;;
    *)
      log_error "Unknown step: ${step}"
      return 1
      ;;
  esac
}

# Runs the selected steps in order. A failed step is reported and setup goes
# on, unless SETUP_STRICT=1 (or SETUP_MISE_STRICT=1 for mise-tools).
run_setup_steps() {
  local only_csv="$1"
  local skip_csv="$2"
  shift 2
  local -a steps=("$@")
  local -a selected=()
  local -a failed_steps=()
  local step
  local step_status

  validate_step_csv "only" "${only_csv}" "${steps[@]}" || return 1
  validate_step_csv "skip" "${skip_csv}" "${steps[@]}" || return 1

  for step in "${steps[@]}"; do
    if should_run_step "${step}" "${only_csv}" "${skip_csv}"; then
      selected+=("${step}")
    fi
  done

  if [ "${SETUP_DRY_RUN}" != "1" ] && printf '%s\n' "${selected[@]}" | grep -Fxvq links; then
    require_cmd curl || return 1
    require_cmd tar || return 1
    require_cmd git || return 1
  fi
  make_directory "${SETUP_TMPDIR}" "${SETUP_DRY_RUN}"

  for step in "${steps[@]}"; do
    if ! should_run_step "${step}" "${only_csv}" "${skip_csv}"; then
      log_info "Skipping step: ${step}"
      continue
    fi

    log_info "Running step: ${step}"
    step_status=0
    run_setup_step "${step}" || step_status=$?
    if [ "${step_status}" -eq 0 ]; then
      continue
    fi

    if step_is_strict "${step}"; then
      log_error "Step failed: ${step} (exit ${step_status})."
      return "${step_status}"
    fi
    failed_steps+=("${step}")
    log_warn "Step failed: ${step} (exit ${step_status}). Continuing setup."
  done

  if [ "${#failed_steps[@]}" -gt 0 ]; then
    log_warn "Continuing despite failed steps: ${failed_steps[*]}"
  fi
}
