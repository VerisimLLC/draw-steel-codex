# Panel Library -- Design Brief

Status: IN PROGRESS -- decisions are being made round by round; everything in
the decision ledger is settled, everything under Open questions is not.

## 1. Framing

The icon rail's + button currently opens a small anchored popup: a "Create"
row (New tool panel), a Recommended section, and a flat alphabetical list of
every registered panel. It works, but it is cramped: no search, no
descriptions, no room to grow -- and we want it to grow into community-made
content.

**Problem:** the + picker serves two intents -- "add a panel I know exists"
(rail configuration) and "what could I add / what could I build?"
(discovery, authoring) -- and its current form serves neither well enough to
host the planned community-button ecosystem.

**For whom:** rail configuration is a burst activity (first setup, new
feature shipped), then dormant. It serves both persona poles, but the
DISCOVERY intent dominates: the power user browses for what to build, the
set-and-forget user needs recommendations and legibility. Speed of a single
add is NOT the binding constraint -- the rail buttons themselves are the
everyday fast path; the + is only ever configuration. The library should
make customization feel fun ("getting to scroll through the buttons"), not
merely efficient.

**Done looks like:** clicking + opens a Panel Library surface that hosts
recommended panels, a searchable list of all official panels, the user's
toolkits plus creation, and (phased later) community-made buttons -- with
the single-add path still competitive with today's menu (+, type, click).

## 2. Verified engine reality

- The current picker is `RailShowAddPicker` in
  `DocumentSystem/DocumentSystem.lua` (anchored popup, popupsInheritStyles,
  scrim palette from IconRailStyles). Clicking a row calls `RailAddPanel`
  (rail config -- it does not merely open the panel).
- Toolkits exist end-to-end: `iconrailtoolkits` setting, strips, create/edit
  dialogs with the curated Phosphor icon grid (60 glyphs,
  `g_toolkitIconOptions`), delete purges the layout entry.
- The toolkit item schema reserves an explicit `type` field for custom
  action buttons -- authoring custom buttons has a designed-for landing
  place, but "what is an action" is an unmade decision.
- Distribution infra VERIFIED (Definitions/module.lua, 2026-08-16): a
  full module pipeline exists -- module.CreateModule / publish-from-game,
  QueryModuleIndex with `purchased` / `installed` / `published` /
  `patreon` categories (a store), creator organizations with invites and
  Patreon-gated grants, dependency tracing, download-size estimation,
  module snapshots, and per-module stats. Distribution does not need to
  be built, only pointed at.
- Trust model: ALREADY SETTLED BY PRECEDENT, twice -- game-system mods
  are community Lua with full engine access, and dice sets ship
  user-authored Lua scripts through the shop today. Community buttons
  inherit this policy (with plain install-consent copy), they do not
  invent it.
- Load-bearing unknown for sharing (verify at Phase 2 start): modules
  are published FROM a game's content; toolkits live in user settings.
  Packaging a toolkit as a module needs either an engine-side content
  type or a convention (module carries a small code mod that registers
  the buttons). Only place engine C# work may appear.

## 3. Decision map

- Surface form of the + target (DECIDED -- see ledger)
- Library internal layout: size, position, section grammar (tiles vs rows),
  search behavior, New-tool-panel entry treatment (NEXT ROUND)
- Close/dismiss behavior: single-add auto-close vs multi-add session
- What a community button IS: action model, capability bounds, trust/consent
  UX, review/moderation (LATER -- needs infra verification first)
- Community browse presentation: cards, authors, install flow, relationship
  to shop pipeline (LATER)
- Regression surface: every capability of the old picker must land somewhere
  (Recommended filtering, folder-member exclusion, add-to-side, New tool
  panel)
- Copy: section names ("Panel Library"? "Recommended"? "All panels"?),
  + button tooltip
- States: empty recommended row (hide entirely), no search results,
  mid-session open (must not block play), late-join/multi-client (layout is
  per-user preference -- low risk)
- Performance: library build cost on open (build-once, no per-frame
  rebuilds); panel count today is ~40 rows -- trivial, but community content
  changes that

## 4. Decision ledger

