# Global AI Operating Guidelines

This document defines the universal standard operating procedures for all AI-assisted development sessions. 
**You must strictly adhere to these rules across all repositories and tools.**

## 1. Git Workflow & Version Control

### Atomic Commits
- **Focus**: Every commit must be atomic.
- **Explicit Staging**: **Never use `git add .` or `git add -A`.** You must strictly stage only the specific files you modified (e.g., `git add path/to/file.py`).
- **Exclusion**: Strictly avoid mixing unrelated refactors, formatting changes, or untracked files into a single commit.

### Commit Message Standards
- **Format**: Adhere to the [Conventional Commits](https://www.conventionalcommits.org/) specification.
  - Pattern: `<type>(<scope>): <subject>`
  - Common types: `feat`, `fix`, `refactor`, `style`, `docs`, `test`, `chore`.
- **Content**: Clearly state the "what" and "why" of the change.

### Branch Naming Conventions
- **Prefix**: Start branch names with a category tag: `feat/`, `fix/`, `refactor/`, `chore/`, or `test/`.
- **Issue Integration**: If a tracking issue or work item (e.g., Azure DevOps, GitHub) exists, place its ID immediately after the slash.
- **Example**: `fix/47-description-of-change`

### Mainline Sync Before Branch/Worktree Creation
- **Mandatory Sequence**: Before creating a new branch or git worktree from `main`, always run the following sequence and verify each command succeeds:
  1. `git fetch origin --prune`
  2. `git switch main`
  3. `git pull --ff-only`
- **Failure Handling**: If any step fails, stop and report the reason before proceeding.

## 2. Context & State Management

- **Local Overrides**: You were invoked via a tool-specific configuration file in the project root (e.g., `AGENTS.md`, `AGENT.md`, `GEMINI.md`, `CLAUDE.md`, or `.cursorrules`). **Always prioritize any project-specific architecture, tech stack, and local rules defined in that invoking file over these global rules.**
- **Tool Availability (e.g., Serena MCP)**: If a context management tool is active, utilize it for project activation and memory portability. Treat each directory or git worktree as an isolated environment.

## 3. Execution Boundaries & Error Handling

### Autonomous Execution (File Editing & Testing)
- **Proactive Implementation**: You are authorized to autonomously edit files, write code, run linters, and execute local test suites to complete the requested task. You do not need to ask for permission for routine file modifications.
- **Review Before Commit**: Once the implementation is complete and verified locally, present a summary of the changes (or a `git diff`). **Always request explicit user approval before executing `git commit` or `git push`.**
- **Destructive Commands**: Never execute destructive system commands (e.g., `rm -rf` on critical directories, dropping databases) without prior confirmation.
- **Dependency Management**: Always ask for explicit user approval before installing new packages, libraries, or modifying dependency files.

### Error Handling
- **Stop and Analyze**: If a test, build, or command fails, do not blindly retry or guess the fix.
- **Report**: Stop execution, analyze the root cause of the error based on the logs, and report your findings clearly to the user with a proposed solution.

## 4. General Principles & Communication Style

### Investigation and Planning
- **Plan before Act**: Before making complex changes, briefly outline your step-by-step execution plan. This ensures alignment and prevents unnecessary code churn.
- **Informed Planning**: Always perform a thorough investigation of the codebase (using grep, read tools, etc.) before proposing or implementing changes.
- **Verification**: Ensure all changes are validated through existing project standards and tests before finalizing a task.

### README-First Execution Policy
- **Source of Truth**: Before running tests, builds, or local services, first check `README.md` and documents explicitly linked from it.
- **Project-Specific Commands First**: If `README.md` defines commands (including `docker compose` workflows), use those commands as the default path.
- **Fallback Rule**: Use generic fallback commands only when no project-specific instructions are documented.

### Security
- **Zero Secrets**: Never hardcode API keys, passwords, or sensitive credentials in source code, logs, or commit messages. Always use environment variables or appropriate secret management tools.

### Formatting & Tone
- **Professional Tone**: Communication should be concise, direct, and focused on the technical task.
- **Japanese Formatting Preferences**: When generating Japanese text for documentation, comments, or chat responses, strictly adhere to the following rules:
  - Use commas (`,`) and periods (`.`) instead of standard Japanese punctuation (`、` and `。`).
  - Insert a half-width space between Japanese text and numbers, symbols, or English alphabets.
