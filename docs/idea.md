# Quest Party

The idea is to re-create the basic functionality of my old addon quest-tweet here ../questtweet/

We want these enhancements:
- Party Panel: shown in the concept-art.png
- Ability to filter; we want persistent feed, meaning, if a user has a quest in progress and is actively gathering kills or mats. we want to show that as apersisted card instead of a chat feed? 
- We would like more persistences and the ability to sync and track what your party is doing
- We want the ability for folks to easily tap into a feed or be part of a feed. 

## Notes

- Sharing may have to scale to larger channels (8 or more players, not just a few friends). Each player's messages go to everyone, and the game allows an addon a short burst and then about one message a second. What is already in place for that: only quests that are underway are shown and told, a newcomer's catch-up is one message per quest, answers to a hello are spread over a few seconds, and rapid counts for one objective collapse to the newest. What to watch as channels grow: the burst when several people join at once, kills still costing a message each, and how many quest cards fit in the panel.

## Future ideas

Dreamed up on 13 November 2026, after channel sharing started working. None of this is planned or built. Each idea says what it would need, so it can be picked up later.

### A state tab that scales to any number of players

For people who want more than the feed: a passive view of where everyone stands, that still reads well with 3 players or 30.

- **Shape:** a table, one row per player, that scrolls and sorts. Columns such as level, zone, what they are working on, XP per hour, last active. A row stays one line however many players there are, which is what a card per player per quest cannot do.
- **What it needs:** one small status message per player that says how they stand now, sent on hello and again when it changes, no more than about once a minute. This is the same "how things stand" idea the quest messages already use.
- **Cost:** one message per player per minute at most, so it grows gently with the size of the channel.
- **Open questions:** which columns; whether sorting by XP per hour turns it into a race, and whether that is wanted; whether a row opens to show that player's quests.

### Tabs as stat containers

The XP, Achv, Prof and Party tabs are only the feed with a filter on it. Each could show stats for everyone on the channel above its feed rows.

- **XP:** level, bar to next level, XP per hour, estimated time to level, levels gained today.
- **Achv:** total points, how many earned, earned this week, the most recent one.
- **Prof:** each profession with a skill bar, points gained this session.
- **Party:** who is sharing, level, zone, what they are working on, last active.
- **What it needs:** the same status message as above. Each player's own client works its numbers out, since only it sees every gain. Rates over time (per hour, this week) need the player's client to keep its own tallies, which can only start from when this is installed.
- **Not checked yet:** which achievement totals and profession skill levels the Forever client lets an addon read. Today Quest Party only catches skill-up messages.

### Sharing professions and goods

Each player shares what they can make and what they have to spare, so friends know who to ask.

- **Examples:** "Uther: Blacksmithing 150, can make Iron Buckle", "Jaina has 40 Linen Cloth spare".
- **Why it is harder:** it is verbose. A recipe list or a bag of goods is far more than fits in a message or two, and sending it to everyone on a channel would flood it.
- **A way that scales:** tell everyone only the short part (which professions, at what skill), and send the long part (recipes, goods) only when someone asks for one player's list. A request and an answer between two players, not a broadcast.
- **Open questions:** whether goods to spare are picked by hand or read from bags; whether this overlaps with what the auction addon already knows about items.

### The look

The concept art is much fancier than the panel today: player portraits, art behind each row, a big level badge, a search box. See `concept-art.png` here and the newer renders in `../auction-hero/docs/concept-art/`. Portraits and row art are a separate job from any of the ideas above, and none of them depend on it.

### A more realistic emulator

The emulator's players travel over the channel with the real protocol, so it proves the wire and the panel. It is not yet a believable party. Gaps seen on 14 November 2026:

- Its players never say hello, so they are not peers: they appear in the party bars only through a debug-mode exception, and never carry XP until their first gain.
- Only one of them gains XP, and none name a kill, so the XP bars and "Kills X for N XP" rows are barely exercised.
- No deaths, no quest state on join, no level-ups mid-quest, and nobody joins or leaves part way through.
- Everything happens on a fixed script at a fixed pace.

