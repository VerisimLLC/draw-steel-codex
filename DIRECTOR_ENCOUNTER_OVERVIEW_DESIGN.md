# Director Encounter Overview - Design Brief

**Status: LOCKED for v1 as of 2026-08-14 (critique round folded in; see Decisions
47-52). Implementation may begin with Phase 0. Working name only; feature is
unnamed. This document is the single source of truth for this design. Supersede
sections rather than accreting.**

## Frame

**Problem:** A Director running an encounter cannot see what their monsters can do
across the whole board. The knowledge lives one-monster-deep behind character sheets
and hover tooltips, so running many unfamiliar monsters in the Codex is worse than
running them from a printed encounter sheet (reference: Delian Tomb Encounters v1.02
pp. 95-96, the "Mystic Goblins" spread).

**For whom:** The IMPROVISING Director, mid-combat, under time pressure. Explicitly
including: the Director who had a busy week and did not prep, and the Director whose
players went off script and who is throwing an impromptu encounter with monsters they
have never run. Power-user density, but under high cognitive load - the tool must
reduce workload, never add a management layer (Hodent: minimum workload).

**Done looks like:** On the Director's turn, "which of my monsters can hit that
2-cube cluster of heroes?" is answered in seconds, without opening a character sheet,
for monsters the Director has never run before.

**THE REFRAME (2026-08-13):** The surface's real deliverable is the ACTIVATION
decision: "which monster do I activate next, and with what?" The ability lens is
the means, not the end. The decision has two intertwined halves:
1. **Ability-need driven** - "I need a pull to knock someone into the brazier;
   who has one?" (the funnel below)
2. **Attrition driven** - "which squishy monsters die if they don't act soon?"
   Real Director heuristics: minions first (players kill unacted minions), then
   regular monsters (squishier = more urgent, tempered by ranged/safe positioning),
   leaders last (confident they survive to end of round).
A full activation also weighs Main action + Maneuver + movement/range together,
not just one ability. Today the complexity is so high the honest fallback is
"select a semi-random ability from an available monster" - that is the bar to beat.

## Decision Ledger

