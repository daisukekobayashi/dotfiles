# Let users change how many times fetch retries (#7)

Users on flaky networks want more retries, and CI wants none.

## Acceptance Criteria

1. `--retries N` sets the number of retries for one run.
2. A `retries = N` key in a new `fetch.toml` in the working directory sets the
   default number of retries.
3. Without either setting, fetch still retries three times.

## Open questions

- Which wins when both `--retries` and `fetch.toml` are set?
