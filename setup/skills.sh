#!/usr/bin/env bash

skills_profile_helper() {
  printf '%s/skills-profile.js' "${SCRIPT_DIR}"
}

validate_skills_agents() {
  local agents_csv="$1"
  local agent

  IFS=',' read -r -a agent_list <<< "${agents_csv}"
  for agent in "${agent_list[@]}"; do
    agent="$(trim_whitespace "${agent}")"
    case "${agent}" in
      codex | claude-code) ;;
      *)
        log_error "unsupported skills agent: ${agent}"
        return 1
        ;;
    esac
  done
}

create_skills_plan() {
  local dotfiles_root="$1"
  local scope="$2"
  local profiles_csv="$3"
  local agents_csv="$4"
  local plan_file="$5"

  require_cmd node || return 1
  node "$(skills_profile_helper)" plan \
    --dotfiles-root "${dotfiles_root}" \
    --scope "${scope}" \
    --profiles "${profiles_csv}" \
    --agents "${agents_csv}" \
    --output "${plan_file}"
}

write_skills_metadata() {
  local plan_file="$1"
  local output_file="$2"
  local dry_run="${3:-0}"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN write skills metadata ${output_file}"
    return 0
  fi

  node "$(skills_profile_helper)" metadata \
    --plan "${plan_file}" \
    --output "${output_file}"
}

link_skills_local_project() {
  local dotfiles_root="$1"
  local plan_file="$2"
  local project_root="$3"
  local dry_run="$4"

  local dry_run_arg=()
  if [ "${dry_run}" = "1" ]; then
    dry_run_arg=(--dry-run)
  fi

  node "$(skills_profile_helper)" link-local \
    --dotfiles-root "${dotfiles_root}" \
    --plan "${plan_file}" \
    --target project \
    --root "${project_root}" \
    "${dry_run_arg[@]}"
}

link_skills_local_user() {
  local dotfiles_root="$1"
  local plan_file="$2"
  local skills_dir="$3"
  local dry_run="$4"

  local dry_run_arg=()
  if [ "${dry_run}" = "1" ]; then
    dry_run_arg=(--dry-run)
  fi

  node "$(skills_profile_helper)" link-local \
    --dotfiles-root "${dotfiles_root}" \
    --plan "${plan_file}" \
    --target user \
    --skills-dir "${skills_dir}" \
    "${dry_run_arg[@]}"
}

write_skills_external_lines() {
  local plan_file="$1"
  local output_file="$2"

  node "$(skills_profile_helper)" external-lines \
    --plan "${plan_file}" > "${output_file}"
}

skills_plan_has_external() {
  local external_file="$1"
  [ -s "${external_file}" ]
}

run_skills_external_installs() {
  local work_dir="$1"
  local external_file="$2"
  local agents_csv="$3"
  local npm_cache_dir="$4"
  local dry_run="$5"

  local source
  local skills_csv
  local agent
  local skill
  local -a agent_list
  local -a skill_list
  local -a cmd

  skills_plan_has_external "${external_file}" || return 0
  require_cmd npx || return 1

  while IFS=$'\t' read -r source skills_csv; do
    [ -n "${source}" ] || continue
    IFS=',' read -r -a agent_list <<< "${agents_csv}"
    IFS=',' read -r -a skill_list <<< "${skills_csv}"

    cmd=(npx skills add "${source}" --copy --yes)
    for agent in "${agent_list[@]}"; do
      agent="$(trim_whitespace "${agent}")"
      [ -n "${agent}" ] || continue
      cmd+=(--agent "${agent}")
    done
    for skill in "${skill_list[@]}"; do
      skill="$(trim_whitespace "${skill}")"
      [ -n "${skill}" ] || continue
      cmd+=(--skill "${skill}")
    done

    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN cd ${work_dir} && NPM_CONFIG_CACHE=${npm_cache_dir} ${cmd[*]}"
    else
      (
        cd "${work_dir}" || exit 1
        NPM_CONFIG_CACHE="${npm_cache_dir}" "${cmd[@]}" < /dev/null
      ) || return 1
    fi
  done < "${external_file}"
}

backup_skills_path() {
  local target_path="$1"
  local backup_root="$2"
  local dry_run="$3"
  local backup_log="${4:-}"

  if ! [ -e "${target_path}" ] && ! [ -L "${target_path}" ]; then
    if [ -n "${backup_log}" ] && [ "${dry_run}" != "1" ]; then
      printf '%s\t\n' "${target_path}" >> "${backup_log}"
    fi
    return 0
  fi

  local backup_name
  local backup_path
  backup_name="$(basename "$(dirname "${target_path}")")-$(basename "${target_path}")"
  backup_path="${backup_root}/${backup_name}.$(date +%Y%m%d%H%M%S).$$"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN mv ${target_path} ${backup_path}"
    return 0
  fi

  mkdir -p "${backup_root}"
  mv "${target_path}" "${backup_path}"
  if [ -n "${backup_log}" ]; then
    printf '%s\t%s\n' "${target_path}" "${backup_path}" >> "${backup_log}"
  fi
  log_warn "Backed up existing skills path to ${backup_path}"
}