- **2026-08-16 -- The + opens the Panel Library directly; no intermediate
  menu.** Rationale: rail adds are rare configuration acts, so
  discoverability and room-to-grow beat shaving a click; an intermediate
  menu is a lobby for two rooms; a hover flyout for "All panels" violates
  the no-hover-only-paths rule and needs a click fallback anyway. The
  library absorbs the old picker's jobs as layout, not navigation:
  Recommended as a tile row (hidden when empty), All panels as the
  searchable body (search focused on open), New tool panel as a visually
  distinct create entry, Community as a later section in the same surface.
  Owner's note: browsing the library should itself be enjoyable -- the
  customization burst is part of the fun.

- **2026-08-16 -- The library is a floating window (~900x640), undimmed,
  opening centered-left near the rail; no window chrome (no title-bar
  furniture, no persisted position, no resize handles); dismissed by esc,
  click-outside, or completing an add.** Rationale: matches the rail's
  native grammar (every rail button summons a floating window); width
  earns the tile grids and future community cards; an oversized anchored
  popup re-fights screen-edge geometry forever. Rejected alternative
  recorded below.

- **2026-08-16 -- Visual language: theme vocabulary, not a new skin.**
  The library window is `framedPanel toplevel` (flat @bgAlt surface, 1px
  @border, themed corner radius) with `modalTitle`, the standard
  SearchInput, and @fgMuted/@border section headers with hairline rules.
  The Recommended and toolkit sections render faithful rail-button
  REPLICAS (the rail's exact 40px #000000cc face, 20px @fg glyph, hover
  tints) with names beneath -- an honest preview of exactly what lands on
  the rail. The replica hex is deliberate (must match the rail's scrim);
  everything else is existing tokens/classes plus component-local rules.
  Rejected on the way: a glassy off-theme "modern" skin (v2 mock) --
  looked good alone, made the rest of the app's dialogs look dated.

- **2026-08-16 -- v1 IMPLEMENTED and live** (`RailShowAddPicker` in
  DocumentSystem/DocumentSystem.lua): the + opens the library as a
  900-wide auto-height popup-layer window CENTERED ON SCREEN (owner
  preference, amending the earlier "near the rail" placement; done by
  anchoring popupPositioning to the full-screen documents layer --
  popups otherwise position relative to their owning button),
  esc/click-outside/single-add dismissal, search focused on open.
  Defaults chosen by Claude pending owner sign-off (all adjustable):
  - All Panels as two dense columns (no per-panel descriptions yet).
  - "New tool panel" as the first (accent-outlined) tile of YOUR TOOL
    PANELS; off-rail toolkits listed after it, click re-adds to rail.
  - Auto-close on single add.
  - "Add surface" semantics kept from the old picker: All Panels lists
    only panels not already on a rail / in a folder (search therefore
    only finds addable panels). Revisit if the library should become a
    complete catalog with "already added" states.
  - COMMUNITY renders as a reserved section with a coming-soon card.
  Verified live: search-filter, add-and-close, toolkit re-add, create
  flow, recommended section auto-hiding when empty.

- **2026-08-16 -- Script button action contract: Option A (AMENDED,
  supersedes the same-day Option C pick).** A script button stores a
  plain Lua chunk run in the standard global environment -- full engine
  access, same trust posture as mods and dice scripts -- and the editor
  is a bare code box (placeholder comment only). The starter-template
  chips were built, shipped briefly, and then REMOVED at the owner's
  direction: "just A first, pure lua." Errors unchanged: pcall around
  every run, button flashes danger, error message opens in a dialog (no
  silent failure). Templates remain a possible later addition; if they
  return, the removed set lives in git history (five chips: Roll dice /
  Post to chat / Selected tokens / Open a panel / Blank).

- **2026-08-17 -- Community packs: owner directives.** (1) Publish side
  mirrors module publishing in UX but rides NEW infrastructure -- a
  dedicated button-pack system; C# and database-side changes are
  authorized. (2) Install side is SEAMLESS for any user, player or
  Director: "adding a button to my panel", no install ceremony, no
  warnings -- justified by running pack scripts SANDBOXED. (3) An added
  button records as a per-game preference for that user; the pack
  downloads automatically. (4) Pack script execution is conservatively
  insulated: pcall everywhere, restricted environment, best-effort
  protection of the rest of the app from a broken button. Owner offers
  help with backend permissions (Firebase rules deploy).

## 4b. Community feature roadmap (decided 2026-08-16)

Three phases, each independently shippable:

1. **Local custom buttons** (SHIPPED 2026-08-16): toolkit items gained
   `type = "script"` {name, icon, script}. Two entry points: a toolkit
   strip's + menu ("New script button...") and the Panel Library's "New
   button" create tile, which adds an "Add to" toolkit dropdown (with
   "New toolkit" auto-creating a "My Buttons" toolkit) and, on save,
   puts the toolkit on the rail and opens its strip. The editor dialog
   is name + bare Lua code box + the Phosphor icon grid (pure Option A;
   the briefly-shipped template chips were removed -- see the amended
   action-contract decision). Buttons render on the strip like panel
   buttons (context menu: Run / Edit Script... / Move / Remove); click
   runs the chunk via load+pcall; on error the button flashes the
   rail's stop-button red and the message opens in a ModalMessage
   (chunk name "script-button:<name>" so line numbers read well).
   Verified live end-to-end: create -> run (chat message posted),
   edit -> broken code -> error dialog with line number.
   Follow-up niceties, not blockers: a softer error toast than the
   full-screen ModalMessage; a monospace/larger code editor surface.
