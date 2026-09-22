#!/usr/bin/env python3
"""Promote an already-public WindowRanger Stable release through its channels.

This coordinator deliberately starts *after* the immutable GitHub release.  A
JSON configuration binds one version, build and source commit to a durable
journal.  Preview is the default.  ``--execute`` is required for every write
and a failed checkpoint never authorises a later checkpoint.

It uses fixed argv calls only; configuration supplies paths and identities,
not arbitrary shell fragments.  It never installs or launches WindowRanger.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


VERSION = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
SHA = re.compile(r"^[0-9a-f]{40}$")
REQUIRED = {"version", "build_number", "release_commit", "source_repository", "website_repository", "tap_repository", "release_root", "sparkle_bin", "key_plist"}
LOG_DIRECTORY: Path | None = None
COMMAND_NUMBER = 0


class ChannelError(RuntimeError):
    pass


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_json(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def run(argv: list[str], cwd: Path, *, capture: bool = True, environment: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    if LOG_DIRECTORY and capture:
        LOG_DIRECTORY.mkdir(parents=True, exist_ok=True)
        prefix = f"{COMMAND_NUMBER:03d}-{Path(argv[0]).name}-{uuid.uuid4().hex[:8]}"
        stdout_path, stderr_path = (LOG_DIRECTORY / f"{prefix}.{stream}.log" for stream in ("stdout", "stderr"))
        command_log = LOG_DIRECTORY / f"{prefix}.command.log"
        command_log.write_text(f"Started: {now()}\n$ " + " ".join(argv) + "\n", encoding="utf-8")
        started = time.monotonic()
        with stdout_path.open("w", encoding="utf-8") as output, stderr_path.open("w", encoding="utf-8") as errors:
            process = subprocess.Popen(argv, cwd=cwd, text=True, stdout=output, stderr=errors, env=environment)
            try:
                while True:
                    try:
                        returncode = process.wait(timeout=30)
                        break
                    except subprocess.TimeoutExpired:
                        print(f"Still running {Path(argv[0]).name} ({int(time.monotonic() - started)}s); logs: {LOG_DIRECTORY}", flush=True)
            except KeyboardInterrupt:
                process.terminate()
                process.wait()
                raise
        with command_log.open("a", encoding="utf-8") as record:
            record.write(f"Finished: {now()}\nExit: {returncode}\nElapsed: {time.monotonic() - started:.3f}s\n")
        return subprocess.CompletedProcess(argv, returncode, stdout_path.read_text(encoding="utf-8"), stderr_path.read_text(encoding="utf-8"))
    return subprocess.run(argv, cwd=cwd, text=True, stdout=subprocess.PIPE if capture else None,
                          stderr=subprocess.PIPE if capture else None, check=False,
                          env=environment)


def checked(argv: list[str], cwd: Path, *, environment: dict[str, str] | None = None) -> str:
    global COMMAND_NUMBER
    COMMAND_NUMBER += 1
    result = run(argv, cwd, environment=environment)
    if result.returncode:
        detail = f"exit {result.returncode}; inspect {LOG_DIRECTORY}" if LOG_DIRECTORY else (result.stderr or result.stdout or "command failed").strip()[-1200:]
        raise ChannelError(f"{' '.join(argv[:3])}: {detail}")
    return (result.stdout or "").strip()


def git(root: Path, *arguments: str) -> str:
    return checked(["git", *arguments], root)


def revision(root: Path, ref: str) -> str:
    value = git(root, "rev-parse", "--verify", f"{ref}^{{commit}}")
    if not SHA.fullmatch(value):
        raise ChannelError(f"{root}: {ref} did not resolve to a full commit SHA")
    return value


def clean(root: Path) -> None:
    if git(root, "status", "--porcelain", "--untracked-files=normal"):
        raise ChannelError(f"Refusing to use dirty checkout: {root}")


def load_config(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ChannelError(f"Cannot read configuration {path}: {error}") from error
    if not isinstance(value, dict) or REQUIRED - value.keys():
        raise ChannelError("Configuration is missing required release-channel fields")
    if not VERSION.fullmatch(str(value["version"])) or not str(value["build_number"]).isdigit() or int(value["build_number"]) < 1:
        raise ChannelError("Configuration version/build_number is invalid")
    if not SHA.fullmatch(str(value["release_commit"])):
        raise ChannelError("Configuration release_commit must be a full lowercase SHA")
    value["tooling_commit"] = str(value.get("tooling_commit", value["release_commit"]))
    if not SHA.fullmatch(value["tooling_commit"]):
        raise ChannelError("tooling_commit must be a full lowercase SHA")
    for name in REQUIRED - {"version", "build_number", "release_commit"}:
        value[name] = str(Path(value[name]).expanduser().resolve())
    return value


def release_directory(config: dict[str, Any]) -> Path:
    return Path(config["release_root"]) / config["version"]


def journal_path(config: dict[str, Any], config_path: Path) -> Path:
    root = Path(config.get("journal_root", Path(config["source_repository"]) / ".build" / "release-channel-runs"))
    return root / f"{config['version']}-{config['build_number']}-{config['release_commit'][:12]}" / "journal.json"


def fingerprint_config(config_path: Path) -> str:
    return hashlib.sha256(config_path.read_bytes()).hexdigest()


def source_remote(config: dict[str, Any]) -> str:
    if config.get("source_remote", "origin") != "origin":
        raise ChannelError("source_remote must be origin; alternate remotes are not supported by channel recovery")
    return "origin"


def ensure_github_release(config: dict[str, Any]) -> None:
    source = Path(config["source_repository"])
    remote = git(source, "remote", "get-url", "origin")
    if not re.search(r"(?:github\.com[:/])AppRanger/windowranger(?:\.git)?$", remote):
        raise ChannelError("source origin is not the canonical AppRanger/windowranger repository")
    payload = json.loads(checked(["gh", "release", "view", f"v{config['version']}", "--repo", "AppRanger/windowranger", "--json", "tagName,isDraft,isPrerelease,isImmutable,targetCommitish"], source))
    if payload.get("tagName") != f"v{config['version']}" or payload.get("isDraft") or payload.get("isPrerelease") or not payload.get("isImmutable"):
        raise ChannelError("GitHub release is not a public immutable Stable release")
    target = str(payload.get("targetCommitish", ""))
    # GitHub may return a branch name here.  The tag binding remains authoritative.
    if SHA.fullmatch(target) and target != config["release_commit"]:
        raise ChannelError("GitHub release target commit does not match release_commit")
    if revision(source, f"v{config['version']}") != config["release_commit"]:
        raise ChannelError("Local release tag does not match release_commit")
    tag = f"refs/tags/v{config['version']}"
    refs = dict(line.split()[::-1] for line in git(source, "ls-remote", "--tags", "origin", tag, tag + "^{}").splitlines())
    if refs.get(tag + "^{}", refs.get(tag)) != config["release_commit"]:
        raise ChannelError("Public remote release tag does not match release_commit")


def verify_release_inputs(config: dict[str, Any], tooling: Path) -> None:
    """Run the existing manifest/assets and remote tag verifiers before any ledger write."""
    source = Path(config["source_repository"])
    common = [sys.executable, str(tooling / "scripts" / "release.py"), "--version", config["version"],
              "--build-number", str(config["build_number"]), "--commit", config["release_commit"],
              "--repository-root", str(tooling), "--release-root", config["release_root"], "--execute"]
    for stage in ("verify-local", "verify-github"):
        command = [*common, "--stage", stage]
        journal = tooling / ".build" / "release-runs" / f"{config['version']}-{config['build_number']}-{config['release_commit'][:12]}" / "journal.json"
        if journal.exists(): command.append("--resume")
        checked(command, tooling)


def ledger_row(path: Path, build: str, version: str) -> tuple[int, list[str]]:
    matches = []
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        columns = line.split("\t")
        if len(columns) >= 3 and columns[0] == build and columns[1] == version:
            matches.append((index, columns))
    if len(matches) != 1:
        raise ChannelError("Release ledger must contain exactly one allocated/published row for this version/build")
    return matches[0]


def mark_ledger_published(path: Path, build: str, version: str) -> None:
    index, row = ledger_row(path, build, version)
    if row[2] == "published":
        return
    if row[2] != "allocated":
        raise ChannelError(f"Release ledger state is {row[2]!r}, expected allocated")
    row[2] = "published"
    if len(row) >= 4:
        row[3] = f"GitHub Stable release v{version}"
    lines = path.read_text(encoding="utf-8").splitlines()
    lines[index - 1] = "\t".join(row)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def add_worktree(repository: Path, destination: Path, ref: str, branch: str | None = None, remote: str = "origin") -> None:
    if destination.exists():
        if not (destination / ".git").exists():
            raise ChannelError(f"Existing worktree path is not a Git checkout: {destination}")
        clean(destination)
        if git(destination, "remote", "get-url", "origin") != git(repository, "remote", "get-url", "origin"):
            raise ChannelError(f"Existing worktree belongs to a different repository: {destination}")
        if branch and git(destination, "branch", "--show-current") != branch:
            raise ChannelError(f"Existing worktree is not on expected branch {branch}: {destination}")
        if not branch and revision(destination, "HEAD") != revision(repository, ref):
            raise ChannelError(f"Existing detached worktree is not at expected commit {ref}: {destination}")
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    git(repository, "fetch", remote, "--prune")
    command = ["git", "worktree", "add"]
    if branch:
        command += ["-b", branch]
    command += [str(destination), ref]
    checked(command, repository)


def create_pr(repository: Path, branch: str, base: str, title: str, body: str) -> str:
    result = checked(["gh", "pr", "create", "--base", base, "--head", branch, "--title", title, "--body", body], repository)
    match = re.search(r"https://github\.com/[^\s]+/pull/(\d+)", result)
    if not match:
        raise ChannelError("gh pr create did not return a pull-request URL")
    return match.group(1)


def existing_pr(repository: Path, branch: str, expected_head: str, base: str = "main") -> str | None:
    payload = json.loads(checked(["gh", "pr", "list", "--head", branch, "--base", base, "--state", "all", "--json", "number,headRefOid,state"], repository))
    if not payload: return None
    if len(payload) != 1 or payload[0].get("headRefOid") != expected_head:
        raise ChannelError("Existing release PR does not have this run's exact head")
    if payload[0].get("state") == "CLOSED":
        raise ChannelError("Release PR was closed without merging; resolve it before resuming")
    return str(payload[0]["number"])


def recover_pending_pr(worktree: Path, repository: Path, branch: str, base: str, title: str, body: str) -> tuple[str, str] | None:
    """Recover a commit/push/PR interruption without replaying the content edit."""
    head = revision(worktree, "HEAD")
    existing = existing_pr(repository, branch, head, base)
    if existing:
        return existing, head
    ahead = git(worktree, "rev-list", "--count", f"origin/{base}..HEAD")
    if not ahead.isdigit() or int(ahead) == 0:
        return None
    git(worktree, "push", "--set-upstream", "origin", branch)
    return existing_pr(repository, branch, head, base) or create_pr(worktree, branch, base, title, body), head


def pr_state(repository: Path, number: str) -> dict[str, Any]:
    return json.loads(checked(["gh", "pr", "view", number, "--json", "state,mergeCommit,headRefOid,statusCheckRollup"], repository))


def wait_for_merge(repository: Path, number: str, expected_head: str, *, poll_seconds: int = 20, timeout_seconds: int = 1800, require_checks: bool = True) -> str:
    deadline, last_heartbeat = time.monotonic() + timeout_seconds, 0.0
    while True:
        payload = pr_state(repository, number)
        if payload.get("headRefOid") != expected_head:
            raise ChannelError("Pull request head changed after this run created it")
        checks = payload.get("statusCheckRollup") or []
        if any(check.get("conclusion") in {"FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"} for check in checks if isinstance(check, dict)):
            raise ChannelError("Pull request has a failed required check; refusing to merge")
        if payload.get("state") == "MERGED":
            merge = (payload.get("mergeCommit") or {}).get("oid")
            if not isinstance(merge, str) or not SHA.fullmatch(merge):
                raise ChannelError("Merged pull request has no immutable merge commit")
            return merge
        if payload.get("state") != "OPEN":
            raise ChannelError(f"Pull request is {payload.get('state')}, not open")
        complete = checks and all(check.get("conclusion") in {"SUCCESS", "SKIPPED", "NEUTRAL"} for check in checks if isinstance(check, dict))
        if (complete if require_checks else (not checks or complete)):
            checked(["gh", "pr", "merge", number, "--merge", "--delete-branch", "--match-head-commit", expected_head], repository)
        if time.monotonic() >= deadline:
            raise ChannelError(f"Timed out waiting for PR #{number}; resume after resolving its state")
        if time.monotonic() - last_heartbeat >= 60:
            print(f"Waiting for PR #{number} checks/merge…", flush=True)
            last_heartbeat = time.monotonic()
        time.sleep(poll_seconds)


def release_notes_path(config: dict[str, Any]) -> Path:
    notes = Path(config.get("release_notes", Path(config["source_repository"]) / "docs" / "releases" / f"v{config['version']}.md"))
    if not notes.is_file():
        raise ChannelError(f"Release notes are required to generate the signed feed: {notes}")
    if "release_notes" in config and hashlib.sha256(notes.read_bytes()).hexdigest() != config.get("release_notes_sha256"):
        raise ChannelError("Custom release notes require a matching release_notes_sha256 in the approved configuration")
    return notes


def stage_website_payload(config: dict[str, Any], website: Path, scratch: Path) -> None:
    public = website / "public"
    react_source = website / "src" / "App.jsx"
    if react_source.is_file():
        stage_react_website_sources(config, website)
        stage_website_feed(config, website, scratch, public)
        return

    index = public / "index.html"
    active = re.search(r'src="/assets/([^"?]+\.js)', index.read_text(encoding="utf-8"))
    if not active:
        raise ChannelError("Website public/index.html has no active JavaScript bundle")
    old_bundle = public / "assets" / active.group(1)
    if not old_bundle.is_file():
        raise ChannelError("Active website JavaScript bundle is missing")
    appcast = public / "appcast.xml"
    root = ET.parse(appcast).getroot()
    versions = [node.text.strip() for node in root.findall(".//{*}shortVersionString") if node.text and "-beta." not in node.text]
    if not versions:
        raise ChannelError("Website appcast has no previous Stable version")
    old_version = max(versions, key=lambda value: tuple(map(int, value.split("."))))
    contents = old_bundle.read_text(encoding="utf-8")
    occurrences = contents.count(old_version)
    if occurrences < 1:
        raise ChannelError("Active bundle has no exact previous Stable version to replace")
    new_name = old_bundle.stem + f"-v{config['version'].replace('.', '')}" + old_bundle.suffix
    new_bundle = old_bundle.with_name(new_name)
    if new_bundle.exists():
        raise ChannelError(f"Refusing to replace existing versioned website bundle: {new_bundle.name}")
    new_bundle.write_text(contents.replace(old_version, config["version"]), encoding="utf-8")
    index.write_text(index.read_text(encoding="utf-8").replace(old_bundle.name, new_bundle.name, 1), encoding="utf-8")
    if old_bundle.name in index.read_text(encoding="utf-8"):
        raise ChannelError("Website index still points at prior active JavaScript bundle")

    stage_website_feed(config, website, scratch, public)


def previous_stable_version(appcast: Path) -> str:
    root = ET.parse(appcast).getroot()
    versions = [node.text.strip() for node in root.findall(".//{*}shortVersionString") if node.text and "-beta." not in node.text]
    if not versions:
        raise ChannelError("Website appcast has no previous Stable version")
    return max(versions, key=lambda value: tuple(map(int, value.split("."))))


def replace_required(path: Path, old: str, new: str, description: str) -> None:
    contents = path.read_text(encoding="utf-8")
    if old not in contents:
        raise ChannelError(f"{description} has no exact previous Stable release reference")
    path.write_text(contents.replace(old, new), encoding="utf-8")


def stage_react_website_sources(config: dict[str, Any], website: Path) -> None:
    old_version = previous_stable_version(website / "public" / "appcast.xml")
    new_version = config["version"]
    replace_required(website / "src" / "App.jsx", f"releases/tag/v{old_version}", f"releases/tag/v{new_version}", "React homepage")
    replace_required(website / "src" / "App.jsx", f"Download {old_version}", f"Download {new_version}", "React homepage")
    replace_required(website / "index.html", f"releases/tag/v{old_version}", f"releases/tag/v{new_version}", "Homepage JSON-LD")
    replace_required(website / "CONTENT.md", f"Stable {old_version}", f"Stable {new_version}", "Website content")


def stage_website_feed(config: dict[str, Any], website: Path, scratch: Path, public: Path) -> None:
    staged = scratch / "feed"
    checked([sys.executable, str(Path(config["source_repository"]) / "scripts" / "stage-release-feed.py"), "--public-directory", str(public), "--destination", str(staged)], website)
    notes = release_notes_path(config)
    environment = dict(os.environ, WINDOWRANGER_RELEASE_ROOT=config["release_root"])
    checked([str(Path(config["source_repository"]) / "scripts" / "generate-update-appcast.sh"), "--version", config["version"], "--feed-directory", str(staged), "--sparkle-bin", config["sparkle_bin"], "--release-notes", str(notes)], website, environment=environment)
    archive = release_directory(config) / f"WindowRanger-{config['version']}.zip"
    checked([sys.executable, str(Path(config["source_repository"]) / "scripts" / "verify-appcast.py"),
             "--feed", str(staged / "appcast.xml"), "--key-plist", config["key_plist"],
             "--expected-build", str(config["build_number"]), "--expected-version", config["version"],
             "--expected-archive", str(archive), "--artifact-directory", str(staged), "--local-only",
             "--download-directory", str(scratch / "verification")], website)
    shutil.copy2(staged / "appcast.xml", public / "appcast.xml")
    for artifact in staged.iterdir():
        if artifact.name != "appcast.xml":
            shutil.copy2(artifact, public / "updates" / artifact.name)


def deployment_directory(website: Path) -> Path:
    rendered = website / "dist" / "client"
    return rendered if (rendered / "index.html").is_file() else website / "public"


def verify_website_release_content(config: dict[str, Any], website: Path) -> None:
    """Bind the rendered homepage and active client bundle to the release being published."""
    deployed = deployment_directory(website)
    index = deployed / "index.html"
    if not index.is_file():
        raise ChannelError(f"Website deployment has no homepage: {index}")
    contents = index.read_text(encoding="utf-8")
    expected_link = f"releases/tag/v{config['version']}"
    expected_label = f"Download {config['version']}"
    if expected_link not in contents or expected_label not in contents:
        raise ChannelError("Rendered homepage does not contain the expected Stable release link and label")
    active = re.search(r'src="/assets/([^"?]+\.js)', contents)
    if not active:
        raise ChannelError("Rendered homepage has no active JavaScript bundle")
    bundle = deployed / "assets" / active.group(1)
    if not bundle.is_file():
        raise ChannelError("Rendered homepage active JavaScript bundle is missing")
    bundle_contents = bundle.read_text(encoding="utf-8")
    if expected_link not in bundle_contents or expected_label not in bundle_contents:
        raise ChannelError("Rendered active JavaScript bundle does not contain the expected Stable release link and label")


def commit_and_push(worktree: Path, message: str, remote: str = "origin") -> str:
    if git(worktree, "diff", "--cached", "--name-only") == "":
        raise ChannelError("Dedicated worktree has no staged change to commit")
    # Callers deliberately stage only their declared paths before this checkpoint;
    # reject any remaining unstaged edits without rejecting the intended index.
    if git(worktree, "diff", "--name-only"):
        raise ChannelError("Dedicated worktree has unstaged changes")
    git(worktree, "commit", "-m", message)
    head = revision(worktree, "HEAD")
    branch = git(worktree, "branch", "--show-current")
    if not branch:
        raise ChannelError("Dedicated worktree is detached before push")
    git(worktree, "push", "--set-upstream", remote, branch)
    return head


def validate_website_worktree(worktree: Path, config: dict[str, Any], expected_head: str | None = None) -> None:
    """Run the website's local gate before its content can be published or merged."""
    if expected_head is not None:
        clean(worktree)
        if revision(worktree, "HEAD") != expected_head:
            raise ChannelError("Website worktree no longer matches the pull-request head")
    checked(["bun", "install", "--frozen-lockfile"], worktree)
    checked(["bun", "run", "lint:html"], worktree)
    checked(["bun", "run", "check"], worktree)
    checked(["bun", "run", "test"], worktree)
    verify_website_release_content(config, worktree)


