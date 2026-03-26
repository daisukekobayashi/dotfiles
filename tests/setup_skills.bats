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

@test "skills restores external skills, links local skills, and wires assistant skill directories" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/skills/external-skill" ]
  [ -L "${TEST_DOTFILES}/.agents/skills/git-workflow-guardrails" ]
  [ "$(readlink "${TEST_DOTFILES}/.agents/skills/git-workflow-guardrails")" = "${TEST_DOTFILES}/skills/git-workflow-guardrails" ]
  [ -L "${TEST_HOME}/.agents/skills" ]
  [ "$(readlink "${TEST_HOME}/.agents/skills")" = "${TEST_DOTFILES}/.agents/skills" ]
  [ -L "${TEST_HOME}/.claude/skills" ]
  [ "$(readlink "${TEST_HOME}/.claude/skills")" = "${TEST_DOTFILES}/.agents/skills" ]
  [ -L "${TEST_HOME}/.gemini/skills" ]
  [ "$(readlink "${TEST_HOME}/.gemini/skills")" = "${TEST_DOTFILES}/.agents/skills" ]
  [ "$(cat "${TEST_LOG}")" = "skills experimental_install" ]
}

@test "skills fails when a local skill name conflicts with a restored skill" {
  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"

if [ "$#" -ge 2 ] && [ "$1" = "skills" ] && [ "$2" = "experimental_install" ]; then
  mkdir -p .agents/skills/git-workflow-guardrails
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
    "$(setup_script_path)" \
    skills

  [ "$status" -eq 1 ]
  [[ "$output" == *"local skill already exists in restore target: git-workflow-guardrails"* ]]
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
