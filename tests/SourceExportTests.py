#!/usr/bin/env python3
"""Regression tests for the publication boundary, without Bluetooth or network."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("source_export", PROJECT / "scripts/export-source.py")
source_export = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_export)


class SourceExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        (self.root / "scripts").mkdir(parents=True)
        shutil.copyfile(PROJECT / "scripts/check-public-privacy.py", self.root / "scripts/check-public-privacy.py")
        self.write("LICENSE", "MIT fixture\n")
        self.destination = Path(self.temp.name) / "export"

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_only_git_tracked_files_are_exported(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("docs/public.md", "Public documentation\n")
        self.write("docs/untracked.md", "Must not ship\n")
        subprocess.run(["git", "add", "LICENSE", "scripts", "docs/public.md"], cwd=self.root, check=True)
        source_export.export(self.root, self.destination, source_export.tracked_names(self.root))
        self.assertTrue((self.destination / "docs/public.md").is_file())
        self.assertFalse((self.destination / "docs/untracked.md").exists())

    def test_private_artifact_in_public_directory_blocks_export(self):
        self.write("docs/capture.jsonl", "{}\n")
        with self.assertRaisesRegex(ValueError, "private artifact path"):
            source_export.export(self.root, self.destination, ["LICENSE", "docs/capture.jsonl"])
        self.assertFalse(self.destination.exists())

    def test_symlink_blocks_export(self):
        (self.root / "docs").mkdir()
        (self.root / "docs/linked.md").symlink_to(self.root / "LICENSE")
        with self.assertRaisesRegex(ValueError, "Symlink"):
            source_export.export(self.root, self.destination, ["docs/linked.md"])

    def test_directory_symlink_blocks_export(self):
        external = Path(self.temp.name) / "external"
        external.mkdir()
        (external / "note.md").write_text("External data\n")
        (self.root / "docs").symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symlink"):
            source_export.export(self.root, self.destination, ["docs/note.md"])

    def test_traversal_and_absolute_paths_are_rejected(self):
        for name in ("../LICENSE", "/LICENSE", "docs/../../LICENSE"):
            with self.assertRaisesRegex(ValueError, "Unsafe path"):
                source_export.export(self.root, self.destination, [name])

    def test_image_free_export_preserves_licensed_logo(self):
        self.write("Resources/Devices/model.png", "render")
        self.write("Resources/Icon/OpenSound.png", "logo")
        self.write("docs/images/sound.png", "screenshot")
        names = ["LICENSE", "Resources/Devices/model.png", "Resources/Icon/OpenSound.png", "docs/images/sound.png"]
        source_export.export(self.root, self.destination, names, omit_images=True)
        self.assertTrue((self.destination / "Resources/Icon/OpenSound.png").is_file())
        self.assertFalse((self.destination / "Resources/Devices/model.png").exists())
        self.assertFalse((self.destination / "docs/images/sound.png").exists())

    def test_archive_manifest_and_executable_permissions(self):
        self.write("scripts/run.sh", "#!/bin/bash\nexit 0\n").chmod(0o755)
        source_export.export(self.root, self.destination, ["LICENSE", "scripts/run.sh", "scripts/check-public-privacy.py"])
        self.assertEqual(source_export.tracked_names(self.destination), ["LICENSE", "scripts/check-public-privacy.py", "scripts/run.sh"])
        second = Path(self.temp.name) / "second"
        source_export.export(self.destination, second, source_export.tracked_names(self.destination))
        self.assertTrue((second / "scripts/run.sh").stat().st_mode & 0o111)

    def test_private_content_is_not_written(self):
        self.write("docs/note.md", "ghp_" + "A" * 40)
        with self.assertRaisesRegex(ValueError, "access token"):
            source_export.export(self.root, self.destination, ["docs/note.md"])
        self.assertFalse(self.destination.exists())

    def test_environment_variant_is_private(self):
        self.write("docs/.env.production", "LOCAL_SETTING=example\n")
        with self.assertRaisesRegex(ValueError, "private artifact path"):
            source_export.export(self.root, self.destination, ["docs/.env.production"])

    def test_guard_catches_staged_content_after_working_copy_is_cleaned(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("docs/note.md", "ghp_" + "A" * 40)
        subprocess.run(["git", "add", "docs/note.md"], cwd=self.root, check=True)
        self.write("docs/note.md", "Clean working copy\n")
        result = subprocess.run(["python3", "scripts/check-public-privacy.py"], cwd=self.root,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("index:docs/note.md: access token", result.stderr)
        self.assertNotIn("A" * 40, result.stderr)

    def test_manifest_is_required_without_git(self):
        with self.assertRaisesRegex(ValueError, "Git checkout"):
            source_export.tracked_names(self.root)


if __name__ == "__main__":
    unittest.main()
