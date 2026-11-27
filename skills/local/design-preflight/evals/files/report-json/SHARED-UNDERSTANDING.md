# Shared Understanding: example/report#15

Status: confirmed

## Agreed Decisions
- `--json` output is read by the dashboard, a separate program that the
  dashboard team maintains and deploys on its own schedule (ISSUE.md; user decision).
- The CSV output without `--json` stays byte-identical (ISSUE.md criterion 2).

## Agreed Issue Changes
None

## Carry to Design Preflight
- The shape of the JSON output, including how the dashboard detects an added or
  renamed field (ISSUE.md criterion 3).

## Open Points
None