2. **Publish a toolkit as a BUTTON PACK** (amended 2026-08-17: new
   dedicated infrastructure, not module reuse -- see the viability
   research below): right-click "Publish..." wraps a toolkit's buttons
   into a pack record on new Firebase paths, via a new C# Lua bridge.
3. **COMMUNITY section goes live**: pack browsing over the new pack
   index; adding a button is seamless (no install ceremony, no
   warnings), auto-downloads the pack, records per-game per-user, and
   runs the scripts in an insulated, restricted environment.

### Phase 2/3 plan of record (2026-08-17)

1. **Backend contract**: pack schema {id, owner, name, description,
   icon, version, buttons[], mtime}; new rules for /ButtonPack +
   /ButtonPackIndex cloned from the /Module owner-write/public-read
   pattern. STATUS 2026-08-17: rules WRITTEN into
   cloud-functions/database.rules.json (four stanzas: ButtonPack,
   ButtonPackIndex, ButtonPackKilled admin-only kill index cloned from
   /ModuleDeprecated, ButtonPackStats read-only stub) and parse-checked.
   NOT YET DEPLOYED: no Firebase credentials on this machine
   (firebase-tools installed, login:list empty, no service account /
   FIREBASE_TOKEN). Blocked on owner running `npx firebase login` in
   cloud-functions/ (or providing a CI token / service account).
   Bridge-side note: author updates must round-trip the killed field
   unchanged (validate rule), same as Module.cs does for deprecated.
