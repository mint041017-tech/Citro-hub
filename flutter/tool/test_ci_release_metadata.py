import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "metadata", Path(__file__).with_name("ci_release_metadata.py")
)
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "flutter").mkdir()
        (self.root / "flutter/pubspec.yaml").write_text("version: 2.1.0+2100\n")
        self.git("init", "-q")
        self.git("config", "user.name", "CI Test")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("add", ".")
        self.git("commit", "-qm", "initial")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True).strip()

    def test_direct_main_push(self):
        result = metadata.release_metadata(self.root, "push", "refs/heads/main")
        self.assertEqual(result["version"], "2.1.0")
        self.assertEqual(result["sha"], self.git("rev-parse", "HEAD"))

    def test_matching_tag_on_main(self):
        result = metadata.release_metadata(self.root, "push", "refs/tags/v2.1.0")
        self.assertEqual(result["base_build"], "2100")

    def test_mismatched_tag_and_branch_are_rejected(self):
        for ref in ("refs/tags/v2.1.1", "refs/heads/feature", "refs/tags/v2.1.0;echo injected"):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                metadata.release_metadata(self.root, "push", ref)

    def test_tag_on_unmerged_commit_is_rejected(self):
        (self.root / "unmerged").write_text("new code")
        self.git("add", ".")
        self.git("commit", "-qm", "unmerged")
        with self.assertRaises(subprocess.CalledProcessError):
            metadata.release_metadata(self.root, "push", "refs/tags/v2.1.0")

    def test_manual_release_must_use_main(self):
        metadata.release_metadata(self.root, "workflow_dispatch", "refs/heads/main")
        with self.assertRaises(ValueError):
            metadata.release_metadata(self.root, "workflow_dispatch", "refs/heads/feature")


if __name__ == "__main__":
    unittest.main()
