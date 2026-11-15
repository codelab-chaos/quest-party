import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("make_recordings", ROOT / "scripts/make-recordings.py")
make_recordings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_recordings)


def record(time, text, direction="out", sender=None):
    return {"time": time, "text": text, "direction": direction, "sender": sender}


class ModernizeTest(unittest.TestCase):
    def modernize(self, *texts):
        messages = []
        for time, text in texts:
            _, kind, fields = make_recordings.decode(text)
            messages.append((time, kind, fields))
        return make_recordings.modernize(messages)

    def test_keeps_only_entries_without_message_keys(self):
        steps = self.modernize(
            (0, "1:H:c=PALADIN;l=#12;v=0.1.2"),
            (1, "1:Q:c=PALADIN;id=#1;quest=A Quest"),
            (2, "1:E:as=Jaina;c=PALADIN;s=Reached level 12;t=level;level=#12"),
        )
        self.assertEqual(steps, [(2, "level", {"level": 12})])

    def test_drops_weapon_skills_and_keeps_professions(self):
        steps = self.modernize(
            (0, "1:E:c=WARRIOR;t=skill;skill=Swords;level=#40"),
            (1, "1:E:c=WARRIOR;t=skill;skill=Cooking;level=#26"),
        )
        self.assertEqual([data["skill"] for _, _, data in steps], ["Cooking"])

    def test_tags_a_turn_ins_xp_with_its_quest(self):
        steps = self.modernize(
            (0, "1:E:c=WARRIOR;t=quest_complete;quest=Tomb Weed;xp=#875"),
            (1, "1:E:c=WARRIOR;t=xp;xp=#875;mob=;level=#12;currentXP=#65;maxXP=#10100"),
            (9, "1:E:c=WARRIOR;t=xp;xp=#875;level=#12;currentXP=#940;maxXP=#10100"),
        )
        self.assertEqual(steps[1][2]["quest"], "Tomb Weed")
        self.assertNotIn("quest", steps[2][2])  # too late to be the turn-in's

    def test_players_share_one_timeline_with_gaps_between_steps(self):
        recording = {"players": [
            {"who": "a", "direction": "out", "name": "A", "class": "MAGE"},
            {"who": "b", "direction": "in", "sender": "Friend", "name": "B", "class": "ROGUE"},
        ]}
        records = [
            record(100, "1:E:c=MAGE;t=level;level=#2"),
            record(105, "1:E:c=ROGUE;t=level;level=#3", "in", "Friend"),
            record(107, "1:E:c=PRIEST;t=level;level=#9", "in", "Stranger"),
            record(130, "1:E:c=MAGE;t=level;level=#3"),
        ]
        steps = make_recordings.steps_for(records, recording)
        self.assertEqual([(after, who) for after, who, _, _ in steps], [(0, "a"), (5, "b"), (25, "a")])


if __name__ == "__main__":
    unittest.main()
