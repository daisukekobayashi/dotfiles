---
name: azure-devops-work-item-create
description: Use when the user wants to create Azure DevOps Work Items from a discussion, investigation, rough idea, plan, bug report, or feature request.
---

# Azure DevOps Work Item Create

## Scope

Use this skill to turn user intent into one or more well-scoped Azure DevOps
Work Items in the current repository's Azure DevOps project.

Read `../azure-devops-common/references/context.md` before resolving the Azure
DevOps target or creating anything.

## Workflow

1. Resolve the current Azure DevOps organization, project, and repository from
   local git context and `az devops configure --list`.
2. Understand the source material.
   - If the current conversation is enough, summarize it into Work Item-ready
     points.
   - If requirements are vague, ask focused questions one at a time.
   - Split work when separate deliverables, dependencies, risks, or parallel
     workstreams would make implementation and review easier.
3. Look for a repo-local template:
   - `docs/agents/azure-devops-work-item-template.md`
   - If absent, use a compact body with `Summary`, `Background`, `Acceptance
     Criteria`, `Implementation Notes`, `Dependencies`, and `Parallelization`.
4. Determine Work Item type.
   - Do not hardcode `Issue`.
   - Prefer repository guidance when present.
   - Otherwise infer a candidate such as `Bug`, `User Story`, `Product Backlog
     Item`, `Task`, or `Issue` from available project types and the request.
   - If the type is unclear, stop and ask before creating.
5. Draft each Work Item title, type, description, and optional fields.
   - Optional fields include area, iteration, assigned-to, tags, and custom
     fields only when explicitly supported by repo docs or user input.
   - Include only supported facts.
   - Put unknowns in open questions instead of inventing answers.
6. Show a preview before creating anything:
   - target organization, project, and repository
   - proposed Work Item count and split rationale
   - title, type, body, optional fields, dependencies, and parallelization notes
   - creation order when dependencies exist
7. Wait for explicit user confirmation.
8. Create approved Work Items with `az boards work-item create`.
9. Return created IDs and URLs plus dependency and implementation-order notes.

## Guardrails

- This skill is current-repository only.
- Do not create Work Items before preview and explicit confirmation.
- Do not assign, tag, set custom fields, or create relations unless approved or
  clearly specified by repository guidance.
- Do not mutate existing Work Items unless the user explicitly asks.
- Stop if Azure DevOps organization, project, or repository is ambiguous.
