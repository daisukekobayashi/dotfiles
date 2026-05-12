#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

npm --prefix setup run build
git diff --exit-code -- setup/skills.js