| # | Date | Decision | Rationale |
|---|------|----------|-----------|
| 1 | 2026-08-13 | Target moment is in-combat activation: encounter start + every activation, treated as ONE repeated moment ("encounter start is just the first activation"). | The tool serves the improvising Director during play. |
| 2 | 2026-08-13 | Prep (study-the-encounter-in-advance) is OUT of scope - a different solution case. | Hobby pain point is that prep is too hard; this feature must not assume prep happened. |
| 3 | 2026-08-13 | The Codex surfaces and organizes options; the human judges. Target output shape: "Director, these are the 3 area abilities you have, on these monsters." No recommendation engine, no tactical AI scoring. | User: "it's up to the player to identify which is best." |
| 4 | 2026-08-13 | Availability state matters: an ability on a monster that has already acted this round must be visibly de-emphasized but still discoverable ("aware I have it, aware I can't use it right now"). | Improvising Director cares about what is usable NOW; already-acted options are context, not options. |
| 5 | 2026-08-13 | Core pain is SEEING abilities. Passive-trait contextual prompts (e.g. a trait that synergizes with the ability type being browsed) are a cherry-on-top, explicitly NOT core scope. | User flagged this themselves as a possible derail; recorded to keep it from creeping in. |
| 6 | 2026-08-13 | Organizing axis: ABILITY-FIRST pool (Option B). Every ability chip carries its owner's identity (portrait + name); hover/select cross-highlights the token on the map. A monster-first pivot lens (Option C) may grow later if orientation proves underserved - phase 2 at earliest. | User preference (B first, C close second); persona did not prep, so "what can this band do" stated tactically IS the orientation view. |
| 7 | 2026-08-13 | Owner identity on each chip is FIRST-CLASS, not a footnote: it must carry the attrition signals - organization (minion/horde/elite/leader), current stamina state, ranged-vs-melee disposition, and acted/unacted - because "who should act before they die" is half the activation decision. | Falls directly out of the reframe. |
| 8 | 2026-08-13 | Categories are FACETS (lenses), not folders. An ability appears exactly once in any given view; the active lens filters/groups the list; an ability's other facets show as small badges on the chip; per-facet counts live on the filter chips ("Area 3"). No duplication anywhere. | Resolves the multi-category problem (e.g. Shadow Chains = Area+Control+Malice) with zero duplication fuzz; user asked to minimize duplication, delegated mechanism to UX judgment. |
| 9 | 2026-08-13 | Damage is a SORT, not a bucket. Every lens brings its own natural sort (Damage lens: descending by computed expected damage with raw tier numbers displayed; Malice lens: cost ascending; Area lens: grouped by shape). No computed-vs-raw preference setting at v1; add only if playtests show divergence. | Serves both compute-for-me and raw-numbers personas simultaneously with zero configuration. User signed off. |
| 10 | 2026-08-13 | Default scope = ALL director monsters, unacted prominent, acted de-emphasized. Map multi-select NARROWS the pool (e.g. select just the minion squads to plan attrition; exclude the leader who will survive to go last). Zero setup clicks for the common case. | User's own scenario: "I'd select just the minions and exclude the leader." Selection is a refinement gesture, not a ritual. |
| 11 | 2026-08-13 | Two-stage interaction: click ability chip = PREVIEW (highlight owner token, render range/area overlay from their position, show full ability card); explicit second action = commit. Preview IS the reach check (funnel step 3). | Misclicks cost nothing (error prevention); reach verified before commitment. |
| 12 | 2026-08-13 | The overview is a FULL FRONT DOOR to taking a turn: committing claims the initiative turn and starts the cast. No malice exception needed - verified in Monsters book v1.01: ALL band malice features and the universal ones (Brutal Effectiveness, Malicious Strike) activate "at the start of any [band] monster's turn", so the claim-turn moment is exactly when the malice menu is relevant. Ability-attached "N+ Malice" riders happen mid-cast as today. | Rules verified against Draw_Steel_Monsters_v1.01.pdf; the suspected exception dissolves - turn start is the malice window, so the front door can OFFER band malice features at claim time. |
| 13 | 2026-08-14 | SURFACE (supersedes the open Round-4 question): evolve the EXISTING action bar with minimal aesthetic change - a "Unique Abilities" folder adjacent to "Common Abilities" on the director side, replacing the Main Action/Maneuver split for monsters. Opening it shows PARALLEL PER-MONSTER COLUMNS of each monster's full unique kit (main actions AND maneuvers together), excluding band malice features and global common abilities. Solo/leader info-overload risk accepted for v1 testing. | Mockup v1 was far too large / obscured the map. ~80% of monsters have at most 1 main + 1 maneuver; seeing the whole turn kit at once is the point ("if I like one ability I want to see what else that monster can do that turn"). Reuse familiar tech; existing users keep their mental model. |
| 14 | 2026-08-14 | The ability chip is the EXISTING AbilityHeading component (DrawSteelActionBar/DrawSteelActionBar.lua:1921, class "abilityHeading"), enriched rather than replaced. It already carries cannotAfford/expended/suppressed class plumbing to build the greying on. | User: it conveys a lot in minimal real estate; replicate, don't invent. |
| 15 | 2026-08-14 | Portrait on each chip/column (center-left): hover = monster type + role + the Monsters book's role description; click = pan camera to the creature and PULSE it in its role color; multiple identical monsters = center on all, pulse all. Engine hooks exist: dmhub.FocusToken(charid) pans+pulses+selects, dmhub.PulseHighlightToken(tokenid) (Definitions/dmhub.lua:512, :1869); color-parameterized pulse needs verification (DrawSteelTokenHud.lua's dead-minion pulse is the Lua-side pattern if the engine call is not colorable). | Locate-the-monster is half the value of the mapping; role color reinforces the role vocabulary. |
| 16 | 2026-08-14 | TRIGGERED abilities and VILLAIN ACTIONS are excluded from the Unique Abilities content: villain actions are used at the end of ANOTHER creature's turn and never inform which monster to activate now; triggers are off-turn by nature. They remain where they live today (initiative bar / trigger panel). | User decision with rules rationale. |
| 17 | 2026-08-14 | Unusable abilities grey out with a hover reason in red text: already acted this round, insufficient Malice, no enemy within reach even after full movement (Charge keyword extends reach by charge movement), area ability unable to cover more than 1 enemy from any reachable origin. v1 reach math is a straight-line (Chebyshev) ESTIMATE ignoring walls/difficult terrain, labeled as such; true pathing later. | Usability-at-a-glance was a top user request; estimate-first keeps v1 cheap. |
| 18 | 2026-08-14 | Selection flow: clicking an ability whose statblock has exactly one FRESH owner claims that monster's turn and selects the ability; multiple fresh owners -> prompt "Select the creature to claim their turn and use this ability" with all capable owners highlighted/targetable on the map. | User-specified; composes with Decision 12. |
| 19 | 2026-08-14 | At-risk nudge: monsters likely to die if targeted before they act get a visible preference indicator. Pulsing reserved as the locate gesture, not the at-risk signal. | The lost-turn-forever insight from the reframe. |
| 20 | 2026-08-14 | At-risk visual = TRAFFIC LIGHT dot on the portrait corner (static, hover explains why): RED = use first or maybe never; AMBER = in between; GREEN = low risk of dying before the director's next turn AND/OR not positioned to contribute anyway. Plus PLACEMENT: red/fresh columns sort first. Heuristic v1 kept simple and explainable; user may crowdsource refinements from designers/community. | User proposal (traffic light) + accepted static-ring and placement suggestions. |
| 21 | 2026-08-14 | Per-lens sorts locked: Damage = tier-2 desc; Area = area size desc; Forced Move = distance desc; Malice = cost asc. ALL ties broken by tier-2 damage desc. | User signed off with tie-break amendment. |
| 22 | 2026-08-14 | Sub-filter multi-select is OR (pick "slowed" + "restrained" -> abilities applying either). | User confirmed. |
| 23 | 2026-08-14 | The small button = SELECT ALL FRESH: one click selects every monster that has not acted this round; sits beside the Unique Abilities drawer. Whether it also auto-opens the folder: test both in implementation. | User clarified the previously unfinished request (it selects the browsing scope, pairing with Decision 10). |
| 24 | 2026-08-14 | Claiming a turn is gated to the correct juncture of combat (start of a director turn slot). Off-turn the director can still browse AND still use abilities (as today) without altering the round/turn state; the claim element is disabled with the reason shown. | User confirmed with the off-turn-use nuance. |
| 25 | 2026-08-14 | Malice is a SINGLE director pool - the Codex is 1v1 factions and Draw Steel malice is one director resource spendable on any band's feature list. CORRECTS mockup v1's dual "Goblins 5 / Gilded Hand 3" pools; per-band FEATURE LISTS remain per-band, the POOL is one. Insufficient-malice greying checks the one pool. | User correction, matches RAW. |
| 26 | 2026-08-14 | Common maneuvers (Hide, Aid Attack, etc.) live in the Common Abilities folder when Main Action/Maneuver merge into Unique Abilities on the director side - no capability silently lost. | Regression-surface rule. |
| 27 | 2026-08-14 | Lens control: cycle arrows AND clickable lens label opening a dropdown of all lenses with counts; sub-filter chips appear inline for Control/Area/Forced Move. Active lens tints the control + a left-edge tick on matching chips; non-matching chips dim; chips otherwise stay visually identical to today's AbilityHeading. Demonstrated in mockup v2 for aesthetic sign-off. | Resolves the cycle-vs-counts concern while keeping the compact aesthetic; user asked to see it rather than decide blind. |
| 28 | 2026-08-14 | Chip visual fidelity: match the LEGACY common-ability badges as closely as possible - translucency, icon treatment, sizes, quietness. Mockup chips are approximations; the implementation reuses the real AbilityHeading styles/classes so fidelity is automatic. | User: "really trying to maintain the look of the legacy common abilities as much as possible." |
| 29 | 2026-08-14 | TRAFFIC LIGHT SEMANTICS REVERSED (supersedes the color mapping in 20): the light answers "activate this monster now?" - GREEN = go now (e.g. fragile + exposed: use them or maybe lose the turn; minions before heroes thin them), AMBER = fine either way, RED = hold/save (leader, safe, or cannot contribute). Dot carries a tiny glyph (play/square) so color is not the only signifier. Hover explains the verdict first, then the why. | User re-read his own mapping against the metaphor and flipped it; assessment agrees: traffic lights direct ACTION (green=proceed), and red=urgent collided with red=danger/dying semantics elsewhere. |
| 30 | 2026-08-14 | Progressive disclosure default: the folder opens showing SUGGESTED (green-light) creatures only, with a clear segmented toggle "Suggested (N) / All fresh (M)" and a "+N more" stub to expand. EXPERIMENTAL - evaluate cognitive-load vs completeness in testing. RULE: when a LENS is active, completeness wins - every monster with a matching ability shows regardless of scope (the funnel promise "these are ALL your area abilities" must never silently lie). | User's cognitive-load concern ("where do I begin?"); the lens-overrides-scope rule protects Decision 3's funnel integrity. |
| 31 | 2026-08-14 | Lens filtering HIDES non-matching columns entirely; the visible result is CENTERED on screen (guide the eye to the middle, minimal cursor/eye travel); within visible columns, non-matching kit chips dim but stay (kit context). Lens control is FIXED-WIDTH so the cycle arrows never move - rapid double/triple-click cycling without mouse relocation. Malice lens sorts cost ascending (v2 bug fixed). | User feedback: matches were stranded far-left; label resize forced mouse relocation. |
| 32 | 2026-08-14 | Copy rules: owner-selection prompt names the statblock ("Select a Goblin Warrior to claim their turn...") and lists NAMED individuals by their custom names (live A5 has "Sneaky"/"Dizzy" Goblin Assassins - same statblock, custom token names; dedupe by statblock, disambiguate by name). Traffic-light hover uses QUALITATIVE stamina (low/moderate/high), leads with the verdict, e.g. "Use them now. Low stamina and enemies nearby - high risk of dying before your next turn." | User-specified copy; renamed-token edge case discovered in live data. |
| 33 | 2026-08-14 | Stress-test scenarios: Delian Tomb A5 war room (live in Codex; mockup v3 built on it) and FoBB "To the Skies" (7 statblocks). User's original 10-statblock custom ambush was HARDER than anything published - real adventures peak at 5-7. | Calibrates the design target to published reality. |
| 34 | 2026-08-14 | Chip anatomy matched to the LIVE action menu (studied via magnified screenshot of the real open menu): frameless line-art icons - GOLD for signature abilities, WHITE for the rest - bold white serif title over keyword subline, translucent column with hairline separators between chips (no per-chip borders), and the column identity as a SOLID DARK FOOTER BAR with gold text (legacy "Signature Abilities" bar position) carrying portrait + traffic light + name; clicking it locates on the map. | User: v3 chips looked "nothing like" the real ones; v4 rebuilt from direct visual reference. Implementation inherits exactness for free by reusing AbilityHeading. |
| 35 | 2026-08-14 | Lens bar geometry HARD-FIXED: constant bar width with core controls at constant offsets; sub-chips render in absolutely-positioned reserved space. Root cause of the v3 shift: the centered bar re-centered itself when sub-chips appeared, displacing the arrows. | Second report of the same symptom; fixed structurally, not by width tweaks. |
| 36 | 2026-08-14 | Owner-selection prompt options pulse/highlight their creature on the map ON HOVER, so the Director sees who they are about to activate before clicking. | User request; completes the see-before-commit loop. |
| 37 | 2026-08-14 | Product uses REAL TOKEN PORTRAITS (token portrait art) on columns and prompts; mockup monograms are a mockup-only shortcut (no cheap access to art assets from HTML). | User assumption confirmed. |
| 38 | 2026-08-14 | Action-type marking convention: unmarked chip = main action (the majority default); MNVR tag marks maneuvers; signature = gold icon (legacy convention); villain actions and triggers never appear here (Decision 16). Mark the exception, not the rule. | User question answered and locked. |
| 39 | 2026-08-14 | Naming: the scope toggle is "Suggested / All Units" (NOT "All fresh" - availability is inferred). The select-all button selects every available unit but does NOT auto-open the Unique Abilities folder; opening is a separate click. | User: "fresh" was unclear jargon; gut call on the two-step flow. |
| 40 | 2026-08-14 | The Unique Abilities DRAWER must look identical to the existing actionBarDrawer (DrawSteelActionBar.lua:1608): octagonal chamfered slab, near-opaque dark navy, muted blue-grey uppercase serif when inactive / cream when active, gold rim + top-edge gem when open, red numbered diamond on Malice. Studied from magnified screenshot; implementation reuses ActionBarDrawer directly. | User pasted the exact UI element; identical means identical. |
| 41 | 2026-08-14 | A separate SHAREABLE review artifact exists for stakeholder feedback, with a dismissible intro card (what it is, five things to try, fidelity disclaimer). It is a stable snapshot: the working mockup URL keeps iterating; the review URL only updates deliberately. | User wants to circulate the mockup to other reviewers. |
| 42 | 2026-08-14 | Scope toggle copy is "Suggested" / "Available" (supersedes 39's "All Units"). | User pick. |
| 43 | 2026-08-14 | MULTI-SELECT DRAWER STRIP (director side, >1 unit selected): TRIGGER stays (comparison plausible, low cost); UNIQUE ABILITIES; MALICE reworked into per-BAND columns (one column per malice-feature list represented in the selection, e.g. Delian "Mage Tower Third Level" = Ogre column + Orc column for the mohlers) using the same column/chip grammar as Unique Abilities, single director pool shown once; COMMON ABILITIES and MOVE are REMOVED - identical across creatures, zero comparative information. Exception: selecting exactly ONE minion squad keeps the single-creature strip (squad = one actor). Single-selection strip is unchanged. | User proposal; Hodent minimum-workload/clarity - drawers that cannot inform a decision are noise. Regression note: common abilities/move remain one click away by selecting a single unit, so relocated not lost. |
| 44 | 2026-08-14 | RIGHT-CLICK COMPARE: right-clicking a chip pins the ability's full card - the EXISTING ability card renderer (ActivatedAbility:Render, MCDMActivatedAbility.lua:706, the abilityScrollFrame the user inspected) - into a compare tray; multiple pins sit side by side and the tray scales with count (2 is the sweet spot; more allowed, cards shrink/scroll). Right-click on the legacy AbilityHeading currently opens Share/View Source/Edit; the compare action is ADDED to that menu (or a modifier-click) rather than replacing it. | User need: hovering serially forces memory of the previous card; comparison must be simultaneous. |
| 46 | 2026-08-14 | COMPARE GESTURE = ONE-CLICK PIN via a small always-visible pin/preview affordance on each chip (no right-click menu; menus get lost). Icon choice OPEN: the binoculars (icons/icon_game/icon_game_193.png) has exactly ONE existing meaning in the app - "Preview as player" in the Document system (DocumentSystem.lua:1275) - so reusing it for "director compare" would give one glyph two meanings (form-follows-function violation). Prefer a distinct pin/compare glyph; keep binoculars for player-preview. Final glyph chosen in the Lua phase from the icon set. | User: one-click preferable, right-click menu "would get lost"; icon semantics verified in code. |
| 47 | 2026-08-14 | **X1 ACCEPTED (supersedes 18, restores 11).** Chip click = PREVIEW: pin the ability card, highlight the owner, draw the reach/area overlay. The preview card carries an explicit primary button - "Take <Creature>'s turn" - AND the claim also happens implicitly at the first irreversible step of the existing cast flow (target confirm). Cancelling targeting releases the claim; Esc always backs out fully. Casting for a non-selected owner uses PushCasterToken, never SelectToken, so browsing scope survives. | User sign-off. Removes the hidden-ambusher leak, the accidental initiative flip, and the undo gap that all four persona reviewers hit. |
| 48 | 2026-08-14 | **X2 ACCEPTED (supersedes 20 and 29's semantics).** v1 footer shows SIGNALS, not a verdict: stamina band (low/moderate/high), enemies-within-reach count, melee/ranged glyph, acted state, instance/minion count. The traffic-light VERDICT becomes an opt-in "suggestions" overlay, DEFAULT OFF for v1, never a sort key. If/when enabled: indicator lives in a fixed footer slot (never the portrait corner - that slot reads as health in every VTT), >=16px, three distinct SHAPES (filled triangle / pause bars / square), luminance-stepped colours, 1px inner white ring, and the verdict WORD printed in the footer line. Heuristic must be role-aware before it ships enabled (support/leader = early while allies unacted; controller/area = when >=2 enemies coverable; artillery = when LoS exists). | User sign-off. Resolves the health-metaphor collision, the CVD failure, AND the Decision-3 boundary violation (a verdict IS a recommendation; signals are facts). |
| 49 | 2026-08-14 | **X8 MIDDLE PATH ACCEPTED (amends 31).** A lens still HIDES non-matching columns and CENTERS the result (user's original instinct preserved), but surviving columns keep their original relative order - no re-sorting by light or by impact score at the column level. Within a column, chips still sort by the lens's natural sort. Column order is otherwise stable within a round; new/reinforcement columns append at the right with the novelty pip. | User sign-off ("go with your suggestion and test it"). Preserves centering while protecting the spatial memory experts rely on under load. |
| 50 | 2026-08-14 | **PHASE 1 CUT ACCEPTED (engine reviewer's scope).** Phase 1 = new "unique" drawer shown when >1 director token selected; per-statblock columns via pooled ActionSubMenu + AbilityHeading{casterToken}; kit = GetActivatedAbilities{excludeGlobal=true, bindCaster=true} minus Trigger/Villain Action; footer = portrait + name + signals + acted (HasHadTurn); greying limited to acted-this-round and cannot-afford-malice; chip press = preview -> PushCasterToken + beginCasting; locate = CenterOnToken + PulseHighlightToken. NO lenses, NO traffic light, NO reach math, NO compare tray, NO condition icons in Phase 1. | User sign-off. Lands the risky structural work (multi-select, columns, caster override) on its own, then builds the comparison layer on a stable base. |
| 51 | 2026-08-14 | **REMAINING CRITIQUE AMENDMENTS ACCEPTED AS WRITTEN: X3** (three distinct state channels; unusable stays clickable; never grey an area ability on target-count; off-lens opacity >= .45, never stacked), **X4** (nothing lives only in a tooltip; inline greyed-reasons; Lua hotkeys; focus parity for the owner prompt), **X5** (never FocusToken; explicit scope snapshot), **X6** ("Everyone can:" dimmed line under a lens a common ability satisfies), **X7** (per-instance footer mini-rows when count>1; partial-reach badges), **X10** (leader/solo VA used-state strip + turn counter; dimmed captain riders), **X11** (11/12/13-14px text floors, >=16px icons, panel alpha >= .75, Font Size scaling), **X12** (role colour is decoration, role WORD is the channel; lens hues disjoint or dropped; one published palette table), **X13** (newcomer copy pass: "Filter:", "take their turn" not "claim", "Tier 1 (<=11)", worded potency, real power-roll bonus, Malice explainer, "Maneuver" spelled out, first-open hint strip doubling as the empty state), **X14** (each lens shows its sort key on the chip, damage labelled "per target"), **X15** (condition icons >=16px, one + "+N", union tier-parse with a behavior scan, text mirror in the card). | User sign-off ("happy to go with" the four headline calls; remaining amendments recommended and accepted). |
| 52 | 2026-08-14 | Copy correction recorded: "Suggested / Available" (Decision 42) survives, but reviewer B's objection is noted - "Available" may imply acted monsters are gone, which contradicts Decision 4. Revisit the pair during the X13 copy pass with "Act now / All monsters" as the leading alternative. | Deferred, not decided. |
| 45 | 2026-08-14 | CONDITION ICONS ON CHIPS: a small status icon (the token-UI status-icon art from charConditions, same glyphs players see on tokens) in the chip's right corner for each condition the ability can apply; "+" suffix when it comes with a condition RIDER; multi-condition = up to 2 icons then "+N"; tier-varying conditions show the highest tier's condition with the tooltip listing per-tier. Icons appear ALWAYS (not lens-gated) so the Control lens is discoverable from the chips themselves. Feasibility: conditions are parsed from tier text by the existing rule-pattern engine (MCDMAbilityBehavior.lua ~1531/1667, ValidateRule 2489) matching charConditions with powertable=true - so structured condition data per ability is derivable without hand-tagging. Density risk accepted for testing; fallback is lens-gated icons. LIVE-VERIFIED 2026-08-14: all 26 charConditions carry an iconid; 20 are powertable-flagged (bleeding, dazed, frightened, grabbed, prone, restrained, slowed, weakened, ...); tier-text derivation confirmed (Bury the Point->bleeding, Eye of Surlach->weakened, Dizzying Hex->prone). IMPLEMENTATION TRAP: derive via the engine's regex rule matcher (MatchMCDMEffect), NOT substring search - "strained" is a substring of "restrained" and a naive scan mis-tags Shadow Chains. | User proposal; extends existing token-status vocabulary (consistency pillar) at ~14px, legibility to be verified in Lua. |

## The funnel (user's articulated model of the moment)

The Director's per-activation question resolves in three narrowing steps:

1. **What exists** - across all my monsters, what abilities of the kind I need
   (e.g. area/cube, control, high damage) are in this encounter at all?
2. **What is usable now** - filter to monsters that have not yet activated this
   round. Already-acted monsters' abilities stay visible but de-emphasized.
3. **What can reach** - of those, which monster can actually deliver it to the
   target squares from where they stand (range/position check)?

The Codex's job ends when the funnel presents the shortlist with clear
ability-to-monster mapping. Choosing among the shortlist is the Director's craft.

## Candidate tactical categories (from user, to be refined)

High Damage; Control (collapsible by condition: bleeding, dazed, slowed, restrained,
weakened, prone...); Malice abilities; Forced Movement (push/pull/slide - e.g. "knock
a hero into a pit"); Area (subset by shape: cube, line, burst, wall...). Visual
coding per category so type is readable at a glance.

## What the print gold standard does right (evidence)

From Delian Tomb pp. 95-96 (six stat blocks across one spread):
1. Color-coded monster headers with LEVEL + ROLE ("Horde Ambusher", "Leader") -
   role alone conveys most of how to play the monster.
2. Per-ability glyphs on the left edge (melee/ranged/area/triggered/trait/villain
   action) - scannable without reading.
3. Malice costs surfaced in ability headers, right-aligned - sweepable for budgeting.
4. Compression: ONLY unique content. Common abilities (Charge/Defend/Grab etc.)
   are invisible; that is why six monsters fit on two pages.

## Current-state evidence (live probe, 2026-08-13)

Test encounter: Goblin war band (Monarch, 2 Assassins, Cursespitter, Stinker,
10 Warriors) + Gilded Hand crew (Boddorff Buckfeather, Gorek, Mara, Targon,
Illwyth) - 10 unique statblocks, 2 monster groups, 2 malice pools of concern.
- Every monster carries ~20 common abilities burying 1-3 unique ones (Goblin
  Warrior: 2 unique of ~25 listed; Monarch: ~7 of ~28).
- Action bar already splits Signature vs Common abilities, but is one-monster-
  at-a-time; ability facts (shape, conditions, malice cost) are hover-only.
- Villain actions render in the initiative bar for the Monarch (I/II/III).
- Ability data is structured in the compendium (targeting shape, damage type,
  malice cost, conditions are real fields, not just text) - depth to be verified
  in the engine-capability phase.

## Critique round (2026-08-14) - five independent reviewers

Reviewers: (A) experienced Director, (B) Director new to the Codex, (C) Director
new to Draw Steel AND the Codex, (D) accessibility specialist, (E) engine
feasibility engineer. A-D used the Hodent lens. Findings below are ranked by how
many independent reviewers CONVERGED on them - convergence across personas that
did not see each other's work is the strongest signal this round produced.

### CONVERGENT BLOCKERS (proposed ledger amendments - awaiting user sign-off)

**X1. Click-to-claim contradicts click-to-preview (A, B, C, D all flagged; E
confirms mechanics).** Decision 11 says first click = PREVIEW; Decision 18 says
click = claim turn. The mockup implements 18. A single click on a browse surface
would flip the initiative tracker (player-visible), fire start-of-turn triggers,
open the band-malice window, and - if the monster is a hidden ambusher - ANNOUNCE
its turn to the players (A). Newcomers click to READ (B). No Esc/undo exists (B,D).
Off-turn the same click means something different (A,B). E adds: claiming touches
selection (SelectToken/PushCasterToken) which would collapse the browsing scope
(Decision 10), and the claim sequence is an inline closure in MCDMInitiativeBar
(:4577-4602) that must be extracted before it can be reused at all.
PROPOSED AMENDMENT (supersedes 18, restores 11): chip click = PREVIEW (pin card,
highlight owner, draw reach overlay; owner-selection prompt is part of preview).
The claim happens on the FIRST IRREVERSIBLE STEP of the existing cast flow (target
confirm), and cancelling targeting releases the claim. Esc always backs out fully.
Casting uses PushCasterToken (never SelectToken) so scope is preserved. Band
malice is offered as a non-modal strip on the claimed column, not a popup ahead
of targeting (A: "I do not spend band malice on 9 of 10 activations").

**X2. The traffic light reads as HEALTH and fails colour-vision deficiency
(A, B, C, D all flagged).** Every VTT and the Codex's own stamina bars put a
green/amber/red dot on a token to mean healthy/hurt/dying (B,C). Amber has NO
glyph (colour-only, violating the brief's own rule) (B,C,D). D measured: 8px
colour disc, 6px glyph; deuteranopia collapses go vs hold to ΔE 14
(indistinguishable); go-green on Runner-teal portrait contrast 1.04:1. A adds
the deeper problem: the light IS the recommendation engine Decision 3 forbade,
and its v1 heuristic is WRONG for the roles it will show most - a support leader
(Handaxe grants a free strike; Get in Here! summons runners who need turns THIS
round) wants to go EARLY, not "hold"; a controller wants to hold the cube until
heroes clump; snipers gain an edge by NOT moving. "Amber = your call" carries
zero information (A,C).
PROPOSED AMENDMENT (supersedes 20/29): (a) move the indicator OFF the portrait
corner (that slot means health everywhere) to a fixed footer slot; (b) three
distinct SHAPES not just colours (filled triangle / half-disc or pause bars /
square), >=16px, luminance-stepped colours (light green ~L.65 / mid amber ~L.50 /
dark red ~L.08), 1px inner white ring; (c) the VERDICT WORD printed in the footer
line ("Act now" / "Either" / "Can wait") - never colour alone; (d) v1 SHOWS THE
SIGNALS not a verdict: stamina band, enemies-within-reach count (threat),
melee/ranged glyph, acted state, minion count - and the light becomes an OPT-IN
"suggestions" overlay, default OFF for v1 testing, never used as a sort key (A).
If/when the heuristic is kept, it must be role-aware (support/leader = early
while allies unacted; controller/area = when >=2 enemies coverable; artillery =
when line of sight exists) and the hover leads with FACTS.

**X3. Three greys, three meanings (A, B, C, D).** Acted-this-round, unusable
(no reach / no malice), and off-lens all render as reduced opacity. Stacked, an
acted+off-lens chip is 0.06 opacity - invisible (D). Off-lens at .18 makes the
"kit context stays" promise a lie (D: name contrast 1.8:1). Reach greying is an
admitted estimate that HARD-BLOCKS the click - a false negative hides a legal,
often optimal play (A: Swamp Gas as a zone with zero enemies inside; Toxic Winds
on ONE hero to slide him; assassin behind a door).
PROPOSED AMENDMENT (supersedes part of 17/31): distinct channels - acted = tag on
the FOOTER (whole column, "acted"); unusable = desaturated + slash/lock glyph on
the icon + 11px inline micro-reason, STILL CLICKABLE (preview draws the true
reach overlay), hard-disable reserved for acted-this-round and insufficient
malice only; off-lens = opacity >= .45, never stacked. NEVER grey an area ability
on target-count (A blocker) - grey only on "zero enemies within range+speed".

**X4. Hover-only content with no alternate path (B, C, D).** Tier table, effect
text, why-greyed, role description, and light verdict live only in mouseenter
tooltips; toasts appear at the TOP of the screen while the strip is at the
BOTTOM (~900px eye travel) and auto-dismiss (D). No keyboard path exists in the
mockup (D). PROPOSED: preview-on-click (X1) fixes the primary case; greyed
reasons shown INLINE above the columns; hotkeys in Lua ([ ] cycle lens, 1-5 pick,
Esc back out, arrows/Enter across chips); owner-prompt options pulse on focus,
not just hover.

**X5. Selection-collapse hazard (A, B, E).** dmhub.FocusToken pans+pulses AND
SELECTS (Definitions/dmhub.lua:512) - clicking a footer to locate the Snipers
would narrow the pool to Snipers (Decision 10 interaction). E: keep an explicit
scope snapshot; locate = CenterOnLoc + hud-panel pulse; NEVER FocusToken.

**Data clarification (2026-08-14), so X3's example is not re-litigated:** SWAMP GAS
is the Goblin Stinker's own maneuver - an Area, 3 cube within 15, live-verified
targetType=cube/range=15/radius=3 - haze that is difficult terrain for non-goblins
and deals 2 poison per square moved inside. It is NOT encounter-wide. The map-wide
green mist is SWAMP STINK, the goblin BAND MALICE feature (7 Malice, targetType=map).
Two different abilities with similar names. X3's example therefore stands: Swamp Gas
is legitimately placed with ZERO enemies inside it (terrain denial in a doorway),
which is exactly the play a target-count-based greying rule would wrongly block.

### CONVERGENT MAJORS

**X6. Common maneuvers make Forced Move and Control lenses LIE (A; C by
implication).** Every monster can Knockback (push) and Grab (grabbed) - the
lens's "you have 0 pushes" is false for the persona who does not know that.
PROPOSED: one dimmed static "Everyone can:" line under a lens a common ability
satisfies (Forced Move: Knockback; Control: Grab; Damage: free strike/Charge).
Not chips, not per-column.

**X7. Statblock columns erase per-actor state (A).** "Sniper x12, 3 squads":
squad A is 1 minion behind a wall, squad C is whole with clean LoS - one dot,
one column, one grey state. Which instance's reach did the chip compute from?
PROPOSED: kit column per statblock stays; footer expands to per-instance
mini-rows (portrait, name, stamina pip, reach tick, acted) when count>1 / per
squad for minions; chip grey = "no instance can"; partial = badge "2 of 3 can
reach"; the owner prompt reuses the same rows.

**X8. Layout churn defeats spatial memory (A, D).** Columns re-sort by light AND
per lens; hidden columns re-center; the "+N" stub comes and goes. PROPOSED:
stable column order within a round (initiative or statblock order); lens
dims/collapses in place rather than hiding+recentering; new columns append at
the right with the novelty pip. NOTE: this partially reverses Decision 31 (user
explicitly asked for hidden non-matches CENTERED). Trade-off for the user:
centering vs stability. Middle path: hide non-matches but keep the SURVIVORS in
their original relative order and center the group.

**X9. Suggested-mode/lens interaction (A, B, C).** Every activation opens on the
suggested subset; a lens reveals hidden units; clearing the lens re-hides them -
contents change for reasons unrelated to the lens; the scope toggle dims to .35
with only a title tooltip (looks broken to B, C). PROPOSED: default scope =
ALL available (greens sort first - placement carries the nudge); Suggested is a
remembered filter chip; while a lens is active replace the toggle with static
text "Filter on - showing every match" instead of dimming.

**X10. Leader/solo/squad state invisible (A).** VA I/II/III used-state, solo's
two turns per round (binary acted flag greys the column after turn one), minion
"With Captain" riders that vanish when the captain dies. PROPOSED: leader/solo
footer gets a tiny VA I/II/III strip + turn counter; minion chips render the
captain rider dimmed when no captain in range. E confirms HasHadTurn is round-
based (MCDMInitiativeQueue.lua:580) - solo double-turn needs a distinct check.

**X11. Legibility floors (D).** 8px MNVR tag, 9px role line, 6px light glyph,
9.5px counts fail at 1080p-1440p; translucent panels over the map make contrast
map-dependent (keyword subline crosses 4.5:1 on sand/snow). PROPOSED minimums:
11px glance text, 12px read-under-pressure text, 13-14px names, 16px icons,
panel alpha >= .75 or a text plate; all scale with the Font Size setting.

**X12. Palette collisions (D).** Controller role hex == Area lens hex; Harrier
== Forced Move; Hexer == Control; Leader gold == accent gold. Under protanopia
Harrier teal and the Forced Move tick both go grey. Ten role hues exceed
working memory. PROPOSED: role colour is DECORATION only, the role WORD is the
channel (raise to 11px); lens hues disjoint from role/light hues (ΔE>=30 under
P/D) or drop lens hue and rely on tick+dim; one published palette table.

**X13. Newcomer vocabulary + tier notation (B, C).** "claim", "lens", "fresh",
"unique", "drawer", "MNVR", "✦3", "≤11 / 12-16 / 17+", "M<1" are all opaque to
the stated persona's extreme case. PROPOSED copy: "Filter:" prefix on the lens
control; "Take their turn"/"activate" not "claim"; tooltip rows "Tier 1 (<=11)";
worded potency "Might 1 or lower: bleeding (save ends)"; power roll line with
the monster's REAL bonus; Malice hover "Costs 3 Malice - you have 3. Shared pool,
gained each round"; "Maneuver" spelled out; first-open dismissible hint strip
(3 opens) doubling as the nothing-selected empty state; "Act now (3) / All
monsters (7)" (B) vs "Suggested/Available" (user) - copy decision needed.

**X14. Damage lens sorts by an invisible number (C).** Columns re-order, chips
re-order, nothing on the chip shows WHY. PROPOSED: in each lens, the chip's
right slot shows the sort key in the lens colour (Damage "4/6/7" or tier-2 value
"per target"; Area "3 cube"; Forced Move "slide 3"; Malice "✦3"). A adds: label
single-target numbers "per target" - a 4-sniper squad activation is 4 strikes.

**X15. Condition icons at 14px will not survive (D; E adds false-negative
risk).** Token status art is drawn for 24-32px; the chip's right slot already
holds cost + MNVR + planned pin. E: the tier parser stops at the first unparsed
clause and misses conditions applied via behaviors/auras. PROPOSED: >=16px, ONE
icon + "+N", monochrome silhouette with outline, text mirror in the pinned card;
derive by UNIONING WalkParsedSegments (MCDMAbilityBehavior.lua:3254) with a
behavior scan (ApplyOngoingEffect/ConferConditions); reconsider lens-gating.

### ENGINE VERIFICATION (E) - what is TRUE about the code today

- Action bar is STRICTLY SINGLE-TOKEN: g_token = dmhub.selectedOrPrimaryTokens[1]
  (DrawSteelActionBar.lua:1777); multi-select today casts for the first token
  only. dmhub.selectedTokens is settable (select-all is feasible). Whether the
  hud refresh re-fires when a second token joins the selection is UNPROVEN.
- AbilityHeading is file-local and hard-binds g_token at 6 sites (:1926, :1944,
  :2044/2091, :2099-2139, :2255). Needs an args.casterToken override. Casting
  for a non-selected token has precedent via PushCasterToken (:429-454, :5580).
  ActionMenu's container is already flow="horizontal" with pooled ActionSubMenu
  columns (:2491-2505, :2558-2564) - per-monster columns fit the grammar.
- Acted-this-round: InitiativeQueue:HasHadTurn(id) (MCDMInitiativeQueue.lua:580);
  named tokens (Sneaky/Dizzy) are separate entries; minions group by squad.
  Claim gate = q:ChoosingTurn() and not q:IsPlayersTurn(); the claim sequence is
  an inline closure (MCDMInitiativeBar.lua:4577-4602) with file-local
  CanControlInitiative (:277) - MUST be extracted to InitiativeQueue.ClaimTurn.
- PulseHighlightToken: no colour param; locality UNDOCUMENTED (all callers are
  local hover handlers, suggesting local - verify with two clients). FocusToken
  SELECTS. Coloured pulse = TokenHud.RegisterPanel pattern
  (DrawSteelTokenHud.lua:19-60, 345-401); pan = dmhub.CenterOnToken/CenterOnLoc.
- Malice = single global resource (DSResources.lua:62-88); band lists attach per
  creature via MonsterGroup().maliceAbilities (MCDMMonster.lua:57-111) and appear
  as categorization=="Malice"; excludeGlobal=true yields the unique kit
  (MCDMCreature.lua:3099).
- Lens classification: structured fields exist (targetType/IsTargetTypeAOE,
  GetRange/GetRadius, HasKeyword, behavior typeNames); tier-text derivation via
  WalkParsedSegments returns match.condition and match.movement/distance. NO
  existing categorize/facet helper, NO tier-damage-number helper. Reach: Chebyshev
  helpers (:2915-2983) and MonsterAI:FindValidTargetsOfStrike (per-tile, slow).
- Role book descriptions have NO data source in the codex (must be added as a
  table). Decision 17's "area can cover >1 enemy from any origin" is an
  AI-grade per-origin search - needs the heuristic "two enemies within area
  diameter of each other and centroid within move+range".
- ActivatedAbility:Render(options,{token,maxHeight}) is standalone-usable
  (MCDMMonster.lua:559-565 precedent) - the compare tray is cheap.
- Drawer hiding per selection count is trivial (:1700-1734, :1858-1863; each
  drawer's refresh already toggles collapsed/hidden).

E's suggested PHASE 1 (buildable): new "unique" drawer shown when >1 director
token selected; per-statblock columns via pooled ActionSubMenu +
AbilityHeading{casterToken}; kit = GetActivatedAbilities{excludeGlobal=true}
minus Trigger/Villain; footer = portrait + name + acted (HasHadTurn); grey =
acted OR cannot afford; chip press = PushCasterToken + beginCasting (NO claim);
locate = CenterOnToken + PulseHighlightToken. No lenses, no traffic light, no
reach math, no compare tray. PHASE 2: lenses/sub-filters (WalkParsedSegments
cache), extracted claim-turn helper, reach estimate. Phase 0 spike: verify hud
refresh on multi-select and pulse locality with two clients.

### What every reviewer said to KEEP

Ability-first pool with owner identity on every chip; facets-not-folders;
per-lens natural sorts; one instance per ability; living inside the existing
action bar / AbilityHeading / drawer grammar; verdict-first qualitative hover
copy; honest greyed-reasons ("estimate ignores walls"); named-individual owner
prompt with hover-pulse; locate-by-click on the footer; hard-fixed lens-bar
geometry; real buttons with focus-visible outlines and a reduced-motion query.

## Phase 1 handover - READ THIS FIRST when resuming implementation

Ricky is usage-limited per session and asked for the build to be cut into small
deployable slices, each of which leaves the running app WORKING. Never deploy a
half-built slice. Update this section after EVERY slice, before deploying.

Verification: the live Delian Tomb A5 war-room game over the dmhub MCP bridge
(execute_lua / reload_lua / screenshot). The bridge drops often; if it is down,
write code but record the slice as UNVERIFIED. On this Mac the repo IS the
gitfolder the app reads (no deploy step; reload_lua re-reads files).
Syntax-check every Lua edit before reload: `luac -p <file>` (Lua 5.4).

| Slice | What | Status | Notes |
|---|---|---|---|
| (a) | Extract the claim-turn sequence out of the `selectinitiative` closure in `MCDMInitiativeBar.lua` into reusable `InitiativeQueue.ClaimTurn(initiativeid, {canControlInitiative})` + `InitiativeQueue.CanClaimTurn(...)` on `MCDMInitiativeQueue.lua` (added after `HasHadTurn`, ~line 589); bar's closure now a one-liner calling ClaimTurn with the bar's setting-backed control check. NO visible behaviour change. | **DONE 2026-08-14, deployed + reload-verified** (both files luac-clean, ASCII-clean; 43 mods reloaded with zero console errors; helpers present; gate returns true for a real entry as DM, false for a bogus id). NOT yet exercised: an actual claim through the bar click (irreversible - left for natural play). UNCOMMITTED in git. | Semantics preserved exactly: live queue, loop-key initiative id, group entries claim as a unit, chat card only when tokens exist. |
| (b) | Add `args.casterToken` override to `AbilityHeading` in `DrawSteelActionBar.lua` (~1892) so a chip can represent a NON-selected owner; resolve once, fall back to `g_token`; touch the 6 bind sites (:1926, :1944, :2044/2091, :2099-2139, :2255). Press path = `PushCasterToken` before `beginCasting`. NO visible change for existing menus. | **DONE 2026-08-17, reload-verified** (luac -p clean, ASCII-clean, CRLF preserved; 43 mods reloaded, zero console errors; smoke test: selected a Goblin Sniper, opened the main-action drawer -> 3 headings populated via the new `CasterToken()` path, closed it, zero errors). NOT exercised live: an actual press with a non-selected `casterToken` (nothing calls it yet). UNCOMMITTED in git. | HOW IT WORKS: `AbilityHeading` now has a file-local `CasterToken()` = `args.casterToken` if non-nil AND `.valid`, else `g_token` (a function, not a captured value - pooled chips outlive selection changes). ALL g_token reads inside the function go through it: suppression (`ability` event), Share to Chat charid, Edit Innate Ability (presence check + close-time resolve), hover (both branches - the menu branch now passes the caster as a 2nd arg to `showability`, and `ActionMenu.showability(element, ability, casterToken)` uses `casterToken or g_token`), press (DisplayAbility, improvements scan, LookupSymbol, HighlightAbilitySection caster), and the cost/greying `GetCost`. NEW EVENT `setCasterToken(token)` on the heading panel re-points `args.casterToken` (nil restores default) - for pooled chips fire it BEFORE the `ability` event, since `ability` computes suppression/cost from the caster (`ActionSubMenu` pool at ~:2544 does `m_children[i] = m_children[i] or AbilityHeading()` then `FireEventTree("ability", ...)`; slice (c) should insert `m_children[i]:FireEvent("setCasterToken", tok)` between them, or construct with `AbilityHeading{casterToken = tok}`). PRESS PUSH/POP: in `press`, after the `m_ability == nil` / instantCast handling and before DisplayAbility, if `CasterToken()` differs from `g_token` (charid compare, or g_token nil) it (1) fires `cancelCasting` if `g_currentAbility ~= nil` (so an in-flight cast's own pushed caster is popped first - keeps the stack balanced), (2) `PushCasterToken(caster)` (sets g_token/g_creature + engine `PushSelectedTokenOverride`), (3) `g_actionBar:FireEvent("refresh")` (rebinds g_abilities/resources to the caster; refresh closes menus because charid changed - harmless, beginCasting closes them anyway), then falls through to the normal `beginCasting`. This is exactly the `invokeAbility` sequence (~:5632) minus the `invokingAbility` class. THE POP IS NOT IN AbilityHeading: every cast ends via `cancelCasting` (finishCasting after Cast, Skip button, Esc, opening a drawer menu, controller disable, restoreFromBackup) which calls `TryPopCasterToken()` once (~:5430) - restores g_token = selectedOrPrimaryTokens[1]. Note `refresh` only re-reads the selection while the stack is EMPTY (~:1776), so a leaked push = bar stuck on a stale token; the in-flight-cancel guard exists to prevent that. Caveat for (c): with a caster pushed, the whole bar shows the CASTER's single-token bar for the duration of the cast, then pops back to the multi-selection - same as invoke prompts today. |
| (c) | New "unique" `ActionBarDrawer` shown ONLY when >1 director token is selected (director side); Common Abilities + Move drawers hidden in that state (Decision 43; single minion squad = single-creature strip). Menu = per-statblock columns via pooled `ActionSubMenu` + `AbilityHeading{casterToken}`; kit = `GetActivatedAbilities{excludeGlobal=true, bindCaster=true}` minus Trigger/Villain Action; dedupe by statblock, disambiguate renamed tokens by name (Decision 32). Bar must read the WHOLE selection, not `selectedOrPrimaryTokens[1]` (:1777). | **DONE 2026-08-17, reload-verified in the A5 war room** (luac -p clean, ASCII-clean, CRLF preserved; 43 mods reloaded, zero codex console errors). Live checks passed: (1) `dmhub.selectedTokens = {Stinker 1, Cursespitter 1, Dizzy Assassin}` -> strip reads TRIGGER / UNIQUE ABILITIES / MALICE (Main Action/Maneuver/Move collapsed); (2) drawer press -> three columns "Goblin Stinker" (Swamp Gas, Toxic Winds), "Goblin Cursespitter" (Eye of Surlach, Dizzying Hex w/ malice-1 diamond), "Goblin Assassin" (Sword Stab, Shadow Chains w/ malice-3 diamond) - NO Charge/Defend/Grab/Goblin Mode/Tiny Stabs/Swamp Stink chips; (3) 7-token selection (2 stinkers, both assassins, 2 warriors, monarch) -> "Goblin Stinker x2 / Goblin Assassin x2 / Goblin Warrior x2 / Goblin Monarch" columns, the monarch column shows Handaxe melee + Handaxe ranged + Get in Here! and NOT its 3 villain actions or Meat Shield; (4) single token -> classic TRIGGER / MAIN ACTION / MANEUVER / MOVE / MALICE strip; (5) 4 Goblin Runners of one squad -> classic strip (squad exception); (6) pressed the Sword Stab chip in the Assassin column while the primary was Stinker 1: console showed `push g_token` then `TARGETDIAG:: ability=Sword Stab caster=Dizzy Goblin Assassin`, targeting overlay drew for the assassin, `initiativeQueue.currentTurn` stayed `false` (no claim), and `cancelCasting` popped back to the 2-token selection. UNCOMMITTED in git. | HOW IT WORKS (all in `DrawSteelActionBar/DrawSteelActionBar.lua`): `g_selectedTokens` (:98) = whole `dmhub.selectedOrPrimaryTokens` filtered to `.properties ~= nil`, captured in the root `refresh` (:1888-1898) only while `#g_casterTokenStack == 0`; `InOverviewMode()` (:121) = `dmhub.isDM` AND `#g_selectedTokens > 1` AND NOT all tokens sharing one non-nil `MinionSquad()`. **ENGINE FINDING (new): the engine re-fires the bar's `refresh` ONLY when the PRIMARY token changes** - adding/removing tokens behind the same primary is silent (verified live: strip did not switch until a manual refresh). Fix = director-only poll on the root panel (`thinkTime = 0.2`, :1870-1878) comparing `SelectionSignature()` (:106, charids in order) with `element.data.selectionSignature`; fires `FireEventTree("refresh")` on change, skipped while a caster is pushed or `g_currentAbility ~= nil`. Root refresh also fires `closemenu` when overview mode flips (:1914-1918) so a Main Action menu never lingers under a collapsed drawer. DRAWER: `m_uniquePanel` (:1811, type "unique", created for everyone, starts collapsed) placed between the trigger container and `m_actionPanel` (:1988); the drawer `refresh` (:1348-1367) collapses "unique" unless overview and collapses action/maneuver/move when overview; "unique" is always `available`; :1089 keeps it out of the move-bar `else` branch. COLUMNS: `IsUniqueKitAbility` (:2730) = drop categorization Trigger / Villain Action / Malice / Common Ability / Basic Attack / Move / Hidden and anything whose `actionResourceId == CharacterResource.triggerResourceId` (excludeGlobal already removes free strikes, band malice and global-modifier commons - the categorization filter is belt-and-braces). `BuildOverviewColumns()` (:2756) groups `g_selectedTokens` by `properties:GetMonsterType()` (falls back to `tok.id`), order = first appearance in the selection; REPRESENTATIVE token = first member with `not q:HasHadTurn(InitiativeQueue.GetInitiativeId(tok))` (live, non-hidden queue) else the first member; label = statblock name + " xN" when N>1; kit = representative's `GetActivatedAbilities{excludeGlobal=true, bindCaster=true}` filtered, melee/ranged bifurcated, `hideWhenFiltered` honoured against the representative. MENU: `ActionMenu` "menu" handler branch `args.type == "unique"` (:2995-3030) uses the pooled `m_uniqueColumns` (:2832) of `ActionSubMenu{}`; per column `submenu:FireEvent("setCasterToken", column.token)` THEN `FireEventTree("abilities", column.abilities, column.label)`. `ActionSubMenu` gained `m_casterToken` + a `setCasterToken` event (:2640-2652) and fires `setCasterToken` into each pooled `AbilityHeading` before its `ability` event (:2689) - nil for the ordinary menus, so they are unchanged. FOR SLICE (d): the column label lives in the `ActionSubMenu`'s `submenuHeading` label (the first entry of `m_children`, moved to the END of the column each populate = the legacy footer-bar position); its text is set from the `grouping` arg of the `abilities` event, so (d) can either replace that label panel inside `ActionSubMenu` when a caster is set, or wrap each pooled column in a vertical panel with a new footer and leave the label collapsed. `column.tokens` (all members) and `column.token` (representative) are available on the column record for the portrait/acted/count signals. CAVEATS: Malice drawer in overview mode still shows the PRIMARY token's band list (per-band columns are Phase 1.5); chip press pushes the caster and the whole bar shows that caster's single-token strip for the duration of the cast, then pops back (as documented in (b)); a column whose kit is empty is collapsed by `ActionSubMenu` (menu hides entirely if every column is empty). |
| (d) | Column footer bar (legacy gold footer style): real portrait, name, role text, SIGNALS (stamina band low/moderate/high, acted via `InitiativeQueue:HasHadTurn`, instance/minion count, melee/ranged glyph); acted greys the column; cannot-afford-malice greys the chip. Footer click = `dmhub.CenterOnToken` + `PulseHighlightToken` (NEVER FocusToken). Per-instance mini-rows when count>1 (X7). | not started | No traffic-light verdict in v1 (Decision 48). |
| (e) | Preview-on-click: chip click pins the ability card (`ActivatedAbility:Render(options,{token,maxHeight})`), highlights owner, draws reach overlay; card carries "Take <Creature>'s turn" (enabled only when `CanClaimTurn`); implicit claim at target confirm only when legal; Esc backs out fully; owner-selection prompt (named individuals, hover/focus pulse) is part of preview. | not started | Decisions 47, 36, 32. |
| Phase 2 | Lenses + sub-filters (WalkParsedSegments cache), "Everyone can:" line, reach estimate, per-lens sort keys on chips, copy pass (X13), select-all button, Suggested overlay opt-in. | not started | |
| Phase 1.5 | Compare tray, condition icons, band-malice columns, drawer rationalization details. | not started | Decisions 43-46. |

## Field test log

**2026-08-14, first user test of slice (c) (Ricky, live A5 game):**
- BUG (fixed, commit fa2053b7): pressing Unique Abilities did nothing after any
  ordinary drawer menu had been opened. Root cause: the unique branch assigned
  ONLY its own columns to `m_containerPanel.children`, which orphaned - and the
  engine then destroyed - the ordinary pooled `m_submenus`; the next open crashed
  on a dead panel (`submenu.data` nil) so the click appeared inert. Both menu
  paths now keep every pooled panel parented and collapse the unused ones. Rule
  for anyone touching the action menu: NEVER assign a children list that omits a
  pooled panel you intend to reuse.
- NOT A BUG (user perception): "warrior + assassin didn't do anything" - the
  Goblin Assassins in A5 are horde monsters, not minions, so that selection WAS
  overview mode; it was hit by the same crash above. Squad exception is
  separately verified (4 runners of one squad -> classic strip).
- Debugging trap (record for the future): DMHub's Lua tracebacks report line
  numbers of the CHUNK AS LOADED; after editing a file, stale tracebacks keep
  showing pre-edit numbers until reload, and a reload CLEARS the token
  selection, so a "press" right after reload is a no-op (g_token nil). Always
  re-select tokens after reload_lua before testing menu behaviour, and read the
  console's sequence numbers, not the entry list, to know if an error is new.

## Phase 0 findings

### ANSWERED 2026-08-14: what "claim turn" actually does

Read from MCDMInitiativeBar.lua:4570-4604 (the `selectinitiative` closure) and
Creature.lua:9072 (`creature:BeginTurn`). Claiming a turn does FOUR things:

1. `q:SelectTurn(k)` - sets the current turn on the initiative queue.
2. `dmhub:UploadInitiativeQueue()` - **uploads to the cloud, so EVERY client's
   initiative bar updates immediately.** Claiming is a broadcast, not a local act.
3. `tok.properties:BeginTurn()` for every token in that initiative id - which
   clears momentary ongoing effects, then dispatches the `prestartturn` (and
   subsequently start-of-turn) triggers via a coroutine. These are real, chained
   state mutations, not a flag flip.
4. `chat.SendCustom(StartOfTurnChatMessage{tokenids})` - **posts a player-visible
   chat card naming the token(s) whose turn began.**

Consequences, now settled rather than assumed:
- There is NO unclaim path in this code, and BeginTurn's trigger dispatch is not
  cheaply reversible. So a design where a browse click can claim is unrecoverable
  by construction - Decision 47 (never claim during preview) is not merely
  preferable, it is the only safe option.
- The experienced reviewer's hidden-ambusher leak is REAL and is caused by items
  2 and 4 together: the initiative bar and a chat card both announce the monster.
- Minions/groups claim as a unit (BeginTurn runs for every token sharing the
  initiative id), which matches the squad-acts-together model.
- `CanControlInitiative()` is file-local (:277) and the whole sequence is an
  inline closure: extracting `InitiativeQueue.ClaimTurn(initiativeid)` is a
  prerequisite for reusing it from the overview, as the engine reviewer said.

**Conflict surfaced and resolved:** Decision 47 says the claim happens at target
confirm; Decision 24 says off-turn ability use must NOT alter turn state. These
collide when the director casts off-turn. RESOLUTION: the implicit claim at target
confirm fires ONLY when claiming is legal (`q:ChoosingTurn() and not
q:IsPlayersTurn()` and the entry is unmoved). Off-turn, target confirm casts
without touching the queue, exactly as today. The explicit "Take <Creature>'s
turn" button on the preview card is hidden/disabled with a reason off-turn.

### ANSWERED 2026-08-14 (live spike, A5 game): multi-select and locate

Ran with the app up: `dmhub.selectedTokens = {assassin, stinker}` (programmatic
multi-select, the exact mechanism the select-all button will use).
- **Multi-select HOLDS and the action bar APPEARS for it.** `selectedTokens` and
  `selectedOrPrimaryTokens` both report the two tokens; the drawer strip rendered
  at the bottom of the screen for the multi-selection (screenshot verified).
- **The bar binds to the FIRST token only:** with both selected it reports
  binding to "Sneaky Goblin Assassin" and ignoring "Goblin Stinker 1" - exactly
  the `selectedOrPrimaryTokens[1]` behaviour the engine reviewer read from
  DrawSteelActionBar.lua:1777. So the hud refresh DOES fire on multi-select (no
  gap there); the work is purely in the bar: read the whole list, not [1].
- **`dmhub.CenterOnToken` pans WITHOUT touching selection** - after centering on
  the stinker the selection was still both tokens. Confirms X5's fix: locate =
  CenterOnToken (never FocusToken).
- **`dmhub.PulseHighlightToken(charid)` accepts a charid and runs cleanly.**
  Colour is engine-fixed (no parameter).

### STILL PENDING (needs two connected clients)

- **Pulse locality:** whether PulseHighlightToken is visible to other clients.
  Fallback if broadcast: the TokenHud.RegisterPanel pattern
  (DrawSteelTokenHud.lua:19-60), which is director-local by construction and
  can carry role colour.

### The question the brief could not answer (A, E agree) - NOW ANSWERED ABOVE

What EXACTLY does "claim turn" do in the engine, what do players see the instant
it happens (initiative bar, aura, hidden tokens), and can cancelling targeting
revert ALL of it cleanly? Every interaction decision (11/12/18/24/36) is
downstream. E located the code (MCDMInitiativeBar.lua:4577-4602) - the answer is
a phase-0 read, not a design guess.

## Open questions (interview in progress)

- Mockup v2 aesthetic sign-off: lens bar look, chip fidelity to AbilityHeading,
  traffic-light dot, column density (user was "very concerned about aesthetic").
- Select-all-fresh button: does it auto-open the Unique Abilities folder or is
  that a separate click? Test both (Decision 23).
- At-risk heuristic refinement: user may ask MCDM designers/devs/community;
  question phrasing drafted (see chat 2026-08-14). v1 ships the simple heuristic.
- Multiplayer/visibility: pulse + camera pan must be DIRECTOR-LOCAL only (players
  must not see browsing; hidden ambusher positions must not leak). Verify
  PulseHighlightToken locality; the white active-turn aura is engine-rendered
  (C#) - role-COLORED pulse needs either an engine color param or the Lua
  token-hud pulse pattern (DrawSteelTokenHud.lua dead-minion pulse).
- Role -> color mapping (10 roles + Leader/Solo): palette TBD, must stay
  color-blind-legible with role text/glyph always paired.
- States: round rollover, monster death mid-browse, mid-session join, minion
  squads acting together, abilities gained mid-fight (novelty pip composes).
- Naming ("Unique Abilities" is working copy; every string needs sign-off).

## Reference encounters for stress-testing (evidence, 2026-08-14)

Most complex encounters per adventure (unique statblocks, scanned from PDFs):
- Delian Tomb: A5 war room (6 statblocks + leader + per-round reinforcements);
  "Hail to the Queen" (mounts + 32 minions); D8 (5 statblocks + reinforcements).
- Fall of Blackbottom: "To the Skies" (7: mucerons, war dog neuronite/
  subcommander/tetherite, lesser chorogaunt, pitlings); "Pursuing the Lantern"
  (6 human bandits); "Drunken Fool Ground Floor" (6 demons).
- Red Road: "Hunger Hunters" (5: gnoll chainflails/maulers/spikesnatcher +
  relentless tusker demon); "Siege of the Gnolls" (4).
- Dark Heart of the Wood: "Chapel" (4 threxyl types).
- The Condemned: war dog battles scale PER CHARACTER (up to 5 war dog types at
  once, e.g. commandos/equivites/hypokrites/sparkslingers/sweepers) - roster
  count scales with party size.

## Rules findings (verified against source texts, 2026-08-13)

- **Band Malice window** (Draw_Steel_Monsters_v1.01.pdf + monster-reference.md):
  "At the start of any goblin's turn, you can spend Malice to activate one of the
  following features." Same template for rivals, bugbears, hobgoblins, and the
  universal features (Brutal Effectiveness 3, Malicious Strike 5+). A band feature
  cannot be decoupled from a turn: the acting monster's turn start IS the window.
- **Role-based activation order**: the Monsters book has NO formal rule for which
  roles act first. It has per-role play-pattern prose (controllers "use their
  biggest and most powerful effects at the start of an encounter"; artillery
  reposition behind brutes; ambushers hide; leaders/support stay near allies) and
  the "Whoa! Those Minions Died Too Quickly!" sidebar acknowledging minions can die
  before acting. The user's minions-first/leaders-last heuristic is table craft,
  consistent with but not codified by the book.

## Mockup

**STALE NOTICE (2026-08-14): mockup v1's standalone-panel SHELL is superseded by
Decision 13 (action-bar-native). Its interaction grammar survives: facets with
counts, per-lens sorts, single-instance chips with badges, owner attrition
signals, acted de-emphasis, usability greying, front-door claim. Mockup v2 will
recreate the grammar inside the real action bar's visual frame.**

Interactive mockup v1 (2026-08-13): https://claude.ai/code/artifact/2c6cc22e-0a0d-4344-90df-aa297f4ffe51
Working mockup v2-v4 (action-bar-native, Delian A5): https://claude.ai/code/artifact/5dffc044-6c6e-4ee3-ba40-e0ac9cf66675
REVIEW mockup (shareable, intro card, drawer fidelity, "All Units"):
https://claude.ai/code/artifact/c16802cc-471b-462e-af85-5d782369b9a4
Source: session scratchpad directors-overview-mockup.html. Demonstrates: facet
chips with counts + condition/shape sub-facets, per-lens sorts, single-instance
rows with facet badges, owner badges carrying attrition signals (role, stamina,
fresh count, acted de-emphasis), band malice strips with pool affordability,
scope narrowing (all vs map selection), two-stage preview with schematic map +
reach check, front-door Use button. Data is the real Bargnot ambush encounter.
NOTE: companion artifact - re-sync or mark stale when the brief moves.
Known fabrications for demo purposes: token positions are schematic; Illwyth's
role line abbreviated; one warrior squad/Gorek/Illwyth marked acted (simulated).

## Out of scope / rejected (with reasons)

- Prep-time study surface (Decision 2): different solution case.
- Tactical recommendation engine (Decision 3): the Director judges; the Codex organizes.
- Passive-trait synergy prompts (Decision 5): cherry-on-top, revisit only after core ships.
