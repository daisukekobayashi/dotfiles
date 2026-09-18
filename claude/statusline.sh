#!/usr/bin/env bash

# Claude Code supplies session data as JSON on stdin.
input=$(cat)
{
  IFS= read -r dir
  IFS= read -r model
  IFS= read -r used
  IFS= read -r effort
  IFS= read -r usage
} < <(printf '%s' "$input" | jq -r '
  def percent: floor | tostring;
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // "Claude"),
  (.context_window.used_percentage | if . == null then "--" else percent end),
  (.effort.level // ""),
  ([
    (if .rate_limits.five_hour.used_percentage != null then
      "5h \(.rate_limits.five_hour.used_percentage | percent)%" else empty end),
    (if .rate_limits.seven_day.used_percentage != null then
      "7d \(.rate_limits.seven_day.used_percentage | percent)%" else empty end)
  ] | join(" / ")) as $windows |
  (if $windows != "" then "usage \($windows)" else "" end) as $usage |
  (if .rate_limits.spend_limit.used_percentage != null then
    "spend \(.rate_limits.spend_limit.used_percentage | percent)%" else "" end) as $spend |
  ([$usage, $spend] | map(select(. != "")) | if length == 0 then "usage --" else join(" | ") end)
')

branch=""
if [ -n "$dir" ] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  if [ -n "$(git --no-optional-locks -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
    branch="${branch}*"
  fi
fi

display_dir="${dir%/}"
display_dir="${display_dir##*/}"
display_dir="${display_dir:-${dir:-~}}"
printf '\033[01;34m%s\033[00m' "$display_dir"
[ -z "$branch" ] || printf ' (%s)' "$branch"
printf ' [%s' "$model"
[ -z "$effort" ] || printf ' / %s' "$effort"
printf '] | ctx %s%% | %s\n' "$used" "$usage"
