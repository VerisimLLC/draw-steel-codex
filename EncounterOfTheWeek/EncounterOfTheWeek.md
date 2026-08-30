# Encounter of the Week

The "Encounter of the Week" is a new game mode for the Codex. It will have a weekly "encounter" on a set map where some players will take on a group of monsters controlled by the monster AI.

It will use a new dev setting, dev:encounteroftheweek to gate it. If this setting is turned on, then the Encounter of the Week game mode is available from a link in the top-right corner of the titlescreen.

When entering the Encounter of the Week game mode, a new section of the titlescreen will be available. It will give an overview of the game mode, and have a lobby where games that a player may join or observe are displayed as well as a way to create a game and a chat interface (visually consistent with in-app chat, but backed by the lobby -- see below).

**The Encounter of the Week lobby is NOT a game.** It is the first instance of a new first-class concept: a **Lobby** -- a Durable Object that users connect to. Users in a Lobby can chat with each other, see who else is present, and see shared lobby state (for EotW: the roster of joinable games). The C# engine gets a new lobby interface for connecting to lobbies; the app can host connections to different lobbies, and this one is the `"eotw"` lobby. Future lobby types (e.g. a general community lobby, per-module lobbies) reuse the same concept.

A user may create a game and set it to public or private. Private games are not listed. Anyone can join a public game though the user who initiated it is the host and may kick people out of it.

An Encounter of the Week can have between three and seven heroes participate. One player may play multiple heroes. When joinining an Encounter of the Week, a player can fill the 'slots' with their heroes. They can pick their lobby/titlescreen heroes or from the pregen heroes. Pregen heroes are found in the mcdm-encounteroftheweek module.

Once a game has the required number of heroes, the host may select to begin and it launches into the encounter.

An enounter of the week is played as a game which has a special mcdm-encounteroftheweek module installed. It should automatically include the monsterai code mod, with monster ai always running. Upon entry into the game, it should automatically choose the "Encounter" map within the module. A special environmental keyword "Start" should mark the hero's "starting zone" and before proceeding the heroes should be able to move around their starting zone and select their position.

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
  tokens, tables all valid) and after codemods' `enterGameHandlers` have run. The
  callback is created in the titlescreen Lua state and survives the codemod
  unload/reload of the game switch, so it captures ONLY plain data and resolves
  the game-side global late via `rawget(_G, "EncounterOfTheWeekGame")`.
- **Explicit handoff, no auto-detection**: the game-side codemod does nothing on
  load; setup runs only when the titlescreen's Enter World calls
  `EncounterOfTheWeekGame.SetupOnArrival{heroes, clipboardIds, numHeroes}`. This
  is deliberate -- the authoring/source game also loads the EotW codemod, and any
  on-entry auto-spawn there would dump monsters into the user's source game.
  Consequence: entering an EotW game from the CAMPAIGNS list (not the EotW
  screen) runs no setup; acceptable for now, revisit with Begin (step 21).
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
- **Lua Loc gotcha (2026-08-27)**: a Loc's floor is READ as `loc.floor`;
  `loc.floorIndex` is not a property and reads nil (the CONSTRUCTOR arg is named
  `floorIndex`, the getter is `floor`). Passing a floorless Loc to
  `token:Teleport`/`ChangeLocation` lands the token on floor 0 -- derive
  destinations from an existing token's Loc (`ref.loc:dir(dx,dy)`) or pass
  `floorIndex` explicitly when constructing.

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
  Compendium > documents -- nothing else; the `[[encounter]]` annotation (and its
  banked spawnlocs) rides inside the doc record** (see Encounter spawning above).

## In-game flow

- Map on entry: rather than forcing a map switch, **make "Encounter" the module's only (or lowest-ord) map** so the natural fallback selection (`GameController.cs:4871`) picks it with no extra loading beat. `executeOnArrive` on `lobby:EnterGame(gameid, fn)` (fires after loading completes, `GameController.cs:7170`) and `dmhub.RegisterEventHandler("EnterGame", ...)` are both available if forcing is needed; `map:Travel()` / `game.ChangeMap(map, floor)` do the switch.
- Start zone: an `EnvironmentalKeyword` named "Start" -- the keyword is defined in the mcdm-encounteroftheweek module -- (compendium: Rules > Environmental Keywords; `EnvironmentalKeyword.lua`), painted as a markup zone (`floor.markupZones` records, `floor:SetMarkupZone`; schema at `MapMarkupPanel.lua:944-998`). Query tiles by scanning `floor.markupZones` for records with `keyword == startKeywordId` (skip `category == "surface"/"hole"`); resolve the id via `EnvironmentalKeyword.keywordsByName["start"]`. Per-square test: `game.GetAurasAtLoc(loc)` + `aura.auraInstance.aura:try_get("environmentalKeywordId")`. GoblinScript: `target.Environment has "Start"` works as a targetFilter.
- Monster AI: lives in `Monster AI/` as a `dmonly` DockablePanel background process (`MonsterAIPanel.lua`). BUILT (2026-08-28): `MonsterAI.StartAI()` / `MonsterAI.StopAI()` / `MonsterAI.IsAIRunning()` exported from `MonsterAIPanel.lua`, wrapping the same StartProcess/StopProcess calls the panel button makes (the button now routes through them). `DockablePanel.StartProcess` is independent of panel visibility (verified in source), so the AI runs headless on a host whose dmonly panels are hidden. `MonsterAI.active` (default false in `MonsterAI.lua:21`) is the "is it running" read.

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
  on an EotW client for debugging/manual recovery.
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
`CharacterToken.DragBlockedByMovementRules` (the `strictmovementrules`
drag block) has the same shape -- on a player host it now stops the host
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
a player host. The host can still physically drag monsters -- the
accepted manual-recovery path.

