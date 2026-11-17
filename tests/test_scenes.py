import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("scenes", ROOT / "scripts/scenes.py")
scenes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scenes)


class ScenesTest(unittest.TestCase):
    def test_reads_sixteen_scenes_that_fill_the_atlas(self):
        atlas, found = scenes.read_scenes()
        self.assertEqual((atlas["width"], atlas["height"], atlas["cellWidth"], atlas["cellHeight"]), (1024, 512, 512, 64))
        self.assertEqual(len(found), 16)
        self.assertEqual(len({scene["id"] for scene in found}), 16)
        self.assertEqual(scenes.cell_origin(atlas, 3), (512, 64))

    def test_builds_the_atlas_from_art_and_placeholders(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            # Art for one scene, the wrong shape and size: it is cropped to fit.
            art = scenes.Image(300, 100, (230, 220, 210, 255))
            scenes.write_png(art, folder / "meadow.png")
            report = scenes.build(art=folder, output=folder / "scenes.tga")
            self.assertIn("art, text zone too bright", report[0])
            self.assertIn("placeholder", report[1])
            data = (folder / "scenes.tga").read_bytes()
            self.assertEqual(len(data), 18 + 1024 * 512 * 4)
            # The top left pixel (the last row in the file) is the art (light, so its text zone is flagged).
            top_left = 18 + (511 * 1024) * 4
            self.assertEqual(tuple(data[top_left:top_left + 4]), (210, 220, 230, 255))

    def test_png_round_trip(self):
        with tempfile.TemporaryDirectory() as folder:
            image = scenes.Image(3, 2, (1, 2, 3, 255))
            image.set(2, 1, (9, 8, 7, 6))
            scenes.write_png(image, Path(folder) / "a.png")
            again = scenes.read_png(Path(folder) / "a.png")
            self.assertEqual(again.get(2, 1), (9, 8, 7, 6))
            self.assertEqual(again.get(0, 0), (1, 2, 3, 255))


if __name__ == "__main__":
    unittest.main()
