import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
} from "./skills-helpers.mjs";

const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const scriptClause = "where `<script>` is [`check-branch-name.mjs`](../delivery-common/scripts/check-branch-name.mjs) resolved from this skill's directory";
const quoteRule = "Write a name into this or any command only when it uses solely ASCII letters, digits, `/`, `.`, `_`, and `-`; any other name is not safe, without running the check.";

test("Codex review cycle detects completion from the review-state marker", async () => {
  const cycle = await readText(
    path.join(repoRoot, "skills", "local", "github-pr-codex-review-cycle", "SKILL.md"),
  );
  const wait = cycle.match(/\n4\. Wait for Codex review completion\.\n[\s\S]*?(?=\n5\. )/)?.[0];

  assert.ok(wait, "missing wait step");
  assert.match(wait, /`<!-- codex-review-state:v1 \{\.\.\.\} -->`/);
  assert.match(wait, /`updated_at` is later than the trigger comment's `created_at`/);
  assert.match(wait, /Track only `code_review`/);
  assert.match(wait, /`code_review\.status` is `completed` and whose `code_review\.commit_sha`\s+equals the full published head SHA/);
  assert.match(wait, /`running`, `null`, or missing, or with\s+another `commit_sha`, is not completion; keep waiting/);
  assert.match(wait, /`has_any_findings: false` means no actionable\s+feedback: continue at step 8/);
  assert.match(wait, /does not parse, fall back[\s\S]*report\s+that completion was inferred without the marker/);
  assert.doesNotMatch(wait, /review threads, inline comments, or a review summary\/comment that indicates/);
  assert.match(cycle, /^8\. Verify final PR state when possible\.\n   - Re-read thread state after writeback\./m);
});

test("Codex review cycle pushes review fixes to the publication remote", async () => {
  const cycle = await readText(
    path.join(repoRoot, "skills", "local", "github-pr-codex-review-cycle", "SKILL.md"),
  );
  const publish = cycle.match(/\n2\. Use `github-pr-publish`\.\n[\s\S]*?(?=\n3\. )/)?.[0]?.replace(/\s+/g, " ");
  const push = cycle.match(/\n6\. If review fixes changed files[\s\S]*?(?=\n7\. )/)?.[0]?.replace(/\s+/g, " ");

  assert.ok(publish, "missing publish step");
  assert.match(publish, /Capture the PR number, PR URL, branch, push remote,/);
  assert.ok(push, "missing review-fix push step");
  assert.match(push, /`git push <remote> <branch>:refs\/heads\/<branch>`/);
  assert.match(push, /`<remote>` is the push remote captured in step 2/);
  assert.match(push, /`branch\.<branch>\.pushRemote` or `remote\.pushDefault`/);
  assert.match(
    push,
    new RegExp(escapeRegExp(`Stop and report \`<branch>\` unless it is a **safe branch name**: run \`node <script> -- '<branch>'\`, ${scriptClause}, and continue only on exit 0. ${quoteRule}`)),
    "branch checked before the refspec",
  );
  assert.ok(push.indexOf("check-branch-name.mjs") < push.indexOf("git push <remote>"), "branch checked before the push");
  assert.match(push, /`<remote>` is the push remote captured in step 2, used as is\./, "captured remote skips the resolution");
  assert.match(push, /On resume without it, resolve `<remote>` by the push target rule in `github-pr-publish` step 2: run `node <push-script> resolve --github '<host>' '<owner>\/<repo>'` with the PR URL's host and the PR's head repository \(`gh pr view --json headRepository,headRepositoryOwner`\)/, "resume resolves against the PR head repository");
  assert.match(push, /\[`check-push-target\.mjs`\]\(\.\.\/delivery-common\/scripts\/check-push-target\.mjs\) resolved from this skill's directory, and use line 1 on exit 0\./, "resume uses the shared script");
  assert.match(push, /Otherwise stop before the push and ask the user to confirm or name the remote; use a remote the user names as given\./, "unresolved resume remote asks the user");
  assert.doesNotMatch(push, /compared as in `github-pr-publish` step 2|git config --get-all branch\.<branch>\.remote/, "resume prose replaced by the script");
  assert.doesNotMatch(push, /normal push/, "a plain push follows pushRemote away from the PR head");
  assert.match(push, /Confirm the fixes are present in the remote PR head/);
});

test("AI review follow-up and Codex cycle return per-item triage for items not applied", async () => {
  const followup = (await readText(
    path.join(repoRoot, "skills", "local", "github-pr-ai-review-followup", "SKILL.md"),
  )).replace(/\s+/g, " ");
  const cycle = (await readText(
    path.join(repoRoot, "skills", "local", "github-pr-codex-review-cycle", "SKILL.md"),
  )).replace(/\s+/g, " ");

  assert.match(followup, /Also give every item a triage class, whatever its disposition: `pre-existing` under step 5, which takes precedence; otherwise `material` when it describes a concrete failure under step 6's criterion, whatever its label; otherwise `minor`\./);
  assert.match(followup, /per-item disposition, triage class \(step 8\), reviewer label \(`none` when the reviewer gives none, `unknown` when it cannot be read\), and supporting evidence/);
  assert.match(cycle, /- When the caller supplies a progress record location, write the record's items not `applied` there \(the head Codex reviewed, thread, finding, reviewer label, triage class, disposition, and reason\), or return them to the caller and wait until it confirms they are persisted\./);
  const writeback = cycle.match(/7\. Use only the \*\*Writeback\*\* phase.*?(?= 8\. )/)?.[0];
  assert.ok(writeback, "missing Writeback step");
  assert.match(writeback, /- With a caller's progress record location, enter only after step 5's items are persisted there\. When they are missing for the head Codex reviewed, as on a resume that reaches a pending Writeback, re-triage only the prepared record's items not `applied` against that head, keep step 6's publication evidence, and persist them before continuing; Prepare does not run again\./);
  assert.doesNotMatch(writeback, /rerun step 5/, "resume re-triage keeps step 6's publication evidence");
  const report = cycle.match(/## Final Report.*/)?.[0];
  assert.ok(report, "missing final report");
  assert.match(report, /- Not applied: one line per item not `applied`, from the prepared record: `<thread>`: <finding> - `<reviewer label>` - `<triage class>` - `<disposition>`: <reason>; or "None"/);
});

test("PR create opens a fork PR with the head owner and reuses only its own head", async () => {
  const create = await readText(
    path.join(repoRoot, "skills", "local", "github-pr-create", "SKILL.md"),
  );
  const publish = await readText(
    path.join(repoRoot, "skills", "local", "github-pr-publish", "SKILL.md"),
  );
  const step = (text, n) =>
    text.match(new RegExp(`\\n${n}\\. [\\s\\S]*?(?=\\n${n + 1}\\. |\\n## )`))?.[0]?.replace(/\s+/g, " ");
  const context = step(create, 1);
  const reuse = step(create, 4);
  const createStep = step(create, 5);
  const verify = step(create, 6);
  const resolve = step(publish, 2);
  const handoff = step(publish, 8);
  const report = step(publish, 9);

  assert.ok(context && reuse && createStep && verify, "missing create steps");
  assert.ok(resolve && handoff && report, "missing publish steps");

  assert.match(context, /the push remote and `<owner>\/<repo>` that `github-pr-publish` passes, as given/, "publish handoff used as given");
  assert.match(context, /`gh repo view --json nameWithOwner,url,defaultBranchRef`\. This is the PR \*\*base repository\*\*; `<base host>` is the host of its `url`\./, "base host comes from the base url");
  assert.match(context, /Otherwise, when the skill is invoked directly, resolve it by the push target rule in `github-pr-publish` step 2: run `node <push-script> resolve --github '<base host>' '<owner>\/<repo>'` with the base repository's `nameWithOwner`/, "direct call resolves with the shared script");
  assert.match(context, /\[`check-push-target\.mjs`\]\(\.\.\/delivery-common\/scripts\/check-push-target\.mjs\) resolved from this skill's directory\. On exit 0, line 2 is the head repository\./);
  assert.match(context, /Otherwise stop and ask the user to name the head `<owner>\/<repo>` or the remote; do not fall back to a bare `--head <branch>`/);
  assert.match(context, /\*\*safe owner name\*\*, using only `\[A-Za-z0-9-\]` and not starting with `-`/);
  assert.match(context, /before any command uses it, including an owner that `github-pr-publish` passes/);
  assert.match(context, /\*\*cross-repository\*\* when the head repository differs from the base repository, compared case-insensitively\./);
  assert.doesNotMatch(context, /pushRemote|pushDefault|git ls-remote|normalized as in/, "direct-call derivation replaced by the script");
  assert.doesNotMatch(context, /owners match but the repository names differ|users\/<owner>|Organization|set-url/, "same-owner and Organization stops removed");

  assert.match(reuse, /`gh pr view --json number,url,state,headRefName,baseRefName,headRepository,headRepositoryOwner`/);
  assert.match(reuse, /If a PR exists and its head repository is the head repository \(`headRepositoryOwner\.login`\/`headRepository\.name`, compared case-insensitively\), return that PR/);
  assert.match(reuse, /If a PR exists with another head repository or none, stop and report its number, URL, and head repository; do not create or reuse a PR/);

  assert.match(createStep, /`gh pr create --base <base> --head <branch> --body-file <tmp-file>`/, "same-repository command unchanged");
  assert.match(createStep, /For a cross-repository PR, pass `--head <owner>:<branch>` with the head repository's owner/);
  assert.match(verify, /`gh pr view <number> --json number,url,title,state,baseRefName,headRefName,headRepository,headRepositoryOwner`/);
  assert.match(verify, /Stop and report unless the PR's head repository is the head repository\./, "verification checks the head");
  assert.match(create, /^- Do not create or reuse a PR whose head repository is not the head repository\.$/m, "guardrail");

  assert.match(resolve, /Resolve the push remote and the \*\*head repository\*\*/);
  assert.match(resolve, /On exit 0, line 1 is `<remote>` and line 2 is the head repository `<owner>\/<repo>`\./, "head repository from the shared script");
  assert.doesNotMatch(resolve, /normalized as above/, "user-named remote URL normalization moved into the script");
  assert.match(handoff, /Pass the push remote and the head repository `<owner>\/<repo>` from step 2/);
  assert.match(report, /`gh pr view <number> --json number,url,title,state,baseRefName,headRefName`/);
});
