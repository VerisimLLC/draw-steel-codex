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
2. **Game lobby.** A player creates a game (public or private, and which of
   the week's encounters to play) or joins a public one, then fills hero
   slots with their own titlescreen heroes or the module's pregens: up to 4
   heroes per player, 4-6 per game. The creator is the host and may kick
   players.
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

# Where things stand (2026-10-02)

**Everything in the flow above is built**, from the lobby server to the
victory screen, and most of it has been played in real EotW games at some
point (live playtests on 2026-09-06, 09-16, 09-19/20, 09-24 and 09-30). What
has NOT happened is a clean multi-client playthrough of the current scripted
week from Begin to the titlescreen. Most of the script features were verified
on one client in the authoring game (the Director driving the party-owned
pregens through dev drivers), so the open risk is in the multi-client paths:
a second player's turns, rolls and votes, late joiners, and the beat
handovers on a non-host screen.

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
- **Lobby server.** It runs on the **staging** worker only
  (`game-server-staging`). The titlescreen connects with `staging = true` and
  creates games on `durableobjects-staging`. Deploying it to release is a
  launch task.
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
| **Outcome icons** on entry cards and option buttons (see "Outcome icons") | `EncounterScript.lua`, `EncounterMontageStage.lua`, `tests/encounter_script_test.lua` (461 checks) | Verified live in the authoring game, except the red "?" on a threat (only Goblin Scouts, a Round 2 threat, has one) |
| **Party size 4-6** (was 3-7) | `Codex Titlescreen/EncounterOfTheWeek.lua` (`MIN_HEROES`/`MAX_HEROES`), `EncounterOfTheWeek.lua` (comment only); server `cloudflare-game-server/src/lobby-core.ts` + tests (280/280) | Worker DEPLOYED to staging 2026-10-02 (it rode along with the City deploy; `lobby-smoke.ts` passes there); Lua NOT deployed, untested live |
| **No cancelling a montage roll once thrown**: a failed test could be retried via the roll card's X / ESC | `EncounterMontage.lua` (`noCancelOnceThrown = true`); core `DMHub Utils/Utils.lua` (`RollDialogCancelOffered`), `Draw Steel UI/DSRollDialog.lua`, `Timeline/EmbeddedRollDialog.lua` | Untested |
| **City DO** for the Blackbottom town (committed; listed for its deploy state) (2026-10-02; see "The City DO") | `cloudflare-game-server`: new `src/city.ts`, `src/city-core.ts`, `test/city-core.test.ts`, `test/city-smoke.ts`; hooks in `src/lobby.ts`; `"roster"` hero kind in `src/lobby-core.ts`; routes in `src/index.ts`; binding + migration `v4` in `wrangler.toml` and `wrangler.dmhub.toml`; `CLAUDE.md` | **DEPLOYED to staging 2026-10-02** (version `a867550f`); `city-smoke.ts` all 34 checks passed against staging; committed dmhub `4a0a9e3af` |
| **Town front end** (2026-10-02; see "The town client") | Engine: `Assets/Scripts/LobbyConnection.cs`, `LobbiesLua.cs` (route option, empty-args fix), `GameController.cs` + `LuaInterface.cs` (`ExportCharacter`/`ImportCharacter`); stubs `Definitions/dmhub.lua`, `Definitions/lobbies.lua`. Codex: NEW `Codex Titlescreen/EotwHeroCard.lua` and `EotwRoster.lua` (registered in the Codex Titlescreen codemod, Firebase confirmed), `EncounterOfTheWeek.lua` (the town screen), `CodexTitlescreen.lua` (`TitlescreenHeroes`, `LobbyHeroes` skip), `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` (card aliases), `EncounterOfTheWeek/EncounterOfTheWeek.lua` (city id). Server: `city.ts`/`city-core.ts` `asJson` + tests | C# BUILT (dev build); server DEPLOYED to staging (`22189dfe`); Lua typing clean; single-client verified live (see that section); NOT deployed to the cloud codemods (new core files need an app restart wherever they land) |
| **Encounter stories + Victories** (2026-10-02; see "Encounter stories and the Victory award") | Server: `city-core.ts` / `city.ts` (`city_completions`, `record-outcome {completed}`, `completed` on `list-heroes` and party heroes), `lobby-core.ts` (`completed` survives sanitizing), `test/city-core.test.ts` (307/307). Core: `Draw Steel UI/DSVictoryScreen.lua` (`AwardVictories` + exemptions). Codex: `EncounterScript.lua` (story sections) + `tests/encounter_script_test.lua` (474), `EncounterOfTheWeek.lua` (game side), `EncounterMontageStage.lua` (`ShowStoryScreen`), `Codex Titlescreen/EncounterOfTheWeek.lua`, `Codex Titlescreen/EotwRoster.lua`. Publisher: `tools/eotw_publish/documents.py` (`story_section`), `publish_eotw.py`. Content: `C:\dev\eotw\objectTables\documents\encounter.yaml` (Goblin Ambush: Town Gate, Conclusion, Defeat) | Unit tests + luac + typing pass; **module v29 PUBLISHED 2026-10-03** (dataid `d240b941`, carries the Town Gate text); Form a Party backstory verified live; server NOT deployed (the user deploys: `npm run deploy` in `cloudflare-game-server`); the rest unverified |
| **EotW hero builder** (2026-10-03; see "The hero builder and hero sheet") | NEW `Codex Titlescreen/EotwBuild.lua` (step engine) and `EotwBuilder.lua` (screen), both registered in the Codex Titlescreen codemod (Firebase confirmed); `EotwRoster.lua` (drafts, Create/Continue/Discard, Rebuild); `CodexTitlescreen.lua` (`LobbyHeroes` skips `eotwDraft`) | Typing clean; engine MCP-verified; screen user-tested once, round-1 fixes not re-tested; needs an app restart to load |
| **New Player Window in the Codex menu** (2026-10-03; see "Debug New Player Window"): the game view's "Player Window" button and its `--eotw-game` auto-join removed | `Codex Titlescreen/EncounterOfTheWeek.lua` (`autoOpen`/`WantsAutoOpen`, `IsScreenOpen`, `CodexMenuItems`), `CodexTitleBar.lua` (main-menu Codex menu appends them), `CodexTitlescreen.lua` (comment) | luac + typing clean; no engine change (uses the existing `connect`/`args` options); needs an app restart; UNTESTED |
| **Active heroes join by default + other players' portraits in the party view** (2026-10-03; see "The town client", Gate) | Engine: `GameController.ReadDetachedCharacter`, `LuaInterface.cs` `dmhub.CreateDetachedCharacter`; stub `Definitions/dmhub.lua`. Codex: `Codex Titlescreen/EncounterOfTheWeek.lua` (`ClaimActiveHeroes`, `RosterHeroSpec`, `ResolveHeroToken` + `m_remoteHeroTokens`, `artRegistered`; `RefreshGames` is now forward-declared) | C# NEEDS BUILD; luac + typing clean; needs an app restart; UNTESTED |
| **Location scenes + creator credits** (2026-10-03; see "The town client" -> "Locations take over the screen" and "Creator credits") | NEW `DMHub Core UI/CreatorCredit.lua` (registered, Firebase confirmed); `Codex Titlescreen/EncounterOfTheWeek.lua` (scenes, Gate card, Escape fix); `Codex Titlescreen/EotwRoster.lua` (`GuildPanel` replaces `ShowGuild`; ModalFrame escape priority). Art + logo uploaded as core image assets | luac + typing clean; verified live on one client: both scenes, the logo's tooltip, Back, Escape, the recruit picker and Form a Party dialog over the scenes. Party view at 1240 wide and the video path not seen. NOT deployed to the cloud codemods; the new core file needs an app restart wherever it lands |
| **Community encounter modules + the encounter pool** (2026-10-03; see "Community encounter modules and the encounter pool") | `DMHub Core Panels/ModShare.lua` (`eotw` module type, `CheckEncounterModule`, `available`/`publishingProperties`/`include` hooks); `Codex Titlescreen/EncounterOfTheWeek.lua` (the pool, encounter keys, grouped Form a Party dropdown + credit line, admin "Encounter Pool..." dialog); `Codex Titlescreen/EotwRoster.lua` (epitaph name); `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`ParseEncounterKey`, `EnsureEncounterModule`, `encounterMapId`/`encounterModule` stamps); `EncounterOfTheWeek/EncounterMontage.lua` (`ScriptForMap`) | luac + typing clean; no engine or server change; needs an app restart; UNTESTED |
| **No targeting without line of effect** (2026-10-03; see "Strict rules and forced settings"): a hero could pick a strike target the arrow marked "No Line of Effect" | `DrawSteelActionBar/DrawSteelActionBar.lua` (`DrawSteelActionBar.LineOfEffectFailReason`; the check in `CalculateSpellTargetFocusing`; the arrow labels use the same helper). The file also holds older unrelated uncommitted changes | luac clean; the live map's line-of-effect results probed over MCP; needs an app restart; the click block itself is UNTESTED |
| **Arrange your heroes** (2026-10-04; see "Start-zone confinement": "Arranging the heroes") | Core `Draw Steel UI/DSInitiativeRoll.lua` (`holdBeforeQueue`, `CreateCombatQueue`); `EncounterOfTheWeek.lua` (`HoldForArrangement`, `ArrangeHostTick`, the panel); `EncounterMontage.lua` (reset) | luac + typing clean; VERIFIED 2026-10-04 in the authoring game with /eotwencounter (single client): the banner then the panel, Ready -> queue with the heroes first, confinement to Start + an unlocked Start2. The lost-`begin` fallback and a multi-client Ready are untested |
| **Dwarvish Bandits script features** (2026-10-04; see "Script features added for The Dwarvish Bandits") | Core: `DMHub Game Rules/TestRiders.lua` (movement/wealth requirements, `(Round N)` riders), `Draw Steel UI/DSVictoryScreen.lua` (`RegisterHeroCardNote`), `Codex Titlescreen/EotwRoster.lua` (treasure home). EotW: `EncounterScript.lua` (new clauses, entry dice tables, round scenes, bystander setup line) + `tests/encounter_script_test.lua` (503), `EncounterMontage.lua` (effects, `MontageSceneImage`, round in `HeroFacts`), `EncounterMontageStage.lua` (`SetBackdropScene`: video loop, round scenes), `EncounterZones.lua` (object reveals, `UnlockedStartZones`), `EncounterOfTheWeek.lua` (extra start zones, bystanders out of initiative, arrival item snapshot, `TreasureGained`, treasure on the outcome + victory card) | luac + parser tests (503) + typing clean. VERIFIED 2026-10-04 by an MCP-driven single-client playtest in game `1e3c159e` (via `codex-eotwauthor`): day video backdrop playing, night backdrop in round 2, Zaliac speech/branch, the Zaliac edge chip, a tier-3 double table roll, Start2 + 2 hero tokens, chest reveal, a lost consumable with and without consumables (silent recovery), the max-Stamina curse, the rolled-damage boon (a live power modifier), recovery value +2, the locked mother -> trail -> cave chain (+3 tokens), the Wolf ally, a party-wide damage boon, all three end-of-montage consequences, Civilians out of initiative, freed on contact, walking 4 per hero turn, the scripted victory (2/2) and "Treasure: Bastion Belt" on the victory card. NOT seen: the Wealth / climb-fly edges with a qualifying hero (none of the pregens qualifies; unit-tested), the treasure reaching the town, a multi-client run |
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
- **A player who disconnects wedges the story.** A montage round waits for
  every hero, and a narrative section waits for every voter. Neither has a
  timeout or a "skip" control. The host has `/eotwnarrative force` only.
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
   the other screen, an assist, scenes paging for the acting player only, a
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
5. Decide the disconnected-player rule (montage and narrative share it).
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
     and the Victory award"); still open are burying the dead
     (`record-outcome {died}`), landing in town, and "Away" in the guild;
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

   Progression is Phase 11, after its own design pass. **Note:** the EotW
   screen now IS the town, and its games live in the City's roster instead
   of the old `eotw` lobby, so steps 1-2 above run through the town.

---

# Where the code lives

| Area | Path |
|---|---|
| Titlescreen screen, lobby client UI, create/join/launch, hero picker | `Codex Titlescreen/EncounterOfTheWeek.lua` (core codex, Codex Titlescreen codemod, before `CodexTitlescreen.lua`) |
| Titlescreen link | `Codex Titlescreen/CodexTitlescreen.lua` (`eotwTitlescreenLink`) |
| Town roster sync, Hero's Guild, Graveyard | `Codex Titlescreen/EotwRoster.lua` (global `EotwRoster`) |
| Creator credits (logo badge, art backdrop) for the location scenes | `DMHub Core UI/CreatorCredit.lua` (global `CreatorCredit`, core) |
| Hero card (town strip + montage HUD) | `Codex Titlescreen/EotwHeroCard.lua` (global `EotwHeroCard`) |
| City DO (the town's server) | `cloudflare-game-server/src/city-core.ts` (pure logic), `src/city.ts` (`CityObject`), tests `test/city-core.test.ts`, `test/city-smoke.ts` |
| Character export/import | `dmhub.ExportCharacter` / `dmhub.ImportCharacter` in `Assets/Scripts/LuaInterface.cs` -> `GameController.ExportCharacter` / `ImportCharacter` |
| Game-side mod (codemod `cdc19d98-...`, `EncounterOfTheWeek_1428`, ships in the module) | `EncounterOfTheWeek/`: `EncounterOfTheWeek.lua` (setup, map script, beat machine, combat glue), `EncounterScript.lua` (pure parser), `EncounterZones.lua` (traps/zones), `EncounterScriptValidator.lua` (dev panel), `EncounterMontage.lua` (montage runtime + shared effect application), `EncounterNarrative.lua`, `EncounterOfTheWeekHud.lua` (custom interface), `EncounterPrep.lua` (Tactical Preparation), `EncounterMontageStage.lua` (all stage UI) -- that is the codemod's file order |
| Parser unit tests | `tests/encounter_script_test.lua` (run with `../dependencies/lua/bin/lua.exe` from the codex root) |
| Test riders (core, also used by the journal) | `DMHub Game Rules/TestRiders.lua` |
| Lobby server | `cloudflare-game-server/src/lobby-core.ts` (pure logic), `src/lobby.ts` (`LobbyObject` DO), tests `test/lobby-core.test.ts`, `test/lobby-smoke.ts` |
| Lobby C# client + Lua bridge | `Assets/Scripts/LobbyConnection.cs`, `Assets/Scripts/LobbiesLua.cs` (global `lobbies`), stub `Definitions/lobbies.lua` |
| Publisher (official module) | `tools/eotw_publish/` (`publish_eotw.py`, README) |
| Community Encounter of the Week modules (publish-dialog type + checks) | `DMHub Core Panels/ModShare.lua` (`eotw` in `g_moduleTypes`, `CheckEncounterModule`) |
| Encounter pool, encounter keys, admin pull | `Codex Titlescreen/EncounterOfTheWeek.lua` ("the encounter pool" section, `ShowPoolDialog`) |
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
- **Games list** from `/state/games` (private games only to their host), plus
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
  week). **Join** uses `lobby:JoinGameEotw(gameid)`.
- **One EotW game per account.** `AccountInfo.eotwGame` is a dedicated slot
  like `lobbyGame`: EotW games never enter the campaigns list or count
  against its cap. Lua reads it as `lobby.eotwGameid`. Creating or joining a
  new game destroys the previous one (`DestroyPreviousGame`: lobby
  `leave-game` + `LuaGameInfo:DeleteAndReleaseStorage`). For an owned game
  that marks `/games/{id}/deleted`, clears the slot and POSTs
  `/admin/delete-game/{gameid}`, which closes every socket with
  `1001 "game-deleted"` and deletes the DO's storage. A non-owner just leaves.
  `DOConnection` treats `game-deleted` as terminal.
- **Launch protocol.** Begin sends `launch-game`. The **host** enters on
  `launched`, installs the module and runs setup, then the game-side codemod
  sends `ready-game`. **Members enter on `ready`.** Entering together made
  joiners run the module install themselves and spam Firebase permission
  denials; the engine also now restricts the starting-module install and the
  `contentSummary` write to the owner, and stops retrying 401/403 writes.
- While in the game nobody heartbeats the roster record, so it expires about
  5 minutes after launch.
- **Choosing the encounter.** A map named exactly `Encounter` is the
  default; any map named `Encounter: <title>` is an alternative. The
  create dialog lists the whole **encounter pool**: the official module's
  maps, plus every Public or Unlisted community Encounter of the Week
  module's maps,
  one flyout per module (see "Community encounter modules and the
  encounter pool"). Names come from each module record's `contentSummary`
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

## Locations on the map

Locations are data, not code: one Lua table of `{id, label, x, y, icon,
unlocked(), open()}`, with positions as fractions of the map image so they
survive any re-export size. Adding a location is adding a row. The art
already has natural homes (fractions of the 6160x4480 canvas):

| Location | Where | Notes |
|---|---|---|
| **Town Gate** | the walled city gate, top centre (~0.53, 0.13) | labeled "City Gate" on the source map |
| **Graveyard** | the green churchyard beside the Cathedral (~0.31, 0.85) | |
| **Hero's Guild** | the small walled green island with a lone building in the canal (0.44, 0.42) | chosen when building (2026-10-02); the Safe House block (~0.54, 0.60) was the alternative |
| later | the Drunken Fool tavern (chat?), the Docks, Bora's Wagon Yard, the Cathedral | |

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
- **Graveyard** (0.31, 0.86); `cross-fill`.

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
  `JoinRoster`. **Create**: `TitlescreenHeroes.Create`, then `JoinRoster`
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
  Hero and Recruit a Hero (a grid of the week's pregens, then a name prompt
  prefilled with the pregen's name). `EotwRoster.GuildPanel(host)` returns
  the card's body (it was the `ShowGuild` dialog).
- **Gate**: the old games list, retitled. It groups "Parties Forming" and
  "Encounters Underway"; Form a Party opens the old create dialog,
  renamed. The add-hero picker lists your living roster heroes that are
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
  **Fill in the Rest** (disabled on a complete page), and **Next**. Next
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
  `EotwRoster.CanRebuildHero`: the hero has no completed encounters and is
  not away in a party. Otherwise it opens the old full sheet, until the
  read-only sheet exists. A survived *defeat* is not recorded anywhere, so
  a hero who lost an encounter can still be rebuilt; this is a known gap.
  Rebuilding pushes to the city on close and on finish. A hero rebuilt into
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
Builder appears only for the player's own hero, and only before its first
encounter.

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
4. **Editing after creation:** allowed until the hero's first encounter;
   after that only level-up changes the build.
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
a build.

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
4. Every member stamps `arrived[userid]` once its heroes exist.

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
- `/toggle eotw:forcecustomui`: shows the EotW interface in any game, for
  iterating without a real EotW game.

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
  (`AcquireAbilityRollDialog` begins sharing for `_tmp_aicontrol` casts).
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
   (`ApplyPendingCombatBoons`), stamp `combatStarted`, and check the outcome.

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

**Arranging the heroes (BUILT 2026-10-04, untested).** When the heroes win
the initiative -- the die, or a montage outcome that hands it to them ("you
win initiative", "you surprise the enemy") -- the Draw Steel banner still
announces it, but the initiative queue is not created yet. Core hook:
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
  victory = `live:CheckVictory()`; defeat = `live:CheckDefeat()` or every
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
(unless `eotw:showdirectorui`) or with `eotw:forcecustomui`:

- No side rails, no Panels menu, no Compendium (menus, toolbar and search).
  The title bar's Codex menu stays.
- **Bottom-left corner**: Journal, Chat and Action Log rail-style buttons
  (unread badges, active underline). "/" still opens chat.
- **Right edge**: the **encounter pools strip** (Malice, Hero Tokens, and
  Intelligence when unlocked; read-only; hovering a cell explains the pool and
  shows its history) above the **hero roster**: one portrait card per hero
  (`dmhub.allTokens` + `IsHero()`, not `Party.GetPlayerCharacters()`, which
  drops blank names), with name and controlling player, a state-tinted stamina
  bar with temporary stamina, the heroic resource, one icon per surge,
  condition chips, and a pulsing trigger badge (click to jump to the hero).
  Own heroes sort first with a blue border. Ally mini-cards sit under their
  hero. The column shrinks to fit the screen (uiscale, top-right pivot). It is
  collapsed while a stage beat is up. Clicking a card opens the character
  panel beside it, **read-only for everyone**.
- Unnamed heroes read "Unnamed Hero" everywhere.

Gotchas from building it: `positionInScreenSpace` is in the documents layer's
units (origin bottom-left), not screen pixels, and is the *pivot's* position.
A panel with no `bgimage` is not hit-tested, so give hover targets a
transparent `panels/square.png`. `gui.StatsHistoryTooltip`'s text is a bare
auto-width label, so wrap long text yourself.

---

# Encounter scripts

**Author-facing copy:** the `/eotw` Claude skill (`.claude/skills/eotw/` at the
repo root: `SKILL.md` workflow, `script-reference.md` grammar,
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

## The document, discovery and sub-documents

- **Which document**: every non-hidden markdown document filed under the
  encounter map's journal folder (`FindMapScript`). A document that another
  one includes is a *part*, never a candidate.
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
  the critical), matched with `MarkdownDocument`'s own regexes. `Attr` maps
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

  The whole delve is the approaching hero's one turn, alone (no assists). The
  hero meets random unmet obstacles, a chest comes due every 1-2 obstacles
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

**Intelligence** is one party pool (`data.intelligence` + its own history
log), earned by `+N Intelligence` clauses. At the encounter beat, before
traps and spawn, **Tactical Preparation** (`EncounterPrep.lua`) offers three
bars at 1 Intelligence per notch; any player may spend:

| Bar | Levels (players only ever read the rung they are on) |
|---|---|
| Surprise | surprised / lose initiative / roll / win / enemy surprised -- opens on what the montage decided; bought levels are applied with the montage's own clauses |
| Traps (only if the beat has a setup instruction) | unaware / "There are 4 Snare Traps hidden on the map." / all marked (a banked reveal); opens at 2 if the montage already earned the reveal |
| Enemy Stamina | none / bar / exact (`enemystambardisplay`); **with this feature on, the week starts the party at `none`** |

Proceed appears once the pool is spent (or nothing can be raised), and every
player must press it (one voice each). The final levels show for 4s, then
the encounter beat carries on. State: `data.prep`. Bar texts come from
`EncounterPrep.BarInfo`, not the document.

## Runtime state and authority

Everything lives in the `eotwscript` mod document (next to `eotwstate`):

```
beat                       -- current beat index (host-stamped)
montage   = { beatIndex, round, phase = "arriving"|"rounds"|"consequences"|"done",
              acted, taken, vanquished, removed, removedForPartySize, unlocked = {key=round},
              expired, testmods, turn, consequences, consequenceIndex,
              requests, handled, log, seq }
montageScene = { id, index }   -- the scene page cursor (the one player-written key)
narrative = { beatIndex, sectionIndex, phase, choices, decision, result,
              announce, requests, handled, log, seq }
prep      = { ... }            -- Tactical Preparation
allies    = { [heroCharid] = { charid, ... } }
items     = { [heroCharid] = { {itemid, name, qty}, ... } }   -- the montage haul
initiative, surprised = {party, enemy}, noSurprise, surges = { [heroCharid] = n }
zoneSetup, revealZones, zonesRevealed, unlocked, intelligence, intelligenceLog,
chestSeen, stageDismissAt
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
2. Scene intro (status `scene`).
3. `choosing`: `choose {optionIndex}` (gated by riders) or `pass` (Leave,
   which passes the turn; not offered inside a delve).
4. The option's pre-roll scene.
5. `rolling`: **the owning client rolls**, not the host. The test shows as
   a synthetic test ability in the timeline sidebar with the roll dialog
   embedded: 2d10 + best listed characteristic, Skilled +2 for a listed
   skill, the normal edges/banes, rider and standing-edge chips. The roll is
   shared to every other client's sidebar as a read-only card. Once the dice
   are thrown the roll cannot be cancelled (`noCancelOnceThrown`); a cancel
   before that returns the turn to choosing.
6. `rolled {tier, total, attrid, skillid}`.
7. **Assist window** when the roll is below tier 3 and someone is eligible: a
   hero who has not acted, trained in a listed skill other than the one the
   roller used. They roll the same characteristic with their own Skilled +2
   against a fixed table -- tier 1 bane (-2), tier 2 edge (+2), tier 3 double
   edge (+1 tier, max 3) -- which shifts the test's result. It costs their
   turn; one assist per test. "Take the result", a 30s window timeout and a
   90s claimed-roll timeout keep it from wedging. An empty window is never
   shown. No assists in a delve.
8. Outcome scene, then **resolve** (`ApplyResolution`, elevated): apply the
   tier's clauses, mark acted/taken/vanquished, log it. A resolved turn
   never blocks the next approach.
9. Round end when every hero has acted or nothing is left; then the
   consequences phase (each unvanquished, unremoved, unexpired threat, one at
   a time; anyone presses Continue), then done.

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
re-checks ownership, the haul record and the real inventory). The icon
decrements optimistically.

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

  Teased tiers count, `{hidden}` clauses do not, and a `Delve:` option takes
  every obstacle test and chest row. Most opportunities show the "?" because
  flavour prose counts as unreadable. Presses pass through the icons, so
  click and drag are unaffected.
