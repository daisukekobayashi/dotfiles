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
        output = self.root / f"run-{len(self.workspaces)}"
        result = PREPARE.prepare(TRIAGE_SUITE, case_id, agent, "with-skill", output)
        workspace = Path(result["workspace"])
        self.workspaces.append(workspace)
        return result, workspace, output / "run.json"

    def stage_triage(self, case_id):
        result, workspace, run_json = self.prepare_triage(case_id)
        tmpdir = self.root / f"tmp-{len(self.workspaces)}"
        tmpdir.mkdir()
        dest = self.root / f"stage-{len(self.workspaces)}"
        env = STAGE.stage(run_json, dest, tmpdir, os.environ["PATH"])
        self.staged.append(dest)
        return workspace, run_json, dest, env

    def run_gh(self, env, args):
        # The staged stand-in runs by absolute path, so no host gh can answer.
        return subprocess.run([env["stand_in"], *args], env=dict(os.environ, **{
            "PATH": env["PATH"], "GH_SNAPSHOT_LOG": env["GH_SNAPSHOT_LOG"]}),
            capture_output=True, text=True, check=False, timeout=60)

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
        self.assertIn("never from the report", rule)
        self.assertEqual(set(execution["recorded_fields"]), {
            "next", "current_wave", "next_wave", "parallel_groups", "detail_reads", "gh_bytes"})
        self.assertTrue((TRIAGE_SUITE.parent / "stage_gh.py").is_file())
        claude, codex = execution["agents"]["claude"], execution["agents"]["codex"]
        self.check_claude_policy(TRIAGE_SUITE, claude)
        self.check_agent_policies(claude, codex)
        for agent in (claude, codex):
            self.assertIn("stage_gh.py stage", agent["policy"])
            self.assertTrue(any("staged stand-in" in check for check in agent["pre_run_checks"]))
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
                self.assertEqual(full["read_scope"], {
                    "text": open_numbers,
                    "comments": [n for n in open_numbers if issues[n]["comments"]]})

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

    def test_triage_stage_keeps_candidate_writable_paths_off_path(self):
        workspace, run_json, dest, env = self.stage_triage(1)
        tmpdir = self.root / "tmp-1"
        hostile = os.pathsep.join(["", ".", "bin", str(workspace / "bin"), str(tmpdir),
                                   str(tmpdir / "x"), "/usr/bin", "/usr/bin"])
        self.assertEqual(STAGE.trusted_path(hostile, [str(workspace), str(tmpdir)]), ["/usr/bin"])
        entries = env["PATH"].split(os.pathsep)
        self.assertEqual(entries[0], str(dest / "bin"))
        for entry in entries:
            self.assertTrue(os.path.isabs(entry), entry)
            self.assertFalse(STAGE.inside(entry, workspace) or STAGE.inside(entry, tmpdir), entry)
        self.assertEqual(Path(env["stand_in"]), (dest / "bin/gh").resolve())
        self.assertEqual(Path(env["GH_SNAPSHOT_LOG"]),
                         workspace.resolve() / ".snapshot/gh-calls.jsonl")
        for path in (dest, dest / "bin", dest / ".snapshot", dest / "bin/gh", dest / ".snapshot/issues.json"):
            self.assertFalse(path.stat().st_mode & 0o222, path)
        self.assertEqual((dest / "bin/gh").read_bytes(), (workspace / "bin/gh").read_bytes())

        with self.assertRaises(ValueError):
            STAGE.stage(run_json, workspace / "inside", tmpdir, os.environ["PATH"])
        with self.assertRaises(ValueError):
            STAGE.stage(run_json, tmpdir / "inside", tmpdir, os.environ["PATH"])
        (workspace / "bin/gh").write_text("#!/bin/sh\necho changed\n")
        with self.assertRaises(ValueError):
            STAGE.stage(run_json, self.root / "stage-changed", tmpdir, os.environ["PATH"])
        (workspace / "bin/gh").unlink()
        (workspace / "bin/gh").symlink_to(dest / "bin/gh")
        with self.assertRaises(OSError):
            STAGE.stage(run_json, self.root / "stage-linked", tmpdir, os.environ["PATH"])

    def test_triage_collect_reads_only_a_regular_ledger_inside_the_workspace(self):
        workspace, run_json, dest, env = self.stage_triage(5)
        self.assertEqual(self.run_gh(env, ["issue", "view", "32", "--json", "body"]).returncode, 0)
        self.assertEqual(self.run_gh(env, ["issue", "list", "--json", "number"]).returncode, 0)
        self.run_gh(env, ["issue", "edit", "30"])
        summary = STAGE.collect(run_json, self.root / "evidence")
        ledger = (workspace / ".snapshot/gh-calls.jsonl").read_bytes()
        self.assertEqual((self.root / "evidence/gh-calls.jsonl").read_bytes(), ledger)
        lines = [json.loads(line) for line in ledger.decode().splitlines()]
        self.assertEqual(summary["calls"], 3)
        self.assertEqual(summary["gh_bytes"], sum(line["stdout_bytes"] for line in lines))
        self.assertEqual(summary["text_issues"], [32])
        self.assertEqual(summary["comment_issues"], [])
        self.assertEqual(summary["stand_ins"], [env["stand_in"]])
        with self.assertRaises(FileExistsError):
            STAGE.collect(run_json, self.root / "evidence")
        with self.assertRaises(ValueError):
            STAGE.collect(run_json, workspace / "evidence")

        outside = self.root / "outside.jsonl"
        outside.write_text("{}\n")
        (workspace / ".snapshot/gh-calls.jsonl").unlink()
        (workspace / ".snapshot/gh-calls.jsonl").symlink_to(outside)
        with self.assertRaises(OSError):
            STAGE.collect(run_json, self.root / "evidence-file-link")
        (workspace / ".snapshot/gh-calls.jsonl").unlink()
        (workspace / ".snapshot/gh-calls.jsonl").mkdir()
        with self.assertRaises((OSError, ValueError)):
            STAGE.collect(run_json, self.root / "evidence-dir")
        (workspace / ".snapshot/gh-calls.jsonl").rmdir()
        moved = self.root / "moved-snapshot"
        (workspace / ".snapshot").rename(moved)
        (moved / "gh-calls.jsonl").write_text("{}\n")
        (workspace / ".snapshot").symlink_to(moved)
        with self.assertRaises(OSError):
            STAGE.collect(run_json, self.root / "evidence-dir-link")

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
                    args = shlex.split(command)[1:]
                    if args[0] in ("issue", "pr"):
                        args += ["--repo", repo]
                    if "<number>" not in command:
                        result = call(args)
                        self.assertEqual(result.returncode, 0, (args, result.stderr))
                        continue
                    numbers = ([pr["number"] for pr in snapshot["pull_requests"]]
                               if args[0] == "pr" else list(issues))
                    for number in numbers:
                        concrete = [arg.replace("<number>", str(number)) for arg in args]
                        result = call(concrete)
                        self.assertEqual(result.returncode, 0, (concrete, result.stderr))
                        if "blocked_by" in command:
                            got = [json.loads(line)["number"] for line in result.stdout.splitlines()]
                            self.assertEqual(got, issues[number]["blocked_by"])
                        elif args[:2] == ["issue", "view"]:
                            got = json.loads(result.stdout)
                            self.assertEqual((got["body"], [c["body"] for c in got["comments"]]),
                                             (issues[number]["body"],
                                              [c["body"] for c in issues[number]["comments"]]))
                        elif args[:2] == ["pr", "view"]:
                            pr = next(p for p in snapshot["pull_requests"] if p["number"] == number)
                            self.assertEqual(result.stdout.splitlines(), pr["files"])

                # Compact JSON, as gh prints when stdout is not a terminal.
                result = call(["repo", "view", "--json", "nameWithOwner,defaultBranchRef"])
                self.assertEqual(result.stdout,
                                 '{"nameWithOwner":"example/tasklet","defaultBranchRef":{"name":"main"}}\n')
                # Supported filters apply; an empty match is an empty list.
                result = call(["pr", "list", "--state", "closed", "--json", "number"])
                self.assertEqual(result.stdout, "[]\n")
                result = call(["issue", "list", "--label", "polish", "--json", "number"])
                self.assertEqual([item["number"] for item in json.loads(result.stdout)],
                                 sorted((n for n, i in issues.items() if "polish" in i["labels"]), reverse=True))
                result = call(["issue", "list", "--milestone", "export-v1", "--limit", "1", "--json", "number"])
                self.assertEqual(len(json.loads(result.stdout)), 1)

                snapshot_file = dest / ".snapshot/issues.json"
                before = snapshot_file.read_bytes()
                for args in (["issue", "edit", "10", "--add-label", "x"],
                             ["issue", "comment", "10", "--body", "x"],
                             ["pr", "merge", "1"],
                             ["api", "-X", "POST", "repos/example/tasklet/issues/10/comments"],
                             ["api", "repos/example/tasklet/issues/10/comments", "-f", "body=x"],
                             ["api", "repos/example/tasklet/issues/10?state=closed"],
                             ["issue", "list", "--repo", "other/repo"],
                             ["issue", "list", "--search", "export"],
                             ["issue", "list", "--state", "merged"],
                             ["issue", "view", "10", "--web"],
                             ["pr", "list", "--author", "someone"],
                             ["pr", "view", "1", "--comments"],
                             ["repo", "view", "--web"],
                             ["search", "issues", "export"]):
                    result = call(args)
                    self.assertNotEqual(result.returncode, 0, args)
                    self.assertEqual(result.stdout, "", args)
                self.assertEqual(snapshot_file.read_bytes(), before)

                log = [json.loads(line) for line in
                       (workspace / ".snapshot/gh-calls.jsonl").read_text().splitlines()]
                self.assertEqual(len(log), len(calls))
                for entry, (args, result) in zip(log, calls):
                    self.assertEqual(entry["argv"], args)
                    self.assertEqual(entry["exit"], 0 if result.returncode == 0 else 1)
                    self.assertEqual(entry["stdout_bytes"], len(result.stdout.encode()))
                    self.assertEqual(entry["stderr_bytes"], len(result.stderr.encode()))
                    self.assertEqual(entry["exe"], env["stand_in"])
                    exposed = [n for n, issue in issues.items()
                               if json.dumps(issue["body"])[1:-1] in result.stdout or issue["body"] in result.stdout]
                    self.assertEqual(entry["text"], exposed, args)
                    if args[:2] == ["issue", "view"] and entry["exit"] == 0:
                        number = int(args[2])
                        self.assertEqual(entry["text"], [number])
                        self.assertEqual(entry["comments"], [number] if issues[number]["comments"] else [])
                    elif "--jq" in args and args[0] == "api":
                        self.assertEqual((entry["text"], entry["comments"]), ([], []))

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
