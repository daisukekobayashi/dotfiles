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
  FZF_LOG="${TEST_ROOT}/fzf.log"
  FZF_ROWS="${TEST_ROOT}/fzf-rows.log"
  CODEX_HOME="${TEST_ROOT}/codex-home"

  mkdir -p "${FAKE_BIN}" "${CODEX_HOME}"
  touch "${CODEX_HOME}/azure_gpt-5_6-sol_xhigh.config.toml"
  touch "${CODEX_HOME}/azure_gpt-5_6-luna_max.config.toml"
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
  {"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","default_reasoning_level":"low","supported_reasoning_levels":[
    {"effort":"low","description":"Fast responses"},
    {"effort":"medium","description":"Balanced"},
    {"effort":"high","description":"Greater depth"},
    {"effort":"xhigh","description":"Extra high depth"},
    {"effort":"max","description":"Maximum depth"},
    {"effort":"ultra","description":"Automatic delegation"}
  ]},
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
  {"slug":"gpt-5.5","display_name":"GPT-5.5","visibility":"list","default_reasoning_level":"medium","supported_reasoning_levels":[
    {"effort":"low","description":"Fast responses"},
    {"effort":"medium","description":"Balanced"},
    {"effort":"high","description":"Greater depth"},
    {"effort":"xhigh","description":"Extra high depth"}
  ]},
  {"slug":"gpt-5.3-codex-spark","display_name":"GPT-5.3-Codex-Spark","visibility":"list","default_reasoning_level":"medium","supported_reasoning_levels":[
    {"effort":"low","description":"Fast responses"},
    {"effort":"medium","description":"Balanced"},
    {"effort":"high","description":"Greater depth"},
    {"effort":"xhigh","description":"Extra high depth"}
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

original_args=("$@")
if [[ "${1:-}" == "--profile" ]]; then
  shift 2
fi

if [[ "${1:-}" == "debug" && "${2:-}" == "models" ]]; then
  {
    printf 'argv='
    printf '<%s>' "${original_args[@]}"
    printf '\n'
  } >> "${CODEX_DEBUG_LOG}"
  printf 'home=%s\n' "${CODEX_HOME:-}" >> "${CODEX_DEBUG_LOG}"

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
  printf '<%s>' "${original_args[@]}"
  printf '\n'
} > "${CODEX_LOG}"
printf 'home=%s\n' "${CODEX_HOME:-}" >> "${CODEX_LOG}"
exit "${CODEX_EXIT_STATUS:-0}"
BASH
  chmod +x "${FAKE_BIN}/codex"
}

write_fake_fzf() {
  cat > "${FAKE_BIN}/fzf" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'argv='
  printf '<%s>' "$@"
  printf '\n'
} >> "${FZF_LOG}"

rows=()
while IFS= read -r row; do
  rows+=("${row}")
done
if [[ -n "${FZF_ROWS:-}" ]]; then
  printf '%s\n' ${rows[@]+"${rows[@]}"} >> "${FZF_ROWS}"
fi
IFS= read -r choice < "${FZF_CHOICES}"
tail -n +2 "${FZF_CHOICES}" > "${FZF_CHOICES}.next"
mv "${FZF_CHOICES}.next" "${FZF_CHOICES}"

if [[ "${choice}" == "__CANCEL__" ]]; then
  exit "${FZF_CANCEL_STATUS:-130}"
fi

for row in ${rows[@]+"${rows[@]}"}; do
  key="${row%%$'\t'*}"
  legacy_choice="${choice#chatgpt_}"
  if [[ "${key}" == "${choice}" || "${key#*/}" == "${legacy_choice}" ]]; then
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
    FZF_LOG="${FZF_LOG}" \
    FZF_ROWS="${FZF_ROWS}" \
    CODEX_HOME="${CODEX_HOME}" \
    "${ROOT}/tools/codex/codex-pick" "$@"
}

