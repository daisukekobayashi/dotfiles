#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

npm --prefix setup run build

status=0
git diff --exit-code -- 'setup/*.js' || status=$?

untracked="$(git ls-files --others --exclude-standard -- 'setup/*.js')"
if [[ -n "${untracked}" ]]; then
  printf 'Untracked generated setup runtime; commit it or remove it:\n%s\n' "${untracked}" >&2
  if ((status == 0)); then
    status=1
  fi
fi

exit "${status}"
