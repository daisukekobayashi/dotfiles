#!/usr/bin/env bats

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
}

teardown() {
  teardown_test_env
}

@test "post step seeds tmux plugin manager path before plugin install" {
  touch "${TEST_HOME}/.tmux.conf"

  run env \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    SETUP_DRY_RUN=1 \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY-RUN tmux start-server"* ]]
  [[ "$output" == *"DRY-RUN tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH ${TEST_HOME}/.tmux/plugins/"* ]]
  [[ "$output" == *"DRY-RUN ${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"* ]]
  [[ "$output" == *"DRY-RUN tmux source-file ${TEST_HOME}/.tmux.conf"* ]]
}

@test "post step does not create a tmux session when sessions already exist" {
  local fake_bin="${TEST_ROOT}/bin"
  local log_file="${TEST_ROOT}/commands.log"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
printf 'install_plugins\n' >> "${LOG_FILE}"
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "config ls --no-header -E linux")
    exit 0
    ;;
esac
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "${LOG_FILE}"
case "$*" in
  "list-sessions")
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  run grep -F "tmux list-sessions" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "tmux new-session" "${log_file}"
  [ "$status" -ne 0 ]
  run grep -F "install_plugins" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "post step cleans up a named tmux bootstrap session when no sessions exist" {
  local fake_bin="${TEST_ROOT}/bin"
  local log_file="${TEST_ROOT}/commands.log"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
printf 'install_plugins\n' >> "${LOG_FILE}"
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "config ls --no-header -E linux")
    exit 0
    ;;
esac
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "${LOG_FILE}"
case "$*" in
  "list-sessions")
    exit 1
    ;;
esac
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  run grep -F "tmux list-sessions" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "tmux new-session -d -s dotfiles-tpm-bootstrap-" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "install_plugins" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "tmux kill-session -t dotfiles-tpm-bootstrap-" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "post step cleans up the tmux bootstrap session when plugin install fails" {
  local fake_bin="${TEST_ROOT}/bin"
  local log_file="${TEST_ROOT}/commands.log"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
printf 'install_plugins\n' >> "${LOG_FILE}"
exit 7
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "config ls --no-header -E linux")
    exit 0
    ;;
esac
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "${LOG_FILE}"
case "$*" in
  "list-sessions")
    exit 1
    ;;
esac
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 7 ]
  run grep -F "tmux new-session -d -s dotfiles-tpm-bootstrap-" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "install_plugins" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "tmux kill-session -t dotfiles-tpm-bootstrap-" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "post step continues when a mise tool install fails by default" {
  local fake_bin="${TEST_ROOT}/bin"
  local log_file="${TEST_ROOT}/commands.log"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'mise %s\n' "$*" >> "${LOG_FILE}"
case "$*" in
  "config ls --no-header -E linux")
    cat <<'OUT'
/fake/config.toml        python, node
/fake/config.linux.toml  azure
OUT
    ;;
  *)
    if [[ "$1" == "install" ]]; then
      tool="${!#}"
      if [[ "${tool}" == "azure" ]]; then
        exit 1
      fi
    fi
    ;;
esac
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "${LOG_FILE}"
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing mise tool: python"* ]]
  [[ "$output" == *"Installing mise tool: node"* ]]
  [[ "$output" == *"Installing mise tool: azure"* ]]
  [[ "$output" == *"Failed to install mise tool: azure"* ]]
  [[ "$output" == *"Continuing despite failed mise tool installs: azure"* ]]
  run grep -F "tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH ${TEST_HOME}/.tmux/plugins/" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "post step fails in strict mode when a mise tool install fails" {
  local fake_bin="${TEST_ROOT}/bin"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
set -eu
case "$*" in
  "config ls --no-header -E linux")
    cat <<'OUT'
/fake/config.toml        python, azure
OUT
    ;;
  *)
    if [[ "$1" == "install" && "${!#}" == "azure" ]]; then
      exit 1
    fi
    ;;
esac
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    SETUP_MISE_STRICT=1 \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install mise tool: azure"* ]]
  [[ "$output" == *"mise tool installs failed: azure"* ]]
}

@test "post step uses wsl mise env when running under WSL" {
  local fake_bin="${TEST_ROOT}/bin"
  local log_file="${TEST_ROOT}/commands.log"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/mise" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'mise %s\n' "$*" >> "${LOG_FILE}"
case "$*" in
  "config ls --no-header -E wsl")
    cat <<'OUT'
/fake/config.toml      python
/fake/config.wsl.toml  terraform
OUT
    ;;
  *)
    ;;
esac
EOF
  chmod +x "${fake_bin}/mise"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    WSL_DISTRO_NAME="Debian" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  run grep -F "mise config ls --no-header -E wsl" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "mise install -E wsl terraform" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "post step installs uv-managed cli tools" {
  local fake_bin="${TEST_ROOT}/bin"
  local log_file="${TEST_ROOT}/commands.log"
  mkdir -p "${fake_bin}" "${TEST_HOME}/.tmux/plugins/tpm/scripts" "${TEST_HOME}/.vim/autoload" \
    "${TEST_HOME}/.mintty" "${TEST_HOME}/.solarized-mate-terminal"
  : > "${TEST_HOME}/.vim/autoload/plug.vim"

  cat > "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"

  cat > "${fake_bin}/uv" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'uv %s\n' "$*" >> "${LOG_FILE}"
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then
  exit 0
fi
exit 0
EOF
  chmod +x "${fake_bin}/uv"

  cat > "${fake_bin}/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/git"

  cat > "${fake_bin}/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/curl"

  cat > "${fake_bin}/tmux" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${fake_bin}/tmux"

  run env \
    PATH="${fake_bin}:/usr/bin:/bin" \
    LOG_FILE="${log_file}" \
    SETUP_HOME="${TEST_HOME}" \
    SETUP_TMPDIR="${TEST_TMP}" \
    "$(setup_script_path)" \
    post

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing uv tool: posting"* ]]
  [[ "$output" == *"Installing uv tool: nvitop"* ]]
  run grep -F "uv tool list" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "uv tool install --python 3.13 posting" "${log_file}"
  [ "$status" -eq 0 ]
  run grep -F "uv tool install --python 3.13 nvitop" "${log_file}"
  [ "$status" -eq 0 ]
}

@test "linux and wsl mise configs install btop through github backend" {
  run grep -F 'btop = "1.4"' "$(repo_root)/mise/config.linux.toml" "$(repo_root)/mise/config.wsl.toml"
  [ "$status" -ne 0 ]

  run grep -F '"github:aristocratos/btop" = "1.4"' "$(repo_root)/mise/config.linux.toml"
  [ "$status" -eq 0 ]

  run grep -F '"github:aristocratos/btop" = "1.4"' "$(repo_root)/mise/config.wsl.toml"
  [ "$status" -eq 0 ]
}
