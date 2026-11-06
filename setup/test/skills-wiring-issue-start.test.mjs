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
const quoteRule = "A name containing `'` or a newline is not safe; do not write it into any command.";
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

test("publish skills push with an explicit refspec and recheck the upstream", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    const push = flat(skill.match(/^7\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(push, `${publish}: missing push step`);
    assert.match(push, /`<remote>` is the [^.]*remote resolved in step 2\./, `${publish}: remote binding`);
    assert.match(push, /PR base branch is the existing PR's (base|target), otherwise[^.]*default branch unless the user specifies another/, `${publish}: base definition`);
    assert.match(push, upstreamRead, `${publish}: upstream read`);
    assert.doesNotMatch(push, /%\(upstream/, `${publish}: upstream format atoms need a remote-tracking ref`);
    assert.doesNotMatch(push, /git config --get branch/, `${publish}: --get returns the last of several values`);
    assert.match(push, /Continue when there is no upstream, the same branch name on `<remote>`, or the PR base branch, either local \(remote `\.`\) or remote-tracking\./, `${publish}: accepted upstreams`);
    assert.match(push, /Stop and report any other upstream/, `${publish}: report other upstream`);
    assert.match(push, /`git push -u <remote> <branch>:refs\/heads\/<branch>`/, `${publish}: explicit refspec`);
    assert.doesNotMatch(push, /`git push -u <remote> <branch>`/, `${publish}: bare push follows push.default=upstream to the base`);
    assert.doesNotMatch(push, /normal push/, `${publish}: every push case uses the refspec`);
    assert.match(push, /sets the upstream for the same branch name/, `${publish}: first-push upstream`);
    assert.match(push, /Re-read the upstream; stop and report unless the remote is `<remote>` and the merge ref is `refs\/heads\/<branch>`\./, `${publish}: post-push recheck`);
  }
});

test("publish skills check the branch name and resolve one push remote", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    const context = flat(skill.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(context, `${publish}: missing step 2`);
    assert.match(context, safeBranchRun("the branch", "'<branch>'"), `${publish}: safe branch name`);
    assert.match(context, /leading `\+`[^.]*force push/, `${publish}: + refspec refused`);
    assert.match(context, /Use the remote the user names\./, `${publish}: user-named remote`);
    assert.match(context, /Otherwise `<remote>` is the one remote whose fetch URL and every push URL \(`git remote -v`\)/, `${publish}: URL-matched remote`);
    assert.match(context, /Stop and report the candidates when more than one remote matches\./, `${publish}: several matches stop`);
    assert.match(context, /When none matches, as with an SSH host alias, stop and ask the user to name the remote\./, `${publish}: no match asks for a remote`);
  }

  const github = flat(await readText(path.join(repoRoot, "skills", "local", "github-pr-publish", "SKILL.md")));
  assert.match(github, /ignoring the scheme, user, letter case, and a trailing `\.git` or `\/`/, "github: URL normalization");
  const azure = flat(await readText(path.join(repoRoot, "skills", "local", "azure-devops-pr-publish", "SKILL.md")));
  assert.match(azure, /accepted remote URL shapes/, "azure: URL shapes from the common context");
  assert.match(azure, /decoding percent-encoding \(`My%20Project` is `My Project`\) and ignoring letter case, the `user@` part, and a trailing `\.git` or `\/`/, "azure: URL normalization");
});

test("github-pr-publish stops in an unresolved fork layout", async () => {
  const skill = await readText(path.join(repoRoot, "skills", "local", "github-pr-publish", "SKILL.md"));
  const context = flat(skill.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

  assert.ok(context, "missing step 2");
  assert.doesNotMatch(context, /set-default|shows no default/, "gh's default names the PR base, not the push target");
  assert.match(context, /Check every other remote: stop and ask the user to name the remote when its repository or the resolved repository has a parent/, "any parent asks for a remote");
  assert.match(context, /has a parent, when its fetch URL and push URLs name different repositories \(normalized as above\), or when the check cannot finish/, "split fetch and push repositories stop");
  assert.match(context, /`gh repo view <owner>\/<repo> --json parent,isFork`/, "parent lookup");
  assert.match(context, /Look up the resolved repository and each other remote's repository with `gh repo view <owner>\/<repo> --json parent,isFork`;/, "both repositories looked up");
  assert.match(context, /a repository \*\*has a parent\*\* when `parent` is not null or `isFork` is true/, "isFork counts as a parent");
  assert.match(context, /rule out a fork layout when at least one other remote exists[^.]*\. With no other remote, skip this check\./, "a lone remote skips the check");
  assert.match(context, /cannot rule out a fork of a fork or a cousin fork/, "fork of a fork stops");
  assert.doesNotMatch(context, /fork network|both are forks with the same parent/, "direct-parent comparison removed");
  assert.match(context, /any of its fetch or push URLs does not name an `<owner>\/<repo>` on the resolved repository's host/, "every remote URL checked");
  assert.match(context, /or a parent lookup fails[^.]*a failed lookup is not "no parent"/, "failed lookup fails closed");
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
    `For each PR, check its source and target names as \`az repos pr list\` returns them before running any command with them: run \`node <script> -- '<target>' '<source>'\`, ${scriptClause}. When either name contains \`'\` or a newline, or the check exits 1, they are not both a **safe branch name**: skip that PR's comparison without writing the names into any command, report the PR and its branch as not compared, and continue. On any other non-zero exit, including when the check cannot run, stop and report it. On exit 0, compare`,
  )));
  assert.ok(check >= 0, "both names checked by the script; only exit 1 or an unquotable name skips the PR, and other failures stop");
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
