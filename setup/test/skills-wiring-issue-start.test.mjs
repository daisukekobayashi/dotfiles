import assert from "node:assert/strict";
import { readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
} from "./skills-helpers.mjs";

const flat = (text) => text?.replace(/\s+/g, " ");
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const scriptClause = "where `<script>` is [`check-branch-name.mjs`](../delivery-common/scripts/check-branch-name.mjs) resolved from this skill's directory";
const quoteRule = "Write a name into this or any command only when it uses solely ASCII letters, digits, `/`, `.`, `_`, and `-`; any other name is not safe, without running the check.";
// The one-line run of the shared safe branch name check, as each calling step states it.
const safeBranchRun = (subject, args) => new RegExp(escapeRegExp(
  `Stop and report ${subject} unless it is a **safe branch name** before running any command with it: run \`node <script> -- ${args}\`, ${scriptClause}, and continue only on exit 0. ${quoteRule}`,
));
// Drops the check's own command, which single-quotes names on purpose.
const withoutCheckRuns = (text) => text.replace(/`node <script> -- [^`]*`/g, "");
const upstreamRead = /`git config --get-all branch\.<branch>\.remote` and `git config --get-all branch\.<branch>\.merge`[^.]*?no output means no upstream[^.]*?more than one value for either key[^.]*?stop and report/;

test("start skills create worktree branches without tracking the base", async () => {
  for (const start of ["github-issue-start", "azure-devops-work-item-start", "beads-issue-worktree"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", start, "SKILL.md"));
    const prep = skill.match(/\n## Worktree Preparation\n[\s\S]*?(?=\n## )/)?.[0];

    assert.ok(prep, `${start}: missing Worktree Preparation`);
    assert.match(prep, /`git worktree add --no-track -b <branch> <path> <base>`/, `${start}: --no-track`);
    assert.doesNotMatch(skill, /git worktree add -b/, `${start}: tracking worktree add`);
    assert.doesNotMatch(skill, /@\{upstream\}/, `${start}: @{upstream} hides a configured upstream whose ref is missing`);
    assert.doesNotMatch(skill, /%\(upstream/, `${start}: upstream format atoms need a remote-tracking ref`);
    const base = flat(prep.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.ok(base, `${start}: missing step 2`);
    assert.match(base, /^2\. Resolve the base\b/, `${start}: base resolved for reuse too`);
    const reuse = flat(prep.match(/^1\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.ok(reuse, `${start}: missing step 1`);
    assert.match(reuse, /Reuse[\s\S]*resolve its base as in step 2 and check its upstream as in step 5\./, `${start}: reuse check`);

    const check = flat(prep.match(/^5\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.ok(check, `${start}: missing step 5`);
    assert.match(check, upstreamRead, `${start}: upstream read`);
    assert.doesNotMatch(skill, /git config --get branch/, `${start}: --get returns the last of several values`);
    assert.match(check, /no upstream or the same-named branch on the publication remote/, `${start}: kept upstreams`);
    assert.match(check, /base or its local branch \(remote `\.`\)[\s\S]*`git branch --unset-upstream <branch>`/, `${start}: unset base upstream`);
    assert.match(check, /Stop and report any other upstream/, `${start}: report other upstream`);
  }

  const beads = await readText(path.join(repoRoot, "skills", "local", "beads-issue-worktree", "SKILL.md"));
  assert.match(beads, /`bd worktree create`[\s\S]*?Verify[^\n]*on either path/, "beads: bd path checked too");
});

test("start skills restrict branch names to shell-safe characters", async () => {
  for (const start of ["github-issue-start", "azure-devops-work-item-start", "beads-issue-worktree"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", start, "SKILL.md"));
    const workflow = flat(skill.match(/\n## Workflow\n[\s\S]*?(?=\n## )/)?.[0]);
    const prep = skill.match(/\n## Worktree Preparation\n[\s\S]*?(?=\n## )/)?.[0];

    assert.ok(workflow, `${start}: missing Workflow`);
    assert.match(workflow, /Derive `<slug>` from the [^.]*title using only lowercase ASCII letters, digits, and hyphens \(`\[a-z0-9-\]`\); drop or replace every other character\./, `${start}: slug charset`);
    assert.match(workflow, /If no characters remain, write a short English slug from the [^.]* content in the same character set\./, `${start}: empty slug`);
    assert.match(workflow, new RegExp(escapeRegExp(`A **safe branch name** passes \`node <script> -- '<name>'\` with exit 0, ${scriptClause}. ${quoteRule}`)), `${start}: safe branch check`);
    assert.match(workflow, /Use a branch name supplied by the user or reused from an existing worktree as-is only when it is a safe branch name; otherwise, including when the check cannot run, stop and report it before running any command with it\./, `${start}: unsafe branch stops`);

    assert.ok(prep, `${start}: missing Worktree Preparation`);
    const reuse = flat(prep.match(/^1\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.match(reuse, /reused branch[^.]*safe branch name/, `${start}: reused branch checked`);
    assert.doesNotMatch(withoutCheckRuns(skill), /["']<branch>["']/, `${start}: the charset rule replaces quoting <branch>`);
  }
});

const pushScriptClause = "where `<push-script>` is [`check-push-target.mjs`](../delivery-common/scripts/check-push-target.mjs) resolved from this skill's directory";
const pushTargetRule = "push only to the remote the user names, or the single remote that names the repository, with an explicit `<branch>:refs/heads/<branch>` refspec; with more than one remote and none named, ask.";

test("publish skills check the upstream with the push target script around a visible push", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    const push = flat(skill.match(/^7\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(push, `${publish}: missing push step`);
    assert.match(push, /`<remote>` is the [^.]*remote resolved in step 2\./, `${publish}: remote binding`);
    assert.match(push, /PR base branch is the existing PR's (base|target), otherwise[^.]*default branch unless the user specifies another/, `${publish}: base definition`);
    const pre = push.indexOf("`node <push-script> pre --branch '<branch>' --remote '<remote>' --base '<");
    const run = push.indexOf("`git push -u <remote> <branch>:refs/heads/<branch>`");
    const post = push.indexOf("`node <push-script> post --branch '<branch>' --remote '<remote>'`");
    assert.ok(pre >= 0 && run > pre && post > run, `${publish}: pre check, visible push, post check in order`);
    assert.match(push, /Continue only on exit 0, and report the note it prints when the push replaces a PR base upstream\. On exit 3, stop and report the upstream it names; it may back an existing PR\./, `${publish}: pre outcome`);
    assert.match(push, /stop and report unless it exits 0\./, `${publish}: post outcome`);
    assert.match(push, /stop and report an existing PR's (base|target) that does not use solely ASCII letters, digits, `\/`, `\.`, `_`, and `-`/, `${publish}: existing base written only when safe`);
    assert.doesNotMatch(push, /`git push -u <remote> <branch>`/, `${publish}: bare push follows push.default=upstream to the base`);
    assert.doesNotMatch(push, /normal push/, `${publish}: every push case uses the refspec`);
    assert.doesNotMatch(push, /git config --get-all|Re-read the upstream/, `${publish}: upstream prose moved into the script`);
  }
});

test("publish skills check the branch name and resolve the push remote with the push target script", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    const context = flat(skill.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(context, `${publish}: missing step 2`);
    assert.match(context, safeBranchRun("the branch", "'<branch>'"), `${publish}: safe branch name`);
    assert.match(context, /leading `\+`[^.]*force push/, `${publish}: + refspec refused`);
    assert.match(context, new RegExp(escapeRegExp(`by the **push target rule**: ${pushTargetRule}`)), `${publish}: push target rule`);
    assert.match(context, new RegExp(escapeRegExp(pushScriptClause)), `${publish}: script link`);
    assert.match(context, /adding `--remote '<name>'` when the user names a remote that uses solely ASCII letters, digits, `\/`, `\.`, `_`, and `-` \(ask again for any other name\)/, `${publish}: user-named remote written only when safe`);
    assert.match(context, /On exit 3, stop and ask the user to name the remote, listing the candidates it reports; stop and report any other status\./, `${publish}: exit handling`);
    assert.doesNotMatch(context, /git remote -v|ignoring the scheme|decoding percent-encoding|letter case/, `${publish}: URL normalization moved into the script`);
  }

  const github = flat(await readText(path.join(repoRoot, "skills", "local", "github-pr-publish", "SKILL.md")));
  assert.match(github, /`node <push-script> resolve --github '<host>' '<owner>\/<repo>'` with the resolved repository's `url` host and `nameWithOwner`/, "github: resolve run");
  assert.match(github, /On exit 0, line 1 is `<remote>` and line 2 is the head repository `<owner>\/<repo>`\./, "github: resolve output");
  const azure = flat(await readText(path.join(repoRoot, "skills", "local", "azure-devops-pr-publish", "SKILL.md")));
  assert.match(azure, /`node <push-script> resolve --azure '<org>' '<project>' '<repo>'` with the resolved organization, project, and repository/, "azure: resolve run");
  assert.match(azure, /accepted remote URL shapes from the common context/, "azure: URL shapes from the common context");
});

test("azure-devops-pr-publish writes the Azure DevOps names into the push target check only when safe", async () => {
  const skill = await readText(path.join(repoRoot, "skills", "local", "azure-devops-pr-publish", "SKILL.md"));
  const context = flat(skill.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

  assert.ok(context, "missing step 2");
  assert.match(context, /with the resolved organization, project, and repository, percent-decoded \(`My Project`, not `My%20Project`\), writing each into the command only when it uses solely ASCII letters, digits, space, `\.`, `_`, and `-` \(otherwise stop and report\)/, "org, project, and repo written only when safe");
});

test("GitHub skills write the host and repository into the push target check only when safe", async () => {
  const gate = "writing the host into the command only when it uses solely ASCII letters, digits, `.`, and `-`, optionally followed by `:` and digits, and `<owner>/<repo>` only when it uses solely ASCII letters, digits, `.`, `_`, `-`, and one `/` (otherwise stop and report)";
  for (const name of ["github-pr-publish", "github-pr-create", "github-pr-codex-review-cycle"]) {
    const skill = flat(await readText(path.join(repoRoot, "skills", "local", name, "SKILL.md")));
    const run = skill.indexOf("`node <push-script> resolve --github '<");
    assert.ok(run >= 0, `${name}: missing resolve run`);
    const gated = skill.indexOf(gate, run);
    assert.ok(gated > run && gated - run < 400, `${name}: host and repository written only when safe`);
  }
});

test("publish skills drop the fork-layout lookups", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const context = flat((await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"))).match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(context, `${publish}: missing step 2`);
    assert.doesNotMatch(context, /parent,isFork|fork layout|has a parent|fork of a fork|set-default/, `${publish}: fork-layout check removed`);
    assert.match(context, /with more than one remote and none named, ask\./, `${publish}: several remotes ask instead`);
  }
});

test("PR create and cleanup skills check the branch name in step 1", async () => {
  for (const name of [
    "github-pr-create",
    "azure-devops-pr-create",
    "github-worktree-cleanup",
    "azure-devops-worktree-cleanup",
    "beads-merge-cleanup",
  ]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", name, "SKILL.md"));
    const step1 = flat(skill.match(/^1\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(step1, `${name}: missing step 1`);
    assert.match(step1, safeBranchRun("the branch", "'<branch>'"), `${name}: branch checked in step 1`);
    assert.doesNotMatch(withoutCheckRuns(skill), /["']<(?:feature-)?branch>["']/, `${name}: the charset rule replaces quoting <branch>`);
  }
});

test("azure-devops-work-item-start skips comparing an open PR with an unsafe branch name", async () => {
  const skill = await readText(path.join(repoRoot, "skills", "local", "azure-devops-work-item-start", "SKILL.md"));
  const step2 = flat(skill.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

  assert.ok(step2, "missing step 2");
  const check = step2.search(new RegExp(escapeRegExp(
    `For each PR, check its source and target names as \`az repos pr list\` returns them before running any command with them. When either name uses any character other than ASCII letters, digits, \`/\`, \`.\`, \`_\`, and \`-\`, it is not a **safe branch name**: skip that PR's comparison without writing the names into any command, report the PR and its branch as not compared, and continue. Otherwise run \`node <script> -- '<target>' '<source>'\`, ${scriptClause}. When it exits 3, or exits non-zero with stderr of one or more \`unsafe branch name: \` lines and nothing else, skip and report that PR the same way and continue. On any other non-zero exit, including when the check cannot run, stop and report it. On exit 0, compare`,
  )));
  assert.ok(check >= 0, "the ASCII gate precedes the check; only a name outside the ASCII set, exit 3, or unsafe-only stderr skips the PR, and other failures stop");
  assert.ok(step2.indexOf("any character other than ASCII letters") < step2.indexOf("`node <script> --"), "ASCII gate precedes writing the names into the check");
  assert.ok(check < step2.indexOf("available as local or remote-tracking refs"), "names checked before the ref availability check");
  assert.ok(check < step2.indexOf("git diff --name-only"), "names checked before git diff");
});

test("PR create and publish skills check base and target names with the same script", async () => {
  for (const [name, subject, arg] of [
    ["github-pr-create", "the base branch, the default branch unless the user specifies another base,", "base"],
    ["azure-devops-pr-create", "the target branch, the default branch unless the user specifies another target,", "target"],
  ]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", name, "SKILL.md"));
    const step1 = flat(skill.match(/^1\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(step1, `${name}: missing step 1`);
    assert.match(
      step1,
      new RegExp(escapeRegExp(
        `Stop and report ${subject} unless it is a **safe branch name** before running any command with it: run \`node <script> -- '<${arg}>'\` with the script above, and continue only on exit 0. ${quoteRule}`,
      )),
      `${name}: ${arg} checked in step 1`,
    );
  }

  for (const [name, target] of [["github-pr-publish", "base"], ["azure-devops-pr-publish", "target"]]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", name, "SKILL.md"));
    const step2 = flat(skill.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(step2, `${name}: missing step 2`);
    assert.match(
      step2,
      new RegExp(escapeRegExp(
        `Stop and report the default branch, and a ${target} the user specifies, unless each is a **safe branch name** before running any command with it: run \`node <script> -- '<default branch>'\`, adding \`'<${target}>'\` when the user specifies one, with the script above, and continue only on exit 0. ${quoteRule}`,
      )),
      `${name}: default branch and ${target} checked in step 2`,
    );
  }
});

test("skills state the safe branch name rule only through the shared script", async () => {
  const skillsDir = path.join(repoRoot, "skills", "local");
  const callers = [];
  for (const name of await readdir(skillsDir)) {
    const file = path.join(skillsDir, name, "SKILL.md");
    if (!existsSync(file)) continue;
    const skill = await readText(file);
    assert.doesNotMatch(skill, /\[A-Za-z0-9\/\._-\]/, `${name}: restates the safe branch name charset`);
    if (skill.includes("../delivery-common/scripts/check-branch-name.mjs")) callers.push(name);
  }

  assert.deepEqual(callers.sort(), [
    "azure-devops-pr-create",
    "azure-devops-pr-publish",
    "azure-devops-work-item-delivery",
    "azure-devops-work-item-start",
    "azure-devops-worktree-cleanup",
    "beads-issue-worktree",
    "beads-merge-cleanup",
    "github-issue-delivery",
    "github-issue-start",
    "github-pr-codex-review-cycle",
    "github-pr-create",
    "github-pr-publish",
    "github-worktree-cleanup",
  ]);
  assert.equal(existsSync(path.join(skillsDir, "delivery-common", "scripts", "check-branch-name.mjs")), true);
});
