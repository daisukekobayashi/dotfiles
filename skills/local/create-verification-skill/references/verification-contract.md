# Project Verification Contract

Use this contract while generating a project skill. Replace descriptions with
observed project facts. It is a content guide, not a template to leave unfinished.

## Launch and readiness

Name the supported wrapper, working directory, build prerequisites, runtime
arguments, and observable readiness condition. For short-lived CLIs and
libraries, document invocation rather than inventing a persistent server.

Give each run its own temporary data/output directory and, when relevant, a free
port or supported dynamic-port setting. Track the process actually started.
Never stop a process by name or reuse an unknown instance as if it belonged to
this run.

## Doctor

Provide the smallest read-only check that establishes whether this is the right
artifact and instance to drive: revision/build identity, ownership, readiness,
and required configuration availability. Do not expose credential values.

## Drive and assert

Describe the real user path with stable selectors, CLI arguments, public API
calls, or library entry points. Avoid internal state setters and test-only
shortcuts that skip the behavior being claimed.

Name a known expected result and what observable failure would falsify it.
Capture both the action and resulting state, including relevant persistence or
other side effects. Restrict external integrations to authorized test targets.
Confirm dry-run semantics by inspection or isolated observation.

## Evidence

Record revision/input identity, command or action, expected/actual result, and
the location of logs, screenshots, or output files. Keep secrets and personal
data out of artifacts. Treat each executed feature as its own coverage claim.

Use an ignored run directory or /tmp with an explicit location; cleanup must
retain the proof. Stable reusable helpers belong with the project skill or the
project's existing test tools, not in a session-specific absolute path.

## Cleanup

Document teardown of owned processes and scratch state, including failed runs.
Keep evidence available after teardown. Never delete pre-existing data, shared
services, or unrelated worktrees.

## Feature map

Keep a small index linking each feature to its procedure. Each procedure names:

- the behavior and relevant sub-features;
- the entry point from the user's perspective;
- the exact driving steps and observable acceptance result;
- required fixtures, alternate paths, and consequential limitations.

Start with the important behaviors established from the repository. Run at
least one through the generated instructions and label the remaining coverage
honestly. Update the map when a feature's behavior or entry points change.