- **Hero cards** (`CreateHeroCard` with `showStats`, uiscale 1.2):
  characteristics down the right edge, trained skills under the name, the
  controlling player, and the hero taking or assisting the test in gold with
  the characteristic and skill in use highlighted. Acted heroes are dimmed.
  A card is `draggable` only while its hero can act
  (`LocalUserCanAct`). Drag a card onto an entry, or click the card then the
  entry (droppable targets light up). Ally mini-cards stack against the
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

## Dev tools

| Command | What it does |
|---|---|
| `/eotwscript` | dump the parse of the current map's script, warnings, name lookups |
| `/eotwvalidate` (Panels > Development Tools > Encounter Script) | dev-only validator panel: every beat, entry, option and tier with recognized clauses lit and the plain-English effect, problems, text-only clauses, and name/attr/skill lookups -- built on the runtime's own functions, so it cannot drift |
| `/eotwmontage start\|stop\|state\|reset` | dev driver for the first montage beat outside an EotW game; `reset` restarts the whole test (allies and spawned monsters deleted, state cleared, malice zeroed, heroes healed, traps and zones restored, map script re-attached) and refuses during combat |
| `/eotwnarrative start\|stop\|state\|force\|reset` | the same for narratives; `force` resolves on the choices in |
| `/eotwprep start\|stop\|state\|force\|reset\|unlock\|intelligence <n>` | Tactical Preparation |
| `/eotwzones setup\|reveal <zone>\|apply\|state\|reset` | traps and zones alone |
| `/eotwencounter start\|stop\|state` | the encounter beat outside an EotW game (`DevEncounterStart`): setup instructions, the spawn for `numheroes`, pending zone + object reveals, then `StartEncounterCombat` -- the montage's initiative outcome, bystanders and the arrangement pause (it stands in for the host tick's `ArrangeHostTick` until the queue exists; `m_devEncounter` lets the panel show). The Director plays both sides. `stop` abandons a held arrangement |
| `EncounterOfTheWeekGame.EnsureArrivalItems()` | the arrival item snapshot; `/eotwnarrative start` and `/eotwmontage start` take it too, so a playtest's treasure is tracked |
| `EncounterOfTheWeekGame.DebugGetState()` | the `eotwstate` doc |
| Codex menu > New Player Window (titlescreen, town open, admin) | a second window as the secondary account, opened into the town; see "Debug New Player Window" |

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
Bitter Night Chill. The fight: level-1 gold-tier dwarves on the ledge (two
Gunner squads with Axethrowers / Hunters, a Trapper with Catchpoles, a lone
Trapper, two Reel Winches; EV 45 / 39 / 33 for 6 / 5 / 4 heroes, all Hard),
the two Civilians as bystanders, and the inline Hostage Rescue script. The
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

