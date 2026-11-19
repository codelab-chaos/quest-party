import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("package", ROOT / "scripts/package.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackagingTests(unittest.TestCase):
    def test_installable_archive_and_checksum(self):
        original = (ROOT / "QuestParty/QuestParty.toc").read_bytes()
        with tempfile.TemporaryDirectory() as output:
            archive = package.build("v0.2.0-rc.1", output)
            with zipfile.ZipFile(archive) as release:
                self.assertIsNone(release.testzip())
                self.assertTrue(all(name.startswith("QuestParty/") for name in release.namelist()))
                toc = release.read("QuestParty/QuestParty.toc").decode()
                self.assertIn("## Version: 0.2.0-rc.1\n", toc)
                self.assertNotIn("X-Debug", toc) # dev mode is off by default, everywhere
                self.assertEqual(release.read("QuestParty/LICENSE"), (ROOT / "LICENSE").read_bytes())
                for line in toc.splitlines():
                    if line.strip() and not line.startswith("#"):
                        self.assertIn("QuestParty/" + line.replace("\\", "/"), release.namelist())
                self.assertFalse(any("tests/" in name or ".deploy-target" in name for name in release.namelist()))
            checksum, filename = archive.with_suffix(".zip.sha256").read_text().split()
            self.assertEqual(checksum, hashlib.sha256(archive.read_bytes()).hexdigest())
            self.assertEqual(filename, archive.name)
        self.assertEqual((ROOT / "QuestParty/QuestParty.toc").read_bytes(), original)

    def test_one_build_ships_dev_mode(self):
        """No sandbox build: the release carries dev mode, woken only by /qp debug."""
        with tempfile.TemporaryDirectory() as output:
            archive = package.build("v0.2.0-rc.1", output)
            with zipfile.ZipFile(archive) as release:
                names = release.namelist()
                toc = release.read("QuestParty/QuestParty.toc").decode()
                self.assertIn("dev\\dev.lua", toc)
                self.assertIn("QuestParty/dev/dev.lua", names)
                self.assertNotIn("X-Sandbox", toc)
                self.assertFalse(any("sandbox" in name.lower() for name in names))

    def test_harness_loads_dev_mode_as_the_toc_does(self):
        toc = (ROOT / "QuestParty/QuestParty.toc").read_text()
        dev = [line for line in package.toc_files(toc) if line.startswith("dev/")]
        self.assertTrue(dev)
        harness = (ROOT / "tests/harness.lua").read_text()
        for path in dev:
            self.assertIn(f'"{path}"', harness)

    def test_versions(self):
        for value in ("0.1.0", "v1.2.3", "2.0.0-alpha.1", "1.0.0-rc.2"):
            with self.subTest(value=value):
                self.assertEqual(package.normalize_version(value), value.removeprefix("v"))
        for value in ("latest", "1.0", "01.0.0", "v1.0.0-01", "1.0.0/../../file", "1.0.0\ninvalid"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                package.normalize_version(value)


if __name__ == "__main__":
    unittest.main()
