#!/usr/bin/env bash

setup_skills() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local setup_tmpdir="$3"
  local dry_run="$4"

  local restore_root="${dotfiles_root}/.agents"
  local restore_skills_dir="${restore_root}/skills"
  local local_skills_dir="${dotfiles_root}/skills"
  local lock_file="${dotfiles_root}/skills-lock.json"
  local npm_cache_dir="${setup_tmpdir}/skills-npm-cache"

  if [ ! -f "${lock_file}" ]; then
    log_error "skills lock file not found: ${lock_file}"
    return 1
  fi

  if [ ! -d "${local_skills_dir}" ]; then
    log_error "local skills directory not found: ${local_skills_dir}"
    return 1
  fi

  require_cmd npx || return 1

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN rm -rf ${restore_skills_dir}"
  else
    rm -rf "${restore_skills_dir}"
  fi
  make_directory "${restore_root}" "${dry_run}"
  make_directory "${restore_skills_dir}" "${dry_run}"
  make_directory "${npm_cache_dir}" "${dry_run}"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN cd ${dotfiles_root} && NPM_CONFIG_CACHE=${npm_cache_dir} npx skills experimental_install"
  else
    (
      cd "${dotfiles_root}" || exit 1
      NPM_CONFIG_CACHE="${npm_cache_dir}" npx skills experimental_install
    )
  fi

  local skill_dir
  local skill_name
  for skill_dir in "${local_skills_dir}"/*; do
    [ -d "${skill_dir}" ] || continue

    skill_name="$(basename "${skill_dir}")"
    if [ -e "${restore_skills_dir}/${skill_name}" ] || [ -L "${restore_skills_dir}/${skill_name}" ]; then
      log_error "local skill already exists in restore target: ${skill_name}"
      return 1
    fi

    link_file "${skill_dir}" "${restore_skills_dir}/${skill_name}" "${dry_run}"
  done

  make_directory "${setup_home}/.agents" "${dry_run}"
  make_directory "${setup_home}/.claude" "${dry_run}"
  make_directory "${setup_home}/.gemini" "${dry_run}"

  link_file "${restore_skills_dir}" "${setup_home}/.agents/skills" "${dry_run}"
  link_file "${restore_skills_dir}" "${setup_home}/.claude/skills" "${dry_run}"
  link_file "${restore_skills_dir}" "${setup_home}/.gemini/skills" "${dry_run}"
}
