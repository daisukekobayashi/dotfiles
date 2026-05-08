#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_DOTFILES="${TEST_ROOT}/dotfiles"
  TEST_BIN="${TEST_ROOT}/bin"
  TEST_LOG="${TEST_ROOT}/skills.log"
  TEST_PROJECT="${TEST_ROOT}/project"

  mkdir -p \
    "${TEST_BIN}" \
    "${TEST_DOTFILES}/skills/local/local-one" \
    "${TEST_DOTFILES}/skills/profiles" \
    "${TEST_PROJECT}"

  cat > "${TEST_DOTFILES}/skills/local/local-one/SKILL.md" <<'EOF'
---
name: local-one
description: Test local skill
---

Local skill.
EOF

  cat > "${TEST_DOTFILES}/skills/profiles/base.json" <<'EOF'
{
  "description": "Base test profile",
  "external": [
    {
      "source": "vercel-labs/skills",
      "skills": ["find-skills"]
    }
  ],
  "local": ["local-one"]
}
EOF

  cat > "${TEST_DOTFILES}/skills/profiles/office.json" <<'EOF'
{
  "description": "Office test profile",
  "includes": ["base"],
  "external": [
    {
      "source": "anthropics/skills",
      "skills": ["docx", "pdf"]
    }
  ],
  "local": []
}
EOF

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

agents=()
skills=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      agents+=("$2")
      shift 2
      ;;
    --skill)
      skills+=("$2")
      shift 2
      ;;
    --copy|--yes)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

mkdir -p .agents/skills .claude/skills
printf '{"version":3,"source":"%s"}\n' "${source_name}" > skills-lock.json

for skill_name in "${skills[@]}"; do
  for agent_name in "${agents[@]}"; do
    case "${agent_name}" in
      codex)
        mkdir -p ".agents/skills/${skill_name}"
        printf '%s\n' "${skill_name}" > ".agents/skills/${skill_name}/SKILL.md"
        ;;
      claude-code)
        mkdir -p ".claude/skills/${skill_name}"
        printf '%s\n' "${skill_name}" > ".claude/skills/${skill_name}/SKILL.md"
        ;;
    esac
  done
done
EOF
  chmod +x "${TEST_BIN}/npx"

  git -C "${TEST_PROJECT}" init -q
}

teardown() {
  teardown_test_env
}

@test "skills --scope project installs external skills and links local skills for selected agents" {
  cd "${TEST_PROJECT}"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --scope project --profile office --agent codex --agent claude-code

  [ "$status" -eq 0 ]
  [ -d "${TEST_PROJECT}/.agents/skills/docx" ]
  [ -d "${TEST_PROJECT}/.agents/skills/pdf" ]
  [ -d "${TEST_PROJECT}/.agents/skills/find-skills" ]
  [ -d "${TEST_PROJECT}/.claude/skills/docx" ]
  [ -d "${TEST_PROJECT}/.claude/skills/pdf" ]
  [ -d "${TEST_PROJECT}/.claude/skills/find-skills" ]
  [ -L "${TEST_PROJECT}/.agents/skills/local-one" ]
  [ "$(readlink "${TEST_PROJECT}/.agents/skills/local-one")" = "${TEST_DOTFILES}/skills/local/local-one" ]
  [ -L "${TEST_PROJECT}/.claude/skills/local-one" ]
  [ "$(readlink "${TEST_PROJECT}/.claude/skills/local-one")" = "${TEST_DOTFILES}/skills/local/local-one" ]
  [ -f "${TEST_PROJECT}/skills-lock.json" ]
  [ -f "${TEST_PROJECT}/.agents/skills-profile.json" ]
  grep -F '"requestedProfiles": [' "${TEST_PROJECT}/.agents/skills-profile.json"
  grep -F '"office"' "${TEST_PROJECT}/.agents/skills-profile.json"
  grep -F 'skills add anthropics/skills' "${TEST_LOG}"
  grep -F 'skills add vercel-labs/skills' "${TEST_LOG}"
}

@test "skills --scope project restores existing skills when external install fails" {
  cd "${TEST_PROJECT}"

  mkdir -p .agents/skills/old-agent .claude/skills/old-claude
  printf 'old-lock\n' > skills-lock.json
  printf 'old-profile\n' > .agents/skills-profile.json
  printf 'old-agent\n' > .agents/skills/old-agent/SKILL.md
  printf 'old-claude\n' > .claude/skills/old-claude/SKILL.md

  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"
exit 42
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
    skills --scope project --profile office --agent codex --agent claude-code

  [ "$status" -ne 0 ]
  [ "$(cat skills-lock.json)" = "old-lock" ]
  [ "$(cat .agents/skills-profile.json)" = "old-profile" ]
  [ "$(cat .agents/skills/old-agent/SKILL.md)" = "old-agent" ]
  [ "$(cat .claude/skills/old-claude/SKILL.md)" = "old-claude" ]
}

