---
name: principle-redesign-from-first-principles
description: "Apply when integrating a new requirement into an existing design."
license: MIT
disable-model-invocation: true
---

# Redesign From First Principles

When integrating a change, don't bolt it onto the existing design. Redesign as if the requirement had been a foundational assumption from the start.

- Read all affected files and understand the current design
- Ask: "if we were writing this from scratch with this new requirement, what would we build?"
- Propagate the change through every reference: types, docs, examples, rationale sections
- Think about the whole redesign, then deliver it incrementally

This is the method for preserving option value when integrating changes into an existing design.

## Source

Adapted from Lauren Tan's [pstack Redesign From First Principles](https://github.com/cursor/plugins/blob/0b46ec399d55f2829e88822998f53b84944837d3/pstack/skills/principle-redesign-from-first-principles/SKILL.md).
Local changes: none to the text. Where this leaf conflicts with the approval,
safety, or scope rules that apply to the task, those rules win; for example,
propagating the change beyond the requested change follows the scope rules.
See [LICENSE](LICENSE).
