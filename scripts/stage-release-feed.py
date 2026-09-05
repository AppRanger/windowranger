#!/usr/bin/env python3
"""Create a fresh flat Sparkle work directory from a website's public directory."""
import argparse
import os
from pathlib import Path
import re
import shutil
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET


def stage(public, destination):
    public, destination = Path(public).resolve(), Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"Destination already exists: {destination}")
    feed = public / "appcast.xml"
    updates = public / "updates"
    root = ET.parse(feed).getroot()
    required = set()
    notes = {}
    for item in root.findall("./channel/item"):
        enclosures = item.findall(".//enclosure")
        if not enclosures:
            raise ValueError("Feed item has no enclosure")
        for enclosure in enclosures:
            url = enclosure.get("url", "")
            prefix = "https://windowranger.com/updates/"
            name = url.removeprefix(prefix)
            if not url.startswith(prefix) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
                raise ValueError(f"Unsupported enclosure URL: {url}")
            required.add(name)
        archive = item.find("enclosure")
        description = item.find("description")
        if archive is not None and description is not None and description.text:
            name = urllib.parse.urlparse(archive.get("url", "")).path.rsplit("/", 1)[-1]
            if name.endswith(".zip"):
                # Sparkle needs the source notes again when regenerating retained items.
                notes[name[:-4] + ".html"] = description.text
    if not required:
        raise ValueError("Feed has no enclosures")
    for name in required:
        candidate = updates / name
        if not candidate.is_file() or candidate.is_symlink():
            raise ValueError(f"Missing regular retained artifact: {candidate}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=".feed-stage-", dir=destination.parent))
    try:
        for source in updates.iterdir():
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Expected flat regular update files: {source}")
            if source.name == "appcast.xml":
                raise ValueError("Updates directory must not contain another appcast.xml")
            shutil.copy2(source, temporary / source.name)
        shutil.copy2(feed, temporary / "appcast.xml")
        for name, content in notes.items():
            if not any((temporary / (name[:-5] + ext)).exists() for ext in (".html", ".txt")):
                (temporary / name).write_text(content, encoding="utf-8")
        # Never replace an existing directory, including an empty one created concurrently.
        destination.mkdir()
        try:
            for source in temporary.iterdir():
                os.rename(source, destination / source.name)
        except BaseException:
            shutil.rmtree(destination)
            raise
    finally:
        shutil.rmtree(temporary)
    print(f"Staged {len(required)} retained enclosure files: {destination}")
    print("Generate the new signed appcast, then independently verify every enclosure.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-directory", required=True)
    parser.add_argument("--destination", required=True)
    args = parser.parse_args()
    try:
        stage(args.public_directory, args.destination)
    except (ValueError, OSError, ET.ParseError) as error:
        parser.exit(1, f"ERROR: {error}\n")
