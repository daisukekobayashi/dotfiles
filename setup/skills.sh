#!/usr/bin/env bash

remove_local_skill_links() {
  local restore_skills_dir="$1"
  local local_skills_dir="$2"
  local dry_run="${3:-0}"

  local existing_entry
  local existing_target
  for existing_entry in "${restore_skills_dir}"/*; do
    [ -e "${existing_entry}" ] || [ -L "${existing_entry}" ] || continue
    [ -L "${existing_entry}" ] || continue

    existing_target="$(readlink "${existing_entry}")"
    case "${existing_target}" in
      "${local_skills_dir}"/*)
        if [ "${dry_run}" = "1" ]; then
          log_info "DRY-RUN rm -rf ${existing_entry}"
        else
          rm -rf "${existing_entry}"
        fi
        ;;
    esac
  done
}

link_local_skills() {
  local restore_skills_dir="$1"
  local local_skills_dir="$2"
  local dry_run="${3:-0}"

  remove_local_skill_links "${restore_skills_dir}" "${local_skills_dir}" "${dry_run}"

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
}

setup_skills() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local setup_tmpdir="$3"
  local dry_run="$4"
  local source_mode="${5:-both}"

  local restore_root="${dotfiles_root}/.agents"
  local restore_skills_dir="${restore_root}/skills"
  local local_skills_dir="${dotfiles_root}/skills"
  local lock_file="${dotfiles_root}/skills-lock.json"
  local npm_cache_dir="${setup_tmpdir}/skills-npm-cache"
  local install_lock="0"
  local install_local="0"
  local preserve_local_after_lock="0"

  case "${source_mode}" in
    both)
      install_lock="1"
      install_local="1"
      ;;
    lock)
      install_lock="1"
      ;;
    local)
      install_local="1"
      ;;
    *)
      log_error "unsupported skills source mode: ${source_mode}"
      return 1
      ;;
  esac

  if [ "${install_lock}" = "1" ]; then
    if [ ! -f "${lock_file}" ]; then
      log_error "skills lock file not found: ${lock_file}"
      return 1
    fi

    require_cmd npx || return 1
  fi

  if [ "${install_local}" = "1" ] && [ ! -d "${local_skills_dir}" ]; then
    log_error "local skills directory not found: ${local_skills_dir}"
    return 1
  fi

  if [ "${install_lock}" = "1" ] && [ "${install_local}" = "0" ] && [ -d "${local_skills_dir}" ]; then
    preserve_local_after_lock="1"
  fi

  if [ "${install_lock}" = "1" ]; then
    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN rm -rf ${restore_skills_dir}"
    else
      rm -rf "${restore_skills_dir}"
    fi
  fi
  make_directory "${restore_root}" "${dry_run}"
  make_directory "${restore_skills_dir}" "${dry_run}"
  make_directory "${npm_cache_dir}" "${dry_run}"

  if [ "${install_lock}" = "1" ]; then
    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN cd ${dotfiles_root} && NPM_CONFIG_CACHE=${npm_cache_dir} npx skills experimental_install"
    else
      (
        cd "${dotfiles_root}" || exit 1
        NPM_CONFIG_CACHE="${npm_cache_dir}" npx skills experimental_install
      )
    fi
  fi

  if [ "${install_local}" = "1" ]; then
    link_local_skills "${restore_skills_dir}" "${local_skills_dir}" "${dry_run}" || return 1
  elif [ "${preserve_local_after_lock}" = "1" ]; then
    link_local_skills "${restore_skills_dir}" "${local_skills_dir}" "${dry_run}" || return 1
  fi

  make_directory "${setup_home}/.agents" "${dry_run}"
  make_directory "${setup_home}/.claude" "${dry_run}"

  link_file "${restore_skills_dir}" "${setup_home}/.agents/skills" "${dry_run}"
  link_file "${restore_skills_dir}" "${setup_home}/.claude/skills" "${dry_run}"
}