### Strict rules enforcement (DECIDED + BUILT 2026-08-28)

User direction (2026-08-28): EotW games strictly enforce all game rules -- the
settings screen's "Rules Enforcement" options that start with "Strict"/"Strictly"
are force-enabled. The forced set (`g_strictRuleSettings` in
`EncounterOfTheWeek/EncounterOfTheWeek.lua`):

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

Mechanism: `EnforceStrictRules()` writes any of the six game-scoped settings
that is not already `true`. Called from the host's `SetupOnArrival` block
(next to the `permission:playersinitiative` write) and re-asserted at the top
of every `MapScriptHostThink` tick (check-before-write, so steady-state ticks
write nothing).

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

### Victory/defeat auto-detection, player Proceed, and auto-exit (DECIDED + BUILT 2026-08-28)

User direction (2026-08-28): the game detects the encounter's victory/defeat
conditions itself, triggers the victory/defeat screen, players (not just the
Director) can press Proceed, and after Proceed everyone is returned to the
Codex titlescreen.

- **Detection (host map-script tick, while the queue is live)**: if
  `live:GetAwardedOutcome()` is nil, evaluate victory =
  `live:CheckVictory()` (the existing evaluator: all seven authored conditions
  plus encounter-script overrides, pending reinforcements included) and defeat
  = `live:CheckDefeat()` (script-declared) OR all heroes down via
  `live:CountLiveCombatants()` returning `heroes == 0`. Note
  `CountLiveCombatants` counts `CurrentHitpoints() > 0`, so DYING heroes
  (hp <= 0 but above the death threshold) count as down -- an all-dying party
  is a defeat, which is the intended one-shot semantics. Award = set
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
- **Player Proceed (core hook)**: `DSVictoryScreen.RegisterProceedOverride{
  canProceed, proceed }` in `Draw Steel UI/DSVictoryScreen.lua`. Proceed-button
  visibility becomes `dmhub.isDM OR canProceed()` (pcall-guarded); the click
  runs `proceed(ProceedEndCombat)` first and only falls through to the normal
  Director teardown when the override declines. `ProceedEndCombat` is also
  exported as `DSVictoryScreen.ProceedEndCombat` for the host-side automation.
  The Victories award section's visibility gate converts `dmhub.isDM` ->
  `GameHud.DirectorUIVisible()` (identical in normal games; hidden in EotW for
  everyone including the host, per the no-Director presentation).
- **EotW override**: when `IsEotwGame()`, everyone may press Proceed. The HOST
  pressing runs the normal full teardown directly (battle log +
  `encounter_complete` analytics + role history are `dmhub.isDM`-gated and must
  run on the host). A PLAYER pressing stamps `proceedRequested` into the
  `eotwstate` doc; the host tick (which is already watching the awarded
  outcome) sees it and runs `DSVictoryScreen.ProceedEndCombat()` -- worst case
  ~2s latency before the screen dismisses for everyone. If the host client is
  gone, the request sits until the host returns (same accepted class as the
  other host-crash edges).
