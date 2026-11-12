# test(skills): keep the list-processes "without slowing down" tests from failing on a slow runner

## Summary

The bats test "list-processes ps fallback reads non-ASCII before a long ASCII run without slowing down" fails intermittently on the macOS CI runner. It compares two wall-clock listing times measured in whole seconds and fails when the difference reaches 4 seconds, so a slow or noisy runner can fail it with no change in the script. Make the check tell a real slowdown from runner noise.

## Background

- PR #179 (test-only change in `setup/test/`): `unix (macos-latest)` failed with `not ok 189 ... reads non-ASCII before a long ASCII run without slowing down` (`tests/list_processes.bats:1054`), "listing took 5s with the long line, 1s without". A rerun of the same job passed (run 43024309626).
- main push run 42827792240 (2026-11-10): the same test failed with "listing took 6s with the long line, 2s without".
- The test measures `SECONDS` around one listing without and one with a long argv line, and requires `long_time - plain_time < 4` (`tests/list_processes.bats:1035-1056`).
- The sibling test "reads a long argument line without slowing down" (`tests/list_processes.bats:1007-1031`) uses the same pattern with a threshold of 3. It has not been observed failing, but shares the weakness (inferred).
- Found during the delivery of #120 and #178.

## Acceptance Criteria

- [ ] The non-ASCII timing test no longer fails from runner noise alone, while it still fails when the long-line handling regresses to the slow path it guards against.
- [ ] The sibling "reads a long argument line without slowing down" test is fixed the same way, or recorded as not affected.
- [ ] The check that the long line's row is listed is unchanged.
- [ ] Evidence shows the revised check still catches a regression (for example, a scratch copy that disables the fast path fails).

## Implementation Notes

Open question: how to make the check robust. Options raised so far: compare against a ratio or a larger margin, measure with finer resolution than `SECONDS`, take the best of several runs, or count work done (such as `ps` calls) instead of time.

## Touched Areas

- `tests/list_processes.bats` (estimate)

## Dependencies

None.

## Parallelization

Overlaps #167, which also changes `tests/list_processes.bats`; do not run alongside it.

