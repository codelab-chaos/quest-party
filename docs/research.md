# Quest Party Research

Date: 2026-11-12

## Direction

Quest Party takes its inspiration from Quest Tweet (`../questtweet/`). It keeps the same idea (share your adventuring progress with friends) and enhances it with:

- A user interface (the Party Panel in `concept-art.png`).
- Easier usability for folks to join a feed.

See `idea.md` for the enhancement list.

## Quest Tweet (the inspiration)

- **What it does:** a small Interface 70000 (Legion) addon, about 550 lines, that listens for game events and reposts them as chat lines to say, party, raid, guild or a custom channel.
- **What it covers:** quest accepted, quest objective progress, quest XP plus percent of level, level up, zone discovery, achievements, profession skill-ups, and optional kill XP.
- **How it detects things:** mostly by pattern-matching English strings from `UI_INFO_MESSAGE`, `CHAT_MSG_SYSTEM` and `CHAT_MSG_COMBAT_XP_GAIN`, so it is locale-bound and fragile.
- **Feed model:** the custom chat channel was the preferred way to share (`/qtweet channelid ourchannel`). Joining a feed meant everyone manually joining the same channel and setting the same id.
- **State:** it has none. It only emits chat, with no receiving side. That is the gap the Party Panel, persistent cards and sync would fill.
- **Open feature requests from its README:** world quests, raid icons, toys and mounts, rare kills, and a "special frame for feeds".

### What carries over

- The event categories and the per-category toggles.
- The targets idea (party, raid, guild, channel).
- The data-driven options table (`QuestTweetOptionLabels`) and the separate localized text file.
- The built-in test command that replays sample events.

### What does not carry over

- Global-namespace functions and variables.
- The `seterrorhandler` override.
- The XML options panel on `InterfaceOptions_AddCategory`.
- `GetAddOnMetadata`, `PARTY_MEMBERS_CHANGED`, and the hardcoded level 80 cap.
- The "local" (say) target, see chat output below.

## Concept art

`concept-art.png` shows a "Quest Party" panel with:

- Filter tabs: All, XP, quests, achievements, professions, party.
- Timestamped cards (quest completed with XP and gold, level reached, zone discovered, skill-up, quest accepted, objective completed).
- `[Quest Party]` lines in the chat frame naming the party member.

## WoW Forever addon development

- **API baseline:** Forever is client 1.60.1, built on the retail (Midnight 12.1.5) API, not Classic Era. Blizzard's 2026-09-15 post says it shares "the vast majority of APIs available in 12.1.5".
- **TOC:** interface number is `16001`. The game type is `forever` (internally "Camelot", `WOW_PROJECT_CAMELOT` = 18), and `MyAddon_Forever.toc` suffixes work.
- **Loading on the right client:** use `## AllowLoadGameType: forever`, and exclude `standard, classic`, because older clients don't recognize the type yet.
- **Restrictions:** Midnight's addon restrictions apply in full, including secret values. They target combat data (spell casts, health, auras, creature IDs). Quest helpers are reported as unaffected.
- **Chat output:** `SAY`, `YELL` and now `EMOTE` need a hardware event outside instances.
- **Distribution:** CurseForge has a "Forever" flavor tagged 1.60.1. Questie, Leatrix, Bagnon, Auctionator and TomTom already ship Forever builds. WeakAuras and TradeSkillMaster do not.

### Addon comms (the part that matters for sync)

- Inside instances, addons cannot send to other players (addon messages or chat), and incoming chat arrives as secret values.
- Outside instances, `C_ChatInfo.SendAddonMessage` over PARTY, RAID, GUILD and WHISPER is reported working. Sends to General and Trade are refused.
- Trial accounts can't send addon messages.
- Defaults are a 16-character prefix, 255-character messages and a 10-message burst allowance per prefix. The server can change these.
- Detect lockdown with `C_ChatInfo.InChatMessagingLockdown()` and `ADDON_RESTRICTION_STATE_CHANGED`, and queue sends until it clears.

## What this means for Quest Party

- **Sync transport:** use hidden addon messages on PARTY/RAID/GUILD instead of chat spam, with the visible chat line as an optional extra. This allows structured data (quest ID, objective counts) and therefore the persistent cards.
- **Event detection:** read `C_QuestLog` and events like `QUEST_LOG_UPDATE`, `QUEST_TURNED_IN` and `PLAYER_LEVEL_UP` instead of string matching.
- **Instances:** sync has to pause and catch up on exit.
- **Joining a feed:** party, raid and guild feeds can be automatic (anyone in the group with the addon is in). A feed between friends who are not grouped needs a whisper or custom-channel design, and that is the least certain part.

## Not verified

- Launch status: sources conflict between "released November 4, 2026" and "still in beta".
- The comms details for Forever come from community sources (a GitHub issue and an unofficial guide), not Blizzard notes. Test them in-game before designing around them.
- Whether hidden custom channels work for addon messages is disputed between sources.
- The fine detail of quest and skill API changes in 1.60.1. The wiki diff lists some `C_QuestLog` and `C_SkillInfo` entries without a clear added/removed split.

## Local reference: Blizzard UI source

- `/home/chadneff/git/hub/wow-ui-source` holds Blizzard's UI code. Forever is on the `origin/forever` branch (build `1.60.1.70888`, 2026-11-10). The checkout itself sits on `live` (retail).
- Read it with `git show origin/forever:<path>` and `git grep <pattern> origin/forever`, so the checkout stays untouched.
- It confirms the addon message APIs, the lockdown check and the `Chat` restriction type listed above. It does not confirm which chat types the server accepts.
- See `toc.md` for the TOC write-up built from it.

## Sources

- [Patch 1.60.1 API changes (Warcraft Wiki)](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes)
- [Patch 1.60.1 API change notes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes)
- [C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API:C_ChatInfo.SendAddonMessage)
- [Patch 12.0.0 API change notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes)
- [Secret Values (Warcraft Wiki)](https://warcraft.wiki.gg/wiki/Secret_Values)
- [TOC format (Warcraft Wiki)](https://warcraft.wiki.gg/wiki/TOC_format)
- [wow-ui-source diff, 12.1.5 to forever](https://github.com/Gethe/wow-ui-source/compare/12.1.5..forever)
- [WoW Forever Addons: As Restricted As Midnight (Kami Labs)](https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/)
- [WoW Forever Addon Restrictions (unofficial)](https://wowforevertierlist.com/addons/restrictions)
- [Hidden custom channel under Midnight (GitHub issue)](https://github.com/Shtian/bff-wow/issues/2)
- [ForeverPlus on CurseForge](https://www.curseforge.com/wow/addons/foreverplus)
- [WoWAddonAPIAgents instructions](https://github.com/JBurlison/WoWAddonAPIAgents/blob/main/.github/instructions/wow-api-important.instructions.md)
- [Mobalytics WoW Forever addons guide](https://mobalytics.gg/wow-forever/profile/scorpius/guides/wow-forever-addons-guide)
