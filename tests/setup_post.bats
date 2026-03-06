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
  [[ "$output" == *"DRY-RUN tmux new-session -d"* ]]
  [[ "$output" == *"DRY-RUN ${TEST_HOME}/.tmux/plugins/tpm/scripts/install_plugins.sh"* ]]
  [[ "$output" == *"DRY-RUN tmux source-file ${TEST_HOME}/.tmux.conf"* ]]
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
