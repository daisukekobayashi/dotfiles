#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'
load 'helpers/mock_env.bash'

setup() {
  setup_test_env
  ROOT="$(repo_root)"
  FAKE_BIN="${TEST_ROOT}/bin"
  CODEX_LOG="${TEST_ROOT}/codex.log"
  CODEX_DEBUG_LOG="${TEST_ROOT}/codex-debug.log"
  FZF_CHOICES="${TEST_ROOT}/fzf-choices"

  mkdir -p "${FAKE_BIN}"
  ln -s "$(command -v jq)" "${FAKE_BIN}/jq"
  write_fake_codex
  write_fake_fzf
}

teardown() {
  teardown_test_env
}

catalog_json() {
  cat <<'JSON'
{"models":[
  {"slug":"gpt-5.6-sol","display_name":"GPT-5.6-Sol","visibility":"list","default_reasoning_level":"low","supported_reasoning_levels":[
    {"effort":"low","description":"Fast responses"},
    {"effort":"medium","description":"Balanced"},
    {"effort":"high","description":"Greater depth"},
    {"effort":"xhigh","description":"Extra high depth"},
    {"effort":"max","description":"Maximum depth"},
    {"effort":"ultra","description":"Automatic delegation"}
  ]},
  {"slug":"gpt-5.6-terra","display_name":"GPT-5.6-Terra","visibility":"list","default_reasoning_level":"medium","supported_reasoning_levels":[
    {"effort":"low","description":"Fast responses"},
    {"effort":"medium","description":"Balanced"},
    {"effort":"high","description":"Greater depth"},
    {"effort":"xhigh","description":"Extra high depth"},
    {"effort":"max","description":"Maximum depth"},
    {"effort":"ultra","description":"Automatic delegation"}
  ]},
  {"slug":"gpt-5.6-luna","display_name":"GPT-5.6-Luna","visibility":"list","default_reasoning_level":"medium","supported_reasoning_levels":[
    {"effort":"low","description":"Fast responses"},
    {"effort":"medium","description":"Balanced"},
    {"effort":"high","description":"Greater depth"},
    {"effort":"xhigh","description":"Extra high depth"},
    {"effort":"max","description":"Maximum depth"}
  ]},
  {"slug":"codex-auto-review","display_name":"Codex Auto Review","visibility":"hide","default_reasoning_level":"medium","supported_reasoning_levels":[
    {"effort":"medium","description":"Balanced"}
  ]}
]}
JSON
}

ambiguous_catalog_json() {
  catalog_json | jq '.models += [{
    "slug": "gpt-6-terra",
    "display_name": "GPT-6-Terra",
    "visibility": "list",
    "default_reasoning_level": "medium",
    "supported_reasoning_levels": [{"effort": "medium", "description": "Balanced"}]
  }]'
}

write_fake_codex() {
  cat > "${FAKE_BIN}/codex" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "debug" && "${2:-}" == "models" ]]; then
  {
    printf 'argv='
    printf '<%s>' "$@"
    printf '\n'
  } >> "${CODEX_DEBUG_LOG}"

  if [[ "${3:-}" == "--bundled" ]]; then
    printf '%s\n' "${CODEX_BUNDLED_CATALOG:-${CODEX_CATALOG}}"
    exit 0
  fi

  if [[ "${CODEX_LIVE_FAIL:-0}" == "1" ]]; then
    exit 70
  fi

  printf '%s\n' "${CODEX_CATALOG}"
  exit 0
fi

{
  printf 'argv='
  printf '<%s>' "$@"
  printf '\n'
} > "${CODEX_LOG}"
BASH
  chmod +x "${FAKE_BIN}/codex"
}

write_fake_fzf() {
  cat > "${FAKE_BIN}/fzf" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

mapfile -t rows
IFS= read -r choice < "${FZF_CHOICES}"
tail -n +2 "${FZF_CHOICES}" > "${FZF_CHOICES}.next"
mv "${FZF_CHOICES}.next" "${FZF_CHOICES}"

if [[ "${choice}" == "__CANCEL__" ]]; then
  exit "${FZF_CANCEL_STATUS:-130}"
fi

for row in "${rows[@]}"; do
  if [[ "${row%%$'\t'*}" == "${choice}" ]]; then
    printf '%s\n' "${row}"
    exit 0
  fi
done

printf 'fake fzf choice not found: %s\n' "${choice}" >&2
exit 1
BASH
  chmod +x "${FAKE_BIN}/fzf"
}

