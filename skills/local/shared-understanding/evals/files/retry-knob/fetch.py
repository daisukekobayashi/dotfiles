"""Download a URL to a file, retrying transient failures."""
import os
import sys
import time
import urllib.request

RETRIES = int(os.environ.get("FETCH_RETRIES", "3"))


def fetch(url, dest):
    for attempt in range(RETRIES + 1):
        try:
            with urllib.request.urlopen(url, timeout=10) as response, open(dest, "wb") as out:
                out.write(response.read())
            return 0
        except OSError as error:
            if attempt == RETRIES:
                print(f"fetch: {error}", file=sys.stderr)
                return 1
            time.sleep(2 ** attempt)


if __name__ == "__main__":
    sys.exit(fetch(sys.argv[1], sys.argv[2]))