def named_tap_checkout(config: dict[str, Any], tap: Path) -> Path:
    named = config.get("named_tap_checkout")
    if not isinstance(named, str) or not named.strip():
        raise ChannelError("named_tap_checkout is required for Homebrew validation")
    named_path = Path(named).expanduser().resolve()
    clean(named_path)
    if git(named_path, "remote", "get-url", "origin") != git(tap, "remote", "get-url", "origin"):
        raise ChannelError("named_tap_checkout remote differs from tap_repository")
    if Path(checked(["brew", "--repository", "appranger/tap"], named_path)).resolve() != named_path:
        raise ChannelError("named_tap_checkout is not the configured appranger/tap checkout")
    return named_path


def audit_cask_candidate(named_path: Path, generated: Path) -> None:
    """Audit generated cask bytes through Homebrew's configured named tap, restoring them always."""
    destination = named_path / "Casks" / "windowranger.rb"
    if not destination.is_file():
        raise ChannelError("named_tap_checkout is missing Casks/windowranger.rb")
    original = destination.read_bytes()
    try:
        destination.write_bytes(generated.read_bytes())
        environment = dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1")
        checked(["brew", "style", "--cask", "appranger/tap/windowranger"], named_path, environment=environment)
        checked(["brew", "audit", "--strict", "--online", "--cask", "appranger/tap/windowranger"], named_path, environment=environment)
    finally:
        destination.write_bytes(original)


