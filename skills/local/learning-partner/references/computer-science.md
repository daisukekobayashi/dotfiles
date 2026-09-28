# Computer Science learning guidance

Use the algorithm, model, design, code, diff, or operational observation under
discussion. Theory and software engineering are both in scope; an executable
implementation is not required. Choose a tractable question from the work.

## Relate the model and its consequences

For a theoretical question, identify the representation, computational model,
assumptions, and property at issue. Reason about correctness, termination, or
resource use under those assumptions. Make the input size and cost model explicit
when comparing complexity; distinguish that claim from measured performance.

Trace only the parts needed to reason about the chosen question: relevant inputs,
state and its owner, assumptions, boundaries, effects, and observable outcomes.
Connect a design claim to the mechanism that implements it. Language semantics,
runtime behavior, contracts, invariants, and failure paths are useful lenses when
they affect this work, not mandatory subjects for every session.

Use a short code trace, reading task, or modification when concrete practice
would expose a gap that verbal explanation alone cannot. A diagram, invariant,
counterexample, or pseudocode may be more useful for an abstract question. Do not
require the user to reproduce an implementation merely to prove participation.

## Match evidence to the question

Distinguish three questions:

- **What does this implementation do?** Inspect the relevant revision and path.
  Code inspection supports a source-derived account; a test or experiment
  supports behavior only under the conditions it actually exercises.
- **What behavior is required or guaranteed?** Check the applicable contract,
  proof, language or runtime specification, or official documentation for the
  relevant version. Observed behavior alone does not establish a general guarantee.
- **Is this a suitable design?** Relate its behavior to requirements, constraints,
  alternatives, and operating costs. A passing test does not establish that the
  trade-off is appropriate; several choices may be defensible.

When these disagree, expose the discrepancy. Neither the current code nor an
AI-authored test automatically defines the intended contract. Treat unsupported
historical explanations as hypotheses unless there is evidence of the rationale.

## Use a discriminating check

Choose a check that could distinguish the competing explanations or predictions.
Before running it, identify the relevant condition and observable outcome. When
eliciting a prediction, leave that outcome for the user to predict.

Exercise the path relevant to the claim and inspect its actual result. Compilation,
an unrelated passing test, or a health check may leave the learning question open.
For failures, examine which state and effects survive and what the observer can
know; a stopped operation does not by itself describe every external outcome.

Use the repository's documented execution entry point and stay within the task's
existing authorization. Prefer an isolated, minimal reproduction when an
experiment could affect ongoing work. If a check cannot be run, explain its
purpose and mark the result as unobserved.

## Transfer the reasoning

When useful, vary a consequential assumption from the actual task and invite
the user to adapt their explanation or choice. Changing a boundary, input
condition, available guarantee, or operating constraint can be enough. Choose a
variation that tests the reasoning rather than recall of the earlier answer.

Allow the user to consult code and documentation. Look for their ability to find
the relevant evidence, identify what would change the decision, and revise the
model. State what their response demonstrates and what is still untested.
