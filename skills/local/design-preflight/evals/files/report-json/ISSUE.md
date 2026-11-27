# Add JSON output for the dashboard (#15)

The dashboard team wants to read the open tasks automatically, and they asked
for JSON.

## Acceptance Criteria

1. `python3 report.py --json` prints the open tasks as JSON.
2. Without `--json`, the CSV output stays byte-identical.
3. The dashboard can tell when a later change adds or renames a field.
