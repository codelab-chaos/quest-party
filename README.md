# Quest Party

Quest Party brings your adventures in **World of Warcraft: Forever** into one
compact, live feed. Follow quest objectives, level-ups, achievements, discoveries,
and profession gains without losing ongoing progress in a stream of chat.

- **Persistent quest cards** keep objectives and item counts visible across
  reloads, even without a channel connection. Your own quests refresh from your
  quest log; cached cards stay visible and turn gray after five minutes without
  an update.
- **Filter tabs** let you focus on quests, XP, achievements, professions, or the party view.
- **Detailed and compact views** fit the way you like to track your adventures.
- **Customizable output** lets you choose event categories, include your own
  progress, and optionally show updates in your local chat window.

Quest Party is being built for social questing, so friends can follow each
other's adventures even when they are in different places. Channel creation,
joining, and reconnecting are available now; **sharing quest progress through
the channel is still in development**.

## Installation

Quest Party targets **WoW Forever**, using the `_forever_` game installation.

### Manual installation

Download `QuestParty-<version>.zip` from the
[latest GitHub release](https://github.com/codelab-chaos/quest-party/releases/latest)
and extract it into `World of Warcraft/_forever_/Interface/AddOns/`.
The ZIP already contains the `QuestParty` folder.

Launch WoW Forever, enable **Quest Party** in **AddOns**, and type `/qp` in game.

To update manually, replace the installed `QuestParty` folder with the folder
from the newer release ZIP.

### CurseForge installation (coming soon)

Quest Party is not yet available on CurseForge. Use the manual installation above
for now. The planned listing is [Quest Party on CurseForge](https://www.curseforge.com/wow/addons/quest-party/).

Once the listing and its Forever release are available:

1. Install and open the [CurseForge app](https://www.curseforge.com/download/app).
2. Select **World of Warcraft**, then choose your **Forever** installation from
   the game instance dropdown. If needed, add the game's `_forever_` folder.
3. Browse or search for **Quest Party**, then click **Install**.
4. Launch WoW Forever, enable **Quest Party** in **AddOns**, and type `/qp` in game.

See [CurseForge's WoW installation and game instance guide](https://support.curseforge.com/support/solutions/articles/9000198422-faq-and-troubleshooting)
if the app does not show the expected installation or addon.

## Getting started

Use the tabs beneath the title to choose a feed. The view button switches between
detailed quest cards and compact rows; **O** opens Options for event categories,
chat output, **Include self**, channel setup, and **Clear**. The emulator toggle
also appears in Options when debug mode is enabled. Type `/qp` again to hide or
show the panel.

## Builds and releases

Every push to `main` and every pull request runs Lua 5.1 syntax checks, addon
tests, packaging tests and an installable ZIP build. Download test builds from
the **Checks and package** workflow's `QuestParty-build` artifact on the
[Actions page](https://github.com/codelab-chaos/quest-party/actions).
These builds do not publish a release.

When a version is ready to mark for release, open **Actions → Release → Run
workflow**, select `main`, and enter a version such as `0.1.0`. The workflow
runs all checks, stamps the version into the packaged TOC, creates the `v0.1.0`
tag at the tested commit, and publishes a **GitHub Release** with the
installable ZIP, SHA-256 checksum and generated release notes. These downloads
are visible on GitHub and can be shared for testing. This does not upload to
CurseForge. The working source's version is not changed by packaging. Update
its TOC version when starting a new version. Stable version tags become the
**Latest** release, visible in the repository sidebar. Tags with a suffix such
as `v0.2.0-rc.1` are marked as prereleases instead.

Alternatively, push an explicit version tag:

```sh
git tag -a v0.1.0 -m 'Quest Party 0.1.0'
git push origin v0.1.0
```

A failed check prevents publication. If a tag-triggered release fails before
publication, fix the issue in a new commit and use a new version, or re-run the
failed workflow if it was a temporary infrastructure failure. Existing release
assets are not overwritten. Pushing ordinary commits never deploys a release.

CurseForge publishing is planned for later. Follow
[Synthborn Terrascape's release pipeline](https://github.com/codelab-chaos/synthborn-terrascape/blob/main/.github/workflows/release-candidate.yml)
when connecting it: upload the same tested release archive after the GitHub
Release succeeds, and record the upload to avoid duplicates. No CurseForge
upload workflow or credentials are configured here yet.

## Local checks

From this project folder, with Lua 5.1 and Python 3.9 or newer installed:

```sh
find QuestParty tests -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/package.py
```

The Lua tests exercise real addon modules with mocked game APIs: quest card
lifecycle, saves, filters, timeline ordering, event collection, kill-credit
pairing, local chat output, debug tools and transport throttling. They do not
run the game's frame renderer or prove live server API behavior.

Before tagging a public release, smoke-test in WoW: `/reload`, open and close
Options, change each filter, resize the panel, switch row views, enable
`/qp debug on`, and use the emu-on/off button in Options to preview a sample party.
Then run `/qp debug off` and confirm the emulator stops and its
button disappears. Live channel sharing needs an in-game test once implemented.
Check for Lua errors with `/console scriptErrors 1` before reloading.

For local installation, `scripts/deploy.sh` uses the AddOns path in
`.deploy-target` (ignored by Git) or `WOW_ADDONS_DIR`.

Local source installs start in debug mode, making the emulator button available
after every reload. `/qp debug off` hides it until the next reload. Packaged ZIPs
disable this development default; users can still opt in with `/qp debug on`.

## License

[MIT](LICENSE).
