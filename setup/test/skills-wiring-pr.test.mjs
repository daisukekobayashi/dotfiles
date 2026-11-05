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