setup_default_homes() {
  PICKER_HOME="${TEST_ROOT}/user home"
  PRIMARY_HOME="${PICKER_HOME}/.codex"
  AZURE_HOME="${PICKER_HOME}/.codex-azure"
  mkdir -p "${PRIMARY_HOME}" "${AZURE_HOME}"
  printf '{}\n' > "${AZURE_HOME}/.dotfiles-azure.json"
  printf 'model_provider = "azure"\n' > "${AZURE_HOME}/config.toml"
  touch "${AZURE_HOME}/azure_gpt-6_1-sol_max.config.toml"
}

setup_openai_home() {
  OPENAI_HOME="${PICKER_HOME}/.codex-openai"
  mkdir -p "${OPENAI_HOME}"
  printf '{}\n' > "${OPENAI_HOME}/.dotfiles-openai.json"
  printf 'model_provider = "openai"\n' > "${OPENAI_HOME}/config.toml"
  touch "${OPENAI_HOME}/openai_gpt-6_1-sol_max.config.toml"
}

run_default_picker() {
  run env -u CODEX_HOME \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    HOME="${PICKER_HOME}" \
    CODEX_HOME="${INHERITED_CODEX_HOME:-}" \
    CODEX_CATALOG="$(catalog_json)" \
    CODEX_LOG="${CODEX_LOG}" \
    CODEX_DEBUG_LOG="${CODEX_DEBUG_LOG}" \
    FZF_CHOICES="${FZF_CHOICES}" \
    FZF_LOG="${FZF_LOG}" \
    FZF_ROWS="${FZF_ROWS}" \
    CODEX_EXIT_STATUS="${CODEX_EXIT_STATUS:-0}" \
    "${ROOT}/tools/codex/codex-pick" "$@"
}

@test "codex-pick help does not require catalog commands" {
  run env PATH="/usr/bin:/bin" "${ROOT}/tools/codex/codex-pick" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-pick [--env ENV] [-q QUERY] [-p PROFILE] [MODEL [EFFORT]] [-- CODEX_ARGS...]"* ]]
}

@test "codex-pick resolves a unique model suffix and forwards Codex arguments" {
  run_picker terra high -- -C /tmp/project "investigate failures"

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-terra><-c><model_reasoning_effort='high'><-C></tmp/project><investigate failures>" "${CODEX_LOG}"
}

@test "codex-pick accepts a full model slug" {
  run_picker gpt-5.6-sol max

  [ "$status" -eq 0 ]
  grep -Fx "argv=<-m><gpt-5.6-sol><-c><model_reasoning_effort='max'>" "${CODEX_LOG}"
}

@test "codex-pick launches an explicit profile without extra arguments" {
  run_picker --profile azure_gpt-5_6-sol_xhigh

  [ "$status" -eq 0 ]
  grep -Fx 'argv=<--profile><azure_gpt-5_6-sol_xhigh>' "${CODEX_LOG}"
}

@test "codex-pick preserves profile and empty or spaced Codex arguments with model overrides" {
  run_picker --profile azure_gpt-5_6-sol_xhigh gpt-5.6-sol max -- "" "two words"

  [ "$status" -eq 0 ]
  grep -Fx "argv=<--profile><azure_gpt-5_6-sol_xhigh><-m><gpt-5.6-sol><-c><model_reasoning_effort='max'><><two words>" "${CODEX_LOG}"
}

@test "codex-pick selects a ChatGPT model without profile files" {
  CODEX_HOME="${TEST_ROOT}/empty-codex-home"
  mkdir -p "${CODEX_HOME}"
  printf '%s\n' chatgpt_gpt-5.6-terra_high > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
  grep -Fx "argv=<-m><gpt-5.6-terra><-c><model_reasoning_effort='high'>" "${CODEX_LOG}"
}

@test "codex-pick selects a ChatGPT model and effort in one step" {
  printf '%s\n' chatgpt_gpt-5.6-terra_high > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-terra><-c><model_reasoning_effort='high'>" "${CODEX_LOG}"
}

