#!/usr/bin/env python3
"""Focused safety tests for release-channels.py."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).with_name("release-channels.py")
SPEC = importlib.util.spec_from_file_location("release_channels", SCRIPT)
assert SPEC and SPEC.loader
channels = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(channels)


class ChannelTests(unittest.TestCase):
    sha = "a" * 40

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = {"version": "1.0.9", "build_number": "22", "release_commit": self.sha,
                       "source_repository": str(self.root / "source"), "website_repository": str(self.root / "site"),
                       "tap_repository": str(self.root / "tap"), "release_root": str(self.root / "releases"),
                       "sparkle_bin": str(self.root / "sparkle"), "key_plist": str(self.root / "Info.plist")}
        for name in ("source", "site", "tap"):
            (self.root / name / ".git").mkdir(parents=True)
        self.path = self.root / "config.json"
        self.path.write_text(json.dumps(self.config), encoding="utf-8")

    def tearDown(self): self.temp.cleanup()

    def test_verified_feed_and_payloads_are_copied_to_public_directory(self):
        site = self.root / "site"
        public = site / "public"
        (public / "updates").mkdir(parents=True)
        (public / "appcast.xml").write_text("old feed")
        scratch = self.root / "scratch"
        staged = scratch / "feed"
        staged.mkdir(parents=True)
        (staged / "appcast.xml").write_text("verified feed")
        (staged / "release.zip").write_bytes(b"archive")
        notes = self.root / "notes.md"
        notes.write_text("Release notes")
        with patch.object(channels, "checked", return_value=""), patch.object(channels, "release_notes_path", return_value=notes):
            channels.stage_website_feed(self.config, site, scratch, public)
        self.assertEqual((public / "appcast.xml").read_text(), "verified feed")
        self.assertEqual((public / "updates" / "release.zip").read_bytes(), b"archive")

    def test_logs_keep_both_streams_and_do_not_overwrite_attempts(self):
        logs = self.root / "logs"
        with patch.object(channels, "LOG_DIRECTORY", logs):
            self.assertEqual(channels.checked([sys.executable, "-c", "print('retained output')"], self.root), "retained output")
            with self.assertRaises(channels.ChannelError):
                channels.checked([sys.executable, "-c", "import sys; print('failure evidence', file=sys.stderr); sys.exit(3)"], self.root)
        self.assertEqual(len(list(logs.glob("*.command.log"))), 2)
        self.assertIn("failure evidence", "".join(path.read_text() for path in logs.glob("*.stderr.log")))
        self.assertIn("retained output", "".join(path.read_text() for path in logs.glob("*.stdout.log")))

    def test_remote_branch_target_cannot_hide_wrong_tag(self):
        payload = dict(tagName="v1.0.9", isDraft=False, isPrerelease=False, isImmutable=True, targetCommitish="main")
        with patch.object(channels, "git", side_effect=["https://github.com/AppRanger/windowranger.git", "b" * 40 + "\trefs/tags/v1.0.9\n"]), patch.object(channels, "revision", return_value=self.sha), patch.object(channels, "checked", return_value=json.dumps(payload)):
            with self.assertRaisesRegex(channels.ChannelError, "Public remote"):
                channels.ensure_github_release(self.config)

    def test_merged_pr_is_recovered_without_another_push_or_pr(self):
        payload = [dict(number=12, headRefOid=self.sha, state="MERGED")]
        with patch.object(channels, "revision", return_value=self.sha), patch.object(channels, "checked", return_value=json.dumps(payload)) as checked, patch.object(channels, "git") as git, patch.object(channels, "create_pr") as create:
            self.assertEqual(channels.recover_pending_pr(self.root, self.root, "branch", "main", "title", "body"), ("12", self.sha))
        git.assert_not_called(); create.assert_not_called()
        self.assertIn("all", checked.call_args.args[0])

    def test_signed_but_changed_live_feed_is_not_exact_deployment(self):
        worktrees = self.root / "worktrees"
        public = worktrees / "website-deploy" / "public"
        public.mkdir(parents=True)
        (public / "appcast.xml").write_text("expected feed")
        def command(argv, cwd):
            if argv[0] == "/usr/bin/curl":
                Path(argv[argv.index("--output") + 1]).write_text("different signed feed")
            return ""
        journal = {"steps": {}}
        with patch.object(channels, "checked", side_effect=command):
            with self.assertRaisesRegex(channels.ChannelError, "Live appcast bytes"):
                channels.verify_live_feeds(self.config, self.root / "journal.json", journal, worktrees)
        self.assertNotIn("live_feed", journal["steps"])

    def test_custom_notes_are_bound_to_reviewed_hash(self):
        notes = self.root / "notes.txt"
        notes.write_text("reviewed notes")
        config = dict(self.config, release_notes=str(notes), release_notes_sha256=channels.hashlib.sha256(notes.read_bytes()).hexdigest())
        self.assertEqual(channels.release_notes_path(config), notes)
        notes.write_text("changed after review")
        with self.assertRaisesRegex(channels.ChannelError, "release_notes_sha256"):
            channels.release_notes_path(config)

    def test_plan_does_not_mutate_or_invoke_commands(self):
        before = sorted(str(path.relative_to(self.root)) for path in self.root.rglob("*"))
        with patch.object(channels, "run", side_effect=AssertionError("plan must not run commands")):
            self.assertEqual(channels.main(["--config", str(self.path)]), 0)
        self.assertEqual(before, sorted(str(path.relative_to(self.root)) for path in self.root.rglob("*")))

    def test_ledger_rejects_wrong_state(self):
        ledger = self.root / "ledger.tsv"
        ledger.write_text("22\t1.0.9\tsuperseded\tno\n", encoding="utf-8")
        with self.assertRaises(channels.ChannelError): channels.mark_ledger_published(ledger, "22", "1.0.9")

    def test_ledger_promotes_only_exact_allocated_row(self):
        ledger = self.root / "ledger.tsv"
        ledger.write_text("21\t1.0.8\tpublished\told\n22\t1.0.9\tallocated\treserved\n", encoding="utf-8")
        channels.mark_ledger_published(ledger, "22", "1.0.9")
        self.assertIn("22\t1.0.9\tpublished\tGitHub Stable release v1.0.9", ledger.read_text())

    def test_website_rejects_missing_exact_previous_version(self):
        site = self.root / "website"; public = site / "public"; assets = public / "assets"; updates = public / "updates"
        assets.mkdir(parents=True); updates.mkdir(); (public / "index.html").write_text('<script src="/assets/index.js"></script>')
        (assets / "index.js").write_text("no release value")
        (public / "appcast.xml").write_text('<rss><channel><item><shortVersionString>1.0.8</shortVersionString></item></channel></rss>')
        config = dict(self.config, website_repository=str(site))
        with self.assertRaises(channels.ChannelError): channels.stage_website_payload(config, site, self.root / "scratch")

    def test_react_sources_update_only_exact_previous_release_references(self):
        site = self.root / "website"
        (site / "src").mkdir(parents=True)
        (site / "public").mkdir()
        (site / "public" / "appcast.xml").write_text('<rss><channel><item><shortVersionString>1.0.8</shortVersionString></item></channel></rss>')
        (site / "src" / "App.jsx").write_text('const url="releases/tag/v1.0.8"; const label="Download 1.0.8";')
        (site / "index.html").write_text('{"downloadUrl":"releases/tag/v1.0.8"}')
        (site / "CONTENT.md").write_text('Stable 1.0.8 remains current. README was checked at release tag v1.0.8.')
        channels.stage_react_website_sources(self.config, site)
        self.assertIn('releases/tag/v1.0.9', (site / "src" / "App.jsx").read_text())
        self.assertIn('Download 1.0.9', (site / "src" / "App.jsx").read_text())
        self.assertIn('releases/tag/v1.0.9', (site / "index.html").read_text())
        content = (site / "CONTENT.md").read_text()
        self.assertIn('Stable 1.0.9 remains current.', content)
        self.assertIn('README was checked at release tag v1.0.8.', content)

    def test_react_deployment_uses_rendered_client_output_and_verifies_release_links(self):
        site = self.root / "website"
        bundle = site / "dist" / "client" / "assets" / "index.js"
        bundle.parent.mkdir(parents=True)
        bundle.write_text('releases/tag/v1.0.9 Download 1.0.9')
        (bundle.parents[1] / "index.html").write_text('<script src="/assets/index.js"></script> releases/tag/v1.0.9 Download 1.0.9')
        (site / "public").mkdir()
        self.assertEqual(channels.deployment_directory(site), site / "dist" / "client")
        channels.verify_website_release_content(self.config, site)

    def test_failed_pr_check_never_requests_merge(self):
        payload = {"state": "OPEN", "headRefOid": self.sha, "statusCheckRollup": [{"conclusion": "FAILURE"}]}
        with patch.object(channels, "pr_state", return_value=payload), patch.object(channels, "checked") as checked:
            with self.assertRaises(channels.ChannelError): channels.wait_for_merge(self.root, "12", self.sha, poll_seconds=0)
        self.assertFalse(any(call.args[0][:3] == ["gh", "pr", "merge"] for call in checked.call_args_list))

    def test_merge_binds_the_exact_pr_head(self):
        open_state = {"state": "OPEN", "headRefOid": self.sha, "statusCheckRollup": [{"conclusion": "SUCCESS"}]}
        merged = {"state": "MERGED", "headRefOid": self.sha, "statusCheckRollup": [], "mergeCommit": {"oid": "b" * 40}}
        with patch.object(channels, "pr_state", side_effect=[open_state, merged]), patch.object(channels, "checked") as checked, patch.object(channels.time, "sleep"):
            self.assertEqual(channels.wait_for_merge(self.root, "12", self.sha, poll_seconds=0), "b" * 40)
        merge = next(call.args[0] for call in checked.call_args_list if call.args[0][:3] == ["gh", "pr", "merge"])
        self.assertEqual(merge[-2:], ["--match-head-commit", self.sha])

    def test_wrong_public_release_fails_closed(self):
        config = channels.load_config(self.path)
        response = {"tagName": "v1.0.9", "isDraft": False, "isPrerelease": False, "isImmutable": False, "targetCommitish": self.sha}
        with patch.object(channels, "checked", return_value=json.dumps(response)), patch.object(channels, "revision", return_value=self.sha):
            with self.assertRaises(channels.ChannelError): channels.ensure_github_release(config)

    def test_wrong_tag_commit_fails_before_channel_mutation(self):
        with patch.object(channels, "revision", return_value="b" * 40), patch.object(channels, "clean") as clean:
            self.assertEqual(channels.main(["--config", str(self.path), "--execute"]), 2)
        clean.assert_called_once()
        self.assertFalse((self.root / "source" / ".build" / "release-channel-runs").exists())

    def test_restart_skips_completed_website_without_deploying_again(self):
        journal = {"steps": {"website": {"status": "succeeded", "deployed_commit": self.sha}}}
        with patch.object(channels, "add_worktree") as worktree, patch.object(channels, "checked") as checked:
            channels.website_publish(self.config, self.root / "journal.json", journal, self.root / "worktrees", 0)
        worktree.assert_not_called()
        checked.assert_not_called()

    def test_wrong_live_artifact_stops_before_feed_is_recorded(self):
        journal = {"steps": {}}
        with patch.object(channels, "checked", side_effect=channels.ChannelError("archive hash differs")):
            with self.assertRaises(channels.ChannelError):
                channels.verify_live_feeds(self.config, self.root / "journal.json", journal, self.root / "worktrees")
        self.assertNotIn("live_feed", journal["steps"])

    def test_interrupted_deploy_is_never_retried(self):
        journal = {"steps": {"website": {"status": "pending", "pr": "12", "head": self.sha}, "website_deploy": {"status": "started", "commit": "b" * 40}}}
        with patch.object(channels, "wait_for_merge", return_value="b" * 40), patch.object(channels, "checked") as checked:
            with self.assertRaises(channels.ChannelError):
                channels.website_publish(self.config, self.root / "journal.json", journal, self.root / "worktrees", 0)
        checked.assert_not_called()

    def test_website_stage_validates_before_it_can_commit_or_deploy(self):
        journal = {"steps": {}}
        order = []
        def stage(_config, worktree, _scratch):
            order.append("local-appcast-validation")
            (worktree / "public").mkdir(parents=True, exist_ok=True)
        def add(_repository, destination, _ref, *_args):
            destination.mkdir(parents=True, exist_ok=True); (destination / ".git").write_text("gitdir: fixture")
        with patch.object(channels, "add_worktree", side_effect=add), patch.object(channels, "recover_pending_pr", return_value=None), \
             patch.object(channels, "stage_website_payload", side_effect=stage), patch.object(channels, "git", return_value=""), \
             patch.object(channels, "run", return_value=subprocess.CompletedProcess([], 1, "", "")), \
             patch.object(channels, "commit_and_push", side_effect=lambda *_: order.append("commit-push") or self.sha), \
             patch.object(channels, "existing_pr", return_value=None), patch.object(channels, "create_pr", return_value="12"), \
             patch.object(channels, "wait_for_merge", return_value="b" * 40), patch.object(channels, "revision", return_value="b" * 40), \
             patch.object(channels, "checked", side_effect=lambda command, *_args, **_kw: order.append("deploy" if command[:3] == ["bun", "run", "deploy"] else "command") or ""), \
             patch.object(channels, "verify_website_release_content"):
            channels.website_publish(self.config, self.root / "journal.json", journal, self.root / "worktrees", 0)
        self.assertLess(order.index("local-appcast-validation"), order.index("commit-push"))
        self.assertLess(order.index("commit-push"), order.index("deploy"))

    def test_website_gate_failure_prevents_merge(self):
        worktrees = self.root / "worktrees"; website = worktrees / "website"
        website.mkdir(parents=True); (website / ".git").write_text("gitdir: fixture")
        journal = {"steps": {"website": {"status": "pending", "pr": "9", "head": self.sha}}}
        def checked(command, *_args, **_kwargs):
            if command[:3] == ["bun", "run", "lint:html"]:
                raise channels.ChannelError("lint failed")
            return ""
        with patch.object(channels, "checked", side_effect=checked), patch.object(channels, "clean"), \
             patch.object(channels, "revision", return_value=self.sha), patch.object(channels, "wait_for_merge") as merge:
            with self.assertRaisesRegex(channels.ChannelError, "lint failed"):
                channels.website_publish(self.config, self.root / "journal.json", journal, worktrees, 0)
        merge.assert_not_called()

    def test_tap_candidate_audit_failure_prevents_pr_or_merge_and_restores_cask(self):
        worktrees = self.root / "worktrees"; tooling = worktrees / "release-tooling"
        generated = tooling / ".build" / "release-runs" / "1.0.9-22-aaaaaaaaaaaa" / "WindowRanger.rb"
        generated.parent.mkdir(parents=True); generated.write_text('version "1.0.9"\n')
        named = self.root / "named-tap"; (named / ".git").mkdir(parents=True); (named / "Casks").mkdir(); (named / "Casks" / "windowranger.rb").write_text('version "1.0.8"\n')
        config = dict(self.config, named_tap_checkout=str(named))
        original = (named / "Casks" / "windowranger.rb").read_bytes()
        journal = {"steps": {}}
        def checked(command, *_args, **_kwargs):
            return str(named) if command[:3] == ["brew", "--repository", "appranger/tap"] else ""
        def failing_audit(command, *args, **kwargs):
            if command[:2] == ["brew", "audit"]:
                self.assertEqual(kwargs["environment"]["HOMEBREW_NO_AUTO_UPDATE"], "1")
                raise channels.ChannelError("audit failed")
            return checked(command, *args, **kwargs)
        with patch.object(channels, "checked", side_effect=failing_audit), patch.object(channels, "commit_and_push") as commit, \
             patch.object(channels, "create_pr") as create, patch.object(channels, "wait_for_merge") as merge, \
             patch.object(channels, "clean"), patch.object(channels, "git", return_value="git@github.com:AppRanger/homebrew-tap.git"):
            with self.assertRaises(channels.ChannelError): channels.tap_publish(config, self.root / "journal.json", journal, worktrees, 0)
        self.assertEqual((named / "Casks" / "windowranger.rb").read_bytes(), original)
        commit.assert_not_called(); create.assert_not_called(); merge.assert_not_called()

    def test_tap_exact_updated_bytes_are_styled_and_audited(self):
        worktrees = self.root / "worktrees"; tooling = worktrees / "release-tooling"
        generated = tooling / ".build" / "release-runs" / "1.0.9-22-aaaaaaaaaaaa" / "WindowRanger.rb"
        generated.parent.mkdir(parents=True); generated.write_text('version "1.0.9"\n')
        named = self.root / "named-tap"; (named / ".git").mkdir(parents=True); (named / "Casks").mkdir(); (named / "Casks" / "windowranger.rb").write_bytes(generated.read_bytes())
        config = dict(self.config, named_tap_checkout=str(named))
        journal = {"steps": {"tap": {"status": "pending", "pr": "9", "head": self.sha}}}
        def checked(command, *_args, **_kwargs): return str(named) if command[:3] == ["brew", "--repository", "appranger/tap"] else ""
        def merged(*_args, **_kwargs):
            self.assertTrue(any(call.args[0][:2] == ["brew", "audit"] for call in commands.call_args_list))
            return "b" * 40
        with patch.object(channels, "checked", side_effect=checked) as commands, patch.object(channels, "wait_for_merge", side_effect=merged), \
             patch.object(channels, "clean"), patch.object(channels, "git", return_value="git@github.com:AppRanger/homebrew-tap.git"), patch.object(channels, "revision", return_value="b" * 40):
            channels.tap_publish(config, self.root / "journal.json", journal, worktrees, 0)
        actions = [call.args[0][:2] for call in commands.call_args_list]
        self.assertIn(["brew", "style"], actions); self.assertIn(["brew", "audit"], actions)

    def test_tap_requires_named_checkout_for_candidate_validation(self):
        with self.assertRaisesRegex(channels.ChannelError, "named_tap_checkout is required"):
            channels.named_tap_checkout(self.config, self.root / "tap")

    def test_release_input_verifiers_use_bound_tooling_checkout(self):
        tooling = self.root / "tooling"; tooling.mkdir()
        with patch.object(channels, "checked") as checked:
            channels.verify_release_inputs(self.config, tooling)
        self.assertEqual(checked.call_count, 2)
        for call in checked.call_args_list:
            self.assertIn(str(tooling / "scripts" / "release.py"), call.args[0])
            self.assertEqual(call.args[1], tooling)

    def test_push_before_pr_recovery_pushes_once_then_creates_pr(self):
        with patch.object(channels, "git", side_effect=["1", "ok"] ) as git, patch.object(channels, "revision", return_value=self.sha), patch.object(channels, "existing_pr", return_value=None), patch.object(channels, "create_pr", return_value="42"):
            self.assertEqual(channels.recover_pending_pr(self.root, self.root, "codex/release-1.0.9-ledger", "develop", "title", "body"), ("42", self.sha))
        self.assertEqual(git.call_args_list[1].args[1:], ("push", "--set-upstream", "origin", "codex/release-1.0.9-ledger"))

    def test_cli_happy_path_runs_all_channel_checkpoints_in_order(self):
        tooling = self.root / "tooling"
        def add_worktree(_repository, destination, _ref, *_args):
            destination.mkdir(parents=True, exist_ok=True); (destination / ".git").write_text("gitdir: fixture")
        with patch.object(channels, "clean"), patch.object(channels, "revision", return_value=self.sha), \
             patch.object(channels, "ensure_github_release") as github, patch.object(channels, "add_worktree", side_effect=add_worktree), \
             patch.object(channels, "verify_release_inputs") as inputs, patch.object(channels, "source_ledger") as ledger, \
             patch.object(channels, "website_publish") as website, patch.object(channels, "verify_live_feeds") as live, \
             patch.object(channels, "tap_publish") as tap:
            self.assertEqual(channels.main(["--config", str(self.path), "--execute"]), 0)
        github.assert_called_once(); inputs.assert_called_once()
        self.assertEqual(ledger.call_args.args[0]["source_repository"], str((self.root / "source").resolve()))
        self.assertEqual(website.call_args.args[0]["source_repository"], str((self.root / "source" / ".build" / "release-channel-runs" / "1.0.9-22-aaaaaaaaaaaa" / "worktrees" / "release-tooling").resolve()))
        live.assert_called_once(); tap.assert_called_once()

    def test_cli_stops_before_live_or_tap_when_website_fails(self):
        def add_worktree(_repository, destination, _ref, *_args):
            destination.mkdir(parents=True, exist_ok=True); (destination / ".git").write_text("gitdir: fixture")
        with patch.object(channels, "clean"), patch.object(channels, "revision", return_value=self.sha), \
             patch.object(channels, "ensure_github_release"), patch.object(channels, "add_worktree", side_effect=add_worktree), \
             patch.object(channels, "verify_release_inputs"), patch.object(channels, "source_ledger"), \
             patch.object(channels, "website_publish", side_effect=channels.ChannelError("local appcast failed")), \
             patch.object(channels, "verify_live_feeds") as live, patch.object(channels, "tap_publish") as tap:
            self.assertEqual(channels.main(["--config", str(self.path), "--execute"]), 2)
        live.assert_not_called(); tap.assert_not_called()


if __name__ == "__main__": unittest.main()
