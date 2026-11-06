import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
} from "./skills-helpers.mjs";

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
  assert.match(push, /Stop and report `<branch>` unless it is a \*\*safe branch name\*\*, using only `\[A-Za-z0-9\/._-\]`/, "branch checked before the refspec");
  assert.match(push, /On resume without it, read `<remote>` with `git config --get-all branch\.<branch>\.remote`[^.]*exactly one value/, "resume reads the upstream remote");
  assert.match(push, /`gh pr view --json headRepository,headRepositoryOwner`/, "resume checks the PR head repository");
  assert.match(push, /`<remote>` is the push remote captured in step 2, used as is\./, "captured remote skips the URL check");
  assert.match(push, /exactly one value\. Use it only when its URLs name the PR's head repository/, "URL check only on resume");
  assert.match(push, /Otherwise, as with an SSH host alias, stop before the push and ask the user to confirm or name the remote; use a remote the user names as given\./, "unconfirmed resume remote asks the user");
  assert.doesNotMatch(push, /Then stop unless that remote's URLs/, "ambiguous check could reject the captured remote");
  assert.doesNotMatch(push, /resolve it as `github-pr-publish` step 2 does/, "URL matching can pick the parent in a fork layout");
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

  assert.match(followup, /Also give every item a triage class, whatever its disposition: `material` when it describes a concrete failure under step 6's criterion, whatever its label; `pre-existing` under step 5; otherwise `minor`\./);
  assert.match(followup, /per-item disposition, triage class \(step 8\), reviewer label \(`none` when the reviewer gives none, `unknown` when it cannot be read\), and supporting evidence/);
  assert.match(cycle, /- When the caller keeps a progress record, hand it the record's items not `applied` before step 7\./);
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
  assert.match(context, /Otherwise, when neither is given and the skill is invoked directly:/, "derivation and stop only without a user-named head");
  assert.match(context, /Then read `<remote>` with `git config --get-all branch\.<branch>\.remote` and continue only on exactly one value/, "direct call derives from the upstream");
  assert.match(context, /every push URL \(`git remote -v`\) name on `<base host>`/, "URL matching uses the base host");
  assert.match(context, /normalized as in `github-pr-publish` step 2/);
  assert.match(context, /When the head repository cannot be determined[^.]*stop and ask the user to name the head `<owner>\/<repo>` or the remote; do not fall back to a bare `--head <branch>`/);
  assert.match(context, /\*\*safe owner name\*\*, using only `\[A-Za-z0-9-\]` and not starting with `-`/);
  assert.match(context, /before any command uses it, including an owner that `github-pr-publish` passes/);
  assert.match(context, /\*\*cross-repository\*\* when the head repository differs from the base repository, compared case-insensitively/);
  assert.match(context, /Stop and report when the owners match but the repository names differ/, "same-owner fork stops");
  assert.match(context, /`gh api --hostname <base host> users\/<owner> --jq \.type`[^.]*stop and report when it is `Organization`/, "org-owned head stops; lookup on the base host");
  assert.match(context, /continue only on exactly one value\. Confirm that `<remote>` holds this branch at local `HEAD`:/, "upstream check follows the remote read, before head derivation");
  assert.match(context, /`git config --get-all branch\.<branch>\.merge` prints exactly one value, `refs\/heads\/<branch>`/, "merge ref must be the same branch");
  assert.match(context, /`git ls-remote <remote> refs\/heads\/<branch>` prints exactly one line whose ref is exactly `refs\/heads\/<branch>` and whose SHA equals `git rev-parse HEAD`/, "head remote must hold local HEAD");
  assert.match(context, /Otherwise, including when `git ls-remote` fails, stop and ask the user to name the head `<owner>\/<repo>` or the remote/, "stale or unverifiable head stops");
  assert.match(context, /the effective push remote is `branch\.<branch>\.pushRemote`, or `remote\.pushDefault` when that is unset; when it is set and names a different remote than `branch\.<branch>\.remote`, stop and ask the user to name the head `<owner>\/<repo>` or the remote/, "divergent effective push remote stops");
  assert.match(context, /`git remote set-url`[^.]*renamed or transferred repository/, "stop suggests updating a stale remote URL");

  assert.match(reuse, /`gh pr view --json number,url,state,headRefName,baseRefName,headRepository,headRepositoryOwner`/);
  assert.match(reuse, /If a PR exists and its head repository is the head repository \(`headRepositoryOwner\.login`\/`headRepository\.name`, compared case-insensitively\), return that PR/);
  assert.match(reuse, /If a PR exists with another head repository or none, stop and report its number, URL, and head repository; do not create or reuse a PR/);

  assert.match(createStep, /`gh pr create --base <base> --head <branch> --body-file <tmp-file>`/, "same-repository command unchanged");
  assert.match(createStep, /For a cross-repository PR, pass `--head <owner>:<branch>` with the head repository's owner/);
  assert.match(verify, /`gh pr view <number> --json number,url,title,state,baseRefName,headRefName,headRepository,headRepositoryOwner`/);
  assert.match(verify, /Stop and report unless the PR's head repository is the head repository\./, "verification checks the head");
  assert.match(create, /^- Do not create or reuse a PR whose head repository is not the head repository\.$/m, "guardrail");

  assert.match(resolve, /Resolve the \*\*head repository\*\*/);
  assert.match(resolve, /For a user-named remote, it is the `<owner>\/<repo>` that its fetch URL and every push URL name on the resolved repository's host, normalized as above/, "user-named remote URL normalization");
  assert.match(resolve, /stop and ask the user to name the head `<owner>\/<repo>`/);
  assert.match(handoff, /Pass the push remote and the head repository `<owner>\/<repo>` from step 2/);
  assert.match(report, /`gh pr view <number> --json number,url,title,state,baseRefName,headRefName`/);
});
