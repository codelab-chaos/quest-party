#!/usr/bin/env python3
"""Build an installable QuestParty ZIP without changing the working addon.

With --sandbox it builds QuestPartySandbox instead: the same source as a
second addon that plays pretend players (see QuestParty/sandbox). It renames
the folder, the TOC, the saved variables and the title, adds the sandbox's own
files from QuestParty/sandbox/files.toc, and always keeps debug on. With
--stage DIR it writes the sandbox as a folder from the working tree, for
scripts/deploy.sh, instead of a ZIP from the tracked files.
"""

import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import zipfile


ROOT = Path(__file__).resolve().parent.parent
SOURCE = "QuestParty"
SANDBOX = "QuestPartySandbox"
SANDBOX_DIR = "QuestParty/sandbox/"
SANDBOX_FILES = "QuestParty/sandbox/files.toc"


def sandbox_toc(toc, fragment):
    """The sandbox's TOC: Quest Party's, renamed, with the sandbox's files added."""
    replacements = [
        (r"^## Title:.*$", "## Title: Quest Party Sandbox"),
        (r"^## Notes:.*$", "## Notes: Pretend Quest Party players, for testing a party on the channel. Debug only."),
        (r"^## X-Debug:.*$", "## X-Debug: true\n## X-Sandbox: true"),
        (r"^## SavedVariables:.*$", f"## SavedVariables: {SANDBOX}DB"),
        (r"^## SavedVariablesPerCharacter:.*$", f"## SavedVariablesPerCharacter: {SANDBOX}CharDB"),
        (r"^## AddonCompartmentFunc:.*$", f"## AddonCompartmentFunc: {SANDBOX}_OnAddonCompartmentClick"),
    ]
    for pattern, value in replacements:
        toc, count = re.subn(pattern, value, toc, flags=re.MULTILINE)
        if count != 1:
            raise ValueError(f"QuestParty.toc has no line for {pattern}")
    lines = [line.strip() for line in fragment.splitlines() if line.strip() and not line.startswith("#")]
    return toc.rstrip("\n") + "\n" + "\n".join(lines) + "\n"


def toc_files(toc):
    return [line.strip().replace("\\", "/") for line in toc.splitlines() if line.strip() and not line.startswith("#")]


def stage_sandbox(destination):
    """Writes the sandbox addon folder from the working tree, for deploying."""
    destination = Path(destination)
    source = ROOT / SOURCE
    toc = sandbox_toc((source / "QuestParty.toc").read_text(), (ROOT / SANDBOX_FILES).read_text())
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if path.is_file() and relative.name != "QuestParty.toc" and "__pycache__" not in relative.parts:
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(path.read_bytes())
    (destination / f"{SANDBOX}.toc").write_text(toc)
    for name in toc_files(toc):
        if not (destination / name).is_file():
            raise ValueError(f"Sandbox TOC references a missing file: {name}")
    return destination


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


def build(version=None, output_dir=None, sandbox=False):
    toc = (ROOT / "QuestParty/QuestParty.toc").read_text()
    match = re.search(r"^## Version: *(.+)$", toc, re.MULTILINE)
    if not match:
        raise ValueError("QuestParty.toc has no Version metadata.")
    version = normalize_version(version or match[1].strip())
    tracked = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "QuestParty/"], cwd=ROOT
    ).decode().split("\0")
    files = {name: (ROOT / name).read_bytes() for name in tracked if name}
    if sandbox:
        toc = sandbox_toc(toc, files.pop("QuestParty/sandbox/files.toc").decode())
    else:
        # The sandbox's files are for the sandbox build only.
        files = {name: data for name, data in files.items() if not name.startswith(SANDBOX_DIR)}
    for name in toc_files(toc):
        if "QuestParty/" + name not in files:
            raise ValueError(f"TOC references an untracked or missing file: QuestParty/{name}")
    packaged_toc = re.sub(
        r"^## Version:.*$", f"## Version: {version}", toc, flags=re.MULTILINE
    )
    if not sandbox:
        packaged_toc = re.sub(r"^## X-Debug:.*$", "## X-Debug: false", packaged_toc, flags=re.MULTILINE)
    del files["QuestParty/QuestParty.toc"]
    files["QuestParty/LICENSE"] = (ROOT / "LICENSE").read_bytes()
    folder = SANDBOX if sandbox else SOURCE
    files = {folder + name[len(SOURCE):]: data for name, data in files.items()}
    files[f"{folder}/{folder}.toc"] = packaged_toc.encode()
    output = Path(output_dir) if output_dir else ROOT / "dist"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{folder}-{version}.zip"
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
    parser.add_argument("--sandbox", action="store_true", help="Build QuestPartySandbox instead.")
    parser.add_argument("--stage", type=Path, help="With --sandbox: write the addon folder from the working tree here.")
    args = parser.parse_args()
    try:
        if args.stage:
            if not args.sandbox:
                parser.error("--stage is for --sandbox")
            print(stage_sandbox(args.stage))
        else:
            build(args.version, args.output_dir, args.sandbox)
    except ValueError as error:
        parser.error(str(error))
