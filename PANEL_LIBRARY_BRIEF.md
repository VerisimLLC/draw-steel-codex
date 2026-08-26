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
   STATUS 2026-08-17: WRITTEN -- Assets/Scripts/ButtonPackLua.cs
   (+.meta), registered as the `buttonpack` global in ScriptEngine.cs
   beside `module`, LuaLS stub at Definitions/buttonpack.lua. Rules are
   DEPLOYED and verified (index/killed publicly readable via REST,
   locked paths still deny). API: Publish{pack,success,failure} (stamps
   id/owner/auto-incremented version/mtime, refuses foreign or killed
   ids BEFORE writing, writes record then index), QueryIndex, Download,
   QueryKilled. Publish never writes the killed field: an admin-set
   kill freezes the record via the validate rule by design. NOT yet
   compile-verified -- no Unity build on this machine; every API call
   was checked against real signatures (DataStore delegates,
   ScriptSerialize JsonStyle, LuaValue factories, ScriptEngine
   CreateTable/Call), so a build should be clean or trivially fixable.
   The codex publish/add flows (steps 3-4) can be written now but only
   TESTED against an engine build that includes this bridge.
3. **Publish flow (codex)**: toolkit right-click "Publish..." dialog,
   payload built from the toolkit's items. STATUS 2026-08-17: WRITTEN
   (RailPublishToolkitDialog + menu entry, gated on the buttonpack
   bridge existing). Pack = name/description/icon + ALL toolkit items
   (panel shortcuts included -- they resolve on any client and unknown
   types already degrade). The minted packid is remembered on the
   toolkit record (per-game), so republishing from the same game
   updates the same pack.
4. **Seamless add (codex)**: COMMUNITY section renders pack cards from
   the index; clicking a button just adds it -- auto-download, per-game
   per-user preference record, button on the rail. No ceremony.
   STATUS 2026-08-17: WRITTEN. Community section queries the index on
   library open (killed packs filtered out), rows show icon/name/count/
   description; click downloads and MATERIALIZES the pack as a toolkit
   in iconrailtoolkits (per-game preference), each item stamped with
   pack = packid; re-clicking updates the same materialized toolkit.
   Falls back to the coming-soon card on engine builds without the
   bridge.
5. **Insulated runner**: pack buttons run with the FULL engine API (the
   API itself is the sandbox -- owner decision), wrapped in pcall, with
   the instruction-count watchdog against runaway scripts, gated by the
   kill switch check. STATUS 2026-08-17: WRITTEN. Kill-switch cache
   (g_buttonPackKilled) fetched lazily + refreshed on library open;
   pack-sourced buttons (item.pack set) check it before running and
   execute under a 20M-instruction debug.sethook watchdog; local
   buttons keep plain pcall. ALL of steps 3-5 are UNTESTED until an
   engine build with the bridge exists -- see the build blocker below.

**END-TO-END VERIFIED 2026-08-17** (build succeeded after the owner
activated the Unity license; ButtonPackLua compiled clean first try):
published the first real pack -- "Quick Rolls", id
5eb99075-648f-4803-8e01-b8890c8d6fc6 -- from the live app via the
bridge; verified the record and index landed in Firebase via REST;
republish auto-incremented to v2/v3; QueryIndex read it back; the
library's COMMUNITY section listed it; clicking it seamlessly
materialized the toolkit on the rail (and a later click UPDATED the
same toolkit in place to the new version); both pack buttons ran
through the insulated path -- real dice physics (DiceScaleDiag roll
START/END, atRest=2/2) and a chat message.

**Roll-macro gotcha for pack authors** (worth docs later): a bare
`dmhub.Roll{roll=...}` creates a PENDING roll awaiting the hurl
gesture, and `chat.Send("/roll ...")` does not roll. The quick-macro
form that hurls immediately is
`dmhub.Roll{ roll = "2d6", ["local"] = true, silent = true, ... }`
(the shop's Try Dice pattern). The Quick Rolls pack uses it.
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
3), watchdog budget and kill-switch data shape (before 5/6).
(Add-per-button vs add-whole-pack: DECIDED 2026-08-17 -- see below.)