**Authoring module `codex-eotwauthor`** (created 2026-10-04 by the user in
the app): a code-only module carrying just the EncounterOfTheWeek
(`cdc19d98`) and Monster AI (`263594e2`) codemods. Authors install it in their
authoring game instead of `mcdm-encounteroftheweek`, which would drag the
official week's maps and pregens in. It has no compendium content on purpose:
community modules never take a dependency on it, so it can never put a second
(older) copy of the EotW code into a real game, whose code comes from the
official starting module. The Start zone type is the author's own (matched by
name). Its pinned code snapshot must be republished when the EotW code
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

- **A disconnected player** blocks a montage round and a narrative section.
  Options: a host-visible "skip hero/voter" control, or a timeout. One answer
  for both.
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
  (a week cannot author its own rungs).
- **Kick UX**: the engine game's player list is not updated by lobby
  leave/kick, and a kicked client is not disconnected from the game.
- **Unlisted module access for non-owners** (fetching the pregen snapshot,
  creating a game from it) is unverified with a second account.
- ~~Remote hero portraits show a silhouette.~~ Fixed for roster heroes
  2026-10-03 (`dmhub.CreateDetachedCharacter` over `get-hero`; NEEDS BUILD,
  untested).
- Montage stage vs narrative/prep stages lay the hero row out differently
  (the montage row is ~80px lower). Unify?