def record_step(journal_file: Path, journal: dict[str, Any], name: str, **fields: Any) -> None:
    journal["steps"][name] = {"status": "succeeded", "at": now(), **fields}
    write_json(journal_file, journal)


def step_done(journal: dict[str, Any], name: str) -> bool:
    return journal["steps"].get(name, {}).get("status") == "succeeded"


def source_ledger(config: dict[str, Any], journal_file: Path, journal: dict[str, Any], worktrees: Path, poll_seconds: int) -> None:
    name = "ledger"
    if step_done(journal, name): return
    source = Path(config["source_repository"])
    branch = f"codex/release-{config['version']}-ledger"
    worktree = worktrees / name
    prior = journal["steps"].get(name, {})
    if "pr" not in prior:
        add_worktree(source, worktree, f"{source_remote(config)}/develop", branch, source_remote(config))
        recovered_state = recover_pending_pr(worktree, source, branch, "develop", f"Record {config['version']} release ledger", f"Bind build {config['build_number']} to immutable v{config['version']}.")
        recovered = recovered_state[0] if recovered_state else None
        if recovered:
            journal["steps"][name] = {"status": "pending", "pr": recovered, "head": recovered_state[1]}
            write_json(journal_file, journal)
            prior = journal["steps"][name]
        else:
            ledger = worktree / "config" / "release-builds.tsv"
            _, existing = ledger_row(ledger, str(config["build_number"]), config["version"])
            if existing[2] == "published":
                record_step(journal_file, journal, name, already_published=True)
                return
            mark_ledger_published(ledger, str(config["build_number"]), config["version"])
            checked([str(worktree / "scripts" / "verify-release-build-registry.sh"), "--version", config["version"], "--build-number", str(config["build_number"]), "--require-state", "published"], worktree)
            git(worktree, "add", "config/release-builds.tsv")
            head = commit_and_push(worktree, f"Record {config['version']} build {config['build_number']} as published")
            number = existing_pr(source, branch, head, "develop") or create_pr(worktree, branch, "develop", f"Record {config['version']} release ledger", f"Bind build {config['build_number']} to immutable v{config['version']}.")
            journal["steps"][name] = {"status": "pending", "pr": number, "head": head}
            write_json(journal_file, journal)
    prior = journal["steps"][name]
    merge = wait_for_merge(source, prior["pr"], prior["head"], poll_seconds=poll_seconds)
    record_step(journal_file, journal, name, pr=prior["pr"], head=prior["head"], merge_commit=merge)


