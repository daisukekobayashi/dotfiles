#!/usr/bin/env bash

# Bash before 4.1 does not apply `set -e` to a failing `[[ ]]`, so a
# non-final `[[ ]]` assertion would let a broken test report ok.
setup_suite() {
  if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 1))); then
    printf 'bats tests need Bash 4.1 or later, but %s is Bash %s.\n' "${BASH}" "${BASH_VERSION}" >&2
    printf 'On macOS, install Homebrew bash and put it ahead of /bin/bash on PATH.\n' >&2
    return 1
  fi
}