@test "codex-pick passes an initial query to the configuration picker" {
  printf '%s\n' azure_gpt-5_6-luna_max > "${FZF_CHOICES}"

  run_picker --query azure

  [ "$status" -eq 0 ]
  grep -F -- '<--query=azure>' "${FZF_LOG}"
}

@test "codex-pick offers GPT-5.3-Codex-Spark in the ChatGPT picker" {
  printf '%s\n' chatgpt_gpt-5.3-codex-spark_xhigh > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.3-codex-spark><-c><model_reasoning_effort='xhigh'>" "${CODEX_LOG}"
}

@test "codex-pick offers GPT-6-Astra in the ChatGPT picker" {
  printf '%s\n' chatgpt_gpt-6-astra_medium > "${FZF_CHOICES}"

  run_picker -q astra

  [ "$status" -eq 0 ]
  grep -Fx "argv=<-m><gpt-6-astra><-c><model_reasoning_effort='medium'>" "${CODEX_LOG}"
}

@test "codex-pick excludes older non-Spark models from the ChatGPT picker" {
  printf '%s\n' chatgpt_gpt-5.5_high > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 1 ]
  [[ "$output" == *"fake fzf choice not found: chatgpt_gpt-5.5_high"* ]]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick applies an interactively selected profile to launch" {
  printf '%s\n' azure_gpt-5_6-luna_max > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  grep -Fx 'argv=<debug><models>' "${CODEX_DEBUG_LOG}"
  grep -Fx "argv=<--profile><azure_gpt-5_6-luna_max>" "${CODEX_LOG}"
}

@test "codex-pick launches an explicit profile without model overrides" {
  run_picker --profile azure_gpt-5_6-sol_xhigh -- -C /tmp/project

  [ "$status" -eq 0 ]
  [ ! -e "${CODEX_DEBUG_LOG}" ]
  grep -Fx "argv=<--profile><azure_gpt-5_6-sol_xhigh><-C></tmp/project>" "${CODEX_LOG}"
}

@test "codex-pick rejects a missing profile" {
  run_picker --profile missing terra high

  [ "$status" -eq 2 ]
  [[ "$output" == *"Profile not found: missing"* ]]
  [ ! -e "${CODEX_LOG}" ]
}

@test "codex-pick selects only effort when model is supplied" {
  printf '%s\n' ultra > "${FZF_CHOICES}"

  run_picker sol

  [ "$status" -eq 0 ]
  grep -F "argv=<-m><gpt-5.6-sol><-c><model_reasoning_effort='ultra'>" "${CODEX_LOG}"
}

@test "codex-pick passes an initial query to the effort picker" {
  printf '%s\n' high > "${FZF_CHOICES}"

  run_picker -q high sol

  [ "$status" -eq 0 ]
  grep -F -- '<--query=high>' "${FZF_LOG}"
}