- **Auto-exit to the titlescreen**: each client's 1s driver latches "outcome
  seen" while the queue is live with an awarded outcome; when the queue then
  hides/disappears (Proceed ran), it schedules `dmhub.LeaveGame()` once, ~4s
  out (covers the victory screen's 0.7s fade plus the 1-3s GameDetails write
  coalescing so the host's battle-log/queue writes flush before the socket
  closes). Every client leaves, host included, landing on the titlescreen --
  the existing post-leave flow (stale-screen sweep, resume row, no auto
  re-entry) already handles the arrival. Clients that never saw an awarded
  outcome (a combat ended via the Director escape hatch, or a mid-join) do NOT
  auto-exit. `dmhub.LeaveGame` is deferred via `dmhub.Schedule` because it
  synchronously unloads the calling codemod.
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
- **Kept buttons (user direction 2026-08-28): Chat and Action Log survive
  in the bottom-left corner** -- `railBottomPanel("left")` returns a strip
  of rail-style buttons (`CreatePanelButton`): 40px iconRailButton look
  (the wrapper's IconRailStyles makes the classes native), the panel's
  registered icon, its unread badge (hasNewContent/newContentCount/
  markContentSeen on the refreshRail cadence, the real button's recipe),
  the active underline while the window is up, and the real open path
  (`DockablePanel.LaunchPanelByName(name, "toggle")` -> the rail's open
  handler -> a normal rail window). Chat and Action Log share a window as
  tabs exactly as on the real rail. Verified live via the force toggle:
  buttons render bottom-left, chat opens with input focused, active class
  lights, action log opens tabbed, toggle closes, zero errors.
- **Hero roster** on the right edge (REDESIGNED 2026-08-28, user
  direction: portraits ARE the card; moved from the left edge 2026-08-29,
  user direction -- `railPanel(side)` now answers for `"right"`, and the
  cards `halign = "right"` so the column packs against that edge. The
  kept rail buttons stay in the bottom-LEFT corner, where the real
  rail's live): one card per party hero
  (`Party.GetPlayerCharacters()` + `IsHero()`, so off-map heroes count) --
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

12. [x] Create-game flow: "Create Game" button + dialog (name input, public checkbox)
    in the EotW screen. Flow as designed: lobby `create-game` request (reserve) ->
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
17. [~] Build the first Encounter map. PARTIAL (re-inspected 2026-08-27 against v2, dataid `c0805b51-...`): the map named "Encounter" exists and is the module's only map (natural fallback selects it), in folder "Delian Tomb - Part 1", with the Start zone painted (19 tiles on floor `8de328e8`, zone `0ee1e996`). **GAP (still present in v2): the map has NO live encounter.** Its 5 map characters are all `despawned: true` -- 3 Goblin Snipers with 9 damage_taken and leftover combat paths (a played-out fight) plus 2 blank "Monster" strays. **The intended encounter is now known**: the source game's journal doc "Goblin Guards Combat" (docid `04eae049-3fdf-478c-a40f-d2376837e0fa`) specifies the tomb-exterior fight -- six **goblin warriors** at start (groups of two), round-2 reinforcements of two goblin warriors + two **goblin assassins** from the tomb entrance, with hero-count adjustments (6 heroes: +2 warriors; 4 heroes: -2; 3 heroes: -4), staged via `[[encounter]]` island widgets with a Place on Map button. Neither that document nor any encounter asset ships with the module yet. **DECIDED (2026-08-27): the encounter is spawned programmatically at game setup, scaled to hero count (Phase 6 step 20)** -- the map stays token-free by design. Remaining module work for this step (user, in the source game -- the how is now RESEARCHED, see "How journal documents ship" in Module + codemod bundling): tick the "Goblin Guards Combat" doc (docid `04eae049-3fdf-478c-a40f-d2376837e0fa`) under ModShare's Compendium > "documents" section, delete the despawned sniper/stray characters from the map, and republish (v3). No encounter asset is needed -- the `[[encounter]]` annotation with its banked spawn positions rides inside the doc record.
18. [X] Author 3+ pregen heroes as module content. VERIFIED against v2: 8 pregens ship with `IsHero()` true and resolvable classes -- Dwarf Fury, High Elf Tactician, Human Censor, Human Null, Human Talent, Orc Conduit, Polder Elementalist, Polder Shadow (only Wode Elf Troubadour of the 9 official pregens is absent).
19. [X] Publish the module with the Monster AI codemod ticked in ModShare. VERIFIED in v2's snapshot.codemods: both the EotW stub codemod (`cdc19d98-...1428`) and Monster AI (`263594e2-aca1-4ce5-b70e-8d690695d7b4`) are bundled. (v1 lacked Monster AI; `ReconcileStartingModuleCodemods` repairs v1-created games as the version advances.) The install-side `codeModsFromModules` write is engine code proven by the Crowdex precedent; verify once the first game is created from the module.

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
    and auto-exit".

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

---

# Open Questions

- ~~**EotW games in the CAMPAIGNS list**~~ RESOLVED (2026-08-27): a dedicated
  `accountInfo.eotwGame` slot (one game per account, never in `games`), with
  entering a new game destroying the previous one -- DO released -- and a resume
  row on the EotW screen. See "One EotW game per account" in Architecture Notes.
- **Observers**: the spec says games can be observed. Join as a player with zero hero slots, or a true spectator mechanism? Affects permissions and the players list.
- **Weekly rotation**: who publishes the new encounter each week, and does the module id stay stable (`mcdm-encounteroftheweek` with version bumps) or rotate? Version bumps + `ReconcileStartingModuleCodemods` suggests a stable id.
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

---

# Status

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