- **2026-08-17 -- COMMUNITY becomes COMMUNITY SPOTLIGHT + a full
  Community Browser (owner decision), and community adds land in YOUR
  BUTTONS as standalone rail buttons.** The library section shows the
  four most-hearted community buttons (CommunityFetch pre-sorts by
  hearts, then downloads, then name -- the spotlight earns its name
  honestly) plus a "Browse all community buttons..." row that closes
  the library and opens the COMMUNITY BROWSER: a dedicated 900x700
  window with live search (matches button name/description and pack
  name/author), a sort dropdown (Most hearted / Most downloaded /
  Newest), and every button as a card. Both surfaces share one card
  renderer, one fetch pipeline, and one add path
  (CommunityAddButton): adds now create a pack-stamped STANDALONE
  button (insulated, kill-checked, refresh-on-re-add) instead of
  materializing a per-pack toolkit; legacy materialized toolkits still
  count toward the Added state. VERIFIED live: spotlight renders with
  the browse door; browser opens with search/sort working (search
  matches pack names too -- "roll" matches both Quick Rolls buttons,
  "hello" isolates Say hello); cards show Added overlays. The
  standalone-add path itself is exercised by the same code the
  standalone create flow verified.

- **2026-08-17 -- The vocabulary, in the owner's words: "the
  difference between buttons and panels is that buttons can DO things
  without showing a panel."** A PANEL is a surface you open and look
  at; a BUTTON is an action that just happens. This is the test for
  every future what-goes-where question in the library -- and for what
  a community item is (actions, not surfaces).

- **2026-08-17 -- Library taxonomy: buttons get their own section
  (owner decision: "new button can't be under tool panels").** The
  library's user sections are now kind-pure, each led by its create
  tile: YOUR TOOL PANELS ("New tool panel" + off-rail toolkits), YOUR
  BUTTONS ("New button" + off-rail standalone buttons), COMMUNITY
  (other people's buttons). Discussed and endorsed but NOT yet built: a
  "Share your buttons..." entry in COMMUNITY as the discoverable path
  to the publish flow (currently only reachable via toolkit
  right-click); creation stays out of the compendium -- buttons are
  personal tools, not game content.

- **2026-08-17 -- STANDALONE rail buttons (owner decision: "you
  shouldn't have to create a new tool panel just to create a new
  button").** Script buttons are now first-class rail citizens:
  "button:<id>" layout keys backed by the iconrailscriptbuttons
  per-game preference. The library's "New button" dialog defaults its
  "Add to" dropdown to "On the rail" (toolkits and "New tool panel"
  remain as destinations); the created button sits directly on the
  rail, click runs the script (same insulation rules), right-click
  gives Run / Rearrange / moves / Remove from rail / Edit Script... /
  Delete Button (delete purges the layout entry, same fix pattern as
  RailDeleteToolkit). Off-rail standalone buttons appear as re-add
  tiles in YOUR TOOL PANELS so parking one never strands it. VERIFIED
  live end-to-end: create-on-rail -> click runs (chat post) ->
  context menu -> delete purges definition and layout.

- **2026-08-17 -- Community entries are module-style CARDS (owner
  request): each button card shows the replica face, name, short
  description, author, download count, and a heart count with a
  toggleable heart.** Implementation: per-button `description` field
  (new input in the script-button editor, carried through publish);
  `authorName` denormalized onto pack + index at publish time from the
  account display name; engagement stats at
  /ButtonPackStats/{packid}/{downloads|hearts}/{uid} = true -- per-user
  marks so re-adds/re-hearts cannot inflate counts, own-uid writes
  only, public read (RULES UPDATED in cloud-functions -- NEEDS DEPLOY);
  bridge additions QueryStats / RecordDownload / SetHeart (+ stubs);
  AddSingleButton records a download; the heart is its own swallowPress
  click target with optimistic UI. Stats are PER PACK, shown on each of
  the pack's button cards (the pack stays the unit of publishing, kill,
  and versioning). VERIFIED live post-rebuild: cards render with
  description / "by Venla" / counts; heart toggles optimistically and
  does not trigger the add; server write denied gracefully pending the
  rules deploy (logged, no user-facing error).

- **2026-08-17 -- Already-added community buttons show a darkening
  ADDED overlay (owner request).** A card whose button already exists
  in the user's materialized pack toolkit (matched pack id + button
  name) darkens under a floating #000000a6 overlay with a centered
  check-circle + "Added" label, and its add-click is gated off -- so
  nobody keeps pressing a button they already own. The overlay is
  non-interactable, so the heart beneath it still toggles. Recomputed
  each library open. VERIFIED live: both Quick Rolls cards darken with
  the marker; clicking the card body does nothing; hearting still
  works. (Hover suppression added same day at owner request: an added
  card shows NO hover response -- rule {libPackCard, added, hover}
  holds the rest palette, because a hover glow would promise a click
  the card refuses to honor. Verified: hovering an added card leaves it
  flat.)

