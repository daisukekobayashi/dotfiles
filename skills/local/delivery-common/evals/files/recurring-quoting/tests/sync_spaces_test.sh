#!/usr/bin/env bash
# Regression test for round 1 CR1: a source directory whose path contains a space.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/my notes" "$tmp/backups"
echo hello > "$tmp/my notes/a.txt"
"$(dirname "$0")/../bin/sync-notes.sh" "$tmp/my notes" "$tmp/backups"
ls "$tmp"/backups/*/"my notes"/a.txt > /dev/null
echo ok
