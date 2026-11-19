#!/usr/bin/env python3
"""Prune Quest Party's saved file while the game is closed.

Shows what the file holds; with --write, removes what is asked for and keeps
the original beside it as .bak. The same pruning is in game under Options
(Forget players, Forget cards) and Clear.

  scripts/prune-saved.py PATH                       show what it holds
  scripts/prune-saved.py PATH --log --write         drop the message log
  scripts/prune-saved.py PATH --players 7 --write   forget players not seen for 7 days
  scripts/prune-saved.py PATH --cards --keep "Your Name" --write
                                                     forget quest cards but your own
  scripts/prune-saved.py PATH --feed --write        empty the feed

PATH is WTF/Account/<ACCOUNT>/SavedVariables/QuestParty.lua. The game
rewrites the file on logout, so close it first.
"""

import argparse
import importlib.util
from pathlib import Path
import shutil
import time

spec = importlib.util.spec_from_file_location("saved_vars", Path(__file__).with_name("saved_vars.py"))
saved_vars = importlib.util.module_from_spec(spec)
spec.loader.exec_module(saved_vars)


def size(value):
    return len(saved_vars.dump_value(value, ""))


def describe(db):
    lines = []
    for key in ("feed", "cards", "members", "commsLog", "stats"):
        value = db.get(key)
        if isinstance(value, dict):
            lines.append(f"  {key:9} {len(value):5} entries  {size(value) / 1024:7.1f} KB")
    return "\n".join(lines)


def prune(db, args, now):
    removed = []
    if args.log and isinstance(db.get("commsLog"), dict):
        removed.append(f"message log ({len(db['commsLog'])})")
        db["commsLog"] = {}
    if args.feed and isinstance(db.get("feed"), dict):
        removed.append(f"feed ({len(db['feed'])})")
        db["feed"] = {}
    if args.cards and isinstance(db.get("cards"), dict):
        keep = set(args.keep or [])
        before = len(db["cards"])
        db["cards"] = {key: card for key, card in db["cards"].items() if isinstance(card, dict) and card.get("player") in keep}
        removed.append(f"quest cards ({before - len(db['cards'])})")
    if args.players is not None and isinstance(db.get("members"), dict):
        limit = now - args.players * 86400
        keep = set(args.keep or [])
        before = len(db["members"])
        db["members"] = {name: member for name, member in db["members"].items()
                         if name in keep or (isinstance(member, dict) and member.get("time", 0) >= limit)}
        removed.append(f"players not seen for {args.players} days ({before - len(db['members'])})")
    return removed


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", type=Path)
    parser.add_argument("--log", action="store_true", help="drop the saved message log")
    parser.add_argument("--feed", action="store_true", help="empty the feed")
    parser.add_argument("--cards", action="store_true", help="forget quest cards, but for --keep players")
    parser.add_argument("--players", type=float, metavar="DAYS", help="forget players not seen for this many days")
    parser.add_argument("--keep", action="append", metavar="NAME", help="a player to keep (your own characters)")
    parser.add_argument("--write", action="store_true", help="write the pruned file (keeps a .bak)")
    args = parser.parse_args()

    variables = saved_vars.parse(args.path.read_text(encoding="utf-8"))
    name = next((key for key in variables if key.endswith("DB") and not key.endswith("CharDB")), None)
    if not name or not isinstance(variables[name], dict):
        parser.error("no Quest Party saved variables in that file")
    db = variables[name]
    print(f"{args.path.name}: {args.path.stat().st_size / 1024:.1f} KB")
    print(describe(db))
    removed = prune(db, args, time.time())
    if not removed:
        return
    print("removes: " + ", ".join(removed))
    if not args.write:
        print("(nothing written: add --write)")
        return
    shutil.copyfile(args.path, args.path.with_suffix(args.path.suffix + ".bak"))
    args.path.write_text(saved_vars.dump(variables), encoding="utf-8")
    print(f"written: {args.path.stat().st_size / 1024:.1f} KB")
    print(describe(db))


if __name__ == "__main__":
    main()
