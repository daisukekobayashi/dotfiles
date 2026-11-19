#!/usr/bin/env bash
# Measure the context a delivery coordinator used, from one Claude Code
# session transcript. Prints one JSON object: peak_tokens, compactions, and
# characters by tool kind. See docs/skill-evaluation.md#delivery-coordinator-context.
set -euo pipefail

usage() {
  printf 'usage: %s <session.jsonl>\n' "${0##*/}" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
transcript="$1"
if [[ ! -f "${transcript}" || ! -r "${transcript}" ]]; then
  printf 'cannot read transcript: %s\n' "${transcript}" >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || {
  printf 'jq is required\n' >&2
  exit 2
}

# Classification is a heuristic for comparing like with like, not a shell
# parser:
# - The first line has a heredoc (<< or <<-, not a <<< here-string):
#   Bash:write, or Bash:ambiguous when the line also has a quote, $(, a
#   backtick, or bash -c / sh -c. A delimiter word that is wholly single- or
#   double-quoted and followed by whitespace or the line end, such as <<'EOF'
#   or <<-"END JSON", does not count as a quote.
# - tee, or a redirect operator anywhere (N>>, N>, &>>, &>, >>, >; not a
#   descriptor duplication or close such as >&2 or 2>&-), unless its
#   destination word is exactly /dev/null: Bash:ambiguous when the
#   command has a quote, $(, a backtick, or bash -c / sh -c anywhere,
#   otherwise Bash:write. Uncertain cases fall toward write or ambiguous.
# Writes cost their input; reads and fetches cost their result.
# shellcheck disable=SC2016 # $ and backticks are jq regex text, not expansions.
jq -s '
  def quoting: test("[\u0027\"`]|\\$\\(|\\b(ba)?sh -c");
  def redirect: test("\\btee\\b|(?>(?<![0-9])[0-9]*>>|(?<![0-9])[0-9]*>|&>>|&>)(?!&(?:[0-9]+|-)(?:[\\s;&|()<>]|$))(?>[ \\t]*)(?!/dev/null(?:[\\s;&|()<>]|$))");
  def kind:
    (split("\n")[0]
      | gsub("(?<!<)<<(?!<)-?[ \\t]*(?:\u0027[^\u0027]*\u0027|\"[^\"]*\")(?=[ \\t]|$)"; "<<EOF")) as $line
    | if ($line | test("(?<!<)<<(?!<)")) then
        (if ($line | quoting) then "Bash:ambiguous" else "Bash:write" end)
      elif quoting and redirect then "Bash:ambiguous"
      elif redirect then "Bash:write"
      elif test("(^|[;&| ])(cat|sed -n|head|tail) [^|]*\\.md") then "Bash:read-md"
      elif test("gh issue (view|list)|az boards work-item show") then "Bash:issue-fetch"
      else "Bash:other" end;
  [.[] | select(.isSidechain | not)] as $e
  | ([$e[] | select(.type == "assistant" and .message.usage) | .message.usage
      | .input_tokens + (.cache_creation_input_tokens // 0)
        + (.cache_read_input_tokens // 0)] | max) as $peak
  | ([$e[] | select(.type == "system" and .subtype == "compact_boundary")]
      | length) as $compactions
  | ([$e[] | select(.type == "assistant") | .message.content[]?
      | select(.type == "tool_use")
      | {key: .id, value: {
          kind: (if .name == "Bash" then ((.input.command // "") | kind) else .name end),
          input: ((.input.command // .input.content // .input.new_string
            // (.input | tostring)) | length)}}]
      | from_entries) as $use
  | {peak_tokens: $peak, compactions: $compactions,
     tools: ([$e[] | select(.type == "user") | .message.content[]?
       | select(.type == "tool_result")
       | ($use[.tool_use_id] // {kind: "?", input: 0})
         + {result: (.content | if type == "string" then length
             else ([.[]? | .text? // ""] | add // "" | length) end)}]
       | group_by(.kind)
       | map({kind: .[0].kind, calls: length,
           input_chars: (map(.input) | add), result_chars: (map(.result) | add)})
       | sort_by(-(.input_chars + .result_chars)))}
' "${transcript}"
