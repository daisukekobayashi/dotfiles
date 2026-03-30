# Sample Compose App

This sample repository documents a Docker Compose based local workflow for a containerized web application with a JavaScript app and a Python worker.

## Local development

Start the full development stack with:

```bash
docker compose up --build
```

This starts:
- `web` for the main application
- `worker` for background jobs
- `db` for Postgres
- `redis` for shared runtime state

## Tests

Run the full test suite in Docker:

```bash
docker compose --profile test run --rm test
```

Run JavaScript and Python tests inside the test service:

```bash
docker compose --profile test run --rm test sh -lc "./scripts/setup.sh && npm test"
docker compose --profile test run --rm test sh -lc "./scripts/setup.sh && pytest"
```

Equivalent Make target:

```bash
make test-docker
```
