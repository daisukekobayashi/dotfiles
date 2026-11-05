import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
} from "./skills-helpers.mjs";

const flat = (text) => text?.replace(/\s+/g, " ");
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
    assert.match(workflow, /A \*\*safe branch name\*\* uses only `\[A-Za-z0-9\/._-\]`\./, `${start}: safe branch charset`);
    assert.match(workflow, /Use a branch name supplied by the user or reused from an existing worktree as-is only when it is a safe branch name; otherwise stop and report it before running any command with it\./, `${start}: unsafe branch stops`);

    assert.ok(prep, `${start}: missing Worktree Preparation`);
    const reuse = flat(prep.match(/^1\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.match(reuse, /reused branch[^.]*safe branch name/, `${start}: reused branch checked`);
    assert.doesNotMatch(skill, /["']<branch>["']/, `${start}: the charset rule replaces quoting <branch>`);
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
    assert.match(context, /Stop and report the branch unless it is a \*\*safe branch name\*\*, using only `\[A-Za-z0-9\/._-\]`, before running any command with it\./, `${publish}: safe branch name`);
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
  assert.match(context, /Check every other remote: stop and ask the user to name the remote when its repository is in the resolved repository's fork network/, "fork layout asks for a remote");
  assert.match(context, /`gh repo view <owner>\/<repo> --json parent`/, "fork network lookup");
  assert.match(context, /Look up the parent of the resolved repository and of each other remote's repository with `gh repo view <owner>\/<repo> --json parent`\./, "both parents looked up");
  assert.match(context, /one is the other's parent, or both are forks with the same parent/, "shared parent means both are forks");
  assert.match(context, /any of its fetch or push URLs does not name an `<owner>\/<repo>` on the resolved repository's host/, "every remote URL checked");
  assert.match(context, /or a parent lookup fails[^.]*a failed lookup is not "no parent"/, "failed lookup fails closed");
});
