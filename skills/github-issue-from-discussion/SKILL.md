---
name: github-issue-from-discussion
description: Use when the user has already discussed or investigated a topic in the current repository and now wants to check the repository's GitHub issue template or issue form, draft an issue from that discussion, preview it, and then create the issue.
---

# GitHub Issue From Discussion

## Workflow

1. Resolve the current repo from local git context.
2. Summarize the discussion so far into the minimum issue-ready points:
   - problem or request
   - relevant background
   - desired outcome
   - open questions, if any
3. Check the repository's GitHub issue template files before drafting the issue.
   - Look for markdown templates and issue forms under `.github/ISSUE_TEMPLATE/`.
   - If there are multiple templates, infer the best fit from the discussion.
4. Draft the issue title and body from the chosen template.
   - Carry over template defaults such as labels or assignees when the template makes them clear.
   - If the repository uses an issue form, convert the form fields into an equivalent markdown issue body.
5. If no issue template exists, fall back to a compact generic issue draft with `Summary`, `Background`, `Problem`, `Desired Outcome`, and `Notes`.
6. Show a preview before creating anything:
   - chosen template
   - proposed title
   - proposed body
   - labels or assignees, if any
7. After the user confirms the preview, create the GitHub issue.
8. Return the created issue number and URL plus a short summary of what was submitted.

## Guardrails

- This skill is current-repo only.
- Do not create the issue before showing a preview.
- If the best template is unclear, say so and ask instead of guessing.
- If required information is missing from the discussion, ask for it before creating the issue.
- Do not ignore the repository's issue template just because a generic issue would be faster.
