#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "tmux does not enable C-b as a global secondary prefix" {
  run grep -Eq '^set[[:space:]]+-g[[:space:]]+prefix2[[:space:]]+C-b([[:space:]]|$)' "$(repo_root)/.tmux.conf"

  [ "$status" -ne 0 ]
}

@test "tmux passes terminal identity through for yazi" {
  run grep -Eq '^set[[:space:]]+-gq?[[:space:]]+allow-passthrough[[:space:]]+on([[:space:]]|$)' "$(repo_root)/.tmux.conf"
  [ "$status" -eq 0 ]

  run grep -Eq '^set[[:space:]]+-ga[[:space:]]+update-environment[[:space:]]+TERM([[:space:]]|$)' "$(repo_root)/.tmux.conf"
  [ "$status" -eq 0 ]

  run grep -Eq '^set[[:space:]]+-ga[[:space:]]+update-environment[[:space:]]+TERM_PROGRAM([[:space:]]|$)' "$(repo_root)/.tmux.conf"
  [ "$status" -eq 0 ]
}

@test "tmux-palette opens direct tools from PATH without relaunching palette" {
  run node -e '
const fs = require("fs");
const items = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const byTitle = new Map(items.map((item) => [item.title, item]));

if (byTitle.has("Tools...")) {
  throw new Error("Tools submenu should not be required for direct tools");
}

for (const [title, commandPattern] of [
  ["gitui", /(^|\s)gitui($|\s)/],
  ["lazygit", /(^|\s)lazygit($|\s)/],
  ["btop", /(^|\s)btop($|\s)/],
  ["nvtop", /(^|\s)nvtop($|\s)/],
  ["nvitop", /(^|\s)nvitop --readonly($|\s)/],
  ["bandwhich", /(^|[\s/])network-bandwidth($|\s)/],
  ["Trippy", /(^|[\s/])network-trace($|\s)/],
  ["termshark", /(^|[\s/])network-packets($|\s)/],
  ["lazydocker", /(^|\s)lazydocker($|\s)/],
  ["oxker", /(^|\s)oxker($|\s)/],
  ["yazi", /(^|[\s/])yazi-popup($|\s)/],
  ["gh-dash", /(^|\s)gh-dash($|\s)/],
  ["mprocs", /(^|\s)mprocs($|\s)/],
  ["Find Files", /(^|[\s/])find-files($|\s)/],
  ["Jump Directory", /(^|[\s/])jump-directory($|\s)/],
  ["Command History", /(^|\s)atuin search -i($|\s)/],
  ["Git Diff", /(^|[\s/])git-diff($|\s)/],
  ["Project Commands", /(^|[\s/])project-command($|\s)/],
  ["Watch Command", /(^|[\s/])watch-command($|\s)/],
  ["Project Services", /(^|[\s/])project-services($|\s)/],
  ["Background Jobs", /(^|[\s/])background-jobs($|\s)/],
  ["Disk Free", /(^|[\s/])disk-free($|\s)/],
  ["Disk Usage", /(^|\s)gdu \.($|\s)/],
  ["Disk Usage Home", /(^|\s)gdu ~($|\s)/],
  ["Disk Cleanup", /(^|\s)dua interactive \.($|\s)/],
  ["Disk Tree", /(^|[\s/])disk-tree($|\s)/],
  ["Database Client", /(^|\s)lazysql($|\s)/],
  ["SQL IDE", /(^|\s)harlequin($|\s)/],
  ["Markdown Viewer", /(^|\s)glow($|\s)/],
  ["Posting", /(^|\s)posting($|\s)/],
  ["Resterm", /(^|\s)resterm($|\s)/],
]) {
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
  if (!commandPattern.test(item.action.tmux)) {
    throw new Error(`${title} action does not call the expected executable`);
  }
}
' "$(repo_root)/tmux/tmux-palette/commands.json"

  [ "$status" -eq 0 ]
}

