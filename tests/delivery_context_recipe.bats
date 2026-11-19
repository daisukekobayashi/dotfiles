#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/test_helper.bash'

setup() {
  script="$(repo_root)/scripts/delivery-context.sh"
  transcript="${BATS_TEST_TMPDIR}/session.jsonl"
}

# Write a coordinator transcript with one Bash call per argument; each call
# gets a 10-character result.
bash_calls() {
  local i=0 cmd
  : >"${transcript}"
  for cmd in "$@"; do
    i=$((i + 1))
    jq -cn --arg id "t${i}" --arg cmd "${cmd}" '
      {type: "assistant", isSidechain: false, message: {content: [
        {type: "tool_use", id: $id, name: "Bash", input: {command: $cmd}}]}},
      {type: "user", isSidechain: false, message: {content: [
        {type: "tool_result", tool_use_id: $id, content: "0123456789"}]}}' \
      >>"${transcript}"
  done
}

# Assert that the single Bash call in the transcript has the given kind.
assert_kind() {
  local expected="$1" cmd="$2" actual
  bash_calls "${cmd}"
  run --separate-stderr "${script}" "${transcript}"
  [ "${status}" -eq 0 ]
  actual="$(jq -r '.tools[0].kind' <<<"${output}")"
  if [[ "${actual}" != "${expected}" ]]; then
    printf 'command: %s\nexpected: %s\nactual: %s\n' "${cmd}" "${expected}" "${actual}" >&2
    return 1
  fi
}

@test "delivery-context counts digit and ampersand redirects as writes" {
  assert_kind Bash:write 'echo x 1> out.txt'
  assert_kind Bash:write 'echo x 2>> err.log'
  assert_kind Bash:write 'echo x &> out.txt'
  assert_kind Bash:write 'echo x &>> out.txt'
  assert_kind Bash:write 'echo x > out.txt'
  assert_kind Bash:write 'echo x | tee out.txt'
}

@test "delivery-context sends redirects inside bash -c to ambiguous" {
  assert_kind Bash:ambiguous "bash -c 'echo x 1> out.txt'"
  assert_kind Bash:ambiguous "bash -c 'echo x &> out.txt'"
  assert_kind Bash:ambiguous "bash -c 'true; cat state.md 2>errors.log'"
  assert_kind Bash:ambiguous 'echo "$(date)" > out.txt'
}

@test "delivery-context ignores redirects to /dev/null and to file descriptors" {
  assert_kind Bash:read-md 'cat notes.md 2>/dev/null'
  assert_kind Bash:read-md 'cat notes.md &> /dev/null'
  assert_kind Bash:read-md 'cat notes.md 2>&1'
  assert_kind Bash:other 'git status >&2'
  assert_kind Bash:issue-fetch "gh issue view 1 --json body 2>&1"
}

@test "delivery-context sends a heredoc on a line with a quote to ambiguous" {
  assert_kind Bash:ambiguous "printf '%s\n' '<<EOF > state.md'"
  assert_kind Bash:ambiguous "gh issue view 212 --json title --jq '.title | contains(\"<<\")'"
  assert_kind Bash:ambiguous 'cat <<EOF > "$(pwd)/a.md"'
}

@test "delivery-context keeps unquoted and quoted-delimiter heredocs as writes" {
  assert_kind Bash:write $'cat <<EOF > a.md\nsay "hi"\nEOF'
  assert_kind Bash:write $'cat <<\'EOF\' > a.md\nx\nEOF'
  assert_kind Bash:write $'cat <<-"EOF" > a.md\nx\nEOF'
}

@test "delivery-context matches whole redirect operators anywhere" {
  assert_kind Bash:ambiguous "bash -c 'true&&1>out.txt'"
  assert_kind Bash:ambiguous "bash -c 'true&&&>out.txt'"
  assert_kind Bash:write 'true&&1>out.txt'
  assert_kind Bash:write 'true;2>>err.log echo x'
  assert_kind Bash:write 'true|tee out.txt'
  assert_kind Bash:write '(echo x)>out.txt'
  assert_kind Bash:write $'echo x\t>out.txt'
  assert_kind Bash:ambiguous 'echo "x">out.txt'
  assert_kind Bash:write 'git log a->b'
  assert_kind Bash:write 'git diff x12>y'
  assert_kind Bash:write 'cat a.md>b.md'
  assert_kind Bash:write 'cat notes.md>>snapshot.md'
  assert_kind Bash:write 'printf x|tee>/tmp/log'
  assert_kind Bash:write 'cat notes.md 2> >(wc -l)'
  assert_kind Bash:write 'gh issue view 217 2>/dev/null>output.md'
  assert_kind Bash:ambiguous "echo 'a -> b'"
}

