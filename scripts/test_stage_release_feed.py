import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("stage_feed", Path(__file__).with_name("stage-release-feed.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FeedStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.public = self.base / "public"
        (self.public / "updates").mkdir(parents=True)
        self.archive = self.public / "updates/WindowRanger-1.0.7.zip"
        self.archive.write_bytes(b"retained")
        self.feed = self.public / "appcast.xml"
        self.feed.write_text('<rss><channel><item><description>&lt;p&gt;Old notes&lt;/p&gt;</description>'
                             '<enclosure url="https://windowranger.com/updates/WindowRanger-1.0.7.zip"/>'
                             '</item></channel></rss>')
        self.destination = self.base / "stage"

    def test_preserves_feed_and_restores_missing_notes(self):
        module.stage(self.public, self.destination)
        self.assertEqual((self.destination / "appcast.xml").read_bytes(), self.feed.read_bytes())
        self.assertEqual((self.destination / self.archive.name).read_bytes(), b"retained")
        self.assertEqual((self.destination / "WindowRanger-1.0.7.html").read_text(), '<p>Old notes</p>')

    def test_existing_notes_preserved(self):
        (self.public / "updates/WindowRanger-1.0.7.txt").write_text("Original notes")
        module.stage(self.public, self.destination)
        self.assertFalse((self.destination / "WindowRanger-1.0.7.html").exists())

    def test_missing_artifact_leaves_no_destination(self):
        self.archive.unlink()
        with self.assertRaises(ValueError):
            module.stage(self.public, self.destination)
        self.assertFalse(self.destination.exists())

    def test_existing_destination_untouched(self):
        self.destination.mkdir()
        with self.assertRaises(ValueError):
            module.stage(self.public, self.destination)
        self.assertTrue(self.destination.is_dir())

    def test_symlink_artifact_rejected(self):
        self.archive.unlink()
        self.archive.symlink_to(self.feed)
        with self.assertRaises(ValueError):
            module.stage(self.public, self.destination)


if __name__ == "__main__":
    unittest.main()
