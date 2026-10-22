# Encounter of the Week

Encounter of the Week (EotW) is a Codex game mode: each week a curated
encounter ships in the `mcdm-encounteroftheweek` module, and a group of 4-6
heroes plays it with **no Director** -- the Monster AI runs the monsters and
the game runs everything a Director would (setup, initiative, scripted story
beats, victory and defeat).

The player's path:

1. **Titlescreen.** With the dev setting `dev:encounteroftheweek` on
   (`/toggle dev:encounteroftheweek` in chat), a link in the top-right corner
   opens the EotW screen: an overview, a lobby chat, who is present, and the
   list of joinable games.
2. **Game lobby.** At the Town Gate a player forms a party for **the**
   Encounter of the Week (or one of the past ones) or joins a public one;
   community-made encounters play in the **Proving Pits** instead, as
   practice. Hero slots are filled from the player's town roster: up to 4
   heroes per player, 4-6 per game. The creator is the host and may kick
   players. (See "The Encounter of the Week and the Proving Pits".)
3. **Begin.** The host presses Begin; the host enters and sets the game up,
   then everyone else enters.
4. **The script.** The week's journal document is a script of beats. Story
   beats (narratives and montages) play on a full-screen stage; then, if the
   week unlocked it, a Tactical Preparation screen; then the encounter: traps
   placed, monsters spawned scaled to the party, the stage dissolves, Draw
   Steel.
5. **Combat** runs under strict rules with the Monster AI playing the
   monsters. The game detects victory or defeat, shows the victory screen,
   and each player returns to the titlescreen when they press Proceed.

**How to use this document.** "Where things stand" is the live status and
the place to start. The design sections after it describe how the mode works
*now*; they are not a changelog. The Development Plan at the end is a compact
checklist. The dated history of how each piece came to be (root-cause
write-ups, superseded designs, old module versions) was removed on
2026-10-01 and lives in git: see this file as committed in `draw-steel-codex`
`51f5be67` (2026-09-27) and earlier.

---

# Where things stand (2026-10-06)

**Everything in the flow above is built**, from the lobby server to the
victory screen, and most of it has been played in real EotW games at some
point (live playtests on 2026-09-06, 09-16, 09-19/20, 09-24 and 09-30). What
has NOT happened is a clean multi-client playthrough of the current scripted
week from Begin to the titlescreen. Most of the script features were verified
on one client in the authoring game (the Director driving the party-owned
pregens through dev drivers), so the open risk is in the multi-client paths:
a second player's turns, rolls and votes, late joiners, and the beat
handovers on a non-host screen.

**Encounter series (2026-10-17):** one map, several encounters unlocked in
order, each bounded to its encounter's region. Built across the parser, game,
town, both publishers and the City; nothing run, not deployed, uncommitted.
See "Encounter series".

**Carrying the story forward (designed 2026-10-18, signed off 2026-10-19):**
story tracks and each part's montage outcome and winning round carried
between series parts, plus part maps ("<series> (Part N)"). The Lua side
(parser, game, town, ModShare, validator, Test Encounter's Story so far) is
committed on the EotW-Campaign-Tracking branch (PR 410); the handoff to the
City is NOT built (waits on David's series City source), so real games start
every later part with an empty story. See "Encounter series" -> "Carrying
the story forward".

**Encounter Rules (2026-10-20):** an optional `Encounter Rules` journal
document in the map's folder, shown read-only from a book button above
Journal once combat begins. Verified live 2026-10-20 in an authoring test
(Aixco, Part 1, Test from Combat) with a temporary rules document; type
check clean; UNCOMMITTED. NOT seen: a real multi-client EotW game, a
published module carrying the document, a series part's own rules. See "The
EotW interface".

**Forced-maximized map (2026-10-17):** the encounter's map is held maximized
with no restore/minimize/close, in games and tests. Written, type-checks,
NOT run, uncommitted. See "The EotW interface".

## Committed, deployed, published

- **Codex (Lua).** EotW work is committed on `draw-steel-codex` `main` up to
  `0dc04e18` (2026-09-29). The last cloud deploy of the EotW mod that is on
  record is 0.0.841 (2026-09-24, deploy id
  `7e97ecbe-f241-448f-bdc4-78ad65c6793e`, delve tuning). The two commits since
  -- screen-space stage cursors (`51f5be67`) and the controlling player's name
  on hero cards (`0dc04e18`) -- are not recorded as deployed. **Check before a
  playtest with other players.**
- **Engine (C#).** All EotW engine work is committed. The newest piece is the
  screen-space cursor mode (`928b426e1`, 2026-09-25). The version was bumped
  to 0.0.843 on 2026-09-28, after every EotW engine commit, so builds from
  0.0.843 on should carry all of it. That is inferred from commit dates and
  has not been checked against a build.
- **Lobby server.** Live players are on the **staging** worker
  (`game-server-staging`) until the cutover below. The code written
  2026-10-21 (uncommitted) moves everyone to **release**: see "Moving to the
  release server".
- **Community modules.** Since 2026-10-03, an "Encounter of the Week"
  module type published from the in-app dialog adds encounters to a pool
  beside the official module's (built, untested; see "Community encounter
  modules and the encounter pool").
- **Module.** The latest known `mcdm-encounteroftheweek` is version 29
  (dataid `d240b941`, 2026-10-03: the Goblin Ambush story sections and the
  Town Gate text on the module record), published with `--force` over the
  standing warnings below.

## Uncommitted work (as of 2026-10-02)

| Change | Files | State |
|---|---|---|
| **Complication trinkets in the builder** (2026-10-21; see "Treasure-granting complications"): Secret Twin / Amnesia's trinket pick now actually gives the trinket (worn while a slot is free), swaps it on a re-pick, and takes it back when the pick or complication changes; also on joining the roster, including titlescreen recruits | `Codex Titlescreen/EotwBuild.lua` (`SyncTreasureGrants`, `Modify`, `Unchoose`, `RowOptions`), `Codex Titlescreen/EotwRoster.lua` (`JoinRoster`, `RecruitTitlescreenHero`), `Draw Steel Modifiers/ModifierGrantTreasure.lua` (`prompt` field) | luac + typing clean; in the git folder; app restarted. VERIFIED over MCP on in-memory heroes: pick / swap / same pick / unpick / switch to Amnesia / Fill / No Complication, and a trinket worn in `trinket1` that the swap replaced. NOT clicked through on the builder screen; the roster join and titlescreen recruit paths NOT run. The later Gold-only trinket filter (`RegisterOptionFilter`, `EnsureGoldTreasureFilter`) is luac + typing clean but NOT run (needs an app RESTART): expect 5 options on Secret Twin (Color Cloak Blue/Yellow/Red, Hellcharger Helm, Gecko Gloves; not Precious Collar). The Secret Twin assassin (respite d10 -> banner -> montage threat -> outcome clears the mark; `EotwDowntime.lua`, `FullscreenDisplay.lua`, `EncounterMontage.lua`, `EncounterScript.lua`, `EncounterOfTheWeek.lua`, `EotwRoster.lua`) is luac + typing clean and the snippet parse was checked with the bundled interpreter (951 parser checks still pass), but NOTHING of it has run in the app. To test: force `math.random` or set `eotwAssassinPending` on a Secret Twin hero; take a respite (banner and portrait); enter a game with a montage (threat card mid-arrival, 4d6 dice for the hero's player, damage lands); come home (mark cleared). UNCOMMITTED |
| **Auto-equip treasure** (2026-10-19, user direction; see "Treasure goes home"): an equippable treasure a hero gains in a game (montage/narrative reward, delve or map chest, hand-over) is worn at once when there is a free slot, by the EotW hero sheet's rules; treasure arriving home in town is equipped the same way; the haul hand-over can give a worn find | `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`AutoEquipTreasure`, host, from `MapScriptHostThink`; state doc `autoEquip`, cleared by `ClearTestArrival`), `EncounterOfTheWeek/EncounterMontage.lua` (`GrantItem` with a negative quantity goes through `GiveItem`, which unequips; `HeldQuantity` for the hand-over check), `Codex Titlescreen/EotwHeroSheetData.lua` (`EotwHeroSheet.EquipInPlace`), `Codex Titlescreen/EotwRoster.lua` (`ApplyOutcome` equips each treasure) | luac + typing clean; deployed; needs an app RESTART; NOT run. To test: win a trinket in a montage (it shows in a trinket slot on the hero sheet), loot a map chest (equipped within ~0.5s), take one off (it stays off), a hero at the leveled cap of 3 (stays in the bag), hand an equipped find to another hero (it moves and is worn there), and the town roster hero wearing it after the outcome lands |
| **The town's welcome dialog** (2026-10-19, user direction; see "The welcome dialog"): the first time an account reaches the town map it gets "Welcome to Encounter of the Week" (what EotW is, beta + Feedback, the DMHub Discord, be kind) | `Codex Titlescreen/EncounterOfTheWeek.lua` (preference `eotw:welcomed`, `ShowWelcomeDialog` / `EncounterOfTheWeek.ShowWelcomeDialog`, `MaybeShowWelcome` in the town's watcher think) | luac + typing clean. VERIFIED 2026-10-19 single client after a restart: it opened by itself on first entering the town, was marked seen (`eotw:welcomed`), and Let's Go! closed it; the "DMHub Discord" link was clicked with no error (the browser side not seen). Join the Discord not clicked. Reshow with `dmhub.SetSettingValue("eotw:welcomed", "")`. UNCOMMITTED |
| **Per-hero Intelligence** (2026-10-09, user direction; see "Optional features and Tactical Preparation"): each hero keeps the Intelligence they earned, shown as a brain chip on their card; each player spends their own heroes' Intelligence on Tactical Preparation, with "yours to spend" and the party total both on screen | `EncounterMontage.lua` (`GetHeroIntelligence`, `SharedIntelligence`, `SpendableIntelligence`, `CreditIntelligence`, `SplitIntelligence`, `SpendIntelligence`; the `intelligence` effect branch; reset clears `intelligenceByHero`), `EncounterNarrative.lua` (agreed choices pass `splitIntelligence`), `EncounterPrep.lua` (`VoterHeroids`, `LocalSpendable`, per-player `CanSpend`/`CanProceed`, spend + ready handling, `/eotwprep intelligence <n>` splits evenly), `EncounterMontageStage.lua` (prep header), `EncounterOfTheWeekHud.lua` (pool tooltip text), core `Codex Titlescreen/EotwHeroCard.lua` (`CreateIntelligenceBadge`) | luac + typing clean. The helpers were checked live against a scratch doc (credit, even split with remainder to the least, per-player spend from the richest hero, losses clamp at 0, legacy shared part). The card chip was seen live in the authoring game (shows "3", hidden at 0). NOT seen live: the prep header ("N yours to spend / M in the party") and the spend round trip with two players -- try it in an authoring test or a real game. Needs an app RESTART. UNCOMMITTED |
| **Knacks** (2026-10-05, user direction; see "Knacks" below and `KNACKS_REFERENCE.md` in this folder): secret options (an `Allow` line now HIDES the option from heroes who do not meet it), options with no roll, `#### If <requirement>` knack versions (no roll or a better table), a capability vocabulary of author intents (`you can teleport` = a teleport speed OR an ability that teleports), many new requirement kinds (perk, complication, career, culture, kit, deity, domain, item, immunity, weakness, size, Wealth/Renown/Level/characteristics), scene conditions on the same vocabulary, real perk rules (Brawny, Lucky Dog, Put Your Back Into It!, Team Leader, Teamwork, Ritualist, Born Tracker, Polymath, Handy, Power Player, Mighty Leaps), skill-scoped feature edges now apply in montage rolls, and a validator Knack coverage report. Both montages re-authored to the standard (Dwarvish Bandits docs in game `1e3c159e`; Goblin Ambush docs in `e96656f3` / `C:\dev\eotw`) | core `DMHub Game Rules/TestRiders.lua`; `EncounterScript.lua`, `EncounterMontage.lua`, `EncounterMontageStage.lua`, `EncounterScriptValidator.lua`; `tests/encounter_script_test.lua` (877 checks); docs `KNACKS_REFERENCE.md`, `.claude/skills/eotw/` | luac + parser tests + typing clean. VERIFIED 2026-10-05 single-client in `1e3c159e` (Heroes() pointed at six pregens for the session): Team Leader spends a token and lends Lift/Jump/Climb/Endurance; a Polder Shadow sees "Find another crossing (no roll)" via Black Ash Teleport and resolves it (tier 0, log "Knack: ..."); Wealth-3 secret hidden; a Dwarf sees the Dwarf-only secret; a faked failed Might roll offers Brawny + Put Your Back Into It!, Brawny costs 1d6+1 and lifts tier 1 to 2; the Ritualist blessing and a knack edge land as roll-dialog chips (Skilled in Sneak + edge + double edge). NOT seen: multi-client, Teamwork, Lucky Dog, Power Player, Born Tracker, a rolled knack version, delve knacks. Modules NOT republished. UNCOMMITTED |
| **Outcome icons** on entry cards and option buttons (see "Outcome icons") | `EncounterScript.lua`, `EncounterMontageStage.lua`, `tests/encounter_script_test.lua` (461 checks) | Verified live in the authoring game, except the red "?" on a threat (only Goblin Scouts, a Round 2 threat, has one) |
| **Party size 4-6** (was 3-7) | `Codex Titlescreen/EncounterOfTheWeek.lua` (`MIN_HEROES`/`MAX_HEROES`), `EncounterOfTheWeek.lua` (comment only); server `cloudflare-game-server/src/lobby-core.ts` + tests (280/280) | Worker DEPLOYED to staging 2026-10-02 (it rode along with the City deploy; `lobby-smoke.ts` passes there); Lua NOT deployed, untested live |
| **No cancelling a montage roll once thrown**: a failed test could be retried via the roll card's X / ESC | `EncounterMontage.lua` (`noCancelOnceThrown = true`); core `DMHub Utils/Utils.lua` (`RollDialogCancelOffered`), `Draw Steel UI/DSRollDialog.lua`, `Timeline/EmbeddedRollDialog.lua` | Untested |
| **City DO** for the Blackbottom town (committed; listed for its deploy state) (2026-10-02; see "The City DO") | `cloudflare-game-server`: new `src/city.ts`, `src/city-core.ts`, `test/city-core.test.ts`, `test/city-smoke.ts`; hooks in `src/lobby.ts`; `"roster"` hero kind in `src/lobby-core.ts`; routes in `src/index.ts`; binding + migration `v4` in `wrangler.toml` and `wrangler.dmhub.toml`; `CLAUDE.md` | **DEPLOYED to staging 2026-10-02** (version `a867550f`); `city-smoke.ts` all 34 checks passed against staging; committed dmhub `4a0a9e3af` |
| **Town front end** (2026-10-02; see "The town client") | Engine: `Assets/Scripts/LobbyConnection.cs`, `LobbiesLua.cs` (route option, empty-args fix), `GameController.cs` + `LuaInterface.cs` (`ExportCharacter`/`ImportCharacter`); stubs `Definitions/dmhub.lua`, `Definitions/lobbies.lua`. Codex: NEW `Codex Titlescreen/EotwHeroCard.lua` and `EotwRoster.lua` (registered in the Codex Titlescreen codemod, Firebase confirmed), `EncounterOfTheWeek.lua` (the town screen), `CodexTitlescreen.lua` (`TitlescreenHeroes`, `LobbyHeroes` skip), `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` (card aliases), `EncounterOfTheWeek/EncounterOfTheWeek.lua` (city id). Server: `city.ts`/`city-core.ts` `asJson` + tests | C# BUILT (dev build); server DEPLOYED to staging (`22189dfe`); Lua typing clean; single-client verified live (see that section); NOT deployed to the cloud codemods (new core files need an app restart wherever they land) |
| **Encounter stories + Victories** (2026-10-02; see "Encounter stories and the Victory award") | Server: `city-core.ts` / `city.ts` (`city_completions`, `record-outcome {completed}`, `completed` on `list-heroes` and party heroes), `lobby-core.ts` (`completed` survives sanitizing), `test/city-core.test.ts` (307/307). Core: `Draw Steel UI/DSVictoryScreen.lua` (`AwardVictories` + exemptions). Codex: `EncounterScript.lua` (story sections) + `tests/encounter_script_test.lua` (474), `EncounterOfTheWeek.lua` (game side), `EncounterMontageStage.lua` (`ShowStoryScreen`), `Codex Titlescreen/EncounterOfTheWeek.lua`, `Codex Titlescreen/EotwRoster.lua`. Publisher: `tools/eotw_publish/documents.py` (`story_section`), `publish_eotw.py`. Content: `C:\dev\eotw\objectTables\documents\encounter.yaml` (Goblin Ambush: Town Gate, Conclusion, Defeat) | Unit tests + luac + typing pass; **module v29 PUBLISHED 2026-10-03** (dataid `d240b941`, carries the Town Gate text); Form a Party backstory verified live; server NOT deployed (the user deploys: `npm run deploy` in `cloudflare-game-server`); the rest unverified |
| **EotW hero builder** (2026-10-03; see "The hero builder and hero sheet") | NEW `Codex Titlescreen/EotwBuild.lua` (step engine) and `EotwBuilder.lua` (screen), both registered in the Codex Titlescreen codemod (Firebase confirmed); `EotwRoster.lua` (drafts, Create/Continue/Discard, Rebuild); `CodexTitlescreen.lua` (`LobbyHeroes` skips `eotwDraft`) | Typing clean; engine MCP-verified; screen user-tested once, round-1 fixes not re-tested; needs an app restart to load |
| **Rebuild any time in town** (2026-10-20, user direction; see decision 4 under "The hero builder and hero sheet"): the Guild pencil and the hero sheet's Edit in Builder open the builder for a roster hero whenever they are home, not only before their first encounter; Ancestry and Class are locked on a rebuild | `Codex Titlescreen/EotwRoster.lua` (`CanRebuildHero`: on the roster and not away; `EditHero` passes `lockedSteps`), `EotwHeroSheet.lua` (`CanEditInBuilder`, tooltip), `EotwBuilder.lua` (`lockedSteps` arg, `BaseLocked`, `BaseCards`, the base header) | luac + typing clean. LIVE-TESTED 2026-10-20 in town: all four roster heroes (1 encounter completed each) report rebuildable; the Guild pencil (new tooltip) and the sheet's Edit in Builder open "Rebuild Your Hero"; Ancestry (Orikk: Dwarf) and Class (Fury; Bracegirdle via the sheet) show only the chosen card with the can't-be-changed note, traits / Primordial Aspect / characteristics still editable; no builder errors. Create (not locked) not re-checked: the roster was full. UNCOMMITTED |
| **New Player Window in the Codex menu** (2026-10-03; see "Debug New Player Window"): the game view's "Player Window" button and its `--eotw-game` auto-join removed | `Codex Titlescreen/EncounterOfTheWeek.lua` (`autoOpen`/`WantsAutoOpen`, `IsScreenOpen`, `CodexMenuItems`), `CodexTitleBar.lua` (main-menu Codex menu appends them), `CodexTitlescreen.lua` (comment) | luac + typing clean; no engine change (uses the existing `connect`/`args` options); needs an app restart; UNTESTED |
| **Active heroes join by default + other players' portraits in the party view** (2026-10-03; see "The town client", Gate) | Engine: `GameController.ReadDetachedCharacter`, `LuaInterface.cs` `dmhub.CreateDetachedCharacter`; stub `Definitions/dmhub.lua`. Codex: `Codex Titlescreen/EncounterOfTheWeek.lua` (`ClaimActiveHeroes`, `RosterHeroSpec`, `ResolveHeroToken` + `m_remoteHeroTokens`, `artRegistered`; `RefreshGames` is now forward-declared) | C# NEEDS BUILD; luac + typing clean; needs an app restart; UNTESTED |
| **Location scenes + creator credits** (2026-10-03; see "The town client" -> "Locations take over the screen" and "Creator credits") | NEW `DMHub Core UI/CreatorCredit.lua` (registered, Firebase confirmed); `Codex Titlescreen/EncounterOfTheWeek.lua` (scenes, Gate card, Escape fix); `Codex Titlescreen/EotwRoster.lua` (`GuildPanel` replaces `ShowGuild`; ModalFrame escape priority). Art + logo uploaded as core image assets | luac + typing clean; verified live on one client: both scenes, the logo's tooltip, Back, Escape, the recruit picker and Form a Party dialog over the scenes. Party view at 1240 wide and the video path not seen. NOT deployed to the cloud codemods; the new core file needs an app restart wherever it lands |
| **Community encounter modules + the encounter pool** (2026-10-03; see "Community encounter modules and the encounter pool") | `DMHub Core Panels/ModShare.lua` (`eotw` module type, `CheckEncounterModule`, `available`/`publishingProperties`/`include` hooks); `Codex Titlescreen/EncounterOfTheWeek.lua` (the pool, encounter keys, grouped Form a Party dropdown + credit line, admin "Encounter Pool..." dialog); `Codex Titlescreen/EotwRoster.lua` (epitaph name); `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`ParseEncounterKey`, `EnsureEncounterModule`, `encounterMapId`/`encounterModule` stamps); `EncounterOfTheWeek/EncounterMontage.lua` (`ScriptForMap`) | luac + typing clean; no engine or server change; needs an app restart; UNTESTED |
| **No targeting without line of effect** (2026-10-03; see "Strict rules and forced settings"): a hero could pick a strike target the arrow marked "No Line of Effect" | `DrawSteelActionBar/DrawSteelActionBar.lua` (`DrawSteelActionBar.LineOfEffectFailReason`; the check in `CalculateSpellTargetFocusing`; the arrow labels use the same helper). The file also holds older unrelated uncommitted changes | luac clean; the live map's line-of-effect results probed over MCP; needs an app restart; the click block itself is UNTESTED |
| **Arrange your heroes** (2026-10-04; see "Start-zone confinement": "Arranging the heroes") | Core `Draw Steel UI/DSInitiativeRoll.lua` (`holdBeforeQueue`, `CreateCombatQueue`); `EncounterOfTheWeek.lua` (`HoldForArrangement`, `ArrangeHostTick`, the panel); `EncounterMontage.lua` (reset) | luac + typing clean; VERIFIED 2026-10-04 in the authoring game with /eotwencounter (single client): the banner then the panel, Ready -> queue with the heroes first, confinement to Start + an unlocked Start2. The lost-`begin` fallback and a multi-client Ready are untested. 2026-10-05: the phase is now no-roll only (a rolled initiative passes no `holdBeforeQueue`; the heroes arrange before rolling) -- UT |
| **Dwarvish Bandits script features** (2026-10-04; see "Script features added for The Dwarvish Bandits") | Core: `DMHub Game Rules/TestRiders.lua` (movement/wealth requirements, `(Round N)` riders), `Draw Steel UI/DSVictoryScreen.lua` (`RegisterHeroCardNote`), `Codex Titlescreen/EotwRoster.lua` (treasure home). EotW: `EncounterScript.lua` (new clauses, entry dice tables, round scenes, bystander setup line) + `tests/encounter_script_test.lua` (503), `EncounterMontage.lua` (effects, `MontageSceneImage`, round in `HeroFacts`), `EncounterMontageStage.lua` (`SetBackdropScene`: video loop, round scenes), `EncounterZones.lua` (object reveals, `UnlockedStartZones`), `EncounterOfTheWeek.lua` (extra start zones, bystanders out of initiative, arrival item snapshot, `TreasureGained`, treasure on the outcome + victory card) | luac + parser tests (503) + typing clean. VERIFIED 2026-10-04 by an MCP-driven single-client playtest in game `1e3c159e` (via `codex-eotwauthor`): day video backdrop playing, night backdrop in round 2, Zaliac speech/branch, the Zaliac edge chip, a tier-3 double table roll, Start2 + 2 hero tokens, chest reveal, a lost consumable with and without consumables (silent recovery), the max-Stamina curse, the rolled-damage boon (a live power modifier), recovery value +2, the locked mother -> trail -> cave chain (+3 tokens), the Wolf ally, a party-wide damage boon, all three end-of-montage consequences, Civilians out of initiative, freed on contact, walking 4 per hero turn, the scripted victory (2/2) and "Treasure: Bastion Belt" on the victory card. NOT seen: the Wealth / climb-fly edges with a qualifying hero (none of the pregens qualifies; unit-tested), the treasure reaching the town, a multi-client run |
| **The authoring test** (2026-10-05; see "The authoring test"): Game menu rows to play the map's encounter as a player host from the start, the montage or the combat, with a pregen picker and End Test | Engine: `GameController.cs` (`playerHostModeForced`, `directorlessPlay`), `LuaInterface.cs` (`dmhub.playerHostModeForced`, `dmhub.directorlessPlay`), `GameHarness.cs` (carried across the refresh), `LevelObject.cs` (trap freeze); stub `Definitions/dmhub.lua`. Codex: `EncounterOfTheWeek.lua` (`IsTestPlayer` in `IsEotwGame`, "the authoring test" section, conclusion + proceed + host-tick gates), NEW `EncounterTest.lua` (registered in the EncounterOfTheWeek codemod after `EncounterMontageStage.lua`, Firebase confirmed), `EncounterMontageStage.lua` (`ShowStoryScreen` `buttonText`/`busyText`) | C# NEEDS BUILD; luac + typing clean; needs an app restart; UNTESTED |
| **Reinforcements + clear-the-map victory** (2026-10-05, user direction; see "Reinforcements and the clear-the-map victory"): `## Reinforcements: <Name>` sections (`Arrive:` / `Enter:` / `Shout:` + islands that take turns) and `Victory: every Dwarf on the map is defeated`. Applied to The Dwarvish Bandits in game `1e3c159e` | NEW `EncounterReinforcements.lua` (registered in the EncounterOfTheWeek codemod after `EncounterZones.lua`, Firebase confirmed); `EncounterScript.lua` (grammar), `EncounterOfTheWeek.lua` (host tick + victory OR), `EncounterZones.lua` (victory setup entry), `EncounterMontage.lua` (reset), `EncounterScriptValidator.lua` (rows; bystander lines no longer reported as unrecognized); core `DMHub Game Rules/Creature.lua` (`eotwReinforcement` field annotation); `tests/encounter_script_test.lua` (909); skill `script-reference.md` | luac + parser tests + typing clean; the live document parsed offline with the new parser (no warnings; gunners round 2, trappers round 3, alternating). NOT run in the app: needs an app RESTART (new codemod file), then the authoring test (Combat) to see a wave arrive, the shout, the clear-map win. UNCOMMITTED |
| **One Encounter of the Week + the Proving Pits** (2026-10-06, user direction; see "The Encounter of the Week and the Proving Pits"): a single scheduled Encounter of the Week at the Gate (blurb from its `# Town Gate`) + Past Encounters; community encounters moved to a new **Proving Pits** location (practice: no Victory, treasure or outcome; a town-side debrief: vote, feedback for the creator, nomination); Proving Pits unlock after a first Encounter of the Week win; admin rotation (Codex menu dialog, `SetWeek`, `tools/eotw_week.py`, `/eotw-rotate` skill); Goblin Ambush to be the first week, Angry Dwarves retired | Server: `cloudflare-game-server/src/city-core.ts` (schedule, debriefs, nominations, unlocks), `src/city.ts` (tables `city_settings`, `city_danger_feedback`, `city_nominations`; actions; `/city/week`; admin HTTP `/admin/city/{id}/week`), `src/index.ts` (route, `CITY_ADMINS` env), `wrangler.toml` + `wrangler.dmhub.toml` (`CITY_ADMINS`), `test/city-core.test.ts` (315 total pass). Codex: `Codex Titlescreen/EncounterOfTheWeek.lua` (schedule API, `CityRequest`, `ShowWeekDialog`, the two party boards, `WeekBanner`, Past Encounters, Proving Pits board + location + art, creator feedback, debrief), `Codex Titlescreen/EotwRoster.lua` (`DangerRoomsUnlocked`), `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`practice` stamp, `IsPracticeGame`, no award / outcome / treasure, `eotw-practice` card note, `eotw:pendingDebrief`). Tools: NEW `tools/eotw_week.py`, NEW skill `.claude/skills/eotw-rotate/`; `/eotw` skill text. Art: core image `92f3f806-...` from `~/Downloads/Steel Draw monsters cover.psd` | Server unit tests + tsc pass; luac + typing clean. **Worker DEPLOYED to staging 2026-10-06** (version `97d3fe50`; `/api/city/blackbottom/doc` shows `city.week = null`). Schedule SEEDED: Goblin Ambush (now week 3 after a test rotation and restore). VERIFIED 2026-10-06 single client, titlescreen town: see that section's "Verified". NOT seen: a practice game played (game side), the locked Proving Pits node (this account is unlocked), a second client, `tools/eotw_week.py` (no admin secret here). UNCOMMITTED |
| **Every test has a critical** (2026-10-07, user direction; see "Montage beats"): a missing 4th tier is built as tier 3 + an additional hero token; the critical stays hidden (roll dialog, stage rows, icons) until a natural 19-20 lands, then the stage shows a "Critical" row | `EncounterScript.lua` (`AutoCriticalText`, `critAuto`, hero-token "additional"/"extra", `OptionEffectLists` `includeCritical`), `EncounterMontage.lua` (`TeaserTiers` 1-3 only), `EncounterMontageStage.lua` (`TierName`, `TierRows`, "Critical" labels), `EncounterScriptValidator.lua`; `tests/encounter_script_test.lua` (923); skill `script-reference.md` | luac + parser tests + typing clean. UNTESTED in the app (needs an app restart; check: a forced natural 19-20 shows tiers 1-3 while rolling, then the Critical row with the bonus token, +1 hero token in the pool). Modules NOT republished (the change is code only; no script edits needed). UNCOMMITTED |
| **Roll button pings; companions and assists REMOVED** (pings 2026-10-08; removal 2026-10-18, user direction: "remove the idea of assisting someone during a montage"): a hero approaches an entry alone -- no "Accompany them" gathering, no companions, no pre-roll assists, no Teamwork go-along. Knacks, secret options, languages and riders read only the hero at the entry. Pardon My Friend and Put Your Back Into It! are now offered to ANY other hero with the perk (delves included); the Ritualist blesses only their own test; a "you and each ally" consumable reaches only its user. Ghost Accept / Re-roll on other players' roll cards still ping the button for everyone with a pulse in the pinger's colour | `EncounterMontage.lua`, `EncounterMontageStage.lua`, `EncounterScript.lua` (`MainTestSkill`; `AssistSkillChoices` deleted) + `tests/encounter_script_test.lua`, `EncounterMontageBuilder.lua` (assist hint), `Codex Titlescreen/EotwHeroSheet.lua`; core `Timeline/EmbeddedRollDialog.lua`, `Timeline/AbilitySidebar.lua` (pings, unchanged); docs `KNACKS_REFERENCE.md`, skill `script-reference.md` / `lua-toolkit.md` | Removal: luac + parser tests (942) + typing clean. NOT run in the app (needs a RESTART: the request kinds and turn statuses changed). A montage document saved mid-turn by the old code in status `gathering`/`assist`/`assisting` would be stuck; reset the montage. UNCOMMITTED |
| **Players leaving and coming back, phase 1** (2026-10-09, user direction; see "Players leaving and coming back"): a player who leaves hands everything they control to the host as free agents; a notice under the title bar's players row on every screen; the players-row popout lists who is here and lets the host hand a free agent to another player; a returning player gets their free agents back; the montage turn in progress follows its hero | NEW `EncounterPresence.lua` (registered in the EncounterOfTheWeek codemod after `EncounterTest.lua`, Firebase confirmed); `EncounterOfTheWeek.lua` (host tick calls `EncounterPresence.HostTick`), `EncounterOfTheWeekHud.lua` (`playersPopout`), `EncounterMontage.lua` (`SyncTurnToOwners`); core `Codex Titlescreen/CodexTitleBar.lua` (`CodexTitleBar.ShowPlayersToast` / `OpenPlayersPopout`, the custom popout, the player host's portrait in a directorless game), `DMHub Core UI/Hud.lua` (`playersPopout` provider field, `GameHud.CustomInterfacePlayersPopout`) | luac + typing clean. VERIFIED 2026-10-09 single client in `RadiantFascinatingLoudWorg` (combat, round 1) with `EncounterPresence.DevSimulateLeave/Return` and a placeholder userid on two heroes: the host's portrait in the players row, the notices (stacked under the row, above the hud), Reassign opening the popout, the popout (free agents marked, a hand-over dropdown for the host), ownership moving both ways, the error paths of `Give`. NOT seen: a real second client leaving (session-driven detection and its timing), a hand-over to another real player, a montage turn changing hands, a returning player's re-arrival. UNCOMMITTED |
| **Players leaving and coming back, phase 2** (2026-10-09, user direction; see "Players leaving and coming back"): leaving or quitting an EotW game asks "You are leaving the Encounter of the Week. You can resume later" -- Leave / **Abandon Game** (red, second click confirms); abandoning keeps the heroes as free agents for good and tells the others; the last member who has not abandoned deletes the game on abandoning (when they own it); a player away at a victory gets "While You Were Away" in town to claim it or count the game as abandoned | Engine: `LuaInterface.cs` (`QuitApplication` asks the Lua global `OnQuitRequested`; new `ForceQuitApplication`; `Application.wantsToQuit` routed through it), `GameHarness.cs` (a launched window's Leave forces the quit); stub `Definitions/dmhub.lua` (hand-added to match). Core: `Hud.lua` (`confirmExit` provider field, `GameHud.CustomInterfaceConfirmExit`), `CodexTitleBar.lua` (`OnQuitRequested`; the close button defers to it), `Commands.lua` (Leave Game asks it). EotW: `EncounterPresence.lua` (`ConfirmExit`, `Abandon`, `eotwleave-<userid>` documents, abandoned events, `Members` / `IsLastMember`), `EncounterOfTheWeekHud.lua` (`confirmExit`), `EncounterOfTheWeek.lua` (`eotw:abandonedgame`, `OutcomeDecided`, `VictoryOutcomesFor`, `OfferAbsentOutcomes`). Town: `Codex Titlescreen/EncounterOfTheWeek.lua` (abandon cleanup, `DestroyPreviousGame` keepIfOthers/neverDelete, "While You Were Away"), `EotwRoster.lua` (`AddPendingOutcomes`). Server: `city-core.ts` / `city.ts` (`offer-outcomes`, `list-offered-outcomes`, `resolve-offered-outcomes`, table `city_offered_outcomes`) + tests; `index.ts` (delete-game releases a game marked `deleted` + `releaseStorage`). Cloud function `eotwAbandonGame` (`cloud-functions/functions/index.js`, `eotw-games.js` + test) | luac + typing clean; server tsc clean, 319 tests pass; functions 208 tests pass. `eotwAbandonGame` DEPLOYED 2026-10-09 (refuses an unvalidated call, checked). Game server DEPLOYED to staging 2026-10-09 (version `c6028b38`; delete-game still demands auth for an unflagged game, checked); release NOT deployed. C# NEEDS BUILD; Lua needs a RESTART. Nothing run in the app. UNCOMMITTED |
| **Players leaving and coming back, phase 3: host migration** (2026-10-09, user direction; see "Players leaving and coming back"): the host leaving puts a sticky "X, the host, has left" notice with **Claim Host** on every player's screen; a claim makes that player the host (the old host's heroes become their free agents, the Monster AI moves with the host tick); the owner coming back loads as a player and is offered **Reclaim Host**; every screen is told who the new host is | Cloud function `eotwSetHost` (`cloud-functions/functions/index.js`; `gameHosts` / `sessionIsLive` in `eotw-games.js` + tests). EotW: `EncounterPresence.lua` (`WatchHost`, `RequestHost`, `data.host` + "newhost" events), `EncounterOfTheWeek.lua` (map script `onLoseHost` -> `MapScriptLoseHost` stops the AI). Core: `CodexTitleBar.lua` (`HasPlayersToast`, `DismissPlayersToast`) | luac + typing clean; functions 210 tests pass. `eotwSetHost` DEPLOYED 2026-10-09 (refuses an unvalidated call, checked). Lua needs a RESTART (and phase 2's C# build). Nothing run in the app. UNCOMMITTED |
| **Consumables in a montage** (2026-10-09, user direction; see "Consumables in a montage" under "Runtime state and authority"): the strip shows every carried consumable; click for a use menu (free, any time in the rounds but mid-roll); short effects last one location, long ones the encounter; an alert "!" + "Use it now:" tooltip + option highlight when an item would reveal a secret option, open a knack or add an edge | `EncounterMontage.lua` (`GetStripItems`, the "consumables in the montage" and "what an item could do" sections, the `consumed` request, `MaintainMontageUses` in the host tick, `EndMontageUses` in `ApplyPendingCombatBoons`, the `HeroFacts` override + consumeSeq), `EncounterMontageStage.lua` (`CreateItemIcon` menu / badge / tooltip / highlight, `CreateItemStrip`, `TurnSignature`, styles) | luac + typing clean. Needs an app RESTART. UNTESTED: nothing has been run in the app. Check: Healing Potion heals and leaves the strip; Buzz Balm's Speed +2 survives the turn it was used in and ends when it resolves; Float Powder / Concealment Potion last into combat; Imp's Tongue on a companion raises the "!" where a `you speak X` secret option exists and the option appears after use; Concealment Potion "!" on a Sneak test; a garbled Hyrallic line on screen fades into plain words when a hero in the group uses Imp's Tongue (and the "!" offered it), and later lines show plain; a dice-rolling item (Restorative) shows its roll over the stage; Black Ash Dart greyed "combat only"; a second client sees the "!" and the effects end there too. UNCOMMITTED |
| **Downtime** (2026-10-10, user direction; see "Downtime: wounds, the Blue Fish Inn, respite and projects", which has the file-by-file table): wounds come home, the Blue Fish Inn (respite + Catch Your Breath), Downtime Activities, projects, Expand the Guild + roster slots 4 -> 9 | City `city-core.ts`/`city.ts`/tests/`CLAUDE.md`; game `EncounterOfTheWeek.lua`; town `EotwRoster.lua`, NEW `EotwDowntime.lua` (registered), `EotwHeroCard.lua`, `Codex Titlescreen/EncounterOfTheWeek.lua`; core `DMHub Core UI/CreatorCredit.lua` | Server tests + tsc pass, DEPLOYED to staging; Lua luac + typing clean; assets uploaded; played live 2026-10-10 (respite, project start, rolls, breakthrough refund, completion). COMMITTED 2026-10-10 except the defeat-survivor wounds (they ride with the burial write-back) |
| **The Arcane Market** (2026-10-10, user direction; see "The Arcane Market"): a town location selling consumable treasures -- a Presence test (Alchemy/Magic) sets 2/3/4 treasures on offer (a critical: 4 + one extra purchase), buy up to Wealth, once per hero between Town Gate encounters | NEW `Codex Titlescreen/EotwMarket.lua` (registered, Firebase confirmed), `Codex Titlescreen/EncounterOfTheWeek.lua` (location + scene), `DMHub Game Rules/Creature.lua` (field annotation); video + poster core assets uploaded | luac + typing clean; needs an app RESTART; NOT run (the user is testing it). UNCOMMITTED |
| **Leads: carousing at the inn; the Arcane Market must be found** (2026-10-11, user direction; see "Leads: carousing at the Blue Fish Inn"): the inn moves up-left to (0.235, 0.455); a respite needs someone hurt; each respite earns one Carouse (Presence test, tier 3 learns a lead); the old Elementalist's conversation; the lead opens Find the Arcane Market (90 points, Intuition/Presence; Alchemy, Magic, Read Person) with hero lines by tier and progress; completing it puts the market on the map, which is otherwise hidden | City `city-core.ts` (Leads section, `CITY_LEADS`, `find-arcane-market`, `requiresLead`, `unlocks.market`), `city.ts` (tables `city_leads`, `city_carouse_chance`, `city_carouses`; `carouse`, `dev-reset-leads`), tests; town NEW `EotwLeads.lua` (registered after `EotwDowntime.lua`, position 8, Firebase confirmed), `EotwDowntime.lua`, `EotwRoster.lua`, `EncounterOfTheWeek.lua` | Server tsc + 338 tests pass, **DEPLOYED to staging 2026-10-11** (version `910e1fa0`). Lua luac + typing clean (0). Played live 2026-10-11 (respite gate, carouse, lead, conversation, project rolls). COMMITTED 2026-10-12 with the inn's reveal (the Hero-module pregen hunks in the same files stay uncommitted) |
| **The montage builder** (Game > Montage Builder; B1 the lossless edit layer 2026-10-11, the UI 2026-10-12, user direction; see "The montage builder"): the parser now records where each field it reads sits (`roll.line` / `tierLines` / `lastLine`, `free.lines`, `entry.descriptionLines` / `approachLines` / `consequence.lines` / `sceneSepLine`, `option.textLines`, `knack.textLines`, `beat.introLines`, delve `orderLines` / `chestLines`, table `line` / `lastLine`, `beat.encounterLine`, narrative `section.textLines` / `promptLines`); the new pure module `EncounterScriptEdit` splits and rejoins text byte for byte and turns builder edits into line patches on the right sub-document | `EncounterScript.lua` (additive fields only), NEW `EncounterScriptEdit.lua`, NEW `EncounterMontageBuilder.lua` (both registered in the EncounterOfTheWeek codemod), NEW `tests/encounter_script_edit_test.lua` (99 checks alone, 1484 with the corpus) | luac + typing clean (both 0); `encounter_script_test.lua` 934 pass; `encounter_script_edit_test.lua` 91 pass on its own, 1476 with the authoring corpus (258 documents from `C:\dev\eotw`, 6 scripts, 37 entries, every one of 80 rolls rewritten by the writers reads back identical with no new warnings). 2026-10-12: the builder UI `EncounterMontageBuilder.lua` (B3-B8 first version) built on it, both files registered in the codemod (Firebase confirmed) and verified live in `e96656f3` (see "The montage builder"). UNCOMMITTED |
| This document | | |

The codex working copy also holds plenty of unrelated uncommitted work, so
commit the EotW files selectively.

The authoring directory `C:\dev\eotw` (its own git repo) has ~260
uncommitted entries. The Hero Death rule was renamed by a write-back to
`hero-death-encounter-of-the-week.yaml`, and the documents folder now holds
the authoring game's whole journal (Delian Tomb rooms and more) beside the
week's 17 script documents. Only documents filed under an encounter map are
published. Review the directory before committing it wholesale.

## Known open problems

- **No bare `Encounter` map** in the authoring game. Only `Encounter: Goblin
  Ambush` and `Encounter: Angry Dwarves` exist, so a resumed game with no
  recorded choice has no default. The publisher warns about this; it is one
  of the standing warnings `--force` overrides.
- **Two floor objects reference assets that ship nowhere** (`5939fe95`
  `GL_OvergroundDwarvenCityCenter_Original_Day` and `9325d163`). Low severity:
  a placed object embeds its own copy of the art. This is the other standing
  publish warning. Exporting the assets to `C:\dev\eotw` would close it.
- **A player who disconnects** no longer wedges the story once phase 1 of
  "Players leaving and coming back" is live: their heroes pass to the host,
  and every wait is keyed on who controls a hero. Still open: a player who
  never ARRIVES (a crash during load) holds the party gate, and the HOST
  leaving stops everything (phase 3).
- **Publisher has no script awareness** (plan steps 35/45). An item or
  monster a clause names that is not in the core data module silently
  grants nothing for players. See "Compendium content the script needs".
- **Two module pregens are authored into the Players party** (High Elf
  Tactician, Human Null). `SweepPlayersParty` moves them at every arrival,
  so this is cosmetic. The proper fix is to move them to the *Delian Tomb
  Pregens* party in the authoring game and republish. Not done.
- **Suppressed triggers are silent.** A "can't use triggered actions" effect
  or an empty resource pool drops a hero's trigger prompt with no feedback,
  which strict-rules players read as a bug. The Tactician's Mark on a killing
  blow, seen 2026-09-16, is the known case. Wanted: a hint on the hero card's
  trigger badge, or a notice.
- **Re-roll is still a free retry when `strict:rolls` is off.** Moot in EotW,
  which forces it on.
- The stage mounts its own pools strip at the rail's spot, so check that the
  rail's strip does not also show through (a duplicate was noted
  2026-09-18 and not re-checked).

## Verification still owed (do these first)

In a real EotW game with **at least two clients** and the current week:

1. Begin -> host enters -> the loading screen dissolves straight onto the
   opening narrative (held loading screen); the member's screen does the same.
2. Narrative: an agreed vote with a genuine disagreement (the random flash
   across real players), and an individual section.
3. Montage on the split document: each player drags their own heroes, a
   non-host player's roll with the remote card and the live tier highlight on
   the other screen, the ghost Accept / Re-roll on
   the watching screen pinging the roller's buttons (pulse in that player's
   colour), scenes paging for the acting player only, a
   delve with a chest roll seen by both, the haul strip and item hand-over,
   locked/temporary entries, outcome icons.
4. Stage cursors: each player sees the other's pointer on the stage.
5. Tactical Preparation: a second player spending, and Proceed waiting on both.
6. Encounter beat: traps placed (and revealed when earned), monsters spawn
   behind the stage, the dissolve, Draw Steel with any allies on the heroes'
   side, Surprised applied as the montage decided.
7. Combat: the AI waits on prompts and end-of-turn saves (the banner names
   the hero), a dead hero leaves and the turn advances.
8. Victory: each screen holds until its own Proceed, then that client exits;
   the lobby row and the resume row are gone afterwards.

## Next steps

1. Commit the uncommitted EotW work above (selectively), deploy the lobby
   worker's 4-6 change to staging, deploy the EotW mod and the core files
   it now needs (`Utils.lua`, `DSRollDialog.lua`, `EmbeddedRollDialog.lua`).
2. Run the two-client playthrough above, fixing what it finds.
3. Content hygiene: add a bare `Encounter` default map, export the two
   orphaned floor-object assets, move the two stray pregens, then republish
   without `--force`.
4. Publisher validation of the script grammar (plan steps 35 and 45).
5. ~~Decide the disconnected-player rule~~ DECIDED 2026-10-09: the host
   takes a leaver's heroes as free agents (see "Players leaving and coming
   back"). Phase 1 BUILT; verify it with two clients, then phase 2 (the
   leave dialog, Abandon, outcomes for absent players) and phase 3 (host
   migration).
5a. **Companions and assists removed** (2026-10-18, see the status table):
   restart the app, play a montage turn end to end (approach -> intro ->
   choose -> roll), and check Pardon My Friend / Put Your Back Into It!
   offers reach another hero; check the ghost buttons from a second client.
5b. **Consumables in a montage** (BUILT 2026-10-09, untested; see the status
   table and "Consumables in a montage"): restart, start a montage with
   `/eotwmontage start` in an authoring game, give the pregens a few
   consumables (Healing Potion, Buzz Balm, Concealment Potion, Imp's Tongue,
   Black Ash Dart) and run the table's checks.
6. Before opening EotW beyond the dev machine: verify a non-owner account can
   fetch the unlisted module and create a game from it; deploy the lobby to
   release and switch `LOBBY_OPTIONS`/`GAME_BACKEND` off staging.
7. **Blackbottom, the town** (server + basic client built 2026-10-02; see
   "The town client" for exactly what is verified). Next, in order:
   - finish the single-client checks: form a party with a roster hero
     (abandon the old staging EotW game first), Begin and play, Create
     through the builder, dismiss;
   - verify the active-hero auto-claim and remote portraits (BUILT
     2026-10-03, see "The town client"; needs the engine build for
     `dmhub.CreateDetachedCharacter`): form a party and join one from the
     New Player Window, each with active heroes;
   - verify the encounter stories + Victory award live (see that section's
     "Not yet verified"): deploy the City to staging (`npm run deploy`; the
     module is already republished as v29), then play Goblin Ambush to a
     victory and back;
   - step 62, coming home: the Victory half is BUILT (see "Encounter stories
     and the Victory award"), and burying the dead (`record-outcome {died}`)
     is BUILT 2026-10-09, untested; still open are landing in town and
     "Away" in the guild;
   - other players' heroes in town (`town-heroes`) and a second machine;
   - the real map export.

8. **The hero builder and hero sheet** (see that section). Step engine and
   builder screen BUILT 2026-10-03, with the user's round-1 notes addressed.
   Next: re-test those notes, a live end-to-end Create -> Finish -> roster,
   then build step 5 (the read-only hero sheet).

9. **Community encounter modules** (BUILT 2026-10-03, untested; see
   "Community encounter modules and the encounter pool"). Next: restart and
   run that section's five-step test, starting with the publish dialog in
   the authoring game. Watch the host install step (behind the 20s
   loading-screen hold).

10. **The Dwarvish Bandits features** (BUILT and single-client VERIFIED
   2026-10-04; see the status table). Still open: the town receiving the
   Bastion Belt (needs a real EotW game: the City round trip), a multi-client
   arrangement, and publishing the encounter as a community module. The EotW
   code must also reach players: republish `mcdm-encounteroftheweek` (and
   `codex-eotwauthor`) once the code is committed and deployed.

11. **The authoring test** (BUILT 2026-10-05, untested; see "The authoring
   test"). Build the engine (`playerHostModeForced`), restart, then in an
   authoring game with pregens installed: Game menu > Test Encounter:
   Montage with 4 pregens -> the refresh lands on the montage stage as a
   player (EotW HUD, test bar); play into combat; win; the Conclusion screen's
   End Test -> back to the Director with the map as authored (no copies,
   spawns or allies; settings and hero tokens restored). Then Combat (straight
   to the spawn and Draw Steel), From the Start, End Test mid-montage and
   mid-combat, and RESUME after an app restart mid-test.

13. **The Encounter of the Week and the Proving Pits** (BUILT and town side
   VERIFIED 2026-10-06; see that section's "Verified"). Still owed: play a
   real Proving Pits game (4 heroes from the Proving Pits board) and check the
   game side -- no Victory award, "Proving Pits: practice only" on the cards,
   no treasure, the debrief on return; see the locked node with an account
   that has never won (the New Player Window's secondary account); commit.

12. **Reinforcements** (BUILT 2026-10-05, untested live; see "Reinforcements
   and the clear-the-map victory"). Restart the app (new codemod file), open
   The Dwarvish Bandits (`1e3c159e`) and run Test Encounter: Combat. Check:
   `/eotwreinforce` lists the section; at the start of round 2 four to eight
   Dwarf Hunters and a Gunner appear on the stairs (tiles x 4-7 around y -5,
   zone `Reinforcements`), take turns that round and one shouts; round 3
   brings the Trappers; killing every Dwarf present wins even with the
   hostages still bound; End Test removes the arrivals. Tune the numbers with
   the user afterwards.

14. **Downtime** (BUILT 2026-10-10, not run live; see "Downtime: wounds,
   the Blue Fish Inn, respite and projects", "As built"). The City is deployed
   to staging (`b66c3536`); restart the app (new codemod file), then run that section's five
   "To test" steps.

15. **The Arcane Market** (BUILT 2026-10-10, not run; see "The Arcane
   Market"). Restart the app and run that section's five "To test" steps,
   then commit `EotwMarket.lua` with the location.

16. **The montage builder** (first version BUILT and verified live
   2026-10-12; see "The montage builder"). Next: the user's first real
   authoring session with it, then B2 (the clause picker), speaker /
   monster pickers in the scene editor, the journal-document button, and
   B9 (narratives, encounter setup).

17. **Leads** (BUILT 2026-10-11, played live, COMMITTED 2026-10-12; see
   "Leads: carousing at the Blue Fish Inn"). Left: finish a hunt to the
   market's appearance on the map, and the release deploy of the City.

   Progression is Phase 11, after its own design pass. Downtime (step 14) is
   its first piece. **Note:** the EotW
   screen now IS the town, and its games live in the City's roster instead
   of the old `eotw` lobby, so steps 1-2 above run through the town.

---

# Where the code lives

| Area | Path |
|---|---|
| Titlescreen screen, lobby client UI, create/join/launch, hero picker | `Codex Titlescreen/EncounterOfTheWeek.lua` (core codex, Codex Titlescreen codemod, before `CodexTitlescreen.lua`) |
| Titlescreen link | `Codex Titlescreen/CodexTitlescreen.lua` (`eotwTitlescreenLink`) |
| Town roster sync, Hero's Guild, Graveyard | `Codex Titlescreen/EotwRoster.lua` (global `EotwRoster`) |
| The Arcane Market (consumable treasures: Presence test, Wealth purchases) | `Codex Titlescreen/EotwMarket.lua` (global `EotwMarket`) |
| Leads: carousing at the inn, the lead conversations, the inn's leads section | `Codex Titlescreen/EotwLeads.lua` (global `EotwLeads`) |
| Creator credits (logo badge, art backdrop) for the location scenes | `DMHub Core UI/CreatorCredit.lua` (global `CreatorCredit`, core) |
| Hero card (town strip + montage HUD) | `Codex Titlescreen/EotwHeroCard.lua` (global `EotwHeroCard`) |
| City DO (the town's server) | `cloudflare-game-server/src/city-core.ts` (pure logic), `src/city.ts` (`CityObject`), tests `test/city-core.test.ts`, `test/city-smoke.ts` |
| Character export/import | `dmhub.ExportCharacter` / `dmhub.ImportCharacter` in `Assets/Scripts/LuaInterface.cs` -> `GameController.ExportCharacter` / `ImportCharacter` |
| Game-side mod (codemod `cdc19d98-...`, `EncounterOfTheWeek_1428`, ships in the module) | `EncounterOfTheWeek/`: `EncounterOfTheWeek.lua` (setup, map script, beat machine, combat glue), `EncounterScript.lua` (pure parser), `EncounterZones.lua` (traps/zones), `EncounterReinforcements.lua` (reinforcements, the clear-the-map victory), `EncounterScriptValidator.lua` (dev panel), `EncounterMontage.lua` (montage runtime + shared effect application), `EncounterNarrative.lua`, `EncounterOfTheWeekHud.lua` (custom interface), `EncounterPrep.lua` (Tactical Preparation), `EncounterMontageStage.lua` (all stage UI), `EncounterTest.lua` (the authoring test's menu rows, hero picker and test bar) -- that is the codemod's file order |
| Parser unit tests | `tests/encounter_script_test.lua` (run with `../dependencies/lua/bin/lua.exe` from the codex root) |
| Montage builder: lossless script edits (pure) + tests | `EncounterOfTheWeek/EncounterScriptEdit.lua`, `tests/encounter_script_edit_test.lua` (optional arg: a corpus manifest; see "The montage builder") |
| Montage builder window (Game > Montage Builder, `/eotwbuilder`) | `EncounterOfTheWeek/EncounterMontageBuilder.lua` (global `EncounterMontageBuilder`; codemod file order after `EncounterTest.lua`) |
| Test riders (core, also used by the journal) | `DMHub Game Rules/TestRiders.lua` |
| Lobby server | `cloudflare-game-server/src/lobby-core.ts` (pure logic), `src/lobby.ts` (`LobbyObject` DO), tests `test/lobby-core.test.ts`, `test/lobby-smoke.ts` |
| Lobby C# client + Lua bridge | `Assets/Scripts/LobbyConnection.cs`, `Assets/Scripts/LobbiesLua.cs` (global `lobbies`), stub `Definitions/lobbies.lua` |
| Publisher (official module) | `tools/eotw_publish/` (`publish_eotw.py`, README) |
| Community Encounter of the Week modules (publish-dialog type + checks) | `DMHub Core Panels/ModShare.lua` (`eotw` in `g_moduleTypes`, `CheckEncounterModule`) |
| Encounter pool, encounter keys, admin pull | `Codex Titlescreen/EncounterOfTheWeek.lua` ("the encounter pool" section, `ShowPoolDialog`) |
| The week's schedule, the Gate and Proving Pits boards, Past Encounters, the debrief, the admin week dialog | `Codex Titlescreen/EncounterOfTheWeek.lua` ("the week's schedule" section, `ShowWeekDialog`; in `CreateScreen`: `PartyBoard`, `BoardChildren`, `WeekBanner`, `DangerEncounterRow`, `ShowPastEncountersDialog`, `ShowCreatorFeedbackDialog`, `ShowDebriefDialog`) |
| The schedule, debriefs, nominations and unlocks on the server | `cloudflare-game-server/src/city-core.ts` ("The Encounter of the Week and the Proving Pits"), `src/city.ts` |
| Weekly assessment + rotation tooling | `tools/eotw_week.py` (admin HTTP), `.claude/skills/eotw-rotate/` (MCP) |
| Authoring content | `C:\dev\eotw` (git repo, no remote) + the Local authoring game `e96656f3-a11c-477b-89f1-978452983324` |

Codemod gotchas that apply to all of it:

- **Separate codemods do not load at the titlescreen.** The lobby game loads
  only the core codex, so all titlescreen-facing EotW code is core codex, and
  the game-side globals (`EncounterOfTheWeekGame`, `EncounterMontage`, ...)
  must be read with `rawget(_G, ...)` from anywhere that may run without them.
  Lua globals are strict, so even `X ~= nil` on an undefined global raises.
- The titlescreen is built once per app run. Edits to the titlescreen file
  need an app restart, not a Lua reload.
- **Registering a new file in the codemod needs an app restart**, and so,
  in practice, does iterating on the EotW files: `reload_lua` re-runs what the
  app already read, and the git-folder watcher dies often (the tell is a
  backtrace whose line numbers lag the working copy). Never `dofile` an EotW
  file into the running app: `dmhub.GetModLoading()` is nil outside a mod load
  and the runtime breaks until a restart. After a restart, re-present the
  stage (`EncounterMontage.Present`) to pick up stage edits.
- `DMHub Core UI/Hud.lua` resets `GameHud.customInterfaces = {}` when it
  loads, so if that mod reloads after the EotW hud, the takeover silently
  disappears until a restart.
- Do not hot-reload during someone's roll: it destroys the open roll dialog.

---

# Titlescreen and lobby

## Moving to the release server (WRITTEN 2026-10-21; nothing deployed or run in the app)

Decided with the user 2026-10-21: EotW players move from the staging worker to
release with the next update, their progress copied over; admins keep a
choice of server; staging keeps its data afterwards as a test bed; old
clients still pointed at staging are refused with "restart Codex".

**Client.** One preference, `eotw:server` (`"release"` default, or
`"staging"`), honoured only for `dmhub.isAdminAccount`; everyone else is
always on release. `EotwRoster.UseStaging()` / `CityOptions()` /
`GameBackend()` (titlescreen) and `EotwLobbyOptions()` (game side, same rule,
declares the setting too) read it at each connect, so the town, new games and
the in-game city requests (ready, leave, outcomes, Hall of Heroes) all follow
it. Admins pick it from a dropdown at the top right of the titlescreen's EotW
card; the card's headcount follows it. Chosen over stamping the server on each
game: non-admins can only reach parties through their own city, so everyone
in a game is already on one server, and games started on staging before the
switch report to release once their players restart. Admin-only edge: an
admin who changes the dropdown and then resumes a game made on the other
server sends that game's city requests to the wrong town.

**Server** (`cloudflare-game-server/src/city.ts`, "Moving a city to another
server"): admin routes `freeze` (every request but ping refused with a
message; flag kept in `freeze_state`, outside `city_*`, so it is never copied),
`dump` (every `city_*` table + the town chat rows of `lobby_doc`, paged, BLOBs
as base64), `restore` (per table, `clear=1` on the first page,
`X-Confirm-Restore: {cityid}`) and `restore-finish` (closes sockets and
restarts the object so memory reloads). Parties, invite codes and party chat
are not copied. `tools/eotw_city.py` drives it: `status`, `freeze`,
`unfreeze`, `clone --from staging --to release` (refuses an unfrozen source,
backs up BOTH cities to `~/eotw-city-backups` first, checks every table's row
count after). Tested locally 2026-10-21: `test/city-move-smoke.ts` against
`wrangler dev` (17 checks: heroes byte-identical, outcomes, graves,
graveyardRev, chat, freeze refuses / ping answers, unfreeze), plus the 356
unit tests.

**Cutover, in order:**
1. Lisa's Discord-bridge work (migration v5, `DiscordGatewayObject`) is in
   master; both workers deploy the same code from it. Release has never had
   the City's recent code: test it on staging first.
2. Release secrets: `ADMIN_SECRET` (have it locally as `tools/admin-secret.txt`
   or `$DMHUB_ADMIN_SECRET`) and `SURVEY_READ_SECRET`. `CITY_ADMINS` is already
   in `wrangler.toml` for both.
3. `npm run deploy` (staging) and `npm run deploy:release` from the same
   commit. `python tools/eotw_city.py status --env release` must list the
   same tables as staging.
4. Quiet hour: `python tools/eotw_city.py freeze --env staging`, then
   `python tools/eotw_city.py clone --from staging --to release`.
5. Deploy the EotW Lua (titlescreen + game side) the usual way. Players
   pick it up on their next launch; until then staging refuses them with the
   restart message. Outcomes of games that end on old Lua after the freeze
   are lost (accepted).
6. Re-point the tools at release: `tools/eotw_week.py` defaults to
   `--env staging` (and so does the `/eotw-rotate` skill that runs it), the
   survey dashboard reads `/admin/city/blackbottom/survey` on staging (move
   its `SURVEY_READ_SECRET` and URL to release). The bug-fix skill's scripts
   take the server per game and need nothing.
7. When old clients have had time to update: `python tools/eotw_city.py
   unfreeze --env staging` to use staging as the test town (its data stays
   as it was at the freeze).

## The Lobby: a Durable Object that is not a game

A **Lobby** is a first-class server concept, separate from games: a Durable
Object users connect to, which holds presence, chat and a small shared state
document. EotW uses the lobby `"eotw"`; future social surfaces can reuse the
concept. Nothing about it touches the local lobby game, Firebase game
records, or the campaigns list.

**The DO arbitrates; clients never write.** Clients `subscribe` (store
`"lobby"`) and `get`; every mutation is a typed request
`{type:"request", action, args, reqId}` answered by an `ack` carrying a
`result`. The DO validates and applies it, so the roster's invariants hold by
construction.

- Route `wss://.../lobby/{lobbyid}` (ids `[a-zA-Z0-9_-]{1,64}`); read-only
  debug snapshot at `GET /api/lobby/{lobbyid}/doc` (unfiltered). `LOBBY` DO
  binding, migration v3, in both wrangler configs.
- Document: `/chat/{msgid}`, `/gamechat/{gameid}/{msgid}` (private per game,
  members only: snapshots are filtered per client, broadcasts go to members,
  a join gets the backlog, a leaver gets a null put), `/presence/{userid}`
  (memory-only, derived from authed sockets), `/state/games/{gameid}`,
  `/state/reservations/{userid}`. Lobby chat and each game chat keep the last
  200 messages.
- Actions:
  - `chat {text, gameid?}`: 400 chars max. One 8-token bucket per user across
    all channels; each spent token regenerates 15s after it was spent.
  - `create-game {name?, public?, encounter?}`: reserves; one hosted game per
    user, enforced by **supersession** (an existing hosted record is dropped
    as if its host had left, `ack.result.superseded` names it).
  - `confirm-game {gameid}`: publishes the record once the engine game exists.
  - `join-game {gameid, heroes?}`: public + open games only (the host is
    exempt from the public check). Joining with zero heroes is allowed.
  - `set-heroes {gameid, heroes}`: replaces the caller's whole hero list.
  - `leave-game {gameid}`: the host leaving drops the record and its chat.
  - `kick-player {gameid, userid}`: host only.
  - `launch-game {gameid}`: host only, needs `4 <= slotsFilled <= 6`;
    status `open` -> `launched` and the roster freezes.
  - `ready-game {gameid}`: host only, `launched` -> `ready`.
  - `heartbeat {gameid}` and `ping`.
- Hero slots: each roster player carries `heroes: [{kind, id, name,
  className, ancestry?, level?}]`, where `kind` is `"lobby"` (a titlescreen
  hero, id = charid) or `"pregen"` (module charid). The display fields are
  copies so any client can render the roster. Caps: `MAX_HEROES_PER_PLAYER` 4,
  `SLOTS_TOTAL` 6, `MIN_HEROES_TO_LAUNCH` 4. `{}` is accepted as an empty list
  (Lua cannot tell `{}` from `[]`).
- Liveness: clients ping at least every 120s (the C# client pings every 50s).
  A game record or unconfirmed reservation expires after 5 minutes without a
  heartbeat (members heartbeat every 30s while the screen is open). Expiry
  runs lazily and via a 60s alarm -- no `setInterval`, which would stop the DO
  hibernating. Chat rows and the state row are persisted in SQLite; presence
  and rate buckets are memory-only.
- Auth is the real Firebase JWT check shared with games. On staging,
  `ALLOW_UNAUTHENTICATED_DEV` accepts tokenless sockets with a self-reported
  userId, so identity is spoofable there; release has no such path. Display
  names are self-reported.

**C# client** (`LobbyConnection.cs`): `LobbyConnectionManager` keeps one
shared connection per lobby id + staging flag. A `LobbyConnection` is a slim
sibling of `DOConnection`: same transport, token and reconnect backoff, a
local mirror of the document, `Request(action, args, ...)`, `GetAtPath`, and
change/status events. It is independent of `GameController`, so it works at
the titlescreen. A `Close()`d connection is terminal -- it never reconnects.
Lua: `lobbies:Connect(lobbyid, {staging, displayName})` (colon call) returns a
connection with `connected/status/revision`, `GetDoc/GetPath`,
`Request{action, args, success, error}`, `MonitorChanges/MonitorStatus` and
`Disconnect`. The global `lobby` already means the titlescreen/game-lobby
API, hence the different name.

## The EotW screen

All in `Codex Titlescreen/EncounterOfTheWeek.lua`, mounted on
`CodexTitlescreenRoot`.

- **Opening behind a loading veil.** Building the screen stalls for a second
  or two, so `ShowScreen` mounts a cheap veil first, builds the screen behind
  it, waits for the portrait warmer to settle (`PortraitWarmupSettled`: every
  warm panel reported `imageLoaded`, or 0.5s with no progress, or a 4s
  deadline), then cross-fades. Each step is scheduled from the end of the
  previous one so a slow build delays the reveal instead of exposing it. An
  invisible `eotwOpeningBlocker` stops clicks reaching the half-built screen;
  escape cancels the open.
- **Portrait warm-up.** Images only stream when a live panel references them,
  so the screen mounts 1x1 panels for every portrait the hero picker could
  show (own lobby heroes and pregens), a few per tick, rescanning while the
  pregen cache fills. **Never gate UI on an image-load count**: a "Loading..."
  cover over the picker was tried and stalled on portraits whose texture never
  arrives. Warming ahead has no worst case.
- **Games list** from `/state/games` (private games only to their members), plus
  presence and chat. A **resume row** ("Your game in progress", Resume /
  Abandon) appears when the account's EotW slot holds a live game with no
  roster record.
- **Game lobby view** (create/join/open lands here; no back button -- the way
  out is Leave/Abandon): hero **cards** in a wrapping row (portrait card, name,
  "Level N Ancestry Class", "Controlled by <player>", a PREGEN chip), a hover
  trash on your own heroes, a hover kick on others' (host), and a "+" card
  that opens the Add Hero picker (a card grid of your titlescreen heroes and
  the pregens). Another player's roster hero is not on your machine, so its
  card first shows a silhouette and fetches the hero from the City (see
  "The town client", Gate). New cards fade
  in; neighbours slide apart through a scripted width tween (width is not
  style-animatable). The game's private chat replaces lobby chat. Host
  controls: Kick, Begin (enabled at 4-6 heroes), Abandon (two-click confirm).
  A **Re-join** button appears for a game already launched/ready.
- **Pregens** come from the module without installing it:
  `module.DownloadModuleSnapshot{moduleid, success, failure}` returns the
  latest engine-compatible version's characters as detached tokens
  (disk-cached per version), filtered to `IsHero()`. Their art lives in a
  *dependency* module (`venla-deliantomb`), so the engine registers the image
  records of the whole dependency closure, images only
  (`EnsureModuleArtPreviewCo`). Entering a game wipes module stores, so
  `EnsurePregenArt` re-registers when a sampled portrait stops resolving.
  `CachePregens` runs 5s after the titlescreen loads and again on open; an
  empty result is not committed, so it retries.
- **Leaving for the game.** The screen hides itself 0.35s after
  `beginLoading` (once the loading screen is opaque) and un-hides on
  `returnFromGameComplete`. It is hidden, never destroyed: a surviving screen
  is how `SweepStaleScreen` knows to rebuild a fresh one (new lobby
  connection, current state) after the player returns -- the old one belongs
  to the previous codemod generation and its connection is dead.
  `CheckLaunchedGames` auto-enters only on a status *transition* it watched,
  so returning from a launched game does not yank the player back in.

## Creating, joining and launching

- **Create** = lobby `create-game` (reserve) -> `lobby:CreateGame{
  startingModule = "mcdm-encounteroftheweek", backend =
  "durableobjects-staging", accountSlot = "eotw", directorless = true,
  create = fn }` -> lobby `confirm-game` -> host `join-game`. The game's
  `coverart` is `LOADING_SCREEN_ART` (Delian Tomb art -- update it with the
  week). **Join** uses `lobby:JoinGameEotw(gameid)`. A private game is
  joined only with its invite code (see "Steam invites").
- **One EotW game per account.** `AccountInfo.eotwGame` is a dedicated slot
  like `lobbyGame`: EotW games never enter the campaigns list or count
  against its cap. Lua reads it as `lobby.eotwGameid`. Creating or joining a
  new game destroys the previous one (`DestroyPreviousGame`: lobby
  `leave-game` + `LuaGameInfo:DeleteAndReleaseStorage`). For an owned game
  that marks `/games/{id}/deleted`, clears the slot and POSTs
  `/admin/delete-game/{gameid}`, which closes every socket with
  `1001 "game-deleted"` and deletes the DO's storage. A non-owner just leaves.
  `DOConnection` treats `game-deleted` as terminal.
- **Launch protocol (fast launch, 2026-10-08).** Begin sends `launch-game`.
  **Everyone enters on `launched`**: the host installs the module and runs
  setup while the members load alongside it. The engine keeps a member's load
  waiting until the host's install lands (only the owner installs: the
  starting-module install and the `contentSummary` write are owner-only, and
  401/403 writes are not retried). A member's setup then waits, behind the
  held loading screen, for the host's `eotwstate.setupReady` stamp
  (`WaitForHostSetup`, renewing the hold). The host stamps it, and sends
  `ready-game` over a connection it opened at the start of setup, as soon as
  the encounter map is stamped and the opening beat has begun. `ready` still
  matters for late joiners and Re-join. `/toggle eotw:fastlaunch` restores
  the old order (members enter on `ready`), for timing the two.
  Measured 2026-10-08 (two clients on one machine, `/debug` off; Begin to
  loading screen gone): host 5.2s -> 3.9s, member 11.8s (bare map, heroes
  at 13.8s) -> 4.5s (straight onto the stage). See "Launch timing" below.
- While in the game nobody heartbeats the roster record, so it expires about
  5 minutes after launch.
- **Choosing the encounter.** Since 2026-10-06 the party's encounter is
  chosen by WHERE it is formed, not from a dropdown: the Gate's Form a Party
  sets out for the Encounter of the Week, Past Encounters for an earlier
  one, and a Proving Pits row for that encounter (see "The Encounter of the
  Week and the Proving Pits"). The maps are still found by name: a map named
  exactly `Encounter` is a module's default and any map named
  `Encounter: <title>` is another; the **encounter pool** is the official
  module's maps plus every Public or Unlisted community Encounter of the
  Week module's maps (see "Community encounter modules and the encounter
  pool"). Names come from each module record's `contentSummary`
  via `module.DownloadModuleInfo`, with no snapshot download. The choice
  rides the roster record as `encounter`, an **encounter key** (string,
  120 chars, opaque to the DO). The publisher, the titlescreen's
  `IsEncounterMapName` (which ModShare's validator also uses) and the
  game-side `DEFAULT_ENCOUNTER_MAP` test hold three copies of the naming
  rule; keep them in step.
- **Debug New Player Window** (admin accounts, the town screen open; user
  direction 2026-10-03, replacing the game view's old "Player Window"
  button and its auto-join): the titlescreen's **Codex** menu gets a "New
  Player Window" row (`EncounterOfTheWeek.CodexMenuItems()`, appended by
  `CodexTitleBar.lua`'s main-menu Codex menu; shown only while
  `EncounterOfTheWeek.IsScreenOpen()`). It runs
  `dmhub.DuplicateWindowInNewProcess{asplayer = true, connect = false, args =
  "--eotw"}`. The child boots to the titlescreen as the secondary account
  (dev-key builds: `--asplayer` picks the partner account in `devkey.json`),
  and on reaching the selection screen opens the town once
  (`WantsAutoOpen` is one-shot; the arg bypasses the dev gate). From there it
  is an ordinary separate player: its own City roster (keyed by its userid),
  its own lobby game holding the hero working copies (`AccountInfo.lobbyGame`
  is per account, and `connect = false` keeps it from borrowing the parent's),
  its own builder drafts, parties and joins.
  **Shared-machine caveat:** both processes read and write the same
  preference files (`PrefsManager`, `<persistentDataPath>/settings/`), and
  each caches a preference in memory after its first read. The per-userid
  JSON maps `eotw:heroRevs` and `eotw:pendingOutcomes` are each one file, so
  the last window to write one overwrites the other window's newer entries
  **on disk** (its in-memory copy stays right). After a restart, a clobbered
  `heroRevs` costs only a redundant re-import from the City; a clobbered
  `pendingOutcomes` could lose a win not yet applied. Not fixed; it only
  matters if a window restarts between leaving an encounter and reopening
  the town.

---

# Blackbottom: the town (DESIGN 2026-10-01; server + basic client BUILT 2026-10-02)

User direction (2026-10-01): replace the plain lobby screen (the title,
games list and chat column in `CreateScreen`) with a **persistent town,
Blackbottom**. Players who take part in Encounter of the Week live there: they
keep a roster of heroes, move around the town by clicking locations on its
map, and set out from the town gate to face the week's encounters. They come
back to the town afterwards, and the heroes who died are buried in its
graveyard.

## The experience

- **The map.** Opening Encounter of the Week shows Miska Fredman's
  *Blackbottom* map full-screen (from
  `BlackBottom-44x32-layers-1.1 by Miska Fredman.psd`), with **location
  nodes** -- labeled markers -- on top of it. Clicking a node opens that
  location's interface over the map. A locked location shows as locked, with
  a tooltip saying what unlocks it.
- **Active heroes along the bottom.** A player has a **roster** of heroes. Up
  to **four** of them are **active**, meaning they are adventuring in town
  right now. The active heroes are shown along the bottom of the screen as the
  same hero cards the montage stage uses.
- **The Hero's Guild** (the first location, the hub):
  - It shows the player's whole roster as a stacked list, up to **12** heroes.
  - **Create** opens the character builder. The finished hero joins the roster
    and the player returns to the guild.
  - **Recruit** adds a pregen to the roster. The player is asked to name them;
    the pregen's generic name ("Dwarf Fury") is the suggested default.
  - **Recruit also offers the player's own titlescreen heroes** (user
    direction 2026-10-09), in a "Your Heroes" section above the pregens. A
    **copy** joins the roster; the titlescreen hero is never touched
    (decision 1 below still holds). The copy is brought to **level 1** and
    arrives with **no items** (inventory and every equipment slot emptied;
    the kit is kept), so treasure is only earned in town. A titlescreen
    hero with a living copy in the roster shows faded, "Already in your
    roster", and cannot be picked again.
  - Each hero in the list can be made active or inactive (at most four
    active), opened read-only, or dismissed (deleted, after a confirmation).
- **The Town Gate** is locked until the player has at least one hero. Opening
  it shows:
  - **parties forming**, which are open games the player can join;
  - **encounters underway**, which are launched games shown for information.

  The player joins a forming party or forms a new one (name, public or
  private, which of the week's encounters). This is today's create/join flow
  and game lobby view, except that **heroes come from the roster** -- the
  active heroes pre-selected -- instead of from titlescreen heroes plus
  pregens. From there everything is as now: Begin, launch, the script,
  combat.
- **Coming home.** After an encounter the player lands back in the town, not
  on the bare titlescreen.
- **The Graveyard.** A hero who dies while adventuring is taken off the
  roster and buried in the Graveyard location, where players can browse the
  fallen: name, ancestry and class, the encounter they fell in, when, and who
  played them.
- **The Hall of Heroes** (BUILT 2026-10-21, NOT run). Every party that wins
  a Town Gate encounter (current or past week, any series part; never the
  Proving Pits) gets one entry: its heroes and their players, when, the
  HOST's play time, rounds of combat (every fight in the game), and deaths.
  Decided with the user: newest first by default, also sortable by fastest /
  fewest rounds / fewest deaths; a tab per encounter; players' display names
  shown. Clicking an entry replays the victory screen the party saw.
  - Game side (`EncounterOfTheWeek.lua`, "the Hall of Heroes"): the host
    builds the entry right after the automatic Victory award, while combat is
    still live, and sends the city's `hall-record`. It waits in the
    `eotw:pendingHall` preference until the city answers; one left there
    when the game closes is sent by the town (`EotwRoster` FlushPendingHall,
    after each roster refresh).
  - The victory screen (`Draw Steel UI/DSVictoryScreen.lua`) now draws its
    cards from plain data: `CaptureSnapshot(live, outcome)` ->
    `SavedSnapshot` (still portraits, no tokens) is what the Hall stores, and
    `ShowReplay(parent, snapshot, {caption})` draws it again anywhere (Close
    button, Escape, the award drop replayed).
  - Town: the location at ~0.33, 0.2 (placeholder spot, check it against
    the art).
  - **Built by the town first** (2026-10-22, user direction; written
    code-only, NOT run). The location starts as **the Construction**
    (hammer icon; scene: Czepeku "Train Station Approach", Town Square
    still, Czepeku credit; the message "Join in the construction of the
    great Hall of Heroes where the works and deeds of heroes shall be
    recorded!"). Its card is the community project **Build the Hall of
    Heroes** (`build-hall-of-heroes`, scope `community`, 1000 points, one
    completion, `autoStart`: under way without anyone starting it). Any
    hero spends Downtime Activities on it with the usual project roll
    (Might or Reason; Architecture, Blacksmithing, Carpentry, Mechanics),
    and every roll adds to one town-wide total. Completing it sets
    `unlocks.hallOfHeroes` for every account; the node turns into the
    **Hall of Heroes** (trophy) and becomes a full-screen location (scene:
    the same scene's "Original Day" video loop over its first frame,
    Czepeku credit) with the Hall list as its card (`EotwRoster.HallPanel`).
    An open Construction swaps to the Hall 4s after completion; on the map
    the node beckons. The town re-lists community projects whenever
    `/city/projectsRev` changes. Wins are recorded into the Hall while it is
    still being built, so it opens with history.
  - **Art UPLOADED 2026-10-22** as core image assets (confirmed under
    `/CoreAssetsCurrent/images`), tagged `czepeku` with
    `CreatorCredit.RegisterArt`: Construction still
    `c9e0c66f-4f10-441d-8acf-3f4bdb17b373` (3840x2160), Hall video
    `7d454b91-a9f0-495a-94e2-8754b33fa619`, its first frame
    `e35b71f8-8fb4-4e4d-ae59-0e9fb3814e72` (1920x1080). Sources:
    `C:/dev/eotw/art/hall-construction-train-station-approach-town-square.jpeg`
    and `hall-of-heroes-train-station-approach-day.webm` (from
    `~/Downloads/Train Station Approach Scenes/` and `~/Downloads/Train
    Station Approach Original Day HD.webm`); the Hall's still is the
    video's first frame (`assets:ExtractVideoFrame`), as for the Market.
  - City: `hall-record` / `list-hall` / `get-hall-entry`, table `city_hall`,
    `/city/hallRev` (see `cloudflare-game-server/CLAUDE.md`). Needs a worker
    deploy before it does anything.

## Locations on the map

Locations are data, not code: one Lua table of `{id, label, x, y, icon,
unlocked(), open()}`, with positions as fractions of the map image so they
survive any re-export size. Adding a location is adding a row. The art
already has natural homes (fractions of the 6160x4480 canvas):

| Location | Where | Notes |
|---|---|---|
| **Town Gate** | the walled city gate, top centre (~0.53, 0.13) | labeled "City Gate" on the source map |
| **Graveyard** | the green churchyard beside the Cathedral (~0.31, 0.85) | |
| **Hall of Heroes** | placeholder (0.33, 0.2), between the Inn and the Gate | BUILT 2026-10-21, not run; spot not yet checked against the art |
| **Hero's Guild** | the small walled green island with a lone building in the canal (0.44, 0.42) | chosen when building (2026-10-02); the Safe House block (~0.54, 0.60) was the alternative |
| **Blue Fish Inn** | the canal-side building west of the Guild (0.235, 0.455); moved 2026-10-11 (user direction) from the "Drunken Fool" tavern (0.335, 0.575), which the hero cards along the bottom covered | BUILT 2026-10-10 (Downtime); hidden until heroes first come home, then revealed once (2026-10-11, see "The inn's reveal") |
| **Arcane Market** | the shop the "Front and Back" label points at (0.695, 0.18) | BUILT 2026-10-10; since 2026-10-11 hidden until the player finds it (see "Leads") |
| later | the Docks, Bora's Wagon Yard, the Cathedral, the Safe House | |

## Decisions taken (2026-10-01, with the user)

1. **The town roster is separate from the titlescreen's heroes.** Town
   heroes are their own pool of 12 living heroes. The titlescreen's 8 campaign
   heroes never see the level-1 clamp, progression or permadeath.
2. **The roster lives in the cloud, per account, and players can see each
   other's heroes**, full sheets included. 2026-10-02: the whole town is one
   **City** Durable Object, and a hero's record uses the same format a game
   stores (see "The City DO").
3. **Death and progression both carry home** from an encounter. What
   "progression" means is its own design pass; see "Progression" below.
4. **The graveyard is shared**: every player's fallen, with the player's own
   marked.

## Viability

**Verdict: viable.** It is now a real backend feature and no longer a
re-skin of the lobby screen:

- **Lua:** the town screen, the Guild, the Gate and the Graveyard, in
  `Codex Titlescreen`.
- **Server:** one **City** Durable Object for the whole town (lobby + every
  account's heroes + the graveyard) -- BUILT 2026-10-02, not deployed.
- **Engine:** two small APIs (export a character as data, import one into the
  current game) and a city route for the C# lobby client, so an engine
  build.
- **Unchanged:** the encounter flow itself.

The open piece is **progression**, which also touches the weekly encounters'
balance. The findings it rests on (2026-10-01):

**The art.**
- The PSD is 6160x4480 (44x32 tiles at 140 px). Its layers separate cleanly:
  - **Remove:** `Grid` and the `Labels` group (its text plus the `Line 1-8`
    arrows). We put our own nodes on top.
  - **Keep:** `Border`, `Compass`, the `Blackbottom` title cartouche, `SEA`,
    and the artist's `mf18-signature` (keep the credit). Everything else is
    the art itself.
- `psd-tools` re-composites it with those layers hidden in about two minutes.
  **It is not faithful enough to ship.** Re-compositing with every layer
  visible and comparing against Photoshop's own embedded composite gives a
  mean difference of about 19/255 per channel, with 24% of pixels off by
  more than 24. The cause is the adjustment layers (Brightness/Contrast,
  Hue/Saturation, Photo Filter, Color Lookup), which `psd-tools` only
  approximates; its output reads slightly washed out. **The final export
  must come from Photoshop** with `Grid` and `Labels` hidden (owner: the
  user, or anyone with Photoshop). The `psd-tools` render is fine for
  placing nodes and for mock-ups.
- **Size: 4096x2980** -- one axis a power of two, the other a multiple of 4,
  per the `map-psd-target-size` rule. Both dimensions being multiples of 4
  gets DXT compression, about 16 MB of VRAM with mips; the full 6160x4480
  would be about 37 MB. At 1920x1080 the map is shown roughly 1920x1400, so
  4096 leaves headroom for 4K screens and a later zoom.
- **Shipping: upload it as a core cloud image asset**
  (`assets:UploadImageAsset{core = true, ...}`, admin only). That is how
  ShopAdmin ships all shop and adventure art. It resolves by GUID at the
  titlescreen with no engine build and no module install, so a constant in
  the titlescreen Lua holds the id.
  - Not a built-in `panels/backgrounds/...` image: those need the scene's
    ImageManager re-imported, which means an engine build.
  - Not module art: module stores are wiped on every game switch.
- **Licence:** this is commissioned MCDM map art (*The Fall of Blackbottom*).
  Confirm it may be shown in the app outside that product. **Owner: the user.**

**Showing it.**
- The map is 1.375:1 and the screen 16:9. Cover the screen (fit the width) and
  let the player **drag to pan** vertically and a little sideways; nodes are
  children of the map panel, so they move with it. Wheel zoom can come later.
- Precedents in the codebase:
  - pinned labels on a map image: `AdventurePage.lua` `MakeMapsSlide` (pins
    as image fractions) and `CoverWindow` (`imageRect` crop by zoom/u/v);
  - drag-pan and cursor-anchored zoom: `CreateMapDialog.lua`'s floor preview.
- The loading veil should also wait for the map image, so the town fades in
  whole.

**The roster today, and what the town needs from it.**
- Titlescreen heroes are characters in the per-machine **local lobby game**
  and are **not synced** anywhere. The **8-hero cap is Lua only**: eight
  hard-coded `MakeHeroPanel` slots and two `>= 8` checks in
  `CodexTitlescreen.lua`, with `LobbyHeroes()` ranking the characters. There
  is no engine limit.
- **The character builder only edits a character in the current game**, and
  at the titlescreen that is the lobby game. So whatever stores the roster,
  a hero must exist as a lobby-game character while it is being built or
  edited. Town heroes are mirrored as lobby characters tagged
  `properties.eotwCity = {heroid, rev}`, and `LobbyHeroes()` must skip them
  so they never take one of the titlescreen's 8 slots.
- **Create** reuses `CreateHero`/`EditHero` (`game.CreateCharacter` + the
  sheet, with a one-shot `characterSheetClosed` handler, and an unstarted
  shell deleted on close). They are file-local in `CodexTitlescreen.lua`
  today and have to be exported (e.g. `CodexTitlescreen.CreateHero{onDone}`).
  The town hides itself while the sheet is up.
- **Recruit:** copy the module's detached pregen token
  (`dmhub.CopyTokenToClipboard` works on a detached token's `charInfo`) and
  paste it into the lobby game (`PasteTokenFromClipboard`: fresh charid, the
  clipboard's image records uploaded -- so the pregen art must be registered
  first, `EnsurePregenArt`). Then set `token.name` + `UploadToken`, and push
  it to the city. With the engine import API below, recruiting becomes
  "export the pregen, import it under a new name".
- **There is no Lua API today to turn a character into data or back**
  (checked 2026-10-01: nothing in `LuaInterface.cs`;
  `ImportFramework.ImportCharacter` takes a token, not data). The clipboard
  code (`CharacterTokenClipboard`, `GameController.CopyCharacters` /
  `PasteCharacters`) already builds and consumes exactly the payload needed
  -- character JSON plus the image and audio asset records it references --
  so exposing it is small engine work. See the City DO.

**The gate and the encounter flow** are today's code with a new frame:
- `BuildGameView`, `ShowCreateDialog` and `ShowAddHeroDialog` are closures
  inside `CreateScreen`. They already float as modals over `resultPanel`, so
  the cheapest path is to make **the town panel the new `resultPanel`**
  (replace the content column) and open those modals from the gate node.
  Lifting them out into a context table is the cleaner but larger refactor.
- Heroes still come from the player's own working copies, so the lobby
  server's hero records need no change; the pregen claim path (and the
  picker's pregen section) goes away.
- The games list splits into the two lists by `status`: `open` = forming,
  `launched`/`ready` = underway.

**Coming home: death and progression write-back.**
- Today nothing flows from an EotW game back to a lobby hero, by design:
  `DetachFromLobbySync` cuts the char-cache sync so combat damage and the
  level-1 clamp do not leak home. The town replaces that sync with an
  explicit, rule-driven write-back to the city.
- The mapping already exists:
  `eotwstate.placedHeroes[userid]["lobby:<rosterid>"] = <copy charid>`.
- At the conclusion, before the client leaves the game, each owning client
  reads its copies' final state:
  - dead or alive -- true death, `IsDead()`, the state the Hero Death rule
    acts on. Re-check at the conclusion, so a hero revived mid-fight is not
    buried;
  - and whatever the progression rules count.

  It writes the outcome to a **machine-local preference** first (the
  `eotw:concludedgame` trick, so it survives the game switch and a crash),
  then applies it once back in town: update the working copy, push it to the
  city with `put-hero`, and send `record-outcome` (`died` digs the grave).
- **Idempotent per game**: the city keeps an outcome log keyed by
  `(heroid, gameid)`, so a resend never applies twice.
- A client that crashes mid-fight and never reaches the conclusion has no
  final state to read. **Decision needed**: does the hero count as
  surviving, or is the last observed state recorded on every change?

**The bottom hero cards.**
- The montage card (`EncounterOfTheWeekHud.CreateHeroCard`) is **game-only**.
  It lives in the game-side mod, which does not load at the titlescreen, and
  it reads live map tokens.
- The titlescreen has its own card (`MakeCardPanel`/`MakeHeroCard`).
- The plan: lift the card's *look* into a builder that takes a character
  record rather than a map token (the lobby game exposes characters through
  `dmhub.GetCharacterById`), shared by both mods; or extend `MakeCardPanel`
  to the montage card's look. Either way it is a refactor, not new
  capability.

**Risks.**
- **Progression vs the weekly balance** (below). This is the largest design
  risk.
- **Art licensing** (owner: the user).
- **Engine-build dependency:** the export/import API and the city route must
  ship in a build before the town works.
- **Working-copy consistency:** a hero edited on two machines at once.
  Mitigated by revision checks, described below.
- **Trust:** outcomes and edits are self-reported by the owner's client. That
  is consistent with the existing stance (cheating through Lua is not a threat
  model here), but it does make a shared graveyard and visible heroes
  spoofable. A server-authoritative path (the EotW game's DO reports
  outcomes) is possible later.

## The City DO: storage infrastructure (DECIDED 2026-10-02; server BUILT and DEPLOYED to staging)

**Decided with the user (2026-10-02).** The whole town is **one Durable
Object, a "City"**: the lobby (presence, chat, parties) plus every account's
heroes and the graveyard, in one SQLite database. It may hold other city
data later; heroes are the starting point.
- Anyone may see anyone's **full** hero sheet.
- A hero's stored record is **the same format a regular game stores**, so a
  hero can move between a game and the city unchanged.

This replaces the per-account "Hero Vault" DO proposed on 2026-10-01.

**Why one DO works.**
- **Storage:** a SQLite DO holds 10 GB, with values up to 2 MB. A hero is
  about 10 KB at rest (the gzipped record plus its summary and asset
  records), so roughly a million heroes fit.
- **Memory** is the constraint. Hero data therefore lives in SQL tables read
  by indexed query on demand, never in memory or in the subscribed document,
  and memory scales with who is online.
- **Throughput** has a soft limit of 1,000 requests/s on one thread. Hero
  traffic is light: one query to open the town, one write per sheet close.
  Broadcasts are kept small.
- **The win:** party membership, hero ownership, "away" status, death and
  the graveyard are all checked and changed **atomically on the server**.
- **Escape hatch:** everything is keyed by (userid, heroid), so rosters can
  later move to DOs sharded by user id, or blobs to R2, without a protocol
  change.

**As built** (`cloudflare-game-server`: `src/city.ts`, `src/city-core.ts`;
route `/city/{cityid}`, binding `CITY`, migration `v4` in both wrangler
configs; city id for the town: `blackbottom`):
- `CityObject` **extends `LobbyObject`** through protected hooks, so a city
  keeps every lobby action (chat, presence, create/join/launch/ready, ...).
  The plain `eotw` lobby is unchanged; its only change is that hero `kind`
  also accepts `"roster"`.
- **Tables:**
  - `city_heroes(userid, heroid, rev, status, active, summary, record BLOB,
    assets BLOB, created, updated, fallenAt)`, with the primary key
    (userid, heroid);
  - `city_accounts(userid, rosterRev)`;
  - `city_outcomes` (primary key userid, heroid, gameid);
  - `city_graves` (time-sortable id);
  - `city_meta`.
- **Record format:** the character JSON as a game stores it at
  `/characters/{charid}`, run through the game server's own normalization
  (arrays become numeric-keyed objects, slash keys are unfolded). The
  `assets` bundle is `{images: {id: record}, audio: {...}}`. Both are stored
  with the game server's value encoding (1-byte header, gzip at or above
  2 KB).
- **Actions** (the lobby's `{type:"request"}` envelope; results in the
  `ack`):

  | Action | Who | What |
  |---|---|---|
  | `list-heroes {userid?, includeFallen?}` | anyone | an account's roster as summaries + `rosterRev` (no records); each hero carries `completed`, the encounters (map names) it has won |
  | `get-hero {userid?, heroid}` | anyone | one hero: summary, status, full record, assets |
  | `put-hero {heroid, baseRev, summary, record, assets?}` | owner | `baseRev` 0 creates (12 living max); otherwise must equal the stored `rev` (conflict -> reload and retry). A fallen hero cannot be changed |
  | `delete-hero {heroid}` | owner | dismiss; refused while the hero is in a party |
  | `set-active {heroids}` | owner | replace the active set (max 4, living, own) |
  | `record-outcome {heroid, gameid, outcome, died?}` | owner | append to the hero's adventure log, idempotent per (hero, game). `died` sets the hero fallen and inactive and digs a grave whose epitaph comes from the summary + `outcome.encounter` + owner name. `outcome.completed` (with `outcome.encounter`, not dying) records that the hero won that encounter (`city_completions`) |
  | `list-outcomes {userid?, heroid}` | anyone | the hero's adventure log |
  | `list-graveyard {before?, limit?}` | anyone | graves newest first, paged (50 default, 100 max), `more` flag |
  | `town-heroes {}` | anyone | the active heroes of everyone currently present |
- **Parties take roster heroes only.** In a city, `join-game`/`set-heroes`
  accept only the caller's own living heroes as `{kind: "roster", id:
  heroid}`, none already claimed by another party. "Away" is derived from
  the game records, never stored. The party's display copies are rewritten
  from the stored summary, so a client cannot misrepresent a hero; a hero
  that already won the game record's `encounter` gets `completed: true`.
- **Change signals in the subscribed document:** each presence entry carries
  `rosterRev` (a roster change re-broadcasts that one entry), and
  `/city/graveyardRev` is pushed on each new grave. Clients re-query on a
  change; no hero data is ever broadcast.
- **Limits:**
  - record 1 MB, assets 256 KB, summary 4 KB, outcome 16 KB;
  - inbound frames 1.5 MB (a plain lobby keeps 16 KB);
  - hero writes share a 20-token bucket per account, refilling one token
    every 3 s.
- **Backup:** `GET /admin/city/{cityid}/export?after={userid}&limit=N` with
  `X-Admin-Secret` pages every account's heroes with full records. Cloudflare
  point-in-time recovery also covers the DO's SQLite.
- **Verified 2026-10-02:**
  - unit tests `test/city-core.test.ts` (24 new; the suite is 304/304, tsc
    clean);
  - `test/city-smoke.ts` **all 34 checks passed** against
    `wrangler dev --env staging`: a ~24 KB record round trip in game-store
    shape read by another user, revision conflicts, the active set,
    town-heroes, party claims (stranger's / non-roster / away heroes refused,
    stored name shown), death -> graveyard + push + idempotent resend, lobby
    chat, no hero data in the debug doc;
  - the existing `lobby-smoke.ts` still passes;
  - data and the admin export survived a server restart.
- **Deployed to staging 2026-10-02** (`game-server-staging`, version
  `a867550f-f20c-4d8a-8944-5a54415ea2ca`): `test/city-smoke.ts` passed all
  34 checks against it, and `lobby-smoke.ts` still passes there. Release is
  NOT deployed. The `wrangler.dmhub.toml` white-label config has the same
  binding and migration but was not deployed.

- **`get-hero {asJson: true}`** (added 2026-10-02, deployed to staging as
  version `22189dfe`) returns `record` and `assets` as JSON **text**, and
  `put-hero` accepts them as text. The client passes the text straight
  between `dmhub.ExportCharacter`/`ImportCharacter` and the server, so a
  character never round-trips through Lua tables (which would turn empty
  objects into lists and lose key types). Unit test + a `city-smoke.ts`
  section cover it.

**The client half (BUILT 2026-10-02).**
- **Route option:** `lobbies:Connect(id, {staging=true, route="city"})`
  reaches `/city/{id}`. `LobbyConnection.cs` keys connections by route +
  id + staging; `LobbiesLua.cs` accepts `"lobby"` (default) or `"city"`. An
  empty `args = {}` is sent as `{}` (an empty Lua table serializes as `[]`,
  which the server rejects).
- **Character data APIs** (`LuaInterface.cs`, `GameController.cs`):
  - `dmhub.ExportCharacter(token)` -> `{record, assets}`, both JSON text.
    `assets` is `{images, audio}`: the records the character's appearances
    reference (`CollectCharacterAssets`, shared with `CopyCharacters`).
  - `dmhub.ImportCharacter{record, assets, charid?, name?}` -> charid. It
    normalizes the stored shape (strips the store's meta keys), PUTs
    `/characters/{charid}` in the current game, and uploads the asset
    records the game lacks. It returns nil (and logs) if the record cannot
    be read or the game's assets have not loaded yet. The character resolves
    by id once the write echoes back, like a paste.
- **Other players' heroes** reach the town by `town-heroes` and
  `list-heroes`. Inspecting a sheet is one `get-hero`, imported as a
  read-only working copy (or shown through a detached sheet, engine support
  to confirm). Shipping the asset records with each hero is what lets other
  players' portraits resolve.
- **Into an encounter:** unchanged at first -- the owner pastes their working
  copy on arrival. Later the host could fetch every party hero from the city
  directly.

**Alternatives considered and rejected:**
- per-account Hero Vault DOs (the 2026-10-01 proposal), which lose the
  atomic party/roster checks;
- Firebase RTDB, with per-download billing;
- a per-account DO-backed "hero game" that the titlescreen would enter to
  edit heroes;
- moving the lobby game back to a DO.

## The town client (BUILT 2026-10-02; single-client verified)

The EotW screen **is** the town now: `CreateScreen` in
`Codex Titlescreen/EncounterOfTheWeek.lua` builds it, and it connects to the
City (`LOBBY_ID = EotwRoster.CITY_ID = "blackbottom"`,
`LOBBY_OPTIONS = {staging=true, route="city"}`) instead of the old `eotw`
lobby. The game side (`EncounterOfTheWeek/EncounterOfTheWeek.lua`) sends its
lobby requests to the same city.

**Files (all core codex, Codex Titlescreen codemod, registered in this
order before `EncounterOfTheWeek.lua`):**
- `EotwHeroCard.lua` (NEW): the hero card, moved verbatim out of
  `EncounterOfTheWeekHud.lua` so the titlescreen can use it. Global
  `EotwHeroCard` = `CreateHeroCard`, `CreateStaminaBar`, `CreateCardFlash`,
  `CollectHeroes`, `RosterSignature`, `HeroDisplayName`, `rules`,
  `CARD_WIDTH`, `CARD_HEIGHT`. New option `subtitle = function(tok)` for the
  line under the name. The HUD now aliases these.
- `EotwRoster.lua` (NEW): roster sync + the Guild and Graveyard UI. Global
  `EotwRoster`.
- `EncounterOfTheWeek.lua`: the town screen (map, nodes, hero strip, gate,
  chat drawer, plaque).
- `CodexTitlescreen.lua`: global `TitlescreenHeroes = {Create(onCreated),
  Edit(character, onClosed)}` exposes the titlescreen's own builder flow;
  `LobbyHeroes()` skips characters with `properties.eotwHero`, so town
  heroes never show among the titlescreen's campaign heroes.

**The map.** `CITY_MAP_IMAGE = "39beb163-c5b5-408d-be3c-191825776239"`, a
**placeholder**: a psd-tools render of the PSD with `Grid` + `Labels`
hidden, 4096x2980, uploaded as a core image asset. Swap in a Photoshop export
later by uploading it and changing the constant. The map covers the screen
and pans by dragging (`draggable`, `dragMove = false`, `dragDelta`); the
nodes ride on a separate layer moved in step. Two traps found building it:
- a `clip = true` panel whose own `bgcolor` is `"clear"` draws **none** of
  its children (they still hit-test), so the viewport is black;
- a panel whose cloud image id was not yet in the loaded asset records
  (built at startup, or during a codemod reload) fell back to a white square
  for good. Fixed in the engine 2026-10-02: `ImageDownloader` now leaves a
  pending downloader that re-resolves the id once its record arrives (NEEDS
  BUILD). A `GetImageDimensionsCallback` re-assign does NOT work around it:
  the dimensions come from the record, so the callback can fire too early.

Near-opaque fills like `#14110df8` also render visibly translucent over the
map, so every panel over it is fully opaque (`ff`).

**Locations** (`CITY_LOCATIONS`, fractions of the map image):
- **Hero's Guild** (0.44, 0.42), the walled canal island; `phosphor/shield-star-fill.png`.
- **Town Gate** (0.53, 0.135); `sword-fill`. Locked until the roster has
  been listed and holds at least one living hero.
- **Graveyard** (0.31, 0.86); `hands-praying-fill`.

**Working copies.** A town hero is a character in the per-player **lobby
game** whose charid **is** its city heroid, tagged `properties.eotwHero`.
The character builder only edits characters in the current game, which is
why heroes are copied there. The machine-local preference `eotw:heroRevs`
(`{userid: {heroid: rev}}`, JSON) records which city revision each copy
holds.
- `Refresh` (on connect, on `/`, and when our presence entry changes, since
  it carries `rosterRev`) does `list-heroes`, then `SyncWorkingCopies`. That
  waits for the lobby game to finish loading (`gameLoadingProgress == 1`,
  else the importer fails), then:
  - imports any listed hero that is missing or at another revision
    (`get-hero asJson` -> `ImportCharacter{charid = heroid}`);
  - deletes copies of heroes the city no longer lists;
  - pushes copies that never reached the city.
- `PushHero` = `ExportCharacter` -> `put-hero` with `baseRev` from the
  revision map. A stale revision re-lists and reloads the city's copy.
- `JoinRoster` (Create and Recruit) stamps `eotwHero`, puts the copy in the
  lobby's player party, and pushes. If the city refuses the push (the roster
  is full), the local copy is deleted.
- **Recruit**: export the pregen token -> `ImportCharacter{name}` ->
  `JoinRoster`. **Recruit a titlescreen hero**
  (`EotwRoster.RecruitTitlescreenHero(source, name)`, BUILT and verified
  live 2026-10-09): the same export/import of the lobby character, then one
  `ModifyProperties` on the copy before `JoinRoster` stamps
  `eotwSourceId` = the original's charid, re-points `originalid` at the
  copy (so the lobby char-cache sync can never save the stripped copy over
  the original), sets every class entry to level 1 and `levelOverride` to 1
  (as the game's `NormalizeHeroLevel` does), and empties `inventory`,
  `equipment` and `equipmentMeta`. `currency`, Victories, damage taken and
  conditions are copied as they are (not decided; see below).
  `EotwRoster.FindCopyOf(charid)` finds the living copy that blocks a second
  pick. The list comes from the NEW `TitlescreenHeroes.List()` in
  `CodexTitlescreen.lua`: the first 8 of `LobbyHeroes()` (the HEROES slots),
  minus `HeroIsUnstarted` shells. **Create**: `TitlescreenHeroes.Create`, then `JoinRoster`
  if the builder kept the hero. **Edit**: `TitlescreenHeroes.Edit`, then
  push on close.

**The screen.**
- **Plaque** (top left): "Blackbottom", the adventurer count from presence,
  and the connection status.
- **Hero strip** (bottom): one `EotwHeroCard` per active hero, with its
  subtitle "Level N Ancestry Class". It shows characteristics, stamina and
  recoveries (`showStats`), but no skills line or heroic resource row
  (`showSkills = false`, `showResources = false`; user direction
  2026-10-02). Clicking a card opens
  the sheet. With no active hero it shows a hint plaque instead.
- **Locations take over the screen** (user direction 2026-10-03). Opening
  the Hero's Guild or the Town Gate replaces the Blackbottom map with a
  full-screen scene: Czepeku Scenes art, a header at the top left (Back to
  Town, a "BLACKBOTTOM" overline, the place's name in the display face over
  a gold rule, a line of flavor), a translucent card on the right holding
  the location's controls, and the Czepeku logo in the bottom-right corner.
  The map, plaque and hero strip collapse while a scene is up; the Town
  Chat button moves left of the logo.
  - **Art.** Guild = *Viking Longhouse, Original Day*; Gate = *Market
    Streets, Original Day*. The user asked for the "Original Day video", but
    both downloaded zips (`~/Downloads/Market Streets Scenes.zip`,
    `Viking Longhouse Scenes.zip`) hold only 3840x2160 JPEG stills, so the
    stills ship for now (user's call). They are core image assets
    `GUILD_ART` `db897e57-...` and `GATE_ART` `db5bcf88-...` in
    `Codex Titlescreen/EncounterOfTheWeek.lua`; the source files sit in
    `C:/dev/eotw/art/`. **To switch to video:** upload the mp4/webm as a
    core asset and pass it as the scene's `video` (the still stays as the
    poster under it) -- `CreatorCredit.Backdrop` already layers a video over
    the still, but that path has not been run with a real video.
  - **Data.** A location row's `scene = {art, aspect, focusX, title,
    tagline}` in `CITY_LOCATIONS`; `LocationScene(loc, cardWidth, content)`
    builds it. The Gate's scene is built once and kept (collapsed when
    closed), because `RefreshGames` is what notices a launched game and
    takes the player into it, so the games list must stay alive; the Guild's
    is built on each visit. Opening the Gate also re-runs
    `RefreshResumeState`: the lookup made when the screen is built at boot
    can come back empty, which used to hide the "Your game in progress" row
    until the screen was reopened.
  - The Gate card is 1000 wide over the parties list (the tower stays
    clear) and widens to 1240 in a party view so six hero cards fit one row
    (`SetGateCardWidth`). The party view at 1240 has NOT been seen live:
    forming a party would delete the account's existing staging game.
  - The Graveyard is still a dialog over the map (no art chosen for it).
- **Guild**: a stacked list, up to 12 rows. Each row has a portrait,
  details, a star (active, max 4), a pencil (edit) and a trash can (dismiss,
  with a confirm). Above it "Your Roster" with the counts; below it Create a
  Hero and Recruit a Hero. The recruit picker has two sections: **Your
  Heroes** (the titlescreen heroes; hidden when there are none) and
  **Adventurers for Hire** (the week's pregens). Picking one opens a name
  prompt: a pregen's is prefilled with a rolled name, a titlescreen hero's
  with its own name, and the reroll button rolls from the ancestry's name
  table for both. The picker mounts on the town screen, outside the Guild
  list that carries `GUILD_STYLES`, so its card styles live in their own
  `PICKER_STYLES` (before 2026-10-09 the cards had no background or hover
  at all for that reason). `EotwRoster.GuildPanel(host)` returns
  the card's body (it was the `ShowGuild` dialog).
- **Gate**: since 2026-10-06 a "This Week's Encounter" banner (title,
  creator credit, the `# Town Gate` blurb), then "Parties Forming" and
  "Encounters Underway" for Gate parties; Form a Party (this week's) and
  Past Encounters along the bottom. The Proving Pits are a second board of
  the same kind; see "The Encounter of the Week and the Proving Pits". The add-hero picker lists your living roster heroes that are
  neither claimed nor away, active ones first, as `{kind = "roster"}`.
  - **Active heroes join by default** (user direction 2026-10-03). Forming a
    party, or joining one, sends a `set-heroes` with your active heroes right
    after the `join-game` succeeds (`ClaimActiveHeroes`): as many as fit the
    open slots and the per-player cap of 4, in roster order, skipping heroes
    claimed by another party except the one being left (its `leave-game`
    goes out first and the City handles requests in order). It runs only
    while you hold no heroes in that party, and a refusal is logged, not
    shown, since the party is joined either way. Joining as well as forming
    was a judgment call: the user asked about "starting" a game.
  - **Other players' portraits.** A roster hero exists as a working copy
    only in its owner's lobby game, so another machine had nothing to read
    the portrait from (its image records live in the owner's game, and the
    party record carries only display text). Now the first time a party
    card needs another player's roster hero, `ResolveHeroToken` sends
    `get-hero {userid, heroid, asJson}` and hands the record + assets to
    the engine's **`dmhub.CreateDetachedCharacter{record, assets}`** (NEW,
    NEEDS BUILD). That returns a detached token (like the pregen snapshot's)
    and registers the hero's image records as session extras
    (`ImageDownloader.AddExtraImageAsset`), so they render in the lobby game
    without being uploaded into it. Tokens are cached per screen in
    `m_remoteHeroTokens` (`false` while pending or after a failure, so each
    hero is asked for once); the view rebuilds when one lands. The card
    skips its `IsUnresolvableAssetId` check for these (`artRegistered`),
    because that check reads `assets.allAssets`, which does not list
    session extras. A hero is not editable while in a party, so the cache
    does not go stale. The same call can back the read-only sheet of
    another player's hero and `town-heroes` later.
- **Graveyard**: everyone's graves, paged, with your own highlighted.
- **Town Chat**: a drawer toggled from the bottom-right button.
- **Escape** closes the chat drawer, then an open location, then the
  screen. That only became true 2026-10-03: before, the top-right
  `gui.CloseButton` took Escape at `EXIT_DIALOG` (14) and closed the whole
  town from anywhere, including from inside the Gate, the Guild's dialogs
  and the hero builder. Now the close button has `escapeActivates = false`,
  the screen's handler is at priority 4 (above the titlescreen's 3, below
  the builder's 5), and the town's dialogs (`ModalFrame`, Form a Party,
  Add a Hero) are at `EXIT_MODAL_DIALOG`. Verified live: Gate -> map,
  recruit picker -> Guild -> map.

**Creator credits** (2026-10-03; general mechanism, user direction). Art by
outside creators carries the creator's logo, via the NEW core file
`DMHub Core UI/CreatorCredit.lua` (global `CreatorCredit`, registered in the
DMHub Core UI codemod after `GuiUtils`, Firebase confirmed):
- `CreatorCredit.Register(id, {name, logo, logoWidth, logoHeight, url})`
  adds a creator. The list lives at the bottom of that file. Logos are core
  image assets, light on transparent.
- `CreatorCredit.RegisterArt(imageid, id)` tags a piece of art, so a
  backdrop of it finds its credit without being told.
- **Scene "Art by"** (2026-10-04, user direction: per scene object, badge on
  the montage stage, the narrative stage and the Director's full-screen
  scenes). A `[[scene]]` tag's `RichScene.credit` (creator id or false) is set
  from the settings button on its editor in the journal (dropdown from
  `CreatorCredit.DropdownOptions()`). `EncounterMontage.SceneImage` calls
  `CreatorCredit.TagSceneArt(image, tag:GetCredit())` as it resolves a scene,
  and `ForArt` checks `art` then `sceneArt`. The stages' backdrops carry a
  sibling credit holder (`CreateCreditHolder` / `CreditOf` in
  `EncounterMontageStage.lua`, refreshed by `SetBackdropScene`), and
  `FullscreenDisplay` badges `doc.data.coverartCredit` (written by the
  scene's Show control; Game Controls' cover-art picker clears it). Set on
  The Dwarvish Bandits (all four scenes) and Goblin Ambush (all three);
  verified on screen in both authoring games.
- `CreatorCredit.Badge{creator, width?, halign?, valign?, hmargin?,
  vmargin?}` is the logo as a floating badge, bottom-right by default. Hover
  shows "Art by <name>" and the site; click opens the url through
  `dmhub.OpenURL`.
- `CreatorCredit.Backdrop{width, height, image, video?, aspect?, focusX?,
  focusY?, creator?, badge?, children}` is a full-bleed, cover-fitted art
  panel on black. It fades in when the image loads, has a soft shade in the
  bottom-right corner under the badge, and draws the badge.
  `CreatorCredit.ReplayFade(panel)` replays the fade for a backdrop that is
  kept and re-shown.
- Registered: `czepeku` = "Czepeku Scenes", logo `4e3b9a3b-...` (242x79,
  made from the user's `~/Downloads/czepeku-scenes.png` by turning black
  into transparency; source in `C:/dev/eotw/art/czepeku-scenes-logo.png`),
  url https://czepeku.com.
- Possible later: take a creator's logo and url from their creator
  organization's branding (`/ModuleAuthor/{orgid}`) instead of the file.

**Verified live, one client, 2026-10-02:**
- the map, panning, nodes and the plaque;
- the Gate locked with no heroes;
- Guild: Recruit end to end (Dwarf Fury -> "Thorga Ironhand" on the
  server, rev 1), the star (active) toggling, the strip card appearing, and
  the Gate unlocking;
- the edit round trip: the sheet opens on the imported copy, and the push
  after it reached rev 2, once the revision-map bug was fixed;
- the Gate panel and the Form a Party dialog open;
- the Graveyard opens on its empty state.

**Not yet verified:**
- Create driven through the builder to a kept hero;
- forming a party and the roster add-hero picker. Forming would have deleted
  the account's existing staging EotW game ("Denivarius's Game"), so it was
  not done;
- Begin -> encounter with roster heroes;
- dismiss;
- a second machine importing the roster;
- the sync moving an existing copy into the lobby's player party. The last
  edit added it, and it has not run since a restart. The mechanism
  (`partyId` + `UploadToken`) was checked by hand, and Thorga now shows
  "Players".

Verified after the final engine build: the town opened right at boot waits
for the lobby game (no import errors), then the hero card appears. The Guild
panel is opaque.

## Progression (OPEN -- needs its own design pass)

The user wants progression to carry home. That collides with how the weekly
encounter is built today: **every hero is forced to exactly level 1 on
arrival** (`NormalizeHeroLevel`), and the week is balanced for a level-1
party, scaling only by hero *count*. Options to weigh:

- **Draw Steel-native levelling**: Victories per encounter, XP at respite,
  level-ups. Then the weekly content has to meet levelled parties, either
  through **level bands** (several `Encounter: <title>` maps per week, each
  for a band, with the create dialog filtering by the party's level) or
  through **scaling the encounter by party level** (the encounter budget;
  today's scaling is by hero count only). Either way the level-1 clamp goes,
  or becomes a clamp to the band.
- **Progression without levels**: heroes keep **treasure** (the montage haul
  and delve chests are already concrete items), **titles/renown**, a record
  of encounters survived, and town unlocks. The weekly balance is untouched.
- A mix: items and renown now, levels later with bands.

**First piece designed 2026-10-10:** wounds carried home, Victories to XP at
a respite at the Blue Fish Inn, Downtime Activities and projects, with heroes
still level 1 in encounters. See "Downtime: wounds, the Blue Fish Inn,
respite and projects".

Recommendation: record a full **outcome log from day one** (encounter, result,
victories, items gained, death) in the city (`record-outcome`), whatever is decided, so later
progression rules can be applied after the fact. Run the design with the
`feature-design` skill before Phase 11.

## Other open decisions (recommended default first)

5. **Active heroes and the gate.** DECIDED 2026-10-03: forming or joining a
   party claims the active heroes automatically, as space allows (see "The
   town client", Gate); the picker still offers the whole living roster.
   Picking a hero for a party does not change the active set.
6. **The town's social layer.** Built as recommended, minus the other
   players' heroes: the plaque says "N adventurers in town", and the lobby
   chat is a drawer. Showing who is present with their active heroes
   (`town-heroes`) is still to do.
7. ~~Hero's Guild location~~ taken as the canal island (see the table above).
8. **Smaller defaults**, taken unless overruled:
   - Dismissing a hero deletes it (from the city and the working copy) after
     a two-click confirm.
   - A hero in a forming or underway party shows "Away: <party>" and cannot
     be dismissed or edited.
   - The Town Gate unlocks with one living hero.
   - The recruit name prompt allows any non-empty name of up to 60
     characters.
   - Titlescreen campaign heroes cannot be copied into the town roster.

## Spikes before building

1. **Character data round trip** (engine): BUILT and used by Recruit (a
   pregen export is ~13 KB record + ~1.3 KB assets). Still owed: a hero with
   a custom (uploaded) portrait imported on a second machine.
2. **Builder round-trip from a new screen:** BUILT as `TitlescreenHeroes`
   (see "The town client"). Opening and closing works; a builder session
   that produces a kept hero has not been driven to the end.
3. **Final-state read:** in an EotW game, kill a hero, end the fight, and read
   each placed copy's final state (dead, victories, inventory) from the owning
   client before it leaves. Confirm the placed-hero mapping resolves the
   roster id.
4. ~~City DO skeleton~~ DONE 2026-10-02 (deployed to staging, smoke-tested
   there).

---

# The Encounter of the Week and the Proving Pits (BUILT 2026-10-06; town side verified)

User direction (2026-10-06): at any time there is ONE specific encounter that
is **the** Encounter of the Week. It stays so until it is rotated by hand
(a script or a Claude skill). The Town Gate describes it from its published
blurb and parties form for it; a **Past Encounters** option offers the
earlier ones, but this week's is the default and focus. User-made encounters
never appear at the Gate: they play in a new town location, the **Danger
Rooms** -- experimental, no Victories, no treasure, nothing durable, otherwise
a normal encounter (a practice ground). After a Proving Pits game each player
can up- or downvote it and write feedback for its creator (a nomination for
next week was dropped 2026-10-18); the team assesses that weekly and picks
the next one. The Proving Pits are locked until the player
first defeats the Encounter of the Week, then open for good. The background
is the cover side of the Draw Steel: Monsters cover PSD. Goblin Ambush is the
first Encounter of the Week; Angry Dwarves is retired.

## The schedule

- The City stores `{week, current, past, since}` (`city_settings` row
  `week`), encounter KEYS as everywhere else (`Encounter: Goblin Ambush`;
  `<moduleid>|<map name>` for a community map). It rides the subscribed
  lobby document as **`/city/week`**, so a rotation reaches every open town
  at once (the town's monitor re-renders on `/city/week`).
- **`set-week {current, past?}`** (city admins only): without `past` it
  rotates -- the old current becomes the newest past, the week number goes
  up, `since` is stamped (the same current again is a no-op); with `past` it
  replaces the schedule (repairs). Admins = the userids in the worker env
  `CITY_ADMINS` (wrangler.toml, both environments; David's
  `4V4KWXdW7ScFIiEyuknO4bqmQSc2`). On staging `ALLOW_UNAUTHENTICATED_DEV`
  makes userids self-reported, so there the gate is a courtesy.
- **Rotating** (any one of):
  - the admin's Codex menu -> **Encounter of the Week...** (town open):
    every pool encounter except the current, best net vote first, with
    votes, plays and all feedback, each with "Make Encounter of the Week"
    (second click confirms);
  - Lua, anywhere (titlescreen or a game; over MCP):
    `EncounterOfTheWeek.SetWeek(key, cb)` / `EncounterOfTheWeek.DangerReport(cb)`
    (`CityRequest` uses the town's connection, else a short-lived one);
  - the skill **`/eotw-rotate`** (`.claude/skills/eotw-rotate/`): reads the
    report over MCP, summarizes it, and rotates only after the user picks;
  - `python tools/eotw_week.py report|rotate <key>|set <key> --past "a;b"`
    over **`/admin/city/blackbottom/week`** (GET = report, POST = set-week),
    which needs the worker's `ADMIN_SECRET` (not on this machine as of
    2026-10-06).
- **Which board an encounter belongs to** (`IsScheduledEncounter`,
  `IsDangerRoomEncounter`): scheduled (current or past) -> the Gate; a
  community encounter never scheduled -> the Proving Pits; an official
  module map never scheduled -> nowhere (this is how Angry Dwarves is
  retired; it can still be scheduled again). A community encounter that
  becomes the Encounter of the Week moves to the Gate; no Victory was ever
  recorded for it in the Proving Pits, so heroes can still earn it.
- **Seeding:** the schedule starts empty, and the Gate then says the guild
  has not posted this week's encounter. After the City deploy, an admin runs
  `EncounterOfTheWeek.SetWeek("Encounter: Goblin Ambush")` once.

## The Town Gate

- The board opens with a **"This Week's Encounter"** banner: the title (the
  pool entry's, so the module record must be loaded), the creator credit for
  a community encounter, and the `# Town Gate` blurb, which reaches the town
  through the module record (`publishingProperties.eotwEncounters`, written
  by the publisher / ModShare) -- a script edit shows only after a publish.
- Then "Parties Forming" / "Encounters Underway" for Gate parties only.
- Bottom: **Form a Party** (this week's; an error line if none is posted)
  and **Past Encounters** (a dialog of every past encounter, newest first,
  with title, credit, blurb and its own Form a Party). Past encounters award
  the Victory as before (once per hero per key).
- **Form a Party** no longer has an encounter dropdown: `ShowCreateDialog(key)`
  shows where the party is going (title, credit, blurb, and for a Danger
  Room the practice note). The key rides `create-game` as before.

## The Proving Pits

- **Location** `danger` (`CITY_LOCATIONS`): "Proving Pits",
  `phosphor/skull-fill.png`, at (0.74, 0.42) on the map, level with the
  Guild (at the first try, (0.6, 0.56), the hero cards along the bottom
  covered it). Locked with "Defeat the Encounter of the Week to unlock the
  Proving Pits." until `EotwRoster.DangerRoomsUnlocked()`, and like the Gate
  it needs a living hero.
- **Unlock.** `list-heroes` now returns `unlocks = {dangerRooms}`: true once
  any of the account's heroes has a completion of a scheduled encounter
  (current or past). Completions are never deleted (a dismissed hero keeps
  them) and the schedule only grows on rotation, so it never re-locks.
  Judgment calls (not asked): a past Encounter of the Week counts, not only
  the current one (it also makes a win near a rotation count); it is
  derived, not stored, so it is retroactive; and since completions are
  written only for heroes alive at the end, a player whose every hero died
  in a winning party does not unlock it.
- **Scene**: core image `92f3f806-327b-498c-9705-49972311c3e3`, the front
  cover of Draw Steel: Monsters rendered from
  `~/Downloads/Steel Draw monsters cover.psd` with the `text` group, spine
  group, text shadow (`Layer 16`) and guides hidden (Background + Final
  Cover + bleed `Layer 15`), cropped at x 7073..13627 (the front cover), then
  a 16:9 band (y 1900..5586) scaled to 3840x2160 around the beholder. Sources
  in `C:/dev/eotw/art/` (`danger-rooms-monsters-cover-front.png` full
  front, `danger-rooms-scene-3840x2160.jpg`). MCDM's own art: no creator
  badge. The card is 900 wide (the Gate's 1000) to keep the monster clear.
- **Board** (`PartyBoard("danger")`): the practice note, the resume row,
  Proving Pits parties forming / underway, then **Encounters to Try**: one
  row per Proving Pits encounter (title, "<module> by <author>", "N up, M
  down -- played P times", the blurb, Form a
  Party). Votes come from `danger-stats` when the location opens.
- **Feedback on Your Encounters** (bottom button, shown when the pool holds
  a module this account published -- `ourModule`): votes and every
  feedback line per encounter, newest first (`danger-feedback-for`). The
  server cannot check who made a module, so the feedback is not private;
  the client only asks for its own.
- **Both boards are built once and kept** (the Gate was already, because
  `RefreshGames` must stay live to notice a launched game); `RefreshGames`
  renders each board, and a party view renders on its party's board (by
  `PartyMode(record)`) while the other board keeps its lists. Errors show
  on both boards.

## Practice games (game side)

- `EnterWorld` adds `practice = IsDangerRoomEncounter(key)` to the arrival;
  the host stamps `eotwstate.practice = true` at setup (`RecordPracticeMode`,
  set only, so a resume keeps it). `EncounterOfTheWeekGame.IsPracticeGame()`.
- In a practice game: `AutoAwardVictories` awards nothing (the victory
  screen's award controls are Director-only and never show), the treasure
  card note is suppressed, `RecordPendingOutcomes` writes nothing (no
  Victories, treasure or completion go home), and every hero card says
  "Proving Pits: practice only" (`eotw-practice` note). A Proving Pits death
  buries no one (user decision 2026-10-09): `RecordPendingOutcomes` and
  `OfferAbsentOutcomes` send nothing home from a practice game.
- On leaving (victory or defeat) each client writes
  **`eotw:pendingDebrief`** (`{[userid] = {gameid, encounter, result}}`,
  machine-local, one game per player).

## The debrief (town side)

- Back in town, once connected (`MaybeShowDebrief` on `/` and on connect),
  the **Proving Pits Debrief** dialog: the encounter's title, the result and
  "It was practice: nothing was awarded", **Upvote / Downvote** toggles
  (`phosphor/thumbs-up-fill.png` / `thumbs-down-fill.png`) and a multiline
  **feedback for its creator** (2000 chars). **Send** -> `danger-feedback`;
  **Skip** or Escape clears it.
- **No nomination** (2026-10-18, user direction after a playtest: "just
  upvote/downvote and a comment is all we need"). The debrief's "Your pick
  for next week's Encounter of the Week" dropdown is gone, and so are
  "your nomination this week" on the board, the nomination count and
  most-nominated-first order in the admin dialog (now best net vote first)
  and the practice blurb's mention. The City still accepts `nominate?` and
  still reports `nominations`; the client just never sends one.
- City: `danger-feedback {encounter, gameid, vote, feedback, nominate?}`
  stores one row per (player, encounter, game) and one nomination per
  (player, week) (a new one replaces the old; rotation starts a new week).
  Refused for a scheduled encounter. Votes count each player once per
  encounter with their latest up/down; plays count every debrief.
  `danger-stats {encounters?}` -> `{stats, week, nomination}`;
  `danger-report` (admin) -> `{week, encounters (best net vote first, with
  feedback), nominations (most first)}`. Debrief writes share the hero write
  bucket.

## Verified (2026-10-06, single client, the titlescreen town)

City deployed to staging (`97d3fe50`); the week seeded with
`SetWeek("Encounter: Goblin Ambush")` from INSIDE the authoring game (so
`CityRequest`'s short-lived connection and the `CITY_ADMINS` check work).
Then, in the town: the Proving Pits node (unlocked: Ampeth had won Goblin
Ambush); the Gate's banner with the Goblin Ambush blurb; Past Encounters
(empty, then listing Goblin Ambush after a rotation, and its Form a Party
opening the create dialog for it); Form a Party with the encounter, blurb and
no dropdown; the Proving Pits scene (art, crop, practice note, The Dwarvish
Bandits row, Feedback on Your Encounters shown for the module's publisher);
the debrief raised automatically from a staged `eotw:pendingDebrief` on
reopening the town, Upvote toggling, feedback typed, the nomination picked,
Send -> the pending entry cleared and `danger-report` holding the vote, text
and nomination; the row's "1 up, 0 down -- played 1 time -- your nomination
this week"; Feedback on Your Encounters; the admin dialog; a live rotation to
The Dwarvish Bandits from the dialog (both boards re-rendered at once, the
Bandits left the Proving Pits, the Gate showed them, nominations reset), then
restored with the repair form (`set-week` with `past = {}`), now week 3.
Fixed on the way: the node position, and `EncounterDisplayName` reading
"The Dwarvish Bandits (The Dwarvish Bandits)" when a module is named after its
encounter. The staging City keeps one test debrief of The Dwarvish Bandits
(an upvote, "[test from Claude, ignore] Debrief flow check.", game
`claudetest-debrief-1`); there is no delete action.

Gotcha: `dmhub.LeaveGame()` QUITS an app launched with `--gameid` (the MCP
restart does that), so reach the titlescreen with a plain start instead.

## Known gaps

- The game side (practice stamp, no award, card note, pending debrief) has
  not run: no Proving Pits game has been played.
- A player who never returns to the town (crash, quits at the titlescreen)
  keeps the debrief pending until the next town visit; a second Proving Pits
  game replaces it.
- Feedback is readable by anyone who asks for an encounter's key.
- `LOADING_SCREEN_ART` is still the Delian Tomb art for every encounter.

## To test (after the City deploy, the Lua deploy and a restart)

1. As admin, `EncounterOfTheWeek.SetWeek("Encounter: Goblin Ambush")`; the
   Gate's banner shows Goblin Ambush and its blurb; Past Encounters says
   none; Angry Dwarves is offered nowhere.
2. Without a scheduled win, the Proving Pits node is locked with its
   tooltip. Win Goblin Ambush (or a past one) with a roster hero; back in
   town it unlocks.
3. Proving Pits: the scene art and crop, the practice note, The Dwarvish
   Bandits under Encounters to Try; Form a Party shows the practice note; the
   party appears on the Proving Pits board, not the Gate's.
4. Play it: no Victory award, "Proving Pits: practice only" on the cards, no
   treasure; back in town the debrief appears; send a vote and feedback;
   the row's counts update; Feedback on Your Encounters (as the
   module's publisher) shows it; the admin dialog shows it all.
5. Rotate to The Dwarvish Bandits from the admin dialog: both boards update
   live, Goblin Ambush moves to Past Encounters, the Bandits leave the
   Proving Pits. Rotate back if wanted.

# The welcome dialog (BUILT + verified 2026-10-19)

User direction: the first time someone enters Encounter of the Week they are
welcomed. The town shows a modal titled "Welcome to Encounter of the Week"
with the user's text: play Draw Steel alone, with friends or people met
along the way; experimental and in beta, report bugs with Feedback in the
menus; discuss it in the DMHub Discord ("DMHub Discord" is a clickable link
to https://discord.gg/q7kg5AVSfj, the url itself is not shown -- user
direction); you play with other users, so be kind -- we don't want to ban
anybody, but will.
Buttons: "Join the Discord" (`dmhub.OpenURL`; discord.gg is an allowed
domain, the title bar uses it) and "Let's Go!" (Escape also closes it).

- **When.** Polled by the town's watcher think (before the inn reveal and
  the survey): the screen up and settled, on the map (no location open), no
  other dialog, the inn reveal not playing. It is a `ModalDialog`, so the
  inn reveal, the debrief and the survey wait for it.
- **Once.** Preference `eotw:welcomed` = JSON `{ [userid] = true }`,
  machine-local, marked as the dialog opens (an app quit with it up does not
  bring it back). A second machine shows it once more. Every account sees it
  once, existing beta players included (decided while building: the Discord
  and conduct text is worth showing them too).
- Testing: `EncounterOfTheWeek.ShowWelcomeDialog()` with the town open, or
  clear the preference and reopen the town.

# The beta survey (BUILT 2026-10-19; not run, worker not deployed)

While EotW is in beta, every player is invited to a short survey back in
town after each game they finish -- won, lost or abandoned, Encounter of
the Week or Proving Pits -- unless they played under ten minutes. They can
answer or decline ("No thanks", or Escape); both are recorded.

- **Decisions (2026-10-19, with the user):** store in the Blackbottom city,
  not Firebase (no engine build); ask after all three outcomes and both
  boards; skip games under 10 minutes; the leave question has a joke
  option ("I saw the writing on the wall, I knew I was going to lose :)").
- **Questions** (`SURVEY_QUESTIONS` in `Codex Titlescreen/EncounterOfTheWeek.lua`,
  set id `eotw-beta-1`; bump it when they change): length (too short /
  about right / too long), difficulty satisfaction (too easy / felt right /
  too hard), bugs (none / minor annoyances / got in the way / ruined the
  session, with a comment box), interface clarity (with a comment box),
  keep playing (yes / maybe / no), and a free-text box. An abandoned game
  first asks what made them leave. Every question is optional.
- **Game side** (`EncounterOfTheWeek/EncounterOfTheWeek.lua`, "the beta
  survey"): a play clock in the 1s driver banks seconds per game into the
  `eotw:playtime` preference (so a resumed game keeps counting);
  `EncounterOfTheWeekGame.RecordPendingSurvey(outcome)` runs on the
  conclusion exit and from `EncounterPresence.Abandon`, and leaves
  `eotw:pendingSurvey` {gameid, encounter, kind, outcome, minutes, players,
  heroes}. Tests never count. `EOTW_BETA_SURVEY = false` turns it all off.
- **Town side:** `MaybeShowSurvey` (polled by the inn-reveal watcher) waits
  for the connection, any Proving Pits debrief, results left while away,
  other modals and the inn's reveal, then `ShowSurveyDialog`.
- **City:** `eotw-survey` (write bucket; table `city_survey`, one row per
  account per game, answers = choice ids, comments = text, context =
  minutes/party/version) and admin `survey-report` / `GET
  /admin/city/{id}/survey` (counts by kind and outcome, choice tallies,
  every response). A dev account reset keeps survey rows.
- **To test:** deploy the worker to staging; finish (or abandon) a 10+
  minute game; the dialog shows in town; Send and No thanks both land in
  `survey-report`; a sub-10-minute game shows nothing (log: "no survey for
  a N second game").

# Steam invites (BUILT 2026-10-20; NEEDS ENGINE BUILD + worker deploy, not run, UNCOMMITTED)

Friends can be brought into a forming party through Steam, in two ways:
an explicit invite from the party view, and the party advertised as each
member's Steam "Join Game" on the friends list.

- **Decisions (2026-10-20, with the user):** an invite gets a friend into
  a PRIVATE party too; ANY member can invite (not just the host); accepting
  works without the `dev:encounteroftheweek` beta setting (the invite is the
  way in); both the explicit invite and the friends-list Join Game.
- **Connect string:** `dshub2:eotw:<gameid>:<code>`. `dshub1:<gameid>` (a
  normal game to enter) is unchanged; older clients reject `dshub2:`, so they
  never try to enter a party id as a game. Steam caps it at 256 bytes.
- **City / lobby** (`cloudflare-game-server/src/lobby-core.ts`, `lobby.ts`):
  `invite-code {gameid}` (members of an OPEN game only) returns the game's
  code, minted on first ask (16 hex chars) and stable after; `join-game`
  admits a non-member to a private game when `args.invite` matches. Codes are
  NOT in the document (every subscriber sees all of `/state`): they live in
  the DO's own `invites` row and are dropped with their game. Unit tests in
  `test/lobby-core.test.ts` ("invite-code").
- **Engine:** `SteamJoinHandler` routes every connect string through
  `HandleConnectString`; a `dshub2:` one becomes a pending invite, taken by
  `dmhub.TakeSteamInvite()`. Accepted inside a game, it first confirms leaving
  the game (`SteamJoinConfirmDialog.ShowMessage`), then `LeaveGame`. A cold
  launch (OS args or `GetLaunchCommandLine`) boots to the titlescreen as usual
  with the invite pending. `dmhub.InviteViaSteam(kind, payload)` opens the
  overlay invite dialog; `dmhub.SetSteamJoinTarget(kind, payload, group,
  size)` sets the rich-presence `connect` + `steam_player_group` (expires 10s
  after the last push; wins over the in-game target). Also fixed in passing:
  the titlescreen's own lobby game was advertised as a joinable game.
  `dmhub.SimulateSteamJoin(connect)` runs the receiving side without Steam.
- **Town** (`Codex Titlescreen/EncounterOfTheWeek.lua`): `PollSteamInvite`
  (module level, every 1s) takes the invite once at the titlescreen past the
  splash and opens the town; the screen's `TryAcceptInvite` (on the 0.5s
  watcher) waits for the lobby snapshot and any modal, then opens the party's
  board and joins with the code -- asking first if that leaves a party the
  player is already in. Errors: party gone / already set out. The party view
  shows "Invite Friends" to every member while open, only when the Steam
  overlay is running. `PushSteamJoinTarget` (3s think) advertises the forming
  party (the viewed one first). Private parties are now listed for their
  members, not just the host. Analytics: `eotw_party_invite`,
  `eotw_party_invite_accept`.
- **Known gaps:** a session started with `--gameid` (or an old-style Steam
  cold-launch join) quits on `LeaveGame`, so an invite accepted inside one is
  lost. A friend with no roster heroes joins with none and must build one in
  the Guild first. Rich presence carries the code, so any Steam friend of any
  member can join a private party (intended: that is the friends-list Join).
- **To test** (engine build, worker deployed to staging, Lua deployed,
  RESTART): with the town open in a party, `dmhub.SimulateSteamJoin(
  "dshub2:eotw:<gameid>:<code>")` from a second account (New Player Window)
  -- get the code with the city `invite-code` request -- joins it, private
  included; a wrong code says the party is private; from inside a game the
  confirm dialog appears and the town opens after leaving. Real Steam: two
  Steam accounts on the Steam build; Invite Friends opens the overlay, the
  friend's Join lands in the party; the friends list shows Join Game on a
  member while the party forms.

# Analytics (BUILT 2026-10-20; NEEDS ENGINE BUILD, not run)

User direction (2026-10-20): serious analytics for EotW -- mark every in-app
analytics event as EotW or not, track every EotW game to its outcome
(victory, defeat or abandoned), and follow closely how people play.
Firebase `/AnalyticsType` like all telemetry (the `codex-analytics` skill
reads it); `telemetry_enabled` / `analytics:enabled` opt-outs apply.

- **Every event is tagged** (engine, `Assets/AnalyticsManager.cs`
  `StampContext`): `eotw = true|false` on every event, engine and Lua alike.
  True when the loaded game is the account's EotW slot game (works before
  any Lua runs, so `gameLoaded` / `loadGame` / `playingGame` are tagged) or
  when Lua set the `eotw` context (the town). The new
  `analytics.SetContext(key, value, scope)` stamps any field onto every
  later event; scope `"game"` stops applying when that game is left,
  `"titlescreen"` applies only with no game loaded. The town sets
  `eotwWhere = "town"`; an EotW game sets `eotwWhere = "game"`, `eotwBoard`
  (`gate`/`pits`) and `eotwEncounter`, so `use_ability`, `turn_end`,
  `encounter_complete`... split by board and encounter without a join.
- **The run** (`Codex Titlescreen/EotwAnalytics.lua`, core codex so the
  town has it): one player's time in one EotW game. `runid` = the gameid.
  `eotw_run_start` (or `eotw_run_resume` on a later sitting) once the host
  has stamped the encounter and this player's heroes are down; exactly one
  `eotw_run_end` with `outcome` victory / defeat / abandoned and `how`:
  `conclusion` (the normal exit), `abandon` (the in-game Abandon), `quit`
  (left and never came back: closed the next time this machine opens the
  town or starts another run, from the `eotw:analyticsRun` preference),
  `replaced` (a new party replaced the game), `resume_abandon` (the resume
  row's Abandon). A Leave/Quit that keeps the game resumable leaves the run
  open. Judgment call: a player who quits on the victory screen before
  pressing on ends as `abandoned`/`quit` with `lastPhase = "victory"`.
  Every `eotw_*` event sent in a game carries `runid`, `encounter`, `board`,
  `week` (the town sends it with the arrival), `part` and `practice`.
- **Phases** are the host's to report (`EncounterOfTheWeekGame.AnalyticsPhase`,
  never throws): `eotw_phase` with `phase` = gathering / montage /
  narrative / prep / combat / victory / defeat, the script `beat`,
  `fromPhase` and `fromSeconds` (server time, so a host migration keeps it).
  The host stamps it on `eotwstate` (`analyticsPhase*`); every client mirrors
  it into its run record, so `eotw_run_end.lastPhase` is right for members.
- **Tests never count**: an authoring test is not the slot game and every
  run hook checks `IsTestPlayer`.

Events (fields beyond the run fields):

| Event | Sent by | Fields |
|---|---|---|
| `eotw_town_open` / `eotw_town_close` | client | `seconds`, `reason` (enter_game / close) |
| `eotw_welcome` | client | `action` shown (first visit on this machine) / discord |
| `eotw_location_open` / `_close` | client | `location`, `seconds` |
| `eotw_party_create` / `_join` / `_launch` / `_leave` | client | `encounter`, `board`, `public`; `members`, `slotsFilled`/`slotsTotal`; leave `how` leave / disband |
| `eotw_enter_game` | client | `resume`, `members`, `slotsFilled`, `myHeroes`, `host`, `fastLaunch` |
| `eotw_run_start` / `_resume` | client | `host`, `sittings`, `players`, `partyHeroes`, `heroCount`, `heroClasses`/`heroAncestries`/`heroLevels` (comma lists), `combatStarted`, `lastPhase` (resume) |
| `eotw_run_end` | client | `outcome`, `how`, `lastPhase`, `lastPhaseSeconds`, `minutes`/`seconds` (this machine's play time, all sittings), `heroesDied`/`heroesSurvived`, `victoriesEarned`, `treasuresEarned`, `rounds`, `combatStarted` |
| `eotw_phase` | host | above, plus `title`, `round`, `livingHeroes` |
| `eotw_montage_test` | host | `beat`, `round`, `entry`, `entryKind`, `option`, `attr`, `rolled`, `tier`, `total`, `natural`, `knack`, `heroClass`, `owner`, `effects` |
| `eotw_montage_end` | host | `rounds`, `tests`, `tier1..3`, `unrolled`, `knacks`, `delves`, `vanquished`, `taken`, `consequences` |
| `eotw_delve` | host | `entry`, `depth`, `chests`, `steps`, `why` (leave / forced / exhausted / complete) |
| `eotw_narrative_choice` | host | `section`, `mode`, `options`, `option`/`optionIndex`/`decidedBy` or `optionCounts` |
| `eotw_item_grant` | host | `item`, `itemid`, `qty` |
| `eotw_presence` | host | `event` left / abandoned / returned / given / newhost, `member`, `memberHeroes`, `phase` |
| `eotw_exit_choice` | client | `kind` leave / quit, `choice` leave / quit / abandon / cancel, `phase`, `host`, `othersPlaying` |
| `eotw_hero_recruit` / `_dismiss` / `_outcome` | client | `how` pregen / titlescreen / built, `heroClass`/`heroAncestry`/`heroLevel`; outcome `result`, `died` (the burial), `victories`, `treasures` |
| `eotw_hero_sheet_open`, `eotw_equip` | client | `where`, `fallen`; `action` equip / unequip, `itemid`, `slot` |
| `eotw_downtime`, `eotw_project_start`, `eotw_project_roll`, `eotw_carouse`, `eotw_market_buy` | client | `activity` respite / catch_breath; project `tier`, `natural`, `total`, `characteristic`, `skill`, `breakthrough`, `progress`, `completed`; carouse `tier`, `leads`; buy `itemid`, `item` |
| `eotw_debrief`, `eotw_survey`, `eotw_offered_outcome` | client | `action` send / skip / decline, `vote`, `hasFeedback`; survey `answers` (choice ids, no text), `hasComment`; offer `claim` |

## Known gaps

- Trap TRIGGERS are not tracked: they happen in the engine (`LevelObject.cs`
  pressure plates), not in EotW Lua. Reveals are not tracked either.
- Montage tests are host-side, so a test's `owner` is the userid who rolled
  it, not the reporting client.
- The engine caps `encounter_complete` at 20 per install per day; EotW play
  is far below that.

## To test (after the engine build and a RESTART: EotwAnalytics.lua is a new file)

1. Open the town: in the Player.log, `Analytics:` lines for
   `eotw_town_open`; `analytics.IsEotw()` over MCP is true in town, false on
   the titlescreen once the town is closed.
2. Form a party and play: `eotw_party_create`, `_launch`, `eotw_enter_game`,
   `eotw_run_start`, `eotw_phase` per beat, `eotw_montage_test` per test,
   `eotw_montage_end`, `eotw_phase` combat then victory/defeat, and
   `eotw_run_end` with `how = conclusion` on the way out.
3. Quit mid-game, then Abandon from the resume row: one `eotw_run_end` with
   `how = resume_abandon`. Quit, start a new party: `how = replaced`.
4. Any engine event in the game (`playingGame`) carries `eotw: true`,
   `eotwWhere: "game"`, `eotwBoard`, `eotwEncounter`.
5. The Unity Editor suppresses almost every event: test in a built player.

# Encounter series (BUILT 2026-10-17; nothing run yet)

User direction (2026-10-17): an Encounter of the Week can be several
encounters on different parts of ONE map, played in order: win the first to
unlock the second, win that to unlock the third. It works the same in the
Proving Pits and, once it becomes the Encounter of the Week, at the Town Gate.
Decisions taken with the user:

- **The unlock is per account**, not per hero or per party.
- **One Victory per part** (each part has its own encounter key, so the
  existing one-Victory-per-hero-per-key rule gives this for free).
- **Proving Pits wins do not carry over** to the Gate: a series promoted to the
  Encounter of the Week starts again from Part 1 there.
- **Votes and nominations are for the whole series** (its bare key, which is
  also Part 1's).
- **Each part is bounded by its encounter's region** (the encounter builder's
  region rectangle, see `MCDMEncounter.lua` "Encounter region and hero start
  zone"), which hard-restricts the heroes to that part of the map.

**Part maps (2026-10-20, user direction):** a playtest showed the region
hides nothing -- players saw the whole map, and on an upper floor every floor
below shows through -- so a part may have its own map, named after the series
map plus " (Part <n>)" ("Encounter: The Crypt (Part 2)"). Rules:
- Part n plays on its part map when one exists, else on the series map (so
  one-map series still work). The KEY is unchanged (`<key>#<n>`); only the
  map it resolves to changes: game side `PartMapName` / `SplitPartMapName` /
  `FindPartMap`, used by `EnsureOnEncounterMap`, `OnRequestedEncounterMap`
  and `EnsureEncounterModule` (which, for a later part, waits up to 3 s past
  the series map for the part map to arrive).
- A part map's scripts must all say its own part. On a part map with no key
  and no test running, `ActivePart` is that map's part, so the validator and
  script panel read the right script while authoring.
- The town never lists a part map as an encounter (`GetEncounters` skips
  names `SplitPartMapName` accepts). Both publishers read a series' part maps
  with it, number-check all its parts together, and record `map = <part map
  name>` on each part in `eotwEncounters`; `ReadSeriesParts` keeps it as
  `mapName`, which the fast launch's `startMap` uses.
- Test Encounter's Part dropdown lists the parts on the current map. The
  validator's "no region" problem shows only when the map holds more than
  one part.
- **Part 1 too (2026-10-21, user direction):** every part may have a part
  map, `(Part 1)` included. The series is named and keyed by the name before
  the suffix even when no map has it: `FindPartMap` tries the part map first
  for every part; the install wait takes the part map at once, and the
  plain-named map at once for an ordinary encounter but only after a 3 s
  grace for a series part; the town lists the plain name once for all its
  part maps; both publishers make a series with no plain-named map.
- Not run yet: a real arrival on a part map, a community install of a
  series with part maps, and both publishers on one.

Each part is a separate game: the map starts fresh. As built, nothing that
happened in Part 1 carries into Part 2 except through the story text; the
DESIGNED (not built) way to carry results forward is "Carrying the story
forward" below.

## Authoring

- One script document per part in the map's journal folder, each with a
  `# Part N` / `# Part N: Title` heading (`EncounterScript.ParsePartHeading`;
  `parse.part = {number, title, line}`; not a beat, prose under it is notes; a
  second part heading in one document warns). Grammar in the /eotw skill's
  `script-reference.md`, "Series".
- `ChooseMapScript` (`EncounterMontage.lua`): once any candidate declares a
  part the map is a series, and the script is the candidate whose part number
  is `EncounterMontage.ActivePart()` (documents without a part heading are
  ignored). `FindMapScript` caches by part and stamps `script.part` and
  `script.seriesParts` (`{ {number, title} }`). A series with no script for
  the part gets an empty script (no info-bubble fallback).
  `ScriptForMap` (the publisher's) also returns `parts`.
- Each part's `[[encounter]]` island is loaded from a saved encounter that has
  its region and hero start zone drawn. `FindMapEncounter` on a series looks
  only at the active part's documents (`EncounterMontage.ScriptDocuments`) and
  never at info bubbles (re-entry guard: FindMapScript falls back on it).
- The validator panel names the part and flags a part whose island encounter
  has no region. Test Encounter has a Part dropdown on a series map
  (`StartTest{part}`, `CanStartTest(mode, part)`, `EncounterOfTheWeekGame.SeriesParts()`).
  Parts can differ in beats, so a Game menu row shows when ANY part has its
  mode, the dialog opens on the first such part, and its Start at choices
  are rebuilt for the chosen part (`EncounterTest.lua` `TestableParts`,
  `ModeOptionsForPart`; verified live 2026-10-17).

## Keys

Part 1 is the map's bare key; part n >= 2 is `<key>#<n>`
(`Encounter: The Crypt#2`, `<moduleid>|Encounter: The Crypt#3`). Map names
can never hold `#` (the publisher refuses them), so the suffix is
unambiguous, and the bare key keeps meaning the whole series for the
schedule, the Proving Pits rows, votes and nominations. Both
`ParseEncounterKey` copies return `moduleid, mapName, part`; the town adds
`SplitPartKey`, `PartKey`, `GetPart`, `PartName`, `PartUnlocked`, `PartWon`,
`NextPartKey`. `NormalizeKey` (the schedule's) strips the part, so
`IsScheduledEncounter` / `IsDangerRoomEncounter` treat a part as its series.
The party record, `eotwstate.encounterMap`, the pending outcome and
`city_completions` all carry the PART key: that is what makes one Victory
per part and what the Gate's unlock reads.

## Game side (`EncounterOfTheWeek.lua`)

- `EncounterOfTheWeekGame.ActivePart()`: the test's part (`m_testPart` while
  a test sets up, then `data.test.part`), else the part in
  `eotwstate.encounterMap`, else the key this client arrived with
  (`m_arrivalKey`, for a member placing heroes before the host's stamp), else 1.
- `EncounterOfTheWeekGame.PlayArea()` (cached 2 s, keyed by map + part):
  `{region, startLocs, encounter}` from the active island's encounter.
  `InPlayRegion(x, y)`.
- The host's setup calls `ApplyPlayRegion()` right after `RecordEncounterMap`
  and before any hero lands: `Encounter.ApplyRegion(encounter, {hold = true,
  anyMap = true})`. **Core change** (`MCDMEncounter.lua`): `ApplyRegion` takes
  options; `hold` stamps `saved.held` in `encounterRegionBounds` and the
  restore driver skips held maps until `Encounter.RestoreRegionBounds`
  (a real EotW game never restores -- it is thrown away; the authoring test's
  teardown does, `ReleasePlayRegion`). Combat start's own `ApplyRegion` leaves
  the held record alone. This applies to ANY EotW encounter whose island has
  a region, not only a series.
- `StartZoneLocs`: the island encounter's hero start tiles replace the
  `Start` zone when it has any; otherwise `Start` (and unlocked extra start
  zone) tiles inside the region. The confinement cache key includes the part,
  region and start-tile count.
- `EncounterZones.ZoneRecords` keeps only zones with a tile in the region
  (`TouchesPlayRegion`), and trap placement and reinforcement `Enter:` tiles
  only draw tiles inside it (`EncounterZones.InPlayRegion`).
- The story screen's title names the part ("The Crypt -- Part 2: The Ossuary").

## Publishing

`publishingProperties.eotwEncounters[<map name>]` gains `parts = { {number,
title, townGate}, ... }` for a series; its `townGate` is Part 1's (a town
that knows nothing of parts still shows something). ModShare's
`CheckEncounterModule` checks each part like an encounter and errors on a gap
or a repeated number (warns on a one-part series); the Python publisher
(`tools/eotw_publish`, `documents.series_parts`) writes the same shape and
stops on bad numbering. The town reads `parts` leniently (a list may come back
keyed "0", "1").

## Town side

- Pool entries carry `parts` (`ReadSeriesParts`). `GetEncounter(partKey)` is
  the series' entry; `GetTownGateText(partKey)` the part's own text.
- `SeriesPartChips` (a chip per part: tick = won on this board, lock =
  not yet playable) under the Gate's week banner, on each Proving Pits row and
  in Past Encounters.
- **Form a Party** (`ShowCreateDialog(key, explicitPart)`): a series key opens
  on `NextPartKey` (the first unlocked part not yet won, else the last
  unlocked); the chips re-open the dialog on another unlocked part; Create
  refuses a locked part. The party record carries the part key.
- **Unlock rule** (`PartUnlocked`): part 1 always; part n once `PartWon(part
  n-1)`: at the Gate `EotwRoster.AccountCompleted` (list-heroes'
  `unlocks.completed`, every key any of the account's heroes has won,
  dismissed and fallen heroes included); in the Proving Pits
  `EotwRoster.PracticeWon` (`unlocks.practiceWins`).
- **Proving Pits wins**: `MaybeShowDebrief` sends `record-practice-win
  {encounter = part key, gameid}` for a pending debrief whose result is
  `victory`, before (and whatever happens to) the debrief dialog; the answer's
  list goes to `EotwRoster.SetPracticeWins` and the boards re-render. The
  debrief's vote goes to the series' bare key.

## City (`cloudflare-game-server`)

Table `city_practice_wins(userid, encounter, gameid, at)`, PK (userid,
encounter); action `record-practice-win` (write bucket; idempotent; no
schedule check); `accountUnlocks` adds `completed` and `practiceWins`;
`dev-reset-account` deletes practice wins. Unit-tested
(`test/city-core.test.ts`, "encounter series unlocks"). **Not deployed.**
**Checked 2026-10-18 and again 2026-10-19 (after pulling DMHub to
`84a0dcfd8`): this City code is NOT in `D:\DMHub` (src, test or git
history); `accountUnlocks` there returns only `dangerRooms` and `market`.**
Find where it was written, or rebuild it, before deploying. The Python
publisher's half did land later, in DMHub `84a0dcfd8` (2026-10-18,
`documents.series_parts` / `part_heading`, per-part records in
`publish_eotw.py`).

## Not done / known gaps

- **Nothing has run.** Needs: the City deployed to staging, the Lua deployed
  and an app restart, then an authored series to try (no series exists yet).
- No server-side enforcement: a modified client could create a party for a
  locked part (the City does not check `create-game`'s key). Practice wins are
  client-reported, like every town roll.
- The unlock is read when the town lists heroes; a part won in a game unlocks
  the next once the roster is listed again after coming home (the outcome
  apply already re-lists), or at once in the Proving Pits (the
  record-practice-win answer).
- The part chips show this account's progress only; a party view does not
  show which part the party is on beyond the encounter name.
- Sub-documents shared between parts are fine; a part's Town Gate text in a
  sub-document is found by the Lua publisher but not by the Python one (it
  reads the part document alone).

## To test

1. Author a three-part series in an authoring game: one map `Encounter: <X>`,
   three saved encounters each with a region and start zone in a different
   part of the map, three documents `# Part 1..3` each with `# Encounter`,
   the island loaded from its saved encounter, and `# Town Gate` text.
2. Validator: each document says its part; remove a region and see the
   problem row.
3. Test Encounter -> Part 2: the map shrinks to Part 2's region, heroes land on
   its start tiles, its monsters spawn; End Test puts the map's bounds back.
4. Publish (Unlisted): the record's `eotwEncounters` entry has `parts`.
5. Proving Pits: the row shows three chips, 2 and 3 locked; Form a Party opens
   on Part 1 and refuses Part 2. Win Part 1: back in town the debrief appears,
   Part 2 unlocks (tick on Part 1), Form a Party opens on Part 2.
6. Rotate it to the Encounter of the Week: the Gate opens on Part 1 again
   (Proving Pits wins do not count); win Part 1 at the Gate: a Victory, and
   Part 2 opens. A hero who won Part 1 shows "Already Completed" only for Part 1.

## Carrying the story forward (DESIGN signed off 2026-10-19; build started)

Decided with the user on 2026-10-18 through the feature-design loop and
**signed off on 2026-10-19** ("we can start working on this"); the proposed
script wording and player-facing strings were accepted with it and can be
adjusted as the build meets them. Everything here is a settled decision
unless it is listed under "Open questions". Build status is in
"Implementation steps".

### Why

A series forgets everything between parts, so a choice in Part 1 can never
matter in Part 3. The first series to need it is The Bone Cathedral, three
parts on one stitched map. In its Director-run original, a **Rite's Progress**
track starts at 0, Part 1 adds 0, 1 or 2 depending on the montage, and Part 3
pays it off. Two things carry forward:

1. **Story tracks**: named numbers ("Rite's Progress") that a part's clauses
   and results raise or lower, and that later parts read.
2. **Each part's result**: its montage **outcome** (total success / partial
   success / failure), its montage **score**, and the **round** its fight was
   won in.

Who it serves: the **players**, who should feel that the series remembers
them, and the **author**, who needs plain words to write it. Players never
manage any of it.

### Decision ledger (2026-10-18, with the user)

| # | Decision | Why |
|---|---|---|
| D1 | The state belongs to an **account**, and a party plays with its **host's** story. A newcomer just joins the host's story. | It matches the unlock (per account), and the host already picks the part. |
| D2 | When a part is won, the result is saved for **every account in the party**, not only the host's. | A member who later hosts the next part brings the run they played. |
| D3 | **Latest win counts.** Each part keeps its own result row; a later win of that part replaces it. A defeat saves nothing. | Replays can fix a bad run. Replaying Part 1 changes only Part 1's share of the track. |
| D4 | **Danger Room and Town Gate stories are separate**, like the unlocks. A series promoted to the Week starts with a clean story. | Consistent with "Danger Room wins do not carry over". |
| D5 | **The montage outcome covers every montage in the part.** Score = tier-3 results (crits included) − tier-1 results − threats left unvanquished. Each event counts once, and tests on Opportunities count too. | The user's definition: successes, minus failures and complications (an unvanquished threat is a complication). |
| D6 | Outcome = the score **per hero** (divided by the number of heroes who began the part) against two bars: **total success at or above the first, partial at or above the second, failure below**. Written `Outcome: total success at 1, partial at 0` in `# Results`, per hero. **Default: total at 0.5, partial at −0.25** (the old raw +2 / −1 at four heroes). | The user picked net score + thresholds, then per hero after the critique (2026-10-18): six heroes make about 50% more tests than four, so raw bars favoured big parties. |
| D7 | The **round the fight was won in** is recorded (wins only) and is readable by later parts. It does not feed the outcome. | The user wants it tracked; keeping it apart keeps the outcome about the montage. |
| D8 | Tracks are **declared**: `Track: Rite's Progress` in each part document that uses one, or `Track: Rite's Progress (Hidden)`. **No range.** Ordinary clauses change them wherever clauses go, and `{...}` hides a change as usual. | The validator can then catch typos. The user declined a range. |
| D9 | A new **`# Results`** section (not a beat) runs once, at victory, after the outcome and round are known. It holds the `Outcome:` bars and `<condition>: <clauses>` lines. | The end-of-part result usually drives the track; written once in the part that causes it, not re-derived in every later part. |
| D10 | Later parts read the story in **four places**: scene branches, `When <condition>:` setup lines under a beat heading, fight variants (a `When` line above an `[[encounter]]` island or a Reinforcements section), and `If <condition>:` / `Otherwise:` / `End` lines in story text (Town Gate, Narrative sections, Conclusion, Defeat; changed from `## If` headings after the critique, because `##` already means a section). | All four, the user's pick. |
| D11 | A part with **no saved result** (for example, unlocked by a win in someone else's party before this existed) reads as **"not recorded"**. That is a condition of its own (`Part 1 was not recorded`). Every other condition about that part is false, and its track share is 0. | The user: let the author decide. |
| D12 | The City runs **cheap sanity checks** on a reported result. It accepts a report only for that game's own part key, from a member of the run, where the snapshot host's report is final and another member's is a provisional fallback, with the outcome one of the three values, the round from 1 to 50, and each track share between −100 and 100. | Not cheat-proof, but bounded, and the same trust as wins. |
| D13 | **Visibility is per track**: a plain `Track:` is shown, a `(Hidden)` one never appears as a number. | Hidden suits a looming threat; shown suits a scoreboard. |
| D14 | Shown on the **victory story screen** (a recap under the Conclusion) and **in town** (a "story so far" line in Form a Party and the party view). Not on the in-game HUD, and no live change toasts. | The user's pick. |
| D15 | A **replay** of a part shows a one-line note in Form a Party AND in the party view to **every member** whose account has a saved result for that part. There is no confirm dialog. | Latest win replaces the row for every member (D2, D3), so warn everyone it affects, without blocking (the user's pick after the critique). |
| D16 | A track may carry a **description**: `Track: Rite's Progress -- how close the cult is to finishing the rite`, shown next to the value in town and on the recap (shown tracks only). | Players can't tell whether "rose to 2" is good without it. The user declined a score breakdown on the recap. |
| D17 | **Delve tests do not count** toward the score; only the montage board's own tests do. | The user's pick. |
| D18 | **Replaying an earlier part never clears later parts' results.** Replaying Part 1 after Part 2 replaces Part 1's row only; Part 2's share stays, even if Part 2 branched on the old value. | The user, 2026-10-19. |

### The design

**Prerequisite: the series' City half is not in this checkout.** The series
section says `record-practice-win`, `city_practice_wins` and the `completed` /
`practiceWins` unlocks are built and unit-tested. On 2026-10-18 none of them
exist anywhere in `D:\DMHub\cloudflare-game-server` (src or test, working
tree clean; rechecked 2026-10-19 after DMHub `84a0dcfd8`), but the town
already sends `record-practice-win` (`Codex Titlescreen/EncounterOfTheWeek.lua`
~5881). Find that work (another clone or branch?) or rebuild it before
anything here; this design sits on top of it. The Python publisher's series
half is no longer missing: it landed in DMHub `84a0dcfd8` (2026-10-18).

**What is stored (the City).** Two new tables:

- `city_series_results(userid, board, series, part, gameid, outcome, score,
  rounds, tracks, at)`, primary key `(userid, board, series, part)`.
  `board` is `gate` or `practice`. `series` is the bare series key, `part`
  is the part number, and `tracks` is a JSON object `{name: share}`, the net
  change the part made to each track. A later win replaces the row (D3).
- `city_series_runs(gameid, series, part, board, host, members, story,
  result, at)`: a snapshot taken at launch of every series game. It records
  the part key, the board, the host, every account with heroes in the party,
  the story handed out, and later the result. It exists because the lobby's
  game record is swept about 5 minutes after launch, once heartbeats stop
  (`lobby-core.ts` ~45, ~727), long before the result comes in.

**The board, decided once, by the City.** The City's `isScheduled`
(`city-core.ts` ~833) compares the raw key, so `Encounter: X#2` would never
match the bare key the schedule holds and every part from 2 on would count
as practice. The City gains its own `splitPartKey`, used by `isScheduled`
and `applyDangerFeedback` (~938), with the Lua rule that an official-module
key is never practice. At launch the City stamps `board` on the lobby
record, and the arrival's `practice` flag comes from that stamp rather than
the client's own reading of the week (titlescreen ~3051). Otherwise a client
with a stale week plays practice while the City files the result under the
Gate.

**Handing the story to the game.** The base lobby runs `launch-game` with no
City hook (`lobby.ts` ~525, `applyLaunchGame` `lobby-core.ts` ~621), so the
City gains one (`prepareLaunch`, like `prepareHeroClaim`). For part n of a
series it writes the `city_series_runs` row, and it stamps `board` and the
story on the record. The story is built from the **host's** rows on that
board for parts 1..n−1:
`story = {parts = {[k] = {outcome, score, rounds, tracks} | "not recorded"},
tracks = {name = sum of shares}}`. The story rides the arrival args the way
`completed` does (`checkHeroClaim`), and the game host copies it into
the script document's `data.story` during setup. The value comes from the City, never from a
client's claim.

**Resuming.** The seeded story lives in the game's own script document, so
a resume keeps it. Only a host who crashed before seeding it needs the City:
when a player resumes after the record has been swept, the arrival carries
nothing, so whenever the script document's `data.story` is missing, the game
host fetches it with a new read, `get-series-run {gameid}` (the game already
sends lobby requests, `EncounterOfTheWeek.lua` ~1531). A part never plays as
"not recorded" just because someone crashed.

**During the part (the game).** The script document's (`eotwscript`) `data.story` holds each track's
live value. It starts from the carried sums (0 for a declared track the story
does not have), and the host changes it for every track clause, like any
other effect.

The montage totals live at the TOP level of the state document as
`montageTotals[beatIndex]`, because `data.montage` is replaced at every
montage's start (`EncounterMontage.lua` ~5843). Keying them per beat means a
host change cannot add one twice. They are derived when each montage ends,
from its log plus its consequence list:

- **success**: tier 3 or tier 4 (the critical is its own tier, a natural
  19-20, ~3141);
- **failure**: tier 1;
- **unvanquished**: a threat whose consequence actually landed, meaning not
  vanquished, not scaled away, and unlocked (~6117);
- delve obstacles do NOT count (D17). They resolve through
  `DelveObstacleResolved` rather than the log anyway (~3509).

**The result is decided once, by the host.** When the outcome is first
detected (`UpdateEncounterConclusion`, ~1609; NOT the Victory award, which
practice games skip, ~1212), the host computes everything in one
`CompleteChange`, guarded by `data.seriesResult == nil`:

1. the score, the score per hero (divided by the heroes who began the part,
   from the arrival roster), the outcome (D6), and the round from the
   initiative queue;
2. `# Results`: each `<condition>: <clauses>` line whose condition holds
   applies its clauses (track changes, mostly) in document order. These
   conditions can read this part (`total success`, `the fight lasted 5 or
   more rounds`, `score 0.5 or more`, a track's value) as well as earlier
   parts;
3. the stamp `data.seriesResult = {series, part, outcome, score,
   rounds, tracks = this part's shares}`.

A new host or a reloaded client never recomputes; it only reads the stamp,
which is what the recap shows. The host then sends `record-series-result
{gameid, ...}` from inside the game at once, and keeps a copy as a retry
(machine-local, next to the pending outcomes at the Gate and on
`eotw:pendingDebrief` in the Danger Rooms, since practice games return early
from `RecordPendingOutcomes`, ~1465).

**What the City accepts.** A report for a game in `city_series_runs` whose
part key matches, passing the D12 checks. The **snapshot host's** report is
final. A report from another member is accepted only as a provisional
fallback (for a host who never reconnects), and the host's report may
replace it once. The accepted result is written to every member account of
the run (D2). A defeat stores nothing (D3).

**Writing it (script grammar).** Proposed wording; the exact words are part
of the sign-off. The Bone Cathedral's real rule, Part 1 adding 0, 1 or 2 by
the montage result, is all in `# Results`:

```
# Part 1: The Road Off the Moor
Track: Rite's Progress (Hidden) -- how close the cult is to finishing the rite

# Results
Outcome: total success at 1, partial at 0
Total success: nothing happens
Partial success: Rite's Progress +1
Failure: Rite's Progress +2
```

A threat's `Consequence:` or a tier line may also change a track (`Rite's
Progress +1`). That stacks with `# Results`, and an unvanquished threat
already lowers the score, so the validator mentions it when one part does
both.

Track clauses are `<Track> +N` / `<Track> -N`, `<Track> rises by N` /
`falls by N`, and `raise` / `lower <Track> by N`. They are matched only
against the names the part declares, so they cannot collide with `+2 malice`
and the rest. **A clause that changes a hidden track is always hidden**, as
if it were in `{...}`, so it can never print "Rite's Progress +2" on the
stage.

**Reading it (conditions).** There is **one condition parser for every
place**: these new atoms join `EncounterScript.ParseCondition`, so every atom
works in scenes, `When` lines, story text and `# Results`. The validator
names the right place when an atom cannot apply (for example, `PC ...` in
story text). Comparisons accept `N or more` / `or higher` / `at least N`,
`N or less` / `or lower` / `or fewer` / `at most N`, and `is N`, everywhere,
including the existing knack requirements.

- `Rite's Progress is 2 or more`
- `Part 1 was a total success` / `a partial success` / `a failure`,
  `Part 1 was not recorded`
- `Part 1 scored 0.5 or more`, `Part 1's fight lasted 5 or more rounds` (a
  part that is not recorded makes these false)
- `the previous part ...` works as well as `Part n-1 ...`
- in `# Results` only: `total success` / `partial success` / `failure`,
  `score 0.5 or more`, `the fight lasted 5 or more rounds` (about this part).
  It is "the fight", because montages have rounds of their own.
- A score in any condition is the per-hero score (D6), the same number the
  `Outcome:` bars use, so `Part 1 scored 0.5 or more` means the same for
  four heroes or six.

Where they go (D10):

- **Scenes**: `if Rite's Progress is 2 or more then` ... `end`.
- **Setup lines**: `When <condition>: <clauses>` directly under `# Montage`,
  `# Narrative` or `# Encounter`, applied as that beat starts. For example,
  `When Rite's Progress is 2 or more: +2 malice` under `# Encounter`, or
  `When Part 1 was a failure: unlock The Bone Choir` under `# Montage` (a
  harder `(Locked)` threat).
- **Fight variants**: a `When <condition>:` line directly above an
  `[[encounter]]` island or a `## Reinforcements:` heading. A gated opening
  island is used only when its condition holds; the first opening island
  whose gate holds (or that has no gate) is the fight. A gated
  Reinforcements section never comes when its gate fails.
- **Story text**: NOT headings. `##` already starts a section in a
  Narrative, and the publishers strip `##` lines from story text
  (`tools/eotw_publish/documents.py` `story_section`, ~301 and ~315 as of
  `84a0dcfd8`). Instead, `If <condition>:`
  ... `Otherwise:` ... `End` lines inside `# Town Gate`, a Narrative
  section, `# Conclusion` and `# Defeat`. Both publishers send the Town Gate
  as structured `{text, blocks}`, and the town resolves it: against the
  viewer's own story while browsing, and against the host's once in a party.

**What players see (D13-D15).** Proposed copy; every string needs sign-off:

- Victory story screen, under the Conclusion text: "Montage: Partial
  success." / "Won in round 4." / "Rite's Progress rose to 2." ("fell to",
  "stays at"). Hidden tracks never appear.
- Town, Form a Party and the party view, for a part after Part 1: "Your story
  so far: Part 1 -- Partial success, won in round 4. Rite's Progress 2." In a
  party, members see the host's story, labelled "(the host's story)" (D1). A
  part that is not recorded reads "Part 1 -- not recorded". The party view
  reads the host's rows through a new `series-story {userid, series, board}`
  read.
- Replay note in Form a Party, and in the party view for every member with a
  saved result for the part (D15): "Winning this part again replaces its
  result in your story."
- A track's description (D16) follows its value: "Rite's Progress 2 -- how
  close the cult is to finishing the rite."

**Hidden is not secret.** The story rides the broadcast lobby record and
the script document, so a determined client can read a hidden track's value. That is
accepted at D12's level of trust; hidden means "not shown", not
"protected".

**Authoring and testing.**

- The validator checks that:
  - a track clause or condition names a declared track;
  - a condition names a part before this one;
  - the `Outcome:` bars are in order;
  - `# Results` sits in a part document.
- It warns when a part that a later part reads has no `Outcome:` line, and
  when a part reads a track or outcome but has no `was not recorded` branch
  anywhere. It lists each part's declared tracks.
- Test Encounter gets a **Story so far** editor for Part 2 and later: each
  earlier part's outcome, score and rounds (or "not recorded"), and each
  track's value. Without it, a later part's branches can only be reached by
  really winning the earlier parts. A test ends with the computed outcome,
  score and Results in the chat log, and saves nothing.
- The publishers (ModShare and `tools/eotw_publish`) copy each part's track
  declarations (name and hidden flag) into `eotwEncounters[...].parts[i]`, so
  the town can tell shown tracks from hidden ones.

### Out of scope / rejected (with reasons)

- **A per-hero or per-run (party-chain) story**: rejected for the host's
  account (D1). Per hero needs an arbitrary rule for combining heroes; per run
  needs a "continue a run" step and breaks when the group changes.
- **First win only, or best result**: rejected for the latest win (D3).
  First-only cannot fix a bad run, and best-result invites grinding.
- **A shared story across both boards**: rejected (D4).
- **Draw Steel success and failure limits that stop a montage early**:
  rejected for net score (D6). EotW montages do not end early.
- **Undeclared tracks**: rejected (D8), because a typo makes a second track
  silently.
- **Later parts computing Part 1's effect**: rejected for `# Results` (D9).
- **A track range**: declined by the user (D8); only the City's ±100 sanity
  bound applies.
- **An in-game HUD readout and live change toasts**: not wanted for the
  first version (D14). The stage still shows a clause on a shown track as
  text, like any clause.
- **`## If` headings for story text**: replaced by `If:` / `Otherwise:` /
  `End` lines, which clash with neither Narrative sections nor knacks.
- **"First report wins"**: replaced by the snapshot host's report being
  final, so a member who left early, or a modified client, cannot lock in
  the result.
- **Server-side verification of a result** (the City replaying the game):
  out of scope, the same as wins (D12).

### Implementation steps (build started 2026-10-19)

Status as of 2026-10-19: the Lua side of steps 1-3, 6 and 7 is BUILT,
uncommitted, in the working clone `D:\draw-steel-codex`. It passes `luac -p`,
the LuaLS check (0 problems in every changed file) and the parser tests
(`tests/encounter_script_test.lua`, 1017 checks; 67 new). Nothing has run in
the app. The City (step 4) and the town (step 5) wait on step 0.

0. **The series' City half** (NOT DONE; BLOCKS 4 and 5): the series'
   City code (`record-practice-win`, the practice-wins table, the unlock
   lists) is deployed to the staging City (the series plays on the current
   build, per the user) but its SOURCE is in no local repo, branch or stash
   (checked 2026-10-19). It is presumably unpushed on David's machine.
   **Do not deploy the City from `D:\DMHub` until that source is in**: a
   deploy would wipe the series code off staging. Get David's source first.
1. **Parser** (BUILT, `EncounterScript.lua`): `Track:` declarations
   (`ParseTrackDeclaration`, `parse.tracks` / `parse.trackKeys`); track
   clauses (`ParseTrackClause`, effect kind `track`, checked against the
   declarations once the whole script is read; `undeclared` ones warn and
   do nothing; a hidden track's clause gets `hidden`, and `HiddenRanges`
   hides it in any displayed text as if braced); `# Results`
   (`parse.results = {line, bars, lines}`); the story condition atoms
   (`ParseStoryAtom`, ops `track` / `part` / `this`) and the comparison words
   (`ParseComparison`; the condition tokenizer keeps "2 or more" together)
   in the one shared `ParseCondition`; `When <condition>: <clauses>` lines
   (`beat.when`); gates on opening islands (`beat.islands = {tag, line,
   gate}`; `beat.encounterTag` is still the first island) and on
   Reinforcements (`reinforcement.gate`); `If:` / `Else if:` / `Otherwise:`
   / `End` in Town Gate, Conclusion, Defeat and narrative sections
   (`ParseStoryBlocks` -> `holder.storyBlocks`, `holder.rawText`, and
   `holder.text` becomes the no-story text; `ResolveStoryText`). Checks in
   `CheckStory`: undeclared tracks, parts that are not earlier, `the
   previous part` in Part 1, this-part atoms outside `# Results`, `# Results`
   or `Track:` outside a part, and the "was not recorded" nudge. Evaluation:
   `EvalStoryAtom`, `EvalStoryCondition`. `script-reference.md` has a
   "Carrying the story forward" section.
2. **Montage totals** (BUILT, `EncounterMontage.lua`): `TotalsFromLog`
   (tier 3-4 success, tier 1 failure, each logged consequence an
   unvanquished threat; delve and passed turns have no tier), stamped into
   `data.montageTotals["b<beat>"]` by `HostTick` when a montage reaches
   "done"; `PartTotals` sums them, plus a montage still running.
3. **Game** (BUILT except the City calls): the live story lives in the
   SCRIPT document (`eotwscript` `data.story`, next to the beat index and
   the montage state, where effects already write), not in `eotwstate` as
   the design first said. `SeedStory` (`EncounterOfTheWeek.lua`
   `SeedSeriesStory`) runs on the host at setup from `args.story`, before the
   region (a fight with variants picks by it) and the opening beat; a story
   already seeded for the part is kept, so a resume keeps it without a City
   read (`get-series-run` is then only needed for a host who crashed before
   seeding). Track clauses (`ApplyEffects` kind `track` -> `ChangeTrack`,
   live value plus this part's share); `ApplyWhenLines` from
   `EncounterMontage.Begin`, `EncounterNarrative.Begin` and the encounter
   beat in `RunScriptBeat`, once per beat (`data.whenApplied`); island
   variants (`GatedIslandEntry` in `FindMapEncounter`, resolved like a
   reinforcement island); gated Reinforcements (`DueArrivals`); scene
   conditions (`SceneEnv`); `DecideSeriesResult` once, just before
   `live.victoryAwarded` is set (Gate and practice; per-hero score over the
   `numheroes` setting, the initiative round, `# Results`, the
   `data.seriesResult` stamp); the Conclusion/Defeat text resolved for the
   story and the recap appended (`OutcomeStory`, `SeriesRecap`); narrative
   section text resolved on the stage (`EncounterMontageStage`). Test reset
   clears `story`, `montageTotals`, `whenApplied` and `seriesResult`.
   **NOT DONE**: sending `record-series-result` (and its retry copy next to
   the pending outcomes / the pending debrief), and `args.story` arriving
   from the City; both need step 4.
4. **City** (NOT DONE; waits on step 0): `splitPartKey` in `isScheduled` and
   `applyDangerFeedback`; a `prepareLaunch` hook that stamps the board and
   the story and writes `city_series_runs`; the results table;
   `record-series-result` (D12 checks, host final, member provisional, the
   write to every member); `get-series-run` and `series-story`;
   `dev-reset-account` clearing both tables. Unit tests in
   `test/city-core.test.ts`.
5. **Town** (NOT DONE; waits on step 4): the arrival's `practice` from the
   City's board stamp; `args.story` passed through the arrival; the "story
   so far", host-story label and replay lines; resolving `townGateSource`
   for the viewer's / host's story. Until then the town shows `townGate`,
   which is already the no-story text.
6. **Publishers**: ModShare (BUILT): each part record carries `tracks =
   {{name, hidden, description}}` and, when its Town Gate has `If` blocks,
   `townGateSource` (the text as written) beside `townGate` (the no-story
   text). Python publisher (BUILT, `tools/eotw_publish` in the DMHub repo,
   uncommitted): the same records; `documents.py` gains a Python mirror of
   the story-condition parser and `ParseStoryBlocks` / `ResolveStoryBlocks`
   (`resolve_story_text`) and `track_declarations`, checked case by case
   against the Lua (8 tests, kept outside the repo since the tool has no
   test file). Like the Lua, any condition that parses opens an `If` block
   (a hero atom too). It does not log the story-block or track warnings
   the Lua parser gives. It reads each part's Town Gate from the part document
   alone (`story_section([entry], ...)`), so a part's Town Gate kept in a
   sub-document is still not found (the series' known gap).
7. **Validator and Test Encounter** (BUILT): the validator lists each
   part's tracks and its `# Results` bars; the parser's warnings carry the
   checks. Test Encounter's dialog has a **Story so far** box for Part 2
   and later (each earlier part's outcome, score per hero and round, or Not
   recorded; each declared track's value), passed as `StartTest{story}` and
   seeded like a real arrival. The test prints its result in the console
   ("EotW story: Part n result: ..."), not the chat log, and the Conclusion
   screen shows the recap.
8. **Run it** (NOT DONE): author a two-part sample with a track, `#
   Results`, a When line, a gated island and an `If` block in the
   Conclusion; Test Encounter Part 1 (check the console result and the
   recap), then Part 2 with each Story so far (check the When line, the
   island chosen, the story text). Then author The Bone Cathedral's Rite's
   Progress across the three parts.

### Open questions

- **A track's starting value** in Part 1 is 0. Is there any case for
  `Track: X starts at N`? (Proposed: no, until a script needs it.)

### Evidence (2026-10-18)

- The montage has no overall result today: `EncounterMontage.lua` tracks
  only `vanquished[entryId]`, and every unvanquished threat delivers its
  consequence at the end (~line 6117).
- Conditions exist only in scenes: `EncounterScript.ParseCondition` (~line
  2306), `EvalCondition` (~2541).
- The City already stamps party heroes at claim time (`checkHeroClaim`,
  `city-core.ts` ~770). `record-outcome` stores an opaque outcome per (hero,
  game), and `accountUnlocks` serves the unlock lists (as committed it
  returns only `dangerRooms` and `market`, ~849).
- Critique round 2026-10-18 (two independent reviewers: author/player UX and
  systems against the code). Their mechanical findings are folded in above:
  the board key bug, the launch hook, resume, the practice path, a one-time
  host result, where the totals live, story-text grammar, hidden-track
  clauses, comparison words, the Bone Cathedral example. Findings that
  touched the user's decisions went to the user (see the ledger).

---

# Downtime: wounds, the Blue Fish Inn, respite and projects (DESIGNED + BUILT 2026-10-10; not yet run live)

User direction (2026-10-10). This is the first piece of "Progression" (Phase
11). It needs no level bands, because heroes stay level 1 in encounters.

- **Wounds come home.** A hero who survives a Town Gate encounter brings back
  their lost Stamina and spent Recoveries; nothing heals on the way. This does
  not apply in the Proving Pits, which stay practice-only.
- **The Blue Fish Inn** is a new town location. There a player takes a
  **Respite**, and every one of their heroes rests at once:
  - each hero's Victories become XP, and Victories drop to 0;
  - each Victory spent this way becomes one **Downtime Activity**, a new
    resource shown prominently on the hero card with a hammer icon;
  - Stamina and Recoveries are restored in full.
- **Projects** cost Downtime Activities. A project can belong to one hero, to
  one player, or to the whole community. The first one is **Expand the Guild**,
  at the Hero's Guild:
  - a player's roster starts at **4 hero slots** (it was 12 living heroes);
  - each completion adds one slot, up to 5 completions (9 slots);
  - the costs are 60, 90, 120, 150 and 180 Project Points (+30 each time);
  - it is a Reason or Presence project, using Brag, Empathize, Flirt, Lead,
    Perform or Persuade.
- **Project Rolls** have no tiers. A hero spends one Downtime Activity and
  rolls 2d10 + the characteristic (+ any bonus), and the total is the points
  added. A natural 19 or 20 is a **Breakthrough**: it gets a dramatic banner
  and one more roll at no cost, which can chain. These are the Draw Steel book's
  own project rules (Downtime Projects chapter).

Visual mockups of the four screens below were shown to the user on
2026-10-10, in the chat, not in the repo. Also added the same day (user
direction): at the inn a hero who does not want to rest can **Catch Their
Breath** instead -- spend one Recovery to regain Stamina, keeping their
Victories.

## As built (2026-10-10) and what is left

| Piece | Where | State |
|---|---|---|
| City: `grant-downtime`, `list-projects`, `start-project`, `project-roll` (refused unless the project is under way), roster slots (4 + Expand the Guild, max 9; `CITY_MAX_LIVING_HEROES` is gone), `downtime` per hero + `slots` in `list-heroes`, dying heroes refused by party claims, `/city/projectsRev` | `cloudflare-game-server/src/city-core.ts` (section "Downtime" at the end; `CITY_PROJECTS`, `rosterSlots`, `applyGrantDowntime`, `applyListProjects`, `applyProjectRoll`), `src/city.ts` (tables `city_downtime`, `city_downtime_grants`, `city_projects`, `city_project_rolls`; actions; write bucket), `test/city-core.test.ts` (9 new tests, 328 total pass), `CLAUDE.md` | tsc + 329 tests pass. **DEPLOYED to staging 2026-10-10** (version `e361e908`, with `start-project`; first deploy `b66c3536`); release NOT deployed |
| Game side: survivors' wounds on the outcome (`outcome.wounds = {damage, recoveriesUsed}`), victory AND defeat (a defeat's survivors now send an outcome too) | `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`HeroWounds`, `OutcomesFor`) | luac + typing clean; untested. COMMITTED: `HeroWounds` and the wounds of a VICTORY's survivors (in the committed `VictoryOutcomesFor`). The defeat-survivor branch lives in `OutcomesFor`, the burial write-back's rewrite, and is still uncommitted with it |
| Town: wounds applied (`EotwRoster.SetWounds`, inside `ApplyOutcome`'s stamped write), `summary.dying`, slots (`EotwRoster.Slots`, `BASE_SLOTS`/`MAX_SLOTS`, `FullRosterMessage`), Downtime cache (`GetDowntime`, `SetListedDowntime`, `SetListedSlots`), `IsInStep`, `IsDying`/`TokenIsDying`; Guild header slot pips (filled / hollow / padlock) + the Expand the Guild card under the roster | `Codex Titlescreen/EotwRoster.lua` | luac + typing clean; untested |
| NEW `Codex Titlescreen/EotwDowntime.lua` (global `EotwDowntime`, registered in the Codex Titlescreen codemod after `EotwRoster.lua`, Firebase confirmed): project mirror (`PROJECTS`), respite (`TakeRespite`, resumable via `eotw:pendingRespite`), Catch Breath, project rolls (`Roll` with real 3D dice through `dmhub.Roll`, resumable via `eotw:pendingProjectRoll`), `ResumePending` on connect, the inn card (`InnPanel`), the project card (`ProjectCard`), the roll dialog (`ShowRollDialog`), banners through a town-mounted `DramaticBanner.Create()` | new file | luac + typing clean (0); needs an app RESTART; untested |
| Hero card hammer chip (`opts.showDowntime`, top-left, town strip only); strip subtitle says "Dying: needs a respite" | `Codex Titlescreen/EotwHeroCard.lua` (`CreateDowntimeBadge`), `Codex Titlescreen/EncounterOfTheWeek.lua` | clean; untested |
| The inn location (node at (0.335, 0.575), `phosphor/beer-stein-fill.png`, locked until a living hero), scene with the looping video, laid out like the other locations (`scene.cardSide = "left"` is supported but unused), Away/dying gates in `ClaimActiveHeroes` and the add-hero picker, "came back wounded" in While You Were Away, `ResumePending` 2s after connecting | `Codex Titlescreen/EncounterOfTheWeek.lua` (`INN_VIDEO`, `INN_ART`, `LocationScene`, `SceneHeader(scene, side)`, `m_innScene`) | clean; untested |
| `CreatorCredit.Backdrop`'s video layer now streams through a private looping player (`bgimageStreamed = id .. "###LOOP" .. guid`, as the montage stage does) and schedules its own `imageLoaded`; before, a plain `bgimage` played once and went blank | `DMHub Core UI/CreatorCredit.lua` | clean; untested (the first real video backdrop) |
| Assets: inn video core image `07d3b304-792c-4b5c-8340-814c9da9f864` (isVideo true) and its poster `e9f0c6ae-2041-476b-ba46-e945b374fa6b`, both tagged `czepeku` | sources `C:/dev/eotw/art/blue-fish-inn-ages-of-the-vale-pt3-day.webm`, `blue-fish-inn-poster.jpg` | UPLOADED 2026-10-10 |
| The inn's reveal (2026-10-11): inn hidden until unlocked, a returning hero's line in a montage-style dialog box, the node dropping onto the map | `Codex Titlescreen/EotwRoster.lua` (`eotw:innState`, `InnUnlocked`, `InnRevealed`, `MarkInnRevealed`, `Homecomings`, `NoteHomecoming` in `ApplyOutcome`'s `Record`, `OutcomesInFlight`); `Codex Titlescreen/EncounterOfTheWeek.lua` (`hidden(ctx)` on `CITY_LOCATIONS` rows, `InnShown`, `PlayInnReveal`, `MaybePlayInnReveal`, `PickInnSpeaker`, per-node halo ids `eotwTownHalo-<id>`, hero strip id `eotwTownHeroStrip`) | luac + typing clean; played live 2026-10-11 through the fallback path (an account with past wins, no homecoming this session). The homecoming path (NoteHomecoming after a real encounter) is NOT yet run |

### The inn's reveal (BUILT 2026-10-11)

User direction (2026-10-11): a new player's town has no Blue Fish Inn. It
appears the first time heroes come home from a Town Gate adventure, and then
one of the returning heroes says, in a dialog box like the montage's, "That
was a tough challenge! We should head to the Blue Fish Inn to rest before
continuing on more adventures."

- **What unlocks it.** Any living hero coming home from a Town Gate
  adventure, a victory or a defeat (user direction: today a defeat means the
  whole party is dead and in the Graveyard, so in practice it is a win). The
  Proving Pits send nothing home, so they never unlock it. The trigger is
  `record-outcome` succeeding for a living hero (`NoteHomecoming` in
  `EotwRoster`'s `ApplyOutcome`).
- **Where the state lives.** A machine-local preference per account,
  `eotw:innState` = `{ [userid] = {unlocked, revealed} }`. So that an
  account that adventured before this change, or on another machine, keeps
  its inn, `InnUnlocked()` is also true when the city says the account has
  won before (`unlocks.dangerRooms`, or any hero's `completed` list). Such
  an account sees the reveal once on each machine. If that matters later, a
  server-side unlock (`accountUnlocks` gains `inn`: the account has any
  living outcome on record) would make it per account rather than per
  machine; not built.
- **When it plays.** `MaybePlayInnReveal`, from a 0.5s watcher on the town
  screen, waits until the town is up and on the map (no location, no
  dialog, no debrief or While You Were Away, no outcome still being carried
  home) and that has held for 1.5s. `EncounterOfTheWeek.innRevealWaitingOn`
  says what it is waiting on (`screen`, `unlock`, `location`, `dialog`,
  `outcomes`, `speaker`), for debugging over MCP.
- **Who speaks.** Of this session's homecomings, the hero who lost the most
  Stamina; with none (the fallback above), the most wounded hero at home,
  active heroes first. The hero needs a loaded working copy for the
  portrait, so right after a restart it waits a few seconds (`speaker`).
- **The sequence** (`PlayInnReveal`):
  1. The map pans (0.9s, ease in-out) to put the inn in the upper third.
  2. The hero's portrait and an opaque dialog box rise in at the bottom
     (the montage stage's sizes and box style), and the hero strip hides.
     The line types at 45 characters a second.
  3. When it finishes, or on a click, the inn's node appears at 5x its size,
     fades in, and accelerates down into place (0.85s), lands with a small
     bounce, a halo pulse, a stone thud and a short jolt of the map.
  4. A blinking caret waits for a click (or Escape). The dialog fades and
     sinks away, the strip returns, the reveal is recorded, and the inn's
     halo pulses three more times. The Guild's own "no active hero" beckon
     holds off during all of this.
- **Gotcha found while building it:** `Panel:Get(id)` searches the whole
  hierarchy from the root, so every node's halo shared one id and the inn's
  pulses lit the Guild's halo. The halos now have per-location ids.
- **Test it again:** `dmhub.SetSettingValue("eotw:innState", "")`, then
  reopen the town (`EncounterOfTheWeek.ShowScreen()`; the codemod needs a
  RESTART after edits). Still to try: a real homecoming on a fresh account,
  so the speaker is a hero who just came back wounded.

**To test, in order** (the City is deployed to staging; needs an app
restart):
1. Town map: the Blue Fish Inn node over the tavern; the scene opens with
   the video LOOPING (watch past 30s), header on the left and card on the
   right like the other locations, Czepeku badge, Back to Town and Escape.
2. Guild: "N / 4 slots" with pips and padlocks; no project card by default;
   at the cap Create/Recruit point at a project and **Project: Expand
   Guild** appears; its dialog starts the project, whose card then shows on
   the scene's left (the 39/60 test row from 2026-10-10 is already under
   way, so it shows at once and the button stays hidden).
3. Give a test hero Victories (`/eotwdowntime victories 2 <name>`, or win an
   encounter; `/eotwdowntime wound 8 <name>` to hurt them), take a respite: XP up,
   Victories 0, full Stamina/Recoveries, the hammer chip on the strip card,
   `list-heroes` shows `downtime`. Catch Breath on a wounded hero.
4. Roll on Expand the Guild: 3D dice with the amber ghost previewing the
   running total on the bar, "+N", the gain easing in, chip down by one,
   the latest-rolls line. Force a breakthrough with `/eotwdowntime
   breakthrough` (the next roll counts as a natural 20): the
   swords banner (a town-mounted `DramaticBanner` -- untried at the
   titlescreen; the dialog's own "Breakthrough!" label is the fallback),
   "Breakthrough Roll (free)" with no Downtime spent. Complete the project
   (overflow lost): "The Guild Expands!", 5 slots, the goal now 90.
5. Win (and lose) an encounter wounded: the wounds arrive in town; a hero
   home dying is refused by the party picker and auto-claim until they rest.

**Dev commands** (`/eotwdowntime`, in `EotwDowntime.lua`; dev mode or an
admin account; the town must be open): `grant <n> [hero]` gives Downtime
Activities through `grant-downtime` with a fresh `dev-` grant id (every hero
at home when no name is given; a name matches its start), `victories <n>
[hero]`, `wound <n> [hero]` (n damage + one Recovery spent), `tire <n> [hero]` (n Recoveries spent, no damage: enough for a respite; added 2026-10-11), `breakthrough`
(toggles: the next project roll counts as a natural 20), and `state`.

**Known limits.** Rolls are client-reported (the city checks only that the
numbers are possible). A banner shown with `DramaticBanner.Show` writes the
lobby game's banner document; harmless, but noted. Edges and banes from
features on project rolls (`project_roll` modifiers) are not applied --
only the characteristic and +2 for a listed skill.

## Why it is a good loop

- Unspent Victories already matter in combat: a hero starts each fight with
  Heroic Resource equal to their Victories, and town heroes carry Victories
  into every encounter. A respite trades that edge for XP, a full heal and
  Downtime. That makes "press on wounded with 3 Victories, or rest?" a real
  weekly choice. Nothing else is needed to create it.
- Victories are scarce. An encounter gives 1 Victory, and only the first time
  a hero wins that encounter (`ENCOUNTER_VICTORIES`, the "Already Completed"
  exemption), so the Week is roughly 1 per hero per week. A four-hero player
  therefore gets about 4 rolls a week. At about 13 points a roll (2d10 + 2,
  with breakthroughs), the first slot (60) takes a week or two, and all five
  (600 points) take about 46 rolls. That is a long-term goal, as intended. A
  dead hero's unspent Downtime is lost with them.
- Reuse:
  - Respite = core `creature:Rest("long")` (`DMHub Game Rules/Creature.lua`).
    It heals `damage_taken`, converts `victories` into `xp`, and sets a new
    `longRestId`, which zeroes the Recovery usage.
  - Project-roll rules = `Downtime Projects/` (`DTConstants.BREAKTHROUGH_MIN
    = 19`, `RollUtils.IsCrit`, the `_respiteProgressBar` look, and
    `DramaticBanner`).
  - The `Downtime Projects/` UI itself is NOT reusable at the titlescreen.
    `DTProjectRollDialog` goes through `dmhub.SendActionRequest` and
    `GameHud.instance.rollDialog`, and the lobby's GameHud has no
    `rollDialog`. That was checked live on 2026-10-10: reading
    `rollDialog` raises "unknown field".

## Spike results (2026-10-10, live, at the titlescreen)

- `dmhub.Roll{roll = "2d10+2", complete}` works in the lobby game. **The 3D
  dice are thrown and visible over the titlescreen**, and `complete` gets
  `total`, `naturalRoll` and the dice (`total=13 nat=11 dice=5,6`). So the town
  can have real dice, with no engine work.
- `RollUtils`, `DTProjectEditor` and `DramaticBanner` are all loaded at the
  titlescreen (core codex).
- The video (`~/Downloads/Ages of the Vale Pt. 3 Original Day HD.webm`) is
  1920x1080, 30 fps, 30 s, VP9, 7.5 MB. It shows a tavern interior with the
  hearth on the right. The first frame is saved as the poster still
  `C:/dev/eotw/art/blue-fish-inn-poster.jpg`. Neither file is uploaded yet.

## 1. Wounds come home (game side + town apply)

- `OutcomesFor` (`EncounterOfTheWeek/EncounterOfTheWeek.lua`) adds
  `outcome.wounds = {damage = damage_taken, recoveriesUsed = n}` for every
  hero alive at the end.
  - This covers victories AND defeats. Today a defeat's survivors send
    nothing home; with Downtime they send their wounds. A defeat's outcome
    has `result = "defeat"` and no `completed`.
  - An "Already Completed" winner sends 0 Victories but still sends wounds.
  - `OfferAbsentOutcomes` uses the same function, so a player who was away
    also gets their wounds home.
  - A practice game sends nothing (unchanged).
- `EotwRoster.ApplyOutcome` sets those values as **absolute** values in the
  same stamped `ModifyProperties` as the Victories and treasure. Absolute is
  right because the placed copy started from the working copy:
  - `damage_taken = wounds.damage`;
  - Recovery usage moved to `recoveriesUsed`, with `ConsumeResource` /
    `RefreshResource` on `CharacterResource.recoveryResourceId`, "long".
  - **Not carried:** temporary Stamina, conditions, ongoing effects,
    surges and Heroic Resource. In Draw Steel these end with the encounter,
    and the working copy never had them.
  - The `eotwOutcomes[gameid]` stamp already makes this idempotent.
- Spike owed: confirm that a pasted copy keeps the working copy's
  `longRestId`, so that a hero who arrives already wounded shows the right
  Recoveries in the encounter. If the copy gets a fresh id, the arrival must
  copy the usage over.
- **Dying heroes** (Stamina 0 or below, but not dead): see question Q2.

## 2. The Blue Fish Inn (location + respite)

- **Map node** `inn` in `CITY_LOCATIONS`: "The Blue Fish Inn",
  `phosphor/beer-stein-fill.png` (or `fish-fill`; check the glyph exists), at
  **(0.335, 0.575)**. That is the tavern building the map's own "Drunken
  Fool" label points at: the label sits at (0.298, 0.636), and its arrow
  (`Labels/Line 4`) ends at about (0.33, 0.58), read from the PSD on
  2026-10-10. The inn is not on the map at all for a new player: it appears
  once a living hero first comes home from the Town Gate (see "The inn's
  reveal" below). After that it is locked only while the roster has no
  living hero, like the Gate.
- **Scene** (the Guild/Gate pattern, `LocationScene`):
  - The webm is uploaded as a core image asset and passed as the scene's
    `video`, with the poster jpg as the still underneath. Credit: `czepeku`
    badge.
  - This is the first real run of `CreatorCredit.Backdrop`'s video path, so
    expect fixes. The montage stage's `IsVideoAsset` + loop flag is the
    proven way to play a video.
  - The card is on the right like every other location (user direction
    2026-10-10, after first trying it on the left to keep the hearth in
    view). `LocationScene` still supports `scene.cardSide = "left"`, unused.
- **The respite card** ("Take a respite", "24 hours of rest"):
  - It has one row per living roster hero:
    - portrait and name;
    - a Stamina bar with "Stamina 9/21 - Recoveries 3/8";
    - on the right, the trophy count and what the respite gives
      ("+2 XP - +2 [hammer]").
  - A hero who is away in a party is greyed out: "Away: <party>",
    "Can't rest".
  - A hero with nothing to gain (full health, 0 Victories) still rests and
    shows "Rested".
  - The footer sums it up, for example "2 heroes rest: Victories to XP, +3
    Downtime, full Stamina and Recoveries", next to **Take a respite**. A
    second click confirms ("Rest now? Unspent Victories become XP"), because
    it gives up the Victories' combat edge.
  - After the respite, each row plays a short beat: the trophy count ticks
    down into the XP and hammer counts, then the bar fills. The footer turns
    into "You have N Downtime Activities: Expand the Guild (38/60) [Go]" and
    lists the open projects in town with links to their locations.
- **What a respite does to each resting hero.** These are steps on the
  working copy, then `PushHero`:
  1. `Rest("long")`: heals, converts Victories to XP and resets Recoveries.
  2. Stamp `properties.eotwRespites[respiteid] = victoriesConverted`.
  3. Push.
  4. `grant-downtime {grantid = respiteid, grants = {heroid, amount}}` to the
     City.
  - Each step is idempotent and resumable through a machine-local
    `eotw:pendingRespite`, the same pattern as `eotw:pendingOutcomes`: stages
    new -> pushed -> granted.
  - The Victories count is read before `Rest`, and the stamp keeps it. A retry
    after a crash between push and grant therefore re-sends the same amount,
    and the City ignores a `grantid` it has seen.
- **Level-ups:** `Rest` raises `classes[1].level` once XP reaches
  `xpperlevel` (16). At about 1 Victory a week that is months away, and
  encounters still clamp to level 1 (`NormalizeHeroLevel`). See question Q4.

## 3. Downtime Activities (the resource)

- **Held by the City, not on the character record** (recommendation). The
  common operation is spending an activity and adding project points. That
  must be one atomic server action, or a crash between the two loses or
  doubles a roll. Granting happens once per respite, and is already
  idempotent through its `grantid`.
  - It also keeps the counter off the in-game copies, where it means
    nothing.
  - The cost: the hero card reads it from the town's roster list, not from
    the token.
- City: a column `city_heroes.downtime INTEGER DEFAULT 0`. `list-heroes`
  returns it per hero. Granting and spending bump the account's `rosterRev`,
  so other open towns re-list. A fallen hero keeps the number on its row,
  but nothing can spend it.
- **On the hero card** (`EotwHeroCard`): `CreateDowntimeBadge`, modeled on
  `CreateIntelligenceBadge`:
  - an amber chip (`#3a2a10` fill, `#e0a43a` border, `#ffd38a` text) at the
    **top right of the portrait**, with `phosphor/hammer-fill.png` and the
    count;
  - hidden at 0, and town only (it reads `rawget(_G, "EotwRoster")`);
  - tooltip: "N Downtime Activities: spend them on projects";
  - shown on the town strip, in the Guild rows and in the Gate's party
    cards.
  - The card subtitle gains XP ("Level 1 Dwarf Fury - 7 XP").
  - A wounded hero's strip card shows the carried Stamina and Recoveries.
    That already works, because the strip reads the working copy.

## 4. Projects

- **Definitions live in the City** (`CITY_PROJECTS` in `city-core.ts`),
  because the City enforces what a completion does: a slot is checked by
  `put-hero`. The town keeps a Lua mirror for display only (title, blurb,
  icon, location, characteristics, skills).

  ```
  expand-guild: { scope: "player", goal(n) = 60 + 30*n, maxCompletions: 5,
                  effect: "rosterSlot", characteristics: [rea, prs],
                  skills: [Brag, Empathize, Flirt, Lead, Perform, Persuade] }
  ```
- **Scopes:**
  - `hero` (owner = heroid): only that hero rolls. The roster could later
    show a hero's personal projects on their sheet.
  - `player` (owner = userid): any of that player's heroes rolls.
  - `community` (owner = "city"): anyone's heroes roll. It keeps a
    per-player contribution tally and pushes `/city/projectsRev` so open
    towns refresh.
- **Tables:**
  - `city_projects(scope, owner, projectid, completions, points, updated)`,
    primary key (scope, owner, projectid);
  - `city_project_rolls(rollid PK, scope, owner, projectid, userid, heroid,
    total, natural, dice, characteristic, skill, breakthroughOf, open, at)`,
    the log the card shows.
- **Actions:**
  - `list-projects {scope, owner?}` returns `{projects: [{projectid,
    completions, points, goal, maxed}], recent: [...last 10 rolls]}`.
  - `project-roll {rollid, projectid, scope, owner, heroid, total, natural,
    dice, characteristic, skill, breakthroughOf?}`, in one transaction:
    1. Check the caller may roll for this scope (the hero is theirs, living
       and not away).
    2. Charge the roll:
       - **without `breakthroughOf`**, spend 1 Downtime (refused at 0);
       - **with `breakthroughOf`**, the roll is free, but only as the
         follow-up to that hero's own open breakthrough roll. It closes that
         roll.
    3. Add the points.
    4. On reaching the goal: `completions + 1`, apply the effect, and carry
       the overflow (see Q5).
    5. Log the roll. A natural of 19 or more is logged `open = true`.
    - It is idempotent per `rollid`.
    - Sanity checks: the natural must be 2..20 and the total at most
      natural + 10.
    - Rolls are client-reported, which matches the town's existing trust
      stance.
  - An open breakthrough survives a crash or a closed window. Next time,
    the project card offers "Thorga has a breakthrough roll waiting".
- **Expand the Guild and the slot cap:**
  - Slots = 4 + completions of `expand-guild`, at most 9. This replaces
    `CITY_MAX_LIVING_HEROES = 12` in `put-hero` (create) and in
    `list-heroes`, which returns `slots`.
  - Fallen heroes free their slot.
  - Accounts that already hold more than 4 living heroes keep them, but
    cannot create or recruit until they are under the cap (see Q3).
- **The Guild screen:**
  - The header reads "Your roster: 3 of 4 slots", with filled and empty
    pips and five padlocks for the slots not yet built.
  - Create and Recruit are disabled at the cap, with the tooltip "Expand the
    Guild for more slots".
  - The **Expand the Guild** project card sits under the roster list:
    - the title with "expansion 1 of 5";
    - the line "Win over the guildmasters to open a 5th hero slot";
    - a wide bar, "38 / 60";
    - "Reason or Presence - Brag, Empathize, ...";
    - the last few rolls ("Thorga +14 (Persuade) - Pip +13 breakthrough");
    - "Next: 90 points for a 6th slot";
    - the button **[hammer] Work on this project**. It is disabled with a
      tooltip when no hero at home has Downtime ("Rest at the Blue Fish Inn
      to earn Downtime").
  - After the fifth completion it collapses to "The Guild is fully expanded
    (9 slots)".

## 5. The project roll dialog (town modal)

- **Who works on it:** chips for each eligible hero, showing their hammer
  count. Heroes with 0 Downtime are greyed. The default is the hero with the
  best roll, then the one with the most Downtime.
- **Characteristic:** Reason or Presence, showing each value. The default is
  the higher one.
- **Skill:** a dropdown of the project's skills that the hero has. The default
  is the first one. "No skill" is offered when they have none.
- **The formula line** in mono, for example "2d10 + 2 Presence + 2
  Persuade". A skill adds +2, as a Skilled test does.
- **Later:** edges and banes from features. The `project_roll` modifiers
  through `creature:GetModifiersForPowerRoll` may work at the titlescreen;
  that is a spike.
- **Roll (spend 1 [hammer])**:
  1. A fresh `rollid` is saved to `eotw:pendingProjectRoll` before
     anything else.
  2. `dmhub.Roll` throws the 3D dice.
  3. On `complete`, the dialog shows a big "+17", and the project bar
     animates from the old value to the new one.
  4. `project-roll` is sent. A failure retries from the pending entry, so
     the dice result is never lost and never re-rolled.
- **A natural 19-20:**
  1. `DramaticBanner.Show` "Breakthrough!" (the DT editor's wording).
  2. The result says "natural 19 - 9 + 10 + 4".
  3. The button becomes **Breakthrough roll (free)**, with the same hero,
     characteristic and skill, and `breakthroughOf` set.
  4. Breakthroughs can chain.
- **On completion:** a second banner, "The Guild expands!". The newly built
  slot pip lights up and its padlock falls away, and the bar restarts toward
  90 with any overflow.
- The dialog stays open after a roll, so a player with several Downtime
  Activities can keep rolling: **Roll again** / **Done**.

## Decisions (2026-10-10, with the user)

- **Q1. Who rests:** every living roster hero who is not away in a party.
- **Q2. Dying heroes** keep their real Stamina and cannot go out on another
  adventure while dying (the picker and auto-claim skip them; the City
  refuses a claim of a hero whose summary says `dying`).
- **Q3. Rosters already over 4 heroes** keep them; they cannot add a hero
  until under their slots.
- **Q4. Levels:** later. `Rest` is used as it is (it would raise the town
  level at 16 XP); not a concern for now.
- **Q5. Points past a goal are lost** (the book's rule). But a
  **breakthrough on the roll that completes a project** refunds one
  Downtime Activity to that hero instead of an extra roll, since nothing is
  left to roll on (user direction 2026-10-10; the City returns
  `refunded: true`; server `85aeb9e5`). Ampeth's lost refund from the
  first live test was granted back by hand.
- **Flavor** (user direction 2026-10-10): Expand the Guild reads "Recruit new
  Heroes into the Guild." Its start dialog says only "N Project Points to
  complete." and the benefit "+1 Hero Slot" (`benefit` in the project
  mirror).
- **Q6. The breakthrough roll is a button** the player presses (free).
- **Q7. Inn icon:** beer stein (`phosphor/beer-stein-fill.png`).
- Added: **Catch Your Breath** at the inn (spend a Recovery, regain
  Stamina, keep Victories).
- **No project by default** (user direction after the first live test,
  2026-10-10): the inline Expand the Guild card cluttered the Guild. A project
  must be **started** (`start-project`; the City row's `active` flag) before
  it takes rolls, and completing it ends it. The Guild's bottom row gains
  **Project: Expand Guild** beside Create / Recruit, shown only when the
  roster is full, no project is under way and the guild can still grow; it
  asks in a dialog (`EotwDowntime.ShowStartProjectDialog`). A project under
  way shows in the free space on the LEFT of the Guild scene
  (`EotwDowntime.ProjectSidePanel`, through `LocationScene`'s new `side`
  argument). The inn's "spend your Downtime" list offers only projects under
  way, else a way to the Guild. Rows made before `active` existed are under
  way (column default 1).
- **The bar previews and animates the roll** (same direction): while the
  dice tumble, an amber ghost segment past the gold fill shows their running
  total plus the bonus ("39 + 14 / 60"), from each die's `chat.DiceEvents`
  `diceface` events (`dmhub.Roll`'s `begin` gives the dice guids); when the
  roll is recorded the fill eases over the ghost (0.9s, ease-out cubic), the
  count ticks up and the bar flashes; a completion fills to the end, holds,
  then shows the next state. Banners wait for the bar to settle. The
  project card's bar also eases up when its points rise.
- **The dice are the roll button** (user direction 2026-10-10): like the
  game's roll dialog, the project roll dialog shows resting 3D dice at its
  bottom (a `gui.DicePreview` cage armed by `dmhub.Roll{preview = true,
  previewPanel = cage}` through `EotwDowntime.Roll`'s `previewPanel`);
  clicking or throwing them makes the roll. They are re-armed when the
  hero, characteristic, skill or free breakthrough changes and after every
  roll, disarmed when no roll is possible, and a hint line above says which
  ("Click or throw the dice...", "Breakthrough! ... free roll", or why
  not). A too-weak throw re-arms them. The Roll button is gone, and so is
  Done: an X in the dialog's top-right corner closes it (not mid-roll).
  VERIFIED live 2026-10-10: the dice rest armed, re-arm on a characteristic
  change, a click rolls, the amber preview shows on the bar ("43 + 18 /
  60"), the gain eases in, the chip drops by one and the dice re-arm. The
  preview layer sits BEHIND the fill and spans to fill + preview (a
  collapsed sibling in a horizontal flow never showed). After a completing
  roll the dialog's bar stays full and the hint says "Project complete! +1
  Hero Slot." rather than jumping to the next goal. The dialog has a FIXED
  size (860 x 820, `flow = "none"`): the title, bar and choices hang from
  the top and the hint (fixed height) and dice sit on the bottom, so rows
  appearing during a roll no longer resize it (user direction 2026-10-10;
  a fixed height with `flow = "vertical"` would spread the rows instead).
  When the dialog is FINISHED -- the project just completed, it is not under
  way, or no hero at home has a roll left (no Downtime, no free
  breakthrough) -- the dice give way to a big **Close** button at the bottom
  centre; at any other time the X is the only way out (user direction
  2026-10-10).
- **The slot cap is not shown** (user direction 2026-10-10): the Guild's
  pips show only the slots the roster has (no padlocks), the project card
  has no "expansion N of M", and Project: Expand Guild is offered whenever
  the roster is full and no project is under way
  (`EotwDowntime.CanOffer`) -- even at the cap, when its dialog says the
  guildmasters have no room left to grow and offers no Start.

## Build plan

1. **Assets:**
   - upload the webm and the poster jpg as core image assets;
   - check that `phosphor/hammer-fill.png` and the inn icon exist.
2. **City** (`city-core.ts`, `city.ts`, tests, then deploy to staging):
   - the `downtime` column (an `ALTER TABLE` guarded by a column check);
   - `grant-downtime`;
   - `city_projects` + `city_project_rolls`, `list-projects` and
     `project-roll`;
   - `CITY_PROJECTS`, the slot cap, and `slots` + `downtime` in
     `list-heroes`;
   - `/city/projectsRev`.
3. **Game side:** `OutcomesFor` wounds (victory and defeat survivors).
4. **Town:**
   - `ApplyOutcome` wounds;
   - NEW `Codex Titlescreen/EotwDowntime.lua`, registered in the Codex
     Titlescreen codemod before `EncounterOfTheWeek.lua`. It holds the
     project mirror, the respite flow + `eotw:pendingRespite`, the
     project card, the roll dialog + `eotw:pendingProjectRoll`, and the inn
     card;
   - `CreateDowntimeBadge` in `EotwHeroCard.lua`;
   - slots + the project card in `EotwRoster.GuildPanel`;
   - the `inn` location + scene in
     `Codex Titlescreen/EncounterOfTheWeek.lua`.
5. **Verify** single client:
   - win an encounter wounded -> the wounds show in town;
   - respite -> XP, hammer badge, full heal;
   - roll on Expand the Guild, including a forced breakthrough (add a dev
     `/eotwbreakthrough` toggle, as `DTConstants` has);
   - complete it -> 5 slots.

---

# The Arcane Market (BUILT 2026-10-10; not run live)

User direction (2026-10-10): a town location where heroes buy consumable
treasures. Since 2026-10-11 it is **not on the map until the player finds
it** through a lead and a project (see "Leads: carousing at the Blue Fish
Inn").

- **Shopping is a test.** A hero makes a **Presence test**; Alchemy or Magic
  apply (+2 for having either). The result sets how many treasures are on
  offer to that hero:
  - tier 1 (11 or lower): 2;
  - tier 2 (12-16): 3;
  - tier 3 (17+): 4;
  - a natural 19-20: 4, and the hero may buy one more than usual.
- **Buying.** A hero may buy as many of their offered treasures as their
  **Wealth** (`CalculateNamedCustomAttribute("Wealth")`; +1 after a critical).
  Each offered treasure can be bought once. Treasures cost nothing else.
- **Once between encounters.** After the roll a hero cannot roll again, and
  cannot buy past the limit, until they come home from another encounter.
- **The stock** is read live from the compendium, so it grows as items reach
  Gold: every consumable that is echelon 1, `implementation` Gold (4), not
  `hiddenFromPlayers`, and has an `itemPrerequisite` (the book's crafting
  line -- this keeps out the Gold fishing meals, which are rewards, not
  treasures). Plus `EotwMarket.EXTRA_STOCK`: **Imp's Tongue** (Silver only
  because the engine cannot run a real-time hour; in EotW an "until the hour
  ends" effect lasts the whole encounter, and montage use + translation work,
  see "Consumables in a montage"). Live stock on 2026-10-10: Black Ash Dart,
  Buzz Balm, Growth Potion, Healing Potion, Imp's Tongue.

## Decisions (2026-10-10, with the user)

- **Free**: Wealth is a count, not a price.
- **One of each** offered treasure (no duplicates, even with Wealth 2+).
- **Town Gate encounters only** reset the market. A Proving Pits game keeps
  nothing, so it does not refresh the stalls either (no farming).
- **Live pool** (the rule above) plus Imp's Tongue.
- Technical: the dice are real 3D dice in a resting cage, as in the project
  roll dialog; no edges or banes from features (as project rolls).

## As built

| Piece | Where | State |
|---|---|---|
| NEW `Codex Titlescreen/EotwMarket.lua` (global `EotwMarket`; registered in the Codex Titlescreen codemod after `EotwDowntime.lua`, position 8, Firebase confirmed): `Stock`, `Epoch`, `Visit`, `Offer`, `Wealth`, `PurchaseLimit`, `BoughtCount`, `TrainedSkills`, `RollBonus`, `Blocked`, `Roll`, `BuyBlocked`, `Buy`, the stall dialog `ShowShopDialog`, the card `MarketPanel`, dev `/eotwmarket` | new file | luac + typing clean (0); not run |
| The `market` location: node at **(0.695, 0.18)** -- the shop the map's own "Front and Back" label points at -- `phosphor/storefront-fill.png`, locked until a living hero; scene with the looping video; `townContext.OpenMarket`, `m_marketScene` built per visit (like the inn) | `Codex Titlescreen/EncounterOfTheWeek.lua` (`MARKET_VIDEO`, `MARKET_ART`, `CITY_LOCATIONS`, `OpenLocation`/`CloseLocation`) | clean; not run |
| `--- @field eotwMarket?` on `creature` | `DMHub Game Rules/Creature.lua` (annotation only) | |
| Assets: video core image `2d82c3b6-de21-47f0-bfd2-f17708bf4c85` (`isVideo` true) and poster `a2a30693-a725-48fc-90cd-dfd028e58dc8` (first frame via `assets:ExtractVideoFrame`), both tagged `czepeku` | source `C:/dev/eotw/art/arcane-market-black-market-streets-day.webm` (from `~/Downloads/Black Market Streets Original Day HD.webm`, 1920x1080, 30s) | UPLOADED 2026-10-10 |

**Where the state lives: on the hero's own record**, `properties.eotwMarket
= {epoch, rollid, natural, total, tier, critical, skill, offer = {itemid =
place}, bought = {itemid = true}}`, pushed to the City like any edit. No server
change. A purchase is one `ModifyProperties` that gives the item AND marks it
bought, then `PushHero`, so the two cannot come apart. The **epoch** is the
number of encounters the hero has brought home (the keys of
`properties.eotwOutcomes`, which `ApplyOutcome` stamps once per Town Gate
game); a visit counts only while its epoch matches, so coming home opens a
fresh visit with nothing to clear. Proving Pits send no outcome, so they never
move it. `offer` is a map, not a list, because the City stores lists as
numeric-keyed objects. The roll is written the moment the dice land, so
closing the dialog cannot buy a re-roll (a crash with the dice in the air
can; the same stance as project rolls). Trust is the town's usual
client-reported one.

**The screens.**
- **The card** (right side of the scene): "Shop the Stalls", the rules in a
  line, "In stock:" icons (tooltips are the codex item card), then one row
  per living hero: portrait, name, "Wealth N - has not shopped since their
  last encounter" or "Tier 2: 3 on offer - bought 1 of 2" with the offered
  treasures as icons (bought ones bright), and **Shop** / **Browse**. A hero
  away in a party is dimmed ("Away: <party>").
- **The stall dialog** (860x820, fixed like the project roll dialog): before
  the roll, the skill dropdown (Alchemy/Magic the hero has, or No skill), the
  formula ("2d10 +2 Presence +2 Magic"), the four tier lines, "can buy up to
  N (Wealth N)", and the dice resting at the bottom -- click or throw them.
  After the roll: "Tier N" or "Critical!", the roll, "N treasures on offer.
  Bought x of y (Wealth N[, +1 for the critical])", and a card per treasure
  (icon, name, short text, **Buy** / "Bought" / dimmed with the reason in its
  tooltip). The dice give way to a Close button; X and Escape close it too.

**Dev** (`/eotwmarket`, dev or admin, town open): `critical` (next roll is a
natural 20), `reset [hero]` (forget the visit so the hero can shop again),
`stock`, `state`.

**Known limits.**
- A defeat's survivors only move the epoch once the burial write-back's
  `OutcomesFor` (which sends defeat survivors' outcomes) is committed and
  live; until then only a victory reopens the market.
- An encounter's outcome reaches the hero only when the town applies it, so
  a hero just home shows the old visit until `ApplyPendingOutcomes` runs.
- Nothing stops a player buying while another of their machines does the
  same; the revision check on `put-hero` makes the second push fail and
  reload, so the City keeps one consistent record.

**To test** (needs an app RESTART -- new codemod file, and the titlescreen is
built once per run):
1. Town map: the Arcane Market node at the "Front and Back" shop (top right
   of the city, east of the Gate); the scene opens with the video LOOPING,
   header left, card right, the Czepeku badge, Back to Town and Escape.
2. Card: "In stock" shows the five treasures with item-card tooltips; each
   hero row shows Wealth and Shop.
3. Shop: the skill defaults to Alchemy/Magic if the hero has one (formula
   +2); the dice rest armed; click them -> the tier and 2-4 treasure cards.
   Close and reopen: no re-roll, the same offer (Browse).
4. Buy up to Wealth: the item lands in the inventory (hero sheet), "Bought",
   the others dim with "No purchases left...". `/eotwmarket critical` then a
   roll on a fresh hero: "Critical!", 4 on offer, Wealth + 1 purchases.
5. `/eotwmarket state`; restart the app: the visit survives (it came back
   from the City). Win a Town Gate encounter with a shopper: the market
   offers them a new roll.

---

# Leads: carousing at the Blue Fish Inn (BUILT 2026-10-11; not run live)

User direction (2026-10-11):
- **The inn moves** further up and to the left so the hero cards do not
  cover it: the canal-side building west of the Guild, **(0.235, 0.455)**,
  level with the Guild and the Proving Pits.
- **The Arcane Market is not there by default.** A player finds it.
- **A respite needs healing**: at least one hero at home has lost Stamina or
  spent Recoveries. Otherwise Take a Respite is dimmed and says "Your heroes
  are fresh and whole...". No spamming it.
- **Leads** are things a player can learn. While some are left to learn,
  each respite earns **one Carouse** at the inn: the player picks a hero,
  who makes a **Presence test**. Tier 1-2 learns nothing; **tier 3 learns a
  lead**, and learning it is a conversation. The first and only lead so far
  is the Arcane Market, told by **Old Ysolde, an old Elementalist**, that
  the hero talks to: a market you get into with "just the right set of
  contacts".
- **The lead opens a project**, **Find the Arcane Market**: 90 Project
  Points, Intuition or Presence, Alchemy, Magic or Read Person. Each roll
  on it ends with a **line the hero says**, picked by the roll's tier and
  how close the project now is ("This seems like I'm getting close.",
  "Hmmm stymied again, but we'll keep looking.", "If I have to talk to one
  more Crazy Gnome Tinkerer I think I'm going to come unglued...").
- **Completing it** puts the Arcane Market on that player's map for good,
  and the project is gone.

## Decisions taken while building (not asked; easy to change)

- **What counts as hurt:** Stamina below max OR any Recovery spent. A hero
  with Victories but no wounds therefore cannot convert them until they are
  hurt again -- a consequence of the literal rule; say if Victories alone
  should also allow a respite (still unspammable, since they drop to 0).
- **One carouse per respite, lost at the next respite** (not banked).
  After the last lead is learned no carouse is offered at all.
- **Carouse skills** (+2 when trained): Brag, Flirt, Gamble, Music,
  Perform, Rumors (`EotwLeads.CAROUSE_SKILLS`). Tiers are Draw Steel's: 11-,
  12-16, 17+, and a natural 19-20 is tier 3.
- **The Elementalist's portrait** is the bestiary's Rival Elementalist art
  (image `3492c3c2-871e-44c5-abc1-1cde5a7fb097`); her name is invented.
- **Project roll lines, a jukebox** (user direction 2026-10-11/12: the
  same line kept repeating): three progress bands (under 34%, 34-66%,
  67%+) x three moods from the roll's tier (3 hopeful, 2 neutral, 1 fed
  up), three lines each, plus three completion lines (`rollLines` on the
  project). `EotwDowntime.PickRollLine` never picks a line said among the
  project's last 12 while its pool has another; when the whole pool was
  said lately, the one said longest ago plays. The history lives for the
  session (not saved). The user's three lines are used verbatim. Project
  rolls still have no tiers for points; the tier only picks the mood.
- **Where the project lives**: at the inn. Under way, its card shows on
  the inn scene's left (`ProjectSidePanel`), and the inn's "spend your
  Downtime" button opens its roll dialog directly.
- **The market's appearance**: no drop animation (the inn's reveal is
  inn-specific). The completing roll shows the banner "The Arcane Market!";
  back on the map the node appears and its halo beckons three times
  (`RevealFoundLocations`). Accounts that used the market before keep
  their purchases but lose the location until they find it.

## As built

| Piece | Where | State |
|---|---|---|
| City: `CITY_LEADS = ["arcane-market"]`; `testTier`; tables `city_leads(userid, leadid, heroid, at)`, `city_carouse_chance(userid PK, respiteid, at)`, `city_carouses(userid, respiteid PK pair, heroid, natural, total, tier, leadid, at)`; `grant-downtime` with `respite: true` opens the carouse (a resend or a dev grant does not) and returns `carouse`; `carouse {respiteid, heroid, natural, total}` (write bucket; refused unless it is the latest respite, uncaroused, with a lead left; idempotent per respite: `duplicate`); `find-arcane-market` (player, 90, one completion, `effect: "marketAccess"`, `requiresLead`); `start-project` refuses it without the lead; `projectView.locked`; `unlocks.market`; `list-heroes` returns `leads` and `carouse`; admin `dev-reset-leads`; `dev-reset-account` wipes all three tables | `cloudflare-game-server/src/city-core.ts` (section "Leads" at the end), `src/city.ts`, `test/city-core.test.ts` (6 new tests) | tsc + 338 tests pass. **DEPLOYED to staging 2026-10-11** (version `910e1fa0`) |
| Town: `EotwRoster.MarketUnlocked` (unlocks.market, or the project's completions), `LearnedLeads`, `CarouseRespite`, `SetListedLeads` | `Codex Titlescreen/EotwRoster.lua` | clean; not run |
| Town: the `find-arcane-market` mirror (`lead`, `completeBanner`, `rollLines` + the `PickRollLine` jukebox), `EotwDowntime.TestTier`, `RestCandidates().wounded` + `NO_WOUNDS_MESSAGE` (respite gate in `TakeRespite` and the inn card), `respite = true` on the grant, the hero's line in the roll dialog (portrait + quote, after the bar settles), the project card's characteristics from the project (was hard-coded Reason or Presence), inn-located projects open their roll dialog from the inn, `EotwDowntime.UI` (helpers EotwLeads reuses), `/eotwdowntime resetproject [id]` | `Codex Titlescreen/EotwDowntime.lua` | clean; not run |
| NEW `Codex Titlescreen/EotwLeads.lua` (global `EotwLeads`; registered in the Codex Titlescreen codemod after `EotwDowntime.lua`, position 8, Firebase confirmed): `LEADS` (title, project, npc, `conversation(heroName)`), `ORDER`, `CAROUSE_SKILLS`, `CanCarouse`, the carouse dialog (`ShowCarouseDialog`: hero chips, skill, formula, a power-roll tier table like the game's roll dialog (`TierTable`: DrawSteelGlyphs tier glyphs, the tier the tumbling dice show lit gold, a flash when they land; user direction 2026-10-11), dice cage, tier text, "A New Lead!" banner, **Listen...**), `eotw:pendingCarouse` + `ResumePending`, the conversation (`ShowConversation`: NPC figure left, hero right, the speaker lit, typed at 45 cps, click to advance, Escape skips), then the Start Project dialog; `InnLeadsPanel` (Carouse row; Start Project row per learned lead not yet started); dev `/eotwleads` | new file | luac + typing clean (0); needs an app RESTART; not run |
| Map: inn at (0.235, 0.455); market `hidden` unless found; `RevealFoundLocations` (a collapsed node stops thinking, so the town's watcher un-hides it); the inn scene's left shows Find the Arcane Market while under way | `Codex Titlescreen/EncounterOfTheWeek.lua` | clean; not run |

**Dev** (`/eotwleads`, dev or admin, town open): `crit` (next carouse is a
natural 20), `reset` (forget leads and carouses; the latest respite's
carouse opens again), `talk` (replay the conversation; open the inn first),
`state`. To restart the whole hunt: `/eotwleads reset` and `/eotwdowntime
resetproject find-arcane-market`.

**To test** (the City is deployed to staging; RESTART the app):
1. Town map: the inn node sits on the canal-side building west of the
   Guild, clear of the hero cards; the Arcane Market node is gone.
2. Inn with everyone unhurt: Take a Respite dimmed, the footer says why.
   `/eotwdowntime wound 5`, then rest: the Carouse row appears.
3. Carouse: chips with Presence, skill dropdown (Rumors etc.), formula; click
   the dice. Tier 1/2: the result text, no lead, Close; the Carouse row is
   gone. Rest again (wound first) and `/eotwleads crit`: tier 3, the "A New
   Lead!" banner, **Listen...**, the conversation (portraits, typing, click
   through), then "Start a Project: Find the Arcane Market?" (90 points).
4. Start it: its card on the inn's left; the inn's Downtime button opens the
   roll dialog. Roll (grant Downtime with `/eotwdowntime grant 10`): each
   roll ends with the hero's line, varying with tier and progress.
5. Complete it: "The Arcane Market!" banner; Back to Town: the market node
   appears and beckons; it opens as before. Restart: still there
   (`unlocks.market`).

---

# The hero builder and hero sheet (DESIGN 2026-10-03; step engine + builder screen BUILT 2026-10-03)

User direction (2026-10-03): EotW gets **its own guided character builder
and its own simplified hero sheet**, written as new code. The existing
builder and sheet are inspiration and keep their look (same styles, same
theme tokens), but EotW stops opening them.

## What the user asked for

- **A guided builder** that walks the player through the steps in turn and
  steers them to a complete hero: **Ancestry -> Culture -> Career -> Class
  -> Complication -> Appearance**. There is no "Character" step and no
  "Title" step.
- **At most one complication**, and only complications whose automation is
  **gold tier** are offered.
- **Clear progress**: the player can always see what is filled in and what is
  not.
- **"Fill in the rest"**: one button that fills the remaining choices on the
  current page with good defaults where there are any, random valid picks
  otherwise.
- **Level 1 only.** No level control. Level-up comes later and opens the
  builder only when a level-up has actually happened.
- **A simple hero sheet** that the player cannot change. The build decides
  it, and so do the rules of the game. It uses the same styling as today.

## Feasibility (checked 2026-10-03)

**Feasible, with no engine work.** The rules layer already does all the hard
parts, and none of it is tied to the old builder's UI. What is new is the
step engine, the pages and the sheet.

**Reusable as-is (rules and data):**
- Where each choice is stored on the character:
  - `raceid`;
  - `culture.aspects` / `culture.aggregate`, plus the culture language
    `levelChoices.cultureLanguageChoice`;
  - `backgroundid`;
  - `classes = {{classid, level}}`, with the subclass as an ordinary
    `levelChoices` entry;
  - `attributeBuild` (characteristics);
  - `kitid` / `kitid2`;
  - `complications = {[id] = true}`;
  - the inciting incident, which is a `notes[]` entry, not a `levelChoices`
    entry;
  - `characterDescription` (`DSCharacterDescription.lua`), `token.name` and
    `token.portrait`.
- `character:GetClassFeaturesAndChoicesWithDetails()`
  (`MCDMCustomRules.lua:131`) lists every feature and choice from ancestry,
  culture, career, class/subclass, kit and complications. The prerequisites
  are already applied, and nested choices are revealed through
  `FillFeaturesRecursive`.
- The old builder's **data model**, which has no UI in it:
  - `CBFeatureCache`, `CBFeatureWrapper`, `CBOptionWrapper`
    (`Draw Steel Character Builder/FeatureCache.lua`). Between them they
    cover `GetChoices` (already-taken options are excluded), `IsComplete`
    (points-aware), and `SaveSelection` / `RemoveSelection` (one write path
    for every choice type);
  - the synthetic choices the rules API does not return:
    - `CharacterAspectChoice` / `CharacterCultureAggregateChoice`
    - `CharacterCharacteristicChoice` (store the array *index*, because its
      option guids are regenerated on every build)
    - `CharacterKitChoice`
    - `CharacterIncidentChoice`
    - `CharacterComplicationChoice`
  - These are loaded in the running app as globals. **Still to check: that
    they load at the titlescreen.** They should: today's titlescreen Create
    opens the sheet with that module's Builder tab.
- `CharacterBuilder.STRINGS` holds the intro text for each step.
- Race name generators: `token.properties:GetNameGeneratorTable()`, from
  `race.nameGenerator`. They give a default name.
- `/buildchar ... random` (`Codex Macros/Macros.lua:2165`,
  `BuildChar_RandomFillUnchosen`) is a working precedent for random filling.
  It loops until nothing changes, then fills the kit. It is not points-aware
  and skips culture, career, incident and complication, so treat it as a
  reference, not a dependency.

**Why not reuse the old builder's UI:**
- Its panels hang off one global controller and `CharacterSheet.instance`.
- It can only run as a tab inside the sheet harness, which:
  - is one instance per app;
  - has a tab list that is global and fixed when the sheet is built;
  - saves every edit automatically.
- The user wants new code anyway.

**Why not keep the full sheet:**
- There is no read-only mode anywhere on it, and the engine harness saves
  any change.
- A player can edit stamina, recoveries, features and abilities there.
- `GameHud.RegisterCustomInterface` has no hook to replace the sheet, and
  `CharSheet.DeregisterTab` (the Crows approach) replaces it for every game,
  not just EotW.
- Today the town opens it **fully editable**: both the Guild pencil and the
  strip card call `EotwRoster.EditHero` -> `ShowSheet()`. That contradicts the
  "opened read-only" line above.

## Complications: what "gold tier" means

A complication has no automation tier of its own. The tier
(`implementation`: 0 Narrative, 1 Not Automated, 2 Partly, 3 Mostly, 4 Fully
/ Gold; `gui.ImplementationStatus`) sits on each feature in
`complication:GetClassLevel().features`. The complication's tier is
therefore computed, the same way `monster:CalculateImplementationStatus`
works out a monster's: **the minimum over its features, skipping Narrative
(0)**. An unset value counts as 1.

Live counts (2026-10-03, 110 complications):
- **28** have every feature at Gold.
- **44** are Gold once their purely narrative parts are skipped. This is
  the monster rule, and the recommended one.
- An offline YAML pass suggests 3 of the 44 have a nested ability or
  modifier below Gold (Corrupted Mentor, War Dog Collar, Curse of Stone).
  A stricter rule that also looks inside the features would leave about 41.

**Decided (2026-10-03): the 44 rule**, computed live, so the list grows as
the data team raises tiers. Apply each complication's prerequisite
GoblinScript as well, as the old adapter does. A complication that has its
own choices goes through the same choice rows as everything else.

**Treasure-granting complications (BUILT 2026-10-21; verified over MCP,
not yet clicked through on screen).** Secret Twin and Amnesia (the two gold
ones; Betrothed, Strange Inheritance, Cursed Weapon and Artifact Bonded are
not gold) carry a Grant Treasure modifier
(`Draw Steel Modifiers/ModifierGrantTreasure.lua`, "a 1st-echelon trinket
of your choice"). The shared feature cache already turns it into a
`CharacterTreasureGrantChoice` row with the matching trinkets as options,
and the pick is stored in `hero.treasureGrants[modifier guid].itemid`. But
the old builder only hands the item over through a separate **Claim
Treasure** button, which the EotW screen never had. So the row said "Done"
and the hero never got the trinket.

How EotW does it: `EotwBuild.hero.SyncTreasureGrants(hero, token)` keeps
the hero holding exactly the treasure they picked:
- it runs after **every builder write** (the token `Modify` helper);
- it gives the item on a pick (`GiveItem`, then
  `EotwHeroSheet.EquipInPlace` to wear it while a slot is free, as all
  EotW treasure is);
- it takes the item back (`GiveItem(-1)`, which also unequips) when the
  pick changes, the row is unpicked, or the complication changes or is
  removed. That works on a rebuild too.

`state.eotwGiven` records what the sync handed over. A claim made elsewhere
(the full sheet, a pregen) is adopted the first time the sync sees it.
`EotwBuild.hero.Unchoose` special-cases the grant row, because the grant's
own `RemoveSelection` keeps a claimed pick locked. Manifest-mode grants only
record the pick. `RowOptions` replaces the old "then claim it" text with the
choice's new `prompt` field ("Choose a 1st-echelon trinket. It goes straight
into your hero's gear."). Fill picks a random trinket, as for any row.

**Gold trinkets only (user direction 2026-10-21; built, NOT run).** An EotW
hero (`eotwDraft` or `eotwHero`) is offered only treasure whose own
`implementation` is Gold, the same test as the market (`EotwMarket`
`Stocked`). It applies to Amnesia too. Two lists by gear id adjust it
(user direction 2026-10-21):
- `EotwBuild.EXTRA_GRANT_TREASURE` adds below-Gold treasure that plays
  well: **Color Cloak - Red** (the same item as Blue/Yellow; only fire that
  does not come from a power roll cannot be zeroed) and **Gecko Gloves**
  (only the Escape Grab bane is automated, but nothing can be abused);
- `EotwBuild.EXCLUDED_GRANT_TREASURE` removes **Precious Collar**, which is
  for a beastheart's companion only.

So the 1st-echelon trinkets offered are Color Cloak Blue, Yellow and Red,
Hellcharger Helm and Gecko Gloves (5 of 16).

The Silver review also turned away three items:
- **Divine Vine**: its Pull maneuver is not gated on a grab, so it is a
  free pull 6 on anyone within 5 squares;
- **Deadweight**: its Falling Free Strike refunds the maneuver and is not
  gated on falling, so it reads as a free free strike on any turn;
- **Speaking Scarab**: for companions and animals only.

The Divine Vine and Deadweight problems are in the compendium data and
affect every game, not just EotW. They were found by reading the data, not
in play.
Mechanism: `CharacterTreasureGrantChoice.RegisterOptionFilter(id, fn)` in
`ModifierGrantTreasure.lua`, a generic hook that `CreateNew` applies to its
options. EotwBuild registers `"eotw-gold"` the first time `Wrappers` runs,
because Draw Steel Modifiers loads after Codex Titlescreen. Other heroes
and the full sheet's dropdown are unaffected. A non-Gold trinket picked
earlier now shows as a stale pick; Fill or a new pick replaces it, and the
sync takes the old item back.

**Secret Twin's drawback: the assassin (user direction 2026-10-21; built,
NOT run).** The rules: after a respite roll a d10, and on a 1 or 2 the
Director may have your past catch up with you. EotW has no Director, so it
plays this out as follows.

1. **The roll.** Every Blue Fish Inn respite rolls a d10 for each resting
   Secret Twin hero (`RollSecretTwin`, inside `RestHero`'s write in
   `Codex Titlescreen/EotwDowntime.lua`). The roll is silent and logged
   ("rolls N for Secret Twin"). It is skipped while the hero is already
   marked (user choice: no stacking).
2. **The mark and the banner.** On a 1 or 2 the hero is marked
   `eotwAssassinPending` (`EotwDowntime.ASSASSIN_FIELD`). When the respite
   finishes, `ShowPastCatchesUp` shows a malice-type DramaticBanner with
   the hero's portrait, heading "Secret Twin" and the line "You sense your
   past will soon catch up with you...". With several heroes, the banners
   play 4.5 s apart.
   - `ShowBanner` gained `tokenid` / `bannerType` parameters.
   - `DramaticBanner` (`DMHub Game Hud/FullscreenDisplay.lua`) now falls
     back to `dmhub.GetCharacterById` when `GetTokenById` (map tokens only)
     misses. That is what gives an off-map town hero a portrait.
3. **The threat.** The mark rides into the next game inside the pasted
   hero's properties. When the party arrives at a montage, the host's
   `AddAssassins` (`EncounterMontage.lua`, in `HostTick`'s arriving -> rounds
   write) does three things for each marked hero not yet hunted in this
   game:
   - records `{charid, name}` in `m.assassins`;
   - sets `doc.data.assassinsSent[charid]`;
   - unlocks the entry's key (`m.unlocked`), so the stage adds its card
     mid-montage.
   
   Every client then adds the entry to round 1 of that beat inside
   `FindMapScript` (`InjectAssassins`, which first removes earlier injected
   entries). The entry is built by running `EncounterScript.Parse` on a
   snippet (`AssassinEntry`):
   - name: **"An Assassin Hunts <hero name>"**, written `(Locked)`;
   - one option, **Ambush the Assassin**, an Agility or Intuition test
     (Alertness, Sneak):
     - tier 1: the assassin slips away;
     - tier 2: "You lose 3 stamina, the threat is vanquished";
     - tier 3: vanquished;
     - critical (auto): vanquished plus a hero token;
   - **Consequence:** "<hero> takes 4d6 damage". This is a new effect kind,
     `{kind = "damage", heroid, dice, label}`. `ApplyEffects` applies it
     with `LoseStamina` to that one hero. `PendingDice` puts the 4d6 out for
     that hero's player (key `"d:<clause>:<charid>"`). `OUTCOME_OF_EFFECT`
     gives it the harm icon. The entry is not Temporary: a temporary
     threat's consequence skips the player dice.
   
   The test and its tiers were Claude's choice (the user asked for "one test
   to stop it"). Change them in `AssassinEntry`.
4. **Clearing the mark.** `OutcomesFor` (`EncounterOfTheWeek.lua`) sets
   `outcome.assassinMet` for a hero in `assassinsSent`. The town's
   `ApplyOutcome` (`EotwRoster.lua`) then clears the mark, so the next
   respite rolls again. A death needs no clearing. An abandoned or Proving
   Pits game sends no outcome, so the mark stays and the assassin comes in
   the next montage.

The heading and consequence use the hero's name (user choice). A game with
no montage leaves the mark for a later game.

**Worn automatically (user direction 2026-10-21).** The picked trinket is
put on in the builder and on joining the roster. It stays in the pack only
when every trinket slot is already full, which happens only on a rebuild of
a hero already wearing trinkets. The player's own choices are not taken off.

Roster: `JoinRoster` runs `EotwBuild.SyncTreasureGrants(tok)` so every
recruit path is covered. `RecruitTitlescreenHero` strips all items, so it
also unclaims the grants, and the trinket comes back on joining (it is part
of the build, not earned treasure). Roster heroes made **before** this fix
hold a recorded pick but no item. They get it the next time they are opened
in the builder (Rebuild) and any change is made. **Decided (user,
2026-10-21): no automatic repair**; a rebuild is enough.

## Architecture

**Where the code lives.** Core codex, in the **Codex Titlescreen** codemod.
Separate codemods do not load at the titlescreen, and the builder runs there
over the lobby game's working copy. New files (registered through MCP; each
one needs an app restart):
- `Codex Titlescreen/EotwBuild.lua` -- the step engine. Headless, no UI.
  Global `EotwBuild`.
- `Codex Titlescreen/EotwBuilder.lua` -- the builder screen.
- `Codex Titlescreen/EotwHeroSheet.lua` -- the read-only sheet.

Core code also loads in-game, so the sheet works there too.

**The builder is a standalone full-screen panel, not a sheet tab.** It opens
over the town the way the Guild does, and it owns its own lifecycle. Every
write is `token:ModifyProperties{...}` on the lobby-game working copy; the
`CB*` wrappers' `SaveSelection` runs inside the `execute`. After each write
the step engine re-reads the character. `TitlescreenHeroes` and the full
sheet drop out of the EotW path.

**The step engine (`EotwBuild`, BUILT 2026-10-03)** is
`Codex Titlescreen/EotwBuild.lua` (~1,300 lines, typing clean, registered in
the Codex Titlescreen codemod before `EotwRoster.lua`). It has no UI, so it
was driven and tested over MCP before any screen exists. It has two layers:
- **hero functions** (`EotwBuild.hero.*`) take the character properties and
  mutate them directly. The token functions run them inside
  `ModifyProperties`; tests run them on an in-memory
  `character.CreateNew(<Hero type id>)`. A bare `character.new{}` lacks
  `skillProficiencies` and `attributes` and errors;
- **token functions** (`EotwBuild.SetAncestry(token, id)`, `Fill`,
  `Status`, ...) are what the screen calls. Each write is one
  `token:ModifyProperties` (undoable = false). Name and portrait go through
  `token.name` / `token.portrait` + `UploadAppearance`.

`EotwBuild.STEPS` holds the six steps `{id, title, base?}`:

| Step | Main pick (`BaseOptions(hero, stepid)`) | Choice rows |
|---|---|---|
| `ancestry` | `Race` table (`SetAncestry`) | the race's `FillFeatureDetails` (traits, points-bought) |
| `culture` | the typical cultures, `CultureAggregates()` grouped "Ancestry Cultures" / "Archetypical Cultures" (`SetCultureAggregate`) | the 3 aspects (`CharacterAspectChoice`; `SetCultureAspect(category, id)`), the cultural language, each aspect's skill |
| `career` | `Background` table (`SetCareer`) | the career's skills, languages, perk + the inciting incident (`CharacterIncidentChoice`, stored as a note *and* `levelChoices`) |
| `class` | `Class` table (`SetClass`: level 1, locked characteristics applied) | deity, subclass(es), **characteristics** (row id `"characteristics"`; `SetCharacteristics(arrayIndex, build?)`), **kit** (row id `"kit"`), then every level-1 class choice |
| `complication` | gold complications passing their prerequisite (`SetComplication(id)`; `SetComplication(nil)` = "none", stored as `eotwNoComplication = true`; `ClearComplication` undoes both) | the complication's own choices |
| `appearance` | -- | Name, Portrait (a fresh token's portrait is the placeholder `DEFAULT_MONSTER_AVATAR`, which counts as unset: `PortraitIsSet`); `descriptionFilled/Total` counts the 9 optional description fields |

- **`EotwBuild.Status(token)`** returns `{complete, incomplete = {stepid},
  steps}`. `StepStatus(token, stepid)` returns `{id, title, complete, filled,
  total, stale, rows}`. Each row is `{guid (the row id), name, complete,
  remaining, numChoices, selectedNames, stale = {ids}, exhausted, nested,
  base?}`. Base rows have `guid = "base"` (Appearance has `"name"` and
  `"portrait"`). Status is computed fresh every call.
- A row is **complete** when its picks or points are spent, or when no
  option is left to pick (`exhausted`; the old sheet treats it the same
  way). Example: Orc's *Passionate Artisan* is a 2-pick choice with **zero
  options** in the data, so it is always "exhausted". That is a content gap,
  not an engine bug.
- **Stale** = a picked id the row no longer offers. Fill removes stale picks
  before filling. **Not detected yet:** a pick that became a *duplicate*
  (e.g. a culture changed later grants a skill the career already picked).
  The pickers avoid creating duplicates, but a later change can still leave
  one.
- **Writes.** `Choose(token, stepid, rowid, optionId)` /
  `Unchoose(...)` act on the row ids Status reports. A one-pick row swaps
  its pick. An id that is no longer offered can still be removed.
  `HasDependentPicks(token, stepid)` tells the UI whether to confirm before
  `SetAncestry` / `SetCareer` / `SetClass` / `SetCultureAggregate` /
  `SetComplication`. Those setters **clear the step's old picks**
  (`hero.ClearStepChoices`: `levelChoices` entries, incident notes, kit,
  characteristics, kit/companion bonus choices, culture aspects), so nothing
  orphaned is left behind. The old builder left them.
- **`Fill(token, stepid)`** makes the main pick if it is missing, removes
  stale picks, then fills **one pick at a time**, rebuilding the rows after
  each one. That way nested choices (a subclass's abilities, a deity's
  domains) are filled too. A row that refuses a pick is skipped (`stuck`),
  and the loop is bounded at 60 picks. It never replaces a player's pick.
  Order of preference for each pick:
  1. `EotwBuild.DEFAULTS.choices[choiceGuid]` / `DEFAULTS.classes[classid] =
     {array, kit}`. These start **empty**;
  2. the heuristics:
     - culture: the one named after the ancestry ("Elf, High" -> "High
       Elf"); Revenant has none, so it gets a random culture;
     - characteristics: highest values to the unlocked characteristics in
       attribute order;
     - name: the ancestry's name generator (`GenerateName`), or "<Ancestry>
       <Class>";
     - portrait: the class `portraitid`;
  3. random from `GetChoices` (already-taken options excluded,
     points-aware).

  On the Complication page, Fill picks **none**. `FillAll(token)` fills
  every step (a dev convenience: a complete random hero).
- **Parent choices first.** A Conduit's domain rows are subclass choices
  that exist *before* the deity is picked, and change once it is. Rows are
  therefore ordered (on screen and for Fill): deity / ancestry inheritance,
  then subclass, then characteristics and kit, then the rest. Fill uses the
  same order.
- **Gotcha:** the old builder's `CharacterCharacteristicChoice` and
  `CharacterKitChoice` both use the **class id as their guid**. In one
  `CBFeatureCache` they collapse into one row (Kit overwrote
  Characteristics). `Wrappers` gives each of them its own cache and a row id
  of its own.
- **Characteristic option ids are regenerated on every rebuild**, so the UI
  must use `SetCharacteristics(arrayIndex)`. `Choose` on the
  characteristics row also works, but only with an id from the same Status.
- **Level.** `SetClass` writes `classes = {{classid, level = 1}}`. There is
  no level control. Level-up later reuses the engine with a "Level N" step
  that lists only that level's new choices.
- **Possible later source of defaults:** copy the picks of the week's pregen
  for the same class or ancestry wherever they are valid, so every pregen
  becomes a hand-made default. Not built.

**Verified 2026-10-03 (MCP, at the titlescreen):**
- The `CB*` data layer is loaded at the titlescreen.
- 33 in-memory heroes (3 for each of the 11 classes, across all 12
  ancestries) were filled to complete. Every one was level 1 with sensible
  stamina, and only kit-using classes got a kit. The only rows that needed
  a closer look were the Passionate Artisan rows above. Where an ancestry
  culture exists, the culture always matched the ancestry.
- Fill kept a player-picked subclass.
- Switching class cleared every old pick (`levelChoices` back to empty).
- A planted bogus pick showed as stale and was replaced by Fill.
- A gold complication's own choice was filled.
- Clearing the complication made the step incomplete again.
- End to end on a **real lobby character** through the token functions:
  `FillAll` made 29 picks and all six steps were complete. The class art
  replaced the placeholder portrait. A Conduit filled deity before domains.
  The test character was deleted afterwards.
- After an app restart, `EotwBuild.lua` loads from the codemod
  (`READ CONTENTS ... EotwBuild` in Player.log).

## The Skills & Languages step (BUILT 2026-10-03; user direction; untested)

A seventh step, after Class (`EotwBuild.STEPS`: ancestry, culture, career,
class, **skills**, complication, appearance). Skills and languages come from
many sources, so every **skill choice** (`CharacterSkillChoice`) and
**language choice** (`CharacterLanguageChoice`) is made here, not on its
own step.

- **The native language is the exception.** The culture's
  `cultureLanguageChoice` stays on the Culture page, and it is the hero's
  **native language**.
- **Other steps** leave the skill and language choices out of their rows:
  `Wrappers(hero, stepid, includePools)`. Clearing a step's picks still
  includes them.
- **The info box.** The page of a step that grants skills or languages
  shows a small box (`StepGrants`): what it grants outright ("You gain:
  Sneak (skill)") and what it lets the hero choose, plus a "Pick These on
  Skills & Languages" button. Fixed grants are `proficiency` modifiers
  (subtype skill/language) whose `sourceguid` is not one of the step's
  choices.
- **Pools.** `EotwBuild.hero.Pools(hero, kind)` turns each of those choices
  into a pool: capacity = `NumChoices`; allowed = the choice's
  `GetOptions()` (for skills, only unhidden skills from
  `Skill.SkillsById`); current picks = `levelChoices[guid]`.
- **Matching.** The player picks skills, not pools. `MatchPools` places the
  picks into pool slots by augmenting paths (bipartite matching). It tries
  each pick's current pool first, so adding a pick moves as few others as
  possible. A pick sitting in an "any skill" pool is moved to make room for
  a skill only that pool can take.
  - A skill is **selectable** when the current picks plus that skill can
    still all be placed.
  - `TogglePoolPick` adds or drops one pick, re-matches, and rewrites
    every pool's `levelChoices`. Stale picks (no longer allowed) drop out on
    the next write.
  - Fill (`FillPools`) adds random selectable picks until no pool has room.
  - Unit-tested standalone (`MatchPools` extracted and run with the bundled
    `lua.exe`: reroute, refusal, capacity and preference cases all pass).
- **What the page shows** (`PoolTable`):
  - a list of every pool, with its source step, description and remaining
    count;
  - every unhidden skill, grouped by skill group;
  - the native language, then every language.
  - Each card's state is one of:
    - **native**: teal, from the culture;
    - **fixed**: known from elsewhere, tan;
    - **selected**;
    - **selectable**;
    - **unavailable**: dimmed.
  - Hovering a card shows its description, its state, which pools could
    take it, and any special benefit.
- **Special benefits.** A gold star marks a skill that an active `power`
  modifier names in its `skills` array: an edge, a +2, a project-roll
  bonus. Example: Passionate Artisan's chosen crafting skills, once its
  data is fixed. The tooltip names the modifier. Languages have no
  equivalent scan.
- **Not checked in the app yet:**
  - `FixedKnown` / `SkillBenefits` reading `GetActiveModifiers()` entries
    (`entry.mod`);
  - `innateLanguages`;
  - the step's status rows (the generic `RowStatus` over the pool rows,
    whose "exhausted" check uses each row's own free options, not the
    matching).

## The builder screen (BUILT 2026-10-03; three rounds of user testing)

`Codex Titlescreen/EotwBuilder.lua` (global `EotwBuilder`; registered in the
Codex Titlescreen codemod after `EotwBuild.lua`; typing clean).
`EotwBuilder.Open{host, token, title?, step?, onFinish(token),
onClose(token)}` mounts a full-screen opaque panel on `host` (the town
screen, above the Guild dialog; `escapePriority = 5`). Every write goes
through `EotwBuild`, and then the whole screen redraws from
`EotwBuild.Status`.

**Redraws are incremental (round 3).** The page is a list of keyed blocks
with signatures:
- the title and intro;
- the main-pick cards (signature: the current pick);
- the grants box;
- one block per choice row (signature: its status plus every option's
  selected/available state; characteristics add the values and the
  half-done swap);
- the Appearance page as one block (name, portrait, frame and anthem).

A block whose signature is unchanged keeps its panel, and only changed
blocks are rebuilt and swapped into the same content panel. Rebuilding the
whole page flickered on every pick. The stepper and summary lines are
skipped when their signatures are unchanged.

**Scrolling.** The page keeps its scroll offset **in pixels** across
redraws: `ScrollOffset` before the rebuild, then `RestoreScrollOffset`
after layout (applied at once, then again at 0.05 s and 0.2 s). The page's
content panel is fresh only on a new step. When blocks are swapped in
place, the offset is restored only after layout. Keeping the 0..1 fraction
instead sent the page to the bottom when it grew (picking a class), and a
page that did not scroll read as 0, which is the bottom.

**Look.** The old builder's cream-on-near-black palette (`CBStyles.COLORS`)
in local rules. The root cascade is `ThemeEngine.MergeStyles(CBStyles
rules + EotwHeroCard.rules + ours)`, so ability and kit renders in the
detail pane get their usual classes. It is re-merged on `OnThemeChanged`.

**Layout.**
- **Header**: the title ("Create Your Hero" / "Rebuild Your Hero"), the
  **stepper**, and **Save and Close**. The stepper has six pills; each shows
  a number, or a tick when done, plus "Not started" / "n left" / "Done" /
  "Needs attention" (stale). Every pill is clickable.
- **Summary rail** (left, 360): the town's own hero card
  (`EotwHeroCard.CreateHeroCard`, characteristics + stamina + recoveries)
  and lines for Culture, Career, Kit and Complication.
  - **The card is built once.** Only the lines are rebuilt; rebuilding the
    card on every redraw made it flicker through the placeholder image.
  - **It repaints only on `refreshCard`**, which its host must fire. The
    rail fires it on create and every 0.25 s, as the town strip does.
- **Page** (centre, scrolls):
  - the step's title and intro (`CharacterBuilder.STRINGS`);
  - **main-pick cards**. Culture groups them under "Ancestry Cultures" and
    "Archetypical Cultures", then "Or build your own culture from three
    aspects". Complication puts "No Complication" first;
  - **one block per choice row**: name, a status line ("Choose 2", "3
    points to spend", "Done", "Nothing left to choose", or the stale
    warning), the row's description, and option chips. A chip that is
    taken elsewhere or unaffordable is dimmed; clicking a chip
    picks/unpicks it.
  - The **characteristics** row's chips are the arrays. Under them are the
    five characteristic boxes, with fixed ones marked. **Drag one onto
    another**, or click both, to swap their values
    (`SetCharacteristics(array, build)`). Clicking uses `click`, not
    `press`, because press also fires when a drag ends.
  - **A one-pick row** (subclass, kit, deity, ...) switches its pick on a
    click of another option: `RowOptions` marks every offered option
    available, and `Choose` swaps the pick. Before this, the player had to
    unpick first.
- **Detail pane** (right, 500): what the player is looking at.
  - **Main picks**: hovering a card previews it while nothing is chosen,
    and the preview **stays** after the pointer leaves, until another card
    is hovered. Once something is chosen, the pane stays on the chosen item
    (user direction 2026-10-03). The Complication page always previews,
    because "No Complication" is a default, not a choice.
  - **A class or ancestry** fills the whole pane with its art
    (cover-cropped, top kept; `CoverCrop`), with the name and text on a
    darkened band. The crop waits until both the image and the panel size
    are known: `imageLoaded` can come before layout, or not at all for a
    cached image, so a 0.05 s think retries it until it succeeds. Round 3:
    the art was sometimes stretched before this
    (`#10110Fe6`) over the lower part that scrolls when long. This is the
    old builder's look (user direction).
  - **A subclass or domain** shows its description and what it grants at
    1st level (`FillFeatureDetailsForLevel(..., 1, ...)`), with ability
    cards for the abilities.
  - **A typical culture** shows what it sets: each aspect with its
    description and the choices it offers, and its language.
  - **A kit** shows the whole kit (`Kit:Render`: bonuses, signature
    abilities, maneuver).
  - **An ability pick** shows its ability card (`AbilityCard`), rendered top-aligned
    (`ability:Render{valign = "top"}`), with no repeat of the flavor text.
    The old `CBOptionWrapper:Panel()` render left a large gap above the
    card and repeated the text.
  - Anything else falls back to `CBOptionWrapper:Panel()` plus the option's
    description.
- **Footer**: a message line (fill results, "Still to do: ..."), **Back**,
  **Fill in the Rest** (disabled on a complete page; after it fills a page
  it turns into **For All Tabs?**, which fills every remaining tab via
  `EotwBuild.FillAll` -- changing page or any other edit turns it back), and
  **Next**. Next
  reads "Skip for Now" on an incomplete page and "Finish" on the last step.
  Finish with steps incomplete lists them and jumps to the first.
- **Changing a main pick** that has dependent picks asks first
  (`EotwBuilder.Confirm`).

**The Appearance page** (user direction 2026-10-03: no Description section):
- **Name**: an input that saves on edit (0.5 s lag) without rebuilding the
  page, which would steal focus; plus **Suggest a Name** (the ancestry's
  name generator).
- **Portrait**:
  - a 240px **framed preview** (portrait + `bgimageTokenMask` frame,
    `portraitRect`). **Drag** it to move the portrait (`portraitOffset`);
  - a **Zoom** slider (`portraitZoom`) and **Reset Placement**;
  - **Use Class Art**, **Use Ancestry Art**, and an `IconEditor` (library
    Avatar) to pick or upload an image;
  - **The portrait defaults to the class art**: `EotwBuild.SyncDefaultPortrait`
    runs on every redraw. A portrait that is unset, or is still *some*
    class's art, follows the current class. Ancestry art or an upload is
    left alone.
- **Frame**: an `IconEditor` on the `AvatarFrame` library (`portraitFrame`;
  none allowed).
- **Anthem**: `gui.AudioEditor` (autoplay through the `anthem` mix group)
  and a volume slider (`anthem`, `anthemVolume`).
- The description fields and their engine helpers were removed.

**Wiring (`EotwRoster`).**
- **Create a Hero** -> `EotwRoster.CreateHero(host)`. It reopens the
  player's **draft** (`EotwRoster.FindDraft`: a lobby character with
  `eotwDraft = true` and `creatorid` = this user) if there is one.
  Otherwise it creates a Hero-type character stamped `eotwDraft = true`
  (with `mtime`/`originalid`/`creatorid`) and opens the builder on it.
- **Finish** sets `eotwDraft = false` and goes through `JoinRoster` (which
  stamps `eotwHero` and pushes to the city).
- **Save and Close / Escape** keeps the draft, unless `EotwBuild.IsUnstarted`
  (nothing chosen, no name, no portrait), in which case the character is
  deleted.
- **The Guild**: Create reads **Continue Your Hero** while a draft exists,
  and a **Discard Draft** button appears (click twice).
- **The pencil** on a Guild row opens the builder ("Rebuild Your Hero") when
  `EotwRoster.CanRebuildHero`: the hero is on the roster and not away in a
  party, i.e. home in Blackbottom. Encounters played no longer lock the
  build (user direction 2026-10-20, replacing "until the first
  encounter"). Otherwise it opens the EotW hero sheet. Rebuilding pushes to the city on close and on finish. A hero rebuilt into
  an incomplete state is still pushed, and nothing stops it yet.
- The town strip's card still opens the old sheet.
- Drafts are kept out of the titlescreen's campaign heroes (`LobbyHeroes()`
  skips `eotwDraft` as well as `eotwHero`). The roster sync never sees them,
  because it only handles `eotwHero` characters.

**Complication defaults to No Complication** (user direction 2026-10-03).
The step is complete from the start, so it never blocks Finish. Its pill
and header read **"Optional"**, with no tick, whenever no complication is
taken, and **"Done"** only once one is chosen. `EotwBuild` reports
`optional` (= no complication) on the step and its base row. The "No
Complication" card shows as selected. The portrait
thumbnail in the picker is cover-cropped, not stretched.

**Round 4 changes (2026-10-03, user direction; addressed in code, not re-tested):**
- **Default portrait.** The default is the **ancestry's art** until a class
  is chosen, then the class's. `SyncDefaultPortrait` treats any class or
  ancestry art as "the default".
- **The ancestry's culture.**
  - Picking an ancestry fills in its own culture (`AncestryCultureId`: "Elf,
    High" -> "High Elf"): aspects plus native language, flagged
    `eotwAutoCulture`.
  - The Culture step then reads **"Optional"** (complete, so it never
    blocks Finish).
  - Any change the player makes clears the flag, and the step reads "Done":
    choosing a culture, an aspect, or the language.
  - Changing ancestry again re-applies the culture while it is still the
    automatic one. If the new ancestry has no culture (Revenant), an
    automatic culture is cleared.
- **"Known" says where from.** `GrantSources` maps each outright-granted
  skill or language to a phrase like "your career (Agent)", built from
  each source step's `StepGrants().fixedIds`. The native language says
  "your culture"; anything unmatched says "another of your features".
- **Dead languages** (`Language.dead`) carry a "(dead)" suffix and a
  violet, italic style, and their detail says they are read, not spoken.
- **Appearance flicker.** Appearance is three blocks: name, portrait and
  extras.
  - Suggest a Name writes the input directly and redraws only the chrome.
  - The portrait block's signature is portrait + zoom + offset.
  - The extras block reaches the preview through `state.preview`.
- **Portrait thumbnail.** The `IconEditor` swaps its own image, and
  `imageLoaded` never reached our handler, so a 0.1 s think cover-crops
  each new image once.
- **Save and Close becomes Finish** once every step is complete
  (`UpdateFooter`; the click finishes).
- **New heroes start active.** `JoinRoster` (Create and Recruit) calls
  `SetActive` after a successful push if fewer than four heroes are active.

**User testing, round 3 (2026-10-03), addressed, re-tested in round 4:**
- Complication says Optional rather than Done;
- flicker when picking on a scrolled page;
- the Skills & Languages step;
- art stretching;
- ancestry art like classes.

**User testing, round 2 (2026-10-03), addressed, re-tested in round 3:**
- the preview reverted on dehover;
- the hero card flickered;
- picking a class scrolled to the bottom;
- one-pick rows had to be unpicked first;
- thin subclass details;
- class art should fill the pane;
- drag-to-swap characteristics;
- Complication defaults to none / "Optional";
- a stretched portrait thumbnail.

**User testing, round 1 (2026-10-03), all addressed, re-tested by round 2:**
- hover previews stuck after a pick;
- the page scrolled to the bottom when changing step;
- no culture overview;
- kits showed only a description;
- the ability preview had a gap above it;
- the Description section was replaced with anthem, frame and placement;
- the hero card never showed the name or portrait;
- the portrait now defaults to the class art, with Use Ancestry Art added.

**Not yet checked:**
- the drag direction of the portrait offset (copied from the old Appearance
  tab);
- whether the anthem autoplays when the Appearance page opens on a hero
  that already has one;
- an end-to-end Finish -> roster -> city push;
- Continue/Discard Draft;
- the Rebuild path.

**Cleanup owed:** a test character `94056de3-a979-4d3b-acd2-3a4862ac0aee`
may have been left in the lobby game (created for a look at the old
builder just as the app switched games). If it shows among the
titlescreen heroes, delete it.

## The hero sheet

`EotwHeroSheet.Show(token)` is a read-only full-screen panel. It is built
from the character every time it opens, and it has no edit controls at all.
It shows:
- **Header**: portrait, name, "Level 1 <Ancestry> <Class> (<subclass>)",
  culture, career, complication;
- **Stats**: characteristics, Stamina / Recoveries / Recovery Value, Speed,
  Size, Stability, Disengage, Potencies, and the heroic resource name;
- **Skills and languages**: a flat list;
- **Kit**: its name and bonuses;
- **Abilities**: `ActivatedAbility:Render` cards, grouped by action type;
- **Features**: name and text, grouped by source. Complication benefit and
  drawback come from `CharacterComplication:Render`;
- **Inventory**: list only.

It opens from:
- the Guild row (replacing the pencil);
- the town strip card;
- later, the in-game hero card (which opens the read-only character panel
  today) and another player's hero (which needs a way to render a hero that
  is not a lobby character: a temporary import, or a detached creature).

The only actions on the sheet are Close and **Edit in Builder**. Edit in
Builder appears for the player's own roster hero, in town, whenever the
sheet is open (disabled while the hero is away with a party; 2026-10-20).

**Hardening (later).** In an EotW game, the token radial menu, the "sheet"
keybind and the character-panel context menu can still reach the full
sheet. Point them at `EotwHeroSheet` for `eotwHero` characters.

## Build order

1. ~~**Step engine, headless.**~~ DONE 2026-10-03 (see "The step engine"
   above for what was verified).
2. ~~**Builder shell**~~ BUILT 2026-10-03 (see "The builder screen").
3. ~~**The remaining pages**~~ BUILT 2026-10-03; round-1 feedback addressed,
   re-test owed.
4. ~~**Guild wiring**~~ BUILT 2026-10-03 (drafts, Continue/Discard,
   Rebuild). Still owed: a live end-to-end with a kept hero; this also
   closes "Create through the builder" in "The town client".
5. **Hero sheet**: switch the Guild and the strip to it.
6. **Later**: the in-game card, other players' heroes, the hardening above,
   the pregen-derived defaults, and level-up (with Phase 11).

Size so far: engine ~1,350 lines, builder screen ~1,900 lines; sheet estimated ~1,200.

## Decisions taken (2026-10-03, with the user)

1. **Gold rule: the 44.** A complication is offered when every
   non-Narrative feature is Gold, computed live.
2. **Fill in the rest on the Complication page chooses no complication.**
3. **One resumable draft per player**, local only, not counted against the
   12.
4. **Editing after creation:** ~~allowed until the hero's first encounter;
   after that only level-up changes the build.~~ SUPERSEDED 2026-10-20 (user
   direction): the builder stays open to a hero any time they are back in
   Blackbottom (not away in a party). Rebuilding touches only build choices;
   treasure, wounds, Victories, XP and downtime are untouched. **Ancestry
   and Class are fixed at creation** (user direction 2026-10-20): a rebuild
   opens the builder with `lockedSteps = {ancestry, class}`, and those pages
   show only the chosen card under "Your ancestry/class" with a note that it
   can't be changed. Everything under them (traits, subclass, kit,
   characteristics, level-1 choices) stays editable. A locked step whose
   pick is somehow missing is not locked. Because the class cannot change,
   `SetClass`'s reset to level 1 can never hit a levelled hero; the builder
   still offers only level-1 choices, which level-up will have to extend.
5. **Free navigation:** the player can skip around. Unfinished steps they
   leave stay marked incomplete, and Finish requires all six.
6. **Appearance:** name and portrait are required, and everything else is
   optional. No saddles. The class art is the default portrait, and the
   player may upload their own.
7. **Culture:** the typical (aggregate) cultures come first, and "build your
   own from three aspects" is the secondary option.
8. **Reuse the old builder's data layer** (`CB*` wrappers and synthetic
   choices) under the new UI.

---

# Entering the game

## The arrival handoff

The titlescreen's `EnterWorld` (every entry path funnels through it: host on
launch, members on ready, Resume, Re-join):

1. copies the player's claimed lobby heroes to the engine token clipboard
   (`dmhub.CopyTokensToClipboard`; the clipboard is C# static state and
   survives the game switch, the lobby tokens do not);
2. fires `overrideLoadingScreenArt` so every player gets the standard loading
   screen;
3. calls `dmhub.HoldLoadingScreen()` (see below);
4. parks the setup arguments in `_G.EotwPendingArrival` (keyed by gameid);
5. calls `lobby:EnterGame(gameid, fn)`; the callback marks the parked args
   ready and calls `EncounterOfTheWeekGame.ConsumePendingArrival()`.

The game-side codemod calls `ConsumePendingArrival` at load too, and whichever
runs second starts `SetupOnArrival`, exactly once. The game's codemod list
can arrive after loading finishes, so neither order can be assumed.
**Setup runs only through this handoff, never on plain game entry**, so the
authoring game (which also loads the codemod) never spawns monsters into
itself. Entering an EotW game from the campaigns list runs no setup.

`EncounterOfTheWeekGame.IsEotwGame()` is true when the game is this account's
EotW slot or the shared state doc (`eotwstate`) carries the host's
`eotw = true` stamp. `ClearEotwMarker()` is the dev reset if setup ever runs
in the authoring game.

## The loading-screen hold

`dmhub.HoldLoadingScreen()` / `ReleaseLoadingScreen()` /
`dmhub.loadingScreenHeld` (engine, static state). When a hold is set, the
engine fires the arrival callback while the loading screen is still up and
waits for the release (20s timeout, logged) before clearing it. Leaving the
game clears any hold. The host's setup presents the opening stage beat
(`BeginOpeningMontage`, which handles a narrative or a montage) before
placing heroes. The stage's `create` releases the hold, so the loading screen
dissolves straight onto the stage. A week with no opening stage releases
after hero placement. **A new engine with an old game-side module never
releases and eats the 20s timeout**, so ship the codemod with or before such
a build. Each further `HoldLoadingScreen()` call re-arms the timeout (engine
2026-10-08), which is how a fast-launch member waits out the host's setup.

**The reveal waits for the whole party (2026-10-08).** Releasing on the
stage's `create` showed the host's heroes alone, with the others' heroes and
the beat's `Unlock:` features (Intelligence) popping in seconds later. Now the
stage's release is gated on `EncounterOfTheWeekGame.RevealReady()`: no
narrative or montage beat still in `"arriving"`. The host opens that beat
(`OpenOpeningBeatWhenPartyIn`, a direct call of the beat's `HostTick`, not
waiting for the map-script driver's first tick) the moment
`AllPlayersArrived()`, and opening it applies the first section's unlocks in
the same write. A member's characters reach every client before its arrival
stamp (one DO, ordered broadcasts), so the opening implies every hero is
there. `AllPlayersArrived` skips its 3s settle while an opening stage is
arriving (nobody can load into the middle of anything). Each client renews
its hold while it waits and reveals anyway after 45s
(`REVEAL_WAIT_MAX_SECONDS`), so a player who never arrives cannot trap the
rest. A week with no opening stage releases once `AllPlayersArrived()`.

## Launch timing

Every step of a launch logs an `[EOTWPROF]` line with `dmhub.serverTime`
(shared by all clients, so the host's `Player.log` and a player window's
`dmhub_player.log` merge onto one clock): Begin, `launched`/`ready` seen,
`lobby:EnterGame`, the arrival callback, each `SetupOnArrival` step, the
ready-game connection and ack, and the stage's create/release. The engine's
`[LOADPROF]` lines cover the load itself (milestones, each `InstallModule`
stage, the hud build, the loading-screen hold); launch the app with
`--no-load-opt` to turn the engine's load speedups off for an A/B.
Measure with `/debug` off: it makes every panel ~60us slower, and the hud
build goes from ~0.6s to ~2s.

What the 2026-10-08 work changed, besides the fast launch:
- engine: a whole dictionary arriving on a game-record stream (e.g. the
  host's `codeModsFromModules` write) was silently dropped by
  `PatchObject`, so a member who entered before the install never loaded
  the EotW codemod; fixed in `GWSerialization.PatchObject`.
- engine: the install now registers the module's code mods as it writes
  them (`SyncGameCodeMods`), so they load during the install instead of
  after the hud is built (which then rebuilt the hud).
- engine: start on the party's map (`lobby:EnterGame(..., {startMap})`) instead
  of the module's first map and travelling; no 1s update embargo on the
  WebSocket backends; the module snapshot is cached on disk by its content
  hash; the map uploads go out together; the two asset reloads of the
  first game update are coalesced into one.
- Lua: pregens paste in one batch; the character sheet's Inventory tab is
  built when first shown.

## Setup on arrival (`SetupOnArrival`)

On every member's client, inside the arrival coroutine:

1. **`EnsureOnEncounterMap`**: resolve the chosen map (argument -> the host's
   `eotwstate.encounterMap` stamp -> `Encounter`), travel there if needed,
   wait for the switch. The host then stamps the name for late joiners and
   resumes.
2. **`PlaceMyHeroes`**: each player places their own heroes (only their
   machine has their lobby heroes).
   - Lobby heroes: one batch `dmhub.PasteTokensFromClipboard(loc)` at the
     Start-zone tile nearest the zone's centroid.
   - Pregens are already in the game (installing the module writes its
     characters); the player duplicates one with a same-game copy/paste.
   - **Claim order matters**: set `partyId = GetDefaultPartyID()` *before*
     `ownerId = loginUserid`, because the engine's `partyId` setter
     force-writes `ownerId = "PARTY"`. A DM-side paste otherwise lands as an
     ownerless hostile.
   - Vacancy across separate paste calls needs a wait: pasted characters
     reach the local mirror only on the server echo, so `WaitForPastedCharacters`
     waits for them to resolve, then `game.UpdateCharacterTokens()`.
     `UnstackPlacedHeroes` repairs the cross-client race (two players pasting
     onto the same tile in the same instant) deterministically: sort the pile
     by charid, the lowest keeps the tile, the rest move to the Nth free Start
     tile in a shared order.
   - Re-entry guard: `eotwstate.placedHeroes[userid][kind:heroid] = charid`.
     `ResetPlacedHeroes()` is the dev reset.
   - Every placed copy runs `ClaimPastedHero` -> `DetachFromLobbySync`
     (clears `properties.originalid`/`creatorid`; otherwise the engine's
     campaign-to-lobby character cache copies the EotW copy's combat state
     back over the lobby hero) -> `NormalizeHeroLevel` (exactly level 1:
     every class entry and `levelOverride` to 1, and `extraLevelInfo.encounter`
     cleared so a slow-start hero is promoted; multiclassing is logged, not
     fixed). Both are `undoable = false` patches issued only when needed.
     They touch the game's copy, never the original.
3. **Host only**: write `numheroes` (clamped 3..7, the setting's range),
   `permission:playersinitiative = true`, the forced settings (see "Strict
   rules and forced settings"), `SeedHeroTokens` (one Hero Token per hero,
   once per game), `SweepPlayersParty` (moves unclaimed module characters out
   of the default party into the pregens' party, elected by majority),
   `AttachMapScript`, then `SignalGameReady` (sends `ready-game` over its own
   lobby connection).
4. Every member stamps `arrived[userid]` once its heroes exist (on the host,
   after the game-wide writes of step 3), THEN runs `UnstackPlacedHeroes`
   (its 1s+ wait for other clients' pastes is off the reveal's path; the stage
   covers the map while it moves anyone). Since 2026-10-08 the host sends
   `ready-game` and attaches the map script right after the opening stage
   begins, before placing its own heroes; and a fast-launch member already on
   the party's official map places its heroes before waiting for the host's
   `setupReady` stamp.

Loc gotcha: a Loc's floor reads as `loc.floor`; `loc.floorIndex` is the
constructor argument and reads nil, and a floorless Loc teleports to floor 0.
Derive destinations from an existing Loc (`ref.loc:dir(dx, dy)`).

No welcome documents: `DocumentNewUser.ShowDocumentOnStart` returns early in
an EotW game (three pcall-guarded signals, since the codemod may not be
loaded yet).

---

# The directorless game

## Player host

EotW games are created `directorless = true` (`GameInfo.directorless`). The
host's machine keeps hosting -- it installs, runs setup, runs the Monster AI
and the map script -- while its user is a **player**: player vision, player
UI, bound by the strict rules. The engine model, the flag table and the
audited list of sites are in
[`PERMISSIONS_MODEL_REFERENCE.md`](../../PERMISSIONS_MODEL_REFERENCE.md).
The rules of thumb that matter for EotW code:

| Read | Means | Use for |
|---|---|---|
| `dmhub.isDM` | the Director *experience*; false on a player host | UI, strict-rule gates, anything about what the user sees or may do |
| `IsDMOrPlayerHost()` (`dmhub.isDMOrPlayerHost`) | this machine hosts | host-only work: setup writes, elections, teardown |
| `token.canControl` | elevation-aware: on a player host, true for monsters only inside host elevation | most code; it presents the host as a player |
| `token.canControlAsUser` / `TokenControlledByUser(tok)` | the user's own tokens, never elevated | user-driven UI (End Turn, selection, drag) |
| `canControlAsHost` (C# only) | the old capability body | un-elevated host-machine work in the engine |
| `GameHud.DirectorUIVisible()` | `isDM` plus registered presentation filters | Director chrome |

**Host-permission elevation**: `dmhub.ExecuteWithHostPermissions(fn)` (fn
must not yield) and `dmhub.PushHostPermissions()` /
`PopHostPermissions()` for a whole coroutine; codex helpers
`ElevateToHostPermissions()` / `DropHostPermissions()`. Elevation is parked
whenever the coroutine yields, so nothing outside a Lua execution window
(rendering, vision, UI) ever sees an elevated `isDM`. It restores Director
*capability*, never presentation. The Monster AI's coroutines and every EotW
host-side write (zones, objects, montage effects, combat start) run elevated.

When something works for a Director but not for a player host, look for an
`isDM` read that is really a capability (journal access needed
`GetAccessibleRoots(hostAccess)`; the map's encounter lookup passes
`hostAccess = true`), or a `canControl` read that is really a user question.

**Debug hatches.**

- `/toggle eotw:showdirectorui`: a per-account preference that restores the
  full Director experience (and the normal interface) in an EotW game. It
  sets `dmhub.playerHostModeSuppressed`, which forces a refresh. This is the
  manual-recovery path.
- `--director` launch flag: the title-bar Codex menu's **New Director Window**
  is offered to dev + admin accounts on a player host and launches the child
  with it. The child is a full Director from its first frame while the parent
  stays a player host. Nothing stops the debug window from being elected as
  the map-script host.
- (`/toggle eotw:forcecustomui`, which forced the EotW interface on in any
  game, was retired 2026-10-05: the authoring game always shows the Director
  interface, and the authoring test is how to see the EotW one there. See
  "The authoring test".)

## Strict rules and forced settings

The host writes `g_forcedGameSettings` at setup and re-asserts them every
host tick (writing only what differs):

| Setting | Value | Why |
|---|---|---|
| `strictmovementrules` (engine) | true | "strictly enforce all rules" |
| `strict:movement`, `strict:targeting`, `strict:resources`, `strict:inventory` | true | |
| `strict:rolls` | true | withdraws re-roll, expression editing, click-a-tier overrides, modifier toggles, the edge/bane bar, and backing out of a cast that has paid |
| `enemystambardisplay` | `"bar"` (from `EncounterPrep.EnemyStaminaDisplay()`: `none`/`bar`/`val` when the week sells it on the preparation screen) | players see bars, not numbers |
| `hpbarsonlyincombat` | false | bars from arrival |
| `monsterinfo`, `monsterinfoautolearn` | true | players learn stat blocks with no Director |

**Line of effect under `strict:targeting`** (2026-10-03). A single-target
ability's (`targetType == "target"`) candidate is invalid when the caster
has no line of effect to it, or it is beyond a "Line Of Effect Limit"
(Dazzled). Strict targeting then refuses the player's click and flashes the
arrow's "No Line of Effect" / "Beyond Line of Effect" label. Before this,
the arrow showed the label but the click went through, so heroes could
strike through walls. One helper,
`DrawSteelActionBar.LineOfEffectFailReason` in
`DrawSteelActionBar/DrawSteelActionBar.lua`, drives both the label and the
validity flag, measured from the same origin as the arrow (the caster, or a
closer casting-origin relay). Area abilities were already safe:
`ActivatedAbility:TargetPassesFilter` drops targets with no line of effect
from the area's origin (and from the caster for `"all"`). Not covered: squad
strikes (each minion draws its own ray; players don't run squads in EotW),
aura casts with a `casterLocOverride`, and the action bar's "choose a
target" prompt used during resolution, which has its own reasons table.
Wall voxels are not blocked by their own wall: a hero facing a wall's near
side has line of effect to those voxels (checked live).

`strict:hiddeninvisible` is deliberately not forced. Since all of these gate
on `isDM`, they bind the player host. `strict:resources` also refuses
off-turn use of turn-bound abilities (main action, maneuver, move) in the
action bar; the drawers still open so players can read them. Arrow-key
movement honours the same gates as dragging (`token:Move{playerMovement =
true}`).

Monster stamina: exact stamina shows on a monster's bar (and in Monster Info)
once the party knows it -- the third kill via auto-learn, a Director reveal,
or a montage `you know the stamina of <keyword>` clause
(`MonsterKnowledge.RevealStaminaForKeyword`, keyed by stat-block keyword in
the `monsterKnowledge` document). A Director hide still wins.

## The Monster AI and players

- The map script keeps the AI running while combat is live
  (`MonsterAI.StartAI/StopAI/IsAIRunning`; the watchdog reads `IsAIRunning`).
  AI failures are contained per move/actor/turn/trigger so a bad move cannot
  strand initiative.
- **The AI waits for players**: on a turn-claim trigger (Hesitation Is
  Weakness), on reactions provoked by its movement *or its casts* (the
  `aiActivityId` / `pendingAIActivityReactions` protocol, set around every AI
  action), on a hero's end-of-turn save prompts and their rolls, and on a
  hero's mandatory end-of-turn prompts (`End Turn Casts` keeps the ended turn
  current until the ending client's casts are idle). There is no timeout on
  the save wait.
- **"Waiting for <hero>'s <ability>" banner**: the host writes the
  `monsterAIWaiting` document (`MonsterAI.SetWaiting/ClearWaiting`) and every
  client shows it through the tip banner's notice channel
  (`Tip.RegisterNotice`, 1s grace, Dismiss hides that text only). Everyone
  sees it, Director included.
- The trigger-reaction countdown dice never count down in EotW: they start
  paused ("Click to dismiss").
- Charges move with `freeMovement = true` (a Charge's movement belongs to the
  ability), and the `token:Move` budget clamp uses
  `subjectToPlayerMovementRules`, so it binds the host's own hero but not the
  monsters it runs.
- Monster rolls are shared to every client's sidebar
  (`AcquireAbilityRollDialog` begins sharing for casts by AI-controlled tokens).
  AI casts with no power roll still do not share.

---

# In-game flow

## The map script and the beat machine

The codemod registers the builtin map script `builtin:eotw-encounter`
(forwarding `hostThink` to `EncounterOfTheWeekGame.MapScriptHostThink`, every
0.5s) and the host attaches it to the encounter map. The map-script election
always picks a live host client (the session's real `dm` flag survives player
host mode). `EnsureMapScriptRunning` (every client's 1s driver) re-registers
the builtin if a Lua reload lost it and re-attaches the record if needed.
`MapScript.lua` keeps its registry in a global so registrations survive a
Core Rules reload.

`MapScriptHostThink`:

1. re-assert the forced settings;
2. wait for `AllPlayersArrived()` -- every expected member (anyone with a
   claimed hero at launch) has stamped `arrived`, and the newest stamp is
   3s old;
3. run the **script beats** in order (`RunScriptBeat`, beat index stamped in
   the `eotwscript` document so late joiners and resumes land in the right
   beat): narrative and montage beats run their host ticks; the encounter
   beat runs Tactical Preparation (if unlocked), then the encounter setup
   instructions, then the monster spawn, then pending zone reveals, then
   dismisses the stage, then starts combat;
4. while combat is live: keep the AI running, pay banked surges
   (`ApplyPendingCombatBoons`), stamp `combatStarted`, check the outcome, and
   (while no outcome is pending) bring in the round's reinforcements.

A document with no `#` beats but an `[[encounter]]` island is one implicit
encounter beat, so a week without a script plays as a plain fight.

## Spawning the encounter

`SpawnEncounterMonsters` finds the map's encounter with `FindMapEncounter`:
the first `[[encounter]]` island from `Encounter.GetEncountersOnCurrentMap
(hostAccess)` that is either bubble-sourced or in a document whose
`parentFolder` chain roots at the map. **Authoring convention: the first
island in the document is the start-of-combat encounter**; reinforcement
islands come after it. It spawns with `Encounter.SpawnGroupForReal(group,
numHeroes, anchor)` on raw groups (skipping waves and zero-count groups),
which handles banked positions, a fallback grid, minion squads, balancing and
initiative grouping. Spawned ids go on `richEncounter.spawns` (also the
double-spawn guard).

Islands under a `## Reinforcements: <Name>` section of the encounter beat are
not the opening fight (the parser keeps them off `beat.encounterTag`); they
arrive later, see "Reinforcements and the clear-the-map victory".

## Reinforcements and the clear-the-map victory (BUILT 2026-10-05, untested live)

User direction (2026-10-05, for The Dwarvish Bandits): fewer monsters at the
start, a new group (a squad and its captain) entering from the stairs every
round, alternating types, more for a bigger party; the heroes should really
have to work to get the hostages out. And when the heroes kill every Dwarf on
the map, they win. Decisions taken:

- **Authored in the document**, not in the encounter builder's waves. Core
  `Encounter.waves` exist (Director-deployed from the initiative bar's
  Reinforcements strip) but have no "every other round" and no Director to
  click them in EotW. A `## Reinforcements: <Name>` section under `# Encounter`
  carries `Arrive:` (schedule), `Enter:` (a zone type), `Shout:` lines and one
  or more `[[encounter]]` islands. Grammar: the /eotw skill's
  `script-reference.md`.
- **Alternation = several islands in one section**, taken in turn by arrival
  number (`EncounterScript.ScheduleOrdinal`). Separate sections with offset
  schedules (`every other round from round 2` / `... from round 3`) also work.
- **Party-size scaling** is each island's own (encounter builder `Appears:`
  gates and per-size balancing), through `Encounter.SpawnGroupForReal`, like
  the opening fight.
- **Arrival timing**: at the START of each scheduled round; the new groups go
  into the initiative with `SetInitiative(groupid, 0, 0)` (entry round = the
  current round, so they act this round), and `RecordOnsetMonsterGroups` gives
  them victory-screen cards.
- **Placement**: the zone's free tiles in random order (each tile once, then
  repeated; the spawn's `fitLocation` nudges overflow onto a free neighbour).
  A group copy is spawned with `spawnlocs` replaced and `placementid` dropped,
  so the island's own record and its Save and Remove tags are untouched. No
  `Enter:` = the island's saved positions.
- **Shouts**: one arriving non-minion (else any) says a random `Shout:` line
  through `creature:CharacterSpeech` (no language, so everyone reads it).
- **`Victory: every <kind> on the map is defeated`** (a setup line, `{kind =
  "victory", condition = "clearmap", who}`) is an OR on top of the encounter's
  own victory (`live:CheckVictory()`, which an Encounter Script replaces):
  `EncounterReinforcements.ClearMapVictory()` = no living, uncontrolled,
  non-bystander monster of that keyword / bestiary-type word on the map.
  Minions count (unlike core `CountLiveCombatants`). Reinforcements still to
  come do not count -- the user's "kill all Dwarves PRESENT on the map".
- **A won fight is never snatched back**: the host runs the reinforcement tick
  after `CheckEncounterOutcome` and only while `m_outcomeMetTime` is nil and no
  outcome is awarded, so a map cleared just before a round boundary still
  wins.

Runtime (`EncounterReinforcements.lua`, codemod order after
`EncounterZones.lua`, registered 2026-10-05, Firebase confirmed):
`HostTick(queue, live)` from `MapScriptHostThink` while combat is live;
idempotent per `<sectionId>-r<round>` in `eotwscript.data.reinforcements =
{arrived = {key = {round, at, island, count}}, spawned = {charid...}}`,
stamped BEFORE spawning so a failed spawn never doubles. Spawned tokens carry
`properties.eotwReinforcement = <sectionId>`; `EncounterMontage.ResetTest`
(and so `/eotwmontage reset` and End Test) deletes them and clears the state.
Islands resolve like scenes: `parse.sources[line]` gives the document, and
`EncounterScript.AnnotationKey` the journal key (`encounter-1`,
`encounter-2`, ...). The validator panel lists each section; `/eotwscript`
dumps them.

**Gaps**: the HUD's objective strip still shows only the script's victory
text ("Rescue the Hostages"), so players learn of the clear-the-map win from
the narrative text; reinforcements do not run under the `/eotwencounter`
dev driver (it has no host tick) -- use the authoring test or
`/eotwreinforce arrive <n>`; the publisher does not yet check that an
`Enter:` zone keyword ships with the module.

## Combat entry

`Encounter.StartCombatWithTokens{playerTokens, monsterTokens, encounter,
immediateResult, surprisedTokens}` (core, `DSInitiativeRoll.lua`) starts
combat with no Prepare Combat dialog. Sides come from `GatherCombatSides`:
heroes and player-controlled allies vs non-player monsters. It returns nil
while a side is empty, so the run-once is never wasted. The normal Draw Steel
banner is presented to everyone and any player may roll. The die result is
written to the shared `drawsteel` document by the roller, so the controller
never reads a stale local die. `immediateResult` (`"heroes"`/`"monsters"`)
forces the winner with no die. `surprisedTokens` get Surprised (until end of
encounter) before the banner. The montage's initiative outcome drives both
(see the clause rules). Players run initiative
(`permission:playersinitiative`).

## Start-zone confinement and the quiet pre-combat phase

From arrival until the initiative queue first goes live (latched by
`combatStarted`), each client's 1s driver:

- installs the engine **movement restriction** (`dmhub.SetMovementRestriction{
  locs}`): steps outside the Start zone are impassable for pathing, arrows,
  and drags (forced movement exempt), with a commit backstop;
- outlines the zone with `dmhub.MarkLocs{locs, color, style = "dashed"}`;
- holds `GameHud.SetTooltipsSuppressed("eotw", true)`: no tooltips and no
  movement cross-section anywhere -- **except while a stage beat is up**, so
  the stage's own tooltips work.

The restriction is rebuilt when `game.currentMapId` or
`dmhub.markupZonesSeq` changes. The game loads on whichever map the engine
picks first, before `EnsureOnEncounterMap` travels, so any cache of the Start
zone must be keyed the same way. The Start zone is a markup zone painted with
the module's `Start` environmental keyword, resolved by name.

**Extra start zones.** The clause `the <Zone> zone becomes a starting area`
banks `doc.data.startZones[zone]` (and a reveal of that zone).
`StartZoneLocs()` adds those zone types' tiles to the Start zone's, so the
confinement and its outline grow (the cache key includes the unlocked list);
`StartZoneLocs(true)` (hero placement's anchor) stays the Start zone alone.
Heroes are placed long before the montage, so the extra area matters in the
arrangement phase (below), when a winning party may move into it.

**Arranging the heroes (BUILT 2026-10-04, untested).** The phase only
happens when there is **no initiative roll**: a montage outcome hands the
heroes the initiative ("you win initiative", "you surprise the enemy"). When
the die is rolled there is no phase: the banner waits for a player to roll, and
the heroes arrange themselves (inside the start area) before rolling.
`StartEncounterCombat` passes `holdBeforeQueue` only when `immediateResult ==
"heroes"` (decided 2026-10-05). In the no-roll case the Draw Steel banner still
announces the win, but the initiative queue is not created yet. Core hook:
`Encounter.StartCombatWithTokens{ holdBeforeQueue = fn(heroesWin, begin) }`
(`DSInitiativeRoll.lua`; the banner's queue creation is now the local
`CreateCombatQueue(heroesWin)`, and `begin()` runs it once). EotW passes
`HoldForArrangement`: a loss calls `begin()` at once (a surprised party always
loses, so it never arranges); a win stores `begin` on the host
(`m_arrangeBegin`) and writes `eotwstate.arrange = { phase = "arranging",
startedAt, deadline = +ARRANGE_SECONDS (120), ready = {} }`. With no queue
the start-zone confinement (Start + unlocked zones) is still on, so heroes
move freely inside it. Every client with heroes gets the "Arrange Your Heroes"
panel (1s driver, `UpdateArrangePanel`): Ready / Not Ready writes the
player's own voter key (`EncounterNarrative.Voters` keys: the owner's userid,
or "PARTY") into `arrange.ready`, plus who is still arranging and a countdown.
The host's pre-combat tick (`ArrangeHostTick`, ahead of the script beats)
waits for every voter or the deadline, stamps `phase = "done"`, and calls
`begin()`. If `begin` was lost (a Lua reload on the host), it starts combat
again with `StartEncounterCombat(sides, { forceHeroes = true, noArrange =
true })`. `/eotwmontage reset` clears `arrange` and `arrivalItems`.

## Victory, defeat and leaving

- **Detection** (host tick, while the queue is live and nothing is awarded):
  victory = `live:CheckVictory()` or the script's `Victory:` clear-the-map
  line (`EncounterReinforcements.ClearMapVictory`); defeat = `live:CheckDefeat()` or every
  hero **dead** (`CountLivingHeroes`, `not IsDead()` -- dying heroes still
  count). The award sets `victoryAwarded`/`defeatAwarded` and uploads the
  queue; `DSVictoryScreen` shows on every client.
- **The award waits**: for every client's ability activity to settle (each
  client mirrors "I have casts, targeting, roll dialogs, modals or
  non-hostile prompts in flight" into `eotwstate.abilityBusy`; stamps older
  than 15s are ignored; 2 consecutive idle ticks), and for at least
  `OUTCOME_LINGER_SECONDS` (5) after the condition was first met. The two
  waits run concurrently.
- **Proceed is per client** (`DSVictoryScreen.RegisterProceedOverride{
  canProceed, proceed, holdUntilLocalProceed}`). Everyone may press Proceed.
  The host's press runs the full teardown (battle log, analytics, role
  history); a player's press stamps `proceedRequested` for the host to act
  on. Each client's screen is **held** until that client presses -- one
  player's Proceed never closes another's screen.
- **Auto-exit**: after the local Proceed, once the queue is gone, the client
  leaves (`dmhub.LeaveGame`, deferred ~4s so the host's writes flush). When
  the script has a `# Conclusion` (victory) or `# Defeat` section, the
  story screen comes first and its button is what leaves (never sooner
  than those ~4s). See "Encounter stories and the Victory award".
- **The Victory is awarded automatically** by the host, 3s after the
  victory screen goes up (or at once if someone presses Proceed first).
- **Cleanup**: before leaving, each client stamps the machine-local
  `eotw:concludedgame` preference and sends lobby `leave-game`. The
  titlescreen (`RefreshResumeState`) then destroys or leaves that game and
  clears the slot, so no stale lobby row and no resume row remain.
- Every combatant who started the fight gets a victory-screen card, despawned
  dead heroes included (`GetBattleHeroTokens` merges onset heroes).
- **Treasure goes home.** Once every player has arrived, before the first
  beat, the host snapshots every hero's items (inventory + equipment slots)
  into the state doc's `arrivalItems` (each record carries `_snapshot`, so a
  hero with no record is never credited). `TreasureGained(token)` = the
  NON-consumable items held now beyond the snapshot (consumables stay behind,
  by `EquipmentCategory.IsConsumable`). After a victory each living hero's
  card names it (`DSVictoryScreen.RegisterHeroCardNote("eotw-treasure")`), and
  `RecordPendingOutcomes` puts it on the outcome as `treasures = {{itemid,
  name, quantity}}`; the town's `ApplyOutcome` gives the items to the roster
  hero inside the same stamped `ModifyProperties` as the Victories, so a retry
  never doubles them. The City server stores the outcome opaquely.
- **Treasure found is worn** (user direction 2026-10-19). An equippable
  treasure (trinket, leveled treasure, artifact: `EquipmentCategory.
  IsEquippable`) a hero gains in the game is equipped at once when they have
  room, by the EotW hero sheet's own rules (`EotwHeroSheet.EquipSlot`: a free
  trinket or leveled slot, at most `LEVELED_EQUIP_CAP` = 3 leveled treasures).
  No room: it stays in the inventory and is NOT equipped later when room
  frees up. Mechanism: rather than hooking every way an item can arrive (the
  montage's `GrantItem`, a map chest's Take All or drag, a hand-over), the
  host's script tick (`AutoEquipTreasure`) compares each hero's items with
  the arrival snapshot and handles new gains; state doc `autoEquip[charid]
  [itemid]` counts the gained units already handled, so an item the player
  takes off stays off. Items brought from town are never touched. Back in
  town, `ApplyOutcome` equips each treasure the same way
  (`EotwHeroSheet.EquipInPlace`, inside the outcome's `ModifyProperties`), so
  a find worn in the game is worn at home.

## Encounter stories and the Victory award (BUILT 2026-10-02, not verified live)

User direction (2026-10-02): each encounter tells its story at both ends,
and winning one is worth a Victory that the hero keeps -- once per
encounter.

**The story sections** are three more `#` headings in the encounter's
script, parsed into `parse.story.towngate` / `.conclusion` / `.defeat`
(`{text, title, line, sceneTag, sceneLine}`). They are not beats and can sit
anywhere in the document (or a sub-document). `##` headings and `[[tags]]`
inside them are not text, except that a `[[scene]]` is the section's
backdrop.
- `# Town Gate`: the backstory, shown in the town while a party forms: under
  the encounter choice in the Form a Party dialog, and under the host line
  in the party view. The town cannot read the module's documents, so the
  **publisher** copies each encounter map's Town Gate text into the module
  record (`publishingProperties.eotwEncounters[<map name>].townGate`,
  `documents.story_section`), and the town reads it with the encounter
  list from `module.DownloadModuleInfo`
  (`EncounterOfTheWeek.GetTownGateText`). **A script edit reaches the town
  only on the next publish.**
- `# Conclusion` (after a victory) / `# Defeat` (after a defeat): the story
  screen (`EncounterMontageStage.ShowStoryScreen`), shown on each client
  alone after its own Proceed and the victory screen's fade: "Victory" or
  "Defeat", the encounter's title, the text over the section's `[[scene]]`
  (else the script's last backdrop), and **Return to Blackbottom**, which
  leaves the game. Escape does the same. No section, no screen.

The Goblin Ambush script (`encounter.yaml`, the master document) carries
all three, appended at the end (text-storage keys `zA`..`zF`). The user's
Town Gate text said "sort"; it was written as "sought".

**The Victory award.**
- One Victory per won encounter (`ENCOUNTER_VICTORIES`), awarded by the host
  through the core `DSVictoryScreen.AwardVictories(live, amount,
  exemptions)` -- the same code the Director's Award button now runs --
  elevated, so it can write every player's heroes. Every client plays the
  usual icon drop.
- **Exemptions** (`live.victoryExemptions = {[charid] = note}`): a hero who
  died gets nothing and no note (user decision: no Victory for the dead);
  a hero who already won this encounter gets "Already Completed" in grey
  italics where the "Victories: old -> new" line would be.
- **Who already won it** comes from the City: `checkHeroClaim` marks a party
  hero `completed: true` when `city_completions` has (owner, hero, the
  game record's `encounter`). The party view shows "Already Completed"
  (grey italics) on that hero's card, and the add-hero picker does too
  (from `list-heroes`' per-hero `completed` list,
  `EotwRoster.HasCompleted`). The flag rides the arrival args, and each
  owner stamps its placed copies into `eotwstate.alreadyCompleted[charid]`
  (`RecordCompletedHeroes`), which the host's award reads.
- Encounters are identified by their **encounter key**, the same string the
  party record carries: the map name ("Encounter: Goblin Ambush") for the
  official module, `<moduleid>|<map name>` for a community module (see
  "Community encounter modules and the encounter pool"). A week that reuses
  a map name counts as the same encounter. The Form a Party dialog now records the
  encounter even when the week has only one (no dropdown), so every party
  has a name to match.

**Carrying it home** (the Victory half of step 62).
- When a client sees the award land (or, failing that, as it leaves), it
  writes `eotw:pendingOutcomes` (machine-local preference, JSON
  `{userid: {"<gameid>|<heroid>": {gameid, heroid, stage, outcome}}}`) for
  each of its own town heroes **alive at the end**:
  `outcome = {encounter, result = "victory", victories = 1 or 0, completed
  = true}`. Dead heroes and defeats record nothing yet, because
  `record-outcome` is idempotent per (hero, game) and the burial
  write-back must still be able to send `died` for that game.
- The town applies it after every roster sync
  (`EotwRoster.ApplyPendingOutcomes`), once the hero's working copy is in
  step with the city: add the Victories to the working copy and stamp
  `properties.eotwOutcomes[gameid] = true` (the stamp travels with the
  record, so no machine adds them twice), push it (`put-hero`), mark the
  entry `pushed`, then `record-outcome`, which inserts the completion. A
  hero no longer in the roster drops its entry; each entry gets 3 tries per
  session.
- City side: `city_completions(userid, heroid, encounter, gameid, at)`,
  primary key (userid, heroid, encounter), written by `record-outcome` when
  `outcome.completed == true` and `outcome.encounter` is set (not for a
  death). Unit-tested; **not deployed**.

**Verified live 2026-10-03:** module v29 (`d240b941`) carries
`eotwEncounters`; the town reads it, and the Form a Party dialog shows the
Goblin Ambush backstory under the dropdown and hides it for Angry Dwarves
(no section).

**Not yet verified** (needs the City deployed to staging first): the
backstory in the party view; a hero who won before shows "Already
Completed" in the party view and the picker; the victory screen awards
automatically, with the note on that hero and nothing on a dead one; the
Conclusion screen, and the Defeat screen on a defeat; back in town the
roster hero's Victories went up by one, and a second win of the same
encounter adds none.

## Dead heroes leave the battlefield

A module-shipped global rule, no code: **Hero Death (Encounter of the Week)**
(`C:\dev\eotw\objectTables\globalrulemods\hero-death-encounter-of-the-week.yaml`,
id `a011c97a-...`). It mirrors core Monster Death for characters only:
`creaturedeath` trigger (true death, not dying), `mandatory: local`, delay,
wait for the hero's triggers and in-flight casts, remove with a corpse, no
loot drop, re-check `target.dead` at removal (a revived hero is spared).
Removal despawns rather than deletes. The publisher seeds non-core
`globalRuleMods` rows explicitly, because nothing references a global rule.

When a removal empties the current initiative entry, the removing client ends
that turn (`ActivatedAbilityRemoveCreatureBehavior.EndTurnIfEntryEmptied`), and
the bubble offers End Turn for a zero-token entry to anyone who can run
initiative. Both are core and apply to every game. Manual unlock:
`GameHud.instance:NextInitiative(function() dmhub:UploadInitiativeQueue() end)`.

## Players leaving and coming back (phases 1-3 BUILT 2026-10-09)

User direction (2026-10-09). Three phases:

1. **Leave and rejoin (BUILT).** A player who leaves (quits, crashes, loses
   the connection) hands everything they control -- heroes, montage allies,
   companions -- to the **host**, as **free agents**. Every screen gets a
   notice under the title bar's players row: the host's says "X has left.
   You control A and B until they return." (with a **Reassign** button), the
   others' say who controls them now. The players-row popout lists every
   player, whether they are here, and the heroes each controls; free agents
   are marked, and the host has a "give to" dropdown on each (any player who
   is here, the host included). When the player comes back their free agents
   return to them, with a notice.
2. **Leaving the game (BUILT 2026-10-09, untested).** Quitting or leaving
   shows "You are leaving the Encounter of the Week. You can resume later"
   with **Leave** (a normal exit) and **Abandon Game** (red; a second click
   confirms). Abandoning: the player's heroes stay and fight as free agents
   for good (user decision: anything else is too hard), and the others'
   notices say the player abandoned. If the abandoner is the **last member
   who has not abandoned** (user decision; not "the last one online"), the
   game is deleted -- see "Leaving and abandoning" below for the one case
   that cannot delete yet.
3. **Host migration (BUILT 2026-10-09, untested).** The host leaving: the
   others get "X, the host, has left" with **Claim Host**; the AI moves to
   the new host; a returning host gets their heroes back and an offer to
   reclaim. See "Host migration" below.

**Host migration** (phase 3):
- **Who hosts** is the engine's `GameInfo.IsDM`: the owner unless
  `ownerRevokedDMStatus`, plus the game's `dm` list. The game record is
  monitored live (`GamesMonitor`), and `isDMOrPlayerHost` /
  `isDMPossiblyImpersonating` read it on every call, so a change takes
  effect without a reload. Not yet proven live: the few engine pieces set up
  once at load (the DM HUD container, permissions finding 16) are not
  re-armed for a claimant.
- **Only the owner may write `/games/{id}`**, so the cloud function
  `eotwSetHost` (DEPLOYED) does it. `claim`: the caller is a member of a
  `directorless` game and every current host's session on the game server
  (`/api/{gameid}/store/game?path=/usersToSessions/{uid}`) is logged out or
  more than 40s silent; then `dm = [caller]`, `ownerRevokedDMStatus = true`.
  `reclaim` (the owner only): `dm = []`, `ownerRevokedDMStatus = false`.
  Revoking the owner on a claim is what makes a returning owner load as a
  plain player (`SetupOnArrival` takes the member path) and be OFFERED the
  role, rather than both machines hosting at once.
- **Every client** (`WatchHost`, once a second, not on a host, not in an
  authoring test) watches the hosts' sessions: all gone (a clean exit at
  once, a silent one after the same 35s + 15s as any player) -> a sticky
  notice "X, the host, has left. Nobody can play on until someone takes over
  hosting." with **Claim Host**. The first claim wins; a second one is
  refused (the first claimant is now a live host) and says so. The owner,
  back while someone else hosts, gets "Welcome back. X is hosting the game
  while you were away." with **Reclaim Host**. A notice clicked away comes
  back after 30s while it still applies; a host appearing takes it down.
- **The hand-over** needs nothing else: the claimant passes
  `isDMOrPlayerHost` as soon as the record lands, wins the map-script
  election once its session pings with `dm = true` (<= ~12s), and its host
  tick then (a) records itself as `eotwpresence.host` and announces the
  "newhost" event to every screen, (b) departs the old host like any player
  who left (their heroes become the new host's free agents), and (c) starts
  the Monster AI. The old host's client, if it is still running when it is
  demoted (a reclaim), stops its AI in the map script's new `onLoseHost`
  (`MapScriptLoseHost`).
- **Known gaps.** `LiveEncounter.IsElectedHost` (core) reads the session
  `dm` flag of players present within 140s, so after a host CRASH (no
  logout) its stale session can keep that election away from the new host
  for up to ~2 minutes. A Monster AI turn cut off mid-action by the host
  leaving is untested (the new host's AI picks up from the board as it is).
  The host tick's in-memory state (award timers, the arrangement) was built
  to survive a Lua reload and is expected to survive a hand-over the same
  way; not audited line by line. A false claim is possible only when the
  host is really silent for 40s (a network drop); the owner can always
  reclaim.

**Outcomes for absent players (user decision 2026-10-09; BUILT, untested).**
A player who ABANDONED gets nothing. A player who left without abandoning
gets a dialog the next time they are in town: what happened to their heroes
while they were away, and a choice to claim the result or count it as an
abandon and ignore it. Only VICTORIES travel, exactly as for a present
player (`RecordPendingOutcomes` sends surviving heroes' victories and
treasure; deaths and defeats send nothing today), so the dialog only ever
offers a won game.
- The host, the moment it sees the victory (`OfferAbsentOutcomes`, from
  `UpdateEncounterConclusion`), sends `offer-outcomes {userid, gameid,
  entries}` to the City for each player in `eotwpresence.away` who has not
  abandoned. Entries are built by `VictoryOutcomesFor(userid, encounter)`,
  the same builder the player's own client uses.
- The City keeps them in `city_offered_outcomes`. An offer applies nothing;
  it skips heroes that do not exist, have fallen, or already have an
  outcome for that game. Anyone can offer to anyone (the City does not know
  who played which game), so the worst a false offer can do is ask.
- The town asks `list-offered-outcomes` once per connection (beside the
  Proving Pits debrief check) and shows **While You Were Away** per game:
  each hero's Victory and treasure, **Claim the Victory** (the entries join
  the usual `eotw:pendingOutcomes` queue through
  `EotwRoster.AddPendingOutcomes`, which applies them and sends
  `record-outcome`) or **Count as Abandoned**. Either way
  `resolve-offered-outcomes {gameid}` drops the offer.
- A player who comes back before the end records their own outcome as
  usual; a duplicate is harmless (record-outcome is idempotent per hero and
  game, and the hero's `eotwOutcomes[gameid]` stamp blocks a second
  Victory).

**Leaving and abandoning** (phase 2):
- **One exit hook for everything.** The engine's `QuitApplication` (the
  window's close button, Alt+F4, the menus' Quit to Desktop) and
  `Application.wantsToQuit` (Cmd+Q on macOS, a native close) first call the
  Lua global `OnQuitRequested()` (`CodexTitleBar.lua`); true holds the quit
  and the Lua side later calls `dmhub.ForceQuitApplication`. The in-game
  Leave Game command asks the same thing. Both go to the active custom
  interface's new `confirmExit(kind, proceed)` provider field
  (`GameHud.CustomInterfaceConfirmExit`), so other games are untouched. The
  EotW provider answers with `EncounterPresence.ConfirmExit`, which steps
  aside in an authoring test and once the encounter is decided (the
  conclusion's own `dmhub.LeaveGame` never goes through the hook).
- **The dialog**: "Leave the Encounter?" / "Quit the Encounter?", the
  resume-later line, and notes: the host is warned the others cannot play
  on until they come back (host migration is phase 3), and Abandon Game
  explains what it does (or that it ends the game for the last player).
- **Abandon** (`EncounterPresence.Abandon`): writes the player's own
  document `eotwleave-<userid>` (`abandoned = serverTime`; one writer, so
  the state doc's clobbering cannot touch it), stamps the machine-local
  `eotw:abandonedgame` = `{gameid}`, and goes 0.75s later so the note
  reaches the server first. (`IsLastMember` -- every other member, from
  `Members()`: expected users, placed heroes, current hero owners,
  free-agent owners, has abandoned -- only picks the dialog's wording; the
  server decides the deletion.)
- **The host** reads the abandon documents every presence tick: a player
  seen abandoning is departed with `abandoned` (event "abandoned"), or a
  player already away is upgraded (`MarkAbandoned`). An abandoned player's
  free agents are never handed back, and the popout shows them as
  Abandoned.
- **The town** finishes it on its next refresh (`RefreshResumeState` ->
  `DestroyPreviousGame(gameid, {abandon = true})` -> `AbandonGame`): it calls
  the **`eotwAbandonGame` cloud function** (DEPLOYED 2026-10-09), which
  deletes the game only when no OTHER member still holds it in their EotW
  account slot -- owner or not -- and then leaves it
  (`LuaGameInfo:Leave()`: off the player list, slot cleared). A player who
  merely left keeps their slot, so the game stays for them. The town's
  other ways of walking away -- the resume row's **Abandon**, and creating
  or joining a new game -- go the same way. (Before, the owner deleted the
  game outright, from under anyone still playing.) Concluded games still
  delete as before (owner deletes, members leave).
- **How a non-owner's delete works.** Only the owner may write
  `/games/{id}`, so the function (admin rights) marks it `deleted` +
  `releaseStorage` and asks the game server to release the Durable Object;
  the game server's delete-game route now lets anyone release a game whose
  record says both (`isReleasedGame` in `cloudflare-game-server/src/index.ts`).
  That route change is DEPLOYED to staging (2026-10-09), where EotW games
  live; the release worker still needs it before launch. Details in
  `cloud-functions/CLOUD_FUNCTIONS.md`.
- **Known gap: the host abandoning while others play** freezes their game
  (no host tick) until phase 3. The dialog warns the host.

**Why free agents unwedge the game.** Every wait asks who controls a hero:
narrative votes and the preparation / arrangement Proceed group heroes by
`ownerId` (`EncounterNarrative.Voters`), and montage requests are checked
with `UserControlsHero`. Moving the leaver's heroes to the host removes the
leaver from every wait; the host then votes or acts for them.

**How it works** (`EncounterPresence.lua`):
- The HOST decides, from the map script's host tick (`HostTick`, once a
  second; not in an authoring test; not in the first 10s after loading).
  A player has left when their session says `loggedOut` (a clean exit:
  acted on at the next check, so the notices go up within a second or two)
  or has not pinged for 35s (sessions ping every ~12s), confirmed over 15s
  more: after a reconnect the game server re-sends session records with
  timestamps rounded down to 5 minutes, so a present player can look silent
  until their next ping. A crash is therefore noticed after about a minute.
- **The engine announces a clean exit** (2026-10-09, C# NEEDS BUILD):
  `GameController.AnnounceLeaving` writes `loggedOut` while the game's
  connection is still up and stops the pings. `LuaInterface.QuitApplication`
  (the window's close button, Alt+F4, Quit to Desktop, and a launched
  window's Leave Game) hides the window, announces, and quits once the
  server confirms or 1.5s pass; `GameHarness.LeaveGame` and a direct
  game-to-game `EnterGame` announce first thing. Before this the only write
  was in `GameController.OnDestroy`, which on a QUIT runs after the
  connection has closed, so a player who closed the window was only noticed
  by the silence timeout (seen 2026-10-09). `GameHarness.RefreshGame`
  suppresses the write (`SuppressLeaveAnnouncement`): an in-place reload is
  not a departure, and the old backstop briefly marked the player logged out.
- Only players who control something on the map are watched; a player with
  no session record has never been here and is ignored.
- A player is back when their session is fresh (pinged within 20s) and their
  client has re-stamped `eotwstate.arrived` since they left (their heroes
  are placed again), or after 30s back regardless.
- The document `eotwpresence` has the host as its only writer, so the state
  doc's concurrent-write clobbering cannot touch it: `away[userid] = {name,
  at}`, `agents[charid] = {owner, controller}`, and the newest 16 `events`
  (left / returned / given) for the notices. Every client watches the events
  and shows a notice for each new one; events from before it started
  watching the game are history, not news.
- `Give(charid, userid)` (host only, from the popout) moves a free agent and
  any montage allies of it that are free agents too. A free agent given to
  B, who then leaves, goes back to the host, still owned by its original
  player. Ownership changes go through `token.ownerId` (undoable, applied
  locally at once).
- **The montage turn follows its hero** (`EncounterMontage.SyncTurnToOwners`,
  every presence tick): the acting user and a Pardon My Friend roller
  become whoever controls that hero now.
  A roll already out stays with its roller unless they are away; the new
  controller's client then rolls it afresh (its own `m_launchedRollSeq`
  differs). A chest roll works the same way.
- **The title bar** (core): `CodexTitleBar.ShowPlayersToast{text, actions,
  duration, id}` shows the notices as a popup of a zero-size anchor under
  the players plate. The title bar itself draws BELOW the game hud, so a
  plain child was hidden behind the End Turn banner. The popup is rebuilt
  whole whenever a notice comes or goes: popup placement is computed from
  the panel as first shown, and a column grown afterwards spilled upward
  over the bar. A click elsewhere closes the notices, like any popup.
  `CodexTitleBar.OpenPlayersPopout()` opens the plate's popout; a custom
  interface supplies its content through the new `playersPopout` provider
  field (`GameHud.CustomInterfacePlayersPopout`). In a directorless game the
  players row now shows the host too (it skipped every `dm` session, which
  hid the player host).
- Dev: `EncounterPresence.DevSimulateLeave(userid)` /
  `DevSimulateReturn(userid)` play a departure / return on one machine. Set
  some heroes' `ownerId` to a placeholder userid first, and restore them
  after.

**Known gaps (phase 1).** A player who leaves before they ever arrive still
holds the party gate (`AllPlayersArrived`). A free agent's trigger prompts
and saves are answered on the host's client the normal way (the hero card's
trigger badge jumps to the hero); a prompt that was already open on the
leaver's screen when they went has not been tested, and the AI's save wait
has no timeout. Nothing yet tells a player in town that their game went on
without them (phase 2).

---

# The EotW interface (custom HUD)

Core hook `GameHud.RegisterCustomInterface{id, active, suppressRails,
railPanel(side), railBottomPanel(side), suppressTitlebarMenu, titlebarPanels,
suppressPanel, suppressSearchBucket, characterPanelAccess(token)}`
(`DMHub Core UI/Hud.lua`). The first active provider wins; a provider with
the same id replaces the old one. Every read is pcall-guarded. Consumers: icon
rails (`DocumentSystem.lua` swaps the button columns for provider widgets and
hides docks with the `offscreen` class only, never by writing dock settings),
the title bar, dockable/launchable panel registries, search buckets, and the
character panel's access level.

The EotW provider (`EncounterOfTheWeekHud.lua`), active in an EotW game
(unless `eotw:showdirectorui`) or for the tester during an authoring test
(both via `IsEotwGame()`):

- No side rails, no Panels menu, no Compendium (menus, toolbar and search).
  The title bar's Codex menu stays.
- **Bottom-left corner**: Journal, Chat and Action Log rail-style buttons
  (unread badges, active underline). "/" still opens chat. Above them, behind
  a short rule, Measuring Tool and Whiteboard buttons (playtest 2026-10-19 N4;
  the takeover hides the map rail that normally carries them). The two share
  one folder window, so pressing the one not on screen switches its tab.
- **Encounter Rules book** (user direction 2026-10-20): when the encounter
  has an Encounter Rules document (see "The document, discovery and
  sub-documents"), a book button (`phosphor/book-bookmark.png`, tooltip
  "Encounter Rules") appears directly above Journal **once combat begins**
  (`EncounterOfTheWeekGame.CombatStarted()`: the host's `combatStarted`
  stamp, or a live initiative queue before it replicates). It wears the
  rail's "new" badge until first opened this session and the active
  underline while its window is up. Press toggles a 760x860
  `PresentDocument` window over a local `DeepCopy` of the document with
  `readonly = true` (so not even a testing Director or the author playing
  their own module can edit or upload it), in `presentationMode` (no edit,
  present, preview or breadcrumb chrome) with the new generic
  `presentationAllowClose` arg (`DocumentSystem.lua` `CreateInterface`)
  keeping the close button. A reopened window keeps where it was dragged
  (the copy's `_tmp_location` is carried over). The button's think lives on
  a never-collapsed wrapper (a collapsed panel does not think); the window
  closes when the combat stamp goes away (a test restarted or ended) or the
  corner strip is destroyed without being remounted within 0.5 s. Code:
  `CreateRulesButton` in `EncounterOfTheWeekHud.lua`. Verified live
  2026-10-20 (Aixco authoring test from Combat, temporary document since
  removed): the script was still Part 1, the rules document was in
  `ScriptForMap`'s publish set, no button during the Draw Steel banner, the
  button and its badge appeared with the initiative roll, the window showed
  the rendered markdown (glossary links live) with only the close button and
  reader tools (back/forward, zoom), the badge cleared, close and End Test
  both took the window away. UNCOMMITTED.
- **Right edge**: the **encounter pools strip** (Malice, Hero Tokens, and
  Intelligence when unlocked; read-only; hovering a cell explains the pool and
  shows its history) above the **hero roster**: one portrait card per hero
  (`dmhub.allTokens` + `IsHero()`, not `Party.GetPlayerCharacters()`, which
  drops blank names), with name and controlling player, a state-tinted stamina
  bar with temporary stamina, the heroic resource, one icon per surge,
  condition chips, a pulsing trigger badge (click to jump to the hero), and
  the hero's unspent Intelligence as a brain chip (only when above 0).
  Own heroes sort first with a blue border. Ally mini-cards sit under their
  hero. The column shrinks to fit the screen (uiscale, top-right pivot). It is
  collapsed while a stage beat is up. Clicking a card opens the character
  panel beside it, **read-only for everyone**.
- Unnamed heroes read "Unnamed Hero" everywhere.
- **The map is held maximized** (user direction 2026-10-17), in a real game
  and in an authoring test alike: the encounter's map window (the client's
  `game.currentMapId`) is opened, maximized and focused, and its restore,
  minimize and close buttons are gone, exactly as for a player whose
  Director holds a shared map maximized. The provider's `forcedMap` field
  (a new `GameHud.RegisterCustomInterface` field, read through
  `GameHud.CustomInterfaceForcedMap`) feeds Tabletop's existing forced-window
  machinery (`ApplyForced` / `rec.forced` in `DMHub Game Hud/Tabletop.lua`),
  so every guard that keeps a Director-forced window up applies. Unlike the
  Director's force it needs no share or token and binds a Director client
  too; it is re-checked every frame (`g_sharing.SyncLocalForced`), so End
  Test or the Director-UI hatch releases it at once and the window goes back
  to its previous maximized/windowed state. Written 2026-10-17, NOT run
  (needs a restart: `Hud.lua`, `Tabletop.lua`, `EncounterOfTheWeekHud.lua`).
- **Codex > About Encounter of the Week** (user direction 2026-10-19), in
  any EotW game and an authoring test (`filtered` on `IsEotwGame()`): a
  `Commands.Register` row (`menu = "codex"`, identifier `eotwabout`) opening
  `EncounterOfTheWeekHud.ShowAbout()`, a modal with the Town Gate art as a
  banner (Czepeku's watermark via `CreatorCredit.Backdrop`), the title
  "About Encounter of the Week", and the credits "Draw Steel by MCDM",
  "Encounter of the Week concept and engineering by the Codex Development
  Team", "Cartography by Czepeku". Under them, "About <encounter>" from
  `EncounterOfTheWeekGame.EncounterInfo()` (the current map's name without
  "Encounter: ", plus the series part), beside the map's thumbnail:
  - **Written by**: the encounter module's creator organization's
    `displayName`, else the organization its `authorid` names (the official
    module's `authorid` is `mcdm`, so it reads "MCDM"), else the raw
    `authorid`. The module comes from the `eotwstate.encounterMap` key, so
    an authoring test shows no author line.
  - **Map by**: only for a map from a map pack (`map.packSource.pack`):
    the pack's entry in `ABOUT_MAP_PACK_CREATORS` when it has one (user
    direction 2026-10-19: `mcdm-encountermaps`, the pack Aixco Hollow is
    from, credits "MAD Cartographer", linked to
    https://themad.network/the-mad-cartographer), else the pack's creator
    organization (`mappacks.packs[].org`) by its `displayName`
    ("2-Minute Tabletop", "Tehox Maps"). The pack index is synced first when
    it is not, since an old map's provenance is only known from it.
  - **Links**: a name with a url is an underlined accent-colored TMP
    `<link>` (underlined because some schemes' accent is near the body
    text), opened on press through `dmhub.OpenURL`, which shows the app's
    "Open External Web Site?" confirm for these domains. Czepeku in the
    credits links to https://czepeku.com; an organization-derived map or
    author credit links to the `url` on its organization record.
  Verified live 2026-10-19 after a restart, in the Aixco authoring game: the
  row is registered and hidden there (not an EotW game); with its filter
  briefly lifted it shows in its own group, opens the dialog, and the real
  `EncounterInfo` gives "Aixco Hollow -- Part 1: Sandy Shore", "Map by MCDM",
  no author (no encounter key in an authoring game, as designed). "Written
  by MCDM" was seen in an earlier preview with the official module id. The
  MAD Cartographer credit and both links were then seen in a live preview of
  the block (no restart yet): each link raised the confirm prompt with the
  right URL (cancelled).
  NOT seen: a real EotW game (whether a module-installed map keeps
  `packSource`), an authoring test, a community module's author. UNCOMMITTED.
- **Map creator watermark** (user direction 2026-10-19): while the EotW
  interface is up and the live map came from a map pack, the pack's creator
  organization's logo sits in the bottom-right of the map window
  (`Tabletop.MapOverlayHost()`, under the map's HUD and dialogs), on a dark
  translucent plate, 36px tall. Hover: "Map by <org>"; click: the org's
  Patreon campaign, else its website. MCDM's maps carry none
  (`MAP_WATERMARK_EXEMPT_ORGS`); hidden while a montage is presented. Logo,
  name and link come from the org's `/ModuleAuthor` branding via
  `CreatorCredit.ForOrganization` (registered as creator `org:<orgid>`), so
  a new pack's creator needs no code. Kept up by the right rail's think
  (`UpdateMapWatermark` in `EncounterOfTheWeekHud.lua`), removed when the
  rail is destroyed. Map -> pack -> org is shared with the About dialog
  (`MapPackOf`, `MapPackOrg`). Verified live 2026-10-19 with
  `IsEotwGame` briefly forced on in the Aixco game: none on the MCDM Aixco
  map; Tehox wordmark on Dwarven Fortress; the click opened
  patreon.com/tehox (`dmhub.OpenURL` opens at once -- no confirm prompt,
  despite CreatorCredit's comment); gone when the interface went away.
  Module-installed maps keep `packSource` by code reading (publish copies
  the manifest whole, install writes it back under the same map id); not
  seen in a real EotW game, as no published encounter uses a pack map from
  a non-MCDM creator yet. UNCOMMITTED.

Gotchas from building it: `positionInScreenSpace` is in the documents layer's
units (origin bottom-left), not screen pixels, and is the *pivot's* position.
A panel with no `bgimage` is not hit-tested, so give hover targets a
transparent `panels/square.png`. `gui.StatsHistoryTooltip`'s text is a bare
auto-width label, so wrap long text yourself.

---

# Encounter scripts

**Author-facing copy:** the `/eotw` Claude skill (`.claude/skills/eotw/` in this
codex repo: `SKILL.md` workflow, `script-reference.md` grammar,
`lua-toolkit.md` MCP checks) guides an author from map to published module.
When the grammar below changes, update `script-reference.md` too.

The encounter map's journal document is a **script**: an ordered list of
beats. All of it is Lua in the EotW codemod, with three small core pieces:
`Encounter.StartCombatWithTokens`'s optional args, `TestRiders.lua`, and the
ability-share exports in `Timeline/AbilitySidebar.lua`. The parser
(`EncounterScript.lua`) is pure Lua with no engine globals, unit-tested with
the bundled interpreter. The runtime (`EncounterMontage`, `EncounterNarrative`,
`EncounterPrep`, `EncounterZones`) and the stage (`EncounterMontageStage`) sit
on top. A Director-run montage in a normal game could reuse the parser and
runtime later; only the hero row and HUD wiring are EotW-specific.

## Knacks (BUILT 2026-10-05)

User direction 2026-10-05: montages should reward what makes each hero
different -- languages, movement, immunities, perks, complications, class and
ancestry features, abilities such as Black Ash Teleport. The reference (grammar,
the capability vocabulary, the perks played by their real rules, the authoring
STANDARD) is `EncounterOfTheWeek/KNACKS_REFERENCE.md`; the analysis that led
to it is `EOTW_MONTAGE_KNACKS.md` at the dmhub repo root. Decisions:

- `Allow` riders make an option SECRET (hidden, not locked). Spectators see a
  secret option exactly when the choosing player does (everyone watches the hero
  at the entry). Journal rolls keep the locked display.
- Authors write INTENT; `TestRiders.CAPABILITIES` maps it to every source.
  Pregens are a breadth test (validator Knack coverage), never named in code.
- A knack can remove the roll or replace the power table (`#### If ...`).
- Real perk rules are implemented in the montage wherever possible.
- The host fixes the version a hero takes at `choose` (`t.knackIndex`);
  `EncounterMontage.TurnOption` is the one way runtime code reads the turn's
  option. A free version resolves as tier 0.

## The document, discovery and sub-documents

- **Which document**: every non-hidden markdown document filed under the
  encounter map's journal folder (`FindMapScript`). A document that another
  one includes is a *part*, never a candidate.
- **Encounter Rules** (2026-10-20): a document in that folder named
  `Encounter Rules` (case-insensitive) is never a script candidate
  (`EncounterMontage.RulesDocumentPart`, applied in `MapJournalDocuments`).
  It is the players' in-combat rules reference, shown read-only from the
  HUD's book button (see "The EotW interface").
  `EncounterMontage.FindRulesDocument(mapid, part)` picks it; a series part
  may have its own, `Encounter Rules: Part N` (or `- Part N`, `(Part N)`,
  `Part N`), which wins over the general one for that part. Decision taken
  without asking (easy to change): identified by NAME in the map's folder,
  like the script, rather than by a link from the script -- simplest for
  authors and needs no grammar. `ScriptForMap` adds the rules documents to
  its `documents`, so the publisher ships them. Documents the rules
  document merely links to are NOT shipped unless they are in the map's
  folder anyway.
- **Sub-documents**: before parsing, any line that is *only* a link to
  another journal document -- `[label](document:Name)`, `[:Name]` (embed) or
  `[Name]` -- is replaced by that document's text, recursively (depth 8,
  cycles warn). A link inside a sentence stays a link. Resolution prefers a
  document filed under the same map, then `CustomDocument.ResolveLink`. A
  link to something that is not a journal document stays prose; an
  unresolvable one warns. Keep sub-documents directly in the map's journal
  folder, because that is what the publisher ships. Warnings name their
  document (`'Mysterious Cottage' line 29: ...`). Rich tags stay with their
  document: `[[scene]]` records its source line, and repeated tags use the
  journal's keys (`scene`, `scene-1`, ...). The parse is cached on a
  signature of every candidate and included document's id, name and length.
- **Beats** are `#` headings: `# Narrative`, `# Montage`, `# Encounter`
  (case-insensitive). Anything else warns and is ignored. `# Delve: <Name>`
  sections are not beats (see Delves), and neither are the story sections
  `# Town Gate`, `# Conclusion` and `# Defeat` (see "Encounter stories and
  the Victory award").
- Parse text comes from `doc:GetTextContent()`. The journal stores a
  shift+enter soft break as a **vertical tab**, so the parser splits on it.

## Montage beats

```
# Montage

[[scene]]

The party's standing context, shown in the header for the whole beat.

## Round 1
3-5 Players: -1 Opportunity, -1 Threat

## Opportunity: Mysterious Cottage

A mysterious cottage lays off the path. Dare you approach?

---

PC approaches the cottage...
Witch (Wode Hag) enters
Witch: (in Hyrallic) Oh ancient spirits...

### Negotiate with her for some aid

PC: Good morrow!

|Negotiation Test: Presence (Empathize, Lie, Flirt, Persuade)
|You fail at the test => The witch is unimpressed.
|A small boon => You gain one Healing Potion
|A large boon => Each party member gains one Healing Potion
|Edge: You speak Hyrallic

if tier1 then
    Witch: Begone!
else
    Witch: Here, take these.
end

## Threat: Goblin Scouts (Temporary)

They will raise the alarm if you let them go.

Consequence: You begin the encounter surprised
```

**Structure**

- `[[scene]]` / `[[scene:name]]`: the `RichScene` annotation's image is the
  stage backdrop.
- Prose before the first `##` is the montage intro, shown in the header for
  the whole beat (wraps up to about 7 lines).
- `## Round N` opens a round. **Entries persist into every later round**
  until taken or vanquished, except `(Temporary)` ones. No round heading = one
  implicit round.
- `## Opportunity: <Name>` / `## Threat: <Name>` with optional heading tags
  in parentheses, combinable in any order:
  - `(Required)`: never removed by party-size scaling.
  - `(Locked)`: off the board until an `Unlock <name>` outcome lands. It then
    appears at once if its round has been reached, otherwise when that round
    comes. Out of the scaling draw. A never-unlocked threat has no
    consequence. The parser warns both ways (an unlock naming nothing, a lock
    nothing opens).
  - `(Temporary)`: gone at the end of the round it appeared in (for a locked
    one, the round its unlock landed). An unvanquished temporary threat pays
    its consequence at that round boundary, read out at the start of the next
    round. In the last round it falls to the normal consequences phase. The
    card tells the party ("Gone at the end of this round").
  - Body: paragraphs = card description; `Options:` = approach text;
    `Consequence:` (threats) = applied at the end if never vanquished.
- `### <Option>`: an option, whose test is the journal's power-roll block:
  `|Name: Attr (Skill, Skill)` plus three tier lines (an optional fourth is
  the critical), matched with `MarkdownDocument`'s own regexes.
- **Every test has a critical** (user direction 2026-10-07): a natural 19-20
  lands on tier 4 (`TierIndexForRoll`). A roll written
  with three tiers gets a built one: tier 3's full text plus "The party gains
  an additional hero token." (`EncounterScript.AutoCriticalText`;
  `roll.critAuto`; the hero-token clause accepts "an additional"/"an extra").
  So `roll.tiers` always has four entries. The critical is **secret until
  rolled**: the roll dialog and remote card get tiers 1-3 only
  (`TeaserTiers`), the stage's tier rows (`TierRows`) add a "Critical" row
  only once tier 4 has landed, outcome icons ignore it
  (`OptionEffectLists(option, includeKnacks, includeCritical)`), and the
  hero slot / tooltip / last-turn line read "Critical". Tier 3's range always
  reads "17+". The validator labels a built one "critical (automatic)". `Attr` maps
  to characteristics and skills the way `PowerRollDisplay` does it. **Skill
  names must match `Skill.skillsDropdownOptions` exactly** (`Track`, not
  "Tracking"; `Handle Animals`), and **every roll needs a `###` option
  heading above it**, or it is dropped. The validator catches both.
- **Teasers**: `|teaser => full text` on a tier line. Players see the teaser
  (in the stage and the roll dialog's table) until that tier lands; only the
  full text is parsed for effects; tiers not achieved keep their teaser for
  good. `=>` was chosen because `|` breaks the journal's tier regex and `:`
  collides with tier prose.
- **Riders** (`TestRiders.lua`, core): `|<Effect>: <requirement>` after the
  tiers. Effects are `Allow` (aliases `Requires`/`Required`/`Allowed`/
  `Require`), `Edge`, `Double Edge`, `Bane` and `Double Bane`. A requirement
  is alternatives joined by `or`/commas: "you are skilled in X", "you speak
  X", "you are a/an X" (class, subclass or ancestry; "Elf" matches a High
  Elf). Bare names inherit the previous kind. `Allow` gates who may take the
  test (shown locked with "Requires: ..." for others, violet "Unlocked: ..."
  for a hero who meets it; the host refuses a `choose` that fails it). Met
  edge/bane riders become pre-ticked chips in the roll dialog. Riders also
  render in the journal under any power roll.
- **Party-size scaling**: lines directly under `## Round N`, `3`/`3-5`/`3+`
  `Players:` followed by `-<n> Opportunity`/`-<n> Threat` lists. Every
  directive covering the party size applies, cumulatively, drawing at random
  from entries **that round introduces**, once, when the party has arrived.
  Removed entries simply never appear; there is no message to players. The
  draw is printed to the console in full and kept on the document
  (`m.removed`, `m.removedForPartySize`, `/eotwmontage state`).
- **Scenes**: a `---` line in an entry (above its first option) ends the card
  text and starts its scene; every non-blank line after it is one step.
  - `PC` is the approaching hero.
  - `Name (Monster) enters`/`appears`/`arrives` and `Name exits`/`leaves`/
    `departs`. The monster gives the portrait; a bare name is its own monster.
  - `Name: text` is speech (only for `PC` or a character who enters
    somewhere in the entry). `(in <Language>)` garbles the line for everyone
    unless the hero speaks it.
  - Emotes: `Witch is alert|alarmed|scared`, or `Goblin (scared): ...`.
  - Off-stage voices (2026-10-20): `??? (offstage): Who goes there?` or
    `Guard (off-stage): Halt!` is speech from someone who never enters: the
    name shows over the line, no portrait comes on, and they are not a
    character of the entry. Without the marker, a speaker who never entered
    is still narration.
  - `if/elseif/else/end` on `PC speaks X`, `PC is X`, `PC has X` (skill),
    `PC chose X`, `tier1..tier3`, `crit`, with `not/and/or` and parentheses.
  - In a scripted entry, an option's lines above its roll are its pre-roll
    scene and the lines below are its outcome scene. **Effects apply after
    the outcome scene has been read.**
  - Entries without a scene get an automatic intro.
- **Delves**: an option line `Delve: <Name>` (the option has no roll) enters a
  `# Delve: <Name>` section anywhere in the document:
  - `Chest: every 1-2 obstacles`;
  - `## Obstacle: ...` entries shaped exactly like opportunities;
  - `## Chest` (a scene, then a dice table `|Treasure: 1d6` with rows
    `|1-2: <clauses>`);
  - `## Continue`, `## Leave` (or `## Turn Back`) and `## Forced Out`.

  The whole delve is the approaching hero's one turn, and they go in
  alone. The hero meets random unmet obstacles, a chest comes due every 1-2 obstacles
  (real dice, rolled by the delving player and followed on every screen;
  unfound rows read `???` until first landed, remembered per game in
  `data.chestSeen`, which the dev reset deliberately keeps), the find is
  taken with Continue, then "Press deeper (lose 1 Recovery)" -- locked unless
  the hero has more Recoveries than the cost -- or "Turn back". At 0
  Recoveries the hero is forced out. The tomb is then taken and the log
  summarises it. Delving is flat: deeper is not harder, just more chests.
- **In-order delves** (2026-10-04, user direction: a quest's steps should
  all follow from one starting point, like the tomb, not be separate turns).
  `Order: in sequence` (also `Order: in order`, `Obstacles: in order`) under
  the `# Delve:` heading sets `delve.ordered`. Obstacles come in written
  order; after each step but the last the `## Continue` scene plays and the
  hero picks "Press on" (free: `EncounterMontage.DelvePressOnCost` is 0) or
  "Turn back"; `## Chest` is optional and its absence does not warn;
  finishing the last step leaves with why = "complete", which plays
  `## End` / `## Finish` (section key `finish`; a random delve with one
  warns) and resolves the turn even on 0 Recoveries. The 0-Recovery
  forced-out rule still applies before a later step. The turn log reads
  "<hero> took on <entry>: N of M steps." Parser tests in
  `tests/encounter_script_test.lua`.

**Effect clauses.** Each tier line (and `Consequence:` line) is split into
clauses on `. , ; ! ?`, and each clause is matched case-insensitively.
Quantities are digits or `one`..`ten`, with `a`/`an` = 1. Anything wrapped in
`{...}` is applied but **never shown** (stage, roll dialog, log); the raw
line is the author's view. Clause positions are kept as byte spans, so the
stage colours recognised rules green inside the prose. A teaser is never
coloured.

| Clause | Effect |
|---|---|
| `you gain <qty> <item>` / `each party member gains ...` | item to the acting hero / every hero (`tbl_Gear` by name, trailing `s` tolerated) |
| `you lose <n> stamina` / `each party member loses ...` | damage (`InflictDamageInstance`, so Hero Death sees it) |
| `you heal <n> stamina` (`regain`, `recover`) | heal |
| `you gain <n> temporary stamina` | temporary Stamina, higher of old and new |
| `[at the start of the next combat] you gain <n> surges` | banked on the document, paid when combat is live (surges are cleared outside combat) |
| `your recovery value is increased by <n>` / `+<n> recovery value` | ongoing effect "Montage Boon: Recovery Value +N" until the next respite; the effect asset is created at beat start (`PrepareBoonAssets`) because `GetTableCached` cannot see a row uploaded the same moment |
| `you lose <n> recoveries` | flat loss, no Stamina back; a hero with none loses nothing |
| `+<n> hero token[s]` / `you gain <n> hero tokens` | party pool |
| `+<n> intelligence` / `you gain <n> intelligence` | the party's Intelligence pool (warns unless an `Unlock: Intelligence` exists) |
| `+<n> malice` | malice pool (carries into combat; Draw Steel adds start-of-combat malice to it) |
| `a <monster> joins you` | allied monster spawned on the nearest free Start tile, owned by the acting player, on the heroes' side in combat |
| `the threat is vanquished` / `you vanquish the threat` | threat resolved |
| `you begin the encounter surprised` | monsters first; Surprised on every hero **at once**, sticky |
| `you surprise the enemy` | heroes first; every monster Surprised at combat start |
| `you win initiative` / `you lose initiative` | forced initiative, no die |
| `you cannot be surprised` | Surprised withheld from heroes and allies (and lifted if already applied); a later `surprised` still loses the initiative and is announced as "lose initiative, but cannot be surprised" |
| `the encounter begins with a fair roll` (many spellings) | takes back only what went *against* the party: drops the party's Surprised and a lose/surprised outcome; leaves a win or a surprised enemy |
| `you know the stamina of <keyword>` | exact stamina for every monster with that stat-block keyword, for the campaign |
| `reveal <zone>s [during the next combat]` | that zone type becomes player-visible at the encounter beat |
| `unlock <name>` | a `(Locked)` entry joins the board |
| `edge on <option>` (`double edge`, `bane`, `double bane`) | a standing edge/bane on that `###` test for whoever takes it; stacks with riders |
| `you fail the test`, anything unmatched | narrative only |

Initiative rules: `doc.data.initiative` (last outcome wins) decides who goes
first, but a surprised side overrides it -- a surprised party always loses
the initiative, a surprised enemy always gives it to the heroes. Surprise is
tracked separately in `doc.data.surprised.party/.enemy` and is never cleared
by a later initiative clause. Parse order matters: test-mod, fair-roll and
surprise-immunity clauses are matched *before* the generic rules that would
otherwise misread them (`you gain an edge on X` as an item; `you cannot be
surprised` as `^you .*surprised$`).

Names (`tbl_Gear`, `assets.monsters`) resolve at run time on the host; the
parser records every name for the validators.

## Encounter setup instructions and zone reveals

Under `# Encounter`, each line `Label: Place <n> <Object> objects in [the]
<Zone> zones [and delete the other <Zone> zones]` is a setup instruction
(`EncounterZones.RunEncounterSetup`, host, before the spawn, idempotent via
`doc.data.zoneSetup`). The host pools every tile of that zone keyword's
markup zones on the map, draws `n` at random, spawns the object asset there,
and with the delete clause trims each zone record to its drawn tiles. The
object is matched by its display name (`ObjectNodeLua.description`; there is
no `name`); the zone is an environmental keyword by name. Everything runs
elevated. A missing object or zone is logged and skipped. The live week:
`Trap: Place 4 Snare Trap objects in Trap zones and delete other Trap zones.`

A banked reveal (`revealZones`) is applied after the spawn and before the
dissolve: every record of the keyword gets `playerVisible = true`, and each
client's driver adds the keyword to that user's `mapoverlay:shownzones` once
per reveal. A player sees a zone only when both are true. The placed objects
are whatever the asset is; hiding or triggering them is the asset's job.

**Object reveals.** `reveal the <Object> object` (montage/narrative clause)
banks `doc.data.revealObjects[name]`; `EncounterZones.ApplyPendingObjectReveals`
runs beside the zone reveals and switches every map object of that name (its
`name` or `description`) from `inactive` to active, recording what it switched
in `objectsRevealed` so `/eotwmontage reset` can switch it back. The author
leaves the object inactive (Object Properties -> deactivate). A loot chest
works this way: its loot component holds the treasure.

**Bystanders.** `Hostages: Civilian tokens stay out of initiative.` (also
`take no turns`, `<A> and <B> are bystanders`) parses to `{kind =
"bystanders", names}`. `GatherCombatSides` skips any token whose name is a
listed name, starts with "<name> ", or whose bestiary `monster_type` is it
(`EncounterOfTheWeekGame.IsBystander`). With no initiative entry the Monster
AI never picks them as strike/advance targets, and the burst planners count
them as friends (they are unaffiliated monsters), so they are not hit either.
They also make no opportunity attacks and provoke none: EotW wraps
`creature:CanOpportunityAttack` (which both the `OnMove` dispatch and the
token HUD's OA preview ask) to fail when either side is a bystander, in EotW
games and authoring tests only.
What happens to them is an Encounter Script's job (below).

**Encounter Scripts in EotW.** Core Encounter Scripts (`MCDMEncounter.lua`,
"Encounter Scripts") attached to the `[[encounter]]` ride into the live
encounter (`StartCombatWithTokens` deep-copies the encounter) and run on the
EotW host (`IsElectedHost` accepts a player host). A script `victory` replaces
"all monsters defeated" for `CheckEncounterOutcome`; a script `defeat` is
honoured too. The Dwarvish Bandits' inline "Hostage Rescue" script polls
every 0.7s: a living hero within 1 of a restrained hostage purges Restrained;
each new `endTurnTimestamp` on a player initiative entry walks every freed
hostage `squares` along its `MarkMovementArrow` path to the nearest free
safe-zone tile (elevated `token:Move`, freeMovement); a hostage on a
safe-zone tile is rescued. Victory: every living hostage rescued; defeat:
every hostage dead.

## Narrative beats

```
# Narrative

[[scene]]

Beat intro.

## The Crossroads

The road forks.

Choose together: Which way do you go?

### Take the high road

|+1 hero token

### Take the low road

## The Shrine

Choose individually:

### Offer a coin

|You gain 1 Healing Potion
```

- `## <Name>` sections play in order. A section's `[[scene:x]]` overrides the
  beat's backdrop while that section is up.
- Mode marker paragraph, matched loosely ("together", "agree", "as a group",
  ... vs "individual", "each hero", "separately", ...); the default is
  together, with a warning when a section has 2+ options and no marker.
- `### Option` prose is its description; `|lines` are rules text in the same
  clause grammar. No power rolls in narratives. A section with no options
  gets an implicit Proceed.
- **Together** = one vote per **player** (party-owned heroes collapse into one
  shared voter). Rules text is re-aimed at the whole party (one ally, not one
  per hero). **Individually** = one choice per **hero**: each option applies
  once for the group that took it (self clauses on each chooser, party and
  pool clauses once).
- Choices can change until the last one is in. A split vote is settled by a
  random **voter** (not the majority) with a deterministic flash across the
  candidates (`decision.startedAt` + the shared clock, 21 steps over 3.2s,
  landing on the winner), then applied.
- Lingers: 4s after a section that applied something, 0.4s after one that
  applied nothing.
- `Unlock: <Feature>` lines (see below) belong to narrative beats.

## Optional features and Tactical Preparation

`Unlock: Intelligence` (a paragraph in a narrative beat or one of its
sections; registered features live in `EncounterScript.FEATURES`) turns the
feature on for the rest of the game (`doc.data.unlocked`). The stage shows a
callout explaining it while a white rectangle blinks round the new pool cell,
until the section resolves. A week that never unlocks it plays without it.

**Intelligence** is a party pool (`data.intelligence`, the total, + its own
history log) that is also tracked per hero (`data.intelligenceByHero =
{[charid] = n}`, each hero's unspent share), earned by `+N Intelligence`
clauses. Who earns it (user direction 2026-10-09):

- a montage test or delve obstacle: the hero who made it;
- a narrative option picked individually: **each** hero who picked it gets
  the full N;
- no hero behind it (a montage consequence) or a choice the party agreed on
  (`ctx.splitIntelligence`): N is **split evenly** across the heroes, the odd
  points going to whoever holds the least, ties in roster order.

The two numbers are only written together (`EncounterMontage.CreditIntelligence`
/ `SpendIntelligence`). Any part of the total no hero holds -- Intelligence
earned before per-hero tracking existed, or with no heroes on the map -- is
"shared" and any player may spend it. A hero's unspent Intelligence shows on
their hero card (roster, montage and prep stages alike) as a brain chip with
the count just above the name plate, and not at all at 0.

At the encounter beat, before traps and spawn, **Tactical Preparation**
(`EncounterPrep.lua`) offers three bars at 1 Intelligence per notch. Each
player spends **their own** heroes' Intelligence (plus any shared part); a
player with several heroes spends their combined total, each point coming
off whichever of their heroes holds the most. The screen's header shows the
local player's "N yours to spend" with "M in the party" beside it (an
onlooker sees only the total):

| Bar | Levels (players only ever read the rung they are on) |
|---|---|
| Surprise | surprised / lose initiative / roll / win / enemy surprised -- opens on what the montage decided; bought levels are applied with the montage's own clauses |
| Traps (only if the beat has a setup instruction) | unaware / "You know where some of the traps are." (two of the placed traps, drawn at random, are marked: `EncounterZones.BankPartialReveal`) / all marked (a banked reveal); opens at 2 if the montage already earned the reveal |
| Enemy Stamina | none / bar / exact (`enemystambardisplay`); **with this feature on, the week starts the party at `none`** |

A player's Proceed appears once **their own** Intelligence is spent (or
nothing can be raised), and every player must press it (one voice each). The final levels show for 4s, then
the encounter beat carries on. State: `data.prep`. Bar texts come from
`EncounterPrep.BarInfo`, not the document.

## Runtime state and authority

Everything lives in the `eotwscript` mod document (next to `eotwstate`):

```
beat                       -- current beat index (host-stamped)
montage   = { beatIndex, round, phase = "arriving"|"rounds"|"consequences"|"done",
              acted, taken, vanquished, removed, removedForPartySize,
              unlocked = {key=round}, expired, testmods, turn, consequences,
              consequenceIndex, requests, handled, log, seq }
             -- turn carries pardon (the field list is in EncounterMontage.lua's header)
montageScene = { id, index }   -- the scene page cursor (the one player-written key)
narrative = { beatIndex, sectionIndex, phase, choices, decision, result,
              announce, requests, handled, log, seq }
prep      = { ... }            -- Tactical Preparation
allies    = { [heroCharid] = { charid, ... } }
items     = { [heroCharid] = { {itemid, name, qty}, ... } }   -- the montage haul
montage.consumeSeq                     -- bumped by every item use (see "Consumables in a montage")
initiative, surprised = {party, enemy}, noSurprise, surges = { [heroCharid] = n }
zoneSetup, revealZones, zonesRevealed, unlocked, intelligence, intelligenceByHero,
intelligenceLog,
chestSeen, stageDismissAt
reinforcements = { arrived = { ["<sectionId>-r<round>"] = {round, at, island, count} },
                   spawned = { charid, ... } }
```

- **Host-arbitrated, single writer.** Players stamp
  `requests[userid] = {seq, kind, ...}`; the host tick (0.5s) validates and
  applies. The one exception is the scene page cursor, which the acting
  player advances directly (`AdvanceScene`) so dialogue is not sluggish.
- **Ids must never contain `/`.** Ids are document keys, and the engine joins
  keys into patch paths unescaped, so `vanquished["r1/x"]` is stored as
  nested keys on every other client. Entry ids are `r<n>-<kind>-<slug>`.
- `arriving`: the stage is up (it is what the held loading screen reveals)
  but nobody can act until the host tick, which only runs once the party has
  arrived.

**Turn lifecycle (montage).**

1. `approach {heroid, entryId}`: the hero is the requester's (or
   party-owned), has not acted this round, the entry is available, and no
   turn is in flight.
2. Scene intro (status `scene`). The hero goes alone: there are no
   companions and no assists (removed 2026-10-18, user direction; the
   gathering, `accompany` / `stayBehind` / `setOff`, `m.accompanied`, the
   pre-roll `assist` / `assisting` statuses and Teamwork's go-along are
   gone).
3. `choosing`: `choose {optionIndex}` (gated by riders) or `pass` (Leave,
   which passes the turn; not offered inside a delve).
4. The option's pre-roll scene.
5. `rolling`: **the owning client rolls**, not the host. The test shows as
   a synthetic test ability in the timeline sidebar with the roll dialog
   embedded: 2d10 + the characteristic, Skilled +2 for the first listed
   skill the hero is trained in, the normal edges/banes, rider,
   standing-edge and perk chips. The roll is shared to every other client's
   sidebar as a read-only card, whose Accept / Re-roll appear there as
   pingable ghosts (see "Roll button pings" under the stage). Once the dice
   are thrown the roll cannot be cancelled (`noCancelOnceThrown`); a cancel
   before that returns the turn to choosing.
6. `rolled {tier, total, attrid, skillid}`, then perk offers on a failed
   test (status `perk`): Brawny, Lucky Dog, Put Your Back Into It! (any
   other hero with it, delves included), and **Pardon My Friend** -- on a
   failed Presence test any other hero with the perk may make the test
   instead (status `pardon`, `pardonRolled`): Presence + their own skill,
   edges and perks, plus a bane, on the test's table; their roll replaces
   the hero's (the hero's blessing does not carry over). Once per test. A
   Pardon roll never made is dropped after 5 minutes
   (`PARDON_ROLL_SECONDS`) and the hero's own roll stands.
7. Outcome scene, then **resolve** (`ApplyResolution`, elevated): apply the
   tier's clauses, mark acted/taken/vanquished, log it. A resolved turn
   never blocks the next approach.
8. Round end when every hero has acted or nothing is left; then the
   consequences phase (each unvanquished, unremoved, unexpired threat, one at
   a time; anyone presses Continue), then done.

**Only the hero at the entry counts.** Knacks (`#### If ...` versions),
secret options (`Allow` riders), edge/bane riders, languages (garbling and
`PC speaks X`) and the other scene conditions all read the hero making the
test. The Ritualist blesses only their own test (the ritual needs a touch).

**Effect application** (`EncounterMontage.ApplyEffects(ctx)`, shared by
montage, narrative, delve chests and prep): items via `SetItemQuantity`
(recorded in `items`); stamina via `InflictDamageInstance` (source "Montage:
<entry>" / "Narrative: <section>"); malice via `CharacterResource.SetMalice`;
hero tokens and intelligence via their pools; allies via
`game.SpawnTokenFromBestiaryLocally` + partyId-then-ownerId + `eotwAllyOf`;
initiative and surprise on the document (Surprised goes on the heroes
immediately via `SetHeroesSurprised`, duration end-of-encounter). `ctx.heroEntries`
gives a multi-target apply (narratives). Hidden effects are applied and then
removed from the `applied` list.

**Haul hand-over**: a hero's player can drag a haul icon onto another hero's
card to give one unit (`giveItem {heroid, targetId, itemid}`; the host
re-checks ownership, the haul record and what the hero really holds, worn
items included: a treasure found is auto-equipped, and the give takes it off
first via `GiveItem`). The icon
decrements optimistically. Only montage finds can be handed over; consumables
the hero carried in show on the strip but stay with them.

**Consumables in a montage** (BUILT 2026-10-09, user direction; untested in
the app). Heroes can use their consumables during the montage rounds:

- **The strip** beside each hero card (`EncounterMontage.GetStripItems`) holds
  the montage haul plus every consumable the hero carries, so items brought
  from town are usable too. A consumable's count is what the hero really
  holds.
- **Using one**: the hero's own player clicks the icon and gets a menu with
  one entry per use (each mode of a multi-mode item). Free (no maneuver), any
  time in the rounds, except while that hero's own test or Pardon
  roll is out (`ConsumeBlockedReason`). The owning client casts the item's
  ability exactly as the action bar would (`EncounterMontage.ConsumeItem`:
  `ability:Cast` with `pay = true` and a `costOverride` that spends only the
  item), then sends `consumed`, which only bumps `m.consumeSeq` so every
  stage rebuilds (it is in `TurnSignature` and retires the `HeroFacts`
  cache). That request waits for the user's previous one to be handled
  (requests share one slot per user).
- **Which uses work away from the map** (`ConsumableUses`): the ability
  targets the user (self, or a target ability that may target itself), or
  is "you and each ally" (`targetType all`, ally, self-target), which in a
  montage reaches only the user (a hero is alone at a location); and every
  behavior is an ongoing effect, heal, purge, temporary Stamina or
  Recoveries (or invokes a self ability made only of those). Anything else
  (strikes, areas, auras, walls, forced movement, raising the dead,
  trigger-only items like Mirror Token) shows greyed "(combat only)". An
  ability filter that fails (Elixir of Saint Elspeth with no Victories)
  greys it with its own reason. Greyed context-menu entries show no tooltip,
  so the reason is in the entry text.
- **Durations** (user decision 2026-10-09). A SHORT effect (numeric rounds,
  end of turn, save ends, end of encounter) lasts one location: the turn
  the hero is in when they use it, else the next turn they take; it ends when that turn resolves, and
  anything left ends when the rounds end. A LONG effect (until respite, or
  no duration -- "for an hour" items are authored that way) lasts the whole
  encounter, combat included. Mechanism: an effect counted in rounds that
  is made outside combat expires at once
  (`CharacterOngoingEffectInstance:Expired`), so EotW wraps
  `creature:ApplyOngoingEffect`: while a montage use is casting on this
  client (`Consume.capture`) a short effect on the targeted heroes is made
  with NO duration and marked `instance.eotwMontageUse = {itemid, item,
  turnSeq}`. The marker lives on the token, not in a request. The host tick
  (`MaintainMontageUses`) binds an unbound marker to the turn its hero
  takes, removes it when its turn resolves or another turn starts, and removes every
  marked effect once the phase leaves "rounds". `EncounterMontage.
  EndMontageUses` (from `ApplyPendingCombatBoons`, every combat host tick)
  is the backstop. The same tick trims the haul record of a used
  consumable to what the hero holds.
- **The alert** (`EncounterMontage.ItemBenefits`): while a hero stands at an
  entry (scene or choosing), each of that hero's items is tried on: its
  effects are added
  as TRANSIENT built-in effects (`_tmp_builtinOngoingEffects`, never saved
  or sent), `TestRiders.CreatureFacts` is read off the creature, and the
  options are weighed again through a facts override in `HeroFacts`. It
  reports a secret option that would appear ("Could reveal a hidden
  option here", unnamed), a knack version that would open, more edges from
  riders, or a power-roll modifier that would switch on for the test
  (Concealment Potion on a Sneak test). Cached 2s per (hero, item, turn state). The
  icon gets a green border and a "!" badge (everyone sees it), its tooltip
  leads with "Use it now:" and the benefits, and hovering it lights up the
  options it helps (`itemBenefitHighlight` on the scene option buttons and
  the option detail card).
- **Translating garbled speech** (user direction 2026-10-09). The host keeps
  a garbled line's own words on the step (`step.plain`, set in
  `BuildScenePart`). The stage asks `EncounterMontage.HeroSpeaks(t, lang)`
  (the same test `SceneEnv` uses) when it shows a line: once the hero
  speaks the language, a garbled line shows as written. While a garbled line
  is on screen the narration label checks every 0.5s; when the group gains
  the language (an item such as Imp's Tongue -- the `consumed` bump retires
  the facts cache) the line is "transposed": it fades out (`transposing`,
  0.45s), its words and font are swapped, the speaker reads "(in X)", and it
  fades back in with a brief green glow (`translated` pulse). `ItemBenefits`
  also flags an item that would teach the language of a garbled line in the
  scene ("Lets you understand the X being spoken").
- **Not covered**: a characteristic change from an item is not weighed for
  the alert; lines already paged past are not re-shown, and `if PC speaks
  X` scene branches stay as the host built them; a Recovery item is not
  flagged before "Press deeper"; using the same short effect twice keeps one
  instance, which ends with the earlier binding.

**Allies in combat**: `GatherCombatSides` puts player-controlled non-heroes
on the heroes' side; the AI ignores owned tokens; defeat counts heroes only;
Hero Death is heroes-only.

## Script features added for The Dwarvish Bandits (2026-10-04, untested in the app)

The grammar is in the /eotw skill's `script-reference.md`; in short:

- **Round scenes and video.** A `[[scene:x]]` directly under `## Round N`
  sets `round.sceneTag`; `EncounterMontage.MontageSceneImage(script, beat,
  round)` picks the latest round scene at or before the current round, else
  the beat's. The montage stage checks it every refresh (it used to set the
  backdrop only when the beat was rebuilt). Every backdrop goes through
  `SetBackdropScene`: a video asset (`assets.imagesTable[id].isVideo`) is set
  as `bgimageStreamed = id .. "###LOOP" .. guid` (a private, muted, looping
  player; a plain bgimage video goes blank when it ends), and the aspect fit
  falls back to `gui.GetImageDimensionsCallback` when there is no sprite.
- **Entry dice tables** (`entry.tables[MatchKey(name)]`) and the `rolltable`
  clause: rolled with `math.random` on the host inside `ApplyEffects`
  (`ctx.entry` is now passed by every montage call site), the row's effects
  applied through a nested `ApplyEffects` (depth-capped).
- **New effects**: `damageboon` ("Montage Boon: Rolled Damage +N", a `power`
  modifier with `damageModifier`), `maxstamina` ("Montage Curse: Stamina
  Maximum -N", attribute `hitpoints` add -N), both until the next respite and
  pre-created by `PrepareBoonAssets`; `loseconsumable` (random consumable,
  silent fallback to 1 Recovery); `startzone`; `revealobject`.
- **2026-10-17 (Aixco Hollow montage)**: `immunityboon` ("you gain poison
  immunity 2", any Draw Steel damage type in `EncounterScript.DAMAGE_TYPES`):
  "Montage Boon: Poison Immunity N", a `resistance` modifier (Damage
  Reduction N to that type), until the next respite, pre-created by
  `PrepareBoonAssets`. `loserecovery` takes dice ("each party member loses
  1d3 recoveries"): `effect.dice` is rolled for each target separately, and
  `effect.qty` holds the most it can take.
- **Montage dice are rolled by the players (2026-10-17, user direction).**
  Before a landed tier (`ApplyResolution`, non-delve) or a consequence
  (`ApplyConsequence`, the "continue" request) applies,
  `EncounterMontage.PendingDice(effects, ctx)` lists the dice its clauses
  need: each `roll on <table>` (key `t:<clause>:<n>`, rolled by the acting
  player) and each hero's share of a dice `loserecovery` (key
  `r:<clause>:<charid>`, rolled by that hero's owner). If any, `OpenDice` puts
  `m.dice` out (the turn waits in status `"dice"`; a consequence hides its
  Continue). The player is prompted: the stage shows a **Roll** button
  (`DiceRollButton`, while `EncounterMontage.MyDiceWaiting()`), and one click
  (`EncounterMontage.RollMyDice`) arms that dice seq for this client; until
  then nothing is thrown (2026-10-17: the dice used to throw themselves the
  moment they went out). Once armed, `ClientTick` rolls each of this user's
  dice with `dmhub.Roll`, ONE AT A TIME (the next goes once the host has recorded the last, since
  `SendRequest` keeps one request slot per user), and sends `diceRolled
  { diceSeq, key, total }` -- `diceSeq`, never `seq`, which is SendRequest's
  own request counter (a `seq` arg overwrites it and the host drops the
  request as old). When every total is in, `ResumeDice` re-runs the
  resolution/consequence with `ctx.diceTotals`, which `ApplyEffects` reads
  before falling back to `RollDiceExpression`. `DICE_ROLL_SECONDS` (45) rolls
  for anyone who never does. Stage: `DiceCard` (one line per roll, the table
  with landed rows lit) and `DiceHint`; `TurnSignature` includes the dice seq
  and landed count. Hidden clauses, delve obstacles, chest rows and
  narratives still roll silently on the host. Verified live 2026-10-17
  (Flotsam x2, Rising Waters 1d3 x4, the 45s fallback).
- **Riders**: `movement` (climb = `IsClimber`, fly/swim/burrow speed > 0,
  teleport) and `wealth` (`CalculateNamedCustomAttribute("Wealth") >= N`)
  requirement kinds; `(Round N)` in a rider label (`rider.round`) gates it on
  `facts.round`, which `EncounterMontage.HeroFacts` fills from the montage.

## The stage (UI)

`EncounterMontageStage.lua`. One presented dialog, `eotwmontage`, presented
by the host through `GameHud.PresentDialogToUsers` with **constant args**
(`{}`). `GameHud` rebuilds a presented dialog whenever its args change, and
forgets -- without destroying -- a dialog presented twice, so
`EncounterMontage.Present` returns early when the stage is already up.

- **The mounted script stage** (`CreateScriptStage`) is created once for a
  whole run of stage beats and owns the shared chrome: opaque background,
  scene art (an unchanged image is not reloaded), dim, pools strip, the
  ref-counted action-bar hide (`hideactionbar`, restore deferred 0.15s so a
  handover cannot blink it), the screen-space cursor mode, and the
  loading-screen release. Inside it sits ONE body -- montage, narrative or
  prep -- swapped when the beat kind changes.
- **Handovers between stage beats never uncover the map**:
  `AdvanceFromStageBeat` seeds the next beat's state, then stamps the beat
  index, then runs its first tick, in one pass.
- **The dissolve to combat**: the encounter beat spawns behind the stage,
  then `EncounterMontage.DismissStage()` stamps `stageDismissAt`; every
  client snapshots the screen (`dmhub.StartScreenTransition`), hides the
  stage under the snapshot and cross-fades it away over 0.8s. Only then is
  Draw Steel rolled. A 4s timeout keeps a stuck surface from wedging combat.
- **Montage body**: Opportunities on the left and Threats on the right. Only
  entries in play are shown: they materialize when their round comes and
  fade out when dealt with at round end (staggered; opacity is not inherited,
  so the fade classes go on the whole card subtree). A round with a scaling
  directive shows nothing until the draw lands. The header holds the title,
  the intro, "Round N of M" and who is still to act. The centre is the turn
  panel. The bottom row holds the hero cards.
- **Outcome icons** (2026-09-30, uncommitted): every entry card and every
  option button carries a row of icons for what it *may* lead to, computed
  from the parsed effects (`EncounterScript.EntryOutcomes` /
  `OptionOutcomes`, in `OUTCOME_ORDER`, gains first):

  | Icon | Kind | Comes from |
  |---|---|---|
  | brain | Intelligence | `intelligence` |
  | hero token | Hero Tokens | `herotoken` |
  | gold chest | treasure | `item` |
  | blue shield | Temporary Stamina | `temphp` |
  | malice diamond | Malice | `malice` |
  | red sword | harm | `stamina`, `loserecovery` |
  | "?" | anything else, including unreadable clauses | white "May lead to a mysterious reward." on opportunities; red "Beware, this threat has an unknown consequence." on a threat (consequence only) |

  Teased tiers count, `{hidden}` clauses and the critical tier do not, and a `Delve:` option takes
  every obstacle test and chest row. Most opportunities show the "?" because
  flavour prose counts as unreadable. Presses pass through the icons, so
  click and drag are unaffected.
- **Hero cards** (`CreateHeroCard` with `showStats`, uiscale 1.2):
  characteristics down the right edge, trained skills under the name, the
  controlling player, and the hero taking the test (or stepping in with
  Pardon My Friend) in gold with the characteristic and skill in use
  highlighted. A hero who has approached is dimmed (`acted`). A card the
  local user can act with wears a pulsing green ring (`eotwCanActRing`) and
  is `draggable` only then (`LocalUserCanAct`). Drag a card onto an entry,
  or click the card then the entry (droppable targets light up). Ally mini-cards stack against the
  card's right edge. The **haul strip** down the left edge holds one icon per
  item with a tooltip; new items drop in with the pickup sound.
- **Scene stage** (`CreateSceneStage`, the centre during a turn): the hero on
  the left and the cast on the right, standing on a bottom dialog box
  (portraits fade at the top and sides, `edgeFade` set on the panel itself --
  it is not applied from a class rule). The speaker lights up and grows;
  others sink back. Narration is italic in the box; speech shows under the
  speaker's gold name. Typing is local and layout-stable (the untyped rest is
  drawn clear). Only the acting player gets the caret and pages. Choices sit
  in the box as an RPG menu (Leave is the do-nothing choice); hovering one
  shows its test mid-stage. While the dice tumble, the live tier is
  highlighted and teasers stay hidden until the roll settles (`LiveTierRows`
  subscribes to the shared roll's dice events). The chest card and the delve
  haul card appear mid-stage.
- **The hero** (CreateSceneStage's `heroSlot`): the one hero at the entry
  (`SyncHero`), shrunk with a transform `scale` from its bottom-left corner
  when the stage is short. Box contents per status include
  `PerkOfferChildren` and `PardonChildren`.
- **Roll button pings** (core, `Timeline/EmbeddedRollDialog.lua` +
  `Timeline/AbilitySidebar.lua`; user direction 2026-10-08): a roll shown
  with the ShowDialog option `pingButtons` (every montage roll, from
  `ShowMontageRoll`) broadcasts its Accept Result and Re-roll (caption,
  hero-token icon, enabled) in `dialogState.pingButtons` once the dice land.
  Everyone else's read-only card (`CreateReadOnlyRollInfo`) shows them as
  ghosts with a dotted outline (`borderStyle = "dotted"`). Clicking a ghost
  writes `[userid] = {rollId, button, at}` to the Timeline mod's
  `rollbuttonpings` document (each user writes only their own key); every
  client's copy of that button -- the roller's real one and every ghost --
  pulses with a ring in the pinger's `displayColor`, three times
  (`CharacterPanel.PulseRollButton`). Only pings made after a card (or the
  roll) appeared pulse on it. A ghost does nothing to the roll.
- **Narrative body**: a centred panel with the text, the prompt, option cards
  (buttons in an agreed section, drop targets in an individual one), the
  hero row with each hero's choice ("Ready" while an agreed vote is open, a
  pulsing "?" for heroes still owed a choice), and the split-decision flash.
- **Prep body**: the three bars, the pool, Spend and Proceed/Wait.
- **Other players' cursors**: the stage sets `dmhub.screenSpaceCursorSurface =
  "eotwstage"` (ref-counted). The engine then shares pointers as 0..1 screen
  positions to clients showing the same surface, drawn over the UI. The
  `blockingui` class suppresses sending, so the stage must not carry it.
  Unverified: that the cursors sort above the stage.

UI facts learned here that apply elsewhere:

- Style transitions run per rule, so put `transitionTime` on the rule whose
  match changes. A class present at creation applies at full strength with no
  ramp, so "born with the class, remove it a frame later" is the shape for an
  entrance.
- Style `y` accumulates across all matching rules.
- The engine paints valid drop targets `drag-target`, darkening only their
  direct children's text.
- `selfStyle` is write-mostly: reading a key it never set raises.

## The authoring test (BUILT 2026-10-05, untested; needs an engine build)

User direction (2026-10-05): testing an encounter in the authoring game
should be quick, through menu options rather than the dev drivers: pick heroes
from the pregens installed in the game, launch into the montage or straight
into the combat, get the full EotW interface, and have an easy way back to the
normal Director UI. This is what `codex-eotwauthor` authors use; the dev
drivers below remain for single-beat poking.

**Decisions taken with the user (2026-10-05):**
- **True player view.** The Director plays the test as a *player host*:
  player vision, player UI, the strict rules binding them, the same as the
  host of a real EotW game. Accepted cost: entering and leaving refresh the
  game (as view-as-player does).
- **A test plays on from where it starts**, through every later beat, to
  combat and its outcome, like a real game. Three starts: **From the Start**
  (beat 1, opening narratives included), **Montage** (the first `# Montage`
  beat), **Combat** (the `# Encounter` beat).
- **End Test puts the map back as authored**: combat ended with no victory
  screen, the hero copies, allies and spawns deleted, traps/zones/revealed
  objects restored, script state cleared, and every game setting the test
  overrode (and the hero-token pool) restored.

**Engine: `dmhub.playerHostModeForced`** (`GameController.playerHostModeForced`,
`LuaInterface.cs`; stub hand-added to `Definitions/dmhub.lua`). Player-host
mode used to exist only in a directorless game. The new client-only,
session-scoped switch makes `playerHostMode` true in an ordinary game for a
client with hosting status; `playerHostModeSuppressed` still wins. Its setter
forces the view-as-player hard refresh when `isDM` changes, and
`GameHarness.RefreshGame` carries it across that refresh (like the
suppression). `dmhub.directorlessPlay` (= directorless game OR forced) now
gates the pressure-plate game freeze in `LevelObject.cs`, so a trap does not
freeze a test with nobody to unfreeze it. NEEDS BUILD.

**The flow** (`EncounterOfTheWeek.lua`, "the authoring test"; UI in
`EncounterTest.lua`):
1. **Game menu** rows `Test Encounter: From the Start / Montage / Combat`
   (plus `/eotwtest start|montage|combat`) show for the Director while the
   current map's script has that beat, no test exists and combat is not live
   (`CanStartTest`). They are registered without `dmonly` (that is decided at
   load, and a test reloads the file as a player) and hide via `filtered`.
2. **The hero picker** (`EncounterTest.ShowDialog`): every hero character in
   the game that is not on the current map (`TestCandidates`, via
   `dmhub.GetAllCharacters`), module pregens first
   (`module.IsCharacterAvailableInModule`), then "Other heroes in this game";
   a Start-at dropdown; 1-6 heroes; the last pick is remembered
   (`eotw:testheroes` preference). Heroes already standing on the map are
   named, because the montage and combat take every hero on the map.
3. **StartTest** parks `{gameid, mode, heroes, at}` in `_G.EotwPendingTest`
   and sets `dmhub.playerHostModeForced = true`; the game refreshes.
   `playerHostMode` reads true the instant the switch is set, before the
   refresh, so the request stays parked until a live instance's
   `RunTestSetup` has waited out the reload (2s, `gameLoadingProgress`, map
   + hud up, and every setting it saves registered: `TestSettingsRegistered`);
   only a copy of the file loaded after StartTest takes it (`m_loadedAt`; the
   pre-refresh copy once ran the setup mid-reload and touched
   `permission:playersinitiative` before `MCDMInitiativeBar.lua` registered
   it -- "Could not find setting"), unless no reload comes within 15s; a
   request whose switch never took is dropped after 30s.
4. **TestArrival** (host, player-host mode): `EncounterMontage.ResetTest()`
   for a clean slate; the record `eotwstate.test = {phase = "setup", mode,
   by, startedAt, mapid, heroes, saved = {settings, heroTokens}}` with every
   overridden setting saved (`numheroes`, `permission:playersinitiative`, all
   of `g_forcedGameSettings`); `PlaceMyHeroes` pastes copies of the chosen
   heroes into the Start zone as this user's own heroes (the real pregen
   path: level 1, detached); `numheroes` = party size clamped 3..7, Hero
   Tokens = party size, players-run-initiative, forced strict settings;
   `expectedUsers`/`arrived` = this user; the chosen beat is begun
   (montage/narrative `Begin`) and stamped; the map script attached; phase
   `running`.
5. **While running**, `IsEotwGame()` is true on the tester's client
   (`IsTestPlayer()`: running AND `dmhub.playerHostMode`; never cached), so
   the EotW HUD, the start-zone confinement, the arrangement panel, the
   strict rules and the paused trigger timers all behave as in a real game.
   `MapScriptHostThink` and `EnsureMapScriptRunning` accept
   `IsTestRunning()` too, so the host tick runs wherever it is elected.
   Real-game-only pieces stay off: no `RecordPendingOutcomes` (no town), no
   lobby `leave-game`, no `eotw:concludedgame`, no `LeaveGame`, and the
   Director-UI hatch preference is ignored. Everyone else in the authoring
   game keeps their normal view (though they would see the presented stage).
6. **The title-bar item** (`EncounterTest.CreateTitlebarItem`, supplied by
   the EotW interface's `titlebarPanels` hook while `IsTestPlayer()`, so it
   sits in the title bar's status area and never covers the initiative bar
   or the stage; a floating bar did, and was replaced 2026-10-05):
   "Encounter Test: <mode>" and END TEST. After an app restart mid-test the
   client is a Director again with no EotW interface: Game menu > Resume
   Encounter Test / End Encounter Test cover it (also `/eotwtest end`).
7. **The outcome**: the victory/defeat screen as usual (Victories are
   awarded to the copies); the host's Proceed ends combat through
   `EndTestCombat` (no battle log, no analytics) instead of the default
   teardown; then the `# Conclusion` / `# Defeat` story screen with an
   **End Test** button (`ShowStoryScreen{buttonText, busyText}`), or straight
   to End Test when the script has none.
8. **EndTest**: phase `ending` (the host tick stops), the AI stopped,
   `EndTestCombat`, `ResetTest()` (state, allies, spawns, traps, zones,
   objects, malice, map script detached), the hero copies deleted (from
   `test.placed` and `placedHeroes`), every corpse/loot object the test's
   deaths left destroyed (objects from the `corpse` keyword's blueprint not
   in `saved.corpses`, the ids noted at the start, so authored corpses stay),
   every token that was on the map at the start written back exactly
   (`RestoreMapTokens`: `dmhub.ImportCharacter{record, charid}` from the
   `eotwtestsnapshot` document, which `SnapshotMapTokens` filled with
   `dmhub.ExportCharacter` records after the start's clean-slate reset --
   position, conditions, stamina, re-created if deleted; this is what puts a
   hostage script's freed and moved Civilians back), saved settings and hero
   tokens restored, the arrival keys and the record cleared, then
   `playerHostModeForced = false`, refreshing back to the Director.

**Fixed after the first live try (2026-10-05, UNTESTED):** the New Player
Welcome document opened over the test (the refresh re-enters as a player
with no character; `DocumentNewUser.lua`'s EotW check now also counts a
parked `_G.EotwPendingTest` or a test on the record); heroes floated over a
sunken Start zone (-4): `GameController.PasteCharacters` (engine, NEEDS
BUILD) now stands every pasted token on the surface under its footprint
(`GetAltitudeMax`, which settles on the highest surface at or below the
loc), and `UnstackPlacedHeroes` moves heroes to `dest.withGroundAltitude`.
Monsters and allies had the same float: `game.SpawnTokenFromBestiaryLocally`
gained an `onGround` option (engine, NEEDS BUILD) that settles the token on
the surface in either direction instead of only raising it; the three
encounter fallback grids (`Encounter.SpawnGroupForReal`, the second grid in
`EncounterPanel.lua`, `LiveEncounter:DeployWave`) and the montage's
`SpawnAlly` pass it. Saved spawn positions keep their height (fliers).

**Known gaps:** a second Director in the authoring game could win the
map-script election (the host tick still runs there, since it accepts
`IsTestRunning()`, but that client does not see the test); a hero
already on the map joins the test (it is restored at the end, but
the start's reset heals it first, so the snapshot holds it healed).

## Dev tools

| Command | What it does |
|---|---|
| `/eotwscript` | dump the parse of the current map's script, warnings, name lookups |
| `/eotwvalidate` (Panels > Development Tools > Encounter Script) | dev-only validator panel: every beat, entry, option and tier with recognized clauses lit and the plain-English effect, problems, text-only clauses, and name/attr/skill lookups -- built on the runtime's own functions, so it cannot drift |
| `/eotwmontage start\|stop\|state\|reset` | dev driver for the first montage beat outside an EotW game; `reset` restarts the whole test (allies and spawned monsters deleted, state cleared, malice zeroed, heroes healed, traps and zones restored, map script re-attached) and refuses during combat |
| `/eotwnarrative start\|stop\|state\|force\|reset` | the same for narratives; `force` resolves on the choices in |
| `/eotwprep start\|stop\|state\|force\|reset\|unlock\|intelligence <n>` | Tactical Preparation |
| `/eotwzones setup\|reveal <zone>\|apply\|state\|reset` | traps and zones alone |
| `/eotwreinforce [state \| arrive <n>]` | list the script's reinforcement sections, its `Victory:` line (with how many such enemies stand now) and what has arrived; `arrive <n>` brings section n's next group in now (combat must be live) |
| `/eotwencounter start\|stop\|state` | the encounter beat outside an EotW game (`DevEncounterStart`): setup instructions, the spawn for `numheroes`, pending zone + object reveals, then `StartEncounterCombat` -- the montage's initiative outcome, bystanders and the arrangement pause (it stands in for the host tick's `ArrangeHostTick` until the queue exists; `m_devEncounter` lets the panel show). The Director plays both sides. `stop` abandons a held arrangement |
| `EncounterOfTheWeekGame.EnsureArrivalItems()` | the arrival item snapshot; `/eotwnarrative start` and `/eotwmontage start` take it too, so a playtest's treasure is tracked |
| `EncounterOfTheWeekGame.DebugGetState()` | the `eotwstate` doc |
| Codex menu > New Player Window (titlescreen, town open, admin) | a second window as the secondary account, opened into the town; see "Debug New Player Window" |
| Game menu > Test Encounter: From the Start / Montage / Combat, End Encounter Test; `/eotwtest start\|montage\|combat\|end\|state` | the authoring test: play the map's encounter as a player host with copies of chosen pregens; see "The authoring test" |

**Dev-driver trap**: outside an EotW game nothing stamps `doc.data.beat`, and
the stage chooses its body from it, so set it to the beat you are testing.
The party-size draw may also remove the entry you want to test.

## The Dwarvish Bandits (authored 2026-10-04)

Authored with /eotw in the Local game `1e3c159e-3f02-43d5-b681-bd5230db0a25`,
map `Encounter: The Dwarvish Bandits` (`b6f4bf92`): master document
`Encounter` (`adb94670`) plus 16 entry sub-documents in the map folder. Two
rounds: day (round 1) and night (round 2) video scenes uploaded from
`Dark Woods Edge Original Day HD.webm` / `... Night HD.webm` (`cd409aca`,
`16c33251`). Round 1: Dwarf Tinkerer (dice table, Wealth/Zaliac edges, party
temp Stamina), Exotic Herbs, Wanderers (Start2 unlock / chest reveal), The
Indebted Farmer, The Unattended Toll Post; threats Dangerous Plants, Roving
Bandits, Lost in the Badwoods (Required, `Edge (Round 1): you can climb or
fly`), Toll Collectors (lose a consumable). Round 2: A Worried Mother (its
one option enters the in-order delve `The Lost Boy`: Where Did He Go? ->
Down the Gully -> The Sinkhole Cave, one hero's turn, +3 hero tokens at the
end; it replaced a chain of `(Locked)` entries 2026-10-04), Mysterious Dwarvish Runes (rolled-damage / recovery-value
blessings, max-Stamina curse), The Caged Wolf; threats Golden Hand Lookouts,
Bitter Night Chill. The fight (reworked 2026-10-05, user direction: fewer
at the start, a wave every round): level-1 gold-tier dwarves on the ledge at
the start -- the Crates Gunner squad (Axethrowers), the Pens Trapper squad
(Catchpoles) and the Reel Winches (1 at 5 heroes, 2 at 6); EV 30 / 24 / 18
for 6 / 5 / 4 heroes (was 45 / 39 / 33 with the South Ledge gunners and the
lone Lookout trapper, both removed). `## Reinforcements: The Golden Hand`:
every round from round 2, from the `Reinforcements` zone painted on the
stairs that climb west off the ledge up to the ruins (tiles (7,-5) (6,-5)
(5,-5) (4,-5) (4,-4) (4,-3), keyword `f5f0517b`, map-scoped like Start2),
alternating the islands `Golden Hand Gunners` (Gunner + Hunters) and `Golden
Hand Trappers` (Trapper + Catchpoles): 4 minions + captain at 4 heroes, 6 at
5, 8 at 6 (balancing +2 / +4), EV 9 each; five shouts ("Don't let them get
away!" ...). `Victory: The heroes also win once every Dwarf on the map is
defeated.` The hideout narrative now warns the party about the stairs and the
way to buy time. The two Civilians stay bystanders under the inline Hostage
Rescue script. The
Treasure Chest (inactive, loot = Bastion Belt) is revealed by the Wanderers.
The map's info bubble (`79776ab1`, hidden from players: `map:playerinfobubbles`
is off) links to the master `Encounter` document; the empty `Room 1` document
it used to point at is left in the folder.

## The week's script as it stands

The authoring game's `Encounter` document (`98a5a5bf`, filed under
`Encounter: Goblin Ambush`, map `9ca4404c`) is a ~2 KB master that links 16
sub-documents in the map's journal folder:

1. **`# Narrative`**: "Ajax's Patrols" (Press on), and "Goblins in the Wode"
   (a flavour-only agreed vote: deep wood or game trails).
2. **`# Montage`**, two rounds.
   - Round 1: Mysterious Cottage (incl. an `Allow`-gated arcane option),
     Elvish Enclave (`Edge: You speak Yllyric`), Wayside Shrine, The Little
     Stalker, Talk to the Goblin, Scout out the Forest (Required), Dangerous
     Beasts, Treacherous Ravine, Traps in the Forest.
   - Round 2: Hunter's Camp, Hot Spring, Warded Standing Stones, Forbidden
     Tomb (-> the `Forbidden Tomb Delve` sub-document: nine obstacles, the
     d6 chest table), Goblin Scouts, Gathering Darkness.
   - The entries carry scripted scenes (the cast is played by bestiary
     monsters, e.g. the Witch is the Wode Hag; lines in Hyrallic, Yllyric,
     Szetch and Ullorvic), with emotes throughout.
3. **`# Narrative`**: "Surrounded" (Draw steel!).
4. **`# Encounter`**: the Trap setup line and `[[encounter]]`.

The master and sub-documents are YAML files in
`C:\dev\eotw\objectTables\documents\` (`encounter.yaml`,
`mysterious-cottage.yaml`, `forbidden-tomb-delve.yaml`, ...). Edit an entry in
its sub-document, not the master. The week does not use `Unlock:
Intelligence` or `+N Intelligence` yet. A pre-scenes backup is the private
document "Encounter (backup before scenes, 2026-09-23)" (`4711d2b5`).

---

# The montage builder (BUILT 2026-10-12; first version verified live)

User direction (2026-10-11): a dedicated graphical interface for building
and editing EotW montages that works through the journal system, presents
everything graphically, and covers every possibility the script grammar has
now, so an author can add and edit montages without learning the markdown.

## Decisions (2026-10-11, with the user)

1. **The markdown stays the source of truth.** The builder edits the
   script's own journal documents through a lossless layer; hand edits, the
   `/eotw` skill, publishing and the parser are unchanged, and existing
   scripts open as they are. (Rejected: a structured document type like
   `MontageDocument` with generated text; it would need a migration and
   break hand-editing.)
2. **Scope: montages and delves first**, fully. Narratives, the encounter
   beat (setup lines, reinforcements) and the story sections show as text
   blocks in the beat list until a later step (B9).
3. **A dedicated builder window**, opened from a button on script documents
   and from the Game menu. A script spans the master and many
   sub-documents, which one journal tab cannot.
4. **A new entry goes into its own sub-document** in the map's journal
   folder, named after the entry, with an include line `[Name]` in the
   master under its round (the current authoring convention).

## Why a lossless layer (what was found)

- `EncounterScript.Parse` builds the full tree, but it is lossy: it trims
  every line, collapses blank lines, pulls rolls, `Options:` and
  `Consequence:` out of the prose order, joins free clause lines, and drops
  prose before the first beat. There is no tree-to-text writer. "Parse,
  edit the tree, regenerate" would therefore rewrite authors' documents.
- What it does keep is a `line` on nearly every element, and
  `ParseExpanded`'s `sources[expandedLine] = {docid, name, line}` maps each
  line back to the sub-document it came from.
- So the builder never regenerates a document. Each edit replaces only the
  lines of the field it changes, in the document that field came from, and
  the real parser re-runs afterwards. This is the standard technique of code
  refactoring tools (Roslyn, rust-analyzer, recast): a lossless syntax layer
  under a semantic model.

## The layers

1. **Parser line fields** (BUILT, additive): `roll.line`, `roll.tierLines`
   (none for an automatic critical), `roll.lastLine`, `free.lines`,
   `entry.descriptionLines` / `approachLines` (lists of `{first, last}`
   spans), `entry.consequence.lines`, `entry.sceneSepLine`,
   `option.textLines`, `knack.textLines`, `beat.introLines` (a montage
   beat's intro paragraphs that sit outside a round; prose mixed into a
   round's scaling lines has no span), delve `orderLines` / `chestLines`,
   table `line` / `lastLine`, `beat.encounterLine`, and narrative
   `section.textLines` / `promptLines` (for B9). Every line number is in the
   expanded text; `EncounterScriptEdit.Source` turns it into a document line.
2. **`EncounterScriptEdit`** (BUILT, pure Lua, tested):
   - `Split` / `Join`: lines with their own terminators (`\n`, or `\v` for
     a journal soft break), byte-identical round trip, numbered exactly like
     `EncounterScript.SplitLines`.
   - Patches `{docid, first, last, lines}` and `Apply` (bottom-up per
     document); `Source`, `SourceRange`, `PatchExpanded`, `PatchAfter` (an
     insertion after a sub-document's last line stays in that sub-document),
     `ElementRange` (an entry / option / knack's extent in its own document).
   - Writers that read back to the same values: `EntryHeadingLine`,
     `OptionHeadingLine`, `KnackHeadingLine`, `RoundHeadingLine`,
     `AttrText`, `RollHeaderLine`, `TierLine` (teasers), `RiderLine`
     (`Allow` / `Edge` / ... with `(Round N)`), `RollLines`, `TableLines`,
     `ScalingLine`, `ProseLines` + `ProseProblem` (refuses prose that would
     become a heading, rule, scene break, tag or field), `OptionBlock`,
     `EntryBlock`, `IncludeLine`.
   - Edit operations returning patches: `SetLine`, `DeleteLine`,
     `SetEntryHeading`, `SetDescription`, `SetConsequence`, `SetRollHeader`,
     `SetTier`, `ClearCritical`, `AddRider` / `SetRider` / `RemoveRider`,
     `SetRules` (a whole roll or free-rules block), `InsertAfterElement`,
     `DeleteElement`, `ElementLines`.
   - Writing rule found while building it: **`Consequence:` must come before
     the first option.** Below an option the parser reads it as that
     option's text and warns "threat has no Consequence:". `SetConsequence`
     and `EntryBlock` write it right under the card text. NB the worked
     example in the `/eotw` skill's `script-reference.md` (Goblin Scouts)
     puts it after the option, so it shows the warning; the real scripts
     put it first. That doc example was not changed (flagged to the user).
3. **Clause catalogue** (B2, BUILT 2026-10-20 -- see "Outcome forms" below): there is no enumerable list of
   effect clauses; `ParseClause` is an ordered if-chain of about 26 kinds.
   Add `EncounterScript.CLAUSES`: per kind a label, parameters (quantity,
   item / monster / zone / object / keyword / option / entry name, self vs
   party) and a template that writes the canonical clause, with a unit test
   that every template parses back to its own kind. That keeps the picker
   from drifting from the parser. Requirements for riders, knacks and scene
   conditions come from TestRiders: `CAPABILITIES`, `BARE_FORMS` and the
   requirement kinds of `ParseRequirementClause`.
4. **The builder window** (B3 on). It loads the map's script with
   `EncounterMontage.LoadScript`, keeps `docTexts` for the master and every
   included document, and writes a change by applying patches, then
   `doc:SetTextContent(text)` + `doc:Upload(orig)` on a fresh copy from
   `dmhub.GetTable("documents")`. When one change touches several
   documents, uploads are spaced with `dmhub.Schedule`, because a second
   upload to the same table in one frame is dropped. It watches each
   document's path (`/assets/objectTables/documents/table/<id>`) and
   re-parses when another client or the journal changes one. It keeps its
   own undo stack of text snapshots per change.

## The interface (as built, `EncounterMontageBuilder.lua`)

Opened from **Game > Montage Builder** (Director only) or `/eotwbuilder`,
on the current map's script (`EncounterMontage.FindMapScript`). A full-screen
modal: the board on the left, the editor for what is picked on the right,
Undo / Test this montage / Validator / Close in the header, the last action
and the real-problem count in the footer.

- **Board**: the montage intro; each round with its party-size lines (a
  form per line, 2026-10-20: "Between [n] and [n / or more] players: [-n]
  Opportunity; [-n] Threat" + Remove, rewritten whole with `E.ScalingLine`;
  a line dropping nothing is refused; + "+ Party-size line"), the count it introduces, its
  entry cards (kind, name, options / secret options / scene, tags, problem
  count) and "+ Opportunity" / "+ Threat"; "+ Round". Then each delve the
  montage's options lead into: a settings card, its obstacles, its scenes,
  "+ Obstacle". Several montage beats: a dropdown in the header.
- **Entry editor**: name (renaming an entry that is the whole of a
  sub-document named after it renames the document and the master's link
  too), kind, Required / Locked / Temporary, card text, approach
  (`Options:`) text, consequence (threats), the scene (or "+ Add a scene",
  which writes `---`), dice tables, the options, problems and text-only
  clauses, and Edit entry as text / Open in journal / Move to round /
  Delete entry (two clicks; a sub-document entry is unlinked and its
  document hidden).
- **Option editor**: name; prose (unscripted entries) or pre-roll scene
  (scripted); the test (name, characteristic checks, skill chips with a
  searchable add dropdown -- unknown skill names show red -- tiers 1-3 as
  teaser + text with the recognised clauses lit and described, the
  automatic critical toggle or a written critical); or no-roll rules; the
  riders (effect, round, requirement, with TestRiders' requirement
  problems inline; + Edge / + Bane / + Secret); the outcome scene; knack
  versions (the same rules editor under an `#### If <requirement>`
  heading, with its own scenes); and Edit as text / Make it no-roll / Make
  it a test / + Knack version (no roll / own test) / Delete option. "+
  Option that enters a delve" makes a new delve sub-document (included at
  the END of the master, after every beat, so it never splits the
  montage) with a starter obstacle, chest and exit scenes.
- **Scene editor** (forms 2026-10-20, user direction: "dramatically lower
  the bar for who can write montages"): each line is read with the parser's
  own rules (`E.ReadSceneStep`, which runs `CompileScene` on the one line
  with the entry's `actors`) and shown as a form for its kind; a form writes
  its line back whole (`E.SceneStepLine`) keeping the indentation.
  - Narration: a text box. Says: speaker (PC, every character who enters in
    the entry, "Unknown voice (???)", "Named voice off stage" + a name box),
    emote (hidden for an off-stage voice), language (searchable), then the
    words on a full-width line. Enters: name + "played by" a searchable
    bestiary dropdown (red note when the monster is not found: no
    portrait); renaming a character renames their entrances, lines, exits
    and emotes in every scene of the entry in one undo step. Exits: a
    character dropdown. Emote: PC or a character + the emote.
  - Branches: an "if" row holds the condition as clause rows (`E.ReadCondition`
    / `E.ConditionText`): [If / Unless / and / and not / or / or not]
    [predicate] [value]. Predicates: PC is a (ancestry) / (class), was a
    (career), speaks, is skilled in, has the perk, can (TestRiders
    capabilities), chose the option (the entry's options), the roll is
    (tier 1-3, critical; flagged red outside an outcome scene), PC has /
    is (anything, typed), custom. Ancestry vs class is decided by looking
    the name up in the classes table (both write `PC is a X`). A condition
    with parentheses stays a text box. "+ and" / "+ or" copy the last
    clause; the condition's parser problems show under it.
  - A new branch is written with its `end`; the "if" row offers "+ Else if"
    (copies the if's condition, inserted before the else or end) and
    "+ Else" (once). An unclosed if offers "+ End". "x" on an if removes
    the whole block (two clicks), on else-if / else that branch and its
    lines, on a line just the line; "end" has no x.
  - "+" on each row is a menu (Narration, PC says, Character says, Character
    enters, Character exits (only when there are characters), Emote, Branch):
    inside the branch on an if / else-if / else row, below otherwise; "+ Add
    a step at the end..." appends at the top level.
  - Dropdown lists (`B.Lists()`: bestiary 617, languages, ancestries,
    classes without subclasses, careers, perks, skills, capabilities) are
    built once per window.
- **Delve editor**: in sequence or random, the chest interval, the intro,
  which scenes exist and "+" buttons for the missing ones; obstacles edit
  in the entry editor, delve scenes in the scene editor with the chest's
  treasure table.
- **Writes**: every change is a patch; the builder's own copy of each
  document is updated, the parse re-run, and the documents uploaded (each
  `dmhub.Schedule`d 0.1 s apart). While an upload is in flight the 1 s poll
  for outside changes skips that document. Undo is a stack of
  per-document text snapshots.
- **Text-only clauses** (the parser's "unrecognized effect" warnings, 128
  of them in Goblin Ambush, all deliberate flavour) are listed apart from
  real problems and never counted as problems on the cards.

**Verified live 2026-10-12** in the authoring game `e96656f3` (Goblin
Ambush): the board and every editor render the real script; a tier edit
lands as exactly that change in the right sub-document and Undo restores
it byte for byte; + Opportunity made a sub-document under the map and
linked it in round 1; renaming it renamed the document and the link;
Delete unlinked it and hid the document (the hidden "The Old Mill"
document is left in the journal); a batch of a scene-line edit, a scene
step added, a chest-row edit, a knack version added and Elvish Enclave
moved to round 2 then undone left all 17 documents byte-identical. Found
and fixed on the way: deleting a link left a double blank line (it now
takes one blank line with it).

**Scene and party-size forms verified live 2026-10-20** in `e96656f3`
(Mysterious Cottage): every line of the real scene read into the right
form; an emote, an off-stage voice, "+ Else if", a predicate change to a
class, "+ and", "or not", a branch inserted from the "+" menu and renaming
the Witch to Xochi (17 lines across 4 options' scenes, narration
untouched) all wrote the expected text, and Undo restored every document.
The party-size forms read all three real lines. Tests: `encounter_script_test.lua`
951, `encounter_script_edit_test.lua` 255 (scene/condition round trips).

**Outcome forms (B2) built 2026-10-20** (user direction: "a space for free
form text, then dropdowns for rewards and consequences ... with all our
possibilities exposed"):
- `EncounterScript.CLAUSES` (in the parser) lists every mechanical clause
  kind ParseClause knows -- 26: item, hero tokens, Intelligence, heal,
  temporary Stamina, surges, recovery value, rolled damage, damage
  immunity, ally; lose Stamina, lose Recoveries (a number or 1d3 / 1d6),
  lose a consumable, maximum Stamina reduced, Malice; initiative (win /
  lose / surprise / surprised), cannot be surprised, fair roll, know
  monsters' Stamina, reveal zones, extra starting zone, reveal a map
  object; vanquish, unlock an entry, edge/bane on a test, roll on a dice
  table -- each with a group (Reward / Cost / Next encounter / Montage),
  a label, its parameters and defaults. `EncounterScript.ClauseText`
  writes the canonical clause; the edit test checks every kind with every
  value its picker offers parses back to itself (an item of qty > 1 is
  written plural; FindGear drops the s).
- `E.ReadOutcome` / `E.OutcomeText` split a tier line into the free text
  (the flavour before the first effect) and the effects. Each effect keeps
  its own words while untouched, its punctuation (the whole run: "..."),
  flavour written between effects as a `prefix` and after the last as a
  `suffix`, and braces (`hidden`); adjacent hidden effects share one pair
  of braces. All 215 outcome lines of Goblin Ambush come back byte for
  byte, and every one of their 241 effects rewritten from the catalogue
  keeps its meaning.
- The builder's `OutcomeEditor` (tiers 1-3, a written critical, threat
  consequences, no-roll rules -- now one editor per "|" paragraph with
  "+ Paragraph" -- and dice-table rows): a free-text box, then one row per
  effect: [Group: kind] [parameters] [Shown / Hidden] [x], a one-line help
  note for the less obvious kinds, and "+ Add a reward or cost..."
  (searchable). Parameters are dropdowns: who (the hero / every hero),
  how many, the gear table (416), the bestiary, the montage's (Locked)
  entries, every test name, the entry's dice tables, edge/bane, the
  initiative outcome, damage types, monster keywords (from stat blocks'
  own `keywords`; `Keywords()` evaluated every modifier), single-word
  zone keywords, the map's object names (a text box when a list is
  empty). "Vanquish the threat" is offered on threats only. Changing a
  row's kind keeps who / how many (not a dice maximum) and its
  punctuation. The old green "Does: ..." preview is gone.
- Verified live in `e96656f3` (Dangerous Beasts' consequence): a count to
  1d3, a new initiative effect and its outcome, Hidden, a kind change,
  free text, remove; every write was the expected text, the visible text
  dropped the hidden clause, and Undo restored the document.

**Not yet**: the same condition form for knack
requirements and Allow / Edge / Bane riders (they are still text); round backdrop `[[scene]]` tags; moving an
entry written inline in a shared sub-document (refused: move it as text);
renaming a delve; a "Montage Builder" button on the journal document
itself; narratives and the encounter beat (B9). Not seen: two Directors
editing at once (the poll takes the other's text, but an edit made from a
stale parse could patch the wrong lines).

## The Encounter Builder (BUILT 2026-10-20; verified live on a test script)

User direction 2026-10-20: a "higher level" builder for the whole narrative,
choosing what is unlocked, adding montages (which open the Montage
Builder) and other entries. Decisions (asked): an `Unlock:` line goes into
the FIRST narrative beat only; narratives get full forms; the encounter
beat gets forms now; the new builder REPLACES the "Montage Builder" menu
item.

- **Where.** Game > **Encounter Builder** (`/eotwencounter`). The same
  window as the Montage Builder in a "script" view (`session.view`):
  `EncounterMontageBuilder.lua` owns the window, session, undo and the
  shared forms and hands them to `EncounterScriptBuilder.lua` (NEW,
  registered after EncounterMontageBuilder in the EncounterOfTheWeek
  codemod, Firebase confirmed) as `ctx`. A montage card's "Open in the
  Montage Builder" switches the view; the montage header has "Back to the
  script". `/eotwbuilder` still opens the montage board directly. A map
  with no script is offered "Create the script": a journal document
  "Encounter Script" filed under the map with a starter narrative, montage,
  encounter and the three story texts (`B.Load(docid, pendingDoc)` copes
  with a document the server has not sent back yet).
- **Outline.** Optional features (card); "Before the adventure" (Town
  Gate); "The adventure, in order" (each beat with ^ / v, problem count;
  + Narrative / + Montage go in front of the encounter, + Encounter when
  there is none); "After the adventure" (Conclusion, Defeat, + buttons for
  missing ones). `S.RootSpans` finds each beat's lines in the master: from
  its heading (or the include link that brings it in) to the next
  top-level section; a link that brings in several sections is `shared`
  and cannot be moved or deleted here.
- **Features.** A checkbox per `EncounterScript.FEATURES` entry. On: an
  `Unlock:` line after the first narrative beat's intro (a new narrative
  at the start when there is none). Off: every `Unlock:` line for it is
  removed. The editor says which beat or scene explains it, what the party
  is told, and warns when Intelligence is on with nothing granting it, or
  off while outcomes grant it.
- **Narrative editor.** Intro; per scene: name, text, who chooses
  (together / each hero) and the question (`E.NarrativeModeLine`, written
  over the `promptLines` or after the text), choices (name, description,
  and the outcome editor per `|` line -- `option.ruleLines`, new in the
  parser), + Choice, Delete; + Scene, Delete this narrative. The parser's
  implicit "Proceed" option (its `line` is the scene heading!) is never
  shown as a choice.
- **Montage card.** Intro, rounds and their entries, "Open in the Montage
  Builder".
- **Encounter editor.** The opening line-up and every reinforcement group
  show their monsters and EV (the island's saved `RichEncounter`) and an
  **Open Combat Encounter Builder** button (2026-10-21, user direction; no
  "Open in journal" in the encounter section): it opens
  `Encounter.CreateEditorDialog` -- the same builder the journal island's
  settings button opens -- on a copy of the island's encounter, after
  closing this window so the map is free for staging. Each Save there
  writes the encounter into the script document under the island's key
  (`IslandKey`: the tag's order among same-named tags). With no opening
  island the button first writes `[[encounter]]` under the beat heading
  (a `keepTags` commit, so a reinforcement island below keeps its data as
  its key moves from `encounter` to `encounter-1`). Verified live on a
  hidden test document: a reinforcement group saved 4 Abyssal Hyenas; the
  button then added the opening island, the hyenas moved to
  `encounter-1`, and the opening Abyssal Rift saved under `encounter`.
  Setup forms (`E.SetupLine`): "Place [n]
  [object] objects in [zone] zones (and delete the other ones)" from the
  map's objects and zone keywords, bystanders, an extra way to win
  ("every [keyword] on the map is defeated"); reinforcement groups: name,
  Arrive (on rounds "2, 4" / every N rounds from X until Y, written with
  `EncounterScript.DescribeSchedule`, which the schedule parser reads
  back), Enter zone (or "where their group was placed": the parser's
  "no Enter: zone" warning is shown as that choice, not as a problem),
  shouts, + Group (another `[[encounter]]`). The parser now records
  `scheduleLine`, `zoneLine`, `shoutLines`, `noteLines`.
- **Story editors.** Town Gate / Conclusion / Defeat text, add, delete.
- **Islands keep their data.** A journal binds repeated tags to their data
  BY ORDER (`scene`, `scene-1`, ... in `GetReferencedAnnotations`), so
  moving or deleting a beat that holds a `[[scene]]` would have handed the
  other beats the wrong backdrops. Structural edits commit with
  `keepTags`: `E.RekeyTags` tracks every tag through the line map of the
  edit (`E.PatchLineMap`, or `E.SwapBlocks` for a move; a tag on an
  inserted line takes a removed tag's identity, so delete + insert is a
  move), `B.CommitTexts` re-keys the document's annotations and uploads
  them with the text, and Undo restores both.

**Verified live 2026-10-20** in `e96656f3` on a throwaway document (now
hidden, outside the map folder) whose three `[[scene]]` islands carried
distinct markers: moving beat 1 down left each beat on its own marker
(keys swapped), Undo restored text and keys; deleting the first narrative
moved the montage's island onto key `scene` with its own data; Intelligence
on wrote the line into the first narrative; a choice and its +1
Intelligence; Open in the Montage Builder and back; a setup count edit;
an extra victory; + Reinforcements, Arrive "every other round from round
2", Enter the Start zone; + Narrative landed in front of the encounter;
+ Conclusion. Tests: edit test 831 (writers, starter blocks, tag re-keying),
parser test 951. **Not seen live:** "Create the script" on a map with no
script; the last cosmetic change (warning de-duplication).

## Build plan

| Step | What | State |
|---|---|---|
| B1 | parser line fields, `EncounterScriptEdit`, `tests/encounter_script_edit_test.lua` | BUILT 2026-10-11, tested offline |
| B2 | clause catalogue (`EncounterScript.CLAUSES` + test), requirement / condition picker data | BUILT 2026-10-20: catalogue + outcome forms; requirement picker for riders/knacks not started |
| B3 | window shell: open (Game menu, `/eotwbuilder`), load, apply + upload, watch, undo; `EncounterScriptEdit.lua` (after `EncounterScript.lua`) and `EncounterMontageBuilder.lua` (after `EncounterTest.lua`) registered in the EncounterOfTheWeek codemod, Firebase confirmed | BUILT 2026-10-12, verified live; journal-document button not done |
| B4 | the board: rounds, cards, scaling, add / delete / move entries (new sub-document + include line) | BUILT, verified live |
| B5 | the entry editor (heading, prose, consequence, options, tests, tiers, riders, knacks, free options, tables) | BUILT, verified live |
| B6 | the scene editor | BUILT (line rows + templates), verified live; no per-field speaker / monster pickers yet |
| B7 | the delve editor | BUILT, verified live (renaming a delve not supported) |
| B8 | inline validation, Show in journal, Test this montage | BUILT (parser warnings per entry, Open in journal, Test this montage, Validator); the validator's name checks and knack coverage are not inline yet |
| B9 | narratives, encounter setup, reinforcements, story sections | later |

**Running the edit tests against real scripts.** The corpus is not in the
repo. Dump the authoring repo's documents to text (TextStorage sections
joined in sorted key order; raw vertical tabs in the YAML must be swapped
out before `yaml.safe_load` and back after), write a `manifest.lua` of
`{id, name, folder, hidden, file}` rows, then run
`../dependencies/lua/bin/lua.exe tests/encounter_script_edit_test.lua
<dir>/manifest.lua`. The 2026-10-11 run used `C:\dev\eotw` (Goblin Ambush
and older journal pages). The Dwarvish Bandits documents live only in
game `1e3c159e` and are not in it.

**Open questions (ask the user when the step comes up):**
- Is the builder Director-only in any game, or only with
  `dev:encounteroftheweek` on?
- A document open in the journal editor while the builder writes it: warn,
  refuse, or let the journal's own refresh take it?
- More than one montage beat in a script: tabs, or one board per beat?

---

# The module and publishing

## What the module carries

`mcdm-encounteroftheweek` (fullid; stable id, a new version each week) ships:

- every encounter map (`Encounter`, `Encounter: <title>`) with its Start zone
  and no live monsters;
- every document filed under those maps (script + sub-documents);
- the `Start` environmental keyword;
- the Hero Death global rule;
- the 9 pregens (identified by the pregen party
  `7870ffcb-c942-4db9-a831-bf0210aa11ea`);
- the pinned codemods (EncounterOfTheWeek `cdc19d98-...`, Monster AI
  `263594e2-aca1-4ce5-b70e-8d690695d7b4`);
- and the dependency closure of all of it. Content from `venla-deliantomb` (art,
  the DelianTomb codemod) arrives as a declared dependency.

Installing the module writes `codeModsFromModules` so the game loads the
codemods; `ReconcileStartingModuleCodemods` repairs games as versions advance.

### Compendium content the script needs

Montage effects use core rules content (Surprised, temporary Stamina, surges,
hero tokens, malice) and manufacture the Recovery Value effect at run time,
so nothing extra ships for them. **But item and monster names in clauses are
prose**: no dependency walk can see them. Any item or monster a week names
that is not in the core data module must be ticked by hand in ModShare, or it
silently grants nothing for players. `/eotwscript` and the validator check
only the *authoring* game's tables.

## Publishing headlessly

```bash
python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data"            # dry run
python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data" --publish   # ship
```

Both `--assets-dir` entries are required (the authoring game is in
local-assets mode; without them the tool reads a frozen store and drops the
documents). `--force` is currently routine for the standing warnings. Full
design in [`tools/eotw_publish/README.md`](../../tools/eotw_publish/README.md).
The facts worth knowing:

- The authoring game is a **Local** game; its data is
  `%USERPROFILE%/AppData/LocalLow/MCDM/Codex/local-games/e96656f3-.../game.db`.
  The tool copies it and runs the real local game server against the copy.
  It needs neither DMHub nor Unity.
- Maps are found **by name** every week (ids rotate). Document discovery
  ports the runtime exactly (info bubbles or a `parentFolder` chain;
  documents resolve against the merged game + module table; text from
  `textStorage.sections`, falling back to `content` only when that is
  absent).
- It refuses to publish without `--force` when the result would not play,
  and refuses outright when a hero outside the pregen party sits on an
  encounter map.
- **Payloads must be engine-shaped.** The game server stores arrays as
  numeric-keyed objects, which decode to null in a module payload, and the
  Firebase copy always *looks* clean. `strip_meta_keys` normalizes on read
  and `validate_engine_shapes` aborts a bad publish.
- `--verify-against <dataid>` rebuilds a past version and diffs it. Re-run it
  after any engine change to the publish pipeline.
- The publisher scans floor contents (the engine's walk never sees placed
  objects) and seeds non-core global rules.
- It copies each encounter map's `# Town Gate` text into the module record
  (`publishingProperties.eotwEncounters`), and logs what it found ("town
  gate text:"). A map name holding `. $ # [ ] /` cannot be a Firebase key
  and is skipped with a log line.

## Playtesting against local asset directories

An EotW game is created fresh each time, so the per-game `localassets:dirs`
cannot target it. The global preference `localassets:eotwdirs` (Settings >
Editing > "Encounter of the Week Assets (Developer)", needs `dev` and
`dev:encounteroftheweek`) is appended, at lowest precedence, for whichever
game sits in the account's EotW slot. Set it to the same pair as the
authoring game (`C:\dev\eotw`, then `C:\dev\dmhub\draw-steel-codex\data`) so
a playtest write-back and the authoring game edit the same files.

- **It is silent when empty**: the game just loads the published module. The
  only positive signal is `LocalAssets:: ACTIVE for game ...` in the log.
  Check the setting before a playtest.
- It is per client: everyone else plays the published module (and your
  overlay outranks Module and Core, so you play a different rule set).
- **Writes land on disk**: any asset edit during the session rewrites the
  YAML. Keep `C:\dev\eotw` committed before a playtest.
- Mod documents (all EotW runtime state) are unaffected.
- To hand it to another developer: dev mode + `dev:encounteroftheweek`, add
  their directories in that settings block, create or join from the EotW
  screen (both write the slot), and re-enter if already in the game. Paths
  are typed as Explorer shows them; a trailing separator was a trap until the
  `NormalizePath` fix.

## Community encounter modules and the encounter pool (BUILT 2026-10-03, untested)

**Superseded in part (2026-10-06):** the pool no longer feeds the Town Gate's
Form a Party. A community encounter plays in the **Proving Pits** until an
admin makes it the Encounter of the Week; only scheduled encounters appear at
the Gate. The publishing, discovery, encounter keys, pulling and the host's
module install below are unchanged. See "The Encounter of the Week and the
Proving Pits".

**Authoring module `codex-eotwauthor`** (created 2026-10-04 by the user in
the app): the EncounterOfTheWeek (`cdc19d98`) and Monster AI (`263594e2`)
codemods. Authors install it in their authoring game instead of
`mcdm-encounteroftheweek`, which would drag the official week's maps and
pregens in. It was code-only at first, so that community modules never take a
dependency on it and can never put a second (older) copy of the EotW code
into a real game, whose code comes from the official starting module.
**v2 (2026-10-05, user direction)** also carries the two rows a real EotW
game has that an authoring test needs: the **Hero Death (Encounter of the
Week)** global rule and the **Trap** zone type, under the SAME ids as the
official module's (`a011c97a`, `9b16ee37`), the Trap made a full keyword
(the official one is scoped to the official map). Without Hero Death a hero
who died in an authoring test stayed on the map. Same ids mean a community
map's Trap zones match a real game's Trap, and if a community module ever
picks the rows up as a dependency it is the same row, not a second one (not
verified whether the publisher pulls them in). The Start zone type is still
the author's own (matched by name). Published by script from game
`1e3c159e`; the rows were copied from `C:\dev\eotw\objectTables`. Keep both
copies in step when either rule changes. Its pinned code snapshot must be republished when the EotW code
changes (a dev machine's git folder overrides the pin anyway). The /eotw
skill preflight and ModShare's "cannot check scripts" error point at it.

User direction (2026-10-03): anyone with Encounter of the Week enabled can
publish a new kind of module, an **Encounter of the Week module**, from the
ordinary in-app publish dialog. Publishing it adds its encounters to the
**pool**: the encounters every party chooses from at the Town Gate.

**Decisions taken with the user (2026-10-03):**
- **Straight into the pool, and an admin can pull it.** No approval step;
  admins get a Pull / Restore control. This is acceptable while EotW is
  dev-gated.
- **Discovery filters the public module index** (`/ModuleIndex`, by
  `moduleType == "eotw"`). No server work. Consequence: only a module
  published **Public** or **Unlisted** joins the pool. A Private or Premium
  one never reaches the index.
- **Unlisted (2026-10-04).** A Listing Status offered only for the Encounter
  of the Week type, so an encounter can join the pool without being
  advertised in the module browser. It is published like Public (it is in
  `/ModuleIndex`, which the pool reads) with
  `publishingProperties.eotwUnlisted = true`; ModShare's Hot / New / Best
  tabs skip such a module unless the search text is exactly its module ID.
  Changing the type away from Encounter of the Week drops it back to
  Private. The "Submit to be included with DMHub" box is hidden for it.
- **The official module stays the base.** Every EotW game is still created
  from `mcdm-encounteroftheweek`, which carries the EotW and Monster AI
  codemods, the Start keyword and the Hero Death rule. For a community
  encounter, the host installs the community module on top during setup.
  Authors ship no framework.
- **One list, grouped by module.** The official encounters come first, then
  one flyout per community module ("<module> by <author>").

**Publishing** (`DMHub Core Panels/ModShare.lua`, the `eotw` entry in
`g_moduleTypes` plus `CheckEncounterModule`):
- The Module Type dropdown offers "Encounter of the Week" only while
  `dev:encounteroftheweek` is on. A module that already has the type always
  shows it. The type list gained two generic hooks: `available()`, and
  `publishingProperties(ctx)`, whose result is merged into the record at
  publish. The validator ctx gained `include(guid)`, which ticks an entry
  the way the author would.
- **The author works in a game with the official module installed.** The
  validator parses scripts with the EotW codemod, so without the module it
  shows one error and nothing else. That is also the game the author
  playtests in.
- **Errors (they block Proceed):**
  - no map named `Encounter` / `Encounter: <title>`;
  - two encounter maps with the same name;
  - a name holding `. $ # [ ] / |` or longer than 80 characters;
  - a map with no script, or a script with no `# Encounter` beat;
  - any included code (codemods), because a community module plays on the
    official module's code.
- **Warnings:** the first three script warnings per map, a map with no
  `# Town Gate` section, and a module that is neither Public nor Unlisted.
- **Documents are included automatically.** Every document in each
  encounter map's journal folder, plus everything those documents include,
  is ticked. Nothing else links a map to those documents.
  `EncounterMontage.ScriptForMap(mapid)` (new; uncached, any map) returns
  `{script, documents}`. `FindMapScript` was refactored onto the same
  helpers (`MapScriptCandidates`, `ChooseMapScript`) without changing its
  behaviour.
- At publish, `publishingProperties.eotwEncounters` is written from the real
  parser (`parse.story.towngate.text`), in the shape the Python publisher
  writes. The status line says whether the encounters are now in the pool.
- **Publish Encounter Update** (2026-10-19, user direction: an update should
  go up in one step, with everything needed selected). A Codex-menu row
  (`share` group, Director only, shown while `dev:encounteroftheweek` is on
  and the EotW code is loaded; also `/quickpublishencounters`).
  `mod.shared.QuickPublishEncounters` downloads every module published from
  this game, keeps the live `moduleType == "eotw"` ones, and picks one: the
  only one, else the one whose `includedAssets` holds the current map, else
  the author chooses. None: a notice pointing at Create Module..., because a
  first publish needs a module id, author and listing. It then opens the real
  publish dialog with `autoPublish`: the dialog stays hidden behind a
  progress line, the previous version's ticks are seeded as usual, every
  encounter map is ticked (except maps another of this game's EotW modules
  ships), and the think loop re-runs the type's checks (which tick the
  script documents) until a pass changes nothing. No errors: it clicks
  through page 2 and uploads with the module's existing settings (empty
  version notes). Errors: the content page comes back with them shown.
  Prose-named items/monsters are not ticked (the same gap as the dialog), but
  ones ticked by hand in an earlier version stay ticked. The official module
  (`moduleType` "general", Python-published) is never picked.
  `DMHub Core Panels/ModShare.lua`; luac + typing clean; uncommitted.
  VERIFIED 2026-10-19: in Goblin Ambush (`e96656f3`, which publishes only
  "general" modules) the row shows and gives the no-module notice; in Aixco
  (`ed8ae76b`) it republished `codex-aixcohollow` v2 -> v3 from the menu in
  one click, no Lua errors, the same 22 ticked / 30 shipped assets, still
  Unlisted, all three parts' Town Gate texts unchanged. NOT seen: the
  error-stop path, the several-modules chooser, a newly added script
  document or encounter map being picked up.

**The pool** (`Codex Titlescreen/EncounterOfTheWeek.lua`, "the encounter
pool" section):
- `CacheEncounters(force)` reads the official record with
  `DownloadModuleInfo` as before. It also runs
  `module.QueryModuleIndex{index = "all"}` and an empty `Search`, keeping
  the items whose `moduleType == "eotw"`.
- It then **re-fetches each candidate fresh** with `DownloadModuleInfo`.
  The index is an incremental local cache (`ModuleCache` pref, `mtime`
  deltas), and it never hears about a module that left
  `/ModuleIndex` (unlisted or deleted). Only a fresh record that is still
  `eotw`, `published`, not `deleted` and not `deprecated` counts
  (`PoolStanding`).
- Entries are `{key, moduleid, mapName, title, official, moduleName, author,
  townGate}`.
- The pool loads when the town is built, and again every time the Gate
  opens (`RefreshPool`), so a module published meanwhile appears.
- API: `GetEncounters`, `GetEncounter(key)`, `GetTownGateText(key)`,
  `EncounterDisplayName(key)`, `GetPoolModules`, `RefreshPool(cb)`,
  `SetModulePulled`, `ShowPoolDialog`.
- **Pulling.** The admin's Codex menu "Encounter Pool..." row (town open,
  next to New Player Window) lists every community module, pulled ones
  included, each with Pull or Restore. Pull sets
  `publishingProperties.eotwPulled = true` on the module's own record:
  `DownloadModuleInfo`, then `ModuleLua:Upload`, which the database rules
  allow for an admin. The author's next publish keeps the flag, because
  ModShare only rewrites the properties it owns. A determined author could
  still strip it from a modified client. The real lock is deprecation
  (`deprecate-module.py`), which also takes a module out of the pool.

**Encounter keys.** An encounter is identified by a key string:
- the bare map name for the official module's maps, so every existing party
  record, completion and the published v29 still mean the same thing;
- `<moduleid>|<map name>` for a community module's maps, so two modules can
  each ship an `Encounter`.

`EncounterOfTheWeek.EncounterKey` / `ParseEncounterKey` build and parse it.
The game side has its own `ParseEncounterKey`; keep the two in step. The
key rides:
- the party record's `encounter` (the server's 120-character cap is why map
  names are capped at 80);
- `eotwstate.encounterMap`;
- `eotw:pendingOutcomes` (`outcome.encounter`);
- `city_completions`, so one Victory is awarded per hero per key. The
  completions were never deployed, so there was no data to migrate.

The display reads "<title> (<module name>)" for a community key: the party
rows, the graveyard epitaph (`EotwRoster.lua`), and the story screen's
title, which strips the module id.

**Game side** (`EncounterOfTheWeek/EncounterOfTheWeek.lua`):
- `EnsureOnEncounterMap` now resolves a key and returns `key, mapid`.
- For a community key, the host runs `EnsureEncounterModule`:
  1. snapshot the map ids;
  2. `DownloadModuleInfo` -> `ModuleLua:Install`;
  3. wait up to 120s for a **new** map with that name;
  4. stamp `eotwstate.encounterModule`.

  The new-map rule is what tells it apart from a same-named official map.
- On a re-entry, the host uses the stamp instead of installing again.
- `RecordEncounterMap(key, mapid)` stamps `encounterMapId` as well.
  Members and resumes find the map by that id first, then by name.
- An unknown key falls back to the official `Encounter` map, as before.

**Known gaps / risks (untested):**
- The install runs behind the held loading screen, which times out after
  20s. A slow install would show the bare map before the stage goes up.
- Whether `ModuleLua:Install` works for a player host in a directorless DO
  game is unverified. The engine's own `additionalModules` path skips
  directorless games, which is why setup does the install from Lua.
- A community module's own dependencies install with it. Whether that
  re-imports the official module when the author's game declared it as a
  dependency is unverified.
- The pool's first fetch downloads the whole public module index (cached
  incrementally afterwards, as the module browser does).
- `LOADING_SCREEN_ART` is still the Delian Tomb art for every encounter (the
  module's cover art would be the natural choice). The pregens and the
  Recruit picker still come from the official module only.
- No Start-zone check at publish: a map without a Start zone publishes
  cleanly.
- The Python publisher (`tools/eotw_publish`) is unchanged and still
  publishes the official module. It does not set `moduleType`, and the pool
  reads the official module by id.

**To test** (needs an app restart; ModShare, the titlescreen file and the
EotW codemod all changed):
1. With the dev setting on, in a game with `mcdm-encounteroftheweek`
   installed, add a map `Encounter: Test` with a script document in its
   journal folder. Check the publish dialog: the type is offered, the script
   documents tick themselves, and the errors fire (rename the map, drop the
   `# Encounter` beat).
2. Publish it Public or Unlisted. Open the Gate: Form a Party shows the module's flyout
   and its backstory and credit line.
3. Form a party on it, Begin. The host log shows
   `EotW: installing the encounter module ...` and then the map. The member
   lands on the same map.
4. Win it: back in town the Victory lands, and the completion key is
   `<moduleid>|Encounter: Test`.
5. As admin: Codex menu -> Encounter Pool... -> Pull. The encounter leaves
   Form a Party. Then Restore.

---

# Open questions

- ~~**A disconnected player** blocks a montage round and a narrative
  section.~~ Decided 2026-10-09: free agents (see "Players leaving and
  coming back").
- **Observers**: join as a player with no heroes (works today), or a true
  spectator mechanism?
- **Does the player host see the monsters it runs?** With `canControl`
  elevation-aware the host now sees monsters like a player (no X-ray). If the
  host needs to notice a wedged monster, the debug hatch is the answer.
- **Hero victories** carried in from a campaign still feed the `victories`
  symbol. Zero them like the level clamp?
- **Hero Tokens after setup**: nothing re-awards them during the session, and
  nothing clears them at the end.
- **Intelligence** has no other spend and no persistence; the bars are fixed
  (a week cannot author its own rungs). "Each party member gains N Intelligence"
  parses the same as "+N Intelligence", so it credits the acting hero rather
  than every hero.
- **Kick UX**: the engine game's player list is not updated by lobby
  leave/kick, and a kicked client is not disconnected from the game.
- **Unlisted module access for non-owners** (fetching the pregen snapshot,
  creating a game from it) is unverified with a second account.
- ~~Remote hero portraits show a silhouette.~~ Fixed for roster heroes
  2026-10-03 (`dmhub.CreateDetachedCharacter` over `get-hero`; NEEDS BUILD,
  untested).
- Montage stage vs narrative/prep stages lay the hero row out differently
  (the montage row is ~80px lower). Unify?
- Not built: voice/sound per line; keyboard paging; scenes in
  narratives; a portrait override for a cast member; per-hero rider weighing
  in the Director's Request Rolls.

---

# Development Plan

Status keys: [x] done, [~] built but not verified live where it matters, [ ]
open, [-] superseded.

**Phase 1 -- dev gate, titlescreen link, screen shell.** [x] 1 setting + global
entry point, [x] 2 titlescreen link, [x] 3 screen shell.

**Phase 2 -- Lobby backend.** [x] 4 design, [x] 5 `LobbyObject`, [x] 6
arbitration handlers + unit tests, [x] 7 staging deploy + smoke test.

**Phase 3 -- C# lobby client + EotW screen.** [x] 8 `LobbyConnection.cs`, [x] 9
`lobbies` bridge, [x] 10 screen wired to the lobby, [x] 11 games list. Verified
live.

**Phase 4 -- creating and joining.** [x] 12 create flow (+ encounter dropdown),
[x] 13 hero slots in the roster, [x] 14 game lobby view (hero cards, picker),
[x] 15 kick + Begin gating (now 4-6).

**Phase 5 -- the module.** [x] 16 Start keyword, [x] 17 encounter maps +
documents, [x] 18 pregens, [x] 19 codemods bundled, [x] 19b headless publisher.

**Phase 6 -- launch and the in-game flow.** [x] 20 setup on arrival (heroes,
spawn), [x] 21 Begin -> launched -> ready, [-] 22 positioning/ready-up stage
(replaced by start-zone confinement), [x] 23 Monster AI auto-run + no Director,
[x] 24 automatic combat entry, [x] 25 start-zone confinement, [x] 26
victory/defeat + per-client Proceed + auto-exit, [x] 27 strict rules, [x] 28
player-host / directorless games, [x] 28b custom interface.

**Phase 7 -- encounter scripts and montages.** [x] 29 parser, [x] 30 beat
machine + deferred spawn, [x] 31 montage runtime, [x] 32 stage, [~] 33 combat
with allies (spawn and cards verified; AI/victory in real combat not), [ ] 34
two-client live playthrough of the scripted week, [ ] 35 publisher validation
of the grammar, [x] 36 initiative clauses, [x] 37 boon clauses, [x] 37b
loading-screen hold, [x] 38 surprise immunity, [x] 38b stray-pregen sweep, [~]
39 assists (superseded 2026-10-08 by companions + pre-roll assists, then
REMOVED 2026-10-18: heroes act alone), [x] 46 entries come and go with the rounds, [x]
47 sticky surprise, [x] 48 losing recoveries, [~] 49 traps + zone reveals
(headless only), [~] 50 scenes (single client), [~] 51 delves (played once,
tuning untested), [~] 52 sub-documents (montage on the split document
unplayed), [x] party-size scaling, locked / temporary entries, standing
edges, fair roll, test riders, teasers, hidden clauses, script validator,
haul strip + hand-over, stage cursors (engine), [~] outcome icons
(uncommitted), [~] 79 the authoring test: Game menu test from the start /
montage / combat as a forced player host, pregen picker, End Test clean-up
(built 2026-10-05; engine NEEDS BUILD; untested).

**Phase 8 -- narrative beats.** [x] 40 parser, [x] 41 runtime, [x] 42 stage,
[x] 43 beat machine, [ ] 44 two-client live test (genuine disagreement), [ ] 45
publisher validation.

**Phase 9 -- optional features.** [x] `Unlock:` features, [x] Intelligence pool,
[x] per-hero Intelligence (built 2026-10-09, prep spend untested live),
[x] Tactical Preparation (verified live up to the spawn), [ ] used by the live
week.

**Phase 10 -- Blackbottom, the town (designed 2026-10-01; server + basic client built 2026-10-02).**
Design in "Blackbottom: the town"; what was built is in "The town client".
[~] 53 **decide**: storage infrastructure DECIDED 2026-10-02 (one City DO);
spikes 1, 2 and 4 done (see "Spikes"); spike 3 (final-state read) open; the
open decisions 5 and 8 were taken at their recommended defaults where built.
[x] 54 **art**: placeholder uploaded 2026-10-02 (`39beb163-...`, a psd-tools
render, Grid + Labels hidden, 4096x2980). Swap in a Photoshop export later.
[x] 55 **engine**: `dmhub.ExportCharacter` / `dmhub.ImportCharacter` and the
`route = "city"` lobby option, stubs hand-added, BUILT (dev build
2026-10-02). Uncommitted.
[~] 56 **City DO** (`cloudflare-game-server`): BUILT 2026-10-02 -- `CityObject`
(extends the lobby), binding `CITY`, migration `v4`, the roster / outcome /
graveyard actions, roster-checked party claims, admin export; unit tests +
`city-smoke.ts` pass; DEPLOYED to staging 2026-10-02 and smoke-tested there.
Committed dmhub `4a0a9e3af`. `get-hero asJson` added and deployed to staging
the same day (uncommitted). Remaining: release deploy when the town ships.
[x] 57 **town screen shell**: built and verified live (map, drag-pan, nodes,
plaque, chat drawer). Not done: a veil that waits for the map image (the map
draws once its image arrives), and other players' active heroes in town.
[x] 58 **city sync**: built (`EotwRoster.lua`; tag `properties.eotwHero`,
revision map `eotw:heroRevs`). Recruit and edit pushes verified live;
conflict reload and a second machine untested.
[~] 59 **Hero's Guild**: built; Recruit, the active toggle and edit verified.
Create through a full builder session untested. Recruiting a titlescreen
hero (2026-10-09, `EotwRoster.lua` + `TitlescreenHeroes.List` in
`CodexTitlescreen.lua`) verified live on one client with a temporary level 3
Human Censor carrying an item: the copy reached the city at level 1 with no
items and its kit, the original stayed level 3 with its item, the faded
"Already in your roster" card showed after a restart, and dismissing the
copy through `DismissHero` worked. Uncommitted. **Open:** whether the copy
should also drop the original's `currency`, Victories, damage taken and
conditions (it carries them today).
[x] 60 **active-hero strip**: `EotwHeroCard.lua` shared with the montage HUD;
verified live.
[~] 61 **Town Gate**: unlock rule, lists and Form a Party verified to open;
the add-hero picker lists roster heroes only (the pregen claim path is gone)
with the active ones first; forming or joining a party now claims the active
heroes automatically (2026-10-03, untested), and other players' cards load
their portraits from the City (NEEDS BUILD). Forming a party,
joining and Begin with roster heroes untested.
[~] 62 **coming home**: the Victory half BUILT 2026-10-02, unverified
(conclusion-time outcome read -> `eotw:pendingOutcomes` -> applied in town
-> `put-hero` + `record-outcome {completed}`; see "Encounter stories and the
Victory award"). Open: landing in town, "Away" status in the guild.
Burying the dead BUILT 2026-10-09, untested: `OutcomesFor(userid, encounter,
result)` gives every placed hero who is fully dead (`IsDead()`, not dying;
the Hero Death rule's despawned token still resolves) an outcome
`{encounter, result, died = true}`, at a victory or a DEFEAT (user decision
2026-10-09: a defeat buries its dead; survivors of a defeat still take
nothing). Victories are noted when awarded, as before; a defeat is noted on
the way out (after Proceed), so a Recovery on Death prompt still open under
the defeat screen cannot bury a hero it saves. The town's `ApplyOutcome`
sends a died outcome straight to `record-outcome {died = true}` (no Victory,
no push); the re-list then drops the working copy. Absent players: the host
offers deaths (victory or defeat) like Victories, and the player must accept
in "While You Were Away" ("fell in battle", "Accept the Defeat") for the
hero to be buried -- Count as Abandoned buries no one. No server change: the
`died` flag rides inside the offered outcome.
[~] 62b **encounter stories + once-per-encounter Victory**: `# Town Gate`
(town, via the publisher), `# Conclusion` / `# Defeat` story screens, the
automatic award with "Already Completed" exemptions, `city_completions`.
BUILT 2026-10-02; server undeployed, module unpublished, unverified.
[~] 63 **graveyard**: the server half is the City's `record-outcome {died}` +
paged `list-graveyard`; the Graveyard location (everyone's fallen, own
marked) is built and its empty state verified. Not built: opening a fallen
hero's sheet from the city. `record-outcome {died}` is called by the
burial write-back (step 62, built 2026-10-09, untested).
[ ] 64 two-client playthrough of the whole loop on two machines: town ->
gate -> encounter -> town, a death in both players' graveyards, and the roster
present on a second machine.

**Phase 11 -- hero progression (OPEN; needs a design pass first).** [ ] 65
design what carries home (levels and bands vs treasure and renown; see
"Progression"), then plan it. The outcome log from step 62 is its input.

**Phase 12 -- hero builder and hero sheet (designed 2026-10-03; not
started).** Design in "The hero builder and hero sheet". [x] 66 design
decisions taken, [x] 67 `EotwBuild` step engine (headless, MCP-verified; uncommitted),
[~] 68 builder shell + Ancestry/Career pages, [~] 69 Culture/Class/
Complication/Appearance pages, [~] 70 Guild Create -> builder -> JoinRoster
(all built and user-tested once; round-1 fixes not re-tested; uncommitted),
[ ] 71 `EotwHeroSheet` from the Guild and the strip, [ ] 72 in-game card,
other players' heroes, sheet hardening, level-up.

**Phase 13 -- community encounter modules (designed and built 2026-10-03).**
[x] 73 decisions (straight in + admin pull, `/ModuleIndex` filter, official
module as base, grouped list), [~] 74 `eotw` module type in the publish
dialog (checks, auto-included script documents, `eotwEncounters`), [~] 75
the encounter pool + encounter keys at the Town Gate, [~] 76 host installs
the community module at setup (`EnsureEncounterModule`), [~] 77 admin
Encounter Pool dialog (pull/restore). All untested live. [ ] 78 per-encounter
loading art (module cover art), Start-zone check at publish.

**Phase 14 -- reinforcements (built 2026-10-05).** [x] 79 grammar
(`## Reinforcements:` with `Arrive:` / `Enter:` / `Shout:` and islands that
take turns; `Victory: every <kind> on the map is defeated`), parser + tests;
[~] 80 host runtime (`EncounterReinforcements.lua`: arrivals, shouts,
initiative, the clear-the-map OR, reset cleanup) -- needs a restart and a live
run; [~] 81 The Dwarvish Bandits reworked to use it (in game `1e3c159e`);
[ ] 82 show the extra victory on the objective strip; [ ] 83 publisher check
that `Enter:` zone keywords ship.

**Phase 15 -- one Encounter of the Week + the Proving Pits (built 2026-10-06).**
[x] 84 design with the user (see the section); [~] 85 City: schedule
(`set-week`, `/city/week`), debriefs (`danger-feedback`), stats, creator
feedback, nominations, admin report + HTTP route, unlock derived from
completions -- unit-tested, deployed to staging 2026-10-06; [x] 86 town: the Gate's week banner +
Past Encounters, the Proving Pits location, art and board, the debrief,
creator feedback, the admin week dialog -- verified live; [~] 87
game side: practice stamp, no award / outcome / treasure, practice card note,
pending debrief -- never run; [x] 88 seed the week with Goblin Ambush; [~] 89 the section's test list (town
side verified; a practice game and the locked node not yet); [ ] 90 republish the official module
without Angry Dwarves (optional: it is already offered nowhere).

**Phase 16 -- Downtime (designed 2026-10-10).** [x] 91 design + mockups +
spikes (titlescreen dice, lobby has no rollDialog, video probed, inn map
spot); [x] 92 the user's answers to Q1-Q7 (+ Catch Your Breath); [x] 93 assets
(inn video + poster uploaded, icons checked); [~] 94 City: Downtime tables,
`grant-downtime`, projects + rolls, slot cap, `list-projects` /
`project-roll` -- unit-tested, deployed to staging 2026-10-10; [~] 95 game side: wounds on the
outcome (victory and defeat survivors); [~] 96 town: wounds applied, respite
+ Catch Breath, hammer badge, the Blue Fish Inn location + looping video;
[~] 97 Guild slots + the Expand the Guild card + the project roll dialog
with breakthroughs; [ ] 98 single-client verification (the section's "To
test").

**Phase 17 -- the montage builder (designed 2026-10-11).** [x] B0 design +
the user's four decisions; [x] B1 lossless edit layer (parser line fields,
`EncounterScriptEdit`, tests incl. the corpus); [ ] B2 clause catalogue +
requirement picker data; [x] B3 window shell (open, load, write, watch,
undo); [x] B4 board; [x] B5 entry editor; [~] B6 scene editor (line rows);
[x] B7 delve editor; [~] B8 inline validation + authoring-test launch; [ ] B9 the rest of
the script (narratives, encounter setup, reinforcements, story sections).

**Phase 18 -- encounter series (built 2026-10-17).** [x] S1 design with the
user (account unlock, a Victory per part, no carry-over, series votes,
region-bounded parts); [x] S2 parser `# Part N` + tests; [x] S3 part-aware
script choice, island lookup, play area (region held from arrival, start
tiles, zone filtering), core `ApplyRegion{hold, anyMap}`; [x] S4 test Part
dropdown + validator rows; [x] S5 ModShare + Python publisher `parts`; [x] S6
town keys, part chips, part-aware Form a Party, unlock rule, practice wins
from the debrief; [~] S7 City `record-practice-win` + unlocks -- unit-tested,
NOT deployed; [ ] S8 the section's "To test" (author a series first).
[~] S9 carrying the story forward (tracks, part results, `# Results`):
signed off 2026-10-19; Lua steps 1-3, 6, 7 built (not run); City and town
wait on the series City source (step 0); steps in that subsection.

**Launch readiness (not started).** [ ] lobby on the release worker and games on
release DOs, [ ] non-owner module access verified, [ ] disconnected-player
rule, [ ] content hygiene (default map, orphan assets, pregen parties), [ ]
remove the dev gate.
