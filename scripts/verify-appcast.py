#!/usr/bin/env python3
"""Independently verify a Sparkle appcast and every referenced enclosure.

This tool is deliberately read-only with respect to a feed and its artifacts.  It
uses the public Ed25519 key embedded in a built app's Info.plist, so it does not
need a Keychain item or any release credentials.
"""

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DEFAULT_UPDATE_PREFIX = "https://windowranger.com/updates/"
PUBLIC_KEY_DER_PREFIX = bytes.fromhex("302a300506032b6570032100")
SAFE_FILENAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*\.(?:zip|delta)$")


class VerificationError(RuntimeError):
    pass


def fail(message):
    raise VerificationError(message)


def run(command, *, input_bytes=None):
    return subprocess.run(
        command,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def resolve_openssl(explicit_path):
    if explicit_path:
        candidates = [Path(explicit_path)]
    else:
        discovered = shutil.which("openssl")
        candidates = [Path("/opt/homebrew/bin/openssl")]
        if discovered:
            candidates.append(Path(discovered))
    candidate = next((path for path in candidates if path.is_file() and os.access(path, os.X_OK)), None)
    if candidate is None:
        requested = explicit_path or "OpenSSL from /opt/homebrew/bin or PATH"
        fail(f"OpenSSL verifier is not executable: {requested}")
    version = run([str(candidate), "version"])
    version_text = (version.stdout + version.stderr).decode(errors="replace").strip()
    if version.returncode or "LibreSSL" in version_text:
        fail(
            f"OpenSSL verifier must support Ed25519; found {version_text or candidate}. "
            "Install Homebrew OpenSSL or pass --openssl PATH_TO_OPENSSL."
        )
    return candidate


def load_public_key(plist_path):
    try:
        with plist_path.open("rb") as file:
            plist = plistlib.load(file)
    except (OSError, plistlib.InvalidFileException) as exc:
        fail(f"could not read key plist {plist_path}: {exc}")
    encoded = plist.get("SUPublicEDKey")
    if not isinstance(encoded, str):
        fail(f"SUPublicEDKey is missing from {plist_path}")
    try:
        key = base64.b64decode(encoded, validate=True)
    except ValueError as exc:
        fail(f"SUPublicEDKey is not valid base64: {exc}")
    if len(key) != 32:
        fail(f"SUPublicEDKey decoded length is {len(key)}, expected 32")
    return key


def enclosure_filename(url, allowed_prefix):
    if not url.startswith(allowed_prefix):
        fail(f"enclosure URL is outside {allowed_prefix}: {url!r}")
    parsed = urllib.parse.urlsplit(url)
    expected = urllib.parse.urlsplit(allowed_prefix)
    if (parsed.scheme, parsed.netloc) != (expected.scheme, expected.netloc):
        fail(f"invalid enclosure URL authority: {url!r}")
    if parsed.query or parsed.fragment or parsed.username or parsed.password:
        fail(f"enclosure URL must not contain credentials, query, or fragment: {url!r}")
    relative = parsed.path[len(expected.path):]
    if not relative or "/" in relative or "\\" in relative:
        fail(f"enclosure URL must name one artifact directly below the update prefix: {url!r}")
    decoded = urllib.parse.unquote(relative)
    if decoded != relative or not SAFE_FILENAME.fullmatch(decoded):
        fail(f"unsafe enclosure filename: {relative!r}")
    return decoded


def item_value(item, name):
    node = item.find(f"{{*}}{name}")
    if node is not None and node.text:
        return node.text.strip()
    return None


def parse_feed(feed_path, allowed_prefix):
    try:
        root = ET.parse(feed_path).getroot()
    except (ET.ParseError, OSError) as exc:
        fail(f"invalid appcast XML: {exc}")

    items = []
    enclosures = []
    seen_names = set()
    for item in root.findall(".//item"):
        channel = item_value(item, "channel") or "default"
        build = item_value(item, "version")
        version = item_value(item, "shortVersionString")
        item_enclosures = item.findall(".//{*}enclosure")
        for enclosure in item_enclosures:
            legacy_build = enclosure.get(f"{{{SPARKLE_NS}}}version")
            if build and legacy_build and build != legacy_build:
                fail(f"conflicting item and enclosure build numbers: {build}/{legacy_build}")
            build = build or legacy_build
            version = version or enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString")
        if not build or not build.isdigit() or not version:
            fail("every appcast item must provide a numeric build and short version")
        record = {"build": build, "version": version, "channel": channel}
        items.append(record)
        has_full_enclosure = False
        for enclosure in item_enclosures:
            url = enclosure.get("url")
            length = enclosure.get("length")
            signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature")
            if not url or not signature:
                fail("enclosure must have url and sparkle:edSignature")
            name = enclosure_filename(url, allowed_prefix)
            if name in seen_names:
                fail(f"appcast references {name} more than once")
            seen_names.add(name)
            has_full_enclosure = has_full_enclosure or name.endswith(".zip")
            try:
                declared_length = int(length)
            except (TypeError, ValueError):
                fail(f"invalid enclosure length for {url}: {length!r}")
            if declared_length <= 0:
                fail(f"enclosure length must be positive for {url}")
            enclosures.append({
                "url": url,
                "name": name,
                "length": declared_length,
                "signature": signature,
                "item": record,
            })
        if not has_full_enclosure:
            fail(f"appcast item build {build} has no full ZIP enclosure")
    if not enclosures:
        fail("feed has no enclosures")
    for item in items:
        if item["version"] and "-beta." in item["version"] and item["channel"] != "beta":
            fail(f"beta version {item['version']} must have beta channel")
    return items, enclosures


def verify_signature(openssl, public_key_der, artifact, signature):
    try:
        signature_bytes = base64.b64decode(signature, validate=True)
    except ValueError as exc:
        fail(f"invalid Ed25519 signature encoding for {artifact.name}: {exc}")
    if len(signature_bytes) != 64:
        fail(f"signature for {artifact.name} is {len(signature_bytes)} bytes, expected 64")
    with tempfile.NamedTemporaryFile(dir=artifact.parent, suffix=".sig") as signature_file:
        signature_file.write(signature_bytes)
        signature_file.flush()
        result = run([
            str(openssl), "pkeyutl", "-verify", "-rawin", "-pubin",
            "-inkey", str(public_key_der), "-in", str(artifact),
            "-sigfile", signature_file.name,
        ])
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        fail(f"Ed25519 verification failed for {artifact.name}: {detail}")


def newest_stable(items, enclosures, expected_build, expected_version):
    stable = [item for item in items if item["channel"] == "default" and (item["build"] or "").isdigit()]
    if not stable:
        fail("feed has no default-channel item with a numeric build")
    newest = max(stable, key=lambda item: int(item["build"]))
    if sum(item["build"] == newest["build"] for item in stable) != 1:
        fail(f"newest Stable build {newest['build']} appears more than once")
    if int(newest["build"]) != expected_build or newest["version"] != expected_version:
        fail(
            f"newest Stable item is build {newest['build']} version {newest['version']}, "
            f"expected {expected_build}/{expected_version}"
        )
    expected_name = f"WindowRanger-{expected_version}.zip"
    matching = [enclosure for enclosure in enclosures if enclosure["item"] is newest and enclosure["name"] == expected_name]
    if len(matching) != 1:
        fail(f"newest Stable item must directly enclose {expected_name}")
    return newest, matching[0]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feed", required=True, help="HTTPS feed URL or local XML path")
    parser.add_argument("--key-plist", required=True, type=Path, help="built app Info.plist with SUPublicEDKey")
    parser.add_argument("--expected-build", required=True, type=int)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--download-directory", required=True, type=Path)
    parser.add_argument("--artifact-directory", type=Path, help="directory containing every referenced artifact")
    parser.add_argument("--expected-archive", type=Path,
                        help="independently verified ZIP to hash-match against the newest Stable enclosure")
    parser.add_argument("--local-only", action="store_true", help="verify local artifacts without downloading")
    parser.add_argument("--openssl", help="path to OpenSSL (default: PATH, then /opt/homebrew/bin/openssl)")
    parser.add_argument("--allowed-url-prefix", default=DEFAULT_UPDATE_PREFIX)
    args = parser.parse_args(argv)
    if args.expected_build <= 0:
        parser.error("--expected-build must be positive")
    if "-beta." in args.expected_version:
        parser.error("--expected-version must be a Stable version; this verifier selects the default Stable channel")
    if args.local_only and not args.artifact_directory:
        parser.error("--local-only requires --artifact-directory")
    prefix = urllib.parse.urlsplit(args.allowed_url_prefix)
    if prefix.scheme != "https" or not prefix.netloc or not prefix.path.endswith("/") or prefix.query or prefix.fragment:
        parser.error("--allowed-url-prefix must be an HTTPS URL ending in /")

    download_directory = args.download_directory.resolve()
    download_directory.mkdir(parents=True, exist_ok=True)
    result_path = download_directory / "verification-result.json"
    result_path.unlink(missing_ok=True)
    openssl = resolve_openssl(args.openssl)
    if urllib.parse.urlsplit(args.feed).scheme:
        feed_url = urllib.parse.urlsplit(args.feed)
        if feed_url.scheme != "https" or feed_url.query or feed_url.fragment:
            fail("feed URL must be HTTPS without query or fragment")
        feed_path = download_directory / "appcast.xml"
        result = run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--retry", "2",
                      "--connect-timeout", "15", "--max-time", "120", "--output", str(feed_path), args.feed])
        if result.returncode:
            fail(f"curl failed ({result.returncode}) for {args.feed}: {result.stderr.decode(errors='replace').strip()}")
    else:
        feed_path = Path(args.feed).resolve()
        if not feed_path.is_file():
            fail(f"feed not found: {feed_path}")

    local_directory = args.artifact_directory.resolve() if args.artifact_directory else None
    if local_directory and not local_directory.is_dir():
        fail(f"artifact directory not found: {local_directory}")
    expected_archive = args.expected_archive.resolve() if args.expected_archive else None
    if expected_archive and not expected_archive.is_file():
        fail(f"expected archive not found: {expected_archive}")
    expected_archive_digest = hashlib.sha256(expected_archive.read_bytes()).hexdigest() if expected_archive else None
    items, enclosures = parse_feed(feed_path, args.allowed_url_prefix)
    newest, expected_enclosure = newest_stable(items, enclosures, args.expected_build, args.expected_version)
    public_key = load_public_key(args.key_plist.resolve())
    public_key_der = download_directory / "ed25519-public.der"
    public_key_der.write_bytes(PUBLIC_KEY_DER_PREFIX + public_key)

    records = []
    for index, enclosure in enumerate(enclosures, 1):
        print(f"[{index}/{len(enclosures)}] verifying {enclosure['name']}", flush=True)
        artifact = download_directory / f"{index:03d}-{enclosure['name']}"
        local_artifact = local_directory / enclosure["name"] if local_directory else None
        if args.local_only:
            if not local_artifact.is_file():
                fail(f"missing local artifact for {enclosure['url']}: {local_artifact}")
            shutil.copyfile(local_artifact, artifact)
        else:
            result = run(["/usr/bin/curl", "--fail", "--silent", "--show-error", "--location", "--retry", "2",
                          "--connect-timeout", "15", "--max-time", "120", "--output", str(artifact), enclosure["url"]])
            if result.returncode:
                fail(f"curl failed ({result.returncode}) for {enclosure['url']}: {result.stderr.decode(errors='replace').strip()}")
        actual_length = artifact.stat().st_size
        if actual_length != enclosure["length"]:
            fail(f"length mismatch for {enclosure['url']}: {actual_length} != {enclosure['length']}")
        verify_signature(openssl, public_key_der, artifact, enclosure["signature"])
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        if enclosure is expected_enclosure and expected_archive_digest and digest != expected_archive_digest:
            fail(f"SHA-256 mismatch against expected archive {expected_archive}")
        local_digest = None
        if local_artifact:
            local_digest = hashlib.sha256(local_artifact.read_bytes()).hexdigest()
            if local_digest != digest:
                fail(f"SHA-256 mismatch against local artifact {local_artifact}")
        records.append({"url": enclosure["url"], "item": enclosure["item"], "length": actual_length,
                        "sha256": digest, "local_sha256": local_digest})

    result = {
        "feed": args.feed,
        "feed_path": str(feed_path),
        "verification_mode": "local-only" if args.local_only else "network",
        "expected": {"build": args.expected_build, "version": args.expected_version},
        "newest_stable": newest,
        "counts": {"items": len(items), "enclosures": len(records)},
        "items": items,
        "enclosures": records,
    }
    if expected_archive:
        result["expected_archive"] = {"path": str(expected_archive), "sha256": expected_archive_digest}
    temporary_result = result_path.with_suffix(".json.tmp")
    temporary_result.write_text(json.dumps(result, separators=(",", ":")) + "\n")
    temporary_result.replace(result_path)
    print(json.dumps({"status": "ok", "items": len(items), "enclosures": len(records),
                      "newest_stable": newest, "result": str(result_path)}, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except VerificationError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
