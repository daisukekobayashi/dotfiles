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
    assert.match(reuse, /Reuse[\s\S]*check its upstream as in step 5\./, `${start}: reuse check`);

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

test("publish skills replace a base upstream and report any other mismatch", async () => {
  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    const push = flat(skill.match(/^7\. [\s\S]*?(?=\n\d\. )/m)?.[0]);

    assert.ok(push, `${publish}: missing push step`);
    assert.match(push, upstreamRead, `${publish}: upstream read`);
    assert.match(push, /same branch name on the [^\n]*remote, use a normal push\./, `${publish}: same-named upstream`);
    assert.match(push, /If no upstream exists, set upstream for the same branch name\./, `${publish}: first-push upstream`);
    assert.match(push, /PR base branch, local or remote-tracking[\s\S]*`git push -u <remote> <branch>`[\s\S]*report the replacement/, `${publish}: replace base upstream`);
    assert.match(push, /Stop and report any other upstream/, `${publish}: report other upstream`);
  }
});