What would make it realistic: each pretend player says hello with level and XP, then plays a loop (kill, gain XP, quest progress, the odd death or level-up) at a believable pace, with players joining and leaving. Recorded sessions can feed it too: the saved message log from a real session (see `/qp replay`) is real traffic to play back.

### Creature headshots on kill rows

Stashed on 14 November 2026. The wish: a kill row ("Kills Scarlet Missionary for 46 XP") shows a headshot of the creature as its badge, and hovering it shows the creature's details.

What the Forever client allows, checked in its API documentation:

- **No name lookup.** Nothing turns a creature's name into an ID or a model. The kill message ("Scarlet Missionary dies, you gain 46 experience") carries only the name, and the combat log that used to carry IDs is restricted.
- **Ways to draw one:** `model:SetCreature(creatureID)`, `model:SetDisplayInfo(displayID)`, `model:SetModel(file)`, and `model:SetUnit(unit)` or `SetPortraitTexture(texture, unit)` for a unit you can see right now. `SetPortraitZoom` makes any model a head-and-shoulders shot.
- **Where an ID can come from:** your target, as it dies (`UnitCreatureID("target")`, along with `UnitCreatureType`, `UnitCreatureFamily` and `UnitClassification`). The game hides these "when unit identity is restricted", which looks like dungeons and similar.

Two routes, which stack:

1. **Your target's ID at the moment it dies.** Exact, nothing to ship. Only your own targeted kills, not in dungeons. The ID is a number, so it can be saved with the row and sent to friends.
2. **A shipped name-to-ID table**, built from the game's creature data, as Questie ships its creature database. Works for every named kill, anywhere, for everyone, at the cost of building and refreshing the data when Forever adds content. Names are not quite unique ("Rat"); pick one, the model is nearly always the same.

For the hover: level, creature type, family and elite or rare can be read from the target at the same moment as its ID, and travel with it. With only a name table, the details would come from the table.

Cost to watch: a 3D model per visible kill row is heavier than an icon. Try it on a screenful of rows before settling on it. Fallbacks: the creature type icon when there is a type but no model, then the XP icon.


--- 
Celebration-type sounds in Forever's sound list, to try in game:

┌─────────────────────┬─────────────────────────────────────────────────────────────────────────────────────────┐
│    Paste in chat    │                                       What it is                                        │
├─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ /run                │ UI_MISSION_SUCCESS_CHEERS: a crowd cheering, from garrison mission success. The closest │
│ PlaySound(74702)    │  to "hooray".                                                                           │
├─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ /run                │ UI_WORLDQUEST_COMPLETE: a short victory fanfare.                                        │
│ PlaySound(73277)    │                                                                                         │
├─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ /run                │ UI_AUTO_QUEST_COMPLETE: the quest-complete chime.                                       │
│ PlaySound(23404)    │                                                                                         │
├─────────────────────┼─────────────────────────────────────────────────────────────────────────────────────────┤
│ /run                │ UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP: a level-up flourish.                       │
│ PlaySound(46893)    │                                                                                         │
└─────────────────────┴─────────────────────────────────────────────────────────────────────────────────────────┘

## What the Forever client gives us (researched 2026-11-15)

Source: Blizzard UI source, `origin/forever` ref (API docs in `Blizzard_APIDocumentationGenerated`, plus Blizzard addons as working examples). Nothing here was tested in game yet.

How to read the flags:
- `SecretArguments = "AllowedWhenUntainted"`: an addon can call it with normal values, but not with secret values. Almost every API carries this; it is fine for us.
- `HasRestrictions = true`: the call is gated (secure code, a hardware event like a click, or blocked in some contexts). Only call it from a button click, and test.
- `SecretWhenUnitIdentityRestricted` / `SecretInChatMessagingLockdown`: the result can come back as a secret value we cannot read. Check `C_Secrets.ShouldUnitIdentityBeSecret(unit)` and `C_ChatInfo.InChatMessagingLockdown()` first and degrade quietly.
- `IsProtectedFunction`: only frame methods (Show, SetPoint, etc.) on protected frames. None of the fun APIs below are protected.

