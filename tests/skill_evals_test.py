import importlib.util
import json
from pathlib import Path
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
                        workspace = Path(result["workspace"])
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