prepare_project_skills_targets() {
  local project_root="$1"
  local agents_csv="$2"
  local backup_root="$3"
  local dry_run="$4"
  local backup_log="$5"

  local agent
  local target_dir
  IFS=',' read -r -a agent_list <<< "${agents_csv}"

  if [ "${dry_run}" != "1" ]; then
    mkdir -p "$(dirname "${backup_log}")"
    : > "${backup_log}"
  fi

  backup_skills_path "${project_root}/skills-lock.json" "${backup_root}" "${dry_run}" "${backup_log}"
  backup_skills_path "${project_root}/.agents/skills-profile.json" "${backup_root}" "${dry_run}" "${backup_log}"

  for agent in "${agent_list[@]}"; do
    agent="$(trim_whitespace "${agent}")"
    case "${agent}" in
      codex)
        target_dir="${project_root}/.agents/skills"
        ;;
      claude-code)
        target_dir="${project_root}/.claude/skills"
        ;;
      *)
        log_error "unsupported skills agent: ${agent}"
        return 1
        ;;
    esac
    backup_skills_path "${target_dir}" "${backup_root}" "${dry_run}" "${backup_log}"
  done
}

rollback_project_skills_targets() {
  local backup_log="$1"
  local dry_run="$2"

  [ "${dry_run}" != "1" ] || return 0
  [ -s "${backup_log}" ] || return 0

  local target_path
  local backup_path
  while IFS=$'\t' read -r target_path backup_path; do
    [ -n "${target_path}" ] || continue

    rm -rf "${target_path}"
    if [ -n "${backup_path}" ] && { [ -e "${backup_path}" ] || [ -L "${backup_path}" ]; }; then
      mkdir -p "$(dirname "${target_path}")"
      mv "${backup_path}" "${target_path}"
    fi
  done < "${backup_log}"

  log_warn "Restored previous project skills after failed install"
}

copy_user_external_skills() {
  local temp_install_dir="$1"
  local restore_skills_dir="$2"
  local dry_run="$3"
  local temp_skills_dir="${temp_install_dir}/.agents/skills"

  [ -d "${temp_skills_dir}" ] || return 0

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN cp -R ${temp_skills_dir}/. ${restore_skills_dir}/"
    return 0
  fi

  cp -R "${temp_skills_dir}/." "${restore_skills_dir}/"
}

run_user_external_installs() {
  local temp_install_dir="$1"
  local restore_skills_dir="$2"
  local external_file="$3"
  local npm_cache_dir="$4"
  local dry_run="$5"

  local source
  local skills_csv
  local skill
  local -a skill_list
  local -a cmd

  skills_plan_has_external "${external_file}" || return 0
  require_cmd npx || return 1

  while IFS=$'\t' read -r source skills_csv; do
    [ -n "${source}" ] || continue

    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN rm -rf ${temp_install_dir}"
      log_info "DRY-RUN mkdir -p ${temp_install_dir}"
    else
      rm -rf "${temp_install_dir}"
      mkdir -p "${temp_install_dir}"
    fi

    IFS=',' read -r -a skill_list <<< "${skills_csv}"
    cmd=(npx skills add "${source}" --copy --yes --agent codex)
    for skill in "${skill_list[@]}"; do
      skill="$(trim_whitespace "${skill}")"
      [ -n "${skill}" ] || continue
      cmd+=(--skill "${skill}")
    done

    if [ "${dry_run}" = "1" ]; then
      log_info "DRY-RUN cd ${temp_install_dir} && NPM_CONFIG_CACHE=${npm_cache_dir} ${cmd[*]}"
    else
      (
        cd "${temp_install_dir}" || exit 1
        NPM_CONFIG_CACHE="${npm_cache_dir}" "${cmd[@]}" < /dev/null
      ) || return 1
    fi

    copy_user_external_skills "${temp_install_dir}" "${restore_skills_dir}" "${dry_run}" || return 1
  done < "${external_file}"
}

cleanup_user_skills_staging() {
  local staging_skills_dir="$1"
  local staging_metadata="$2"
  local temp_install_dir="$3"
  local dry_run="$4"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN rm -rf ${staging_skills_dir} ${staging_metadata} ${temp_install_dir}"
    return 0
  fi

  rm -rf "${staging_skills_dir}" "${staging_metadata}" "${temp_install_dir}"
}

