---
name: principle-laziness-protocol
description: "Apply when refactoring, evaluating diff size, or tempted to add abstractions, layers, or signal threading. Bias toward deletion and the smallest change that solves the problem."
license: MIT
disable-model-invocation: true
---

# Laziness Protocol

- **Consolidate decisions.** Do not repeat the same choice in several places. Put it behind one source of truth and pass the result as a simple flag.
- **Minimize the diff.** Make the smallest change that solves the problem. Fewer lines beat "elegant" boilerplate.

## Source

Adapted from Lauren Tan's [pstack Laziness Protocol](https://github.com/cursor/plugins/blob/0b46ec399d55f2829e88822998f53b84944837d3/pstack/skills/principle-laziness-protocol/SKILL.md).
Local changes: none to the text. Where this leaf conflicts with the approval,
safety, or scope rules that apply to the task, those rules win. See
[LICENSE](LICENSE).
