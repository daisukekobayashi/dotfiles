#!/usr/bin/env bats

load 'helpers/test_helper.bash'

require_pwsh() {
  PWSH="$(command -v pwsh || true)"
  if [ -z "${PWSH}" ]; then
    skip "pwsh is not installed (mise installs powershell on Linux, WSL, and macOS)"
  fi
}

@test "tracked PowerShell scripts parse without errors" {
  require_pwsh

  run "${PWSH}" -NoProfile -NonInteractive -File "${BATS_TEST_DIRNAME}/helpers/check_powershell_syntax.ps1" "$(repo_root)"

  [ "$status" -eq 0 ]
  [[ "$output" == *"with 0 error(s)."* ]]
}

@test "Windows setup tests pass, skipping Windows-only cases elsewhere" {
  require_pwsh

  run "${PWSH}" -NoProfile -NonInteractive -File "$(repo_root)/tests/setup_windows.ps1"

  [ "$status" -eq 0 ]
  [[ "$output" != *"not ok"* ]]
}