2. **Engine bridge (C#)**: ButtonPackLua -- Publish / QueryIndex /
   Download -- plus Definitions/ stubs. First testable milestone.
3. **Publish flow (codex)**: toolkit right-click "Publish..." dialog,
   payload built from the toolkit's items.
4. **Seamless add (codex)**: COMMUNITY section renders pack cards from
   the index; clicking a button just adds it -- auto-download, per-game
   per-user preference record, button on the rail. No ceremony.
5. **Insulated runner**: pack buttons run with the FULL engine API (the
   API itself is the sandbox -- owner decision), wrapped in pcall, with
   the instruction-count watchdog against runaway scripts, gated by the
   kill switch check.
6. **Kill switch + rating system**: a remotely-set killed flag checked
   before running pack buttons (modeled on /ModuleDeprecated), and a
   pack rating/validation surface.
7. **Hardening pass**: republish/update semantics, removal, offline
   behavior, hostile-script tests (infinite loop, error spam) against
   watchdog and kill switch.
8. **Separate task, outside this feature: engine Lua API safety
   review** -- the "API is safe by construction" principle is now
   explicitly load-bearing; audit it as its own effort.

Remaining design rounds before their steps: publish metadata (before
3), add-per-button vs add-whole-pack (before 4), watchdog budget and
kill-switch data shape (before 5/6).

### Phase 2/3 viability research (verified against code, 2026-08-17)

- **Backend pattern to clone**: modules live entirely on Firebase RTDB
  paths written directly by the client -- `/Module/{id}` (record),
  `/ModuleIndex` (public browse), `/ModuleVersions/{guid}` (+snapshot),
  `/ModuleAuthor`, `/ModuleStats` -- with access control in
  `cloud-functions/database.rules.json` (checked into this repo; e.g.
  /Module write = "!data.exists() || auth.uid == owner || org member ||
  admin"). Large content compresses and uploads to Google Cloud Storage
  via `ImageManager.UploadDataBlobToGoogleCloud` keyed by MD5
  (Assets/ModuleManager.cs ~line 730-1013). Button-pack scripts are
  kilobytes, so packs can live ENTIRELY in RTDB records -- no blob
  store needed for v1.
- **New infra shape**: `/ButtonPack/{packid}` + `/ButtonPackIndex`
  (+ later `/ButtonPackStats`), rules cloned from the /Module pattern.
  Rules deploy needs Firebase project access (owner offered).
- **C# work required**: the engine exposes no Lua API for arbitrary
  DataStore paths, so a small bridge class (ButtonPackLua or additions
  to Module.cs's pattern) is needed: Publish, QueryIndex, Download.
  Plus LuaLS stubs in Definitions/.
- **Per-user per-game storage exists**: Storage.PerGamePreference
  (SettingsManager.cs:32) stores as local pref keyed "{gameid}.{id}" --
  exactly where iconrailtoolkits already lives. NOTE: device-local, so
  an added button does not follow the user to another machine;
  Storage.Account exists if cross-device ever matters.
- **Sandbox viability CONFIRMED**: the engine's Lua is standard 5.4
  (lua-core.txt keeps debug/os; same source as the bundled
  interpreter). Verified: `load(chunk, name, "t", env)` runs a chunk in
  a restricted environment with no `_G` leak, and `debug.sethook` is
  available for instruction-count watchdogs against runaway scripts.
  HONESTY LINE: pcall = fault isolation; the restricted env = capability
  restriction. The sandbox is exactly as strong as the whitelist is
  conservative -- any powerful engine userdata we expose is a door. The
  whitelist contents are their own design round, and the no-warnings
  decision means it must start conservative.
- **Execution model (owner-decided 2026-08-17, supersedes the proposed
  two-tier restricted env): the ENTIRE engine Lua API is considered the
  safe sandbox.** Pack buttons run with the same full API as local
  buttons -- no whitelist environment. The safety posture instead
  rests on: (1) the engine's standing principle that the Lua API is
  safe by construction; (2) an API SAFETY REVIEW as a separate,
  explicit task; (3) a RATING system validating packs as safe; (4) a
  KILL SWITCH to remotely disable malicious buttons; (5) conservative
  fault insulation on every run -- pcall everywhere plus the
  instruction-count watchdog (debug.sethook), which is kept.
  Kill-switch shape (to design): a flag the client checks (e.g. a
  killed index or field on the pack record, mirroring how
  /ModuleDeprecated works for modules) that stops execution of
  affected buttons on all clients.

## 5. Open questions

- Section grammar: tiles vs rows per section; what the distinct
  New-tool-panel treatment looks like.
- Auto-close on single add vs stay-open multi-add.
- Community round: everything (action model, trust, distribution,
  presentation).

## 6. Out of scope / rejected

- **Intermediate 3-item menu (Library / New tool panel / All-panels hover
  flyout)** -- rejected 2026-08-16: thin navigation layer; hover-only
  flyout fails accessibility and misclick-cheapness; protects a fast path
  that is rare anyway.
- **Full-screen dimmed modal as the library's form** -- rejected as a
  *default posture* (config sometimes happens mid-session and must not
  block play); the concrete size/position is still open, but "heavyweight
  screen takeover" is off the table.
- **Separate marketplace surface behind a door in a small picker** --
  superseded by the library decision: community lives as a section of the
  library itself.
- **Oversized anchored popup as the library's form** -- rejected
  2026-08-16: a column pinned to the screen edge fights its anchor as soon
  as wide content (tile rows, community cards) arrives, and a tall popup
  anchored low on the rail clips against the screen edge.
