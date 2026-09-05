#!/usr/bin/env python3
"""Offline tests for scripts/verify-appcast.py."""

import base64
import json
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERIFIER = ROOT / "scripts" / "verify-appcast.py"
PREFIX = "https://windowranger.com/updates/"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class AppcastVerifierTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        candidates = ["/opt/homebrew/bin/openssl", shutil.which("openssl"), "/usr/local/bin/openssl"]
        self.openssl = next((candidate for candidate in candidates if candidate and Path(candidate).is_file()), None)
        if not self.openssl:
            self.skipTest("OpenSSL is unavailable")
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        self.key = self.root / "key.pem"
        self.public = self.root / "public.der"
        self.run_openssl("genpkey", "-algorithm", "Ed25519", "-out", str(self.key))
        self.run_openssl("pkey", "-in", str(self.key), "-pubout", "-outform", "DER", "-out", str(self.public))
        self.plist = self.root / "Info.plist"
        with self.plist.open("wb") as file:
            plistlib.dump({"SUPublicEDKey": base64.b64encode(self.public.read_bytes()[-32:]).decode()}, file)

    def tearDown(self):
        self.temp.cleanup()

    def run_openssl(self, *arguments):
        result = subprocess.run([self.openssl, *arguments], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def signed_artifact(self, name, payload=b"fixture payload"):
        artifact = self.artifacts / name
        artifact.write_bytes(payload)
        signature_path = self.root / f"{name}.sig"
        self.run_openssl("pkeyutl", "-sign", "-rawin", "-inkey", str(self.key), "-in", str(artifact), "-out", str(signature_path))
        return artifact, base64.b64encode(signature_path.read_bytes()).decode()

    def write_feed(self, *, build="20", version="1.0.7", length=None, signature=None, url=None, channel=None,
                   artifact_name="WindowRanger-1.0.7.zip"):
        artifact, generated_signature = self.signed_artifact(artifact_name)
        enclosure = ET.Element("enclosure", {
            "url": url or PREFIX + artifact.name,
            "length": str(len(artifact.read_bytes()) if length is None else length),
            f"{{{SPARKLE_NS}}}edSignature": generated_signature if signature is None else signature,
        })
        item = ET.Element("item")
        ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = build
        ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = version
        if channel:
            ET.SubElement(item, f"{{{SPARKLE_NS}}}channel").text = channel
        item.append(enclosure)
        rss = ET.Element("rss", {"xmlns:sparkle": SPARKLE_NS, "version": "2.0"})
        channel_node = ET.SubElement(rss, "channel")
        channel_node.append(item)
        feed = self.root / "appcast.xml"
        ET.ElementTree(rss).write(feed, encoding="utf-8", xml_declaration=True)
        return feed

    def invoke(self, feed, *, expected_build="20", expected_version="1.0.7", directory_name="output", expected_archive=None):
        output = self.root / directory_name
        command = [
            "python3", str(VERIFIER), "--feed", str(feed), "--key-plist", str(self.plist),
            "--expected-build", expected_build, "--expected-version", expected_version,
            "--artifact-directory", str(self.artifacts), "--local-only", "--download-directory", str(output),
            "--openssl", self.openssl,
        ]
        if expected_archive:
            command.extend(["--expected-archive", str(expected_archive)])
        return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True), output

    def test_verifies_real_signature_and_writes_result(self):
        result, output = self.invoke(self.write_feed())
        self.assertEqual(result.returncode, 0, result.stderr)
        verified = json.loads((output / "verification-result.json").read_text())
        self.assertEqual(verified["counts"]["enclosures"], 1)
        self.assertEqual(verified["newest_stable"]["build"], "20")

    def test_rejects_bad_signature_and_clears_prior_result(self):
        feed = self.write_feed()
        good, output = self.invoke(feed)
        self.assertEqual(good.returncode, 0, good.stderr)
        root = ET.parse(feed)
        enclosure = root.find(".//enclosure")
        enclosure.set(f"{{{SPARKLE_NS}}}edSignature", base64.b64encode(b"x" * 64).decode())
        root.write(feed, encoding="utf-8", xml_declaration=True)
        bad, _ = self.invoke(feed)
        self.assertNotEqual(bad.returncode, 0)
        self.assertFalse((output / "verification-result.json").exists())

    def test_rejects_wrong_length(self):
        result, _ = self.invoke(self.write_feed(length=1))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("length mismatch", result.stderr)

    def test_rejects_unsafe_filename(self):
        result, _ = self.invoke(self.write_feed(url=PREFIX + "../WindowRanger-1.0.7.zip"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directly below", result.stderr)

    def test_rejects_unexpected_newest_stable(self):
        result, _ = self.invoke(self.write_feed(build="21", version="1.0.8"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("newest Stable item", result.stderr)

    def test_rejects_item_without_full_zip_enclosure(self):
        result, _ = self.invoke(self.write_feed(artifact_name="WindowRanger20-19.delta"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no full ZIP enclosure", result.stderr)

    def test_rejects_valid_signed_old_zip_claiming_newest_metadata(self):
        result, _ = self.invoke(self.write_feed(artifact_name="WindowRanger-1.0.6.zip"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must directly enclose WindowRanger-1.0.7.zip", result.stderr)

    def test_compares_newest_zip_with_expected_archive(self):
        feed = self.write_feed()
        expected_archive = self.root / "independently-verified.zip"
        expected_archive.write_bytes(b"a different artifact")
        result, _ = self.invoke(feed, expected_archive=expected_archive)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mismatch against expected archive", result.stderr)

    def test_ignores_newer_beta_when_selecting_newest_stable(self):
        feed = self.write_feed()
        artifact, signature = self.signed_artifact("WindowRanger-1.0.8-beta.1.zip")
        root = ET.parse(feed)
        item = ET.SubElement(root.getroot().find("channel"), "item")
        ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = "99"
        ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = "1.0.8-beta.1"
        ET.SubElement(item, f"{{{SPARKLE_NS}}}channel").text = "beta"
        ET.SubElement(item, "enclosure", {
            "url": PREFIX + artifact.name,
            "length": str(artifact.stat().st_size),
            f"{{{SPARKLE_NS}}}edSignature": signature,
        })
        root.write(feed, encoding="utf-8", xml_declaration=True)
        result, output = self.invoke(feed)
        self.assertEqual(result.returncode, 0, result.stderr)
        verified = json.loads((output / "verification-result.json").read_text())
        self.assertEqual(verified["newest_stable"]["build"], "20")


if __name__ == "__main__":
    unittest.main(verbosity=2)
