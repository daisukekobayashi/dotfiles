---
name: readme-first-repo-onboarding
description: Use this skill when the task requires figuring out how to run tests, builds, local services, setup steps, or other repository workflows from project documentation. Do not use it when the user already provided the exact command to run or when the task is unrelated to repository onboarding.
---

# README-First Repo Onboarding

Use this workflow before choosing project commands.

## Inputs

- The repository task, such as running tests, building, starting services, or local setup.

## Workflow

1. Read the root `README.md` first.
2. If the README links to other docs that are relevant to the requested task, read those next.
3. Prefer repository-specific commands from the docs over generic fallback commands.
4. If the docs do not cover the task, inspect likely local sources such as manifests, config files, or scripts to determine a reasonable fallback.
5. State the command source when it matters, especially if you had to fall back to inference.
6. Keep the global approval rules in force for dependency changes, destructive operations, and commit or push actions.

## Output

- The command or workflow chosen from repository docs when available.
- A brief note when the final command came from fallback inspection rather than documentation.
