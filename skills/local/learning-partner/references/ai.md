# AI learning guidance

Use the AI method, system behavior, design, or experiment in the current work.
Include machine learning as well as search, planning, knowledge representation,
and combinations of learned and programmed components. Do not assume every AI
question calls for training a model or comparing benchmark scores.

## Identify the task and mechanism

Clarify the task, inputs, available information, desired outputs or actions, and
constraints. Distinguish the system's objective from the metric used to evaluate
it and from the outcome the user actually needs.

Identify what is learned, specified by rules, retrieved, searched, or supplied by
external tools. Connect the proposed explanation to the component responsible
for the behavior. Output alone may not establish an internal mechanism, and a
system's account of its own behavior is not independent verification.

For search or planning, inspect the representation, available actions, goal,
constraints, and assumptions behind claims such as completeness or optimality.
For learning, inspect the relationship between the objective, training signal,
data, and behavior expected on new cases. Use only the details needed to answer
the current learning question.

## Evaluate the evidence

Identify the system and evaluation conditions behind a result: relevant model or
algorithm, configuration, data, tools, and procedure. Separate intended behavior,
observed behavior, and a claim about generalization.

For an empirical comparison, examine whether the baseline, test conditions,
available information, and resource budgets make the comparison meaningful.
Check separation of training, tuning, and evaluation information where applicable.
Consider selection effects, repeated tuning, and contamination when they could
explain the apparent improvement.

Relate aggregate metrics to relevant errors, subgroups, uncertainty, and operating
conditions. A higher score may not settle the user's design decision. Distinguish
an observed improvement from an explanation of which change caused it, especially
when several conditions changed together.

## Choose a useful learning activity

Invite the user to predict a failure case, explain an objective, compare plausible
mechanisms, or identify the evidence needed to distinguish them. A small trace,
controlled comparison, ablation, or error analysis can support the discussion.
Choose the smallest useful check; do not start expensive experiments merely to
complete the learning loop. Mark proposed experiments as unrun until observed.

When transfer would help, vary the data distribution, available information,
objective, resource constraint, or consequence of an error. Ask which assumptions
and evaluation choices must change, rather than expecting the same method to
remain appropriate.
