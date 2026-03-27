---
name: execution-context-first-repo-onboarding
description: Use when a repository task requires figuring out how tests, builds, setup, or local services should be run, especially when the repo may require wrappers such as docker compose, make, just, devcontainers, task runners, or project scripts instead of raw host commands.
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
4. Inspect likely local evidence when the docs are incomplete: `compose.yaml`, `docker-compose.yml`, `Makefile`, `justfile`, `Taskfile.yml`, `package.json`, language-specific manifests, helper scripts, and CI configuration.
5. Prefer the most repository-specific entry point over a generic host command. If the repo's workflow routes tests through `docker compose exec ...`, `make test`, `just test`, or a project script, use that path instead of substituting raw `pytest`, `npm test`, or similar host-level commands.
6. Treat containerized workflows as high-signal. If the docs, scripts, or CI show that commands run inside a `docker compose` service, do not assume the same command should run directly on the host.
7. Do not over-infer from weak signals. A `Dockerfile` or container tooling by itself does not prove that every workflow must run through `docker compose`; prefer explicit evidence from docs, scripts, Make targets, CI, or named helper commands.
8. If the evidence is ambiguous or conflicting, surface that uncertainty and ask before running a risky command.
9. State the command source and execution-context reasoning when it matters, especially if you had to fall back to inference.
10. Keep the global approval rules in force for dependency changes, destructive operations, and commit or push actions.

## Output

- The command or workflow chosen from repository docs when available.
- A brief note describing the execution context, such as host, `docker compose`, `make`, `just`, or project script.
- A brief note when the final command came from fallback inspection rather than documentation.
