#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_DOTFILES="${TEST_ROOT}/dotfiles"
  TEST_BIN="${TEST_ROOT}/bin"
  TEST_LOG="${TEST_ROOT}/skills.log"
  mkdir -p "${TEST_BIN}" "${TEST_DOTFILES}"

  cp "$(repo_root)/skills-lock.json" "${TEST_DOTFILES}/skills-lock.json"
  cp -R "$(repo_root)/skills" "${TEST_DOTFILES}/skills"
  TEST_LOCAL_SKILL="$(find "${TEST_DOTFILES}/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort | head -n 1)"

  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"

if [ "$#" -ge 2 ] && [ "$1" = "skills" ] && [ "$2" = "experimental_install" ]; then
  mkdir -p .agents/skills/external-skill
  exit 0
fi

printf 'unexpected npx invocation: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/npx"
}

teardown() {
  teardown_test_env
}

@test "skills restores external skills and wires only the required assistant skill directories" {
  mkdir -p "${TEST_HOME}/.gemini"
  ln -s /tmp/stale-gemini-skills "${TEST_HOME}/.gemini/skills"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    TEST_LOCAL_SKILL="${TEST_LOCAL_SKILL}" \
    "$(setup_script_path)" \
    skills

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/skills/external-skill" ]
  local skill_name
  for skill_name in $(find "${TEST_DOTFILES}/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do
    [ -L "${TEST_DOTFILES}/.agents/skills/${skill_name}" ]
    [ "$(readlink "${TEST_DOTFILES}/.agents/skills/${skill_name}")" = "${TEST_DOTFILES}/skills/${skill_name}" ]
  done
  [ -L "${TEST_HOME}/.agents/skills" ]
  [ "$(readlink "${TEST_HOME}/.agents/skills")" = "${TEST_DOTFILES}/.agents/skills" ]
  [ -L "${TEST_HOME}/.claude/skills" ]
  [ "$(readlink "${TEST_HOME}/.claude/skills")" = "${TEST_DOTFILES}/.agents/skills" ]
  [ -L "${TEST_HOME}/.gemini/skills" ]
  [ "$(readlink "${TEST_HOME}/.gemini/skills")" = "/tmp/stale-gemini-skills" ]
  [ "$(cat "${TEST_LOG}")" = "skills experimental_install" ]
}

@test "skills --source local refreshes local skills without clearing existing restored skills" {
  mkdir -p "${TEST_DOTFILES}/.agents/skills/external-skill"
  local backup
  backup="${TEST_ROOT}/skills-lock.json.backup"
  mv "${TEST_DOTFILES}/skills-lock.json" "${backup}"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --source local

  mv "${backup}" "${TEST_DOTFILES}/skills-lock.json"

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/skills/external-skill" ]
  local skill_name
  for skill_name in $(find "${TEST_DOTFILES}/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do
    [ -L "${TEST_DOTFILES}/.agents/skills/${skill_name}" ]
    [ "$(readlink "${TEST_DOTFILES}/.agents/skills/${skill_name}")" = "${TEST_DOTFILES}/skills/${skill_name}" ]
  done
  [ ! -e "${TEST_LOG}" ]
}

@test "skills --source local links the GitHub workflow custom skills" {
  local expected_skills
  expected_skills=(
    github-ai-review-followup
    github-issue-from-discussion
    github-issue-worktree
    github-merge-cleanup
  )

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --source local

  [ "$status" -eq 0 ]

  local skill_name
  for skill_name in "${expected_skills[@]}"; do
    [ -d "${TEST_DOTFILES}/skills/${skill_name}" ]
    [ -L "${TEST_DOTFILES}/.agents/skills/${skill_name}" ]
    [ "$(readlink "${TEST_DOTFILES}/.agents/skills/${skill_name}")" = "${TEST_DOTFILES}/skills/${skill_name}" ]
  done
}

@test "github issue workflow skill documents type-prefixed branch naming" {
  run grep -F '`type/<id>-<slug>`' "$(repo_root)/skills/github-issue-worktree/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F '`type/<id1>-<id2>-<slug>`' "$(repo_root)/skills/github-issue-worktree/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'conventional-commit-style branch prefix' "$(repo_root)/skills/github-issue-worktree/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "github issue from discussion skill documents preview and template checks" {
  run grep -F 'issue template' "$(repo_root)/skills/github-issue-from-discussion/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'preview' "$(repo_root)/skills/github-issue-from-discussion/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'current-repo only' "$(repo_root)/skills/github-issue-from-discussion/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "skills --source lock refreshes restored skills and preserves local skills when available" {
  mkdir -p "${TEST_DOTFILES}/.agents/skills/stale-external-skill"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --source lock

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/skills/external-skill" ]
  [ ! -e "${TEST_DOTFILES}/.agents/skills/stale-external-skill" ]
  [ -L "${TEST_DOTFILES}/.agents/skills/${TEST_LOCAL_SKILL}" ]
  [ "$(readlink "${TEST_DOTFILES}/.agents/skills/${TEST_LOCAL_SKILL}")" = "${TEST_DOTFILES}/skills/${TEST_LOCAL_SKILL}" ]
  [ "$(cat "${TEST_LOG}")" = "skills experimental_install" ]
}

@test "skills fails when a local skill name conflicts with a restored skill" {
  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"

if [ "$#" -ge 2 ] && [ "$1" = "skills" ] && [ "$2" = "experimental_install" ]; then
  mkdir -p ".agents/skills/${TEST_LOCAL_SKILL}"
  exit 0
fi

printf 'unexpected npx invocation: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/npx"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    TEST_LOCAL_SKILL="${TEST_LOCAL_SKILL}" \
    "$(setup_script_path)" \
    skills

  [ "$status" -eq 1 ]
}

@test "skills fails when skills-lock.json is missing" {
  local backup
  backup="${TEST_ROOT}/skills-lock.json.backup"

  mv "${TEST_DOTFILES}/skills-lock.json" "${backup}"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills

  mv "${backup}" "${TEST_DOTFILES}/skills-lock.json"

  [ "$status" -eq 1 ]
  [[ "$output" == *"skills lock file not found:"* ]]
}

@test "skills fails when --source value is unsupported" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --source invalid

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown skills source: invalid"* ]]
}