@test "tmux network wrappers keep privilege failures visible" {
  local root fake_bin log_file
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/network.log"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/bandwhich" <<'EOF'
#!/usr/bin/env bash
printf 'bandwhich should run through sudo\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/bandwhich"

  cat > "${fake_bin}/trip" <<'EOF'
#!/usr/bin/env bash
printf 'trip should run through sudo\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/trip"

  cat > "${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "${LOG_FILE}"
printf 'sudo failed\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/sudo"

  cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Linux\n'
EOF
  chmod +x "${fake_bin}/uname"

  run env PATH="${fake_bin}:/usr/bin:/bin" LOG_FILE="${log_file}" bash -c "printf '\n' | '${root}/tmux/bin/network-bandwidth'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bandwhich requires network capture privileges"* ]]
  [[ "$output" == *"sudo failed"* ]]
  [[ "$output" == *"Press Enter to close..."* ]]
  run grep -F "sudo ${fake_bin}/bandwhich" "${log_file}"
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:/usr/bin:/bin" LOG_FILE="${log_file}" bash -c "printf '\n' | '${root}/tmux/bin/network-trace'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trippy requires network tracing privileges"* ]]
  [[ "$output" == *"sudo failed"* ]]
  [[ "$output" == *"Press Enter to close..."* ]]
  run grep -F "sudo ${fake_bin}/trip 1.1.1.1" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "tmux network packet wrapper explains macOS ChmodBPF setup" {
  local root fake_bin log_file
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/packets.log"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/termshark" <<'EOF'
#!/usr/bin/env bash
printf 'termshark %s\n' "$*" >> "${LOG_FILE}"
printf 'capture permission denied\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/termshark"

  cat > "${fake_bin}/tshark" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/tshark"

  cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
  chmod +x "${fake_bin}/uname"

  run env PATH="${fake_bin}:/usr/bin:/bin" LOG_FILE="${log_file}" bash -c "printf '\n' | '${root}/tmux/bin/network-packets'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"capture permission denied"* ]]
  [[ "$output" == *"brew install --cask wireshark-chmodbpf"* ]]
  [[ "$output" == *"Press Enter to close..."* ]]
  run grep -F "termshark " "${log_file}"
  [ "$status" -eq 0 ]
}

@test "tmux network wrappers use macOS-specific privilege guidance" {
  local root fake_bin
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/bandwhich" <<'EOF'
#!/usr/bin/env bash
printf 'capture permission denied\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/bandwhich"

  cat > "${fake_bin}/trip" <<'EOF'
#!/usr/bin/env bash
printf 'privileges are required\n' >&2
exit 1
EOF
  chmod +x "${fake_bin}/trip"

  cat > "${fake_bin}/sudo" <<'EOF'
#!/usr/bin/env bash
shift 0
"$@"
EOF
  chmod +x "${fake_bin}/sudo"

  cat > "${fake_bin}/uname" <<'EOF'
#!/usr/bin/env bash
printf 'Darwin\n'
EOF
  chmod +x "${fake_bin}/uname"

  run env PATH="${fake_bin}:/usr/bin:/bin" bash -c "printf '\n' | '${root}/tmux/bin/network-bandwidth'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"brew install --cask wireshark-chmodbpf"* ]]
  [[ "$output" != *"setcap"* ]]

  run env PATH="${fake_bin}:/usr/bin:/bin" bash -c "printf '\n' | '${root}/tmux/bin/network-trace'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS does not support Linux setcap"* ]]
  [[ "$output" != *"setcap cap_net_raw"* ]]
}

@test "tmux disk wrappers keep one-shot disk output visible" {
  local root fake_bin log_file
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/disk.log"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/duf" <<'EOF'
#!/usr/bin/env bash
printf 'duf %s\n' "$*" >> "${LOG_FILE}"
printf 'duf output\n'
EOF
  chmod +x "${fake_bin}/duf"

  cat > "${fake_bin}/dust" <<'EOF'
#!/usr/bin/env bash
printf 'dust %s\n' "$*" >> "${LOG_FILE}"
printf 'dust output\n'
EOF
  chmod +x "${fake_bin}/dust"

  run env PATH="${fake_bin}:/usr/bin:/bin" LOG_FILE="${log_file}" bash -c "printf '\n' | '${root}/tmux/bin/disk-free'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"duf output"* ]]
  [[ "$output" == *"Press Enter to close..."* ]]
  run grep -F "duf " "${log_file}"
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:/usr/bin:/bin" LOG_FILE="${log_file}" bash -c "printf '\n' | '${root}/tmux/bin/disk-tree'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dust output"* ]]
  [[ "$output" == *"Press Enter to close..."* ]]
  run grep -F "dust ." "${log_file}"
  [ "$status" -eq 0 ]
}

@test "tmux project command wrappers discover commands and run selected actions" {
  local root fake_bin log_file project_dir
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/commands.log"
  project_dir="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${fake_bin}" "${project_dir}/tests"
  touch "${project_dir}/app.py" "${project_dir}/compose.yml"
  printf '{}\n' > "${project_dir}/package.json"
  printf 'build:\n\t@true\n' > "${project_dir}/Makefile"
  printf '[project]\nname = "demo"\n' > "${project_dir}/pyproject.toml"
  printf 'default:\n\ttrue\n' > "${project_dir}/justfile"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "tasks" ] && [ "$2" = "ls" ]; then
  printf 'setup    bootstrap project\n'
fi
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/just" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--summary" ]; then
  printf 'serve lint\n'