@test "delivery-context excludes only an exact /dev/null destination" {
  assert_kind Bash:read-md 'cat notes.md 2>>/dev/null'
  assert_kind Bash:read-md 'cat notes.md &>> /dev/null'
  assert_kind Bash:read-md 'cat notes.md >>/dev/null'
  assert_kind Bash:read-md $'cat notes.md 2>\t/dev/null'
  assert_kind Bash:read-md 'cat notes.md 2>/dev/null;true'
  assert_kind Bash:read-md 'cat notes.md 2>/dev/null|wc -c'
  assert_kind Bash:issue-fetch 'gh issue view 217 2>>/dev/null'
  assert_kind Bash:write 'echo x 1>/dev/null-output'
  assert_kind Bash:write 'echo x >>/dev/nullx'
  assert_kind Bash:other 'git status 1>&2'
  assert_kind Bash:other 'git status >>&2'
}

@test "delivery-context accepts any wholly quoted heredoc delimiter" {
  assert_kind Bash:write $'cat <<\'END-JSON\' > a.json\n{}\nEND-JSON'
  assert_kind Bash:write $'cat <<\'123\' > a.txt\nx\n123'
  assert_kind Bash:write $'cat <<-"END JSON" > a.txt\nx\nEND JSON'
  assert_kind Bash:write $'cat <<\t\'EOF\' > a.txt\nx\nEOF'
  assert_kind Bash:ambiguous $'cat <<\'EOF\' > "a b.txt"\nx\nEOF'
}

@test "delivery-context exempts only descriptor duplication and close after >&" {
  assert_kind Bash:write 'cat notes.md >&snapshot.md'
  assert_kind Bash:write 'gh issue view 217 >&issue.json'
  assert_kind Bash:write 'echo x 2>&err.log'
  assert_kind Bash:ambiguous 'echo x >&"$log"'
  assert_kind Bash:read-md 'cat notes.md 2>&1'
  assert_kind Bash:read-md 'cat notes.md >&2'
  assert_kind Bash:read-md 'cat notes.md 2>&-'
  assert_kind Bash:read-md 'cat notes.md >&-;true'
  assert_kind Bash:read-md 'cat notes.md 3>&1 1>&2 2>&3'
}

@test "delivery-context classifies a long digit run in linear time" {
  local digits start elapsed
  digits="$(printf '%065536d' 0)"
  bash_calls "printf ${digits} > out.txt"
  start="${SECONDS}"
  run --separate-stderr "${script}" "${transcript}"
  elapsed=$((SECONDS - start))
  [ "${status}" -eq 0 ]
  if ((elapsed >= 10)); then
    printf 'classification took %ss\n' "${elapsed}" >&2
    return 1
  fi
  [ "$(jq -r '.tools[0].kind' <<<"${output}")" = Bash:write ]
}

@test "delivery-context exempts only a complete quoted heredoc delimiter" {
  assert_kind Bash:other 'jq . <<<"$output"'
  assert_kind Bash:ambiguous 'jq . <<<"$output" > out.json'
  assert_kind Bash:ambiguous $'cat <<\'END-JSON\'L > a.json\nx\nEND-JSONL'
  assert_kind Bash:ambiguous $'cat <<"END\\"JSON" > a.json\nx\nEND"JSON'
}

@test "delivery-context classifies reads, fetches, and other commands" {
  assert_kind Bash:read-md 'sed -n 1,20p docs/setup.md'
  assert_kind Bash:issue-fetch 'gh issue view 217'
  assert_kind Bash:other 'git status --short'
}

@test "delivery-context reports coordinator peak tokens, compactions, and chars" {
  bash_calls 'echo abc > out.txt' 'cat notes.md'
  jq -cn '
    {type: "assistant", isSidechain: false, message: {content: [], usage:
      {input_tokens: 10, cache_creation_input_tokens: 20, cache_read_input_tokens: 300}}},
    {type: "assistant", isSidechain: false, message: {content: [], usage:
      {input_tokens: 5}}},
    {type: "assistant", isSidechain: true, message: {content: [], usage:
      {input_tokens: 9999}}},
    {type: "system", subtype: "compact_boundary"},
    {type: "system", subtype: "compact_boundary"},
    {type: "system", subtype: "compact_boundary", isSidechain: true}' \
    >>"${transcript}"
  run --separate-stderr "${script}" "${transcript}"
  [ "${status}" -eq 0 ]
  [ -z "${stderr}" ]
  [ "$(jq '.peak_tokens' <<<"${output}")" -eq 330 ]
  [ "$(jq '.compactions' <<<"${output}")" -eq 2 ]
  [ "$(jq -c '.tools | map({(.kind): [.calls, .input_chars, .result_chars]}) | add' <<<"${output}")" \
    = '{"Bash:write":[1,18,10],"Bash:read-md":[1,12,10]}' ]
}

@test "delivery-context rejects a missing or unreadable transcript" {
  run --separate-stderr "${script}"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == usage:* ]]
  run --separate-stderr "${script}" "${BATS_TEST_TMPDIR}/missing.jsonl"
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == "cannot read transcript: "* ]]
}
