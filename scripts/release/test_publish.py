"""Offline checks of archive preflight and partial release detection."""
import io
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import publish


class PublishTests(unittest.TestCase):
    base = "https://example.invalid"
    new = (4, "1.2.0", "14.0", f"{base}/Coinscal-1.2.0.zip", "42", "test-signature")
    old = (3, "1.1.0", "14.0", f"{base}/Coinscal-1.1.0.zip", "24", "previous-signature")

    def test_extracts_the_release_identity_from_the_feed(self):
        build, version, system, _, length, signature = self.new
        xml = publish.render_appcast(version, build, system, self.base, "Coinscal-1.2.0.zip", length, signature)
        with patch.object(publish.urllib.request, "urlopen", return_value=io.BytesIO(xml.encode())):
            self.assertEqual(publish.published_item(self.base, "appcast.en.xml"), self.new)

    def test_resume_only_skips_matching_feeds(self):
        feeds = ["appcast.en.xml", "appcast.zh-Hans.xml", "appcast.xml"]
        with patch.object(publish, "published_item", side_effect=[self.new, self.old, None]):
            self.assertEqual(publish.completed_appcasts(self.base, feeds, self.new), {"appcast.en.xml"})

    def test_refuses_to_overwrite_an_existing_versions_archive(self):
        higher = (5, *self.new[1:])
        with patch.object(publish, "published_item", return_value=self.new), patch("sys.stderr", new=io.StringIO()):
            with self.assertRaises(SystemExit):
                publish.completed_appcasts(self.base, ["appcast.xml"], higher)

    def test_archives_with_an_old_bundle_build_fail_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Coinscal.app"
            contents = app / "Contents"
            contents.mkdir(parents=True)
            (contents / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "3", "LSMinimumSystemVersion": "14.0",
            }))
            with patch.object(publish, "run"), patch("sys.stderr", new=io.StringIO()) as error:
                with self.assertRaises(SystemExit):
                    publish.check_app(app, "1.2.0", 4, "14.0", "EXAMPLETEAM")
            self.assertIn("CFBundleVersion is '3', expected '4'", error.getvalue())


if __name__ == "__main__":
    unittest.main()