Good news for our channel: `CHAT_MSG_ADDON` has no secret or lockdown flag, and `SendAddonMessage` only refuses secret arguments. Our ID-only messages are not affected.

### Best bets

1. **3D creature with a chosen animation** (`ModelScene` actor `SetModelByCreatureDisplayID` + `SetAnimation`, or `PlayerModel:SetCreature` + `FreezeAnimation`). A dying/dead creature on kill rows, a dancing party member in chat. All unrestricted.
2. **Creature heads as flat images** (`SetPortraitTextureFromCreatureDisplayID(texture, displayID)`). Works for a creature known only by display ID, no target needed. Perfect for feed rows and "last killed" on the player card.
3. **Spell visual kits on a model** (`actor:SetSpellVisualKit(id, oneShot)`). Blizzard's shop uses kit 259750 as a "fanfare" celebration. Real game particles, far richer than our icon engine.
4. **Local text to speech of pre-made sayings** (`C_VoiceChat.SpeakText`). Speaks a saying from each client's own data, so it stays moderation safe.
5. **Map waypoint "meet here"** (`C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint`). Send mapID + x,y as numbers; the receiver gets the gold pin and the on-screen arrow.
6. **Big screen banner** (`RaidWarningUtil.AddMessage`) plus `FlashClientIcon()` and `READY_CHECK`/`RAID_WARNING` sounds for party-wide moments.
7. **Atlas stamps** (`Texture:SetAtlas`, `CreateAtlasMarkup`): quest !/?, boss and rare dragons, achievement shields, class and race icons, waypoint pins. No files to ship.
8. **Emote buttons** (`C_ChatInfo.PerformEmote("DANCE")`), restricted, so only from a click. A "dance with me" chat effect that makes your own character dance.

### Sounds

- **PlaySound(soundKitID, channel, forceNoDuplicates, runFinishCallback, priority, volumeOverride)** in the `Sound` system, plus `PlaySoundWithOptions(params)`, `StopSound(handle)`, `C_Sound.IsPlaying(handle)`, event `SOUNDKIT_FINISHED`. Usable, unrestricted. `volumeOverride` lets a celebration be quieter than default.
- **Own .ogg files**: `PlaySoundFile` is not documented on forever and no Blizzard code calls it. Treat shipping our own audio as unconfirmed; test `/run PlaySoundFile("Interface\\AddOns\\QuestParty\\x.ogg")` before planning on it. Stick to SOUNDKIT ids.
- **Fun SOUNDKIT candidates** (from `SoundKitConstants.lua`):
  - Cheers and fanfares: `UI_MISSION_SUCCESS_CHEERS` 74702 (crowd cheer), `UI_WORLDQUEST_COMPLETE` 73277, `UI_GARRISON_MISSION_COMPLETE_MISSION_SUCCESS` 43502, `CATALOG_SHOP_UI_PURCHASE_CELEBRATION` 304902, `CATALOG_SHOP_UI_PURCHASE_BUNDLE_FANFARE_START` 339650, `HOUSING_MARKET_PURCHASE_CELEBRATION` 325723, `TRADING_POST_UI_PURCHASE_CELEBRATION` 218231.
  - Level up and unlocks: `UI_GARRISON_COMMAND_TABLE_FOLLOWER_LEVEL_UP` 46893, `UI_ADVENTURES_ADVENTURER_LEVEL_UP` 167127, `UI_HERO_TALENTS_UNLOCKED` 283863, `UI_72_ARTIFACT_FORGE_FINAL_TRAIT_UNLOCKED` 83682.
  - Quest: `UI_AUTO_QUEST_COMPLETE` 23404, `IG_QUEST_LIST_COMPLETE` 878, `HOUSING_ENDEAVORS_ACTIVITY_COMPLETE` 325764.
  - Coins and loot: `LOOT_WINDOW_COIN_SOUND` 120, `TRADING_POST_UI_COLLECTING_COINS` 218228, `UI_GARRISON_COMMAND_TABLE_CHEST_UNLOCK_GOLD_SUCCESS` 44332, `UI_EPICLOOT_TOAST` 31578, `UI_LEGENDARY_LOOT_TOAST` 63971.
  - Horns, bells, alerts: `RAID_WARNING` 8959, `READY_CHECK` 8960, `ALARM_CLOCK_WARNING_1/2/3` 18871/12867/12889, `MAP_PING` 3175, `UI_BNET_TOAST` 18019.
  - Silly: `FISHING_REEL_IN` 3407, `UI_GARRISON_MISSION_COMPLETE_MISSION_FAIL_STINGER` 43503 (a "wah wah" for wipes).
