# Quest Party TOC

Date: 2026-11-12

How our `.toc` file should look for WoW Forever, based on Blizzard's own UI source.

## Reference source

- Local checkout: `/home/chadneff/git/hub/wow-ui-source` (a clone of Gethe/wow-ui-source).
- The checkout sits on the `live` branch (retail 12.1.5, build 70783). Forever lives on `origin/forever`.
- Forever build at time of writing: `1.60.1.70888` (commit `4cd0ab752`, 2026-11-10).
- Read it without switching branches:

```sh
cd /home/chadneff/git/hub/wow-ui-source
git show origin/forever:version.txt
git grep -n 'SendAddonMessage' origin/forever -- '*.lua'
git show origin/forever:Interface/AddOns/Blizzard_Minimap/Blizzard_Minimap.toc
```

Useful places on that branch:

| Path | What it gives us |
| --- | --- |
| `Interface/AddOns/Blizzard_APIDocumentationGenerated/` | Generated docs for every API, event and enum |
| `Interface/AddOns/Blizzard_AddOnList/AddonList.lua` | How the addon list reads our TOC metadata |
| `Interface/AddOns/Blizzard_Minimap/Mainline/AddonCompartment.lua` | How the minimap addon menu picks up addons |
| `Interface/AddOns/Blizzard_ProjectConstants/Camelot/ProjectConstants.lua` | The Forever project id |
| `Interface/AddOns/Blizzard_ObjectiveTracker/` | Blizzard's own quest tracking UI, a model for our cards |

## What the source tells us about game types

- Forever's internal game type is `camelot`. Blizzard's TOCs on the forever branch use `camelot` 406 times and never use `forever`.
- `WOW_PROJECT_CAMELOT = 18`, and `WOW_PROJECT_ID` is set to it. The constant only exists when the camelot game type is loaded.
- Camelot is part of the `mainline` family. In Blizzard TOCs, `[Family]` resolves to the `Mainline` folder and `[Game]` resolves to the `Camelot` folder. So Forever gets retail code by default, with Camelot overrides on top.
- The Warcraft Wiki says `forever` is accepted as an alias for `camelot` in TOC directives and file suffixes, and that Camelot is due to be renamed. The source does not confirm the alias, so it needs an in-game check.

## Directives Blizzard uses

Counted across the 350 TOC files on `origin/forever`. Only the ones relevant to a third-party addon are listed.

| Directive | Uses | Notes for us |
| --- | --- | --- |
| `Title` | 350 | Required. Shown in the addon list. |
| `Notes` | 29 | Tooltip text in the addon list. |
| `Version` | 32 | Read by `C_AddOns.GetAddOnMetadata(name, "Version")`. |
| `Author` | 141 | Plain metadata. |
| `AllowLoadGameType` | 97 | Restricts the addon to listed game types. |
| `ExcludeLoadGameType` | 5 | The inverse. |
| `SavedVariables` | 12 | Account-wide saved globals. |
| `SavedVariablesPerCharacter` | 10 | Per-character saved globals. |
| `LoadOnDemand` | 154 | Not needed, we load at login. |
| `OptionalDeps` / `OptionalDep` | 20 | Only if we embed or soft-depend on libraries. |
| `IconTexture` | 1 | Icon in the addon list and the minimap addon menu. `IconAtlas` is the alternative. |
| `Category` | 1 | Tree grouping in the addon list. |
| `Interface` | 1 | Blizzard addons skip it. Third-party addons need it, or the client flags them out of date (reason `INTERFACE_VERSION`). |

Metadata the client reads but Blizzard's own TOCs never set:

- `AddonCompartmentFunc`, `AddonCompartmentFuncOnEnter`, `AddonCompartmentFuncOnLeave`: names of global functions. Setting the first one adds us to the minimap addon menu. The compartment is loaded for camelot (it has its own `Camelot/AddonCompartment.lua`).
- `Group`: set automatically by the client from addon names and dependencies. Leave it alone.

Directives we should not use: `UseSecureEnvironment`, `Secure`, `LoadFirst`, `AllowLoad`, `OnlyBetaAndPTR` and similar are for Blizzard's signed addons.

## Inline tags

Blizzard tags individual lines, which lets one TOC serve several clients:

```
[Family]\AddonCompartment.lua   [AllowLoadGameType mainline]
[Game]\AddonCompartment.lua     [AllowLoadGameType camelot]
```

We target Forever only, so we don't need these yet. They are the route to take if we later support retail from the same folder.

## Proposed TOC

Folder and file name: `QuestParty/QuestParty.toc` (the TOC name must match the folder name). This is the TOC as it stands in the repo:

