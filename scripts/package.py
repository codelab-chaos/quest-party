#!/usr/bin/env python3
"""Build an installable QuestParty ZIP without changing the working addon."""

import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parent.parent


def normalize_version(value):
    version = value.removeprefix("v")
    number = r"(?:0|[1-9][0-9]*)"
    if not re.fullmatch(rf"{number}\.{number}\.{number}(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?", version):
        raise ValueError("Use a version such as 0.1.0 or 0.2.0-rc.1 (optional v prefix).")
    if "-" in version:
        for part in version.split("-", 1)[1].split("."):
            if part.isdigit() and len(part) > 1 and part.startswith("0"):
                raise ValueError("Numeric prerelease identifiers cannot have leading zeroes.")
    return version


def build(version=None, output_dir=None):
    toc = (ROOT / "QuestParty/QuestParty.toc").read_text()
    match = re.search(r"^## Version: *(.+)$", toc, re.MULTILINE)
    if not match:
        raise ValueError("QuestParty.toc has no Version metadata.")
    version = normalize_version(version or match[1].strip())
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "QuestParty/"], cwd=ROOT
    ).decode().split("\0")
    files = {name: (ROOT / name).read_bytes() for name in tracked if name}
    for line in toc.splitlines():
        if line.strip() and not line.startswith("#"):
            name = "QuestParty/" + line.strip().replace("\\", "/")
            if name not in files:
                raise ValueError(f"TOC references an untracked or missing file: {name}")
    files["QuestParty/QuestParty.toc"] = re.sub(
        r"^## Version:.*$", f"## Version: {version}", toc, flags=re.MULTILINE
    ).encode()
    files["QuestParty/LICENSE"] = (ROOT / "LICENSE").read_bytes()
    output = Path(output_dir) if output_dir else ROOT / "dist"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"QuestParty-{version}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for name, data in sorted(files.items()):
            package.writestr(name, data)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(".zip.sha256").write_text(f"{checksum}  {archive.name}\n")
    print(archive)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Override the packaged TOC version; source stays unchanged.")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    try:
        build(args.version, args.output_dir)
    except ValueError as error:
        parser.error(str(error))
