#!/usr/bin/env python3
"""Build the sandbox's recordings (QuestParty/sandbox/recording.lua) from a
saved message log, as 0.3.0 clients (the side quest build) would send them.

Each recording is one player's messages from the log, turned into a pretend
player: its name, class, race and sex are given here, and its messages are
brought up to what Quest Party 0.3.0 sends (RULES below), so two recordings
from one evening play back as two 0.3.0 clients together, in time with each
other.

  scripts/make-sandbox-recordings.py PATH   PATH is WTF/.../SavedVariables/QuestParty.lua
"""

import argparse
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
def load(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(f"{name}.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


saved_vars = load("saved_vars")
wire = load("wire")

# Which messages make each recording, and who it plays as. Race and sex were
# not in the log; these are made up.
RECORDINGS = [
    {"id": "tirisfal", "direction": "out", "name": "Replay Paladin", "class": "PALADIN", "race": "Human", "sex": 2,
     "about": "a level 11 paladin in Tirisfal Glades (the owner's side)"},
    {"id": "silverpine", "direction": "in", "sender": "Tombert Roams", "name": "Replay Warrior", "class": "WARRIOR", "race": "Scourge", "sex": 2,
     "about": "a level 14 warrior in Silverpine Forest (a friend's side, sent by 0.1.2)"},
]

VERSION = "0.3.0"
# 0.2.0 and later report skill-ups in professions only.
PROFESSIONS = {"Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid", "Fishing",
               "Herbalism", "Leatherworking", "Mining", "Skinning", "Tailoring"}
TURN_IN_SECONDS = 3  # an XP gain this soon after a turn-in, of the same amount, is its XP




def modernize(messages, recording):
    """Brings one player's messages up to 0.3.0. messages: [(time, kind, fields)]."""
    out, xp, last_turn_in = [], {}, None
    for time, kind, fields in messages:
        if kind == "E" and fields.get("t") == "xp":
            xp = {"x": fields.get("currentXP"), "m": fields.get("maxXP")}
    # A hello first, as 0.3.0 sends on connecting, if the log has none.
    first_xp = next((f for _, k, f in messages if k == "E" and f.get("t") == "xp"), None)
    if not any(kind == "H" for _, kind, _ in messages) and messages:
        hello = {"c": recording["class"], "v": VERSION, "r": recording["race"], "g": recording["sex"]}
        if first_xp:
            hello.update({"l": first_xp["level"], "x": first_xp["currentXP"] - first_xp["xp"], "m": first_xp["maxXP"]})
        zone = next((f.get("z") for _, k, f in messages if k in ("A", "H") and f.get("z")), None)
        if zone:
            hello["z"] = zone
        out.append((messages[0][0], "H", hello))
    xp = {}
    for time, kind, fields in messages:
        fields = dict(fields)
        if kind == "E":
            entry = fields.get("t")
            if entry == "skill" and fields.get("skill") not in PROFESSIONS:
                continue
            if entry == "quest_complete":
                last_turn_in = (time, fields.get("xp"), fields.get("quest"))
            if entry == "xp":
                xp = {"x": fields.get("currentXP"), "m": fields.get("maxXP"), "l": fields.get("level")}
                if last_turn_in and time - last_turn_in[0] <= TURN_IN_SECONDS and fields.get("xp") == last_turn_in[1] and "quest" not in fields:
                    fields["quest"] = last_turn_in[2]
        elif kind in ("H", "A", "P"):
            # An answer said again unprompted is a presence: never answered.
            if kind == "A":
                kind = "P"
            fields["v"] = VERSION
            fields.setdefault("r", recording["race"])
            fields.setdefault("g", recording["sex"])
            for key in ("x", "m"):
                if key not in fields and xp.get(key) is not None:
                    fields[key] = xp[key]
        out.append((time, kind, fields))
    return out


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(path):
    variables = saved_vars.parse(Path(path).read_text(encoding="utf-8"))
    log = variables["QuestPartyDB"]["commsLog"]
    records = [log[index] for index in sorted(log)]
    start = min(record["time"] for record in records)
    blocks = []
    for recording in RECORDINGS:
        chosen = [r for r in records if r.get("direction") == recording["direction"]
                  and (recording.get("sender") is None or r.get("sender") == recording["sender"])]
        messages = []
        for record in sorted(chosen, key=lambda r: r["time"]):
            version, kind, fields = wire.decode(record["text"])
            fields.pop("as", None)
            messages.append((record["time"], kind, fields))
        messages = modernize(messages, recording)
        lines, previous = [], messages[0][0] if messages else start
        for time, kind, fields in messages:
            lines.append(f"\t\t\t{{ after = {time - previous}, text = {lua_string(wire.encode('1', kind, fields))} }},")
            previous = time
        offset = (messages[0][0] - start) if messages else 0
        blocks.append(f'''	{recording["id"]} = {{
		-- {recording["about"]}
		name = {lua_string(recording["name"])},
		class = {lua_string(recording["class"])},
		race = {lua_string(recording["race"])},
		sex = {recording["sex"]},
		start = {offset}, -- seconds into the evening it starts
		messages = {{
''' + "\n".join(lines) + "\n\t\t},\n\t},")
    text = '''-- Real Quest Party sessions, for the sandbox to play back as pretend
-- players: what each player's client sent over one evening of leveling
-- (14 November 2026), with the seconds between messages, brought up to what
-- Quest Party 0.3.0 sends. Played together they are two 0.3.0 clients on one
-- channel, in time with each other.
-- Made by scripts/make-recordings.py from a saved message log; do not edit.
--   start  seconds into the evening the recording starts
--   after  seconds after the message before
--   text   the message as it goes over the wire
local _, ns = ...

ns.SandboxRecordings = {
''' + "\n".join(blocks) + "\n}\n"
    target = ROOT / "QuestParty/sandbox/recording.lua"
    target.write_text(text)
    print(f"{target.relative_to(ROOT)}: " + ", ".join(f"{r['id']}" for r in RECORDINGS))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", type=Path)
    build(parser.parse_args().path)
