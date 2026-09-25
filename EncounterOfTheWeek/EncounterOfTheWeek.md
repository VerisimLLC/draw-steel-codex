# Encounter of the Week

The "Encounter of the Week" is a new game mode for the Codex. It will have a weekly "encounter" on a set map where some players will take on a group of monsters controlled by the monster AI.

It will use a new dev setting, dev:encounteroftheweek to gate it. If this setting is turned on, then the Encounter of the Week game mode is available from a link in the top-right corner of the titlescreen.

When entering the Encounter of the Week game mode, a new section of the titlescreen will be available. It will give an overview of the game mode, and have a lobby where games that a player may join or observe are displayed as well as a way to create a game and a chat interface (visually consistent with in-app chat, but backed by the lobby -- see below).

**The Encounter of the Week lobby is NOT a game.** It is the first instance of a new first-class concept: a **Lobby** -- a Durable Object that users connect to. Users in a Lobby can chat with each other, see who else is present, and see shared lobby state (for EotW: the roster of joinable games). The C# engine gets a new lobby interface for connecting to lobbies; the app can host connections to different lobbies, and this one is the `"eotw"` lobby. Future lobby types (e.g. a general community lobby, per-module lobbies) reuse the same concept.

A user may create a game and set it to public or private. Private games are not listed. Anyone can join a public game though the user who initiated it is the host and may kick people out of it.

An Encounter of the Week can have between three and seven heroes participate. One player may play multiple heroes. When joinining an Encounter of the Week, a player can fill the 'slots' with their heroes. They can pick their lobby/titlescreen heroes or from the pregen heroes. Pregen heroes are found in the mcdm-encounteroftheweek module.

Once a game has the required number of heroes, the host may select to begin and it launches into the encounter.

An enounter of the week is played as a game which has a special mcdm-encounteroftheweek module installed. It should automatically include the monsterai code mod, with monster ai always running. Upon entry into the game, it should automatically choose the encounter map within the module: the module ships one map named "Encounter" (the default) and may ship more named "Encounter: <title>"; the game creator picks which to play from a dropdown when creating the game (see "Choosing the week's encounter"). A special environmental keyword "Start" should mark the hero's "starting zone" and before proceeding the heroes should be able to move around their starting zone and select their position.

The encounter should be run with the monster AI playing the monsters turns automatically.

---

# Architecture Notes

Condensed findings from a codebase survey (2026-08-27). File:line refs are anchors, not gospel -- verify before editing.

## Titlescreen

- The titlescreen is **Lua UI running inside the per-user local lobby game**. `CodexTitlescreen.lua:5381` defines the global `CreateTitlescreen()`, hosted by `Assets/LuaTitlescreen.cs`. On boot, `lobby:EnterLobbyGame()` (`CodexTitlescreen.lua:7756-7781`) makes `GameController.instance` the local lobby game, so `game.*`, `chat.*`, `dmhub.GetAllCharacters()`, and `mod:GetDocumentSnapshot()` all target it.
- Three states via `SetTitlescreenState()`: `starting-screen`, `selection-screen`, `games-screen`. Root panel is published as `_G.CodexTitlescreenRoot` (`:7776-7778`) -- the standard host for full-screen titlescreen panels (shop screen pattern).
- **Top-right of the titlescreen root is empty.** Cleanest placement for the EotW link: a `floating, halign="right", valign="top"` sibling of the `"<<Back"` button (`CodexTitlescreen.lua:6009-6033`), with `classes = {"hideOnStartingScreen"}`.
- **Separate codemods do NOT load at the titlescreen.** Verified at runtime (2026-08-27): the lobby game loads only the core codex codemod -- `DiceStudio`, `ShopAdmin`, `MonsterAI`, and the `EncounterOfTheWeek_1428` mod are all undefined there (`EncounterWrangler`, part of core, is defined). The `main.lua` require order is NOT what governs this; per-game codemod installation is. Consequence: **all titlescreen-facing EotW code lives in the core codex** -- specifically `Codex Titlescreen/EncounterOfTheWeek.lua`, registered in the Codex Titlescreen codemod at position 1 (before `CodexTitlescreen.lua`, which reads the `EncounterOfTheWeek` global). The `EncounterOfTheWeek_1428` mod (`EncounterOfTheWeek/EncounterOfTheWeek.lua`) is now a stub reserved for game-side logic in later phases (it is the codemod that will ship with `mcdm-encounteroftheweek` games, monsterai-style).
- **Lua globals are strict**: reading an undefined global raises ("Attempt to read uninitialized variable"), so even a `SomeGlobal ~= nil` guard crashes. Cross-codemod references must use `rawget(_G, "Name")`. The titlescreen link does this everywhere it touches `EncounterOfTheWeek`.
- The titlescreen is only built **once per app run** -- `CodexTitlescreen.lua`'s main chunk is guarded by `TitlescreenVersion`, so a crash inside `CreateTitlescreen` leaves the app half-initialized (`CodexTitlescreenRoot` nil) until a full restart. Reloads do not rebuild it.
- Titlescreen "heroes" are characters in the local lobby game (`/characters` of the lobby game, cap 8, `MakeHeroPanel` at `:4210`, `CreateHero` at `:869`). They are per-machine (Local backend). Moving a hero into a real game uses `dmhub.CopyTokenToClipboard(token)` then `dmhub.PasteTokenFromClipboard(loc)` in the `lobby:EnterGame` arrival callback (`:1246-1258`) -- reuse this for slot filling.
- **Pregen heroes exist only as display JSON in the companion app**: `companion-app/src/pregens/` holds the 9 official Draw Steel pregens (dwarf-fury, high-elf-tactician, human-censor, human-null, human-talent, orc-conduit, polder-elementalist, polder-shadow, wode-elf-troubadour) as stats/summary JSON -- a roster and stat source, but NOT DMHub character records. Nothing in the Codex can instantiate them; EotW pregens must still be authored as playable content in the mcdm-encounteroftheweek module (closest playable precedent: premade retainers via `game.SpawnTokenFromBestiaryLocally`).

## Pregen heroes from the module (DECIDED + BUILT 2026-08-27; engine NEEDS BUILD)

Pregens are **module characters**: characters ticked into the
mcdm-encounteroftheweek module at publish time land in the module version's
snapshot (`ModuleVersionSnapshotData.characters`, keyed by stable charids).
A survey (2026-08-27) found NO pre-existing Lua path to enumerate a module's
characters without installing it -- `ModuleLua.contentSummary` has names only,
and `module.IsCharacterAvailableInModule` searches installed modules only. So
the engine gained a purpose-built API:

- **`module.DownloadModuleSnapshot{moduleid, success, failure}`**
  (`Assets/Scripts/Module.cs`, coroutine in `Assets/ModuleManager.cs`
  `DownloadModuleSnapshotCo`): downloads `/Module/{id}` then the latest
  **engine-compatible** version's snapshot (GCS `gcsSnapshotId` first, Firebase
  `/ModuleVersions/{dataid}/snapshot` fallback), WITHOUT installing anything or
  touching the current game. Success gets `{moduleid, version, characters}`
  where characters maps module charids to **detached LuaCharacterTokens**
  (`charInfo`-backed, MonsterAssetLua pattern -- name/properties/appearance
  resolve; the token is in no game). The snapshot path is disk-cached forever
  (`DataStore` ttl=-1 rule), so this is one network fetch per module version,
  shared with the install path. LuaLS stub in `Definitions/module.lua`.
- **Eager cache** (`Codex Titlescreen/EncounterOfTheWeek.lua`):
  `EncounterOfTheWeek.CachePregens()` runs 5s after titlescreen load (when the
  dev gate is on) and again on ShowScreen; it builds `m_pregens` (sorted
  `{id, name, className}` list; className read from the token's
  `properties:try_get("classes")` against the classes table) and keeps the raw
  tokens in `m_pregenTokens` for later phases (portraits, launch-time
  instantiation). `EncounterOfTheWeek.GetPregens()` returns nil while
  unavailable (module unpublished, fetch in flight, or an engine build without
  the API -- probed safely, unknown userdata members read as nil);
  `GetPregenToken(id)` returns the snapshot token.
- Launch-time instantiation (Phase 6) should copy `SpawnTokenFromBestiaryLocally`
  (`GameLua.cs:604`): deep-copy the CharacterInfo, clear ownerId, fresh guid --
  NOT `ReinstallCharacter`, which reuses the module charid.
- **Pregen portraits at the titlescreen (CONFIRMED BROKEN + FIXED 2026-08-28;
  engine NEEDS BUILD)**: the old caveat proved real -- snapshot characters'
  portrait ids are cloud-asset GUIDs whose ImageAsset RECORDS live in the
  version's **streamed** payload (`ver.streamed.assets.images` +
  `imageLibraries`), which only `CloudAssetManager.LoadModulesDependencies`
  registers, and only for modules the current game installs. At the
  titlescreen `assets.allAssets` simply lacks the GUIDs (verified live), so
  card bgimages rendered nothing. Fix: `DownloadModuleSnapshotCo` now runs
  `EnsureModuleImageAssetsCo` (`Assets/ModuleManager.cs`) -- fetches the
  version's streamed payload (shared `module-streamed-{dataid}.json` disk
  cache first, then GCS `gcsStreamedId`, then Firebase
  `/ModuleVersions/{dataid}/streamed`) and calls the new
  `CloudAssetManager.RegisterModuleImageAssets(moduleid, streamed)`
  (`Assets/Scripts/CloudAssetManager.cs`): registers a Module-type asset
  store containing ONLY `images` + `imageLibraries` -- no monsters/tables/
  documents, no `RecordNovelModuleContent`, `_moduleidToDependencyInfo`
  untouched (so the dependency sweep ignores it and a real install replaces
  it). The image BYTES need no help -- they are md5-content-addressed and
  download from anywhere; only the records were missing. Entering any game
  wipes module stores (`ClearModules`), so the Lua side re-ensures:
  `EnsurePregenArt` (in `CachePregens`) re-invokes DownloadModuleSnapshot
  (disk-cached, no network) whenever a sampled cached pregen portrait GUID is
  absent from `assets.allAssets`. Stopgap for builds without the engine fix:
  `MakeCardPanel` drops portrait/frame ids that are unresolvable asset GUIDs
  (`IsUnresolvableAssetId`: GUID-shaped AND not in allAssets) so cards show
  the silhouette instead of an empty frame.
- **DEEPER ROOT CAUSE (2026-08-28, after the registration fix tested no-change
  on a fresh build): the art ships in an INHERITED module, not this one.**
  mcdm-encounteroftheweek v4's own streamed payload is 2 objectTables and
  ZERO images -- correctly so: the pregen portraits live in the source
  game's Avatar/AvatarBackground image libraries, which belong to
  **venla-deliantomb**, and v4's version record declares
  `dependencies = [venla-deliantomb v21 (77e58585-...)]` (verified in
  Firebase). venla-deliantomb v21's streamed payload carries all 18 pregen
  art GUIDs. ModShare rightly never offers another module's assets when
  publishing yours, so NO republish is needed -- the titlescreen just was
  not loading dependencies. In-game this works because
  `GameController.LoadModulesFromGameDetails` ->
  `ModuleManager.TraceDependencies` (transitive resolver) ->
  `CloudAssetManager.LoadModulesDependencies` loads the streamed payload of
  EVERY closure member; my first registration fix fetched only the root
  module's own (art-less) payload. It also registered that empty store,
  which made `HasModuleAssetStore` skip all retries for the session -- now
  guarded (empty-images payloads register nothing, logged at info level).
- **Module art preview infrastructure (BUILT 2026-08-28; engine NEEDS
  BUILD)**: `ModuleManager.EnsureModuleArtPreviewCo(module, ver)` -- kicked
  off (fire-and-forget, never blocks/fails the caller) by
  `DownloadModuleSnapshotCo` after its success callback. Resolves the
  module's full transitive dependency closure with the SAME
  `TraceDependencies` resolver the in-game install path uses
  (deprecation-aware; 30s deadline falls back to the root module alone),
  then for each member without a loaded asset store runs
  `RegisterStreamedImageAssetsCo(moduleid, versionid)`: streamed payload
  from the shared disk cache -> GCS (`GetGcsStreamedId` works for deps
  because the trace loads their /Module records) -> Firebase
  `/ModuleVersions/{versionid}/streamed`, then
  `CloudAssetManager.RegisterModuleImageAssets` (images + imageLibraries
  ONLY -- content collections never leak into the current game, no
  novel-content recording, real installs replace the store). A per-module
  60s in-flight stamp prevents concurrent runs without being able to wedge
  the session. All failures log with the `ModuleArtPreview:` prefix.
  Re-ensure after game switches is unchanged: `ClearModules` wipes the
  stores, and the EotW titlescreen's `EnsurePregenArt` re-invokes
  DownloadModuleSnapshot when a sampled portrait stops resolving (all
  payloads disk-cached, so re-registration is local). Extending the preview
  beyond images later = widening the filter in RegisterModuleImageAssets.
  The interim doctored-v4-cache test band-aid was removed once this landed
  (original cache restored); venla-deliantomb v21's payload is already in
  this machine's disk cache, so the new build registers art with no network.

## Stray extra pregens from shop auto-install (DIAGNOSED 2026-08-29; not an EotW bug)

An EotW game can show a hero nobody claimed. Traced live in
`OtherworldlyWailingCorruptedWorg`: an unclaimed **Dwarf Fury** sat in the
**Players** party (so it reads as somebody's hero in the party UI) while the
state doc's `placedHeroes` recorded only the four pregens actually claimed.

It is **not** an EotW placement bug -- `PlaceMyHeroes` never touched it.
`codex-vextestmodule` is **shop-auto-installed into every game David DMs**
(`GameController.cs:5446-5462` walks `/Patrons/{userid}/inventory` and installs
every `ItemType.Module` item unless `accountInfo.autoInstallShopModules[assetid]
== false`), and its v1 snapshot carries **its own copy of the same 9 Draw Steel
pregens** plus the stray `Test` map, 3 Shriekers, `Specter 1` and
`Lv3 Summoner (Graves)`. See the `project_test_map_vextestmodule_autoinstall`
memory for the giftcode provenance.

The sharp edge is **charid overlap, and where it fails**:

| pregen | vextestmodule v1 | mcdm-encounteroftheweek v4 |
|---|---|---|
| Human Null, Polder Elementalist, Orc Conduit, High Elf Tactician, Human Talent, Human Censor, Polder Shadow, Wode Elf Troubadour | same charid | same charid |
| **Dwarf Fury** | `54ff6135-...` | `a0748893-...` |

Eight of the nine share a charid (both modules descend from the same
venla-deliantomb source game), so installing both is idempotent for them. The
**Dwarf Fury alone diverges**, so the game ends up with two character records --
and the vextestmodule one was authored with `partyid` = the Players party guid
(`0339ff3e-...`, the same guid this game's default party uses), so it presents
as a claimable/owned hero rather than sitting quietly with the other pregens in
`Delian Tomb Pregens`.

Consequences to keep in mind:

- **Any module in a player's shop inventory that shares content lineage with
  `mcdm-encounteroftheweek` can inject look-alike pregens into an EotW game.**
  EotW never enumerates the game's characters to build its roster (the
  titlescreen reads the module snapshot directly via
  `module.DownloadModuleSnapshot`), so the roster stays correct -- the stray is
  cosmetic, an extra unplaced character in the party UI.
- Diagnosis recipe: `dmhub.GetAllCharacters()` for the full list (map tokens
  alone miss it), `module.IsCharacterAvailableInModule(charid)` to tell module
  content from EotW-pasted copies, then `module.DownloadModuleSnapshot` per
  entry of `module.GetLoadedModules()` to find which module owns the charid.
  `EncounterOfTheWeekGame.DebugGetState()` shows what EotW actually placed.
- Dev-machine cleanup: turn off auto-install for the test modules
  (`ShopInfo.cs:471` `autoInstall` setter -> `accountInfo.autoInstallShopModules
  [assetid] = false`) rather than deleting the character per game.
- Worth deciding later whether EotW games should suppress shop auto-install
  entirely (`s_autoInstallSkipGameIds` already exists as a mechanism) so a
  player's owned modules cannot leak content into a curated weekly encounter.

### Two of our OWN pregens are authored into the Players party (ROOT-CAUSED + FIXED 2026-09-18; Lua live on disk, repaired in the running game, NOT deployed)

The same symptom with a different, closer-to-home cause: a two-player game
(`FleetArcaneVelvetScaletooth`) listed **six** heroes in the party UI with only
four placed. Live diagnosis:

| in the Players party (`0339ff3e-...`) | source |
|---|---|
| Dwarf Fury, Human Censor (owner = player B), Polder Shadow, Human Talent (owner = player A) | the four EotW-placed copies, `placedHeroes` agrees |
| **High Elf Tactician, Human Null** (owner = `PARTY`, no token on the map) | module characters, `IsCharacterAvailableInModule` = true |

`module.DownloadModuleSnapshot("mcdm-encounteroftheweek")` shows the cause is in
the **published module itself**, not in an installed third-party module and not
in placement: of its 9 pregens, 7 carry `partyId = 7870ffcb-...`
(*Delian Tomb Pregens*), but **High Elf Tactician and Human Null carry
`partyId = 0339ff3e-...`** -- the very guid the EotW game's default party uses
(both descend from the same venla-deliantomb source game, so the guid matches
exactly). Any roster UI that lists the default party therefore shows them as two
unclaimed heroes. Purely cosmetic -- they have no token, no owner and take no
turn -- but it reads as "where did these two come from".

**Chosen fix (user direction 2026-09-18): the runtime sweep** -- the players'
party holds the heroes the players brought, and nothing else. It fixes games
that already exist, needs no republish, and catches third-party strays too.
`SweepPlayersParty()` in `EncounterOfTheWeek/EncounterOfTheWeek.lua`, called
from the host-only tail of `SetupOnArrival` just before `SeedHeroTokens`:

- **What moves**: a character in the default party is a stray only if
  `module.IsCharacterAvailableInModule(charid)` is true AND its `ownerId` is
  nil or `"PARTY"`. A hero EotW placed is a paste with a fresh guid (so the
  first test fails) and a claimed hero carries its owner's userid (so does the
  second) -- both would have to be wrong at once to touch a real hero. The
  module character is **re-partied, never deleted**: `PlaceMyHeroes`
  duplicates it when a player claims that pregen.
- **Where they go**: `PregenPartyID()` elects the party the week's other
  pregens already live in, by a majority vote over module-content characters
  outside the default party (ties break on party id). No hardcoded guid, no
  module download -- in this module it elects *Delian Tomb Pregens*, 7 votes.
  If the game has no such party (a future week that authors ALL its pregens
  into the Players party) the sweep logs and leaves them alone rather than
  inventing somewhere to put them; the root fix for that is option 1 below.
- **When**: host only, after hero placement and after the module has certainly
  installed, on every setup -- it is cheap and idempotent, so no `eotwstate`
  stamp (a module can finish installing after a first pass).
- Verified live in `FleetArcaneVelvetScaletooth` by running the same body
  through the MCP bridge: the vote elected the pregen party, exactly the two
  strays were flagged and moved, and the Players party went from 6 to the 4
  placed heroes. The Lua itself is **untested in a real arrival** and, being
  part of the weekly module rather than core codex, is **not deployed**.

Still worth doing at the root, independently:

1. **Source + republish**: move those two characters into the *Delian Tomb
   Pregens* party in the authoring game and republish
   `mcdm-encounteroftheweek`, so new games never have the strays in the first
   place and the sweep stays a safety net.
2. (Rejected for now) **Give EotW games a fresh default-party guid** so no
   inherited module content can ever land in it. Widest blast radius; every
   EotW code path that says `GetDefaultPartyID()` would have to agree.

Diagnosis recipe (fast, no UI): `dmhub.GetCharacterIdsInParty(partyid)` per
entry of the `parties` table, then `module.IsCharacterAvailableInModule(charid)`
to separate module content from placed copies, then
`module.DownloadModuleSnapshot` for the authored `partyId`. Note
`dmhub.GetAllCharacters()` returns 0 in this build -- use the per-party lists.

## Dev setting

- Pattern: `setting{ id = "dev:encounteroftheweek", default = false, storage = "preference" }` with **no `editor`** so it never shows in settings UI; toggled via `/toggle dev:encounteroftheweek` in chat (`Commands.lua:451`). Template: `EncounterWrangler.lua:44-53`.
- Live UI refresh idiom: `multimonitor = {"dev:encounteroftheweek"}` + `monitor = function(element) element:SetClass("collapsed", not setting:Get()) end` (see `dev:storepreview` at `CodexTitlescreen.lua:6548-6596`).
- Settings are keyed globally by id, so any file can re-declare the same `setting{}` for read access.

## The Lobby: a new first-class concept (DECIDED 2026-08-27)

A lobby is **not a game at all**. It is a new concept -- a **Lobby** -- with its own
Durable Object type, its own connection surface in C#, and its own chat. The EotW
titlescreen section connects to the `"eotw"` lobby; other lobby ids/types can exist later.

What this buys:

- **The local lobby game is never disturbed.** `GameController.instance` stays on the
  local lobby game the whole time, so the titlescreen heroes column, `mod:GetDocumentSnapshot`,
  and everything else keep working live. No swap-and-restore dance.
- **No fake game record.** No `/games/{id}` GameInfo, no players list growing unbounded,
  no pollution of `accountInfo.games` / the CAMPAIGNS list, no interaction with game
  membership enforcement (`ENFORCE_GAME_MEMBERSHIP`) -- a lobby is open to any
  authenticated user by construction.
- **A reusable primitive.** "Connect users, let them chat, share a small state document,
  show who is present" is exactly what future social surfaces need.

Consequences and known facts that carry over:

- The Unity `chat.*` global (`ChatPanel.cs:2379+`) is hard-wired to `GameController.instance`,
  so `ChatPanel.lua` cannot be reused as-is. **EotW chat is a purpose-built view** in the
  EotW screen, talking to the lobby API.
- The wire-format precedent stands: **the companion app ships a GameController-less
  WebSocket client** (`companion-app/src/games/gameSocket.js` + `sharedGameController.js`,
  chat in `companion-app/src/chat/useGameChat.js` / `sendChatMessage.js`) speaking the DO
  protocol with only a Firebase JWT. The lobby protocol should stay close to this
  (auth message, `put`/`patch`/`get`/`subscribe`, acks with `reqId`) so both the C# client
  and, later, the companion app can connect to lobbies cheaply.
- DOs are created lazily on first connect -- no provisioning call is needed for a lobby to
  exist; the first connector materializes it.
- Server building blocks already in the repo: the worker router (`cloudflare-game-server/src/index.ts:670`
  routes `/game/{gameId}` to the `GameObject` DO namespace), the message protocol
  (`src/types.ts`), the Firebase-semantics patch engine (`src/json-patch.ts`), JWT auth,
  and the hibernatable-WebSocket + SQLite persistence patterns documented in
  `cloudflare-game-server/CLAUDE.md`. A `LobbyObject` DO reuses these modules; it is a much
  smaller sibling of `GameObject` (no map stores, no sharding complexity, no game membership).
- **Lua naming collision**: the global `lobby` (from `LuaLobby.cs`) already means "the
  game-lobby/titlescreen API" (`lobby:CreateGame`, `lobby:EnterGame`, ...). The new Lua
  surface for Lobby connections must use a different name (working name: `lobbies`, e.g.
  `lobbies.Connect("eotw")`). Decide the final name in Phase 2/3 design.

### The DO arbitrates; clients never write lobby state (DECIDED 2026-08-27)

Unlike the game DO -- where clients write raw `put`/`patch` and the server mostly
validates shape -- **the Lobby DO acts as a server**. Clients subscribe to the lobby
document read-only; every mutation is a **typed request** the DO validates against the
requester's permissions and then applies itself:

- **Create game**: one hosted game per user at a time, enforced by SUPERSESSION
  (changed 2026-08-28; originally a rejection): a create request from a user who
  already hosts a registered game drops that record -- exactly as if the host had
  left it, private chat purged -- and grants the new reservation in one step
  (`ack.result.superseded` names the dropped gameid). A still-live unconfirmed
  reservation is likewise replaced rather than rejected. Rationale: the screen
  heartbeats every game the user hosts while it is open, so the old record never
  expired and "already hosting game X" locked hosts out of ever re-creating;
  the client's destroy-previous-game flow only ran AFTER a successful
  reservation. The actual DMHub game is still destroyed client-side
  (`DestroyPreviousGame`) once the replacement exists.
- **Join game**: allowed only if the target game is public and has open slots. On grant,
  the DO updates the slot state itself.
- **Chat**: a send request; the server stamps the sender identity and timestamp, enforces
  length/rate caps, appends, and trims. Clients cannot forge or edit messages.
- Presence and everything else under the document are likewise server-written only.

**IMPLEMENTED (2026-08-27)** in `cloudflare-game-server/`: `src/lobby-core.ts`
(pure arbitration logic, unit-tested), `src/lobby.ts` (`LobbyObject` DO), plus
`types.ts` (request envelope), worker routes and wrangler bindings. The final v1
surface as built:

- Route `wss://.../lobby/{lobbyid}` (ids `[a-zA-Z0-9_-]{1,64}`); read-only debug
  snapshot at `GET /api/lobby/{lobbyid}/doc` (unfiltered -- includes game chats).
  New `LOBBY` DO binding, migration v3, in both `wrangler.toml` and
  `wrangler.dmhub.toml` (release + staging).
- Document: `/chat/{msgid}`, `/gamechat/{gameid}/{msgid}` (per-game private chat,
  member-visible only -- see below), `/presence/{userid}` (memory-only, derived
  from live authed sockets), `/state/games/{gameid}` + `/state/reservations/{userid}`.
  Lobby chat and each game chat retain the last **200** messages (server-trimmed).
  Clients read via `subscribe` (store `"lobby"`) and `get`; all direct writes are
  rejected.
- Actions: `chat {text, gameid?}` (with `gameid`: the private chat of that game's
  lobby -- members only; one shared 8-token rate bucket per user across all
  channels); `create-game {name?, public?}` (one hosted game per user -- an
  existing hosted record is superseded/dropped and a live reservation replaced,
  never rejected; grants a reservation); `confirm-game {gameid}`; `join-game {gameid, heroes?}` (public +
  open gate membership, host exempt from the public check; heroes optional --
  membership no longer implies slots); `set-heroes {gameid, heroes}` (replace the
  caller's hero-slot claim; members only); `leave-game {gameid}` (host leaving
  drops the record); `kick-player {gameid, userid}` (host-only; removes that
  player and their hero claim; the kicked player's sockets get a null
  `/gamechat/{gameid}` put); `launch-game {gameid}` (host-only, needs
  `slotsFilled >= 3` = `MIN_HEROES_TO_LAUNCH`; flips `status` to `"launched"`,
  which freezes the roster -- join-game/set-heroes require an open game -- and
  broadcasts the record; members react by entering the actual DMHub game.
  Heartbeats still work on a launched record, and once members leave the
  titlescreen for the game world the record simply expires via the normal
  5-minute TTL, chat included); `heartbeat {gameid}` (any member; not broadcast/persisted --
  lazily persisted with the next state write); `ping` (liveness no-op). Acks
  carry `result` payloads.
- **Hero slots (DECIDED + IMPLEMENTED 2026-08-27)**: each roster player carries
  `heroes: [{kind, id, name, className, ancestry?, level?}]` instead of a numeric
  slot count. `kind` is `"lobby"` (a titlescreen hero; id = charid) or `"pregen"`
  (a hero from the mcdm-encounteroftheweek module; id = module charid).
  Name/className -- and, since the 2026-08-28 hero-card UI, optional
  ancestry (string, 60-char cap) and level (int, clamped 1..20; malformed
  values dropped, not rejected -- they are cosmetic) -- are display-only copies
  so every client can render the roster without the source data. Caps: **4 heroes per player**
  (`MAX_HEROES_PER_PLAYER`), 7 per game (`slotsTotal`; `slotsFilled` = sum of
  heroes, server-computed). `set-heroes` always sends the complete desired list;
  an empty object is accepted as an empty list (Lua cannot distinguish `{}` from
  `[]`). Joining with zero heroes is allowed even when slots are full (observer /
  pick-later flow).
- **Private game chat (DECIDED + IMPLEMENTED 2026-08-27)**: `/gamechat/{gameid}`
  is visible ONLY to the game's members (host or joined player). The subscribe
  snapshot is filtered per client (`fullDocFor`), message broadcasts go only to
  members, and a successful join-game/confirm-game hands that socket the backlog
  via a `put /gamechat/{gameid}`. Leaving sends the leaver a null put; dropping a
  game record (host leave, expiry sweep) purges its chat -- SQLite rows deleted
  by exact name (LIKE would treat `_` in gameids as a wildcard) and a null put
  broadcast to everyone (harmless no-op for non-members). Rows are
  `gamechat::{gameid}::{msgid}`; orphaned rows are reaped in the DO constructor.
- Liveness: lobby clients must send `ping` (or anything) at least every 120s or
  they are swept; the C# client should ping every ~45-60s. Roster expiry sweeps
  run lazily before every request and via a 60s DO alarm while records exist.
- Persistence: synchronous SQLite rows inside the handler turn (one row per chat
  message, one small `state` row); presence and chat token buckets are memory-only
  by design. Verified to survive a full runtime restart.

Decided parameters (2026-08-27):

- **Request envelope**: `{type:"request", action, args, reqId}` from the client; the
  server answers with the existing `ack` envelope (`{type:"ack", reqId, ok, error?}`)
  carrying a result payload on success.
- **Chat rate limit**: token bucket per user -- capacity 8, one token per message, each
  spent token regenerates 15 seconds after it was spent. A send with an empty bucket is
  rejected via `ack ok:false`.
- **Chat message length**: up to 400 characters.
- **Display name**: self-reported by the client (supplied at auth or on chat-send, like
  game sessions' `usersToSessions.displayName`).
- **Roster liveness**: a client in a lobby game sends a heartbeat request for that game
  every 60 seconds; the DO expires a game's roster record after 5 minutes without one.
  The same 5-minute rule retires unconfirmed create reservations. Implementation note:
  no `setInterval` in the DO (it blocks hibernation) -- expire lazily on message handling
  and/or via a DO alarm, mirroring the game DO's alarm-based flush pattern.

Consequences:

- The games roster is **trustworthy** -- only DO code ever writes it, so invariants
  (one game per host, slot counts, public/private) hold by construction, and the old
  "who may write which `/state` paths" question disappears.
- The protocol needs a **request/response op** on top of the existing envelope: reuse the
  `reqId`/`ack` correlation, but the op is a named action with arguments, not a path
  write. Read side reuses `subscribe` (full snapshot, then server-generated patches).
- **Two-layer create/join**: the actual DMHub game is still created/joined by the client
  through the existing engine flows (`lobby:CreateGame` / `lobby:JoinGame`, which touch
  Firebase `/games/{id}` and account data the DO cannot reach). The lobby request
  brackets that: recommended sequence is request -> DO validates + reserves -> client
  runs the engine-side create/join -> client confirms with the gameid -> DO publishes the
  roster record (reservations time out if never confirmed, so an abandoned create does
  not lock the user out). Pin the exact sequence in the Phase 2 design pass.

Design decisions for the Phase 2 backend design pass (recommendations noted, none final):

- **DO shape**: new `LobbyObject` DO class + its own namespace binding + a `/lobby/{lobbyid}`
  worker route (recommended), vs reusing `GameObject` under a reserved id prefix. A new
  class keeps game-specific guards (entity roots, session-field policy, map stores) out of
  the lobby's way and lets the lobby define its own document schema.
- **Lobby document model**: probably a single small store with well-known top-level keys,
  e.g. `/chat/{msgid}`, `/presence/{userid}`, `/state/...` (for EotW: the games roster
  under `/state/games/{gameid}`). Server-written only (see arbitration above); clients
  reuse the `subscribe` full-snapshot-then-patches flow to read it.
- **Request op set**: the envelope is decided (see above); still to pin is the exact v1
  action list and argument/response shapes (create-game, confirm-game, join-game,
  leave/abandon, chat-send, game-heartbeat; later kick/launch updates from the host).
- **Chat retention**: rate limiting (8-token bucket, 15s regen) and length (400 chars)
  are decided; still open is how many messages the document retains (keep last N,
  trimmed server-side on write) -- games never needed this, lobbies do.
- **Presence**: who is "in" the lobby. The DO already knows its connected WebSockets;
  presence can be derived server-side (broadcast on connect/disconnect/auth) rather than
  client-heartbeat-driven like games' `usersToSessions`. Mind hibernation: connected
  sockets survive it, in-memory maps do not (rehydrate from `getWebSockets()` attachments).
- **Auth + identity**: same Firebase JWT auth as games -- and it is REAL, not stubbed
  (verified in code 2026-08-27; the "auth is stubbed" line in
  `cloudflare-game-server/CLAUDE.md` is out of date). `handleAuth` calls
  `verifyFirebaseJwt` (`index.ts:5055`, verifier at `:221-264`): RS256 signature against
  Google's certs plus iss/aud/exp checks, and `client.userId` is taken from the verified
  token's `sub`, never the client-supplied value. Caveats that matter for the lobby:
  on **staging** (`wrangler.toml` sets `ALLOW_UNAUTHENTICATED_DEV = "true"`), a
  connection with NO token is accepted with a self-reported userId (a supplied token is
  still fully verified) -- so during staging dev, lobby identity stamping is spoofable by
  tokenless clients; release has no such path. `ENFORCE_GAME_MEMBERSHIP` is authorization
  (game membership), unset on both envs, and irrelevant to lobbies by design.
  Display names are self-reported (decided).
- **Moderation/abuse**: the decided rate + length caps are the v1 guard; leave room for
  more later (mute list, etc.).
- **Staging first**: lobby worker deploys to staging (`game-server-staging`) until EotW
  nears release. Whether the lobby DO lives in the existing game-server worker (new DO
  class, same deploy) or its own worker is a Phase 2 decision -- same-worker is simpler
  and shares the deploy pipeline (recommended).

C# side (Phase 3 design, sketched now so the backend API fits it):

- A new lobby interface, deliberately small: connect to a lobby by id, observe connection
  state, monitor chat/presence/state paths (read-only), and send typed lobby requests
  (chat-send, create-game, join-game, ...) with success/failure callbacks; disconnect.
  No raw document writes -- the DO arbitrates all mutations. Multiple simultaneous lobby
  connections must be possible in principle (the interface is instance-based, not a
  singleton), even though EotW only uses one.
- Implementation reuses the `DOConnection` plumbing in `DataStoreDurableObjects.cs`
  (auth handshake, reqId/ack tracking, reconnect backoff, subscription re-send) but is
  **not** routed through `DataStore`/`GameController` -- a lobby connection is independent
  of the current game. Whether to extract/share `DOConnection` or write a slim sibling
  client is a Phase 3 design call.
- A Lua bridge (`*Lua.cs` with `[LuaUserData]`, plus LuaLS stubs in `Definitions/`)
  exposing the interface to the titlescreen EotW code.

## Creating and joining EotW games

EotW games themselves are still ordinary DO-backed games (only the lobby is not a game).

- Create: `lobby:CreateGame{ startingModule = "mcdm-encounteroftheweek", backend = "durableobjects" | "durableobjects-staging", accountSlot = "eotw", create = function(gameid) ... end }` (`LuaLobby.cs:809`, real call site `CodexTitlescreen.lua:3976`). Rate-limited 1/3s. Non-dev users default to Local backend, so `backend` must be passed explicitly. `accountSlot = "eotw"` records the game in the dedicated account slot (see the one-game-per-account section below) instead of `accountInfo.games`.
- The starting module **must contain at least one map** or `GameController.cs:4966` declares the game malformed.
- Join: `lobby:JoinGame(gameid)` appends to `/games/{id}/players`, adds to `accountInfo.games` (CAMPAIGNS list + 24-game cap), and pushes the usersToSessions record. EotW uses `lobby:JoinGameEotw(gameid)` instead: identical except the game is recorded in the eotw account slot, never the games list.
- Roles: `GameInfo.owner/dm/players` (`AccountInfo.cs:520-800`); `IsDM(owner)` is true by default. `dmhub.KickPlayer(userid)` (`LuaInterface.cs:8060`) is already owner-only in the existing UI (`HeroesPanel.lua:492-553`) and genuinely revokes DO access (worker reads owner+dm+players from Firebase, `index.ts:313-329`). Known gap: kicked players are not actively disconnected or notified (engine TODO).
- Worker note: `ENFORCE_GAME_MEMBERSHIP` (`index.ts:5091`) is currently unset, so any authenticated user can open a socket to any gameid today. If it is ever enabled, EotW *games* rely on the normal membership path (join adds you to `/games/{id}/players`), so no allowlist is needed -- but verify observers (if spectators skip `JoinGame`) before enabling it.
- **Keep the host as owner+DM internally** (Monster AI panel is `dmonly`; many systems key off `dmhub.isDM`) and hide Director-facing UI in EotW games, rather than revoking DM status via `ownerRevokedDMStatus`.
- **Loading screen on entry (BUILT + verified 2026-08-28)**: entering an EotW game
  shows the titlescreen's STANDARD game loading screen (cover art + rotating quote +
  progress die, same fade-in/out as any other game). The mechanism: the engine fires
  `beginLoading`/`endLoading` on the titlescreen sheet around every game switch, but
  the Lua handler (`CodexTitlescreen.lua`, `beginLoading` at ~:5530) only builds the
  screen when art was supplied via the `overrideLoadingScreenArt` event -- EotW games
  had no cover art, so entry cut straight to the map. Fix in
  `Codex Titlescreen/EncounterOfTheWeek.lua`: `EnterWorld` fires
  `CodexTitlescreenRoot:FireEventTree("overrideLoadingScreenArt", LOADING_SCREEN_ART,
  gameid)` right before `lobby:EnterGame`. Every entry path funnels through
  `EnterWorld` (host on Begin/"launched", members on "ready", the resume row), so ALL
  players get the same loading screen, each cleared when their own client finishes
  loading (the engine's `endLoading`, which waits on maps/images). The art is the
  `LOADING_SCREEN_ART` constant next to `STARTING_MODULE`
  (`panels/backgrounds/delian-tomb-bg.png`, the Delian Tomb adventure's art -- update
  it alongside the weekly encounter), and create-game now also records it as the
  game's `coverart` so records look like other games' in any generic UI. Verified in
  the running app by simulating the event sequence over the EotW screen: the loading
  screen mounts ABOVE the screen (child order on the titlescreen root) and fades
  correctly. Known residual (accepted): `endLoading` fires just before the arrival
  callback runs `SetupOnArrival`, so the HOST can see their heroes/the encounter pop
  in moments after the fade; members enter on "ready", after host setup, so their
  world is already fully populated. Holding the screen through setup would need a
  different host surface (the engine deactivates the titlescreen ~1s after
  endLoading) -- revisit only if the host pop-in bothers players.
- **The EotW screen must hide itself for the load (FIXED 2026-08-29; verified
  live)**: the loading screen went up, but the EotW screen kept drawing on top
  of it and stayed there until the load finished -- disappearing only a second
  or two later, when the engine deactivates the whole titlescreen GameObject
  (`LuaTitlescreen.EndLoadingCo`, 1s after `endLoading`). The screen is a
  `floating` sibling of the loading screen on `CodexTitlescreenRoot`, so child
  order does not keep it underneath (the earlier "loading screen mounts ABOVE"
  verification was a simulation and did not hold in the real entry). Fix: the
  screen panel handles `beginLoading` by scheduling its own `hidden` class
  `LOADING_SCREEN_FADE_IN_SECONDS` (0.35s) later, and `returnFromGameComplete`
  by clearing it. **The delay matters**: the loading screen dissolves in over
  0.3s (the `"loadingScreen"` / `"loadingScreen create"` style pair in
  `CodexTitlescreen.lua`), so hiding on the event itself made the player watch
  the EotW screen blink out and the loading art fade in over the bare
  titlescreen. The screen must duck out *underneath* a loading screen that is
  already opaque. A `data.loadingUp` flag (set on `beginLoading`, cleared by
  `returnFromGameComplete` and `ShowScreen`) makes the scheduled hide a no-op
  if the load resolved inside that 0.35s window. It is **hidden, never destroyed** --
  a surviving screen on the root is exactly what `SweepStaleScreen` uses as the
  record that the player was on this screen when they left, and destroying it
  would drop them on the plain titlescreen (no resume row) when they came back.
  `ShowScreen` also clears `hidden` on an already-live screen, so the
  titlescreen link can never become a dead click if a return path skips both
  the sweep and `returnFromGameComplete`. Hidden panels still receive events
  (C# fires these with `FireEventRecursive`; `FireEventTree` also ignores the
  hidden flag -- only `FireEventTreeVisible` skips them), so the screen can
  always bring itself back. The heartbeat `think` does stop while hidden
  (SheetPanel deactivates hidden panels), which costs nothing: the titlescreen
  is deactivated moments later anyway, and nobody heartbeats a roster record
  from inside a game.

## Choosing the week's encounter (DECIDED + BUILT 2026-09-15; staging worker DEPLOYED; map switch VERIFIED live 2026-09-16, spawn blocked by the module's content)

A week's module may offer more than one encounter. The rule is a **naming
convention on the maps in the authoring game**, so nothing has to be
registered anywhere:

- a map named exactly **`Encounter`** is the **default** encounter;
- any map named **`Encounter: <title>`** (colon-space) is an alternative,
  e.g. `Encounter: Fight the Dwarves`.

No two encounter maps may share a name (the game finds the chosen map BY
NAME, since map ids change every week). The bare `Encounter` should always
exist: it is what an older client, a week that shipped only alternatives, or
a resumed game with no recorded choice falls back to. The publisher errors on
a duplicate name and warns when the default is missing.

The choice is made **by the game creator, in the create-game dialog**, and
then rides the game as the map's name:

1. **Listing the encounters (titlescreen)**: `EncounterOfTheWeek.CacheEncounters`
   / `GetEncounters` in `Codex Titlescreen/EncounterOfTheWeek.lua` fetch the
   module RECORD with `module.DownloadModuleInfo` (not the snapshot -- one
   small Firebase read) and take the map names from its `contentSummary`
   (`{type = "map", items = {...}}`, which the headless publisher already
   writes), keeping those that pass `EncounterOfTheWeek.IsEncounterMapName`.
   Sorted default-first, then alphabetically. Kicked off in `buildScreen`
   next to `CachePregens`. No engine change was needed for this.
2. **The dropdown**: `ShowCreateDialog` shows an "Encounter:" `gui.Dropdown`
   row (between the name input and the Public checkbox; dialog grows 340 ->
   400) ONLY when the module lists two or more encounter maps; the default is
   preselected. With one, none, or a list not loaded yet, there is no
   dropdown and no choice is sent -- the game plays the default map. The
   choice goes to the lobby as `create-game { ..., encounter = <map name> }`.
3. **The lobby record**: `LobbyReservation.encounter` and
   `LobbyGameRecord.encounter` (a string; `""` = not chosen) in
   `cloudflare-game-server/src/lobby-core.ts`. `applyCreateGame` trims and
   caps it at `MAX_ENCOUNTER_NAME_LENGTH` (120) and ignores non-strings;
   `applyConfirmGame` copies it onto the record. Opaque to the DO. Unit test
   "carries the chosen encounter map name onto the roster record" (suite 35
   green, tsc clean). Staging worker deployed 2026-09-15 (version
   `0732550b`), so the field is live on `game-server-staging`.
4. **Showing it**: the games list rows and the game lobby view header append
   ` -- Encounter: <title>` (`EncounterSuffix`) when the record carries a
   choice.
5. **Entering the game**: `EnterWorld` passes `encounterMap = record.encounter`
   into `EncounterOfTheWeekGame.SetupOnArrival` (nil on a resume with no
   record). Game-side (`EncounterOfTheWeek/EncounterOfTheWeek.lua`),
   `EnsureOnEncounterMap(requested)` runs on EVERY member's client, inside
   the arrival coroutine, BEFORE hero placement: it resolves the name
   (argument -> the host's stamp `doc.data.encounterMap` in the state doc ->
   `DEFAULT_ENCOUNTER_MAP`), finds the map by `description` over `game.maps`
   (an unknown name falls back to the default; no default = stay put), and
   if it is not the current map calls `map:Travel()` and polls
   `game.currentMapId` (0.1s, up to 60s) then settles 0.5s so the Start zone
   and floors are readable. The host then stamps the resolved name
   (`RecordEncounterMap`) so late joiners and resumes agree even after the
   lobby record expires. The engine's own map choice on entry (lowest-ord
   map, or your own token's map) is no longer relied on -- it just decides
   which map loads first.
6. **Publishing**: `tools/eotw_publish/publish_eotw.py` now seeds EVERY
   encounter map (`find_encounter_maps` / `is_encounter_map_name`, default
   first), each map's reachable documents, each map's floor scan and asset
   references, and runs the per-map warnings (prefixed `[<map name>]`) plus
   the missing-default warning. `--map-name` is still the base name.

The three copies of the naming rule -- the publisher's `is_encounter_map_name`,
the titlescreen's `IsEncounterMapName`, and the game-side resolver's
`DEFAULT_ENCOUNTER_MAP` prefix test -- must stay in step.

Not done / open:
- Dropdown labels are the full map names (`Encounter: Fight the Dwarves`),
  not just the title. Revisit if it reads badly once several ship.
- `LOADING_SCREEN_ART` / the game's `coverart` are still one image for all
  encounters.
- The lobby smoke test (`test/lobby-smoke.ts`) does not exercise the field.
- First live run (2026-09-16, game `BlazingPrinceCrystalChimera` on staging,
  module version shipping `Encounter: Goblin Ambush` + `Encounter: Angry
  Dwarves`): the CHOICE path works end to end -- the create dialog listed
  both maps, the record carried `Encounter: Goblin Ambush`, the host
  travelled there, stamped it in the state doc, placed 5 heroes, attached
  the map script and signalled ready. **The encounter did not spawn**:
  `EotW: encounter spawn failed: This map's journal has no encounter to
  spawn.` Root cause is content, not code: the published module's only
  document is `Room 1` (`645e4522`, the dwarf fight: Dwarf Trapper x2 /
  Warden + Driver x4 / Gunner + Axethrower x4), filed under
  `Encounter: Angry Dwarves` (`8d78cadf`). `Encounter: Goblin Ambush`
  (`9ca4404c`) has NO document filed under it and no info bubble on either
  of its two floors (checked under host elevation too), so
  `FindMapEncounter` has nothing to pick from -- the three encounters
  `GetEncountersOnCurrentMap` does return in that game are all off-map
  (the `Combat Encounter` template, `Useful Macros` in private, a Part 2
  montage doc) and are correctly rejected by the parentFolder filter. The
  published version also has no bare `Encounter` default. Both conditions
  are exactly what the publisher's per-map warnings cover ("[Encounter:
  Goblin Ambush] no document reachable from this map contains an
  encounter" and the missing-default warning), and warnings refuse to
  publish unless `--force` was passed -- so either that run was forced or
  the warning did not fire; check the publish log before authoring the fix.
  Fix (authoring game): write the goblin encounter document with
  `parentFolder = 9ca4404c-...` (or an info bubble on that map AND file it
  under the map), and name one map exactly `Encounter` so there is a
  default; republish without `--force`. Games created against the current
  version cannot be repaired in place: the host client re-runs
  `SpawnEncounterMonsters` only via `SetupOnArrival`, and the document is
  simply absent from the game.
- No game-side change is proposed for this. One option, if it recurs:
  `EnsureOnEncounterMap` could treat "map exists but no encounter under it"
  like "map missing" and fall back to a map that has one -- but that hides
  authoring mistakes the publisher is meant to surface, so it is NOT done.

## Debug "Player Window" from the game lobby view (DECIDED + BUILT 2026-09-15; engine NEEDS BUILD, UNTESTED)

User direction: an admin in a game's lobby view gets a "Player Window" button
that launches a second copy of the app logged in as the secondary account
(same mechanism as the `New Player Window` command), which can add heroes and
play once the game begins -- the multiplayer flow from one machine.

- **Button** (`Codex Titlescreen/EncounterOfTheWeek.lua`, `BuildGameView`
  control row): shown to any member while the game is `open` and
  `dmhub.isAdminAccount`. Click:
  `dmhub.DuplicateWindowInNewProcess{ asplayer = true, connect = false,
  args = "--eotw-game <gameid>" }`.
- **Engine** (`GameController.DuplicateWindowInNewProcess(asplayer, extraArgs,
  connectToGame)` + the `dmhub` binding in `LuaInterface.cs`): two new options.
  `args` is appended verbatim to the child's command line; `connect = false`
  omits `--gameid` AND the borrowed `--local-game-server-port`, so the child
  boots to the titlescreen exactly like a fresh launch, on its own local server
  (its own lobby game -- the secondary account's -- lives there, not on the
  parent's). `--asplayer` still selects the secondary account both for the
  dev-key login and the Steam `secondary` login. Stub updated in
  `Definitions/dmhub.lua`.
- **Child boot**: `EncounterOfTheWeek.autoJoinGameid` is parsed from
  `dmhub.commandLineArguments` at load. `CodexTitlescreen.SetTitlescreenState`
  calls `EncounterOfTheWeek.ShowScreen()` on arriving at `selection-screen`
  when `WantsAutoOpen()` (the user still presses a key on the starting screen;
  the arg bypasses the `dev:encounteroftheweek` gate, which is a per-account
  preference the secondary account may not have set). `RefreshGames` then
  consumes the id on the first connected roster snapshot: already a member ->
  `OpenGameView`; else `JoinGame` (whose success opens the view); not listed ->
  error line. One shot, so a rejected join leaves the child on the list.
- **Known limitation**: the child joins through the normal `join-game`
  arbitration, so a **private** game rejects it ("game is private"). Use a
  public game for this, or add an invite/allowlist path server-side if private
  testing matters.

## Debug "Director Window" from inside an EotW game (DECIDED + BUILT 2026-09-16; engine NEEDS BUILD, UNTESTED)

User direction: a dev+admin account hosting an EotW game gets a working
"New Director Window" -- a second window, same account, same game, that
runs as a FULL Director (Director UI, Director vision, no strict rules) so
the game can be administered and debugged while the first window keeps
playing as the player host.

- **Core command** (`DMHub Core Panels/Commands.lua`, "New Director Window"):
  no longer `dmonly` (which drops the registration outright when
  `dmhub.isDM` is false at load -- true on every player host). It now uses
  a `filtered` function: shown when `dmhub.isDM`, OR when `devmode()` and
  `dmhub.isAdminAccount` and `IsDMOrPlayerHost()`. Everyone else sees exactly
  what they saw before. Registered commands with no `menu` land in the title
  bar's **Codex** menu (`WindowMenuItems("codex")`), which the EotW custom
  interface leaves visible (it only suppresses "Panels"), so that is where
  it appears in an EotW game. On click, if `dmhub.playerHostMode == true`
  the child is launched with `args = "--director"`; otherwise the call is
  unchanged.
- **Engine** (`GameController.cs`): `playerHostModeSuppressed` is seeded
  from a `static readonly` scan of the command line for `--director`, so the
  child is the Director from its first frame with no in-session flip and no
  view-as-player refresh. Harmless outside directorless games. The existing
  `GameHarness.RefreshGame` carry-over is untouched. Documentation on
  `dmhub.playerHostModeSuppressed` (`LuaInterface.cs`, `Definitions/dmhub.lua`)
  mentions the flag.
- **EotW codemod** (`EncounterOfTheWeek/EncounterOfTheWeek.lua`):
  `EncounterOfTheWeekGame.IsDirectorDebugWindow()` (scans
  `dmhub.commandLineArguments` once for `--director`) and
  `EncounterOfTheWeekGame.ShowDirectorUI()` = the `eotw:showdirectorui`
  preference OR the flag. The Director-UI presentation filter, the
  `UpdateDirectorUIHatch` driver and the custom interface's `active`
  (`EncounterOfTheWeekHud.lua`, nil-guarded for an older codemod) all read
  `ShowDirectorUI()`. Without this the 1s driver would have switched the
  engine-seeded suppression straight back off. On an engine that predates
  the flag the driver instead sets `playerHostModeSuppressed` itself, which
  costs one refresh -- still functional.
- **Why a launch flag and not the preference**: `eotw:showdirectorui` is a
  per-account preference; setting it in the child would also flip the
  parent window (same account), which is the window that must stay a
  player host.
- **Not done**: the child is a second session of the host account in the
  same game, exactly like the ordinary New Director Window; the map-script
  election already picks one session, but nothing was added to keep the
  debug window from being elected as the EotW setup/AI host.
- **UNTESTED**: the running app at verification time was loading its core
  mods from `c:\dev\d20-dmhub\d20`, not this checkout, and no EotW game
  was open; the Lua is luac-clean only. Needs an engine build, then: open
  the Codex title-bar menu in an EotW game as the host -> New Director
  Window -> the child should arrive with Director UI, no strict-rule
  clamps, and the parent should remain a player host.

## Hero-card lineup (game lobby view UI; DECIDED + BUILT 2026-08-28)

The game lobby view's hero slots are **portrait cards in a horizontal wrapping
row**, not vertical rows (user direction 2026-08-28). All in
`Codex Titlescreen/EncounterOfTheWeek.lua`:

- **Card**: 176x235 (3:4, `Styles.portraitWidthPercentOfHeight`, the character
  panel's portrait-frame aspect). Frame = the token's `portraitBackground` (or a
  dark plate), 2px border, cornerRadius 8; portrait = `tok.offTokenPortrait`
  inset 2px with `GetPortraitRectForAspect(0.75, portrait)` (imageRect skipped
  for spine tokens). A translucent bottom plate carries name (bold),
  "Level N Ancestry Class" (`FormatHeroDetails`), and "Controlled by <player>".
  Pregens get a small "PREGEN" chip top-left. Shared builder `MakeCardPanel`;
  `MakeHeroCard` adds the lineup behaviors, `PickerCard` reuses it in the picker.
- **Token resolution** (`ResolveHeroToken`): pregen -> snapshot cache token; MY
  lobby hero -> `dmhub.GetCharacterById`. **Another player's lobby hero has no
  local token and no resolvable portrait** (portrait assets are per-game cloud
  assets; they are re-uploaded on paste precisely because they do not resolve
  cross-game), so those cards show a phosphor `user-fill` silhouette plus the
  roster record's display copies. That is why the roster hero record gained
  optional `ancestry`/`level` display fields (server `sanitizeHeroes` extension;
  an old server silently drops them and the card falls back to name+class).
- **Actions on hover** (`heroCardAction` style: opacity 0 unless `parent:hover`):
  my heroes get a trash icon (removes that hero via set-heroes); the host sees a
  kick icon on other players' cards (kick-player -- removes the whole player,
  tooltip says so). Sounds + tooltips follow the titlescreen idiom.
- **"+" card**: last card; opens the Add Hero picker. Hidden entirely once
  `slotsFilled >= slotsTotal` (7) or for non-members/launched games; when only
  the per-player cap (4) blocks, it renders dimmed and click/tooltip explain.
  The old "Add Hero" control-row button is gone.
- **Entrance animation**: `RefreshGames` rebuilds the view on every roster
  broadcast, so `m_knownHeroCards` tracks the hero keys ("userid|kind|id") of
  the previous build (nil right after OpenGameView -> first build is quiet).
  A card not seen before is created with class `born` (style: opacity 0, scale
  0.85, transitionTime 0.35) which is shed a beat later -> fade/zoom in; and,
  because **width is NOT style-animatable** (the engine lerps only
  brightness/hue/sat/contrast/inversion/opacity/uiscale/scale/x/y --
  `CharacterSheetStyle.LerpTo`), a scripted `ScheduleEvent` tween grows
  `selfStyle.width` 16 -> 176 over 0.3s so neighbors visibly slide apart to
  make room.
- **Add Hero picker**: same-size cards in wrapping grids under "Your Heroes" /
  "Pregenerated Heroes" sections (dialog now 1040x740); clicking a card claims
  the hero. Specs now carry ancestry/level (read via
  `creature:RaceOrMonsterType()` / `CharacterLevel()`, pcall-guarded; pregen
  cache entries store them too).
- **Picker portrait warm-up**: the picker's portraits are streamed textures,
  so a grid built cold paints in halves -- some cards drawn, a ~1s hitch while
  the rest decode, then the remainder popping in. Nothing in the engine
  preloads an image on request: a texture streams because a live panel
  references it (`ImageDownloader.SetImageByIdentifier`, see
  `Assets/IMAGE_MANAGEMENT.md`). So **opening the EotW screen mounts a
  warmer** (`CreatePortraitWarmer`, added to `resultPanel` at the end of
  `CreateScreen`): one 1x1 panel per eligible portrait, stacked invisibly in
  the screen's top-left corner, floating so it joins no layout. Image ids
  resolve by id alone -- panel size selects no mip and no thumbnail -- so a
  1x1 panel warms exactly the texture the full-size card will later use.
  - **Eligible** (`EligiblePortraitImageIds`) = what the picker can actually
    offer: this machine's `dmhub.GetAllCharacters()` heroes and
    `m_pregenTokens`, each contributing `offTokenPortrait` and
    `portraitBackground`. Other players' heroes are skipped deliberately
    (their portraits are per-game cloud assets that do not resolve here --
    that is why those cards show a silhouette); spine portraits are skipped
    because they are addressable skeletons, not streamed textures; and ids
    failing `IsUnresolvableAssetId` are skipped *unmarked*, so a later pass
    picks them up once the module's art registers.
  - **Re-scans** every `PORTRAIT_WARM_RESCAN_SECONDS` (2s) up to
    `PORTRAIT_WARM_PASSES` (8) times, because the eligible set grows
    asynchronously -- the pregen snapshot lands after the screen opens, and
    its art has to be re-registered after returning from a game
    (`EnsurePregenArt`). It stops early once `m_pregens` is non-nil and a
    pass adds nothing. The first pass is scheduled a tick out rather than
    fired inline from `create`, since it adds children.
  - **Nothing blocks on it.** A portrait that has not arrived by the time the
    picker opens behaves exactly as it does today; the warm-up only makes
    that case rarer. This is the deliberate contrast with the rejected
    approach below.
- **REJECTED: a "Loading..." cover over the picker** (tried and reverted
  2026-08-29). The first attempt copied the shop's first-open cover
  (`CodexShopScreen.lua`, `TrackCoverImage` + `shopLoadingCover`): cards fired
  pending/ready events as their streamed art loaded, and a cover hid the grid
  until the count balanced, with a 4s backstop. **In practice it stalled for a
  long time** -- the counter did not balance, so it sat until the backstop on
  every open, which is worse than the trickle it replaced. The likely cause is
  a card incrementing pending in its `create` whose portrait's `imageLoaded`
  never fires (an asset record that exists but whose texture never arrives
  passes `IsUnresolvableAssetId` and is then counted but never satisfied), so
  one dead portrait holds the whole grid. Do not re-attempt this without first
  instrumenting which cards report ready and which do not. The core lesson:
  **gating the UI on an image-load count makes the worst case worse**, whereas
  warming ahead of time has no worst case.

## Opening the screen: the loading veil (DECIDED + BUILT 2026-08-30; waits for the art since 2026-08-31)

Pressing the titlescreen's `eotwTitlescreenLink` used to show the screen and
then freeze for one to two seconds. That is the whole open happening inline:
`ShowScreen` built the entire panel tree, opened the lobby connection and
mounted the portrait warmer in one go, and the first frames afterwards paid
for the layout and the texture decodes. The screen was on screen for all of
it, so the stall read as the app hanging on a half-drawn page.

The fix is to make the wait deliberate rather than to try to remove it: a
**loading veil** goes up first, the screen is built behind it, and the two
cross-fade once the build has settled. All of it is in
`Codex Titlescreen/EncounterOfTheWeek.lua`.

- `EncounterOfTheWeek.ShowScreen()` no longer builds anything. It mounts
  `CreateLoadingVeil(root)` on `CodexTitlescreenRoot` and returns. The veil is
  deliberately cheap -- a flat dark panel (`panels/square.png`) and two labels,
  no streamed art of its own -- so it can be up and painted within a frame of
  the click. It carries the screen's title at the screen's own authoring scale
  (the `dialog.width / 1920` math copied from `CreateScreen`) plus the codex's
  usual animated "Loading..." ticker.
- The veil owns the whole opening sequence, because **every step has to be
  scheduled from the end of the previous one**. `ScheduleEvent` is wall-clock,
  so an event scheduled just before a frame-long stall fires on the first frame
  after the stall ends. That is what makes the timings robust: a slow build
  pushes the reveal back instead of uncovering a half-drawn screen.
  1. `create` -> `buildScreen` after `VEIL_BUILD_DELAY_SECONDS` (0.15) -- long
     enough for the veil to paint and finish its `create`-class fade-in.
  2. `buildScreen` calls `CachePregens()` + `CreateScreen`, sets the class
     `eotwOpening` on the result **before** parenting it (so it is never
     parented visible), adds it to the root, and schedules `waitForImages`
     after `VEIL_SETTLE_SECONDS` (0.35) -- a beat for layout, and long
     enough for the portrait warmer to have mounted its first batches.
  3. `waitForImages` polls `PortraitWarmupSettled()` every
     `VEIL_WAIT_POLL_SECONDS` (0.1) until the art has settled or the
     deadline passes, then fires `revealScreen`. See "Waiting for the art"
     below.
  4. `revealScreen` sheds `eotwOpening` and puts `dying` on the veil; both
     ramps run over `VEIL_CROSSFADE_SECONDS` (0.3), then the veil destroys
     itself.
- The screen fades via a new rule in its own `styles` list,
  `{ selectors = { "framedPanel", "eotwOpening" }, opacity = 0, transitionTime
  = VEIL_CROSSFADE_SECONDS }` -- the hero-card `born` pattern: the panel is
  *created* carrying the class (so there is no transition to play on the way
  in) and the rule's `transitionTime` governs the ramp back out when the class
  is shed. Two selectors deliberately, to sit above the `framedPanel` rules in
  DefaultStyles.
- **The screen is invisible during the settle window but not inert.** It has to
  render -- that is what makes its textures stream, which is the entire point
  of building it early -- and a live panel takes raycasts whatever its opacity
  (`interactable` is per-panel `raycastTarget`; `alphaHitTest` is opt-in, so a
  fully transparent image still blocks). So `buildScreen` caps the screen with
  a transparent `eotwOpeningBlocker` panel added LAST, which puts it above
  everything in the screen including the floating close button -- which sits
  roughly under the titlescreen link that opened us. `revealScreen` drops it;
  it also self-destructs after 5s as a safety net.
- The veil captures escape and cancels the open outright (destroying the
  screen if it has been built), so changing your mind does not mean waiting
  for the screen to arrive just to close it. It also blocks clicks on the
  titlescreen beneath while it is up, and `ShowScreen` refuses to stack a
  second veil if one is already in flight.
- `SweepStaleScreen` now also destroys any `eotwLoadingVeil` left on the root
  by a previous codemod generation. A stale veil is worse than a stale screen:
  its scheduled `buildScreen` bails on `mod.unloaded`, so left alone it would
  sit there opaque and inert.

**Portrait warming is amortized to match.** `CreatePortraitWarmer` used to
mount a panel for every eligible portrait in one tick, which made the engine
stream and decode a dozen textures inside a single frame -- most of the hitch
a cold open showed. It now mounts at most `PORTRAIT_WARM_BATCH` (3) per tick,
`PORTRAIT_WARM_BATCH_SECONDS` (0.05) apart, coming straight back for the rest
without spending one of its `PORTRAIT_WARM_PASSES`; a pass that does not fill
its batch has drained the current eligible set and waits out the rescan
interval as before. Its first pass fires `PORTRAIT_WARM_START_SECONDS` (0.05)
after the warmer mounts -- i.e. immediately, **under the veil**. It used to be
pushed out to 0.75s, past the reveal, on the theory that no decode should land
during the cross-fade; that just moved the decodes onto a screen the player
was already looking at, which is what the 2026-08-31 change fixes by having
the veil wait for them instead.

### Waiting for the art (2026-08-31)

The purely time-based veil above tested out as *too short*: it appeared,
disappeared after its ~0.8s floor, and then the screen hitched as the
portraits streamed in behind it (user report, 2026-08-31). Absorbing those
decodes is the whole point of the veil, so it now **waits for the art rather
than for a timer**.

- The **portrait warmer is the tracking point**, not the screen's panels. The
  only streamed art the screen shows is hero-card portraits and portrait
  backgrounds (everything else is `panels/square.png`, phosphor icons and
  `ui-icons`), and those are exactly the ids `CreatePortraitWarmer` already
  mounts a 1x1 panel for. Warming an id makes the texture resident, so a hero
  card built later -- when the lobby roster broadcast arrives, well after the
  reveal -- paints from cache with nothing to stream. Tracking the warmer
  therefore covers the screen without wrapping a single card.
- Each warm panel reports itself: `mounted` is bumped where the panel is
  added, `ready` in its `imageLoaded` (guarded by a per-panel `reported`
  flag, since `imageLoaded` fires both for an instant cache hit and for a
  later download). Both stamp `changed = dmhub.Time()`. The record is the
  module-level `m_warmState`, replaced wholesale by each new warmer.
- `PortraitWarmupSettled()` is true when the warmer is `drained` (a pass
  found nothing new with the pregen cache landed, or the passes ran out --
  either way no more panels are coming) **and** `ready >= mounted`; **or**
  when nothing at all has moved for `VEIL_WAIT_IDLE_SECONDS` (0.5).
- `waitForImages` polls it every `VEIL_WAIT_POLL_SECONDS` (0.1) and gives up
  at `VEIL_WAIT_MAX_SECONDS` (4) past the settle. The `eotwOpeningBlocker`'s
  self-destruct timeout is now derived from those constants rather than the
  old hardcoded 5s, so it can never expire while a legitimate wait is still
  running.

**Why this is not the rejected picker cover**, even though it does now gate on
images. The Add-a-Hero "Loading..." cover (rejected above, 2026-08-29) waited
for a pending count to reach zero and nothing else, so one portrait whose
record exists but whose texture never arrives -- it fires no `imageLoaded`,
ever -- held the whole grid until the backstop on *every* open. Three things
make the veil's wait different:

1. **The idle rule, not the count, is the usual exit.** A dead portrait keeps
   the count from balancing, but it produces no progress either, so 0.5s of
   silence settles the veil. The worst case is "last arrival + 0.5s", not
   "the slowest image".
2. **The deadline is the second floor, not the first.** 4s, and it is only
   reachable by art that keeps trickling in with real progress.
3. **The veil is up regardless.** The rejected cover was extra UI erected
   solely to hide loading; the veil already exists because building the
   screen is slow, so waiting longer on it spends a beat of an
   already-planned loading screen rather than adding a new stall.

The floor is now ~1.3s (0.15 build + 0.35 settle + 0.5 idle + 0.3 cross-fade)
in the common case where the pregen snapshot is already cached --
`CachePregens` runs eagerly 5s after the titlescreen loads, so it normally is.
If it is *not* cached, the eligible set is still growing when the idle rule
fires and the late pregen portraits warm after the reveal. That is accepted
deliberately: the alternative -- refusing to settle while `m_pregens == nil`
-- would make an EotW module that never downloads cost the full 4s deadline on
every single open.

**Status: the veil itself is verified live** (it appears within a frame of the
click and cross-fades; the 2026-08-31 report is about its length, not its
behavior). **The wait is UNTESTED**: on disk and syntax-checked, needs a Lua
reload and a titlescreen. What to check: opening the screen cold shows the
veil for appreciably longer than before and the revealed screen no longer
hitches as portraits pop in; a second open (everything warm) is still quick,
~1.3s, not 4s; escape during the wait still cancels cleanly; and the
Add-a-Hero grid still opens warm.

## One EotW game per account (DECIDED + BUILT 2026-08-27; worker DEPLOYED to staging, engine NEEDS BUILD, UNTESTED live)

EotW games never appear in the CAMPAIGNS list and each account holds at most one at
a time. Entering a new EotW game destroys the previous one -- including releasing
its Durable Object. Implemented across all three components:

**Account model (engine).** `AccountInfo.eotwGame` is a dedicated slot exactly like
`lobbyGame` -- EotW games never enter `accountInfo.games`, so no campaigns card, no
24-game cap. Written by `GamesMonitor.CreateGameCo` when `lobby:CreateGame` gets
`accountSlot = "eotw"`, and by the new `lobby:JoinGameEotw(gameid)` (a slot-aware
sibling of `JoinGame`; plain `JoinGame` now also refuses to add a slot-held game to
the campaigns list, covering the Steam-join edge). Read from Lua as
`lobby.eotwGameid` (nil when unset); `lobby:ClearEotwGame(gameid)` clears the slot
iff it still points at that game. `GamesMonitor` pulls the slot's game at startup
and in its Update sweep (so `lobby:EnterGame` can route storage), and its
deleted/kicked cleanup in `ApplyGameInfo` clears the slot automatically.

**Destruction (all three layers).** `LuaGameInfo:DeleteAndReleaseStorage{complete}`:
for a game the caller owns it (1) marks `/games/{id}/deleted = true` -- the record
is kept, NOT removed, because the server route authorizes against its owner field
and the flag is what stops clients from reconnecting; (2) removes it from the
account list/slot; (3) releases server storage -- DO backends POST
`/admin/delete-game/{gameid}` (new `DeleteGameStorageCoroutine` in
`DataStoreDurableObjects.cs`, bearer-token auth, 3 attempts), Local games use
`LocalGameServerProcess.DeleteGame`, Firebase games have nothing to release. For a
game the caller does NOT own it degrades to `Leave()` (permissions force this:
joiners replace their slot reference, only the host can destroy). The worker route
(`cloudflare-game-server/src/index.ts`) shares `authorizeBulkUpload` (owner/DM JWT
or ADMIN_SECRET); the DO's `handleDeleteGame` closes every socket with
`close(1001, "game-deleted")`, `storage.deleteAll()` (drops ALL SQLite tables,
bookmarks included), cancels the alarm, clears the in-memory mirrors, and aborts
the instance 250ms later (rollback pattern) -- zero storage + no alarms + no
sockets means Cloudflare deletes the DO itself. The C# `DOConnection` treats a
close with reason `"game-deleted"` as terminal (sets `_closing`, no reconnect), so
a connected client of a destroyed game cannot re-materialize an empty DO.
Verified by `test/delete-game-smoke.ts` (ALL PASSED against local `wrangler dev`:
persisted rows exist -> 405 on GET, 401 unauthenticated, 200 delete, socket closed
1001/"game-deleted", zero rows + empty store on the fresh instance); unit suite
247 green, tsc clean.

**Titlescreen flow (`Codex Titlescreen/EncounterOfTheWeek.lua`).** Create and join
both capture the previous slot value BEFORE the engine call overwrites it, then --
once the new game exists -- call `DestroyPreviousGame(prev)`: a lobby `leave-game`
request for the old game (drops any lingering roster record + its chat) plus
`LookupGame` -> `DeleteAndReleaseStorage` (or `ClearEotwGame` if the record is
gone). The create dialog shows a pre-flight warning when a previous game exists.
On screen open, `RefreshResumeState` looks up the slot's game: still-alive ->
a "Your game in progress" resume row at the top of the games list (hidden when the
game also has a live roster record -- the roster row is richer) whose Resume button
goes straight to `EnterWorld`; deleted/missing -> the slot is cleared. Resume has
no lobby record, so `EnterWorld` now passes `numHeroes = nil` and the game codemod's
`SetupOnArrival` keeps the game's existing "Number of Heroes" setting instead of
re-clamping (falling back to the setting value for the spawn call, whose
double-spawn guard makes re-entry a no-op anyway). Every new-API read is
nil-guarded (unknown userdata members read as nil), so an old engine build
degrades to exactly the old behavior (games land in the campaigns list).

Deliberately NOT built: destroying the old game while other players are inside it
still works (spec'd: the host entering a new game destroys the previous one; their
clients get the terminal close and their slots self-clear via the deleted-game
cleanup).

**Standalone Abandon (BUILT + verified live 2026-08-28; user direction).** The
"abandon only on entering a new game" stance was revisited: leaving a game in
progress had no way to either destroy it or get back in. Now:

- The **resume row** ("Your game in progress") has an **Abandon** button next to
  Resume. It calls `DestroyPreviousGame` (lobby `leave-game` best-effort +
  `DeleteAndReleaseStorage`/`ClearEotwGame`) and removes the row.
- The **game lobby view's host Abandon** now also destroys the game outright via
  `DestroyPreviousGame` (previously it only dropped the lobby roster record,
  stranding the engine game in the account slot). A non-host's Leave is unchanged
  (leave-game only).
- Both destructive Abandons use a two-click confirm: the button flips to
  "Really?" and reverts after 4 seconds if not confirmed.
- The game view also gained a **Re-join** button for members of a launched/ready
  game (any member on "ready"; the host also on "launched" -- setup re-runs are
  re-entry safe), since auto-entry no longer fires for pre-existing records (see
  "Returning to the titlescreen" below).

## Returning to the titlescreen after leaving a game (ROOT-CAUSED + FIXED 2026-08-28; verified live)

Leaving an EotW game mid-encounter dumped the player on a **zombie EotW screen**:
frozen roster ("Entering the game..."), and every control failing with "Not
connected to the lobby". Root cause, established against the live app + Player.log:

- Returning to the titlescreen **reloads the titlescreen codemods but PRESERVES
  the titlescreen's panel tree** -- including the EotW screen that was open when
  the game was entered (always the case for a game launched from it). The
  surviving screen belongs to the previous codemod generation: one shared Lua
  state, so its closures still run, but its file-locals (`m_conn`, `m_screen`)
  are frozen from before the switch.
- During the game switch the screen's **lobby connection is closed** (wrapper
  status "closed" and the manager's shared-connection entry gone) and the C# side
  never reconnects a `Close()`d `LobbyConnection` -- "closed" is terminal, with no
  reconnect, no pings, no log lines. Every `Request` on it fails fast with
  "Not connected to the lobby" (`LobbyConnection.cs`).

Fixes (all Lua, in `Codex Titlescreen/EncounterOfTheWeek.lua`):

- **Stale-screen sweep** (file-scope, scheduled 1s after every codemod load):
  if this generation owns no screen (`m_screen == nil`) but an
  `encounterOfTheWeekScreen` panel exists on `CodexTitlescreenRoot`, it is
  destroyed and `ShowScreen()` builds a fresh one -- which connects anew and
  renders current lobby state, including the resume row for the game just left.
  Runs only at the titlescreen (`(not dmhub.inGame) or dmhub.isLobbyGame`),
  retrying up to 5x2s otherwise (mid-game reloads leave the hidden zombie for
  the return reload to sweep). The old screen's destroy-handler Disconnect is
  safe next to the new connection: `CloseConnection` only removes the dict entry
  if it still maps to that exact connection.
- **Connection self-heal** (screen think, 30s): a `m_conn.status == "closed"`
  connection is replaced via a fresh `lobbies.Connect` and the document/status
  monitors are rebound (`AttachMonitors`, extracted from the inline registration).
  Backstop only -- the sweep handles the main path.
- **Transition-gated auto-entry**: `CheckLaunchedGames` snapshots each record's
  status on the first roster scan (`m_initialGameStatus`) and only auto-enters on
  a status CHANGE it observed. A record already launched/ready when the screen
  opened (i.e. a game the player just stepped out of) no longer yanks them
  straight back in -- without this, the rebuilt screen would make leaving
  impossible while the roster record lived. Re-entry for those is the explicit
  Re-join button / resume row. The Begin flow is unaffected (open->launched and
  launched->ready are transitions). The "Entering the game..." label now only
  shows while `m_enteringWorld` is actually set.

While in the game nobody heartbeats the roster record, so it expires <=5 min
after launch; the common post-leave state is therefore the resume row
(record gone, engine game alive in the eotw slot), now with Resume + Abandon.

## Hero transfer into the game (DECIDED + BUILT 2026-08-27)

How claimed heroes physically get from the titlescreen into an EotW game:

- **Each owner places their own heroes** (decided; forced by the architecture --
  lobby heroes exist only in that machine's local lobby game, so no other client
  can transfer them). Pregens are placed by their claiming player too, uniformly.
- **Lobby heroes travel via the engine token clipboard**: copy BEFORE
  `lobby:EnterGame` (the clipboard is C# static state that survives the game
  switch; the lobby token objects do not), paste on arrival. Cross-game paste
  deep-copies the CharacterInfo (fresh guid) and re-uploads referenced portrait
  and anthem assets into the destination game (`GameController.PasteCharacters`).
  Ownership on cross-game paste: a non-DM pasting gets `ownerId = self`; the DM
  (the EotW host) gets `ownerId = nil, partyid = nil`, which renders as a HOSTILE
  NPC -- so the game side re-claims every pasted hero: `partyId =
  GetDefaultPartyID()` THEN `ownerId = loginUserid`, `UploadToken`, with a retry
  loop because pasted characters can take a tick to resolve by id.
  **Order matters (bug found + fixed 2026-08-27)**: the engine's `partyId` setter
  (`CharacterToken.cs:1966`) force-writes `ownerId = "PARTY"` as a side effect, so
  setting partyId after ownerId silently converts every hero to party ownership
  (any party member can control it, no player color/name). The ownerId setter
  preserves the current partyid, so partyId-first is safe.
- **The Lua clipboard API was single-slot** (`CopyTokenToClipboard` clears the
  clipboard each call, `PasteTokenFromClipboard` returns only the first id), while
  the C# underneath handles lists natively. The engine gained
  `dmhub.CopyTokensToClipboard(tokenList)` / `dmhub.PasteTokensFromClipboard(loc)
  -> string[]` (`LuaInterface.cs`, stubs in `Definitions/dmhub.lua`) -- paste
  results align index-for-index with copy order, and placement fans out around the
  anchor via the vacancy-aware `FindBestTokenLoc`. NEEDS ENGINE BUILD; until then
  the titlescreen degrades to carrying the first claimed lobby hero only.
- **Pregens need no transfer at all**: installing the module writes its characters
  into the game's `characters`, so every pregen already exists (unplaced) under
  its module charid. The claiming player duplicates one onto the map with a
  same-game `CopyTokenToClipboard` + `PasteTokenFromClipboard(loc)` round trip
  (after the batch paste -- copying wipes the clipboard), then the same re-claim
  fix-up. The pristine module character stays untouched as a template.
- **Arrival timing**: the `lobby:EnterGame(gameid, fn)` callback fires in
  `FinishLoadingCo` after the game is FULLY loaded (map, floors, markup zones,
  tokens, tables all valid). The callback is created in the titlescreen Lua state
  and survives the codemod unload/reload of the game switch, so it captures ONLY
  plain data and resolves the game-side global late via `rawget(_G,
  "EncounterOfTheWeekGame")`. It does **not** wait for the game's own codemods:
  the EotW codemod's id rides in on the `/games/{gameid}` record, and that update
  can land AFTER the loading screen clears. See the handoff bullet below.
- **Explicit handoff, no auto-detection**: setup runs only off the titlescreen's
  Enter World, never off game entry itself. This is deliberate -- the
  authoring/source game also loads the EotW codemod, and any on-entry auto-spawn
  there would dump monsters into the user's source game. Consequence: entering an
  EotW game from the CAMPAIGNS list (not the EotW screen) runs no setup;
  acceptable for now, revisit with Begin (step 21).
  - **Both sides of the handoff, either order** (2026-09-17, bug 32UW4UQB):
    Enter World parks the args in `_G.EotwPendingArrival` (keyed by gameid)
    *before* `lobby:EnterGame`, and the arrival callback stamps `.ready = true`
    on them -- the engine fires it only once loading is done, so that stamp is
    also the game side's licence to travel maps and paste tokens. The callback
    then calls `EncounterOfTheWeekGame.ConsumePendingArrival()`; the game-side
    codemod calls the same function once at load. Whichever lands second runs
    `SetupOnArrival`, guarded by a module-local `m_arrivalStarted` so it runs
    exactly once. Without this, a member whose `/games` record update lost the
    race by ~300ms found `EncounterOfTheWeekGame` nil, silently skipped setup,
    and sat on the engine's default map choice -- no travel, no heroes, so no
    vision at all: a black screen with nothing but the Start zone outline.
    Mixed versions degrade cleanly: an old module (no `ConsumePendingArrival`)
    still gets the direct `SetupOnArrival` call, and an old core titlescreen
    (parks nothing) leaves the new module's load-time call a no-op.
    NOTE the two halves ship in DIFFERENT mods -- `Codex Titlescreen` is core
    codex, `EncounterOfTheWeek` rides the weekly module publish.
- **Re-entry guard**: the game-side state doc (`mod:GetDocumentSnapshot
  ("eotwstate")`) records `placedHeroes[userid][kind..":"..heroid] = charid`;
  already-recorded heroes are skipped (batch-paste duplicates of them are
  deleted). `EncounterOfTheWeekGame.ResetPlacedHeroes()` is the dev reset.
- **Start zone placement**: zone records in `floor.markupZones` carry their
  rasterized tiles in `.locs` (no aura queries needed); heroes are pasted at the
  zone tile nearest the zone centroid and fan out from there. Strict keep-inside-
  the-zone enforcement is the step-22 positioning-stage rule, not placement.
- **Paste vacancy across calls needs a WAIT, not just an update (stacking bug;
  root-caused for real 2026-08-28)**: `PasteCharacters` avoids collisions WITHIN
  one call via an exclude set, but ACROSS calls its vacancy scan
  (`FindBestTokenLoc` -> `LocOccupiedByToken`) reads
  `GameController.charactersByLoc`, which only holds live token GameObjects.
  The 2026-08-27 fix (call `game.UpdateCharacterTokens()` between pastes) DOES
  NOT WORK: the paste is a GameCommand patch with no `patchImmediate`, so the
  new characters reach the local `gameDetails.characters` mirror only when the
  server ECHOES the patch back -- immediately after the paste call there is
  nothing for UpdateCharacterTokens to materialize (the same async mirror that
  `ClaimPastedHero`'s resolve-retry loop always compensated for). Observed live
  2026-08-28 (solo game, 2 lobby heroes + 1 pregen): the batch paste spread its
  own two correctly, then the pregen paste -- a separate call -- stacked on the
  anchor tile, reading as a "missing" third hero. REAL fix (in
  `PlaceMyHeroes`): `WaitForPastedCharacters(charids)` yields until every
  pasted id resolves via `dmhub.GetCharacterById` (<=5s), THEN runs
  `game.UpdateCharacterTokens()` -- after the batch paste (also before its
  claim/duplicate-delete loop, making the re-entry duplicate-delete reliable:
  deleting an id the mirror does not know yet is a no-op) and after each
  pregen paste. A residual CROSS-client race remains (two clients arriving at
  the same moment both anchor at the same tile and cannot see each other's
  un-synced writes); accepted for now -- arrivals are naturally staggered by
  load time, and combat entry waits for every player anyway.
  **Observed live 2026-09-08 (4-player game, host log):** two heroes stacked on
  the anchor tile (1,-8, floor 2). The host had placed and then WALKED its own
  hero off the anchor tile ~70s before the next arrivals, so the anchor read
  vacant to everyone; two players' paste patches then reached the server
  within the same instant (their `/characters` echoes arrived back-to-back in
  the host's stream, the second token logging `canFit = False`), so neither
  vacancy scan could see the other's write and both took the anchor. The
  fourth arrival, seconds later, saw both and fanned out to (1,-7). The
  vacancy scan (`FindBestTokenLoc` -> `charactersByLoc`) is correct for
  everything it can see; the race is in what it cannot see yet.
  **Post-paste stacking repair (BUILT 2026-09-08, UNTESTED, not yet
  deployed):** `UnstackPlacedHeroes(charids, anchor)` runs at the end of
  `PlaceMyHeroes` over every hero this client pasted. It waits 1s (for the
  other clients' pastes from the same instant to echo back), runs
  `game.UpdateCharacterTokens()`, and for each of its heroes checks
  `game.GetTokensAtLoc(token.loc)`. A pile is repaired deterministically so
  two clients fixing the same pile at once do not collide again: the members'
  charids are sorted, the lowest keeps the tile, and the hero of sorted rank
  `r` moves (`token:ChangeLocation`, which goes through the engine's
  `SummonTokens` and is itself vacancy-aware) to the `r`-th free tile of the
  Start zone in a shared order -- tiles sorted by distance from the anchor,
  ties by x then y (`StartZoneTilesByDistance`, `NthFreeStartTile`). Up to 3
  check/repair rounds run; a round that moves nothing ends it. Maps with no
  Start zone skip the repair (nothing to spread across). Each client repairs
  only its own heroes, so no elevated permissions are needed.
- **Lua Loc gotcha (2026-08-27)**: a Loc's floor is READ as `loc.floor`;
  `loc.floorIndex` is not a property and reads nil (the CONSTRUCTOR arg is named
  `floorIndex`, the getter is `floor`). Passing a floorless Loc to
  `token:Teleport`/`ChangeLocation` lands the token on floor 0 -- derive
  destinations from an existing token's Loc (`ref.loc:dir(dx,dy)`) or pass
  `floorIndex` explicitly when constructing.

## Heroes enter at exactly level 1 (DECIDED + BUILT 2026-08-31; UNTESTED)

The weekly encounter is built and balanced for a **level-1 party**, but heroes
arrive from wherever their owner built them -- a lobby hero can be any level,
and a hero made through the Draw Steel "slow start" onboarding sits *below*
level 1. So every hero is forced to exactly level 1 as it is placed.

Two directions have to be corrected, and the level model makes each its own fix
(`NormalizeHeroLevel` in `EncounterOfTheWeek/EncounterOfTheWeek.lua`, mirroring
the character builder's level dropdown in `Draw Steel Character
Builder/CharacterPanel.lua`):

- **Above level 1.** `character:CharacterLevel()` is `max(sum of class entry
  levels, levelOverride)`, so `levelOverride = 1` **alone cannot lower a level-6
  hero** -- the class entries have to come down too. Both are set: every entry
  in `classes` gets `level = 1`, and `levelOverride` is set to 1 when it is not
  already (left absent if it was absent -- the getter already defaults to 1).
- **Below level 1: the "Encounter 1..4" rungs.** The slow-start track is *not* a
  level; it is `levelOverride = 1` plus `extraLevelInfo.encounter = 1..4` (the
  builder's "First Encounter".."Fourth Encounter" options, and what
  `/slowstartlevel` sets). In `Class:FillLevelsUpTo`, a non-nil `encounter`
  hands out `tutoriallevel-1..encounter` and **skips `level-1` entirely** -- a
  fraction of a level-1 hero. Clearing `extraLevelInfo.encounter` promotes the
  hero to a full level 1 (all four `tutoriallevel-*` entries plus `level-1`),
  which is exactly what the builder's "Level 1" option produces.

Design points:

- **It runs on the game's COPY of the hero, never the original.** The fix-up
  lives in `ClaimPastedHero`, which only ever sees the pasted duplicate that
  lives in the EotW game; the player's hero in their lobby game or campaign is
  untouched, so nobody's character is retroactively de-levelled.
- **A `ModifyProperties` patch, and only when something is wrong.** House rule:
  property mutations outside the character sheet go through
  `token:ModifyProperties{}`, so the clamp is its own patch issued right after
  `ClaimPastedHero`'s `UploadToken` (which covers the token-level ownership
  fields, not properties). Every condition is evaluated BEFORE opening the
  modify block, so an already-level-1 hero produces no upload at all. The patch
  is `undoable = false` -- this is setup, and an undo must not put a hero back
  to a level the encounter is not balanced for.
- **Every hero goes through it**, pregens included. Module pregens should
  already be level 1, so it is a no-op for them -- but a mis-authored pregen
  gets corrected rather than shipping an off-level hero into the encounter.
- **Placement is the choke point**, so this happens once, at arrival. Heroes
  skipped on re-entry (already recorded in `placedHeroes`) were normalized on
  their first placement.
- **Multiclassing is reported, not "fixed".** Draw Steel has no multiclassing,
  so `classes` should hold exactly one entry; with two the level would sum to 2
  and no per-entry clamp could fix it. Deleting a class is destructive, so the
  case is logged (`printf`) and left alone.

Known gap (accepted for now): a player who opens their character sheet and
levels up **during the pre-combat positioning phase** is not re-normalized --
nothing re-checks between placement and combat entry. If that turns out to be
reachable in practice, the place to re-run it is per-client at combat start
(the host cannot rewrite other players' hero properties without elevation).

Open question for the user: **victories**. A hero carried in from a campaign
keeps `victories`, which feeds the `victories` GoblinScript symbol and the
encounter-strength maths. Zeroing them would be the same "start clean" spirit as
the level clamp, but it was not asked for and is not done.

## An unnamed hero vanished from the montage (ROOT-CAUSED + FIXED 2026-09-19, report QKG5YTWG; Lua UNTESTED live)

Report `QKG5YTWG` (reporter haezan, v0.0.835 devbeta, staging game
`RepulsivePhantomHeartLegate`): "My Null didn't load into the montage. It does
load into the game when we join combat but isn't in this montage screen."

The hero was placed correctly. Its row in that game's `characterIndex` (the
player's own log carries the whole index) reads:

    e6ba4f90-340e-4b77-8ae3-091c617c6bcb | name="" | owner=<reporter userid>
                                         | party=<default Players party>
                                         | "Level 1 Dwarf Disciple of the Metakinetic Null"

**Its name is the empty string** -- the player never typed one in the lobby.

`Party.GetPlayerCharacters()` (`DMHub Game Rules/Party.lua`) filters blank names
out TWICE: once in its `playerControlled` scan, and again in the final pass that
materializes the tokens, which is the pass the party-membership path also goes
through. So a nameless hero is invisible to every caller of it -- which was the
montage roster (`EncounterMontage.Heroes`) and the HUD hero strip
(`CollectHeroes`). Combat is unaffected because `GatherCombatSides` walks
`dmhub.allTokens` + `IsHero()` with no name test. Hence the exact symptom: in
the fight, absent from the montage. Corroborated in the log by
`EotW: seeded 5 Hero Tokens for the session` against four rendered hero cards,
and only four heroes ever taking a montage turn.

How a nameless hero gets claimed at all: the EotW picker card does
`name = token.name or "Unnamed Hero"`, and `""` is truthy in Lua, so the
fallback never fires -- the player sees a blank card carrying only
class/ancestry/level, and picks it. `HeroIsUnstarted` does not treat it as a
ghost either, because it has a portrait and a class.

**Fix (2026-09-19, Lua only, luac-clean, UNTESTED live):** both EotW hero
gathers now enumerate the way combat entry does -- `dmhub.allTokens` filtered by
`IsHero()` -- instead of going through `Party.GetPlayerCharacters()`:

- `EncounterMontage.Heroes()` (`EncounterMontage.lua`)
- `CollectHeroes()` (`EncounterOfTheWeekHud.lua`)

Both label a blank name "Unnamed Hero" (`EncounterMontage.HeroDisplayName`, and
a local twin in the HUD because that file only reaches the montage module
defensively), so a claimed hero can no longer render as an empty card. The
HUD's hero-card name label and its trigger tooltip use the same fallback; the
ALLY card deliberately does not, because an ally is a monster that joined a
hero. Everything downstream inherits it: `EncounterNarrative.Voters` builds its
labels from `hero.name`.

Consequence of the switch worth knowing: `dmhub.allTokens` is "tokens deployed
on the CURRENT map", where `Party.GetPlayerCharacters()` also returned off-map
party members. In an EotW game that is not a loss -- `EnsureOnEncounterMap` puts
every client on the one encounter map before any hero placement, and the montage
waits on arrivals -- and it matches what combat already counts.

Not fixed here: `Party.GetPlayerCharacters()` itself still drops blank-named
tokens, so `Equipment.lua`'s party inventory has the same blind spot. Whether
that filter is deliberate (keeping placeholder tokens out of party lists) or
legacy was not established, so it was left alone.

## Hero combat state leaks back into the lobby (ROOT-CAUSED + FIXED 2026-09-16, ticket 3GJJQYJV; Lua UNTESTED live, not deployed)

Ticket `3GJJQYJV` (reporter thc1967, v0.0.831, filed from the lobby): "Heroes
coming out of Encounter of the Week with residual combat effects. Jacy has temp
stamina, Ysoreth is down stamina and recoveries." Its Player.log shows the
whole mechanism. **It is not the copy** -- the copy is a true deep copy under a
fresh guid (`CopyCharacters`/`PasteCharacters`, `GameController.cs:3628/3722`;
log: lobby Ysoreth is `204f5fb7`, her EotW copy is a different id). **It is the
engine's existing campaign-to-lobby hero sync, the local character cache.**

- **Stamp.** `CreateHero` (`CodexTitlescreen.lua:1041`) writes
  `properties.originalid = <lobby charid>` and `properties.creatorid = <userid>`
  on every lobby hero. Both ride inside `properties`, so the JSON deep copy
  carries them into the EotW copy unchanged.
- **Save.** `GameController.Update` (`GameController.cs:8213`): a non-Director
  client, every 6000 frames, calls `CharacterToken.SaveLocally()` on its
  `primaryCharacter` when `ShouldSaveLocally()` (`creatorid == me`) holds. It
  bumps `properties.mtime` and writes the ENTIRE `CharacterInfo` to
  `{persistentDataPath}/char-cache/{originalid}.json` -- keyed by the LOBBY id
  (`CharacterToken.cs:22950`). Log: 5 saves of `char-cache/3756365b.json` during
  game 1 (`ObsidianSiegeSilverBrandbearer`) and 19 saves of
  `char-cache/204f5fb7.json` (Ysoreth) during game 2
  (`RainbowDoomedShackledSoulraker`).
- **Restore.** On the first `UpdateGameDetails` of a lobby game
  (`GameController.cs:6159`, `isLobbyGame && !_lobbyGameUpdatedCharacters`),
  `SerializedCharacterInfo.LoadLocally` (`CharacterInfo.cs:792`) runs for every
  lobby character: if a cache file exists with a newer `mtime`, it PUTs the
  cached record over the lobby hero (`"Update Character Details"`, not
  undoable) and deletes the file. Log: `LOCALCHAR:: Restore character:
  204f5fb7` followed by `PutData /GameDetails/4727ff75.../characters/204f5fb7
  (30799b)` two lines before `LOBBYGAME:: ENTERED!`.

So the lobby hero is replaced wholesale by the EotW copy's final state: stamina,
temporary stamina, recoveries, ongoing effects/conditions, surges, heroic
resource, `dsVictoryRoleHistory`, the EotW `partyid`/`ownerId`, **and the
level-1 clamp from `NormalizeHeroLevel`** -- a level-6 lobby hero comes home
level 1 (the "runs on the game's COPY, never the original" claim in the
level-1 section is therefore only true until the next lobby load). The
`mtime` guard cannot help: the EotW save always stamps a newer server time
than the lobby record. Only the reporter's `primaryCharacter` is affected per
game (one hero per player per session), which is why "some" heroes leak.

The sync is intentional for campaigns (a lobby hero mirrors its campaign copy),
so the fix exempts EotW copies rather than removing the feature.

**FIX (BUILT 2026-09-16, codex only, no engine change):** `DetachFromLobbySync
(token)` in `EncounterOfTheWeek/EncounterOfTheWeek.lua`, called from
`ClaimPastedHero` right after `UploadToken` and before `NormalizeHeroLevel`.
It is a `ModifyProperties` patch (`undoable = false`) that sets
`properties.originalid = nil` and `properties.creatorid = nil` on the pasted
copy, issued only when either stamp is present (a properties key set to nil
diffs as a null patch, i.e. a deletion -- `ScriptSerialize.LuaValuePatch`).
Both are cleared on purpose: `creatorid` is `ShouldSaveLocally`'s gate and
`originalid` is the cache file name, and a copy with the gate but no name
would save to `char-cache/.json`. With `creatorid` gone the periodic save never
fires, so nothing is ever restored over the lobby hero. Module pregens carry
the module author's creatorid and never saved; they now lose it too, harmless.
Runs for every placed hero, once, at placement (the same choke point as the
level clamp). luac-clean.

**UNTESTED live.** Verify: place a lobby hero into an EotW game, check the
copy's properties have no `originalid`/`creatorid` (`DebugGetState` or the
character sheet), play >6000 frames (~2 min), confirm no `LOCALCHAR:: SAVE
TO` line in the log, leave, and confirm the lobby hero is unchanged and no
`LOCALCHAR:: Restore character` line appears.

**Not covered:** heroes already damaged before the fix are not repaired (the
cache file is consumed on restore); those users fix stamina/recoveries/level by
hand in the builder. A future engine guard (skip `SaveLocally` when
`originalid` is empty; skip the periodic save in EotW games) would make this
robust against any other codemod re-stamping the fields -- optional, NEEDS
BUILD, not done.

## Entry is slow because the host still pays for the Director's tooling (ROOT-CAUSED + FIXED 2026-09-20; engine, NEEDS BUILD, UNTESTED)

An EotW host is a Director by *permission* -- `playerHostMode`, so `isDM` is
false and every `dmonly` panel is hidden -- but three load-time code paths were
still keyed on `isDMPossiblyImpersonating` or on plain DM status, which stay
true for a player host. They did a Director's authoring work for a client that
cannot reach any of it, all of it inside the loading screen.

Measured on a real EotW entry (`SacredClockworkThornSpindlegoth`, 11.2s to
Complete and another 5.5s before the screen cleared):

1. **Shop-module auto-install, ~5.3s.** `UpdateGameDetails` auto-installs every
   module the account owns from the shop into any game it DMs. A fresh EotW
   game got `premium-tc_cemeteriescrypt` and `premium-tc_diggersdelvers` --
   map-building asset packs -- and each install cost a module install, a
   dependency re-trace and a full re-merge of every compendium table. Now
   skipped for `directorlessGame`, joining the existing `isLibraryGame` /
   Great Library exclusions, which exist for the same reason (a curated module
   list that should not accumulate whatever the DM happens to own). This does
   *not* affect dependencies: a premium pack the week's encounter actually uses
   still arrives through `TraceDependencies`, which is the correct mechanism.
2. **The object-palette thumbnail atlas, ~2.5s.** `ThumbnailManager.InitGame`
   builds the 62px thumbnails behind `ObjectNodeLua.thumbnailId`, used only by
   Objects, MapImport, CreateMapDialog and the Map Markup palette. The cached
   path alone measured `GameInit:: Read 3 atlases in 2345ms` (11,201
   `Sprite.Create` calls on the main thread); an object with no atlas entry is
   *downloaded at full resolution* just to be scaled down, so the first entry
   after a new module lands is far worse. Now gated on the new
   `GameController.isDMExperience` (`isDMPossiblyImpersonating && !playerHostMode`)
   -- the C# counterpart of `GameHud.DirectorUIVisible()`, and the third flag
   `PERMISSIONS_MODEL_REFERENCE.md` finding 16 asked for by name.
3. **Per-row load logging.** Not Director-specific, but it lands on the same
   loading screen: the object-table merge logged one `NewTable::` line per row
   of every compendium table per merged store (~2500 lines a pass, five or more
   passes a load), and `RefreshMonsterTree` logged one line per monster (709
   per rebuild). The merge trace is now behind `CloudAssetInfo.s_debugMergeLog`
   (off by default -- it is still the diagnostic for the fork/merge bug family);
   the bestiary one is a single summary line.

The `--director` debug window and the `/toggle eotw:showdirectorui` hatch both
clear `playerHostMode`, so a client that has asked for the Director experience
still gets the thumbnails. Auto-install is deliberately gated on the *game*
rather than on the client's experience, so a debug Director window cannot
quietly install modules into a shared EotW game either.

**To verify:** build, enter a fresh EotW game as host, and check the log for
`Module:: trying auto install of` (should be absent), `GameInit:: Initialize
texture thumbnails` (absent), and the `LoadingMilestone:: FinalImages` delta
plus the `[LOADPROF]` timeline. Then confirm the encounter still plays: the
week's maps, monsters and documents all arrive, since they come in as module
dependencies rather than auto-installs.

## Joiner-side module install race + Firebase permission denials (FOUND 2026-08-27, engine fix pending)

Diagnosed from the first live 2-client Begin (game `DeathlessChainedSuperiorOrc`):
the joiner client reported "connectivity trouble / writes not going through". The
game-data transport was actually fine (DO WebSocket authed, session pings acked,
token writes working); what was failing -- permanently, with retries every ~25s --
were **Firebase writes to owner-only fields of `/games/{gameid}`**: `contentSummary`,
`codeModsFromModules`, `codeModsFromModulesVersion`, all rejected with
`Permission denied`. The RTDB rules (`cloud-functions/database.rules.json:463`)
allow only the game owner to write `/games/{game_id}` except the `players`,
`characterIndex`, and own-`playerInfo` carve-outs.

Two engine paths issue those writes from non-owner clients:

1. **The joiner ran the full starting-module install.** Begin pulls every member
   into the game at the same moment the host is still installing, so the joiner's
   `EnsureDownloadedStartingMap` gate (`GameController.cs:4693`) saw
   `starterMap=NOTINSTALLED, mapManifests=0` and started its own
   `ModuleManager.InstallModule` -- concurrent with the host's. Its DO writes
   (maps/characters) are allowed, its Firebase marker writes are denied forever,
   and the install coroutine's `PutObjectWithRetry` never gives up. In normal
   games joiners arrive long after install, so this gate practically never fired
   for a non-owner before; EotW's simultaneous entry makes it routine.
2. **The 60s summary sweep** (`GameController.cs:6400`) writes
   `/games/{id}/contentSummary` from ANY client whose computed summary differs
   from the record -- a non-owner then retries a denied write forever.

Effects observed: endless retry/log spam on the joiner ("writes aren't going
through"), plus racing double-install (the joiner's install is also a plausible
source of the stray despawned duplicates seen on the map).

**FIXED (2026-08-27; engine NEEDS BUILD).** Three engine changes plus a new
launch protocol:

- **Engine (a)**: starting-module install/reconcile is DM-only
  (`GameController.cs`, the `EnsureDownloadedStartingMap` gate). A non-DM
  arriving before the host has installed just waits: the mapid==null path
  returns false every tick until the host's install populates `mapManifests`.
  Verified safe: the malformed-game abort only fires when `startingModule` is
  EMPTY, so a waiting joiner never trips it. Tradeoff: a player joining a
  fresh module game whose DM has NEVER entered it now waits at loading instead
  of self-installing (previously "worked" with permission-denied spam) --
  acceptable, the create flows always enter the game immediately.
- **Engine (b)**: the 60s summary sweep writes `contentSummary` only when
  `gameInfo.IsOwner(LoginController.instance.userid)` (`characterIndex` and
  own-`playerInfo` stay open to all -- the rules carve them out).
- **Engine (c)**: `WriteDataCo` (`DataStore.cs`) treats HTTP 401/403 as
  permanent: `retryOnFailure` writes log one error and give up instead of
  retrying a rules rejection forever.
- **Launch protocol ("ready" signal, DECIDED + BUILT 2026-08-27)**: see the
  launch-flow bullet in "Creating and joining EotW games" / step 21 -- the
  host alone enters on "launched", runs setup in-game, then sends the new
  lobby action `ready-game` ("launched" -> "ready"); members enter only on
  "ready". This removes the simultaneous-entry race at its source; the
  engine gates above are defense in depth for every other module game.

## Module + codemod bundling

- Module dependency -> codemod chain is proven (Crowdex precedent): publish `mcdm-encounteroftheweek` from a game that has the Monster AI codemod loaded and tick it in ModShare's Code Mods section (`ModShare.lua:1525-1603`); install then writes `gameInfo.codeModsFromModules` (`ModuleManager.cs:1420-1461`) and `codeModsIncludingCore` unions it in. Monster AI codemod id: `263594e2-aca1-4ce5-b70e-8d690695d7b4`.
- `ModuleManager.ReconcileStartingModuleCodemods` auto-repairs codemods when the module version advances.
- **How journal documents ship (RESEARCHED 2026-08-27)**: ModShare has no Journal
  section -- journal docs are rows of the `documents` data table and appear under
  **Compendium, in a section titled with the raw table name "documents"** (every
  data table gets a section; entries are ticked individually, never wholesale).
  The map itself ships only info-bubble `docid` REFERENCES (inside
  `MapFloor.infoBubbles` in the snapshot); the doc bodies must be ticked by hand
  and no dependency edge warns the publisher (`ModuleDependencySearcher` never
  walks the documents table). A doc's `parentFolder = mapid` filing travels inside
  the doc record, and installs preserve map/floor ids, so a ticked map-doc lands
  back in the installed map's "Map Documents" root with working bubbles. Installed
  table content is LAYERED (read-through `AssetStore.Module` merge), not copied
  into the game store; snapshot content (maps/floors/characters) is copied.
  Consequence: **the weekly module needs its encounter doc ticked under
  Compendium > documents; the `[[encounter]]` annotation (and its
  banked spawnlocs) rides inside the doc record** (see Encounter spawning above).
  That used to be the whole story ("nothing else"); since the document became a
  script it is not -- see the next subsection.

### Compendium content the script needs (AUDITED 2026-09-19)

What the publisher seeds today (`build_seed`, `tools/eotw_publish/publish_eotw.py`)
is the encounter map, every document reachable from it, the `Start`
environmental keyword, the pregen heroes and the pinned codemods -- plus
whatever `ModuleDependencySearcher` reaches transitively from those guids.
Everything the montage and narrative beats do rides on **core** machinery and
adds no compendium rows of its own:

- The Surprised condition, temporary Stamina, surges, the hero-token global
  resource and the malice resource are all core Draw Steel rules content.
- The Recovery Value boon is a real ongoing-effect asset, but it is
  **manufactured at run time** in the game's own `characterOngoingEffects`
  table (`EnsureRecoveryBoonEffect` / `PrepareBoonAssets`,
  `EncounterMontage.lua`), one row per distinct `+N`, created at the start of
  the beat. Nothing about it has to be authored or ticked, and a week may
  invent any value. (The run-time creation is not a convenience -- it is the
  `GetTableCached` trap; see step 37.)
- The initiative clauses need the **core hook**
  `Encounter.StartCombatWithTokens{immediateResult, surprisedTokens}`
  (`Draw Steel UI/DSInitiativeRoll.lua`) -- core codex, not module content, and
  still uncommitted as of 2026-09-19. A week must not use those clauses until
  that hook is in the retail core.

**The one real hole is name resolution.** `you gain <qty> <item>` and
`a <monster> joins you` resolve against `tbl_Gear` and `assets.monsters` **by
name, at run time**. In the module those names are plain prose inside a journal
document -- not guid references -- so `ModuleDependencySearcher` can never see
them and they can never become a dependency or a ticked row by themselves. An
unresolvable name fails silently at the table: the clause is applied, nothing is
granted, and the publish reported no warning.

- **Today: nothing extra to tick.** The live script names only
  `Healing Potion` (`data/objectTables/tbl-gear/healing-potion.yaml`) and
  `Wode Elf Sentry` (`data/monsters/wode-elf-sentry.yaml`), both owned by the
  core Draw Steel data module that every game has installed.
- **The rule for future weeks**: any item or monster a clause names that is not
  in the core data module must be ticked by hand in ModShare (Compendium >
  `tbl_Gear` / the bestiary section), exactly as the encounter document is.
  Until Phase 7 step 35 lands, `/eotwscript` in the authoring game is the only
  check -- it resolves every name against the game's tables -- and it is a check
  of the AUTHORING game, not of the published module, so a name that resolves
  only because of a module the authoring game happens to have installed will
  still be missing for players.

## Publishing the weekly module headlessly (BUILT 2026-08-30)

The week's module is published by a script, not by hand in ModShare:

```bash
python tools/eotw_publish/publish_eotw.py            # dry run: report only
python tools/eotw_publish/publish_eotw.py --publish  # ship a new version
```

The authoring game runs in local-assets mode, so in practice both of its
directories must be passed (highest precedence first) or the tool reads a
frozen store and ships stale content:

```bash
python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data" --publish
```

**`C:\dev\eotw` is the EotW authoring directory** -- the one place the
week's own content lives (the encounter document, the `Start` keyword, the
Hero Death global rule), and the top entry of both the authoring game's
`localassets:dirs` and the global `localassets:eotwdirs` playtest list. It is
deliberately the SAME directory for both, so a playtest write-back and the
authoring game edit the same files and the publisher cannot pick up a
divergent copy. (A `D:\dev\eotw` existed briefly on 2026-08-30 and split the
content in two -- see the 2026-08-31 status entry; it is retired and nothing
should reference it.)

It needs neither DMHub nor Unity. Full design in
[`tools/eotw_publish/README.md`](../../tools/eotw_publish/README.md); the
points that matter to this feature:

- **The authoring game is a Local game.** `e96656f3-a11c-477b-89f1-978452983324`
  ("Encounter of the Week") has `GameInfo.storage == 3`, so its entire contents
  live in `%USERPROFILE%/AppData/LocalLow/MCDM/Codex/local-games/{gameid}/game.db`.
  The script copies that SQLite file and runs the real
  `local-game-server-windows.exe` against the copy, then reads the assembled
  stores over its REST API -- so the live database is never touched and the
  documents are exactly what the engine would see. (The server only
  materializes a game on a WebSocket connect, so the script opens one first;
  that also hands it the whole `game` store, which *is* `GameDetails`.)
- **The week's contents are derived, not re-ticked.** The maps are found *by
  name* -- every map named `Encounter` (the default) or `Encounter: <title>`
  (an alternative; see "Choosing the week's encounter") -- because the ids
  change every week. (v4 shipped
  `05ac910d`, which now reads "Goblin Guardians". That map belongs to
  `venla-deliantomb` and is named "Goblin Guardians" *in the module*, so its
  game-side rename to "Encounter" either was undone by hand or was reset when a
  module version bump re-copied the snapshot -- which of the two is UNVERIFIED.
  Either way, do not assume a rename sticks: check the name each week.) Everything else follows: the documents the
  map can reach (see below), the `Start` keyword, every hero in the pregen
  party
  (`7870ffcb-c942-4db9-a831-bf0210aa11ea` -- adding a hero to that party is all
  it takes to ship them), the pinned EncounterOfTheWeek + Monster AI codemods,
  the dependency closure of all of it, and any codemod a dependency module
  contributed (this is how DelianTomb ships).
- **Finding the encounter document mirrors the runtime.** The publisher ports
  `FindMapEncounter` (`EncounterOfTheWeek.lua:652`) and
  `Encounter.GetEncountersOnCurrentMap` (`MCDMEncounter.lua:3607`) rather than
  inventing a rule, because it has to ship exactly what the game will later look
  for. Two routes reach a document from a map and the runtime prefers the first:
  an **info bubble** on any floor (`floors[*].infoBubbles[*].document.docid` --
  beware `sourceReference.docid`, a different namespace for PDFs), or the
  **journal**, meaning any non-hidden document whose `parentFolder` chain roots
  at the map id. A document *has an encounter* when its text contains a rich tag
  whose annotation is a `RichEncounter` with a non-nil `encounter`; the text
  reference is what counts, since orphaned annotations linger in records whose
  tag was deleted. Take the text from `textStorage.sections` (keys sorted,
  concatenated) and fall back to `content` only when `textStorage` is absent --
  never union them, as `content` is a stale mirror that can still hold deleted
  tags. Do **not** additionally require monsters: an island with none is the
  normal half-authored state and the engine still treats it as the map's
  encounter. **The `(N monster(s))` in the report counts monster ENTRIES, not
  spawned tokens** (`island_monster_count`, `documents.py:105`, sums each
  group's `monsters` map length and ignores the per-entry count), so a
  3-group/12-token encounter built from 5 distinct monsters reports 5. A drop
  in that number between weeks means fewer monster *kinds*, not a smaller fight.
- **Documents resolve against the MERGED table**, the game's rows plus every
  installed module's -- 104 of the 105 info bubbles in the authoring game
  resolve only through `venla-deliantomb`. A module-owned document is seeded but
  cannot be shipped (`MergeSubset` reads the game store only,
  `ModuleManager.cs:729`); seeding its guid is what makes the dependency pass
  record the owning module, which is how the document actually arrives.
- **A pure "trace the map" rule would have shipped a broken module**: the 9
  pregens are not on the map and nothing references them, and codemods live in
  the Firebase game record, outside the walked JSON. Hence the pinned extras.
- **The port is verified against what the app published.**
  `--verify-against <dataid>` rebuilds a past version and diffs it. Against v4
  (`c1b80b60-...`, with `--map-name "Goblin Guardians"`) every key set matches
  and every shared value is byte-identical after Firebase's null-stripping; the
  only differences are real edits made to the game since. **Re-run this after
  any engine change to the publish pipeline** -- structural drift is the signal
  that `MergeSubset`, `ModuleDependencySearcher` or the snapshot builder moved
  and the port must follow.
- **Two engine quirks are reproduced deliberately** (marked `ENGINE QUIRK` in
  `tools/eotw_publish/depsearch.py`): the dependency walk only descends into
  dictionaries, never arrays (`Glowwave.Json` writes lists as JSON arrays and
  the walker has no array branch); and `Search` clears the set it aliased from
  the selection, making the engine's "modules containing a selected guid" pass
  dead code.
- **One deliberate improvement**: the engine's walk never sees floor contents
  (a migrated map's floors live in the `MapDetails` store, so
  `GameDetails.mapFloors` is empty), so objects placed on the map are never
  discovered as dependencies. The script scans the week's floors too and
  reports what only that scan found -- on the current Encounter map that is the
  `GL_OvergroundDwarvenCityCenter_Original_Day` object, which the app would
  have shipped a dangling reference to. `--no-floor-scan` restores strict
  ModShare parity.
- **The game's own `modulesPublished` record is deliberately not written.**
  ModShare re-downloads `/Module/{id}` when it opens (`DownloadModuleInfo`) and
  the game-side copy's `properties` are empty in practice, so leaving it alone
  costs nothing and avoids writing into a live game database.
- Dry run is the default. The script refuses `--publish` (without `--force`)
  when the report warns that the result would not play -- no encounter document
  under the map, no floors, fewer than three pregens, no `Start` keyword.

### The store speaks Firebase, the payload must speak Glowwave (ROOT-CAUSED + FIXED 2026-08-30)

Module version 5 installed as far as "install map ..." and then NRE'd inside
`ModuleManager.InstallModuleCo`, leaving the game with no starting map and the
loading screen stuck at "No starting map yet". The payload was malformed, and
the reason generalizes to any tool that reads a game store directly:

- **The server stores arrays as numeric-keyed objects.**
  `normalizeForFirebaseCompat` (`cloudflare-game-server/src/json-patch.ts:69`)
  rewrites every array to `{"0":x,"1":y}` on write, matching Firebase. The C#
  client reverses that in `JsonDoc.StripMetaKeys` before any typed deserializer
  runs (`DataStoreDurableObjects.GetFullStoreSnapshot`, `DataStore.cs:2729`),
  which is why the shape is invisible in-game.
- **Module payloads get no such pass.** `InstallModuleCo` hands the blob
  straight to `Glowwave.Json.FromJson<ModuleVersionSnapshotData>`, and a
  `List<T>` fed a Dictionary decodes to **null** after logging "Could not
  convert Dictionary to list" (`GWSerialization.cs:959`). `MapManifest.floors`
  was null, so `q.Value.floors.Contains(...)` in the mapFloors loop NRE'd. An
  empty object (`{}`) decodes to null the same way.
- **Firebase hides it.** RTDB coerces dense numeric-keyed objects back to
  arrays on read and refuses to store empty objects, so `/ModuleVersions/{id}/
  snapshot` reads back clean; only the gzipped GCS blob -- which the installer
  *prefers* -- carries the bad shape. Never conclude a payload is fine from the
  Firebase copy.
- Version 4 was clean because those rows predated the server-side
  normalization; the shape appears as rows are rewritten, so this was latent
  and would have struck any later week regardless.

Fixed in two places, and both matter:

- `gamesource.strip_meta_keys` ports `JsonDoc.StripMetaKeys` and now runs on
  the WebSocket game-store push and every REST store read, so everything
  downstream of `LocalGameSource` is engine-shaped by construction (arrays
  restored, `{}` dropped, `__del`/`__basis` stripped). Faithful to the C# down
  to the details: 1-3 digit keys make an object array-shaped, holes become
  null, and a value that is already a list is returned untouched.
- `publish_eotw.validate_engine_shapes` preflights the outgoing snapshot and
  streamed blobs for both shapes and **aborts the publish** (exit 3) like the
  Firebase preflight, rather than warning. Replayed against the published v5
  payload it reports 105 problems; after normalization, none.

Engine side (NEEDS BUILD): the mapFloors loop in `ModuleManager.cs` now skips a
manifest with a null `floors` and logs which module was malformed, so a bad
payload can no longer wedge a game mid-install.

## Playtesting against local asset directories (DECIDED + BUILT 2026-08-30; engine shipped in the 2026-09-18 build)

Local-assets mode -- the dev feature that replaces a game's cloud `/assets`
with an ordered overlay of YAML directory trees, hot-reloads external edits
and writes in-game edits back to the files -- could never be pointed at an
Encounter of the Week game, because it is configured through the *per-game*
`localassets:dirs` preference and an EotW game is created fresh for each
encounter: there is no gameid to configure until the game already exists.
Playtesting therefore always ran against the last PUBLISHED module version,
so every content fix cost a republish.

The gap is closed by a second, GLOBAL list that follows the account's EotW
slot rather than a gameid:

- **Setting**: `localassets:eotwdirs` (`storage = "preference"`, declared in
  `DMHub Titlescreen/Settings.lua`, no generic editor) -- newline-delimited
  paths, top-most first, exactly the `localassets:dirs` format.
- **Engine** (`Assets/Scripts/LocalAssetDirectory.cs`): `ReadConfiguredDirs`
  appends `ReadEotwDirs(gameid)` AFTER the per-game list, so the EotW entries
  are the LOWEST precedence and a per-game list (if one is ever set for that
  game) still wins. `IsEotwGame` compares the gameid against
  `LoginController.instance.accountInfo.eotwGame` -- the same slot the codex
  reads as `lobby.eotwGameid` in `EncounterOfTheWeekGame.IsEotwGame`, written
  by the titlescreen's create/join flows *before* the game is entered, so it
  is already set when `GameController.Start` calls `MaybeActivate`. (The
  codex's second signal -- the host's stamp on the shared state doc -- is not
  readable that early and is not needed: these directories only ever matter
  on the developer's own client, and their own slot is what points at the
  game.) `ReadSettingString` grew a null-gameid mode for reading a global
  setting: the pref-store fallback key is the bare setting id rather than
  `{gameid}.{id}`, matching how `SettingsManager` writes it. That fallback is
  what makes this work at all on a cold start, since settings are declared in
  Lua and Lua has not necessarily loaded when the first game activates.
  Nothing else changes: same overlay, same watcher, same write-back, and the
  activation log names the EotW list when it contributed.
- **UI**: a second block in Settings > Editing under the existing Local
  Assets section -- "Encounter of the Week Assets (Developer)"
  (`CreateEotwLocalAssetsSection` in `DMHub Titlescreen/SettingsScreen.lua`),
  gated on `dev` + `dev:encounteroftheweek`. Unlike the per-game block it is
  NOT hidden in the lobby game, because the titlescreen is where you set it
  up -- before launching into the encounter. The row widgets (index, path,
  Browse, Top/Up/Down/X, Add Directory) are now shared by both lists through
  `CreateDirectoryListPanels`, and `SmallButton` moved to file scope since
  the file browser and cloud-diff blocks also use it. Sharing the rows
  surfaced a latent bug in them: the list was built by appending rows onto an
  args table of named keys (`args[#args+1] = row`), which puts the numeric
  keys in Lua's hash part where enumeration order is undefined -- 5.4 hands
  back exactly two numeric keys REVERSED, so a two-directory list rendered
  upside down (the index labels and the dimmed Top/Up/Down proved the data
  was right and only the order was wrong). Now passed as `children = ...`.
  **Copy From This Game**
  fills the list from the current game's per-game dirs, which in the usual
  workflow is the authoring game's own list. The status line reads the slot:
  not set / set for a named slot game / active in this game / pending a
  reload.

Consequences worth knowing before using it:

- **Module content still layers underneath.** Local-assets mode replaces only
  the CurrentGame store, and store priority is Core < Module < CurrentGame,
  so a local YAML item overrides the module's copy of the same guid while
  everything you have not authored keeps coming from the module.
- **Writes land on disk, not in the game.** An EotW session that writes an
  asset rewrites the file in your directory instead of patching the cloud --
  most plausibly the encounter DOCUMENT, since journal documents are rows of
  the `documents` table under `/assets` and the host banks spawn locations
  into the encounter annotation. Both overlay directories are now git
  repositories, so a write-back shows up as a diff rather than silently:
  `C:\dev\eotw` was `git init`-ed on 2026-09-06 (it had been loose files
  with no history until then -- see that day's status entry), and
  `draw-steel-codex/data` is the `draw-steel-data` submodule. Still, point
  the list only at content you are happy to have a playtest write to.
- **Mod documents are unaffected.** The EotW shared state doc lives at
  `/modDocuments/{modguid}/documents/...`, outside the intercepted
  `/GameDetails/{gid}/assets` prefix, so all the runtime state the encounter
  flow depends on syncs normally.
- **It is per-client and one-way.** Everyone else in the encounter sees the
  published module. This is an iteration tool, not a way to ship a fix
  mid-week.

- **There is no "dev game" flag, and none is needed.** Nothing marks a game
  as a developer game; the gates are the account-level `dev` setting and a
  non-empty directory list, and the EotW list is matched to the game by the
  account's EotW slot rather than by anything stored on the game. So the
  whole question "can I make the EotW game a dev game" reduces to "is
  `localassets:eotwdirs` set on this client".
- **A cloud-loading playtest is silent.** If the list is empty the game
  loads the published module with no warning -- `MaybeActivate` just
  returns. The only positive signal is the `LocalAssets:: ACTIVE for game
  ...` line in the log, which names the EotW list when it contributed.
  **Check the setting before a playtest**; it was found empty on 2026-09-18
  (see that day's status entry), which is exactly how an iteration session
  ends up quietly testing last week's published content.

### Handing this to another developer

Everything is client-side and there is nothing to arrange with the host, so
the whole recipe is:

1. Dev mode on (`dev`), and `dev:encounteroftheweek` on -- toggle the latter
   from chat with `/toggle dev:encounteroftheweek`. The first gates
   local-assets mode in the engine; the second only gates the settings block
   (`CreateEotwLocalAssetsSection` returns nothing without both).
2. Settings > Editing > **Encounter of the Week Assets (Developer)** -- add
   their content directories, top-most first. The status line tells them
   which state they are in ("Not set" / "applies to your EotW game (id)" /
   "Active ... N directories" / "reload the game to apply").
3. Create or join the EotW game from the Encounter of the Week screen as
   usual. Both flows route through `lobby:JoinGameEotw`, which writes the
   account's EotW slot, and the slot is what the engine matches the
   directories against -- so a JOINING developer gets their own overlay just
   as the host does.
4. It binds at game load. Already in the game when they set it? Leave and
   re-enter.

On path syntax (Windows): type the path exactly as Explorer shows it. `\`
and `/` are equally fine and `C:\dev\eotw` and `C:/dev/eotw` are the same
directory -- every path goes through `Path.GetFullPath` and then
`NormalizePath`, which folds separators to `/` and lowercases. Nothing is
escaped: the setting holds the raw string and the JSON encoding of the
preference is handled by the encoder/decoder on both sides, so a single
backslash is correct (a doubled one in this repo's Lua or Python is only
that language's own string escaping). Surrounding whitespace is trimmed
per line (`ReadEotwDirs`). A trailing separator used to be a trap --
`Path.GetFullPath` preserves it, so `C:\dev\eotw\` normalized to
`c:/dev/eotw/` and every `norm == root || norm.StartsWith(root + "/")`
containment test (`DirIndexForPath`, the duplicate/nesting check in
`ReadConfiguredDirs`, the move guard in `MoveItemFile`, and
`GitStatusService`, which keys its cache on the same function) compared
against `c:/dev/eotw//` and matched nothing, so files under the directory
were attributed to no root at all. **FIXED 2026-09-19 (engine NEEDS
BUILD)**: `LocalAssetDirectory.NormalizePath` now strips trailing slashes,
which fixes every caller at once since they all share it; it stops short of
emptying the path, so the unix root `/` survives and a drive root becomes
`c:`, self-consistently. Until that build ships, tell them to leave the
trailing backslash off.

Directories must be in local-assets YAML layout -- `<root>/<category>/<item>.yaml`,
with `objectTables/<tableid>/<item>.yaml` plus a `_meta.yaml` per table, and
a `_manifest.yaml` at the root. The `draw-steel-data` tree
(`draw-steel-codex/data`) already is one, which is why it is the second
entry in the canonical pair; a tree produced by the in-game export is too.

Two things to warn them about:

- **Their working copy is writable from inside the game.** Any asset edit
  during the session rewrites the YAML file it came from. Their content repo
  should be clean before a playtest so the write-back reads as a diff.
- **They will be playing a different rules set from everyone else.** The
  overlay is that one client's CurrentGame store, and CurrentGame outranks
  both Module and Core, so an edited ability or monster behaves one way on
  their machine and another way on every other player's. Useful for seeing
  their own content; not a way to test what the table will actually
  experience.


## In-game flow

- Map on entry: SUPERSEDED 2026-09-15 by "Choosing the week's encounter" -- with several encounter maps in the module, every client now travels to the chosen map on arrival (`EnsureOnEncounterMap`), waiting for the switch to land before placing heroes. The engine's natural fallback (`GameController.cs:4871`, lowest-ord map) only decides which map loads first; keeping the default "Encounter" lowest-ord still saves the extra loading beat in the common case. Original note: rather than forcing a map switch, **make "Encounter" the module's only (or lowest-ord) map** so the natural fallback selection picks it with no extra loading beat. `executeOnArrive` on `lobby:EnterGame(gameid, fn)` (fires after loading completes, `GameController.cs:7170`) and `dmhub.RegisterEventHandler("EnterGame", ...)` are both available if forcing is needed; `map:Travel()` / `game.ChangeMap(map, floor)` do the switch.
- Start zone: an `EnvironmentalKeyword` named "Start" -- the keyword is defined in the mcdm-encounteroftheweek module -- (compendium: Rules > Environmental Keywords; `EnvironmentalKeyword.lua`), painted as a markup zone (`floor.markupZones` records, `floor:SetMarkupZone`; schema at `MapMarkupPanel.lua:944-998`). Query tiles by scanning `floor.markupZones` for records with `keyword == startKeywordId` (skip `category == "surface"/"hole"`); resolve the id via `EnvironmentalKeyword.keywordsByName["start"]`. Per-square test: `game.GetAurasAtLoc(loc)` + `aura.auraInstance.aura:try_get("environmentalKeywordId")`. GoblinScript: `target.Environment has "Start"` works as a targetFilter.
- Monster AI: lives in `Monster AI/` as a `dmonly` DockablePanel background process (`MonsterAIPanel.lua`). BUILT (2026-08-28): `MonsterAI.StartAI()` / `MonsterAI.StopAI()` / `MonsterAI.IsAIRunning()` exported from `MonsterAIPanel.lua`, wrapping the same StartProcess/StopProcess calls the panel button makes (the button now routes through them). `DockablePanel.StartProcess` is independent of panel visibility (verified in source), so the AI runs headless on a host whose dmonly panels are hidden. `MonsterAI.active` is presentation/lifecycle state; `MonsterAI.IsAIRunning()` is the authoritative process-liveness read. As of 2026-08-31, `EnsureAIRunning` uses the latter so EotW restarts a process even if a catastrophic exit left the former stale. Normal turn, actor, move, trigger, and process-iteration failures are contained inside the Monster AI framework before that watchdog is needed.

### End-of-turn prompts hold the turn before Monster AI turns

Implemented in source 2026-09-22, UNTESTED in-app: a hero's mandatory end-of-turn
trigger that prompts them (Revitalizing Limerick: choose allies to spend a
Recovery) used to lose the race with the turn handoff. `GameHud:NextInitiative`
dispatched `EndTurn`, waited 0.1s, and marked the entry moved, so the AI host saw
the monsters' side arrive and claimed a turn while the troubadour's player was
still choosing. The prompt is a local cast on the ending player's client (the
invoke has no `runOnController`), so nothing synced could tell the host about it.

Fix: the `End Turn Casts` between-turn handler in
`Draw Steel Core Rules/MCDMInitiativeBar.lua` (priority 0) keeps the ended entry
current until this client's casts have been idle for 0.3s, bounded at 600s with an
`ENDTURN::` log line. Every remote client, including the AI, already respects a
turn that is still current, so no new marker or AI-side check was needed.
`tests/end_turn_cast_wait_test.lua` covers release, hold, chained-cast gaps, and
the deadline. Known gap: a `runOnController` invoke that prompts a DIFFERENT
player (an ally's client) finishes the ending client's cast immediately, so that
prompt is still not waited on.

### End-of-turn saving throws before Monster AI turns

Implemented in source 2026-09-21: Monster AI waits for player-controlled
combatants' end-of-turn save prompts and their accepted rolls to finish before
selecting or playing a monster turn. This applies to the shared Monster AI,
including EotW. The waiting notice names the hero. There is no automatic timeout
for this wait; dismissing a save card releases that card's wait, and dead or
removed combatants do not block. Monster trigger dispatch and stopping the AI
remain available while waiting.

Save cards are hostile invocation prompts, so ordinary non-hostile-trigger
checks miss them. Acceptance also clears the card before the roll completes.
`MCDMAbilitySaveBehavior.lua` now tags these prompts with the `end-turn-save`
activity ID. `DMHub Game Rules/AbilityInvokeAbility.lua` carries optional activity
tracking from prompt creation through acceptance to the cast's finish callback,
using the existing shared `pendingAIActivityReactions` records. The AI can
therefore see a remote player's unfinished roll after its card disappears.
`Monster AI/MonsterAIPanel.lua` checks both markers and outstanding save cards,
and rechecks after initiative scoring, which can yield.

Validation: `tests/ai_end_turn_save_test.lua` passes 18 checks covering multiple
saves, remote cast completion, dismissal, missing abilities, dead/noncombatant
heroes, legacy cards, and the real AI process's wait/resume/stop behavior. The
existing AI reaction-delivery suite also passes all 35 checks. Runtime syntax,
ASCII, and focused diff checks pass. The full Lua type check reports unchanged
counts in all three changed runtime files (49/3/4 respectively for invocation,
save behavior, and AI panel), but fails its total ceiling: 9721 diagnostics versus
9717 allowed, with increases in other files. Changes are uncommitted and not deployed; no engine build
is needed. Next test: with updated rules and AI on both clients, end a remote
hero's turn with two save-ends effects, accept each save and linger before Accept
Result; verify the monsters start only after both saves resolve or are dismissed.

### Automated combat entry + no Director (DECIDED + BUILT 2026-08-28; UNTESTED live)

> **2026-08-29 update**: the Director-UI presentation filter described below is
> now the OLD-ENGINE FALLBACK. On engine builds with player-host mode (see the
> "Player-host mode" section), the host's `dmhub.isDM` itself reads false, so
> `GameHud.DirectorUIVisible()` is false without the filter, the recorded
> presentation gaps (engine DM vision, showInvisibleTokens, token-menu DM
> entries, etc.) close automatically, and the `eotw:showdirectorui` escape
> hatch works by DISARMING player-host mode. The filter registration is kept
> so old builds keep the weaker chrome-only hiding.

The user-facing spec for game start: once every player is in the game, combat is
entered automatically -- heroes and monsters both -- with the normal "Draw Steel"
banner + claim-the-die roll; the Monster AI plays the monsters; and nobody is a
Director: every user, the game host included, presents as a player. Built almost
entirely as leafy EotW-module code plus small named hooks in core:

- **Core hook: `Encounter.StartCombatWithTokens{playerTokens, monsterTokens,
  encounter}`** (`Draw Steel UI/DSInitiativeRoll.lua`, next to
  `DrawSteelWithEncounter`): programmatic combat start that skips the Prepare
  Combat dialog -- fills the file-local side pools (the dialog's Draw Steel!
  press path), then `showDrawSteelBanner(nil)` = the normal roll. Call on ONE
  Director client; the banner broadcasts itself to every client on the map via
  `GameHud.PresentDialogToUsers` and ANY user may claim/roll the die (no DM
  gate on the die click -- verified in source). Queue creation, live-encounter
  attachment, `Commands.rollinitiative()` population, malice/villain-action
  seeding all happen in the existing banner-resolution path, unchanged.
  Since 2026-09-18 it also takes optional `immediateResult = "heroes" |
  "monsters"` (forced winner, no die -- the banner's existing forced-result
  path) and `surprisedTokens = {...}` (each gets Surprised until end of
  encounter before the banner shows); the montage's initiative clauses
  drive both (see "Encounter scripts", effect application).
- **Core hook: Director-UI presentation filter** (`DMHub Core UI/Hud.lua`,
  right after `RegisterGameType("GameHud", "Hud")`):
  `GameHud.RegisterDirectorUIFilter(fn)` + `GameHud.DirectorUIVisible()`.
  DirectorUIVisible = `dmhub.isDM` AND no registered filter returns false
  (filters run under pcall). This gates PRESENTATION ONLY -- `dmhub.isDM`
  stays the permission truth. Rationale: 279 `dmhub.isDM` sites exist across
  95 codex files; flipping the engine's Lua-facing isDM would also flip the
  ability/roll pipeline the AI drives (hang risk), and `CharacterInfo.canControl`
  reads `GameController.isDM`, so an engine-level flip would strip the host's
  monster control outright. Converted sites (chrome only):
  - `DockablePanel.lua`: `GetDockablePanelsSetting` (host loads the PLAYER dock
    layout) and `MayHavePanel`'s dmonly check (every dmonly panel hidden).
  - `GameHud.lua`: `CreateToolbarPanel` config choice (player toolbar),
    `DMGameControlsPanel` (rest/require-roll strip), `TipAudienceOk`.
  - `MCDMInitiativeBar.lua`: the four Director strips (VILLAIN ACTIONS /
    REINFORCEMENTS / CUES / ENCOUNTER ACTIONS refresh+think gates), the combat
    settings gear (Revert Turn menu), the End Turn bubble's DM fallback, and
    the objective + boss-bar "DM sees unrevealed" reads.
  NOT yet presentation-gated (recorded gaps): engine-level DM vision/fog and
  `showInvisibleTokens` (the host still sees the whole map + hidden tokens),
  the C# `_dmhud` / session `dm` flag (other clients' user lists may still
  badge the host as Director -- and the map-script election NEEDS that flag
  true, so do not blindly flip `isDMPossiblyImpersonating`), token context
  menu DM entries (`TokenUI.lua`), HeroesPanel host controls, victory-screen
  Director controls, CodexTitleBar bits. Escape hatch: the hidden preference
  `eotw:showdirectorui` (`/toggle eotw:showdirectorui`) restores Director UI
  on an EotW client for debugging/manual recovery. Since 2026-09-16 the
  `--director` launch flag is a second way in (see "Debug Director Window");
  both feed `EncounterOfTheWeekGame.ShowDirectorUI()`.
- **`EncounterOfTheWeekGame.IsEotwGame()`** (EotW codemod): true when the game
  occupies this account's eotw slot (`lobby.eotwGameid == dmhub.gameid`) OR the
  shared state doc carries the host-stamped `eotw = true` marker. Cached once
  true. The authoring game has neither, so it presents normally -- but running
  `SetupOnArrival` there WOULD stamp it; `EncounterOfTheWeekGame.ClearEotwMarker()`
  is the dev recovery.
- **Arrival tracking** (`eotwstate` doc): the host's setup stamps
  `eotw = true` + `expectedUsers` (userids with >=1 claimed hero at launch,
  computed on the titlescreen from the roster record and passed as
  `SetupOnArrival{members}`); every member writes `arrived[userid] = serverTime`
  AFTER `PlaceMyHeroes` returns, so a visible arrival implies that player's
  hero records exist. `AllPlayersArrived()` = every expected userid has an
  arrival AND the newest arrival is >=3s old (grace beat so the last client in
  sees the banner appear; math.abs guards serverTime rebasing). Known edge
  (accepted): an expected member who never arrives (crash at loading) stalls
  combat entry until they do -- same class as the host-crash-during-setup edge.
- **The EotW Map Script** (the once-only/elected-writer layer): the EotW codemod
  registers builtin `builtin:eotw-encounter` via `MapScript.RegisterBuiltin`
  (thin code-string shim forwarding `hostThink` to
  `EncounterOfTheWeekGame.MapScriptHostThink(ctx)`, interval 2s -- all real
  logic stays in the codemod), and the host's setup attaches it to the map
  (`AttachMapScript`: `map:scripts` record via CreateRecordFromLibrary /
  SetAttachedRecords -- Director-writable, replicates, persists with the game;
  idempotent). The authoring game's map never gets the attachment because
  setup never runs there. Election always picks a live host client: the host
  is the game's only Director and `GameSession.dm` (what `IsDirectorPresent`
  reads) reports the REAL DM flag, untouched by the presentation filter.
  `MapScriptHostThink` state machine, stage mirrored in the script's shared
  state: (nil) wait for `AllPlayersArrived`, gather sides, then
  `ctx:RunOnce("draw-steel", ...)` -> `Encounter.StartCombatWithTokens` with
  the map's authored encounter (via `FindMapEncounter`; nil = Custom is fine);
  queue live -> stage "combat" + `EnsureAIRunning`; queue gone while "combat"
  -> `EnsureAIStopped` + stage "complete" (inert; post-encounter flow is later
  work). Side gathering (`GatherCombatSides`): every valid map token,
  `IsHero()` -> heroes, else non-playerControlled `IsMonster()` -> monsters;
  returns nil while either side is empty so the run-once is never burned on a
  half-ready map. Known edge (accepted): host crash after the run-once fires
  but before the roll resolves burns the one shot -- recovery is
  `/toggle eotw:showdirectorui` + manual combat start.
- **Players run initiative**: host setup writes the existing game setting
  `permission:playersinitiative = true` (`MCDMInitiativeBar.lua:277`), so
  `CanControlInitiative` passes for every player -- turn selection and round
  advance need no Director.
- Encounter spawning (DECIDED 2026-08-27; BUILT + VERIFIED same day): the map ships
  with no live monsters; EotW game-side Lua discovers the encounter from the map's
  journal documents (`[[encounter]]` islands) and spawns it scaled to hero count,
  after setting the "Number of Heroes" setting (id `numheroes`, game-scoped, enum
  3..7 ONLY -- clamp before writing). Facts pinned by the implementation session:
  - **`[[encounter]]` islands embed the whole Encounter by value** in
    `doc.annotations["encounter"]` (`RichEncounter`; suffixed tags like
    `[[encounter:round2]]` are separate annotation keys, NOT references) -- there is
    no `encounters`-table asset involved, so shipping the doc ships the encounter,
    banked `spawnlocs` included. The Goblin Guards doc's groups use `minHeroes`
    gates (base 2 warriors + a 2-warrior group each at 4/5/6+ heroes) and its
    round-2 reinforcements are a separate island, not wave groups.
  - **Discovery**: `Encounter.GetEncountersOnCurrentMap()` (`MCDMEncounter.lua:3391`)
    returns `{name, encounter, richEncounter, docid, bubbleid}` in content order;
    the EotW codemod takes the first entry that is bubble-sourced (info bubbles are
    per-floor, so on the current map by construction) or whose doc's `parentFolder`
    chain roots at the current mapid (`CustomDocument.IsDocInAccessibleRoot(doc,
    {[mapid]=true})`). WEEKLY AUTHORING CONVENTION: the first `[[encounter]]`
    island in the doc is the start-of-combat encounter; reinforcement islands come
    after it. Note the map-docs root is DM-only (`GetAccessibleRoots`), which is
    fine: only the host spawns.
  - **Spawning**: `Encounter.SpawnGroupForReal(group, numHeroes, fallbackAnchor)`
    and `Encounter.AdjustedGroupCount(group, numHeroes)` -- promoted from locals in
    `Draw Steel V/EncounterPanel.lua` (2026-08-27) so headless callers reuse the
    combat-grade walk (stable `SortedMonsterIds` order, per-monster banked-position
    queues, fallback grid instead of silent skips, minion squads, balancing
    stamina, initiative grouping). Call it on RAW groups (it applies
    `AdjustedMonsterQuantity` itself -- do NOT pre-clone with
    `CloneForNumberOfHeroes` or deltas apply twice), skipping `group.wave ~= nil`
    and `AdjustedGroupCount == 0` groups. Also fixed in the promotion: it now calls
    `game.UpdateCharacterTokens()` after each token, because
    `OnCreateFromBestiary`'s name numbering reads `dmhub.GetTokens{pending=true}`,
    which cannot see fresh spawns until an update -- without it every monster in a
    batch was named "<type> 1" (latent bug in the builder's real-placement path;
    the journal island's own spawn already updated per token).
  - **Guard + island consistency**: spawned charids are recorded on
    `richEncounter.spawns` + `UploadDocument()` (exactly like the island's Place on
    Map), so the island's Save and Remove / Run Encounter buttons and the
    combat-setup dialog (`Encounter.SetReadiedEncounter`) work; the already-spawned
    check is "any id in `richEncounter.spawns` with `dmhub.GetTokenById(id) ~= nil`"
    -- GetTokenById returns nil for deleted AND despawned characters (verified), so
    the stale ids in the shipped doc never trip it.

### Initiative roll: monsters took the first turn on a 10 (ROOT-CAUSED + FIXED 2026-09-08; core fix, reload pending, UNTESTED live)

Report (2026-09-08, live EotW game): the players rolled a 10 on the Draw
Steel die, the banner said the heroes won, and the Monster AI took the
first turn anyway. Live queue inspection confirmed the mechanism: the
queue's stored `playersGoFirst` was **nil** (resolved to the class default
`true`), so `playersTurn` had also been written nil and resolved to ITS
class default `false` = monsters' turn (`MCDMInitiativeQueue.lua:41-42`).

Root cause, in `Draw Steel UI/DSInitiativeRoll.lua`: the banner's
controller (the EotW host) creates the queue with `playersGoFirst =
m_heroesWin`, and `m_heroesWin` was set ONLY by the `diceface` event of the
controller's own local die. Dice are simulated on the roller's machine and
shipped as a recorded replay in the chat message (`Assets/DICE_REFERENCE.md`
sections 7-8), so on any client that did not roll -- always the case in EotW
when a player claims the die -- the replay only starts after the roller has
finished, and the controller's finish path (`doc.data.finished` + 2.6s of
banner animation) fires while that replay is still tumbling, or before the
client ever subscribed to the die (the subscription in `refreshGame` needs
the roll's chat message to have arrived before the last document change).
Result: stale or nil `m_heroesWin` -- a coin flip or, as here, nil -> the
bar shows heroes won while the monsters act. Normal games rarely hit this
because the Director both controls the banner and rolls the die.

Fix (core, applies to every game, not EotW-only): the roller's
`complete` callback now writes the authoritative die value into the shared
`drawsteel` document (`doc.data.result = rollInfo.total`, next to
`finished`; cleared at banner init), and the controller resolves the winner
from `doc.data.result >= m_initiativeThreshold` (its own threshold -- the
surprise/Initiative Threshold calc only has the player tokens on the
controller) before creating or re-rolling the queue. If no result is known
it logs `BANNER:: no die result known` and defaults to heroes, so both
`playersGoFirst` and `playersTurn` are always explicit booleans -- the
nil-falls-to-mismatched-defaults path is closed. The reroll path's
`m_heroesWin ~= nil` guard went with it. luac-clean; live in the
git folder (= this repo) pending a Lua reload; needs a live EotW check
where a non-host player rolls.

### Start-zone confinement during the pre-combat phase (DECIDED + BUILT 2026-08-28; engine NEEDS BUILD)

User direction (2026-08-28): while the initiative roll is displayed, heroes may
move around inside the Start zone but not leave it, and the zone is marked
visibly for the players. Built as a general engine **Movement Restriction Mode**
hook plus leafy EotW code:

- **Window**: the whole pre-combat phase -- from entering an EotW game until the
  initiative queue goes live. That covers both the waiting-for-players stretch
  and the Draw Steel banner (the "initiative is displayed" moment), i.e. the
  original step-22 positioning phase minus the ready-up. Once combat has started
  the restriction never returns: the host stamps `combatStarted = true` into the
  `eotwstate` doc when the queue first goes live, and clients treat that as a
  permanent latch (so a resume after combat, or after the encounter concludes,
  is never confined).
- **Engine hook (`Assets/Scripts/LuaInterface.cs`)**:
  `dmhub.SetMovementRestriction{locs}` / `dmhub.ClearMovementRestriction()`.
  Stores a `HashSet<Loc>` (normalized `withoutTinySizeOrAltitude`) on
  `GameController.instance.movementRestrictionLocs`, so the mode dies with the
  game session automatically. Enforcement, both in `CharacterToken.cs`:
  1. `GetMoveCostFn`'s `singleMoveCostFn` treats any step destination outside
     the set as impassable (`return null`) -- pathfinding, the drag preview
     arrow, and the movement-radius markers all clip to the zone for free, and
     `token:Move` (arrow keys, AI, abilities) is covered too. The
     `MoveCostFlags.ForcedMovement` flag set is exempt (pushes/slides are not
     player movement).
  2. A commit backstop in `UpdateDragging` right after `canMakeMove` is
     computed: a path whose `dest` is outside the set forces
     `legalMove/canMakeMove` false -- including for the DM (`dmillegalmoves`
     does NOT punch through a mod-installed restriction, and the ctrl-teleport
     and alt-force-move commits gate on `canMakeMove` too).
  The restriction is a per-client install and applies to all tokens while
  installed; the installing mod controls when it is active. LuaLS stubs in
  `Definitions/dmhub.lua`. On an engine build without the API the Lua degrades
  to no confinement (nil probe), overlay still shown.
- **Zone overlay**: each client draws the Start zone itself with
  `dmhub.MarkLocs{locs, color, style="dashed"}` while the restriction is
  active, destroying the returned handle when it lifts. Every EotW client runs
  the codemod, so local drawing needs no networking (MarkLocs markers DO also
  self-transmit when the user's cursor-broadcast setting is on -- remote
  duplicates render identically, harmless).
- **Driver**: a 1s poll coroutine in the EotW codemod (started at codemod load,
  `mod.unloaded`-guarded) evaluates the desired state per client:
  `IsEotwGame()` AND `combatStarted` not stamped AND queue not live AND the map
  has Start-zone tiles -> install restriction + overlay, else clear both. A
  poll (rather than event wiring) self-heals across Lua reloads, late
  `IsEotwGame` flips, and map loads.
- **The confinement follows the current map (FIXED 2026-09-16, verified live
  on the Angry Dwarves map)**: the poll remembers the `game.currentMapId` and
  `dmhub.markupZonesSeq` the restriction/outline were built from
  (`m_restrictionMapId` / `m_restrictionZonesSeq`) and tears down and rebuilds
  when either changes. Before this it installed once and then returned early
  on `m_restrictionInstalled` forever -- and the game LOADS on whichever map
  the engine picks first (lowest ord: `Encounter: Goblin Ambush`) before
  `EnsureOnEncounterMap` travels to the chosen encounter, so every encounter
  inherited the Goblin Ambush starting area (restriction AND dashed outline)
  while hero placement, which reads the zone fresh after the travel, was
  correct. Any future "read the Start zone once and cache it" code must key
  the cache the same way.

### Tooltip suppression during the pre-combat phase (DECIDED + BUILT 2026-08-30; engine NEEDS BUILD)

User direction (2026-08-30): the same pre-combat window that confines heroes to
the Start zone should also be quiet -- no tooltips, and in particular no
movement cross-section diagram, while players shuffle their heroes around.
Nothing in that phase is a rules decision a tooltip would help with, and the
drag tooltip plus its diagram is a lot of chrome for "stand over there".

Built as a **general** switch rather than an EotW special case, because
"silence the tooltips for this phase" is a thing any mod may want:

- **Engine flag: `dmhub.tooltipsSuppressed`** (`Assets/Scripts/LuaInterface.cs`,
  next to the Movement Restriction bridge). A settable boolean. While true, no
  tooltip is DISPLAYED anywhere on this client, whatever its source. Two choke
  points cover the whole app:
  1. `SheetPanel.ShowTooltip` (`Assets/Scripts/SheetPanel.cs`) -- the single
     path behind both `panel.tooltip = ...` and `panel:FloatTooltipNearTile`,
     so panel hover tooltips, map/tile tooltips and the token-drag movement
     tooltip all pass through it. A refused tooltip panel is destroyed the same
     way a replaced one is, so the caller's panel does not leak.
  2. `GameCanvas.ShowTooltip` (both overloads) -- the legacy in-engine
     `TooltipText` tooltips on prefab buttons, palette entries and context-menu
     rows.
  Setting it also dismisses whatever is already on screen
  (`SheetPanel.DismissAllTooltips` + `GameCanvas.HideTooltip`), so a
  suppression that begins under a resting mouse takes effect at once. The flag
  lives on `GameController.instance.tooltipsSuppressed` -- exactly like
  `movementRestrictionLocs` -- so it dies with the game session and a mod that
  forgets to clear it can never break tooltips beyond that game.
- **Core codex wrapper: `GameHud.SetTooltipsSuppressed(key, suppressed)` /
  `GameHud.TooltipsSuppressed()`** (`DMHub Game Hud/GameHud.lua`, right under
  `ClearMapTooltip`). Keyed, so several mods can hold the suppression
  independently and tooltips return only when the last key is released;
  releasing a key that was never held is a no-op, which is what makes it safe
  to call every tick with a computed value. Beyond pushing the engine flag it
  adds two Lua-side gates the engine one cannot do, because the engine only
  refuses to *display* a finished panel:
  - the `tiletooltip` handler returns early (next to the existing
    `maptooltips` setting check), so the map tooltip is never built;
  - the movement-diagram panel's `args` handler collapses (next to the existing
    `showmovementcrosssection` check), so `dmhub.SetMovementCrossSection` is
    never called and the offscreen render texture is never built for a tooltip
    nobody would see.
- **EotW use**: `UpdateStartZoneConfinement` (the existing 1s poll) calls
  `GameHud.SetTooltipsSuppressed("eotw", desired)` with the same `desired` that
  drives the movement restriction, so the quiet window is exactly the
  confinement window: arrival -> initiative queue live, never again once
  `combatStarted` is stamped. It is called BEFORE the Start-zone lookup, so a
  map with no Start zone (no confinement possible) still gets the quiet, and
  `ClearStartZoneConfinement` releases the key -- which is also the codemod's
  unload path.

Note this deliberately silences ALL tooltips for the phase, not only the map
ones: the user's ask was "any tooltips in this phase".

### Player-host mode: the isDM / isDMOrPlayerHost split (DECIDED + BUILT 2026-08-29; engine NEEDS BUILD)

User direction (2026-08-29, after finding the strict rules did not bind the
host): invert the presentation-filter approach. The EotW host becomes a
**player host** -- a machine that HOSTS the game (real DM status, runs setup
and the Monster AI) whose USER is presented and treated as a player. A new
engine flag makes `dmhub.isDM` read FALSE on that client, and every isDM
site was audited to decide whether it means "the Director experience"
(keeps isDM -- player behavior for the host) or "hosting capability"
(converted to the new real check).

**Engine surface** (`GameController.cs`, `LuaInterface.cs`):
- `GameController.playerHostMode` -- instance bool, so it dies with the
  game session (GameController is destroyed/recreated per game switch --
  no leak into the next game, even one without the EotW codemod).
  **Refresh-survival is load-bearing** (found 2026-08-29, see the reload
  loop below): the view-as-player hard refresh ITSELF destroys and
  recreates the GameController for the same game
  (`GameHarness.RefreshGame` -> `EnterGame(gameid)`), so
  `GameHarness.RefreshGame` now carries `playerHostMode` onto the fresh
  instance. Without that, arming the mode (which forces a refresh) wipes
  the mode, the 1s driver re-arms it, and the game re-enters forever.
- `GameController.isDMOrPlayerHost` -- the REAL check (the old isDM body,
  unchanged). `isDM` now returns `isDMOrPlayerHost && !playerHostMode`, so
  every unconverted consumer -- C# vision/fog, showInvisibleTokens, the
  engine's strictmovementrules exemption, dmillegalmoves, DM context menus,
  and all Lua `dmhub.isDM` reads -- flips to player behavior automatically.
- Lua: `dmhub.isDMOrPlayerHost` (read-only), `dmhub.playerHostMode`
  (settable; toggling forces the view-as-player hard refresh). Stubs in
  `Definitions/dmhub.lua`.
- Unchanged and load-bearing: `isDMPossiblyImpersonating` stays REAL --
  it gates game/map/floor setting writes (host setup keeps working) and
  feeds the session record's `dm` flag (`GameController.cs:10179`), which
  is what `IsDirectorPresent`/the map-script election read on every
  client. Consequence: other clients may still badge the host as Director
  in user lists (accepted, pre-existing gap).

**Codex fallback helper**: global `IsDMOrPlayerHost()` in
`DMHub Utils/Utils.lua` -- returns `dmhub.isDMOrPlayerHost`, falling back
to `dmhub.isDM` when the engine lacks the API (unknown userdata members
read nil). ALL codex conversions go through it, so on an old engine build
every converted site behaves exactly as before (verified live on the
un-rebuilt engine: helper returns isDM, reload clean). `dmhub.playerHostMode`
disjuncts are written as `== true` so nil degrades safely.

**DIRECTORLESS IS A PROPERTY OF THE GAME (DECIDED + BUILT 2026-08-29, user
direction; engine NEEDS BUILD). This supersedes all "arming" designs
below.** Directorless games -- host hosts, host plays -- are expected to be
common beyond EotW, so the engine supports them intrinsically instead of
EotW switching a session flag on after the fact. Every timing hazard
recorded in this section (mid-install corruption, mid-combat interruption,
the double load) existed only because the mode was switched on *inside* a
running session, which forces the view-as-player hard refresh. Now nothing
ever switches it on.

- **`GameInfo.directorless`** (`AccountInfo.cs`), a bool on the game record
  at `/games/{id}`, `NoSerializeValue(false)` so old records read false.
  Set at creation; `GamesMonitor.CreateGameCo` reads a `directorless`
  option from `lobby:CreateGame`.
- **`GameController.playerHostMode` is now DERIVED, not stored**:
  `directorlessGame && isDMOrPlayerHost`, with a session-only
  `playerHostModeSuppressed` override for the debug hatch.
  `directorlessGame` caches `GameInfo.directorless` in a `bool?` that reads
  through until the summary lands then sticks -- so `isDM` costs what it
  always did (the cached false short-circuits before the host lookup in
  ordinary games). There is no setter, no latch, and no arming step.
- **Timing is free**: the flag arrives with the game summary
  (`LoadingMilestones.GameSummary`), and game-details processing is already
  gated behind that same summary (`_waitingForGameSummary` in the
  `SetShouldQueuePredicate`), so nothing that reads `isDM` meaningfully runs
  before the mode is known.
- **`GameHarness` lost both its player-host special cases**: `EnterGame`
  needs no latch, and `RefreshGame` no longer carries the flag across a
  refresh -- the fresh GameController re-derives it from the record. The
  infinite-reload trap that carry-over existed to prevent is gone with it.
- Lua: `dmhub.directorlessGame` and `dmhub.playerHostMode` are now
  READ-ONLY; `dmhub.playerHostModeSuppressed` is the settable hatch (and
  refreshes only when it actually changes this client's mode). Stubs
  updated in `Definitions/dmhub.lua`.
- EotW creates with `directorless = true`
  (`Codex Titlescreen/EncounterOfTheWeek.lua`), and the game codemod's 1s
  driver now only syncs the hatch (`UpdateDirectorUIHatch`). Deleted as
  no-longer-needed: `UpdatePlayerHostMode`, `WantPlayerHostMode`, the
  quiescence gate, the `hostSetupComplete` stamp and its writer, the
  combat-entry gate, and the `ClearEotwMarker` disarm.
- **Existing EotW games predate the flag** and will run with a Director
  host: abandon and recreate them. There is deliberately no backfill --
  if one is wanted later, add a settable `directorless` to `LuaGameInfo`
  (`LuaLobby.cs`) alongside its `gameSystem` setter.
- The Director-UI filter registration is retained as the presentation
  fallback for engine builds without the flag.

**Arming is quiescence-gated (ROOT-CAUSED + FIXED 2026-08-29, second
live find).** Arming forces the hard refresh, and the refresh destroys
the GameController and its server connection -- killing in-flight
writes AND the pending `executeOnArrive` callback. On the first fresh
CREATE under the armed build, the 1s driver armed mid-starting-module
install: the install's floor-data uploads died with the connection while
its GameDetails patch survived, so mapManifests read INSTALLED and the
install never retries -- a permanently half-installed game (black map:
no floor data on the server, no characters placeable, and SetupOnArrival
never ran because the arrival callback was destroyed). Yesterday's live
test missed this because it re-entered an already-installed game. Fixes:

- *Lua (deployed)*: `UpdatePlayerHostMode` defers the false->true
  transition until `dmhub.gameLoadingProgress == 1` AND the state doc's
  `hostSetupComplete` stamp exists and is >= 10s old (GameDetails writes
  coalesce 1-3s before uploading; the window lets setup's writes flush).
  Disarming is never gated. `SetupOnArrival` no longer arms at its start
  (that refresh would kill the very coroutine doing setup); instead its
  host branch stamps `hostSetupComplete` (`RecordHostSetupComplete`) as
  its LAST step, after SignalGameReady. Setup re-runs on every host
  arrival, so pre-gate games self-heal the stamp on next entry. Net
  sequencing on a fresh create: install -> load completes -> setup runs
  and stamps -> ~10s flush -> arm -> the one refresh -> settle. (The
  host now sees a beat of Director UI on entry -- accepted; the old
  "arm immediately" behavior is what corrupted games.)
- *Engine (GameController.cs Update, NEEDS BUILD)*: the
  `s_forceHardRefresh` consumer defers the refresh (flag stays set)
  while `_installingStarterMap` or `_loadingMilestone` is short of
  Complete (GameDetails for the lobby game) -- defense-in-depth for any
  future refresh trigger during load/install. Deliberate non-cover:
  `_forceRefresh` (backupid restores) bypasses it, as before.
- The broken game (`MythicMintyPersistentScholar`, created 2026-08-29)
  is unrepairable (manifest says INSTALLED, floors gone) -- abandon it
  from the EotW screen and create fresh.

**Second live round (2026-08-29, later): the gate held, and three new
findings.** The user rebuilt but the app was NOT actually restarted
(Player.log + console buffer continuous across both sessions), so the
old engine kept running; the deployed Lua gate alone was in effect. A
fresh game (`BaronVoraciousPeckishScout`) installed and set up
PERFECTLY (all floors, 29 characters, 8 spawned tokens -- the gate did
its job). Then:

1. *Arming landed mid-combat*: the 10s flush window let the player roll
   initiative before the arming refresh fired -- a full game re-entry
   right after their roll. FIXED (Lua, deployed): the map script's
   combat entry now waits for `dmhub.playerHostMode == true` whenever
   `WantPlayerHostMode()` (shared helper: EotW game + isDMOrPlayerHost +
   hatch off + engine API present), so the one arming refresh always
   precedes the first round.
2. *The EotW screen re-opened OVER the in-game view on every mid-session
   refresh* (this is the "sent back to the titlescreen" report): the
   stale-screen sweep's "at titlescreen" check accepted "not in a game",
   which is true during a real game's LOADING phase, so the refresh
   re-entry rebuilt and SHOWED the screen. FIXED (Lua, deployed): the
   sweep only rebuilds when `dmhub.isLobbyGame == true` (pcall-guarded);
   real returns to the titlescreen reload the codemods and re-arm it.
3. *ENGINE BUG (OPEN, the actual black map): the player-vision pipeline
   never bootstraps on a load that starts with `dmhub.isDM == false`* --
   which today only the player host does (playerHostMode carried across
   the refresh). Proven live: same game, disarm the hatch -> renders
   perfectly as Director; armed re-entry -> world black, zero token
   sprites, `FLOOR VISION DIAG` shows `tokenVisionOnFloors=[]` and
   `LightingMesh[VISION]` stuck with `lights=0` and a stale
   `geomCamPos`, and enabling `debug:lightingdiag` produced NO
   `[GeomCacheDiag]` output -- `LightingMesh.BeginJob` (vision's only
   driver is `VisionMeshManager.LateUpdate`) stops being called
   entirely. All data-level gates were verified good (hero owned, party
   == default party, tokens spawned via `GetTokensAtLoc`, tokenVision
   list empty). Root mechanism not yet pinned; the next build carries
   permanent cheap instrumentation: `[VisionStallDiag]` heartbeats in
   `VisionMeshManager.LateUpdate` (mesh count, BeginJob call counters,
   per-mesh controller binding) plus a mesh-side watchdog in
   `LightingMesh.LateUpdate` that fires when BeginJob goes idle under
   player vision (catches a dead manager). Also fixed in the same
   build, a real audit miss: `GameController.primaryCharacter` returned
   null for the player host (`isDMPossiblyImpersonating` gate) -- now
   exempted when `playerHostMode` is set, restoring the host's primary
   character (vision main-floor selection, camera focus, player UX) --
   plausibly the vision root cause, to be confirmed against the
   heartbeat after the rebuild.

**Third live round (2026-08-29, after the rebuild): THE BLACK MAP IS
FIXED.** Verified in `DireAshenGoldenInitiate` with `isDM=false,
playerHostMode=true`: the map, tokens and player action bar all render
correctly, and no `[VisionStallDiag]` line ever fired (the stall state
was never entered). The cause was the audit miss now corrected --
`GameController.primaryCharacter` returned null for a player host via the
`isDMPossiblyImpersonating` gate, which emptied `selectedOrPrimaryTokens`
and starved the vision pipeline of a main floor. The `[VisionStallDiag]`
instrumentation stays in as cheap permanent cover.

The same run showed the arming refresh once more, and the log pinned the
trigger exactly: the hatch was ON at entry (left on from the previous
investigation), so the host set up and entered combat as a Director and
the combat-entry gate correctly let combat proceed; the user then ran
`/toggle eotw:showdirectorui` mid-combat (`ExecuteCommand
(eotw:showdirectorui false)` sits between "Draw Steel!" and
`playerHostMode false -> true` in Player.log), and the driver armed. So
the gates worked as designed -- but a clean run still cost the player TWO
loads, which is what motivated arming-before-entry above.

**Directorless broke the encounter lookup: journal access is isDM-gated
(ROOT-CAUSED + FIXED 2026-08-29, live).** First directorless run: the game
loaded correctly as a player host but never drew steel. The log gave it
away -- `EotW: encounter spawn failed: This map's journal has no encounter
to spawn.` No monsters means `GatherCombatSides()` returns nil, so the map
script's combat entry is never reached; nothing about initiative was
involved. Root cause: `CustomDocument.GetAccessibleRoots()`
(`DocumentSystem.lua`) grants `private`, `templates` and **the current
map's own journal root** only when `dmhub.isDM` -- and the EotW encounter
("Goblin Guards Combat") lives in that map root. With the host now a
player from load, `Encounter.GetEncountersOnCurrentMap()` filtered the
encounter document out before `FindMapEncounter` ever saw it. Verified
live: `GetAccessibleRoots()` returned only `{public, <userid>}`, and 3
markdown docs sat unreachable under the map root.

Fix keeps presentation and capability separate rather than opening the
journal up: `GetAccessibleRoots(hostAccess)` and
`Encounter.GetEncountersOnCurrentMap(hostAccess)` take an optional flag
that resolves access for the machine HOSTING the game
(`IsDMOrPlayerHost()`) instead of the user viewing it; only capability
callers pass it, so the host's journal UI still shows them exactly what a
player sees. `FindMapEncounter` passes `true`. Default nil = today's
behavior, so every other caller is untouched. Verified live: with
hostAccess the lookup finds 5 encounters (0 without), the spawn succeeds,
and `Encounter.StartCombatWithTokens` puts the DRAW STEEL banner up with
`dmhub.isDM == false` -- confirming the initiative/banner chain needs no
Director privileges (its only `isDM` reference is a right-click "Close"
menu).

**This is the third find in the same family** -- a directorless host loses
DM-derived DATA ACCESS, not just Director UI. The others were
`CharacterInfo.canControl` and `GameController.primaryCharacter`. When
something stops working for a player host, look for a read gated on
`dmhub.isDM` that is really a capability, not a presentation choice.

Caveat for anyone re-testing the game used above
(`ImmoralFearfulExternalLancer`): its map script already burned the
`draw-steel` RunOnce watermark (the watermark is written BEFORE the
callback fires), so combat will not auto-start there again. Test on a
fresh game.

**NEXT LIVE TEST (needs the engine build for the directorless flag):**
with the hatch OFF, create a FRESH EotW game (existing ones predate the
flag and must be abandoned) and confirm: a SINGLE load, player UI/vision
from arrival, no second reload at any point, `/games/{id}/directorless`
true in Firebase, and combat entering normally. Then confirm the hatch
still works by toggling `eotw:showdirectorui` on and off mid-game -- that
path should still refresh, which is correct for a debugging action.

**The audit** (2026-08-29, five parallel agents over every isDM site:
~115 engine C# + core-Lua sites, 294 codex Lua sites; full per-site logs
in the session transcripts). Default = KEEP (player behavior). The
conversions applied:

- *Engine C#*: `CharacterInfo.canControl` (monster control / the AI's
  foundation); `GameController.cs` starting-module install gate + its DIAG
  mirrors (host must install) and `PasteCharacters` ownership stamp
  (setup-script pastes must NOT stamp the host as owner of spawned
  monsters); `CharacterToken.cs` prompt routing (`activeControllerId` --
  otherwise the host defers every monster prompt to its own session:
  deadlock), the three frozen-game gates (Teleport/ForcedPush/ExecuteMove
  -- AI movement must never freeze), the two summon camera-centering
  suppressions (canControl is host-wide now), and the hidden-token drag
  P2P embargo; `CloudAssetManager.cs` fork-backfill sweeps;
  `LevelObject.cs` portal recalc sweep; `ObjectController.cs` orphan
  cleanup sweeps; `OnePlayerStatusPanel.cs` bogus "Stop impersonating";
  `RectSelectObjects.cs` current-floor rubber-band restriction;
  cross-map teleport camera-follow now requires OWNERSHIP on a player
  host; `playingGame`/`perfhitch` analytics `dm` dimension = real hosting
  status (workload semantics).
- *Core Lua* (`Assets/CoreAssets/Lua/require-dc-dialog.txt`, ships with
  the build): the two "who does this client prompt for" predicates and
  the monster-save autoroll (see the compound rule below).
- *Codex Lua*: MapScript host-presence write/release + `IsElectedHost`;
  MCDMEncounter `CompleteEncounter` (battle log/analytics) + encounter-
  script `IsElectedHost`; DSVictoryScreen `RecordHeroRoles`;
  MCDMCreature `SyncHiddenInvisibility` single-writer; MCDMInitiativeQueue
  `CanClaimTurn` programmatic default + `GetTokensForInitiativeId`'s
  invisibility filter (mechanical token set for AI/turn processing;
  trade-off: the host's initiative bar can show an invisible monster's
  face); ActivatedAbility's frozen funnel + `params.director` analytics
  (now: real Director, OR non-player-controlled cast on a player host --
  so AI casts attribute as director, host hero casts as player);
  Monster AI `/testai` gate; RequireDCDialog + DSRequestRollsDialog
  monster-save/resistance autoroll.
- *The compound prompt predicate* (core require-dc-dialog.txt + codex
  RequireDCDialog.lua + DSRequestRollsDialog.lua): neither flag alone is
  right -- a plain player prompts for anything they control; a DM/host for
  non-player tokens; a player host BOTH monsters and their OWN tokens
  (canControl is host-wide for them, so `tok.ownerId ==
  dmhub.loginUserid`, gated on `dmhub.playerHostMode == true`, is the
  discriminator; normal games bit-identical).
- *Everything else KEEP*, notably every `strict:*` rules-enforcement gate,
  Director chrome, DM-privileged info display, editor tools -- which is
  the point: with isDM false, the host is bound by the strict rules,
  loses DM vision/hidden-token display, gets the player UI, and the
  Rules Enforcement problem that triggered this work resolves engine-wide.

Notable accepted edges: the host can still physically drag monsters
(canControl is capability -- needed for manual recovery, and the DM-drag
paths are not player-rule-gated); freeze is unreachable in EotW and the
host is exempt from it (AI safety); analytics dm dimensions now mean
"was hosting".

### Monster AI moves are clamped by strict:movement on a player host (ROOT-CAUSED + FIXED 2026-08-29; engine NEEDS BUILD, UNTESTED)

Report: the Goblin Warrior's "Spear Charge" AI move works in a normal
Director game, but in an EotW game the goblin announces the charge, the
charge movement never happens, and it then attacks from outside range.
Suspected to be a permissioning denial under player-host mode. It is not
a permission denial -- token control, prompt routing and the frozen-game
gates were all converted to `isDMOrPlayerHost` and work (the goblin does
act). It is a **rules-enforcement clamp** that now binds the AI.

**Mechanism.** `CharacterToken.Move` -- the `token:Move(loc, options)` Lua
bridge (`Assets/Scripts/CharacterToken.cs:3040`) -- clamps `maxCost` to
`GetRemainingMovementBudget()` when all of these hold:

    !straightline && !freeMovement && movementType in {nil, Walk, Shift}
    && gameDetails.incombat
    && GameController.instance.isDM == false
    && SettingsManager.GetBool("strict:movement")

In EotW all four are true on the host: `strict:movement` is force-enabled
by `EnforceStrictRules()`, and `isDM` is false because the host is a
player host. So *every* Monster AI `token:Move` (29 call sites across
`Monster AI/*.lua`, none of which pass `freeMovement`) is silently
budget-clamped -- something that never happened in a Director game,
where `isDM == true` short-circuits the clamp.

Spear Charge is the case that shows it, because it moves **twice** in one
turn:

1. `execute` calls `token:Move(scoringInfo.loc, {maxCost = 10000})` -- the
   reposition. At turn start the budget is full, so this move happens, and
   `creature:CreatureMove` records it into `moveDistance`
   (`Creature.lua:6829`; it is not `_tmp_freeMovement`, and it *is* the
   monster's turn).
2. `MonsterAI:ExecuteAbility` then runs the charge:
   `token:Move(target.charge, {maxCost = 10000})`. Remaining budget is now
   ~0, so `maxCost` clamps to ~0, `TryMoveTo` returns null, and `Move`
   returns nil. **The AI ignores the nil return** and casts the ability
   anyway -- hence the attack from outside range. Same shape in
   `ExecuteSquadStrike` (`MonsterAI.lua:1167`/`1175`).

**Planner/executor asymmetry makes it silent.** The charge is *validated*
in `FindValidTargetsOfStrike` with `token:MarkMovementArrow(...)`, which
has no `isDM`/`strict:movement` gate at all and measures the charge
against full `CurrentMovementSpeed()` -- so the planner sees a legal
charge that the executor then refuses, with no log line either side.

**The fix, as built (three layers).**

1. *Lua, live now, semantically right in every game*: the two **charge**
   moves (`MonsterAI.lua` `ExecuteSquadStrike` and `ExecuteAbility`) pass
   `freeMovement = true`. A Draw Steel Charge is a main action whose
   movement belongs to the ability, not to the creature's move action, so
   it must never be charged against -- or clamped by -- the move budget.
   This alone resolves the reported symptom, and in a Director game it is
   a behavioural no-op plus a correctness fix (the charge stops consuming
   move distance).
2. *Engine: the clamp learns the difference between the user and the
   host.* New `CharacterToken.subjectToPlayerMovementRules` -- false for a
   Director, and false on a player host for any token the user does not
   own -- replaces the bare `isDM == false` test in the `token:Move`
   clamp. The host's own hero stays fully bound by strict movement (the
   point of player-host mode); a monster it controls only because it hosts
   does not. In an ordinary game this evaluates exactly as before. It is
   the backstop for AI-driven moves that do not run inside an elevated
   coroutine.
3. *Engine: host-permission elevation* -- the systemic answer, see the
   next section.

**This is the fourth find in the player-host family** and the first that
is not a data-access gate: a *rules* gate the audit deliberately kept on
`isDM` turns out to bind the host's AI, not just the host's own hero.
Rule of thumb: a `strict:*` gate is correct on `isDM` only for tokens the
USER is playing; anything the host drives programmatically needs either
the ownership discriminator or host-permission elevation.

### Host-permission elevation: coroutine-scoped, inert while yielded (DECIDED + BUILT 2026-08-29; engine NEEDS BUILD, UNTESTED)

User direction (2026-08-29): rather than chase `isDM` gates one at a time,
give the engine a scope that guarantees DM-level permissions for a stretch
of Lua, and run the Monster AI inside it -- the AI *should* have host
permissions, and enumerating every rule it might trip is a losing game.

The naive form does not survive contact with the AI. `dmhub.Coroutine` is
real Lua coroutines resumed once per frame from the harness in
`LuaNative.cs`, and an AI turn spans hundreds of frames with `Sleep` calls
throughout -- including one immediately before the charge move. A flag
held for "the duration of the block" would therefore stay set across the
frames *between* resumes, where `VisionMeshManager.LateUpdate`, fog,
`showInvisibleTokens`, Director chrome and DM context menus all sample
`isDM`. The player host would flip to Director vision and Director UI for
the 10-odd seconds of every monster turn -- the exact family that produced
the black map.

So the elevation is **per-coroutine and inert while yielded**:

- `ScriptEngine.hostPermissionDepth` (static int). `GameController.isDM`
  reports real hosting status while it is non-zero:
  `if(playerHostMode && ScriptEngine.hostPermissionDepth == 0) return false;`
  -- the `playerHostMode` test stays first, so an ordinary game
  short-circuits on the cached directorless check and costs exactly what
  it did before.
- The coroutine harness (`_callco` / `_updateco` in `LuaNative.cs`) parks
  the depth on the coroutine record (`co.hostElevation`) via
  `dmhub.SuspendHostPermissions()` the instant a coroutine yields, and
  restores it with `dmhub.RestoreHostPermissions(n)` when that coroutine
  is resumed. Between resumes the global depth is zero, so **nothing
  outside a Lua execution window can ever observe an elevated `isDM`** --
  rendering, vision and UI are structurally excluded rather than trusted
  to behave. An elevation also dies with its coroutine, so a `Push` with
  no matching `Pop` (an early return, an error) cannot leak.
- Lua API: `dmhub.ExecuteWithHostPermissions(fn)` for a synchronous block
  (`fn` must not yield -- it runs through `lua_pcall`, so a yield inside
  raises the C-call-boundary error), and `dmhub.PushHostPermissions()` /
  `dmhub.PopHostPermissions()` to elevate a whole coroutine.
  `SuspendHostPermissions` / `RestoreHostPermissions` are harness
  plumbing, marked `[Deprecated]` so they stay out of the generated docs.
  Stubs in `Definitions/dmhub.lua`.
- Codex helpers `ElevateToHostPermissions()` / `DropHostPermissions()` in
  `DMHub Utils/Utils.lua`, guarded so they are no-ops on an engine build
  without the API (unknown userdata members read nil) -- same pattern as
  `IsDMOrPlayerHost()`.
- Applied at the Monster AI's three coroutine entry points:
  `MonsterAI:PlayTurn` (the turn itself), `MonsterAIThread`
  (`MonsterAIPanel.lua` -- the watcher loop, which also handles triggers
  inline), and the `/testai` one-shot run.
- **Steady-state cost is zero.** The harness runs per coroutine per frame,
  so it must not pay for a feature almost nothing uses:
  `dmhub.PushHostPermissions` sets a `g_hostElevationDirty` Lua global, and
  the harness only calls Suspend/Restore for a coroutine that is already
  elevated or elevated itself during that resume. Coroutines that never
  elevate touch neither bridge.
- **The invariant is enforced, not merely maintained**: `Update()` and
  `CallCoroutine()` zero `hostPermissionDepth` immediately after the
  harness returns, so even a stray push (an at-exit callback, a `Push`
  with no `Pop` outside a coroutine) cannot leak elevation into a frame.

**Naming is deliberate: "host permissions", not "DM permissions".** The
scope restores Director *capability*, never Director *presentation*.
Wrapping UI or vision code in it would reintroduce precisely what
player-host mode exists to prevent, and a name with "DM" in it invites
exactly that.

Accepted, per user direction: a codemod or rail-button macro can wrap the
host's own hero in the scope and step outside the strict rules. Cheating
via Lua is not a threat model here.

Deliberately NOT replaced: the ~15 capability sites the audit converted to
`isDMOrPlayerHost` stay as they are. Elevation is for automation acting on
tokens the user does not own, not a general substitute for the
capability/presentation split.

**Known related site, left alone pending a decision**:
`CharacterToken.PlayerMoveBlockedByMovementRules` (the `strictmovementrules`
drag block, renamed from `DragBlockedByMovementRules` on 2026-09-08 when the
arrow keys started sharing it -- see "Arrow-key movement bypassed the drag
gates" below) has the same shape -- on a player host it now stops the host
manually dragging a monster during combat when it is not that monster's
turn, which the audit had explicitly accepted as a manual-recovery path.
It is a user action rather than automation, so it was not changed; the
same `subjectToPlayerMovementRules` helper would fix it in one line.

### Turn control on a player host: End Turn for AI monsters (ROOT-CAUSED + FIXED 2026-08-29; engine NEEDS BUILD, UNTESTED)

Report (2026-08-29): during a monster's turn in an EotW game the host is
offered the initiative bubble's **End Turn** button and can click it,
ending the AI's turn out from under it. A host who is not playing those
monsters -- they are run by the Monster AI -- must not get that button.

**Mechanism, and the fifth find in the player-host family.** The audit
converted `CharacterInfo.canControl` to `isDMOrPlayerHost` because it is
hosting capability (the Monster AI's foundation). But `canControl` is
also read by UI asking a different question -- *is this token mine to
drive?* -- and on a player host it answers "yes" for every token in the
game. `ShouldShowEndTurn` in `MCDMInitiativeBar.lua` walks the tokens of
the current initiative entry and shows End Turn if any is `canControl`,
so the host got it on the goblins' turn. The same read sits on the
bubble's three selected-token paths (the swords hover, its press, and the
Claim Turn think), which would likewise let the host claim a monster's
turn.

This is the counterpart to the movement clamp: there, a *rules* gate kept
on `isDM` wrongly bound the host's AI; here, a *capability* read
converted to `isDMOrPlayerHost` wrongly frees the host's UI. Rule of
thumb, extended: `canControl` is the right read for "may this machine do
it"; UI asking "is this the user's token" needs the user-level read.

**The fix (engine property + codex helper).**

- *Engine*: `CharacterInfo.canControlAsUser` (`CharacterInfo.cs`) is
  `canControl` with `isDMOrPlayerHost` swapped back to `isDM` -- the
  Director, ownership and party-ownership arms unchanged. So it is
  bit-identical to `canControl` in every game that is not directorless,
  and on a player host it reports what a plain player would control.
  Bound to Lua as `token.canControlAsUser` (`CharacterToken.cs`, with the
  same `s_viewAsPlayerTokens` override as `canControl`); stub added to
  `Definitions/CharacterToken.lua`.
- *Codex*: global `TokenControlledByUser(tok)` in `DMHub Utils/Utils.lua`
  -- returns `tok.canControlAsUser`, and on engine builds without the API
  falls back to the ownership discriminator already used by the prompt
  predicates (`dmhub.playerHostMode == true` -> `tok.ownerId ==
  dmhub.loginUserid`), else `tok.canControl`. **The fallback is why this
  fix is live before the rebuild**: EotW heroes are transferred with
  strict ownership (`token.ownerId = dmhub.loginUserid`), so the
  discriminator is exact for EotW; the engine property additionally
  covers party-owned tokens, which the fallback misses.
- *Applied* in `Draw Steel Core Rules/MCDMInitiativeBar.lua` at the four
  bubble sites above. `ShouldShowEndTurn` gates both the label and the
  press handler, so denying it removes the click too, and the bubble
  falls back to showing "Enemy Turn" -- which is what the host should see.

Deliberately unchanged: the "Combat Settings" gear menu (Switch Side,
Skip to Next Round, Revert Turn) is gated on `CanControlInitiative()` =
`dmhub.isDM or permission:playersinitiative`, so it is already closed to
a player host. ~~The host can still physically drag monsters -- the
accepted manual-recovery path.~~ SUPERSEDED 2026-08-30: the map-interaction
fix below disables the monster's collider on a player host, so the host
cannot drag it either; manual recovery is now the `eotw:showdirectorui`
hatch.

### Map interaction on a player host: monsters must not be selectable (ROOT-CAUSED + FIXED 2026-08-30; engine NEEDS BUILD, UNTESTED)

Report (2026-08-30): in an EotW game the host can click a monster token on
the map and select it -- and the moment it does, the map goes black.

**Mechanism -- the sixth find in the player-host family, and the first one
inside the engine's own mouse surface.** The black screen is not a vision
bug; it is the correct vision pipeline being pointed at the wrong token:

1. `CharacterToken._collider.enabled = canControl` (`UpdateRendering`).
   That collider is the ONLY mouse surface a token has --
   `CharacterTokenRaycaster` raycasts it for hover, click, drag and the
   right-click menu. On a player host `canControl` is true for every token,
   so monsters are clickable; for a plain player they have no collider at
   all, which is why no player has ever hit this.
2. Clicking selects, which sets `CharacterToken.currentToken` to the
   monster, so `GameController.currentOrPrimaryCharacter` is now the
   monster.
3. `LightingMesh.BeginJob` builds `_reusablePartiesViewing` for a
   non-DM-vision client from **that** character's party. With a monster
   selected the list holds the monster party, so every hero token fails the
   `_reusablePartiesViewing.Contains(...)` filter in the vision loop.
4. Zero vision lights -> the floor is never added to
   `LightingMesh.tokenVisionOnFloors` -> `GameController.LateUpdate` sets
   `renderWorld = false` on the floor. Black map. (Monsters themselves are
   excluded from vision one guard earlier, on empty `ownerId`, which is why
   the host correctly gets no vision *from* the monster -- the user's
   observation.)

**The fix: `canControlAsUser` is now an engine-side gate, not just a Lua
one.** The rule of thumb from the End Turn find -- `canControl` answers
"may this machine do it", the user-level read answers "is this the user's
token" -- applies to every USER-driven interaction, so those sites moved:

- *`CharacterToken.cs`*: a C# `canControlAsUser` property mirroring
  `canControl` (same `s_viewAsPlayerTokens` override, delegating to
  `CharacterInfo.canControlAsUser`), then applied to the **collider enable**
  (the root fix -- no collider means no hover, click, drag or right-click
  menu, exactly a player's experience), the `Clicked()` selection gate, the
  `MouseDown` press gate, the `UpdateDragging` drag branch, and the
  rotation-handle activation.
- *`RectSelectObjects.cs`*: rubber-band token select no longer sweeps in
  monsters.
- *`GameController.cs`*: `NextToken()` (the cycle-tokens hotkey) no longer
  lands on a monster.
- *`LuaInterface.cs`*: `dmhub.SelectToken` / `dmhub.AddTokenToSelection`
  gate on `canControlAsUser`, which closes the codex-side selection paths
  -- notably the initiative bar's entry click
  (`MCDMInitiativeBar.lua:5912`), which would otherwise have selected a
  monster from the bar. No codex change was needed for that. Stub docs
  updated in `Definitions/dmhub.lua`. **`dmhub.selectedTokens` (the setter)
  is deliberately NOT gated** -- it stays the capability-level entry point
  for machine-driven flows (`spawnFromBestiary` -> `rollinitiative`).
- *`OffScreenTokenTracker.cs`*: the off-screen "your token is over here"
  arrows were tracking every monster the host controlled -- a monster
  position radar. Now user-controlled tokens only.
- *`LightingMesh.cs` (defence in depth)*: when
  `currentOrPrimaryCharacter` is a token the user does not control in their
  own right, the parties-viewing list falls back to the default party
  instead of the monster's. Vision must not be one stray selection away
  from a black screen, whatever future path sets the current token.

All of these are bit-identical in any game that is not directorless
(`canControlAsUser == canControl` there), so the blast radius is the player
host only.

**Accepted consequence: the "host can still physically drag monsters"
manual-recovery path recorded in the End Turn section is REVOKED.** With
the collider off, the host cannot touch a monster with the mouse at all.
The recovery path is now the debug hatch: `/toggle eotw:showdirectorui`
restores `isDM`, and with it the collider, the context menus and the rest
of the Director experience.

**Noted but deliberately NOT changed: `CharacterToken.CalculateCanSee`**
still short-circuits to visible on `canControl`, so a player host *sees*
every monster on the map regardless of fog -- an X-ray the host is not
meant to have, but changing it decides a design question (should the
machine running the AI watch the monsters it runs?) rather than fixing a
defect. Raised for a decision; see Open Questions.

### Strict rules enforcement (DECIDED + BUILT 2026-08-28)

User direction (2026-08-28): EotW games strictly enforce all game rules -- the
settings screen's "Rules Enforcement" options that start with "Strict"/"Strictly"
are force-enabled. The forced set (the `true` entries of
`g_forcedGameSettings` in `EncounterOfTheWeek/EncounterOfTheWeek.lua`; the
same table also carries the monster-stamina visibility and Monster Info
settings, see "Players always see monster stamina bars, not amounts" and
"Monster Info is always on" below):

- `strict:movement` (Strictly Enforce Forced Movement Rules)
- `strict:targeting` (Strictly Enforce Targeting Rules)
- `strict:resources` (Strictly Enforce Action Economy and Resource Costs)
- `strict:inventory` (Strict Inventory Management)
- `strict:rolls` (Strictly Enforce Rolls -- added 2026-08-29, see below)
- `strictmovementrules` (the ENGINE's "Strictly Enforce Movement Rules";
  included because the intent is "strictly enforce all game rules" -- drop it
  from the list if unwanted. As of 2026-08-29 it renders WITH the others under
  "Rules Enforcement" rather than under the separate "Game" heading.)

Deliberately NOT forced: `strict:hiddeninvisible` ("Hidden Monsters Invisible
to Players") -- it shares the GameStrictRules section but is a Director
visibility tool, not a strictness rule, and does not match the "Strict..."
naming criterion.

Mechanism: `EnforceStrictRules()` walks `g_forcedGameSettings` (a list of
`{ id, value }` entries) and writes any game-scoped setting whose current
value differs from its forced value. Called from the host's `SetupOnArrival`
block (next to the `permission:playersinitiative` write) and re-asserted at
the top of every `MapScriptHostThink` tick (check-before-write, so
steady-state ticks write nothing).

#### Arrow-key movement bypassed the drag gates (FOUND + FIXED 2026-09-08; engine NEEDS BUILD, UNTESTED)

User report (2026-09-08): in a live EotW game the arrow keys still moved the
reporter's hero when it should have had no movement (off-turn), even though
dragging refused. Root cause (engine-wide, not EotW-specific): the arrow keys
are bound to the built-in `tokenmove` console command
(`Assets/CoreAssets/Lua/commands.txt`, compiled into the engine as builtin
Lua -- NOT a codex file), which calls `token:Move`. The `Move` bridge already
clamped to the strict:movement remaining budget and honoured the
movement-restriction zone, but it skipped the three gates the mouse drag in
`CharacterToken.UpdateDragging` applies before a drag can even start:
`canControlAsUser`, the frozen-game check (`isDM || !frozen`), and the
`strictmovementrules` "in combat, not this token's turn" block. So off-turn
arrow movement went through whenever the budget clamp alone did not catch
it.

Fix, all engine-side:

- `CharacterToken.DragBlockedByMovementRules` renamed to the public
  `PlayerMoveBlockedByMovementRules` (same body: `isDM` short-circuit, the
  `strictmovementrules` setting, the initiative-status switch).
- `Move` (the Lua bridge) gained a `playerMovement` option. When true it runs
  the three drag gates above up front and returns nil if any refuses; the
  budget clamp and zone restriction then apply as before. AI, ability and
  forced movement never pass it, so their behaviour is unchanged.
- `tokenmove` passes `{playerMovement = true}`. The `dmhub.isDM or
  newLoc.isOnMap` pre-check it already had is untouched.
- LuaLS stub `Definitions/CharacterToken.lua` documents the option.

Both halves ship with the engine (the C# and the builtin Lua), so this is
inert until the next build. `flyup`/`flydown` (`MoveVertical`) were not
touched.

#### Off-turn ability use (FOUND + FIXED 2026-09-07; verified live, uncommitted)

User report (2026-09-07): in a live EotW game the action bar let the reporter
use their Polder Elementalist's abilities while another creature's turn was
selected. Root cause (codex-wide, not EotW-specific): the per-drawer
`refresh` in `DrawSteelActionBar.lua` only cleared the drawer's cosmetic
`available` class off-turn (its one style rule is a bgcolor), the drawer's
`press` opened the menu unconditionally, and the `strict:resources` click
gate on ability chips (the `press` in `AbilityHeading`) refused only on
`m_cannotAfford` / `m_expended` / `m_suppressed` -- none of which reflect
"not your turn". `creature:IsOurTurn()` itself was correct. (The "drag out
of turn blocked" note in the step-27 status is about MOVEMENT, engine-side.)

User direction (2026-09-07): keep the drawers openable so players can read
their abilities; make the CHIP press refuse off-turn under strict resource
enforcement, as it already does for unaffordable abilities.

Built (`DrawSteelActionBar/DrawSteelActionBar.lua`, `AbilityHeading`):
- `AbilityIsTurnBound(ability)`: actionResourceId is the main action,
  maneuver or free-maneuver resource, or categorization is "Move". Triggers,
  free actions, malice, respite activities are never turn-bound.
- `AbilityIsOffTurn(ability)`: turn-bound AND the initiative queue is live
  AND the chip's caster (`CasterToken()`, so the overview's re-pointed chips
  are handled) reports `IsOurTurn() == false`.
- Computed into `m_offTurn` in the `abilityInfoLabel`'s `ability` handler
  right after `SetCannotAfford`; the chip gets the class tree `offTurn` and
  the info line reads "Not your turn". `offTurn` is its own class (styled
  like `expended` in `DMHub Titlescreen/AbilityStyles.lua` on `abilityTitle`
  and `abilityInfoLabel`) so a pooled chip re-pointed at an on-turn ability
  clears cleanly.
- The strict-resources `press` gate now also refuses on `m_offTurn`
  (`(not dmhub.isDM) and strict:resources` -- Directors still bypass, as for
  the other three flags). Programmatic invokes (`invokeAbility`, triggers,
  prompts) are untouched.

Verified live 2026-09-07 in the running EotW game (isDM false, strict on,
Dwarf Fury selected between turns): every Main Action chip -- including the
Melee/Ranged Free Strike entries, which off-turn are only legal via the
trigger panel -- showed "Not your turn" in the expended colour; pressing
Brutal Slam started no cast and logged no error. Applies to any game with
`strict:resources` on, not just EotW (by design: it is action-economy
enforcement). Not re-verified on-turn (would have needed to claim a turn in
the user's live game); that path is the pre-existing one with `m_offTurn`
false.

Reload gotcha hit while testing: the file watcher logged the change and
`reload_lua` reported success, yet the mod kept compiling the committed
HEAD version (chip backtrace line numbers were 34 short). The remedy from
memory worked: set `autoreloadlua` true, rewrite the file bytes unchanged,
wait for `MOD:: READ CONTENTS FOR MOD DrawSteelActionBar`, reload, set
`autoreloadlua` back to false.

#### Players always see monster stamina bars, not amounts (DECIDED + BUILT 2026-09-07; UNTESTED)

User direction (2026-09-07, refined later the same day): in an EotW game
every player can always see the monsters' stamina BARS, but not the exact
stamina amounts. This closes the decision left open under "Player host sees
every monster's stamina bar; joiners see none" in Open Questions: with
`canControl` now elevation-aware the host presents as a player, so the only
thing standing between EVERY human and a monster's stamina bar was the
Director-only game setting `enemystambardisplay`, whose `"none"` default turns
off the `showToEnemies` rung of the `lifebar` status bar (`TokenUI.lua`
`ShouldShowElement`; the Draw Steel bar is registered in
`Draw Steel UI/DrawSteelTokenHud.lua` and the minion squad HUD in
`MCDMMinion.lua` reads the same setting).

Two entries in `g_forcedGameSettings`, written by the host through the same
`EnforceStrictRules()` path (setup on arrival, then re-asserted every host
tick):

- `enemystambardisplay = "bar"` -- the bar with no number. The setting's
  enum is `none` / `bar` / `pct` / `val`; the first build of this (earlier on
  2026-09-07) forced `"val"`, which the user corrected to bar-only. `"pct"`
  is also out: a percentage is an exact amount in disguise once the max is
  known. The one sanctioned route to a monster's exact stamina is Monster
  Info (below), which reveals it on the third kill of that monster type.
- `hpbarsonlyincombat = false` -- the bars are shown outside combat too, so
  the bar is visible from the moment the heroes arrive in the start zone
  rather than only after the map script opens initiative. Interpretation of
  "always"; flip this entry back to `true` if the pre-combat bars are
  unwanted.

Both are game-scoped, so each write replicates to every client, and neither
is editable by anyone in a player-host game (dmonly Game settings tab).
Nothing else changed: the bar's own `Calculate` already honours the
`"bar"` mode for `dmhub.isDM == false` clients.

Verify live (two clients): every monster on the map shows a stamina bar with
NO value or percentage to both the host and a joiner, before combat starts and
during it; a minion squad shows its shared squad bar.

#### Monster Info is always on (DECIDED + BUILT 2026-09-07; UNTESTED)

User direction (2026-09-07): the Monster Info feature (players progressively
learn monster stat blocks; see the top-level `MONSTER_INFO_PLAN.md`) is
automatically on in EotW games. Two more entries in `g_forcedGameSettings`,
forced by the same `EnforceStrictRules()` path:

- `monsterinfo = true` -- the feature itself: the Monster Info radial button
  replacing View Portrait on monsters, the fullscreen dialog, and the combat
  hooks. Declared in `Draw Steel Core Rules/MonsterKnowledge.lua`
  (game-scoped, dmonly), which loads in every Draw Steel game, so the id
  resolves in an EotW game.
- `monsterinfoautolearn = true` -- automatic learning from combat events
  (kills reveal stamina, roughly then exactly; ability use reveals the
  ability; and so on). Forced explicitly even though it is the setting's
  default, so a game record that was ever flipped cannot stay off. There is
  no Director in an EotW game to work the eye toggles, so without this the
  feature would reveal nothing.

Caveats: the Monster Info feature is itself NEEDS BUILD / UNTESTED (per
`MONSTER_INFO_PLAN.md`), so this is forced-on ahead of the feature's own
first live run. The Director-side reveal/hide eye toggles are `isDM` UI and
are not reachable in EotW, which is the intent. The `monsterKnowledge`
shared document lives in the game record, and EotW games are one-per-account
and destroyed on replacement, so knowledge does not carry over between weeks
(acceptable for now; revisit if cross-week persistence is wanted).

Verify live (two clients, after the Monster Info engine build): a monster's
radial menu shows Monster Info instead of View Portrait for both the host and
a joiner; the dialog opens with an unknown stat block; killing a monster type
reveals its rough stamina; the Settings > Game tab is unreachable to everyone
(player-host game) so nobody can turn it off, and the host tick re-asserts it.

#### Montage outcome: "You know the Stamina of Goblins" (DECIDED + BUILT 2026-09-19; Lua only; logic VERIFIED in the authoring game via MCP, player-view bars UNTESTED; UNCOMMITTED)

User direction (2026-09-19): a montage tier/consequence line such as "You
know the Stamina of Goblins" reveals the stamina of every Goblin monster
through the monster intelligence system: Monster Info shows the exact
number, and the token stamina bar of every goblin enemy shows the number
too (the EotW default is bar-only, see "Players always see monster stamina
bars, not amounts"). Decided the same day: the bar shows the number for
ANY exact stamina knowledge, including the third-kill reveal from
automatic learning and a Director reveal, so "the party knows this
monster's stamina" means one thing however it was learned. The seven
keyword-less Goblin X bestiary entries (Archer, Bodyguard, Deadshot,
Honcho, Lackey, Skullcrusher, Spidersmith) are out-of-date monsters and
are deliberately not covered; no name matching.

How it works:

- **Grammar** (`EncounterScript.ParseKnowStaminaClause`, called from
  `ParseClause` before the surprise-immunity rule): `you know the stamina
  of <keyword>` (also `learn`; `the party knows ...`; `each party member
  knows ...`; an optional `the`/`every`/`all`/`any` before the keyword) ->
  `{ kind = "knowstamina", keyword = "goblin" }`. The keyword is
  lower-cased and singularised (a trailing `s` is dropped unless the word
  ends in `ss`); a multi-word keyword is not a keyword and falls through to
  narrative. `DescribeEffect` / `DescribeKnowStamina`: "The party knows the
  Stamina of Goblins". Covered in `tests/encounter_script_test.lua`.
- **Matching rule**: a monster counts when its stat-block `keywords` table
  (`props.keywords`, `{ Goblin = true, Humanoid = true }`) has the keyword,
  case-insensitively. This is the Draw Steel meaning of "Goblin": in the
  shipped data it covers goblins, bugbears, hobgoblins, worgs, war spiders,
  Skitterlings and the named goblin bosses (43 visible entries).
- **Storage**: `MonsterKnowledge.RevealStaminaForKeyword(keyword, source)`
  (`Draw Steel Core Rules/MonsterKnowledge.lua`) writes
  `doc.data.keywords[keyword] = { stamina = true, source = "Montage: <entry>" }`
  into the shared `monsterKnowledge` document, NOT into `eotwscript`, so it
  is campaign knowledge like every other reveal and covers goblins that
  arrive later (reinforcements, other modules) with no enumeration of
  `assets.monsters`. `MonsterKnowledge.StaminaKnowledge(key, props)` now
  takes the creature too and answers tier 3 / exact when
  `StaminaKnownByKeyword(props)` is true, unless the Director explicitly
  hid that monster type's stamina (`revealed.stamina == false` still wins,
  matching "Director hides win"). `ClearKeywordReveals()` forgets them;
  the `/eotwmontage reset` test reset calls it.
- **Applying it**: `EncounterMontage.ApplyEffects` has a `knowstamina`
  branch that calls `RevealStaminaForKeyword` under the host elevation it
  already holds (via `rawget(_G, "MonsterKnowledge")`, so the codemod still
  loads against a core without it and logs instead of failing) and adds
  the describe line to the applied list shown on the stage.
- **Monster Info dialog**: `StaminaText` and the Director eye pass
  `ctx.props` into `StaminaKnowledge`; the line reads `Stamina 15`.
- **Token stamina bar** (`Draw Steel UI/DrawSteelTokenHud.lua` lifebar
  `Calculate`, now `Calculate(creature, token)`): for a non-Director viewer
  whose setting would give `"bar"`/`"pct"`, `MonsterKnowledge.PlayersKnowStaminaExactly(creature, token)`
  true flips `showAs` to `"val"`. Same gate in the minion squad bar
  (`MCDMMinion.lua`, the `display == "val"` branch, keyed by the squad's
  first token). `PlayersKnowStaminaExactly` takes the token when the
  caller has one because `dmhub.LookupToken(creature)` is nil for a
  locally spawned, not-yet-deployed token (seen live during this build).
- **Refresh**: `DMHub Token UI/TokenUI.lua` gained a small generic
  extension: a status bar registered with `TokenUI.RegisterStatusBar` may
  declare `monitorGame` (a path, a list, or a function returning either);
  the per-token `StatusPanel` monitors the union of them with
  `monitorGameEvent = "refresh"`, so its bars recalculate when any such
  path changes. The lifebar declares the knowledge document path (through
  `rawget`, so the generic Token UI mod still works without the Draw Steel
  mods). `TokenUI` passes the token as `Calculate`'s second argument for
  every bar (backwards compatible). A first attempt used a parentless
  file-scope `gui.Panel{ monitorGame = ... }` in `MonsterKnowledge.lua`;
  the engine's leak sweep (`SheetManager.cs`, "was created but not
  attached to a parent") DESTROYS such panels at the end of the frame, so
  that never works -- do not reintroduce it.

Verified 2026-09-19 in the authoring game over MCP (Director client):
parse -> `ApplyEffects` -> keyword record with source "Montage: Goblin
Lore"; a spawned Goblin Warrior (bestiary-keyed) reports tier 3 / visible
with `monsterinfo` on and false with it off; a Director hide on that
monster wins; `Reset` and `ClearKeywordReveals` clear it; clean load after
restart with no errors. NOT yet seen: the bar showing `15/15` on a joiner's
client (needs two clients and an EotW game), the minion squad bar, and the
Monster Info dialog line (needs the dialog opened by a player). Note the
Lua reload gotcha struck again on this build: `reload_lua` recompiled
stale content for `Draw Steel Core Rules`; `restart_dmhub` picked the
edits up.

#### Test riders: Allow / Edge / Bane requirements on a montage test (DECIDED + BUILT 2026-09-19; Lua only; parser unit-tested; VERIFIED on screen in the authoring game via the dev driver; UNCOMMITTED)

User direction (2026-09-19): a montage test should be able to carry
**riders**, each an *effect* plus a *requirement*. Effects: **Allow** (the
test can only be taken by a hero who meets the requirement -- it still
appears for everyone, locked for those who do not, and highlighted as
special, with the reason, for a hero who does) and **Edge / Double Edge /
Bane / Double Bane** (modifiers to the hero's roll). Requirements: "You
are skilled in X" (a skill), "You speak X" (a language), "You are a X" (a
class or ancestry), joinable with `or`. The motivating example, now in the
live game's script, is a third option at the Witch's cottage that only a
hero with a magic-related skill or an Elementalist can take.

**Grammar** (parsed by the pure `EncounterScript`, unit-tested in
`tests/encounter_script_test.lua`):

```
### Consult her on the arcane

|Arcana Test: Reason (Magic, Alchemy, Psionics)
|You fail at the test => ...
|You gain a small boon => ...
|You gain a large boon => ...
|Allow: You are skilled in Magic, Alchemy or Psionics, or you are an Elementalist
|Edge: You speak Caelian
```

- A rider is a `|` line after the tiers whose text starts with an effect
  word and a colon: `Allow` (aliases `Allowed`, `Require`, `Requires`,
  `Required`), `Edge`, `Double Edge`, `Bane`, `Double Bane`;
  case-insensitive. `EncounterScript.ParseRiderLine` recognizes only those
  words, so a tier line that happens to contain a colon ("You succeed:
  ...") is still a tier, and the tier loop stops counting at the first
  rider (a rider may follow a fourth tier). Stored on the roll as
  `roll.riders = { { effect = "allow"|"edge"|"doubleedge"|"bane"|"doublebane",
  text, requirement, line }, ... }`.
- A **requirement** is alternatives joined by `or` (commas and semicolons
  count as `or` too). Each alternative is one of three kinds
  (`EncounterScript.ParseRequirement`):
  - `skill`: "you are skilled in X" (also "skilled with/at", "trained in",
    "you have the X skill");
  - `language`: "you speak X" (also "you know X", "fluent in X"; a trailing
    "language" is dropped);
  - `kindred`: "you are a/an X" -- a class, a subclass or an ancestry.
  A bare name in a list inherits the previous clause's kind, so "you are
  skilled in Magic, Alchemy or Psionics, or you are an Elementalist" is
  three skills and one kindred; the bare ones are spelled back out ("you
  are skilled in Psionics") so the stage can quote them. A clause with no
  recognized verb is `unknown`, warned in `/eotwscript`, and never met.
  Names are compared normalized (`EncounterScript.NormalizeName`: lower
  case, single spaces, and a compendium "Elf, High" becomes "high elf", so
  authors write "High Elf"); a fact that ENDS with the wanted name also
  counts, so "you are an Elf" matches a High Elf.
- **Weighing** (`EncounterScript.EvaluateRiders(riders, facts)`, pure):
  every Allow line must be met (several lines AND together; use `or`
  inside one line for alternatives) or the roll is not `allowed`; each met
  edge/bane rider adds to `boons`/`banes` and lands in `applied` with the
  clause that met it; met Allow lines land in `unlocked`, unmet riders of
  any kind in `unmet`. No riders = allowed, nothing applied.

**Facts** come off the acting hero's creature in one place,
`EncounterMontage.HeroFacts(charid)`: skills via `ProficientInSkill` over
the skill table, languages via `LanguagesKnown()` mapped through the
`languages` table's names, kindred = every `GetClassesAndSubClasses()`
name plus `Race()` and `Subrace()` names. `EncounterMontage.RiderVerdict
(charid, option)` returns the evaluation (nil when the roll has no riders)
and is what the three consumers share:

1. **The host gate**: the `choose` request is refused ("ignored choose:
   <hero> does not meet '<requirement>'") when the verdict is not allowed,
   whatever a client sends.
2. **The roll launch** (`LaunchRoll`): each applied edge/bane rider becomes
   a synthetic `power` CharacterModifier (`AppendRiderModifiers`:
   `modtype` edge/double_edge/bane/double_bane, `rollType` test_power_roll,
   `activationCondition = true`) pushed onto the dialog's modifier list
   pre-ticked with the clause as its justification -- so the dialog shows
   a named chip ("Edge: You speak Caelian") next to the Skilled chip and
   the roll text reads "2d10+2 1 edge", exactly as an equipped modifier
   would. The player may untick it like any chip.
3. **The stage** (`EncounterMontageStage`, `RiderRows` + `OptionCard`):
   every rider is a line under the roll header, weighed against the hero
   standing at the entry (`m.turn.heroid`; plain grey lines when nobody
   is). An Allow rider reads "Requires: <as written>" in red while unmet
   and "Unlocked: <the clause that met it>" in violet once met; the whole
   card goes violet (`unlocked` class) when gated and allowed, or dims and
   stops being actionable (`locked` class; the press handler also ignores
   it) when not. An edge rider reads green and a bane red when it applies,
   dim grey when it does not.

VERIFIED 2026-09-19 in the authoring game (dev driver, pregens deployed
on the encounter map, `eotw:forcecustomui` on): the Dwarf Fury at the
cottage sees the arcane option locked with the red Requires line and the
host logs the refusal when a choose is injected for it; the Human Null
(Psionics) sees it violet with "Unlocked: you are skilled in Psionics",
chooses it, and the roll dialog opens with the Edge chip ticked (a
temporary `|Edge: You speak Caelian` line, removed again afterwards) and
"2d10+2 1 edge". Facts read correctly off all three pregens (e.g. the
Tactician: `high elf, tactician, vanguard`).

**Riders are a core feature now (2026-09-19, later the same day).** The user
asked for riders to work in the journal in general: a `|Edge: You speak
Yllyric` line under a journal power roll rendered as the CRITICAL tier. So
the grammar moved out of the codemod into core,
`DMHub Game Rules/TestRiders.lua` (registered through the MCP CodeMod
workflow, after Language): `TestRiders.ParseRiderLine / ParseRider /
ParseRequirement / RequirementMet / Evaluate / DescribeRows / NormalizeName`
are the pure half (still lua.exe-testable; the parser test now `dofile`s
it first), and `TestRiders.CreatureFacts(creature) / VerdictFor / 
AppendModifiers` the engine half. `EncounterScript`'s rider functions are
thin delegates (looked up at call time), `EncounterMontage.HeroFacts` and
the stage's `RiderRows` call core. The journal (`MarkdownDocument.lua`):

- the power-roll block parser keeps consuming `|` lines after the three
  tiers while they are riders (told by their effect word) or the one
  optional critical line, in either order; riders land on the token as
  `riders`, and the island height estimate counts them;
- `PowerRollDisplay` grew a rider-rows panel under the tiers (one label
  per rider, coloured by `TestRiders.DescribeRows`). In the player view the
  rows are weighed against `dmhub.currentToken`; in the Director's view
  they are plain. A player whose hero is locked out sees the roll link go
  dead (the `link` class is dropped) and the press does nothing; a player
  who earned an edge/bane gets it as a pre-ticked chip because
  `creature:RollCustomPowerTableTest` now takes a fifth `options` argument
  whose `modifiers` are appended to the dialog's list;
- the Director's "Request Rolls" path ignores riders (it requests from
  several heroes at once; per-hero weighing there is a later step).

Also fixed on the way: the journal stores a shift+enter soft break as a
VERTICAL TAB, which its own renderer treats as a newline. `EncounterScript`
now splits on it too; before, a rider typed that way rode along inside
the tier line above it and the montage never saw it.

VERIFIED 2026-09-19: the Encounter document renders "Requires: ..." under
the arcane test as a rider row (no CRITICAL badge); the user's own
`|Edge: You speak Yllyric` under the enclave test parses as a rider in
both the journal and the montage; `RollCustomPowerTableTest` with rider
modifiers opens the dialog (the Tactician does not speak Yllyric, so no
chip -- the chip itself was verified on the montage path earlier).
Player-view rendering of the coloured rows in the journal is UNTESTED
(needs a player client with a current token).

Dev-driver gap found on the way: outside an EotW game nothing writes the
stage's beat pointer (`EncounterMontage.GetDoc().data.beat`, normally
stamped by the map-script host in `EncounterOfTheWeek.lua`), so with a
narrative beat first in the script the stage rendered the (empty)
narrative surface over the running montage. Work-around used: set
`data.beat = 2` on the document by hand. Not fixed.

#### Hidden tier outcomes: a teaser before the roll, the real text after (DECIDED + BUILT 2026-09-19; Lua only; parser unit-tested; live UNTESTED; UNCOMMITTED)

User direction (2026-09-19): a montage power roll should be able to show a
player some "narrative text" for a tier BEFORE they roll, while the actual
mechanical effect stays hidden unless they land that tier. The motivating
example is the tracking test: tier 2 reads "A little wisdom" and tier 3 "A
wealth of wisdom" until the roll lands, at which point the landed tier
reveals "You learn some of the hunter's wisdom; +1 hero token." or "You
discover the writings of a fellow named Grenolf ... +1 hero token. You know
the Stamina of Goblins."

**Syntax**: an optional `=>` on a tier line splits it into
`teaser => full text`. The teaser is what players see before the roll (in
the option's tier rows on the stage and in the roll dialog's power table);
the full text is what the landed tier reveals, and it is the ONLY part the
effect grammar parses. A line without `=>` behaves exactly as today, and
lines can mix within one roll.

```
### Track the Goblins

|Tracking Test: Intuition (Track, Nature, Alertness)
|You fail at the test.
|A little wisdom => You learn some of the hunter's wisdom; +1 hero token.
|A wealth of wisdom => You discover the writings of a fellow named Grenolf who seemed rather obsessed with goblins and their anatomy. +1 hero token. You know the Stamina of Goblins.
```

Why `=>` and not the alternatives considered:

- A `|` separator (Discord-style `||spoiler||`, or a fourth cell) breaks the
  journal: `MarkdownDocument`'s tier regex is `^\|(?<text>[^|]*)$`, so any
  `|` inside a tier line stops the block being recognised as a power roll
  in the Director's journal view. Same regex in `EncounterScript`.
- A `:` separator (`Teaser: full text`) collides with Draw Steel's own tier
  prose ("Tier 1: ...", "Consequence: ...") and with the `|Name: Attr`
  header regex, which also keys on `: `. Too easy to trip by accident.
- Brackets (`|[A little wisdom] ...`) read as markdown links / islands
  next to `[[scene]]`.
- `=>` never occurs in tier prose today, reads as "leads to", is one
  greppable token for a future Python port, and renders harmlessly as
  literal text in the journal.

Split rule: the FIRST `=>` (spaces optional) splits; anything after it,
including another `=>`, is the full text. Both halves trimmed. An empty
teaser (`|=> text`) is a parse warning and treated as no teaser.

**Reveal rules** (user approved 2026-09-19, "build it with those rules"):

- Before the roll, every tier row shows its teaser (or its full text when
  it has none).
- After the roll, only the landed tier reveals its full text; the tiers
  not achieved keep showing their teaser, forever. The assist flow reveals
  the tier the assist finally shifted the test to, not the base tier.
- The critical (4th) line follows the same rule.
- The montage log / turn summary (`t.tierText`) records the full text of
  the landed tier.
- The roll dialog's power table shows teasers, so it never leaks the
  hidden text either.
- The Director's stage view shows the same thing as everyone else; the
  journal (raw `teaser => full` line) is the Director's spoiler view.

**As built** (2026-09-19, Lua only, no engine work):

- `EncounterScript.lua`: `EncounterScript.SplitTeaser(line)` splits on the
  first `=>`; the power-roll parse stores `roll.teasers[t]` (nil when the
  line has none) and rewrites `roll.tiers[t]` to the full text, so
  `ParseEffects` and everything downstream (`t.tierText`, the log) see only
  the full text. An empty teaser warns and is dropped.
  `EncounterScript.TierDisplayText(roll, t, landed)` is the one rule for
  what a viewer reads: full text when landed or when there is no teaser,
  the teaser otherwise. `/eotwscript` prints `tier N: [teaser] => full`.
- `EncounterMontageStage.lua`: `TierRows` builds each row from
  `TierDisplayText` and stamps `row.data = {roll, tier}`; `SetLandedTier`
  rewrites the text label alongside the landed/dim classes. Consequence:
  the LIVE rows during a roll reveal a teaser while the tumbling dice's
  running tier sits on it and hide it again when they move on -- the dice
  are visible to everyone anyway, so this leaks nothing the settled result
  would not. The resolved card (`TierRows(option.roll, landed, true)`)
  reveals only the final tier. The assist roll's fixed table has no
  teasers and is unaffected.
- `EncounterMontage.lua`: `EncounterMontage.TeaserTiers(roll)` feeds the
  roll dialog's `RollPropertiesPowerTable` (via `ShowMontageRoll`). No
  state change: `t.tierText` already stores the landed line.
- Tests: `tests/encounter_script_test.lua` covers the split (spaces
  optional, first `=>` wins, empty teaser warned, effects from the full
  text only, `TierDisplayText`, `AttrWithoutSkills`); 183 checks pass.
- The publisher does not port the grammar today, so nothing to mirror
  there yet; when it does, it must learn the same split.
- Flavour prose in front of a mechanical clause ("The witch is
  unimpressed. You gain one Healing Potion") still trips the
  "unrecognized effect (shown as text only)" warning in `/eotwscript` for
  the prose sentence. Harmless, but noisy now that prose is the norm;
  candidate: suppress it on lines that also carry a recognised effect.
- **The option card hides the skill list** (user direction 2026-09-19,
  built the same day, live UNTESTED): the card's roll header reads
  `Negotiation Test: Presence`, not `... Presence (Empathize, Lie, Flirt)`.
  `EncounterScript.AttrWithoutSkills` strips every parenthesised group
  from `attr`; the roll dialog's title and its Skilled chip still show the
  skills, which is where players discover them. The assist prompt is
  unchanged (assisting is about the skill).

Verify live: put a `teaser => full` line in the authoring game's script,
approach the option -- the card shows `Name: Characteristic` with no
skills, and the card and the roll dialog show the teasers; roll -- the
landed tier reveals its full text and the others keep their teaser; the
montage log line shows the full text; the effects land. Then
`/eotwmontage reset` and confirm the rows go back to teasers.

#### "Strictly Enforce Rolls" (strict:rolls) -- NEW 2026-08-29

User direction: the roll prompt was still a free editing surface. A new
game-scoped setting, `Strictly Enforce Rolls`, withdraws every affordance that
lets the roller change a result after the dice have spoken. Defined in
`DMHub Titlescreen/Settings.lua` next to the other `strict:*` settings, in the
`GameStrictRules` section.

Gate: the global `StrictRollsEnforced()` in `DMHub Utils/Utils.lua` --
`(not dmhub.isDM) and dmhub.GetSettingValue("strict:rolls")`. Deliberately
`dmhub.isDM`, NOT `IsDMOrPlayerHost()`: `isDM` is the Director-EXPERIENCE flag,
so a player host is bound exactly like any other player and only a Director is
exempt, matching `strict:resources`/`strict:targeting`/`strict:inventory`.
Sampled once per dialog in `GameHud.CreateEmbeddedRollDialog` (a fresh dialog
is built for every roll, so it cannot go stale mid-roll).

What it withdraws:

- **Re-roll.** `rollAgainButton.selfStyle.collapsed = 1` -- the selfStyle, not
  the `"collapsed"` class, because the trigger countdown's reveal
  (`rollAgainButton:SetClass("collapsed", false)`) clears that class and would
  undo it. **Accept Result then takes the whole button bar**
  (`selfStyle.width = "100%"`, `halign = "center"`; inline geometry beats the
  buttonPanel's `{button}` halign rule, same trick as `rollDiceButton`).
- **Editing the dice expression.** `rollInput` gets `editable = false`;
  programmatic `.text` writes (`CalculateRollText`) are unaffected.
- **Click-a-tier overrides.** `MCDMAbilityRollBehavior` stops putting the
  `"selectable"` class on the power-table rows (same switch the Monster AI's
  `aiDriven` already used). Clicking an **"or" alternative** in the tier text
  is untouched -- that is a legitimate ability choice and runs on the label's
  own `or:` link path.
  The **chat card's** power table offers the very same override
  (`self.overrideTier = i`, gated on the `"amendable"` class) and its own
  edge/bane amend labels, so both are closed there too -- locking only the
  dialog would leave the result editable one panel over.
- **Modifier chips.** Only the modifiers that actually applied are listed
  (unchecked ones `goto continue` out of the build), and the rest are
  read-outs: `ModifierPanel{readOnly = true}` drops the `press` handler and
  the `"hoverable"` class while keeping the linger tooltip.
- **The edge/bane bar.** `boonBar:MakeNonInteractiveRecursive()` after it is
  assembled -- recursive because `interactable` does not cascade; this covers
  the five entry boxes and the reset arrow at once, and takes their hover
  highlight with it.
- **Backing out of a committed cast.** The ability card's close (X) and ESC are
  refused once `options.pay` is set (`ActivatedAbility:CommitToPaying`) -- the
  cost is already spent, so a cancel there is a free undo.
  `CharacterPanel.AcquireAbilityRollDialog` stashes the cast's options on the
  dialog as `data.castOptions` (the close X lives OUTSIDE the dialog's
  subtree, so it has no other way to see them), and both affordances go
  through `RollDialogCancelOffered(dialog)` in Utils. The button polls it on a
  0.25s think -- `pay` is set deep inside the cast coroutine with no hook to
  listen to -- which is self-terminating, since a collapsed panel stops
  thinking and `pay` is never unset. `dialog.data.Cancel()` itself is
  deliberately NOT guarded: `restoreFromBackup`, the request-rolls cleanup and
  the roll-table cleanup call it directly and must always work.

Deliberately left alone: the **"Re-roll for 1 Intel"** button (a sanctioned
re-roll with a resource cost, behind `dev:trackintel`; it still fires the
collapsed Re-roll button's press event, which works because collapsed panels
still receive programmatic events), the **after-roll modifiers panel** (those
are real post-roll player choices, e.g. spending to boost), the **surges bar**,
and the **multicost "Charges" input** -- all spend decisions, which is
`strict:resources`' domain rather than this one. Revisit if any of them turns
out to be a cheat vector in play.

Also 2026-08-29: the engine's **"Strictly Enforce Movement Rules"** row now
renders with the other rules-enforcement toggles. It is registered by the
engine (`Assets/CoreAssets/Lua/settings.txt`) in the plain `"Game"` section, so
`Settings.lua` re-homes it with a single `Settings["strictmovementrules"].section
= "GameStrictRules"` write rather than duplicating the definition -- `setting{}`
stores the info table by id and the settings screen reads `.section` off it, so
the engine's description, help, default and ordinal are untouched. Lua-only; no
engine build needed.

**SUPERSEDED CAVEAT (2026-08-29)**: as originally built, the settings were on
but did not bind the HOST -- every consumer gates on `(not dmhub.isDM)` and
the host kept real DM status (user confirmed live: strict mode enforced for a
player, not for the host). Resolved by **player-host mode** (see the
"Player-host mode" section above): with `dmhub.playerHostMode` armed the
host's `dmhub.isDM` reads false, so the same gates -- deliberately left
reading `dmhub.isDM` -- now bind the host too, while the Monster AI's
capability paths read `IsDMOrPlayerHost()`. Needs the engine build; on an
old engine the host remains exempt (the pre-2026-08-29 behavior).

### Hero Tokens at the start of the session (DECIDED + BUILT 2026-09-18; UNTESTED)

User direction (2026-09-18): at the start of an EotW session the players get
Hero Tokens equal to the number of heroes in the party -- the Draw Steel
per-session award, which in a normal game a Director hands out and which an
EotW game has nobody to do. One EotW game IS one session, so the pool is
seeded once, at setup.

- `SeedHeroTokens(numHeroes)` in `EncounterOfTheWeek/EncounterOfTheWeek.lua`
  (next to the other host-only setup helpers), called from the host's
  `SetupOnArrival` block immediately after `numHeroes` is resolved and the
  `numheroes` setting written -- so the party count the tokens follow is the
  same one the encounter scales to. `numHeroes` is the lobby's filled-slot
  count (clamped 3..7), i.e. one token per hero.
- It writes the shared pool through
  `CharacterResource.SetGlobalResource(CharacterResource.heroTokenId,
  numHeroes, "Start of the session")` -- the same `globalResourcesv2` mod
  document the character panel's Hero Tokens box, the roll dialog's Hero
  Token re-roll rule, and the hud's Encounter pools strip all read. Hero
  Tokens are NOT `clearOutsideOfCombat`, so seeding before combat sticks;
  players see the strip already showing the party's tokens while the montage
  plays, and montage tests can spend them.
- **Seeded once**: `heroTokensSeeded` in the `eotwstate` doc. A resume, or
  the host reconnecting and running setup a second time, must not refund
  tokens the party has already spent. A game whose `combatStarted` is stamped
  is skipped outright, which also keeps a game that launched before this
  existed from being topped up mid-encounter on a resume. `ClearEotwMarker()`
  clears the stamp along with the rest of the dev marker state.
- The resource write is pcall-guarded and stamps only on success: a failed
  write leaves the seed pending rather than silently costing the party its
  tokens, and cannot take down the rest of the host's setup coroutine
  (`AttachMapScript`, `SignalGameReady`).
- Not decided: whether anything re-awards tokens later (the Director's
  "reward a token for good play" beat has no EotW equivalent yet), and
  whether the post-encounter flow should clear the pool.

### Victory/defeat auto-detection, player Proceed, and auto-exit (DECIDED + BUILT 2026-08-28)

User direction (2026-08-28): the game detects the encounter's victory/defeat
conditions itself, triggers the victory/defeat screen, players (not just the
Director) can press Proceed, and after Proceed everyone is returned to the
Codex titlescreen.

- **Detection (host map-script tick, while the queue is live)**: if
  `live:GetAwardedOutcome()` is nil, evaluate victory =
  `live:CheckVictory()` (the existing evaluator: all seven authored conditions
  plus encounter-script overrides, pending reinforcements included) and defeat
  = `live:CheckDefeat()` (script-declared) OR every hero DEAD, via the
  EotW-local `CountLivingHeroes(queue)` (heroes in the queue with
  `not props:IsDead()`). **Dying heroes count as living (DECIDED
  2026-09-07)**: the original build used `live:CountLiveCombatants()`,
  which counts `CurrentHitpoints() > 0`, so an all-dying party read as a
  defeat -- wrong for Draw Steel, where a dying hero still takes turns and
  can win. `CountLiveCombatants` itself is untouched (the core victory
  conditions use it). Award = set
  `live.victoryAwarded`/`defeatAwarded` + `dmhub:UploadInitiativeQueue()` --
  exactly what the initiative bar's Award Victory button does. The existing
  `DSVictoryScreen` (mounted on every client, monitoring `/initiativeQueue`)
  then shows the victory/defeat screen everywhere with hero cards, roles, and
  the defeat backdrop; no new broadcast mechanism.
- **The award waits for ability prompts (ADDED 2026-08-28 after the first
  live run: the victory screen appeared mid-ability-prompt)**. The killing
  blow usually lands mid-ability, with the caster's roll dialog / follow-up
  prompts still open -- and those prompts are LOCAL to the caster's client,
  invisible to the awarding host. So every client mirrors "I have ability
  activity in flight" into the state doc (`abilityBusy[userid] =
  serverTime`, written from the 1s driver on transitions plus a 5s
  keep-alive while busy, cleared when idle; host ignores stamps older than
  15s so a crashed client cannot hold the award hostage). The per-client
  predicate `AbilityActivityInFlight()` composes exactly the primitives the
  codex already trusts (the invoke pipeline's wait, `MonsterAI:
  WaitForAbilityIdle`, the death gate): live cast coroutines
  (`ActivatedAbility.CountActiveCasts` -- on the host this covers Monster AI
  casts), action-bar targeting (`actionBarPanel.data.IsCastingSpell()`,
  tested TRUTHY -- the two bars return different types), all three roll
  surfaces (`CharacterPanel.AnyRollDialogShown`), open modals
  (`gui.GetModal`), and unanswered non-hostile trigger/invocation prompt
  cards on controlled creatures (`GetAvailableTriggers(true)`; hostile
  prompts never age out and must not block). The host awards only when the
  condition is met AND nobody is busy (its own state checked live, remote
  clients via fresh stamps) for 2 consecutive host ticks
  (`AWARD_HOLD_TICKS`) -- the hold lets the fight visibly settle and lets a
  just-started prompt's stamp replicate.
- **The banner lingers a beat after the killing blow (ADDED 2026-08-31, user
  direction: "wait a moment longer before the banner")**: alongside the idle
  hold, the host stamps `m_outcomeMetTime` the first tick the outcome
  condition reads met (busy or not) and refuses to award until
  `OUTCOME_LINGER_SECONDS` (5) have passed since that stamp. The two waits
  run CONCURRENTLY: a fight whose final prompts take longer than the linger
  pays no extra delay, while an instantly-settled fight now breathes ~5-7s
  before the screen takes over (vs ~2-4s before). Reset whenever the
  condition reads unmet; `math.abs` on the elapsed check so a serverTime
  rebase releases the wait rather than wedging it. UNTESTED live.
- **Player Proceed (core hook)**: `DSVictoryScreen.RegisterProceedOverride{
  canProceed, proceed, holdUntilLocalProceed }` in `Draw Steel UI/DSVictoryScreen.lua`.
  Proceed-button visibility becomes `dmhub.isDM OR canProceed()`
  (pcall-guarded); the click runs `proceed(ProceedEndCombat, alreadyEnded)`
  first and only falls through to the normal Director teardown when the
  override declines. `ProceedEndCombat` is also exported as
  `DSVictoryScreen.ProceedEndCombat` for the host-side automation.
- **The screen is dismissed PER CLIENT (DECIDED 2026-09-08, user: "it
  shouldn't proceed until I'm ready under any circumstances")**. The shared
  queue drives the screen's SHOWING, but never its closing in EotW: while the
  override's `holdUntilLocalProceed()` returns true, `checkVictory` reacts to
  the outcome leaving the queue by flagging the screen `held`
  (`rootPanel.data.held`) instead of hiding it -- the cards are already
  built, so the dead live encounter is not needed. Proceed on a held screen
  calls `proceed(ProceedEndCombat, true)` (nothing to tear down or relay) and
  hides locally; its tooltip drops the "for everyone" wording. A new outcome
  landing on a held screen re-shows fresh. Normal Director games register no
  override and are unchanged. This resolves the 2026-09-07 policy question
  (one player's Proceed used to end the screen for everyone): another
  client's Proceed still tears combat down for the game, but each client's
  screen and exit wait for that client's own press.
  The Victories award section's visibility gate converts `dmhub.isDM` ->
  `GameHud.DirectorUIVisible()` (identical in normal games; hidden in EotW for
  everyone including the host, per the no-Director presentation).
- **EotW override**: when `IsEotwGame()`, everyone may press Proceed. The HOST
  pressing runs the normal full teardown directly (battle log +
  `encounter_complete` analytics + role history are `dmhub.isDM`-gated and must
  run on the host). A PLAYER pressing stamps `proceedRequested` into the
  `eotwstate` doc; the host tick (which is already watching the awarded
  outcome) sees it and runs `DSVictoryScreen.ProceedEndCombat()` -- worst case
  ~2s latency before combat is torn down. If the host client is gone, the
  request sits until the host returns (same accepted class as the other
  host-crash edges). Every press (host or player, held or not) first sets the
  module-local `m_localProceeded`; `holdUntilLocalProceed` returns
  `IsEotwGame() and not m_localProceeded`, so the presser's own screen closes
  with the queue as normal while everyone else's stays held.
- **Auto-exit to the titlescreen**: each client's 1s driver latches "outcome
  seen" while the queue is live with an awarded outcome; when the queue has
  hidden/disappeared (combat torn down) AND the local user has pressed
  Proceed (`m_localProceeded`), it schedules `dmhub.LeaveGame()` once, ~4s
  out (covers the victory screen's 0.7s fade plus the 1-3s GameDetails write
  coalescing so the host's battle-log/queue writes flush before the socket
  closes). Each client leaves on its own press, host included, landing on the
  titlescreen -- the existing post-leave flow (stale-screen sweep, resume
  row, no auto re-entry) already handles the arrival. Clients that never saw
  an awarded outcome (a combat ended via the Director escape hatch, or a
  mid-join) do NOT auto-exit. `dmhub.LeaveGame` is deferred via
  `dmhub.Schedule` because it synchronously unloads the calling codemod.
  A client still sitting on its held screen after the host has exited and
  its titlescreen has wiped the game is fine: `DOConnection` treats the
  server's `game-deleted` close as "stop reconnecting" and the client stays
  in place, so the held screen survives until its own Proceed (verified in
  `DataStoreDurableObjects.cs`; UNTESTED live).
- **Finished-game cleanup (ADDED 2026-08-28 after the first live run: the
  game lingered in the lobby list and the account slot after everyone
  exited)**. Two causes: nobody ever told the lobby the game was over (and a
  returning member's EotW screen HEARTBEATS every game it occupies on its 30s
  think, keeping the roster record alive past the 5-minute TTL forever), and
  the finished game still sat in the eotw account slot offering Resume. Fix,
  both halves at conclusion time:
  - **Game-side (before exiting)**: every client stamps the finished gameid
    into the machine-local preference `eotw:concludedgame` and sends a lobby
    `leave-game` over a transient connection (`SendLobbyRequest`, the
    generalized SignalGameReady plumbing). The HOST's leave drops the roster
    record + its chat for the whole lobby immediately; members' leaves remove
    their membership so their returning screens stop heartbeating it.
    Best-effort: if the send loses the race with `LeaveGame` (~4s), the
    titlescreen half re-sends it.
  - **Titlescreen-side**: `RefreshResumeState` (runs on every screen open)
    reads `eotw:concludedgame`; when set it clears the preference and runs
    `DestroyPreviousGame(gameid)` -- on the host's machine that deletes the
    game and releases its Durable Object, on a member's machine it degrades
    to Leave -- and both clear the eotw account slot, so no resume row and no
    stale roster row. The setting is declared in both files (settings are
    keyed globally by id).
  Degraded worst case (host crashed before stamping): the record expires via
  the normal 5-minute TTL once members' leaves land, and the host's next
  screen open still shows the resume row with Abandon.

### Dead heroes leave the battlefield (DECIDED + BUILT 2026-08-30; kill-path UNTESTED)

User direction (2026-08-30): when a hero dies in an EotW game (truly dead,
stamina at -winded -- not merely dying), once all their triggers are resolved
they are removed from the battlefield exactly like a monster is.

**Mechanism: a module-shipped global rule, no code.** The core Monster Death
rule (`data/objectTables/globalrulemods/monster-death.yaml` in mcdm-drawsteel)
is a `GlobalRuleMod` -- a row in the `globalRuleMods` table with a
`creaturedeath`-triggered ability that delays, waits out "Cannot be Removed",
and runs `ActivatedAbilityRemoveCreatureBehavior`. Global rules apply to every
matching creature in any game whose merged table holds the row
(`GlobalRuleMod.GetActiveRuleMods` walks the whole table;
`creature:FillBaseActiveModifiers` gates on the apply* flags). So a rule
shipped inside `mcdm-encounteroftheweek` applies in exactly the games that
install the module -- EotW games and the authoring game -- which is the
scoping the mode wants, with zero Lua.

**The rule**: `C:\dev\eotw\objectTables\globalrulemods\hero-death.yaml`
(id `a011c97a-b8d4-4f35-98a0-6ffb9f5a5993`, plus the folder's `_meta.yaml`
declaring table id `globalRuleMods` -- the folder name alone is unreliable,
it gets lowercased). Modeled on Monster Death with these deliberate deltas:

- `applyCharacters: true`, everything else false (Monster Death is the
  mirror image). Companions/retainers keep the normal rules.
- Trigger `creaturedeath` fires only on the alive->dead transition
  (`MCDMCreature.lua` TakeDamage + SetStaminaDirect), and for characters
  `KillThresholdStamina` is `-BloodiedThreshold` -- so dying heroes are
  untouched; only true death removes.
- `mandatory: local`: resolves automatically on the client that processed
  the killing damage, never prompts, never dispatches remotely.
- Delay `1 + DelayDeath` then proceed on `Cannot be Removed = 0` (same
  escape valves as monsters: the delay behavior's 120s backstop applies).
- `waitForTriggers: true` on the remove behavior -- the removal waits for
  the hero's pending non-hostile trigger prompts AND any executing casts to
  finish (this is the "once all their triggers are resolved" requirement);
  `waitForAbilitiesToFinish` (default true) additionally waits out other
  in-flight reaping casts.
- `leavesCorpse: true, dropsLoot: false`: a corpse object with the death
  message drops, but hero inventory does not spill (unlike monsters).
- `filterTarget: target.dead` re-checks at removal time, so a hero revived
  during the delay window is spared.

**Safety already in core**: `ActivatedAbilityRemoveCreatureBehavior:Cast`
never hard-deletes an owned, non-summoned hero -- it sets
`token.despawned = true` (the H5EEEYHX guard), the same removal a monster
gets, keeping the character record intact. Defeat detection is unaffected:
`LiveEncounter:CountLiveCombatants` counts `CurrentHitpoints() > 0`, and a
dead hero contributes zero whether despawned or not.

**Victory screen shows removed heroes anyway (ADDED 2026-08-31)**: a
despawned hero drops out of the initiative queue's token resolution, so
`LiveEncounter:GetBattleHeroTokens` (core, `MCDMEncounter.lua`) now merges
in onset heroes the queue no longer resolves, via `dmhub.GetCharacterById`
(finds despawned tokens anywhere in the game) -- mirroring what
`GetMonsterGroups` already did for despawned monsters via the onset
snapshot. Everyone who STARTED the encounter (hero or monster) therefore
gets a stats/role card at the end regardless of survival, and the
all-heroes-dead defeat no longer loses its battle-log record (it used to
bail on `#heroTokens == 0`). Stats and role history key off charid, so
nothing else changes.

**Publisher change** (`tools/eotw_publish/publish_eotw.py`): global rules
apply by existing, not by being referenced, so the dependency pass could
never pull one into the payload. After `build_seed`, every `globalRuleMods`
row in the (overlaid) game assets that is not hidden and not already
provided by Core/mcdm-drawsteel or an installed module is now seeded
(reason `global rule ("<name>")`). Core's own rules in the codex data tree
stay excluded via `core_guids`, so only EotW-authored rules ship.

**Verified live (authoring game, this machine)**: the local-assets watcher
picked the YAML up without a restart; the row deserializes as a
`GlobalRuleMod` with both behaviors typed; a hero (Human Censor) carries the
"Hero Death (Encounter of the Week)" trigger modifier via
`GetActiveModifiers` while a monster does not. **Shipped in module version 7
(2026-08-31)** -- the seeding pass picked it up as
`global rule ("Hero Death (Encounter of the Week)")` and the published
payload carries the `globalRuleMods` row. **Kill path exercised live
2026-09-06** (game `BroadEnormousVigorousSalorna`, an Orc Conduit killed on
its own turn): the rule fired and the hero was despawned (`despawned=true`,
stamina -12), and the queue kept its entry -- which exposed the orphaned-turn
lock below.

#### Dying on your own turn: the orphaned-turn lock (ROOT-CAUSED + FIXED 2026-09-06; Lua live on disk, UNTESTED end-to-end)

Report (2026-09-06): a Conduit died during their own turn; the Hero Death
rule removed them from the battlefield; the bubble then read "Hero Turn" with
no way to proceed, and the game was locked.

**Mechanism.** The initiative entry outlives the token. `ShouldShowEndTurn`
(`MCDMInitiativeBar.lua`) resolves the current entry to tokens via
`GetTokensForInitiativeId`, which reads `dmhub.allTokens` /
`dmhub.GetTokenById` -- both exclude despawned tokens -- and shows End Turn
only if the user controls one of them, else falls back to
`GameHud.DirectorUIVisible()`. A removed hero resolves to zero tokens, nobody
controls a token that is not there, and in an EotW game nobody has Director
UI, so no client could end the turn. `IsPlayersTurn()` was still true (the
entry is a player entry), hence "Hero Turn". Monsters never hit this: the
Monster AI advances its own turn after `WaitForAbilityIdle`, and a Director
always sees End Turn. Two dead monster groups in the same game sat with
zero-token entries harmlessly because they were not the current turn.

**Fix (both halves are core, not EotW-specific):**

- *Auto-end on removal* -- `ActivatedAbilityRemoveCreatureBehavior:Cast`
  (`DMHub Game Rules/AbilityRemoveCreature.lua`) records each removed
  creature's initiative id and, after the removals, calls the new
  `ActivatedAbilityRemoveCreatureBehavior.EndTurnIfEntryEmptied`: scheduled
  0.2s later (so the engine token list has dropped the token), it re-checks
  the live queue -- current turn is one of the removed ids, and that entry
  now resolves to no valid non-despawned token -- and then runs
  `GameHud.instance:NextInitiative` + `UploadInitiativeQueue`, exactly what
  the End Turn button does. Exactly one client runs it because the Hero
  Death rule is `mandatory: local` (the client that processed the killing
  damage). If the turn already moved on (e.g. the AI advanced after its own
  monster fell) it is a no-op; `NextInitiative`'s
  `g_betweenTurnTransitionInProgress` guard covers the race the other way.
  This also applies in Director games when a removal wipes the current
  monster group mid-turn -- the Director no longer has to click End Turn for
  an empty entry.
- *Safety net in the bubble* -- `ShouldShowEndTurn` returns true when the
  current entry resolves to zero tokens and `CanControlInitiative()` (which
  every EotW player passes via `permission:playersinitiative`), so an
  orphaned turn from any cause can be closed manually by anyone allowed to
  run initiative. This is the "End Turn when ready" half of the user's ask;
  the auto-end is the default behaviour.

**Manual recovery** for a client running older code: the host toggles
`/toggle eotw:showdirectorui` (restores Director UI, so End Turn appears), or
over MCP on any client in the game:
`GameHud.instance:NextInitiative(function() dmhub:UploadInitiativeQueue() end)`
-- this is how the 2026-09-06 game was unlocked (the queue went back to
choosing a turn with the three surviving heroes able to claim).

**Gotcha hit while deploying**: the git-folder FileSystemWatcher for both
mods was dead (the known Deploy-Changes watcher kill), so `reload_lua`
reloaded 11 mods but not these two. Remedy: `code.GetMod(id).checkedout =
true` for `34c17de9-...` (DMHub Game Rules) and `9000946e-...` (Draw Steel
Core Rules), rewrite the file bytes, confirm `CodeMod: Local file changed` in
Player.log, then reload.

### Custom interface: usurping the game hud (DECIDED + BUILT 2026-08-28)

User direction (2026-08-28): the core app gains hooks for a mod to enforce a
**custom interface** -- the titlebar remains (items suppressible/addable),
the side icon rails are replaceable with mod widgets, and EotW uses it: no
side buttons, no "Panels" menu, no Compendium access, and a hero roster on
the right edge (it started on the left; moved 2026-08-29, user direction).

**The core hook** -- `GameHud.RegisterCustomInterface{...}` in
`DMHub Core UI/Hud.lua` (right after `RegisterDirectorUIFilter`, same
pattern). A provider table: `id` (stable string; consumers watch it to
detect takeovers), `active()` (first registered provider whose active() is
true wins), and optional fields `suppressRails`, `railPanel(side)`,
`suppressTitlebarMenu` (set|fn by menu NAME), `titlebarPanels()`,
`suppressPanel` (set|fn by panel NAME), `suppressSearchBucket` (set|fn by
bucket id), `characterPanelAccess(token)` -> "edit"|"view"|"none"|nil.
Every consumer read is pcall-guarded; a broken provider degrades to the
normal interface. Consumers wired in core:

- **Icon rails** (`DocumentSystem/DocumentSystem.lua`): a takeover
  (`PanelDocument.RailCustomInterfaceId()`, new) forces `RailModeActive()`
  true regardless of the iconrail setting (docks slide away, windows host
  on the layer), and `BuildIconRails` mounts per-side wrapper panels
  holding `railPanel(side)` widgets instead of the button columns, plus an
  optional BOTTOM-corner wrapper per side from `railBottomPanel(side)`
  (stored as `g_iconRails["leftbottom"/"rightbottom"]`; valign bottom,
  setRailScale pivots on the bottom corner so Font Size zoom keeps it
  pinned). The wrappers reuse the `iconRail` class + `g_iconRails` slots
  so every lifecycle path (destroy, stale-generation sweep, theme recolor,
  fontsize-zoom via setRailScale) works unchanged, carry `IconRailStyles()`
  so provider widgets can use the native iconRailButton/iconRailIcon/
  iconRailActiveMark classes, and fire `refreshRail` tree-wide on their
  0.5s think (the standard rail cadence -- unread badges, lit states).
  The left top wrapper is also registered as the chat listener
  (`chat.events:Listen`) with the real rail's `slash` ->
  `RailSlashOpensChat` and `refreshChat` -> `ChatBubbleNotify` handlers,
  so "/" still summons chat during a takeover (the speech bubble bails
  harmlessly -- it needs a slotted chat button to anchor on). Both rail
  kinds watch `RailCustomInterfaceId` on their 0.5s think and swap via
  `PanelDocument.RailCustomInterfaceRebuild()` (DestroyIconRails +
  EnsureIconRail, deferred) when the mode flips mid-session -- so the
  takeover engages even though the EotW state doc may identify the game
  only after EnterGame built the normal rails. Docks are hidden with the
  `offscreen` CLASS only (`SyncDocksOffscreenForCustomInterface`), never
  the dock settings -- SyncDocksToRailMode writes settings and would
  permanently trample the user's dock layout. A takeover restores NO
  pinned/popped windows (the custom interface owns the screen); orphaned
  windows from a previous Lua generation are still swept. NOTE: new
  DocumentSystem cross-function helpers are `PanelDocument.*` fields, not
  locals -- the file's main chunk runs near the 200-local ceiling.
- **Titlebar** (`Codex Titlescreen/CodexTitleBar.lua`):
  `CreateCodexMenuItem` wraps `calculateVisibility` (the 200ms broadcast):
  suppressed items collapse -- via a `customInterfaceHidden` class rule for
  items with no own calculateVisibility (so the mainmenuOnly/ingameOnly
  class rules stay in charge otherwise), and by overriding
  `selfStyle.collapsed` after running the item's own calc for those that
  have one (Developer, Adventure Documents). A `customInterfaceTitlebarItems`
  host panel (after the Feedback menu) rebuilds its children from
  `titlebarPanels()` whenever the active interface id changes.
- **Panel registries**: `DockablePanel.PanelPermittedForUser` checks
  `CustomInterfaceSuppressesPanel(p.name)` (covers Panels menu, toolbar,
  rail, search harvest for dockables); `LaunchablePanel` is ENGINE core Lua
  (`Assets/CoreAssets/Lua/game-hud-menu.txt`) and was NOT touched -- the
  Compendium's own `filtered` registration (`DMHub Compendium/
  Compendium.lua`) checks the hook instead, which removes it from the
  Codex menu, the hud toolbar, and the search apptools bucket.
- **Search** (`DMHub Utils/Utils.lua` `Search.CollectProviderResults`):
  providers whose `bucket` is suppressed are skipped -- this kills the six
  compendium-bucket providers (compendium-content, glossary,
  treasure-items, class features, monsters, monster-abilities) that bypass
  the menus. Verified live: 65 "goblin" results with the interface off, 0 on.
- **Character panel** (`DMHub Core Panels/CharacterPanel.lua`
  `TokenAccessLevel`): the `characterPanelAccess(token)` override runs
  before the normal canControl/partymembercontrols rules; "view" produces
  the existing readonly-class panel (55 TacPanel edit gates + editOnly
  chrome collapse + sheet button blocked).

**The EotW hud** (`EncounterOfTheWeek/EncounterOfTheWeekHud.lua`, new file,
registered in the EotW codemod at position 2 after EncounterOfTheWeek.lua):

- Provider: active when `IsEotwGame()` (the `eotw:showdirectorui` escape
  hatch restores the FULL normal interface), or when the new hidden dev
  toggle `/toggle eotw:forcecustomui` is on (iterate in any game without
  launching a real EotW game -- flips take effect within ~0.5s).
- Suppresses: rails (both sides), the "Panels" titlebar menu, the
  "Compendium" panel, the "compendium" search bucket.
- **Kept buttons: Journal, Chat and Action Log survive in the
  bottom-left corner** (Chat + Action Log by user direction 2026-08-28;
  the Journal button added 2026-08-30, user direction -- players need the
  encounter's briefing/handout documents, and with the rails suppressed
  there was no way in. It sits ABOVE the other two: the strip is a
  vertical flow, so the list order `{"Journal", "Chat", "Action Log"}` is
  top-to-bottom. Nothing else was needed -- the Journal panel is already
  `dmonly = false`, so a player could always open it on a normal rail;
  the takeover was the only thing hiding it.)
  `railBottomPanel("left")` returns a strip
  of rail-style buttons (`CreatePanelButton`): 40px iconRailButton look
  (the wrapper's IconRailStyles makes the classes native), the panel's
  registered icon, its unread badge (hasNewContent/newContentCount/
  markContentSeen on the refreshRail cadence, the real button's recipe),
  the active underline while the window is up, and the real open path
  (`DockablePanel.LaunchPanelByName(name, "toggle")` -> the rail's open
  handler -> a normal rail window). Chat and Action Log share a window as
  tabs exactly as on the real rail. Verified live via the force toggle:
  buttons render bottom-left, chat opens with input focused, active class
  lights, action log opens tabbed, toggle closes, zero errors. The
  Journal button was verified the same way 2026-08-30: it renders as the
  top button of the strip, opens a normal rail window showing the
  document tree (My Private Documents / Shared Documents), lights its
  active underline, the hover tooltip reads "Journal", a second click
  closes it, and the console shows no new errors across the whole
  sequence.
- **Hero roster** on the right edge (REDESIGNED 2026-08-28, user
  direction: portraits ARE the card; moved from the left edge 2026-08-29,
  user direction -- `railPanel(side)` now answers for `"right"`, and the
  cards `halign = "right"` so the column packs against that edge. The
  kept rail buttons stay in the bottom-LEFT corner, where the real
  rail's live): one card per party hero
  (`dmhub.allTokens` + `IsHero()` -- the same enumeration combat entry
  uses; NOT `Party.GetPlayerCharacters()`, which drops blank-named
  tokens, see "An unnamed hero vanished from the montage") --
  132x176 (3:4), the portrait full-bleed as the card's own bgimage
  (bgcolor white so art is untinted; `GetPortraitRectForAspect(0.75)`
  crop; dark plate fallback while art is missing), cornerRadius 8. The
  bottom third is a floating semi-opaque overlay (58px, #000000c0;
  blue-tinted for own heroes) holding the name, a real STAMINA BAR, and
  the heroic-resource icon + value. The stamina bar (refined 2026-08-28,
  user direction): 14px tall, theme `bordered` track whose border AND
  fill track healthy/winded/dying via @success/@warning/@danger (the
  HealthFill tint rules copied into the roster styles), a glossy VERTICAL
  grayscale gradient on the fill (tinted by the state color, overriding
  the global fillBarFill shade), the cur/max numbers centered in white on
  the bar ("+N" appended while temp stamina is up), and an @accent
  temp-stamina segment riding the end of the fill. Heroic resource: the
  class's `heroicResourceIcon` (`GetClass():try_get("heroicResourceIcon")`,
  hidden if absent) with its value, tooltip on linger. SURGES (user
  direction): no default readout at all -- one `game-icons/surge.png`
  icon PER available surge in the card's bottom-right corner, nothing
  when the hero has none (display capped at 9 icons). No card hover
  tooltip (removed, user direction). Recoveries not shown (the popped
  panel carries them). CONDITION ICONS (resized + moved 2026-08-29, user
  direction) float over the artwork in the card's TOP-RIGHT corner -- they
  used to center across the top on small chips. Each is a 26x26 chip
  (`CONDITION_CHIP_SIZE`), `#000000cc`, cornerRadius 6, with a 2px red
  (`#cc2222ff`) border, holding the 18x18 condition icon
  (`CONDITION_ICON_SIZE`), tooltip on linger. The row is a floating
  `halign = "right"` wrap container inset 4 from the right edge, and every
  chip carries `halign = "right"` itself: the flow layout right-packs the
  TRAILING run of `halign="right"` children against the right edge in
  order (`SheetPanel.LayoutChildrenInternal`), so all-right children pack
  right without losing order -- the same trick the surge corner uses. The
  fixed `CARD_WIDTH - 8` container width is what keeps `wrap` meaningful
  for a heavily-conditioned hero (about 4 chips per row); surges live in
  the opposite (bottom-right) corner, so the two never collide.
  Own heroes (strict
  `ownerId == dmhub.loginUserid`, NOT canControl -- the host controls
  everything) sort first, spaced tighter, with a 2px blue border vs 1px
  dark; a 16px gap separates the groups; hover = brightness lift.
  Refresh: 1s think + `/characters` monitor; cards rebuild only when the
  roster signature changes.
- **The roster auto-shrinks to fit** (2026-08-29, user direction: "make it
  auto-scale down once it can't fit in the screen, if there are lots of
  heroes"). A seven-hero column is ~1283 units tall against ~972 of usable
  layer height, so at full size it would run off the bottom. `FitToScreen`
  writes `selfStyle.uiscale = budget / contentHeight` (clamped to <= 1,
  floored at 0.4 -- below that the cards are unreadable and clipping is
  the better failure) with `pivot = {x = 1, y = 1}`, so the column shrinks
  toward the top-RIGHT corner it hangs from. This is the same render-time
  zoom recipe the rail roots use for the Font Size zoom; card layout and
  font sizes inside are untouched, they just render smaller.
  - `contentHeight` is **accumulated exactly as the cards are built**
    (`CARD_HEIGHT` + that card's own margins: +4 own, +19 for the first
    other hero's group gap, +6 for later ones) rather than measured --
    `renderedHeight` is pre-uiscale and would feed back into itself.
  - The budget (`RosterHeightBudget`) is the documents layer's
    `renderedHeight` (~1048 units, NOT 1080 -- measured the way
    `IconRailUIHeight` does, falling back to 1048) less the rail's top
    inset and a 12-unit bottom gap, divided back out of
    `PanelDocument.WindowUIScale()` because the wrapper already renders at
    that zoom. The top inset duplicates `IconRailTop()`'s
    `max(64, (40 + 12) * zoom + 12)` -- both are file locals in
    DocumentSystem, so the constants are mirrored, not shared.
  - It is re-evaluated on every 1s `Refresh` (the budget moves on window
    resize and Font Size changes, neither of which touches the roster
    signature) and force-re-applied on the rail wrapper's first
    `refreshRail` tick, which is the first moment the column is certainly
    attached to the layer -- a pivot write needs an attached panel.
    `selfStyle.uiscale` is write-only; never read it back.
- **Encounter pools strip above the roster (DECIDED + BUILT 2026-09-15,
  user direction: "add a new panel which displays both monster malice as
  well as hero tokens" above the hero panels)**. `railPanel("right")` now
  returns `CreateRightRailPanel()` -- a vertical container holding
  `CreateEncounterPoolsPanel()` above `CreateHeroRosterPanel()`, so both
  live in the same right-rail wrapper. The strip is card-width (132) by
  `POOLS_HEIGHT` (40), the roster overlay's dark plate look (`#000000c0`,
  cornerRadius 8, `bgimage = "panels/square.png"` -- a plain panel paints
  no background without one), two 50% `borderBox` cells: the Malice cell
  (the action bar's `costDiamond`/`costInnerDiamond` malice diamond from
  `Styles.ActionMenu`, 18px, rotated 135, inside a 26x26 slot so the flow
  does not measure the unrotated box) and the Hero Tokens cell
  (`drawsteel/hero-token.png`, 20px), each followed by the count in 16px
  bold white. Values: `CharacterResource.GetMalice()` and
  `CharacterResource.GetGlobalResource(CharacterResource.heroTokenId)`
  (both pcall-guarded, labels only rewritten on change). Refresh: the
  strip monitors `CharacterResource.GlobalResourcePath()` (both pools live
  in the shared global-resource document) plus a 1s think, which covers
  malice reading as 0 outside combat without the document changing.
  **Read-only for everyone** (strict rules: malice is spent by the Monster
  AI, hero tokens through the game's own flows; no +/- and no typed edit
  -- flag if the host should get an edit path). Hovering a cell shows the
  pool's `gui.StatsHistoryTooltip` ("Recent changes to Malice" / "Hero
  Tokens"). `RosterHeightBudget` subtracts `POOLS_HEIGHT + POOLS_GAP` (8)
  so a seven-hero roster still fits below the strip; the roster's own
  top-right-pivot shrink is unaffected by being nested one level deeper
  (the wrapper's `refreshRail` is fired tree-wide). Verified live
  2026-09-15 in a real EotW game (0.0.831): strip renders top-right above
  the cards showing Malice 4 / Hero Tokens 0, cells measure 66x40 each,
  the history tooltip appears, no console errors.
  - **Each cell explains itself (user direction 2026-09-20)**. Hovering a
    cell now shows one tooltip card: a markdown explanation of the pool,
    with the change history under it when there is any. Malice -- "a power
    used by Monsters to charge their most powerful abilities. Beware that
    it will be used against you in battle!"; Hero Tokens -- the character
    panel's own `HERO_TOKEN_TOOLTIP` copy word for word (`Draw Steel Core
    Rules/MCDMCharacterPanel.lua`), so the two never drift; Intelligence --
    "the amount of awareness you have of what you are up against ... used
    at the start of a fight to control how much you know about the
    encounter." Texts live in `POOL_EXPLANATION` beside `POOL_TITLE` in
    `EncounterOfTheWeekHud.lua`. Three details the build turned up:
    - **A cell with no `bgimage` is not hit-tested**, so the pointer sailed
      past it to the strip behind and neither the `hover` tint nor the
      tooltip ever fired -- the cells now carry a fully transparent
      `panels/square.png` of their own. (The 2026-09-15 note above claiming
      the history tooltip appeared was wrong; it never did.)
    - `gui.StatsHistoryTooltip`'s own `text` argument is a bare auto-width
      label, so a paragraph handed to it runs off the screen in one line,
      and the panel it returns paints no background when it is nested.
      `CreatePoolTooltip` therefore owns the card chrome (opaque
      `#000000ff`, cornerRadius 10, `POOL_TOOLTIP_WIDTH` 420 on the
      markdown label) and drops the history panel in below. An empty
      history is omitted entirely rather than showing "No changes recorded
      for Malice", which out of combat is malice's normal state.
    - `EncounterMontage.GetIntelligenceHistory` handed the tooltip its raw
      log rows, whose timestamp field is `at` (a `dmhub.serverTime`, in
      SECONDS) -- so every Intelligence line read "... by Someone nil", and
      passing it to `DescribeServerTimestamp` (which wants the MILLISECONDS
      `ServerTimestamp()` returns) read "20715 days ago". It now maps each
      row to the shape `StatHistory:GetHistory` returns, with
      `DescribeSecondsAgo(dmhub.serverTime - entry.at)`.
    Verified live 2026-09-20 in the montage (all three cells hovered).
  - **Reload gotcha, still live**: `DMHub Core UI/Hud.lua` line ~879 does
    `GameHud.customInterfaces = {}` unconditionally, so whenever that mod
    reloads *after* `EncounterOfTheWeekHud.lua`, the registry is wiped and
    the takeover silently disappears until a restart (`#providers: 0`,
    `PanelDocument.RailCustomInterfaceId() == nil`). Iterating on the hud
    means `restart_dmhub`, not `reload_lua`. A one-line `GameHud
    .customInterfaces = GameHud.customInterfaces or {}` would fix it, at
    the cost of stale providers surviving a reload -- not done.
  - **Core fix that came out of it**: `GameHud.RegisterCustomInterface`
    (`DMHub Core UI/Hud.lua`) appended on every call, so a Lua reload
    that re-ran the EotW mod left the stale generation's provider first
    in the list and still winning ("first active provider wins") -- the
    new roster code was never built. It now replaces an existing provider
    with the same `id` in place.
  - Reload gotcha hit again while iterating: the EotW codemod's
    `localContents` went stale (34682 bytes vs 40113 on disk) and
    `reload_lua` kept compiling the old file. Remedy is the one in memory:
    `autoreloadlua` on, rewrite the file bytes, wait for `MOD:: READ
    CONTENTS`, then `autoreloadlua` off again.
- Clicking a card pops the full character panel **beside the card, on the
  side with more room** (user direction 2026-08-28; it used to open
  mid-screen): `ToggleCharacterPanelDocument(charid, nil, cardPanel)` --
  the third `anchorPanel` arg routes through
  `PanelDocument.PanelWindowPlacement(panel, scaledW, scaledH)` in
  DocumentSystem. It reads the anchor's `positionInScreenSpace`, offsets
  by half its rendered extent at WindowUIScale (true for rail-wrapper
  widgets), and places the window beside it, level with its top, clamped
  on screen. An anchor past the layer's mid-line is tried on its LEFT
  first -- the same preference `TokenWindowPlacement` uses -- so the
  right-edge roster's cards always open their panel to the left.
  - **`positionInScreenSpace` is NOT in screen pixels despite its name.**
    It reads back in the documents layer's own units (the same space as
    `renderedWidth` and `PresentDocument`'s `x`/`y`), origin at the
    layer's bottom-left, y UP. Verified live 2026-08-29: on a 1630x930
    screen the layer reports position (946.45, 524) against a rendered
    size of 1892.9x1048 -- exactly half its own extent, which can only be
    true in layer units. The first cut of the helper divided by
    `screenDimensions.x / uiW`, which is 1 only when the display's pixel
    width happens to equal the layer's unit width (a 1920-wide screen);
    on this 1630-wide one the card read back at x 2108 in a 1892.9-unit
    layer, the "fits on the right" test failed, the left candidate landed
    at 1651 and the window opened straight over the cards. Now the
    conversion is a plain translate by the layer's own rect.
  - It is also the **PIVOT's** position, not the centre. The rail
    wrappers and the roster set `pivot {1,1}` (for their uiscale) and so
    read back their top-RIGHT corner, while the cards keep the default
    centred pivot. Only pass centred-pivot panels as anchors. The panel is **read-only for everyone, own heroes included**
  -- `characterPanelAccess` returns "view" for every player-controlled
  token (interpretation of "read-only when in [encounter] of the week":
  sheet edits are off; state changes go through the action bar and game
  flows -- consistent with strict rules enforcement; flag if own-hero
  read-only is too strict).

Verified live (authoring game via the force toggle): takeover + release
both directions with zero console errors; roster card renders with
portrait/stats/condition icon; panel opens read-only (access "view" for a
canControl token); Panels menu vanishes; Compendium gone from launchable
menu items and search. NOT yet seen: multiple heroes / the mine-vs-others
grouping with real per-player ownership (the authoring hero is
PARTY-owned), a real EotW game end-to-end, and dock-mode users (rails off).

Known gaps (accepted for now): a user who pre-bound a "togglepanel
compendium" keybind may still open it (`LaunchablePanel.LaunchPanelByName`
ignores `filtered`; fixing needs engine core Lua);
`GameHud:ViewCompendiumEntryModal` single-entry cards from journal links
still work (arguably desirable). ~~No chat access with the rails gone~~
RESOLVED (2026-08-28, user direction): Chat + Action Log buttons kept in
the bottom-left corner (see the kept-buttons bullet above), and "/" still
opens chat via the wrapper's chat-listener wiring. Residual: the chat
speech-bubble preview does not show during a takeover (it anchors by
top-slot math on a slotted chat button); the Chat button's unread badge
covers awareness.

### "The AI is waiting on you" notice (DECIDED + BUILT 2026-09-15; luac-clean, UNTESTED live)

**Ability-cast reactions (2026-09-17, user report: the Talent's Repulsive
Ward did not hold the AI).** A prompt provoked by a monster's *cast* -- the
`losehitpoints` trigger behind Repulsive Ward fires when the strike's damage
lands, and the hero answers it after the cast has already closed -- was not
one of the three waits below: `WaitForAbilityIdle` only holds while a cast
is open. Fixed by generalising the movement-reaction machinery (the
`aiActivityId` / `pendingAIActivityReactions` protocol that already holds
the AI for opportunity attacks) to every AI action:
- `DMHub Game Rules/Creature.lua`: a file-local "AI activity in progress"
  (`creature.SetAIActivityInProgress(id)` / `GetAIActivityInProgress()`),
  set by the AI around each action; `creature:DispatchEvent` stamps it onto
  `info.aiActivityId` of every event raised while it is set (a mover's
  `OnMove` stamp still wins; the ids agree). From there the existing path is
  untouched: a player-controlled hero's dispatch becomes an
  `aiReactionRequests` message, the hero's client creates the prompt and a
  `pendingAIActivityReactions` marker, and the host counts both. Delivery
  failure strings now say "reaction event" instead of "movement event".
- `Monster AI/MonsterAI.lua`: `ExecuteAbility` opens an activity on the
  caster (`_tmp_aiActivityId`, reusing a caller's id so
  `ExecuteAdvanceFallback` still tracks one activity) for the cast, clears
  it when `OnFinishCast` arrives, then holds on the new
  `MonsterAI:WaitForActivityReactions(activityId)` -- the reaction/minion-
  death wait extracted from `WaitForMovementActivity`, which now delegates
  to it. It publishes "Waiting for <hero>'s Repulsive Ward" through the
  banner notice (`NoticeTextFromReactionStatus` also strips the transient
  "client to evaluate " delivery phrasing). A stopped AI or an unconfirmed
  reaction aborts the turn exactly as a movement wait does.
- `Monster AI/MonsterAIPanel.lua`: the AI thread clears the in-progress
  activity on start and stop, so an abandoned coroutine never leaves events
  tagged.
Scope: every non-local trigger any hero holds that is provoked by an AI
action now holds the AI -- damage, conditions, forced movement, allies'
"when an ally takes damage" prompts -- not only the wards. Hostile
(non-dismissable) prompts hold it too, as they already did for movement.
luac-clean, ASCII-clean, all six `tests/ai_*` slices + `ai_reaction_delivery_test`
pass; UNTESTED live (needs a Monster AI turn striking a Talent with
Repulsive Ward: banner within ~2s on every client, AI resumes after the
push or the dismiss).

The Monster AI pauses on players in three places, and nothing on any
client says why the monsters are not moving:

1. **Turn-claim pause** -- `FindPendingPlayerTurnClaimTrigger` in
   `Monster AI/MonsterAIPanel.lua` (Hesitation Is Weakness): the watcher
   loop returns early instead of selecting a monster.
2. **Reaction wait after movement** -- `MonsterAI:WaitForMovementActivity`
   (`Monster AI/MonsterAI.lua`): opportunity attacks and other
   movement-triggered player prompts (`pendingAIActivityReactions` on the
   hero's creature, replicated) plus minion death confirmations. Already
   computes the exact text we want ("Waiting for <hero>'s player to answer
   <ability>") into `MonsterAI.reactionStatus`, but that only reaches the
   `dmonly` Monster AI panel label, hidden in EotW.
3. **Ability-cast waits** -- `MonsterAI:WaitForAbilityIdle` while a monster's
   cast is held open by a hero's trigger prompt (`availableTriggers` on the
   hero, replicated). Knows only that a cast is live, not whose prompt holds it.

User direction (2026-09-15): the initiative-bar center-slot label is NOT
obvious enough. Reuse the new-user **tip banner** (`Tip.Register` registry +
`GameHud:ShowTip` / `_TipDriverTick` in `DMHub Game Hud/GameHud.lua`: the
920x80 top-center banner with a Dismiss button) and show it for EVERY AI
wait on a player, e.g. "Waiting for Shadow's Hesitation Is Weakness".

Built 2026-09-15 (all three files luac-clean; an in-session `reload_lua`
did NOT re-read `GameHud.lua` / `MonsterAI.lua` -- the running app still
had the old code -- so verify after the user's own reload or restart):
- **Banner notice channel** -- `DMHub Game Hud/GameHud.lua`: `Tip.notices`
  + `Tip.RegisterNotice{id, priority, text = fn}` / `Tip.UnregisterNotice`;
  `GameHud:_TipDriverNoticeTick` runs first in `_TipDriverTick` and owns
  the banner while any source returns text (suppresses the active tip
  without marking it learned, honors the dialog-blocking check); Dismiss
  (`GameHud:HideTip`) records `{id, text}` in `_noticeDismissed` so only
  that text stays hidden; `Tip.ResetAll` clears notice state too.
- **Shared document + writer** -- `Monster AI/MonsterAI.lua`: mod document
  `monsterAIWaiting` `{key, text}`; `MonsterAI.SetWaiting(key, text)` /
  `MonsterAI.ClearWaiting()` (both idempotent against the snapshot,
  `undoable = false`). The client-side source is registered there too
  (direct insert into `Tip.notices["monster-ai-waiting"]`, priority 1000,
  hidden while the initiative queue is hidden, 1s `NOTICE_GRACE_SECONDS`
  measured on the viewing client's clock).
- **Wait sites**: turn-claim pause (`MonsterAIPanel.lua` watcher loop,
  `FindPendingPlayerTurnClaimTrigger` now also returns the token; a
  `turnClaimWaiting` flag is checked at the TOP of every watcher iteration,
  ahead of the trigger scan and the monster-selection block, and clears
  the notice as soon as the claim is no longer pending -- the hero used
  the trigger, dismissed it, or the queue moved on. Fixed 2026-09-16
  (user report, UNTESTED live): the clear used to live inside the
  `initiativeid == nil and not IsPlayersTurn()` selection block, so once
  the hero USED Hesitation Is Weakness and their turn went live that
  block was skipped and the banner outlived the wait for the whole hero
  turn); movement reactions
  (`WaitForMovementActivity`, text derived from `reactionStatus` by
  `NoticeTextFromReactionStatus`: "Waiting for Shadow's Opportunity
  Attack" / "... to finish" / "Waiting for minion death confirmations");
  cast holds (`WaitForAbilityIdle` scans hero tokens' undismissed
  `availableTriggers` twice a second via `FindPlayerTriggerPromptNotice`).
  Cleared at AI thread start, AI stop, and every wait exit.
- **Audience**: everyone, Director included (user decision 2026-09-15).

To test: EotW game, hero with Hesitation Is Weakness holding the prompt at
the top of a monster side -> banner on every client within ~2s; answer or
dismiss the prompt -> banner leaves within ~1s; a hero with an opportunity
attack prompt during a monster move -> "Waiting for <hero>'s Opportunity
Attack"; Dismiss hides it until the text changes; the Monster AI panel's
status label is unchanged.

Original plan, kept for the rationale:
- **Banner: add a "notice" channel.** Tips are learn-once (a `tipsLearned`
  preference, 5s scan cadence, Dismiss marks learned). A wait notice must
  show immediately, never be learned, take precedence over tips, and
  clear itself when the wait ends; Dismiss should only hide THAT instance
  (until the text changes). Implement as `Tip.SetNotice(id, text)` /
  `Tip.ClearNotice(id)` layered on the same banner and the same
  dialog-blocking rules, with a short `since` grace (~1s) so a wait that
  resolves instantly never flashes a banner.
- **Sharing: host-authoritative shared document.** The host's AI is the
  only party that knows it is waiting, so it publishes `{key, text, since}`
  to a mod document (pattern: `VillainActionState` in
  `Draw Steel Core Rules/DSResources.lua` -- `mod:GetDocumentSnapshot`,
  `BeginChange`/`CompleteChange`, clients `monitorGame` the path); every
  client renders it through the notice channel. One writer:
  `MonsterAI.SetWaiting(key, text)` / `MonsterAI.ClearWaiting()` called
  from the three sites above; the cast site names the prompt by scanning
  hero tokens' undismissed `availableTriggers`. Cleared on AI stop and on
  encounter start (same hook `VillainActionState` uses). Alternative
  rejected: each client deriving the wait from replicated trigger state
  alone -- it cannot tell an AI wait from a Director who simply has not
  moved yet, and it would fire in ordinary Director games.
- **Audience:** everyone, including the hero being waited on (the prompt
  card is small; the banner is the reminder). Open: whether a Director
  running the Monster AI in a normal game should also see it (default yes;
  it is a status, not a tutorial).

## Encounter scripts: montage beats before combat (DECIDED + BUILT 2026-09-18; Lua only; VERIFIED in the authoring game end to end, real EotW game UNTESTED; UNCOMMITTED)

User direction (2026-09-18): the map's journal document stops being "the
place we find the `[[encounter]]`" and becomes a **script** -- the ordered
list of things that happen in the week's session. Combat ("an encounter")
is one kind of beat and keeps working exactly as it does today; the first
new beat is a **montage**. This section is the design; Phase 7 in the
Development Plan is the build order and its status. Everything is Lua in
the EotW codemod; **no engine change was needed**, and the only core codex
change is the two optional args on `Encounter.StartCombatWithTokens`
(`immediateResult`, `surprisedTokens`) that the initiative clauses use
(added 2026-09-18, see "Effect application").

Built 2026-09-18 (all in `EncounterOfTheWeek/`, the three new files
registered in the codemod through the MCP CodeMod workflow, order:
EncounterOfTheWeek, EncounterScript, EncounterMontage, EncounterOfTheWeekHud,
EncounterMontageStage):
- `EncounterScript.lua` -- the pure parser (grammar below), unit-tested by
  `tests/encounter_script_test.lua` (64 checks, run with the bundled
  `lua.exe` from the codex root).
- `EncounterMontage.lua` -- the runtime: the `eotwscript` document, script
  discovery + cache, host arbitration (`HostTick`), the owning client's roll
  launch (`ClientTick`), effect application, name resolution, the
  `/eotwscript` and `/eotwmontage state|reset` dev commands.
- `EncounterMontageStage.lua` -- the stage, a `GameHud` presentable dialog
  (`eotwmontage`).
- `EncounterOfTheWeek.lua` -- the beat machine (`RunScriptBeat`) in the host
  tick, the spawn moved out of `SetupOnArrival`, allies on the players'
  side in `GatherCombatSides`, `hostThinkInterval` 2 -> 0.5, the driver's
  `ClientTick` backstop, `FindMapEncounter` + `FreeStartTileNear` exports.
- `EncounterOfTheWeekHud.lua` -- `CreateHeroCard(entry, opts)` (halign,
  draggable + drag callbacks, click-instead-of-press), the shared
  `g_heroCardRules`, `CreateAllyCard`, ally rows under the roster cards, the
  `EncounterOfTheWeekHud` export table.
The authoring game's `Encounter` document (`98a5a5bf`, filed under
`Encounter: Goblin Ambush`) already holds the sample script, and both names
it references resolve (`Healing Potion` in tbl_Gear, `Wode Elf Sentry`
bestiary id `4311a1bd`).

### The sample script

The document below is the reference input. It is what the parser, the
runtime and the stage are built against, and it is the authoring template
for future weeks.

```
# Montage

[[scene]]

## Round 1

## Opportunity: Mysterious Cottage

A mysterious cottage lays off the path. Dare you approach?

Options: Approaching the cottage, you see a witch within, brewing some potions in her cauldron.

### Negotiate with her for some aid

|Negotiation Test: Presence (Empathize, Lie, Flirt)
|You fail at the test
|You gain one Healing Potion
|Each party member gains one Healing Potion

### Steal some potions

|Thievery Test: Agility (Climb, Disguise, Sneak)
|You lose 6 Stamina.
|You lose 6 Stamina. Each party members gains one Healing Potion.
|Each party members gains one Healing Potion

## Opportunity: Elvish Village

An Elvish Village is nestled in the forest. Approach and ask for aid?

Options: Approaching the village you ask them for aid against dangers ahead.

### Ask for Aid

|Negotiation Test: Presence (Empathize, Nature)
|You fail at the test
|A Wode Elf Sentry joins you. +2 Malice
|A Wode Elf Sentry joins you

## Threat: Dangerous Beasts

Dangerous beasts lurk in the forest, a constant threat.

Consequence: Each party member loses 5 stamina.

Options: You try to deal with the threat.

### Hunt the Beasts

|Hunting Test: Might or Agility (Endurance, Track)
|You lose 5 stamina.
|You lose 5 stamina, the threat is vanquished.
|The threat is vanquished.

### Outsmart the Beasts

|Strategy Test: Reason (Strategy, Animal Handling)
|You fail at the test.
|+2 malice, the threat is vanquished.
|The threat is vanquished.

# Encounter

[[encounter]]
```

The live game's script (2026-09-18) is an expanded version of this one, and
since the narrative beat landed it is bracketed by two of them (see
"The week's script as it stands"): two
rounds, three opportunities and two threats in round 1, three opportunities
and two threats in round 2 (the Goblin Scouts ambush moved there), and one
of each of the boon clauses from step 37 -- a shrine that banks surges, a
hunter's camp whose hearty meal raises Recovery Value, a hot spring that
heals, and warded stones that grant temporary stamina. Two authoring traps
it exposed, both silent:

- **Every power roll needs a `### option` heading above it.** A `|Name: Attr`
  block that follows a `## Threat:`/`## Opportunity:` directly is orphaned:
  the parser warns ("not under a '### option'"), drops the roll, and the
  entry ends up with no options at all.
- **Skill names in the `Attr` parentheses must match
  `Skill.skillsDropdownOptions` exactly** -- they are matched by substring,
  and a name that matches nothing simply contributes no skill, with no
  warning. The sample's "Tracking" and "Animal Handling" were both wrong;
  the real names are `Track` and `Handle Animals`.

### Script discovery and the beat list

- **Which document**: the same search `FindMapEncounter` does today (the
  document filed under the encounter map's journal folder; info bubbles
  are encounter-only because a bubble carries no beats). Nothing new has
  to be registered or named; the week's document simply grows a `# Montage`
  section above its `# Encounter` section. Since 2026-09-24 that document
  may pull in **sub-documents** by linking to them, and a document another
  one includes is never a script of its own -- see "Splitting a script
  across documents" below.
- **Beats** are the document's `#` (H1) headings, in order. Recognized
  kinds, case-insensitive: `# Montage`, `# Narrative` (see "Narrative
  beats" below) and `# Encounter`. Anything else is ignored with a parser
  warning, so the format can grow (negotiation) without breaking older
  clients.
- **Back-compat**: a document with no `#` beats at all but a
  `[[encounter]]` island (every week published so far) is exactly one
  implicit encounter beat. A script with no montage beat therefore plays
  as today.
- The `[[encounter]]` island is still found by `Encounter.GetEncountersOnCurrentMap`
  + the parentFolder filter; the parser only decides WHEN it spawns.

### Splitting a script across documents (DECIDED + BUILT 2026-09-24; Lua only; parser unit-tested, 19 new checks; VERIFIED in the authoring game over MCP -- the split week parses identically; a played-through montage on the split document UNTESTED; UNCOMMITTED)

User direction (2026-09-24): the week's document had grown to 40 KB and
should not have to be one huge page -- make scripts work with the journal's
linking and embedding, and break the live week into sub-documents linked
from a master.

**The rule.** Before a script is parsed, every line that is **nothing but a
link to another journal document** is replaced by that document's text,
recursively. The three link forms the journal itself follows
(`Seamless.LinkAtPosition`) all count:

```
[Opportunity: Mysterious Cottage](document:Mysterious Cottage)   a link (what the week uses)
[:Mysterious Cottage]                                            a page embed
[Mysterious Cottage]                                             the shorthand link
```

- A link **inside a sentence** stays a link; only a line of its own splices.
  Rich `[[tags]]`, checkboxes and images are never links.
- The splice is textual, with a blank line either side: a sub-document can
  hold anything the master could -- an entry (`## Opportunity: ...`), a
  whole round, a whole beat, or a `# Delve:`. Sub-documents may link to
  further sub-documents (depth cap 8); a cycle warns and stops.
- **Link vs embed** is purely how the journal shows the master: a link reads
  as a one-line table of contents entry you click through; an embed renders
  the sub-document inline (the journal nests embeds 3 deep). The parser
  treats both the same. The live week uses links, so the master stays a
  short index.
- **Resolution** (`EncounterMontage.ResolveScriptInclude`): `document:` is
  optional; a document id works too. A document **filed under the same
  map** wins over one of the same name elsewhere in the journal, so two
  weeks can each have a "Mysterious Cottage"; failing that it is
  `CustomDocument.ResolveLink`, exactly what clicking the link opens. A
  link that resolves to something that is not a journal document (a
  monster, a PDF, a map, a URL) is left as prose, silently; a link that
  resolves to nothing is left as prose **with a warning**.
- **Discovery**: `FindMapScript` loads every markdown document under the
  map (each expanded), and any document another one includes is a *part*,
  never a candidate script -- so the sub-documents can sit in the map's
  own journal folder beside the master without competing with it.
- **Where sub-documents live**: directly in the map's journal folder (the
  "Map Documents" list). That is also what the publisher ships: it seeds
  every non-hidden markdown document whose `parentFolder` chain roots at the
  map (`tools/eotw_publish/documents.py` `find_map_documents`), so nothing
  in the publisher had to change. A subfolder under the map would satisfy
  the runtime, but whether the publisher's dependency walk ships the
  *folder* record is unverified, so the week does not use one.
- **Warnings name their document**: a problem on line 29 of the Mysterious
  Cottage sub-document reads `'Mysterious Cottage' line 29: ...`; lines of
  the master keep the plain `line N:`. Same in the validator panel, which
  also lists the sub-documents it pulled in, and in `/eotwscript`.
- **Rich tags stay with their document.** A `[[scene]]` island's annotation
  is stored on the document that contains it, so the parser now records the
  tag's line (`beat.sceneLine` / `section.sceneLine`), and
  `EncounterMontage.SceneImage` reads the annotation from the document that
  line came from. It also now uses the journal's key for a repeated tag --
  the 1st `[[scene]]` is `scene`, the 2nd `scene-1`, the 3rd `scene-2`
  (`EncounterScript.AnnotationKey`, the rule in
  `MarkdownDocument:GetReferencedAnnotations`). Before this, every beat read
  the FIRST scene's annotation whatever the journal showed; it went unnoticed
  because the week's three scenes carry the same image. The `[[encounter]]`
  island needs nothing new: `GetEncountersOnCurrentMap` already harvests
  every document under the map. In the live week every rich tag stayed in
  the master, so no annotation moved.
- **Cache**: `FindMapScript` re-expands only when its signature changes --
  every candidate document's id, name and text length, plus those of every
  document the last parse included (which may live outside the map).

**Code.** `EncounterScript.lua` (pure): `IncludeTarget`, `ExpandIncludes`,
`ParseExpanded`, `LineLabel`, `DescribeSource`, `AnnotationKey`, the
exported `SplitLines`, and `sceneLine` on beats and sections.
`EncounterMontage.lua`: `ResolveScriptInclude`, `LoadScript` (one document
-> expanded + parsed script; the validator uses it too), the rewritten
`FindMapScript` + `ScriptSignature`, `SceneImage`. `EncounterNarrative.lua`:
`SceneImage` passes the section/beat through so `sceneLine` reaches it.
`EncounterScriptValidator.lua`: parses through `LoadDocument`, labels lines
by document, lists the includes. Tests: the "sub-documents" block in
`tests/encounter_script_test.lua` (448 checks in all).

**The live week, split (2026-09-24).** The master `Encounter` document
(`98a5a5bf`) went from 40,123 to 1,978 bytes. It keeps the beat skeleton --
both narrative beats, the montage intro, the three `[[scene]]` islands, the
round headings and their party-size directives, and the `# Encounter` beat
with its setup line and `[[encounter]]` -- and each montage entry and the
delve is a link line. Sixteen sub-documents, all filed under the map
(`9ca4404c`), named after the entry (the `(Required)`/`(Locked)`/
`(Temporary)` tags stay on the heading inside the sub-document, not in its
name):

| Round 1 | Round 2 | Elsewhere |
|---|---|---|
| Mysterious Cottage `e5c2ada5` | Hunter's Camp `38e5ce86` | Forbidden Tomb Delve `589de210` (the `# Delve: Forbidden Tomb`, 12.9 KB) |
| Elvish Enclave `9ccdd7d4` | Hot Spring `02f19814` | |
| Wayside Shrine `6aa4e185` | Warded Standing Stones `6efba4db` | |
| The Little Stalker `e5974dc5` | Forbidden Tomb `27a287aa` | |
| Talk to the Goblin `ae616c58` | Goblin Scouts `2830eeef` | |
| Scout out the Forest `8bc4fc36` | Gathering Darkness `7405567d` | |
| Dangerous Beasts `5390040e` | | |
| Treacherous Ravine `4905e1cd` | | |
| Traps in the Forest `442a2d5a` | | |

VERIFIED over MCP: before writing anything the split was expanded in memory
and parsed to the same `EncounterScript.Describe` output as the unsplit
document (only warning locations differ, now naming the sub-document); after
writing, the runtime `FindMapScript` picked the master (not a part),
included all 16, matched the pre-split parse, resolved the three scene images
and the encounter, found the delve, and re-parsed when a sub-document's text
changed. All 16 master links resolve through `CustomDocument.ResolveLink` to
the map's own sub-document. The 17 files are in `C:\dev\eotw\objectTables\documents\`
(`encounter.yaml` plus one per sub-document). The pre-split document is
saved only in that session's temporary scratchpad (`encounter.yaml.bak`;
the authoring directory's document files are untracked in its git repo),
so treat the split as the source of truth; an older copy is the journal's
"Encounter (backup before scenes 2026-09-23)".

**Still to verify**: a montage played through on the split document (the
data path is proven identical, the stage has not been watched); the
publisher shipping the sub-documents (its dry run currently dies on an
unrelated bad character in `actions-in-combat.yaml` before it gets that
far -- U+008A mojibake, a separate fix).

### Montage grammar

Parsed from the raw markdown text (`doc:GetTextContent()`), line-based, in
a pure module with no engine dependencies so it can be unit-tested with
the bundled `lua.exe`:

- `[[scene]]` / `[[scene:name]]` inside the montage section: the
  `RichScene` annotation (`doc.annotations["scene"]`, resolved with the
  same candidate-key rule as `GetReferencedAnnotations`) supplies
  `.image`, the coverart shown behind the stage. Missing or imageless =
  plain dark backdrop.
- Prose between `# Montage` and the first `##` is the montage intro (shown
  in the stage header).
- `## Round N`: opens round N. Entries that follow are introduced in that
  round and **persist into every later round** (user direction 2026-09-18:
  both opportunities and threats persist; an entry is only ever removed by
  being taken or vanquished). No round heading at all = one implicit round.
- `## Opportunity: <Name>` / `## Threat: <Name>`: an entry in the current
  round. A trailing tag in parentheses -- `(Required)`, `(Locked)`,
  `(Temporary)`, or any combination, `## Threat: The Pact (Required,
  Locked)` -- is stripped from the name. `(Required)` marks an entry a
  party-size directive may never remove; `(Locked)` keeps the entry off
  the board until an `Unlock <name>` outcome lets it on (see "Locked
  entries" below); `(Temporary)` makes it the one kind of entry that does
  NOT persist -- it is gone at the end of the round it appeared in (see
  "Temporary entries"). A parenthesis that is not a recognized tag stays
  part of the name. Its body, up to the next `##`/`#`:
  - plain paragraphs = the description shown on the card;
  - a paragraph starting `Options:` = the approach text, shown when a hero
    approaches, above the option list;
  - a paragraph starting `Consequence:` (threats only) = the effect line
    applied at the end of the montage if the threat was never vanquished.
- `### <Option name>`: an option of the entry. Its power roll is the
  `|Name: Attr` header line plus three (optionally four, the critical
  tier) `|text` lines -- the journal's own block syntax, matched with the
  same two regexes `MarkdownDocument` uses (`^\|(?<name>[^|]+): (?<attr>[^|]+)$`
  and `^\|(?<text>[^|]*)$`). A tier line may read `teaser => full text`:
  players see the teaser until that tier lands, and only the full text is
  parsed for effects (see "Hidden tier outcomes" under Monster Info).
  After the tier lines a roll may carry **rider** lines,
  `|<Effect>: <requirement>` -- `Allow` (alias `Requires`), `Edge`,
  `Double Edge`, `Bane`, `Double Bane` -- that gate or modify the test for
  the hero taking it (see "Test riders" under Monster Info for the
  requirement grammar). A `|` line that starts with one of those words and
  a colon is never a tier, so a rider may follow a fourth tier line.
  `Attr` is turned into characteristics + skills
  the way `PowerRollDisplay`'s press handler already does it: every
  `creature.attributesInfo` description that appears in the text
  (`Might or Agility` -> both), every `Skill.skillsDropdownOptions` name
  that appears in the parenthesized list. That mapping is duplicated in
  the codemod rather than factored into core so the codemod keeps working
  against the retail core it ships with.
### Montage scenes: the approach plays on a stage (DECIDED + BUILT 2026-09-23; Lua only; parser unit-tested, 34 new checks; VERIFIED live end to end in the authoring game (single client); UNCOMMITTED)

User direction (2026-09-23): when a hero approaches an opportunity or
threat, the centre turn panel becomes a small **stage** that plays a
scripted scene, old-school-RPG style. The approaching hero's portrait
stands on the left; characters the scene brings on stand on the right;
speech appears in JRPG bubbles under the speaker's portrait, with the
speaker lit and everyone else dimmed; narration types out in a box along the
bottom; a caret blinks at the end of a finished line, and the acting
hero's player clicks to turn the page.

**Decisions (2026-09-23, with the user):**
- **Layout: the classic bottom box.** Portraits along the top of the stage
  (hero left, cast right, the right side at 0.8 scale when two or more
  share it), speech bubbles under the portraits, and narration ALWAYS in
  the box across the bottom. Chosen over "narration on the free side,
  then a top strip" (it moves mid-scene) and "three fixed columns" (the
  portraits and bubbles get too narrow).
  **Revised after the first playtest (user direction 2026-09-23):** the
  figures stand directly ON the dialog box, larger (230 x 300 showing), and
  are no longer cards: no border or backing, the portrait fades into the
  scene at its top and sides (`edgeFade` 0.15), and the name is overlaid on
  its foot (white over a dark offset copy). The bottom must not fade, and
  the portrait must end cleanly on the box top (a first version ran the
  image on behind the box to hide a faded band; it showed through -- user
  note). `edgeFade` measures from the edges of the whole IMAGE (image-rect
  space), not the panel, so `SetPortraitFrom(..., keepBottom)` frames a
  taller crop and trims its bottom band away: the crop's bottom edge then
  lies beyond the fade and stays crisp, while the top and sides fade. The
  speaker's 6% growth pivots at the feet (`pivot = {0.5, 0}`), so they
  grow upward and never dip into the box. `edgeFade` has to be set on the
  panel itself: from a class rule it is silently not applied (verified
  live). **There are no speech
  bubbles any more** (second playtest note, same day): speech takes the
  narrator's place in the dialog box, upright, under the speaker's name in
  gold (with the language note, "Witch (speaking Hyrallic)"; a garbled line
  is italic and muted). Narration is italic with no name, so the two never
  read alike. Who has the floor is shown on stage: at rest (narration, the
  choice, the roll) the figures are a touch dim (brightness 0.8); the
  speaker lights up (1.1), grows 6% and their overlaid name turns gold;
  anyone else on stage sinks back (0.45, desaturated).
  **Third playtest notes (same day):** (1) once a turn resolves, the centre
  goes straight back to the neutral round view ("Round N", whose move it
  is, and the last log entry as a one-line summary with the applied lines)
  instead of leaving the stage up; the stage is shown only while a turn is
  in flight (`staged` excludes "resolved"; `BuildTurnChildren` treats a
  resolved turn as no turn; the old resolved box view is gone). (2) While
  the dice tumble, the live tier table only HIGHLIGHTS the running tier --
  a hidden outcome keeps its teaser, so the roll is never previewed; when
  the roll settles the landed tier's outcome types in over its teaser
  (`SetLandedTier(rows, tier, reveal)`). (3) All typing is layout-stable:
  the whole line is laid out from the first frame and the untyped rest is
  drawn in a clear colour (`RevealText` / `VisibleLength`, rich-text tags
  kept in the typed part, stripped from the hidden part), so a word never
  starts at the end of a line and jumps down, and a revealed outcome takes
  its final size the moment the roll settles. (4) Entry-card titles were
  unreadable while dragging: the engine marks valid drops `drag-target`,
  the theme (DefaultStyles "DRAG & DROP") paints them light and darkens the
  text of their DIRECT children only (`parent:drag-target`; `parent:`
  matches the immediate parent and nothing further up). The title sat in a
  row panel with the threat's malice diamond, so it stayed white. It is now
  a direct child of the card, and the diamond floats in the corner.
- **Choices live in the bottom box as bare option names**, stacked one per
  row like an RPG choice menu (the box is 196 tall so the prompt plus four
  rows fit; a longer list scrolls). The do-nothing choice is **Leave**
  (was "Pass"), tooltip "Leave without doing anything. This passes your
  turn -- not very heroic." (user direction 2026-09-23). Hovering one
  lays its full test (roll, riders, tier table) in the middle of the stage,
  between the characters. The same centre spot shows the chosen option's
  live tier table while it is rolled, the base tier while an assist is
  possible, and the landed tier once resolved; the box holds the matching
  short text (make your roll / the assist slot / tier + applied lines +
  whose move it is).
- **Only the acting hero's player advances.** No timeout, no takeover by
  other players. If they vanish, the scene waits. (Offered alternatives,
  "others can take over after ~30s" and "auto-advance on a timer", were
  declined.) A click while a line is still typing only finishes it,
  locally, for anyone.
- **Languages: garbled unless the PC speaks it.** The scene is told from
  the approaching hero's point of view: a line tagged `(in Hyrallic)` reads
  plainly for everyone (the bubble says "Witch (in Hyrallic)") if the hero
  knows Hyrallic, and as a deterministic letter-scramble for everyone
  ("Witch (speaking Hyrallic)", italic) if not.
- **Conditions:** `PC speaks X`, `PC is X` (class, subclass, ancestry),
  `PC has X` (skill), `PC chose X` (option), `tier1`..`tier3`, `crit`, and
  `not` / `and` / `or` / parentheses.
- **Every approach uses the stage**, scripted or not. An entry with no
  scene gets an automatic intro: "<Hero> approaches <Entry>...", then its
  `Options:` text if it has one.

**The grammar.** A `---` line inside an opportunity or threat, above its
first `### option`, ends the card text and starts the entry's scene. From
then on, every non-blank line is one step (they are NOT joined into
paragraphs):

```
## Opportunity: Mysterious Cottage

A mysterious cottage lays off the path. Dare you approach?

---

PC approaches the cottage...                  narration ("PC" -> the hero's name)
PC: I see a Witch within!                     speech by the hero
Witch (Hag) enters                            a character comes on; (Hag) is the
                                              bestiary monster whose portrait shows
Witch: (in Hyrallic) Oh ancient spirits...    speech in a language
if PC speaks Hyrallic then                    if / elseif / else / end (any indent)
    PC: She brews healing potions!
else
    PC: Is she wicked?
end

### Negotiate with her for some aid

PC: Good morrow!                              plays once this option is picked

|Negotiation Test: Presence (Empathize, Lie, Flirt, Persuade)
|You fail at the test => The witch is unimpressed.
|...

if tier1 then                                 plays once the roll has landed
    Witch: Begone!
elseif tier2 then
    Witch: Take this and begone.
else
    Witch: Here, potions for you and your friends.
    Witch exits
end
```

- **In a scripted entry, an option's lines above its roll are its pre-roll
  scene and its lines below the roll are its outcome scene.** They are not
  the option's description (in an entry without `---` they still are).
- `Name (Monster) enters` / `appears` / `arrives`; a bare `Name enters`
  uses the name as the monster. `Name exits` / `leaves` / `departs` only for
  a name that enters somewhere in the entry (otherwise it is narration).
- `Name: text` is speech only when Name is `PC` or a character who enters
  somewhere in the entry, so "Beware: the path is steep" stays narration. A
  character who speaks before entering is brought on as they speak.
- **Emotes** (user direction 2026-09-23): `Witch is alarmed` on a line of
  its own, or `Goblin (scared): Let go!` on a line of speech. Three:
  **alert** (a red "!" in a cream balloon pops up over the figure's
  top-right corner), **alarmed** (three yellow dashes fanned out there),
  **scared** (the figure shakes violently, +-7px at ~30Hz, for 1.4s). The
  marks pop in from small, hold 1.6s and fade. Like an entrance, an emote
  plays as the NEXT line appears (it is not a line of its own), and it
  counts only for `PC` or a character who enters in the entry, so "The
  forest is alert" stays narration; an unknown emote word is narration too.
  A stage that comes up mid-line (a join) does not replay emotes. Code:
  `EncounterScript.SCENE_EMOTES`, the `emote` step in `CompileScene`,
  `step.emotes` from `FlattenScene`, the PC -> left-side mapping in
  `BuildScenePart`, and `EmoteMarker` / the actor's `emote` event /
  `PlayEmotes` in the stage (the shake moves an inner wrapper that carries
  no style rules, because a rule's `transitionTime` would smooth the jerks
  into a drift). VERIFIED on screen 2026-09-23 (all three; the shake
  measured at 7px off rest mid-motion and back at rest after).
- `if` is a branch only when the line ends in `then` or its condition
  parses cleanly, so narration like "If you listen closely..." stays
  narration. `then` is optional; `else if` / `elseif` / `end if` /
  `endif` all work.
- `tier3` also holds on a critical; `crit` is the fourth tier only. A tier
  test outside an outcome scene warns and is never true.
- The entry's `Options:` and `Consequence:` lines keep their meaning inside
  a scene (one line each). An `Options:` text plays as the intro's last
  narration.
- Parser warnings: a stray `else`/`elseif`/`end`, an unclosed `if`, an
  unknown condition, a tier test before the roll, `PC chose` naming no
  option of the entry, a second `---`, a `---` outside an entry or below
  an option.

**How it runs** (`EncounterMontage.lua`). New turn status `"scene"`, before
`choosing` (the intro), before `rolling` (an option's pre-roll lines) and
before `resolved` (the outcome lines -- **effects are applied only after the
outcome lines have been read**, so the potions reach the haul after the
witch hands them over). The host flattens each part for this hero and
this roll (`BuildScenePart`: conditions evaluated with the test riders'
`HeroFacts` + `RequirementMet`, "PC" substituted, foreign lines garbled)
and stores the resulting lines on the turn as `turn.scene = { id, part,
steps, cast }`, so every client shows the same thing without evaluating
the script. The page cursor is `data.montageScene = { id, index }`, the
one key a player writes directly (`EncounterMontage.AdvanceScene`, gated by
`LocalUserPacesScene`): a request round trip through the 0.5s host tick for
every line would make dialogue sluggish. The host only reads it, and moves
the turn on (`FinishScenePart`) once `index` passes the last line. Scene ids
come from `m.seq`, and `Begin` clears the cursor so a restarted montage
cannot skip its first scene. `ResolveTurn` became `ApplyResolution` plus a
wrapper that plays the outcome lines first.

**The stage** (`EncounterMontageStage.lua`, `CreateSceneStage`). It
replaces the turn panel's contents for as long as `m.turn` is set
(`turnScroll` holds the old round/idle/consequence text, which
`BuildTurnChildren` now builds only when no turn is in flight; its
per-turn branches became `AssistChildren` / `ResolvedChildren` and the
`Portrait` / `PassCard` helpers they used were removed). Typing is local
(45 chars/s, UTF-8 safe) and keyed on `sceneId:index`, so unrelated
document refreshes never restart a line. Actors fade and rise in and out
(`eotwSceneOffstage`, the entry cards' appear pattern). A stage that comes
up mid-turn (a join, a reload) shows the current line settled, with no
typing and no entrances. Portraits: the hero's `offTokenPortrait`; a cast
member's bestiary monster `asset.info.offTokenPortrait`, found by
`EncounterMontage.FindMonster(monster)` then by name. **The bestiary Hag
has no portrait yet** (it shows the default monster avatar).

**Status / next steps:**
- Parser: `tests/encounter_script_test.lua`, 404 checks pass (34 new).
- Runtime and stage: luac-clean; `check.ps1 -Changed` holds all three files
  to their ceilings. **VERIFIED live 2026-09-23** in the authoring game
  (`e96656f3`, whose week document already carries the user's cottage
  scene), single client, through the virtual input bridge: the Dwarf Fury
  approached the Mysterious Cottage; narration typed into the box with the
  caret; clicks paged through the hero's bubble (hero lit, gold border),
  the Witch's entrance (Hag default avatar, fade-in) and her Hyrallic line
  GARBLED ("Witch (speaking Hyrallic)"), then the non-speaker branch; the
  last click moved the turn to choosing; bare option buttons + Pass in the
  box; hovering "Negotiate" put the test card mid-stage; clicking it played
  the pre-roll line, then the real roll dialog opened with the live tier
  table mid-stage; a real 19 (tier 3) played the Witch's tier-3 line with
  nothing yet in the haul, and only after the last click did the three
  Healing Potions land and the resolved view show tier + applied lines +
  whose move. A second run with the High Elf Tactician (who knows
  Hyrallic) showed the line plainly as "Witch (in Hyrallic)" and the
  friendly branch. Two fixes came out of it: the box's text was centred
  vertically (now top-aligned) and a locked option did not look locked
  (brightness does not reach the label; the name now dims itself). No Lua
  errors. The residue (montage state, the potions) was cleaned out; the
  three pregens were placed on the map for the test and left there.
- **Still to verify:** a second client (only the acting player gets the
  caret; the others watch the same lines), the assist window on the stage,
  and a late joiner arriving mid-scene (it should come up settled).
- **Dev-driver trap** (not new, found on the way): `/eotwmontage start`
  runs the montage beat, but the script stage chooses its BODY from
  `doc.data.beat`, which only the real beat machine sets -- with it unset
  the stage mounts beat 1 (here a narrative) and shows an empty bar. Set
  `doc.data.beat` to the montage's beat index when testing. The party-size
  draw may also remove the entry you want to test (`m.removed`).
- Not built (out of scope for v1): an assisting hero appearing on stage,
  voice / sound per line, keyboard paging, scenes in narrative beats or on
  unresolved-threat consequences, a portrait override for a cast member
  other than its bestiary monster.
- **The week document uses 25 emotes** (2026-09-23): alert as a hero senses
  something (the cottage, the stalker, the howl, the tripwire, the breath
  in the dark) and as the Elf Warden challenges them; alarmed at shocks (the
  ghost at the shrine, the scout's arrow, a pot boiling over, the wards
  backfiring, the witch catching a thief); scared for the captured goblins,
  the falling climber and the arrow volley. Rules re-verified identical
  (395-field fingerprint, same 46 warnings) before the upload.
- **The week document is fully scripted** (2026-09-23, user direction: "the
  same outcomes, scripted dialog throughout"). All 13 montage entries have a
  `---` scene, and every option has a line before its roll and a
  tier-branched outcome after it. The cast is played by bestiary monsters:
  Witch = Hag, Elf Warden = Wode Elf Warleader, Elf Sentry = Wode Elf Sentry,
  Shrine Spirit = Unquiet Spirit, "Snik" the goblin = Goblin Guide (the same
  monster the befriend outcome spawns), Wolf = Wolf, Goblin Scout = Goblin
  Sniper. Language lines use Hyrallic (witch), Yllyric (elves, matching the
  Enclave's `Edge: You speak Yllyric` rider) and Szetch (goblins). Each
  entry's `Options:` line was folded into its scene. **Nothing the rules
  act on changed**: an in-app comparison of the old and new parse matched
  448 fields (beats, sections, unlocks, setup, round scaling, entry ids,
  tags, descriptions, consequences, option names, roll names/attrs, every
  tier's text, teaser and effect count, riders) with zero differences and
  the same 46 warnings (all tier flavour text). The original is kept as
  the document "Encounter (backup before scenes, 2026-09-23)"
  (`4711d2b5-0d68-47b1-8ea7-1642e1918a9e`, in Private Documents, so it is
  never read as the map's script). The narrative beats are unchanged: scenes
  are montage-only.
- The Witch is played by the **Wode Hag** (has portrait art; the montage is set in the Wode), not the bestiary Hag, which has no portrait (2026-09-24; in the working copy, uploads with the delve content).

### Delves: a dungeon crawl inside one approach (DECIDED + BUILT 2026-09-24; Lua only; parser unit-tested, 16 new checks; runtime and stage luac-clean + type-checked but UNTESTED live -- the app was closed; the content is in the week's document (since 2026-09-24 the `Forbidden Tomb Delve` sub-document); UNCOMMITTED)

User direction (2026-09-24): a new opportunity, the **Forbidden Tomb**, is a
loop: the hero meets obstacles (undead, traps, puzzles), finds a chest
(a d6 table of treasure) every 1-2 obstacles, and after each chest may press
deeper or turn back; with no Recoveries left they are forced out.

**Decisions (with the user):** Scout out the Forest is (Required) in Round
1 and the Forbidden Tomb a normal opportunity in Round 2; **flat** -- going
deeper is not harder, it just means more chests; **one hero, one turn** --
the whole delve is the approaching hero's turn, then the tomb is taken;
the chest table is **1-2 Healing Potion, 3 Black Ash Dart, 4 Buzz Balm,
5 Growth Potion, 6 Color Cloak - Blue** (the level-1 / 1st-echelon
trinkets and consumables with gold implementation, fishing meals, the
hunting draught and the beastheart-only collar left out). Ullorvic is the
star elves' dead language; its related languages are Hyrallic and Yllyric
(Heroes, "Dead Languages"), so "can read the tomb" is `PC speaks Ullorvic
or PC speaks Hyrallic or PC speaks Yllyric`, and the puzzles' edge is
`|Edge: You speak Ullorvic, Hyrallic or Yllyric`.

**The grammar.** An option enters a delve with a `Delve: <Name>` line
(above where its roll would be; the option has no roll). The delve itself
is a `# Delve: <Name>` section anywhere in the document -- NOT a beat
(`parse.delves`, by `MatchKey`; nothing plays it in order):

```
# Delve: Forbidden Tomb
Chest: every 1-2 obstacles          (default 1-2)

## Obstacle: The Restless Dead       an obstacle: exactly an opportunity's
Card text.                           shape -- card text, "---" scene,
---                                  "### options" with power rolls,
Skeleton (Soulwight) enters          pre-roll and outcome lines
...
### Fight them
|Combat Test: Might or Agility (Endurance, Gymnastics, Lift)
|...three tiers...

## Chest                             a scene, then a dice table
PC finds a chest...
|Treasure: 1d6
|1-2: You gain one Healing Potion    "|N-M: result" or "|N: result"; each
|3: You gain one Black Ash Dart      row's text uses the tier clause grammar

## Continue                          played after each chest, before the choice
## Leave                             (or "## Turn Back") walking out
## Forced Out                        walking out with no Recoveries left
```

Every line under Chest / Continue / Leave / Forced Out is a scene line (no
`---` needed). Parser warnings: a delve with no obstacles, no Chest, a
Chest with no table, options under a scene section, an obstacle option
with no roll, a `Delve:` naming no delve, a dice table outside a Chest.

**How it runs** (`EncounterMontage.lua`, "delves (host side)"). Choosing
the option sets `turn.delve = { name, entryName, depth, sinceChest,
chestAt, used, obstacleId, chests, applied }`, plays the option's own
lines, then `DelveNextObstacle`: a random obstacle not met yet becomes
`delve.obstacleId`, and from then on `EncounterMontage.TurnEntry(beat, t)`
(which every turn lookup now goes through) returns the OBSTACLE, so its
scene, choice, roll, assist and outcome lines run on the existing
machinery unchanged. When its test lands, `ApplyResolution` hands it to
`DelveObstacleResolved`: effects apply at once (collected in
`delve.applied`), then -- Recoveries at 0 -> forced out; the chest is due
(`sinceChest >= chestAt`, re-drawn from the Chest interval each time) ->
the Chest scene, then status `"chest"`, whose roll the delving player's
client makes with `dmhub.Roll` (real dice, in chat) and reports as
`chestRolled`; the row's effects apply and the Continue scene plays,
led by "<Hero> rolls N: <row>"; then status `"delvechoice"` with "Press
deeper" (`delveOn`) / "Turn back" (`delveOut`); otherwise the next
obstacle. No obstacles left -> "There is nothing further to find here."
and out. Leaving plays Leave / Forced Out and `DelveFinish` resolves the
turn: acted, the entry taken, and a log line `{ delve, depth, chests,
applied }` that the round view summarises ("X delved into Y: N obstacles
met, M chests opened." plus every applied line). Leave is not offered
inside a delve (the host also refuses `pass` there): the way out is
turning back at a chest. Each delve scene starts with an empty stage.

**The stage.** Title "<Hero> in <Entry>: <Obstacle>"; the obstacle's
options as usual; while the chest's dice are out the table sits mid-stage
(`ChestCard`); at the choice, mid-stage shows the haul so far and the
obstacles / chests / Recoveries left (`HaulCard`), the box the two buttons.

**The week document's new content** (written; not yet uploaded -- the app
was closed; the text is the scratch copy `week_scenes.md`, and a rules
diff against the live document showed no existing field changed):
Scout out the Forest (Required, Round 1: "Scout the forest", Agility or
Intuition (Alertness, Navigate, Search, Sneak), +1 Int & -1 Recovery /
+1 Int / +2 Int; "Track goblin trails", Intuition (Track), Allow: skilled
in Track, +2 Int & -2 Recoveries / +2 Int & -1 / +2 Int); Forbidden Tomb
(Round 2, the Ullorvic inscription, "Enter the tomb" -> `Delve: Forbidden
Tomb`); and `# Delve: Forbidden Tomb` at the end of the document with
nine obstacles -- undead: The Restless Dead (Soulwight), The Wailing Ghost
(Ghost), The Armored Guardian (Armored Soulwight), each fought (Might /
Agility) or avoided (Reason / Intuition), -2 / -1 / 0 Recoveries and the
dead always fall; traps: Crushing Stones, Darts in the Walls (stamina
costs), The Collapsing Stair; puzzles: The Sealed Door, The Star Map, The
King's Riddle (Unquiet Spirit, speaking Ullorvic), each solved (+2 / +1 /
0 malice, edge for Ullorvic-family speakers) or broken through (always
cursed: +2 malice and -1 Recovery / +2 / +1) -- plus the Chest, Continue,
Leave and Forced Out scenes.

**Next:** start the app, upload the document (rules-diff it against the
live one first), and play a delve end to end: an obstacle with an assist,
a chest roll, press deeper, turn back; and a forced exit at 0 Recoveries.

### Scaling a montage to the party (DECIDED + BUILT 2026-09-20; Lua only; parser unit-tested with the bundled interpreter; runtime UNTESTED live -- needs a restart; UNCOMMITTED)

User direction (2026-09-20): a week should be able to trim itself for a
small party. Directly under a `## Round N` heading, one line per rule:

```
## Round 1
3-5 Players: -1 Opportunity, -1 Threat
3 Players: -1 Threat
```

At that party size the round drops that many entries of each kind, **drawn
at random**, and the party is never told: a removed opportunity or threat
simply never appears on the stage, is never approachable, and (for a
threat) delivers no consequence. There is no "this was removed" signal of
any kind.

Grammar (`EncounterScript.ParseScalingDirective`, pure and unit-tested):

- The range is `3`, `3-5` or `3+` (open-ended). `Players` may be spelled
  `Player`, `Heroes` or `Hero`. Case does not matter.
- The removals are a comma- (or semicolon-) separated list of
  `-<n> <Opportunity|Threat>`, singular or plural; `<n>` may be a digit or
  a word (`-one Opportunity`). A leading `+` is rejected -- a directive only
  ever removes.
- A line that LOOKS like a directive (`^<digits> Players:`) but does not
  parse warns rather than silently becoming montage intro prose, and so
  does one written below the round's entries instead of directly under the
  heading.

Decisions (2026-09-20):

- **Scope**: a directive draws only from the entries **its own round
  introduces**. An entry carried over from an earlier round is never yanked
  off the board mid-montage.
- **Overlap**: every directive whose range covers the party size applies,
  **cumulatively**. The pair above gives a party of 3 `-1 Opportunity` and
  `-2 Threat`, and a party of 4 or 5 `-1 Opportunity, -1 Threat`.
- **Timing**: the draw is made **once**, by the host, at the moment the
  party has arrived -- the `arriving` -> `rounds` transition in
  `EncounterMontage.HostTick`, not `Begin` (which can run before a single
  hero token is placed, so the roster is not yet trustworthy there). The
  whole beat's rounds are drawn at once, so a player joining or dropping
  later cannot change the montage.
- **`(Required)`**: an entry whose heading ends `(Required)` is out of the
  pool. If a round asks for more than it has removable entries, it drops
  everything it can and the parse warns.

Implementation:

- `EncounterScript.lua`: `round.scaling = { scalingDirective, ... }`
  (`{min, max, removals, text, line}`), `entry.required`,
  `ParseScalingDirective`, `IsScalingDirectiveLine`, `ScalingRemovals`,
  `HasScaling`, `RoundHasScaling`, and `ChooseRemovedEntries(beat,
  partySize, rand)` -- the draw itself, which takes an injected `rand` so
  the tests are deterministic. `/eotwscript` prints each round's directives
  and marks required entries.
- `EncounterMontage.lua`: `RollRemovals` (file-local) writes
  `m.removed = { [entryId] = true }` on the montage document at the
  arrival transition, with a belt-and-braces re-roll in `HostTick` for a
  state written by an older client. `EncounterMontage.EntryRemoved` and
  `EncounterMontage.EntryHidden` and `EncounterMontage.DescribeRemovals` are what everything else
  reads; `EntryAvailable` refuses a removed entry, and the end-of-montage
  consequence list skips removed threats. `/eotwmontage reset` clears the
  montage state, so it re-rolls.
- **Logging.** The draw is invisible to the party, so the console is the
  only account of what a week actually played with. `RollRemovals` prints
  the party size, every directive with `APPLIES` / `out of range at this
  party size`, one line per entry it removed (round, kind, name, id), each
  `(Required)` entry it therefore kept in a scaled round, and a final
  `removed N of M entries`. It is all `printf` -- the Director's console
  and the log, never the montage log the stage shows a player. The draw is
  also durable: `m.removedForPartySize` goes on the montage document beside
  `m.removed`, and `/eotwmontage state` prints
  `EncounterMontage.DescribeRemovals` -- the directives and the removed
  entries by NAME -- under the raw JSON, so a montage can still be
  explained long after the scrollback is gone.
- `EncounterMontageStage.lua`: `AddEntriesForRound` skips anything
  `EntryHidden` says to skip. **Until the draw is made (`m.removed == nil`)
  a round that carries a directive shows NO entries at all** -- a card that
  is about to be removed must never flash up first -- and the draw landing
  is treated as a rebuild (`drawLanded`) so the survivors arrive, since the
  round number has not changed to bring them in. Rounds without directives
  are unaffected and show during `arriving` as before.
- Tests: `tests/encounter_script_test.lua` (260 checks, up from 233).

### Locked entries and "Unlock <name>" (DECIDED + BUILT 2026-09-20; Lua only; parser unit-tested with the bundled interpreter; runtime UNTESTED live)

User direction (2026-09-20): just as an opportunity or threat can be
declared `(Required)`, it should be declarable `(Locked)`. A locked entry
does not show up at all unless something unlocks it. "Interrogate the
Goblin" is locked; the opportunity "Capture the Goblin" carries
`Unlock Interrogate the Goblin` as an outcome, and once that lands the
locked entry appears -- immediately if the round it is declared in has
been reached, otherwise when that round comes.

Grammar:

- `## Opportunity: Interrogate the Goblin (Locked)`, and `(Required,
  Locked)` for both tags. The tags are stripped from the name.
- `Unlock <name>` is an effect clause like any other, so it can sit on a
  power roll tier or on a `Consequence:` line. Spellings: `Unlock ...`,
  `Unlocks ...`, `You unlock ...`, `The party unlocks ...`, `Each party
  member unlocks ...`.
- It is almost always written hidden -- `{Unlock Interrogate the Goblin}`
  -- so the party is not told a card exists before it appears. Written
  unbraced it reads "Interrogate the Goblin is now available" in the turn
  summary and the log.

Decisions (2026-09-20):

- **Matching is by name, not by id.** Both sides go through
  `EncounterScript.MatchKey`: lower-cased, whitespace collapsed, a leading
  `the ` and trailing punctuation dropped. So `{Unlock the Pact}` finds
  `## Threat: The Pact (Locked)`, and an author does not have to copy the
  heading letter for letter.
- **Scope is the montage beat.** The unlocks live in the per-beat montage
  state (`montage.unlocked`), so `/eotwmontage reset` locks everything
  again, and an `Unlock` clause written in a *narrative* beat does nothing
  (the parser warns, and the runtime prints why).
- **Locked entries are out of the party-size draw**, exactly like required
  ones. Letting a directive quietly remove the entry an `Unlock` outcome
  points at would make the unlock a silent no-op.
- **A locked threat that is never unlocked delivers no consequence** --
  the same rule a removed threat follows. It was never on the board.
- **A round with nothing but locked entries completes at once** and the
  montage moves on, because `RoundComplete` already ends a round with
  nothing available. That is the intent: there is nothing there to do.
- **The parser polices both directions.** An `Unlock` clause that names no
  locked entry of the montage warns; a `(Locked)` entry that nothing
  unlocks warns. Either one is a dead end the party would never see.
- **The console is the record.** A hidden unlock leaves no player-visible
  trace, so `ApplyEffects` `printf`s each one, the party-size draw log
  names locked entries it kept, and `/eotwmontage state` prints
  `EncounterMontage.DescribeLocks` -- every locked entry with `locked` or
  `UNLOCKED`, plus any unlock key that matched nothing.

Implementation:

- `EncounterScript.lua`: `entry.locked` (heading tag parsing now loops over
  a comma-separated tag list), `EncounterScript.MatchKey`,
  `ParseUnlockClause`, `DescribeUnlock`, the `unlock` effect kind (with
  `name` and `key`), the two post-parse warnings, `(locked)` in the
  `/eotwscript` dump, and `ChooseRemovedEntries` skipping locked entries.
- `EncounterMontage.lua`: `montage.unlocked = { [entryKey] = true }`,
  `EncounterMontage.EntryUnlocked` (consulted by `EntryHidden` and
  `EntryAvailable`), the `unlock` branch of `ApplyEffects`, the
  end-of-montage consequence list skipping still-locked threats, and
  `EncounterMontage.DescribeLocks` for `/eotwmontage state`.
- `EncounterMontageStage.lua`: `SyncEntries` counts `m.unlocked` and, when
  the count changes without a full rebuild, sweeps `AddEntriesForRound`
  over **every** round up to the current one (not just new ones -- an
  unlock may free a card the party walked past two rounds ago). The
  `m_cards` check makes that a no-op for everything already up, and the
  new card arrives with the usual materialize ramp.
- Tests: `tests/encounter_script_test.lua` (289 checks, up from 260).

### The script validator panel (DECIDED + BUILT 2026-09-20; Lua only; VERIFIED live in the authoring game against the real week document)

User direction (2026-09-20): a simple developer tool that reads a week's
document and validates it -- showing every beat, summarizing them, and
showing which rules were matched -- written in Lua so it reuses the
runtime's own validation and cannot drift from it.

`EncounterOfTheWeek/EncounterScriptValidator.lua` registers a dev-only
dockable panel, **Encounter Script** (Panels > Development Tools, or
`/eotwvalidate`). It is `devonly = true`, so it follows the same
`devmode()` gate as the Character Inspector rather than needing a flag of
its own.

It shows, for a document picked from a dropdown of every markdown journal
document (the current map's script marked `[this map]` and selected):

- a summary: beats, entries, options, **rules matched**, text-only
  clauses, problems;
- **Problems** -- what will not work;
- **Text-only clauses** -- prose the grammar did not match, kept separate
  because it is usually deliberate and would otherwise bury everything
  else (the live week raised 50 warnings, 48 of them prose);
- **Script** -- every beat, round, entry (with its `(Required)` /
  `(Locked)` / `(Temporary)` tags), option, roll and tier. Each tier and
  `Consequence:` line is shown as the players read it with the recognized
  clauses lit green, and under it one line per effect saying in plain
  English what the engine will do -- `(hidden)` prefixed when the clause
  was braced;
- **Names** -- every item, monster, object asset and zone keyword the
  script names, with whether the engine can find it.

Nothing in it re-implements a rule. The highlighting is
`EncounterScript.MarkupRules`, the effect lines are
`EncounterScript.DescribeEffect`, and the lookups are the runtime's own
`EncounterMontage.FindGear` / `FindMonster` and
`EncounterZones.FindObjectAsset` / `FindKeyword` -- so it is 1:1 with what
a montage will actually do by construction.

On top of the parser's warnings it adds the checks a pure module cannot
make: the four name lookups above, and each power roll's `Attr (Skills)`
through `EncounterScript.ParseAttr` -- catching a characteristic that
matched nothing (the test has nothing to roll) and a name in the
parentheses that is not a `Skill.skillsDropdownOptions` entry, which is
the silent trap this document has warned about since the grammar landed.

Two layout notes worth keeping: an indented row must take the indent out
of its own width (`width = "100%-<indent>"`), or a `100%` label with a
left margin overflows the panel and clips its own right-hand words; and
`BuildReport` builds real `gui.Label`s, so calling it from the console
without parenting the result floods the dev console with orphan-panel
warnings.

Found on its first real run, in the live week document: a `|` line at 117
that is not a power roll header, and `## Befriend Them` at 125 written
with two hashes instead of three -- so it parsed as a malformed entry
heading and its option was dropped.

### Temporary entries (DECIDED + BUILT 2026-09-20; Lua only; parser unit-tested with the bundled interpreter; runtime UNTESTED live)

User direction (2026-09-20): an entry should be able to be marked
`(Temporary)`, meaning it expires at the end of the round it appears on --
and for a threat, that its consequence is carried out at the end of that
round if it was not vanquished.

```
## Threat: Goblin Scouts (Temporary)

They will raise the alarm if you let them go.

Consequence: Each party member loses 3 stamina
```

This is the one exception to the rule that entries persist into every later
round (user direction 2026-09-18).

Decisions (2026-09-20):

- **"The round it appeared in" is not always the round that declares it.**
  A plain temporary entry expires at the end of `entry.round`. A
  `(Locked, Temporary)` one expires at the end of the round its `Unlock`
  landed in, when that is later -- it cannot be carried off before the
  party has ever seen it. `montage.unlocked` therefore records the ROUND
  of each unlock rather than a bare flag, and
  `EncounterMontage.EntryAppearRound` is the one place the rule lives.
- **Expiry happens at the round boundary**, in the host's
  round -> round+1 transition, before the round number moves. An expired
  entry is then hidden and unapproachable for good
  (`EncounterMontage.EntryExpired`, consulted by `EntryHidden` and
  `EntryAvailable`), and its card fades out with the round's dealt-with
  ones (`RetireDoneEntries`).
- **A temporary entry in the LAST round is left to the normal
  end-of-montage consequences phase**, which is the same moment and
  presents each threat properly, one at a time. So `ExpireTemporaryEntries`
  only runs on a round-to-round transition, and the end-of-montage
  consequence list skips anything already expired so nothing pays twice.
- **The party is told.** Unlike `(Required)` and `(Locked)`, which are
  bookkeeping and never shown, a temporary entry's card carries its own
  line -- "Gone at the end of this round", or "... deal with it or face
  the consequence" for a threat that has one. A deadline the party cannot
  see is not a deadline.
- **A mid-montage consequence needs somewhere to be read out.** The
  consequences phase never runs mid-montage, and the between-turns panel
  deliberately ignores consequence log lines. So an expiry's log line is
  marked `expired = true`, and the stage opens the new round with the run
  of them that just landed ("Goblin Scouts was left unresolved." plus the
  applied lines) in place of the last hero's result.
- **A temporary entry is removable by a party-size directive** like any
  other, unless it is also `(Required)`. A removed one never appeared, so
  it never expires and never pays a consequence.

Implementation:

- `EncounterScript.lua`: `entry.temporary`; the heading-tag parse is now a
  set of recognized words rather than two booleans, so the three tags
  combine in any order and an unrecognized parenthesis still stays in the
  name. `(temporary)` in the `/eotwscript` dump.
- `EncounterMontage.lua`: `montage.expired`, `montage.unlocked[key]` now
  the round, `EntryAppearRound`, `EntryExpired`, `ExpireTemporaryEntries`
  (called from the round transition), the `expired` skip in the
  end-of-montage consequence list, and `DescribeTemporary` for
  `/eotwmontage state`.
- `EncounterMontageStage.lua`: the deadline line on the card (with its own
  `eotwEntryStatus deadline` style), `RetireDoneEntries` retiring expired
  cards, and the expired-consequence run at the top of the new round.
  `CreateEntryCard` builds its children as a list now -- a conditional
  child inline in the constructor would have put a nil in the middle of
  the array and silently dropped the status label.
- Tests: `tests/encounter_script_test.lua` (342 checks, up from 332).

### Standing edges and banes: "Edge on <option>" (DECIDED + BUILT 2026-09-20; Lua only; parser unit-tested with the bundled interpreter; runtime UNTESTED live)

User direction (2026-09-20): a power roll outcome should be able to put an
edge on another test of the montage, by name, **for all players**:

```
## Opportunity: Goblin Scouts

### Spot Them

|Watch Test: Intuition (Alertness)
|You fail at the test
|+1 malice. {Edge on Capture Them}
|You spot them first. {Double Edge on Capture Them}

## Opportunity: Capture the Goblin

### Capture Them

|Hunting Test: Agility or Intuition (Track, Alertness)
|You scare them off
|You capture them with a consequence => A hapless goblin was trying to stalk you! You capture it! +1 malice {Unlock Interrogate the Goblin}
|You capture them => A hapless goblin was trying to stalk you! You capture it! {Unlock Interrogate the Goblin}
```

`Edge`, `Double Edge`, `Bane` and `Double Bane` are all accepted, with or
without a lead-in (`an edge on ...`, `you gain an edge on ...`, `the party
has an edge on ...`, `each party member gains ...`).

Decisions (2026-09-20):

- **This is not a rider.** A `|Edge: you speak Caelian` rider is weighed
  against the acting hero's own facts; a standing edge applies to whoever
  takes the test, no questions asked. They stack: a hero who also meets an
  Edge rider rolls with both, and the roll nets edges against banes the way
  any other pair does.
- **The target is an `### option` name**, not an entry name -- "that test"
  in the user's wording. Matched with `EncounterScript.MatchKey` (case,
  spacing, a leading "the" and trailing punctuation ignored), the same key
  `Unlock <name>` uses. Two entries that both name an option `Ask for Aid`
  therefore share a grant; distinct names are the author's job, and the
  parser cannot tell the two cases apart.
- **Grants accumulate rather than cap.** Each one becomes its own pre-ticked
  chip in the roll dialog, exactly as an Edge rider does, and the engine's
  power-roll maths nets and caps them. Nothing clamps at parse or apply
  time.
- **They last the beat.** The grants live in the per-beat montage state, so
  `/eotwmontage reset` clears them and a later beat starts clean.
- **The parser polices the name**: an `Edge on <name>` that matches no
  option of the montage warns, and one written in a narrative beat warns.
- Written braced (`{Edge on Capture Them}`) the grant is silent, which is
  the usual shape; unbraced it reads "The party has an edge on Capture
  Them" in the turn summary and the log. Either way it is `printf`d, and
  `/eotwmontage state` prints `EncounterMontage.DescribeTestMods`.

Implementation:

- `EncounterScript.lua`: the `testmod` effect kind (`effect` = the rider
  effect key, `name`, `key`), `ParseTestModClause` -- matched FIRST in
  `ParseClause`, because the generic `you gain <qty> <item>` rule would
  otherwise read "you gain an edge on Capture Them" as an item called
  "edge on Capture Them" -- `DescribeTestMod`, and the option-name check in
  the post-parse pass.
- `EncounterMontage.lua`: `montage.testmods = { [optionKey] = { {effect,
  entryName, at}, ... } }`, the `testmod` branch of `ApplyEffects`,
  `EncounterMontage.OptionTestMods`, and `RiderVerdict` -- which now
  returns a verdict when an option has grants even with no riders of its
  own, and folds each grant in as an applied rider so the roll dialog's
  chips (`TestRiders.AppendModifiers`) and the boon/bane counts pick it up
  with no special case. `DescribeTestMods` for `/eotwmontage state`.
- `EncounterMontageStage.lua`: `GrantedRows` puts an always-lit
  "Edge: earned at Goblin Scouts" line under the option's own rider rows.
- Tests: `tests/encounter_script_test.lua` (313 checks, up from 289).

- **Effect clauses**: each tier line is split on `.`, `,` and `;` and each
  clause is matched case-insensitively against the grammar below. Quantities
  are digits or `one`..`ten`; `a`/`an` = 1.

  The splitter keeps each clause's POSITION (`SplitClauseSpans` ->
  `EncounterScript.ParseEffectSpans`, 1-based inclusive byte offsets into
  the untouched line), which is what lets a display point at the words it
  understood: `EncounterScript.MarkupRules(text, open, close)` wraps every
  clause whose effect is mechanical (`EffectIsMechanical` -- everything but
  `narrative`) and leaves the flavour, the punctuation and anything
  unrecognized exactly as written. The tags are the caller's, so the parser
  stays engine-free and testable.

  **Hidden clauses: `{...}`** (user direction 2026-09-20). Anything a tier
  line (or a `Consequence:` line) wraps in braces is parsed and applied
  exactly as if it were written plainly, but it is never shown to a player.
  `|You gain a Rope. {Unlock the Old Mill}` reads "You gain a Rope." on the
  stage, in the roll dialog's power table and in the montage log, and still
  unlocks the Old Mill. The braces do not have to wrap a whole clause list
  and may sit mid-line -- `|You gain a Rope, {Unlock the Old Mill}, and it
  squeals!` shows "You gain a Rope, and it squeals!" -- because the removal
  tidies up the separators it stranded. An unterminated `{` hides the rest
  of the line. A wholly braced line shows nothing at all, which is the
  author's choice to make.

  Mechanically: `SplitClauseSpans` marks a braced span, so its effect comes
  back with `effect.hidden = true` (and its braces trimmed off, so the
  grammar sees the clause as written); `EncounterScript.VisibleText(text)`
  is what a display shows, and `TierDisplayText` and `MarkupRules` already
  route through it. `EncounterMontage.ApplyEffects` applies a hidden effect
  like any other and then takes back whatever it appended to `applied`, so
  no turn summary or montage log line carries it. The raw line, braces and
  all, is what `/eotwscript` dumps and what the journal shows the author.

  | clause | effect |
  |---|---|
  | `you gain <qty> <item>` | give `<item>` x qty to the acting hero |
  | `each party member[s] gain[s] <qty> <item>` | give to every hero |
  | `you lose <n> stamina` | acting hero takes n damage |
  | `each party member[s] lose[s] <n> stamina` | every hero takes n damage |
  | `you heal <n> stamina` (also `regain`/`recover`; `each party member heals ...`) | heal the acting hero / every hero |
  | `you gain <n> temporary stamina` (also `each party member gains ...`) | temporary Stamina, taking the higher of old and new (Draw Steel: it does not stack) |
  | `[at the start of the next combat[,]] you gain <n> surge[s]` (also `each party member gains ...`) | banked on the script document and paid out when the encounter's combat starts |
  | `your recovery value is increased by <n>` (also `+<n> recovery value`, `each party member's recovery value ...`) | an ongoing effect ("Montage Boon: Recovery Value +N") with an `attribute`/`recoveryvalue` modifier, until the next respite |
  | `you lose <n> recovery`/`recoveries` (also `each party member loses ...`) | n recoveries off the hero's pool, with no Stamina back for them. A hero with none left loses nothing |
  | `[+]<n> hero token[s]` (also `you gain <n> hero tokens`) | the party's hero-token pool += n |
  | `[+]<n> intelligence` (also `you gain <n> intelligence`, `the party gains ...`, `each party member gains ...`) | the party's shared Intelligence pool += n, spent on the Tactical Preparation screen. Only a script that unlocked the feature has a pool; the parser warns about a clause with no `Unlock: Intelligence` behind it (see "Intelligence and Tactical Preparation") |
  | `[+]<n> malice` | malice pool += n |
  | `a`/`an <monster> joins you` | spawn `<monster>` as the acting player's ally |
  | `the threat is vanquished` (also `you vanquish the threat`) | the threat is resolved |
  | `you begin the encounter surprised` (also `you start the next encounter surprised`, `you are surprised`, `the party begins ... surprised`) | next encounter: monsters go first, every creature on the heroes' side (heroes + allies) starts Surprised |
  | `you surprise the enemy`/`enemies` (also `the enemy is surprised`) | next encounter: heroes go first, every monster starts Surprised |
  | `you cannot be surprised` (also `can't`, `you are immune to surprise`, `the party ...`, `each party member ...`) | party-wide: a `surprised` outcome still loses the initiative, but NO hero or ally takes the Surprised condition, and that outcome is ANNOUNCED as "The heroes will lose initiative, but they cannot be surprised" |
  | `the encounter begins with a fair roll` (also `combat starts with ...`, `a fair roll for initiative`, `initiative is rolled normally`, `you roll for initiative [normally]`, `you begin the encounter on even footing`/`terms`, `you are no longer surprised`, `the party is ...`) | takes back what the montage decided AGAINST the party -- the Surprised condition and a `lose`/`surprised` outcome -- and nothing else; an enemy already surprised stays surprised and a `win` still stands (see "Taking an unfavourable initiative back") |
  | `you win [the] initiative` | next encounter: heroes go first, no die |
  | `you lose [the] initiative` | next encounter: monsters go first, no die |
  | `you know the stamina of <keyword>` (also `learn`, `the party knows ...`, `each party member knows ...`; `goblins` -> `goblin`) | monster intelligence: the exact stamina of every monster carrying that stat-block keyword, in Monster Info and on its token bar, for the rest of the campaign (see "Montage outcome: You know the Stamina of Goblins") |
  | `reveal <zone>s [during the next combat]` (also `reveal the <zone> zones`, `the <zone>s are revealed ...`; the timing suffix is optional flavour) | the `<zone>` markup zones (an environmental keyword by name, e.g. Trap) turn player-visible when the encounter beat comes, and every client's zone overlay switches that type on (see "Encounter setup instructions and zone reveals") |
  | `unlock <name>` (also `unlocks`, `you unlock ...`, `the party unlocks ...`) | a `(Locked)` entry of this montage joins the board (see "Locked entries") |
  | `edge on <name>` (also `double edge`, `bane`, `double bane`; `an edge on ...`, `you gain an edge on ...`, `the party has an edge on ...`, `each party member gains ...`) | a standing edge/bane on the `### <name>` test of this montage, for whoever takes it (see "Standing edges and banes") |
  | `you fail (at )?the test`, anything unmatched | narrative only (shown, no effect) |

  The four **initiative** clauses (user direction 2026-09-18) work on power
  roll tiers and on `Consequence:` lines alike, and are the same effect kind
  (`initiative`, `outcome = "win"|"lose"|"surprise"|"surprised"`). The last
  one applied during the montage wins **for who goes first** -- a later tier
  or consequence overrides an earlier one. "Surprise" means losing
  initiative PLUS the Surprised condition on every creature of the losing
  side.

  **Surprise itself is sticky, and lands immediately** (bug found live
  2026-09-19, fixed the same day). The two halves are tracked separately:

  - `doc.data.initiative` -- who goes first. Last one wins, as above.
  - `doc.data.surprised = { party = {entryName, at}, enemy = {entryName, at} }`
    -- who is Surprised. Set by any `surprise`/`surprised` clause and never
    cleared by a later initiative clause; only surprise immunity takes it
    back.

  **Being surprised implies losing the initiative, and it outranks a plain
  `win`/`lose` clause however late that clause landed** -- a montage that
  says "the heroes begin the encounter surprised" and later "the heroes win
  initiative" must not put a surprised party first. So `immediateResult` is
  decided from the outcome and then overridden: party surprised ->
  `"monsters"`, enemy surprised -> `"heroes"`. A montage that surprised BOTH
  sides has no side to favour and falls back to the last outcome. The
  override applies even under surprise immunity: the heroes still lose the
  die, they just do not take the condition.

  **And the announcement has to say both halves** (reported live 2026-09-20).
  A party that had already been told "the heroes cannot be surprised" and then
  read "the heroes will begin the encounter surprised" on the next consequence
  had every reason to believe the boon had been forgotten -- the condition was
  correctly withheld, but nothing on the stage said so. When immunity is already
  on the document, a `surprised` clause is now announced as **"The heroes will
  lose initiative, but they cannot be surprised"**.
  `EncounterScript.DescribeInitiativeOutcome(outcome, immune)` takes the second
  argument; `ApplyEffects` reads `ctx.doc.data.noSurprise` ONCE at the top of the
  `initiative` branch (into `surpriseImmune`, before the branch writes anything)
  and uses it for both the condition guard and the wording, so the two can never
  disagree. `surprise` (the enemy) is untouched by immunity and reads as before.

  **Taking an unfavourable initiative back (user direction 2026-09-20).**
  `The encounter begins with a fair roll` undoes what the montage decided
  against the party, and only that:

  - `doc.data.surprised.party` is dropped and the Surprised condition comes
    off the heroes on the spot (not at combat start);
  - a `lose` or `surprised` outcome is replaced with the new outcome
    `"even"`, which the encounter beat reads exactly like no decision at
    all -- `immediateResult` stays nil and initiative is rolled;
  - `doc.data.surprised.enemy` and a `win`/`surprise` outcome are left
    alone, so a party that had already earned the jump keeps it (user
    direction: "it shouldn't stop them from surprising them if they already
    would"). When the outcome it finds is already favourable it changes
    nothing and says so in the console.

  It is **not** `you cannot be surprised`, which withholds the condition but
  still hands the initiative to the monsters, and it is **not** sticky: it
  clears what is on the board when it lands, and a later
  `you begin the encounter surprised` wins the way any later clause does.
  Reach for the immunity clause when the party should be warded for the
  rest of the montage, and this one when a single bad outcome should be
  wiped off.

  Deriving the condition from the outcome alone was wrong: a montage that
  handed out `Goblin Scouts -> the heroes begin the encounter surprised` and
  then `Gathering Darkness -> the heroes lose initiative` kept only the
  second, and because both mean "the monsters go first" nothing looked
  wrong -- the party watched the montage announce surprise and then entered
  combat with no condition on anyone. Both consequences now land.

  And a `surprised` clause puts the condition on every hero **the moment it
  is announced** (user direction 2026-09-19), rather than at combat start
  minutes later: `EncounterMontage.ApplyEffects` calls the file-local
  `SetHeroesSurprised(true, ...)` (Surprised, `force`, duration `eoe`, via
  `token:ModifyProperties` under the host elevation `ApplyEffects` already
  holds). `eoe` survives the rest of the montage and the narrative beat, and
  `creature:EndCombat` clears it when the encounter ends. The enemy half of
  `surprise` still waits for combat start -- the encounter's monsters are
  not spawned yet. Surprise immunity earned LATER in the same montage lifts
  the condition again (`SetHeroesSurprised(false, ...)` in the `nosurprise`
  branch), and the montage test reset does the same.

  Item names resolve against `tbl_Gear` by name (case-insensitive; a
  trailing `s` is tried without). Monster names resolve against
  `assets.monsters[*].name` (case-insensitive). Both are looked up at RUN
  time on the host, not at parse time, but the parser records every name
  it saw so the validators can check them.
- The parser returns `{beats, warnings}`; warnings name the line and the
  problem (unknown beat kind, entry outside a beat, option with no power
  roll, unrecognized clause). A dev chat command, `/eotwscript`, prints the
  parse of the current map's script with its warnings, and resolves the
  item/monster names against the game's tables. The publisher gets the same
  checks later (a Python port of the grammar -- a second copy that must
  stay in step, like the map-name rule).

### Encounter setup instructions and zone reveals (DECIDED + BUILT 2026-09-19; Lua only; parser unit-tested; setup/reveal/reset VERIFIED headlessly in the authoring game over MCP; the live encounter beat and a player client's overlay UNTESTED; UNCOMMITTED)

User direction (2026-09-19): traps on the map. The author paints "Trap"
markup zones wherever a trap COULD be (the Trap environmental keyword is
in the module; the live Encounter map has six Trap zone records covering
15 tiles) and writes, under `# Encounter`:

```
Trap: Place 4 Snare Trap objects in Trap zones and delete other Trap zones.
```

When the encounter beat comes, the host picks four of those tiles at random,
places a "Snare Trap" object on each, and removes every other Trap tile from
the map, so the only Trap zones left are the ones with a trap in them. The
zones stay hidden from the players (the Trap keyword's default is not
player-visible) -- unless a montage test earned `Reveal Traps during the
next combat`, in which case the surviving zones become player-visible and
every player's zone overlay is switched on so they can see where the snare
traps are.

**Grammar** (`EncounterScript`, unit-tested in `tests/encounter_script_test.lua`):

- Under `# Encounter`, every LINE of the form `Label: Place <n> <Object>
  object[s] in [the] <Zone> zone[s] [and delete|remove [the] other|remaining|
  unused|extra <Zone> zone[s]]` is a setup instruction
  (`EncounterScript.ParseSetupInstruction` -> `{ kind = "placeobjects", label,
  qty, object = "Snare Trap", zone = "trap", deleteOthers }`, collected in
  `beat.setup`). `<n>` is digits or `one`..`ten`. `<Object>` is an object
  asset's display name (its `description` -- object nodes expose no `name`).
  `<Zone>` is an environmental keyword name, lower-cased and singularised. A
  delete clause naming a different zone is rejected. Any other `Label:` line
  there is kept as `kind = "unknown"` with a parser warning, so the format can
  grow. Adjacent lines are one paragraph in the journal, so the parser splits
  the paragraph and reads one instruction per line. `/eotwscript` lists them
  as `setup Trap: place 4 x 'Snare Trap' in trap zones, delete the other trap
  zones`.
- The montage/narrative clause `reveal <zone>s` (`EncounterScript.ParseRevealZonesClause`
  -> `{ kind = "revealzones", zone = "trap" }`): `Reveal Traps`, `Reveal the
  trap zones`, `The traps are revealed during the next encounter`, with an
  optional trailing `during|in the next <word>` / `during|in combat` / `for the
  next <word>`. A multi-word name is narrative. Described as "The Traps will be
  revealed during the next combat"; mechanical, so the stage colours it.

**Runtime** (`EncounterOfTheWeek/EncounterZones.lua`, registered in the codemod
after `EncounterScript`; all Lua, no engine change):

- `EncounterZones.RunEncounterSetup(beat)` -- host, called by the encounter
  beat in `RunScriptBeat` BEFORE `SpawnEncounterMonsters`, so the traps go
  down behind the stage with the monsters. Idempotent: once
  `doc.data.zoneSetup` exists it returns at once, so the beat may call it
  every tick. Per instruction: the object asset by name
  (`FindObjectAsset`), every zone record of the keyword on the current map
  (`ZoneRecords`, matching by keyword id with the record's `keywordName` as
  the heal-by-name fallback, skipping `category` surfaces/holes and negative
  floors), all their tiles pooled, `qty` drawn uniformly without replacement
  (`math.random`, on the host, once -- the result is what the document
  records), one `floor:SpawnObjectLocal(objectId, {posx, posy})` +
  `obj:Upload()` per tile (tile-centre convention: Loc (x,y) is world (x,y)),
  then with `deleteOthers` each zone record is rewritten to its drawn tiles
  (`SetMarkupZone` with a fresh deep copy; a record left with none is
  `RemoveMarkupZone`d). Everything runs under `ElevateToHostPermissions`
  (the EotW host is a player; zone and object writes are Director
  operations). A missing object or zone type is recorded as `entry.error`
  and logged; the beat carries on without traps rather than stalling.
- `EncounterZones.BankReveal(doc, zone, entryName)` -- called by
  `EncounterMontage.ApplyEffects` for a `revealzones` clause inside the
  change it already holds: `doc.data.revealZones[zone] = { entryName, at }`
  (TOP level, like `initiative`, so it survives the per-beat rebuild).
- `EncounterZones.ApplyPendingReveals()` -- host, called by the encounter
  beat after the spawn and BEFORE `DismissStage`, so the zones are on the map
  when the stage dissolves. For each banked type: every zone record of the
  keyword gets `playerVisible = true` (fresh copy + `SetMarkupZone`), the
  originals are kept, and the entry moves to
  `doc.data.zonesRevealed[zone] = { keywordid, at, entryName, original }`.
- `EncounterZones.ClientTick()` -- EVERY client, from the driver's 1 s poll
  in `EncounterOfTheWeek.lua` next to the montage `ClientTick`: for each
  `zonesRevealed` entry whose stamp this client has not applied, the keyword
  id is added to the user's `mapoverlay:shownzones` preference (the
  `;`-joined opt-in list the title bar's overlay menu manages; zone types
  default hidden, and a player client renders a zone only when it is BOTH
  `playerVisible` and opted in -- see `dmhub.GetMarkupZones` in
  `MapMarkupZoneRuntime.lua`). Applied once per stamp, so a player who turns
  the type off again afterwards is not fought.
- **Reset**: `EncounterMontage.ResetTest` (`/eotwmontage reset`) calls
  `EncounterZones.ResetMap(doc)` under its elevation -- deletes the placed
  objects (`floor.objects[objid]:Destroy()`, a networked delete) and puts
  every zone record the setup or a reveal touched back exactly as it was
  (`zoneSetup.original` / `zonesRevealed[*].original`) -- then clears the
  three document fields. Dev command `/eotwzones setup | reveal <zone> |
  apply | state | reset` drives the pieces alone in the authoring game.

**Verified 2026-09-19** in the authoring game over MCP (the new file
`dofile`d into the running app, no reload): the live document's `Trap:`
line parses; `FindObjectAsset("Snare Trap")` resolves (`0f85f34a`);
`RunEncounterSetup` placed 4 Snare Traps on 4 of the 15 Trap tiles and left
3 zone records covering exactly those 4 tiles, each object sitting on a
surviving tile; a banked reveal turned all 3 player-visible and added the
Trap keyword to the overlay preference (the stripes appeared on the map);
`ResetMap` removed the 4 objects and restored all 6 records / 15 tiles /
hidden. No console errors. NOT yet seen: the real encounter beat running it
in an EotW game, and a joiner client's overlay flipping on.

**Open ends**: the placed objects themselves are whatever the "Snare Trap"
asset is -- nothing here hides them from players or gives them a trigger;
that is the asset author's job. The publisher's validation (Phase 7 step
35) should resolve the object name and the zone keyword too.

### Runtime state and authority

A new shared document in the codemod, `eotwscript`, next to `eotwstate`:

```
{
  beat = 1,                      -- index into the parsed beat list (host-stamped)
  montage = {
    beatIndex = 1, round = 1, phase = "rounds" | "consequences" | "done",
    acted = { [heroCharid] = true },          -- this round
    taken = { [entryId] = true },             -- opportunities consumed
    vanquished = { [entryId] = true },        -- threats resolved
    turn = nil | { seq, userid, heroid, heroName, entryId,
                   status = "choosing"|"rolling"|"assist"|"assisting"|"resolved",
                   optionIndex, optionName, rollSeq, tier, total, natural,
                   tierText, applied = { "..." }, resolvedAt = serverTime,
                   attrid, skillid,          -- what the acting hero rolled with
                   baseTier, baseTotal,      -- the test's own result, pre-assist
                   assistOpenedAt,
                   assist = nil | { userid, heroid, heroName, skillid, skillName,
                                    status, rollSeq, tier, total, natural,
                                    outcome = "bane"|"edge"|"doubleedge" } },
    consequences = { entryId, ... }, consequenceIndex, lastApplied,
    requests = { [userid] = { seq, kind, time, ... } }, handled = { [userid] = seq },
    log = { { round, heroid, heroName, entryId, entryName, optionName, tier, total, applied }, ... },
    seq = n,
  },
  allies = { [heroCharid] = { charid, ... } },
  items = { [heroCharid] = { { itemid, name, qty }, ... } },
  initiative = nil | { outcome = "win"|"lose"|"surprise"|"surprised", entryName, at },
  surprised = nil | { party = nil | { entryName, at },   -- sticky; survives a later
                      enemy = nil | { entryName, at } }, -- initiative clause
  noSurprise = nil | { entryName, at },
  zoneSetup = nil | { at, entries = { {label, object, objectId, zone, keywordid, qty,
                      placed = { {objid, floorid, x, y}, ... }, error} },
                      original = { [zoneid] = {floorid, record} } },
  revealZones = nil | { [zone] = { entryName, at } },        -- banked "Reveal Traps"
  zonesRevealed = nil | { [zone] = { keywordid, at, entryName, original } },
  unlocked = nil | { [feature] = { name, entryName, at } },  -- "Unlock: Intelligence"
  intelligence = n,                                          -- the party's pool
  intelligenceLog = { { value, amount, who, note, at }, ... },-- the pool's history
  prep = nil | { ... },                                      -- Tactical Preparation
}
```

`items` is the hero's haul: every `you gain <qty> <item>` / `each party
member gains ...` clause that actually landed on that hero, in grant order.
It is written by `ApplyEffects` (host, inside the same open change that
applies the effect) next to the real inventory write, so the stage can show
the haul without walking every hero's inventory diff. A repeat grant of the
same item bumps `qty` in place rather than appending a second entry, so the
stage shows one icon per distinct item. Like `allies` it lives at the TOP
level -- the haul spans the whole montage, not one beat -- and
`/eotwmontage reset` clears it.

**Haul icons are live (BUILT 2026-09-19; UNTESTED live).** Hovering an icon
shows the item's full `CreateItemTooltip`. Until this change no tooltip
ever appeared on the stage: `UpdateStartZoneConfinement` suppresses every
tooltip on the client until combat starts, which covers the whole montage.
It now leaves them alone while `MontageStageExpected()` (a live montage or
narrative stage) is true; the start-zone shuffle after the stage still gets
the quiet. The hero's own player (`canControlAsUser`, so the Director too)
can drag an icon onto another hero's card to hand over ONE unit of the item
-- a stack takes one drag per unit -- via the `giveItem` request
`{ heroid, targetId, itemid }`. The host (`HandleRequest`) re-checks
ownership, that the item is in the hero's recorded haul AND still in their
real inventory (a used-up potion just drops off the haul), then moves it
between the two inventories with `GrantItem` +1/-1 and updates both haul
records (`RecordItem` / `UnrecordItem`). Any phase is fine; sharing loot is
never "not the moment". `CreateHeroCard` gained `dragTarget` /
`dragTargetPriority` / `dragTargets` pass-through opts for this; the card
lights up (`droppable`) only for an "item" drag from a DIFFERENT hero.

`initiative` lives at the TOP level (like `allies`), not under `montage`,
because `montage.*` is rebuilt for every montage beat while the outcome
must survive until the encounter beat starts combat. `/eotwmontage reset`
clears it with the rest.

Entry ids are `r<n>-<kind>-<slug>` (e.g. `r1-threat-dangerous-beasts`) so a
resumed client re-parsing the same text lands on the same ids.

**An id must never contain `/`.** Ids are used as document KEYS
(`montage.vanquished`, `.taken`, `.expired`, `.removed`), and the engine
builds a patch path by joining table keys with `/`
(`ScriptSerialize.BuildPathToJson`), unescaped. A `/` in a key is read as a
path separator by the server and by every other client, so
`vanquished["r1/threat/beasts"] = true` is stored as
`vanquished.r1.threat.beasts`: the host, which set the flat key in its own
Lua table, sees the threat vanquished, and nobody else ever does. Only the
FIRST such write per table survives -- empty -> non-empty makes
`LuaValuePatch` retransmit the whole node, so that key travels inside the
payload rather than in the path -- which is what made it look intermittent.
Ids used `/` until 2026-09-22; that was the cause of "the threat is gone for
me but still on the board for my players".

**Host-arbitrated, single writer for state.** Players never edit
`montage.*` directly; they stamp `requests[userid]` (each with a rising
`seq`) exactly like `proceedRequested` today, and the host tick validates
and applies. That keeps "one hero acts at a time" and "each hero once per
round" true under concurrent drags from several clients. The tick is the
existing map-script host tick; its `hostThinkInterval` drops from 2 to
0.5 s (a doc read when idle) so a drag answers within half a second.

Turn lifecycle:

1. **approach** (player): `{kind="approach", heroid, entryId}`. Valid when
   the hero's `ownerId` is the requester (or `"PARTY"` -- the authoring
   game's pregens), the hero has not acted this round, the entry has been
   introduced by the current round and is not taken/vanquished, and no
   turn is in flight. Host writes `turn = {status="choosing"}`. A `back`
   request from the same player withdraws the approach before choosing.
2. **choose** (same player): `{kind="choose", optionIndex}`. Host sets
   `status="rolling"` and stamps a fresh `rollSeq`. A `cancel` of that
   rollSeq (the roll dialog dismissed) returns the turn to choosing.
3. **roll** (the OWNING client, not the host): the client whose
   `loginUserid == turn.userid` sees a rolling turn whose `seq` it has not
   handled and rolls the way a characteristic clicked on the character
   panel does (`creature:ShowCharacteristicRollDialog`, user direction
   2026-09-18): a synthetic test ability (`ActivatedAbility.Create{isTest}`
   named after the option's roll) is displayed in the timeline sidebar and
   the roll dialog is embedded in its card (`CharacterPanel.DisplayAbility`
   + `EmbedDialogInAbility`, falling back to the standalone dialog when the
   sidebar is unavailable), with a `RollPropertiesPowerTable` of the
   option's tiers, `2d10 + best listed characteristic`, the Skilled +2 chip
   when the hero has a listed skill, the normal `GetModifiersForPowerRoll`
   edges/banes, and the roller as a synthetic single target so post-roll
   edges/banes refresh the tier. `completeRoll` stamps
   `requests[userid] = {kind="rolled", seq, tier, total}` and hides the
   card. The roller's machine is authoritative for the dice (Dice
   Reference), and the 3D dice are networked, so every client watches the
   same roll land. Strict rules already remove re-roll/edit affordances for
   players. UNRENDERED since the switch: confirm the sidebar draws above
   the stage (the centered dialog did).
   **Every other client gets the read-only remote copy of the dialog**
   (user direction 2026-09-18), the same one shown while a hero rolls on
   its combat turn. In combat that share begins in
   `CharacterPanel.HighlightAbilitySection`, gated on the token being on
   the current initiative turn (`ShouldShareAbility`); a montage has no
   queue, so `Timeline/AbilitySidebar.lua` gained
   `CharacterPanel.ShareDisplayedAbility(token, ability)` (begins the
   `abilityTimelineShare` share for the displayed card with no turn gate;
   still requires `canControl`) and the montage's launch calls it right
   after `DisplayAbility` succeeds. From there everything is the combat
   path: the embedded dialog's `BroadcastDialogState` writes `dialogState`
   (rollState, rollId, highlightedTier, tier texts) into the share, the
   remote sidebar renders the card + tier table with the header "<hero> is
   using <option roll>", and `hideAbility` clears the share 0.2 s after
   the card goes. FOUND on the first live look (2026-09-18): the remote
   card showed the modifiers and "2d10+2" but NO tier table, because
   `BroadcastDialogState` (`Timeline/EmbeddedRollDialog.lua`) only gathered
   `tierTexts` / `isPowerRoll` for roll types containing
   `ability_power_roll`; the montage (like a characteristic test) rolls
   `test_power_roll`. It now matches any `*power_roll`, so test, opposed,
   resistance and project rolls share their tiers too. Remote card
   otherwise VERIFIED to appear; tier table + live highlight UNTESTED
   after the fix.
4. **assist window** (host, optional -- see "Assisting a test" below): if
   the roll landed below tier 3 and some other hero could still help,
   `status="assist"` and nothing is applied yet. A `{kind="assist", heroid}`
   from that hero's owner moves it to `"assisting"`; the helper's client
   rolls and stamps `{kind="assistRolled", rollSeq, tier, total}`, which
   shifts the test's tier and falls through to resolve. `{kind="noassist"}`
   from the acting player (or the host's 30 s timeout) resolves on the
   test's own tier. With no eligible hero, or at tier 3, step 4 is skipped
   entirely and the roll resolves as it always did.
5. **resolve** (host, in an `ElevateToHostPermissions` coroutine): apply the
   chosen tier's clauses, record `acted[heroid]`, `taken[entryId]` for an
   opportunity, `vanquished[entryId]` when a clause says so, append to
   `log`, set `status="resolved"` with what was applied (the stage shows
   "+1 Healing Potion", "-6 Stamina", "+2 Malice", "Wode Elf Sentry joins
   Kira"). A resolved turn never blocks the next one (user direction
   2026-09-19: no waiting out a timer on a result already read):
   `EncounterMontage.TurnOver` treats `status="resolved"` as a free floor,
   so the next hero may approach at once -- the resolved view carries the
   same "Your move" hint as the idle view and its entry card reopens
   immediately. The next `approach` replaces `turn`; the round rollover
   clears it. There is no linger timer any more.
6. **round end**: when every hero has acted -- or nothing is left to
   approach -- `round += 1` and `acted` resets. Past the last round,
   `phase = "consequences"`; with no unvanquished threat, straight to
   `"done"`.
7. **consequences**: every threat never vanquished (across all rounds),
   one at a time. Anyone stamps `{kind="continue"}`; the host applies that
   threat's `Consequence:` clauses, advances `consequenceIndex`, and after
   the last sets `phase = "done"` -- the beat advances.

Effect application (host, elevated):

- item: `token:ModifyProperties{ execute = function() props:SetItemQuantity(itemid, current + qty) end }`
  on the target hero(es) (`current` from `inventory[itemid].quantity`).
- stamina: `props:InflictDamageInstance(n, "untyped", {}, "Montage: <entry>", {})`
  inside `ModifyProperties`, so the character panel's damage history and
  the Hero Death rule see it like any damage (fallback on error: a plain
  `damage_taken` bump clamped at max stamina).
- malice: `CharacterResource.SetMalice(GetMalice() + n, "Montage: <entry>")`.
  The malice resource is `clearOutsideOfCombat: false` so this works
  before combat, and Draw Steel ADDS its start-of-combat malice to the
  pool (`DSInitiativeRoll.lua`, "Start of Combat Malice") rather than
  re-seeding it, so montage malice carries into the fight with no banking.
- ally: `game.SpawnTokenFromBestiaryLocally(monsterid, loc, {fitLocation=true})`
  at the nearest free Start-zone tile to the hero (reuse
  `StartZoneTilesByDistance`/`NthFreeStartTile`), then `partyId` (if any)
  BEFORE `ownerId = turn.userid` (the partyId setter clobbers owner --
  see memory), `properties.eotwAllyOf = heroCharid`, `token:UploadToken()`,
  and `allies[heroCharid]` records the charid. The ally is player-controlled,
  so the Monster AI leaves it alone and its owner drives it in combat like
  a second hero.
- initiative: `ApplyEffects` (which now receives the open script `doc` in
  its ctx) writes `doc.data.initiative = {outcome, entryName, at}`, and for
  a surprise outcome also the sticky `doc.data.surprised.party`/`.enemy`,
  and the stage's applied list shows "The heroes will begin the encounter
  surprised" / "... surprise the enemy" / "... win initiative" / "... lose
  initiative" (`EncounterScript.DescribeInitiativeOutcome`). A `surprised`
  outcome puts the condition on the heroes there and then
  (`SetHeroesSurprised`); nothing else touches a token yet. When the
  encounter beat starts combat, `StartEncounterCombat` reads
  `EncounterMontage.GetInitiativeOutcome()` for the die -- win/surprise ->
  `immediateResult = "heroes"`, lose/surprised -> `"monsters"`, then
  overridden by the surprised side as above -- and
  `EncounterMontage.GetSurprisedSides()`, **separately**, for the condition:
  party -> `sides.playerTokens` (heroes AND montage allies, per
  `GatherCombatSides`), enemy -> `sides.monsterTokens`, unioned when a
  montage managed both. Re-applying to heroes who already took it in the
  montage is idempotent; the pass at combat start is what catches the allies
  and the monsters, who did not exist when the clause landed. Both go to the
  **core hook** `Encounter.StartCombatWithTokens`
  (`Draw Steel UI/DSInitiativeRoll.lua`), which gained those two optional
  args: it runs the file-local `SetTokenSurprised` (now forward-declared;
  Surprised, duration `eoe`, exactly what the Prepare Combat dialog's "All
  Surprised" slider does, and at the same pre-queue moment) on each listed
  token, then `showDrawSteelBanner(immediateResult)` -- the banner's
  existing forced-result path, so the queue is created with the right side
  first and no die is offered. The call is wrapped in
  `ElevateToHostPermissions` because the EotW host is a player and the
  condition also goes on monsters. Against a retail core without the hook
  the extra args are ignored and the normal roll happens (graceful, but the
  outcome is then lost -- the hook must ship with the core before a week
  uses these clauses).

### Assisting a test (DECIDED + BUILT 2026-09-18; Lua only; luac-clean; UNTESTED live)

User direction (2026-09-18): a hero who is not taking a montage beat can
still be part of it. Once a test has been rolled and fallen short, a second
hero may step in and lend a hand, at the cost of their own turn this round.

**When it is offered.** After the acting hero's roll resolves -- the test is
rolled FIRST, not assisted blind -- and only when it landed **below tier 3**
and at least one hero is eligible. At tier 3 (or the crit tier) the turn
resolves immediately as it always did. Nothing is applied while the window is
open: the assist modifies the test's own result, so the effects wait for it.

**Who is eligible.** A hero who

- is not the hero taking the test, and has not acted this round;
- is trained in one of the skills the option's power roll lists (the
  parenthesised list of `|Name: Attr (Skill, Skill)`), and
- that skill is **not the one the acting hero is already using** for their own
  Skilled +2. Two heroes cannot bring the same skill to bear on one test; the
  acting hero uses at most one skill, so the rest of the list stays open.

The acting hero's characteristic and skill are reported by their own client in
the `rolled` request (`attrid`, `skillid`) -- the roller already computes both
to build its dialog -- and the host validates eligibility from them.

**The assist roll.** Dragging an eligible hero into the assist slot stamps
`{kind="assist", heroid}`; the host picks that hero's qualifying skill, writes
`turn.assist` and moves the turn to `"assisting"`. That hero's client rolls
`2d10 + <the characteristic the test used>` with the ASSISTING hero's own
modifier and an automatic Skilled +2 for the skill they are assisting with
(user direction: "the same characteristic, but with their skill, so they are
automatically skilled on it"), through the same timeline-sidebar presentation
and share as any montage roll, against a fixed tier table that is never
authored:

| tier | outcome |
|---|---|
| 1 (11 or lower) | the test has a bane on it |
| 2 (12-16) | the test has an edge on it |
| 3 (17+) | the test has a double edge on it |

**What it does to the test.** `EncounterMontage.ApplyAssistToTier` applies the
Draw Steel edge/bane rules to the result already on the table rather than
re-rolling it: a bane is -2 on the total, an edge +2 (re-tiered at the 12 and
17 thresholds `RollUtils.DiceResultToTier` uses), and a double edge raises the
tier by one, capped at 3. So an assist can make things **worse** -- a bane can
drag a tier 2 back to tier 1. The turn then resolves on the new tier and its
clauses are applied as usual.

**One assist per test** (user direction): the slot fills and closes. The
assisting hero is marked as having acted this round whatever they rolled.

**An empty window is never shown** (user direction 2026-09-19). The `rolled`
branch only opens it when `EligibleAssistants` is non-empty, the host tick
closes an open one the moment the list goes empty (no waiting out the clock),
and the stage renders "Taking the result..." rather than an empty slot if it
ever catches that frame.

Found the first time this ran: the window opened with "Nobody here has an
applicable skill." because the STAGE's candidate list was empty while the
host's was not. `EncounterMontage.CurrentBeat()` returns `(beat, script)`, and
it was being passed as the trailing argument of
`EligibleAssistants(m, CurrentBeat())` -- Lua expands BOTH values there, so
`script` arrived as the `heroes` parameter and `ipairs` walked it as empty,
making every hero silently ineligible. Bind the beat to a local before
passing it. Worth remembering generally: every multi-return engine helper is
a trap in a trailing argument position.

**Closing the window.** The acting player gets a "Take the result" button
(`{kind="noassist"}`, refused from anyone else); the host also closes the
window after `ASSIST_WINDOW_SECONDS` (30) so an absent party cannot wedge the
montage. A cancelled assist roll (`{kind="assistCancel"}`) returns the turn to
`"assist"` and frees the slot -- the helper has not spent their turn. A slot
that is claimed and then never rolled (the dialog closed some other way, or
the client went away) is handed back after `ASSIST_ROLL_SECONDS` (90), after
which the 30 s window clock -- which never restarts -- closes it out. Between
them there is no state the turn can be parked in indefinitely.

Related tightening made here: `{kind="back"}` now only withdraws an approach
while the turn is still `"choosing"`. It used to fire at any status short of
resolved, which after this change could have thrown away a rolled test -- and
an assist already spent on it.

**On the stage.** While the window is open the turn panel shows the option
with the rolled tier landed, the line "<hero> rolled tier N (total)", and an
**assist slot** (`eotwAssistSlot`, a `dragTarget`) naming who could help and
with which skill. Every eligible hero's card -- not just the local user's --
wears a pulsing "!" badge at its top centre (`eotwAssistBadge`; the trigger
corner owns the top left and the condition chips the top right). Dragging or
clicking a hero now carries a **mode**, `"approach"` or `"assist"`, so a hero
picked up to assist does not light up the Opportunity/Threat columns and a
hero picked up to take a beat does not light up the assist slot; the
click-a-hero-then-click-the-target path works for both. While the assist
rolls, the panel shows the assist tier table with the live tier highlight
(`LiveTierRows` over `EncounterMontage.ASSIST_TIERS`). The resolved panel adds
one line -- "Kira helped: an edge -- tier 1 becomes tier 2" -- and the log
entry records `assistName` / `assistOutcome`.

**Files.** `EncounterOfTheWeek/EncounterMontage.lua` (the `ASSIST_TIERS` /
`ASSIST_OUTCOMES` tables, `OptionSkills`, `AssistSkillFor`,
`EligibleAssistants`, `LocalUserCanAssist`, `ApplyAssistToTier`, the
`assist` / `assistRolled` / `assistCancel` / `noassist` requests, the host
timeout, and a `ResolveTurn` helper factored out of the `rolled` branch so
the assisted and unassisted paths close a turn identically) and
`EncounterOfTheWeek/EncounterMontageStage.lua` (the slot, the badge, the drag
mode, the assist branches of the turn panel). The roll launcher was factored
into a shared `ShowMontageRoll` plus `LaunchRoll` / `LaunchAssistRoll`, with
the Skilled-chip and best-characteristic loops pulled out as
`ApplySkilledModifier` / `BestCharacteristic`. No parser change -- the assist
tiers are fixed, not authored -- and no engine change.

### Combat with allies

- `GatherCombatSides`: a `playerControlled` non-hero token goes on the
  players' side (today it is dropped from both lists).
- `CountLivingHeroes` / defeat: unchanged -- allies are not heroes; the
  party is defeated when the HEROES are down.
- Victory: `StartCombatWithTokens` gets the allies in `playerTokens`, so
  the live encounter's evaluators count them as the players' side. VERIFY
  that `CheckVictory` does not count a surviving ally as a monster.
- The AI: `MonsterAI` acts on non-player tokens; an owned ally is never
  picked up. VERIFY with `/testai`.
- Hero Death rule: applies to heroes only (`IsHero()`); an ally that dies
  is just removed by the normal death flow.

### The stage (UI)

A full-screen presentation shown to every client while the montage beat
is live, drawn over the map (the map itself is idle during a montage; the
Start-zone confinement stays on underneath):

- **Mounting**: `GameHud.RegisterPresentableDialog{ id = "eotwmontage",
  keeplocal = false, create = ... }` and the host presents it with
  `GameHud.PresentDialogToUsers` when the beat starts (re-presenting each
  tick it finds it missing), hides it with `HidePresentedDialog` when the
  beat ends. The presented-dialog document persists, so a late joiner or a
  resume gets the stage back. Read in source (`GameHud.lua:1449-1570`): the
  receiving `refreshGame` instantiates the registered dialog on EVERY
  client with no Director gate, and the presenter writes the document
  through an ordinary doc change, so a player host can present. Still to
  see live. Fallback if it misbehaves: an `overlayPanel` slot on
  `GameHud.RegisterCustomInterface`.
- **Backdrop**: the scene image, full-bleed (`bgimage`, aspect-fit like
  `FullscreenDisplay`), dimmed under the columns. No dependency on the
  FullscreenDisplay document.
- **Left column: Opportunities**, **right column: Threats** of the current
  round: name, description, a status ribbon (available / taken /
  vanquished). Threat cards carry the malice diamond
  (`CreateMaliceDiamond` in the hud, to be exported). Cards are
  `dragTarget = true`.
- **The columns hold only what is in play** (user direction 2026-09-19).
  An entry listed under a later round used to sit on the stage from the
  start, greyed out under an "Appears in round 2" line; it is now not
  carded at all until its round comes, and then **materializes** -- the
  card is put into a transparent, slightly small, slightly low state with
  `SetClassTreeImmediate("eotwEntryAppear", true)` (immediate = no ramp)
  and the class comes off a frame later, so the rule ramps back out over
  its own `transitionTime` and that is the animation. Several entries
  entering together are staggered 0.15 s apart. Going the other way, an
  entry the party **dealt with fades away when the round ends** rather
  than lingering greyed out: the round turning (or, for the last round,
  the phase leaving `rounds`) fires each done card's `leave` event, which
  puts `eotwEntryLeave` on it and destroys it 0.5 s later; the new round's
  arrivals wait that fade out so the hand-over reads as one movement.
  Two facts the implementation turns on: style **opacity is not inherited
  by children** (`SheetPanel` applies it to its own background,
  `SheetLabel` to its own text), so the fade classes go on the whole card
  subtree and their opacity rules are written *without* `eotwEntryCard` in
  the selector so they match the labels too -- while `scale`/`y` are
  transform-level and so stay on the card alone; and a build from cold (a
  join or a resume mid-montage) must not put back what has already faded
  away, so it only cards entries still in play plus whatever was dealt
  with in the round that is still running. `m_cards` in `CreateStage`
  holds the live cards by entry id; a card that has begun to leave is
  dropped from it at once.
- **Bottom row: hero cards** -- the existing `CreateHeroCard` (exported
  from `EncounterOfTheWeekHud.lua`), `draggable = true`, plus
  `showStats = true` (user direction 2026-09-18): the montage is where the
  party weighs who should take which beat, so its cards -- and only its
  cards, not the right rail's -- carry the hero's numbers. The five
  characteristics run down the card's right edge as one chip each, initial
  plus score ("M +2", MARIP order, taken from `creature.attributesInfo`
  sorted by `order` rather than hardcoded), floating under the condition
  chips and above the overlay. Every chip is the same fixed width
  (`STAT_CHIP_WIDTH`, user direction 2026-09-18 -- auto width sized "M +2"
  and "I +1" differently and left the column ragged) and holds two labels:
  the letter left-aligned in its own column, the score right-aligned in
  the other, so both line up down the strip. The hero's trained skills
  (`ProficientInSkill` over `Skill.SkillsInfo`, already name-sorted) are
  listed comma separated on the line under the name, inside the overlay;
  the sweep is re-run at most every 5s rather than on every 0.5s card
  tick. The skills block is 46 tall (four lines at font size 9, enough for
  a ten-skill hero) and the montage card grows by exactly that -- 176 ->
  222 -- so the portrait keeps its area. The montage stage's row is
  `MONTAGE_HERO_ROW_HEIGHT` (279: the 1.2-uiscale card, 267, plus a 12px
  gap to the screen edge); the narrative and prep stages still use
  `HERO_ROW_HEIGHT` (360), which leaves room under the card.
  `canDragOnto` = the card's hero is the local user's (`canControlAsUser`),
  has not acted, the target entry is available and no turn is in flight.
  `drag(element, target)` stamps the approach request. **The card is only
  `draggable` when the same gate (`EncounterMontage.LocalUserCanAct`) passes**
  (user report 2026-09-18): gating the drop alone still let a player pick up
  and haul another player's hero around the stage, which reads as permitted.
  `draggable` is therefore computed at card creation and re-set on every
  `refreshMontage` tick of the hero column, so it follows turns and the
  acted set; `CreateHeroCard`'s `draggable` opt is now the card's starting
  state (registered whenever it is non-nil, false included) rather than a
  flag that merely turns the drag callbacks on. Acted heroes render
  desaturated and dimmed. Clicking a card still pops out the (read-only)
  character panel, on `click` rather than `press` so a drag's release does
  not open it. NOT built: a click-to-select fallback for people who do not
  drag. Each hero has a half-size **ally card** per `allies[heroid]` entry
  (portrait + name + stamina bar). On the **montage** stage they stack
  bottom-up against the hero card's right edge at 0.75 uiscale
  (`MONTAGE_ALLY_UISCALE`), and the stack widens the hero's column, so a hero
  with an ally stands a little further from the next hero (user direction
  2026-09-23). That let the row shrink to just the card, so the party sits
  at the bottom of the screen and the turn panel is ~80px taller. The
  narrative and prep stages and the right-rail roster still put ally cards
  UNDER the hero card. Switching from a montage beat to a narrative beat
  therefore moves the hero cards ~80px (open question: give those stages the
  same layout?). A single column of allies holds about four; more would
  climb past the top of the card.
- **The haul strip** (user direction 2026-09-18): down the LEFT edge of
  each montage hero card, one icon per distinct item that hero has been
  granted this montage (`EncounterMontage.GetItems(charid)` over
  `data.items`). The icon is the gear row's `item:GetIcon()`, 30 square,
  with an `xN` chip in its corner when the quantity is above one; hovering
  one shows the item's full compendium card (`CreateItemTooltip`, the
  inventory's own tooltip). A newly granted item **drops in and is heard**:
  the icon is born with a `dropIn` class whose rule raises it a slot-height
  (`y = -(ITEM_ICON_SIZE + 14)`, negative y is up) and makes it
  transparent; taking the class off a frame later ramps that rule back out
  over its own `transitionTime` (0.4 s, `easeOutCubic`), which is the fall,
  and at that moment the client plays the same pickup sound the in-combat
  `giveItem` float plays over a token -- `UI.Inv_Item_Pickup_Special` for
  an `EquipmentCategory.IsTreasure` item, `UI.Inv_Item_Pickup_Gnrc`
  otherwise. Several items landing in one refresh are staggered 0.18 s
  apart so they read as separate pickups. A **repeat** grant bumps an
  existing icon's quantity rather than adding one, so that gain instead
  pulses the icon it owns (`PulseClass("bump")`, scale 1.3) and plays the
  same sound. Because "each party member gains X" lands the same item in
  four strips at the same instant, an identical sound event inside 0.1 s is
  dropped -- four copies of one sample is a mush, not four pickups.
  Items already in the document when the strip is built appear instantly
  and silently, so a hero-row rebuild (an ally joining, which changes
  `HeroSignature`) does not replay the whole montage. The gutter is always
  reserved, empty or not, so the row of cards does not shuffle sideways the
  moment the first item lands.

  Two engine facts, both established live while building this and worth not
  rediscovering: style transitions are computed **per rule**, so the
  `transitionTime` must live on the rule whose match is changing -- a rule
  describing the *resting* state does not animate anything; and style `y`
  **accumulates** across every matching rule (`instance.pos += y`) instead
  of being overridden by the most specific one, so a "landed" rule setting
  `y = 0` alongside a still-matching `y = -44` rule leaves the panel at
  -44 forever. A class present at construction applies at full strength
  immediately (no ramp-in), which is what makes "born raised, ramp the rule
  out" the right shape for a drop.
- **Center: the turn panel**, driven by `montage.turn`: the acting hero's
  portrait and the entry name; the `Options:` approach text; the option
  list, each showing `Name: Attr` and its tier lines (only the acting
  player's client gets press handlers; everyone else sees the same list);
  "Rolling..." while the dice fly; then the landed tier highlighted and the
  applied-effects list. Everyone sees the same thing at the same time.
  **While the dice tumble, the tier they are currently landing on is
  highlighted live** (user direction 2026-09-18), the way the remote
  ability card's tier table and the initiative banner do it.
  `LiveTierRows` in `EncounterMontageStage.lua` replaces the static rows
  on the chosen option while `turn.status == "rolling"`: it monitors the
  share document (`CharacterPanel.AbilityShareDocPath()` /
  `GetAbilityShareData()`, two more exports added to
  `Timeline/AbilitySidebar.lua`), and when `dialogState.rollState` is
  "rolling" it finds the chat message by `dialogState.rollId`, subscribes
  to each die's `chat.DiceEvents(guid)`, and on every `diceface` event
  recomputes the running tier (`RollUtils.DiceResultToTier` over the
  running total with the message's own edges/banes/tier shifts) and moves
  the `landed`/`dim` classes across the rows. A 0.1 s think locks the tier
  in once the last die's `timeRemaining` elapses; after that, or whenever
  `rollState` is "finished", the broadcast `highlightedTier` (which
  follows post-roll edges/banes) is applied instead. The roller's own
  client reads the document it writes, so there is one code path for
  everyone; on a core without the exports the rows stay static. Once the
  host resolves the turn the body rebuilds with `turn.tier` highlighted as
  before. BUILT 2026-09-18, luac-clean, UNTESTED live.
- **The recognized rules are coloured inside the tier text** (user
  direction 2026-09-19). A tier line is part prose and part rules --
  "You make off with some potions! Each party member gains one Healing
  Potion" -- and only the second half does anything. Every tier row that
  is showing its FULL text draws the clauses the effect grammar
  recognized in the applied-effect green (`#8ee08e`, or the muted
  `#5d7a5d` on a dimmed row), the rest in the row's own colour, via
  `TierText` -> `EncounterScript.MarkupRules` with rich-text `<color>`
  tags. That covers the landed tier once a roll resolves, the live rows
  while the dice tumble (`SetLandedTier` re-marks as the tier moves), and
  any tier authored without a teaser -- so the option card shows it
  before the roll too. A **teaser is never marked**: the grammar only
  ever parses the full text, so colouring a teaser would be a guess.
  Colour only, no tooltip and no inline effect text (user direction): the
  parsed mechanics are already listed as green lines under the result, so
  the colour is what ties phrase to effect, and the tier labels stay
  `interactable = false` inside the pressable option card.
  Deliberately NOT extended to the roll dialog's own power table: that
  table is shared core code and fills the landed row gold with forced
  black text, which a colour tag would clash with -- and the montage
  dialog is handed teasers anyway (`TeaserTiers`).
  A useful side effect for authoring: a clause the grammar missed stays
  uncoloured, so "The threat is vanquished, and you gain 2 surges" shows
  its first half green and the second half plain -- which is exactly what
  will and will not happen.
- **The rail behind the stage** (user direction 2026-09-18): the hud's
  right rail keeps rendering while a montage beat is presented, and its
  **pools strip is wanted there** -- hero tokens and malice read in the
  same place as in combat. Its **hero roster is not**: the column is
  combat-only, because the stage already draws a hero card per player
  along the bottom. `CreateRightRailPanel` (EncounterOfTheWeekHud.lua)
  therefore owns a 0.5s think that sets the `collapsed` class on the
  roster child whenever `EncounterMontage.IsPresented()`; the toggle
  lives on the rail rather than inside the roster so it keeps ticking
  while the roster is down, and the roster's own `Refresh` bails out and
  drops its signature while collapsed so the column rebuilds from
  scratch when the montage ends. KNOWN DUPLICATE: the stage mounts its
  own copy of `CreateEncounterPoolsPanel` at the same screen spot
  (below), so two identical strips now stack there -- harmless
  visually, but one of them should go; not decided which. BUILT + Lua
  reloaded clean 2026-09-18; UNTESTED against a live montage.
- **Consequences**: after the last round, the columns give way to one
  threat at a time in the center -- name, malice diamond, consequence
  text -- with a Continue button for anyone; the applied effects flash
  before the next one.
- **Header**: the montage's title, the intro prose, then "Round N of M" and
  who is still to act. The **intro prose is the party's standing context**
  for the whole beat (user direction 2026-09-19): whatever the document
  writes under `# Montage` before the first `##` is shown there from the
  moment the stage comes up until it goes away -- through every turn, every
  roll and the consequences phase -- so a player who joins late, or who
  looks up mid-montage, can still read what this journey is. It is styled
  to be read at a glance rather than as a caption (`eotwMontageIntro`, 19pt
  italic warm-white over the 16pt grey `eotwStageSubtitle` it also carries),
  and it **wraps to as many lines as the writing needs**: the header is
  `height = "auto"` with `minHeight = HEADER_HEIGHT` instead of a fixed 76,
  and a `SyncHeaderHeight` helper (called from `Refresh` and from the 0.5s
  think) re-derives the body's `100%-N` height from what the header
  actually rendered, so the entry columns, the turn panel and the hero row
  all move down together and nothing is clipped. Runaway prose is capped:
  the label's `maxHeight` is 186 (about seven wrapped lines -- a generous
  read-aloud paragraph) and the arithmetic clamps at `HEADER_HEIGHT_MAX`
  260, so the header can never eat the entry columns. The narrative stage
  keeps the plain 16pt subtitle and its fixed header; only the montage was
  changed.
- **Encounter pools** (user direction 2026-09-18): the stage covers the
  right rail, so it mounts the rail's own malice + hero-token strip
  (`CreateEncounterPoolsPanel`, exported from the hud) floating at the
  rail's spot -- top inset 64, right margin 12 -- so players read it in
  the same place and form as during combat. UNRENDERED since the edit.

The parser, the runtime and the stage are built as three separable
modules (`EncounterScript.lua`, `EncounterMontage.lua`,
`EncounterMontageStage.lua`) so a Director-run montage in a normal game
can reuse the first two later; only the hero-card row and the
custom-interface wiring are EotW-specific.

### Sequencing changes in the codemod

Today `SetupOnArrival` spawns the monsters during host setup and the host
tick rolls into combat once everyone has arrived. With scripts:

- the host tick owns a **beat machine** on top of the existing stage
  mirror: `(nil)` -> wait for arrival -> for each beat: `montage` (present
  the stage, run the turn lifecycle to `done`, hide it) or `encounter`
  (spawn the `[[encounter]]` monsters scaled to `numheroes`, then the
  existing `draw-steel` run-once) -> `combat` -> `complete`.
- `SpawnEncounterMonsters` therefore moves from `SetupOnArrival` to the
  start of the encounter beat, so a montage plays on a monster-free map.
  For a script with no montage the only visible difference is that the
  spawn happens on the first host tick after arrival instead of during
  setup; joiners still enter on `ready` as now.
- `eotwscript.beat` is stamped by the host, so late joiners and resumes
  land in the right beat; the stage is rebuilt from the document text +
  the state doc on any client.
- `EnsureAIRunning` stays gated on the initiative queue -- the AI is never
  started during a montage.

### Stage beats hand over without showing the map (FOUND + FIXED 2026-09-19; the mounted stage VERIFIED live, the cut itself UNTESTED)

User report (2026-09-19): a narrative beat followed by a montage "flashed to
revealing the map for a moment" instead of cutting straight across -- jarring
in general, and worse when the two beats name the same `[[scene]]` and the
cut should be invisible.

**Cause.** `RunScriptBeat` finished a stage beat by hiding the stage and
stamping the next beat index, and the NEXT beat only seeded and presented
itself on the following host tick. Between them the presented-dialog document
said "no dialog", so every client had nothing over the map for a tick plus a
present round trip -- half a second or more of battlefield in the middle of
the story.

**Fix.** `AdvanceFromStageBeat` (EncounterOfTheWeek.lua) replaces the
hide-then-advance in both the montage and the narrative branches. When the
NEXT beat is also a stage beat it does not hide at all: it stamps the index,
`Begin`s the next beat (seeding its state and presenting the SAME dialog id
with the new `beatIndex`) and runs its first `HostTick` in the same pass, so
the new beat opens on its first round/section instead of sitting in
"arriving". Only a beat that really hands back to the map -- the encounter, or
the end of the script -- calls `Hide`. GameHud's `refreshGame` destroys the
old presented dialog and creates the new one inside a single handler
(`GameHud.lua`, the `presentdialog` monitor), so the swap is one frame with
nothing uncovered in between, and an unchanged backdrop image is already
loaded.

**Round two (2026-09-19), after the first fix was not enough.** The user
played it solo and reported a *long* pause after pressing the option and then
"the entire screen flickers" on the way to the montage. Two separate causes,
both now fixed:

- **The pause was the lingers.** A narrative section held `RESOLVED_LINGER_SECONDS`
  (5s) showing its outcome, then the finished beat held `DONE_LINGER_SECONDS`
  (4s) showing the very same panel again: **nine seconds** after a "Proceed"
  that did nothing at all. The resolved linger is now chosen when the section
  resolves and recorded on the state (`m.resolvedLinger`): 4s when the option's
  rules text actually applied something worth reading, and
  `RESOLVED_LINGER_QUIET` (0.4s) when it applied nothing. The done linger drops
  to 0.3s, because the resolved panel has already had its time and the "done"
  phase renders the same thing. A plain story beat now turns over in about a
  second, host tick included.
- **The flicker was GameHud rebuilding the dialog.** Presenting carried the
  beat index in the dialog's args, and `refreshGame` destroys and re-creates a
  presented dialog whenever its args change -- so every beat change tore the
  whole surface down and built it again, one frame of nothing over the map.
  The args are now CONSTANT (`EncounterMontage.Present` passes `{}`) and what is
  presented is a new **mounted script stage**, `CreateScriptStage`, created once
  for the whole run of stage beats. It owns everything the two kinds share --
  the opaque background, the scene art, the dim, the pools strip, the
  action-bar hide, the loading-screen release -- and holds ONE body inside it,
  the montage's or the narrative's, swapped when the beat kind changes.
  `CreateStage` and `CreateNarrativeStage` take `args.embedded` and skip the
  chrome when they are that body. Two beats naming the same `[[scene]]`
  therefore cut with nothing moving but the cards. VERIFIED live: the mounted
  stage re-presented over a running montage with the columns, turn panel, hero
  row and pools all intact.

  Note for a session that upgrades mid-script: a stage presented by the old
  code still has `{beatIndex = N}` in its args, so the FIRST handover after the
  upgrade still rebuilds once. Re-presenting (`EncounterMontage.Present`) at any
  quiet moment spends that rebuild where nobody minds it.

**Round three (2026-09-19): the flicker was the presenter re-presenting.**
Round two was still not it -- the background blinked even with the scene
unchanged. Code read, no app: `GameHud`'s `presentDialog` handler nils
`m_presentedDialog` for any non-`keeplocal` dialog **without destroying the
panel it is forgetting** (`GameHud.lua`), and the `refreshGame` that follows
the document write cannot destroy what it no longer has a reference to, so it
builds a second one on top. `EncounterMontage.Begin` presented
unconditionally, and `AdvanceFromStageBeat` calls `Begin` at every handover --
so on the PRESENTING client (the host, which is the whole table when someone
plays solo) every beat change stacked a fresh stage over an orphaned one, and
the new stage's backdrop had to load and aspect-fit from scratch while the old
one sat underneath. That is the flicker. Other clients never saw it: their
args matched, so they early-returned.

Three fixes, all code-only:

- **`EncounterMontage.Present` returns early when `IsPresented()`.** The
  presented-dialog document already says the stage is up and every client reads
  the live beat from the script document, so there is nothing to re-send. This
  also ends the orphan leak -- each orphan kept ticking AND kept its claim on
  the ref-counted action-bar hide, so the count could never fall back to zero
  and the bar would have stayed hidden into combat.
- **`AdvanceFromStageBeat` seeds the next beat's state BEFORE stamping the beat
  index.** The stage picks its body from the index, so stamping first left one
  refresh in which the new body rendered the PREVIOUS beat's state -- a flash of
  the wrong section. Seeding first means the outgoing body draws its own
  finished state for one more refresh, which is what is already on screen.
- **`CurrentSceneImage` only lets a narrative SECTION choose the scene while the
  live narrative state belongs to the beat being drawn.** Across a handover the
  previous beat's state is briefly still on the document; borrowing its section
  would have swapped the backdrop to something not on screen and straight back
  (latent -- it needs a per-section `[[scene:x]]`, which no week uses yet).

The wrapper also carries `StageRules()` now: the backdrop, the dim and the
pools strip used to hang under a stage root that had them, and moving them out
would otherwise have changed their style scope.

Traced end to end on paper, the handover is now four document writes (seed,
beat index, the new beat's first tick, its request pass) producing exactly ONE
body swap and ZERO writes to the backdrop.

### The stage dissolves away to reveal the fight (DECIDED + BUILT 2026-09-19; UNTESTED live)

User report (2026-09-19): after the last narrative section, combat started and
the Draw Steel banner played, but the narrative UI and its scene stayed on
screen -- the party was left staring at the scene instead of the battlefield.
And, wanted: the stage should not simply vanish, it should "disappear nice and
elegantly with the typical cut-scene transition we use", revealing combat.

**Why it stayed up** was the duplicate-stage bug above: the session was running
the code from before that fix, so the presenter had stacked a stage at every
beat change, and `HidePresentedDialog` destroys only the ONE panel GameHud is
still tracking. The orphans underneath stayed exactly where they were. The
`Present` guard fixes that on its own.

**The transition.** `dmhub.StartScreenTransition(onReady)` is the engine's own
dissolve -- the one the titlescreen loading screen uses. It snapshots the
screen into a RenderTexture drawn over all UI, calls `onReady` once the
snapshot is captured (that is when you change what is underneath), and
`CrossFade(1 -> 0)` thins the snapshot away to reveal it; `Destroy()` frees the
texture. The one existing caller, `DMHub Core UI/ThemeSettingsDialog.lua`, is
the idiom this copies, `fadeOut` helper and all.

**The sequence now**, with the spawn hidden behind the scene the way the
loading screen hides the opening montage:

1. The last stage beat finishes. `AdvanceFromStageBeat` stamps the next beat
   index and **does not hide** -- the stage stays up over the map.
2. The encounter beat spawns its monsters behind it (idempotent, as before) and
   gathers the sides. Nothing pops in on a bare map.
3. `EncounterMontage.DismissStage()` stamps `stageDismissAt` on the script
   document: one shared clock, so the cut lands together on every screen.
4. Every client's stage sees the stamp, snapshots the screen, hides itself
   underneath the snapshot (revealing the finished battlefield) and dissolves
   the snapshot away over `STAGE_DISMISS_SECONDS` (0.8).
5. The host takes the panel down for real once that has played, and only THEN
   does the encounter beat roll Draw Steel -- so the banner plays over the map
   rather than over a scene nobody can see past.

`DismissStage` returns true only once the stage is really gone, and the
encounter beat holds on it, so it is bounded: after `STAGE_DISMISS_SECONDS +
STAGE_DISMISS_TIMEOUT` (4s) it logs and carries on regardless rather than
letting a stuck surface wedge the fight. The stamp is deliberately NOT cleared
by the hide (a cleared stamp would just be re-stamped on the next tick -- an
endless dissolve); it clears when the stage is observed gone, on the timeout,
and at the start of any later stage beat so a new one never inherits it. An
engine without the transition bridge falls back to hiding outright.

A script that simply runs out (no encounter beat) dissolves the stage from
`RunScriptBeat`'s "no such beat" branch.

**A restart mid-roll used to wedge the turn.** Found while testing this:
restarting the app while a montage roll was in flight killed the relaunch
coroutine on `GameHud.instance.rollDialog` -- `GameHud.instance` is `false`
until the hud exists, and indexing `false` raises -- which left
`m_launchedRollSeq` consumed and the turn stuck in "rolling" for the rest of
the session. `ShowRollDialog` now reads the hud defensively and takes its
existing graceful bail, which clears the watermark so the client tick simply
tries again once the hud is up.

**The action bar had to follow.** Both stages hide the bar through the
transient `hideactionbar` setting, capturing the old value on create and
restoring it on destroy. With a handover the new stage is created around the
old one's destroy, which either flickered the bar back for a frame or -- if
create ran first -- captured `true` and left the bar hidden for good. It is
now REF COUNTED in `EncounterMontageStage.lua` (`AcquireActionBarHide` /
`ReleaseActionBarHide`): the first stage up captures and hides, the last one
down restores, and the restore is deferred 0.15s so a handover that releases
before it acquires cannot blink the bar.

### The loading-screen hold: the loading screen reveals the montage (DECIDED + BUILT 2026-09-18; C# NEEDS BUILD; Lua UNTESTED; UNCOMMITTED)

**The problem.** Entering a real EotW game whose script opens with a
montage, the host saw the map and the tokens spawn in, and only then the
cut to the montage. Two structural causes: the engine cleared the loading
screen (`FinishLoadingCo`: `GameHarness.loading = false`) and only THEN
fired the `lobby:EnterGame` callback, so `SetupOnArrival` (map travel,
`PlaceMyHeroes`) always ran on a visible map; and the stage was presented
only by the host tick's beat machine, gated on `AllPlayersArrived()` (every
player stamped + 3s settle), then the 1s cadence, then the `presentdialog`
round trip -- 4-6s of bare map for the host, and members waited out their
own arrival + settle too.

**The fix: an engine hold on the loading screen, and an early montage.**

- **Engine** (`GameController.cs`, static so it survives the titlescreen ->
  game handoff and every codemod reload): `dmhub.HoldLoadingScreen()` /
  `dmhub.ReleaseLoadingScreen()` / read-only `dmhub.loadingScreenHeld`
  (bridge in `LuaInterface.cs`, stubs in `Definitions/dmhub.lua`). When a
  hold is set as `FinishLoadingCo` reaches the end of the image wait, it
  fires `executeOnArrive` FIRST (behind the loading screen), then spins
  until the hold is released or `LOADING_SCREEN_HOLD_TIMEOUT` (20s) or the
  game is being left, and only then flips `GameHarness.loading = false`
  (titlescreen `endLoading` -> fade -> deactivate 1s later). The unheld
  path is byte-for-byte the old order. `GameHarness.LeaveGame` clears any
  hold so one can never leak into the next entry. The timeout logs a
  `Debug.LogWarning` naming how long it waited.
- **Titlescreen** (`Codex Titlescreen/EncounterOfTheWeek.lua`, Enter
  World): `pcall(dmhub.HoldLoadingScreen)` right before `lobby:EnterGame`,
  for EVERY EotW entry (host, member, resume). Old engines lack the call and
  degrade to the old behaviour. Mixed-version hazard: a NEW engine with an
  OLD game-side module never releases and eats the 20s timeout -- deploy
  the codemod together with (or before) the build.
- **Game side, host** (`EncounterOfTheWeek.lua`, `SetupOnArrival`): after
  `EnsureOnEncounterMap` + `RecordEncounterMap` and BEFORE `PlaceMyHeroes`,
  `BeginOpeningMontage()`: if the script has not started (no montage state,
  beat index 1) and beat 1 is a montage, `EncounterMontage.Begin(script,
  beat, 1)` seeds the state and presents the stage; a resume mid-montage
  re-presents it. The stage root is opaque, so hero placement happens
  under it, and it is what everyone's loading screen reveals.
- **Game side, everyone**: after `PlaceMyHeroes`, `SetupOnArrival` releases
  the hold UNLESS `MontageStageExpected()` (a live montage state, phase not
  done, whose beat is a montage of this map's script) -- then the stage's
  own `create` event releases it, via a 0.1s `releaseLoadingScreen`
  scheduled event so the first layout is in. Releasing twice is harmless;
  `mod.unloaded` at setup entry also releases.
- **The "arriving" phase** (`EncounterMontage.Begin` seeds `phase =
  "arriving"`): the stage is up but nobody can act (`LocalUserCanAct` and
  `HandleRequest` both require `"rounds"`). `HostTick` -- which the map
  script only runs once `AllPlayersArrived()` -- flips it to `"rounds"` on
  its first tick. The stage renders it as "Waiting for the party to
  arrive..." in the round label and a "Gathering the party" turn panel.
  `HostTick`'s own seeding now goes through `Begin` too, so later montage
  beats start in "arriving" and open on the very next tick.

**Residual / untested.** The whole thing is unbuilt (C#) and unexercised
(Lua): verify the host's loading screen dissolves straight onto the stage
in "arriving", that a member's does the same, that a week with no montage
releases right after placement (no hero pop-in either now), and that
leaving mid-hold does not stall. `SetupOnArrival` now runs while
`GameHarness.loading` is still true; nothing in the setup path was found
to read it, but map travel under a held loading screen is the one thing
to watch. If setup errors out before its release, the 20s timeout is the
only exit -- acceptable, but log-visible.

### The action bar is hidden while the montage stage is up (BUILT 2026-09-18; UNTESTED)

Observed in a montage test: the action bar painted straight through the
full-screen stage (the offending panel traced to `DrawSteelActionBar.lua`
via `DSActionBar.lua`'s custom-action-bar host). The bar renders above
windows (`renderOnTop`), so the stage's opacity and z-order cannot cover
it. The bar already monitors the transient `hideactionbar` setting
(`DMHub Titlescreen/Settings.lua`), which nothing else writes, so the
stage uses it: `CreateStage`'s `create` handler remembers the current
value and sets it true; its `destroy` handler puts the old value back
(`EncounterOfTheWeek/EncounterMontageStage.lua`). Transient storage means
a stage that somehow dies without `destroy` costs at most the session, and
a restart always clears it.

### No welcome documents in EotW games (DECIDED + BUILT 2026-09-18; UNTESTED)

`DocumentSystem/DocumentNewUser.lua` opened the "New Player Welcome"
journal document on entering an EotW game: its EnterGame gate is "no
character owned yet", and an EotW player's heroes are pasted during
arrival setup, after that fires. `ShowDocumentOnStart` now returns early
in an EotW game (both the director and the new-player welcome). It checks
at the last moment, after the hud exists, with three pcall-guarded signals
because the EotW codemod may not have loaded yet: `EncounterOfTheWeekGame.
IsEotwGame()`, `lobby.eotwGameid == dmhub.gameid`, and the titlescreen's
parked `_G.EotwPendingArrival.gameid == dmhub.gameid`.

### Out of scope for the first cut

~~Narration~~ (built 2026-09-18, see "Narrative beats")/negotiation beats;
victories and the montage's Draw Steel
success/failure tally; a Director-facing montage runner in normal games;
publisher validation of the script (a later step, once the grammar has
settled in play); skipping a hero whose owner has disconnected (recorded
in Open Questions); a click-to-select alternative to dragging. Several
montages per script DO work (each beat runs to done in turn).

### Testing it

**Verified 2026-09-18 in the authoring game** (`e96656f3`, map
`Encounter: Goblin Ambush`, whose `Encounter` document carries the sample
script; `eotw:forcecustomui` on; the Director driving the party-owned
pregens; requests injected over MCP exactly as a drop would stamp them):
the stage presents over the map with the scene backdrop, three entry
cards, the hero row; approach -> choosing panel (portrait, approach text,
both options with tier rows, Back); choose -> the real roll dialog opens
for the acting user (2d10 + Presence, the option's tiers); a real roll of
6 resolved tier 1, marked the hero acted and the opportunity taken;
injected tier results exercised every effect kind: item grant (2 x Healing
Potion into the inventory), ally (a `Wode Elf Sentry 1` spawned on the
nearest Start tile, party + owner set, `eotwAllyOf` stamped, its card
under the hero on the stage AND in the rail roster), malice (+2, visible
in the pools strip), stamina loss (21 -> 16); all heroes acted -> the
consequences phase showed the threat with the malice diamond; Continue
applied "Every hero loses 5 Stamina" and the montage finished and hid.
Zero console errors across the whole run. The residue (ally token, malice,
stamina, potions, the state document) was cleaned back out afterwards.

**Outside an EotW game** there is no map-script host tick, so
`/eotwmontage start` runs a dev driver (the first montage beat of the
current map's script, ticked every 0.5s); `/eotwmontage stop` halts it,
`/eotwmontage state` prints the document. `/eotwmontage reset` restarts
the whole test (host only in an EotW game): deletes the montage's allies
and the encounter beat's spawned monsters, clears the script state,
zeroes malice, heals every hero to full, clears the combat flags and
detaches the EotW map script so the self-heal re-attaches a fresh record
(clean run-once watermarks) and the script plays again from beat 1. It
refuses while combat is running -- end combat first. `/eotwscript` dumps
the parse and resolves names.

**Still to verify**:
- ~~the real drag gesture on the hero cards~~ VERIFIED 2026-09-18 through
  the input bridge (a virtual drag of a card onto an entry stamped the
  approach). Discoverability was the problem in the user's first run, so
  the stage now also highlights droppable entries while a hero is dragged
  or clicked, supports click-a-hero-then-click-an-entry (a card whose hero
  can act selects on click; otherwise the click opens the character panel),
  and the idle hint names the local user's heroes still to act. These
  additions are UNRENDERED since the edit;
- a real EotW game on staging with two clients: the map script's beat
  machine, a non-host player rolling on their own client, the presented
  dialog appearing for a joiner, then spawn -> Draw Steel with the ally
  on the heroes' side (AI ignoring it, victory not counting it);
- ~~the roll dialog renders with a transparent backdrop over the stage~~
  superseded: rolls now go through the timeline sidebar (see the turn
  lifecycle); confirm it draws above the stage;
- the hero-row layout fixes made after the run (cards packed at the
  center, row tall enough for ally cards) and the 6s "done" linger with
  the last consequence shown, both unrendered since the edit;
- **the whole assist path** (step 39), nothing of which has run: the
  eligibility rule, the "!" badge, the slot and its drag/click drops, the
  assist roll's dialog and share, the tier shift, "Take the result", and
  the 30 s timeout. The authoring game could not be used to exercise it on
  the day it was built -- the running app hit the known stale-codemod trap
  (`reload_lua` logged the mod's files as loaded but `EncounterMontage`
  still exposed the pre-edit table, no `READ CONTENTS` lines), which for
  the EotW codemod has only ever been cleared by a restart. Restart first,
  then confirm `EncounterMontage.ApplyAssistToTier` exists before testing.

## Narrative beats (DECIDED + BUILT 2026-09-18; Lua only; VERIFIED end to end in the authoring game; real EotW game UNTESTED; UNCOMMITTED)

User direction (2026-09-18): as well as montages and an encounter, a script
can have **narrative** beats. A narrative shows a scene and some text, and
asks the party to choose; an option can carry the same rules text a power
table's tier can ("+1 hero token"), or nothing at all -- a plain "Proceed".
Some choices the party has to **agree** on; others each hero takes **on
their own**. If they cannot agree, it is settled at random, the stage
flashing between the players before it lands. **Everyone chooses before the
next section begins.**

It reuses the montage's machinery wholesale: the same script document, the
same `eotwscript` state document (under its own key), the same
host-arbitrates/players-stamp-requests authority model, the same
`ApplyEffects` (so every montage clause works in a narrative option), and
the same stage frame -- scene backdrop, header, hero cards along the
bottom with their haul strips and ally cards, the encounter pools where
the rail keeps them. No engine change, no core change.

### The grammar

```
# Narrative

[[scene]]

The party sets out at dawn.

## The Crossroads

The road forks at a weathered shrine.

Choose together: Which way do you go?

### Take the high road

The long way, but the safer one.

|+1 hero token

### Take the low road

|+2 malice

## The Shrine

Each of you may leave an offering.

Choose individually:

### Offer a coin

|You gain 1 Healing Potion

### Walk on

## A Quiet Mile

Nothing happens for a while, and the road turns south.
```

- `# Narrative` is a beat like `# Montage`. A script may hold several, in
  any order around the montage and the encounter.
- `[[scene]]` above the first `##` is the beat's backdrop; a `[[scene:x]]`
  **inside** a section is that section's, overriding the beat's for as long
  as it is on screen. A section with neither gets a plain dark backdrop.
- Prose between `# Narrative` and the first `##` is the beat intro (shown
  under the title on the FIRST section only).
- `## <Name>` is a **section**: they play one at a time, in document order,
  and the beat is done when the last one resolves. Its body:
  - plain paragraphs = the text that appears;
  - a `Choose together:` / `Choose individually:` paragraph = the mode,
    plus whatever follows the colon as the prompt line. Spellings are
    matched loosely: anything containing "together", "as one", "as a
    group", "agree" or "unanimous" means agreed; "individual",
    "separately", "each hero", "each of you", "each player" or "their own"
    means each hero on their own. A bare `Options:` / `Choose:` / `Choice:`
    sets only the prompt.
  - **Default is `together`.** A section with two or more options and no
    marker gets a parser warning naming it.
- `### <Option>` is an option. Its prose is the option's description, and
  each `|line` under it is **rules text**: exactly the clause grammar a
  montage tier line uses (the table under "Montage grammar"), several
  clauses per line, several lines per option. An option with no `|` lines
  is a narrative-only choice.
- A section with **no options at all** gets one implicit `Proceed` option,
  so text that simply appears still waits for everybody.
- Section ids are `s<n>/<slug>` so a re-parse lands on the same ids.
- Power rolls in a narrative option are NOT supported (a `|Name: Attr` line
  is read as a clause and ends up as unrecognized narrative text). If a
  choice needs a test, it belongs in a montage.

### Who chooses, and what their choice does

User direction (2026-09-18): **the unit of choice differs by mode** --
"each hero on their own" is per HERO, "everyone must agree" is per PLAYER.

- **individual**: every hero must choose. A player running three heroes
  chooses three times. A hero is dragged onto the option they take (or
  clicked, then the option clicked), exactly the gesture that approaches a
  montage entry.
- **together**: every PLAYER must choose, one voice each however many
  heroes they run, by clicking the option. The voters are the distinct
  `ownerId`s of the party's heroes; party-owned heroes ("PARTY", the
  authoring game's pregens) collapse into ONE pseudo-voter that anyone at
  the table may fill -- which is why a split decision cannot be produced in
  the authoring game without hand-writing the state.
- A choice can be changed until the last one is in; nothing resolves early.

**What an option's rules text targets** (user direction 2026-09-18):

- **together**: the party. Every targeted clause is re-aimed at the whole
  party before it is applied, so `You gain 1 Healing Potion` on an agreed
  option gives one to every hero. `ally` is the exception -- one ally
  joins, anchored on the decider's hero (or the first hero), not one per
  hero.
- **individual**: each option is applied ONCE, for the group of heroes who
  took it (`ctx.heroEntries`). Self-target clauses land on each of them;
  a party-target clause ("Each party member gains...") lands on the whole
  party once rather than once per chooser; and a pool clause (malice, hero
  tokens, initiative, surprise) applies once for that option, not once per
  hero. Decided this way so an option cannot multiply the malice pool by
  the size of the party; an author who wants it per hero should say so with
  separate sections.

### Settling a disagreement

When every player has voted in an agreed-upon section and they do not all
match, the host picks one of them at **random** (`math.random` over the
voters who cast a vote, so a 2-1 split is decided by a voter, not by the
majority -- it is a coin flip between the people, as asked), writes
`decision = { candidates, winner, optionIndex, startedAt }` and moves to
`phase = "deciding"`. Nothing is applied yet.

Every client then flashes through the candidates for
`DECIDE_FLASH_SECONDS` (3.2): the banner says "The party is split!", the
name and their option change under it, the option card they voted for and
their hero cards light up, and a click plays on each step. The sequence is
a pure function of `decision.startedAt` and the shared clock
(`FlashCandidateIndex` in `EncounterMontageStage.lua`) -- there is no
animation state to sync -- decelerating on an ease-out curve over
`DECIDE_FLASH_STEPS` (21) steps arranged so the last step lands exactly on
the winner. (If the step count divides the candidate count the flash would
START on the winner and give it away, so it is bumped by one in that case.)
When the flash is over the host applies the winner's option, exactly as an
unanimous vote would have been applied.

### Runtime state

A second key on the montage's document, `eotwscript`:

```
narrative = {
  beatIndex, sectionIndex,
  phase = "arriving"|"choosing"|"deciding"|"resolved"|"done",
  choices = { [voterKey] = { optionIndex, userid, heroid, name, at } },
  decision = nil | { candidates = { { key, name, optionIndex, optionName, heroids } },
                     winner, winnerName, optionIndex, optionName, startedAt },
  result = nil | { mode, optionIndex, optionName, decidedBy, applied = {...},
                   groups = { { optionIndex, optionName, heroNames, applied } } },
  resolvedAt, doneAt, startedAt, log = {...},
  requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
  seq,
}
```

`voterKey` is a userid in an agreed section and a hero charid in an
individual one. Players stamp `requests[userid]` (`choose` /`unchoose`) and
the host validates and applies them on its tick, the montage's model
exactly. `phase = "arriving"` exists for the same reason the montage's
does: the stage is what the held loading screen reveals, and nobody can act
until the host tick -- which only runs once the whole party is in -- opens
the first section. A resolved section lingers 5s, the finished beat 4s.

Effects go through `EncounterMontage.ApplyEffects` with
`source = "Narrative"` (so damage and resource history read "Narrative:
The Crossroads"), which grew two things for this: `ctx.heroEntries` (a list
of self-targets rather than one) and an `ally` clause that spawns one ally
per target. Its applied lines now name every hero a clause landed on, with
the verb agreeing ("Kira and Osk gain 5 Temporary Stamina").

### The stage

The same presented dialog (`eotwmontage`) serves both beat kinds:
`StageFor(args)` reads the beat kind for the presented `beatIndex` and
builds either `CreateStage` (montage) or `CreateNarrativeStage`. That keeps
the loading-screen hold, the action-bar hiding, the backdrop, the pools
strip and the hero row in one place; the montage's chrome was factored into
`CreateBackdrop` / `CreateDim` / `CreatePoolsPanel` for the two to share.

The middle is a single centred panel that hugs its content: the section
text, the prompt (the author's line plus "The party must agree." / "Each
hero chooses for themselves."), the option cards in a centred wrapping row,
then -- once resolved -- what each option did. Option cards are drop
targets in an individual section and buttons in an agreed one. Under each
hero card is the choice they (or their player) made; while an agreed vote
is still open every card just says "Ready", because a vote nobody can see
is an honest one. A pulsing "?" marks every hero still owed a choice, and
the header lists who is still to choose.

### Open ends

- **A player who never chooses wedges the section.** There is no timeout
  (unlike the montage's assist window) because auto-choosing for someone is
  worse than waiting. The host has `/eotwnarrative force`, which resolves
  on the choices already in. The disconnected-player question is the same
  one the montage has in Open Questions, and wants one answer for both.
- Several heroes taking the same individual option produce one applied
  entry naming all of them; the stage shows one block per option.
- No Director-facing narrative runner in a normal game (the same
  separation the montage has: `EncounterScript` + `EncounterNarrative` are
  reusable, the hero row and the EotW hud wiring are not).

### Testing it

Outside a real EotW game there is no map-script host tick, so
`/eotwnarrative start` runs a dev driver over the first narrative beat of
the current map's script (ticked every 0.5s), `/eotwnarrative stop` halts
it, `/eotwnarrative state` prints the section, the options and who has and
has not chosen, `/eotwnarrative force` resolves on what is in, and
`/eotwnarrative reset` clears the state. `/eotwscript` dumps the parse of a
narrative beat with its sections, modes and clause effects.

**Verified 2026-09-18 in the authoring game** (`e96656f3`), driving a
three-section test script (agreed / individual / implicit-proceed) through
the dev driver with the map's own `[[scene]]` as the backdrop. The script
was injected by pointing `EncounterMontage.FindMapScript` at a parsed test
document for the session rather than editing the week's real `Encounter`
document, which was left untouched and re-verified afterwards. What ran:
the stage presenting with the scene, title, intro, text, prompt and both
option cards; an agreed section resolving off one click (+1 Hero Token
really landing in the pool) and showing the chosen card with its chooser;
the individual section taking a **click-a-hero-then-click-an-option** and
two real **drag** gestures (through the input bridge) onto different
options, resolving into two groups, with 5 Temporary Stamina on exactly the
two heroes who took the offering; the implicit "Proceed" section; and a
hand-seeded split decision flashing through three named players, lighting
their hero cards and option cards in turn, landing on the winner and
applying +2 Malice. Zero console errors. All residue (hero tokens, malice,
temporary stamina, the state document) was cleaned back out.

### The week's script as it stands (2026-09-18)

The authoring game's `Encounter` document (`98a5a5bf`) now parses as FOUR
beats -- narrative, montage, narrative, encounter -- with no warnings:

1. **`# Narrative`** (the opening). `## Ajax's Patrols` sets it up: the
   party is off the road because Ajax's patrols are sweeping the highway,
   they are making for Blackbottom, and the forest crossing is a day and a
   night of hard ground. One option, `### Press on`. Then
   `## Goblins in the Wode`: the cut notches and the print in the mud, and
   a `Choose together:` on how they cross --
   `### Keep to the deep wood` (slow, off any trail a goblin watches) or
   `### Follow the game trails` (fast, and watched). **Neither option
   carries rules text**: it is a flavour vote, so it changes no balance,
   but it is a real agreed-upon choice and a split gets the random flash.
   Attach clauses to it whenever the week wants them to matter.
2. **`# Montage`** -- unchanged, except that the Mysterious Cottage gained a
   third option on 2026-09-19, `### Consult her on the arcane` (an Arcana
   Test: Reason (Magic, Alchemy, Psionics) with an `|Allow:` rider for a
   hero skilled in Magic, Alchemy or Psionics, or an Elementalist -- see
   "Test riders" under Monster Info).
3. **`# Narrative`** (the ambush). One section, `## Surrounded`: the forest
   goes silent, the bracken moves on every side, the ring closes before the
   first goblin screams. One option, `### Draw steel!`, which is the last
   thing anyone presses before combat.
4. **`# Encounter`** -- unchanged.

Both narrative beats reuse the document's existing `[[scene]]` annotation
(the forest-road art), which suits both the journey and the ambush; a
second RichScene would have to be authored in the journal to give the
ambush its own backdrop. VERIFIED on screen: beat 1 both sections
(including the agreed vote resolving and showing "The party moves on") and
beat 3's card.

**Still to verify**: a real EotW game with two clients -- a genuine
multi-player agreed vote and a genuine disagreement (the authoring game
collapses all party-owned heroes into one voter, so the flash could only be
driven by hand); the narrative beat as beat 1 behind the held loading
screen; a narrative beat between a montage and the encounter (beat
advance, stage swap); an ally or item clause on a narrative option; and
`/eotwnarrative force`.

## Optional features: "Unlock: <Feature>" (DECIDED + BUILT 2026-09-20; Lua only; parser unit-tested; the unlock VERIFIED live end to end over a stubbed script)

User direction (2026-09-20): a narrative section should be able to say

```
Unlock: Intelligence
```

and that turns on a feature of the game mode. Everything a week does not
ask for stays off, so a script that never mentions Intelligence shows no
pool and no preparation screen and plays exactly as it did before the
feature existed.

Grammar and decisions:

- The line is a paragraph of a **narrative beat**: inside a `## section` it
  belongs to that section and lands when the section arrives; above the
  first `##` it is the beat's and lands when the beat opens. It is NOT an
  option's line -- a feature is not something the party can choose away --
  and one written under a `###` option warns and is ignored.
- The feature name is matched with `EncounterScript.MatchKey` against
  `EncounterScript.FEATURES`, a table of the features that exist (today:
  `intelligence`). An unknown name warns rather than being swallowed as
  prose, so a typo is visible in `/eotwvalidate`.
- `Unlock:` in a montage entry or the encounter beat warns and is ignored.
  (It is deliberately a different thing from the montage's `Unlock <name>`
  effect clause, which lets a `(Locked)` ENTRY onto the board. The colon
  and a registered feature name are what tell them apart.)
- The unlock is written to the TOP level of the script document
  (`doc.data.unlocked[feature]`), not into `montage.*` or `narrative.*`,
  because a feature must outlive the beat that turned it on.
  `/eotwmontage reset` clears it with everything else.

### Announcing it (DECIDED + BUILT 2026-09-20; VERIFIED live)

User direction (2026-09-20): the unlock should explain itself. A currency
nobody has explained is a number in the corner of the screen, so the moment
one arrives the stage says what it is for, and points at it.

- The wording lives on the feature record
  (`EncounterScript.FEATURES.intelligence.explanation`), not in the stage, so
  a second feature brings its own.
- The unlock stamps `narrative.announce = { feature, name, text, at }`, and
  every client reads `EncounterNarrative.ActiveAnnounce()` off that shared
  state -- so the explanation and the blink start and stop together on all of
  them, and a client that joins late sees whatever is left of it.
- The stage shows a plain callout under the section's text: the feature's
  icon, "Intelligence unlocked", and the explanation. **It does not blink and
  it has no border** (user direction 2026-09-20, having watched the first
  cut): a panel that pulses reads as a button, and this one cannot be pressed.
- **Only the pool blinks** -- a floating white rectangle over that cell of the
  pools strip, fading in and out (`EncounterMontage.FeatureBlinkAlpha`), which
  is what ties the words to the number they are about.
- **It stands until the party presses on.** No timer (user direction: the
  first cut timed out after 20s, which took the explanation away from whoever
  was still reading it). `ActiveAnnounce` shows it while the section is
  `arriving` or `choosing` and drops it the moment the section resolves, so
  the press that moves the story on is also the press that dismisses it.
- Two gotchas worth keeping: a panel's `selfStyle` is write-mostly -- reading
  back a key the style never set raises "Error indexing userdata", so the
  blink keeps its last opacity in `data` and only writes on a change; and the
  pools strip monitors the global-RESOURCE document, so nothing on it fires
  when the SCRIPT document changes. Its think went from 1s to 0.25s, which is
  also what makes a spend on the preparation screen show up in the strip
  promptly.

## Intelligence and Tactical Preparation (DECIDED + BUILT 2026-09-20; Lua only; VERIFIED live in an EotW game -- see below)

User direction (2026-09-20): the party has a shared currency, **Intelligence**,
representing what they have worked out about the ground and the enemy. It
starts at 0, a montage or narrative outcome can add to it, and at the outset
of the encounter a **Tactical Preparation** screen lets them spend it on what
they know going into the fight.

### The pool

- An outcome clause, exactly like hero tokens: `+1 Intelligence`,
  `You gain 2 Intelligence`, `The party gains 2 Intelligence`. One pool for
  the whole party, so there is no self/party distinction.
- It lives on the script document at the top level (`data.intelligence`) with
  a history of its own (`data.intelligenceLog`) -- it is ours, not a
  `CharacterResource`, so the strip's tooltip is fed from that log.
- The **pools strip** (`eotwEncounterPools`, above the hero roster and
  floated over the stage) grows a third cell for it, `phosphor/brain.png`
  plus the count, and the strip widens by half a hero card so three pools
  are never squeezed into two pools' worth of strip. The cell is there only
  while the feature is unlocked; the strip's 1s think is what notices.
- The parser warns when a script earns Intelligence and nothing unlocks the
  feature: the party would have no screen to spend it on.

### The screen

At the encounter beat, BEFORE the traps are placed and the monsters spawned
(`RunScriptBeat` runs `EncounterPrep.HostTick` first and returns until it
says "done"), the stage shows **Tactical Preparation** -- "Combat is upon
you! Spend your Intelligence wisely." -- with one card per bar:

| bar | levels |
|---|---|
| **Surprise** | You are surprised. / You lose the initiative. / You roll for initiative. / You win the initiative. / The enemy is surprised. |
| **Traps** | You are unaware of traps. / "There are 4 Snare Traps hidden on the map." / All traps on the map are marked. |
| **Enemy Stamina** | You have little awareness of the enemy's health. / You see enemy stamina bars. / You fully know the stamina of your enemies. |

- **Players only ever read the rung they are on.** The track above it is
  blank segments. What they have not worked out yet is the thing the screen
  is selling.
- **The track has one segment per notch they can BUY, not one per level**
  (user direction 2026-09-20), so knowing nothing is an empty track: Traps
  shows two segments with none filled, and a bought notch fills one. Nothing
  is half-lit by default -- hovering the Spend button pulses the segment the
  point would fill, and only while the pointer is on it.
- A notch costs **1 Intelligence** and **any player may spend it** -- the
  currency is the party's. A spend is a request the host validates and
  applies, the montage's authority model exactly.
- **Proceed is offered once the Intelligence is spent** (user direction),
  and also when nothing is left to raise, so a point nobody can spend cannot
  wedge the encounter. Every PLAYER presses it -- one voice each however many
  heroes they run, the narrative's agreed-upon voter set -- and the
  encounter begins when all have. A player can take it back ("Wait").
- The bars show the final levels for a 4s beat with the applied lines under
  them ("You are as ready as you will be"), and then the beat carries on:
  traps are placed, monsters spawn behind the stage, and the stage dissolves
  as it always did.

### What a level does

- **Surprise** opens on whatever the montage decided
  (`EncounterPrep.StartingSurpriseLevel` reads `GetInitiativeOutcome`,
  `GetSurprisedSides` and `HasSurpriseImmunity`, with the condition
  outranking the outcome the way it does at combat start): surprised party
  -> 0, lose -> 1, nothing decided -> 2, win -> 3, enemy surprised -> 4. A
  bought level is carried out with the montage's OWN clauses -- a
  `fairinitiative` first when the montage had decided against them (which
  takes the Surprised condition off the heroes and clears the unfavourable
  outcome), then `lose` / nothing / `win` / `surprise`. The party reads one
  line for it, the rung they bought ("The enemy is surprised."); the two
  clauses behind it go to the console.
- **Traps** is offered only when the encounter beat carries a `Place N <object>
  objects in <zone> zones` setup instruction, and it opens at 2 when the
  montage already earned `Reveal Traps` for every zone the encounter uses.
  Level 1 is a fact told to the party and nothing else (the count and the
  object's name come from the instruction, so the sentence cannot drift from
  what is really placed); level 2 banks the same `revealzones` effect the
  montage clause does, which `EncounterZones.ApplyPendingReveals` carries out
  behind the stage.
- **Enemy Stamina** drives the game setting `enemystambardisplay`, which the
  host re-asserts every tick: 0 -> `none`, 1 -> `bar` (a bar, no number),
  2 -> `val` (bar and exact Stamina). **This changes the game mode's
  default**: a week WITHOUT Intelligence still forces `bar`, as EotW always
  has, but a week with it starts the party at `none` and sells them the
  bars. `EncounterPrep.EnemyStaminaDisplay()` is the single authority and
  `EnforceStrictRules` reads it.

### Runtime state

```
data.prep = {
  beatIndex, phase = "spending"|"resolved"|"done",
  bars = { { id = "surprise"|"traps"|"stamina", level }, ... },  -- display order
  start = { [barId] = level },      -- what it opened on, so "bought" reads green
  spent = { { bar, userid, name, level, at }, ... },
  ready = { [userid] = { name, at } },
  applied = { "..." },              -- what the resolution really did
  requests = { [userid] = { seq, kind, ... } }, handled = { [userid] = seq },
  startedAt, resolvedAt, doneAt, seq,
}
```

There is no `arriving` phase (unlike the montage and the narrative): the host
tick only runs once the whole party is in, so the first thing anyone sees is
a screen they can act on. The bar TEXTS are not in the document --
`EncounterPrep.BarInfo(beat, barId)` derives them from the beat -- so a
level's wording can change without a stale document contradicting it.

### Implementation

- `EncounterOfTheWeek/EncounterScript.lua`: `EncounterScript.FEATURES`,
  `ParseFeatureUnlock`, `UnlockedFeatures`, `section.unlocks` / `beat.unlocks`
  and the three warnings (unknown feature, an `Unlock:` under an option or in
  a montage entry, Intelligence earned with nothing unlocking it); the
  `intelligence` effect kind and its `DescribeEffect` line.
- `EncounterOfTheWeek/EncounterMontage.lua`: `FeatureUnlocked`,
  `UnlockFeature`, `GetIntelligence`, `GetIntelligenceHistory`, the
  `intelligence` branch of `ApplyEffects`, and the four new fields in
  `ResetTest`.
- `EncounterOfTheWeek/EncounterNarrative.lua`: `ApplyUnlocks`, called from
  `Begin` (the beat's lines) and when a section opens (its own), plus
  `narrative.announce`, `ANNOUNCE_SECONDS` and `ActiveAnnounce`.
- `EncounterOfTheWeek/EncounterPrep.lua` (NEW -- registered in the CodeMod
  through the MCP workflow, before `EncounterMontageStage`; Firebase
  persistence confirmed): the whole runtime -- the bar definitions,
  `Required`, `IsLive`, `StartingSurpriseLevel`, `EnemyStaminaDisplay`, the
  spend/ready requests, `HostTick`, `Resolve`, a dev driver and
  `/eotwprep start|stop|state|force|reset|unlock|intelligence <n>`.
- `EncounterOfTheWeek/EncounterMontageStage.lua`: the unlock callout on the
  narrative stage (`eotwCallout*`), `CreatePrepStage` and its styles
  (`eotwPrepTrack`, `eotwPrepPip`, `eotwPrepLevel`, `eotwPrepPool`), and
  `PREP_HEADER_HEIGHT` -- the preparation header carries the pool under the
  title, so at the narrative's `HEADER_HEIGHT` the body overlapped it,
  the `"prep"` body kind in the mounted script stage, and the encounter
  beat's backdrop falling back to the last scene the script hung.
- `EncounterOfTheWeek/EncounterOfTheWeekHud.lua`: the Intelligence pool cell,
  the strip's two-or-three-cell layout, and the blinking rectangle.
- `EncounterOfTheWeek/EncounterScriptValidator.lua`: unlock lines in the
  report.
- `EncounterOfTheWeek/EncounterOfTheWeek.lua`: the preparation ahead of the
  spawn in `RunScriptBeat`, and `enemystambardisplay` read from
  `EncounterPrep` in `EnforceStrictRules`.
- `tests/encounter_script_test.lua`: 370 checks, up from 346.

### Verified 2026-09-20, live in an EotW game

The pools strip growing its third cell with the brain icon; the preparation
screen opening on the encounter beat with the three bars at their computed
levels; **real clicks** on "Spend 1 Intelligence" going through the request
path and the host applying them (traps 0->1, stamina 0->2, the pool counting
down in the strip and the header); the Proceed button appearing only at 0
Intelligence, and a Ready REFUSED while a point was still spendable; the
resolution applying `fairinitiative` + `surprise` for a party that opened
surprised (`data.initiative.outcome == "surprise"`, `surprised.party` cleared,
`surprised.enemy` set), banking `revealZones.trap` at traps 2, and
`enemystambardisplay` following the stamina level; and `Unlock: Intelligence`
in a narrative beat turning the feature on and a `|+2 Intelligence` option
filling the pool, end to end, through the real map-script host tick. The
callout and the blink were then verified on both placements of the line (the
beat's and a section's), including the rectangle really pulsing (sampled
bright and dark in consecutive screenshots), with no console errors. The
press-to-dismiss rule was verified against `ActiveAnnounce` for every phase
rather than by pressing on in the author's own live game.

**Still to verify**: two clients (a second player spending, and Proceed
waiting on both); the traps bar at level 2 actually revealing the zones when
the encounter beat runs the setup for real; the `val` stamina display on a
live monster's bar; and the whole beat running through to the spawn and
combat, which the live tests deliberately stopped short of.

### Open ends

- Intelligence does not persist past the week (the game is one encounter);
  leftover Intelligence is simply unspent, and the Proceed gate means there
  is normally none.
- Nothing yet SPENDS Intelligence outside the preparation screen, and nothing
  takes it away.
- The bars are fixed: a week cannot author its own rung texts or add a fourth
  bar. If that is wanted, `EncounterPrep.BarInfo` is the one place that knows
  them, and the levels would come off the script the way the traps count does.

---

# Development Plan

Phases are ordered so each produces something visible/testable. Update the Status section as steps complete.

## Phase 1 -- Dev gate + titlescreen entry point + EotW screen shell

1. [x] Declare `setting{ id = "dev:encounteroftheweek", default = false, storage = "preference" }` and the global entry point `EncounterOfTheWeek` (`.Enabled()`, `.ShowScreen()`). Done -- but in `Codex Titlescreen/EncounterOfTheWeek.lua`, NOT the EotW mod (see Architecture Notes: separate codemods do not load at the titlescreen). Registered in the Codex Titlescreen codemod at position 1.
2. [x] Top-right link in `CodexTitlescreen.lua` (id `eotwTitlescreenLink`, sibling of the `"<<Back"` button): floating `gui.Button`, `halign = "right"`, `classes = {"hideOnStartingScreen", ...}`, gated with `multimonitor`/`monitor` on the setting, all `EncounterOfTheWeek` reads via `rawget`. Verified live: toggling the setting shows/hides it on the next frame.
3. [x] EotW screen shell (`CreateScreen` in `Codex Titlescreen/EncounterOfTheWeek.lua`): full-screen panel mounted on `CodexTitlescreenRoot`, shop-screen 1920x1080 scale math, overview text, placeholder Games/Chat areas, CloseButton + escape both routed through a `closeEncounterOfTheWeek` event. Verified in the app at the real titlescreen: opens from the link, renders correctly, closes, reopens.

Deliverable: MET (verified 2026-08-27) -- toggling the setting shows the link; clicking opens/closes the shell screen.

## Phase 2 -- Design + deploy the Lobby backend

The Lobby is a new server-side concept (see Architecture Notes, "The Lobby"). This phase
designs it and gets it running on staging, testable without any engine build (e.g. a Node
test client or the debug console, per how the game DO is tested today).

4. [x] Design pass: all decisions settled and recorded in the Lobby architecture
   section (DO shape, document model, action list + shapes, chat retention 200,
   presence mechanism, liveness/expiry policy).
5. [x] Implement `LobbyObject`: `src/lobby-core.ts` (pure arbitration logic) +
   `src/lobby.ts` (the DO), `request` envelope + `ack.result` in `types.ts`,
   `/lobby/{lobbyid}` + `/api/lobby/{lobbyid}/doc` worker routes, `LOBBY` binding +
   migration v3 in both wrangler configs. Clients get `subscribe`/`get` only; every
   other write type is rejected.
6. [x] Server-side request handlers (the arbitration layer) implemented per the
   surface above. Unit-tested: `test/lobby-core.test.ts` (20 tests -- bucket regen,
   chat validation + trim, create/confirm/join/leave/heartbeat arbitration, expiry
   sweep); full suite green (239 tests), `tsc --noEmit` clean.
7. [X] Verify + deploy to staging: `test/lobby-smoke.ts` (two clients; chat both ways,
   live presence, stamped identity, direct put/patch REJECTED, duplicate create
   REJECTED, over-capacity and private joins REJECTED, heartbeat, host-leave drops
   record, rate limit engages, HTTP doc snapshot) -- ALL CHECKS PASSED against
   `wrangler dev --env staging` locally, and the document survived a full runtime
   restart (SQLite reload path).

Deliverable: an `"eotw"` lobby reachable on the staging worker; two scripted clients see
each other's chat and presence.

## Phase 3 -- C# lobby interface + EotW screen integration

8. [x] Engine: `Assets/Scripts/LobbyConnection.cs` -- `LobbyConnectionManager`
   (singleton pump, one shared connection per lobbyid+staging) + `LobbyConnection`
   (slim sibling of `DOConnection`: same `DOWebSocketFactory` transport,
   `LoginController` token, 0.5-60s reconnect backoff, 30s request timeouts, plus a
   50s auto-ping for the server's 120s stale sweep). Maintains a local mirror of the
   lobby document by applying server puts; exposes `Request(action, args, ...)`,
   `GetAtPath`, `revision`, and `DocChanged`/`StatusChanged` events. Fully
   independent of `GameController`/`DataStore`. Staging selection is caller-driven
   (the Lua passes `staging = true` while EotW is dev-gated). NEEDS ENGINE BUILD.
9. [x] Lua bridge: `Assets/Scripts/LobbiesLua.cs` -- global `lobbies`
   (`lobbies.Connect(lobbyid, {staging, displayName})` -> `LuaLobbyConnection` with
   `connected/status/revision`, `GetDoc/GetPath`, `Request{action,args,success,error}`,
   `MonitorChanges/MonitorStatus`, `Disconnect`), registered in `ScriptEngine.cs`
   next to `lobby`. LuaLS stub: `Definitions/lobbies.lua`. Display name defaults to
   the account display name via `LoginController.displayNameInCurrentGame`.
10. [x] EotW screen (`Codex Titlescreen/EncounterOfTheWeek.lua` rewritten): connects
    to the `"eotw"` staging lobby on open, disconnects via the panel `destroy` event,
    renders presence ("Here now (N): ..."), a chat view (newest-first list, input with
    400-char limit, rejected sends surface the server's error for 5s), and a
    connection-status line. All `lobbies` access is `rawget`-guarded: on an engine
    build without the bridge the screen shows "engine update required" notes instead.
11. [x] Games-list UI driven by `/state/games`: renders each record's name, host,
    slots, private tag (private records only shown to their host), with an empty-state
    note. Rendering only -- create/join UI is Phase 4.

Deliverable: implemented; NOT yet verified live -- needs an engine build, then two
clients on the EotW screen chatting/seeing presence. Lua deployed (gitfolder = repo).

## Phase 4 -- Creating and joining EotW games

12. [x] Create-game flow: "Create Game" button + dialog (name input, encounter
    dropdown when the module offers more than one -- see "Choosing the week's
    encounter", 2026-09-15 -- public checkbox) in the EotW screen. Flow as designed: lobby `create-game` request (reserve) ->
    `lobby:CreateGame` -> lobby `confirm-game` with the new gameid -> host `join-game`
    with 1 slot. The confirm fires even if the dialog was closed mid-create (an
    engine game exists by then; only a confirm lists it). INTERIM: games are created
    with `startingModule = "mcdm-startermap"` (the Custom Campaign starter) and
    `backend = "durableobjects-staging"` -- switch the module to
    `mcdm-encounteroftheweek` in Phase 5 when it exists (constants `STARTING_MODULE`
    / `GAME_BACKEND` at the top of `Codex Titlescreen/EncounterOfTheWeek.lua`).
13. [x] Per-game lobby state: DECIDED kept in the lobby DO's roster record until
    launch (not a game-side document) -- each player's `heroes` list IS the slot
    state, written only by the DO via `join-game`/`set-heroes` (details in the
    Lobby architecture section). Ready state remains for Phase 6.
14. [x] Join flow + slot-filling view: DONE. Creating, joining, or opening a game
    lands in the **game lobby view** inside the EotW screen. REDESIGNED
    2026-08-28 into **hero cards** (see the "Hero-card lineup" design bullet
    below; originally numbered vertical slot rows): a horizontal wrapping row of
    3:4 portrait cards, each with a translucent identity plate (name /
    level+ancestry+class / "Controlled by X"), a hover trash (remove my hero) or
    kick action, a "+" card that opens the Add Hero picker (now a card GRID of
    the same visuals: local titlescreen heroes via `dmhub.GetAllCharacters` +
    pregens from the module cache; already-claimed ids filtered out; sends the
    full list via `set-heroes`, max 4 per player), membership controls
    (Join / Leave / Abandon; the interim "Enter World" button was removed in
    step 21 -- Begin is the only launch path), and the chat column switched to
    the game's private channel. There is deliberately NO
    back button in the game lobby view (2026-08-27 decision, removed the old
    "<< All Games" relabel of the Create Game button): the only way back to
    the games list is leaving the game -- a player Abandons/Leaves, or the
    host cancels. While the view is open the Create Game button is collapsed.
    The list-mode rows are now Open (members) / Join
    (non-members); joining no longer claims a slot -- heroes are picked in the
    view. Members' games heartbeat every 30s from a screen think.
    Known gap: lobby leave-game does not remove the player from the engine
    game's `players` list (no engine LeaveGame API today).
15. [x] Host controls IMPLEMENTED (2026-08-27; staging deploy + live test pending):
    - **Server**: `kick-player {gameid, userid}` action -- host-only, target must be
      a non-host player; removes the player (their whole hero claim goes with them)
      and broadcasts the roster change. The kicked player's connected sockets get a
      null put for `/gamechat/{gameid}` (mirror cleanup, same as leave). Files:
      `lobby-core.ts` (`applyKickPlayer`), `lobby.ts` (dispatch + kicked-client
      chat cleanup), `lobby-core.test.ts` (2 new tests; suite 247 green, tsc clean),
      `lobby-smoke.ts` (step 8b: non-host kick rejected, self-kick rejected, kick ok,
      roster broadcast, kicked client's chat mirror cleared -- ALL PASSED against
      local `wrangler dev --env staging`). **Staging deploy is a user action**
      (`npm run deploy`); until then the client's Kick shows "Unknown action".
    - **Client** (`Codex Titlescreen/EncounterOfTheWeek.lua`): Kick button on other
      players' slot rows (host only); hero-less members get their own listed row
      ("<name> -- no heroes yet") so the host can see and kick them too; Begin
      button (host-only, open games) enabled at 3-7 filled slots -- dimmed under 3,
      click then explains the gate. (An enabled click originally reported "not
      implemented yet"; step 21 wired it to `launch-game`.)
    - NOT done here: engine-game-side kick (`dmhub.KickPlayer` targets the CURRENT
      game, so it cannot run from the titlescreen). Grouped with the known
      leave-game gap: lobby membership changes do not touch the engine game's
      players list. Revisit in Phase 6 when the host is in-game.

Deliverable: full lobby loop up to pressing Begin.

## Phase 5 -- The mcdm-encounteroftheweek module

16. [X] The "Start" EnvironmentalKeyword (playerVisible, no mechanical effects) is part of the module. VERIFIED in the published snapshot (2026-08-27): keyword `27f8df28-b662-4f81-826a-bd51be4521bb`, empty modifiers, no `defaultPlayerVisible` override (absent = visible); the painted zone record has `playerVisible: true`.
17. [X] Build the first Encounter map. DONE as of module v7 (2026-08-31): the map named "Encounter" (`8d78cadf-03cc-42f1-8c45-8764021b5fb6`) ships with its Start zone painted, no tokens, and a reachable encounter document -- "Room 1" (`645e4522`, via info bubble `c64e02d1`), whose `encounter` island has 6 groups / 23 monsters with per-hero-count `balancing` entries and banked spawn locations. It is authored as a YAML file in `C:\dev\eotw` rather than as a game-store row, so it ships by being derived, not ticked. The rest of this entry is the 2026-08-27 history that led here.

    ORIGINAL (re-inspected 2026-08-27 against v2, dataid `c0805b51-...`): the map named "Encounter" exists and is the module's only map (natural fallback selects it), in folder "Delian Tomb - Part 1", with the Start zone painted (19 tiles on floor `8de328e8`, zone `0ee1e996`). **GAP (still present in v2): the map has NO live encounter.** Its 5 map characters are all `despawned: true` -- 3 Goblin Snipers with 9 damage_taken and leftover combat paths (a played-out fight) plus 2 blank "Monster" strays. **The intended encounter is now known**: the source game's journal doc "Goblin Guards Combat" (docid `04eae049-3fdf-478c-a40f-d2376837e0fa`) specifies the tomb-exterior fight -- six **goblin warriors** at start (groups of two), round-2 reinforcements of two goblin warriors + two **goblin assassins** from the tomb entrance, with hero-count adjustments (6 heroes: +2 warriors; 4 heroes: -2; 3 heroes: -4), staged via `[[encounter]]` island widgets with a Place on Map button. Neither that document nor any encounter asset ships with the module yet. **DECIDED (2026-08-27): the encounter is spawned programmatically at game setup, scaled to hero count (Phase 6 step 20)** -- the map stays token-free by design. Remaining module work for this step (user, in the source game -- the how is now RESEARCHED, see "How journal documents ship" in Module + codemod bundling): tick the "Goblin Guards Combat" doc (docid `04eae049-3fdf-478c-a40f-d2376837e0fa`) under ModShare's Compendium > "documents" section, delete the despawned sniper/stray characters from the map, and republish (v3). No encounter asset is needed -- the `[[encounter]]` annotation with its banked spawn positions rides inside the doc record.
18. [X] Author 3+ pregen heroes as module content. VERIFIED against v2: 8 pregens ship with `IsHero()` true and resolvable classes -- Dwarf Fury, High Elf Tactician, Human Censor, Human Null, Human Talent, Orc Conduit, Polder Elementalist, Polder Shadow (only Wode Elf Troubadour of the 9 official pregens is absent).
19. [X] Publish the module with the Monster AI codemod ticked in ModShare. VERIFIED in v2's snapshot.codemods: both the EotW stub codemod (`cdc19d98-...1428`) and Monster AI (`263594e2-aca1-4ce5-b70e-8d690695d7b4`) are bundled. (v1 lacked Monster AI; `ReconcileStartingModuleCodemods` repairs v1-created games as the version advances.) The install-side `codeModsFromModules` write is engine code proven by the Crowdex precedent; verify once the first game is created from the module.

19b. [X] Automate publishing (`tools/eotw_publish/`, 2026-08-30). `publish_eotw.py` republishes the module headlessly -- no DMHub, no Unity -- reading the Local authoring game's SQLite through a throwaway copy of the real local game server, deriving the week's contents (every map named `Encounter` or `Encounter: <title>` -- multi-map since 2026-09-15 -- + documents filed under them + `Start` keyword + pregen-party heroes + pinned codemods + dependency closure + dependency modules' codemods), and writing `/ModuleVersions`, the blob store and `/Module/{fullid}`. Verified against published v4 with `--verify-against`: identical payload modulo real edits since. Dry run by default; refuses to publish when the report warns the module would not play. Design + gotchas in "Publishing the weekly module headlessly" above and in `tools/eotw_publish/README.md`.

Deliverable: manually creating a game from this module yields a playable encounter map with AI available. NOT YET MET -- the only remaining blocker is the step 17 empty-encounter gap. `STARTING_MODULE` in `Codex Titlescreen/EncounterOfTheWeek.lua` now points at `mcdm-encounteroftheweek` (swapped 2026-08-27), so the next game created through the EotW screen exercises the module end-to-end.

## Phase 6 -- Launch + in-game encounter flow

**DECIDED (2026-08-27): encounter spawning is programmatic ("option 2").** The
Encounter map ships with no live monsters. At game setup, EotW game-side Lua finds
the encounter in the map's journal documents and spawns it, scaled to the number of
heroes in the game. This matches the adventure's own design: the "Goblin Guards
Combat" doc carries hero-count adjustments (5 heroes: 6 goblin warriors; 6 heroes:
+2; 4 heroes: -2; 3 heroes: -4) and stages monsters through `[[encounter]]` island
widgets -- and EotW's 3-7 slot range maps exactly onto those adjustments. The
`[[setting:numheroes]]` island in the doc points at the "Number of Heroes" setting
that drives the encounter panel's scaling (see research pointers below).

**All game-side logic lives in the EotW stub codemod**
(`EncounterOfTheWeek/EncounterOfTheWeek.lua`, codemod `cdc19d98-...1428`), which
already ships with the module -- this is where the serious coding starts. (During
step-20 development it was testable without the Begin flow via an interim
per-member "Enter World" button; that button was removed when step 21 landed --
Begin is now the only launch path, with the resume row for re-entry.)

20. [~] **Game setup on entry: IMPLEMENTED (2026-08-27); partially verified live.**
    The full flow: Enter World (titlescreen) copies the player's claimed lobby
    heroes to the token clipboard, then `lobby:EnterGame` with an arrival callback
    that calls `EncounterOfTheWeekGame.SetupOnArrival{heroes, clipboardIds,
    numHeroes}` (game-side EotW codemod). On arrival every member pastes/claims
    their own heroes into the Start zone (re-entry-safe via the `eotwstate` doc);
    the host additionally sets `numheroes` (clamped 3..7) and spawns the map's
    journal `[[encounter]]` at its banked positions scaled to hero count.
    Design details in Architecture Notes ("Hero transfer into the game" and the
    Encounter spawning bullet). Files:
    - `EncounterOfTheWeek/EncounterOfTheWeek.lua` -- the codemod, no longer a
      stub: SetupOnArrival, SpawnEncounterMonsters, Start-zone query, hero
      paste/claim + re-entry guard, ResetPlacedHeroes dev helper.
    - `Codex Titlescreen/EncounterOfTheWeek.lua` -- EnterWorld (clipboard load +
      arrival handoff). Originally exposed as a per-member "Enter World"
      button; that button was removed in step 21 (DECIDED 2026-08-27: Begin
      is the only way into the game). EnterWorld remains the internal entry
      routine, invoked by the launch watcher and the resume row.
    - `Draw Steel V/EncounterPanel.lua` -- `SpawnGroupForReal`/`AdjustedGroupCount`
      promoted to `Encounter.*` globals + the per-token UpdateCharacterTokens
      naming fix.
    - Engine (NEEDS BUILD): `dmhub.CopyTokensToClipboard`/`PasteTokensFromClipboard`
      in `Assets/Scripts/LuaInterface.cs` + `Definitions/dmhub.lua` stubs.
    **Verified live in the source game** (which has the doc, Start zone, and
    codemod): encounter discovery (finds Goblin Guards via its info bubble, map
    filter excludes other docs), spawn at 5 heroes -> Goblin Warriors 1-6 at the
    exact banked tiles in 3 initiative groups (minHeroes=6 group correctly gated
    out), double-spawn guard, island `spawns` list kept consistent, pregen
    placement (Dwarf Fury duplicated into the Start zone, claimed to the default
    party), and the re-entry guard (second SetupOnArrival placed nothing). All
    test artifacts cleaned up; doc restored.
    **Still to verify: the real end-to-end** -- engine build (batch clipboard),
    module republish with the doc (step 17), then Enter World from the EotW screen
    into a fresh EotW game: lobby-hero paste + Start-zone landing + host spawn,
    and a second client joining. Until the engine build, only the first claimed
    lobby hero is carried (graceful degrade).
21. [x] Begin: IMPLEMENTED (2026-08-27; server locally verified, staging deploy +
    live 2-client test pending). Host's Begin sends `launch-game` (server:
    `applyLaunchGame` in `lobby-core.ts` + dispatch in `lobby.ts`; host-only,
    open game, `slotsFilled >= MIN_HEROES_TO_LAUNCH` (3); flips `status` to
    `"launched"` and broadcasts the record -- the roster is frozen from then on
    since join-game/set-heroes gate on open). Client
    (`Codex Titlescreen/EncounterOfTheWeek.lua`): `CheckLaunchedGames`, run at
    the top of every RefreshGames (so on every roster broadcast, reconnect, and
    screen open), enters the world via the step-20 `EnterWorld` flow
    (`m_enteringWorld` guards double entry). SUPERSEDED DETAIL (2026-08-27):
    host and joiners no longer take the same path at the same time -- the HOST
    enters on "launched", runs setup in-game, and the game-side codemod sends
    `ready-game` ("launched" -> "ready"); other members enter only on "ready"
    (waiting note shown in the game view meanwhile). See "Joiner-side module
    install race" for why. Members with zero heroes (observers) enter too.
    SUPERSEDED (2026-08-28): a member who reopens the screen while their game is
    ALREADY launched/ready is no longer auto-pulled in -- auto-entry fires only
    on status transitions the open screen observed; pre-existing records get an
    explicit Re-join button instead (see "Returning to the titlescreen" in
    Architecture Notes).
    **DECIDED (2026-08-27): the per-member "Enter World" button is gone** --
    Begin is the only way to launch into the game; the resume row ("Your game
    in progress" -> Resume) remains the re-entry path for a game whose roster
    record has expired. Tests: `lobby-core.test.ts` +2 (suite 249 green, tsc
    clean); `lobby-smoke.ts` step 8c (non-host + under-strength + double launch
    rejected, broadcast observed, post-launch join/set-heroes rejected,
    heartbeat still ok) -- ALL CHECKS PASSED against local
    `wrangler dev --env staging`. Staging deploy is a user action
    (`npm run deploy`); until then Begin's click gets "Unknown action".
22. [~] Starting-zone phase: DEFERRED (2026-08-28 user direction: combat enters
    as soon as every player is in the game -- see the "Automated combat entry"
    architecture section; a positioning/ready-up phase may return as a later
    requirement). PARTIALLY REVIVED as step 25 (2026-08-28, later): the
    movement-confinement half (players move only within Start-zone tiles,
    zone marked visibly) is built; the ready-up gate remains unbuilt -- combat
    still enters on the arrival gate alone.
23. [x] Monster AI auto-run + no-Director presentation: BUILT 2026-08-28
    (UNTESTED live). `MonsterAI.StartAI()/StopAI()/IsAIRunning()` exported;
    the EotW map script's host tick keeps the AI running while combat is live
    and stops it when combat ends. Director-facing UI hidden via the new
    `GameHud.RegisterDirectorUIFilter` / `GameHud.DirectorUIVisible()` core
    hook + an EotW filter (host keeps owner+DM internally, exactly as decided).
    Details + the recorded presentation gaps (engine DM vision, token menus,
    etc.) in the "Automated combat entry + no Director" architecture section.
24. [x] Encounter start: BUILT 2026-08-28 (UNTESTED live). When all expected
    players have arrived (arrival tracking in `eotwstate`), the map script's
    host tick calls the new `Encounter.StartCombatWithTokens` hook: the normal
    Draw Steel banner + claim-the-die roll for everyone, all heroes vs all
    monsters, the map's authored encounter driving victory/rewards. Completion
    detection beyond "stage flips to complete and the AI stops" (victory flow,
    next steps) remains later work.

25. [x] Pre-combat start-zone confinement: BUILT 2026-08-28 (engine NEEDS
    BUILD, UNTESTED live). New engine Movement Restriction Mode
    (`dmhub.SetMovementRestriction`/`ClearMovementRestriction` +
    `GameController.movementRestrictionLocs` + enforcement in
    `CharacterToken.GetMoveCostFn` and the `UpdateDragging` commit backstop);
    EotW driver confines every client to the Start zone from arrival until the
    initiative queue goes live, drawing the zone with `dmhub.MarkLocs`.
    Design in "Start-zone confinement during the pre-combat phase".
26. [x] Victory/defeat auto-detection + player Proceed + auto-exit: BUILT
    2026-08-28 (UNTESTED live; Lua only). Host tick awards
    victory/defeat from `CheckVictory`/`CheckDefeat`/all-heroes-down; the
    victory screen shows everywhere via the existing queue flags; new
    `DSVictoryScreen.RegisterProceedOverride` core hook lets every EotW player
    press Proceed (players relay through the host via `proceedRequested`);
    every client that saw the outcome auto-exits to the titlescreen ~4s after
    the queue hides. Design in "Victory/defeat auto-detection, player Proceed,
    and auto-exit". REVISED 2026-09-08 (UNTESTED live): per-client dismissal
    -- the screen is held locally until the local Proceed press
    (`holdUntilLocalProceed` hook in `DSVictoryScreen.lua`,
    `m_localProceeded` gate on the auto-exit in `EncounterOfTheWeek.lua`).

27. [x] Strict rules enforcement: BUILT 2026-08-28 (Lua only, UNTESTED in a
    live EotW game). All "Strict..." rules-enforcement settings (the four
    `strict:*` Rules Enforcement options + the engine's
    `strictmovementrules`) are forced on by the host at setup and re-asserted
    every host tick. Design in "Strict rules enforcement". 2026-08-29: found
    live to not bind the HOST (DM-exempt gates); resolved by step 28.
28. [x] Player-host mode: BUILT 2026-08-29 (engine NEEDS BUILD, UNTESTED
    live). `dmhub.playerHostMode` / `dmhub.isDMOrPlayerHost` engine split +
    the full audit of every isDM site (engine, core Lua, codex) converting
    hosting-capability reads to the real check; EotW arms the mode on the
    host, making the host a genuine player (vision, UI, strict rules) while
    its machine keeps hosting (AI, setup, election, teardown). Design in
    "Player-host mode: the isDM / isDMOrPlayerHost split".
    **2026-08-29 later: infinite reload loop found + fixed (engine NEEDS
    BUILD).** First live entry into an EotW game on the playerHostMode
    build looped forever: arming the mode forces the view-as-player hard
    refresh, the refresh destroys/recreates the GameController for the
    same game (`GameHarness.RefreshGame` -> `EnterGame`), the fresh
    instance starts with `playerHostMode = false`, and the 1s driver
    re-arms it -- one full game re-entry every ~4.3s (loading screen
    restarting from the beginning). Evidenced live via a diagnostic in
    `UpdatePlayerHostMode` (kept, now logs every arming). Fixes:
    `GameHarness.RefreshGame` carries `playerHostMode` onto the new
    GameController; and the spurious "Lua has been updated. F4 to
    refresh." notification the loop surfaced (every teardown's
    `UnloadCodeMod` -> `InvalidateMod` marked checked-out dependent mods
    as locally changed with zero file edits) is fixed by
    `ScriptEngine.UnloadCodeMod(modid, invalidateDependents)` -- full
    teardowns (`UnloadAllCodeMods`, `ReloadScripts`) pass false, targeted
    hot-reloads keep the cascade. Until the engine is rebuilt, the loop is
    held off on the dev machine by `/toggle eotw:showdirectorui` = ON
    (set 2026-08-29): **toggle it back off after the next engine build**
    to actually exercise player-host mode. Expected post-build behavior:
    entering an EotW game still runs the loading screen twice (the one
    legitimate arming refresh), then settles.
    **2026-08-29 (later still): the loop-fix build went live, the hatch
    came back off, and the first fresh CREATE corrupted the game** --
    the driver armed mid-starting-module-install; the refresh killed the
    install's floor uploads and the arrival callback (black map, no
    setup, unrepairable since the manifest reads INSTALLED). Fixed by
    quiescence-gating the arming (Lua deployed: arm only after full load
    + a `hostSetupComplete` doc stamp aged past a 10s flush window,
    stamped at the END of SetupOnArrival's host branch) plus an engine
    deferral of `s_forceHardRefresh` during load/install (NEEDS BUILD).
    Full design in "Arming is quiescence-gated" under the Player-host
    section. The corrupted game `MythicMintyPersistentScholar` must be
    Abandoned. NEXT LIVE TEST: abandon, create fresh, expect Director-UI
    beat -> setup -> one arming refresh ~10s after entry -> player view,
    heroes placed, encounter spawned, floors intact.

28. [x] Custom interface: BUILT + partially verified live 2026-08-28 (Lua
    only, no engine change). Core `GameHud.RegisterCustomInterface` hook +
    consumers (rails, titlebar, panel registries, search, character-panel
    access) and the EotW hud (`EncounterOfTheWeekHud.lua`: no side
    buttons, no Panels menu, no Compendium, right-edge hero roster with
    read-only character-panel popouts). Design + verification status in
    "Custom interface: usurping the game hud". Still to see live: multiple
    heroes with real per-player ownership, and a real EotW game.

Deliverable: end-to-end -- lobby to fought encounter with AI-run monsters.

## Phase 7 -- Encounter scripts: montage beats before combat (BUILT 2026-09-18 through step 33 plus 36-39, plus step 46 on 2026-09-19; UNTESTED live)

Design in "Encounter scripts: montage beats before combat" under
Architecture Notes. All Lua in the EotW codemod (three new top-level files
registered through the MCP CodeMod workflow, `register_lua_file`), one
possible core hook. Steps are ordered so each is testable on its own; 29
and 30 change nothing visible for a script with no montage.

29. [x] **Parser** (BUILT + unit-tested 2026-09-18): `EncounterOfTheWeek/EncounterScript.lua` -- pure Lua,
    no engine globals. `EncounterScript.Parse(text) -> {beats, warnings}`
    per the grammar (beats, rounds, entries, options, power rolls, effect
    clauses), plus `EncounterScript.ParseAttr(attr, attributesInfo,
    skillOptions)` (the characteristic/skill mapping, injected so the
    module stays engine-free). Unit tests under `draw-steel-codex/tests/`
    run with `dependencies/lua/bin/lua.exe` against the sample script and
    edge cases (no beats + `[[encounter]]`, no round heading, four-tier
    roll, unknown clause -> warning). Dev command `/eotwscript` dumps the
    parse of the current map's script with warnings and resolves item and
    monster names against the game.
30. [x] **Beat machine + deferred spawn** (BUILT 2026-09-18, UNTESTED): `FindMapScript` (same discovery
    as `FindMapEncounter`, returns doc + parse), the `eotwscript` state
    doc, the host tick's beat loop, `SpawnEncounterMonsters` moved from
    `SetupOnArrival` to the encounter beat, `hostThinkInterval` 2 -> 0.5.
    Test: today's published week (no montage) plays identically.
31. [x] **Montage runtime** (BUILT + VERIFIED in the authoring game 2026-09-18): `EncounterOfTheWeek/EncounterMontage.lua` --
    request stamping (player side), host validation + turn lifecycle,
    round/consequence progression, the owning client's roll launch
    (`ShowDialog` as in `RollCustomPowerTableTest`, tier out of
    `completeRoll`), effect application under elevation (items, stamina,
    malice, allies), `allies` bookkeeping. Testable headless over MCP
    (`execute_lua` stamping requests, inspecting the doc) before any UI.
    Build-time checks recorded in the design: the untyped damage-type
    string, whether Draw Steel re-seeds malice, the roll-dialog tier field.
32. [x] **Stage UI** (BUILT + VERIFIED in the authoring game 2026-09-18; drag gesture itself unexercised): `EncounterOfTheWeek/EncounterMontageStage.lua` --
    the presentable dialog (or the `overlayPanel` fallback), scene
    backdrop, opportunity/threat columns, draggable hero-card row with
    ally mini-cards, the turn panel, the consequences reveal. Iterate in
    the test harness / `eotw:forcecustomui` before a live game. Export
    `CreateHeroCard` and `CreateMaliceDiamond` from the hud. Refined
    2026-09-19: the header is auto-height and the intro prose is the
    party's standing context for the beat (see the Header bullet under
    "The stage (UI)").
33. [~] **Combat with allies** (sides + ally cards BUILT 2026-09-18, ally spawn + cards VERIFIED; the AI / victory / action-bar checks in a real combat are UNVERIFIED): `GatherCombatSides` puts player-controlled
    non-heroes on the players' side; ally mini-cards under the right-rail
    roster cards too; verify the AI ignores allies, victory does not count
    them as monsters, and the owner can drive one from the action bar.
34. [ ] **Authoring + live test** (the sample script is already in the authoring game's `Encounter` document; the rest is open): put the sample script into the
    authoring game's encounter document (`C:\dev\eotw`, `room-1.yaml` or a
    new doc filed under the map), make sure `Wode Elf Sentry` and `Healing
    Potion` resolve in the published module (the sentry must come from the
    module or a dependency), republish, run a two-client game end to end:
    montage -> consequences -> spawn -> Draw Steel with an ally.
35. [ ] **Publisher validation** (later): port the grammar's checks to
    `tools/eotw_publish/publish_eotw.py` -- unknown beat, option without a
    roll, unrecognized clause, unresolvable item/monster -- as per-map
    warnings like the existing encounter checks.

36. [x] **Initiative clauses** (BUILT 2026-09-18, luac-clean, parser
    unit-tested (77 checks), runtime + core hook UNTESTED live,
    UNCOMMITTED): `you begin the encounter surprised`, `you surprise the
    enemy`, `you win initiative`, `you lose initiative` on tiers and
    `Consequence:` lines. Parser (`EncounterScript.ParseInitiativeClause`,
    `DescribeInitiativeOutcome`), runtime (`doc.data.initiative`,
    `EncounterMontage.GetInitiativeOutcome`), encounter beat
    (`StartEncounterCombat` in `EncounterOfTheWeek.lua`), core hook
    (`Encounter.StartCombatWithTokens{immediateResult, surprisedTokens}` in
    `Draw Steel UI/DSInitiativeRoll.lua`). Test: put `Consequence: You
    begin the encounter surprised.` on a threat, leave it unvanquished,
    Continue through the consequences -> the banner should announce the
    monsters with no die and every hero (and ally) should carry Surprised
    in the queue; then a tier with `You surprise the enemy` -> heroes
    announced, every monster Surprised; `You win/lose initiative` -> the
    side announced, nobody Surprised. Also check the stage's applied line.

37. [x] **Boon clauses** (BUILT 2026-09-18, luac-clean, parser unit-tested
    (93 checks), runtime VERIFIED live for heal / temporary stamina /
    Recovery Value / hero tokens; the surge payout's in-combat half
    UNTESTED): five reward clauses beyond items and malice --
    `you heal <n> stamina`, `you gain <n> temporary stamina`,
    `at the start of the next combat you gain <n> surges`,
    `your recovery value is increased by <n>`, `+<n> hero token`, each with
    an `each party member` spelling (hero tokens are one shared pool, so
    they have no target). Also `you vanquish the threat` as the active
    spelling of `the threat is vanquished`. Parser: the boon block at the
    top of `ParseClause`, matched BEFORE the generic
    `you gain <qty> <item>` rule, which would otherwise read
    "you gain 5 temporary stamina" as an item named "temporary stamina".
    Runtime (`EncounterMontage.lua`): `HealStamina`, `GrantTemporaryStamina`
    (takes the higher of old and new -- Draw Steel temporary Stamina does
    not stack), `GrantRecoveryBoon`, `GrantSurges`, and the hero-token pool
    via `CharacterResource.Set/GetGlobalResource`.

    Two traps worth keeping:

    - **Recovery Value needs an ongoing-effect ASSET.** The boon is an
      ongoing effect named `Montage Boon: Recovery Value +N`, holding one
      `behavior = "attribute"` / `attribute = "recoveryvalue"` modifier,
      applied `until_rest`. `creature:ApplyOngoingEffect` looks the asset up
      through `GetTableCached`, whose snapshot only refreshes on the
      `refreshTables` event -- an asset uploaded in the same breath as the
      grant is INVISIBLE and the apply silently returns nil.
      `EncounterMontage.PrepareBoonAssets(beat)` therefore creates every
      value the beat needs from `EncounterMontage.Begin`, and
      `GrantRecoveryBoon` reports failure rather than a phantom grant if the
      asset still is not visible.
    - **Surges cannot be granted before combat.** Surges are a
      `clearOutsideOfCombat` resource: `creature:AddUnboundedResource` drops
      the grant outright when `dmhub.initiativeQueue` is nil or hidden. They
      are therefore BANKED on the script document (`data.surges =
      { [heroCharid] = n }`, top level like `initiative`, cleared by
      `/eotwmontage reset`) and paid out by
      `EncounterMontage.ApplyPendingCombatBoons`, driven from the host
      tick's queue-live branch in `MapScriptHostThink` -- not from
      `StartEncounterCombat`, where the queue may not be live yet. The
      function re-checks the queue itself, so an early call leaves the bank
      for the next tick.

38. [x] **Surprise immunity** (BUILT 2026-09-18, parser unit-tested (101
    checks), grant + doc state VERIFIED live, the combat-start branch
    UNTESTED): `you cannot be surprised` -- the heroes still LOSE the
    initiative to a `surprised` outcome, but the Surprised condition is
    withheld from the whole party (every hero and ally), whoever earned the
    boon. Parser: `EncounterScript.ParseSurpriseImmunityClause`, effect kind
    `nosurprise`, **checked before the initiative clauses** -- the existing
    `^you .*surprised$` rule matches "you cannot be surprised" and would
    otherwise make it mean its exact opposite (this is how it first landed
    in the live document, silently and with no warning). Runtime:
    `doc.data.noSurprise = { entryName, at }` at the TOP level like
    `initiative`, read by `EncounterMontage.HasSurpriseImmunity` and applied
    in `StartEncounterCombat`, which nils `surprisedTokens` while leaving
    `immediateResult = "monsters"` alone. Cleared by `/eotwmontage reset`.
    It does not touch the `surprise` outcome (that Surprises monsters).
    Extended by item 47: it now also purges the Surprised condition the
    montage already applied, since surprise lands the moment it is
    announced and immunity can be earned after it.

    **Wording fixed 2026-09-20** (reported live; parser tests now 346
    checks, UNTESTED live): the condition was withheld correctly, but a
    `surprised` consequence landing on top of the boon still announced
    "The heroes will begin the encounter surprised", which read as the
    immunity having been lost. `DescribeInitiativeOutcome` now takes an
    `immune` flag and says "The heroes will lose initiative, but they
    cannot be surprised"; `ApplyEffects` computes `surpriseImmune` once
    at the top of the `initiative` branch and feeds both the condition
    guard and the wording from it.

39. [x] **Assisting a test** (BUILT 2026-09-18, luac-clean, parser tests
    still 101/101 -- no parser change; **UNTESTED live**): design in
    "Assisting a test" under Architecture Notes. A test that lands below
    tier 3 opens an assist window; a hero trained in one of the test's
    listed skills -- one the acting hero is not already using -- may be
    dragged into the assist slot, rolls the same characteristic with their
    own modifier and an automatic Skilled +2 against the fixed bane / edge /
    double-edge table, and the result shifts the test's tier before its
    effects are applied. Costs the helper their turn. One assist per test.
    `EncounterMontage.lua` + `EncounterMontageStage.lua`; no engine change.

    Test: approach an entry whose roll lists two or more skills, roll a tier
    1 or 2 with a hero trained in one of them while another hero is trained
    in a different one -- the second hero should grow a "!" and the assist
    slot should name them and their skill. Drag them in, roll: a tier 2
    assist (edge) should push a 15 to a 17 and tier 2 to tier 3; a tier 1
    (bane) should be able to drop a 12 back to tier 1; a tier 3 (double
    edge) should raise the tier with the total unchanged. Then check that
    the helper is marked as acted, that "Take the result" resolves on the
    test's own tier, that the 30 s timeout does the same, and that a tier 3
    test never opens the window at all.

46. [x] **Entries come and go with the rounds** (BUILT 2026-09-19,
    luac-clean, **UNTESTED live**): a later round's entries are no longer
    carded ahead of time under an "Appears in round N" line -- they
    materialize when their round arrives, and an entry the party dealt
    with fades out and is destroyed when the round ends. Design in the
    "columns hold only what is in play" bullet under "The stage (UI)".
    `EncounterMontageStage.lua` only; no parser, runtime or engine change.

    Test: a two-round montage (the sample script's `Through the Wode`
    qualifies). Round 1 should show only the round-1 entries. Take an
    opportunity and vanquish a threat, then let every hero act: as round 2
    opens, those two cards should fade away and go, and the round-2 entries
    should ramp in one after another. Then reload mid-round 2 -- what was
    dealt with in round 1 must not come back, and what was dealt with in
    round 2 should still be there with its "Taken" / "Vanquished" line.

47. [x] **Surprise is sticky, and lands during the montage** (ROOT-CAUSED +
    FIXED 2026-09-19, luac-clean, parser suite still 150 checks, **UNTESTED
    live, UNCOMMITTED, NOT DEPLOYED**). Found in a real game: the montage
    announced "The heroes will begin the encounter surprised" (unvanquished
    `Goblin Scouts`), combat started with the monsters first, and no hero
    had the condition.

    Cause: a SECOND initiative consequence in the same montage
    (`Gathering Darkness -> The heroes will lose initiative`) overwrote
    `doc.data.initiative`, which was the only record of the surprise. Both
    outcomes mean "the monsters go first", so the visible result looked
    right and only the condition was lost. The live document confirmed it:
    `initiative = {outcome = "lose", entryName = "Gathering Darkness"}`, with
    the surprise present only in `montage.log`.

    Fix, in two parts:
    - **Sticky flags.** `ApplyEffects` now also writes
      `doc.data.surprised.party` / `.enemy`, which no later initiative
      clause clears. `EncounterMontage.GetSurprisedSides()` reads them, and
      `StartEncounterCombat` builds `surprisedTokens` from them instead of
      from the (last-one-wins) outcome, unioning both sides if a montage
      managed both. Cleared by the montage test reset.
    - **Surprise forces the initiative.** `immediateResult` is decided from
      the outcome and then overridden by the surprised side (party ->
      monsters first, enemy -> heroes first; both sides surprised falls back
      to the outcome), so a later `you win initiative` cannot put a
      surprised party first. Holds under surprise immunity too.
    - **Immediate application** (user direction): a `surprised` clause runs
      the new file-local `SetHeroesSurprised(true, ...)` in
      `EncounterMontage.lua` on the spot, so the condition appears on the
      heroes as the montage announces it rather than when the Draw Steel
      banner resolves. Duration `eoe`, so it survives the rest of the
      montage and the narrative beat and `creature:EndCombat` clears it at
      the end of the fight. `nosurprise` earned later lifts it again, and so
      does the reset. The enemy half of `surprise` still waits for combat
      start -- those monsters do not exist during the montage.

    Test: a montage with an unvanquished threat whose consequence is
    `You begin the encounter surprised` AND a second unvanquished threat
    whose consequence is `You lose initiative`. As the first consequence is
    announced, every hero token should visibly gain Surprised; the second
    should not remove it; combat should start monsters-first with every hero
    and ally still Surprised. Then re-run with `You cannot be surprised`
    earned after the surprise -- the condition must come off again, but the
    monsters must still go first. And a third run with the second
    consequence changed to `You win initiative` -- the monsters must STILL
    go first, because the party is surprised.

48. [x] **Losing recoveries** (BUILT 2026-09-19, luac-clean, parser suite
    159 checks, the pool mechanics VERIFIED against a live hero's creature
    on a detached copy (8 -> 7 recoveries); **UNTESTED in a real montage,
    UNCOMMITTED, NOT DEPLOYED**): `You lose a recovery`,
    `You lose two recoveries`, `Each party member loses a recovery`,
    `Each party member loses two recoveries` (user request; digits work
    too, and any of `a`/`an`/`one`..`ten`).

    Effect kind `loserecovery` (`target`, `qty`) -- distinct from the
    `recovery` BOON, which raises the Recovery Value and costs nothing.
    Parsed in `ParseClause` by the shared `MatchSelfOrParty` helper against
    both the singular and plural noun, placed after the Recovery Value boon
    rules and before the generic item rule; `you lose <n> stamina` is a
    separate rule and is unaffected.

    **This is a flat cost, NOT Draw Steel's recovery spend** (user
    direction 2026-09-19, after a first pass built it as a spend): the
    recovery is gone and no Stamina comes back for it. `LoseRecoveries` in
    `EncounterMontage.lua` is therefore one
    `ConsumeResource(CharacterResource.recoveryResourceId, "long", n)` --
    which routes to a Bloodbound Band partner when the hero's own pool is
    empty -- and no `Heal`. A hero with fewer recoveries than the clause
    asks for loses what they have, and one with none left loses nothing and
    carries no debt. The applied-effects list reports what each hero
    actually lost, grouped by amount: "Every hero loses 1 Recovery", or
    "Kira and Brann lose 1 Recovery" plus "Osk has no Recoveries left to
    lose".

49. [x] **Traps: encounter setup instructions + zone reveals** (BUILT
    2026-09-19, luac-clean, parser suite 233 checks, setup / reveal / reset
    VERIFIED headlessly in the authoring game over MCP; **the live encounter
    beat and a player client's overlay UNTESTED, UNCOMMITTED, NOT
    DEPLOYED**): `Trap: Place 4 Snare Trap objects in Trap zones and delete
    other Trap zones.` under `# Encounter`, and `Reveal Traps during the next
    combat` as a montage clause. Design in "Encounter setup instructions and
    zone reveals". Files: `EncounterOfTheWeek/EncounterZones.lua` (NEW,
    registered after EncounterScript), `EncounterScript.lua`
    (`ParseSetupInstruction`, `ParseRevealZonesClause`, `beat.setup`),
    `EncounterMontage.lua` (the `revealzones` branch, reset),
    `EncounterOfTheWeek.lua` (the encounter beat's two calls, the driver's
    `EncounterZones.ClientTick`), `tests/encounter_script_test.lua`.

    Test (needs a restart to load the new file): in a real EotW game with the
    live script, let the montage run and take a test whose tier says
    `Reveal Traps during the next combat` (none in the live script yet -- add
    one), then Draw Steel: behind the dissolving stage there should be 4
    Snare Trap objects on 4 former Trap tiles, only those 4 tiles should
    still be Trap zones (`/eotwzones state`), and on EVERY client the Trap
    stripes should be visible without touching the overlay menu. Without the
    reveal, the traps go down and the zones stay hidden from players.
    `/eotwmontage reset` must remove the traps and bring back all 15 tiles.

50. [~] **Montage scenes** (BUILT 2026-09-23; parser unit-tested; VERIFIED
    live end to end on one client, multi-client UNTESTED; UNCOMMITTED). Design, grammar and status in
    "Montage scenes: the approach plays on a stage" under Architecture Notes.
    Files: `EncounterScript.lua` (`ParseCondition`, `CompileScene`,
    `FlattenScene`, `Garble`, `SubstitutePC`, the `---` / option scene
    capture), `EncounterMontage.lua` (`BuildScenePart`, `ResolveTurn` ->
    `ApplyResolution`, `FinishScenePart`, `SceneCursor` / `AdvanceScene`),
    `EncounterMontageStage.lua` (`CreateSceneStage` + its style rules),
    `tests/encounter_script_test.lua`. Next: the "still to verify" list there.

51. [~] **Delves** (BUILT 2026-09-24; parser unit-tested; runtime/stage
    UNTESTED live; the content is in the live week's document -- since the
    split, the `Forbidden Tomb Delve` sub-document; UNCOMMITTED). Design,
    grammar and status in "Delves: a dungeon crawl inside one approach".

52. [~] **Sub-documents** (BUILT 2026-09-24; parser unit-tested; the live
    week SPLIT into a 2 KB master + 16 linked sub-documents and VERIFIED to
    parse identically over MCP; a played montage on it UNTESTED;
    UNCOMMITTED). A line that is only a link (or embed) to another journal
    document splices that document in. Design, the split and status in
    "Splitting a script across documents" under Architecture Notes.

Deliverable: the week's document is a script; a montage plays before the
fight with every player dragging their heroes onto opportunities and
threats, rolling in front of everyone, and its outcomes (items, stamina,
healing, temporary stamina, Recovery Value, lost recoveries, surges, hero
tokens, malice, allied monsters, revealed traps, unresolved-threat
consequences) carrying into the combat, and the encounter's own setup
(traps placed in their zones) running as the fight begins.

## Phase 8 -- Narrative beats (BUILT 2026-09-18; VERIFIED in the authoring game; real EotW game UNTESTED)

Design in "Narrative beats" under Architecture Notes. All Lua in the EotW
codemod; one new top-level file registered through the MCP CodeMod workflow
(`EncounterNarrative.lua`, ordered after `EncounterMontage`); no engine and
no core change.

40. [x] **Parser** (BUILT + unit-tested 2026-09-18): the `# Narrative` beat
    in `EncounterScript.lua` -- sections, per-section scenes, the
    together/individual marker with its loose spellings, options with `|`
    rules-text lines, the implicit `Proceed`, the "no marker" warning, plus
    `NarrativeSections` / `FindSection` / `SectionCount`, narrative names in
    `ReferencedNames` and narrative beats in `Describe`. Tests in
    `tests/encounter_script_test.lua` (150 checks, up from 101).
41. [x] **Runtime** (BUILT + VERIFIED 2026-09-18):
    `EncounterOfTheWeek/EncounterNarrative.lua` -- the `narrative` state
    key, voters per mode, the request/validate/apply loop, the
    agreed/individual resolution split, the random decision and its flash
    window, section progression, `ForceResolve`, the `/eotwnarrative` dev
    command and dev driver. Plus, in `EncounterMontage.lua`,
    `ctx.heroEntries` + `ctx.source` + the multi-target `ally` branch in
    `ApplyEffects`, the exported `RecordAlly`, and `narrative` in the
    reset.
42. [x] **Stage** (BUILT + VERIFIED 2026-09-18): `CreateNarrativeStage` in
    `EncounterMontageStage.lua` behind `StageFor`, sharing the factored
    `CreateBackdrop` / `CreateDim` / `CreatePoolsPanel`; option cards as
    buttons and drop targets, the hero row with its choice line and "?"
    badge, the split-decision flash (`FlashCandidateIndex`), and the
    narrative style rules.
43. [x] **Beat machine** (BUILT 2026-09-18; the real-game path UNTESTED):
    `RunScriptBeat` runs a narrative beat and advances past it (and skips
    it with a warning on a client whose module has no narrative runtime);
    `MontageStageExpected` and `BeginOpeningMontage` cover both beat kinds,
    so a week that opens on a narrative is what the held loading screen
    reveals.
44. [ ] **Live test in a real EotW game**: two clients, an agreed section
    with a genuine disagreement (the flash over real players), an
    individual section with each player dragging their own heroes, a
    narrative before AND after a montage, and an item/ally clause on a
    narrative option.
45. [ ] **Publisher validation**: fold the narrative checks into the Python
    port alongside the montage's (step 35) -- unknown marker, option
    without rules text where one was clearly meant, unresolvable item or
    monster name, a section with no options and no text.

---

# Open Questions

- ~~**EotW games in the CAMPAIGNS list**~~ RESOLVED (2026-08-27): a dedicated
  `accountInfo.eotwGame` slot (one game per account, never in `games`), with
  entering a new game destroying the previous one -- DO released -- and a resume
  row on the EotW screen. See "One EotW game per account" in Architecture Notes.
- **Monster AI rolls are not shown to the other players** (DIAGNOSED +
  FIXED in Lua 2026-09-15; UNTESTED with a second client, not yet deployed). The host sees the AI's ability card + roll dialog
  (`AbilitySidebar` `abilityDisplay`, built by `AcquireAbilityRollDialog` from
  `MCDMAbilityRollBehavior:Cast`), but nothing reaches the players' remote
  display. Not a player-host problem: the same happens under a normal Director
  running the Monster AI. Cause: remote display is driven by the ability-share
  document, and sharing only ever BEGINS in `CharacterPanel.HighlightAbilitySection`
  when it is passed a `caster` -- the only callers that pass one are the action
  bar's targeting paths (`DrawSteelActionBar.lua`, four sites). The cast
  pipeline's own calls (`ActivatedAbility.CastCoroutine`, sections "main" /
  "effects") pass no caster, so for an AI cast -- which never goes through the
  targeting UI -- `g_sharingData` stays nil, `BeginAbilitySharing` never runs,
  and the roll dialog's `UpdateAbilitySharing` writes are all no-ops.
  Fix (Lua only, `Timeline/AbilitySidebar.lua`): `AcquireAbilityRollDialog`
  begins sharing itself for AI-driven casts -- right after `DisplayAbility`
  has set `g_displayedAbility`, when `casterToken.properties._tmp_aicontrol > 0`,
  `IsDMOrPlayerHost()`, `privaterolls ~= "dm"` and the caster is on the current
  turn (same clobber guard as player sharing). `BeginAbilitySharing` took an
  optional `section` argument so the share lands as "main" in one write. Gated
  on `_tmp_aicontrol` + `IsDMOrPlayerHost()` rather than `token.canControl`:
  `canControl` is elevation-aware and the cast coroutine
  (`dmhub.Coroutine(CastCoroutine)`) does not inherit the AI turn's host
  elevation past its first yield. The existing hide path clears the share.
  Not done here: the pre-behavior `HighlightAbilitySection` calls in
  `ActivatedAbility.CastCoroutine` still pass no caster (they fire before the
  card exists), so AI casts with no power roll still do not share.
- **Observers**: the spec says games can be observed. Join as a player with zero hero slots, or a true spectator mechanism? Affects permissions and the players list.
- ~~**Weekly rotation**~~ RESOLVED (2026-08-30): the module id stays stable
  (`mcdm-encounteroftheweek`, version bumps) and publishing is automated by
  `tools/eotw_publish/publish_eotw.py` -- see "Publishing the weekly module
  headlessly" in Architecture Notes. The weekly authoring job is now: build
  the new map, name it `Encounter` (renaming last week's out of the way),
  file its encounter document under it, and run the script.
- **Does the player host see the monsters it runs?** (RAISED 2026-08-30)
  `CharacterToken.CalculateCanSee` short-circuits to visible on `canControl`,
  which on a player host is every token -- so the host sees every monster on
  the map through fog and walls, while the map around them stays dark. The
  Monster AI does not need it (it is data-driven), and a plain player would
  see nothing, so converting it to `canControlAsUser` would close the X-ray.
  Against: the host is the only person who can notice and intervene when the
  AI wedges a monster somewhere, and they would be doing it blind. Not
  changed pending a decision.
- **Player host sees every monster's stamina bar; joiners see none** (FOUND
  2026-09-06 in a live two-client test; same `canControl` family as the X-ray
  above, UNFIXED). `TokenUI.lua` `ShouldShowElement` walks the status-bar
  audiences in order and the second rung is `showToController` gated on
  `token.canControl` -- the hosting-capability grant, true for every monster
  on the player host. So the host takes the "controlling player" branch
  (`hpbarforownplayer`, default on) and gets the bar with the raw value
  (`showAs = "val"` is only overridden for `dmhub.isDM == false` clients via
  `enemystambardisplay`, whose default is `"none"`). A joiner reaches the
  `showToEnemies` rung, which the `"none"` default turns off, so they see
  nothing. Two independent things to decide: (1) convert that
  `showToController` rung (and the minion squad-health readers in
  `MCDMMinion.lua` that also test control) to `token.canControlAsUser` so the
  host presents as a player; (2) what EotW players should see at all --
  `enemystambardisplay` is a Director-only game setting defaulting to
  `"none"`, so if the answer is "bar only" the host's setup needs to write
  it into the game record when it stamps the eotw marker.
  **DONE 2026-09-06 (engine NEEDS BUILD, UNTESTED): `canControl` is now
  elevation-aware.** User direction: `token.canControl` should be FALSE for
  monsters on the player host. `CharacterInfo.canControl` now reads `isDM`
  (true inside the Monster AI's `PushHostPermissions` coroutines, false for
  the user's un-elevated UI) instead of `isDMOrPlayerHost`, so it equals
  `canControlAsUser` except under elevation and is bit-identical in every
  game that is not directorless. This closes the whole presentation family
  at once -- the stamina bar, `hiddenFromEnemies` status effects, private
  names, the raw `showAs` value, monster languages, Character Sheet / Copy
  Token context entries, mouseover highlight, roof vision, the
  `CalculateCanSee` X-ray (the host now sees monsters like a player) and the
  minion squad HUD -- with no codex edits. New engine read
  `CharacterInfo.canControlAsHost` / `CharacterToken.canControlAsHost` (the
  old capability body, C# only, not bound to Lua) for host-MACHINE work that
  runs un-elevated: `CharacterToken.shouldSendRealtimeUpdates` (attack
  animations / targeting for AI-driven monsters) and the summoned-token
  relocation fixup in `GameController` Update. `activeControllerId` prompt
  routing already tested `isDMOrPlayerHost` first and is unchanged.
  Sweep of every Lua `canControl` read (about 60 sites): all but four are
  presentation or user-driven and now behave as the user intended. The
  four machine-responsibility reads: (1) EotW's own pending-prompt busy gate
  (`EncounterOfTheWeek.lua` `AbilityActivityInFlight`) now runs its token
  loop under `ElevateToHostPermissions` so monster prompts the AI is still
  answering keep deferring the victory award; (2) `ActiveTrigger.RefreshAllTimers`
  (`Creature.lua`) no longer re-stamps monster trigger prompts from the host
  -- accepted, the AI answers them promptly and hostile ones never expire;
  (3) the roll-request prompt predicates (`DSRequestRollsDialog.lua`,
  `RequireDCDialog.lua`) no longer prompt the host's user for a MONSTER's
  requested roll (the `playerControlled == false` arm is dead on a player
  host). Nothing in EotW requests rolls from monsters (heroic tests and
  negotiation target heroes; Require Roll is Director UI), and the old
  behavior was Director UI on a player, so left as is -- if an ability ever
  requests a monster roll in EotW it would now stall; (4)
  `creature:RefreshInitiativeGrouping` (`MCDMCreature.lua`) is a local
  grouping HUD, presentation. `Monster AI/` reads `canControl` nowhere, and
  the ability pipeline (`ActivatedAbility.lua`, `MCDMAbilityBehavior.lua`,
  Timeline) reads it only in right-click menus, so the un-elevated
  continuation risk reduces to the already-live `isDM` case, which the AI
  has been running under since 2026-08-29. Stub updated in
  `Definitions/CharacterToken.lua`; `TokenControlledByUser` in `Utils.lua`
  kept for the old-engine fallback and the inside-elevation distinction.
  ~~Remaining decision: what EotW PLAYERS should see of monster stamina
  (`enemystambardisplay`, default `"none"`, Director-only game setting --
  the host's setup would have to write it when it stamps the eotw marker).~~
  DECIDED + BUILT 2026-09-07 (UNTESTED): players always see the monsters'
  stamina BARS but not the amounts -- the host forces
  `enemystambardisplay = "bar"` and `hpbarsonlyincombat = false` via
  `g_forcedGameSettings`; see "Players always see monster stamina bars, not
  amounts" under "Strict rules enforcement". Monster Info is forced on the
  same way ("Monster Info is always on").
  Verify after the build: `/testai` in an EotW game, an AI summon into an
  occupied space, and a monster attack animation seen from a second client.
- **Kick UX**: engine `KickPlayer` does not notify/disconnect the kicked client. Acceptable for v1, or add a watched-document notification?
- **Unlisted module access for non-owners**: the module record has `published: false` /
  `dmhubCanUse: false` (unlisted). The owner can `DownloadModuleSnapshot` it and create
  games from it, but it is unverified whether a NON-owner account can (a) fetch the pregen
  snapshot at the titlescreen and (b) have `lobby:CreateGame{startingModule}` install it.
  Verify with a second account before opening EotW beyond the dev machine; may need the
  module marked published/unlisted-but-usable.
- **Remote-player hero portraits**: another player's lobby-hero card shows a
  silhouette because portrait assets are per-game cloud assets and cannot
  resolve on other machines. If real portraits are wanted later, the client
  would have to publish a small portrait blob somewhere globally fetchable
  (e.g. the R2 disposable-chat-image pattern) and the hero record carry its id.
  Accepted for v1.
- **Pregen hero representation**: DECIDED (2026-08-27) -- module characters in the
  mcdm-encounteroftheweek module's version snapshot, browsed pre-install via the
  new `module.DownloadModuleSnapshot` engine API (see "Pregen heroes from the
  module"). Phase 5 still has to author them (stat source: companion-app pregen
  JSON). ~~Open sub-question: whether pregen portraits render at the titlescreen
  without the module's streamed assets loaded.~~ RESOLVED (2026-08-28): they did
  NOT render; engine-side images-only registration fix built (NEEDS BUILD) plus
  a Lua silhouette stopgap -- see "Pregen portraits at the titlescreen" under
  "Pregen heroes from the module".

- **Montage rules the sample script leaves open** (RAISED 2026-09-18 while
  planning Phase 7; the user confirmed every default below on 2026-09-18
  except the round rule, which changed -- see its entry):
  - *Is an opportunity consumed after one approach?* Default: yes -- one
    hero takes it, whatever the roll, and it greys out. A threat stays
    until a tier says it is vanquished, so several heroes may try it.
  - ~~*Do entries belong to the round they are listed under?*~~ DECIDED
    2026-09-18 (user): both opportunities and threats persist round to
    round; a round heading only introduces entries. Unvanquished threats
    still standing at the end all deliver their consequence.
  - *May two heroes act at once?* Default: no -- turns are serialized so
    every client watches the same roll. Each hero acts once per round;
    the round ends when every hero on the map has acted.
  - *Who advances the end-of-montage consequence reveals?* Default:
    anyone (like Proceed on the victory screen).
  - *A hero whose owner has left the game* blocks the round forever.
    Default for v1: nothing; a host-visible "skip hero" control is the
    likely follow-up.
  - *Where does an ally spawn?* Default: the free Start-zone tile nearest
    its hero. It lives for the rest of the game; when it dies it is just
    gone (the Hero Death rule is heroes-only).
  - *`Options:` text* is shown once a hero approaches, above the option
    list; it is not on the card.

---

# Status

- 2026-09-24 (sub-documents, latest): **A script can be spread over several
  journal documents: a line that is nothing but a link (`[label](document:Name)`),
  a page embed (`[:Name]`) or the `[Name]` shorthand is replaced by that
  document's text before parsing, recursively, preferring a document filed
  under the same map. The live week is now a 1,978-byte master `Encounter`
  (the beat skeleton, every rich tag, the round directives) linking 16
  sub-documents in the map's journal folder -- one per montage entry plus
  `Forbidden Tomb Delve`. BUILT; parser unit-tested (448 checks, up from
  429); VERIFIED over MCP that the split parses identically to the old
  single document and that the runtime picks the master, not a part.
  UNCOMMITTED, not deployed; a montage PLAYED on the split document is
  UNTESTED.** Also fixed on the way: `SceneImage` read the first `[[scene]]`
  for every beat instead of the journal's `scene-1`/`scene-2` keys (harmless
  so far -- one image). Design + file list under "Splitting a script across
  documents". The EotW publisher's dry run currently fails on an unrelated
  U+008A character in `C:\dev\eotw\...\actions-in-combat.yaml`; fix that
  before the next publish.

- 2026-09-20 (Intelligence + Tactical Preparation): **A narrative
  beat can write `Unlock: Intelligence` to turn the feature on; a montage or
  narrative outcome can pay `+1 Intelligence` into a party-shared pool shown
  beside Malice and Hero Tokens (`phosphor/brain.png`); and at the outset of
  the encounter the party spends it on a Tactical Preparation screen -- three
  bars (Surprise, Traps, Enemy Stamina), 1 Intelligence a notch, any player
  may spend, Proceed offered once the pool is empty and taken when every
  player has pressed it. The unlock explains itself on the spot: a callout
  under the section's text ("Intelligence is an important currency! ...")
  while a white rectangle blinks round the pool in the strip, until the
  party presses on. BUILT; parser unit-tested (370 checks, up from 346);
  VERIFIED live in an EotW game through the real host tick, short of the
  spawn. UNCOMMITTED, and NOT deployed to the cloud mod.** Design under
  "Optional features" and "Intelligence and Tactical Preparation", which also
  lists what is still to verify (two clients; the trap reveal actually
  landing; the `val` stamina bar; the beat running on into combat). Files:
  `EncounterOfTheWeek/EncounterPrep.lua` (NEW -- registered in the CodeMod
  via the MCP workflow, before `EncounterMontageStage`; Firebase persistence
  confirmed), `EncounterScript.lua`, `EncounterMontage.lua`,
  `EncounterNarrative.lua`, `EncounterMontageStage.lua`,
  `EncounterOfTheWeekHud.lua`, `EncounterScriptValidator.lua`,
  `EncounterOfTheWeek.lua`, `tests/encounter_script_test.lua`.
  **Note for the next session: registering a new file in the CodeMod needs an
  app RESTART -- `reload_lua` re-runs what the app already read and does not
  re-read the mod from the git folder after the file list changes. And never
  `dofile` these files into the running app: `dmhub.GetModLoading()` returns
  nil outside a real mod load, so every `mod:GetDocumentSnapshot` in the
  freshly loaded chunk dies and the EotW runtime is broken until a restart.**
  **The week's own document does not use any of this yet** -- no
  `Unlock: Intelligence` line and no `+N Intelligence` outcome has been
  written into it, so the live week plays exactly as it did before.

- 2026-09-20 (script validator): **A dev-only "Encounter Script"
  dockable panel (Panels > Development Tools, or `/eotwvalidate`) reads a
  week's journal document through the runtime parser and reports it:
  beats, rounds, entries with their tags, every tier line with the
  recognized clauses lit green and the plain-English effect under it,
  plus problems, text-only clauses and the item/monster/object/zone name
  lookups. VERIFIED live in the authoring game against the real week
  document. UNCOMMITTED.** It re-implements no rule -- highlighting is
  `MarkupRules`, effect lines are `DescribeEffect`, lookups are the
  runtime's own -- and adds the checks the pure parser cannot: the four
  name lookups, and `ParseAttr` on each roll to catch a characteristic
  that matched nothing or a non-skill in the parentheses. Design under
  "The script validator panel". Files:
  `EncounterOfTheWeek/EncounterScriptValidator.lua` (NEW -- registered in
  the CodeMod via the MCP workflow, after `EncounterZones`; Firebase
  persistence confirmed). **Its first run found two real bugs in the live
  week document: line 117 is a `|` line that is not a power roll header,
  and line 125 is `## Befriend Them` where it should be `### Befriend
  Them`, so that option is being dropped.**

- 2026-09-20 (temporary entries): **An opportunity or threat can
  be marked `(Temporary)`: it is gone at the end of the round it appeared
  in, and a temporary threat that was not vanquished pays its consequence
  there and then rather than at the end of the montage. BUILT code-only;
  parser unit-tested (342 checks, up from 332); runtime UNTESTED live.
  UNCOMMITTED.** The card says so ("Gone at the end of this round -- deal
  with it or face the consequence"), since a deadline the party cannot see
  is not a deadline, and the stage opens the next round by reading out
  whatever expired. A `(Locked, Temporary)` entry expires at the end of
  the round its unlock landed in, not the round that declares it, so
  `montage.unlocked` now records the round. Design under "Temporary
  entries". Files: `EncounterOfTheWeek/EncounterScript.lua`
  (`entry.temporary`, the heading tags reworked into a recognized-word
  set), `EncounterOfTheWeek/EncounterMontage.lua` (`montage.expired`,
  `EntryAppearRound`, `EntryExpired`, `ExpireTemporaryEntries`,
  `DescribeTemporary`), `EncounterOfTheWeek/EncounterMontageStage.lua`
  (the deadline line, `RetireDoneEntries`, the expired-consequence
  read-out), `tests/encounter_script_test.lua` (10 new checks).

- 2026-09-20 (a fair roll for initiative): **A montage outcome can
  now take back an unfavourable initiative decision without handing the
  party a favourable one: `The encounter begins with a fair roll` drops the
  party's Surprised condition and a `lose`/`surprised` outcome, leaves an
  already-surprised enemy and a `win` alone, and otherwise lets combat roll
  for it. BUILT code-only; parser unit-tested (332 checks, up from 313);
  runtime UNTESTED live. UNCOMMITTED.** It is distinct from
  `you cannot be surprised`, which withholds the condition but still loses
  the initiative, and it is not sticky. Design under "Taking an
  unfavourable initiative back". Files:
  `EncounterOfTheWeek/EncounterScript.lua` (the `fairinitiative` effect
  kind, `ParseFairInitiativeClause` -- matched BEFORE the surprise-immunity
  and initiative clauses, whose `^you .*surprised$` rules would otherwise
  read "you are no longer surprised" as its own opposite --
  `DescribeFairInitiative`), `EncounterOfTheWeek/EncounterMontage.lua` (the
  `fairinitiative` branch of `ApplyEffects` and the new
  `data.initiative.outcome == "even"`), `tests/encounter_script_test.lua`
  (19 new checks). `EncounterOfTheWeek.lua` needed no change: an outcome it
  does not recognize already leaves `immediateResult` nil.

- 2026-09-20 (standing edges and banes): **A power roll outcome
  can now put an edge or bane on another test of the montage by name --
  `{Edge on Capture Them}` -- and it applies to whoever takes that test,
  not just to the hero who earned it. `Double Edge`, `Bane` and `Double
  Bane` too. BUILT code-only; the parser is unit-tested (313 checks, up
  from 289); the runtime is UNTESTED live. UNCOMMITTED.** Unlike a
  `|Edge:` rider it is weighed against nobody; the two stack, and the
  grants become ordinary pre-ticked chips in the roll dialog via
  `RiderVerdict`, which now folds them in as applied riders. Targets are
  `### option` names matched with `EncounterScript.MatchKey`; the parser
  warns when one matches nothing. Design under "Standing edges and banes".
  Files: `EncounterOfTheWeek/EncounterScript.lua` (`testmod` effect kind,
  `ParseTestModClause` matched first in `ParseClause`, `DescribeTestMod`,
  the option-name check; `EntryKey` was renamed `MatchKey` now that both
  entry and option names go through it),
  `EncounterOfTheWeek/EncounterMontage.lua` (`montage.testmods`, the
  `testmod` branch of `ApplyEffects`, `OptionTestMods`, `RiderVerdict`,
  `DescribeTestMods`), `EncounterOfTheWeek/EncounterMontageStage.lua`
  (`GrantedRows`), `tests/encounter_script_test.lua` (24 new checks).

- 2026-09-20 (locked entries + hidden clauses): **An opportunity
  or threat can be declared `(Locked)` and stays off the board until an
  `Unlock <name>` outcome lets it on, and any part of a tier or
  `Consequence:` line wrapped in `{...}` is applied but never shown.
  BUILT code-only; the parser is unit-tested with the bundled interpreter
  (289 checks, up from 260); the runtime is UNTESTED live -- the app was
  only taken as far as the title screen this session, where the EotW
  codemod is not loaded, so nothing of this has run in a game.
  UNCOMMITTED.** `## Opportunity: Interrogate the Goblin (Locked)` is
  never shown, never approachable, and (for a threat) delivers no
  consequence; `{Unlock Interrogate the Goblin}` on some other entry's
  tier applies silently and the card appears at once if its round has been
  reached, or when that round comes. Names are matched loosely
  (`EncounterScript.MatchKey`: case, spacing, a leading "the" and trailing
  punctuation all ignored), the unlocks live in the per-beat montage state
  so `/eotwmontage reset` re-locks everything, locked entries are out of
  the party-size draw, and the parser warns both ways (an unlock that
  names no locked entry; a locked entry nothing unlocks). Because a hidden
  unlock leaves no player-visible trace, every unlock is `printf`d and
  `/eotwmontage state` prints `EncounterMontage.DescribeLocks`. Design
  under "Locked entries and Unlock <name>" and, for the braces, "Hidden
  clauses" inside the effect-clause grammar.
  Files: `EncounterOfTheWeek/EncounterScript.lua` (`entry.locked` and the
  multi-tag heading parse, `MatchKey`, `ParseUnlockClause`,
  `DescribeUnlock`, the `unlock` effect kind, `HiddenRanges` /
  `VisibleText` / the hidden-aware `SplitClauseSpans` /
  `effect.hidden`, `TierDisplayText` and `MarkupRules` routed through
  `VisibleText`, the two post-parse warnings, `(locked)` in the
  `/eotwscript` dump, `ChooseRemovedEntries` skipping locked entries),
  `EncounterOfTheWeek/EncounterMontage.lua` (`montage.unlocked`,
  `EntryUnlocked`, the `unlock` branch and the hidden-effect suppression
  in `ApplyEffects`, the consequence-list filter, `DescribeLocks` +
  `/eotwmontage state`, `t.tierText` recorded as visible text),
  `EncounterOfTheWeek/EncounterMontageStage.lua` (`SyncEntries` brings
  newly unlocked cards in without waiting for the round to turn; the
  consequence card's text goes through `VisibleText`),
  `tests/encounter_script_test.lua` (29 new checks).
  **To test:** in the authoring game, add a `(Locked)` entry and a
  `{Unlock <it>}` outcome to the week's document, `/eotwmontage reset`,
  `/eotwscript` (the dump should mark it `(locked)` and raise no
  warnings), then `/eotwmontage start` and take the unlocking option --
  the card should appear mid-round with the usual materialize ramp, and
  the tier row and log should never show the braces or the unlock line.

- 2026-09-20 (party-size scaling): **A montage round can now trim
  itself for a small party, and an entry can opt out of being trimmed.
  BUILT code-only; the parser is unit-tested with the bundled interpreter
  (260 checks, up from 233); the runtime is UNTESTED live -- the running
  game's Lua watcher was dead (EncounterScript.lua was last read at app
  startup), so a restart is needed before any of it can be seen.** A line
  directly under a round heading, `3-5 Players: -1 Opportunity, -1 Threat`,
  drops that many of each kind at random from the entries THAT round
  introduces, once, when the party has arrived; `## Opportunity: Hunter's
  Camp (Required)` is never drawn and the tag never displays. A removed
  entry is invisible rather than announced: no card, no approach, no
  consequence, no message -- but every draw is logged in full to the
  Director's console (directives, what fired, each entry removed by name)
  and `/eotwmontage state` reprints it from the document. Design under "Scaling a montage to the party".
  Files: `EncounterOfTheWeek/EncounterScript.lua` (`round.scaling`,
  `entry.required`, `ParseScalingDirective`, `IsScalingDirectiveLine`,
  `ScalingRemovals`, `HasScaling`, `RoundHasScaling`,
  `ChooseRemovedEntries`, the overdraw warning, the `/eotwscript` dump),
  `EncounterOfTheWeek/EncounterMontage.lua` (`RollRemovals` and its
  logging, `m.removedForPartySize`, `EntryRemoved`, `EntryHidden`,
  `DescribeRemovals` + the `/eotwmontage state` dump, the `EntryAvailable`
  gate, the consequence-list filter), `EncounterOfTheWeek/EncounterMontageStage.lua`
  (`AddEntriesForRound` / `SyncEntries` withhold a scaled round's cards
  until the draw lands), `tests/encounter_script_test.lua` (27 new checks).

- 2026-09-19 (traps): **Trap zones + Snare Trap placement + "Reveal
  Traps" montage outcome. BUILT code-only; parser unit-tested (233 checks);
  setup / reveal / reset VERIFIED headlessly in the authoring game over MCP
  (the new file `dofile`d in, the map restored afterwards); the encounter
  beat itself and a joiner's overlay UNTESTED (needs a restart to load the
  NEW registered file `EncounterOfTheWeek/EncounterZones.lua`).** The
  `# Encounter` section now takes `Label: Place <n> <Object> objects in
  <Zone> zones [and delete other <Zone> zones]` lines (the live document
  already has the Trap one), run by the host before the spawn; the montage
  clause `Reveal Traps during the next combat` makes the surviving Trap
  zones player-visible and switches every client's zone overlay on for that
  type. Design under "Encounter setup instructions and zone reveals"; plan
  step 49. Note for the parser: object assets are matched by their
  `description` (their display name) -- `ObjectNodeLua` has no `name`.

- 2026-09-19 (rules highlighting): **The montage tier text now
  colours the clauses the effect grammar recognized, so a player can see
  which words are rules and which are flavour. BUILT code-only; parser
  unit-tested; UNTESTED live (the running game is serving the deployed
  codemod, so it needs a deploy or a restart to see).** The clause
  splitter now keeps byte offsets (`SplitClauseSpans`,
  `EncounterScript.ParseEffectSpans`, `EffectIsMechanical`,
  `EncounterScript.MarkupRules`) and the stage's `TierText` wraps the
  recognized spans in `<color>` tags for every row showing full text.
  Design under "Montage grammar" (the effect-clauses bullet) and "The
  stage (UI)" (the recognized-rules bullet). Files:
  `EncounterOfTheWeek/EncounterScript.lua`,
  `EncounterOfTheWeek/EncounterMontageStage.lua` (`TierText`,
  `RULES_COLOR`, `TierRows`, `SetLandedTier`),
  `tests/encounter_script_test.lua` (8 new checks; 195 pass).

- 2026-09-19 (the cut to combat, latest): **The stage now dissolves away to
  reveal the battlefield instead of hanging over it. BUILT code-only, NOT
  run.** User report: after the last narrative section the Draw Steel banner
  played but the narrative UI and scene stayed on screen. The staying-up half
  was the duplicate-stage bug from round three (their session predated that
  fix; `HidePresentedDialog` only destroys the one panel GameHud still tracks,
  so the orphans remained). The requested half is new: the encounter beat now
  spawns its monsters BEHIND the stage, then `EncounterMontage.DismissStage`
  stamps a shared clock and every client plays `dmhub.StartScreenTransition`
  -- the engine dissolve the titlescreen uses -- hiding the stage under the
  snapshot and thinning it away to reveal the finished battlefield; Draw Steel
  only rolls once the stage is really gone, bounded by a 4s timeout so a stuck
  surface cannot wedge the fight. Design under "The stage dissolves away to
  reveal the fight". Files: `EncounterOfTheWeek/EncounterMontage.lua`
  (`DismissStage`, `DismissAt`, `ClearDismiss`, `STAGE_DISMISS_SECONDS`),
  `EncounterOfTheWeek/EncounterOfTheWeek.lua` (the beat machine stops hiding;
  the encounter beat dismisses then fights),
  `EncounterOfTheWeek/EncounterMontageStage.lua` (`FadeOutScreenTransition`,
  `Dismiss`), `EncounterOfTheWeek/EncounterNarrative.lua` (Begin clears the
  stamp).

- 2026-09-19 (the flicker, round three, latest): **The background no longer
  reloads between beats: the presenting client was stacking a second stage on
  top of the first. FIXED code-only, NOT run.** `GameHud.presentDialog` forgets
  the mounted panel without destroying it, so presenting a dialog that is
  already presented builds a duplicate -- and `Begin` presented unconditionally
  at every handover. `EncounterMontage.Present` now returns early when the
  stage is already up (which also stops the orphans that would have left the
  action bar hidden into combat); `AdvanceFromStageBeat` seeds the next beat's
  state before stamping the beat index, so no refresh renders the new body over
  the old beat's state; and the scene only follows a narrative section while
  that section's beat is the one being drawn. Files:
  `EncounterOfTheWeek/EncounterMontage.lua`,
  `EncounterOfTheWeek/EncounterOfTheWeek.lua`,
  `EncounterOfTheWeek/EncounterMontageStage.lua`. Design under "Stage beats
  hand over without showing the map", round three. Needs a restart to load,
  then the montage -> narrative cut should not touch the backdrop at all.

- 2026-09-19 (seamless beat cuts, round two, latest): **The pause and the
  flicker between a narrative and a montage are both fixed. Mounted stage
  VERIFIED live; the cut itself still to be seen.** User report: playing solo,
  a long wait after pressing the option and then a full-screen flicker on the
  way to the montage. The wait was 5s + 4s of lingers on a section that applied
  nothing (now 0.4s + 0.3s, and 4s only when something actually landed); the
  flicker was GameHud tearing down and rebuilding the presented dialog because
  its args carried the beat index. The presented args are constant now and a
  single mounted `CreateScriptStage` owns the shared chrome with the montage or
  narrative body swapped inside it. Also fixed: a restart taken mid-roll wedged
  the montage turn in "rolling" forever (`GameHud.instance` is `false` during
  load and indexing it raised, eating the retry). Files:
  `EncounterOfTheWeek/EncounterNarrative.lua` (`m.resolvedLinger`,
  `RESOLVED_LINGER_QUIET`, `DONE_LINGER_SECONDS` 4 -> 0.3),
  `EncounterOfTheWeek/EncounterMontage.lua` (constant present args, the
  `ShowRollDialog` hud guard), `EncounterOfTheWeek/EncounterMontageStage.lua`
  (`CreateScriptStage`, `args.embedded` on both bodies). Design under
  "Stage beats hand over without showing the map".

- 2026-09-19 (latest): **Montage entry cards now come and go with the rounds:
  a later round's entries are no longer shown ahead of time, and what the
  party dealt with fades away when the round ends. BUILT; luac-clean;
  UNTESTED live.** User report: the columns showed every entry of the beat
  from the start, the future ones greyed out under "Appears in round 2".
  They now materialize on their own round (staggered) and leaving cards fade
  out and are destroyed before the new arrivals ramp in. Design under "The
  stage (UI)", the "columns hold only what is in play" bullet. File:
  `EncounterOfTheWeek/EncounterMontageStage.lua` (`CreateEntryCard`'s
  `appearIn` / `leave` / `gone`, and `SyncEntries` / `AddEntriesForRound` /
  `RetireDoneEntries` / `ClearEntries` in `CreateStage`, replacing the
  build-everything-once `BuildEntries`). **Not seen running**: the live app
  (`ConnectedJaggedPerfectWarden`, mid-montage on beat 2 round 1) refused to
  pick the edit up -- `code.GetMod("cdc19d98-...")`'s `localContents` for
  `EncounterMontageStage` stayed at the pre-edit bytes through a reload, the
  known stale-watcher trap, so a restart is needed to see it. Worth watching
  for on that first run: the stagger and fade times (0.15 / 0.5 / 0.5 s) and
  whether waiting out the fade before the new round's cards appear reads as
  deliberate or slow.

- 2026-09-19: **Montage <-> narrative beats now cut straight to each
  other; the map no longer flashes between them. FOUND + FIXED; UNTESTED
  live.** User report: after a narrative section the montage came up only
  after a moment of bare map. The beat machine hid the stage and let the next
  beat present itself a tick later; it now hands over under the same dialog
  id without ever taking the stage down, and the action-bar hide is ref
  counted so the bar neither blinks through the cut nor sticks hidden after
  it. Design under "Stage beats hand over without showing the map". Files:
  `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`AdvanceFromStageBeat`),
  `EncounterOfTheWeek/EncounterMontageStage.lua` (the ref-counted
  `AcquireActionBarHide` / `ReleaseActionBarHide`). The live EotW game
  (`ConnectedJaggedPerfectWarden`) reloaded the fix on a restart taken
  mid-montage and came straight back onto its stage, so the next
  montage -> narrative handover in that session is the live test.

- 2026-09-19 (module content audit, latest): **Audited what compendium content
  the weekly module must carry for the script beats; nothing is missing today,
  but a silent hole was identified.** Recorded as "Compendium content the script
  needs" under Module + codemod bundling. Nothing was added to the module or the
  codex for montage effects beyond two things already noted elsewhere: the
  Recovery Value ongoing effect is manufactured at run time in the game's own
  table rather than shipped, and the initiative clauses depend on the core
  `Encounter.StartCombatWithTokens{immediateResult, surprisedTokens}` hook (core
  codex, still uncommitted -- no week may use those clauses until it ships).
  Every other effect (Surprised, temporary Stamina, surges, hero tokens, malice)
  is core rules content. The hole: item and monster clauses resolve by NAME
  against `tbl_Gear` / `assets.monsters` at run time, and those names are prose
  in a journal document, invisible to `ModuleDependencySearcher` -- so custom
  gear or a custom monster named by a week must be ticked by hand in ModShare or
  it silently grants nothing, with no publish-time warning. The live script only
  names `Healing Potion` and `Wode Elf Sentry`, both core data-module content,
  so no ticking is needed for this week. Phase 7 step 35 (publisher validation)
  remains the fix; the publisher has no montage awareness at all today.

- 2026-09-19 (local-assets path normalization): **Trailing-separator
  bug in the local-assets directory list FIXED (engine NEEDS BUILD,
  UNTESTED).** Raised while writing the setup instructions for another
  developer. In the directory list, `\` and `/` are interchangeable and
  nothing is escaped (the setting holds the raw string; the preference's
  JSON encoding is the encoder's business) -- but a path typed as
  `C:\dev\eotw\` was silently inert. `Path.GetFullPath` preserves a
  trailing separator (verified against .NET), so the root normalized to
  `c:/dev/eotw/`, and every containment test in the feature is
  `norm == root || norm.StartsWith(root + "/")` -- which then compares
  against `c:/dev/eotw//` and matches nothing, attributing no file to that
  root: `DirIndexForPath`, the duplicate/nesting check in
  `ReadConfiguredDirs`, the `MoveItemFile` guard, and `GitStatusService`,
  which keys its per-directory cache on the same function. Fixed in
  `LocalAssetDirectory.NormalizePath` rather than at the roots, so all
  callers are corrected at once and a directory keys identically whether or
  not it was typed with a trailing slash; the trim stops at length 1, so the
  unix root `/` survives and a drive root becomes `c:`, self-consistently,
  since roots and the files beneath them share the function. Recipe and
  path-syntax rules are in "Handing this to another developer".

- 2026-09-19 (the montage intro as standing context): **The prose
  under `# Montage` now reads as the party's context line for the whole
  beat. BUILT + VERIFIED on screen in the authoring game; UNCOMMITTED.**
  User direction: if the document has text right below the montage, use it
  as text showing at the top throughout the montage, to give the players
  context. The plumbing already existed -- the parser has always made that
  paragraph `beat.intro` and the stage has always shown it in the header --
  but at 16pt grey it read as a caption, and a header pinned at
  `HEADER_HEIGHT = 76` had no room for more than the one line it happened to
  hold, so anything longer would have run into the entry columns. Changed in
  `EncounterOfTheWeek/EncounterMontageStage.lua`: a new `eotwMontageIntro`
  style (19pt italic `#efe4cc`, `maxWidth` 1000, `maxHeight` 186) carried
  alongside `eotwStageSubtitle` on the montage's intro label; the montage
  header is `height = "auto"` with `minHeight = HEADER_HEIGHT`; and
  `SyncHeaderHeight` (called from `Refresh` and from the stage's 0.5s think)
  re-derives the body's `100%-N` height from `header.renderedHeight`,
  clamped to the new `HEADER_HEIGHT_MAX = 260`. VERIFIED: the live script's
  one-line intro reads clearly and the stage reflows by the ~15 it grew;
  pushed to a four-line paragraph by hand, the header wraps and the columns,
  turn panel and hero row all move down with nothing clipped. The narrative
  stage was deliberately left alone (plain subtitle, fixed header). Design
  under "The stage (UI)", the Header bullet. Note again for the next
  session: `reload_lua` did NOT pick up edits to this file (the known
  dead-watcher trap; the tell was an `inspect_ui` backtrace whose line
  numbers lagged the working copy) -- only `restart_dmhub` did, and after a
  restart the presented dialog must be re-presented.

- 2026-09-18 (the week's script gets its narrative beats): **The
  authoring game's `Encounter` document now opens with a narrative and has
  a second one between the montage and the fight. WRITTEN + VERIFIED on
  screen.** User direction: an introductory narrative explaining that the
  heroes are working through the forest to avoid Ajax's searching patrols,
  hoping to reach Blackbottom, wary of goblins, with the scene set for a
  hard journey; then a second narrative, after the montage, where they find
  themselves surrounded by goblins before the combat. Written straight into
  the live document (`98a5a5bf`) with `SetTextContent` + `Upload`, by
  splicing around the existing text rather than retyping it, so the montage
  and encounter beats are byte-identical; the pre-edit text is in this
  session's `_G.g_eotwScriptBackup`. Contents and the one decision worth
  knowing (the crossing choice is deliberately flavour-only, no rules text)
  are under "The week's script as it stands". Parse: 4 beats, 0 warnings.

- 2026-09-18 (narrative beats, latest): **A script can have `# Narrative`
  beats. DECIDED + BUILT + VERIFIED end to end in the authoring game;
  UNCOMMITTED.** User direction: as well as montages and an encounter there
  can be narrative sections, each with a `[[scene]]`, text that appears, and
  options that either have to be agreed upon or are taken by each hero on
  their own; an option can carry the same rules text a power table can
  ("+1 hero token") or just be a "Proceed"; a disagreement on an agreed
  option is settled at random, flashing between the players before it
  decides; and everyone chooses before the next section. Design in
  [Narrative beats](#narrative-beats-decided--built-2026-09-18-lua-only-verified-end-to-end-in-the-authoring-game-real-eotw-game-untested-uncommitted),
  build order in Phase 8. Files: `EncounterOfTheWeek/EncounterScript.lua`
  (the beat + its grammar), `EncounterOfTheWeek/EncounterNarrative.lua`
  (NEW, registered in the codemod after `EncounterMontage`),
  `EncounterOfTheWeek/EncounterMontageStage.lua` (`CreateNarrativeStage`
  behind `StageFor`, the shared chrome, the flash),
  `EncounterOfTheWeek/EncounterMontage.lua` (`ctx.heroEntries`,
  `ctx.source`, multi-target allies, `RecordAlly`, reset),
  `EncounterOfTheWeek/EncounterOfTheWeek.lua` (the beat machine),
  `tests/encounter_script_test.lua` (150 checks). Decisions recorded with
  the user: sections live under one `# Narrative` beat; individual choices
  are per hero and agreed choices are per player; an agreed option's rules
  text applies to the whole party. Note for the next session: `reload_lua`
  could not load edits to these files (the known dead-watcher / stale
  codemod trap) -- **restart the app after editing them**, and after a
  restart the presented dialog must be re-presented to pick up stage edits.
  Also: `register_lua_file` put `EncounterNarrative.lua` in the codemod's
  file list (confirmed persisted, and a cold restart loads it), but the
  repo's `main.lua` mirror has NOT been rewritten with its `require` yet --
  do not hand-edit it; let the app's mod tools write it.

- 2026-09-18 (montage roll visibility): **Remote roll dialog for the
  other clients + live tier highlight on the stage while the dice roll.
  BUILT, luac-clean, UNTESTED live, UNCOMMITTED.** User direction: show
  the read-only remote copy of the montage roll dialog to everyone else
  (as on a hero's combat turn) and highlight the tier the live roll is
  landing on in the stage's option card, updating as the dice tumble.
  Files: `Timeline/AbilitySidebar.lua` (new exports
  `CharacterPanel.ShareDisplayedAbility`, `AbilityShareDocPath`,
  `GetAbilityShareData`), `EncounterOfTheWeek/EncounterMontage.lua` (share
  call after `DisplayAbility`), `EncounterOfTheWeek/EncounterMontageStage.lua`
  (`SetLandedTier`, `LiveTierRows`, `OptionCard` uses it while rolling).
  Design under "Runtime state and authority" step 3 and "The stage (UI)",
  the turn-panel bullet. `reload_lua` in the running game (montage mid
  round 1, a Human Censor rolling) did not load the core change, so a
  restart is needed to test. Test: two clients, drag a hero onto a threat,
  choose an option, roll -- the other client should get the remote card
  with the option's tier table at the sidebar, and on both clients the
  stage's option card should move the gold highlight between tiers while
  the dice tumble, then settle on the landed tier before the host resolves.
  Also confirm the remote card draws above the stage (same open question
  as the local card).

- 2026-09-18: **Local-assets playtesting of an EotW game works in
  the current build; the global directory list was simply EMPTY.** Asked
  whether an EotW game could be forced to be a "dev game" so it loads
  assets from local YAML instead of the cloud. There is no dev-game flag:
  the mechanism is the global `localassets:eotwdirs` list built on
  2026-08-30, and the engine half (`LocalAssetDirectory.ReadEotwDirs` /
  `IsEotwGame`, commit `d00fca8b3`, 2026-08-31) is in the
  2026-09-18 player build, so the "NEEDS BUILD" caveat on that section is
  retired. Live check on the running client: `dev` = true,
  `dev:encounteroftheweek` = true, slot game
  `FleetArcaneVelvetScaletooth`, but `localassets:eotwdirs` read `""` --
  so every recent playtest had been loading the published module. Reset to
  the canonical pair, `C:\dev\eotw` then
  `C:\dev\dmhub\draw-steel-codex\data` (matching the authoring game's
  `localassets:dirs`), via `dmhub.SetSettingValue`. Takes effect on the
  next game load, so an EotW game already running must be re-entered.
  UNTESTED: an EotW game actually loading its assets from the directories
  -- still the one unverified link in the chain.

- 2026-09-18: **Montage initiative clauses: BUILT, luac-clean,
  parser unit tests pass (77); runtime and core hook UNTESTED live
  (code-only session); UNCOMMITTED.** Tier lines and `Consequence:` lines
  can say `You begin the encounter surprised`, `You surprise the enemy`,
  `You win initiative`, `You lose initiative`; the host remembers the last
  one in `eotwscript.initiative` and the encounter beat starts combat with
  the forced winner and the Surprised condition on the losing side, through
  two new optional args on the core `Encounter.StartCombatWithTokens`.
  Files: `EncounterScript.lua`, `EncounterMontage.lua`,
  `EncounterOfTheWeek.lua`, `Draw Steel UI/DSInitiativeRoll.lua`,
  `tests/encounter_script_test.lua`. Phase 7 step 36 has the live test
  script. Deploy note: the core file must be deployed/reloaded together
  with the codemod files (deploy.ps1 copies all git-modified Lua).
- 2026-09-18: **Montage hero cards show characteristics and
  skills. BUILT + VERIFIED on screen in the authoring game; UNCOMMITTED.**
  `CreateHeroCard` in `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` gained
  an `opts.showStats` mode (`CreateStatStrip` + `CreateSkillsLine`, two new
  style rules, taller card and overlay); `CreateHeroColumn` in
  `EncounterMontageStage.lua` passes it and `HERO_ROW_HEIGHT` grew to 320.
  Design under "Bottom row: hero cards". Note for the next session: the
  EotW codemod's file watcher is dead in this session (the known
  deploy-kills-the-watcher bug), so `reload_lua` cannot pick up edits to
  these files -- only an app restart loads them.

- 2026-09-18: **Hero Tokens are seeded at session start: one per
  hero. DECIDED + BUILT; UNTESTED, UNCOMMITTED.** `SeedHeroTokens` in
  `EncounterOfTheWeek/EncounterOfTheWeek.lua`, called from the host's
  `SetupOnArrival` right after the `numheroes` write, stamped once in the
  `eotwstate` doc (`heroTokensSeeded`) so resumes never refund spent tokens.
  Lua only, luac-clean; could not be exercised locally (the running game is
  not an EotW game, so the codemod is not even loaded there). Design in
  [Hero Tokens at the start of the session](#hero-tokens-at-the-start-of-the-session-decided--built-2026-09-18-untested).

- 2026-09-18 (haul strip): **Items acquired during a montage show beside
  the hero's stage card. DECIDED + BUILT; drop-in + sound VERIFIED live in
  the authoring game, UNCOMMITTED.** User
  direction: show the icons of any items acquired during the montage down
  the left side of the hero card, with the item's details on mouse over,
  and have a new item appear above and animate down into position. The host
  now records each granted item on the script document
  (`data.items[heroCharid]`, written by `RecordItem` beside the inventory
  write in `EncounterMontage.ApplyEffects`; read back through
  `EncounterMontage.GetItems`, cleared by `/eotwmontage reset`), and
  `EncounterMontageStage.lua` grows `CreateItemIcon` / `CreateItemStrip`
  plus an `eotwItemIcon` / `eotwItemQty` style pair; `CreateHeroColumn`
  now puts the strip and the card side by side in a `cardRow`. Design under
  "The stage (UI)", the haul strip bullet. Lua only, luac-clean.

  Later the same day, on user direction ("items should animate in nicely,
  appearing above their starting position, fading in and moving downward
  into position... and play a satisfying sound event the same as when a
  character gets an item in combat"), the drop-in was rebuilt and given
  sound. The first attempt animated by writing `selfStyle.y` /
  `selfStyle.opacity` with a `transitionTime`, which does not animate at
  all -- transitions only run when a *rule's* match changes. A second
  attempt put the timing on a resting-state rule (`~dropIn`), which fades
  but never moves, because style `y` accumulates over matching rules. The
  shipped shape (born with `dropIn`, ramp that rule out) was proven with a
  throwaway panel in the running app -- square raised 300px, transition
  slowed to 8 s, pixel-sampled mid-flight -- and then exercised in the real
  strip with `ITEM_DROP_TIME` temporarily at 4 s and items injected into
  `data.items`: icons fall from above, fading in, staggered, and land
  cleanly. Both sound events fire without error; `EquipmentCategory`
  resolves at stage runtime.

- 2026-09-18 (montage): **Montage VERIFIED end to end in the authoring
  game** (stage, approach, choose, real roll, every effect kind, the
  consequences phase, completion; zero errors). `/eotwmontage start`
  added as the dev driver for games without the EotW map script. Details
  under "Testing it" in the design section. Real two-client EotW game
  still UNTESTED; UNCOMMITTED.

- 2026-09-18 (later): **Encounter scripts + montage beats: BUILT (steps
  29-33), luac-clean, parser unit-tested (64 checks), UNCOMMITTED.** Three new codemod files (`EncounterScript.lua`,
  `EncounterMontage.lua`, `EncounterMontageStage.lua`, registered via the
  MCP CodeMod workflow) plus edits to the codemod and hud; no engine or
  core change. The user decided opportunities persist round to round like
  threats. Files are on disk in the repo (which IS the app's git folder);
  a Lua reload picks them up. The ordered test recipe is under "Testing
  it" in the design section; the next `/week` session should start there.

- 2026-09-18: **Encounter scripts + montage beats: PLANNED.** User
  direction: the map's document becomes a script of beats;
  `# Montage` (scene backdrop, `## Round N`, `## Opportunity:` /
  `## Threat:` entries with `###` options carrying journal power-roll
  blocks whose tier text is parsed into effects -- items, stamina, malice,
  an allied monster, "the threat is vanquished") plays before the
  `# Encounter` beat; unvanquished threats deliver their `Consequence:` at
  the end. Design in
  [Encounter scripts](#encounter-scripts-montage-beats-before-combat-planned-2026-09-18-nothing-built)
  (grammar, the `eotwscript` state doc, host-arbitrated turns with the
  owning client rolling, effect application, the presentable-dialog
  stage, allies in combat, the beat machine that moves the monster spawn
  to the encounter beat); build order is Phase 7 (steps 29-35). Defaults
  taken on the open rules are listed under "Montage rules the sample
  script leaves open" in Open Questions -- confirm or change them before
  step 31. No engine change expected; three new codemod files to register.

- 2026-09-16: **"New Director Window" works from an EotW game for dev+admin
  hosts. DECIDED + BUILT; engine NEEDS BUILD, UNTESTED, UNCOMMITTED** (core
  `Commands.lua`, the EotW codemod + hud, `GameController.cs`,
  `LuaInterface.cs`, stubs). The child launches with `--director`, which
  seeds `playerHostModeSuppressed` in the engine and is honored by the
  codemod's Director-UI gates. Design in
  [Debug "Director Window"](#debug-director-window-from-inside-an-eotw-game-decided--built-2026-09-16-engine-needs-build-untested).

- 2026-09-15: **Debug "Player Window" in the game lobby view. DECIDED +
  BUILT; engine NEEDS BUILD, UNTESTED, UNCOMMITTED.** Admin-only button
  launching a secondary-account child (`--asplayer --eotw-game <id>`,
  `connect = false`) that auto-opens the EotW screen and joins the game.
  Private games reject the join. Design in
  [Debug "Player Window"](#debug-player-window-from-the-game-lobby-view-decided--built-2026-09-15-engine-needs-build-untested).

- 2026-09-15 (latest): **Encounter pools strip (Malice + Hero Tokens) above
  the hero roster. DECIDED + BUILT + VERIFIED LIVE; UNCOMMITTED.** User
  direction: "add a new panel which displays both monster malice as well as
  hero tokens" above the hero panels in the right rail wrapper. Built in
  `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` (`CreateEncounterPoolsPanel`
  + `CreateRightRailPanel`, roster budget reserves the strip's height).
  Read-only, history tooltips on hover. Verified in a real EotW game on
  0.0.831: strip above the cards showing Malice 4 / Hero Tokens 0, no
  console errors. Two things came out of it, both UNCOMMITTED in the codex
  repo: a core fix to `GameHud.RegisterCustomInterface` (`DMHub Core
  UI/Hud.lua`) so a Lua reload replaces a same-id provider instead of
  leaving the stale one first and winning; and another instance of the
  stale-`localContents` reload gotcha (details in the hud section). Open
  question for the user: should the host get an edit path on the pools, or
  is read-only right under strict rules? Note: the panel was iterated on
  by hot-reloading Lua mid-combat in the user's live game, which threw a
  burst of `EmbeddedRollDialog` errors for the in-flight roll dialog (the
  reload destroyed it) -- harmless once the dialog was reopened, but do
  not reload during someone's roll.

- 2026-09-06: **Hero killed on their own turn locked the combat on
  "Hero Turn"; ROOT-CAUSED + FIXED in core Lua, live on disk, UNTESTED
  end-to-end.** First real exercise of the Hero Death rule: it fired and
  despawned the hero (kill path now VERIFIED), but the queue's current entry
  then resolved to zero tokens, so `ShouldShowEndTurn` was false for every
  client and nothing could advance. Fix: removal auto-ends an emptied current
  turn (`ActivatedAbilityRemoveCreatureBehavior.EndTurnIfEntryEmptied`,
  `DMHub Game Rules/AbilityRemoveCreature.lua`) and the bubble shows End
  Turn for a zero-token current entry to anyone who can control initiative
  (`Draw Steel Core Rules/MCDMInitiativeBar.lua`). The locked game
  (`BroadEnormousVigorousSalorna`) was unlocked over MCP with
  `GameHud.instance:NextInitiative`. Design in [Dying on your own turn](#dying-on-your-own-turn-the-orphaned-turn-lock-root-caused--fixed-2026-09-06-lua-live-on-disk-untested-end-to-end).
  Both mods' file watchers were dead and had to be re-armed before the
  change was visible to a reload (recipe in that section). Needs a Lua
  reload (F4) in the running client; UNCOMMITTED in the codex repo. Still to
  test: a hero dying on their own turn in a fresh EotW combat auto-advancing
  without any click.

- 2026-09-06: **Module version 9 PUBLISHED -- it fixes v8's
  `balancing` wire shape.**
  - dataid `e9f6386c-1a55-4fd4-be17-27a34e403de1`, streamed 16,508B, snapshot
    139,379B, blobs `Nbz938ZxMTDGysfBU0sy4A==` (4,804B) and
    `rPS499QYlOGXHZp/G1/+uw==` (24,732B, unchanged from v8). Published as
    `python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data" --publish --force`.
  - **What changed vs v8**: the encounter document `645e4522` and nothing else
    (`--verify-against d8b02254` reported exactly one differing row before the
    publish; every other table, the map, the 9 pregens, the codemods and the
    `venla-deliantomb` dependency matched). The difference is not new authoring
    -- it is the SHAPE of `groups[].balancing`. v8 carried it as
    `{"2": {monsters: ...}}`, Firebase's sparse-array rendering (0-based key 2
    = hero count 3), which is precisely the wire shape
    `validate_engine_shapes` exists to catch: an array encoded as a
    numeric-keyed object decodes to **null** for a `List<>` field on the
    installing engine, so v8's per-hero-count balancing most likely did not
    survive install at all. It shipped because v8 used `--force`. The YAML on
    disk holds the dense 7-entry array the codex deliberately builds
    (`EncounterPanel.lua:932` seeds indices 1..7 so index == hero count
    survives serialization), so simply republishing from `C:\dev\eotw`
    corrects it; the engine shape preflight now reports OK rather than being
    forced past. Re-verified after publishing: `--verify-against e9f6386c`
    matches on every table including `documents rows VALUES MATCH`.
  - `--force` was still needed for the same standing warning v6-v8 shipped
    under (floor object `62b484a3` -> asset `5939fe95`, low severity: the
    placed object embeds its own copy of the art).
  - UNTESTED: a game installing v9 and the balancing actually applying at a
    non-default hero count -- the fix is reasoned from the wire shape and the
    preflight, not observed in a running install.

- 2026-09-06: **`C:\dev\eotw` is now a git repository.** The EotW
  authoring directory -- the sole home of `room-1.yaml` (the week's encounter),
  `start.yaml` (the Start keyword) and `hero-death.yaml` (the Hero Death rule),
  plus their `_meta.yaml` descriptors -- had been loose files on disk with no
  version control and no backup, while local-assets write-back can silently
  rewrite any of them during a playtest. `git init -b master` + an initial
  commit of all six files (`4f7cec2`), followed by a `.gitattributes` carrying
  `* -text` (`f0fa701`) so git never converts the line endings of files the
  engine writes itself. No remote; local history only. Nothing else changed --
  the engine and the publisher both just read the directory. The "shows up as a
  git diff" claim in [Playtesting against local asset directories](#playtesting-against-local-asset-directories-decided--built-2026-08-30-engine-shipped-in-the-2026-09-18-build)
  was false when written and is now true; it has been corrected either way.

- 2026-08-31: **Module version 8 PUBLISHED** -- the first version
  carrying the re-authored encounter.
  - dataid `d8b02254-b767-4bbc-9484-400a4df1070c`, streamed 16,029B, snapshot
    139,379B, blobs `uIqrikBFqDAIX/LFuI1o1w==` (4,504B) and
    `rPS499QYlOGXHZp/G1/+uw==` (24,732B). Published as
    `python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data" --publish --force`.
  - **What changed vs v7**: only the encounter document. `room-1.yaml` was
    re-authored after the v7 publish (3 groups / 12 spawn positions / 5 distinct
    monsters, against v7's 6 groups); everything else -- map `8d78cadf`, the
    9 pregens, the `Start` keyword `47ea72f9`, the Hero Death global rule, the
    three codemods (EncounterOfTheWeek, Monster AI, DelianTomb), the
    `venla-deliantomb` dependency -- is unchanged, which is why the report says
    "identical content set to the last version": that line compares the guid
    SET, and the encounter's monsters come from a dependency module rather than
    from the payload, so re-authoring the fight moves no guids. The streamed
    size (17,978B -> 16,029B) is the honest signal that content changed.
  - `--force` was again needed for the same standing warning v6 and v7 shipped
    under (floor object `62b484a3` -> asset `5939fe95`,
    `GL_OvergroundDwarvenCityCenter_Original_Day`, which exists only in the
    authoring game's frozen store; still UNFIXED, still low severity because
    the placed object embeds its own copy of the asset).
  - **Verified**: engine-shape and Firebase preflights passed, and
    `--verify-against d8b02254-...` rebuilds the published payload with every
    key set and every value matching (`snapshot.*`, `streamed tables`, and all
    six object tables).
  - UNTESTED: a game actually installing v8, and the Hero Death rule (shipped
    since v7) firing on a real hero kill.

- 2026-08-31: **Module version 7 PUBLISHED, and the split EotW authoring directory is consolidated on `C:\dev\eotw`.**
  - **The authoring content had drifted into two directories.** `D:\dev\eotw`
    was the authoring game's `localassets:dirs` top entry; `C:\dev\eotw` was the
    global `localassets:eotwdirs` playtest list. Both ended up holding a
    `room-1.yaml` (the week's encounter) and they had diverged -- C's 6 groups /
    23 monsters, with a mount and a `minHeroes = 5` group, against D's 4 groups /
    17 monsters -- while `start.yaml` lived only in D and `hero-death.yaml` only
    in C. Publishing from D would have shipped a version content-identical to v6
    and silently dropped the Hero Death rule. **User direction: C is correct and
    is the authoring directory; D is retired.**
  - **Consolidated** (files copied, nothing deleted): `C:\dev\eotw` now holds
    `objectTables/documents/{_meta,room-1}.yaml`,
    `objectTables/environmentalkeywords/{_meta,start}.yaml` and
    `objectTables/globalrulemods/{_meta,hero-death}.yaml`. The authoring game's
    `localassets:dirs` was repointed to `C:\dev\eotw` + the codex data tree,
    matching `localassets:eotwdirs` exactly -- one directory for both authoring
    and playtest, so a playtest write-back can no longer fork the content.
    `dmhub.LocalAssetsApplyDirs()` returned `reload`: **the running client still
    has D's overlay in memory until the game is reloaded.** `D:\dev\eotw` is left
    on disk, unreferenced. All `D:/dev/eotw` references removed from this
    document and `tools/eotw_publish/README.md`.
  - **Version 7 published** (dataid `14627d5b-91fa-422d-bd05-f9e5b20b1094`,
    streamed 17,978B, snapshot 139,379B), as
    `python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data" --publish --force`.
    Content vs v6: +1 guid, the `globalRuleMods` row **Hero Death (Encounter of
    the Week)** -- the first publish carrying it -- plus the 6-group encounter
    document (the report's island count went 7 -> 10 monsters once C's copy was
    the one being read). `--force` was needed for the same standing warning v6
    shipped under (floor object `62b484a3` -> asset `5939fe95`,
    `GL_OvergroundDwarvenCityCenter_Original_Day`, which exists only in the
    authoring game's frozen store; still UNFIXED, still low severity because the
    placed object embeds its own copy of the asset).
  - **Verified**: both engine-shape and Firebase preflights passed, and
    `--verify-against 14627d5b-...` rebuilds the published payload with every key
    set and every value matching (`snapshot.*`, `streamed tables`, and all six
    object tables including `globalRuleMods`). The GCS blob could not be
    re-downloaded for an independent check -- `https://storage.googleapis.com/dmhub_images/{urlified-key}`
    404s for v6's known-good key as well as v7's, so that URL form is stale
    (likely the R2 migration); the upload endpoint returned 200 for both blobs.
  - UNTESTED: a game actually installing v7, and the Hero Death rule firing on a
    real hero kill.

- 2026-09-07: **Defeat screen with heroes still standing, then an unrequested exit to the titlescreen. DIAGNOSED from the host log (game `VengefulMountainousDuskSniper`, 2 clients: host `4V4KWXdW7ScFIiEyuknO4bqmQSc2` + player `ZaRxAuEiu6gAkLygFuGMys8ZvAy1`, 3 heroes). Not a code fault; OPEN DESIGN QUESTION.**
  - The exit (not changed): the log shows `the heroes are defeated; showing the defeat
    screen`, then a `proceedRequested` patch RECEIVED from the server (no
    local `DO>> PatchData` send precedes it, and the host never writes that
    key -- the host's own Proceed runs the teardown directly), then `a
    player pressed Proceed; ending the encounter` and the normal relay ->
    auto-exit -> cleanup chain. So the OTHER client pressed Proceed, which
    is exactly the documented player-Proceed relay: any player's Proceed
    dismisses the screen and exits everyone. Working as designed; whether
    one player should be able to end it for everyone is a design question
    (options: require the host, require every present player, or a
    countdown).
  - The "defeat with heroes alive": the game's DO was already wiped by the
    finished-game cleanup, so the final hero stamina could not be read. The
    only defeat paths are a script-declared defeat (none is authored for
    this encounter) and `CountLiveCombatants` returning `heroes == 0`,
    which counts `CurrentHitpoints() > 0` -- so every hero at 0 or fewer
    Stamina (DYING, not dead) read as down. User confirmed this was the
    problem. FIXED same day: `EncounterOfTheWeek.lua` now uses its own
    `CountLivingHeroes(queue)` (`not props:IsDead()`) for the all-heroes
    defeat; design updated above. Syntax-checked, deployed; UNTESTED live.
    The Proceed policy question (one player ends it for everyone) was
    DECIDED 2026-09-08: per-client dismissal (next entry).

- 2026-09-08: **Victory screen closed before the user pressed Proceed. DECIDED + BUILT: per-client dismissal. Syntax-checked, deployed (git folder = repo), reloaded clean; UNTESTED live.**
  - Cause: the screen show/hide was purely a function of the shared
    initiative queue, so any other client's Proceed (relayed to the host's
    teardown) hid it everywhere. User direction: it must never close until
    the local user is ready.
  - Fix: `DSVictoryScreen.lua` -- new optional override field
    `holdUntilLocalProceed()`; when true, the outcome leaving the queue
    flags the screen `held` instead of hiding it, and Proceed on a held
    screen calls `proceed(_, alreadyEnded=true)` then hides locally.
    `EncounterOfTheWeek.lua` -- `m_localProceeded` set on every local press;
    the hold returns `not m_localProceeded`; `UpdateEncounterConclusion`
    exits only when `m_outcomeSeen and m_localProceeded` and the queue is
    hidden. Design folded into "Victory/defeat auto-detection, player
    Proceed, and auto-exit".
  - Live test to run: two clients; one presses Proceed, confirm the other's
    screen stays (tooltip reads "Dismiss the victory screen.") and only that
    client exits; the second presses later and exits, even after the first
    client's titlescreen has wiped the game.

- 2026-09-06: **Live game stuck after the last monster died -- no victory screen. DIAGNOSED + FIXED (self-healing on both layers); Core Rules half VERIFIED live, EotW half UNTESTED.**
  - Symptom: `live:CheckVictory()` read true, nothing awarded, every client
    idle (no busy stamps, no prompts), `MapScript.IsElectedHost(mapid)` false
    on the host. `MapScript.GetBuiltin("builtin:eotw-encounter")` returned
    nil: the attached record's code no longer resolved, so the driver
    destroyed the instance (the last `mapscripts-<mapid>` patch was the
    `ReleaseHostPresence` clear of `hosts`) and the host tick --
    `CheckEncounterOutcome` included -- never ran again.
  - Cause: a mid-game Lua hot-reload. A local edit to
    `EncounterOfTheWeek.lua` force-reloaded the EotW mod (frame 163245),
    then a full reload of every mod (frame 163247) re-executed
    `Draw Steel Core Rules/MapScript.lua`, which recreated
    `MapScript.builtins` with only the two shipped scripts. The EotW mod was
    NOT re-executed in that pass (`Loaded ... in 0ms`, no file lines), so
    its `RegisterMapScriptBuiltin()` registration was lost. Any reload
    order in which Core Rules runs after EotW lost it.
  - Live unblock: re-ran the `MapScript.RegisterBuiltin{...}` call via
    `execute_lua`; the driver re-created the instance on its next tick, the
    host was re-elected, and the award fired within ~7s ("victory condition
    met; showing the victory screen"). The other player then pressed
    Proceed and the relay + auto-exit + cleanup path all ran (log lines
    "a player pressed Proceed", "returning to the titlescreen", "cleaning up
    finished game"). One stray line in that flow: "conclusion leave-game not
    accepted: game ... is not registered" -- the lobby had already dropped
    the roster record; harmless, not chased.
  - Fix 1 (general, `Draw Steel Core Rules/MapScript.lua`): the builtin
    registry now lives in the global `g_mapScriptBuiltinRegistry`
    (`{list, byId}`) and is REUSED when the file reloads, so registrations
    made by any other mod survive a Core Rules reload; the driver's 0.5s
    reconcile then recreates any attached record whose code resolves again.
    New `MapScript.IsRecordRunning(guid)` (backed by the exposed
    `MapScript._runtimeInstances`) lets a managing mod verify its script is
    actually running. VERIFIED live: a throwaway builtin registered via
    `execute_lua` was still resolvable after `reload_lua`.
  - Fix 2 (EotW, `EncounterOfTheWeek.lua`):
    `EncounterOfTheWeekGame.EnsureMapScriptRunning()`, called from every
    client's 1s driver: any client re-registers the builtin if
    `MapScript.GetBuiltin` lost it; the HOST of an EotW game additionally
    re-attaches the record if the map lost it and logs once (not per tick)
    if the record is attached but `IsRecordRunning` is false. UNTESTED in a
    game: the EotW mod is not loaded at the titlescreen, so it could not be
    exercised after the reload; syntax-checked with `luac -p`.

- 2026-08-31: **Victory/defeat banner lingers ~5s after the killing blow, and every combatant who STARTED the encounter now gets a victory-screen card. BUILT + syntax-checked + reloaded live; kill-path UNTESTED.**
  - **Linger**: `OUTCOME_LINGER_SECONDS = 5` in
    `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`CheckEncounterOutcome`) --
    stamped when the outcome condition is first observed met, checked after
    the existing 2-tick idle hold; the two waits run concurrently so
    prompt-heavy endings pay no extra delay. Design folded into
    "Victory/defeat auto-detection" (the linger bullet).
  - **Full roster**: `LiveEncounter:GetBattleHeroTokens`
    (`Draw Steel Core Rules/MCDMEncounter.lua`) merges in onset heroes whose
    tokens the queue no longer resolves (despawned by the hero-death rule),
    via `dmhub.GetCharacterById` -- the hero-side mirror of
    `GetMonsterGroups`' onset merge, which already covered monsters. Also
    fixes the all-heroes-dead defeat losing its battle-log record. Design in
    "Dead heroes leave the battlefield"; `LIVE_ENCOUNTER.md` stat-attribution
    note updated.
  - Verified live after a Lua reload (51 mods, no errors): the roster
    function runs, and `GetCharacterById` resolves an unspawned hero with
    every field the card reads (portrait, `IsDead`, hitpoints). UNTESTED:
    an actual kill -> despawn -> victory/defeat screen showing the removed
    hero's card, and the felt timing of the linger.
- 2026-08-31: **Heroes are forced to exactly level 1 as they are placed. BUILT + syntax-checked; UNTESTED live.**
  - `NormalizeHeroLevel(token)` in
    `EncounterOfTheWeek/EncounterOfTheWeek.lua`, called from
    `ClaimPastedHero` right after its `UploadToken`, on the pasted COPY --
    the owner's original hero is never touched. It checks first and only
    then opens an `undoable = false` `ModifyProperties` patch, so a hero
    that is already level 1 uploads nothing.
  - Clamps from ABOVE (`levelOverride = 1` **and** every `classes` entry to
    `level = 1`, since `CharacterLevel()` is the max of the two) and from
    BELOW (clears `extraLevelInfo.encounter`, the "First Encounter".."Fourth
    Encounter" slow-start rungs that skip `level-1` altogether). Full design
    in [Heroes enter at exactly level
    1](#heroes-enter-at-exactly-level-1-decided--built-2026-08-31-untested).
  - Verified live (read-only, game `DangerousRavenousBalefulMemonek`) that
    the four pregens already read `levelOverride=1, encounter=nil, class
    level=1`, i.e. the fields and accessors behave as the fix assumes and the
    clamp is a no-op for correctly-authored pregens. What is still UNTESTED
    is the correcting case: placing an above-level-1 lobby hero and a
    slow-start hero into an EotW game and confirming both land on Level 1.
  - Lua only, already live on disk (the codex git folder is the repo); needs
    a Lua reload in the running app.
- 2026-08-31: **The loading veil now waits for the screen's portraits instead of revealing on a timer. BUILT + syntax-checked; UNTESTED (needs a Lua reload at the titlescreen).**
  - Reported: the veil "shows very briefly and disappears but then there are
    still hitches as all images are streamed in". Correct -- the veil was
    purely time-based (~0.8s floor) and the portrait warmer deliberately
    started 0.75s in, i.e. *after* the reveal, so its texture decodes landed
    on the visible screen.
  - Fix, all in `Codex Titlescreen/EncounterOfTheWeek.lua`: the warmer starts
    immediately (under the veil) and reports mounted/ready per warm panel
    into `m_warmState`; the veil's new `waitForImages` step polls
    `PortraitWarmupSettled()` until the art has arrived, with an
    idle-for-0.5s exit so a never-arriving texture cannot hold it, and a 4s
    hard deadline. Design and the anti-regression rationale in [Waiting for
    the art](#waiting-for-the-art-2026-08-31).
  - Floor rises from ~0.8s to ~1.3s. That is intended: the veil is supposed
    to be what the player waits on.
  - Lua only, already live on disk (the codex git folder is the repo); needs
    a Lua reload in the running app.
- 2026-08-30: **Opening the EotW screen now plays a brief loading screen instead of freezing on a half-drawn page. BUILT + syntax-checked; the veil is verified live, its image wait is the 2026-08-31 entry above.**
  - `EncounterOfTheWeek.ShowScreen()` mounts a cheap loading veil, builds
    the screen behind it, and cross-fades once the build has settled. Every
    step is scheduled off the END of the previous one, so a slow build
    pushes the reveal back rather than uncovering a stalling screen. An
    `eotwOpeningBlocker` keeps the invisible-but-live screen from taking
    clicks during the settle, escape cancels the open, and
    `SweepStaleScreen` cleans up veils left by a previous codemod
    generation. Full design in [Opening the screen: the loading
    veil](#opening-the-screen-the-loading-veil-decided--built-2026-08-30-waits-for-the-art-since-2026-08-31).
  - Portrait warming amortized in the same file: at most 3 panels per tick
    instead of all of them at once. That single-tick burst of texture decodes
    was most of the hitch itself, so this shortens the wait as well as
    covering it. (The first pass was also pushed past the reveal here;
    2026-08-31 moved it back under the veil -- see the entry above.)
  - Lua only, in `Codex Titlescreen/EncounterOfTheWeek.lua` -- no engine
    change, and already deployed (the codex git folder is the repo). The
    verification checklist is at the end of that design section.
- 2026-08-30: **The Journal is reachable during an EotW game. BUILT + verified live.**
  - The custom interface's bottom-left corner strip now carries three
    kept buttons instead of two: **Journal, Chat, Action Log**, top to
    bottom (`CreateCornerButtonsPanel` in
    `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` -- a one-line list
    change, since `CreatePanelButton` already builds any registered
    dockable panel's rail button). Players get the encounter's briefing
    and handout documents; with the rails suppressed there had been no
    way to open the journal at all.
  - No permission work was needed: the Journal panel registers with
    `dmonly = false` (`DMHub Core Panels/Journal.lua`), so it was always
    a player-visible panel -- only the rail takeover was hiding it.
    Per-document visibility rules are unchanged, so a player still sees
    only the documents shared with them.
  - Verified live in the authoring game via `/toggle eotw:forcecustomui`:
    the strip renders 3x40px buttons, the Journal button is the topmost,
    clicking it opens the normal rail journal window with the document
    tree, the active underline lights, the tooltip reads "Journal", a
    second click closes it, zero new console errors.
  - What players will actually find in there: the weekly module's own
    journal rows (see [Module + codemod bundling](#module--codemod-bundling)
    -- docs ship as `documents`-table rows and the publisher's seed carries
    the encounter doc), plus whatever the game itself shares. NOT yet seen
    in a real EotW game with a published module -- only in the authoring
    game, whose journal holds the dev game's own documents.
  - Lua-only; no engine change, nothing to rebuild.
- 2026-08-30: **Dead heroes are removed from the battlefield like monsters. BUILT + partially verified live; the actual kill path and a publish carrying the rule are UNTESTED.**
  - A `GlobalRuleMod` shipped as EotW module content, not code: `C:\dev\eotw\objectTables\globalrulemods\hero-death.yaml` (+ `_meta.yaml`), mirroring the core Monster Death rule with `applyCharacters: true`, `waitForTriggers: true` (removal waits for the hero's triggers to resolve), `leavesCorpse: true`, `dropsLoot: false`. Full design + verification detail in the new [Dead heroes leave the battlefield](#dead-heroes-leave-the-battlefield-decided--built-2026-08-30-kill-path-untested) section.
  - Publisher taught to seed non-core `globalRuleMods` rows (`tools/eotw_publish/publish_eotw.py`, after `build_seed`) -- global rules are referenced by nothing, so the dependency closure could never ship one. Compiles; the tree loader finds the row; no publish run yet. **The rule reaches real EotW games only with the next module publish (v7+).**
  - Verified in the running authoring game with no restart (local-assets watcher): row loads and deserializes, a hero carries the trigger modifier, a monster does not.
- 2026-08-30: **Tooltips (and with them the movement cross-section diagram) are now silenced for the whole pre-combat phase, through a new general engine flag. BUILT; engine NEEDS BUILD.**
  - Built as a general mechanism rather than an EotW special case: a new engine flag `dmhub.tooltipsSuppressed` gates every tooltip in the app at two choke points, and a keyed core-codex wrapper `GameHud.SetTooltipsSuppressed(key, value)` layers the map-tooltip and cross-section gates on top so neither is even built while it is held. Design in [Tooltip suppression during the pre-combat phase](#tooltip-suppression-during-the-pre-combat-phase-decided--built-2026-08-30-engine-needs-build).
  - Engine (MSBuild-clean, NOT built): `tooltipsSuppressed` field on `Assets/Scripts/GameController.cs` (next to `movementRestrictionLocs`); the gate + `DismissAllTooltips` in `Assets/Scripts/SheetPanel.cs`; the legacy-tooltip gate + `HideTooltip` in `Assets/Scripts/GameCanvas.cs`; the `dmhub.tooltipsSuppressed` property in `Assets/Scripts/LuaInterface.cs`; stub in `Definitions/dmhub.lua`.
  - Codex (deployed): the keyed API and the two gates in `DMHub Game Hud/GameHud.lua`; the `GameHud.SetTooltipsSuppressed("eotw", desired)` call in `UpdateStartZoneConfinement` / `ClearStartZoneConfinement` in `EncounterOfTheWeek/EncounterOfTheWeek.lua`.
  - Verified live in the running client (Lua half only, since the engine is not built): a map tooltip shown through `gamehud:ShowTooltipNearLoc` appears, disappears while a key is held, and comes back when it is released; the keyed refcount holds across two keys and ignores the release of a key never held. Until the engine build lands, each flip logs "Could not set property 'tooltipsSuppressed'" to the console and panel hover tooltips are NOT suppressed -- per the no-stale-engine-guards rule the write is unguarded, so that noise is the expected pre-build state.
  - UNTESTED: the engine half (all tooltip sources), and the suppression actually engaging in a live EotW pre-combat phase.

- 2026-08-30: **Encounter of the Week games can now be played against local asset directories. BUILT; engine NEEDS BUILD, UNTESTED end to end.**
  - Local-assets mode was per-game, and an EotW game is created fresh for each encounter, so it could never be aimed at one: playtests always ran the last published module. A global `localassets:eotwdirs` list now follows the account's EotW slot. Design and consequences in [Playtesting against local asset directories](#playtesting-against-local-asset-directories-decided--built-2026-08-30-engine-shipped-in-the-2026-09-18-build).
  - Engine: `ReadEotwDirs` + `IsEotwGame` in `Assets/Scripts/LocalAssetDirectory.cs` (appended below the per-game list; `ReadSettingString` gained a global-setting mode). MSBuild-clean, NOT built -- until the build lands, the setting can be configured but nothing consumes it.
  - Codex (deployed): the setting in `DMHub Titlescreen/Settings.lua`, and `CreateEotwLocalAssetsSection` + the shared `CreateDirectoryListPanels`/`SmallButton` refactor in `DMHub Titlescreen/SettingsScreen.lua`.
  - Verified live in the running client: the new block renders under the existing Local Assets section, Copy From This Game fills it from the game's own dirs, and the status line names the slot game. The per-game section still renders correctly after the widget refactor. What remains untested is the part the engine build gates -- an EotW game actually loading its assets from the directories.
  - Fixed along the way (it bit the very first two-directory list): the shared directory rows were appended onto an args table of named keys, so Lua stored them in the hash part and 5.4's enumeration handed exactly two of them back reversed -- the list rendered upside down. Both lists now pass `children = ...`. The same pattern is latent elsewhere in the codex wherever such an args literal has no inline child.
  - Set on this machine at the user's request: `C:\dev\eotw` (top, created empty) over `C:\dev\dmhub\draw-steel-codex\data`.

- 2026-08-30: **The player host could select monster tokens, blacking out the map. FIXED (engine); NEEDS BUILD, UNTESTED.**
  - Sixth find in the player-host `canControl`-is-capability family, and the first inside the engine's own mouse surface. Full write-up in [Map interaction on a player host](#map-interaction-on-a-player-host-monsters-must-not-be-selectable-root-caused--fixed-2026-08-30-engine-needs-build-untested).
  - Chain: `_collider.enabled = canControl` makes monsters clickable for a player host -> click selects -> the monster becomes `currentOrPrimaryCharacter` -> `LightingMesh` takes the MONSTER's party as the party being viewed -> every hero fails the party filter -> zero vision lights -> the floor's `renderWorld` goes false. Black map.
  - Fixed by making `canControlAsUser` an engine-side gate on every USER-driven interaction: the token collider, `Clicked()`, `MouseDown`, `UpdateDragging`, the rotation handle (`CharacterToken.cs`), rubber-band select (`RectSelectObjects.cs`), the cycle-tokens hotkey (`GameController.NextToken`), `dmhub.SelectToken`/`AddTokenToSelection` (`LuaInterface.cs`, which also closes the initiative bar's entry click), and the off-screen token arrows (`OffScreenTokenTracker.cs`). Plus a parties-viewing fallback in `LightingMesh.cs` so vision can never be one stray selection away from black. No codex changes were needed.
  - Bit-identical in every non-directorless game, so the blast radius is the player host only. **Consequence to expect when testing: the host can no longer drag a monster by hand at all** -- `/toggle eotw:showdirectorui` is the recovery hatch.
  - Left open for a decision: the host still SEES every monster through fog (`CalculateCanSee` short-circuits on `canControl`) -- see Open Questions.

- 2026-08-30: **Module v5 shipped a payload the engine cannot read; publisher fixed, v6 PUBLISHED.**
  - Symptom: entering an EotW game NRE'd in `ModuleManager+<InstallModuleCo>d__38.MoveNext`, then the loading screen sat forever at "No starting map yet" (`UpdateGameDetails: No starting map yet... False` on repeat). 24 "Could not convert Dictionary to list" errors preceded it.
  - Cause: the publisher copied the local game server's Firebase-shaped JSON verbatim, so `mapManifests/{id}/floors` shipped as `{"0":...,"1":...}` and decoded to null. Full write-up in [The store speaks Firebase, the payload must speak Glowwave](#the-store-speaks-firebase-the-payload-must-speak-glowwave-root-caused--fixed-2026-08-30).
  - Fixed: `gamesource.strip_meta_keys` normalizes on read; `publish_eotw.validate_engine_shapes` aborts a publish carrying either bad shape; `ModuleManager.cs` skips a null `floors` instead of NRE'ing (NEEDS BUILD).
  - **Version 6 published** (`bb5c7389-2cc5-4218-9d5d-7c5ecad742af`, snapshot blob `SjQS+yd+cmsXQvj5jk//oQ==`), content set identical to v5 -- only the JSON shapes differ (139,677B vs 144,965B). Verified by re-downloading the live blob: `floors` is a real array and no array-shaped object survives anywhere. Published with `--force` for the warning below, as:
    `python tools/eotw_publish/publish_eotw.py --assets-dir "C:/dev/eotw" --assets-dir "C:/dev/dmhub/draw-steel-codex/data" --publish --force`
  - A game that hit the v5 crash does not heal: the install died before writing `modulesImported`, and the loading screen never gives up. **Create a fresh EotW game**; it installs v6 from scratch.
  - Separate, pre-existing, NOT fixed: floor object `62b484a3` references asset `5939fe95` (`GL_OvergroundDwarvenCityCenter_Original_Day`, the map-art object), which lives only in the authoring game's frozen store -- local-assets mode replaces `assets`, so it cannot ship. Low severity in practice: the placed floor object embeds its own copy of the asset (`objects/{id}/asset`, imageId and all), so the art renders; only the objects-table row is missing. Exporting it to `C:\dev\eotw` would close it properly.

- 2026-08-30 (later still): **EotW content split into its own local-assets directory, and the publisher taught to read it.**
  - **Local-assets mode is ON for the authoring game.** `dmhub.LocalAssetsStatus()` reports `active: true` with dirs `C:\dev\eotw` (1, top) and `C:\dev\dmhub\draw-steel-codex\data` (2). This is why an earlier pass concluded the week's encounter document "did not exist": the engine replaces `/GameDetails/{gid}/assets` with the YAML trees and intercepts every asset write, so the game store froze and the document is a file on disk, not a row in the store. Nothing was lost.
  - **Moved to `C:\dev\eotw`** (the only two EotW-authored files in the shared repo, confirmed by an 8-agent sweep over 6627 yaml files): `objectTables/documents/room-1.yaml` (the week's encounter, `645e4522`) and `objectTables/environmentalkeywords/start.yaml` (the Start keyword, `47ea72f9`). Both had been swept into `draw-steel-data` by a bulk export commit, not curated in. Their `_meta.yaml` container files were copied alongside so the table ids resolve (`environmentalkeywords` folder -> `environmentalKeywords` table). The deletions in the `draw-steel-data` submodule are STAGED, NOT COMMITTED -- restore with `git -C draw-steel-codex/data checkout HEAD -- <paths>` if the move needs undoing.
  - **Deliberately NOT moved**: `goblin-guards-combat.yaml` (venla-deliantomb content from April, present in 14 games -- EotW only republished a fork), the encounter's monsters (Great Library bestiary), and the other environmental keywords (this week's map itself paints Concealing/Water/Difficult Terrain/Lava, all shared).
  - **There are TWO "Start" keywords.** `27f8df28` shipped in module v4 and lives only in the frozen game store; `47ea72f9` is the file in the assets tree and is what this week's map actually paints. EotW resolves the keyword by NAME (`EncounterOfTheWeek.lua:191`), so the mode works against whichever the overlay supplies -- but the publisher must not ship the stale one, and now does not.
  - **Publisher gained `--assets-dir`** (repeatable, highest precedence first) plus `tools/eotw_publish/localassets.py` and `coreassets.py`. Three non-obvious requirements, all found the hard way: the overlay REPLACES the store's assets rather than merging (merging resurrects the stale Start keyword); Core + `mcdm-drawsteel` guids must be excluded from the dependency universe the way ModShare's `knownAssetsInCore` does, or the closure goes from ~60 guids to ~700 and the payload from 17 KB to 3.1 MB; and table ids come from `_meta.yaml`, never the (lowercased) folder name. Also: DMHub writes vertical tabs into document text, which PyYAML's loaders reject outright -- libyaml first, tolerant pure-Python loader on failure.
  - **Verified**: with both dirs, the publisher now finds the encounter document ("Room 1", islands: `encounter` with 10 monsters), ships keyword `47ea72f9` and not `27f8df28`, 68 guids, 15.8 KB streamed, no warnings -- it would publish. The v4 regression (run WITHOUT `--assets-dir`, against the frozen store) is unchanged: every key set and value matches except the four tokens added to the map since and one `_ntilesRefreshed` counter.
  - **Dry run reviewed in depth (same day).** Two real defects found and fixed in the tool, one real defect found in the DATA:
    - `coreassets.py` was reading only `/CoreAssetsCurrent` (17 objects). Core is two-tier -- `/CoreAssetsArchive` (1499 objects, 788 images, 322 monsters) plus that overlay, merged by `CloudAssetManager.CoreAssetsUpdate`. Now reads both; the core set went 5726 -> 9922. (The exclusion count did not move: `mcdm-drawsteel` already covered everything the trees hold.)
    - New reference-resolution check (`payload.asset_references`): every asset the shipped map and its encounter point at -- placed objects' `assetid`, painted tile/wall ids, zone keywords, bubble docids, and the monster ids an `[[encounter]]` island would spawn (including per-hero-count `balancing` entries) -- must resolve in the payload, Core, or a dependency module. Deliberately a curated key list, not a guid-shaped-string sweep, which would flag object-instance/zone/bubble ids that resolve to nothing by design.
    - **DATA DEFECT, UNFIXED: the Encounter map's art object `5939fe95-d642-467f-83f5-e02bb13d1e4a` (`GL_OvergroundDwarvenCityCenter_Original_Day`) resolves nowhere** -- not Core (neither tier), not any installed module, not either assets tree. It exists only in the frozen game store, which local-assets mode no longer loads. The publisher now refuses to publish over this. Likely already visibly broken in the app; verify by opening the map. Cause: switching local-assets mode to point at the shared codex repo (already populated, so no bootstrap export ran) orphaned the game's own asset table. The frozen store's other rows are fine -- all 7 audio assets resolve from Core, and the two objectTable rows are duplicated in the trees.
    - The encounter's 6 distinct monsters all resolve from Core, so they need no shipping.
  - Still not committed to git anywhere; still never actually published (`--publish` has never been run).
- 2026-08-30 (later): **Encounter-document discovery rewritten to mirror the runtime, and this week's map diagnosed.** New `tools/eotw_publish/documents.py` ports `FindMapEncounter` / `GetEncountersOnCurrentMap` / `GetReferencedAnnotations` / `GetTextContent` / `IsDocInAccessibleRoot`; the publisher now finds documents via info bubbles on every floor as well as the `parentFolder` chain, resolves them against the merged game+module table, and tests for a *referenced* `RichEncounter`. Regression test against v4 still passes (`objectTables.documents MATCH`, values identical), and on last week's map the rule reports all three reachable documents and correctly picks "Goblin Guards Combat" (islands: `encounter` 8 monsters, `encounter:round2` 4) while ignoring the two module-owned ones with no encounter.
  - **THIS WEEK IS BLOCKED BY LOST DATA, not by the publisher.** The Encounter map (`8d78cadf`) has one info bubble (`c64e02d1`, default name "Room 1") pointing at document `645e4522-ffeb-473f-9951-b23ace73edb2` -- **and that document does not exist anywhere**. Verified exhaustively: it appears exactly once across all 299 stores of the game's SQLite (the bubble itself), and is absent from 81 local game databases, 25+ backups of this game, 228 cached module payloads, all six installed modules' Firebase records, 8 versions of mcdm-drawsteel, all four published EotW versions, and both core-asset trees. Time-aligned backups pin it: the map backup written at `2026-8-30-5-27-37` has the bubble, and the game backup from the same instant still has only `04eae049` in `documents`. **The encounter document must be re-authored.** The rest of the map is ready -- art, 18 markup zones (the Start zone), no tokens, exactly as designed.
  - **Engine bug found (unfixed):** `CreateInfoDocument` (`InfoDocument.lua:34-58`) writes the bubble to the floor and the document row to the asset table separately, so abandoning the create dialog leaves a bubble whose docid resolves to nothing -- and clicking it is a silent no-op (`InfoDocument.lua:843` guard falls through; `InfoBubbleController.cs:94-113` never validates the docid). That is almost certainly what happened here.
  - **Latent risk recorded as a publisher warning:** `dmhub.infoBubbles` is gated on `isDMVision AND (isDM OR map:playerinfobubbles)` (`InfoBubbleController.cs:60-72`), and an EotW host runs with `isDM == false` outside a `hostPermission` block. If that gate closes, `FindMapEncounter`'s bubble route collapses and only the `parentFolder` route survives -- so the publisher now warns when the encounter document is reachable *only* via a bubble. Last week's document was reachable both ways, which is why v4 worked; this is unverified live and worth settling by running `for k,v in pairs(dmhub.infoBubbles) do ... end` as the EotW host.
  - Also fixed: `name_for` read `doc.name`, which is never serialized (Lua-side alias for `description`, `DocumentSystem.lua:25`), so document names degraded to bare guids in the report. The stale "no journal document is filed under this week's map" warning was replaced -- it was wrong in both directions (a leftover "Room 1" would satisfy it with no encounter present, and it fires spuriously whenever the encounter document is module-owned, which is the normal case for an imported adventure map).
- 2026-08-30: **Weekly publishing automated** (`tools/eotw_publish/`, Phase 5 step 19b; NOT committed to git yet). `publish_eotw.py` + `gamesource.py` + `depsearch.py` + `payload.py` + `README.md` republish `mcdm-encounteroftheweek` with the app closed. Design and every gotcha are in "Publishing the weekly module headlessly" (Architecture Notes) and the tool's README; the load-bearing facts:
  - The authoring game `e96656f3-...` is a **Local** game (`storage == 3`), so its data is a SQLite file on this machine, not in Firebase or a Durable Object. The script copies it and runs the bundled `local-game-server-windows.exe` against the copy rather than reimplementing the shard layout.
  - The map is found **by name**, because the id rotates weekly (v4 shipped `05ac910d`, which the user has since renamed "Goblin Guardians"; this week's `Encounter` is `8d78cadf-03cc-42f1-8c45-8764021b5fb6`). The 9 pregens are identified by pregen party `7870ffcb-c942-4db9-a831-bf0210aa11ea`, matching v4's ticked set exactly.
  - Verified against published v4: all key sets match, all shared values byte-identical. Only real drift differs (4 tokens placed on the map since, one floor's `_ntilesRefreshed` counter).
  - **Current blocker, surfaced by the tool**: this week's `Encounter` map (`8d78cadf-...`) has **no journal document filed under it**, so there is no encounter for the game-side Lua to spawn, and the script refuses to publish. This is the same step 17 gap, now on the new map. The author needs to write the encounter document with `parentFolder` set to `8d78cadf-...`.
  - The floor scan (an improvement over the engine's walk, which never sees floor contents) found one dependency the app would have missed on this map: the `GL_OvergroundDwarvenCityCenter_Original_Day` object asset.
- 2026-08-27: Plan written; architecture survey done (notes above). `/week` skill created at `.claude/skills/week/SKILL.md` (repo root).
- 2026-08-27 (later): **Phase 1 complete and verified in the app** (harness boot at the real titlescreen; link clicked, shell opened/closed/reopened; setting toggled both ways live; no console errors).
  - Files: `Codex Titlescreen/EncounterOfTheWeek.lua` (new -- setting, `EncounterOfTheWeek` global, screen shell; registered in the Codex Titlescreen codemod at position 1, before `CodexTitlescreen.lua`); `Codex Titlescreen/CodexTitlescreen.lua` (the link button, id `eotwTitlescreenLink`); `EncounterOfTheWeek/EncounterOfTheWeek.lua` (now an intentionally-empty stub reserved for game-side logic -- its old copy of the code was moved out because separate codemods do not load at the titlescreen; see Architecture Notes).
  - The engine's registered file list is in Firebase (persistence confirmed); the checked-in `main.lua` was not regenerated by the app and still lacks a require line for the new file -- expected, the Firebase list is what the app loads.
  - The old `EncounterOfTheWeek_1428` codemod registration cannot be trimmed of its file entry yet: CodeMod delete-file exists in Lua but its C# half needs an engine build. Harmless -- the stub loads and does nothing.
  - `dev:encounteroftheweek` left ON on the dev machine so the link is visible.
  - Changes are deployed (gitfolder = this repo) but NOT committed -- commit when ready.
- 2026-08-27 (later still): **Lobby decision recorded and plan restructured.** The lobby is a new first-class Lobby concept (its own DO type + C# connection interface), NOT a special game. Phase 2 is now "design + deploy the Lobby backend" (server-only, staging), Phase 3 is the C# lobby interface + EotW screen integration; later phases renumbered (games 4, module 5, launch 6). Document rewritten accordingly; no code written for this yet.
- 2026-08-27 (same session): **Arbitration model decided and recorded.** The Lobby DO acts as a server: clients read via `subscribe` only and mutate nothing directly; all mutations are typed requests the DO validates and applies (create-game gated on one-registered-game-per-user, join-game gated on public + open slots, chat stamped/capped/trimmed server-side). Two-layer create/join sequence (lobby request brackets the engine-side `lobby:CreateGame`/`lobby:JoinGame`) sketched with reservation timeouts; exact op set + envelope to be pinned in the Phase 2 design pass. Old connection-route discussion removed from the doc as fully superseded.
- 2026-08-27 (same session, later): **Phase 2 design parameters decided**: request envelope (`{type:"request", action, args, reqId}` -> `ack` with result payload); chat rate limit (8-token bucket per user, one token per message, 15s regen per spent token); 400-char message cap; self-reported display names; roster liveness (clients heartbeat their game every 60s, DO expires records + unconfirmed reservations after 5 minutes without activity, lazy sweep/alarm -- no setInterval). Recorded in the Lobby architecture section; this also resolved the stale-roster-cleanup open question.
- 2026-08-27 (same session, later): **JWT auth verified in code** (read-only agent pass over `cloudflare-game-server/src/index.ts`): token validation is REAL -- RS256 signature vs Google certs + iss/aud/exp (`verifyFirebaseJwt`, `index.ts:221-264`, called at `:5055`), userId taken from the verified `sub`. The "auth is stubbed" line in `cloudflare-game-server/CLAUDE.md` is stale and should be corrected. Staging caveat: `ALLOW_UNAUTHENTICATED_DEV = "true"` in `wrangler.toml` staging vars accepts tokenless connections with self-reported userIds (supplied tokens are still verified); release accepts verified tokens only. `local-game-server` trusts the client by design (local only). Conclusion: the arbitration model can rely on server-side identity on release; nothing blocks implementation.
- 2026-08-27 (same session, later): **Lobby DO implemented and locally verified** (Phase 2 steps 4-6 done, step 7 half done). Files: `cloudflare-game-server/src/lobby-core.ts` (pure arbitration logic), `src/lobby.ts` (`LobbyObject`), `src/types.ts` (request envelope + ack.result + auth displayName), `src/index.ts` (LOBBY binding on Env, `/lobby/` + `/api/lobby/` routes, exported `verifyFirebaseJwt`/`validatePath`, re-exported `LobbyObject`), `wrangler.toml` + `wrangler.dmhub.toml` (binding + migration v3, release + staging), `test/lobby-core.test.ts` (20 unit tests), `test/lobby-smoke.ts` (scripted 2-client verification). Full suite green (239 tests), tsc clean, smoke ALL PASSED against local `wrangler dev --env staging`, persistence verified across a runtime restart. NOT committed yet.
- 2026-08-27 (same session, later): **Staging deploy done by the user; smoke test passed against staging. Phase 2 COMPLETE.**
- 2026-08-27 (same session, later): **Phase 3 client side implemented** (steps 8-11 details inline above). Engine: `Assets/Scripts/LobbyConnection.cs` (new), `Assets/Scripts/LobbiesLua.cs` (new), `Assets/Scripts/ScriptEngine.cs` (one-line `lobbies` registration) -- NEEDS ENGINE BUILD, none of it committed. Codex: `Codex Titlescreen/EncounterOfTheWeek.lua` rewritten (lobby-wired screen, luac-clean, deployed -- gitfolder is this repo), `Definitions/lobbies.lua` (new stub). UNTESTED live.
- 2026-08-27 (same session, later): **Phase 3 verified live by the user** after the engine build (one fix: engine interface methods need colon calls -- `lobbies:Connect`, not `lobbies.Connect`; stub updated to match). Presence + chat working against the staging `eotw` lobby. Phase 3 COMPLETE.
- 2026-08-27 (same session, later): **Phase 4 create/join implemented** (steps 12 done, 14 partial -- details inline above; steps 13/15 untouched). All in `Codex Titlescreen/EncounterOfTheWeek.lua` (luac-clean; gitfolder = repo, so live on reload): create dialog, Join/Enter/Leave/Abandon row buttons, games error line, 30s member heartbeat think. Lua-only -- no engine change, no build needed. UNTESTED live.
- 2026-08-27 (later session): **Hero slots + private game chat + pregen cache built** (steps 13 and 14 done; details inline above).
  - **Server** (`cloudflare-game-server/`): `lobby-core.ts` -- `LobbyHero`/`LobbyPlayer.heroes` model, `sanitizeHeroes` (max 4/player, kind lobby|pregen, 60-char display caps, `{}` accepted as empty list), `applyJoinGame` reworked (membership + optional heroes; no slot gate on joining), new `applySetHeroes`, `applyGameChat` + shared `appendChatMessage`, `isGameMember`. `lobby.ts` -- `gamechat` storage (`gamechat::{gameid}::{msgid}` rows, constructor orphan reap), per-client filtered snapshots (`fullDocFor`), member-filtered broadcasts, backlog put on join/confirm, null put to leavers, purge on record drop. Tests: `lobby-core.test.ts` now 26 tests; `lobby-smoke.ts` extended (3rd client proves non-member exclusion + backlog-on-join). Full suite 245 green, tsc clean, smoke ALL PASSED against local `wrangler dev --env staging`. **STAGING DEPLOY PENDING (user action -- `npm run deploy`; the machine's wrangler auth targets the wrong Cloudflare account and the deploy command is permission-gated for Claude). Until deployed, the client degrades gracefully: set-heroes shows "Unknown action", game-chat sends land in lobby chat.**
  - **Engine (NEEDS BUILD)**: `module.DownloadModuleSnapshot` -- `Assets/Scripts/Module.cs` (Lua API next to DownloadModuleInfo) + `Assets/ModuleManager.cs` (`DownloadModuleSnapshotCo`: compatible-version pick, disk-cache-first, GCS-then-Firebase). Stub added to `Definitions/module.lua`. Until built, the pregen picker section shows "not available" (safe nil probe).
  - **Codex** (`Codex Titlescreen/EncounterOfTheWeek.lua`, luac-clean, live via gitfolder): pregen cache (eager, 5s after load + on ShowScreen), game lobby view (slots/picker/controls; the back button was later removed -- see step 14), chat column channel switching (`/gamechat/{gameid}` when viewing a game, input sends `gameid`), `/gamechat` monitor routing, create/join flows land in the view.
  - **Verified in the harness** (real titlescreen, staging lobby with the OLD server): screen renders, create flow lands in the game lobby view (slots list, Game Chat title, "<< All Games" back button), Add Hero picker lists lobby heroes with class names, old-server `set-heroes` rejection surfaces cleanly in the error line, Abandon drops back to the list with "That game is no longer available", no new console errors. Discovered UI nit (unfixed): ShowCreateDialog does not guard against being opened twice, so double-clicking Create Game stacks two dialogs.
  - Live-testing fixes (same day, engine built by the user): the published module's real fullid is **`mcdm-encounteroftheweek`** (not codex-...; doc updated throughout, `PREGEN_MODULE_ID` fixed -- the original id failed with "Module not found"). The snapshot contains EVERY module character (map monsters, blank strays), so `CachePregens` filters on `tok.properties:IsHero()` -- verified live: exactly the 5 authored pregens (Dwarf Fury, High Elf Tactician, Orc Conduit, Polder Elementalist, Polder Shadow) with class names. Create dialog now prefills "<display name>'s Game". NOTE: `STARTING_MODULE` is still `mcdm-startermap`; Phase 5's swap target is `mcdm-encounteroftheweek`, which now exists.
  - Next steps: user deploys the lobby server to staging (`npm run deploy`, then `npx tsx test/lobby-smoke.ts` against staging) and builds the engine; then verify the full slot flow live with two clients (heroes appear in slots, private chat isolation). Then step 15 (host kick + Begin gating at 3-7 filled slots) and Phase 5 (author the module + pregens -- also unblocks swapping STARTING_MODULE off mcdm-startermap). Side effect of testing: engine games created on staging during EotW tests accumulate in the account (an Abandon only drops the lobby record).
- 2026-08-27 (later session): **Phase 5 inspection pass** against the published module (snapshot version 1, dataid `ad18b21e-ed66-4f40-9c82-0bc4dbc8281b`), via `module.DownloadModuleSnapshot` in-app plus direct Firebase reads. Results folded into the Phase 5 step list above: steps 16 and 18 VERIFIED; step 17 PARTIAL (map + Start zone good; all monsters despawned -- empty encounter -- plus 2 blank stray "Monster" tokens); step 19 NOT MET (Monster AI codemod not bundled, only the EotW stub codemod). Deliverable not yet met; fix is in-app (rebuild encounter, delete strays, tick Monster AI, republish v2), then swap `STARTING_MODULE`.
  - **v2 lobby server confirmed live on staging** (doc endpoint shows the `gamechat` key; two accounts have chatted in the `eotw` lobby), so the Phase 4 staging-deploy blocker is cleared.
  - **Pregen cache bug found + fixed + deployed** (`Codex Titlescreen/EncounterOfTheWeek.lua`): the eager boot-time `CachePregens` (5s after load) can run before the codex rules defining `IsHero` are loaded, so every pcall probe fails, and it then committed an EMPTY pregen list permanently (m_pregens ~= nil blocks all retries) -- the picker showed no pregens for the whole app run. Fix: a snapshot yielding zero heroes is no longer committed; m_pregens stays nil so the next GetPregens/ShowScreen retries. Verified in-app after reload: 5 pregens with classes. NOT committed to git yet.
- 2026-08-27 (same session, later): **Module v2 verified; STARTING_MODULE swapped; step 15 implemented.**
  - The user republished the module (version 2, dataid `c0805b51-98f3-4256-8b64-8ef41b78e8dd`): Monster AI codemod now bundled (step 19 done), pregens now 8 (Human Censor/Null/Talent added). **Step 17's encounter gap remains**: the map's 5 monster characters are still despawned (goblins carry 9 damage -- a played-out fight). The intended encounter was located in the source game's journal: "Goblin Guards Combat" -- 6 goblin warriors + round-2 reinforcements (2 warriors, 2 goblin assassins), hero-count adjustments, `[[encounter]]` islands with Place on Map. Neither the doc nor an encounter asset ships with the module. Details in the step 17 entry.
  - `STARTING_MODULE` in `Codex Titlescreen/EncounterOfTheWeek.lua` now `mcdm-encounteroftheweek` (was `mcdm-startermap`).
  - Step 15 (host kick + Begin gating) implemented server + client; details in the step 15 entry. Local wrangler smoke ALL PASSED (incl. new kick checks); unit suite 247 green; Lua luac-clean and live via gitfolder. **Pending: user runs `npm run deploy` (staging), then live 2-client verification of kick + Begin.** Live UI verification was not possible this session -- the app was inside the Delian Tomb source game, not at the titlescreen (reload produced no console errors, so the new screen code at least loads cleanly).
  - v2 lobby server (hero slots + game chat) confirmed deployed on staging earlier in the session (doc endpoint shows `gamechat`).
- 2026-08-27 (same session, later): **Phase 6 direction decided and recorded** -- programmatic encounter spawning ("option 2"), with the game-side coding starting in the EotW stub codemod. New Phase 6 step 20 is the next implementation task: on entering an EotW game, place the heroes in the Start zone, set the "Number of Heroes" setting, find the encounter in the map's journal documents, and spawn it with hero-count scaling. Full scope, research pointers (EncounterPanel spawn machinery), and the module-republish prerequisite (ship the journal doc + encounter asset) are in the Phase 6 section; old steps 20-23 renumbered 21-24, unchanged. The next session starts here.
- 2026-08-27 (later session): **One-EotW-game-per-account built** (design + full implementation; resolves the CAMPAIGNS-list open question -- see the new "One EotW game per account" Architecture Notes section for the complete design). Server: `POST /admin/delete-game/{gameId}` route + `GameObject.handleDeleteGame` (socket close 1001/"game-deleted", `storage.deleteAll()`, alarm cancel, abort -> platform deletes the DO), sharing bulk-upload's owner/DM auth; `test/delete-game-smoke.ts` ALL PASSED against local wrangler dev, suite 247 green, tsc clean -- **DEPLOYED to staging** (version c783484f; route probed live: GET -> 405, unauthenticated POST -> 401). Engine (NEEDS BUILD, uncommitted): `AccountInfo.eotwGame` slot; `CreateGameCo` `accountSlot="eotw"`; GamesMonitor slot pull + deleted/kick slot cleanup; `lobby.eotwGameid` / `lobby:JoinGameEotw` / `lobby:ClearEotwGame`; `LuaGameInfo:DeleteAndReleaseStorage`; `DeleteGameStorageCoroutine`; `DOConnection` terminal handling of the "game-deleted" close reason. Codex Lua (live via gitfolder, luac-clean): titlescreen create/join record into the slot + destroy-previous flow + create-dialog warning + resume row + stale-slot clearing; game codemod keeps the numheroes setting when resuming (nil numHeroes). LuaLS stubs updated (`Definitions/lobby.lua`, `Definitions/LuaGameInfo.lua`). **UNTESTED live end-to-end** -- needs the engine build + staging worker deploy, then: create game A, create game B (A's lobby record dropped, A marked deleted, A's DO rows gone via `/api/{A}/raw-rows`), resume row shows B after app restart, Resume re-enters B without re-clamping numheroes, and a second client in A gets the terminal disconnect + its slot self-clears.
- 2026-08-27 (later session): **Step 20 (spawn-into-map flow) implemented; spawn + pregen paths verified live in the source game.** Three research passes (spawn machinery, module content shipping, hero transfer/clipboard/arrival semantics) folded into Architecture Notes: new "Hero transfer into the game" section, expanded Encounter-spawning bullet, and "How journal documents ship" under Module + codemod bundling (this also RESOLVED step 17's research item: tick the doc under Compendium > "documents"; no encounter asset exists or is needed -- islands embed the encounter by value). Implementation + verification details inline in step 20. Key discoveries: the Lua token clipboard was single-slot (engine gained batch copy/paste APIs -- NEEDS BUILD; titlescreen degrades to one hero until then); pregens need no transfer (module characters are already in the game; same-game copy/paste duplicates one onto the map); `SpawnGroupForReal`'s name numbering had a latent every-monster-named-"1" bug (fixed with per-token `UpdateCharacterTokens`, matching the journal island's spawn). Setup is an EXPLICIT handoff (`SetupOnArrival` from the Enter World arrival callback, `rawget`-resolved) so the source game can never auto-spawn. Not committed to git; Lua is live via the gitfolder. Next: user ticks the doc + deletes despawned strays + republishes (step 17), builds the engine, then live end-to-end via the EotW screen (fresh game, lobby heroes, second client); then step 21 (Begin) and 22 (positioning stage).
- 2026-08-27 (later session): **"<< All Games" back button removed** (user decision): the game lobby view has no back button -- the only way back to the games list is leaving the game (player Abandons/Leaves, host cancels). `RefreshGames` now collapses the Create Game button while the view is open instead of relabeling it; the button's click is create-only. Follow-up in the same session: **the game lobby view no longer needs a scrollbar** -- the lobby row grew 740 -> 800 (the 1080-logical screen has the headroom), and `RefreshGames` now sizes the list per mode (`100%-100` in game view, reclaiming the collapsed button's space; `100%-160` in list mode). Game-view budget: ~700px available vs ~610px for a full 7-slot roster + 2 no-hero rows + controls. `Codex Titlescreen/EncounterOfTheWeek.lua`, luac-clean, live via gitfolder + reload; visual check pending (the MCP-connected instance was inside a game, not at the titlescreen).
- 2026-08-27 (later session): **Step 21 (Begin -> launch) implemented; "Enter World" button removed** (user decision: Begin is the only way into the game -- it enters ALL joined players at once). Server: `launch-game` action (`applyLaunchGame` in `lobby-core.ts`, `MIN_HEROES_TO_LAUNCH = 3`, dispatch + header docs in `lobby.ts`); unit suite 249 green, tsc clean; `lobby-smoke.ts` gained step 8c and ALL CHECKS PASSED against local `wrangler dev --env staging`. Client (`Codex Titlescreen/EncounterOfTheWeek.lua`, luac-clean, live via gitfolder): Begin sends `launch-game` (errors to the games error line); new `CheckLaunchedGames` at the top of RefreshGames auto-enters any launched game the user is a member of via the step-20 EnterWorld flow (uniform for host/joiners/observers; `m_enteringWorld` double-entry guard); the per-member Enter World button is deleted (the resume row keeps EnterWorld internally for re-entry). **Pending: user deploys the lobby server to staging (`npm run deploy`) -- until then Begin gets "Unknown action" -- then live 2-client verification: host Begins, both clients auto-enter, heroes land in the Start zone, encounter spawns at the right scale.** Also still outstanding from earlier steps for a real end-to-end: the engine build (batch clipboard + eotw slot APIs) and the module v3 republish with the Goblin Guards doc ticked (step 17).
- 2026-08-27 (later session): **First live 2-client Begin analyzed; two placement bugs fixed, one engine gap diagnosed.** The user ran Begin with two clients into game `DeathlessChainedSuperiorOrc` (staging): both entered, heroes placed, 2 Goblin Warriors spawned (correct 3-hero scale). Defects:
  - **Heroes stacked on one tile** (the joiner's two pregens both at the Start-zone anchor). Root cause: separate paste calls cannot see each other's tokens until `UpdateCharacterTokens` runs (`charactersByLoc` only tracks live token objects). FIXED in `EncounterOfTheWeek/EncounterOfTheWeek.lua` (`PlaceMyHeroes` now updates tokens after each paste); design details folded into "Hero transfer into the game". Cross-client anchor race noted there and accepted for now.
  - **All placed heroes were party-owned, not player-owned**: the `partyId` setter force-writes `ownerId = "PARTY"`, clobbering the claim. FIXED (partyId set before ownerId in `ClaimPastedHero`); gotcha recorded in "Hero transfer into the game".
  - **Joiner "connectivity trouble"** = endless Firebase `Permission denied` retries from the joiner running the starting-module install (simultaneous-entry race) plus the non-owner contentSummary sweep -- full analysis + proposed engine fixes in the new "Joiner-side module install race" Architecture Notes section. ENGINE FIX PENDING (user decision needed; needs build).
  - Live game repaired in place via MCP: correct owners restored on all three heroes (attributed via the `eotwstate` doc) and the stack separated (`ref.loc:dir()` used to keep the floor -- see the Loc gotcha bullet). Lua fixes deployed (gitfolder = repo) and reloaded on the host instance; not committed to git.
  - Also observed on the host: repeated "FLOORS:: floor data missing from server" for the two floors of the stray "Test" map (the vextestmodule auto-install artifact) -- noise, tracked separately from EotW.
- 2026-08-27 (later session): **Engine permission fixes + "ready to go" launch signal implemented** (user decision: members only join once the host has initialized the game and signaled ready).
  - **Server** (`cloudflare-game-server/`): new `ready-game` action -- host-only, record status "launched" -> "ready", idempotent re-ready, roster stays frozen; `LobbyGameRecord.status` union gains "ready". Files: `src/lobby-core.ts` (`applyReadyGame`), `src/lobby.ts` (dispatch + docs). Tests: `lobby-core.test.ts` +3 (suite 252 green, tsc clean); `lobby-smoke.ts` step 8d -- **ALL CHECKS PASSED against local `wrangler dev --env staging`** (note: the smoke script defaults to LIVE staging unless `LOBBY_BASE=http://localhost:PORT` is set -- an un-prefixed run against staging correctly showed "Unknown action: ready-game" since staging predates the action). **STAGING DEPLOY PENDING (user: `npm run deploy`) -- REQUIRED before live-testing the new client: without it the host's ready signal gets "Unknown action" and waiting members never enter.**
  - **Engine (NEEDS BUILD)**: the three fixes recorded in "Joiner-side module install race" (DM-only starting-module install; owner-only contentSummary write; 401/403 = no retry in `WriteDataCo`). Files: `Assets/Scripts/GameController.cs`, `Assets/Scripts/DataStore.cs`.
  - **Codex Lua** (luac-clean, live via gitfolder; the titlescreen file needs an app RESTART, not a reload -- the titlescreen builds once per app run): `Codex Titlescreen/EncounterOfTheWeek.lua` -- `CheckLaunchedGames` enters the host on "launched"/"ready" and members on "ready" only; the game view shows "the host is setting up the encounter" to waiting members ("Entering the game..." on ready); Begin comment updated. `EncounterOfTheWeek/EncounterOfTheWeek.lua` -- `SignalGameReady()`: host-side, runs at the end of `SetupOnArrival` (even when the spawn fails, so members are never stranded), opens its own `lobbies:Connect("eotw", {staging=true})` (the titlescreen's connection died with the screen; requests do NOT queue pre-auth, so it polls `conn.connected` up to 30s), sends `ready-game`, logs + disconnects on ack; a resume with no roster record gets a harmless "not registered". `Definitions/lobbies.lua` action list refreshed (was missing set-heroes/kick-player/launch-game too).
  - Known edge (accepted): if the host crashes during setup, the record stays "launched" and waiting members' heartbeats keep it alive -- they wait until they Leave. Revisit with step 22 if it bites.
  - NEXT: user deploys the lobby server to staging, builds the engine, then live 2-client test: Begin -> host enters alone -> members see the waiting note -> members auto-enter on ready -> no stacking, correct per-player ownership, no Permission-denied spam in the joiner's log.
- 2026-08-28: **Automated combat entry + Monster AI auto-run + no-Director presentation built** (user direction this session: when everyone is in, enter combat -- heroes and monsters -- with the normal Draw Steel roll; the AI plays the monsters; nobody, host included, is a Director; lean on leafy EotW code + named core hooks + the new Map Script concept). Steps 23-24 done, step 22 deferred; full design in the new "Automated combat entry + no Director" architecture section. All Lua, NO engine change, nothing committed to git (gitfolder = repo, so edits are live on reload).
  - Files: `Draw Steel UI/DSInitiativeRoll.lua` (`Encounter.StartCombatWithTokens`), `DMHub Core UI/Hud.lua` (`GameHud.RegisterDirectorUIFilter`/`DirectorUIVisible`), `DMHub Core UI/DockablePanel.lua` + `DMHub Game Hud/GameHud.lua` + `Draw Steel Core Rules/MCDMInitiativeBar.lua` (Director-chrome gates converted to the hook), `Monster AI/MonsterAIPanel.lua` (StartAI/StopAI/IsAIRunning exports), `EncounterOfTheWeek/EncounterOfTheWeek.lua` (IsEotwGame, eotw:showdirectorui setting, Director-UI filter, arrival tracking, map-script builtin + attach, MapScriptHostThink state machine, ClearEotwMarker), `Codex Titlescreen/EncounterOfTheWeek.lua` (EnterWorld passes `members`).
  - Verified so far: all files luac-clean + ASCII-clean; full Lua reload in the running app (44 mods) with ZERO new console errors -- in an actual EotW game (`GargantuanHauntedIndignantAborrath`, this account's eotw slot): `IsEotwGame()` true, the Director-UI filter registered, `Encounter.StartCombatWithTokens` and `MonsterAI.StartAI` both present. That instance is signed in as the player account, so host-side behavior was NOT exercised.
  - ~~BLOCKER: MapScript.lua not registered~~ **RESOLVED (2026-08-28, same day)**: with the dev account signed in, `register_lua_file "Draw Steel Core Rules/MapScript.lua"` (after MCDMEncounter) succeeded -- position 65, Firebase persistence confirmed -- and a reload (48 mods, zero errors) loaded it. **The MapScript runtime is now live-verified for the first time** (in `CosmicMammothRidiculousSailor`, single client): a temporary inline script attached via SetAttachedRecords was picked up by the driver, the host election elected the client, think + hostThink ticked on schedule, `ctx:ModifyShared` round-tripped, `ctx:RunOnce` fired exactly once across ~30 host ticks, and detaching the record stopped all ticks. (The `builtin:eotw-encounter` builtin naturally does NOT appear in games without the EotW codemod -- it registers where the codemod loads.)
  - **First solo end-to-end run (2026-08-28, game `ComposedSlivyFabledMemonek`): the automated flow WORKED** -- map script attached, ready signaled, all-arrived gate passed, and the console shows "EotW: Draw Steel! 3 heroes vs 2 monsters" with combat + Monster AI running. One defect found and fixed: the third hero appeared "missing" -- actually STACKED on the anchor tile (pregen paste could not see the batch-pasted lobby heroes). Root cause: the local game mirror is updated asynchronously by the server echo, so the 2026-08-27 update-between-pastes fix was ineffective; real fix is `WaitForPastedCharacters` in `PlaceMyHeroes` (details in the corrected "Paste vacancy" bullet under Hero transfer). Live game repaired (Censor teleported off the stack); fix deployed + reloaded cleanly but NOT yet re-verified with a fresh game entry. Also added `EncounterOfTheWeekGame.DebugGetState()` (dev helper: inspect the eotwstate doc from the console/MCP).
  - Then the live 2-client test (stacked on the still-pending engine build + module v3 republish from earlier sessions): Begin -> host enters, spawns, attaches the map script, signals ready -> members enter -> on the last arrival + 3s, the Draw Steel banner appears for everyone -> any player rolls the die -> combat starts with all heroes + monsters -> AI plays monster turns -> host sees NO Director chrome (player dock layout, no dmonly panels, no DM strips) -> after combat ends the AI stops. Watch for: the host's numeric `permission:playersinitiative` write, double-banner or double-queue (should be impossible via RunOnce), and any cast-pipeline oddity on the host now that its chrome is player-styled (isDM itself is untouched, so none expected).
- 2026-08-28 (later session): **Loading screen on entry built + verified** (user
  request: entering the game should put up a loading screen like other games, same
  transition style, for every connecting player, cleared only once fully loaded).
  Lua-only, one file: `Codex Titlescreen/EncounterOfTheWeek.lua` -- `EnterWorld` arms
  the standard titlescreen loading screen via the `overrideLoadingScreenArt` event
  before `lobby:EnterGame` (all entry paths -- Begin/host, members-on-ready, resume --
  funnel through it); new `LOADING_SCREEN_ART` constant next to `STARTING_MODULE`
  (delian-tomb bg -- update alongside the weekly encounter); create-game now records
  it as the game's `coverart`. Full mechanism + the accepted host-side pop-in residual
  recorded in the new "Loading screen on entry" bullet under "Creating and joining
  EotW games". Verified in the running app by simulating the engine's event sequence
  (overrideLoadingScreenArt + beginLoading, then the return path) over the open EotW
  screen: the standard loading screen (Delian Tomb art, quote banner, progress die)
  mounted on top and cleared with no new console errors. `EnterWorld` is built inside
  `ShowScreen()`, so a Lua reload suffices (no app restart). The real Begin/ready flow
  exercises it in the next live multi-client test. luac-clean, deployed (gitfolder =
  repo), NOT committed.
- 2026-08-28 (later session): **Game-lobby hero slots redesigned into portrait
  cards** (user direction: horizontal cards with portraits in the character
  panel's portrait-frame style, translucent name/class/ancestry/level +
  "Controlled by X" plate, hover trash to remove, a "+" card that vanishes at 7
  heroes, fade-in entrance while the lineup separates to make room, and a
  card-GRID Add Hero popup). Full design in the new "Hero-card lineup"
  architecture section; step 14 entry updated. Files:
  - `Codex Titlescreen/EncounterOfTheWeek.lua` -- card constants + helpers
    (`GetHeroAncestry`/`GetHeroLevel`/`FormatHeroDetails`), `MakeCardPanel` /
    `MakeHeroCard` / `MakeAddHeroCard` / `ResolveHeroToken` (replacing
    MakeSlotRow/MakeEmptySlotRow; empty-slot rows dropped -- the header's
    "x/7 filled" carries capacity), BuildGameView card lineup +
    `m_knownHeroCards` new-hero tracking, picker rewritten as card grids
    (dialog 1040x740), Add Hero button removed from the control row, hero
    specs + `MyHeroesCopy` + pregen cache now carry ancestry/level.
    luac-clean; live via gitfolder; reload in the running app (49 mods) clean.
  - `cloudflare-game-server/src/lobby-core.ts` -- `sanitizeHeroes` accepts
    optional ancestry (60-char cap) / level (int 1..20) display fields
    (undeclared on the LobbyHero interface: an optional property's `undefined`
    is not a JsonValue, so they ride the index signature); +1 unit test
    (suite 253 green, tsc clean). **STAGING DEPLOY PENDING (user:
    `npm run deploy`)** -- until then the old server drops the new fields and
    remote cards show name+class only. Nothing committed to git.
  - Verified via an in-game visual mock (the connected instance was mid-game
    in `HungryPeacefulLumberingMarshal`, so the real titlescreen screen was
    not driven): cards/portraits/plates/chip correct, hover trash appears,
    born tween caught mid-animation (neighbors slide apart, card fades in),
    zero new console errors. Live titlescreen pass (game view over a real
    roster, picker grid, pregen portraits at the titlescreen, remote-player
    cards, kick icon) still pending -- needs the app at the titlescreen.
- 2026-08-28 (same session, later): **Pregen cards had no art at the
  titlescreen -- root-caused and fixed** (user rebuilt + tested the picker:
  cards render, portraits blank). Live probes confirmed the design doc's old
  caveat: the snapshot carries portrait GUIDs (`offTokenPortrait` etc. return
  them fine) but their ImageAsset records live in the version's STREAMED
  payload, registered only for modules the current game installs --
  `assets.allAssets` (5575 entries) lacked all three probed GUIDs at the
  titlescreen. Full mechanism + fix design in the new "Pregen portraits at
  the titlescreen" bullet under "Pregen heroes from the module". Changes:
  - **Engine (NEEDS BUILD, uncommitted)**: `Assets/ModuleManager.cs`
    (`EnsureModuleImageAssetsCo`, run by `DownloadModuleSnapshotCo` before
    its success callback; disk-cache/GCS/Firebase fetch of the streamed
    payload, writes the shared `module-streamed-{dataid}.json` cache) +
    `Assets/Scripts/CloudAssetManager.cs` (`HasModuleAssetStore`,
    `RegisterModuleImageAssets` -- images+imageLibraries only).
  - **Codex Lua (live via gitfolder, reload clean)**:
    `Codex Titlescreen/EncounterOfTheWeek.lua` -- `IsUnresolvableAssetId`
    (GUID-shaped + missing from allAssets; pattern verified against
    md5:/thumb:/#/path id forms), silhouette fallback in `MakeCardPanel`,
    and `EnsurePregenArt` re-registration trigger in `CachePregens` (covers
    ClearModules wiping the store on every game switch).
  - NEXT: user rebuilds the engine, restarts to the titlescreen, opens the
    picker -- pregen cards should show real portraits (first open may need a
    beat while the streamed payload downloads once; thereafter disk-cached).
    On failure, check the console for `DownloadModuleSnapshot:` warnings.
- 2026-08-28 (same session, later): **User rebuilt; still no art -- deeper
  root cause found and the proper infrastructure built.** Live tracing on the
  fresh build showed the registration fix ran once at boot but module v4's own
  streamed payload holds 2 objectTables and ZERO images -- correctly, because
  **the pregen art ships in venla-deliantomb, which v4 declares as a
  dependency** (v21, verified in Firebase; its payload carries all 18 art
  GUIDs). In-game the dependency closure loads every member's streamed assets;
  the titlescreen previously loaded none, and my first fix loaded only the
  root module's. Interim doctored-v4-cache test confirmed the registration
  chain end-to-end on the user's machine ("works now locally"); the cache was
  then restored. Built this session (all engine, NEEDS BUILD, uncommitted):
  **module art preview** -- `EnsureModuleArtPreviewCo` +
  `RegisterStreamedImageAssetsCo` in `Assets/ModuleManager.cs` (dependency
  closure via TraceDependencies, fire-and-forget after the snapshot success,
  60s in-flight stamp, `ModuleArtPreview:` log prefix) and the empty-payload
  guard in `CloudAssetManager.RegisterModuleImageAssets`. Full design in the
  "Module art preview infrastructure" bullet under Pregen heroes. NO module
  republish needed. NEXT: user rebuilds, restarts, opens the picker --
  venla-deliantomb v21's payload is already disk-cached, so pregen portraits
  should appear with no network fetch.
- 2026-08-28 (later session): **"already hosting game X" create lockout fixed**
  (user report: hosting a new game failed with `already hosting game
  SillySilentShackledElf`; expectation is the old game just gets deleted).
  Root cause: the lobby DO's `create-game` REJECTED while the requester's old
  roster record was alive, and the screen's 30s think heartbeats every hosted
  game, so the record never expired while the user was on the EotW screen; the
  client's `DestroyPreviousGame` only runs after a successful reservation.
  Fix is server-side supersession in `applyCreateGame`
  (`cloudflare-game-server/src/lobby-core.ts`): an existing hosted record is
  dropped exactly like a host leave-game (the DO's existing null-put handling
  purges its game chat and broadcasts the removal) and a live reservation is
  replaced; `ack.result.superseded` names the dropped gameid. Design bullet
  under "The DO arbitrates" updated. NO client change needed (the leave-game
  in `DestroyPreviousGame` for the already-dropped record fails harmlessly and
  its error is ignored). Tests: `lobby-core.test.ts` supersede rewrite (suite
  253 green, tsc clean); `lobby-smoke.ts` section 4 updated + new section 9b +
  section 11 checks adjusted -- ALL CHECKS PASSED against local
  `wrangler dev --env staging`. **STAGING DEPLOY PENDING (user:
  `npm run deploy` -- the deploy command is permission-gated for Claude).**
  Note the running eotw lobby DO keeps executing old code until it hibernates;
  after deploying, close the EotW screen for a minute (disconnect all clients)
  so the DO can hibernate and wake on the new code, then create the game.
  Nothing committed to git.
- 2026-08-28 (later session): **Start-zone confinement + victory/defeat
  auto-detection + player Proceed + auto-exit built** (steps 25-26; user
  direction: heroes may move only within the Start zone while initiative is
  displayed, with the zone overlay shown; the game detects victory/defeat
  itself, shows the victory/defeat screen, players may press Proceed, and
  everyone then exits to the titlescreen). Full designs in the two new
  architecture sections ("Start-zone confinement during the pre-combat phase"
  and "Victory/defeat auto-detection, player Proceed, and auto-exit").
  - **Engine (NEEDS BUILD, uncommitted)**: the Movement Restriction Mode --
    `dmhub.SetMovementRestriction{locs}`/`ClearMovementRestriction`
    (`Assets/Scripts/LuaInterface.cs`, next to the movement cross-section
    bridge), `GameController.movementRestrictionLocs`
    (`Assets/Scripts/GameController.cs`), enforcement in
    `Assets/Scripts/CharacterToken.cs` (`GetMoveCostFn` construction snapshot +
    `singleMoveCostFn` step veto; `UpdateDragging` commit backstop after the
    `canMakeMove` computation). Stubs added to `Definitions/dmhub.lua`.
  - **Core codex Lua**: `Draw Steel UI/DSVictoryScreen.lua` --
    `DSVictoryScreen.RegisterProceedOverride` + `CanLocalUserProceed`, the
    proceed click runs the override first, `ProceedEndCombat` exported as
    `DSVictoryScreen.ProceedEndCombat`, victories-section gate converted
    `dmhub.isDM` -> `GameHud.DirectorUIVisible()`.
  - **EotW codemod** (`EncounterOfTheWeek/EncounterOfTheWeek.lua`): per-client
    1s driver (start-zone confinement install/clear + `dmhub.MarkLocs` dashed
    outline + the outcome-seen -> queue-hidden -> `dmhub.LeaveGame` auto-exit,
    EXIT_DELAY 4s); proceed override registration (host falls through to the
    normal teardown, players stamp `proceedRequested`); host tick additions
    (`RecordCombatStarted` stamp, `CheckEncounterOutcome`: award
    victory/defeat via `CheckVictory`/`CheckDefeat`/all-heroes-down and execute
    relayed Proceeds). State doc gained `combatStarted` + `proceedRequested`.
  - **Verified**: all Lua luac-clean; reload in the running app (49 mods,
    zero new errors -- but that instance's game lacks the EotW codemod, so
    only the core hook loaded); `/testvictory` smoke on the live app: the
    victory screen renders with the new gates (Proceed + Victories visible to
    a Director), a registered test override intercepted the real Proceed
    click and received the default-teardown function, cleanup clean; the
    driver's exact `dmhub.MarkLocs{locs,color,style="dashed"}` call shape
    draws and destroys cleanly. NOTE: a pre-existing (not from this session)
    parse artifact exists at `Definitions/dmhub.lua:609` (luac reports it;
    stubs are LSP-only, engine never loads them, harmless).
  - **NOT verified**: the engine restriction (needs the engine build), and
    the whole flow in a real EotW game (confinement on entry, overlay
    visible, restriction lifting when the queue goes live, auto
    victory/defeat award, player Proceed relay, the 4s auto-exit on every
    client). Next live test: enter an EotW game, confirm confinement +
    overlay pre-combat and during the Draw Steel roll, fight to a win/loss,
    watch the screen appear automatically, press Proceed from a PLAYER
    client, and confirm both clients land on the titlescreen.
- 2026-08-28 (same session, continued): **first live run found two defects;
  both fixed** (Lua only, live via gitfolder, reload on the running
  instance clean -- that instance's game lacks the EotW codemod, so the
  codemod-side changes are luac-verified + load-verified only).
  1. **The victory screen appeared mid-ability-prompt.** Fix: the
     per-client ability-activity mirror + host award gate + 2-tick idle
     hold -- full design in the new "The award waits for ability prompts"
     bullet. Files: `EncounterOfTheWeek/EncounterOfTheWeek.lua`
     (`AbilityActivityInFlight`, `UpdateBusyMirror`, `AnyClientAbilityBusy`,
     the `m_awardHoldTicks` gate in `CheckEncounterOutcome`; state doc
     gained `abilityBusy`).
  2. **The finished game lingered in the lobby games list ("(launched)"
     row) and stayed in the account slot.** Root cause: nobody told the
     lobby the game ended, and a returning member's screen HEARTBEATS every
     game it occupies (30s think), so the record's 5-minute TTL never
     fired. Fix: conclusion-time cleanup, designed in the new
     "Finished-game cleanup" bullet -- game-side every client stamps the
     machine-local `eotw:concludedgame` preference and sends a lobby
     `leave-game` (via `SendLobbyRequest`, the generalized SignalGameReady
     plumbing -- SignalGameReady now wraps it); titlescreen-side
     `RefreshResumeState` destroys/leaves the finished game
     (`DestroyPreviousGame`) and clears the slot + preference. Files:
     `EncounterOfTheWeek/EncounterOfTheWeek.lua`,
     `Codex Titlescreen/EncounterOfTheWeek.lua` (setting declared in both).
  Both fixes are UNTESTED live; the next live test above now also covers:
  killing blow mid-prompt -> screen waits until the prompt resolves (~2-4s
  after idle), and after the auto-exit the lobby list shows no stale row
  and the EotW screen offers no resume of the finished game.
- 2026-08-28 (later session): **Strict rules enforcement built** (step 27; user
  direction: the "Rules Enforcement" settings that start with "Strict"/
  "Strictly" are force-enabled in EotW games). One file,
  `EncounterOfTheWeek/EncounterOfTheWeek.lua`: `g_strictRuleSettings` +
  `EnforceStrictRules()` (writes only settings not already true), called from
  the host's `SetupOnArrival` and re-asserted at the top of every
  `MapScriptHostThink` tick. Forces `strict:movement`/`strict:targeting`/
  `strict:resources`/`strict:inventory` plus the engine's
  `strictmovementrules` (judgment call -- it lives under the "Game" heading
  but matches the "Strictly..." intent; easy to drop from the list);
  `strict:hiddeninvisible` deliberately excluded. Full rationale + the
  DM-exemption/editability audit in the "Strict rules enforcement"
  architecture section. luac-clean; reload on the running instance (49 mods,
  game has the EotW codemod loaded) produced zero new errors and all five
  setting ids resolve; the actual force-on is UNTESTED in a live EotW game --
  verify on the next live run (enter an EotW game as host, open Settings >
  Game, confirm the five checkboxes are on and monsters/AI still act).
- 2026-08-29: **Player-host mode built** (step 28; user direction after
  playing EotW live: the strict settings were ON but did not bind the host --
  every strict gate exempts `dmhub.isDM` and the host keeps real DM status.
  User proposed, and directed building, `dmhub.isDMOrPlayerHost`: make the
  host a "player host" -- isDM reads false, capability sites read the new
  real check -- and audit every isDM site). Full design + the complete
  conversion inventory in the new "Player-host mode" architecture section;
  the strict-rules section and the no-Director section carry superseded
  caveats pointing at it.
  - **Engine (NEEDS BUILD, uncommitted)**: `GameController.cs`
    (`playerHostMode` field, `isDMOrPlayerHost` getter, `isDM` override,
    install-gate/PasteCharacters/camera/analytics conversions),
    `LuaInterface.cs` (`dmhub.isDMOrPlayerHost` + settable
    `dmhub.playerHostMode` with hard refresh), `CharacterInfo.cs`
    (`canControl`), `CharacterToken.cs` (prompt routing, 3 frozen gates,
    2 summon-centering, hidden-drag embargo), `CloudAssetManager.cs`,
    `LevelObject.cs`, `ObjectController.cs`, `OnePlayerStatusPanel.cs`,
    `RectSelectObjects.cs`, `GameHarness.cs`, and
    `CoreAssets/Lua/require-dc-dialog.txt` (compound prompt predicate +
    monster-save autoroll).
  - **Codex Lua (deployed -- gitfolder = repo; reload on the running app 49
    mods, zero errors)**: `DMHub Utils/Utils.lua` (the `IsDMOrPlayerHost()`
    fallback helper -- ALL codex conversions route through it, so old engine
    builds behave exactly as before; verified live on the un-rebuilt engine),
    `EncounterOfTheWeek/EncounterOfTheWeek.lua` (arming/disarming +
    host-gate conversions + escape-hatch integration), `MapScript.lua`,
    `MCDMCreature.lua`, `MCDMEncounter.lua`, `MCDMInitiativeQueue.lua`,
    `RequireDCDialog.lua`, `DSRequestRollsDialog.lua`, `DSVictoryScreen.lua`,
    `ActivatedAbility.lua`, `Monster AI/MonsterAI.lua`,
    `Definitions/dmhub.lua` (stubs).
  - Audit method: five parallel read-only agents classified all ~115 engine
    + 294 codex isDM sites (KEEP = player experience / CONVERT = hosting
    capability); I reviewed every CONVERT/UNSURE and applied ~35
    conversions. Highest-risk finds the audit caught: the starting-module
    install gate, PasteCharacters stamping the host as owner of spawned
    monsters, prompt routing deadlocking against the host's own session,
    monster-save autoroll (AI would stall on a prompt), and the map-script
    election trio.
  - **NEXT: engine build, then the live EotW test** -- as host: player
    vision/UI from arrival, strict rules now binding (movement clipped,
    unaffordable abilities refuse, invalid targets refuse, drag out of turn
    blocked), Monster AI still plays monsters (saves auto-resolve, prompts
    route to the host, election holds), no camera yanks on AI
    summons/teleports, victory teardown records battle log + roles, and
    `/toggle eotw:showdirectorui` restores the full Director view. Watch
    the first AI turn closely for any prompt/roll stall -- that is where a
    missed capability site would surface.
- 2026-08-28 (later session): **Custom interface built** (step 28; user
  direction: core hooks so a mod can usurp the game hud -- titlebar stays
  but items suppressible/addable, rails replaceable -- and EotW uses them:
  no side buttons, no Panels menu, no Compendium access, a left-edge hero
  roster with portrait/name/stamina/recoveries/heroic resource/surges/
  condition icons, own heroes grouped on top with a distinct backing, click
  pops the character panel read-only). All design + the file-by-file
  mechanism in the new "Custom interface: usurping the game hud"
  architecture section. Files: `DMHub Core UI/Hud.lua` (the hook),
  `DocumentSystem/DocumentSystem.lua` (rail takeover),
  `Codex Titlescreen/CodexTitleBar.lua` (menu suppression + additions
  host), `DMHub Core UI/DockablePanel.lua` + `DMHub Compendium/
  Compendium.lua` (panel suppression), `DMHub Utils/Utils.lua` (search
  bucket gate), `DMHub Core Panels/CharacterPanel.lua` (access override),
  `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` (NEW -- registered in the
  EotW codemod at position 2; Firebase persistence confirmed). All Lua, no
  engine change, luac + ASCII clean, live via gitfolder, NOT committed.
  Verified live in the authoring game via the new `/toggle
  eotw:forcecustomui` dev switch: takeover and release both directions
  with zero console errors (rails swap within 0.5s), roster card correct
  (portrait, stats, prone icon during a temporary inflict), character
  panel opens read-only, Panels menu gone, Compendium gone from menus and
  search (65 "goblin" results -> 0). Untested: multi-hero grouping with
  real ownership, dock-mode users, and the whole thing inside a real EotW
  game -- add to the next live-run checklist.
  - Follow-up same session (user direction): **Chat + Action Log buttons
    kept, bottom-left corner.** Core: `railBottomPanel(side)` provider
    field + bottom-corner wrappers in `BuildCustomInterfaceRails`
    (IconRailStyles on all wrappers, refreshRail cadence, chat listener
    with slash/refreshChat -- "/" opens chat during takeovers). EotW:
    `CreatePanelButton`/`CreateCornerButtonsPanel` in
    `EncounterOfTheWeekHud.lua` -- native-look rail buttons with unread
    badges + active underline, opening real rail windows via
    `DockablePanel.LaunchPanelByName`. Verified live (open with focused
    input, tabbed window, toggle, active class, clean release; zero
    errors). Residual: no chat speech-bubble preview during takeovers
    (slot-anchored); the unread badge covers it.
  - Follow-up same session (user direction): **card redesign + anchored
    character windows.** Cards are now full-bleed portraits (132x176)
    with a bottom-third semi-opaque overlay (name, unlabeled themed
    stamina bar with winded/dying tinting + temp segment, heroic-resource
    icon + surge icon with values), condition chips over the art; and the
    popped character panel opens BESIDE the clicked card via the new
    `PanelDocument.PanelWindowPlacement` +
    `ToggleCharacterPanelDocument(charid, nil, anchorPanel)` third arg
    (design in the roster/click bullets above). Verified live in a
    4-hero test game: portraits fill the cards, bars read
    correct fractions (11/18 partial, 21/21 full), icons + values render,
    the Orc Conduit panel opened level with its card to the right, toggle
    closed it; no new console errors.
  - Follow-up same session (user direction): **bar + surge refinements.**
    Card hover tooltip removed; stamina bar now 14px with the cur/max
    numbers centered in white and a glossy vertical gradient fill; temp
    stamina confirmed as a distinct accent segment at the end of the bar
    with "+N" in the numbers; surges dropped from the resource row --
    per-surge icons render in the card's bottom-right corner, none when
    zero (capped at 9). Verified live (temp+surges temporarily inflicted
    on Dwarf Fury and reverted): "27/33 +4" centered on the bar, grey
    accent temp segment at the fill's end, two corner surge icons, other
    cards icon-free; zero new errors.
  - **2026-08-29 (user direction): the roster moved to the RIGHT edge and
    now auto-shrinks to fit.** `railPanel(side)` answers for `"right"`
    instead of `"left"` (the kept rail buttons stay bottom-left), the
    cards `halign = "right"`, and the column applies a fit-to-screen
    `uiscale` around a top-right pivot -- design in the two roster
    bullets above. Lua only (`EncounterOfTheWeek/EncounterOfTheWeekHud.lua`),
    luac-clean, live on disk via gitfolder.
    Verified live 2026-08-29 in a 4-hero game: (a) the column hangs off
    the right edge flush with it, and (c) clicking a card opens the
    character window level with the card's top, cleanly to its LEFT --
    but only after the two right-edge fixes below. Still **NOT SEEN**:
    (b) the fit-to-screen shrink with 5+ heroes, (d) re-fit on window
    resize / Font Size change.
- **2026-08-29 (user direction): the two right-edge collisions the move
  exposed are FIXED.** Both were core-codex bugs the roster was simply
  the first widget wide enough to expose; Lua only, live on disk,
  luac-clean, verified live by screenshot in the same 4-hero game.
  - **Character windows opened over the cards, not beside them.**
    `PanelDocument.PanelWindowPlacement` treated
    `positionInScreenSpace` as screen pixels and converted; it is
    already in layer units. See the units bullet in the roster/click
    design above for the full account. The helper now translates by the
    layer's own rect and prefers the roomier side (left for anything
    past the mid-line), matching `TokenWindowPlacement`. Live check on a
    1630x930 screen: a card centred at layer x 1814.9 now places a
    380x520 window at (1358.9, 66) -- right edge 1738.9 against the
    card's left edge 1748.9 -- where it used to place it at x 1651.6,
    straight over the cards.
    File: `DocumentSystem/DocumentSystem.lua`.
  - **The ability sidebar / roll dialog overlapped the cards.** The
    right-edge hosts (`abilityDisplayPanel` and `standaloneRollHostPanel`,
    both 360 wide) reserve a right margin via `RightHostMargin`, which in
    rail mode assumed the rail is the ordinary 40-unit button column
    (`RIGHT_HOST_RAIL_MARGIN = 60`) and otherwise only dodged floating
    panel WINDOWS (`RailWindowsRightIntrusion`). A custom-interface rail
    widget is neither. DocumentSystem gained
    `RailRightColumnWidth()` -- the `"right"`/`"rightbottom"` wrappers'
    `ICON_RAIL_LEFT + renderedWidth * WindowUIScale()`, i.e. how far in
    from the right edge the rail actually reaches -- and `RightHostMargin`
    now takes `max(that + 8, 60, windowIntrusion)`. It is an upper bound:
    a widget that shrinks itself further with its own `uiscale` (the
    roster's fit-to-screen) is invisible from out there, which errs
    toward extra clearance. Live check: the roster reports a 144-unit
    column, the hosts moved from a 60- to a 152-unit margin (right edge
    1740.9 vs the cards' 1748.9), and the "Ray of Wrath" card renders
    fully clear of the roster.
    Files: `DocumentSystem/DocumentSystem.lua`, `DMHub Game Hud/GameHud.lua`.
  - Both are core-codex changes, so they apply to **any** custom
    interface that mounts a wide right rail, not just EotW.
- **2026-08-29 (research only, no code): "Spear Charge doesn't charge in
  EotW" ROOT-CAUSED.** Not a permission denial -- the `strict:movement`
  remaining-budget clamp in the `token:Move` Lua bridge
  (`Assets/Scripts/CharacterToken.cs:3040`) gates on `isDM == false`, which
  is now true on the player host, so every Monster AI move is clamped to
  the monster's remaining move budget. Spear Charge moves twice in a turn,
  so the second (the charge) gets ~0 budget, `Move` returns nil, the AI
  ignores it and attacks from range. Full analysis in the "Monster AI moves
  are clamped by strict:movement on a player host" section above.
- **2026-08-29 (same session): FIXED in three layers, plus a new engine
  concept.** (a) Lua, live now: the two charge moves pass
  `freeMovement = true` -- a Charge's movement belongs to the ability, not
  the move action. (b) Engine: `CharacterToken.subjectToPlayerMovementRules`
  replaces the bare `isDM == false` in the `token:Move` strict:movement
  clamp, so the clamp binds the host's own hero but not a token it controls
  only because it hosts. (c) Engine, user direction: **host-permission
  elevation** -- `ScriptEngine.hostPermissionDepth`, parked and restored
  per-coroutine by the `LuaNative` harness so it is provably zero outside
  Lua execution, exposed as `dmhub.ExecuteWithHostPermissions` /
  `PushHostPermissions` / `PopHostPermissions` with
  `ElevateToHostPermissions()` / `DropHostPermissions()` codex helpers, and
  applied to the Monster AI's three coroutine entry points. Design in the
  "Host-permission elevation" section above.
  Files: `Assets/Scripts/ScriptEngine.cs`, `Assets/Scripts/GameController.cs`,
  `Assets/Scripts/LuaInterface.cs`, `Assets/Scripts/LuaNative/LuaNative.cs`,
  `Assets/Scripts/CharacterToken.cs`; `Definitions/dmhub.lua`,
  `DMHub Utils/Utils.lua`, `Monster AI/MonsterAI.lua`,
  `Monster AI/MonsterAIPanel.lua`.
  **ENGINE NEEDS BUILD; UNTESTED.** On the current (un-rebuilt) engine the
  codex helpers no-op and only the `freeMovement` charge fix is in effect --
  which by itself should already make Spear Charge charge. To verify after
  the build: in an EotW game watch a Goblin Warrior take a Spear Charge turn
  (reposition, "Charge!", the charge move actually happens, strike in range);
  confirm the host still sees player vision and player UI throughout the AI's
  turn (nothing should flicker to Director chrome between AI actions); and
  confirm a hero's own movement is still clamped by strict:movement.

- **2026-08-29 (same session): EotW screen no longer sits on top of the
  loading screen.** Reported: beginning the encounter puts up the loading
  screen, but the EotW screen stays visible over it and through it, vanishing
  only a second or two after the load. Root cause: nothing ever hid the
  screen -- it is a floating sibling of the loading screen on the titlescreen
  root and only went away when C# deactivated the titlescreen 1s after
  `endLoading`. Fix (Lua only, live now): `Codex Titlescreen/EncounterOfTheWeek.lua`
  -- the screen panel gains `beginLoading` (schedule the `hidden` class) and
  `returnFromGameComplete` (clear it), and `ShowScreen` clears `hidden` on an
  existing screen instead of no-opping into an invisible one. Hidden rather
  than destroyed so `SweepStaleScreen` still sees it and rebuilds a live
  screen on return. Verified in the running app by firing `beginLoading` and
  then `returnFromGameComplete` on the live screen panel and screenshotting:
  hides to the bare titlescreen, comes back with roster + chat intact.
  Design detail folded into the loading-screen bullet under "Creating and
  joining EotW games".
  **Follow-up the same session:** the first cut hid on the `beginLoading`
  event itself, which was too eager -- the player saw the screen blink out
  and then the loading art transition in over the bare titlescreen. The hide
  is now scheduled `LOADING_SCREEN_FADE_IN_SECONDS` (0.35s, the loading
  screen's 0.3s dissolve plus margin) after `beginLoading`, gated on a
  `data.loadingUp` flag so a load that resolves inside the window does not
  hide anything. **The delay itself is UNVERIFIED live** -- the app was
  mid-encounter when it was written, and it needs one real Begin to confirm
  the handoff looks continuous.

- **2026-08-29 (same session): Add-a-Hero picker portraits are warmed at
  screen entry.** Reported: the picker comes up half-rendered, freezes for
  about a second while the remaining portraits load, then fills in.
  - **First attempt (a "Loading..." cover over the grid) STALLED and was
    REVERTED** -- it waited on an image-load count that never balanced and sat
    until its 4s backstop on every open. Recorded as REJECTED under
    "Hero-card lineup" with the suspected cause, so it is not re-attempted.
  - **Shipped instead (user direction): warm the portraits when the EotW
    screen opens**, so the picker is already warm whenever it is opened and
    nothing ever blocks on a load. Design in the new "Picker portrait
    warm-up" bullet under "Hero-card lineup". Lua only, one file:
    `Codex Titlescreen/EncounterOfTheWeek.lua` -- new
    `PORTRAIT_WARM_RESCAN_SECONDS` / `PORTRAIT_WARM_PASSES` constants, a
    portrait warm-up section (`EligiblePortraitImageIds`,
    `CreatePortraitWarmer`) after the pregen accessors, and one
    `resultPanel:AddChild(CreatePortraitWarmer())` at the end of
    `CreateScreen`. `MakeCardPanel` and `ShowAddHeroDialog` are back to their
    pre-session state.
  - luac-clean, ASCII-clean, live via the gitfolder, **UNVERIFIED live** --
    the connected instance was inside a game, not at the titlescreen. To
    confirm: open the EotW screen, wait a few seconds, then open Add Hero and
    watch whether the grid paints in one pass. If it still trickles, the
    thing to check first is whether the 1x1 warm panels actually trigger a
    fetch (inspect `#eotwPortraitWarmer`'s children and whether their
    `imageLoaded` fired) before assuming the eligible-id set is wrong.

- **2026-08-29 (user direction): "Strictly Enforce Rolls" + the movement-rules
  row moved.** Full design in the "Strict rules enforcement" section above.
  Two asks, both Lua-only and live on disk via the gitfolder, all files
  luac-clean:
  - The engine's "Strictly Enforce Movement Rules" row now renders under
    "Rules Enforcement" with the other strict toggles, via a one-line
    re-section in `DMHub Titlescreen/Settings.lua` (no engine build).
  - New game setting `strict:rolls` ("Strictly Enforce Rolls") withdraws the
    roll prompt's result-editing affordances for players and hosts, Directors
    exempt: no Re-roll (Accept Result takes the whole bar), no editing the
    dice expression, no click-a-tier override (in the roll dialog AND the chat
    card), modifier chips filtered to the ones that applied and frozen, the
    edge/bane bar frozen, and no backing out of a cast that has committed to
    paying (close X and ESC). Files: `DMHub Titlescreen/Settings.lua`,
    `DMHub Utils/Utils.lua` (`StrictRollsEnforced`,
    `RollDialogCancelOffered`), `Timeline/EmbeddedRollDialog.lua`,
    `Timeline/AbilitySidebar.lua` (stashes `data.castOptions`),
    `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua`,
    `Draw Steel Core Rules/MCDMActivatedAbility.lua`.
  - `strict:rolls` was added to EotW's forced set (`g_strictRuleSettings`),
    so **existing EotW games will turn it on themselves** on the host's next
    `MapScriptHostThink` tick. That is a live behaviour change for EotW, per
    the section's stated intent ("every Strict... option"); remove the one
    list entry if it should be opt-in instead.
  - **UNVERIFIED live.** Registration was confirmed in the running app
    (`dmhub.HasSetting("strict:rolls")` true, both rows report section
    `GameStrictRules`), but no roll was driven through the locked UI: the
    user was working in another game by then. To verify: turn the setting on
    in a game, roll an ability as a PLAYER (or as the EotW player host), and
    check (a) the Re-roll button is gone and Accept Result spans the bar,
    (b) the roll expression will not take keystrokes but still updates itself
    when modifiers change, (c) tier rows do not highlight on hover and do not
    override on click -- in the dialog and in the chat card -- while an "or"
    alternative in the tier text still selects, (d) only applied modifier
    chips are listed and none of them toggle (tooltips still appear),
    (e) the edge/bane boxes do not respond, (f) the card's close X is offered
    before the cost is paid and gone afterwards, and ESC matches it, and
    (g) a Director sees the unrestricted dialog throughout.

- **2026-08-31: Monster AI failures no longer strand EotW initiative.** A live
  EotW turn exposed a despawn race: a War Walker selected Knockback against a
  hero that Grasping Claws had just killed; the delayed hero removal completed
  during the move's speech, its stale target then reached `TargetPassesFilter`,
  and the uncaught error killed the background AI process before turn cleanup.
  The core Monster AI now refreshes combatants each cycle, rejects invalid or
  dead targets immediately before targeting/casting, and contains failures at
  move, actor, whole-turn, trigger, and process-iteration boundaries using the
  yield-aware child-coroutine runner. Failed moves are quarantined per actor so
  a lower-scoring move can run instead of selecting the same broken move again;
  failed triggers are best-effort dismissed so their roll can proceed; actor
  control/prompt state is always restored; an escaped turn error advances only
  when the failed initiative is still current. EotW's watchdog now checks
  `MonsterAI.IsAIRunning()` rather than the possibly stale `MonsterAI.active`.
  Files: `Monster AI/MonsterAI.lua`, `Monster AI/MonsterAIPanel.lua`,
  `EncounterOfTheWeek/EncounterOfTheWeek.lua`. Lua syntax and ASCII checks pass;
  runtime fault-injection verification remains to be done.

- **2026-09-07 (later): Monster Info forced on; monster stamina bars forced
  to bar-only.** User direction: Monster Info is automatically on in EotW,
  and all players see monster stamina bars but not exact amounts. The
  earlier same-day build had forced `enemystambardisplay = "val"` (bar plus
  value); corrected to `"bar"`. Two new `g_forcedGameSettings` entries:
  `monsterinfo = true`, `monsterinfoautolearn = true`. Only
  `EncounterOfTheWeek/EncounterOfTheWeek.lua` changed (luac-clean, ASCII
  clean, live via gitfolder). Confirmed in the running app that all four
  ids (`enemystambardisplay`, `hpbarsonlyincombat`, `monsterinfo`,
  `monsterinfoautolearn`) are declared and game-scoped, so the host's
  `EnforceStrictRules()` writes resolve; the running game was not an EotW
  game, so the enforcement itself is UNTESTED. Existing EotW games will
  switch themselves on the host's next `MapScriptHostThink` tick. Design
  text: "Players always see monster stamina bars, not amounts" and "Monster
  Info is always on" under "Strict rules enforcement". Next: live two-client
  verification per those sections (Monster Info needs its engine build
  first).

- **2026-09-15: Trigger-reaction countdown is infinite in EotW.** When a
  hero has a trigger available during a Monster AI turn, the roll dialog
  shows the "Triggers available" dice (`gui.ProgressDice`, mounted by
  `CreateTriggerReactionPanel` in `DrawSteelActionBar/DrawSteelActionBar.lua`)
  and auto-proceeds after 5 seconds unless clicked, which is too fast for
  players who are new to the app. User direction: in EotW the timer never
  counts down. The two `m_timerState` builders (`Draw Steel UI/DSRollDialog.lua`
  ~3139 and `Timeline/EmbeddedRollDialog.lua` ~6174) now check
  `EncounterOfTheWeekGame.IsEotwGame()` (pcall-guarded, the game codemod
  may be absent) and, when true, create the state already `paused = true`
  with the "Click to dismiss" text, i.e. exactly the state one click on
  the dice would otherwise produce: the dice sits full, nothing
  auto-proceeds, and a single click dismisses and proceeds. The 30-second
  "Waiting for <hero>'s trigger..." state (`m_resolveState`) that appears
  while another player's trigger is actually resolving is unchanged.
  luac-clean, ASCII-clean, live via gitfolder; UNTESTED live (needs a
  Monster AI turn in a real EotW game with a hero holding a trigger).

- **2026-09-15 (later): Hero cards show a pulsing trigger badge.** User
  direction: when a hero has a trigger available, their roster card gets
  the same "!" badge the initiative bar uses (`gui.TriggerPanel`, styled by
  `Styles.TriggerStyles`), gently pulsing, with a tooltip and a click that
  jumps to the hero. `CreateTriggerCorner(charid)` in
  `EncounterOfTheWeek/EncounterOfTheWeekHud.lua` mounts it floating in the
  card's top-left corner (conditions own the top-right, surges the
  bottom-right). Availability is `GetAvailableTriggers(true)` minus hostile
  entries -- the same test `AbilityActivityInFlight` uses; hostile prompts
  are skipped because they never expire and would pulse forever. The
  wrapper rebuilds only when the sorted set of trigger ids changes (it runs
  on every `refreshCard`, i.e. the roster's 1s think and `/characters`
  changes, which is where `availableTriggers` lives). The badge's own 30ms
  think drives a 1.4s sine on opacity (0.6..1) and scale (0.92..1.08).
  Tooltip: "<hero> has a trigger available." + each trigger's
  `powerRollModifier` name (falling back to `text`) + "Click to jump to
  <hero>." Press: `dmhub.CenterOnToken(charid, function()
  dmhub.SelectToken(charid) end)` -- selection only takes for a hero the
  user controls, so on someone else's hero it just centers. The badge
  sets `swallowPress` so the card's own press (character panel toggle)
  does not also fire. luac-clean, ASCII-clean, UNCOMMITTED, UNTESTED live
  (needs a Monster AI turn in an EotW game with a hero holding a trigger).

- **2026-09-16: First live run of the encounter dropdown -- map switch
  works, spawn failed on content.** The user entered an EotW game whose
  creator chose `Encounter: Goblin Ambush`; the host landed on that map,
  placed heroes and signalled ready, but no monsters spawned (console:
  `EotW: encounter spawn failed: This map's journal has no encounter to
  spawn.`). Diagnosed in the running game via MCP: the shipped module's
  only document (`Room 1`, the dwarf encounter) is filed under
  `Encounter: Angry Dwarves`; the goblin map has no document and no info
  bubbles, and the version ships no bare `Encounter` default. Content fix
  in the authoring game + republish (details under "Choosing the week's
  encounter"). No code changed this session.

- **2026-09-16 (later): Tactician Mark prompts absent on a killing blow --
  DIAGNOSED, working as the rules intend, but silently; no code changed.**
  In game `HungeringSilentFacelessTalent` (staging DO) the Shadow's Two
  Throats at Once killed the marked Dwarf Warden 1, and the Tactician got
  neither the Mark: Benefit prompt nor the "place your Mark on a new
  creature" prompt. Two independent gates, both silent (the trigger
  dispatcher only records reasons into `debugLog` for relayed events):
  1. The Tactician was under the Dwarf Axethrower's Whistling Axes effect
     ("can't use triggered actions until the start of the next round",
     ongoing effect `4dadd12e`, applied round 2 at 1789552560851, ~60s before
     the kill). `creature:TriggeredActionsForbidden()` is true, so
     `CharacterModifier:TriggerEvent` (`DMHub Game Rules/CharacterModifier.lua`,
     "Cannot use triggered actions" branch) drops every optional, non-hostile
     trigger on the creature -- both Mark prompts. Mandatory triggers
     (Marked Takes Damage, Monster Death) still fired, which is why the log
     shows them and nothing else.
  2. Independently, the Benefit costs 1 focus and the Tactician was at 0
     (the focus history shows the fourth accepted Benefit set it to 0 at
     1789552415490, no gain until the kill). `HasTriggeredEvent` /
     `TriggerEvent` run `CanAfford` synchronously at the losehitpoints
     dispatch, while the same event's +1 focus grants (Marked Takes Damage,
     Ally Uses Heroic Ability) land later from their cast coroutines -- so a
     Tactician at 0 focus can never spend the focus that the very same hit
     grants. The rules are ambiguous on that ordering; flagged, not changed.
  Diagnosis trail: `MANDATORY:: IS = ...` prints in Player.log (three prints
  plus a `null mandatory =` line per trigger that reaches the prompt stage;
  the re-mark showed only the CharacterModifier print), the Warden record
  still carrying the Mark effect with `casterInfo.tokenid` = the Tactician,
  and the Tactician's `2d3d5511..._history` focus ledger, both read via
  `GET https://game-server-staging.codexback.com/api/<gameid>/store/game?path=/characters/<charid>`.
  UX gap for EotW (open): strict-rules players get no feedback that a
  trigger was suppressed by a "can't use triggered actions" effect or by
  an empty resource pool; a hint on the hero card badge/tooltip or a
  one-line notice when a would-be prompt is suppressed would close it.
37. [x] **Loading-screen hold** (BUILT 2026-09-18; C# NEEDS BUILD; Lua UNTESTED):
    engine `dmhub.HoldLoadingScreen` / `ReleaseLoadingScreen` (`GameController.cs`,
    `LuaInterface.cs`, `Definitions/dmhub.lua`); the titlescreen holds on every
    EotW Enter World; the host presents an opening montage in `SetupOnArrival`
    before hero placement (`EncounterMontage.Begin`, new "arriving" phase);
    the stage's `create` releases the hold, `SetupOnArrival` releases it after
    placement when no montage is expected. Design under "The loading-screen
    hold" above. Test: host and member both dissolve from the loading screen
    straight onto the stage; a no-montage week shows no hero pop-in.
38. [x] **Two module pregens sit in the Players party** (ROOT-CAUSED + FIXED
    2026-09-18; Lua NOT deployed, real arrival UNTESTED): the published
    `mcdm-encounteroftheweek` snapshot authors High Elf Tactician and Human
    Null with `partyId` = the default Players party guid, so every EotW game
    listed two unclaimed, unplaced extra heroes. Fixed by the host-only
    `SweepPlayersParty()` in `SetupOnArrival`, which parks any unclaimed
    module character from the players' party with the rest of the pregens;
    the running game was repaired by hand the same way. Cause, the safety
    tests, and the still-open source republish are under "Two of our OWN
    pregens are authored into the Players party".
