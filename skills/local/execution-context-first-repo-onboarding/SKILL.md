---
name: execution-context-first-repo-onboarding
description: Use when a repository task requires figuring out how tests, builds, setup, or local services should be run, especially when the repo may require wrappers such as docker compose, make, just, devcontainers, CI-backed scripts, task runners, or project scripts instead of raw host commands. Reach for this skill whenever a repo might be containerized or wrapper-driven, even if the requested command sounds simple, because raw host commands like `mix test`, `pytest`, `npm test`, or `cargo test` often bypass the real project workflow.
---

# Execution-Context-First Repo Onboarding

Use this workflow before choosing project commands.

## Inputs

- The repository task, such as running tests, building, starting services, or local setup.

## When Not to Use

- The user already provided the exact repository-specific command to run, unless the repository docs or scripts show that command is wrong or unsafe.
- The task is unrelated to repository setup, builds, tests, or service startup.

## Workflow

1. Read the root `README.md` first.
2. If the README links to other docs that are relevant to the requested task, read those next.
3. Determine the execution context before choosing a command. Look for repository-specific entry points such as `docker compose`, `make`, `just`, `task`, project scripts, devcontainers, or CI workflows.
4. Inspect likely local evidence when the docs are incomplete: `compose.yaml`, `docker-compose.yml`, `compose.*.yaml`, `Makefile`, `justfile`, `Taskfile.yml`, `package.json`, language-specific manifests, helper scripts, and CI configuration.
5. Rank evidence by authority. Prefer, in order: exact README commands, wrapper targets like `make test` or `just test`, project helper scripts, CI commands, then carefully inferred commands from container or task-runner configuration. Use raw host commands only as a last resort.
6. Prefer the most repository-specific entry point over a generic host command. If the repo's workflow routes tests through `docker compose ...`, `make test`, `just test`, a devcontainer, or a project script, use that path instead of substituting raw `mix`, `pytest`, `npm`, `pnpm`, `cargo`, `go test`, or similar host-level commands.
7. Treat containerized workflows as high-signal. If the docs, scripts, Make targets, or CI show that commands run inside a `docker compose` service, do not translate them back into host commands unless the repo explicitly documents a host-native alternative.
8. When `docker compose` is present, distinguish weak from strong signals:
   - Strong signals: README examples that use `docker compose`, a Make or Just target that shells out to `docker compose`, a dedicated `test` service or profile, service commands that already run project bootstrap steps, or CI instructions that execute inside containers.
   - Weak signals: a lone `Dockerfile`, an image build target without local-dev docs, or container files with no matching docs/scripts.
9. If strong compose signals exist, keep language commands inside the container boundary. Prefer forms like `docker compose run --rm <service> ...`, `docker compose exec <service> ...`, or a documented wrapper target over running the inner command directly on the host.
10. If a compose service already encodes setup steps such as dependency install, asset build, migrations, or env wiring, prefer invoking that service or its documented wrapper instead of reconstructing the sequence manually on the host.
11. Before choosing a raw host command, explicitly check that the repo does not expect container-only dependencies, container-only environment variables, or service-to-service networking for the task at hand.
12. Do not over-infer from weak signals. A `Dockerfile` by itself does not prove that every workflow must run through `docker compose`; prefer explicit evidence from docs, scripts, Make targets, CI, or named helper commands.
13. If the evidence is ambiguous or conflicting, surface that uncertainty and ask before running a risky command. When in doubt between a documented wrapper and a raw host command, prefer the wrapper.
14. State the command source and execution-context reasoning when it matters, especially if you had to fall back to inference.
15. Keep the global approval rules in force for dependency changes, destructive operations, and commit or push actions.

## Command Selection Rules

Use this decision order before running anything:

1. If the README gives an exact command for the task, use it as written.
2. If the README points to a wrapper target such as `make test`, `just test`, `task test`, or a project script, use that wrapper instead of expanding it into raw language commands unless you need the underlying command for diagnosis.
3. If local files show the wrapper is just a thin alias over `docker compose`, prefer the wrapper for normal usage and the explicit `docker compose` form when you need to adjust flags, service names, or quoting.
4. If CI shows the task runs through a wrapper or container, treat that as stronger evidence than a language manifest.
5. Only fall back to a raw host command when the repo documents host execution or no higher-signal wrapper exists.

## Compose-Specific Heuristics

- A dedicated compose `test` service or `test` profile is an instruction, not just an implementation detail. Prefer `docker compose --profile test run --rm test` over host commands like `mix test` or `pytest`.
- If a service command contains project bootstrap steps such as `mix deps.get`, `npm ci`, migrations, or asset compilation, assume the service is the intended execution boundary for that workflow.
- If a repo mounts the source tree into a dev container and keeps build artifacts or dependencies in named volumes, treat that as evidence that host installs may be incomplete or intentionally avoided.
- If the task is "run tests", "start the app", "run migrations", or "open a shell", choose the documented service and run inside it before considering host-native equivalents.
- When using `docker compose`, prefer repo-local service names and profiles from the docs instead of inventing new ones.

## Examples

- README says `docker compose --profile test run --rm test` and `make test-docker` wraps the same command:
  Choose `make test-docker` for normal use or the documented compose command if you need to pass through additional shell arguments. Do not substitute `mix test` on the host.
- `compose.yaml` defines a `web` service whose command runs `mix deps.get`, `mix assets.build`, and `mix phx.server`:
  Start the app through `docker compose up web` or the documented compose stack, not `mix phx.server` on the host.
- Repo has only a production `Dockerfile` and the README documents `pytest` directly:
  Host execution is acceptable because the container evidence is weak and the docs are explicit.

## Output

- The command or workflow chosen from repository docs when available.
- A brief note describing the execution context, such as host, `docker compose`, `make`, `just`, or project script.
- A brief note when the final command came from fallback inspection rather than documentation.
