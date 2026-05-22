#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "tmux does not enable C-b as a global secondary prefix" {
  run grep -Eq '^set[[:space:]]+-g[[:space:]]+prefix2[[:space:]]+C-b([[:space:]]|$)' "$(repo_root)/.tmux.conf"

  [ "$status" -ne 0 ]
}

@test "tmux-palette opens direct tools from PATH without relaunching palette" {
  run node -e '
const fs = require("fs");
const items = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const byTitle = new Map(items.map((item) => [item.title, item]));

if (byTitle.has("Tools...")) {
  throw new Error("Tools submenu should not be required for direct tools");
}

for (const title of ["gitui", "lazygit", "btop", "lazydocker", "oxker"]) {
  const item = byTitle.get(title);
  if (!item) throw new Error(`${title} is missing from commands.json`);
  if (item.action && Object.prototype.hasOwnProperty.call(item.action, "popup")) {
    throw new Error(`${title} should not use popup action because it relaunches the palette`);
  }
  if (!item.action || typeof item.action.tmux !== "string") {
    throw new Error(`${title} does not open with a tmux action`);
  }
  if (!item.action.tmux.includes("display-popup")) {
    throw new Error(`${title} does not open a tmux popup`);
  }
  if (item.action.tmux.includes("mise exec")) {
    throw new Error(`${title} should launch from PATH instead of mise exec`);
  }
  if (!new RegExp(`(^|\\s)${title}($|\\s)`).test(item.action.tmux)) {
    throw new Error(`${title} action does not call ${title}`);
  }
}
' "$(repo_root)/tmux/tmux-palette/commands.json"

  [ "$status" -eq 0 ]
}

@test "tmux-palette provides github and container dynamic palettes" {
  run node -e '
const fs = require("fs");
const path = require("path");
const root = process.argv[1];
const commands = JSON.parse(fs.readFileSync(path.join(root, "commands.json"), "utf8"));
const byTitle = new Map(commands.map((item) => [item.title, item]));

for (const [title, paletteName] of [
  ["GitHub PRs", "github-prs"],
  ["GitHub Issues", "github-issues"],
  ["Container Logs", "container-logs"],
]) {
  const item = byTitle.get(title);
  if (!item) throw new Error(`${title} is missing from commands.json`);
  if (!item.action || item.action.palette !== paletteName) {
    throw new Error(`${title} should open ${paletteName} palette`);
  }
  const palettePath = path.join(root, "palettes", `${paletteName}.json`);
  const palette = JSON.parse(fs.readFileSync(palettePath, "utf8"));
  if (!palette.command) throw new Error(`${paletteName} palette is missing command`);
  if (paletteName === "container-logs" && !palette.action) {
    throw new Error(`${paletteName} palette is missing action`);
  }
}

const prs = JSON.parse(fs.readFileSync(path.join(root, "palettes/github-prs.json"), "utf8"));
if (!prs.command.includes("gh pr list")) throw new Error("github-prs should list PRs through gh");
if (!prs.command.includes("gh pr view")) throw new Error("github-prs should view PRs through gh");

const issues = JSON.parse(fs.readFileSync(path.join(root, "palettes/github-issues.json"), "utf8"));
if (!issues.command.includes("gh issue list")) throw new Error("github-issues should list issues through gh");
if (!issues.command.includes("gh issue view")) throw new Error("github-issues should view issues through gh");

const logs = JSON.parse(fs.readFileSync(path.join(root, "palettes/container-logs.json"), "utf8"));
if (!logs.command.includes("docker ps")) throw new Error("container-logs should list containers through docker");
if (!JSON.stringify(logs.action).includes("docker logs -f")) throw new Error("container-logs should follow logs through docker");
' "$(repo_root)/tmux/tmux-palette"

  [ "$status" -eq 0 ]
}

@test "github palettes resolve the active tmux pane git root before running gh" {
  local fake_bin="${BATS_TEST_TMPDIR}/bin"
  local pane_repo="${BATS_TEST_TMPDIR}/pane/repo"
  local log_file="${BATS_TEST_TMPDIR}/gh.log"
  mkdir -p "${fake_bin}" "${pane_repo}"

  cat > "${fake_bin}/tmux" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "display-message" ]; then
  printf '%s\n' "${pane_repo}"
  exit 0
fi
exit 1
EOF
  chmod +x "${fake_bin}/tmux"

  cat > "${fake_bin}/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "-C" ] && [ "\$2" = "${pane_repo}" ] && [ "\$3" = "rev-parse" ]; then
  printf '%s\n' "${pane_repo}"
  exit 0
fi
exit 1
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\t%s\n' "${PWD}" "$*" >> "${GH_LOG}"
printf '[]\n'
EOF
  chmod +x "${fake_bin}/gh"

  local pr_command
  pr_command="$(node -e 'const fs = require("fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).command)' "$(repo_root)/tmux/tmux-palette/palettes/github-prs.json")"
  run env PATH="${fake_bin}:/usr/bin:/bin" GH_LOG="${log_file}" sh -c "${pr_command}"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  run grep -F "${pane_repo}"$'\t'"pr list" "${log_file}"
  [ "$status" -eq 0 ]

  : > "${log_file}"
  local issue_command
  issue_command="$(node -e 'const fs = require("fs"); console.log(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).command)' "$(repo_root)/tmux/tmux-palette/palettes/github-issues.json")"
  run env PATH="${fake_bin}:/usr/bin:/bin" GH_LOG="${log_file}" sh -c "${issue_command}"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
  run grep -F "${pane_repo}"$'\t'"issue list" "${log_file}"
  [ "$status" -eq 0 ]
}