fi
EOF
  chmod +x "${fake_bin}/just"

  cat > "${fake_bin}/make" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-qp"* ]]; then
  printf 'build:\n'
  printf 'test:\n'
fi
EOF
  chmod +x "${fake_bin}/make"

  cat > "${fake_bin}/node" <<'EOF'
#!/usr/bin/env bash
printf 'build\nstart\n'
EOF
  chmod +x "${fake_bin}/node"

  cat > "${fake_bin}/streamlit" <<'EOF'
#!/usr/bin/env bash
printf 'streamlit %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/streamlit"

  cat > "${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/docker"

  cat > "${fake_bin}/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/npm"

  cat > "${fake_bin}/fzf" <<'EOF'
#!/usr/bin/env bash
cat > "${FZF_INPUT}"
case "${FZF_CHOICE}" in
  watch)
    printf 'make build\tmake build\n'
    ;;
  *)
    printf 'npm build\tnpm run build\n'
    ;;
esac
EOF
  chmod +x "${fake_bin}/fzf"

  cat > "${fake_bin}/watchexec" <<'EOF'
#!/usr/bin/env bash
printf 'watchexec %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/watchexec"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    FZF_INPUT="${BATS_TEST_TMPDIR}/project-command-items" \
    bash -c "cd '${project_dir}' && printf '\n' | '${root}/tmux/bin/project-command'"
  [ "$status" -eq 0 ]
  run grep -F $'mise setup\tmise run setup' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F $'just serve\tjust serve' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F $'make build\tmake build' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F $'npm build\tnpm run build' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F $'python pytest\tpython -m pytest' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F $'streamlit app.py\tstreamlit run app.py' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F $'docker compose up -d\tdocker compose up -d' "${BATS_TEST_TMPDIR}/project-command-items"
  [ "$status" -eq 0 ]
  run grep -F "npm run build" "${log_file}"
  [ "$status" -eq 0 ]

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    FZF_INPUT="${BATS_TEST_TMPDIR}/watch-command-items" \
    FZF_CHOICE=watch \
    bash -c "cd '${project_dir}' && '${root}/tmux/bin/watch-command'"
  [ "$status" -eq 0 ]
  run grep -F "watchexec --clear --restart -- make build" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "tmux project service and background job wrappers manage long-running commands" {
  local root fake_bin log_file project_dir
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/services.log"
  project_dir="${BATS_TEST_TMPDIR}/project"
  mkdir -p "${fake_bin}" "${project_dir}"
  printf 'version: "0.5"\nprocesses: {}\n' > "${project_dir}/process-compose.yaml"

  cat > "${fake_bin}/process-compose" <<'EOF'
#!/usr/bin/env bash
printf 'process-compose %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/process-compose"

  cat > "${fake_bin}/fzf" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'Add Command\n'
EOF
  chmod +x "${fake_bin}/fzf"

  cat > "${fake_bin}/pueue" <<'EOF'
#!/usr/bin/env bash
printf 'pueue %s\n' "$*" >> "${LOG_FILE}"
if [ "$1" = "status" ] && [ ! -f "${PUEUE_READY}" ]; then
  exit 1
fi
EOF
  chmod +x "${fake_bin}/pueue"

  cat > "${fake_bin}/pueued" <<'EOF'
#!/usr/bin/env bash
printf 'pueued %s\n' "$*" >> "${LOG_FILE}"
touch "${PUEUE_READY}"
EOF
  chmod +x "${fake_bin}/pueued"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    bash -c "cd '${project_dir}' && '${root}/tmux/bin/project-services'"
  [ "$status" -eq 0 ]
  run grep -F "process-compose up" "${log_file}"
  [ "$status" -eq 0 ]

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    PUEUE_READY="${BATS_TEST_TMPDIR}/pueue-ready" \
    bash -c "printf 'npm run dev\n\n' | '${root}/tmux/bin/background-jobs'"
  [ "$status" -eq 0 ]
  run grep -F "pueued -d" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "pueue add -- npm run dev" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "zsh initializes zoxide and atuin when installed" {
  run grep -F 'zoxide init zsh' "$(repo_root)/zsh/mise.zsh"
  [ "$status" -eq 0 ]

  run grep -F 'atuin init zsh --disable-up-arrow --disable-ai' "$(repo_root)/zsh/mise.zsh"
  [ "$status" -eq 0 ]
}

@test "zsh mise activation refreshes tmux server PATH" {
  local root fake_home fake_bin log_file
  root="$(repo_root)"
  fake_home="${BATS_TEST_TMPDIR}/home"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/tmux.log"
  mkdir -p "${fake_home}/.local/bin" "${fake_bin}"
  ln -s "${root}" "${fake_home}/.dotfiles"

  cat > "${fake_home}/.local/bin/mise" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "activate" ]; then
  printf 'export PATH="/mise/bin:$PATH"\n'
fi
EOF
  chmod +x "${fake_home}/.local/bin/mise"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TMUX_LOG}"
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    HOME="${fake_home}" \
    PATH="${fake_bin}:/usr/bin:/bin" \
    TMUX="/tmp/tmux-test/default,1,0" \
    TMUX_LOG="${log_file}" \
    zsh -c "source '${root}/zsh/mise.zsh'"

  [ "$status" -eq 0 ]
  run grep -F "set-environment -g PATH /mise/bin:${fake_bin}:/usr/bin:/bin" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "yazi popup wrapper filters terminal response timeout warning only" {
  local root fake_bin
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/yazi" <<'EOF'
#!/usr/bin/env bash
{
  printf '\033[38;5;9m\033[1m\r\nTerminal response timeout: \033[0m\033[0mThe request sent by Yazi did not receive a correct response.\n'
  printf 'Please check your terminal environment as per: https://yazi-rs.github.io/docs/faq#trt\n'
  printf 'real yazi error\n'
} >&2
EOF
  chmod +x "${fake_bin}/yazi"

  run env PATH="${fake_bin}:/usr/bin:/bin" "${root}/tmux/bin/yazi-popup"

  [ "$status" -eq 0 ]
  [[ "$output" != *"Terminal response timeout"* ]]
  [[ "$output" != *"The request sent by Yazi"* ]]
  [[ "$output" != *"Please check your terminal environment"* ]]
  [[ "$output" == *"real yazi error"* ]]
}