- Idea: give each effect a default sound and let the sender pick a "sound id" slot from our own curated list, so new sounds are just data.

### Textures and art

- **Atlases**: `C_Texture.GetAtlasInfo(name)` (returns size and tex coords, nil if missing), `Texture:SetAtlas`, inline markup `|A:atlas:h:w|a` and helper `CreateAtlasMarkup(name, w, h)`. Unrestricted. Validate every atlas id in our data with `GetAtlasInfo` at load and drop missing ones.
- **Stamp candidates** (all used by Blizzard code on forever): `QuestNormal`, `QuestTurnin`, `Waypoint-MapPin-Tracked`, `Waypoint-MapPin-Untracked`, `VignetteKill`, `VignetteKillElite`, `vignettekillboss`, `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged`, `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star`, `ui-achievement-shield-1`/`-2`, `UI-Achievement-Shield-NoPoints`, `BonusLoot-Chest`, `LootToast-MoreAwesome`, `Toast-Frame`, `Toast-Flash`, `questlog-questtypeicon-daily`, `questlog-questtypeicon-delves`, `groupfinder-icon-class-<class>`, `classicon-<class>`, `raceicon128-<race>-<sex>`.
- **Raid target icons**: `Interface\TargetingFrame\UI-RaidTargetingIcon_1..8` (see `ICON_LIST` in `ChatFrameConstants.lua`). Usable as chat icons with `|T...|t`.
- **Portraits**: `SetPortraitTexture(texture, unit, disableMasking)` for any unit token (party1, target), round masked by default. Party heads can show live faces.
- Ideas: a "stamp" chat piece that slams a boss dragon frame or achievement shield onto the message; party heads framed with the rare/elite dragon when that player is "on fire".

### Models (3D creatures, players, heads)

- **Widgets**: `PlayerModel` / `DressUpModel` / `CinematicModel` (CharacterModelBase) and `ModelScene` with actors (`ModelScene:CreateActor()`). All methods are unrestricted (`AllowedWhenUntainted` only).
- **Show a creature**:
  - `PlayerModel:SetCreature(creatureID, displayID)` by creature (NPC) id.
  - `PlayerModel:SetDisplayInfo(displayID)` by display id.
  - `actor:SetModelByCreatureDisplayID(displayID)` on a ModelScene actor (returns success).
  - `PlayerModel:GetDisplayInfo()` returns the display id after `SetCreature`, so creature id to display id is probably possible live (needs the creature in the client cache; verify in game).
  - `PlayerModel:SetUnit(unit)` shows a real unit (party member), but is `RequiresDeclassifiedUnitIdentity`, so it can fail where identities are secret.
- **Play an animation**:
  - `PlayerModel:SetAnimation(animID, variation)`, `actor:SetAnimation(animID, variation, speed, offsetSeconds)`.
  - Ids are the standard animation data ids. Blizzard code uses 0 = Stand and 6 = Dead (pet journal shows dead pets with `SetAnimation(6, -1)`); 1 = Death (the falling over) by the usual table; 618 = MountSelfIdle. Emote ids (dance, cheer, wave) come from the same table, so we ship a small `animations` data table and test each.
  - **Freeze on a frame**: `PlayerModel:FreezeAnimation(animID, variation, frame)`. For a ModelScene actor, `actor:SetAnimation(id, 0, 0, offset)` (speed 0) freezes, as Blizzard's Azerite UI does, and `ModelScene:SetPaused(true)` pauses the scene. So "play Death once, then hold Dead (6)" works.
  - `actor:PlayAnimationKit(kitID, isLooping)` / `StopAnimationKit()` for scripted animation kits.
