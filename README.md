# Quest Party

A WoW Forever addon for a party feed of quest progress, levels and achievements.
Options includes a channel name with **Create / Join**, connection status and
**Disconnect**. It remembers the name and reconnects on login until disconnected.
Channel progress broadcasting is the next development step; automatic group
discovery and character-name friend links have been retired. Install the `QuestParty`
folder inside `World of Warcraft/_forever_/Interface/AddOns`, then use `/qp` in game.

## Builds and releases

Every push to `main` and every pull request runs Lua 5.1 syntax checks, addon
tests, packaging tests and an installable ZIP build. Download test builds from
the **Checks and package** workflow's `QuestParty-build` artifact on the
[Actions page](https://github.com/codelab-chaos/quest-party/actions).
These builds do not publish a release.

When a version is ready to mark for release, open **Actions → Release → Run
workflow**, select `main`, and enter a version such as `0.1.0`. The workflow
runs all checks, stamps the version into the packaged TOC, creates the `v0.1.0`
tag at the tested commit, and publishes a **GitHub prerelease** with the
installable ZIP, SHA-256 checksum and generated release notes. These downloads
are visible on GitHub and can be shared for testing. This does not upload to
CurseForge. The working source's version is not changed by packaging. Update
its TOC version when starting a new version.

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
`/qp debug on`, and use the emu-on/off button to preview a sample party.
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
