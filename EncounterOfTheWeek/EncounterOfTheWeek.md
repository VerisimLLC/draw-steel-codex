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
  NOT `ReinstallCharacter`, which reuses the module charid. Caveat noted for
  Phase 5/6: snapshot characters' portrait image ids resolve against the
  module's streamed assets, which only load for installed modules -- verify
  portraits at the titlescreen before promising them in the picker.

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

- **Create game**: allowed only if the requester does not already have a game registered
  in this lobby (one hosted game per user at a time). On grant, the DO records the roster
  entry itself.
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
  channels); `create-game {name?, public?}` (one hosted game per user; grants a
  reservation); `confirm-game {gameid}`; `join-game {gameid, heroes?}` (public +
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
- **Verified 2026-08-28** with an in-game visual mock (real tokens, modal over
  the running game -- the connected instance was mid-game, so the titlescreen
  screen itself could not be exercised): portraits/frames/plates/chip render
  correctly, hover reveals the trash, the born tween + fade works (screenshot
  caught mid-animation with neighbors sliding apart), zero console errors, and a
  full reload (49 mods) was clean. NOT yet seen live: the real game-lobby view
  over a roster record, the picker grid at the titlescreen (incl. whether
  pregen snapshot portraits resolve there -- silhouette fallback covers a miss),
  and remote-player cards.

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
cleanup), and there is no standalone "abandon without starting a new game" button
-- destruction only happens on entering a new game. Revisit if wanted.

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
    install race" for why. Members with zero heroes (observers) enter too. A member who reopens the screen while their
    game is launched (within the record's 5-min TTL) is likewise pulled in.
    **DECIDED (2026-08-27): the per-member "Enter World" button is gone** --
    Begin is the only way to launch into the game; the resume row ("Your game
    in progress" -> Resume) remains the re-entry path for a game whose roster
    record has expired. Tests: `lobby-core.test.ts` +2 (suite 249 green, tsc
    clean); `lobby-smoke.ts` step 8c (non-host + under-strength + double launch
    rejected, broadcast observed, post-launch join/set-heroes rejected,
    heartbeat still ok) -- ALL CHECKS PASSED against local
    `wrangler dev --env staging`. Staging deploy is a user action
    (`npm run deploy`); until then Begin's click gets "Unknown action".
22. [ ] Starting-zone phase: DEFERRED (2026-08-28 user direction: combat enters
    as soon as every player is in the game -- see the "Automated combat entry"
    architecture section; a positioning/ready-up phase may return as a later
    requirement). If revived, it slots in as an extra pre-combat stage in
    `MapScriptHostThink` (players move only within Start-zone tiles; ready-up;
    then the arrival gate).
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
  JSON). Open sub-question: whether pregen portraits render at the titlescreen
  without the module's streamed assets loaded.

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
