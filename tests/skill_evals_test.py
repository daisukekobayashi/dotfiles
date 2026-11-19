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


class SkillEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="skill-check-")
        self.root = Path(self.temp.name)
        self.workspaces = []

    def tearDown(self):
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
                            self.assertTrue((guidance / "prove-it-works/SKILL.md").is_file())
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

    def triage_snapshot(self, case):
        path = TRIAGE_SUITE.parent / case["overlay"] / ".snapshot/issues.json"
        return json.loads(path.read_text())

    def prepare_triage(self, case_id, agent="claude"):
        result = PREPARE.prepare(
            TRIAGE_SUITE, case_id, agent, "with-skill",
            self.root / f"run-{len(self.workspaces)}",
        )
        workspace = Path(result["workspace"])
        self.workspaces.append(workspace)
        return result, workspace

    def run_gh(self, workspace, argv):
        env = dict(os.environ, PATH=f"{workspace / 'bin'}{os.pathsep}{os.environ['PATH']}")
        return subprocess.run(argv, cwd=workspace, env=env, capture_output=True,
                              text=True, check=False, timeout=60)

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
        self.assertTrue(execution["decision_rule"].startswith("Fixed before any run."))
        self.assertEqual(set(execution["recorded_fields"]),
                         {"next", "current_wave", "next_wave", "detail_reads", "gh_bytes"})
        claude, codex = execution["agents"]["claude"], execution["agents"]["codex"]
        self.check_claude_policy(TRIAGE_SUITE, claude)
        self.check_agent_policies(claude, codex)
        for agent in (claude, codex):
            self.assertEqual(agent["path_prefix"], "bin")
            self.assertTrue(any("command -v gh" in check for check in agent["pre_run_checks"]))

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

                expected = default["expected"]
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
                assertions = " ".join(default["assertions"])
                self.assertIn(f"The recommended next issue is #{expected['next']}", assertions)
        self.assertEqual(
            scenarios["list-only-overlap-with-next"]["default"]["expected"]["not_parallel_with_next"], [32])

        source_before = PREPARE.digest_tree(TRIAGE_SUITE.parent)
        for case in data["evals"]:
            for agent in ("codex", "claude"):
                with self.subTest(case=case["name"], agent=agent):
                    result, workspace = self.prepare_triage(case["id"], agent)
                    self.assertIn(".snapshot/issues.json", result["initial_files"])
                    self.assertIn("bin/gh", result["initial_files"])
                    self.assertFalse((workspace / ".git").exists())
                    self.assertFalse(any(Path(name).name in ("evals.json", "claude-settings.json")
                                         for name in result["initial_files"]))
                    guidance = workspace / ".guidance/skills"
                    self.assertEqual(sorted(p.name for p in guidance.iterdir()),
                                     ["github-issue-triage", "triage-common"])
                    self.assertFalse((guidance / "github-issue-triage/evals").exists())
        self.assertEqual(PREPARE.digest_tree(TRIAGE_SUITE.parent), source_before)

    @unittest.skipUnless(shutil.which("jq"), "the gh stand-in runs --jq through jq")
    def test_triage_gh_stand_in_answers_documented_commands_and_logs_bytes(self):
        skill = (ROOT / "skills/local/github-issue-triage/SKILL.md").read_text()
        # `gh issue` and `gh pr` alone name the calls that take --repo; they run nothing.
        templates = [command for command in re.findall(r"`(gh [^`]+)`", skill)
                     if command not in ("gh issue", "gh pr")]
        self.assertEqual(len(templates), 7, templates)
        repo = "github.com/example/tasklet"
        data = json.loads(TRIAGE_SUITE.read_text())
        for case in (case for case in data["evals"] if case["condition"] == "default"):
            with self.subTest(scenario=case["scenario"]):
                snapshot = self.triage_snapshot(case)
                _, workspace = self.prepare_triage(case["id"])
                calls = []

                def call(argv):
                    result = self.run_gh(workspace, argv)
                    calls.append((argv, result))
                    return result

                for template in templates:
                    command = (template.replace("<host>", "github.com")
                               .replace("<owner>/<repo>", "example/tasklet"))
                    argv = shlex.split(command)
                    if argv[1] in ("issue", "pr"):
                        argv += ["--repo", repo]
                    if "<number>" not in command:
                        result = call(argv)
                        self.assertEqual(result.returncode, 0, (argv, result.stderr))
                        continue
                    numbers = ([pr["number"] for pr in snapshot["pull_requests"]]
                               if argv[1] == "pr" else [i["number"] for i in snapshot["issues"]])
                    for number in numbers:
                        concrete = [arg.replace("<number>", str(number)) for arg in argv]
                        result = call(concrete)
                        self.assertEqual(result.returncode, 0, (concrete, result.stderr))
                        if "blocked_by" in command:
                            issue = next(i for i in snapshot["issues"] if i["number"] == number)
                            got = [json.loads(line)["number"] for line in result.stdout.splitlines()]
                            self.assertEqual(got, issue["blocked_by"])
                        elif argv[1:3] == ["issue", "view"]:
                            issue = next(i for i in snapshot["issues"] if i["number"] == number)
                            got = json.loads(result.stdout)
                            self.assertEqual((got["body"], [c["body"] for c in got["comments"]]),
                                             (issue["body"], [c["body"] for c in issue["comments"]]))
                        elif argv[1:3] == ["pr", "view"]:
                            pr = next(p for p in snapshot["pull_requests"] if p["number"] == number)
                            self.assertEqual(result.stdout.splitlines(), pr["files"])

                snapshot_file = workspace / ".snapshot/issues.json"
                before = snapshot_file.read_bytes()
                for argv in (["gh", "issue", "edit", "10", "--add-label", "x"],
                             ["gh", "issue", "comment", "10", "--body", "x"],
                             ["gh", "pr", "merge", "1"],
                             ["gh", "api", "-X", "POST", "repos/example/tasklet/issues/10/comments"],
                             ["gh", "api", "repos/example/tasklet/issues/10/comments", "-f", "body=x"],
                             ["gh", "issue", "list", "--repo", "other/repo"],
                             ["gh", "search", "issues", "export"]):
                    result = call(argv)
                    self.assertNotEqual(result.returncode, 0, argv)
                    self.assertEqual(result.stdout, "", argv)
                self.assertEqual(snapshot_file.read_bytes(), before)

                log = [json.loads(line) for line in
                       (workspace / ".snapshot/gh-calls.jsonl").read_text().splitlines()]
                self.assertEqual(len(log), len(calls))
                for entry, (argv, result) in zip(log, calls):
                    self.assertEqual(entry["argv"], argv[1:])
                    self.assertEqual(entry["exit"], 0 if result.returncode == 0 else 1)
                    self.assertEqual(entry["stdout_bytes"], len(result.stdout.encode()))
                    self.assertEqual(entry["stderr_bytes"], len(result.stderr.encode()))
                self.assertIn("issue view", {entry["kind"] for entry in log})

    def test_old_snapshot_is_supplied_without_the_judging_cases(self):
        bundle = self.root / "snapshot"
        for name in ("maintain-verification-skill", "prove-it-works", "create-verification-skill"):
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