- **2026-08-17 -- The COMMUNITY tab shows BUTTONS only (owner
  decision: "for now the community tab has only space for buttons").**
  Every button from every published pack renders as a rail-button
  replica tile (the same grammar as RECOMMENDED and YOUR TOOL PANELS),
  tooltip naming its pack; clicking adds JUST that button. Behind the
  scenes the button lands in a materialized per-pack toolkit
  (kill-switch and update semantics stay per-pack); re-adding a button
  refreshes it in place rather than duplicating. Implementation note:
  the index carries pack metadata only, so the section downloads each
  pack to surface its buttons -- fine at today's pack counts; when the
  index grows, move button {name, icon} metadata into the index
  entries (bridge change). VERIFIED live: two replica tiles rendered
  from the Quick Rolls pack; per-button add updated the existing
  materialized toolkit without duplicating.

- **2026-08-18 -- Publishing goes BUTTON-first: SHARE YOUR BUTTONS
  replaces toolkit publishing (owner decision: "you aren't supposed to
  be able to publish toolkits -- it's just for buttons").** The
  endorsed-but-unbuilt discoverable path is now built: a "Share your
  buttons..." row in the library's COMMUNITY section (present even when
  the index fetch fails -- sharing does not depend on browsing) opens
  the SHARE YOUR BUTTONS dialog (RailShareButtonsDialog): every one of
  the user's own script buttons -- standalone rail buttons and toolkit
  items alike, community-sourced ones excluded -- as a card row (face,
  name, description, where it lives) with a Share control. Sharing
  publishes the button as its own SINGLE-BUTTON pack via
  buttonpack.Publish; the minted packid is remembered on the button's
  definition (`packid`, distinct from `pack` = added-from-community),
  so the control reads Update afterwards and republishing refreshes
  the same pack. The button editor's save paths carry `packid` through
  their item rebuild so editing a shared button does not orphan its
  pack. The toolkit right-click "Publish..." entry and
  RailPublishToolkitDialog are REMOVED; the pack remains the backend
  unit of versioning, kill, and stats, now at one button per pack.
  Migration note: packs published earlier from a multi-button toolkit
  (e.g. Quick Rolls) keep working for consumers, but their toolkit's
  remembered `packid` no longer has a publish surface -- sharing those
  buttons individually mints fresh single-button packs.