- Not built: a click-to-select alternative to dragging; an assisting hero on
  the scene stage; voice/sound per line; keyboard paging; scenes in
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
39 assists (never run live), [x] 46 entries come and go with the rounds, [x]
47 sticky surprise, [x] 48 losing recoveries, [~] 49 traps + zone reveals
(headless only), [~] 50 scenes (single client), [~] 51 delves (played once,
tuning untested), [~] 52 sub-documents (montage on the split document
unplayed), [x] party-size scaling, locked / temporary entries, standing
edges, fair roll, test riders, teasers, hidden clauses, script validator,
haul strip + hand-over, stage cursors (engine), [~] outcome icons
(uncommitted).

**Phase 8 -- narrative beats.** [x] 40 parser, [x] 41 runtime, [x] 42 stage,
[x] 43 beat machine, [ ] 44 two-client live test (genuine disagreement), [ ] 45
publisher validation.

**Phase 9 -- optional features.** [x] `Unlock:` features, [x] Intelligence pool,
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
Create through a full builder session and dismiss untested.
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
Victory award"). Open: burying the dead (`died`), landing in town, "Away"
status in the guild.
[~] 62b **encounter stories + once-per-encounter Victory**: `# Town Gate`
(town, via the publisher), `# Conclusion` / `# Defeat` story screens, the
automatic award with "Already Completed" exemptions, `city_completions`.
BUILT 2026-10-02; server undeployed, module unpublished, unverified.
[~] 63 **graveyard**: the server half is the City's `record-outcome {died}` +
paged `list-graveyard`; the Graveyard location (everyone's fallen, own
marked) is built and its empty state verified. Not built: opening a fallen
hero's sheet from the city. Nothing yet calls `record-outcome` (that is
step 62).
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

**Launch readiness (not started).** [ ] lobby on the release worker and games on
release DOs, [ ] non-owner module access verified, [ ] disconnected-player
rule, [ ] content hygiene (default map, orphan assets, pregen parties), [ ]
remove the dev gate.