run_picker() {
  run env \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CODEX_CATALOG="$(catalog_json)" \
    CODEX_LOG="${CODEX_LOG}" \
    CODEX_DEBUG_LOG="${CODEX_DEBUG_LOG}" \
    FZF_CHOICES="${FZF_CHOICES}" \
    "${ROOT}/tools/codex/codex-pick" "$@"
}

@test "codex-pick help does not require catalog commands" {
  run env PATH="/usr/bin:/bin" "${ROOT}/tools/codex/codex-pick" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-pick [MODEL [EFFORT]] [-- CODEX_ARGS...]"* ]]
}

@test "codex-pick resolves a unique model suffix and forwards Codex arguments" {
  run_picker terra high -- -C /tmp/project "investigate failures"

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-terra><-c><model_reasoning_effort='high'><-C></tmp/project><investigate failures>" "${CODEX_LOG}"
}

@test "codex-pick accepts a full model slug" {
  run_picker gpt-5.6-sol max

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-sol><-c><model_reasoning_effort='max'>" "${CODEX_LOG}"
}

@test "codex-pick selects both missing values interactively" {
  printf '%s\n' gpt-5.6-terra high > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-terra><-c><model_reasoning_effort='high'>" "${CODEX_LOG}"
}

@test "codex-pick selects only effort when model is supplied" {
  printf '%s\n' ultra > "${FZF_CHOICES}"

  run_picker sol

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-sol><-c><model_reasoning_effort='ultra'>" "${CODEX_LOG}"
}

@test "codex-pick falls back to the bundled catalog" {
  run env \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CODEX_CATALOG="$(catalog_json)" \
    CODEX_LIVE_FAIL=1 \
    CODEX_LOG="${CODEX_LOG}" \
    CODEX_DEBUG_LOG="${CODEX_DEBUG_LOG}" \
    FZF_CHOICES="${FZF_CHOICES}" \
    "${ROOT}/tools/codex/codex-pick" luna medium

  [ "$status" -eq 0 ]
  grep -Fx 'argv=<debug><models>' "${CODEX_DEBUG_LOG}"
  grep -Fx 'argv=<debug><models><--bundled>' "${CODEX_DEBUG_LOG}"
}

@test "codex-pick rejects an invalid live and bundled catalog" {
  run env \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CODEX_CATALOG='not-json' \
    CODEX_LOG="${CODEX_LOG}" \
    CODEX_DEBUG_LOG="${CODEX_DEBUG_LOG}" \
    FZF_CHOICES="${FZF_CHOICES}" \
    "${ROOT}/tools/codex/codex-pick" sol medium

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unable to read the Codex model catalog"* ]]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick rejects an unknown model" {
  run_picker unknown high

  [ "$status" -eq 2 ]
  [[ "$output" == *"Unknown model: unknown"* ]]
  [[ "$output" == *"gpt-5.6-sol, gpt-5.6-terra, gpt-5.6-luna"* ]]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick rejects an ambiguous model suffix" {
  run env \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CODEX_CATALOG="$(ambiguous_catalog_json)" \
    CODEX_LOG="${CODEX_LOG}" \
    CODEX_DEBUG_LOG="${CODEX_DEBUG_LOG}" \
    FZF_CHOICES="${FZF_CHOICES}" \
    "${ROOT}/tools/codex/codex-pick" terra medium

  [ "$status" -eq 2 ]
  [[ "$output" == *"Ambiguous model: terra"* ]]
  [[ "$output" == *"gpt-5.6-terra"* ]]
  [[ "$output" == *"gpt-6-terra"* ]]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick rejects an effort unsupported by the selected model" {
  run_picker luna ultra

  [ "$status" -eq 2 ]
  [[ "$output" == *"Unsupported effort for gpt-5.6-luna: ultra"* ]]
  [[ "$output" == *"low, medium, high, xhigh, max"* ]]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick preserves model picker cancellation status" {
  printf '%s\n' __CANCEL__ > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 130 ]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick preserves effort picker cancellation status" {
  printf '%s\n' __CANCEL__ > "${FZF_CHOICES}"

  run_picker sol

  [ "$status" -eq 130 ]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick reports a missing Codex binary" {
  run -127 env PATH="/usr/bin:/bin" "${ROOT}/tools/codex/codex-pick" terra high

  [ "$status" -eq 127 ]
  [[ "$output" == *"Required command not found: codex"* ]]
}
