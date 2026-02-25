#!/usr/bin/env bash

setup_links() {
  local dotfiles_root="$1"

  link_file "${dotfiles_root}/sheldon" "${HOME}/.config/sheldon"
  link_file "${dotfiles_root}/zsh" "${HOME}/.config/zsh"
  link_file "${dotfiles_root}/mise" "${HOME}/.config/mise"
  link_file "${dotfiles_root}/zellij" "${HOME}/.config/zellij"
  link_file "${dotfiles_root}/nvim" "${HOME}/.config/nvim"
  link_file "${dotfiles_root}/lazygit" "${HOME}/.config/lazygit"
  link_file "${dotfiles_root}/gitui" "${HOME}/.config/gitui"
  link_file "${dotfiles_root}/mcphub" "${HOME}/.config/mcphub"

  make_directory "${HOME}/.vim/vim/undo"
  make_directory "${HOME}/.vim/vim/tmp"
  make_directory "${HOME}/.vim/nvim/undo"
  make_directory "${HOME}/.vim/nvim/tmp"

  make_directory "${HOME}/.codex"
  make_directory "${HOME}/.codex/rules"
  link_file "${dotfiles_root}/codex/config.toml" "${HOME}/.codex/config.toml"
  link_file "${dotfiles_root}/codex/rules/user.rules" "${HOME}/.codex/rules/user.rules"
  link_file "${dotfiles_root}/codex/prompts" "${HOME}/.codex/prompts"

  make_directory "${HOME}/.gemini"
  link_file "${dotfiles_root}/gemini/settings.json" "${HOME}/.gemini/settings.json"
  link_file "${dotfiles_root}/gemini/commands" "${HOME}/.gemini/commands"

  make_directory "${HOME}/.claude"
  link_file "${dotfiles_root}/claude/settings.json" "${HOME}/.claude/settings.json"
  link_file "${dotfiles_root}/claude/commands" "${HOME}/.claude/commands"
  link_file "${dotfiles_root}/claude/.claude.json" "${HOME}/.claude.json"

  local rules_composer="${dotfiles_root}/ai-rules/scripts/compose-rules.sh"
  if [ ! -f "${rules_composer}" ]; then
    log_error "compose script not found: ${rules_composer}"
    return 1
  fi
  bash "${rules_composer}" codex "${HOME}/.codex/AGENTS.md"
  bash "${rules_composer}" gemini "${HOME}/.gemini/GEMINI.md"
  bash "${rules_composer}" claude "${HOME}/.claude/CLAUDE.md"

  local ipy_profile_dir="${HOME}/.ipython/profile_default"
  local dot_ipy_profile="${dotfiles_root}/ipython/profile_default"
  make_directory "${ipy_profile_dir}"
  make_directory "${ipy_profile_dir}/startup"
  link_file "${dot_ipy_profile}/ipython_config.py" "${ipy_profile_dir}/ipython_config.py"
  link_file "${dot_ipy_profile}/ipython_kernel_config.py" "${ipy_profile_dir}/ipython_kernel_config.py"

  local f
  for f in "${dot_ipy_profile}/startup/"*.py; do
    [ -e "${f}" ] || continue
    link_file "${f}" "${ipy_profile_dir}/startup/$(basename "${f}")"
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
    link_file "${f}" "${HOME}/${base}"
  done
}
