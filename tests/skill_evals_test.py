import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
from unittest import mock

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "prepare", ROOT / "skills/local/evaluate-skill/scripts/prepare.py"
)
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)
SUITE = ROOT / "skills/local/maintain-verification-skill/evals/evals.json"
TRIAGE_SUITE = ROOT / "skills/local/github-issue-triage/evals/evals.json"
STAGE_SPEC = importlib.util.spec_from_file_location("stage_gh", TRIAGE_SUITE.parent / "stage_gh.py")
STAGE = importlib.util.module_from_spec(STAGE_SPEC)
STAGE_SPEC.loader.exec_module(STAGE)


class SkillEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="skill-check-")
        self.root = Path(self.temp.name)
        self.workspaces = []
        self.staged = []

    def tearDown(self):
        for dest in self.staged:
            for path in (dest, dest / "bin", dest / ".snapshot"):
                if path.is_dir():
                    path.chmod(0o755)
        for workspace in self.workspaces:
            shutil.rmtree(workspace)
        self.temp.cleanup()

    def prepare(self, case, agent="codex", variant="with-skill", **kwargs):
        result = PREPARE.prepare(
            SUITE, case, agent, variant,
            self.root / f"run-{len(self.workspaces)}", **kwargs,
        )
        self.workspaces.append(Path(result["workspace"]))
        return result

    def test_both_agents_receive_identical_case_inputs_and_isolated_copies(self):
        source_before = PREPARE.digest_tree(SUITE.parent)
        for case in (1, 2, 3):
            baseline = None
            for agent in ("codex", "claude"):
                for variant in ("with-skill", "without-skill"):
                    with self.subTest(case=case, agent=agent, variant=variant):
                        result = self.prepare(case, agent, variant)
                        # macOS temp paths under /var resolve to /private/var.
                        workspace = Path(result["workspace"]).resolve()
                        self.assertEqual(result["status"], "prepared")
                        self.assertIsNone(result["total_tokens"])
                        if baseline is None:
                            baseline = result["initial_files"]
                        self.assertEqual(result["initial_files"], baseline)
                        self.assertEqual(
                            (workspace / ".claude/skills/verify-sample").resolve(),
                            workspace / ".agents/skills/verify-sample",
                        )
                        self.assertFalse((workspace / "evals.json").exists())
                        guidance = workspace / ".guidance/skills"
                        self.assertEqual(guidance.exists(), variant == "with-skill")
                        if guidance.exists():
                            self.assertTrue((guidance / "principle-prove-it-works/SKILL.md").is_file())
                            self.assertTrue((guidance / "create-verification-skill/references/verification-contract.md").is_file())
                            self.assertFalse((guidance / "maintain-verification-skill/evals").exists())
                        (workspace / "app.py").write_text("local change\n")
        self.assertEqual(PREPARE.digest_tree(SUITE.parent), source_before)

    def run_app(self, result, *args):
        return subprocess.run(
            [sys.executable, "app.py", *args], cwd=result["workspace"],
            capture_output=True, text=True, check=False,
        )

    def test_fixture_failures_are_observable_through_the_real_cli(self):
        outdated = self.prepare(1)
        self.assertEqual(self.run_app(outdated, "format", "hello").returncode, 2)
        correct = self.run_app(outdated, "render", "hello")
        self.assertEqual((correct.returncode, correct.stdout), (0, "HELLO\n"))
        regression = self.run_app(self.prepare(2), "render", "hello")
        self.assertEqual((regression.returncode, regression.stdout), (0, "hello\n"))
        unavailable = self.prepare(3)
        self.assertEqual(self.run_app(unavailable, "render", "hello").stdout, "HELLO\n")
        premium = self.run_app(unavailable, "premium")
        self.assertEqual(premium.returncode, 78)
        self.assertIn("entitlement", premium.stderr)

    def test_existing_output_is_preserved(self):
        output = self.root / "existing"
        output.mkdir()
        (output / "keep.txt").write_text("keep")
        with self.assertRaises(FileExistsError):
            PREPARE.prepare(SUITE, 1, "codex", "with-skill", output)
        self.assertEqual((output / "keep.txt").read_text(), "keep")

    def test_failed_overlay_copy_removes_only_the_new_candidate(self):
        suite = self.root / "evals/evals.json"
        fixture = suite.parent / "fixture"
        overlay = suite.parent / "overlay"
        fixture.mkdir(parents=True)
        (overlay / "entry").mkdir(parents=True)
        (self.root / "SKILL.md").write_text("# Sample skill\n")
        (fixture / "entry").write_text("base file\n")
        (overlay / "entry/case.txt").write_text("overlay file\n")
        suite.write_text(json.dumps({
            "skill_name": "sample-skill",
            "evals": [{
                "id": 1, "fixture": "fixture", "overlay": "overlay", "prompt": "Evaluate."
            }],
        }))
        scratch = self.root / "scratch"
        existing = scratch / "workspace-existing"
        existing.mkdir(parents=True)
        (existing / "keep.txt").write_text("keep")
        output = self.root / "run"

        with mock.patch.object(PREPARE.tempfile, "tempdir", str(scratch)):
            with self.assertRaises(shutil.Error):
                PREPARE.prepare(suite, 1, "claude", "with-skill", output)

        self.assertEqual(list(scratch.iterdir()), [existing])
        self.assertEqual((existing / "keep.txt").read_text(), "keep")
        self.assertTrue(output.is_dir())
        self.assertFalse((output / "run.json").exists())

    def test_fixture_path_rejects_escapes_and_symlinks(self):
        suite_dir = self.root / "suite"
        suite_dir.mkdir()
        outside = self.root / "outside"
        outside.mkdir()
        with self.assertRaises(ValueError):
            PREPARE.fixture_path(suite_dir, "../outside")
        linked = suite_dir / "linked"
        linked.mkdir()
        (linked / "escape").symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            PREPARE.fixture_path(suite_dir, "linked")

    def test_each_agent_has_a_launch_command_without_bypassing_permissions(self):
        for agent in ("codex", "claude"):
            result = self.prepare(1, agent)
            argv = result["launch_argv"]
            self.assertEqual(argv[0], agent)
            self.assertNotIn("danger", " ".join(argv))
            if agent == "claude":
                self.assertIn("--disable-slash-commands", argv)
            else:
                self.assertIn("enabled=false", argv[-1])
            saved = json.loads(Path(result["prompt_file"]).with_name("run.json").read_text())
            self.assertEqual(saved, result)

    def test_codex_override_preserves_unrelated_skill_settings(self):
        config = self.root / "config.toml"
        config.write_text(
            '[[skills.config]]\npath = "/skills/unrelated/SKILL.md"\nenabled = false\n'
        )
        with mock.patch.object(PREPARE.os, "environ", {"CODEX_HOME": str(self.root)}):
            argv = PREPARE.codex_launch(self.root, SUITE.parent.parent, "maintain-verification-skill")
        overrides = tomllib.loads(argv[-1])["skills"]["config"]
        self.assertIn({"path": "/skills/unrelated/SKILL.md", "enabled": False}, overrides)
        self.assertEqual(config.read_text(),
                         '[[skills.config]]\npath = "/skills/unrelated/SKILL.md"\nenabled = false\n')

    def check_claude_policy(self, suite, claude):
        settings = json.loads((suite.parent / claude["claude_settings"]).read_text())
        self.assertTrue(settings["sandbox"]["enabled"])
        self.assertFalse(settings["sandbox"]["allowUnsandboxedCommands"])
        self.assertEqual(settings["sandbox"]["network"]["deniedDomains"], ["*"])
        self.assertEqual(claude["fresh_tmpdir"],
                         {"env": "CLAUDE_CODE_TMPDIR", "max_per_uid_path_bytes": 44})
        self.assertTrue(any("no sandbox key and no permissions.allow rule" in check
                            for check in claude["pre_run_checks"]))
        self.assertTrue(any("Inherited hooks run outside the sandbox" in check
                            for check in claude["pre_run_checks"]))
        self.assertTrue(any("Delete" in check for check in claude["post_run_checks"]))

    def check_agent_policies(self, claude, codex):
        for agent in (claude, codex):
            joined = " ".join(agent["extra_args"]).lower()
            self.assertNotIn("danger", joined)
            self.assertNotIn("bypass", joined)
            self.assertIn(agent["model"], agent["extra_args"])
        self.assertNotIn("--sandbox", codex["extra_args"])
        overrides = [codex["extra_args"][i + 1] for i, arg in enumerate(codex["extra_args"])
                     if arg == "-c"]
        config = tomllib.loads("\n".join(overrides))
        self.assertEqual(config["approval_policy"], "never")
        self.assertEqual(config["model_reasoning_effort"], codex["effort"])
        profile = config["permissions"][config["default_permissions"]]["filesystem"]
        self.assertEqual({key: value for key, value in profile.items() if value != "none"},
                         {":root": "read", ":workspace_roots": "write", ":tmpdir": "write"})
        for denied in ("~/.dotfiles", "~/.claude", "~/.agents", "~/.codex/skills"):
            self.assertEqual(profile[denied], "none")
        for feature in ("hooks", "memories", "plugins", "computer_use", "browser_use"):
            self.assertIn(["--disable", feature],
                          [codex["extra_args"][i:i + 2] for i in range(len(codex["extra_args"]))])
        self.assertTrue(any("mcp_servers.<name>.enabled=false" in check
                            for check in codex["pre_run_checks"]))
        self.assertTrue(any("codex sandbox -P" in check for check in codex["pre_run_checks"]))

    def check_plain_fixture_suite(self, suite, private_names):
        data = json.loads(suite.read_text())
        files = suite.parent / "files"
        self.assertFalse(any(p.is_symlink() or p.name == ".git" for p in files.rglob("*")))
        source_before = PREPARE.digest_tree(suite.parent)
        for case in data["evals"]:
            overlay = suite.parent / case["overlay"]
            self.assertTrue((overlay / "change.patch").is_file())
            for agent in ("codex", "claude"):
                for variant in ("with-skill", "without-skill"):
                    with self.subTest(case=case["name"], agent=agent, variant=variant):
                        result = PREPARE.prepare(
                            suite, case["id"], agent, variant,
                            self.root / f"run-{len(self.workspaces)}",
                        )
                        workspace = Path(result["workspace"])
                        self.workspaces.append(workspace)
                        self.assertIn("change.patch", result["initial_files"])
                        self.assertFalse((workspace / ".git").exists())
                        self.assertFalse(any(
                            Path(name).name in (*private_names, "evals.json")
                            for name in result["initial_files"]
                        ))
                        guidance = workspace / ".guidance/skills"
                        self.assertEqual(
                            sorted(p.name for p in guidance.iterdir()) if guidance.exists() else [],
                            [data["skill_name"]] if variant == "with-skill" else [],
                        )
                        applied = subprocess.run(
                            ["git", "apply", "--check", "change.patch"], cwd=workspace,
                            capture_output=True, text=True, check=False,
                        )
                        self.assertEqual(applied.returncode, 0, applied.stderr)
        self.assertEqual(PREPARE.digest_tree(suite.parent), source_before)

    def test_adversarial_review_suite_prepares_every_case_from_plain_fixtures(self):
        suite = ROOT / "skills/local/change-adversarial-review/evals/evals.json"
        data = json.loads(suite.read_text())
        execution = data["execution"]
        self.assertEqual((execution["runs_per_condition"], execution["run_timeout_minutes"]), (3, 30))
        claude, codex = execution["agents"]["claude"], execution["agents"]["codex"]
        self.check_claude_policy(suite, claude)
        self.check_agent_policies(claude, codex)
        for case in data["evals"]:
            self.assertTrue((suite.parent / case["overlay"] / "ISSUE.md").is_file())
        self.check_plain_fixture_suite(suite, [claude["claude_settings"]])

    def test_change_review_suite_runs_both_agents_under_equal_sandboxed_policies(self):
        suite = ROOT / "skills/local/change-review/evals/evals.json"
        data = json.loads(suite.read_text())
        self.assertEqual(data["supporting_skills"], [])
        execution = data["execution"]
        self.assertEqual((execution["runs_per_condition"], execution["run_timeout_minutes"]), (3, 30))
        claude, codex = execution["agents"]["claude"], execution["agents"]["codex"]
        self.check_claude_policy(suite, claude)
        self.check_agent_policies(claude, codex)
        names = [case["name"] for case in data["evals"]]
        self.assertEqual(names[:4], ["misses-one-criterion", "meets-all-criteria",
                                     "breaches-mandatory-rule", "no-issue-available"])
        for case in data["evals"]:
            issue = suite.parent / case["overlay"] / "ISSUE.md"
            self.assertEqual(issue.is_file(), case["name"] != "no-issue-available", case["name"])
        self.check_plain_fixture_suite(suite, [claude["claude_settings"]])

    def test_delivery_instruction_suites_prepare_for_default_launch_settings(self):
        supporting = {
            "delivery-common": ["principles", "principle-attack-the-premise",
                                "principle-subtract-before-you-add", "principle-laziness-protocol",
                                "principle-fix-root-causes", "principle-redesign-from-first-principles"],
            "shared-understanding": ["principles", "principle-subtract-before-you-add",
                                     "principle-laziness-protocol"],
            "design-preflight": ["principles", "principle-subtract-before-you-add",
                                 "principle-laziness-protocol",
                                 "principle-redesign-from-first-principles"],
        }
        for name, expected in supporting.items():
            suite = ROOT / f"skills/local/{name}/evals/evals.json"
            data = json.loads(suite.read_text())
            self.assertEqual((data["skill_name"], data["supporting_skills"]), (name, expected))
            # Delivery smoke runs these with the prepared launch arguments only.
            self.assertNotIn("execution", data)
            files = suite.parent / "files"
            self.assertFalse(any(p.is_symlink() or p.name == ".git" for p in files.rglob("*")))
            source_before = PREPARE.digest_tree(suite.parent)
            for case in data["evals"]:
                for agent in ("codex", "claude"):
                    for variant in ("with-skill", "without-skill"):
                        with self.subTest(suite=name, case=case["name"], agent=agent, variant=variant):
                            result = PREPARE.prepare(
                                suite, case["id"], agent, variant,
                                self.root / f"run-{len(self.workspaces)}",
                            )
                            workspace = Path(result["workspace"])
                            self.workspaces.append(workspace)
                            self.assertIn("ISSUE.md", result["initial_files"])
                            self.assertNotIn("evals.json", result["initial_files"])
                            guidance = workspace / ".guidance/skills"
                            self.assertEqual(
                                sorted(p.name for p in guidance.iterdir()) if guidance.exists() else [],
                                sorted([name, *expected]) if variant == "with-skill" else [],
                            )
                            if guidance.exists():
                                self.assertFalse((guidance / name / "evals").exists())
            self.assertEqual(PREPARE.digest_tree(suite.parent), source_before)

    def triage_snapshot(self, case):
        path = TRIAGE_SUITE.parent / case["overlay"] / ".snapshot/issues.json"
        return json.loads(path.read_text())

    def prepare_triage(self, case_id, agent="claude"):
        output = self.root / f"run-{len(self.workspaces)}"
        result = PREPARE.prepare(TRIAGE_SUITE, case_id, agent, "with-skill", output)
        workspace = Path(result["workspace"])
        self.workspaces.append(workspace)
        return result, workspace, output / "run.json"

    def fake_cli(self, directory, name="claude", shebang="#!/bin/sh"):
        directory.mkdir(parents=True, exist_ok=True)
        cli = directory / name
        cli.write_text(f"{shebang}\nexit 0\n")
        cli.chmod(0o755)
        return cli

    def stage_triage(self, case_id):
        result, workspace, run_json = self.prepare_triage(case_id)
        tmpdir = self.root / f"tmp-{len(self.workspaces)}"
        tmpdir.mkdir()
        dest = self.root / f"stage-{len(self.workspaces)}"
        self.cli = self.fake_cli(self.root / "trusted-cli")
        env = STAGE.stage(run_json, str(dest), tmpdir, str(self.cli.parent))
        self.staged.append(dest)
        return workspace, run_json, dest, env

    def run_gh(self, env, args):
        # The staged stand-in runs by absolute path, so no host gh can answer.
        return subprocess.run([env["stand_in"], *args], env={
            "PATH": env["PATH"], "GH_SNAPSHOT_LOG": env["GH_SNAPSHOT_LOG"]},
            capture_output=True, text=True, check=False, timeout=60)

    @staticmethod
    def documented_gh_commands():
        skill = (ROOT / "skills/local/github-issue-triage/SKILL.md").read_text()
        # `gh issue` and `gh pr` alone name the calls that take --repo; they run nothing.
        return [command for command in re.findall(r"`(gh [^`]+)`", skill)
                if command not in ("gh issue", "gh pr")]

    @staticmethod
    def touched_areas(body):
        section = body.split("## Touched Areas", 1)[1].split("\n## ", 1)[0]
        return set(re.findall(r"`([^`]+)`", section))

    def test_triage_suite_pairs_default_and_full_read_runs_over_offline_snapshots(self):
        data = json.loads(TRIAGE_SUITE.read_text())
        self.assertEqual(data["supporting_skills"], ["triage-common"])
        execution = data["execution"]
        self.assertEqual((execution["runs_per_condition"], execution["run_timeout_minutes"]), (3, 30))
        self.assertEqual(set(execution["conditions"]), {"default", "full-read"})
        rule = execution["decision_rule"]
        self.assertTrue(rule.startswith("Fixed before any run."))
        self.assertIn("a default run in addition names no parallel group", rule)
        self.assertIn("it comes from the arguments of reconciled ledger calls", rule)
        self.assertIn("A full-read run counts only when detail_issues holds every issue in read_scope.detail", rule)
        self.assertIn("a detail-band regression only when a majority of that case's valid full-read runs", rule)
        self.assertIn("inconclusive (suspected case defect)", rule)
        self.assertEqual(set(execution["recorded_fields"]), {
            "next", "current_wave", "next_wave", "parallel_groups", "detail_reads", "gh_bytes"})
        self.assertEqual(set(execution["gh_stand_in"]), {"stage", "collect", "forms", "note"})
        self.assertTrue((TRIAGE_SUITE.parent / "stage_gh.py").is_file())
        claude, codex = execution["agents"]["claude"], execution["agents"]["codex"]
        self.check_claude_policy(TRIAGE_SUITE, claude)
        self.check_agent_policies(claude, codex)
        for agent in (claude, codex):
            self.assertIn("stage_gh.py stage", agent["policy"])
            self.assertIn("never inherited", agent["policy"])
            self.assertIn("resolves the prepared launch_argv's CLI to an absolute executable", agent["policy"])
            self.assertTrue(any("with the printed absolute CLI" in check for check in agent["pre_run_checks"]))
            self.assertTrue(any("derives each record's form and issue from its arguments" in check
                                for check in agent["post_run_checks"]))
            self.assertTrue(any("staged stand-in" in check and "hook command" in check
                                for check in agent["pre_run_checks"]))
            collect = [i for i, check in enumerate(agent["post_run_checks"]) if "stage_gh.py collect" in check]
            delete = [i for i, check in enumerate(agent["post_run_checks"]) if check.startswith("Delete")]
            self.assertTrue(collect and delete and collect[0] < delete[0])

        files = TRIAGE_SUITE.parent / "files"
        self.assertFalse(any(p.is_symlink() or p.name in (".git", "gh-calls.jsonl")
                             for p in files.rglob("*")))
        self.assertTrue(os.access(files / "tasklet/bin/gh", os.X_OK))
        scenarios = {}
        for case in data["evals"]:
            scenarios.setdefault(case["scenario"], {})[case["condition"]] = case
        self.assertEqual(set(scenarios), {
            "dependent-text-raises-blocker", "comment-supersedes-item",
            "list-only-overlap-with-next", "no-propagation-control",
        })
        for name, pair in scenarios.items():
            with self.subTest(scenario=name):
                self.assertEqual(set(pair), {"default", "full-read"})
                default, full = pair["default"], pair["full-read"]
                for key in ("fixture", "overlay", "files", "expected", "expected_output"):
                    self.assertEqual(default[key], full[key], key)
                snapshot = self.triage_snapshot(default)
                issues = {issue["number"]: issue for issue in snapshot["issues"]}
                open_numbers = sorted(n for n, issue in issues.items() if issue["state"] == "open")
                self.assertTrue(full["prompt"].startswith(default["prompt"] + " Read every open issue in full"))
                self.assertNotIn("in full", default["prompt"])
                self.assertEqual([int(n) for n in re.findall(r"#(\d+)", full["prompt"])], open_numbers)
                self.assertEqual(full["read_scope"], {"detail": open_numbers})

                expected = default["expected"]
                self.assertEqual(default["read_scope"], {"list_only": expected["not_parallel_with_next"]})
                current, after = set(expected["current_wave"]), set(expected["next_wave"])
                self.assertIn(expected["next"], current)
                self.assertFalse(current & after)
                self.assertLessEqual(current | after, set(open_numbers))
                for number in current:
                    self.assertFalse(issues[number]["blocked_by"], number)
                for number in after:
                    self.assertEqual(issues[number]["blocked_by"], [expected["next"]], number)
                next_areas = self.touched_areas(issues[expected["next"]]["body"])
                for number in expected["not_parallel_with_next"]:
                    self.assertIn(number, current)
                    self.assertTrue(self.touched_areas(issues[number]["body"]) & next_areas, number)
                self.assertIn(f"The recommended next issue is #{expected['next']}", default["assertions"])
                # The no-pair guard grades only the default run; the control's groups are recorded.
                self.assertFalse(any("parallel group" in item for item in full["assertions"]))
                self.assertEqual(any("parallel group" in item for item in default["assertions"]),
                                 bool(expected["not_parallel_with_next"]))
        self.assertEqual(
            scenarios["list-only-overlap-with-next"]["default"]["expected"]["not_parallel_with_next"], [32])

        # The supersession reaches the triage only through #20's comment.
        superseding = self.triage_snapshot(scenarios["comment-supersedes-item"]["default"])
        texts = [(issue["number"], issue["title"] + "\n" + issue["body"]) for issue in superseding["issues"]]
        texts += [(issue["number"], comment["body"]) for issue in superseding["issues"]
                  for comment in issue["comments"]]
        self.assertEqual([n for n, text in texts if re.search(r"(?i)supersed", text)], [20])
        self.assertEqual(superseding["issues"][0]["comments"][0]["body"].split()[:3],
                         ["Superseded", "by", "#23,"])
        # Every current-wave issue is still open work in the fixture: #13's broken link exists.
        readme = (files / "tasklet/README.md").read_text()
        self.assertIn("(CONTRIBUTING.md)", readme)
        self.assertFalse((files / "tasklet/CONTRIBUTING.md").exists())
        # The dependent's title names it a follow-up, which puts it in the detail band.
        dependent = self.triage_snapshot(scenarios["dependent-text-raises-blocker"]["default"])
        self.assertTrue(next(i for i in dependent["issues"] if i["number"] == 12)["title"]
                        .startswith("Follow-up to #11"))

        source_before = PREPARE.digest_tree(TRIAGE_SUITE.parent)
        for case in data["evals"]:
            for agent in ("codex", "claude"):
                with self.subTest(case=case["name"], agent=agent):
                    result, workspace, _ = self.prepare_triage(case["id"], agent)
                    self.assertIn(".snapshot/issues.json", result["initial_files"])
                    self.assertIn("bin/gh", result["initial_files"])
                    self.assertFalse((workspace / ".git").exists())
                    self.assertFalse(any(Path(name).name in ("evals.json", "claude-settings.json", "stage_gh.py")
                                         for name in result["initial_files"]))
                    guidance = workspace / ".guidance/skills"
                    self.assertEqual(sorted(p.name for p in guidance.iterdir()),
                                     ["github-issue-triage", "triage-common"])
                    self.assertFalse((guidance / "github-issue-triage/evals").exists())
        self.assertEqual(PREPARE.digest_tree(TRIAGE_SUITE.parent), source_before)

    def test_triage_stage_launches_with_a_fixed_path_outside_writable_roots(self):
        workspace, run_json, dest, env = self.stage_triage(1)
        tmpdir = self.root / "tmp-1"
        staged = os.path.realpath(dest)
        self.assertEqual(env["PATH"], os.pathsep.join([f"{staged}/bin", *STAGE.FIXED_PATH]))
        self.assertEqual(STAGE.FIXED_PATH, ("/usr/bin", "/bin", "/usr/sbin", "/sbin"))
        self.assertEqual(env["stand_in"], f"{staged}/bin/gh")
        self.assertEqual(Path(env["GH_SNAPSHOT_LOG"]), workspace.resolve() / ".snapshot/gh-calls.jsonl")
        for path in (dest, dest / "bin", dest / ".snapshot", dest / "bin/gh", dest / ".snapshot/issues.json"):
            self.assertFalse(path.stat().st_mode & 0o222, path)
        self.assertEqual((dest / "bin/gh").read_bytes(), (workspace / "bin/gh").read_bytes())
        self.assertEqual(self.run_gh(env, ["repo", "view", "--json", "nameWithOwner,url,defaultBranchRef"]).returncode, 0)

        # The agent CLI is resolved before the fixed PATH applies, and only from trusted directories.
        self.assertEqual(env["launch_argv"], [str(self.cli), "--disable-slash-commands"])
        for name, cli_path in (("missing", str(self.root / "empty-dir")),
                               ("in-tmpdir", str(self.fake_cli(tmpdir / "bin").parent)),
                               ("in-workspace", str(self.fake_cli(workspace / "cli").parent))):
            with self.subTest(cli=name), self.assertRaises(ValueError):
                STAGE.stage(run_json, str(self.root / f"stage-cli-{name}"), tmpdir, cli_path)
            self.assertFalse((self.root / f"stage-cli-{name}").exists())
        shutil.rmtree(workspace / "cli")
        # A shim that dispatches on its own name, such as mise's node, keeps the path it was found at.
        dispatcher = self.fake_cli(self.root / "mise-bin", "mise")
        dispatcher.write_text('#!/bin/sh\ncase "$(basename "$0")" in fakeshim) echo shim;; *) exit 9;; esac\n')
        shim = self.root / "mise-shims/fakeshim"
        shim.parent.mkdir()
        shim.symlink_to(dispatcher)
        shim_launcher = self.fake_cli(self.root / "shim-launcher", shebang="#!/usr/bin/env fakeshim")
        shim_path = os.pathsep.join([str(shim_launcher.parent), str(shim.parent)])
        shim_launch = STAGE.stage(run_json, str(self.root / "stage-shim"), tmpdir, shim_path)
        self.staged.append(self.root / "stage-shim")
        self.assertEqual(shim_launch["launch_argv"][:2], [str(shim), str(shim_launcher)])
        self.assertEqual(subprocess.run([shim_launch["launch_argv"][0]], capture_output=True, text=True,
                                        timeout=30).stdout, "shim\n")
        # The kept path and its target must both lie outside the writable roots.
        writable_shim = tmpdir / "shims/fakeshim"
        writable_shim.parent.mkdir()
        writable_shim.symlink_to(dispatcher)
        planted_target = self.fake_cli(tmpdir / "planted", "mise")
        (self.root / "trusted-shims").mkdir()
        (self.root / "trusted-shims/fakeshim").symlink_to(planted_target)
        for name, directory in (("shim-in-tmpdir", writable_shim.parent),
                                ("shim-target-in-tmpdir", self.root / "trusted-shims")):
            with self.subTest(shim=name), self.assertRaises(ValueError):
                STAGE.stage(run_json, str(self.root / f"stage-{name}"), tmpdir,
                            os.pathsep.join([str(shim_launcher.parent), str(directory)]))
            self.assertFalse((self.root / f"stage-{name}").exists())
        # An env-shebang launcher, such as npm's codex, would look its interpreter up on the fixed PATH.
        npm = self.root / "npm-bin"
        interpreter = self.fake_cli(npm, "fakeinterp")
        launcher = self.fake_cli(npm / "launcher", shebang="#!/usr/bin/env fakeinterp")
        trusted = os.pathsep.join([str(launcher.parent), str(npm)])
        env_launch = STAGE.stage(run_json, str(self.root / "stage-env"), tmpdir, trusted)
        self.staged.append(self.root / "stage-env")
        self.assertEqual(env_launch["launch_argv"], [str(interpreter), str(launcher),
                                                     "--disable-slash-commands"])
        planted = self.fake_cli(tmpdir / "interp", "fakeinterp")
        for name, shebang, cli_path in (
                ("interpreter-missing", "#!/usr/bin/env missinginterp", str(launcher.parent)),
                ("interpreter-in-tmpdir", "#!/usr/bin/env fakeinterp",
                 os.pathsep.join([str(launcher.parent), str(planted.parent)])),
                ("env-options", "#!/usr/bin/env -S fakeinterp", trusted)):
            self.fake_cli(launcher.parent, shebang=shebang)
            with self.subTest(launcher=name), self.assertRaises(ValueError):
                STAGE.stage(run_json, str(self.root / f"stage-{name}"), tmpdir, cli_path)
            self.assertFalse((self.root / f"stage-{name}").exists())
        for bad in ("relative-stage", str(workspace / "inside"), str(tmpdir / "inside"),
                    str(self.root / "a:b")):
            with self.subTest(dest=bad), self.assertRaises(ValueError):
                STAGE.stage(run_json, bad, tmpdir, str(self.cli.parent))
            self.assertFalse(Path(bad).exists(), bad)
        # A different letter case names the same directory on a case-insensitive file system.
        alias = str(workspace).swapcase()
        if os.path.exists(alias):
            self.assertTrue(STAGE.inside(alias + "/inside", workspace))
            with self.assertRaises(ValueError):
                STAGE.stage(run_json, alias + "/inside", tmpdir, str(self.cli.parent))
        (workspace / "bin/gh").write_text("#!/bin/sh\necho changed\n")
        with self.assertRaises(ValueError):
            STAGE.stage(run_json, str(self.root / "stage-changed"), tmpdir, str(self.cli.parent))
        (workspace / "bin/gh").unlink()
        (workspace / "bin/gh").symlink_to(dest / "bin/gh")
        with self.assertRaises(OSError):
            STAGE.stage(run_json, str(self.root / "stage-linked"), tmpdir, str(self.cli.parent))

    def test_triage_collect_validates_a_regular_ledger_within_one_deadline(self):
        workspace, run_json, dest, env = self.stage_triage(5)
        view = ["issue", "view", "32", "--json", "number,state,body,comments", "--jq",
                "{number, state, body, comments: [.comments[] | {author: .author.login, createdAt, body}]}"]
        self.assertEqual(self.run_gh(env, view).returncode, 0)
        self.assertEqual(self.run_gh(env, ["repo", "view", "--json", "nameWithOwner,url,defaultBranchRef"]).returncode, 0)
        self.assertEqual(self.run_gh(env, ["issue", "view", "32", "--json", "body"]).returncode, 1)
        summary = STAGE.collect(run_json, self.root / "evidence")
        ledger_path = workspace / ".snapshot/gh-calls.jsonl"
        ledger = ledger_path.read_bytes()
        self.assertEqual((self.root / "evidence/gh-calls.jsonl").read_bytes(), ledger)
        lines = [json.loads(line) for line in ledger.decode().splitlines()]
        self.assertEqual(summary["calls"], 3)
        self.assertEqual(summary["gh_bytes"], sum(line["stdout_bytes"] for line in lines))
        self.assertEqual(set(summary["gh_bytes_by_form"]), {"issue view", "repo view", "refused"})
        self.assertEqual(summary["gh_bytes_by_form"]["refused"], 0)
        self.assertEqual(summary["detail_issues"], [32])
        self.assertEqual(summary["stand_ins"], [env["stand_in"]])
        with self.assertRaises(FileExistsError):
            STAGE.collect(run_json, self.root / "evidence")
        with self.assertRaises(ValueError):
            STAGE.collect(run_json, workspace / "evidence")

        def rejected(name, error, pattern=None, **kwargs):
            with self.subTest(case=name):
                if pattern:
                    with self.assertRaisesRegex(error, pattern):
                        STAGE.collect(run_json, self.root / name, **kwargs)
                else:
                    with self.assertRaises(error):
                        STAGE.collect(run_json, self.root / name, **kwargs)
                self.assertFalse((self.root / name).exists(), name)

        outside = self.root / "outside.jsonl"
        outside.write_bytes(ledger)
        ledger_path.unlink()
        ledger_path.symlink_to(outside)
        rejected("evidence-file-link", OSError)
        ledger_path.unlink()
        ledger_path.mkdir()
        rejected("evidence-dir", (OSError, ValueError))
        ledger_path.rmdir()
        os.mkfifo(ledger_path)
        started = time.monotonic()
        rejected("evidence-fifo", ValueError, "not a regular file", seconds=5)
        self.assertLess(time.monotonic() - started, 5)
        ledger_path.unlink()
        ledger_path.write_bytes(ledger)
        os.link(ledger_path, self.root / "hard-link")
        rejected("evidence-hard-link", ValueError, "hard links")
        (self.root / "hard-link").unlink()
        rejected("evidence-large", ValueError, "larger than", max_bytes=len(ledger) - 1)
        for name, line in (("evidence-not-json", b"not json\n"),
                           ("evidence-extra-key", json.dumps(dict(lines[0], extra=1)).encode() + b"\n"),
                           ("evidence-detail-without-view", json.dumps(dict(lines[1], detail=30)).encode() + b"\n"),
                           ("evidence-refusal-with-form", json.dumps(dict(lines[2], form="issue view")).encode() + b"\n"),
                           # Stored values must equal what the arguments and exit status imply.
                           ("evidence-detail-mismatch", json.dumps(dict(lines[0], detail=31)).encode() + b"\n"),
                           ("evidence-detail-dropped", json.dumps(dict(lines[0], detail=None)).encode() + b"\n"),
                           ("evidence-argv-mismatch", json.dumps(dict(lines[0], argv=[
                               "issue", "view", "31", *lines[0]["argv"][3:]])).encode() + b"\n"),
                           ("evidence-undocumented-success", json.dumps(dict(lines[1], argv=["auth", "status"])).encode() + b"\n"),
                           ("evidence-unknown-number", json.dumps(dict(lines[0], detail=999, argv=[
                               "issue", "view", "999", *lines[0]["argv"][3:]])).encode() + b"\n"),
                           ("evidence-long-line", b" " * (STAGE.MAX_LINE_BYTES + 1) + b"{}\n")):
            ledger_path.write_bytes(ledger + line)
            rejected(name, ValueError)
        # Loading the stand-in's rules writes nothing into the committed fixture, even with bytecode enabled.
        ledger_path.write_bytes(ledger)
        fixture = TRIAGE_SUITE.parent / "files"
        before = PREPARE.digest_tree(fixture)
        with mock.patch.object(sys, "dont_write_bytecode", False):
            STAGE.collect(run_json, self.root / "evidence-bytecode")
        self.assertEqual(PREPARE.digest_tree(fixture), before)
        self.assertFalse(any(p.name == "__pycache__" for p in TRIAGE_SUITE.parent.rglob("*")))
        consistent = dict(lines[0], detail=31, argv=["issue", "view", "31", *lines[0]["argv"][3:]])
        ledger_path.write_bytes(ledger + json.dumps(consistent).encode() + b"\n")
        self.assertEqual(STAGE.collect(run_json, self.root / "evidence-consistent")["detail_issues"], [31, 32])
        ledger_path.write_bytes(ledger)
        # The deadline also covers validation and retention, not only the read.
        with mock.patch.object(STAGE, "summarize", side_effect=lambda data, snapshot: time.sleep(5)):
            rejected("evidence-slow", TimeoutError, seconds=0.2)
        self.assertEqual(STAGE.collect(run_json, self.root / "evidence-again")["calls"], 3)

    def test_triage_gh_stand_in_answers_only_documented_forms(self):
        templates = self.documented_gh_commands()
        self.assertEqual(len(templates), 7, templates)
        repo = "github.com/example/tasklet"
        data = json.loads(TRIAGE_SUITE.read_text())
        for case in (case for case in data["evals"] if case["condition"] == "default"):
            with self.subTest(scenario=case["scenario"]):
                snapshot = self.triage_snapshot(case)
                issues = {issue["number"]: issue for issue in snapshot["issues"]}
                workspace, _, dest, env = self.stage_triage(case["id"])
                calls = []

                def call(args):
                    result = self.run_gh(env, args)
                    calls.append((args, result))
                    return result

                for template in templates:
                    command = (template.replace("<host>", "github.com")
                               .replace("<owner>/<repo>", "example/tasklet"))
                    base = shlex.split(command)[1:]
                    variants = [base]
                    if base[0] in ("issue", "pr"):
                        variants.append(base + ["--repo", repo])
                    for args in variants:
                        numbers = ([None] if "<number>" not in command else
                                   [pr["number"] for pr in snapshot["pull_requests"]] if args[0] == "pr"
                                   else list(issues))
                        for number in numbers:
                            concrete = [arg.replace("<number>", str(number)) for arg in args]
                            result = call(concrete)
                            self.assertEqual((result.returncode, result.stderr), (0, ""), concrete)
                            if "blocked_by" in command:
                                got = [json.loads(line) for line in result.stdout.splitlines()]
                                self.assertEqual(got, [{"repository": "example/tasklet", "number": n,
                                                        "state": "open"} for n in issues[number]["blocked_by"]])
                            elif "sub_issues" in command:
                                self.assertEqual(result.stdout, "")
                            elif args[:2] == ["issue", "view"]:
                                got = json.loads(result.stdout)
                                self.assertEqual(list(got), ["number", "state", "body", "comments"])
                                self.assertEqual((got["body"], [c["body"] for c in got["comments"]]),
                                                 (issues[number]["body"],
                                                  [c["body"] for c in issues[number]["comments"]]))
                            elif args[:2] == ["pr", "view"]:
                                pr = next(p for p in snapshot["pull_requests"] if p["number"] == number)
                                self.assertEqual(result.stdout.splitlines(), pr["files"])
                            elif args[:2] == ["issue", "list"]:
                                listed = json.loads(result.stdout)
                                self.assertEqual([i["number"] for i in listed], sorted(issues, reverse=True))
                                self.assertFalse(any("body" in i or "comments" in i for i in listed))

                # Compact, key-sorted JSON, as gh prints when stdout is not a terminal.
                result = call(["repo", "view", "--json=url,defaultBranchRef,nameWithOwner"])
                self.assertEqual(result.stdout, '{"defaultBranchRef":{"name":"main"},'
                                 '"nameWithOwner":"example/tasklet","url":"https://github.com/example/tasklet"}\n')

                view_jq = ("{number, state, body, comments: [.comments[] | "
                           "{author: .author.login, createdAt, body}]}")
                first = str(min(issues))
                snapshot_file = dest / ".snapshot/issues.json"
                before = snapshot_file.read_bytes()
                for args in (["issue", "view", first, "--json", "body"],
                             ["issue", "view", first, "--json", "number,state,body,comments", "--jq", ".body"],
                             ["issue", "view", first, "--json", "number,state,body,comments"],
                             ["issue", "view", first, "--json", "number,state,body,comments,title", "--jq", view_jq],
                             ["issue", "view", first, "--json", "number,state,body,body,comments", "--jq", view_jq],
                             ["issue", "view", "999", "--json", "number,state,body,comments", "--jq", view_jq],
                             ["issue", "view", first, "--json", "number,state,body,comments", "--jq", view_jq,
                              "--repo", "other/repo"],
                             ["issue", "view", first, "--json", "number,state,body,comments", "--jq", view_jq,
                              "-R", repo],
                             ["issue", "list", "--state", "open", "--limit", "100", "--json", "number,body"],
                             ["issue", "list", "--state", "all", "--limit", "100", "--json",
                              "number,title,labels,milestone,assignees,updatedAt,createdAt,url"],
                             ["issue", "list", "--state", "open", "--limit", "100", "--json",
                              "number,title,labels,milestone,assignees,updatedAt,createdAt,url", "--label", "polish"],
                             ["issue", "list", "--search", "export"],
                             ["pr", "list", "--state", "closed", "--limit", "50", "--json", "number"],
                             ["pr", "view", "55", "--json", "files", "--jq", ".files[]"],
                             ["api", "--hostname", "github.com", "repos/example/tasklet/issues/10/dependencies/blocked_by",
                              "--jq", '.[] | {repository: (.repository_url | sub("^.*/repos/"; "")), number, state}'],
                             ["api", "--hostname", "github.com", "--paginate",
                              "repos/example/tasklet/issues/10/dependencies/blocked_by"],
                             ["api", "--hostname", "github.com", "--paginate", "repos/example/tasklet/issues/10"],
                             ["api", "--hostname", "github.com", "--paginate", "-X", "POST",
                              "repos/example/tasklet/issues/10/comments"],
                             ["issue", "edit", first, "--add-label", "x"],
                             ["issue", "comment", first, "--body", "x"],
                             ["pr", "merge", "55"],
                             ["auth", "status"],
                             ["--version"],
                             ["search", "issues", "export"],
                             []):
                    result = call(args)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (1, "", "gh stand-in: refused\n"), args)
                self.assertEqual(snapshot_file.read_bytes(), before)

                log = [json.loads(line) for line in
                       (workspace / ".snapshot/gh-calls.jsonl").read_text().splitlines()]
                self.assertEqual(len(log), len(calls))
                for entry, (args, result) in zip(log, calls):
                    self.assertEqual(STAGE.record(json.dumps(entry)), entry)
                    self.assertEqual(entry["argv"], args)
                    self.assertEqual(entry["exit"], result.returncode)
                    self.assertEqual(entry["stdout_bytes"], len(result.stdout.encode()))
                    self.assertEqual(entry["stderr_bytes"], len(result.stderr.encode()))
                    self.assertEqual(entry["exe"], env["stand_in"])
                    # Read scope comes from the arguments alone: only a documented issue view reads text.
                    if result.returncode == 0 and args[:2] == ["issue", "view"]:
                        self.assertEqual((entry["form"], entry["detail"]), ("issue view", int(args[2])))
                    else:
                        self.assertIsNone(entry["detail"], args)
                    self.assertEqual(entry["form"] is None, result.returncode != 0, args)
                summary = STAGE.summarize((workspace / ".snapshot/gh-calls.jsonl").read_bytes(), snapshot)
                self.assertEqual(summary["detail_issues"], sorted(issues))

    def test_old_snapshot_is_supplied_without_the_judging_cases(self):
        bundle = self.root / "snapshot"
        for name in ("maintain-verification-skill", "principle-prove-it-works", "create-verification-skill"):
            shutil.copytree(ROOT / "skills/local" / name, bundle / name,
                            ignore=shutil.ignore_patterns("evals"))
        old_skill = bundle / "maintain-verification-skill"
        with (old_skill / "SKILL.md").open("a") as stream:
            stream.write("\nSnapshot-specific instruction.\n")
        result = self.prepare(1, skill_source=old_skill)
        supplied = Path(result["workspace"]) / ".guidance/skills/maintain-verification-skill/SKILL.md"
        self.assertEqual(supplied.read_bytes(), (old_skill / "SKILL.md").read_bytes())
        self.assertIn("maintain-verification-skill/SKILL.md", result["guidance_files"])


if __name__ == "__main__":
    unittest.main()
