#!/usr/bin/env python3
"""Run the repeatable, local portions of a WindowRanger release deliberately.

This is an orchestrator, not a replacement for the release runbook.  It never
creates tags, pushes refs, publishes a GitHub release, deploys an update feed,
changes a Homebrew tap, or starts/stops an application.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import hashlib
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


STAGES = (
    "plan",
    "build",
    "verify-local",
    "prepare",
    "draft",
    "verify-github",
    "stage-feed",
    "generate-feed",
    "verify-feed",
    "cask-prepare",
)
VERSION_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[1-9][0-9]*)?$")
BUILD_RE = re.compile(r"^[1-9][0-9]*$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


class ReleaseError(Exception):
    pass


def timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def command_output(command: list[str], cwd: Path) -> str:
    result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        message = result.stderr.strip() or result.stdout.strip() or "command failed"
        raise ReleaseError(f"{' '.join(command)}: {message}")
    return result.stdout.strip()


def git_revision(repository_root: Path, revision: str) -> str:
    resolved = command_output(["git", "rev-parse", "--verify", f"{revision}^{{commit}}"], repository_root)
    if not SHA_RE.fullmatch(resolved):
        raise ReleaseError(f"Git did not return a full commit SHA for {revision}: {resolved}")
    return resolved


def require_clean_bound_head(repository_root: Path, commit: str) -> None:
    if git_revision(repository_root, "HEAD") != commit:
        raise ReleaseError("Refusing to build: HEAD no longer matches the journal commit")
    if command_output(["git", "status", "--porcelain", "--untracked-files=normal"], repository_root):
        raise ReleaseError("Refusing to build from a dirty worktree")


def file_fingerprint(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def stage_input_fingerprints(args: argparse.Namespace, stage: str) -> dict[str, str]:
    candidates: dict[str, Path | None] = {}
    if stage in {"draft", "generate-feed"}:
        candidates["release_notes"] = args.notes_file if stage == "draft" else args.release_notes
    if stage == "verify-feed":
        candidates["key_plist"] = args.key_plist
        if args.feed and Path(args.feed).is_file():
            candidates["feed"] = Path(args.feed)
    if stage == "stage-feed" and args.public_directory:
        candidates["public_appcast"] = args.public_directory / "appcast.xml"
    fingerprints = {}
    for name, candidate in candidates.items():
        if candidate:
            path = Path(candidate).resolve()
            fingerprints[name] = f"{path}:{file_fingerprint(path)}" if path.is_file() else f"{path}:missing"
    return fingerprints


def write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def load_journal(path: Path) -> dict[str, Any]:
    try:
        journal = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ReleaseError(f"Cannot read release journal {path}: {error}") from error
    if not isinstance(journal, dict) or journal.get("schema") != 1:
        raise ReleaseError(f"Release journal {path} has an unsupported schema")
    return journal


def safe_name(value: str) -> str:
    return value.replace("/", "_")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Plan or run one explicit WindowRanger release stage. Dry-run is the default.",
        epilog=(
            "Stages: plan records no command; build runs the credentialed distribution script; "
            "verify-local validates the five local assets; prepare runs build then verify-local; "
            "draft creates a GitHub draft only after an already-pushed tag; verify-github downloads "
            "and checks an existing GitHub release; stage-feed makes a fresh local flat feed work directory; "
            "generate-feed signs a staged feed; verify-feed checks the published appcast and its "
            "enclosures; cask-prepare generates a local cask only after verifying the immutable public "
            "Stable release. Tagging/pushing, publishing a draft, website/feed deployment, Homebrew tap "
            "changes, installation, and live validation remain separate maintainer actions."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--stage", choices=STAGES, default="plan", help="One stage to plan or execute (default: plan).")
    parser.add_argument("--version", required=True, help="Stable X.Y.Z or Beta X.Y.Z-beta.N version.")
    parser.add_argument("--build-number", required=True, help="Allocated positive public build number.")
    parser.add_argument("--commit", default="HEAD", help="Commit to bind into the journal (default: HEAD).")
    parser.add_argument("--execute", action="store_true", help="Run the selected stage and write its journal/logs.")
    parser.add_argument("--resume", action="store_true", help="Resume an existing journal with identical provenance.")
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[1], help=argparse.SUPPRESS)
    parser.add_argument("--release-root", type=Path, help="Artifact root (default: REPOSITORY/.build/releases).")
    parser.add_argument("--notary-profile", help="Required by the build stage.")
    parser.add_argument("--notary-keychain", type=Path, help="Optional file-based keychain passed to the build script.")
    parser.add_argument("--sparkle-feed-url", help="HTTPS feed URL passed to the build script.")
    parser.add_argument("--sparkle-public-key", help="Public EdDSA key passed to the build script.")
    parser.add_argument("--initial-update-feed", action="store_true", help="Pass only for an authoritative absent first feed.")
    parser.add_argument("--notes-file", type=Path, help="Release notes passed to the draft stage.")
    parser.add_argument("--feed", help="Published appcast URL or local feed path for verify-feed.")
    parser.add_argument("--key-plist", type=Path, help="Installed app Info.plist containing SUPublicEDKey for verify-feed.")
    parser.add_argument("--artifact-directory", type=Path, help="Optional local enclosure directory for verify-feed.")
    parser.add_argument("--local-only", action="store_true", help="Verify local feed enclosures without network downloads (verify-feed only).")
    parser.add_argument("--openssl", type=Path, help="Explicit OpenSSL verifier passed to verify-feed.")
    parser.add_argument("--public-directory", type=Path, help="Website public directory used by stage-feed.")
    parser.add_argument("--feed-directory", type=Path, help="Fresh local feed directory used by stage-feed or generate-feed.")
    parser.add_argument("--sparkle-bin", type=Path, help="Directory containing generate_appcast for generate-feed.")
    parser.add_argument("--release-notes", type=Path, help="Release notes HTML/TXT used by generate-feed.")
    parser.add_argument("--sparkle-key-account", help="Optional existing Keychain account passed to generate-feed.")
    return parser


def validate_arguments(args: argparse.Namespace) -> None:
    if not VERSION_RE.fullmatch(args.version):
        raise ReleaseError("--version must be X.Y.Z or X.Y.Z-beta.N")
    if not BUILD_RE.fullmatch(args.build_number):
        raise ReleaseError("--build-number must be a positive integer")
    if args.stage in {"build", "prepare"} and not args.notary_profile:
        raise ReleaseError(f"--notary-profile is required for --stage {args.stage}")
    if args.stage == "verify-feed":
        if not args.feed or not args.key_plist:
            raise ReleaseError("--feed and --key-plist are required for --stage verify-feed")
        if args.local_only and not args.artifact_directory:
            raise ReleaseError("--artifact-directory is required with --local-only")
    if args.stage == "stage-feed" and (not args.public_directory or not args.feed_directory):
        raise ReleaseError("--public-directory and --feed-directory are required for --stage stage-feed")
    if args.stage == "generate-feed":
        if not args.feed_directory or not args.sparkle_bin or not args.release_notes:
            raise ReleaseError("--feed-directory, --sparkle-bin, and --release-notes are required for --stage generate-feed")
    if args.stage == "cask-prepare" and "-beta." in args.version:
        raise ReleaseError("--stage cask-prepare accepts Stable versions only")
    if args.stage == "verify-feed" and "-beta." in args.version:
        raise ReleaseError("--stage verify-feed accepts Stable versions only")


def stage_commands(args: argparse.Namespace, repository_root: Path, release_root: Path, commit: str, journal_root: Path) -> dict[str, list[list[str]]]:
    release_directory = release_root / args.version
    build = [str(repository_root / "scripts" / "build-distribution.sh"), "--version", args.version, "--build-number", args.build_number, "--notary-profile", args.notary_profile or ""]
    if args.notary_keychain:
        build.extend(["--notary-keychain", str(args.notary_keychain.resolve())])
    if args.sparkle_feed_url:
        build.extend(["--sparkle-feed-url", args.sparkle_feed_url])
    if args.sparkle_public_key:
        build.extend(["--sparkle-public-key", args.sparkle_public_key])
    if args.initial_update_feed:
        build.append("--initial-update-feed")

    local_verify = [str(repository_root / "scripts" / "verify-release-assets.sh"), "--version", args.version, "--release-directory", str(release_directory), "--expected-commit", commit]
    draft = [str(repository_root / "scripts" / "create-github-release.sh"), "--version", args.version]
    if args.notes_file:
        draft.extend(["--notes-file", str(args.notes_file.resolve())])
    github_verify = [str(repository_root / "scripts" / "create-github-release.sh"), "--version", args.version, "--verify-existing"]
    feed_verify = [sys.executable, str(repository_root / "scripts" / "verify-appcast.py"), "--feed", args.feed or "", "--key-plist", str(args.key_plist.resolve()) if args.key_plist else "", "--download-directory", str(journal_root / "feed-downloads"), "--expected-build", args.build_number, "--expected-version", args.version, "--expected-archive", str(release_directory / f"WindowRanger-{args.version}.zip")]
    if args.artifact_directory:
        feed_verify.extend(["--artifact-directory", str(args.artifact_directory.resolve())])
    if args.local_only:
        feed_verify.append("--local-only")
    if args.openssl:
        feed_verify.extend(["--openssl", str(args.openssl.resolve())])
    stage_feed = [sys.executable, str(repository_root / "scripts" / "stage-release-feed.py"), "--public-directory", str(args.public_directory.resolve()) if args.public_directory else "", "--destination", str(args.feed_directory.resolve()) if args.feed_directory else ""]
    generate_feed = [str(repository_root / "scripts" / "generate-update-appcast.sh"), "--version", args.version, "--feed-directory", str(args.feed_directory.resolve()) if args.feed_directory else "", "--sparkle-bin", str(args.sparkle_bin.resolve()) if args.sparkle_bin else "", "--release-notes", str(args.release_notes.resolve()) if args.release_notes else ""]
    if args.sparkle_key_account:
        generate_feed.extend(["--key-account", args.sparkle_key_account])
    cask = [str(repository_root / "scripts" / "generate-homebrew-cask.sh"), "--version", args.version, "--release-directory", str(release_directory), "--output", str(journal_root / "WindowRanger.rb"), "--replace", "--verify-public"]
    return {
        "plan": [], "build": [build], "verify-local": [local_verify], "prepare": [build, local_verify],
        "draft": [draft], "verify-github": [github_verify], "stage-feed": [stage_feed], "generate-feed": [generate_feed],
        "verify-feed": [local_verify, feed_verify], "cask-prepare": [cask],
    }


def run_command(command: list[str], cwd: Path, log_path: Path, release_root: Path) -> None:
    # Stream output to both the terminal and a durable stage log. Long notarization
    # and upload waits remain observable without granting the runner retry authority.
    with log_path.open("w", encoding="utf-8") as log_file:
        log_file.write("$ " + " ".join(command) + "\n\n")
        environment = os.environ.copy()
        environment["WINDOWRANGER_RELEASE_ROOT"] = str(release_root)
        process = subprocess.Popen(command, cwd=cwd, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert process.stdout is not None
        try:
            for line in process.stdout:
                log_file.write(line)
                log_file.flush()
                print(line, end="")
            returncode = process.wait()
        except KeyboardInterrupt:
            process.terminate()
            process.wait()
            raise
        finally:
            process.stdout.close()
    if returncode:
        raise ReleaseError(f"Stage command failed ({returncode}); inspect {log_path}")


def require_local_manifest_binding(release_root: Path, version: str, build_number: str, commit: str) -> None:
    manifest = release_root / version / f"WindowRanger-{version}.release.txt"
    if not manifest.is_file():
        raise ReleaseError(f"Missing release manifest required to bind this stage: {manifest}")
    values = {}
    for line in manifest.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if separator and key not in values:
            values[key] = value
    if values.get("build_number") != build_number:
        raise ReleaseError(f"Local manifest build {values.get('build_number')!r} does not match journal build {build_number}")
    if values.get("commit") != commit:
        raise ReleaseError("Local manifest commit does not match the journal commit")


def require_tag_binding(repository_root: Path, version: str, commit: str) -> None:
    tag_commit = git_revision(repository_root, f"v{version}")
    if tag_commit != commit:
        raise ReleaseError(f"Tag v{version} resolves to {tag_commit}, not the journal commit {commit}")


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        validate_arguments(args)
        repository_root = args.repository_root.resolve()
        if not (repository_root / ".git").exists():
            raise ReleaseError(f"Repository root is not a Git checkout: {repository_root}")
        release_root = (args.release_root or repository_root / ".build" / "releases").resolve()
        commit = git_revision(repository_root, args.commit)
        journal_root = repository_root / ".build" / "release-runs" / f"{safe_name(args.version)}-{args.build_number}-{commit[:12]}"
        journal_path = journal_root / "journal.json"
        inputs = {"version": args.version, "build_number": args.build_number, "commit": commit, "repository_root": str(repository_root), "release_root": str(release_root)}
        commands = stage_commands(args, repository_root, release_root, commit, journal_root)[args.stage]

        print(f"Release stage: {args.stage}\nVersion/build: {args.version} / {args.build_number}\nCommit: {commit}\nJournal: {journal_path}")
        if not args.execute:
            print("Dry run: no journal, artifacts, network release, or repository state will be changed.")
            for command in commands:
                print("$ " + " ".join(command))
            return 0

        if journal_path.exists():
            if not args.resume:
                raise ReleaseError(f"Release journal already exists: {journal_path}. Re-run with --resume after reviewing its logs.")
        else:
            if args.resume:
                raise ReleaseError(f"No release journal exists to resume: {journal_path}")
            journal_root.mkdir(parents=True, exist_ok=False)
            (journal_root / "logs").mkdir()
            write_json(journal_path, {"schema": 1, "created_at": timestamp(), "inputs": inputs, "stages": {}})
        lock_path = journal_root / ".lock"
        try:
            lock_descriptor = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.close(lock_descriptor)
        except FileExistsError as error:
            raise ReleaseError(f"Release journal is already active: {lock_path}") from error
        try:
            journal = load_journal(journal_path)
            if journal.get("inputs") != inputs:
                raise ReleaseError("Refusing to resume: version, build, commit, repository root, or release root differs from the journal")
            if args.stage == "plan":
                journal["stages"]["plan"] = {"status": "succeeded", "finished_at": timestamp(), "commands": []}
                write_json(journal_path, journal)
                print("Plan recorded. Use --execute with one later explicit stage after the required human gates.")
                return 0

            if args.stage == "prepare":
                stages_to_run = (("build", commands[0]), ("verify-local", commands[1]))
            elif args.stage == "verify-feed":
                stages_to_run = (("verify-local", commands[0]), ("verify-feed", commands[1]))
            else:
                stages_to_run = ((args.stage, command) for command in commands)
            read_only_stages = {"verify-local", "verify-github", "verify-feed-local", "verify-feed-remote"}
            for stage_name, command in stages_to_run:
                if stage_name == "verify-feed":
                    stage_name = "verify-feed-local" if args.local_only else "verify-feed-remote"
                prior = journal["stages"].get(stage_name)
                fingerprint_stage = "verify-feed" if stage_name.startswith("verify-feed-") else stage_name
                fingerprints = stage_input_fingerprints(args, fingerprint_stage)
                if prior and stage_name not in read_only_stages and (prior.get("command") != command or prior.get("input_fingerprints") != fingerprints):
                    raise ReleaseError(f"Refusing to resume {stage_name}: its command or file inputs differ from the recorded attempt")
                if prior and prior.get("status") == "succeeded" and stage_name not in read_only_stages:
                    print(f"Stage already succeeded in this journal: {stage_name}")
                    continue
                if stage_name == "build":
                    require_clean_bound_head(repository_root, commit)
                if stage_name == "verify-local":
                    require_local_manifest_binding(release_root, args.version, args.build_number, commit)
                if stage_name == "verify-github":
                    require_tag_binding(repository_root, args.version, commit)
                if stage_name == "draft":
                    require_local_manifest_binding(release_root, args.version, args.build_number, commit)
                    require_tag_binding(repository_root, args.version, commit)
                if stage_name in {"generate-feed", "cask-prepare"}:
                    require_local_manifest_binding(release_root, args.version, args.build_number, commit)
                log_path = journal_root / "logs" / f"{stage_name}-{uuid.uuid4().hex[:8]}.log"
                journal["stages"][stage_name] = {"status": "running", "started_at": timestamp(), "command": command, "input_fingerprints": fingerprints, "log": str(log_path)}
                write_json(journal_path, journal)
                try:
                    run_command(command, repository_root, log_path, release_root)
                except (ReleaseError, OSError, KeyboardInterrupt) as error:
                    journal["stages"][stage_name].update({"status": "failed", "finished_at": timestamp(), "error": str(error) or type(error).__name__})
                    write_json(journal_path, journal)
                    raise
                journal["stages"][stage_name].update({"status": "succeeded", "finished_at": timestamp()})
                write_json(journal_path, journal)
            if args.stage == "prepare":
                journal["stages"]["prepare"] = {"status": "succeeded", "finished_at": timestamp(), "commands": commands}
                write_json(journal_path, journal)
            print(f"Stage complete. Journal: {journal_path}")
            return 0
        finally:
            lock_path.unlink(missing_ok=True)
    except KeyboardInterrupt:
        print("release.py: interrupted; inspect the journal before resuming", file=sys.stderr)
        return 130
    except (ReleaseError, OSError) as error:
        print(f"release.py: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
