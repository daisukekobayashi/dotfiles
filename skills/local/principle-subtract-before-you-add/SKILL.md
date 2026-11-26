---
name: principle-subtract-before-you-add
description: "Apply when sequencing an addition, refactor, or rewrite. Remove dead code, redundant validators, and stub references first, then build on the simpler base."
license: MIT
disable-model-invocation: true
---

# Subtract Before You Add

When evolving a system, remove complexity first, then build. Default to subtraction.

Make simplification a continual investment. Leave the design slightly simpler and more capable behind the same or smaller surface than you found it.

- Sequence removal before construction
- Cut before you polish (get to the minimum before investing in quality)
- Design for observed usage, not speculative edge cases
- No speculative validators, parsers, or guards beyond what the spec demands
- Simplify prompts (remove redundant instructions, excessive templates)
- When a reference has no novel content, delete it rather than leaving a stub

## Source

Adapted from Lauren Tan's [pstack Subtract Before You Add](https://github.com/cursor/plugins/blob/0b46ec399d55f2829e88822998f53b84944837d3/pstack/skills/principle-subtract-before-you-add/SKILL.md).
Local changes: none to the text. Where this leaf conflicts with the approval,
safety, or scope rules that apply to the task, those rules win; for example,
removal outside the requested change follows the scope rules on unrelated
refactors and cleanup. See [LICENSE](LICENSE).
