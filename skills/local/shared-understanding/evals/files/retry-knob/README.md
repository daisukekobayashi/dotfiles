# fetch

`python3 fetch.py <url> <dest>` downloads a URL to a file.

Transient failures are retried three times with exponential backoff. Set
`FETCH_RETRIES` to change the count, for example `FETCH_RETRIES=0` to fail fast
in CI. The tool reads no configuration file.
