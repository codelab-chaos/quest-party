#!/usr/bin/env python3
"""Build the emulator's recordings (QuestParty/emulator/recordings.lua) from a
saved message log, as Quest Party 0.1.3 clients would have sent them.

A recording is real players' messages from one evening, turned into pretend
players for the debug emulator (emulator/emulator.lua): `/qp emu play evening`
replays them in time with each other, and `/qp emu speed` speeds them up.
Each player's messages are brought up to what 0.1.3 sends (modernize below)
and written as emulator steps, so they go over the channel the same way the
sample party does.

  scripts/make-recordings.py PATH   PATH is WTF/.../SavedVariables/QuestParty.lua
"""

import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "QuestParty/emulator/recordings.lua"
spec = importlib.util.spec_from_file_location("saved_vars", Path(__file__).with_name("saved_vars.py"))
saved_vars = importlib.util.module_from_spec(spec)
spec.loader.exec_module(saved_vars)

# Which messages make each recording, and who each player in it plays as.
# Names are placeholders, so no real character names end up in the addon.
RECORDINGS = [
    {
        "id": "evening",
        "about": "14 November 2026: the owner leveling a paladin in Tirisfal Glades, a friend a warrior in Silverpine Forest",
        "players": [
            {"who": "paladin", "direction": "out", "name": "Replay Paladin", "class": "PALADIN"},
            {"who": "warrior", "direction": "in", "sender": "Tombert Roams", "name": "Replay Warrior", "class": "WARRIOR"},
        ],
    },
]

ENTRY = "E"
# Keys of an ENTRY that are about the message, not the entry's data
# (see comms/sharing.lua): type, class, pretend player, summary.
MESSAGE_KEYS = {"t", "c", "as", "s"}
# 0.1.3 reports skill-ups in professions only.
PROFESSIONS = {"Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing",
               "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring"}
TURN_IN_SECONDS = 3  # an XP gain this soon after a turn-in, of the same amount, is its XP


def decode(text):
    version, kind, body = text.split(":", 2)
    fields = {}
    for pair in body.split(";"):
        if "=" in pair:
            key, value = pair.split("=", 1)
            fields[key] = int(value[1:]) if value.startswith("#") and value[1:].lstrip("-").isdigit() else value
    return version, kind, fields


def modernize(messages):
    """One player's messages as 0.1.3 entries. messages: [(time, kind, fields)].

    Returns [(time, type, data)]. Only entries are kept: the emulator's
    pretend players send entries, not hellos or quest states.
    """
    out, last_turn_in = [], None
    for time, kind, fields in messages:
        if kind != ENTRY or not fields.get("t"):
            continue
        entry = fields["t"]
        data = {key: value for key, value in fields.items() if key not in MESSAGE_KEYS}
        if entry == "skill" and data.get("skill") not in PROFESSIONS:
            continue
        if entry == "quest_complete":
            last_turn_in = (time, data.get("xp"), data.get("quest"))
        if entry == "xp" and last_turn_in and not data.get("quest") and not data.get("mob") \
                and time - last_turn_in[0] <= TURN_IN_SECONDS and data.get("xp") == last_turn_in[1]:
            data["quest"] = last_turn_in[2]
        out.append((time, entry, data))
    return out


def lua_value(value):
    if isinstance(value, int):
        return str(value)
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_table(data):
    return "{ " + ", ".join(f"{key} = {lua_value(data[key])}" for key in sorted(data)) + " }"


def steps_for(records, recording):
    """Every player's entries in one timeline, with seconds between steps."""
    timeline = []
    for player in recording["players"]:
        chosen = [r for r in records if r.get("direction") == player["direction"]
                  and (player.get("sender") is None or r.get("sender") == player["sender"])]
        messages = []
        for record in sorted(chosen, key=lambda r: r["time"]):
            _, kind, fields = decode(record["text"])
            messages.append((record["time"], kind, fields))
        timeline += [(time, player["who"], entry, data) for time, entry, data in modernize(messages)]
    timeline.sort(key=lambda step: step[0])  # stable: a player's own order is kept
    steps, previous = [], timeline[0][0] if timeline else 0
    for time, who, entry, data in timeline:
        steps.append((time - previous, who, entry, data))
        previous = time
    return steps


def render(records):
    blocks = []
    for recording in RECORDINGS:
        personas = "\n".join(
            f'\t\t\t{p["who"]} = {{ name = {lua_value(p["name"])}, class = {lua_value(p["class"])} }},'
            for p in recording["players"])
        steps = "\n".join(
            f'\t\t\t{{ after = {after}, who = {lua_value(who)}, type = {lua_value(entry)}, data = {lua_table(data)} }},'
            for after, who, entry, data in steps_for(records, recording))
        blocks.append(f'''	{recording["id"]} = {{
		-- {recording["about"]}
		loop = false,
		personas = {{
{personas}
		}},
		steps = {{
{steps}
		}},
	}},''')
    return '''-- Real Quest Party sessions for the emulator to play back as pretend players
-- (/qp emu play <name>): what each player's client sent, with the seconds
-- between, brought up to what Quest Party 0.1.3 sends. Same shape as
-- emulator\\script.lua.
-- Made by scripts/make-recordings.py from a saved message log; do not edit.
local _, ns = ...

ns.EmulatorRecordings = {
''' + "\n".join(blocks) + "\n}\n"


def build(path):
    variables = saved_vars.parse(Path(path).read_text(encoding="utf-8"))
    log = variables["QuestPartyDB"]["commsLog"]
    records = [log[index] for index in sorted(log)]
    TARGET.write_text(render(records))
    print(f"{TARGET.relative_to(ROOT)}: " + ", ".join(r["id"] for r in RECORDINGS))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", type=Path)
    build(parser.parse_args().path)