```
## Interface: 16001
## Title: Quest Party
## Notes: Share quest progress, levels and achievements with your party in a live feed.
## Author: Wizwonk
## Version: 0.1.0
## AllowLoadGameType: forever
## ExcludeLoadGameType: standard, classic
## Category: Quests
## IconTexture: Interface\Icons\spell_nature_astralrecalgroup
## SavedVariables: QuestPartyDB
## SavedVariablesPerCharacter: QuestPartyCharDB
## AddonCompartmentFunc: QuestParty_OnAddonCompartmentClick

core.lua
locales\en-us.lua
data\feed-types.lua
data\filters.lua
data\settings.lua
store.lua
comms\protocol.lua
comms\transport.lua
comms\session.lua
collectors\patterns.lua
collectors\samples.lua
collectors\collectors.lua
emulator\script.lua
emulator\emulator.lua
ui\view-model.lua
ui\panel.lua
ui\chat-echo.lua
commands.lua
```

Why each choice:

- **`Interface: 16001`:** the Forever interface number (from the wiki, matching client 1.60.1).
- **`AllowLoadGameType: forever` plus `ExcludeLoadGameType: standard, classic`:** the wiki's recommended pair. The exclude line is there because clients that don't know `forever` ignore the allow line and would load us anyway.
- **`Version: 0.1.0`:** hand-set for now. When we package for CurseForge it can become the `@project-version@` packager token, as Quest Tweet's `.pkgmeta` flow did.
- **Two saved variables instead of Quest Tweet's `QuestTweetLog, QuestTweetPref`:** `QuestPartyDB` holds account-wide settings and the feed history, `QuestPartyCharDB` holds per-character state such as panel position and active filters.
- **`AddonCompartmentFunc`:** gives a click target in the minimap addon menu to open the panel. It must be a global function, and it should be our only global besides the saved variables and slash commands.
- **`IconTexture`:** the group recall icon, the same icon shown beside the panel title.
- **No XML:** Quest Tweet built its options in XML. The current client lets us build frames in Lua and register options through the Settings API.

Files load top to bottom, and each has one responsibility:

| File | Single responsibility |
| --- | --- |
| `core.lua` | Addon table, message bus, text helpers, feature switches, saved variable defaults, startup |
| `locales\en-us.lua` | Display strings and feed text templates |
| `data\feed-types.lua` | Data table of feed entry types and card kinds. The successor to `QuestTweetOptionLabels`. |
| `data\filters.lua` | Data table of the filter tabs |
| `data\settings.lua` | Data table of the feature switches, and the card timing limits |
| `store.lua` | Feed rows, quest cards and the party roster |
| `comms\protocol.lua` | Wire format: encode and decode messages |
| `comms\transport.lua` | Raw addon messages, with a send queue for the throttle and chat lockdown |
| `comms\session.lua` | Who we share with: the party handshake and friend links |
| `collectors\patterns.lua` | Patterns for the game's own messages, built from its localized format strings |
| `collectors\samples.lua` | Sample game events for `/qp test` |
| `collectors\collectors.lua` | Turns this player's game events into entries, shown locally and sent out |
| `emulator\script.lua` | Facade data: fake party members and what they do |
| `emulator\emulator.lua` | Plays the script as if entries arrived from party members |
| `ui\view-model.lua` | Turns store state into plain rows for the panel |
| `ui\panel.lua` | The Party Panel window, tabs, rows and options view |
| `ui\chat-echo.lua` | Local `[Quest Party]` chat lines |
| `commands.lua` | Slash commands and the minimap menu click |

Entries reach the store through one message, `ENTRY_RECEIVED`, whether they come from the emulator, the collectors (your own play) or the session (other players).

Each file starts with `local addonName, ns = ...` and shares state through `ns`, not globals.

## Comms facts confirmed in the source

These back up the sync plan in `research.md`, from `ChatInfoDocumentation.lua`, `ChatConstantsDocumentation.lua` and `RestrictedActionsConstantsDocumentation.lua`:

- `C_ChatInfo.RegisterAddonMessagePrefix(prefix)` and `C_ChatInfo.SendAddonMessage(prefix, message, chatType, target)` exist on Forever. `chatType` defaults to party.
- `SendAddonMessage` returns an `Enum.SendAddonMessageResult`. Values include `Success`, `AddonMessageThrottle`, `NotInGroup`, `NotInGuild`, `InvalidChannel`, `ChannelThrottle`, `TargetOffline` and `AddOnMessageLockdown`. So `comms.lua` can react to the return value directly.
- `SendAddonMessage` does not accept secret values as arguments.
- `C_ChatInfo.InChatMessagingLockdown()` returns true while chat messaging is restricted.
- `Enum.AddOnRestrictionType.Chat` (value 5) is "the player is in a state where addon chat communications are restricted". The `ADDON_RESTRICTION_STATE_CHANGED` event reports changes.

The source does not say which chat types the server accepts or what the throttle limits are. Those still need testing.

## Verified in-game

Checked on 2026-11-12 on the live Forever client:

- The addon loads with `## Interface: 16001` and `AllowLoadGameType: forever`, so the `forever` alias works.
- The panel, scroll list, tabs, progress bars and footer buttons render.
- The row icons used in `data/feed-types.lua` all exist in the client.

## Still to verify

- That `ExcludeLoadGameType: standard, classic` keeps the addon off retail and Classic clients.
- That the `Category` value shows up sensibly in the addon list.
- That the minimap addon menu entry opens the panel.