- **Spell visuals on a model**: `actor:SetSpellVisualKit(kitID, oneShot)` and `CinematicModel:SetSpellVisualKit`. Blizzard's shop celebration uses creature 27823 with kit 259750 ("fanfare", `Blizzard_CatalogShop_Constants.lua`). `TryOn(itemLink or appearanceID)` dresses a DressUpModel.
- **Heads as images**:
  - `SetPortraitTexture(texture, unit)` for target or mouseover at kill time.
  - `SetPortraitTextureFromCreatureDisplayID(texture, displayID)`: a round head for any display id, no target needed (Encounter Journal uses it for boss heads). This is the main tool for heads.
  - 3D head: `PlayerModel:SetPortraitZoom(0.6)` (quest NPC frame and guild news use this) or `SetCamDistanceScale`, on a small model frame.
- **Getting ids from a kill**:
  - `PARTY_KILL` (attackerGUID, targetGUID) and `UNIT_DIED` (unitGUID) events. Both are `SecretWhenUnitIdentityRestricted`.
  - `C_CreatureInfo.GetCreatureID(guid)` turns a GUID into a creature id. `UnitCreatureID(unit)`, `UnitGUID(unit)`, `UnitCreatureType(unit)` and `UnitCreatureFamily(unit)` work on target/mouseover/nameplates. All return secrets when identity is restricted, and a secret GUID cannot be passed to GetCreatureID (untainted only).
  - `COMBAT_LOG_EVENT_UNFILTERED` is `HasRestrictions`, and `C_CombatLog.IsCombatLogRestricted()` exists. Do not build on the combat log.
  - `C_CreatureInfo.GetCreatureTypeIDs()/GetCreatureTypeInfo(id)` and `GetCreatureFamilyIDs()/GetCreatureFamilyInfo(id)` list types (Beast, Undead, ...) and families with names and icons, unrestricted.
- **What to ship versus read live**: read the creature id from the kill (target GUID at `PARTY_KILL`, or `UnitCreatureID("target")`), and send only that number. Each receiver resolves it: `SetCreature(id)` then `GetDisplayInfo()` for the display id, then the portrait or model. Ship a small fallback table of display ids per creature type (one beast, one undead, one humanoid, and so on) for when the creature is not cached or the id was secret. Also ship the animation id table and a short list of spell visual kits we tested.
- Ideas:
  - Kill rows in the feed: a round creature head, and on hover a tiny 3D model playing Death then holding Dead.
  - A "victory dance" chat effect: the sender's own character (via `SetUnit` on their party token, or a race model fallback) dancing for 3 seconds.
  - "Last killed" on the player card as a head stamp.
  - A rare kill celebration: the rare's model with the fanfare spell visual.
  - Note: models are heavy. Pool one or two model frames and reuse them, never one per chat line.

### Animations

- **AnimationGroups** with Alpha, Scale, Translation, Rotation, Path and FlipBook. `SetFlipBookRows/Columns/Frames/FrameWidth/FrameHeight` on FlipBook animations (sprite sheets). Unrestricted.
- **C_ScriptedAnimations.GetAllScriptedAnimationEffects()**: Blizzard's projectile effect list (trajectories Straight, CurveLeft/Right, behaviors like TargetShake, `UIParentShake`). The controller is Blizzard UI code, so treat it as "maybe"; reading the list is fine.
- Ideas: flipbook sparkles and explosions from Blizzard atlases as new effect particles; a "shake" effect on a chat bubble; icons that fly along a curve from the sender's party head to yours.

### Emotes

- **C_ChatInfo.PerformEmote(token, target)** (the old `DoEmote` is now only a deprecated wrapper and loads only if `loadDeprecationFallbacks` is on). `HasRestrictions`, so call it only from a click. `EmoteList` in `ChatEmoteConstants.lua` lists emotes with animations (WAVE, BOW, DANCE, APPLAUD, CHEER...).
- **CHAT_MSG_TEXT_EMOTE** is `SecretInChatMessagingLockdown`, so its text can be secret.
- Ideas: a "/dance with me" chat piece with a Dance button; clicking it makes the receiver's own character dance (their own click, so it is allowed). Animate the sender's party head when they emote.

