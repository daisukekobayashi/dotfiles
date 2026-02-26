#!/usr/bin/env bash

setup_links() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local dry_run="$3"

  link_file "${dotfiles_root}/sheldon" "${setup_home}/.config/sheldon" "${dry_run}"
  link_file "${dotfiles_root}/zsh" "${setup_home}/.config/zsh" "${dry_run}"
  link_file "${dotfiles_root}/mise" "${setup_home}/.config/mise" "${dry_run}"
  link_file "${dotfiles_root}/zellij" "${setup_home}/.config/zellij" "${dry_run}"
  link_file "${dotfiles_root}/nvim" "${setup_home}/.config/nvim" "${dry_run}"
  link_file "${dotfiles_root}/lazygit" "${setup_home}/.config/lazygit" "${dry_run}"
  link_file "${dotfiles_root}/gitui" "${setup_home}/.config/gitui" "${dry_run}"
  link_file "${dotfiles_root}/mcphub" "${setup_home}/.config/mcphub" "${dry_run}"

  make_directory "${setup_home}/.vim/vim/undo" "${dry_run}"
  make_directory "${setup_home}/.vim/vim/tmp" "${dry_run}"
  make_directory "${setup_home}/.vim/nvim/undo" "${dry_run}"
  make_directory "${setup_home}/.vim/nvim/tmp" "${dry_run}"

  make_directory "${setup_home}/.codex" "${dry_run}"
  make_directory "${setup_home}/.codex/rules" "${dry_run}"
  link_file "${dotfiles_root}/codex/config.toml" "${setup_home}/.codex/config.toml" "${dry_run}"
  link_file "${dotfiles_root}/codex/rules/user.rules" "${setup_home}/.codex/rules/user.rules" "${dry_run}"
  link_file "${dotfiles_root}/codex/prompts" "${setup_home}/.codex/prompts" "${dry_run}"

  make_directory "${setup_home}/.gemini" "${dry_run}"
  link_file "${dotfiles_root}/gemini/settings.json" "${setup_home}/.gemini/settings.json" "${dry_run}"
  link_file "${dotfiles_root}/gemini/commands" "${setup_home}/.gemini/commands" "${dry_run}"

  make_directory "${setup_home}/.claude" "${dry_run}"
  link_file "${dotfiles_root}/claude/settings.json" "${setup_home}/.claude/settings.json" "${dry_run}"
  link_file "${dotfiles_root}/claude/commands" "${setup_home}/.claude/commands" "${dry_run}"
  link_file "${dotfiles_root}/claude/.claude.json" "${setup_home}/.claude.json" "${dry_run}"

  local rules_composer="${dotfiles_root}/ai-rules/scripts/compose-rules.sh"
  if [ ! -f "${rules_composer}" ]; then
    log_error "compose script not found: ${rules_composer}"
    return 1
  fi
  run_cmd "${dry_run}" bash "${rules_composer}" codex "${setup_home}/.codex/AGENTS.md"
  run_cmd "${dry_run}" bash "${rules_composer}" gemini "${setup_home}/.gemini/GEMINI.md"
  run_cmd "${dry_run}" bash "${rules_composer}" claude "${setup_home}/.claude/CLAUDE.md"

  local ipy_profile_dir="${setup_home}/.ipython/profile_default"
  local dot_ipy_profile="${dotfiles_root}/ipython/profile_default"
  make_directory "${ipy_profile_dir}" "${dry_run}"
  make_directory "${ipy_profile_dir}/startup" "${dry_run}"
  link_file "${dot_ipy_profile}/ipython_config.py" "${ipy_profile_dir}/ipython_config.py" "${dry_run}"
  link_file "${dot_ipy_profile}/ipython_kernel_config.py" "${ipy_profile_dir}/ipython_kernel_config.py" "${dry_run}"

  local f
  for f in "${dot_ipy_profile}/startup/"*.py; do
    [ -e "${f}" ] || continue
    link_file "${f}" "${ipy_profile_dir}/startup/$(basename "${f}")" "${dry_run}"
  done

  for f in "${dotfiles_root}"/.??*; do
    local base
    base="$(basename "${f}")"
    case "${base}" in
      .git | .DS_Store | .env | .env.example)
        continue
        ;;
    esac
    [ -d "${f}" ] && continue
    link_file "${f}" "${setup_home}/${base}" "${dry_run}"
  done
}