- **2026-08-20 -- Vocabulary unified on TOOLKIT (owner decision).**
  The UI had two names for one concept: "tool panel" (library
  section, create tile, both dialog titles, Add-to dropdown) vs
  "Toolkit" (rail menu, every strip's serialized default name). All
  user-facing strings now say toolkit: YOUR TOOLKITS / New toolkit /
  Edit toolkit; the rail menu's "New Toolkit" recased to match.
  Rejected: "tool panel" (clunky; collides with the panels-vs-buttons
  vocabulary -- a toolkit is a container of buttons, not a panel;
  sat confusingly above ALL PANELS), "toolbar" (names the geometry,
  not the concept; generic), "toolrail" (overloads "rail", already
  load-bearing for the edge columns). Settings ids (iconrailtoolkits)
  were already toolkit-named and are unchanged. The library window
  also grew to 900x760 (browser matched -- same-frame rule), the
  header-band hairline and section count chips were removed at owner
  request, and both create tiles now share the plus glyph.

- **2026-08-20 -- Library visual refresh: mockup APPROVED, first
  in-engine attempt REVERTED ("this looks completely chopped" --
  owner).** The owner-approved direction lives at
  ui-mockup/panel-library-redesign.html (same section order, same
  palette, white phosphor icons; rhythm, label-anchored section
  headers with count chips, glyph chips on rows, tile plates, wider
  spotlight cards). The blind translation failed three ways, recorded
  so the next attempt avoids them: (1) the header-label "patch" trick
  assumed the window surface is @bgAlt -- it is not, so labels sat in
  visible grey boxes; (2) 1px bordered plates on the near-black
  window read as a harsh chopped grid, nothing like the mockup's
  soft bgAlt-on-bg values; (3) the added vertical rhythm ate the
  FIXED 700px window's budget and collapsed the ALL PANELS
  "available" scroll region to a sliver. Verdict: NO further blind
  visual passes on this surface -- iterate in the ui-harness with
  screenshots and match the mockup by eye before showing the owner.
  SECOND ATTEMPT SHIPPED same day, harness-verified this time (a
  faithful scratch replica of the window, iterated v1->v3 over the
  HTTP bridge with screenshots at each step): soft FILLS instead of
  borders everywhere (tile plates #ffffff08, no border -- 1px borders
  over near-black were the "chopped" read; create tiles keep a
  parchment-alpha outline as the one accent), label-anchored section
  headers (label + a "100% available"-width hairline filling the
  rest of the row -- available-width works horizontally,
  harness-proven; the count chips shipped briefly and were removed
  at the owner's request same day: "remove these little numbers";
  the header-band hairline likewise removed same day at the owner's
  request -- the section rules carry the structure alone), 28px soft glyph chips on ALL PANELS rows, a
  hairline under the header band, and rhythm tuned (16/10 header
  margins, 8/7 tile pads) so the fixed 700px window keeps 2+ visible
  ALL PANELS rows. Cards move to the same soft-fill language
  (#ffffff08 fill, #ffffff14 border, radius 10). Mockup reference at
  ui-mockup/panel-library-redesign.html.
  Two defects from the same screenshots WERE kept: the compact ADDED
  overlay now shows the check alone over the face (its check+label
  used to strike through the tile name), and a @label face that
  cannot evaluate falls back to the icon instead of showing "-".

- **2026-08-19 -- The COMMUNITY SPOTLIGHT switches to compact square
  tiles (owner request): the styled face, the name, and the
  download/heart counts -- no description, no author.** 96x112
  vertical tiles via CommunityButtonCard's new opts.compact; the heart
  stays its own click target and the ADDED overlay/click gate carry
  over unchanged. The full 410x70 card remains the Community
  Browser's form (descriptions live there).

- **2026-08-19 -- Replica faces get honest: community cards, Share
  Your Buttons rows, and the library's replica tiles now render a
  script button's AUTHORED styling (owner request: "show the actual
  button with its styling in the library").** One shared
  ScriptButtonFacePanel builds the 40px face everywhere:
  @bgcolor/@bggradient/@opacity land as the same selfStyle overrides
  the rail's create applies, and a @label button previews its live
  value (evaluated once on the viewer's character at build) instead
  of its icon. Panel replicas and create tiles pass no def and keep
  the plain chip.

- **2026-08-19 -- Script buttons gain @disabled: a GoblinScript
  condition (owner request: "grey it out and remove interactable
  click and hover, for example if there are no more recoveries").**
  While the condition holds, the button greys (opacity 0.4), loses
  its hover tint and swell (higher-selector-count rules -- count
  ranks before declaration order), plays no sounds, and does not run
  from ANY path (click, strip click, context-menu Run -- gated in
  RunToolkitScriptButton plus the press handlers). Deliberate keeps:
  the hover LABEL stays (with @tooltip it says WHY the button is
  off) and right-click stays (Edit Script must always be reachable).
  Unevaluable (no character, bad formula) = ENABLED, so an error can
  never lock a button out. Evaluated live on the rail refreshRail /
  strip refreshToolkit cadences. Canonical pairing, in the template:
  "@disabled Recoveries Available To Spend < 1".

- **2026-08-19 -- Script edits to an EXISTING button apply LIVE on
  every file save (owner-priority fix for the trap they hit: the
  watched-file flow felt live, but nothing landed until the dialog's
  Save).** The Edit code watcher now commits the SCRIPT to the stored
  record on each save -- script only, mutated in place so name / icon /
  description stay dialog-managed and pack / packid survive -- then
  rebuilds the rail (standalone) or the open strip (toolkit item) so
  directives and hover text follow instantly; the status line appends
  "Applied to the button." A NEW button still requires Create (nothing
  exists to commit to). Known accepted edge: Cancel after a live save
  does not revert already-applied script saves. Template copy updated
  to describe both modes.

- **2026-08-19 -- Script buttons gain @tooltip: author-set hover text
  replacing the button's name, with live state via GoblinScript
  (owner idea: "use recovery" -> "at full stamina").** The directive
  value is tried as GoblinScript first (evaluated on the player's
  current character -- data, never Lua, the @label trust rule) and
  falls back to the raw text when the formula errors or returns
  nothing, which is what makes plain-prose tooltips zero-syntax.
  Uppercased into the rail label voice; re-evaluated on the existing
  refresh cadences (rail refreshRail, strip refreshToolkit), so the
  text updates while the pointer sits on the button. Rendered
  everywhere the button renders: rail hover label and strip hover
  label (StripHoverLabel now accepts a text FUNCTION). Deferred
  alternative, recorded 2026-08-19: an imperative
  scriptbutton.SetHoverText() run-time API -- weaker fit (updates
  only on click, new API surface); can coexist later if a case needs
  it. Implementation note: ScriptButtonHoverText squeezed in as ONE
  new file-scope local -- the chunk is within a handful of locals of
  Lua's 200 cap; the next helpers must ride an existing table.

- **2026-08-19 -- Toolkit window CLUSTERS (owner request): panels
  opened from a strip arrange around it, avoid overlapping other
  windows, and follow the strip when dragged.** Design points, from
  the unanswered sign-off round Claude resolved with its
  recommendations (all reversible): (1) the cluster is ONE transient
  unit -- panels from the same strip stay open together, keyed
  "toolkitcluster:<id>" in g_railTransientKey, and opening from the
  rail or another strip sweeps the unpinned members as one
  (RailSweepTransient now centralizes all five former inline sweep
  sites; one of them had silently skipped the pinned check its
  comment promised -- restored). (2) Placement: remembered per-toolkit
  offset first, else first free spot below/right/left/above the strip
  (then a staggered cascade), screened against every open window and
  strip; cluster placement is ABSOLUTE, beating the panel's
  remembered solo spot. Offsets persist as rec.cluster on the toolkit
  record. (3) Sticky: strip drags move members live (dragging-event
  deltas; the drop applies any remainder so a no-dragging engine
  still snaps them); a hand-dragged member STAYS in the cluster at
  its new offset. (4) The window's close button (or strip-click
  close) leaves the cluster; ESCAPE keeps membership, matching
  escape's keep-everything contract. (4b, owner amendment same day,
  superseding "closing the strip leaves windows in place"):
  DELIBERATELY closing the strip -- rail-button toggle, its own X, or
  deleting the toolkit -- closes every open cluster window with it
  (pinned excepted), via ToolkitCluster.CloseAll. The EditToolkit
  hide/show rebuild and the rail-mode-off teardown do NOT count as
  closing. Offsets survive, so reopening rebuilds the arrangement. Implementation note: helpers live on a single
  ToolkitCluster table -- the file's main chunk is at Lua's 200-local
  limit, loose helper locals no longer fit. The rail root's 0.5s
  transient-liveness check learned the cluster key (a cluster is
  live while ANY member window is open).

- **2026-08-19 -- Toolkit strip buttons drop the generic boxed
  gui.Tooltip for the rail's own hover-label grammar (owner request:
  "more like the ones we have in the rail system").** StripHoverLabel
  gives every strip button -- panel shortcuts, script buttons, and
  the + -- a floating iconRailLabel fading in 10px BELOW the hovered
  button (below, not beside: the row is horizontal, so a side label
  would overlap the neighbour; the group flyout's name-slot pattern
  was rejected here because the toolkit strip is persistent and a
  fixed-width slot is permanent dead width). Inherits the rail rules
  wholesale, including parent:active suppression -- an open panel's
  button shows the close hint, not its name.

- **2026-08-19 -- Script buttons get the classic motion package by
  default: swell on hover (1.08), SQUASH on click (0.9 -- the classic
  game-button press, owner-amended from the grow-pop after feel
  testing; EaseOutBack spring back up to the hover swell over 0.25s),
  back to rest; @clickanim none opts out of both
  (owner picked option A default-on/directive-opt-out, then amended
  the motion to hover-swell + click-pop the same day).** Both button
  constructions (standalone rail, toolkit strip) wear a "scriptAnim"
  class when animating -- it gates the hover-swell style rule; pack
  "panel" shortcuts are excluded (their click opens a window). Every
  run path funnels through RunToolkitScriptButton, which pulses
  "clickPop" before the outcome arrives (a pulsed style fades out
  over ITS OWN transitionTime -- the roll dialogs' "flash" precedent;
  the justDropped clear-through-base mechanism does NOT apply to
  PulseClass). Field-debugged gotcha (2026-08-19): style rules rank
  by SELECTOR COUNT before declaration order, and a click always
  happens under hover -- the pop rule must carry the same selector
  count as the hover-swell rule (and be declared later) or its scale
  silently loses the blend and the pop never shows. Rationale:
  script buttons are the rail's only buttons whose click can otherwise
  vanish without a trace (a panel button's feedback is the window
  opening), so they react bodily and panel buttons deliberately do
  not. New directive `@clickanim pop|none` parsed in
  ScriptButtonStyle (string-only, community-safe); rejected: opt-in
  directive (feature invisible to the users who need it), pop on all
  rail buttons (decoration; re-opens the reviewed rail look).
  Squash-on-press remains a possible future @clickanim variant.
  Community-card replicas do NOT pop (their click means "add", not
  "run").

- **2026-08-18 -- The whole Panel Library surface goes behind a dev
  gate (owner request).** SUPERSEDED 2026-08-24, see below. The hidden
  `dev:panellibrary` setting gated creation of the rail's + button --
  and with it everything only the + opens: the library window, the
  community spotlight/browser, and the Share Your Buttons dialog.

- **2026-08-24 -- The dev gate is gone; the Panel Library is on for
  everyone (owner request).** The `dev:panellibrary` setting is
  deleted, and the rail's + button is created unconditionally (still
  suppressed in rearrange mode, which is the trash zone's territory).
  Nothing else read the setting, so the library window, the community
  spotlight/browser and the Share Your Buttons dialog all come back
  with the +.

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