@test "codex-pick falls back to the bundled catalog" {
  run env \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    CODEX_CATALOG="$(catalog_json)" \
    CODEX_LIVE_FAIL=1 \
    CODEX_LOG="${CODEX_LOG}" \
    CODEX_DEBUG_LOG="${CODEX_DEBUG_LOG}" \
    FZF_CHOICES="${FZF_CHOICES}" \
    CODEX_HOME="${CODEX_HOME}" \
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
    CODEX_HOME="${CODEX_HOME}" \
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
    CODEX_HOME="${CODEX_HOME}" \
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

@test "codex-pick preserves configuration picker cancellation status" {
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

@test "codex-pick combines homes and launches ChatGPT from the main home" {
  setup_default_homes
  printf '%s\n' chatgpt_gpt-5.6-terra_high > "${FZF_CHOICES}"

  run_default_picker -q chatgpt

  [ "$status" -eq 0 ]
  grep -Fx "home=${PRIMARY_HOME}" "${CODEX_LOG}"
  grep -F 'azure_gpt-6_1-sol_max' "${FZF_ROWS}"
  grep -F '<--query=chatgpt>' "${FZF_LOG}"
}

@test "codex-pick launches a generated Azure profile with the same picker and forwarded arguments" {
  setup_default_homes
  printf '%s\n' azure_gpt-6_1-sol_max > "${FZF_CHOICES}"

  run_default_picker -q azure -- "" "two words"

  [ "$status" -eq 0 ]
  grep -Fx "home=${AZURE_HOME}" "${CODEX_LOG}"
  grep -Fx 'argv=<--profile><azure_gpt-6_1-sol_max><><two words>' "${CODEX_LOG}"
  grep -F '<--query=azure>' "${FZF_LOG}"
}

@test "codex-pick resolves an explicit Azure profile without the catalog or fzf" {
  setup_default_homes

  run_default_picker -p azure_gpt-6_1-sol_max -- --resume

  [ "$status" -eq 0 ]
  grep -Fx "home=${AZURE_HOME}" "${CODEX_LOG}"
  grep -Fx 'argv=<--profile><azure_gpt-6_1-sol_max><--resume>' "${CODEX_LOG}"
  [ ! -f "${CODEX_DEBUG_LOG}" ]
  [ ! -f "${FZF_LOG}" ]
}

@test "codex-pick migrates existing dotfiles Azure links without duplicate rows" {
  setup_default_homes
  mkdir -p "${TEST_ROOT}/dotfiles/codex"
  touch "${TEST_ROOT}/dotfiles/codex/azure_gpt-6_1-sol_max.config.toml"
  ln -s "${TEST_ROOT}/dotfiles/codex/azure_gpt-6_1-sol_max.config.toml" "${PRIMARY_HOME}/azure_gpt-6_1-sol_max.config.toml"
  printf '%s\n' azure_gpt-6_1-sol_max > "${FZF_CHOICES}"

  run_default_picker

  [ "$status" -eq 0 ]
  [ "$(grep -c '^azure/azure_gpt-6_1-sol_max' "${FZF_ROWS}")" -eq 1 ]
  grep -Fx "home=${AZURE_HOME}" "${CODEX_LOG}"
  [ -L "${PRIMARY_HOME}/azure_gpt-6_1-sol_max.config.toml" ]
}

@test "codex-pick refuses an uninitialized Azure home for a legacy link" {
  setup_default_homes
  mkdir -p "${TEST_ROOT}/dotfiles/codex"
  touch "${TEST_ROOT}/dotfiles/codex/azure_gpt-6_1-sol_max.config.toml"
  ln -s "${TEST_ROOT}/dotfiles/codex/azure_gpt-6_1-sol_max.config.toml" "${PRIMARY_HOME}/azure_gpt-6_1-sol_max.config.toml"
  # A config alone is not a completed generation.
  mv "${AZURE_HOME}/.dotfiles-azure.json" "${AZURE_HOME}/incomplete-marker.json"

  run_default_picker -p azure_gpt-6_1-sol_max

  [ "$status" -eq 2 ]
  [[ "$output" == *"Run ./setup.sh codex first"* ]]
  [ ! -f "${CODEX_LOG}" ]
  printf '%s\n' azure_gpt-6_1-sol_max > "${FZF_CHOICES}"
  run_default_picker
  [ "$status" -eq 2 ]
  [[ "$output" == *"Run ./setup.sh codex first"* ]]
  [ ! -f "${CODEX_LOG}" ]
}

@test "codex-pick requires an explicit home for unrelated duplicate profiles" {
  setup_default_homes
  touch "${PRIMARY_HOME}/azure_gpt-6_1-sol_max.config.toml"

  run_default_picker -p azure_gpt-6_1-sol_max

  [ "$status" -eq 2 ]
  [[ "$output" == *"Ambiguous profile"* ]]
  [ ! -f "${CODEX_LOG}" ]

  CODEX_HOME="${PRIMARY_HOME}"
  run_picker -p azure_gpt-6_1-sol_max
  [ "$status" -eq 0 ]
  grep -Fx "home=${PRIMARY_HOME}" "${CODEX_LOG}"
}

@test "codex-pick with an explicit generated Azure home offers only its profiles" {
  setup_default_homes
  CODEX_HOME="${AZURE_HOME}"
  printf '%s\n' azure_gpt-6_1-sol_max > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  grep -Fx "home=${AZURE_HOME}" "${CODEX_LOG}"
  [ ! -f "${CODEX_DEBUG_LOG}" ]
  run ! grep -F 'chatgpt_' "${FZF_ROWS}"
}

@test "codex-pick keeps working for ChatGPT when no Azure home exists" {
  PICKER_HOME="${TEST_ROOT}/user home without azure"
  PRIMARY_HOME="${PICKER_HOME}/.codex"
  mkdir -p "${PRIMARY_HOME}"
  printf '%s\n' chatgpt_gpt-6-astra_high > "${FZF_CHOICES}"

  run_default_picker

  [ "$status" -eq 0 ]
  grep -Fx "home=${PRIMARY_HOME}" "${CODEX_LOG}"
  [ ! -e "${PICKER_HOME}/.codex-azure" ]
}

@test "codex-pick preserves cancellation and child exit status when selecting homes" {
  setup_default_homes
  printf '%s\n' __CANCEL__ > "${FZF_CHOICES}"
  run_default_picker
  [ "$status" -eq 130 ]
  [ ! -f "${CODEX_LOG}" ]

  CODEX_EXIT_STATUS=42
  run_default_picker -p azure_gpt-6_1-sol_max
  [ "$status" -eq 42 ]
  grep -Fx "home=${AZURE_HOME}" "${CODEX_LOG}"
}

@test "codex-pick combines all three homes and launches OpenAI with forwarded arguments" {
  setup_default_homes
  setup_openai_home
  printf '%s\n' openai_gpt-6_1-sol_max > "${FZF_CHOICES}"

  run_default_picker -q openai -- "" "two words" --resume

  [ "$status" -eq 0 ]
  grep -Fx "home=${OPENAI_HOME}" "${CODEX_LOG}"
  grep -Fx 'argv=<--profile><openai_gpt-6_1-sol_max><><two words><--resume>' "${CODEX_LOG}"
  grep -F 'azure_gpt-6_1-sol_max' "${FZF_ROWS}"
  grep -F 'default/gpt-' "${FZF_ROWS}"
  grep -F 'OpenAI API profile' "${FZF_ROWS}"
  grep -F '<--query=openai>' "${FZF_LOG}"
}

@test "codex-pick launches an explicit OpenAI profile without a catalog or picker and preserves its exit status" {
  setup_default_homes
  setup_openai_home
  CODEX_EXIT_STATUS=42

  run_default_picker -p openai_gpt-6_1-sol_max -- --resume

  [ "$status" -eq 42 ]
  grep -Fx "home=${OPENAI_HOME}" "${CODEX_LOG}"
  grep -Fx 'argv=<--profile><openai_gpt-6_1-sol_max><--resume>' "${CODEX_LOG}"
  [ ! -f "${CODEX_DEBUG_LOG}" ]
  [ ! -f "${FZF_LOG}" ]
}

@test "codex-pick with an explicit OpenAI home offers only its profiles without loading a catalog" {
  setup_default_homes
  setup_openai_home
  CODEX_HOME="${OPENAI_HOME}"
  printf '%s\n' openai_gpt-6_1-sol_max > "${FZF_CHOICES}"

  run_picker

  [ "$status" -eq 0 ]
  grep -Fx "home=${OPENAI_HOME}" "${CODEX_LOG}"
  [ ! -f "${CODEX_DEBUG_LOG}" ]
  run ! grep -F 'chatgpt_' "${FZF_ROWS}"
  run ! grep -F 'azure_' "${FZF_ROWS}"
}

@test "codex-pick rejects ambiguous OpenAI profiles across homes until a home is specified" {
  setup_default_homes
  setup_openai_home
  touch "${PRIMARY_HOME}/openai_gpt-6_1-sol_max.config.toml"

  run_default_picker -p openai_gpt-6_1-sol_max

  [ "$status" -eq 2 ]
  [[ "$output" == *"Ambiguous profile"* ]]
  [ ! -f "${CODEX_LOG}" ]
  CODEX_HOME="${OPENAI_HOME}"
  run_picker -p openai_gpt-6_1-sol_max
  [ "$status" -eq 0 ]
  grep -Fx "home=${OPENAI_HOME}" "${CODEX_LOG}"
}

@test "codex-pick detects duplicate profiles between Azure and OpenAI homes" {
  setup_default_homes
  setup_openai_home
  touch "${AZURE_HOME}/openai_gpt-6_1-sol_max.config.toml"

  run_default_picker -p openai_gpt-6_1-sol_max

  [ "$status" -eq 2 ]
  [[ "$output" == *"Ambiguous profile"* ]]
  [ ! -f "${CODEX_LOG}" ]
}

@test "codex-pick omits incomplete OpenAI homes and preserves cancellation with all three homes" {
  setup_default_homes
  setup_openai_home
  mv "${OPENAI_HOME}/.dotfiles-openai.json" "${OPENAI_HOME}/incomplete-marker.json"
  printf '%s\n' chatgpt_gpt-6-astra_high > "${FZF_CHOICES}"

  run_default_picker

  [ "$status" -eq 0 ]
  run ! grep -F 'openai_gpt-6_1-sol_max' "${FZF_ROWS}"
  mv "${OPENAI_HOME}/incomplete-marker.json" "${OPENAI_HOME}/.dotfiles-openai.json"
  printf '%s\n' __CANCEL__ > "${FZF_CHOICES}"
  run_default_picker
  [ "$status" -eq 130 ]
  [ "$(wc -l < "${CODEX_LOG}")" -eq 2 ]
}

write_env() {
  local destination="$1" name="$2" provider="$3"
  mkdir -p "$destination"
  jq -n --arg name "$name" --arg provider "$provider" \
    '{version:3,env:$name,provider:$provider,defaultProfile:"gpt-6_1-sol_max",files:{}}' > "$destination/.dotfiles-env.json"
  printf 'model_provider = "%s"\n' "$provider" > "$destination/config.toml"
  printf 'model = "gpt-6.1-sol"\nmodel_reasoning_effort = "max"\n' > "$destination/gpt-6_1-sol_max.config.toml"
}

@test "env selects identically named profiles without mixing API homes or loading a catalog" {
  setup_default_homes
  setup_openai_home
  write_env "$AZURE_HOME" azure azure
  write_env "$OPENAI_HOME" openai openai
  run_default_picker --env azure --profile gpt-6_1-sol_max -- '' 'two words'
  [ "$status" -eq 0 ]
  grep -Fx "home=$AZURE_HOME" "$CODEX_LOG"
  grep -Fx 'argv=<--profile><gpt-6_1-sol_max><><two words>' "$CODEX_LOG"
  [ ! -f "$CODEX_DEBUG_LOG" ]
  INHERITED_CODEX_HOME="$AZURE_HOME"
  run_default_picker --env=openai --profile gpt-6_1-sol_max
  [ "$status" -eq 0 ]
  grep -Fx "home=$OPENAI_HOME" "$CODEX_LOG"
  [ ! -f "$CODEX_DEBUG_LOG" ]
}

@test "multiple environments can share a provider and profile and remain distinct picker rows" {
  setup_default_homes
  local first="$PICKER_HOME/.codex-envs/lab-a" second="$PICKER_HOME/.codex-envs/lab-b"
  write_env "$first" lab-a azure
  write_env "$second" lab-b azure
  printf 'lab-b/gpt-6_1-sol_max\n' > "$FZF_CHOICES"
  run_default_picker
  [ "$status" -eq 0 ]
  grep -Fx "home=$second" "$CODEX_LOG"
  grep -F $'lab-a/gpt-6_1-sol_max\tprofile' "$FZF_ROWS"
  grep -F $'lab-b/gpt-6_1-sol_max\tprofile' "$FZF_ROWS"
  grep -Fx 'argv=<--profile><gpt-6_1-sol_max>' "$CODEX_LOG"
  run_default_picker --env lab-a -p gpt-6_1-sol_max
  [ "$status" -eq 0 ]
  grep -Fx "home=$first" "$CODEX_LOG"
}

@test "legacy provider names normalize inside the selected env and cannot override its provider" {
  setup_default_homes
  setup_openai_home
  write_env "$AZURE_HOME" azure azure
  write_env "$OPENAI_HOME" openai openai
  run_default_picker --env openai -p azure_gpt-6_1-sol_max
  [ "$status" -eq 2 ]
  [ ! -e "$CODEX_LOG" ]
  run_default_picker -p azure_gpt-6_1-sol_max
  [ "$status" -eq 0 ]
  grep -Fx "home=$AZURE_HOME" "$CODEX_LOG"
  grep -Fx 'argv=<--profile><gpt-6_1-sol_max>' "$CODEX_LOG"
}

@test "unknown corrupt and symlinked environments never fall back to the subscription" {
  setup_default_homes
  touch "$PRIMARY_HOME/gpt-6_1-sol_max.config.toml"
  local broken="$PICKER_HOME/.codex-envs/broken"
  write_env "$broken" broken azure
  printf '{"version":3,"env":"other","provider":"azure"}\n' > "$broken/.dotfiles-env.json"
  ln -s "$AZURE_HOME" "$PICKER_HOME/.codex-envs/linked"
  for name in absent broken linked '../outside'; do
    run_default_picker --env "$name" -p gpt-6_1-sol_max
    [ "$status" -eq 2 ]
    [ ! -e "$CODEX_LOG" ]
    [ ! -e "$CODEX_DEBUG_LOG" ]
  done
}

@test "ChatGPT environment catalog lookup and execution both use the selected home" {
  setup_default_homes
  local subscription="$PICKER_HOME/.codex-envs/account-b"
  write_env "$subscription" account-b chatgpt
  run_default_picker --env account-b terra high
  [ "$status" -eq 0 ]
  grep -Fx "home=$subscription" "$CODEX_DEBUG_LOG"
  grep -Fx "home=$subscription" "$CODEX_LOG"
  run grep -Fx "home=$PRIMARY_HOME" "$CODEX_DEBUG_LOG"
  [ "$status" -eq 1 ]
  printf 'account-b/gpt-5.6-terra_high\n' > "$FZF_CHOICES"
  run_default_picker
  [ "$status" -eq 0 ]
  grep -Fx "home=$subscription" "$CODEX_LOG"
  grep -F 'default/gpt-5.6-terra_high' "$FZF_ROWS"
  grep -F 'account-b/gpt-5.6-terra_high' "$FZF_ROWS"
}

@test "retained legacy files never replace a missing neutral profile after migration" {
  setup_default_homes
  write_env "$AZURE_HOME" azure azure
  mv "$AZURE_HOME/gpt-6_1-sol_max.config.toml" "$AZURE_HOME/azure_gpt-6_1-sol_max.config.toml"
  run_default_picker --env azure -p azure_gpt-6_1-sol_max
  [ "$status" -eq 2 ]
  [ ! -e "$CODEX_LOG" ]
  printf 'model = "gpt-6-luna"\nmodel_reasoning_effort = "max"\n' > "$AZURE_HOME/gpt-6-luna_max.config.toml"
  printf 'azure/gpt-6-luna_max\n' > "$FZF_CHOICES"
  run_default_picker --env azure
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$FZF_ROWS")" -eq 1 ]
  grep -Fx 'argv=<--profile><gpt-6-luna_max>' "$CODEX_LOG"
}