restore_user_skills_backup() {
  local restore_skills_dir="$1"
  local metadata_file="$2"
  local backup_skills_dir="$3"
  local backup_metadata="$4"

  rm -rf "${restore_skills_dir}" "${metadata_file}"
  if [ -e "${backup_skills_dir}" ] || [ -L "${backup_skills_dir}" ]; then
    mv "${backup_skills_dir}" "${restore_skills_dir}"
  fi
  if [ -e "${backup_metadata}" ] || [ -L "${backup_metadata}" ]; then
    mv "${backup_metadata}" "${metadata_file}"
  fi
}

swap_user_skills_view() {
  local restore_root="$1"
  local restore_skills_dir="$2"
  local staging_skills_dir="$3"
  local staging_metadata="$4"
  local dry_run="$5"

  local metadata_file="${restore_root}/skills-profile.json"
  local backup_skills_dir="${restore_root}/skills.previous.$$"
  local backup_metadata="${restore_root}/skills-profile.json.previous.$$"

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN swap ${staging_skills_dir} into ${restore_skills_dir}"
    log_info "DRY-RUN mv ${staging_metadata} ${metadata_file}"
    return 0
  fi

  rm -rf "${backup_skills_dir}" "${backup_metadata}"
  if [ -e "${restore_skills_dir}" ] || [ -L "${restore_skills_dir}" ]; then
    mv "${restore_skills_dir}" "${backup_skills_dir}"
  fi
  if [ -e "${metadata_file}" ] || [ -L "${metadata_file}" ]; then
    mv "${metadata_file}" "${backup_metadata}"
  fi

  if ! mv "${staging_skills_dir}" "${restore_skills_dir}"; then
    restore_user_skills_backup "${restore_skills_dir}" "${metadata_file}" "${backup_skills_dir}" "${backup_metadata}"
    return 1
  fi

  if ! mv "${staging_metadata}" "${metadata_file}"; then
    restore_user_skills_backup "${restore_skills_dir}" "${metadata_file}" "${backup_skills_dir}" "${backup_metadata}"
    return 1
  fi

  rm -rf "${backup_skills_dir}" "${backup_metadata}"
}

link_user_agent_skill_dirs() {
  local restore_skills_dir="$1"
  local setup_home="$2"
  local agents_csv="$3"
  local dry_run="$4"

  local agent
  IFS=',' read -r -a agent_list <<< "${agents_csv}"

  for agent in "${agent_list[@]}"; do
    agent="$(trim_whitespace "${agent}")"
    case "${agent}" in
      codex)
        make_directory "${setup_home}/.agents" "${dry_run}"
        link_file "${restore_skills_dir}" "${setup_home}/.agents/skills" "${dry_run}"
        ;;
      claude-code)
        make_directory "${setup_home}/.claude" "${dry_run}"
        link_file "${restore_skills_dir}" "${setup_home}/.claude/skills" "${dry_run}"
        ;;
      *)
        log_error "unsupported skills agent: ${agent}"
        return 1
        ;;
    esac
  done
}

setup_project_skills() {
  local dotfiles_root="$1"
  local setup_tmpdir="$2"
  local dry_run="$3"
  local profiles_csv="$4"
  local agents_csv="$5"

  if [ -z "${profiles_csv}" ]; then
    log_error "--profile is required for project scope"
    return 1
  fi

  require_cmd git || return 1

  local project_root
  if ! project_root="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null)"; then
    log_error "project scope requires running inside a git repository"
    return 1
  fi

  validate_skills_agents "${agents_csv}" || return 1

  local work_dir="${setup_tmpdir}/dotfiles-skills"
  local plan_file="${work_dir}/project-plan.json"
  local external_file="${work_dir}/project-external.tsv"
  local npm_cache_dir="${setup_tmpdir}/skills-npm-cache"
  local backup_log="${work_dir}/project-backups.tsv"
  local backup_root
  backup_root="${setup_tmpdir}/dotfiles-skills-backup/$(basename "${project_root}")"

  mkdir -p "${work_dir}" "${npm_cache_dir}"
  make_directory "${project_root}/.agents" "${dry_run}"

  create_skills_plan "${dotfiles_root}" "project" "${profiles_csv}" "${agents_csv}" "${plan_file}" || return 1
  write_skills_external_lines "${plan_file}" "${external_file}" || return 1
  prepare_project_skills_targets "${project_root}" "${agents_csv}" "${backup_root}" "${dry_run}" "${backup_log}" || return 1
  if ! run_skills_external_installs "${project_root}" "${external_file}" "${agents_csv}" "${npm_cache_dir}" "${dry_run}" \
    || ! link_skills_local_project "${dotfiles_root}" "${plan_file}" "${project_root}" "${dry_run}" \
    || ! write_skills_metadata "${plan_file}" "${project_root}/.agents/skills-profile.json" "${dry_run}"; then
    rollback_project_skills_targets "${backup_log}" "${dry_run}"
    return 1
  fi

  log_info "Project skills installed for profiles: ${profiles_csv}"
  log_info "Consider ignoring generated skill directories: .agents/skills/ .claude/skills/"
}

