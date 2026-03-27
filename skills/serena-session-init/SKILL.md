---
name: serena-session-init
description: Initialize Serena at the start of a repository coding session when codebase exploration, symbol lookup, reference tracing, project memory, or structured code edits are likely. Use this skill proactively for repo work where Serena tools may be helpful, even if the user does not explicitly mention Serena, onboarding, or project activation. Do not use it for casual conversation, web-only research, or tasks that clearly do not involve the local codebase.
---

# Serena Session Init

Initialize Serena before relying on Serena project tools in the current repository.

## When To Run

Run this once near the start of a session when the task is likely to involve the local codebase and Serena may help with navigation, symbol-aware inspection, references, memories, or edits.

Do not rerun it if Serena has already been initialized for the same project in the current session unless the working project changes.

## Workflow

1. Call `serena.activate_project` with `project` set to `"."`.
2. Call `serena.check_onboarding_performed`.
3. If onboarding has not been performed, call `serena.onboarding`.
4. Call `serena.initial_instructions`.

## Output

- Serena is ready for the current repository session.
- If onboarding was required, complete it before proceeding with deeper Serena-driven work.
