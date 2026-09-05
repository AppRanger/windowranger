#!/usr/bin/env python3
"""Focused isolated tests for scripts/release.py."""

from __future__ import annotations

import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("release.py")
SPEC = importlib.util.spec_from_file_location("release", SCRIPT)
assert SPEC and SPEC.loader
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class FakeRun:
    def __init__(self, commit: str, failing_command: str | None = None):
        self.commit = commit
        self.failing_command = failing_command
        self.calls: list[list[str]] = []

    def __call__(self, command, **kwargs):
        command = list(command)
        self.calls.append(command)
        if command[:3] == ["git", "rev-parse", "--verify"]:
            return subprocess.CompletedProcess(command, 0, self.commit + "\n", "")
        if command[:3] == ["git", "status", "--porcelain"]:
            return subprocess.CompletedProcess(command, 0, "", "")
        if self.failing_command and self.failing_command in command[0]:
            return subprocess.CompletedProcess(command, 1, "simulated failure\n", "")
        return subprocess.CompletedProcess(command, 0, "ok\n", "")


class FakePopen:
    def __init__(self, fake_run: FakeRun):
        self.fake_run = fake_run

    def __call__(self, command, **kwargs):
        result = self.fake_run(command, **kwargs)
        process = type("Process", (), {})()
        process.stdout = io.StringIO(result.stdout or "")
        process.wait = lambda: result.returncode
        process.terminate = lambda: None
        return process


class InterruptingProcess:
    def __init__(self):
        self.terminated = False
        self.waits = 0
        self.stdout = self
        self.closed = False

    def __iter__(self):
        raise KeyboardInterrupt
        yield ""

    def terminate(self):
        self.terminated = True

    def wait(self):
        self.waits += 1
        return 130

    def close(self):
        self.closed = True