@test "tmux utility wrappers compose fd bat zoxide fzf and delta" {
  local root fake_bin log_file selected_dir selected_file
  root="$(repo_root)"
  fake_bin="${BATS_TEST_TMPDIR}/bin"
  log_file="${BATS_TEST_TMPDIR}/commands.log"
  selected_dir="${BATS_TEST_TMPDIR}/project"
  selected_file="src/main.rs"
  mkdir -p "${fake_bin}" "${selected_dir}"

  cat > "${fake_bin}/fd" <<EOF
#!/usr/bin/env bash
printf 'fd %s\n' "\$*" >> "${log_file}"
printf '%s\n' "${selected_file}"
EOF
  chmod +x "${fake_bin}/fd"

  cat > "${fake_bin}/fzf" <<EOF
#!/usr/bin/env bash
printf 'fzf %s\n' "\$*" >> "${log_file}"
cat >/dev/null
if [[ "\$*" == *"zoxide"* ]]; then
  printf '%s\n' "${selected_dir}"
else
  printf '%s\n' "${selected_file}"
fi
EOF
  chmod +x "${fake_bin}/fzf"

  cat > "${fake_bin}/vim" <<'EOF'
#!/usr/bin/env bash
printf 'editor %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/vim"

  cat > "${fake_bin}/zoxide" <<EOF
#!/usr/bin/env bash
printf 'zoxide %s\n' "\$*" >> "${log_file}"
printf '%s\n' "${selected_dir}"
EOF
  chmod +x "${fake_bin}/zoxide"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "${LOG_FILE}"
EOF
  chmod +x "${fake_bin}/tmux"

  cat > "${fake_bin}/git" <<EOF
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >> "${log_file}"
case "\$*" in
  *"rev-parse --show-toplevel"*)
    printf '%s\n' "${selected_dir}"
    ;;
  *"diff --quiet --exit-code -- ."*)
    exit 1
    ;;
  *"core.pager=delta diff -- ."*)
    printf 'diff output\n'
    ;;
esac
EOF
  chmod +x "${fake_bin}/git"

  run env PATH="${fake_bin}:/usr/bin:/bin" EDITOR=vim LOG_FILE="${log_file}" "${root}/tmux/bin/find-files"
  [ "$status" -eq 0 ]
  run grep -F "fd --type f --hidden --follow --exclude .git ." "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "bat --style=numbers --color=always --line-range :200 {}" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "editor ${selected_file}" "${log_file}"
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:/usr/bin:/bin" LOG_FILE="${log_file}" "${root}/tmux/bin/jump-directory"
  [ "$status" -eq 0 ]
  run grep -F "zoxide query -l" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "tmux new-window -c ${selected_dir}" "${log_file}"
  [ "$status" -eq 0 ]

  run env PATH="${fake_bin}:/usr/bin:/bin" "${root}/tmux/bin/git-diff"
  [ "$status" -eq 0 ]
  run grep -F "git -C" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "git -c core.pager=delta diff -- ." "${log_file}"
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