def website_publish(config: dict[str, Any], journal_file: Path, journal: dict[str, Any], worktrees: Path, poll_seconds: int) -> None:
    name = "website"
    if step_done(journal, name): return
    website = Path(config["website_repository"])
    branch = f"codex/release-{config['version']}-feed"
    worktree = worktrees / name
    scratch = worktrees / "feed-staging"
    prior = journal["steps"].get(name, {})
    locally_validated = False
    if "pr" not in prior:
        add_worktree(website, worktree, "origin/main", branch)
        recovered_state = recover_pending_pr(worktree, website, branch, "main", f"Publish WindowRanger {config['version']} feed", "Generated appcast and immutable release payloads.")
        recovered = recovered_state[0] if recovered_state else None
        if recovered:
            journal["steps"][name] = {"status": "pending", "pr": recovered, "head": recovered_state[1]}
            write_json(journal_file, journal)
        else:
            stage_website_payload(config, worktree, scratch)
            validate_website_worktree(worktree, config)
            locally_validated = True
            paths = ["public/index.html", "public/assets", "public/appcast.xml", "public/updates"]
            if (worktree / "src" / "App.jsx").is_file():
                paths = ["src/App.jsx", "index.html", "CONTENT.md", "public/appcast.xml", "public/updates"]
            git(worktree, "add", *paths)
            if run(["git", "diff", "--cached", "--quiet"], worktree).returncode != 1:
                raise ChannelError("Website staging produced no changes")
            head = commit_and_push(worktree, f"Publish WindowRanger {config['version']} update feed")
            number = existing_pr(website, branch, head) or create_pr(worktree, branch, "main", f"Publish WindowRanger {config['version']} feed", "Generated appcast and immutable release payloads.")
            journal["steps"][name] = {"status": "pending", "pr": number, "head": head}
            write_json(journal_file, journal)
    prior = journal["steps"][name]
    deployment = journal["steps"].get("website_deploy", {})
    if deployment.get("status") == "started":
        raise ChannelError("Website deployment was interrupted after it started; reconcile production before marking the journal and resuming")
    if not locally_validated:
        validate_website_worktree(worktree, config, prior["head"])
    merge = wait_for_merge(website, prior["pr"], prior["head"], poll_seconds=poll_seconds, require_checks=False)
    deploy = worktrees / "website-deploy"
    if deployment.get("status") != "succeeded":
        add_worktree(website, deploy, merge)
        if revision(deploy, "HEAD") != merge:
            raise ChannelError("Deployment worktree is not at the merged website commit")
        checked(["bun", "install", "--frozen-lockfile"], deploy)
        checked(["bun", "run", "lint:html"], deploy)
        checked(["bun", "run", "check"], deploy)
        journal["steps"]["website_deploy"] = {"status": "started", "at": now(), "commit": merge}
        write_json(journal_file, journal)
        checked(["bun", "run", "deploy"], deploy)
        record_step(journal_file, journal, "website_deploy", commit=merge)
    record_step(journal_file, journal, name, pr=prior["pr"], head=prior["head"], merge_commit=merge, deployed_commit=merge)


