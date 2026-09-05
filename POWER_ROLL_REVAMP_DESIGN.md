# Power Roll Revamp - Design Brief

**Status: LOCKED 2026-08-26 (ledger #1-33; #29 two-step confirmed by Ricky).
Implementation in progress - slice S1. Category K (copy) signs off on S1's
final mockup. Do not re-litigate ledger decisions.**

Started 2026-08-26. Driver: Ricky. This document is the single source of truth
for the project; chat is where decisions get made, this file is where they
survive. Supersede-and-rewrite, never accrete.

---

## 1. Framing

**Problem (one sentence):** Test power rolls - skill tests and group resistance
rolls like the werewolf's Howl - still run through the legacy 940x700 roll
dialog (`Draw Steel UI/DSRollDialog.lua`): it blocks the center of the screen,
gives no per-participant visibility during group rolls, has no home for
perks/traits/treasures that modify tests, and leaves players staring at nothing
between pressing Roll and the director's Proceed.

**Personas:**
- **Players (set-and-forget):** immediate feedback the moment their dice land;
  a clear "waiting on X and Y" signal instead of dead air.
- **Director (power user):** a live roster of everyone's results with
  portraits, tiers, and per-row override; control over when outcomes apply.

**Why now:** The Howl playtest made the pain concrete, and the ability
power-roll flow (ability card + `Timeline/EmbeddedRollDialog.lua`) has proven
the visual and interaction language. The gap between the two experiences is
the most visible legacy seam in the app.

**Done looks like:** A test roll - solo or party-wide - runs in a side-docked
surface with the ability-card aesthetic: participant roster with portraits,
per-person dice results and tier as they land, tier text from the test
outcome, a modifier/trigger area (edges/banes, skills, and feature-driven
options like Lucky Dog), tier override, and a results state that stays up for
everyone until explicitly accepted.

### Decision ledger (locked - do not re-litigate)

| # | Date | Decision | Rationale |
|---|------|----------|-----------|
| 1 | 2026-08-26 | Scope of first ship = ALL test rolls (group AND solo character-sheet tests). Downtime project rolls / montage explicitly later phases. | One surface, one migration; solo tests already half-migrated via `ShowCharacteristicRollDialog`. |
| 2 | 2026-08-26 | Tier override: director AND the row's owner can override their own row. Overrides must carry visible attribution (never silent). | Ricky's call; attribution is the guardrail that makes owner-override safe. |
| 3 | 2026-08-26 | The legacy fullscreen dialog is RETIRED for tests once this ships. It remains only for out-of-scope roll types. | Retiring it also retires a 3,340-line near-fork of EmbeddedRollDialog. |
| 4 | 2026-08-26 | Surface = EXTEND the Timeline stack (`EmbeddedRollDialog` + right-docked sidebar). Tests route through `g_timelineRollTypes`; no new roll dialog, no DSRollDialog rehab. | All modern features (after-roll mods, triggers, override, spectator mirror) come free; `ShowCharacteristicRollDialog` proves the path; avoids a third fork. |
| 5 | 2026-08-26 | A PURPOSE-BUILT test card renders above the roll dialog (shares `SpellRenderStyles` vocabulary: head band = test name, skill/characteristic row, tier outcomes). NOT a synthetic ability card. | Ability-shaped framing reads wrong for tests; the participant roster needs a home the ability card cannot give it. |
| 6 | 2026-08-26 | Migration = one roll type per slice via `g_timelineRollTypes` (`test_power_roll`, then resistance custom-check path, then solo entry points). Every slice leaves the app working. | Matches the small-deployable-slices rule; opposed rolls already proved the valve. |
| 7 | 2026-08-26 | Sync model = EXTEND `RollRequest` on `/actionRequests` as the single source of truth: add a real `tier` field, per-token roll guid (pre-assigned so all clients can watch dice live), and an accept lifecycle. No second store. | Smallest delta on proven plumbing; dice-spectating via `chat.GetRollInfo` + `chat.DiceEvents` is the worked DSInitiativeRoll pattern. Undo-noise + same-requester-clears edge cases owned by category I. |
| 8 | 2026-08-26 | ONE shared roster surface for everyone: the right-docked test card hosts the roster on every client; director-only controls (Take Roll, Re-roll, Remove, Accept) render inline on rows. The legacy DM Request Rolls summary retires for tests. | Form follows function - same roll, same surface, role-gated affordances. No dual-surface sync burden. |
| 9 | 2026-08-26 | Audience = ALL connected clients see the group-roll roster (subject to dice-tower/private-roll visibility, category I), not just participants. | Group rolls are a table moment; matches the ability spectator-mirror instinct. |
| 10 | 2026-08-26 | Roster anatomy = C1 LEDGER ROWS (portrait, name, live d10s, bonus, total, tier chip; ~34px/row) PLUS portraits landing on the tier table rows as dice settle (C2's trick, already supported by the tier table's per-target portrait column). Outcome text on row hover/expand, not always-on. States: Waiting / Rolling / Rolled / Overridden-with-attribution / Declined, each labeled by text+form, never color alone. Mockup: "Group Test Roster" artifact (companion, not truth). | Carries the requested per-person dice detail at a cost the 360 dock affords; tier table doubles as group summary. |
| 11 | 2026-08-26 | Player rolls IN the persistent test card: roll controls (edge/bane bar, modifier badges, Roll button) embed in the card and collapse in place once dice land; the player transitions actor->spectator inside one surface. No separate roll popup. | Fixes the vanishing-dialog jank; reuses the embedded dialog's phase-walk grammar. |
| 12 | 2026-08-26 | Immediate tier reveal, deferred application: a player's tier highlights the moment their dice settle; effect application waits for the director's Accept. The deferral is made legible ("Waiting on X and Y...", "results apply when the Director accepts"). | The playtest pain was silence, not the gate itself. |
| 13 | 2026-08-26 | Proceed becomes a DIRECTOR-ARMED ACCEPT on the roster: disabled with waiting copy until every row is complete/declined/removed, then arms. After Accept the roster shows a RESOLVED state; each client dismisses it locally (Done). | Preserves the override/perk window (Lucky Dog decisions happen after seeing a failure); local dismiss delivers "stays up until the user accepts". |
| 14 | 2026-08-26 | RESOLVE-IN-PLACE persistence: Accept stamps `resolved` + final tiers on the request doc and applies outcomes WITHOUT cancelling it; the doc is cleaned up when superseded by the requester's next request (engine auto-clear) or by a timed expiry. | Resolved state is real shared state - late/reconnecting clients still see it; the local-snapshot alternative silently depends on being present at the accept moment. |
| 15 | 2026-08-26 | Re-roll = wipe + attribution: the row returns to Waiting with a "Director asked X to re-roll" line; prior result discarded. Struck-through history recorded as a later nice-to-have (section 4). | Simplest to sync; attribution keeps it non-silent. |
| 16 | 2026-08-26 | Authority stays last-writer-wins with role-gated UI (owner writes own row, director writes any); every mutation attributed by userid. No arbitration layer. | No engine precedent for arbitration; attribution (ledger #2) covers the practical risk. |
| 17 | 2026-08-26 | Undo-stack noise from forced-undoable action-request writes is ACCEPTED for v1. Engine ask recorded: `{undoable=false}` support on `LuaPlayerActionRequest:CompleteChanges` (add to the omnibus engine-PR list). | Living with noise beats splitting state across a second store (would violate ledger #7). |
| 18 | 2026-08-26 | Tier override = the ABILITY-FLOW GESTURE: click a tier table row directly (Ricky's call, differs from the chip-picker recommendation). A player's table click overrides their OWN roll; the director's click applies to the focused/selected roster row. ALSO clickable BEFORE rolling: a pre-roll tier click declares the outcome without dice (precedent: `overrideTier` stamped pre-roll by the test harness). Same permission model as ledger #2 (owner + director), always attributed ("X chose Tier 2 without rolling"). | Consistency with the ability roll wins; pre-roll declaration doubles as the director's skip-the-dice affordance. |
| 19 | 2026-08-26 | Override window closes at Accept; post-resolve corrections go through the existing chat-card amend path. | Resolved means resolved; the chat card already handles post-hoc amendment. |
| 20 | 2026-08-26 | After-roll modifier support ships in v1 for tests (comes nearly free from ledger #4 - collection is already rollType-generic; only the legacy dialog lacked the UI). Render grammar = the ability dialog's: pre-roll modifier badges + an after-roll badge section once dice land. | The perk/treasure/trait "space" Ricky asked for IS this section. |
| 21 | 2026-08-26 | Lucky Dog itself does NOT ship in v1 - it was an example of the future capability, not a deliverable. The cost+tier-shift-once-per-test primitive is recorded as the target shape the after-roll space must eventually host. | Ricky's clarification; v1 proves the space, content passes fill it. |
| 22 | 2026-08-26 | Parry-style triggers on tests = PHASE 2. The trigger rail on the card is designed-for but unpopulated in v1; generalizing the ability-bound dispatch loop (`TriggerModsPowerRoll`'s single call site) lands later. | Thin real demand (most test features are self-activated); longest plumbing pole kept off the critical path. |
| 23 | 2026-08-26 | NO group-outcome aggregation in v1 (Ricky's call; the display-only tally recommendation was declined). Rows only; the director adjudicates group success. Both the tally and rules-active group outcomes go to section 4 as revisitable. | Keeps v1 scope tight. |
| 24 | 2026-08-26 | Edge-case batch (decided by recommendation): late joiners render from the request doc (free); a Rolling row whose user goes offline flips to Disconnected after a grace period with Take Roll as recovery; Take Roll / Remove / forceuserid machinery preserved inline on rows; auto-roll profiles, roll-all-prompts, quick-roll, AI and dice-tower auto-proceed keep current semantics; concurrent requests = newest renders, rest queue (engine auto-clears same-requester); decline preserved and does not block Accept arming. | All machinery exists; no reason to diverge. |
| 25 | 2026-08-26 | Hidden rolls = REDACTED ROWS: everyone sees portraits + states; numbers, tier chips, and table landings render only for the director (and each player's own row per existing visibility rules). | The moment stays shared, the secrets stay secret. |
| 26 | 2026-08-26 | Minimize is DROPPED in v1 - the one deliberate capability drop from the 47-item inventory. The docked surface is non-blocking by construction. Revisit if playtests miss it. | The affordance existed to mitigate a fullscreen dialog that no longer exists. |
| 27 | 2026-08-26 | Phasing = slices S1-S6 as ordered in section 3.7 (card-solo first, then wire, requested tests, shared roster + Accept, resistance rolls, modifier space + retirement). Each slice independently shippable and leaves the app working. | De-risks the new card before the new sync; Howl lands at S5. |
| 28 | 2026-08-26 (critique) | Host & gate policy: the test card stops counting as a blocking roll dialog once the local player's controls collapse; test/resistance prompts are flagged `parallelWithRollDialog`; an ability cast displaces the card with a "Test pending: <name>" banner and the card re-renders from the doc on teardown; re-roll and Take Roll are IN-CARD transitions (controls (re-)expand in place / inline on the row), never fresh listener prompts; requester-side serialization - no new request sends while this requester has an unresolved one (hold + auto-send on Accept). This SPECIFIES #24's queue promise. | All three critics independently hit this: the old plumbing was safe only because tests lived in a separate singleton dialog. |
| 29 | 2026-08-26 (critique) | Tier-click guard rails refining #18: pre-roll clicks are a TWO-STEP commit in place (first click highlights + shows an inline "Declare Tier N - no roll" chip, second click commits); post-roll override stays one-step; owners can withdraw their own declaration/override before Accept (attributed); the director's override requires an explicit visible row selection (non-color marker + "Overriding: <name>" line) and table clicks are INERT with no row selected; outcome-text expansion lives ONLY on roster rows (dedicated chevron zone), never on the tier table. | Two critics flagged the unguarded pre-roll click as a blocker (read-gesture collision); the focused-row ambiguity was a mode-error factory. Gesture preserved, accidents prevented. Two-step pre-roll commit confirmed by Ricky. |
| 30 | 2026-08-26 (critique) | Accept-timing refinements to #13: a row with unresolved after-roll options shows a "Deciding" state and its owner commits with "Keep result" - Accept arms on all-COMMITTED, not all-rolled (rows with no options auto-commit). Accept exists ONLY for requested rolls; solo self-initiated tests apply on dice settle (no roster, no gate). Existing AI/dice-tower auto-proceed maps to auto-commit/auto-Accept. On supersede or fast chaining, clients keep a presentation-only linger of an unread resolved roster until Done or timeout. | Without this, Accept races the after-roll window it exists to protect, solo sheet tests would regress behind a gate, and chained requests would erase resolved state mid-read. |
| 31 | 2026-08-26 (critique) | Redaction hardening of #25: non-privileged clients see redacted rows with a COLLAPSED state set (Waiting / Rolling / Done only) and value-free attribution ("Director adjusted this result"); full states, values, and attribution render only for the director and the row's owner. Redaction is itself a text+form state (label + placeholder glyph). | The state grammar and attribution lines were a metagame side channel through the redaction. |
| 32 | 2026-08-26 (critique) | Accessibility & responsiveness contract: all roster/card sizes in em/sp with a declared column-drop order for Font Size 120-140% (bonus column folds into expand first, then dice minis become totals-only) and a 12px base floor; tier is ALWAYS numeral/glyph + position, color reinforcement only; every pulse/flash routes through the animation setting, batch landings coalesce (max one flash/sec); "your roll is pending" and "Accept armed" get persistent VISUAL states (header treatment + icon-rail badge/dock pulse) with sound as reinforcement; director row actions behind a per-row kebab (Take Roll inline only on Disconnected rows), 24px minimum targets, confirm on Re-roll of a Rolled/Overridden row; row grammar is two-layer (glance: portrait/name/state-tier/total; detail on expand: dice, bonus, attribution); landed tier row gets a persistent non-color marker; declined rows show owner-side "Roll anyway" until Accept. Keyboard operability recorded out of scope (framework has no keyboard path). | Consolidated from the accessibility critique; the 140% Font Size failure was a blocker. |
| 33 | 2026-08-26 (critique) | Integrity latches: resolution is MONOTONIC at the read layer (per-request-id local latch; a rewound doc renders resolved and Accept refuses to double-fire) until the `{undoable=false}` engine ask lands; physical-dice-bridge rolls must produce a sane Rolled row (clean skip of Rolling, correct tier) - J-gate item; multi-token clients re-arm the in-card roll controls per owned token sequentially with a "your roll" row marker, and roll-all-prompts is re-verified against embedded sequencing at S3. | Undo could un-resolve an accepted request while applied outcomes stayed; the bridge and multi-prompt paths were unspecified. |

---

## 2. Decision map (Phase 3 - categories to work, in order)

Worked one category per round. Status: [ ] open, [x] decided (see ledger).

- [x] **A. Architecture & routing** - DECIDED (ledger #4-6): extend Timeline;
  purpose-built test card; per-type migration slices.
- [x] **B. Group roster: surface & sync model** - DECIDED (ledger #7-9):
  extend RollRequest as single store; one shared right-docked surface for
  every client; all clients see it.
- [x] **C. Roster row anatomy & live dice** - DECIDED (ledger #10): C1 ledger
  rows + tier-table portrait landings; state grammar fixed; mockup artifact
  published.
- [x] **D. Player feedback loop** - DECIDED (ledger #11-13): roll inside the
  persistent card; immediate tier reveal w/ deferred application;
  director-armed Accept + resolved state + local dismiss.
- [x] **E. Accept, persistence & authority** - DECIDED (ledger #14-17):
  resolve-in-place; re-roll wipes with attribution; last-writer-wins +
  role-gated UI; undo noise accepted with engine ask recorded.
- [x] **F. Tier override surfaces** - DECIDED (ledger #18-19): direct tier
  table row click (incl. pre-roll declaration); window closes at Accept.
- [x] **G. Modifiers, perks & triggers on tests** - DECIDED (ledger #20-22):
  after-roll modifier space ships v1; Lucky Dog deferred (example only);
  triggers phase 2.
- [x] **H. Group-outcome semantics** - DECIDED (ledger #23): nothing in v1;
  tally + rules-active outcomes recorded as revisitable.
- [x] **I. States & edge cases** - DECIDED (ledger #24-26): edge-case batch;
  redacted rows for hidden rolls; minimize dropped.
- [x] **J. Regression surface** - STANDING GATE, not a debate: the 47-item
  inventory (appendix E4) is the checklist each slice verifies before it
  ships. The embedded dialog is a near-superset of the legacy one; the ONLY
  approved drop is minimize (ledger #26). Three items need a new home in the
  card's roll controls and get verified at slice time: the in-dialog
  visibility dropdown + save-default check (embedded surfaces visibility via
  the card banner/eyelid instead), the auto-roll checkbox cluster, and the
  roll-all-prompts check (listener-side, should carry over unchanged).
- [ ] **K. Copy** - every user-facing string signed off explicitly. Runs as a
  copy-manifest round on the final mockup, after the critique round. Known
  strings to sign: waiting line (count-first: "Waiting on 2 - Kira, Voss"),
  re-roll/override/declared-without-rolling/withdrawn attribution lines,
  Accept button states, resolved header, Done, redacted state label + the
  value-free redacted attribution variants, Disconnected state, "Deciding" /
  "Keep result", "Roll anyway", the pre-roll declare chip ("Declare Tier N -
  no roll"), "Test pending: <name>" banner, "Overriding: <name>", and the
  expand cross-reference line.
- [x] **L. Accessibility & performance** - RECORDED as constraints: tier
  states always text+form, never color alone (ledger #10); outcome text must
  be reachable by click/expand, not hover-only; one `monitorGame` on
  `/actionRequests` with signature-gated rebuilds; DiceEvents listeners
  scoped per active roll and unlistened on settle; no per-frame roster
  rebuilds.
- [x] **M. Phasing** - DECIDED (ledger #27): slices S1-S6, section 3.7.

---

## 3. Decided design

Everything here is settled (ledger # in parentheses) unless listed in section 5.

### 3.1 Surface & architecture

Tests run on the Timeline stack: the right-docked sidebar host (360 wide,
`interactable=false`, margin-tracked) carrying a PURPOSE-BUILT TEST CARD plus
the embedded roll dialog (#4, #5). The card shares `SpellRenderStyles`
vocabulary: head band with the test name (band color: open question Q1),
characteristic/skill row, the tier table, and the participant roster. Requested
rolls reach it through `g_timelineRollTypes`, migrated one type per slice (#6).
`DSRollDialog` retires for tests at the end (#3).

Host & gate policy (#28): the card is a blocking roll dialog only while the
LOCAL player's roll controls are active; once they collapse, the prompt-queue
gate releases. Test/resistance prompts carry `parallelWithRollDialog`. An
ability cast displaces the card ("Test pending: <name>" banner) and the card
re-renders from the doc on teardown. Re-roll and Take Roll are in-card
transitions, never fresh listener prompts. A requester with an unresolved
request cannot send another - the composer/cast paths hold locally and
auto-send on Accept.

### 3.2 Group roll lifecycle

Single source of truth: the `RollRequest` on `/actionRequests`, extended with a
real per-token `tier`, a pre-assigned per-token `rollid`, and a resolved
lifecycle (#7). Flow:

1. Director sends the request (existing Request Rolls composer).
2. Every client renders the test card + roster from the doc (#8, #9).
3. A prompted player's roll controls (edge/bane bar, modifier badges, Roll)
   embed IN the card and collapse in place when their dice land (#11).
4. Dice are watched live on every client via `chat.GetRollInfo(rollid)` +
   `chat.DiceEvents` (the DSInitiativeRoll pattern); tiers reveal the moment
   dice settle, effect application waits for Accept (#12).
5. Rows with unresolved after-roll options show "Deciding"; the owner commits
   with "Keep result" (rows with no options auto-commit). Director-armed
   ACCEPT: disabled with waiting copy until all rows are
   COMMITTED/declined/removed, then arms with a visible state change; on
   press, outcomes apply and the doc is stamped `resolved` + final tiers
   WITHOUT being cancelled (#13, #14, #30).
6. Resolved roster persists (cleaned up on supersede or timed expiry); each
   client dismisses locally with Done. Clients keep a presentation-only
   linger of an unread resolved roster through supersede (#13, #14, #30).
7. Accept exists ONLY for requested rolls; solo self-initiated tests apply on
   dice settle - no roster, no gate (#30). Resolution is monotonic per
   request id at the read layer (#33).

### 3.3 Roster

C1 ledger rows + tier-table landings (#10), sized in em/sp with the #32
column-drop order: per participant a row (2.4em-class height) with
portrait, name, both d10s streaming live, bonus, total, tier chip; the
GLANCE layer is portrait/name/state-tier/total, everything else lives in the
row expand (#32); portraits
also land on the tier table's per-target portrait column as dice settle, so
the table doubles as the group summary. Outcome text on row click/expand (not
hover-only, per L). Row states: Waiting / Rolling / Rolled /
Overridden-with-attribution / Declined / Disconnected - each text+form, never
color alone. No group tally in v1 (#23). Hidden rolls = redacted rows: states
for everyone, numbers only for the director and the row's owner (#25).
Companion mockup: "Group Test Roster" artifact (mockup, not truth).

### 3.4 Overrides & authority

Tier override = click the tier table row directly, the ability-flow gesture
(#18): a player's click overrides their own roll; the director's applies to
an EXPLICITLY SELECTED roster row (visible non-color marker + "Overriding:
<name>" line; inert clicks with no selection). Pre-roll clicks declare an
outcome without dice via a two-step in-place commit; owners can withdraw
their own declaration/override before Accept, attributed (#29 - two-step
pending Ricky's veto). Outcome-text expansion lives only on roster rows
(chevron zone), never the tier table (#29). Permission: owner + director
(#2), every mutation attributed by userid (#16); window closes at Accept,
post-resolve corrections via the chat-card amend path (#19). Re-roll wipes
the row back to Waiting with attribution, confirmed when the row is
Rolled/Overridden (#15, #32). Authority model stays last-writer-wins with
role-gated UI (#16); undo noise accepted, engine ask recorded (#17), with
the monotonic-resolve latch guarding double-application (#33).

### 3.5 Modifiers & future perk space

Pre-roll modifier badges + an after-roll badge section, same grammar as the
ability dialog, wired for `test_power_roll`/`resistance_power_roll` (#20).
Lucky Dog is the target SHAPE (after-roll cost + tier-shift + once-per-test),
not a v1 deliverable (#21). Triggers on tests are phase 2; the rail is
designed-for but unpopulated (#22).

### 3.6 Edge cases

Late joiners render from the doc; Disconnected state after a grace period with
Take Roll as recovery (inline on Disconnected rows; other director actions
behind a per-row kebab, #32); Take Roll / Remove / auto-roll profiles /
roll-all-prompts / quick-roll / AI + dice-tower auto-proceed all keep current
semantics (auto-proceed maps to auto-commit/auto-Accept, #30); requester-side
serialization implements the queue (#28); decline never blocks Accept arming,
and the owner of a declined row gets "Roll anyway" until Accept (#24, #32).
Redacted rows collapse to Waiting/Rolling/Done with value-free attribution
for non-privileged clients (#31). Multi-token clients re-arm roll controls
per owned token sequentially (#33). Minimize dropped (#26).

Named verification cases (J gate): double-ability + test contention repro
(S3); "Howl + AFK player + Take Roll" (S5); physical-dice bridge produces a
sane Rolled row (S3/S4); roll-all-prompts under embedded sequencing (S3);
Font Size 80-140% roster sweep (S1, S4).

### 3.7 Slices (#27)

- **S1 - Test card, solo:** build the card; swap it into
  `ShowCharacteristicRollDialog` + journal player tests. No wire changes.
- **S2 - Wire extensions:** `RollRequest` gains tier/rollid/resolved fields;
  writers populate, legacy readers ignore.
- **S3 - Requested tests roll in the card:** `test_power_roll` joins
  `g_timelineRollTypes`; roll-in-place + immediate tier reveal for the
  prompted player. Legacy DM summary still functions.
- **S4 - Shared roster + Accept:** roster on every client (states, live dice,
  landings, redaction, override, disconnect); Accept/resolve/dismiss; DM
  summary retires for tests.
- **S5 - Resistance rolls:** custom-check reroute (`ShowRollPrompt` ordering)
  + `RequireSavingThrowsCo` accept integration. THE HOWL CASE LANDS HERE.
- **S6 - Modifier space + polish + retirement:** after-roll section, pre-roll
  declaration, DSRollDialog retirement for tests behind the J gate.

---

## 4. Out of scope / rejected

- Downtime project rolls and montage tests: later phase (ledger #1).
- Group-outcome tally ("N of M at Tier 2+") and rules-active group outcomes:
  declined for v1 (ledger #23); revisitable, should align with Montage/Heroic
  Test evolution.
- Lucky Dog implementation: deferred content pass (ledger #21); target shape =
  after-roll cost + tier-shift + once-per-test.
- Struck-through re-roll history: later nice-to-have (ledger #15).
- Triggers on tests: phase 2 (ledger #22).
- Keyboard operability: deliberately out of scope - the gui framework has no
  keyboard path; recorded so the omission is a decision, not an accident. If
  the framework ever grows one, Accept / Done / Roll are the priority
  controls (#32).

---

## 5. Open questions

- **Q1:** Head-band color for tests. The action color keys are
  scheme-independent literals (main #8E2B2B, maneuver #2C5F8A, etc.); tests
  need either the neutral graphite (#1C1C1C, "none") shown in the mockup or a
  new dedicated key. Decide during S1 with the card in front of us.
- **Q2:** Copy manifest (category K) - runs after the critique round on the
  final mockup.
- **Q3:** Exact expiry timing for a resolved request that is never superseded
  (#14) - pick a default during S4.

---

## 6. Implementation log

### S1 - Test card, solo (2026-08-26) - built and live-verified

- `TestRollCard` game type + `:Render` live in `Draw Steel Core
  Rules/MCDMActivatedAbility.lua` beside the card style machinery it reuses
  (`SpellRenderStyles`, `ActionColorKeyStyles`, the close-button contract).
  Band = `ms-action-none` graphite pending Q1.
- `Timeline/AbilitySidebar.lua` showAbility renders a TestRollCard like a
  TriggeredAbilityDisplay, branching before the raw `categorization` read
  (which raises on unknown game-type fields).
- `Draw Steel Core Rules/MCDMCreature.lua`: local `ShowSoloTestRoll` helper
  (queue-wait + card + embed + ShowDialog with single-target tier refresh);
  `ShowCharacteristicRollDialog` and `RollCustomPowerTableTest` are thin
  wrappers over it. The journal path gained the Timeline surface,
  showDialogDuringRoll, amendable, and post-roll tier refresh. Characteristic
  tests pass no cardTiers.
- Verified live: Might Test and Climb the Cliff cards render docked right;
  close tears down card + dialog cleanly.
- Gotcha: a nil child in a gui.Panel constructor's array part truncates
  ipairs, so optional children (the skill line) are appended to an args table.
- Leftovers: Font Size 80-140% sweep (J gate), theme-switch check, copy pass
  (K) incl. the "Skills:" line, Q1 band color, field test.

## Appendix E: Evidence (verified 2026-08-26, file:line anchors from audits)

### E1. The gold-standard surface (what we are matching)

- Host chain: `GameHud:CreateAbilityDisplayPanel()` (`DMHub Game
  Hud/GameHud.lua:1740-1761`) - right-docked, width 360, `interactable=false`;
  margin-tracked against the icon rail (`:1715-1738`). A 540-wide standalone
  host exists (`:1771-1794`) with `InitStandaloneRollHost`
  (`Timeline/AbilitySidebar.lua:1979-2028`).
- The card: `ActivatedAbility:Render` (`Draw Steel Core
  Rules/MCDMActivatedAbility.lua:811-2678`); `SpellRenderStyles` (`:25-198`)
  themed via `ThemeEngine.MergeStyles`; color-keyed head band (`:224-268`);
  scroll frame with bleed for bookmark tabs (`:771-809`).
- The roll dialog: `GameHud.CreateEmbeddedRollDialog()`
  (`Timeline/EmbeddedRollDialog.lua:459`), width 340; phase state machine
  `rolling`/`finishedRolling`/`rollPending` (`:703-851`); the accent band
  walks Roll Dice -> Results -> Triggers as phases advance.
- Tier table: `ActivatedAbilityPowerRollBehavior.GetPowerTablePopulateCustom`
  (`Draw Steel Core Rules/MCDMAbilityRollBehavior.lua:461-872`) - FULLY
  GENERIC: works with plain rollProperties, optional caster/options; already
  called ability-less from `MCDMCreature.lua:4743,4800`. Contains tier
  highlight, flash, audio, or-choices, click-to-override (`pressTierRow`
  `:722-745` -> `overrideTier` + `UploadProperties` = cross-client), and a
  per-target portrait column (`:829-860`).
- Modifier badges: `ModifierPanel` (`EmbeddedRollDialog.lua:342-456`);
  pre-roll container `:3213-3610`; after-roll container `:3612-3776`.
- Triggers: `CreateTriggerPanel` (`:1656-1947`); cross-client dispatch via
  `token.properties:DispatchAvailableTrigger` (`:2221-2234`) and readback on
  `charactersUpdated` (`:2288-2341`).
- Spectator mirror: shared doc `"abilityTimelineShare"`
  (`AbilitySidebar.lua:45,81-135`), read-only mirror `:355-1029`, replays
  remote dice via `chat.DiceEvents` by rollId (`:698-728`), 10s heartbeat.
- **Existing proof-of-concept:** `creature:ShowCharacteristicRollDialog`
  (`MCDMCreature.lua:4753-4907`) already drives a characteristic TEST through
  this surface: synthetic `ActivatedAbility.Create{isTest=true}`, synthetic
  single-entry multitargets (so post-roll tier refresh runs), embeds via
  `CharacterPanel.EmbedDialogInAbility()`. The simpler legacy variant is
  `RollCustomPowerTableTest` (`:4707-4750`).

### E2. The legacy dialog and why players see nothing

- `Draw Steel UI/DSRollDialog.lua` (3,340 lines) is a near-fork of
  EmbeddedRollDialog serving the singleton `GameHud.instance.rollDialog`
  (created `GameHud.lua:1268`, mounted `:1638`, drawn ABOVE modals). 940x700
  centered card, `blurBackground`, no scrim. Partly themed, 7 raw hex
  literals, legacy `Styles.AdvantageBar`.
- Routing: `ShowRollPrompt` (`Draw Steel UI/DSRequestRollsDialog.lua:642-662`)
  sends anything not in `g_timelineRollTypes = {opposed_power_roll=true}`
  (`:466-468`) to the legacy dialog. Custom checks with `ShowDialog`
  (resistance rolls, `MCDMAbilityRollBehavior.lua:3448-3487`) can NEVER route
  to Timeline (checked first at `:647-650`). Comment at `:466` says migration
  is deliberate, one type at a time.
- Why no player feedback (four independent causes):
  1. Request-driven tests never pass `showDialogDuringRoll`, so the player's
     dialog hides the instant Roll is pressed (`DSRollDialog.lua:2961-2964`).
  2. Tier rows only become selectable/highlighted via the dialog's own think
     loop - already hidden.
  3. The outcome is written to the request doc
     (`DSRequestRollsDialog.lua:905-911`) but its ONLY renderer is the
     DM-only Request Rolls summary (`:1957-1962`, panel hidden for non-DM
     `:2245-2247`).
  4. The chat card is not `amendable` for these rolls, so its tier rows are
     inert.
- Tests today get NO triggers (`triggersContainer` needs multitargets;
  requested tests pass none) and NO after-roll modifiers (zero references in
  DSRollDialog.lua).
- Entry points inventory: director Request Rolls panel (`:1164`,`:1745`);
  resistance rolls via `CastResistance` -> `RequireSavingThrowsCo`
  (`MCDMAbilityRollBehavior.lua:3495-3545`, blocks on `dcresult.result`);
  characteristic test (`MCDMCharacterPanel.lua:6231`); journal/heroic-test
  documents; downtime projects (`DTProjectRollDialog.lua:877-935`, tier table
  commented out); jump (`AbilityJump.lua:363-374`); legacy 5e paths in
  `Creature.lua`.

### E3. Group roll plumbing (`/actionRequests`)

- `RollRequest` / `RollCheck` are Lua `RegisterGameType`s
  (`DSRequestRollsDialog.lua:56-85`) sent via `dmhub.SendActionRequest`
  (`Definitions/dmhub.lua:1965`; auto-clears prior requests from the same
  requester unless silent). Observed with `monitorGame = "/actionRequests"`.
- Per-token status machine written by the ROLLING client: nil -> 'dialog'
  (+userid) -> 'rolling' -> 'complete' (result, naturalRoll, boons, banes,
  outcome) or 'cancel' (`:882-955`). Director can stamp `forceuserid` (Take
  Roll `:1875-1879`); Re-roll wipes the record (`:1856-1885`) - no history.
- **No tier on the wire**: only `outcome.outcome == "Tier N"` string.
  `RollRequest:GetTokenResult` deliberately returns nil in the DS override.
- Prompt eligibility decided locally per client (`:740-759`): canControl AND
  (not DM OR token not player-controlled OR no players online). One prompt at
  a time per client; deferred behind open roll dialogs
  (`CharacterPanel.AnyRollDialogShown`).
- The proceed gate: director summary computes `hasIncomplete`; button flips
  Cancel->Proceed (`:2164`); press sets `resultTable.result` then
  `dmhub.CancelActionRequest` (`:1779-1791`) - the record is DESTROYED on
  proceed. Caster-side coroutine blocks on `dcresult.result`
  (`ActivatedAbility.lua:3434-3436`) then runs per-target tier commands
  (`MCDMAbilityRollBehavior.lua:3536-3545`).
- Authority: none - last-writer-wins replicated blob; every status transition
  is unconditionally undoable (`LuaPlayerActionRequest:CompleteChanges`,
  `Definitions/LuaPlayerActionRequest.lua:13-17`).

### E4. Legacy-dialog capability inventory (regression checklist)

47 items catalogued in the audit (2026-08-26): roll-formula free text edit;
modifier checkboxes w/ tooltips + justification; multi-charge modifiers;
caller checkboxes; modifier dropdowns incl. disableRoll; edge/bane slider +
reset; surge spend (ability rolls only); alternate-check selector;
rollRequirement gating; spoiler redaction; multi-target strip w/ per-target
modifiers/surges; per-target boon normalization; trigger cards (activate,
right-click DM menu, ping, augmentations); trigger dispatch/clear + sync;
applyToAllTargets; forceReroll; HoldAmendableRollOpen; Roll/Cancel/close;
minimize (300x100); auto-roll x3 + named profiles + hideFromPlayers +
quickRoll; skipDeterministic fast path; roll-all-prompts; visibility
(Everyone/Director/Dice tower) + save-default; silent/instant/delayed;
coroutine serialization + queueing; tableRef delegation; rolling/finished
state machine; Accept Result; Re-roll via Amend; AI auto-proceed + 5s trigger
timer; dice-tower auto-proceed for non-DMs; resource consumption attribution;
trigger cost payment; surge accounting; ongoing effects to self; retarget
recording; castid stamping; OnBeforeRoll/OnReroll/OnRollCancelled/
OnBeforeTableRoll hooks (consumed by physical-dice bridge + Acolyte); rich
presence; Notify.Diceroll sound; target damage hints; chat events scoping; AI
off-screen parking; nofadein; preview-dice cleanup (engine bug XPWBKEQA);
live re-theme; IsShown/Cancel/rollid public surface (used by
AbilityInvokeAbility.lua:822).

### E5. Engine capabilities (verified)

- **Cross-client per-die observation works**: `chat.GetRollInfo(rollid)` ->
  iterate `rollInfo.rolls` -> `chat.DiceEvents(guid):Listen(panel)` ->
  `diceface(diceguid, num, timeRemaining)` fires on every client during
  replay (`Definitions/chat.lua:6-11`, `DiceInstanceLua.lua:12-16`; worked
  pattern `Draw Steel UI/DSInitiativeRoll.lua:355-386`). Individual d10
  values replicate in `ChatMessageDiceRollInfoLua.rolls[].result`.
- **No engine dice-settled event** - synthesized from `timeRemaining`
  (`MCDMAbilityRollBehavior.lua:583-586`) or poll `isComplete`.
- **Roll guid pre-assignable** (`DSInitiativeRoll.lua:721-737`) so a roster
  can point at a roll before it is thrown.
- `dmhub.Roll` begin/complete callbacks are LOCAL to the rolling client;
  cross-client = chat message + DiceEvents.
- **Tier math**: `RollUtils.DiceResultToTier`
  (`MCDMAbilityRollBehavior.lua:280-325`) returns 1-3 only; Critical is
  display-layer (`GetOutcome` `:2678-2697`, tiers[4] + natural 19+).
  Double-edge/bane shift tier, not total;
  `GetRollModFromEdgesAndBanes` returns 0 for doubles; C# nets the flat +/-2
  into total. UI must never re-apply.
- **Shared visible state**: `GameHud.RegisterPresentableDialog` /
  `PresentDialogToUsers(parent, id, args, livedata)`
  (`GameHud.lua:1370-1451,1685-1835`) - one surface on every client with
  shared mutable `livedata`; `clearPresentDialog` keeps livedata (hide
  without losing state). Shipped consumers: Montage
  (`MontageDocument.lua:407,1191`), Negotiation, journal docs, DS initiative
  banner. Shared-doc alternative: `mod:GetDocumentSnapshot` +
  `CompleteChange(desc, {undoable=false})`; PowerRollSpoilers is the
  director-gated reveal precedent (`EmbeddedRollDialog.lua:105-240`).
- **Claim/cede + spectate pattern fully worked** in
  `DSInitiativeRoll.lua:64-763` (claims map, priority + timestamp winner,
  losing client cancels its roll, everyone watches winner's dice).
- **Portrait primitives**: `gui.CreateTokenImage` (`Gui.lua:4188-4260`);
  existing director roster rows (`DSRequestRollsDialog.lua:1917-2010`) are
  the closest widget to the target; token-pool picker
  `CreatePartyTokenPoolSelector` (`:977-1149`); montage participant strip
  (`MontageDocument.lua:900-990`).
- **Dormant**: `Draw Steel V/CollapsedDiceRollPanel.lua` (complete panel,
  registration commented out); `RollRequest.contest` (no reader);
  `RequireDCDialog.lua` (shadowed 5e copy).

### E6. Modifier / perk reality

- `power` modifiers already support `rollType = test_power_roll /
  resistance_power_roll / opposed_power_roll / project_roll / all`
  (`MCDModifyPowerRolls.lua:16-45`), with characteristic filter, skill
  filter, keyword filter, rollRequirement gating, and GoblinScript
  `activationCondition` symbols incl. `rollcharacteristic`.
- After-roll modifiers (`activationAfterRoll`,
  `GetAfterRollModifiersForPowerRoll`, `afterRollExclusiveGroup`,
  `consumeOncePerRoll`) are implemented ONLY in EmbeddedRollDialog
  (`:3612-3776,4454-4475,6130-6184`). The legacy dialog has zero support -
  the single biggest capability gap for tests.
- **Lucky Dog** (`data/objectTables/feats/lucky-dog.yaml`) is data-only:
  `features: []`. Its text is exactly the after-roll shape ("fail a test
  using an intrigue skill -> lose 1d6+level Stamina -> improve outcome one
  tier, once per test"). No tier-shift-with-cost primitive exists on the test
  path today.
- `powertabletrigger` (Parry et al) is hard-wired to ability casts: its
  `powerRollModifier` defaults `rollType="ability_power_roll"`
  (`PowerTableTriggers.lua:161`) and `TriggerModsPowerRoll` has exactly one
  call site inside `ActivatedAbilityPowerRollBehavior:Cast`
  (`MCDMAbilityRollBehavior.lua:1529-1537`) requiring an ability + target
  token.
- The only test-relevant trigger event is `rollpower`
  (`MCDMRules.lua:1674-1717`), dispatched from the ability roll and
  `ShowCharacteristicRollDialog` only - requested tests and resistance rolls
  dispatch nothing.

### E7. Genuinely absent (new work required)

- Group-test aggregation ("half or more succeed") - reference prose only.
- Player-visible roster - the only roster is DM-hidden.
- An accept/commit step that preserves the record (Proceed destroys it).
- A tier field on the wire.
- Triggers on tests.
- Authority/arbitration model beyond last-writer-wins.
- `{undoable=false}` escape on action-request writes.
