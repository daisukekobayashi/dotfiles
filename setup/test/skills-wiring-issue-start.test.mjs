import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import {
  repoRoot,
  readText,
} from "./skills-helpers.mjs";

test("issue start skills create worktree branches without tracking the base", async () => {
  for (const start of ["github-issue-start", "azure-devops-work-item-start"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", start, "SKILL.md"));
    assert.match(skill, /`git worktree add --no-track -b <branch> <path> <base>`/, `${start}: --no-track`);
    assert.doesNotMatch(skill, /git worktree add -b/, `${start}: tracking worktree add`);
    assert.match(skill, /`git rev-parse --abbrev-ref <branch>@\{upstream\}`\s+reports no upstream/, `${start}: upstream check`);
    assert.match(skill, /`git branch --unset-upstream <branch>`/, `${start}: unset upstream`);
  }

  for (const publish of ["github-pr-publish", "azure-devops-pr-publish"]) {
    const skill = await readText(path.join(repoRoot, "skills", "local", publish, "SKILL.md"));
    assert.match(skill, /If no upstream exists, set upstream for the same branch name\./, `${publish}: first-push upstream`);
  }
});
