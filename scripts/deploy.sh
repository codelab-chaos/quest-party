#!/usr/bin/env bash
# Copies the addon into a local WoW install so it can be tested in game.
#
# The AddOns folder comes from, in order:
#   1. the WOW_ADDONS_DIR environment variable
#   2. the first line of .deploy-target in the repo root (not committed)
#
# Usage:
#   scripts/deploy.sh            copy the addon
#   scripts/deploy.sh --dry-run  show what would change, copy nothing
set -euo pipefail

ADDON_NAME="QuestParty"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$REPO_ROOT/$ADDON_NAME"
TARGET_FILE="$REPO_ROOT/.deploy-target"

fail() {
	echo "deploy: $1" >&2
	exit 1
}

# No permission or owner syncing: the Windows drive cannot store them.
rsync_flags=(--recursive --links --times --delete --itemize-changes)
for arg in "$@"; do
	case "$arg" in
		--dry-run) rsync_flags+=(--dry-run) ;;
		*) fail "unknown option: $arg" ;;
	esac
done

addons_dir="${WOW_ADDONS_DIR:-}"
if [[ -z "$addons_dir" && -f "$TARGET_FILE" ]]; then
	addons_dir="$(head -n 1 "$TARGET_FILE")"
fi
addons_dir="${addons_dir%/}"

[[ -n "$addons_dir" ]] || fail "no target. Set WOW_ADDONS_DIR or put the AddOns path in .deploy-target"
[[ "$addons_dir" == */Interface/AddOns ]] || fail "target must end in Interface/AddOns: $addons_dir"
[[ -d "$addons_dir" ]] || fail "target folder does not exist: $addons_dir"
[[ -f "$SOURCE_DIR/$ADDON_NAME.toc" ]] || fail "addon not found at $SOURCE_DIR"

# --delete only removes stale files inside the addon's own folder.
# Saved variables live in the WTF folder and are never touched.
rsync "${rsync_flags[@]}" "$SOURCE_DIR/" "$addons_dir/$ADDON_NAME/"

version="$(sed -n 's/^## Version: *//p' "$SOURCE_DIR/$ADDON_NAME.toc" | tr -d '\r')"
echo "deploy: $ADDON_NAME $version -> $addons_dir/$ADDON_NAME"
echo "deploy: type /reload in game (restart the client if files were added or the TOC changed)"