def verify_live_feeds(config: dict[str, Any], journal_file: Path, journal: dict[str, Any], worktrees: Path) -> None:
    name = "live_feed"
    if step_done(journal, name): return
    urls = config.get("live_feed_urls", ["https://windowranger.com/appcast.xml", "https://www.windowranger.com/appcast.xml"])
    if not isinstance(urls, list) or len(urls) != 2 or any(not isinstance(url, str) or not url.startswith("https://") for url in urls):
        raise ChannelError("live_feed_urls must contain exactly two HTTPS appcast URLs")
    source = Path(config["source_repository"])
    deploy_root = deployment_directory(worktrees / "website-deploy")
    artifacts = deploy_root / "updates"
    archive = release_directory(config) / f"WindowRanger-{config['version']}.zip"
    for index, url in enumerate(urls):
        checked([sys.executable, str(source / "scripts" / "verify-appcast.py"), "--feed", url,
                 "--key-plist", config["key_plist"], "--expected-build", str(config["build_number"]),
                 "--expected-version", config["version"], "--expected-archive", str(archive),
                 "--artifact-directory", str(artifacts), "--download-directory", str(worktrees / f"live-feed-{index}")], source)
        site_root = url.removesuffix("/appcast.xml")
        site_directory = worktrees / f"live-site-{index}"; site_directory.mkdir(parents=True, exist_ok=True)
        live_feed = site_directory / "appcast.xml"
        checked(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--output", str(live_feed), url], source)
        if live_feed.read_bytes() != (artifacts.parent / "appcast.xml").read_bytes():
            raise ChannelError(f"Live appcast bytes differ from deployed merge commit: {url}")
        live_index = site_directory / "index.html"
        checked(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--output", str(live_index), site_root + "/"], source)
        deployed_index = deploy_root / "index.html"
        if live_index.read_bytes() != deployed_index.read_bytes():
            raise ChannelError(f"Live homepage bytes differ from deployed merge commit: {site_root}")
        active = re.search(r'src="/assets/([^"?]+\.js)', live_index.read_text(encoding="utf-8"))
        if not active: raise ChannelError(f"Live homepage has no active JavaScript bundle: {site_root}")
        live_bundle = site_directory / active.group(1)
        checked(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--output", str(live_bundle), site_root + "/assets/" + active.group(1)], source)
        expected_bundle = deploy_root / "assets" / active.group(1)
        if not expected_bundle.is_file() or live_bundle.read_bytes() != expected_bundle.read_bytes():
            raise ChannelError(f"Live JavaScript bundle differs from deployed merge commit: {site_root}")
        expected_link = f"releases/tag/v{config['version']}"
        expected_label = f"Download {config['version']}"
        if expected_link not in live_index.read_text(encoding="utf-8") or expected_label not in live_index.read_text(encoding="utf-8"):
            raise ChannelError(f"Live homepage does not contain the expected Stable release link and label: {site_root}")
        if expected_link not in live_bundle.read_text(encoding="utf-8") or expected_label not in live_bundle.read_text(encoding="utf-8"):
            raise ChannelError(f"Live JavaScript bundle does not contain the expected Stable release link and label: {site_root}")
    record_step(journal_file, journal, name, urls=urls)


def tap_publish(config: dict[str, Any], journal_file: Path, journal: dict[str, Any], worktrees: Path, poll_seconds: int) -> None:
    name = "tap"
    if step_done(journal, name): return
    source, tap = Path(config["source_repository"]), Path(config["tap_repository"])
    tooling = worktrees / "release-tooling"
    # Reuse the stage runner so cask provenance is bound to the same release manifest.
    release_journal = tooling / ".build" / "release-runs" / f"{config['version']}-{config['build_number']}-{config['release_commit'][:12]}" / "journal.json"
    release_command = [sys.executable, str(tooling / "scripts" / "release.py"), "--stage", "cask-prepare", "--version", config["version"], "--build-number", str(config["build_number"]), "--commit", config["release_commit"], "--repository-root", str(tooling), "--release-root", config["release_root"], "--execute"]
    if release_journal.exists(): release_command.append("--resume")
    checked(release_command, tooling)
    generated = tooling / ".build" / "release-runs" / f"{config['version']}-{config['build_number']}-{config['release_commit'][:12]}" / "WindowRanger.rb"
    if not generated.is_file(): raise ChannelError("release.py did not create the expected cask artifact")
    named_path = named_tap_checkout(config, tap)
    audit_cask_candidate(named_path, generated)
    branch, worktree = f"codex/release-{config['version']}-cask", worktrees / name
    prior = journal["steps"].get(name, {})
    if "pr" not in prior:
        add_worktree(tap, worktree, "origin/main", branch)
        recovered_state = recover_pending_pr(worktree, tap, branch, "main", f"Update WindowRanger cask to {config['version']}", "Generated from the immutable public Stable DMG.")
        recovered = recovered_state[0] if recovered_state else None
        if recovered:
            journal["steps"][name] = {"status": "pending", "pr": recovered, "head": recovered_state[1]}; write_json(journal_file, journal)
        else:
            destination = worktree / "Casks" / "windowranger.rb"; destination.parent.mkdir(exist_ok=True)
            shutil.copy2(generated, destination)
            git(worktree, "add", "Casks/windowranger.rb")
            head = commit_and_push(worktree, f"Update WindowRanger cask to {config['version']}")
            number = existing_pr(tap, branch, head) or create_pr(worktree, branch, "main", f"Update WindowRanger cask to {config['version']}", "Generated from the immutable public Stable DMG.")
            journal["steps"][name] = {"status": "pending", "pr": number, "head": head}; write_json(journal_file, journal)
    prior = journal["steps"][name]
    merge = wait_for_merge(tap, prior["pr"], prior["head"], poll_seconds=poll_seconds, require_checks=False)
    git(named_path, "fetch", "origin", "--prune")
    git(named_path, "checkout", "main")
    git(named_path, "merge", "--ff-only", "origin/main")
    if revision(named_path, "HEAD") != revision(named_path, "origin/main"):
        raise ChannelError("named_tap_checkout did not fast-forward to origin/main")
    if (named_path / "Casks" / "windowranger.rb").read_bytes() != generated.read_bytes():
        raise ChannelError("named_tap_checkout cask differs from the generated immutable cask")
    audit_cask_candidate(named_path, generated)
    record_step(journal_file, journal, name, pr=prior["pr"], head=prior["head"], merge_commit=merge)


def commands(config: dict[str, Any]) -> list[str]:
    source = Path(config["source_repository"])
    return [
        f"verify immutable GitHub release v{config['version']} bound to {config['release_commit'][:12]}",
        f"create clean source worktree from {source_remote(config)}/develop and publish ledger state",
        "wait for successful source PR checks, then merge the exact PR head",
        "stage and sign feed in a clean website worktree; open, verify, merge, then deploy the merged commit",
        "verify both live appcast URLs and all referenced payloads",
        "generate cask, open/merge tap PR, then style and audit the configured named tap checkout",
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--poll-seconds", type=int, default=20)
    args = parser.parse_args(argv)
    started = time.monotonic()
    try:
        config_path = args.config.resolve()
        config = load_config(config_path)
        source = Path(config["source_repository"])
        for key in ("source_repository", "website_repository", "tap_repository"):
            root = Path(config[key])
            if not (root / ".git").exists():
                raise ChannelError(f"{key} is not a Git checkout: {root}")
        journal_file = journal_path(config, config_path)
        print(f"Release channels {config['version']} build {config['build_number']}\nJournal: {journal_file}")
        if not args.execute:
            print("Dry run: no worktrees, commits, pull requests, deployments, or tap changes will be made.")
            for item in commands(config): print(f"- {item}")
            return 0
        clean(source)
        if revision(source, f"v{config['version']}") != config["release_commit"]:
            raise ChannelError("Source tag and release_commit differ")
        if journal_file.exists():
            if not args.resume: raise ChannelError("Journal exists; review it and use --resume")
            journal = json.loads(journal_file.read_text(encoding="utf-8"))
            if journal.get("config_fingerprint") != fingerprint_config(config_path): raise ChannelError("Configuration differs from journal")
        else:
            if args.resume: raise ChannelError("No journal exists to resume")
            journal_file.parent.mkdir(parents=True, exist_ok=False)
            journal = {"schema": 1, "created_at": now(), "config_fingerprint": fingerprint_config(config_path), "config": config, "steps": {}}
            write_json(journal_file, journal)
        worktrees = journal_file.parent / "worktrees"
        lock = journal_file.parent / ".lock"
        try:
            descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY); os.close(descriptor)
        except FileExistsError as error:
            raise ChannelError(f"Release-channel journal is already active: {lock}") from error
        try:
            journal = json.loads(journal_file.read_text(encoding="utf-8"))
            if journal.get("config_fingerprint") != fingerprint_config(config_path):
                raise ChannelError("Configuration differs from journal")
            global LOG_DIRECTORY, COMMAND_NUMBER
            LOG_DIRECTORY, COMMAND_NUMBER = journal_file.parent / "logs", 0
            ensure_github_release(config)
            record_step(journal_file, journal, "github_release")
            tooling = worktrees / "release-tooling"
            add_worktree(source, tooling, config["tooling_commit"])
            if revision(tooling, "HEAD") != config["tooling_commit"]:
                raise ChannelError("Release tooling worktree is not bound to tooling_commit")
            verify_release_inputs(config, tooling)
            record_step(journal_file, journal, "release_inputs", tooling_commit=config["tooling_commit"])
            tooling_config = dict(config, source_repository=str(tooling))
            source_ledger(config, journal_file, journal, worktrees, args.poll_seconds)
            website_publish(tooling_config, journal_file, journal, worktrees, args.poll_seconds)
            verify_live_feeds(tooling_config, journal_file, journal, worktrees)
            tap_publish(tooling_config, journal_file, journal, worktrees, args.poll_seconds)
            journal["finished_at"] = now()
            write_json(journal_file, journal)
        finally:
            LOG_DIRECTORY = None
            lock.unlink(missing_ok=True)
        print(f"All scripted channel checkpoints succeeded in {time.monotonic() - started:.1f}s. Installed-app acceptance remains outside this coordinator.")
        return 0
    except (ChannelError, OSError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