setup_user_skills() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local setup_tmpdir="$3"
  local dry_run="$4"
  local profiles_csv="$5"
  local agents_csv="$6"

  [ -n "${profiles_csv}" ] || profiles_csv="base"
  validate_skills_agents "${agents_csv}" || return 1

  local restore_root="${dotfiles_root}/.agents/user"
  local restore_skills_dir="${restore_root}/skills"
  local staging_skills_dir="${restore_root}/skills.next.$$"
  local staging_metadata="${restore_root}/skills-profile.json.next.$$"
  local temp_install_dir="${setup_tmpdir}/dotfiles-skills-user-install"
  local work_dir="${setup_tmpdir}/dotfiles-skills"
  local plan_file="${work_dir}/user-plan.json"
  local external_file="${work_dir}/user-external.tsv"
  local npm_cache_dir="${setup_tmpdir}/skills-npm-cache"

  mkdir -p "${work_dir}" "${npm_cache_dir}"
  create_skills_plan "${dotfiles_root}" "user" "${profiles_csv}" "${agents_csv}" "${plan_file}" || return 1
  write_skills_external_lines "${plan_file}" "${external_file}" || return 1

  if [ "${dry_run}" = "1" ]; then
    log_info "DRY-RUN rm -rf ${staging_skills_dir}"
    log_info "DRY-RUN rm -rf ${staging_metadata}"
    log_info "DRY-RUN rm -rf ${temp_install_dir}"
  else
    rm -rf "${staging_skills_dir}" "${staging_metadata}" "${temp_install_dir}"
  fi

  make_directory "${restore_root}" "${dry_run}"
  make_directory "${staging_skills_dir}" "${dry_run}"
  make_directory "${temp_install_dir}" "${dry_run}"

  if ! run_user_external_installs "${temp_install_dir}" "${staging_skills_dir}" "${external_file}" "${npm_cache_dir}" "${dry_run}" \
    || ! link_skills_local_user "${dotfiles_root}" "${plan_file}" "${staging_skills_dir}" "${dry_run}" \
    || ! write_skills_metadata "${plan_file}" "${staging_metadata}" "${dry_run}" \
    || ! swap_user_skills_view "${restore_root}" "${restore_skills_dir}" "${staging_skills_dir}" "${staging_metadata}" "${dry_run}"; then
    cleanup_user_skills_staging "${staging_skills_dir}" "${staging_metadata}" "${temp_install_dir}" "${dry_run}"
    return 1
  fi
  cleanup_user_skills_staging "${staging_skills_dir}" "${staging_metadata}" "${temp_install_dir}" "${dry_run}"
  link_user_agent_skill_dirs "${restore_skills_dir}" "${setup_home}" "${agents_csv}" "${dry_run}" || return 1

  log_info "User skills installed for profiles: ${profiles_csv}"
}

setup_skills() {
  local dotfiles_root="$1"
  local setup_home="$2"
  local setup_tmpdir="$3"
  local dry_run="$4"
  local scope="${5:-user}"
  local profiles_csv="${6:-}"
  local agents_csv="${7:-codex,claude-code}"

  case "${scope}" in
    user)
      setup_user_skills "${dotfiles_root}" "${setup_home}" "${setup_tmpdir}" "${dry_run}" "${profiles_csv}" "${agents_csv}"
      ;;
    project)
      setup_project_skills "${dotfiles_root}" "${setup_tmpdir}" "${dry_run}" "${profiles_csv}" "${agents_csv}"
      ;;
    *)
      log_error "unsupported skills scope: ${scope}"
      return 1
      ;;
  esac
}

validate_skills_profiles() {
  local dotfiles_root="$1"
  local profiles_csv="${2:-}"

  require_cmd node || return 1

  local profile_arg=()
  if [ -n "${profiles_csv}" ]; then
    profile_arg=(--profiles "${profiles_csv}")
  fi

  node "$(skills_profile_helper)" validate \
    --dotfiles-root "${dotfiles_root}" \
    "${profile_arg[@]}"
}
