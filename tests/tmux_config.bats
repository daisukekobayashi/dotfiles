#!/usr/bin/env bats

load 'helpers/test_helper.bash'

@test "tmux does not enable C-b as a global secondary prefix" {
  run grep -Eq '^set[[:space:]]+-g[[:space:]]+prefix2[[:space:]]+C-b([[:space:]]|$)' "$(repo_root)/.tmux.conf"

  [ "$status" -ne 0 ]
}

@test "tmux-palette opens gitui and btop directly without relaunching palette" {
  run node -e '
const fs = require("fs");
const items = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const byTitle = new Map(items.map((item) => [item.title, item]));

if (byTitle.has("Tools...")) {
  throw new Error("Tools submenu should not be required for gitui or btop");
}

for (const title of ["gitui", "btop"]) {
  const item = byTitle.get(title);
  if (!item) throw new Error(`${title} is missing from commands.json`);
  if (item.category !== "Tools") throw new Error(`${title} is not in Tools`);
  if (item.action && Object.prototype.hasOwnProperty.call(item.action, "popup")) {
    throw new Error(`${title} should not use popup action because it relaunches the palette`);
  }
  if (!item.action || typeof item.action.tmux !== "string") {
    throw new Error(`${title} does not open with a tmux action`);
  }
  if (!item.action.tmux.includes("display-popup")) {
    throw new Error(`${title} does not open a tmux popup`);
  }
}

const btop = byTitle.get("btop");
if (!btop.action.tmux.includes("mise exec github:aristocratos/btop@1.4 -- btop")) {
  throw new Error("btop should run through mise exec so tmux does not depend on a stale PATH");
}
' "$(repo_root)/tmux/tmux-palette/commands.json"

  [ "$status" -eq 0 ]
}
