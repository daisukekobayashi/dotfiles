import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
} from "./skills-helpers.mjs";

const flat = (text) => text?.replace(/\s+/g, " ");
const upstreamRead = /`git for-each-ref --format='%\(upstream:short\)' refs\/heads\/<branch>`/;

test("start skills create worktree branches without tracking the base", async () => {
  for (const start of ["github-issue-start", "azure-devops-work-item-start", "beads-issue-worktree"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", start, "SKILL.md"));
    const prep = skill.match(/\n## Worktree Preparation\n[\s\S]*?(?=\n## )/)?.[0];

    assert.ok(prep, `${start}: missing Worktree Preparation`);
    assert.match(prep, /`git worktree add --no-track -b <branch> <path> <base>`/, `${start}: --no-track`);
    assert.doesNotMatch(skill, /git worktree add -b/, `${start}: tracking worktree add`);
    assert.doesNotMatch(skill, /@\{upstream\}/, `${start}: @{upstream} hides a configured upstream whose ref is missing`);
    const reuse = flat(prep.match(/^1\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.ok(reuse, `${start}: missing step 1`);
    assert.match(reuse, /Reuse[\s\S]*resolve its base as in step 2 and check its upstream as in step 5\./, `${start}: reuse check`);
    const base = flat(prep.match(/^2\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.doesNotMatch(base ?? "", /^2\. For a new workspace/, `${start}: base resolved for reuse too`);

    const check = flat(prep.match(/^5\. [\s\S]*?(?=\n\d\. )/m)?.[0]);
    assert.ok(check, `${start}: missing step 5`);
    assert.match(check, upstreamRead, `${start}: upstream read`);
    assert.match(check, /no upstream or the same-named branch on the publication remote/, `${start}: kept upstreams`);
    assert.match(check, /base or its local branch[\s\S]*`git branch --unset-upstream <branch>`/, `${start}: unset base upstream`);
    assert.match(check, /Stop and report any other upstream/, `${start}: report other upstream`);
  }

  const beads = await readText(path.join(repoRoot, "skills", "local", "beads-issue-worktree", "SKILL.md"));
  assert.match(beads, /`bd worktree create`[\s\S]*?Verify[^\n]*on either path/, "beads: bd path checked too");
});

test("publish skills push with an explicit refspec and recheck the upstream", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    const push = flat(skill.match(/^7\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(push, `${publish}: missing push step`);
    assert.match(push, /`<remote>` is the [^.]*remote resolved in step 2\./, `${publish}: remote binding`);
    assert.match(push, /PR base branch is the existing PR's (base|target), otherwise[^.]*default branch unless the user specifies another/, `${publish}: base definition`);
    assert.match(push, upstreamRead, `${publish}: upstream read`);
    assert.match(push, /Continue when there is no upstream, the same branch name on `<remote>`, or the PR base branch, local or remote-tracking\./, `${publish}: accepted upstreams`);
    assert.match(push, /Stop and report any other upstream/, `${publish}: report other upstream`);
    assert.match(push, /`git push -u <remote> <branch>:refs\/heads\/<branch>`/, `${publish}: explicit refspec`);
    assert.doesNotMatch(push, /`git push -u <remote> <branch>`/, `${publish}: bare push follows push.default=upstream to the base`);
    assert.doesNotMatch(push, /normal push/, `${publish}: every push case uses the refspec`);
    assert.match(push, /sets the upstream for the same branch name/, `${publish}: first-push upstream`);
    assert.match(push, /Re-read the upstream; stop and report unless it is `<remote>\/<branch>`\./, `${publish}: post-push recheck`);
  }
});
