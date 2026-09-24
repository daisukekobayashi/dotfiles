#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  TEST_DOTFILES="${TEST_ROOT}/dotfiles"
  TEST_PROJECT="${TEST_ROOT}/project"
  TEST_BIN="${TEST_ROOT}/bin"
  mkdir -p "${TEST_DOTFILES}" "${TEST_PROJECT}" "${TEST_BIN}"
  cp -R "$(repo_root)/skills" "${TEST_DOTFILES}/skills"

  cat > "${TEST_BIN}/npx" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected external package execution\n' >&2
exit 99
EOF
  chmod +x "${TEST_BIN}/npx"
}

teardown() {
  teardown_test_env
}

@test "pstack user profile installs all nine local skills for both agents without external tools" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    "$(setup_script_path)" skills --scope user --profile pstack

  [ "$status" -eq 0 ]
  [ -L "${TEST_HOME}/.agents/skills" ]
  [ -L "${TEST_HOME}/.claude/skills" ]
  [ "$(readlink "${TEST_HOME}/.agents/skills")" = "${TEST_DOTFILES}/.agents/user/skills" ]
  [ "$(readlink "${TEST_HOME}/.claude/skills")" = "${TEST_DOTFILES}/.agents/user/skills" ]
  [ ! -e "${TEST_DOTFILES}/skills-lock.json" ]

  run node - "${TEST_DOTFILES}" "${TEST_HOME}" <<'JS'
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const [root, homeDir] = process.argv.slice(2);
const expected = [
  "architect", "arena", "blast-radius", "create-verification-skill",
  "encode-lessons-in-structure", "how", "interrogate", "prove-it-works", "why",
];
const explicitOnly = new Set([
  "arena", "blast-radius", "create-verification-skill", "interrogate",
]);
const metadata = JSON.parse(fs.readFileSync(path.join(root, ".agents/user/skills-profile.json")));
assert.deepEqual(metadata.localSkills, expected);
assert.deepEqual(metadata.external, []);
assert.deepEqual(metadata.requestedProfiles, ["pstack"]);
for (const agentDir of [".agents", ".claude"]) {
  for (const name of expected) {
    const installed = path.join(homeDir, agentDir, "skills", name);
    assert.equal(fs.realpathSync(installed), path.join(root, "skills/local", name));
    assert.ok(fs.statSync(path.join(installed, "LICENSE")).isFile());
    const entry = fs.readFileSync(path.join(installed, "SKILL.md"), "utf8");
    const frontmatter = entry.match(/^---\n([\s\S]*?)\n---/)[1];
    const agentConfig = fs.readFileSync(path.join(installed, "agents/openai.yaml"), "utf8");
    assert.equal(
      /^disable-model-invocation: true$/m.test(frontmatter),
      explicitOnly.has(name),
      `${agentDir}/${name}: Claude explicit-only policy`,
    );
    assert.equal(
      /^policy:\n  allow_implicit_invocation: false$/m.test(agentConfig),
      explicitOnly.has(name),
      `${agentDir}/${name}: Codex explicit-only policy`,
    );
    for (const match of entry.matchAll(/\]\(([^)]+)\)/g)) {
      if (/^https?:/.test(match[1])) continue;
      assert.ok(fs.existsSync(path.resolve(installed, match[1])), match[1]);
    }
  }
}
JS
  [ "$status" -eq 0 ]
}

@test "pstack project install preserves existing tdd teach and external lockfile" {
  git -C "${TEST_PROJECT}" init -q
  mkdir -p "${TEST_PROJECT}/.agents/skills/tdd" "${TEST_PROJECT}/.claude/skills/teach"
  printf 'existing tdd\n' > "${TEST_PROJECT}/.agents/skills/tdd/SKILL.md"
  printf 'existing teach\n' > "${TEST_PROJECT}/.claude/skills/teach/SKILL.md"
  printf '{"existing":"lock"}\n' > "${TEST_PROJECT}/skills-lock.json"
  cd "${TEST_PROJECT}"

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    "$(setup_script_path)" skills --scope project --profile pstack

  [ "$status" -eq 0 ]
  [ "$(cat .agents/skills/tdd/SKILL.md)" = "existing tdd" ]
  [ "$(cat .claude/skills/teach/SKILL.md)" = "existing teach" ]
  [ "$(cat skills-lock.json)" = '{"existing":"lock"}' ]
  for agent_dir in .agents .claude; do
    for skill in architect arena blast-radius create-verification-skill \
      encode-lessons-in-structure how interrogate prove-it-works why; do
      [ -L "${agent_dir}/skills/${skill}" ]
      [ -f "${agent_dir}/skills/${skill}/SKILL.md" ]
    done
  done
}

@test "pstack composes with base and github without entering either default profile" {
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    "$(setup_script_path)" skills profile validate --profile base,github,pstack

  [ "$status" -eq 0 ]
  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DOTFILES_ROOT="${TEST_DOTFILES}" \
    PATH="${TEST_BIN}:${PATH}" \
    SETUP_DRY_RUN=1 \
    "$(setup_script_path)" skills --scope user --profile base,github

  [ "$status" -eq 0 ]
  [[ "$output" != *"/skills/arena"* ]]
  [[ "$output" != *"/skills/interrogate"* ]]
  [ ! -e "${TEST_HOME}/.agents/skills" ]
}
