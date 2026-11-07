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
  assert.match(push, /If verification, commit, or push fails, stop the cycle and report; do not enter step 7\./, "a failed publication stops the cycle before writeback");
  assert.match(push, /Add the published commit to the prepared record\./);
});

test("AI review follow-up and Codex cycle return per-item triage for items not applied", async () => {
  const followup = (await readText(
    path.join(repoRoot, "skills", "local", "github-pr-ai-review-followup", "SKILL.md"),
  )).replace(/\s+/g, " ");
  const cycle = (await readText(
    path.join(repoRoot, "skills", "local", "github-pr-codex-review-cycle", "SKILL.md"),
  )).replace(/\s+/g, " ");

  assert.match(followup, /Also give every item a triage class under \[Triage classes\]\(\.\.\/delivery-common\/references\/local-review\.md#triage-classes\), whatever its disposition\./);
  assert.match(followup, /per-item disposition, triage class \(step 8\), reviewer label \(`none` when the reviewer gives none, `unknown` when it cannot be read\), and supporting evidence/);
  assert.doesNotMatch(cycle, /progress record location|persisted|re-triage/, "the cycle leaves recording items not applied to its caller");
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

  assert.match(resolve, /Resolve the push remote and the \*\*head repository\*\*/);
  assert.match(resolve, /On exit 0, line 1 is `<remote>` and line 2 is the head repository `<owner>\/<repo>`\./, "head repository from the shared script");
  assert.doesNotMatch(resolve, /normalized as above/, "user-named remote URL normalization moved into the script");
  assert.match(handoff, /Pass the push remote and the head repository `<owner>\/<repo>` from step 2/);
  assert.match(report, /`gh pr view <number> --json number,url,title,state,baseRefName,headRefName`/);
});

const localSkill = (...parts) => readText(path.join(repoRoot, "skills", "local", ...parts));
const flatText = (text) => text.replace(/\s+/g, " ");
const sectionOf = (text, heading) => text.match(new RegExp(`\\n## ${heading}\\n[\\s\\S]*?(?=\\n## |$)`))?.[0];
const delegationLink = "[Delegated Authorization](../delivery-common/SKILL.md#delegated-authorization)";

test("delegated authorization has one home that the PR skills link", async () => {
  const commonRaw = await localSkill("delivery-common", "SKILL.md");
  const common = flatText(commonRaw);
  assert.match(commonRaw, /^description: .*Also states the delegated authorization rule that the PR, review request, and delivery skills link\.$/m);
  assert.match(common, /approvals; \[Delegated Authorization\]\(#delegated-authorization\) says how those approvals pass to the skills it calls\./);
  const home = flatText(sectionOf(commonRaw, "Delegated Authorization") ?? "");
  assert.match(home, /A delegated call carries the user's actual request, the exact target, and the existing approvals\./);
  assert.match(home, /the called skill acts only within them and, before an action they do not cover, prepares the concrete result and asks for the missing approval\./);
  assert.match(home, /A skill reference, automatic selection, or automatic discovery authorizes nothing\./);
  assert.match(home, /Reuse approval already given for the same scope instead of asking again\./);
  assert.match(home, /Each called skill keeps its own approval model/);

  const skills = {
    "github-pr-publish": /the exact target is the target branches\. Subject to governing approval instructions, treat the explicit publication request as approval for ordinary non-destructive commits/,
    "github-pr-create": /the exact target is the branch and base, for PR creation\./,
    "github-pr-review-request": /the exact target is the PR and the selected providers\./,
    "github-pr-codex-review-cycle": /the exact target is the requested feature branches\. Honor stricter applicable approval instructions\./,
    "github-pr-publish-and-ai-review-request": /Apply its approval model to the requested publication; delegated calls follow/,
    "azure-devops-pr-publish": /the exact target is the target branches\. Subject to governing approval instructions, treat that request as approval/,
    "azure-devops-pr-create": /the exact target is the branch and target branch, for PR creation or update\./,
  };
  for (const [name, kept] of Object.entries(skills)) {
    const text = flatText(await localSkill(name, "SKILL.md"));
    assert.ok(text.includes(delegationLink), `${name}: links Delegated Authorization`);
    assert.match(text, kept, `${name}: keeps its target and approval scope`);
    assert.doesNotMatch(text, /must forward|forward the actual|automatic (selection|discovery) is insufficient|does not authorize a GitHub write|reference to this skill alone|Pass through existing authorization/, `${name} restates delegated authorization`);
  }
});

test("sequential target processing has one home per provider", async () => {
  const publish = flatText(await localSkill("github-pr-publish", "SKILL.md"));
  assert.match(publish, /1\. Resolve targets\. - Identify each branch or worktree requested by the user\. - If no target is specified, use the current worktree and branch\. - For multiple targets, process them sequentially and stop on the first failure\./);
  for (const name of ["github-pr-codex-review-cycle", "github-pr-publish-and-ai-review-request"]) {
    const text = flatText(await localSkill(name, "SKILL.md"));
    assert.match(text, /Resolve and process targets under `github-pr-publish` step 1, across/, name);
    assert.doesNotMatch(text, /sequentially|first failure|If no target is specified/, `${name} restates target processing`);
  }
  const azureRaw = await localSkill("azure-devops-pr-publish", "SKILL.md");
  const azureStep = flatText(azureRaw.match(/\n1\. Resolve targets[\s\S]*?(?=\n2\. )/)?.[0] ?? "");
  assert.match(azureStep, /For multiple targets, process them sequentially and stop on the first failure\./);
  assert.doesNotMatch(flatText(sectionOf(azureRaw, "Guardrails") ?? ""), /later targets/);
});

test("an acknowledgement is not a completed review has one home", async () => {
  const request = flatText(await localSkill("github-pr-review-request", "SKILL.md"));
  assert.match(request, /A posted or acknowledged request is not a completed review\./);
  for (const [name, text] of Object.entries({
    "github-pr-codex-review-cycle": await localSkill("github-pr-codex-review-cycle", "SKILL.md"),
    "codex.md": await localSkill("github-pr-review-request", "references", "codex.md"),
    "github-issue-delivery": await localSkill("github-issue-delivery", "SKILL.md"),
  })) {
    assert.doesNotMatch(flatText(text), /acknowledgement only|is not review completion|picked it up|not a completed review|unless the posted comment has an `eyes` reaction/, `${name} restates the acknowledgement rule`);
  }
  const cycle = flatText(await localSkill("github-pr-codex-review-cycle", "SKILL.md"));
  assert.match(cycle, /Treat `Codex request posted but not acknowledged` as a blocker unless the user explicitly asks to continue waiting or retry\./);
});

test("Codex cycle leaves writeback prerequisites to the follow-up skill", async () => {
  const cycle = flatText(await localSkill("github-pr-codex-review-cycle", "SKILL.md"));
  assert.doesNotMatch(cycle, /no empty commit is needed|Confirm the fixes are present in the remote PR head|stop before reply or resolution/);
  assert.match(cycle, /Pass the prepared record, publication evidence, and existing authorization/);
  const followup = flatText(await localSkill("github-pr-ai-review-followup", "SKILL.md"));
  assert.match(followup, /require successful relevant verification and confirmation that the fixes are in the remote PR head/);
  assert.match(followup, /Explanation-only items need no new commit/);
});

test("AI review follow-up links the shared triage classes", async () => {
  const followup = flatText(await localSkill("github-pr-ai-review-followup", "SKILL.md"));
  assert.match(followup, /Classify `pre-existing` under \[Triage classes\]\(\.\.\/delivery-common\/references\/local-review\.md#triage-classes\); for a PR, the merge-base is that of its head and base branch\./);
  assert.match(followup, /Defer minor and pre-existing items by default; a `material` item under \[Triage classes\]/);
  assert.match(followup, /fix other instances of the same bug class in the PR diff in the same round/);
  assert.doesNotMatch(followup, /Treat an item as pre-existing only when|occurs? at the PR base|not minor whatever its label|takes precedence/, "follow-up restates triage definitions");
});

test("PR skill guardrails keep only lines their workflow does not state", async () => {
  const guardrails = async (name) => sectionOf(await localSkill(name, "SKILL.md"), "Guardrails") ?? "";
  const cases = {
    "github-pr-publish": {
      kept: [/^- Do not create a PR from the default branch\.$/m, /^- Do not force push, merge, delete remote branches, rewrite history, or clean up worktrees\.$/m, /^- Do not stage dependency manifests or lockfiles/m, /^- Do not hardcode or print secrets/m],
      removed: [/until verification has succeeded/, /later targets/, /duplicate PRs/, /request AI, Copilot, Codex, or human review/],
    },
    "github-pr-create": {
      kept: [/^- Do not commit, push, merge, or request reviews\.$/m, /^- Do not hardcode or print secrets/m, /^- Do not modify repository files while preparing the PR body\.$/m, /^- If GitHub authentication, permissions, or branch publication blocks PR creation/m],
      removed: [/duplicate PR/, /head repository/],
    },
    "github-pr-publish-and-ai-review-request": {
      kept: [/^- Do not force push, merge, delete remote branches, or clean up worktrees\.$/m],
      removed: [/partial AI review failures/, /per-target record/],
    },
    "azure-devops-pr-publish": {
      kept: [/^- Do not create PRs from the default branch\.$/m, /^- Do not force push, rewrite history, merge, complete, or clean up worktrees\.$/m, /^- Do not hardcode or print secrets/m],
      removed: [/later targets/],
    },
  };
  for (const [name, { kept, removed }] of Object.entries(cases)) {
    const text = await guardrails(name);
    assert.ok(text, `${name}: missing Guardrails`);
    for (const rule of kept) assert.match(text, rule, `${name}: kept ${rule}`);
    for (const rule of removed) assert.doesNotMatch(text, rule, `${name}: restates ${rule}`);
  }
  const combined = flatText(await localSkill("github-pr-publish-and-ai-review-request", "SKILL.md"));
  assert.match(combined, /Capture the Copilot and Codex request status for the final report\./);
});