class ReleaseRunnerTests(unittest.TestCase):
    commit = "a" * 40

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repository"
        self.root.mkdir()
        (self.root / ".git").mkdir()
        self.release_directory = self.root / ".build" / "releases" / "1.0.8"
        self.release_directory.mkdir(parents=True)
        (self.release_directory / "WindowRanger-1.0.8.release.txt").write_text(
            f"build_number=21\ncommit={self.commit}\n", encoding="utf-8"
        )

    def tearDown(self):
        self.temporary.cleanup()

    def arguments(self, *extra: str) -> list[str]:
        return ["--repository-root", str(self.root), "--version", "1.0.8", "--build-number", "21", *extra]

    def test_dry_run_creates_no_journal_or_mutates(self):
        before = {str(path.relative_to(self.root)): path.read_bytes()
                  for path in self.root.rglob("*") if path.is_file()}
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            result = release.main(self.arguments("--stage", "verify-local"))
        self.assertEqual(result, 0)
        self.assertFalse((self.root / ".build/release-runs").exists())
        after = {str(path.relative_to(self.root)): path.read_bytes()
                 for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(len(fake.calls), 1)

    def test_prepare_stops_after_build_failure_and_records_it(self):
        fake = FakeRun(self.commit, "build-distribution.sh")
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            result = release.main(self.arguments("--stage", "prepare", "--notary-profile", "WindowRanger", "--execute"))
        self.assertEqual(result, 2)
        self.assertFalse(any("verify-release-assets.sh" in call[0] for call in fake.calls))
        journal = next((self.root / ".build" / "release-runs").glob("*/journal.json"))
        payload = json.loads(journal.read_text())
        self.assertEqual(payload["stages"]["build"]["status"], "failed")

    def test_resume_rejects_provenance_mismatch(self):
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            self.assertEqual(release.main(self.arguments("--stage", "verify-local", "--execute")), 0)
            journal = next((self.root / ".build" / "release-runs").glob("*/journal.json"))
            payload = json.loads(journal.read_text())
            payload["inputs"]["commit"] = "b" * 40
            journal.write_text(json.dumps(payload), encoding="utf-8")
            self.assertEqual(release.main(self.arguments("--stage", "verify-local", "--resume", "--execute")), 2)
        self.assertEqual(sum("verify-release-assets.sh" in call[0] for call in fake.calls), 1)

    def test_resume_skips_successful_stage_with_matching_provenance(self):
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            self.assertEqual(release.main(self.arguments("--stage", "verify-local", "--execute")), 0)
            self.assertEqual(release.main(self.arguments("--stage", "verify-local", "--resume", "--execute")), 0)
        self.assertEqual(sum("verify-release-assets.sh" in call[0] for call in fake.calls), 2)

    def test_stage_feed_is_explicit_and_uses_a_safe_argv(self):
        public = self.root / "site-public"
        public.mkdir()
        destination = self.root / "feed-work"
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            result = release.main(self.arguments("--stage", "stage-feed", "--public-directory", str(public), "--feed-directory", str(destination), "--execute"))
        self.assertEqual(result, 0)
        command = fake.calls[-1]
        self.assertEqual(command[0], release.sys.executable)
        self.assertIn("stage-release-feed.py", command[1])
        self.assertEqual(command[command.index("--destination") + 1], str(destination.resolve()))

    def test_local_feed_verification_has_its_own_resume_key(self):
        key_plist = self.root / "Info.plist"
        key_plist.write_text("fixture", encoding="utf-8")
        feed = self.root / "appcast.xml"
        feed.write_text("fixture", encoding="utf-8")
        artifacts = self.root / "updates"
        artifacts.mkdir()
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            result = release.main(self.arguments("--stage", "verify-feed", "--feed", str(feed), "--key-plist", str(key_plist), "--artifact-directory", str(artifacts), "--local-only", "--execute"))
        self.assertEqual(result, 0)
        command = fake.calls[-1]
        self.assertIn("--local-only", command)
        journal = next((self.root / ".build" / "release-runs").glob("*/journal.json"))
        self.assertIn("verify-feed-local", json.loads(journal.read_text())["stages"])

    def test_later_draft_can_add_notes_without_changing_release_provenance(self):
        notes = self.root / "release-notes.md"
        notes.write_text("notes", encoding="utf-8")
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            self.assertEqual(release.main(self.arguments("--stage", "verify-local", "--execute")), 0)
            self.assertEqual(release.main(self.arguments("--stage", "draft", "--notes-file", str(notes), "--resume", "--execute")), 0)
        self.assertTrue(any("create-github-release.sh" in call[0] for call in fake.calls))

    def test_manifest_build_mismatch_stops_local_verification(self):
        (self.release_directory / "WindowRanger-1.0.8.release.txt").write_text(
            f"build_number=22\ncommit={self.commit}\n", encoding="utf-8"
        )
        fake = FakeRun(self.commit)
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            result = release.main(self.arguments("--stage", "verify-local", "--execute"))
        self.assertEqual(result, 2)
        self.assertFalse(any("verify-release-assets.sh" in call[0] for call in fake.calls))

    def test_failed_local_asset_verifier_stops_feed_verifier(self):
        key_plist = self.root / "Info.plist"
        key_plist.write_text("fixture", encoding="utf-8")
        feed = self.root / "appcast.xml"
        feed.write_text("fixture", encoding="utf-8")
        artifacts = self.root / "updates"
        artifacts.mkdir()
        fake = FakeRun(self.commit, "verify-release-assets.sh")
        with patch.object(release.subprocess, "run", fake), patch.object(release.subprocess, "Popen", FakePopen(fake)):
            result = release.main(self.arguments("--stage", "verify-feed", "--feed", str(feed), "--key-plist", str(key_plist), "--artifact-directory", str(artifacts), "--local-only", "--execute"))
        self.assertEqual(result, 2)
        self.assertFalse(any(len(call) > 1 and "verify-appcast.py" in call[1] for call in fake.calls))

    def test_interrupt_terminates_and_reaps_child_before_returning(self):
        process = InterruptingProcess()
        with tempfile.TemporaryDirectory() as temporary, patch.object(release.subprocess, "Popen", return_value=process):
            with self.assertRaises(KeyboardInterrupt):
                release.run_command(["fixture"], self.root, Path(temporary) / "stage.log", self.root / ".build" / "releases")
        self.assertTrue(process.terminated)
        self.assertEqual(process.waits, 1)
        self.assertTrue(process.closed)


if __name__ == "__main__":
    unittest.main()
