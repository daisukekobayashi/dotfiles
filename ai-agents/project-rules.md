# 1. Global AI Guidelines
First, strictly read and internalize the global operating rules defined in:
`~/.dotfiles/ai-agents/global-rules.md` (Absolute path)

---

# 2. Project-Specific Rules
This section defines the context, architecture, and specific rules for this repository. Prioritize these instructions alongside the global rules.

## 2.1. Project Context & Purpose
- **Description:** [State the project overview. e.g., A Python CLI for investment analysis / An Elixir-based micro-SaaS AI agent / Personal dotfiles management]
- **Primary Tech Stack:** [e.g., Python 3.12 & FastAPI / Elixir & Phoenix / Rust & Actix-web / Modern C++20 / Neovim Lua]

## 2.2. Architecture & Directory Structure
- **Key Directories:**
  - `src/` / `lib/`: [Explain where core logic resides. e.g., 'Core business logic in lib/, API routing in src/']
  - `tests/` / `test/`: [Specify test locations. e.g., 'Unit tests in test/, integration tests in tests/integration/']
- **Design Pattern:** [Specify architectural constraints. e.g., Clean Architecture / MVC / Functional Core, Imperative Shell]

## 2.3. Coding Standards & Tooling
- **Linting/Formatting:** [e.g., Always run `ruff`/`black` (Python), `mix format` (Elixir), `cargo fmt` (Rust), `clang-format` (C/C++), or `stylua` (Lua) before finalizing code.]
- **Typing & Safety:** [e.g., Use strict type hints via `mypy` (Python) / Write `@spec` for all public functions (Elixir) / Ensure memory safety and resolve all `clippy` warnings (Rust).]
- **Dependencies:** [e.g., Managed via `pyproject.toml` (Python), `mix.exs` (Elixir), `Cargo.toml` (Rust), or `CMakeLists.txt` (C/C++). Do not add new libraries without asking.]

## 2.4. Testing & CI/CD
- **Testing Framework:** [e.g., `pytest` (Python), `ExUnit` (Elixir), `cargo test` (Rust), `GTest`/`Catch2` (C/C++), or `busted` (Lua).]
- **Execution:** Ensure all local tests pass before proposing any commits.

## 2.5. Specific Quirks & Boundaries
- [Add project-specific absolute "DO NOTs" or critical warnings.]
- [e.g., "Do not modify database migration files directly; always generate a new migration."]
- [e.g., "Never use raw pointers in C++ unless strictly necessary for hardware interfacing."]
- [e.g., "When editing Neovim configurations, ensure changes are compatible with the existing lazy.nvim plugin structure."]
