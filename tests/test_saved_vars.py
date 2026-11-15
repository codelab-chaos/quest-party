import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("saved_vars", ROOT / "scripts/saved_vars.py")
saved_vars = importlib.util.module_from_spec(spec)
spec.loader.exec_module(saved_vars)

SAMPLE = '''
QuestPartyDB = {
	["feed"] = {
		{
			["type"] = "xp",
			["data"] = {
				["xp"] = 81,
				["mob"] = "Wandering \\"Spirit\\"",
			},
			["time"] = 1794719487,
		}, -- [1]
	},
	["debug"] = true,
	["ratio"] = 0.5,
	["note"] = "line\\nbreak",
}
QuestPartyCharDB = {
	["shown"] = false,
}
'''


class SavedVariablesTests(unittest.TestCase):
    def test_reads_what_the_game_writes(self):
        variables = saved_vars.parse(SAMPLE)
        db = variables["QuestPartyDB"]
        self.assertEqual(db["feed"][1]["data"]["mob"], 'Wandering "Spirit"')
        self.assertEqual(db["feed"][1]["time"], 1794719487)
        self.assertIs(db["debug"], True)
        self.assertEqual(db["ratio"], 0.5)
        self.assertEqual(db["note"], "line\nbreak")
        self.assertIs(variables["QuestPartyCharDB"]["shown"], False)

    def test_round_trip(self):
        variables = saved_vars.parse(SAMPLE)
        self.assertEqual(saved_vars.parse(saved_vars.dump(variables)), variables)


if __name__ == "__main__":
    unittest.main()
