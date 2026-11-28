#!/usr/bin/env python3
"""Prepare one isolated candidate workspace for the evaluate-skill workflow."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import tomllib
from urllib.parse import unquote

# Runner features that would let a candidate reach the runner's own hooks,
# plugins, apps, or memories; MCP servers are disabled by name below.
CODEX_DISABLED_FEATURES = ("hooks", "memories", "plugins", "apps")
# Relative path text in any syntax: links, code, HTML attributes, or prose.
RELATIVE_PATH = re.compile(r"(?<![\w./~%-])\.\.?/[^\s`'\"<>()\[\]{}|*]*")
COPY_IGNORED = {"evals", "__pycache__"}
BARE_KEY = re.compile(r"[A-Za-z0-9_-]+")


def digest_tree(root):
    return {
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def fixture_path(suite_dir, value):
    path = suite_dir / value
    if not path.resolve().is_relative_to(suite_dir.resolve()) or not path.is_dir():
        raise ValueError(f"Fixture must be a directory inside the suite: {value}")
    if path.is_symlink() or any(p.is_symlink() for p in path.rglob("*")):
        raise ValueError(f"Fixture must not contain symlinks: {value}")
    return path


def codex_launch(workspace, skill, name):
    config_root = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
    config_file = config_root / "config.toml"
    config = tomllib.loads(config_file.read_text()) if config_file.is_file() else {}
    overrides = list(config.get("skills", {}).get("config", []))
    locations = [skill, Path.home() / ".agents/skills" / name,
                 config_root / "skills" / name]
    targets = {str(path) for folder in locations for path in (folder, folder / "SKILL.md")}
    overrides = [entry for entry in overrides if entry["path"] not in targets]
    overrides.extend({"path": path, "enabled": False} for path in sorted(targets))
    encoded = ", ".join(
        "{path=" + json.dumps(entry["path"]) + ",enabled="
        + str(entry.get("enabled", True)).lower() + "}"
        for entry in overrides
    )
    argv = ["codex", "--cd", str(workspace), "-c", f"skills.config=[{encoded}]"]
    for feature in CODEX_DISABLED_FEATURES:
        argv += ["--disable", feature]
    # `-c mcp_servers={}` leaves configured servers running, so each is disabled by name.
    for server in sorted(config.get("mcp_servers", {})):
        if not BARE_KEY.fullmatch(server):
            raise ValueError(f"Cannot disable MCP server with a non-bare name: {server!r}")
        argv += ["-c", f"mcp_servers.{server}.enabled=false"]
    return argv


def unsupplied_links(supplied):
    """Return relative path references in the supplied guidance to sibling skill
    content that the guidance copy does not contain."""
    names = {source.name for source in supplied}
    root = supplied[0].parent
    missing = set()
    for source in supplied:
        for page in sorted(source.rglob("*.md")):
            if COPY_IGNORED & set(page.relative_to(source).parts):
                continue
            for text in RELATIVE_PATH.findall(page.read_text()):
                path = unquote(re.split(r"[#?]", text, maxsplit=1)[0].rstrip(".,;:!"))
                resolved = Path(os.path.normpath(page.parent / path))
                if not resolved.is_relative_to(root):
                    continue
                parts = resolved.relative_to(root).parts
                # Paths into no existing skill directory are examples, not references.
                if parts and parts[0] not in names and not (root / parts[0]).is_dir():
                    continue
                # The skills root itself, another skill, or a path the copy skips is not supplied.
                if not parts or parts[0] not in names or COPY_IGNORED & set(parts[1:]):
                    missing.add(f"{page.relative_to(root)} -> {text}")
    return sorted(missing)


def prepare(suite_path, case_id, agent, variant, output, skill_source=None):
    suite_path = suite_path.resolve()
    suite = json.loads(suite_path.read_text())
    case = next((item for item in suite["evals"] if item["id"] == case_id), None)
    if case is None:
        raise ValueError(f"Unknown case: {case_id}")
    skill = (skill_source or suite_path.parent.parent).resolve()
    if not (skill / "SKILL.md").is_file():
        raise ValueError(f"Missing SKILL.md: {skill}")
    sources = [fixture_path(suite_path.parent, case["fixture"])]
    if case.get("overlay"):
        sources.append(fixture_path(suite_path.parent, case["overlay"]))
    supporting = [skill.parent / name for name in suite.get("supporting_skills", [])]
    for source in supporting:
        if source.parent != skill.parent or not (source / "SKILL.md").is_file():
            raise ValueError(f"Missing sibling supporting skill: {source}")
    if variant == "with-skill":
        missing = unsupplied_links([skill, *supporting])
        if missing:
            raise ValueError("Supplied guidance refers to sibling skill content it does not "
                             "contain; add those skills to supporting_skills: " + "; ".join(missing))

    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    # Candidate paths carry neither treatment labels nor the judging rubric.
    workspace = Path(tempfile.mkdtemp(prefix="workspace-"))
    try:
        for source in sources:
            shutil.copytree(source, workspace, dirs_exist_ok=True)
        canonical = workspace / ".agents/skills"
        if canonical.is_dir():
            claude_skills = workspace / ".claude/skills"
            claude_skills.mkdir(parents=True, exist_ok=True)
            for target in canonical.iterdir():
                (claude_skills / target.name).symlink_to(
                    Path("../../.agents/skills") / target.name, target_is_directory=True
                )
        initial_files = digest_tree(workspace)
        prompt = case["prompt"] + "\nWork only in this project. Retain evidence and report its location.\n"
        guidance_files = {}
        if variant == "with-skill":
            guidance = workspace / ".guidance/skills"
            for source in [skill, *supporting]:
                shutil.copytree(
                    source, guidance / source.name,
                    ignore=shutil.ignore_patterns(*COPY_IGNORED),
                )
            guidance_files = digest_tree(guidance)
            prompt = (
                f"Use the {suite['skill_name']} skill at "
                f".guidance/skills/{skill.name}/SKILL.md for this task.\n\n" + prompt
            )
        (output / "prompt.txt").write_text(prompt)

        # Both variants suppress the installed target; treatment is supplied above.
        # Both also drop the runner's hooks, plugins, memories, and MCP servers.
        name = suite["skill_name"]
        if agent == "codex":
            argv = codex_launch(workspace, skill, name)
        else:
            argv = ["claude", "--disable-slash-commands", "--safe-mode"]
        metadata = {
            "agent": agent, "variant": variant, "case_id": case_id,
            "suite": str(suite_path), "workspace": str(workspace),
            "prompt_file": str(output / "prompt.txt"), "launch_argv": argv,
            "skill_sha256": hashlib.sha256((skill / "SKILL.md").read_bytes()).hexdigest(),
            "guidance_files": guidance_files,
            "initial_files": initial_files,
            "status": "prepared", "model": None, "total_tokens": None,
            "total_duration_seconds": None,
        }
        (output / "run.json").write_text(json.dumps(metadata, indent=2) + "\n")
    except BaseException:
        shutil.rmtree(workspace)
        raise
    return metadata


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", type=Path, required=True)
    parser.add_argument("--case", type=int, required=True)
    parser.add_argument("--agent", choices=("codex", "claude"), required=True)
    parser.add_argument("--variant", choices=("with-skill", "without-skill"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--skill-source", type=Path, help="Optional old-version snapshot")
    args = parser.parse_args()
    try:
        result = prepare(args.suite, args.case, args.agent, args.variant,
                         args.output, args.skill_source)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