### Map

- **C_Map.GetPlayerMapPosition(mapID, "player")**: only works for the player and party members. `C_Map.GetBestMapForUnit("player")` for the map id.
- **C_Map.SetUserWaypoint(UiMapPoint)**, `CanSetUserWaypointOnMap(mapID)`, `GetUserWaypointHyperlink()`, plus `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`. Unrestricted. Note this replaces the receiver's own waypoint, so only set it on their click.
- **Pings**: `C_Ping.SendMacroPing` and all of `C_PingSecure` are `HasRestrictions`. Use our own pin instead.
- **Vignettes**: `C_VignetteInfo.GetVignettes()`, `GetVignetteInfo(guid)`, `GetVignettePosition(guid, mapID)` show nearby rares and treasures.
- Ideas: "meet here" chat piece (mapID + x + y as numbers) with a "Set waypoint" button; "rare spotted" shared from the vignette list with a map stamp.

### Screen and UI feedback

- **RaidWarningUtil.AddMessage(text, colorInfo, displayTime)**: the big center screen text (`RaidNotice_AddMessage` is now a deprecated wrapper). Text comes from our own data, so it is safe.
- **UIErrorsFrame:AddMessage(text, r, g, b)**: small top-of-screen line.
- **AlertFrame:AddQueuedAlertFrameSubSystem(template, setUp, maxAlerts, maxQueue)** / `AddSimpleAlertFrameSubSystem`: real toasts (the achievement toast slide). We can register our own toast template.
- **FlashClientIcon(briefly)**: flashes the taskbar icon (Blizzard does it on ready check). Unrestricted.
- **VisualAlertType** enum (MarchingAnts, Flash in colors) exists, but no addon-facing call was found.
- Ideas: a party toast "Mira finished The Missing Diplomat"; flash the taskbar when someone sends you a "help" piece while you are alt-tabbed; a raid-warning style banner for party milestones.

### Social and party

- **RandomRoll(min, max)**: unrestricted. A "roll off" chat piece; read results from `CHAT_MSG_SYSTEM`.
- **C_PartyInfo.DoReadyCheck()**: `HasRestrictions`, so only from a leader's click. `READY_CHECK` events and the sound are fine.
- **Raid markers**: `SetRaidTarget(unit, index)`, `PlaceRaidMarker`, `ClearRaidMarker`, `RemoveRaidTargets` are all `HasRestrictions`. `GetRaidTargetIndex` returns secrets. Use the icons as art only.
- **Events worth a celebration**: `QUEST_TURNED_IN`, `PLAYER_LEVEL_UP`, `ACHIEVEMENT_EARNED`, `CRITERIA_EARNED`, `QUEST_LOG_CRITERIA_UPDATE`, `PARTY_KILL`.
- **SendChatMessage** is `HasRestrictions` and `RestrictedForMacroChatMessages`, which matches what we saw (we do not use it).
- Ideas: auto-celebrate level ups for the whole channel (a level-up sound plus fireworks over that player's party head); a ready check style "everyone at the quest giver?" check made only from our own messages.

### Other surprises

- **Text to speech**: `C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)`, `GetTtsVoices()`, `StopSpeakingText()`. Not flagged restricted, and allowed when tainted. Our sayings are local data, so speaking them is moderation safe. Must be opt-in per player, off by default.
- **Screenshot()**: unrestricted. A "group photo" piece that counts down 3, 2, 1 on everyone's screen and each client takes its own screenshot.
- **Toys**: `UseToy` exists but it is used from Blizzard secure buttons; assume it needs a click. `C_ToyBoxInfo` only manages filters and fanfare.
- **C_DeathAlert.HardcoreDeaths**: hardcore only, not useful here.
- **Camera**: only `GetCameraFOVDefaults` and `GetUICameraInfo` are documented; no fun camera control for addons.