@test "skills --scope project removes partial generated skills when external install fails" {
  cd "${TEST_PROJECT}"

  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"
mkdir -p .agents/skills/partial .claude/skills/partial
printf 'partial-lock\n' > skills-lock.json
printf 'partial-agent\n' > .agents/skills/partial/SKILL.md
printf 'partial-claude\n' > .claude/skills/partial/SKILL.md
exit 42
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
    skills --scope project --profile base --agent codex --agent claude-code

  [ "$status" -ne 0 ]
  [ ! -e skills-lock.json ]
  [ ! -e .agents/skills/partial ]
  [ ! -e .claude/skills/partial ]
}

@test "skills --scope project requires an explicit profile" {
  cd "${TEST_PROJECT}"

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --scope project

  [ "$status" -eq 1 ]
  [[ "$output" == *"--profile is required for project scope"* ]]
}

@test "skills --scope user builds one user skill view and links user agent directories" {
  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    TEST_SKILLS_LOG="${TEST_LOG}" \
    "$(setup_script_path)" \
    skills --scope user --profile base

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/find-skills" ]
  [ -L "${TEST_DOTFILES}/.agents/user/skills/local-one" ]
  [ "$(readlink "${TEST_DOTFILES}/.agents/user/skills/local-one")" = "${TEST_DOTFILES}/skills/local/local-one" ]
  [ -f "${TEST_DOTFILES}/.agents/user/skills-profile.json" ]
  [ -L "${TEST_HOME}/.agents/skills" ]
  [ "$(readlink "${TEST_HOME}/.agents/skills")" = "${TEST_DOTFILES}/.agents/user/skills" ]
  [ -L "${TEST_HOME}/.claude/skills" ]
  [ "$(readlink "${TEST_HOME}/.claude/skills")" = "${TEST_DOTFILES}/.agents/user/skills" ]
  grep -F 'skills add vercel-labs/skills' "${TEST_LOG}"
}

@test "skills --scope user keeps existing skill view when external install fails" {
  mkdir -p "${TEST_DOTFILES}/.agents/user/skills/old-user"
  printf 'old-user\n' > "${TEST_DOTFILES}/.agents/user/skills/old-user/SKILL.md"
  printf 'old-profile\n' > "${TEST_DOTFILES}/.agents/user/skills-profile.json"

  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${TEST_SKILLS_LOG}"
exit 42
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
    skills --scope user --profile base

  [ "$status" -ne 0 ]
  [ "$(cat "${TEST_DOTFILES}/.agents/user/skills/old-user/SKILL.md")" = "old-user" ]
  [ "$(cat "${TEST_DOTFILES}/.agents/user/skills-profile.json")" = "old-profile" ]
}

@test "skills --scope user preserves external skills when the CLI refreshes its target per source" {
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
    --agent)
      shift 2
      ;;
    --copy|--yes)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

rm -rf .agents/skills
mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\n' "${source_name}" > skills-lock.json
for skill_name in "${skills[@]}"; do
  mkdir -p ".agents/skills/${skill_name}"
  printf '%s\n' "${skill_name}" > ".agents/skills/${skill_name}/SKILL.md"
done
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
    skills --scope user --profile office

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/find-skills" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/docx" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/pdf" ]
  [ -L "${TEST_DOTFILES}/.agents/user/skills/local-one" ]
}

@test "skills --scope user preserves external skills when the CLI consumes stdin" {
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
    --agent)
      shift 2
      ;;
    --copy|--yes)
      shift
      ;;
    *)
      shift
      ;;
  esac
done

cat >/dev/null

mkdir -p .agents/skills
printf '{"version":3,"source":"%s"}\n' "${source_name}" > skills-lock.json
for skill_name in "${skills[@]}"; do
  mkdir -p ".agents/skills/${skill_name}"
  printf '%s\n' "${skill_name}" > ".agents/skills/${skill_name}/SKILL.md"
done
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
    skills --scope user --profile office

  [ "$status" -eq 0 ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/find-skills" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/docx" ]
  [ -d "${TEST_DOTFILES}/.agents/user/skills/pdf" ]
  [ "$(wc -l < "${TEST_LOG}")" -ge 2 ]
}

@test "skills profile validate rejects missing local skills" {
  cat > "${TEST_DOTFILES}/skills/profiles/broken.json" <<'EOF'
{
  "description": "Broken test profile",
  "local": ["missing-local"]
}
EOF

  run env \
    HOME="${TEST_HOME}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    "$(setup_script_path)" \
    skills profile validate

  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown local skill missing-local"* ]]
}
