# Add a --since filter to the export

## Acceptance criteria

1. `--since YYYY-MM-DD` prints only rows dated on or after that date.
2. An invalid `--since` value exits with status 2 and writes an error to stderr.
3. Without `--since`, the output is unchanged.

## Out of scope

- Changing the printed columns.
