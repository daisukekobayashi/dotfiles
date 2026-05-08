#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_DOTFILES="${TEST_ROOT}/dotfiles"
  TEST_BIN="${TEST_ROOT}/bin"
  TEST_LOG="${TEST_ROOT}/skills.log"
  mkdir -p "${TEST_BIN}" "${TEST_DOTFILES}"

  cp -R "$(repo_root)/skills" "${TEST_DOTFILES}/skills"

  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"

if [ "$#" -lt 3 ] || [ "$1" != "skills" ] || [ "$2" != "add" ]; then
  printf 'unexpected npx invocation: %s\n' "$*" >&2
  exit 1
fi

shift 2
source_name="$1"
shift

skills=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --skill)
      skills+=("$2")
      shift 2
      ;;
    --agent|--copy|--yes)
      if [ "$1" = "--agent" ]; then
        shift 2
      else
        shift
      fi
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\n' "${source_name}" > skills-lock.json
for skill_name in "${skills[@]}"; do
  mkdir -p ".agents/skills/${skill_name}"
  printf '%s\n' "${skill_name}" > ".agents/skills/${skill_name}/SKILL.md"
done
EOF
  chmod +x "${TEST_BIN}/npx"
}

teardown() {
  teardown_test_env
}

@test "skills defaults to user scope with the base profile" {
  mkdir -p "${TEST_HOME}/.gemini"
  ln -s /tmp/stale-gemini-skills "${TEST_HOME}/.gemini/skills"

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
  [ -d "${TEST_DOTFILES}/.agents/user/skills/find-skills" ]
  [ -L "${TEST_DOTFILES}/.agents/user/skills/github-pr" ]
  [ "$(readlink "${TEST_DOTFILES}/.agents/user/skills/github-pr")" = "${TEST_DOTFILES}/skills/local/github-pr" ]
  [ -L "${TEST_DOTFILES}/.agents/user/skills/github-issue-create" ]
  [ "$(readlink "${TEST_DOTFILES}/.agents/user/skills/github-issue-create")" = "${TEST_DOTFILES}/skills/local/github-issue-create" ]
  [ -f "${TEST_DOTFILES}/.agents/user/skills-profile.json" ]
  [ -L "${TEST_HOME}/.agents/skills" ]
  [ "$(readlink "${TEST_HOME}/.agents/skills")" = "${TEST_DOTFILES}/.agents/user/skills" ]
  [ -L "${TEST_HOME}/.claude/skills" ]
  [ "$(readlink "${TEST_HOME}/.claude/skills")" = "${TEST_DOTFILES}/.agents/user/skills" ]
  [ -L "${TEST_HOME}/.gemini/skills" ]
  [ "$(readlink "${TEST_HOME}/.gemini/skills")" = "/tmp/stale-gemini-skills" ]
  grep -F 'skills add vercel-labs/skills' "${TEST_LOG}"
  grep -F 'skills add obra/superpowers' "${TEST_LOG}"
}

@test "skills profile validate accepts the repository profiles" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    "$(setup_script_path)" \
    skills profile validate

  [ "$status" -eq 0 ]
  [[ "$output" == *"Profiles valid:"* ]]
  [[ "$output" == *"base"* ]]
  [[ "$output" == *"office"* ]]
}

@test "docs profile stays independent from base" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --scope user --profile docs

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/context7-cli" ]
  [ ! -e "${TEST_DOTFILES}/.agents/user/skills/find-skills" ]
  [ ! -e "${TEST_DOTFILES}/.agents/user/skills/github-pr" ]
}

@test "workbench profile composes base docs browser and research" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --scope user --profile workbench

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/find-skills" ]
  [ -L "${TEST_DOTFILES}/.agents/user/skills/github-pr" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/context7-cli" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/agent-browser" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/read-arxiv-paper" ]
}

@test "github issue workflow skill documents type-prefixed branch naming" {
  run grep -F "\`type/<id>-<slug>\`" "$(repo_root)/skills/local/github-issue-worktree/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'current-repo only' "$(repo_root)/skills/local/github-issue-worktree/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'conventional-commit-style branch prefix' "$(repo_root)/skills/local/github-issue-worktree/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "github issue create skill documents preview and template checks" {
  run grep -F 'issue template' "$(repo_root)/skills/local/github-issue-create/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'preview' "$(repo_root)/skills/local/github-issue-create/SKILL.md"
  [ "$status" -eq 0 ]

  run grep -F 'current-repo only' "$(repo_root)/skills/local/github-issue-create/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "skills rejects the removed --source option" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    "$(setup_script_path)" \
    skills --source invalid

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown skills argument: --source"* ]]
}
