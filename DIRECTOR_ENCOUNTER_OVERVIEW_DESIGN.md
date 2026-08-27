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
| (d) | Column footer bar (legacy heading position): real portrait, statblock name (+xN), the stat block's own role line, stamina band Low/Moderate/High, acted state (fresh/acted, "k of N fresh"), per-member mini-rows when N>1 (first 3 then +N more), whole-column dim when all acted; click = `dmhub.CenterOnToken` + `PulseHighlightToken` on the members (never FocusToken, selection untouched). Signals only, no verdict (Decision 48). | **DONE 2026-08-14, committed b913b369, live-verified** (portraits/role/stamina/acted rendered; Warrior x2 mini-rows; locate preserved a 4-token selection; ordinary/unique alternation zero runtime errors). Built by a sub-agent that hit the session limit mid-run; the code was complete and wired, only verification + this row were finished by the main session. | Implementation: `OverviewColumnFooter()` (~2910) pooled per `ActionSubMenu` as `m_footer` (~3096), driven by `FireEvent("overviewColumn", column, signals)`; signals via `OverviewColumnSignals(column)`; `OverviewStaminaBand`, `OverviewActedState`, `OverviewRoleLine`, `OverviewLocate` helpers above it; styles in `OVERVIEW_FOOTER_RULES` (~871) merged into the root cascade beside NOVEL_MARKER_RULES. The unique branch passes the column record as the 2nd arg of `setCasterToken` (~3495). For slice (e): the footer press handler is the natural home for a "Take <Creature>'s turn" button and the column record (`m_column`) is available inside the submenu. NOTE: the "created but not attached" load-time warnings for drawers are PRE-EXISTING for every drawer (Main Action, Maneuver, Move, Respite, Malice) - not a regression. |
| (e) | Preview-on-click + take-turn + implicit claim at target confirm (Decisions 47/32/36/24, Phase 0 resolution). Minimum cut: NO pinned ability card - the existing hover card + the targeting overlay drawn by `beginCasting` are the preview; "Take <Creature>'s turn" lives on the slice-(d) footer, not on a card. | **DONE 2026-08-17, reload-verified in the A5 war room** (luac -p clean, ASCII-clean, CRLF preserved; 43 mods reloaded, zero new codex errors - the only console errors are the PRE-EXISTING "created but not attached" load warnings and two stale entries from an older session). Live checks: (1) queue found `ChoosingTurn=true, IsPlayersTurn=false, round 1, currentTurn=false`, nobody acted -> 4-token selection (Monarch, Warrior 1+2, Stinker 1) showed three footers with ENABLED buttons "Take Goblin Monarch's turn" / "Take a Goblin Warrior's turn" / "Take Goblin Stinker's turn"; (2) pressed the Stinker button (logged `ABOUT TO CLAIM`): console `OVERVIEW:: claiming turn for 78ec9592...`, `currentTurn` == the Stinker entry, `dmhub.selectedTokens` unchanged (4 charids identical), menu re-read the queue: Stinker button disabled "Turn taken - acting now", other two disabled "Another creature's turn is in progress", Stinker signal line "Stamina: High - acting now"; (3) Warrior chip (Spear Charge) with 2 members: in this game BOTH warriors share ONE initiative entry (`initiativeGrouping` 012aecff...), so it is correctly a single-candidate column -> located + cast began for Goblin Warrior 1 (`push g_token`, `TARGETDIAG caster=Goblin Warrior 1`), `currentTurn` unchanged (no claim at chip press), cancelCasting popped back to the 4-token selection; (4) owner prompt exercised with 3 Goblin Snipers spanning two initiative entries (Squad 5 x2 = 37335e55, Squad 4 = f515ba2a): Bow chip -> `OVERVIEW:: chip press Bow candidates 2`, footer showed "Choose which Goblin Sniper uses Bow" + two `promptOption` rows ("Goblin Sniper Squad 5 (2) - ...", "Goblin Sniper Squad 4 - ...") + button reading "Cancel"; hover fired on row 2 (pulse); press row 2 -> `push g_token`, `TARGETDIAG:: ability=Bow caster=Goblin Sniper` for a NON-primary sniper, `currentTurn` unchanged; cancelCasting popped, selection intact; Esc on the drawer hid the menu and disarmed the prompt (button back to "Take a Goblin Sniper's turn"); (5) single Goblin Warrior 1 + Main Action: classic Abilities / Signature Abilities / Common Abilities menu, 9 chips, ZERO take-turn buttons visible. UNVERIFIED-LIVE: the POSITIVE implicit claim at target confirm (an overview cast confirmed while `ChoosingTurn` - the queue was inside the Stinker's turn after check (2), so only the refusal branch was reachable, and a real cast has chat/damage side effects); it is the same `OverviewClaimTurn` the button verified, behind the same gate. Harness trap recorded below. UNCOMMITTED in git. | HOW IT WORKS (all `DrawSteelActionBar/DrawSteelActionBar.lua`): **claim gate + hook** near the top: `g_overviewCastPending` (:158) = `{token, initiativeid}` or nil; `OverviewClaimGate(initiativeid)` (:166) -> ok, reason - stricter than `InitiativeQueue.CanClaimTurn`: no/hidden queue "No initiative running"; not in `q.entries` "Not in the initiative order"; `q.currentTurn == id` "Turn taken - acting now"; `HasHadTurn` "Already acted this round"; not `ChoosingTurn` "Another creature's turn is in progress"; `IsPlayersTurn` "It's the heroes' turn - browse only"; then `CanClaimTurn(id, {canControlInitiative = dmhub.isDM})`. `OverviewClaimTurn(id)` (:194) = gate + `InitiativeQueue.ClaimTurn`. **THE PRE-CAST HOOK is `OverviewClaimBeforeCast(g_token)` (:207)**, called at exactly the two `ability:Cast` sites, immediately after `FireCastControlsOnCommit` and before `Cast` (mappress commit :8794, `CalculateSpellTargeting` commit :9209 - the same shared pre-Cast ordering the cast controls already use). It consumes the pending record (one-shot: `g_overviewCastPending = nil` first), requires `pending.token.charid == g_token.charid` AND `GetInitiativeId(g_token) == pending.initiativeid`, then `OverviewClaimTurn` (which re-runs the gate); any failure = cast proceeds untouched (Decision 24). **The record is SET only in the overview chip commit** (`AbilityHeading` press, `commit(casterToken, ability)` :2528-2549: after the in-flight `cancelCasting` + `PushCasterToken`, before `beginCasting`, and only when `args.overviewPress ~= nil`; ordinary chips set it to nil) and **CLEARED in `cancelCasting` (:6840)**, which finishCasting / Skip / Esc / opening another menu / controller disable / restoreFromBackup all funnel through. **Chip hook**: `ActionSubMenu` defines `OverviewChipPress(ability, casterToken, commit)` (:3633) and passes it as the 2nd arg of the chip's `setCasterToken` event (`AbilityHeading` :2336 stores it as `args.overviewPress`; nil for every ordinary menu, whose press path is unchanged). Press = `OverviewColumnSignals` -> `OverviewFreshCandidates(signals)` (:3104, fresh members deduped by initiative id, minus `acting`) -> if >1: arm the footer prompt with the ability remembered; else `OverviewLocate(owner)` (CenterOnToken + pulse) then `commit(owner, ability)`. When the prompt hands the cast to a non-representative member, `OverviewMemberAbility(memberToken, ability)` (:3129) fetches THAT member's own bound copy (same guid + melee/ranged variation via `NovelAbilityKey`) and the column record + `m_casterToken` are re-pointed to the member (`m_column.token = member.token`) before `commit`. **Footer (pooled, created once in `OverviewColumnFooter` :3190)**: `takeTurnButton` (:3320) + `reasonLabel`; `LayoutTakeTurn()` recomputes from the live queue on every `overviewColumn`: single fresh entry -> gate on the representative's id; several fresh entries -> enabled if ANY passes, press arms the prompt (`choose` = `OverviewClaimTurn(member.initiativeid)`); text via `OverviewTakeTurnText` (:3159; "Take X's turn" / "Take a X's turn", "Take turn" past 32 chars, full text + reason in the hover tooltip AND inline in `reasonLabel`). After a successful claim the footer fires `refreshOverview` on the `actionMenu` (:4045) -> `PopulateUniqueColumns()` (:3958, shared with the "unique" menu open; also parks pooled columns beyond the selection's count as collapsed+unbound and keeps EVERY pooled column in the container list - fixes a latent (c) orphaning when a later selection had fewer statblocks). **Owner prompt** = footer event `armOwnerPrompt(prompt|nil)` (:3502; forwarded by `ActionSubMenu` :3690): `prompt = {members, ability|nil, choose}`; while armed the mini-rows list only the fresh members (whole `OVERVIEW_FOOTER_ROW_POOL` = 6 rows, class `promptOption`), hover pulses the member's tokens (Decision 36), press disarms then `choose(member)`, the button reads "Cancel" (press disarms), `promptLabel` reads "Choose which <Statblock> uses <Ability>" / "takes the turn". Disarmed by: any repopulate (`overviewColumn`), the row press itself, `DisarmOverviewPrompts()` in `ActionMenu` (:3947) from `closemenu` and from the top of every `menu` event (so Esc, click-away/mappress, drawer toggle and menu switches all back out). Signals gained `member.acting` (`q.currentTurn == id`) -> "acting now" text. Styles: `overviewFooterPrompt`, `overviewFooterRow.promptOption`, `overviewTakeTurn` (+`disabled`), `overviewTakeTurnReason` in `OVERVIEW_FOOTER_RULES`. NOT DONE (deliberate cut): pinned `ActivatedAbility:Render` card, reach math, Lua hotkeys / focus parity for the prompt (X4) - Phase 2. |
| Phase 2 | Lenses + sub-filters (WalkParsedSegments cache), "Everyone can:" line, reach estimate, per-lens sort keys on chips, copy pass (X13), select-all button, Suggested overlay opt-in. | IN PROGRESS 2026-08-19, sliced below | Ricky is near his weekly usage limit: every slice must be independently shippable and recorded here before the next starts. |
| P2-a | **Threat flags / status on the footer** (the 2026-08-18 play observation; Decision 15's condition icons, X15): the SAME status icons the token HUD shows (TokenUI.CalculateStatusIcons exposed as a generic hook) rendered >=16px in a footer strip for a single-member column (one row of up to 5 + "+N", hover = the token HUD's hover text); multi-member mini-rows mirror the names as text. An effect/condition whose CASTER is a hero (a Tactician's Mark) is a THREAT FLAG: red ring on the icon + red "<Status> by <Caster>" text on the signal line - deterministic, says who the heroes intend to kill. | **DONE 2026-08-19**, live-verified | `TokenUI.CalculateStatusIcons` exposed (one line, read-only). `OverviewStatusEntries(tok)` filters out the director eye + the walk-elevation glyph, marks `threat` when the caster is not a director monster (`IsOverviewCreatureToken`), threat entries first. Footer: pooled `overviewStatusStrip` (5 x 18px `overviewStatusIcon` + "+N", bgcolor from the HUD style, `threat` = 2px #E06464 ring, hover = HUD hover text) shown for single-member columns; `OverviewThreatText` appends red "Judged by Human Censor" to the signal line (caster named only while the line fits ~26 chars, else just "Judged"), on header AND mini-rows. Live: A5 Sneaky Assassin carries "Judged" cast by the Human Censor -> red-ringed Judged icon + red "14/15 - Judged"; Monarch/Stinker strips collapsed. Regression check passed, zero console errors. NOT done: non-threat statuses on multi-member rows (only the threat mirror), a column-level "N marked" summary. |
| P2-b | **Select-all** (Decision 39): director-only control that selects every director monster on the map that has not acted (or all, out of combat); does NOT open the folder. | **DONE 2026-08-19**, live-verified | Home = the initiative bar's "Ready Monsters" label (MCDMInitiativeBar.lua ~:3976, monster side, Director only; hover tooltip "Click to select every ready monster on the map"): it is the one label on screen that already means "these have not gone yet" and it is visible with ZERO tokens selected, which the action bar is not. Backed by `DrawSteelActionBar.SelectReadyMonsters()` (~:180: alive `IsOverviewCreatureToken` tokens on the current map, minus `HasHadTurn` when a queue runs; sets `dmhub.selectedTokens`, returns the count). Live: press -> 16 selected (12 Snipers, Runner, Monarch, Stinker, Assassin), strip = trigger / unique / malice, folder NOT opened, zero console errors. If a bar-strip button is still wanted, call the same helper. |
| P2-c1 | **Lens control + filtering + per-lens sort** (Decisions 8/21/27/31/49, X3): fixed-width lens control above the columns (All / Damage / Area / Forced Move / Control / Malice + counts), hides non-matching columns and centers the rest, dims non-matching chips (opacity >= .45), per-lens natural sort within a column. | **DONE 2026-08-19**, live-verified | `OVERVIEW_LENSES` + session-scoped `g_overviewLens`; `OverviewTierFacets(text)` (cached per tier string) walks `ActivatedAbilityDrawSteelCommandBehavior.WalkParsedSegments` and reads the builtin match groups `damage` / `movement`+`distance` / `condition` (the regex rule matcher, never substring); `OverviewAbilityFacets(ability)` adds keyword Area (+radius/range size), DamageBehavior, ForcedMovement*/OngoingEffect*/InflictCondition* behaviour types, and malice cost via `GetHeroicResourceOrMaliceCost` -> {damage/damageValue(tier 2), area/areaSize, forced/forcedDistance, control, malice/maliceCost}. `OverviewLensLess` = Decision 21 sorts (ties: tier-2 damage desc, name). `ActionSubMenu` overview populate: lens sort WITHIN the main/maneuver partition, `onLens` (gold frame) / `offLens` (opacity .45) chip classes, column collapses when `lensMatchCount == 0` (stays populated; `data.lensMatchCount`). `ActionMenu`: `m_lensBar` (237px, `< Filter: Malice (2) >`, label press = ContextMenu of all lenses with counts, `overviewLensEmpty` line when a lens matches nothing) above `m_containerPanel`, shown only for the unique menu; `m_relens` re-runs PopulateUniqueColumns on change; `refreshOverview` refreshes counts. Live (Monarch, Stinker, Assassin, Runner, 6 Snipers): All (9); Damage (7) = Handaxe x2 / Toxic Winds / Sword Stab + Shadow Chains / Club Charge / Bow framed, Get in Here! + Swamp Gas dimmed; Area (2) = Stinker only; Forced Move (1) = Toxic Winds; Control (1) = Shadow Chains (restrained); Malice (2) = Monarch + Assassin columns centered, Get in Here! + Shadow Chains framed. Regression check passed, zero console errors. NOT done (P2-c2): sort key printed on chips, sub-filter chips, "Everyone can:", condition icons on chips, Lua hotkeys; importer-table (data-driven) condition patterns are not yet read as Control. |
| P2-c2 | Per-lens sort key on chips (X14), sub-filter chips for Control/Area/Forced Move, "Everyone can:" dimmed line (X6), condition icons on chips (Decision 45). | **PARTLY DONE 2026-08-19** (sort keys + "Everyone can:"), live-verified | Lens block moved above `AbilityHeading` (it needs `GetHeroicResourceOrMaliceCost`, ~:505). Facets now carry `forcedVerb` and `conditions` (names from the parser's `condition` group, or the ongoing effect's condition via `characterOngoingEffects[...].condition`); the Control facet only counts an ongoing effect that CARRIES a condition (Defend/Aid Attack/Charge buffs no longer read as Control). `OverviewLensKeyText` -> "10 damage per target" (tier 2), "Area 3", "Slide 3", "Restrained", "3 Malice", printed by a pooled `overviewLensKey` label on matching overview chips only while a lens is active. `EveryoneCanText` in the lens bar: the first column's representative's NON-kit abilities (minus Trigger/Villain/Malice/Hidden) that match the lens, sorted, 4 + "+N" ("Everyone can: Melee Free Strike, Ranged Free Strike" under Damage; "Everyone can: Knockback" under Forced Move). Condition icons on chips DONE (same day): `OverviewConditionIcons(facets)` maps `facets.conditions` names to `charConditions` (lowercase name match, powertable entries preferred) -> iconid + display bgcolor; `AbilityHeading` gained a pooled `overviewConditionRow` (2 x 16px glyphs + "+N", tooltip "Can apply: Restrained") under the keywords on overview chips only, always on, not lens-gated. DEVIATION from Decision 45's "right corner": that corner already holds the cost diamond and the novelty pip, so the glyphs sit inline under the keywords. Live: Shadow Chains shows the Restrained glyph (the token-HUD art). STILL OPEN: sub-filter chips (Control by condition / Area by shape / Forced Move by verb), Lua hotkeys (X4). |
| P2-d | **Reach estimate** (X7, Decision 48 signal): "N enemies within reach" per column from movement + ability range; partial-reach badge on mini-rows. | **DONE 2026-08-19**, live-verified | `OverviewHeroTokens()` (live, non-object, non-director tokens on the map), `OverviewKitRange(tok, kit)` (longest `GetRange` among kit abilities whose targetType is not self/emptyspace/anyspace/map; melee = 1), `OverviewReach(tok, kit, heroes)` = speed (`GetSpeed`) + range, count heroes whose nearest occupied square is within that many squares (Chebyshev = Draw Steel counting; walls/terrain ignored - an ESTIMATE, the tooltip says so). Computed per member in `OverviewColumnSignals` only while a queue runs. Footer: new `overviewFooterReach` line "5 heroes in reach" / "1 hero in reach" / "No hero in reach" for single-member columns (hover: "Heroes within 11 squares: speed 6 + longest range 5. Straight-line estimate; ignores walls and terrain."); mini-rows append "0 in reach". Live: Monarch/Assassin/Stinker in the A5 room = 5 heroes in reach; Sniper squads far off = 0 in reach. Regression check passed. |
| P2-e | **Threat estimate** (F2-5c): whole-hero-turn risk band with reasons, never a verdict. | **DONE 2026-08-19**, signed off + live-verified | Ricky's answers: (1) safe = print NOTHING (he may revisit); (2) spent heroes count at HALF weight, not zero ("Strike Now" can invoke a spent hero); (3) a third footer line with the reasons, hint in the tooltip. Implementation (`g_overviewRisk` single local - NOTE: the file is at Lua's 200 top-level-locals ceiling, consolidate new state into tables): `OverviewHeroProfiles()` (cached per dmhub.Time(): speed, longest damaging range, best tier-2 burst via the lens facets parser, HasHadTurn); `OverviewThreatEstimate(tok, marked, inCombat)` -> nil when safe else {level, text, tooltip}: heroes who can STRIKE the monster (hero speed + range >= Chebyshev distance), adjusted burst = burst x0.5 when spent, RED = marked-with-anyone-in-reach OR stamina <= best burst + 4 (rider/mark allowance), AMBER = stamina <= two best bursts + 4 OR marked-out-of-reach. Footer: `overviewFooterRisk` line (wraps) "High target risk - marked by heroes, 5 heroes in striking range" / "At risk - ..."; worst member speaks for a multi-member column; mini-rows get a short "high risk"/"at risk" tag. Tooltip = reasons + the arithmetic + "Hint: consider using this monster's turn before the heroes strike" + the estimate caveat. Live: Judged Assassin = RED marked+5-in-reach; 9/10 Stinker = RED (burst 10 + 4 vs 9); 80/80 Monarch = silent; far Snipers = silent with amber "0 in reach" rows. Hero portraits idea parked: revisit with the tooltip once field-tested. |
| P2-f | Copy pass X13 (incl. move OVERVIEW_ROLE_PROSE to data/), first-open hint strip, Suggested overlay opt-in (Decisions 30/48). | not started | |
| Phase 1.5 | Compare tray, condition icons, band-malice columns, drawer rationalization details. | not started | Decisions 43-46. |

**Phase 1 COMPLETE (2026-08-17).** Slices (a)-(e) are all built and
reload-verified in the A5 war room: the Director multi-selects monsters, gets
the "Unique Abilities" drawer with one pooled column per statblock (chips cast
for that statblock's representative via `AbilityHeading{casterToken}`), each
column carries the identity/signals footer (portrait, role, stamina band,
fresh/acted/acting-now, per-member mini-rows, locate on click) and a
"Take <Creature>'s turn" button that is enabled only at the legal
start-of-a-director-turn juncture and otherwise greyed with an inline reason;
a chip press locates the owner and begins the ordinary cast without claiming,
asking which member acts when a column spans several fresh initiative
entries; the claim itself happens exactly once, at the first irreversible
step (immediately before `ability:Cast`), and only if still legal at that
instant - off-turn casts leave the queue untouched. Ordinary single-token
menus are unchanged. The positive claim-at-confirm branch was verified in
real play on 2026-08-18 (third field test).

**Field-test follow-ups COMPLETE (2026-08-19, commits dfcf10c9 .. 180f4566,
all local on `main`, NOT pushed - Ricky decides when).** Everything the
first four user tests asked for is built and live-verified in the A5 game:

| Item | What the Director now sees | Commit |
|---|---|---|
| F3-1 | Chip/footer locate: camera pans (~0.5 s), THEN the token gets a gold `locate` ring held 1.4 s (new generic bottomsheet style in `DMHub Token UI/TokenUI.lua`) | dfcf10c9 |
| F3-2 | Take-turn button HIDDEN once the turn is taken / already acted / nothing running; greyed-with-reason only for transient blocks ("Another creature's turn is in progress", "It's the heroes' turn", "Not in the initiative order") | dfcf10c9, de80fe54 |
| F2-4/F2-5 | Footer text >= 12px, names ellipsized, raw `13/15` stamina (+T temp), two-line mini-rows (name / `18/18 - state`) | de80fe54 |
| F2-3 | "Take the Goblin Assassins' turn" when every member token shares one initiative entry | de80fe54 |
| Layout | `abilitySubMenu` vertical `wrap` misfired once the footer passed ~70px; overview columns set `selfStyle.wrap=false` while bound | de80fe54 |
| Action type | Overview chips carry a 12px gold "Maneuver" / "Free Maneuver" / "Free Action" line (main actions unmarked); columns sort main actions first, hairline between main actions and maneuvers | 71464388 |
| F2-7 | Every chip of an all-acted column greys (title/keywords/icon via an `acted` class tree) | 4a20c599 |
| F2-8 | Dismiss "x" per column (deselects its tokens); the open menu follows the selection live and survives a primary-token change | a385bec2 |
| F2-9 | Role word leads the footer role line in bold gold ("Controller  Level 1 Horde"); hover = one-line play pattern per role/organization (`OVERVIEW_ROLE_PROSE`, Lua table for now) | 8ce9d2d3 |
| Field test 4 | "Not yet acted" dropped (default is silent); acted = red "Turn already taken" on greyed chips; "Acting now" mid-turn | 180f4566 |

STANDING REGRESSION CHECK (passed after every commit above): open a Unique
menu, close it, select ONE monster, open Main Action -> "Signature Abilities /
Common Abilities", 9 chips on the Monarch, 0 take-turn buttons, 0 dismiss x.

"Get in Here!" DATA fix DONE (2026-08-19): draw-steel-data `3fb500c` on
origin/main (`categorization: Signature Ability` -> `Heroic Ability`, the
goblin convention for malice-costed non-signature abilities - Bury the Point,
Shadow Chains). Made in a throwaway worktree off origin/main and pushed
directly; the LOCAL `data/` checkout was NOT touched - it is 127 commits
behind origin/main with the usual export churn plus a one-line uncommitted
hunk that turned out to be already upstream as rickdog's `9629848`. The app
reads local data/, so the live game sees the fix only after a data/ sync
(Ricky's call - back up first, [[data-repo-push-discipline]]) and the placed
A5 Monarch keeps its own snapshot until re-placed/resynced. Noted in passing:
upstream Get in Here! still carries a stale `villainAction: Villain Action 2`
field (harmless unless the categorization were Villain Action; left alone).

NEXT: Phase 2, but start with what the 2026-08-18 play
observation asked for, not the lenses: (1) Marked / condition THREAT FLAGS on
the column (deterministic, says who the heroes intend to kill), (2) the
whole-hero-turn threat estimate as a risk band with reasons (never a
verdict), then (3) lenses + sub-filters, "Everyone can:" line, reach
estimate, copy pass X13, select-all, Suggested overlay opt-in. Also move
`OVERVIEW_ROLE_PROSE` into data/ when X13 settles the wording.

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

**2026-08-17, slice (e) verification (agent, live A5 game):**
- Live data surprise: in A5 the two Goblin Warriors, the two Stinkers, the two
  Assassins and (Cursespitter + all Runners) each share ONE initiative entry via
  `initiativeGrouping`, and the 12 Goblin Snipers span three entries with two of
  them named "Goblin Sniper Squad 5". So "x2 column => owner prompt" is NOT a
  given: the prompt keys on distinct initiative ids (correct per Decision 32),
  which is why the Warrior column claims/casts directly and only the Sniper
  selection exercised the prompt.
- Harness trap (record for the future): `GetChildrenWithClassRecursive
  ("abilityHeading")` also returns chips of the classic menu's pooled
  Abilities/Signature submenus, which sit inside a COLLAPSED wrapper but are not
  collapsed themselves - pressing one of those from Lua casts for `g_token` and
  looks exactly like "the overview chip cast for the wrong creature". Walk the
  parent chain to the actionMenu and require no `collapsed` ancestor before
  firing "press" (the `FindVisibleChip` helper used in this session).
- `HasHadTurn` stays FALSE for the entry whose turn is in progress (it flips at
  end of turn), so "acted" alone cannot show a claim; the footer now reads
  `q.currentTurn == id` as "acting now" / "Turn taken - acting now".
- Live state left behind: the Goblin Stinker entry's turn was claimed (and
  left in progress) as the one authorised claim of this session.

**2026-08-15, second user field test (Ricky, live A5 game, after Phase 1 complete).**
Triaged; each item carries a proposed disposition. Nothing below is implemented yet.

- **F2-1 BUG (scope): the overview fires for multi-selected HEROES too.** Overview
  mode is gated on `dmhub.isDM and #selected > 1`, not on the tokens being
  director-controlled, so a DM selecting several player characters gets columns.
  Heroes are far more complex than monsters and the design was never for them;
  followers/retainers are monster-like and might fit, but not now.
  DISPOSITION: gate overview mode on ALL selected tokens being non-player
  (`not tok.playerControlled`, or the creature not being a hero); mixed
  selections fall back to the classic strip. Small fix; do first.
- **F2-2 REGRESSION (must fix first): single-monster selection lost its unique
  abilities.** Selecting one monster (e.g. the Monarch) no longer shows its
  signature/heroic abilities where they used to be. Root cause hypothesis: the
  drawer refresh collapses/hides Main Action/Maneuver based on overview state OR
  the categorization filter (`IsUniqueKitAbility`) leaked into the ordinary
  path. The intent (Decision 43) was ALWAYS that single selection is
  byte-for-byte unchanged. DISPOSITION: reproduce with one token, compare to
  the committed slice-(c) behaviour, fix, and add "single token shows
  Signature/Common columns exactly as before" to the standing regression check.
- **F2-3 QUESTION answered by data: "which Assassin does the take-turn button
  activate?"** Live check: Sneaky and Dizzy SHARE ONE initiative entry
  (`initiativeGrouping` = same id), so in this game they act as one entry and
  the button legitimately claims that entry for both - there is no choice to
  make. When two same-statblock monsters have DISTINCT entries the footer's
  owner prompt (slice e) asks which one. DISPOSITION: no code change; but the
  button copy should say "Take the Goblin Assassins' turn" (plural) when the
  column's members share one entry, so the Director is not surprised.
- **F2-4 BUG (layout): footer mini-row label overflows the chip border**
  ("Goblin Warrior 1 - Stamina: High - fresh", class overviewFooterRowLabel,
  ~:3248). DISPOSITION: constrain width, ellipsize, and shorten the copy (see
  F2-5); also raise the size - user reports it is very small on a laptop
  screen (X11 floors: 11px glance / 12px read).
- **F2-5 COPY + CONCEPT: "Stamina: High - fresh" is not understood.** "fresh"
  (= has not acted this round) is our jargon; "High" is relative to the
  monster's own max, so a 15-max Warrior and an 80-max Monarch both read
  "High" - the user correctly notes that tells him nothing about survivability.
  Live: 25 of 28 director tokens are at full stamina, so every footer says
  "High". DISPOSITION: (a) replace "fresh"/"acted" with "Not yet acted" /
  "Acted"; (b) DROP the qualitative band as a headline signal and show the raw
  "13/15" (cheap, unambiguous - Decision 9's "show raw numbers" spirit);
  (c) the survivability signal the user actually wants - "if the heroes target
  this creature, will it likely die before it acts?" - depends on hero damage
  output (level, abilities, items) and is a Phase-2 THREAT ESTIMATE, not a
  stamina band. Design it explicitly (e.g. compare max stamina to the party's
  typical tier-2 damage x reachable heroes); until then show the number.
- **F2-6 BUG (pre-existing?): the novel-ability diamond pip on a drawer
  disappears after opening and closing the menu even when nothing was used**
  (novelMarkerInner ~:873, seen on Trigger and Main Action for HEROES).
  DISPOSITION: this is the documented novel-abilities lifecycle (opening a
  drawer ACKNOWLEDGES its pips; closing retires them - see
  DrawSteelActionBar/CLAUDE.md "Novel abilities"), i.e. probably NOT caused by
  this project. Verify against the pre-project commit (0e67503b^) before
  touching it; if it reproduces there, file separately, do not fix here.
- **F2-7 REQUEST (accepted, aligns with Decision 4/50): grey ALL of a
  monster's chips once it has acted this round**, not just the footer, so
  "do not use these" is unmistakable. Slice (d) dims the column via an
  `acted` class - check it actually applies to the chips visually; if the dim
  is too subtle, strengthen it (keep chips discoverable per Decision 4).
- **F2-8 REQUEST (new, good): an "x" on each column to DISMISS that monster**
  from the overview - removes the column AND deselects the token on the map.
  Use case: the Monarch has acted, or the Director has decided against a
  monster this turn; dismissing declutters and refocuses. DISPOSITION: accept
  for Phase 2; implement as a small close affordance on the footer bar
  (top-right of the column), calling into the selection (remove that token
  from `dmhub.selectedTokens`) - the existing selection poll then repopulates.
- **F2-9 REQUEST: show the creature's ROLE prominently** (controller / support /
  brute ...) so the Director can pick which column to read first. Slice (d)
  already prints the stat block role line ("Level 1 Horde Controller") in the
  footer, so this is a VISIBILITY problem: it is small and buried under the
  name. DISPOSITION: promote the role word - larger, first, or as a chip on
  the footer - and add the role's one-line play pattern on hover (Decision 15;
  role prose table still needs adding as data).
- **From the previous message (same session): (i) signature-first row order is
  reliable (categorization sort) but cross-column alignment is coincidental -
  make signature-slot alignment deliberate; (ii) "Get in Here!" is filed
  categorization="Signature Ability" IN THE DATA (its action type is correctly
  Maneuver) - a data/ fix on the Goblin Monarch, not a UI bug; (iii) ACTION
  TYPE must be visible on chips at a glance - "Maneuver" / "Free Maneuver" /
  "Free Action" as legible text (>= 12px, not an 8px tag; main action stays
  unmarked) AND main actions grouped above a hairline with maneuvers below,
  so "Monarch = one above + one below, Warrior = two above" reads structurally
  (this answers the "can this monster do two unique things this turn?"
  comparison, which is core to the activation decision).**

SUGGESTED ORDER FOR THE NEXT SESSION: F2-2 (regression) -> F2-1 (hero gate)
-> F2-4/F2-5 (footer copy/size/raw numbers) -> action-type visibility ->
F2-7 -> F2-8 -> F2-9/role prominence -> Get in Here! data fix. Then Phase 2.

**2026-08-18, F2-2 + F2-1 fixed (agent, live A5 game, launched fresh into
`LargeStoutExpedientBruxer` / Castle Andreas map; zero codex console errors).**
- **F2-2 FIXED - root cause was neither hypothesis.** The "unique" menu branch
  parks every ordinary pooled panel collapsed so it stays parented (the
  fa2053b7 rule). `ActionSubMenu` and the power-roll trigger submenu re-open
  themselves on their next `abilities` / `triggers` event, but
  `m_commonSignatureWrapper` - the plain vertical panel that stacks the
  Abilities and Signature Abilities submenus into one column - is not an
  ActionSubMenu and nothing ever set it back, so after the FIRST overview open
  every later single-token Main Action menu lost that whole column (only
  Common Abilities / Free Maneuvers etc. survived). That is exactly "the
  Monarch lost its signature abilities". Fix: the ordinary menu path now does
  `m_commonSignatureWrapper:SetClass("collapsed", false)` right after it
  repopulates the two submenus (~:4310). Slice (e)'s check (5) had passed only
  because it ran before any overview open in that reload.
  Live: monarch + 2 warriors -> Unique menu opened (5 chips) and closed ->
  Monarch alone -> Main Action = Signature Abilities (Handaxe melee, Handaxe
  ranged) + Common Abilities, 7 chips, screenshot confirmed.
  STANDING REGRESSION CHECK (add to every future slice): open a Unique menu,
  close it, select ONE monster, open Main Action - the Signature/Abilities
  column must be present.
- **F2-1 FIXED.** New file-local `IsOverviewCreatureToken(tok)` (~:116) =
  valid token with properties, `not tok.playerControlled`, and (pcall-guarded)
  `props:IsMonster() and not props:IsFollower() and not props:IsHeroSummon()`
  - the same "director monster" notion the Malice drawer uses. `InOverviewMode`
  requires it of EVERY selected token, so any hero, follower or hero summon in
  the selection falls back to the classic strip. Live: 2 heroes -> `trigger |
  action | maneuver | move`; Monarch + Polder Elementalist -> classic strip
  with malice; Monarch + Warrior 1 + Warrior 2 -> `trigger | unique | malice`.
- Harness notes for the future: reach the bar with
  `GameHud.instance.actionBarPanel:GetChildrenWithClassRecursive("actionBarDrawer")`
  and pick a drawer by `d.data.drawerType`; `FireEvent("press")` on it toggles
  its menu; the menu is the single `actionMenu` panel; count chips/headings
  only after walking the parent chain up to the menu with no `collapsed` /
  `hidden` ancestor. Setting `dmhub.selectedTokens` takes effect on the NEXT
  execute_lua call (the poll/refresh has to run), so set in one call and read
  in the next. On this Mac the app is the Steam depot binary
  `~/Library/Application Support/Steam/steamapps/common/Draw Steel Codex/Contents/MacOS/Codex --gameid <id>`
  (start_dmhub's Windows path does not exist); the bridge came up ~100 s later.

NEXT: F2-4/F2-5 (footer copy/size/raw numbers) -> action-type visibility ->
F2-7 -> F2-8 -> F2-9/role prominence -> Get in Here! data fix. Then Phase 2.

**2026-08-18, play observation (Ricky, live A5 game) - evidence for the F2-5(c)
threat estimate and Phase 1.5 condition icons.** The activation choice was
Goblin Runners vs Goblin Cursespitter, on the theory that whichever did not act
would die before its turn. Runners went; the Cursespitter's turn went unused.
The Tactician then Marked the Cursespitter, used Two Shot on the Runners AND the
Cursespitter, rolled a CRITICAL, spent the Mark benefit trigger (+4 damage to a
marked target) - Cursespitter dead - then Protective Attack on the Runner squad,
tier 2 was enough - squad dead. Theory confirmed: the creature that did not act
first never got to act.
Design consequences:
- The funnel's core question ("who goes first, because the other one dies") is
  real in play, not just in the brief.
- Neither death came from ONE ability's tier-2 damage: it was crit + a
  triggered-action rider stacked in one hero turn, then a second ability. A
  threat estimate keyed to "one hero's tier-2 hit" would have said SAFE for
  both. It must reason about a hero's WHOLE turn (main action + triggered
  action + follow-up) and present itself as a risk band with reasons, never a
  yes/no verdict (crits are luck).
- The cheapest high-value signal was already on the board: "Marked by the
  Tactician" on the Cursespitter - deterministic, no damage model, and it says
  who the heroes intend to kill. Promote Phase 1.5 condition icons (marks,
  ongoing effects) toward the front of the queue; a mark should read as a
  threat flag on the column, not a generic status pip.
- Raw stamina numbers (F2-5b) would have made the Runner squad's "finishable
  by one tier-2 hit" obvious; "High" hides it. Role prominence (F2-9) frames
  the Controller-vs-minions trade-off faster.

**2026-08-18, third user field test (Ricky, live play, real turn).**

- **VERIFIED THE POSITIVE CLAIM PATH (the one Phase 1 could not exercise):**
  with several monsters selected, clicking Spear Charge on a Warrior panned to
  it and began targeting WITHOUT claiming; confirming the cast on the Tactician
  CLAIMED the Warrior's turn at that moment; the columns then read "Turn taken
  - acting now". Afterwards an off-turn Runner ability cast did NOT change
  initiative. Decision 47 + 24 hold in real play. Phase 1 is now fully
  field-verified end to end.
- **F3-1 BUG (minor): no visible pulse on chip-press locate.** Code calls
  `OverviewLocate` -> `dmhub.CenterOnToken(..., {smooth=true})` then
  `PulseHighlightToken` per member (DrawSteelActionBar.lua ~3098, ~3700), so
  the pulse IS requested; the user saw the pan but no pulse. Footer-click
  pulse (no simultaneous pan) was seen in the earlier test. Hypotheses: the
  smooth camera tween swallows/obscures the short engine pulse, or
  PulseHighlightToken is faint on an already-selected token. DISPOSITION:
  fire the pulse after the pan completes (delay ~0.3s via dmhub.Schedule,
  guarded by mod.unloaded) or switch locate to the director-local TokenHud
  pulse pattern (DrawSteelTokenHud.lua:19-60) which can also carry role colour
  and a longer hold - that pattern was already the planned fallback for pulse
  locality. Test both footer and chip paths.
- **F3-2 COPY/STATE (accept): once a turn is taken, the take-turn buttons
  should DISAPPEAR, not show "Turn taken - acting now".** They are no longer
  options; a disabled button with a caption is noise. DISPOSITION: hide the
  button (collapse) when the gate reason is "Turn taken - acting now" or
  "Already acted this round"; keep the state visible in the footer signal
  line instead ("acting now" / "Acted"). Keep the disabled-with-reason button
  ONLY for the transient cases where the Director might want to know WHY they
  cannot act yet ("It's the heroes' turn - browse only", "Another creature's
  turn is in progress").
- Game state: the user ended the Assassins' turn and played on; no cleanup
  outstanding. User does NOT want a push yet.

**2026-08-19, F3-1 + F3-2 fixed (agent, live A5 game, round 3, ChoosingTurn;
zero codex console errors after reload; standing regression check passed:
Unique menu open/close -> Monarch alone -> Main Action = Signature Abilities
+ Common Abilities, 9 chips, 0 take-turn buttons).**
- **F3-1 FIXED - both hypotheses were true, measured live.**
  `dmhub.CenterOnToken{smooth=true}` is a FIXED ~0.5 s eased tween regardless
  of distance (sampled `dmhub.cameraPosition` every 0.05-0.1 s: 79-unit and
  27-unit pans both settle at ~0.5 s) and its `callback` fires SYNCHRONOUSLY
  (useless for sequencing). `PulseHighlightToken` is a brief white flash, so it
  (a) ran entirely inside the pan and (b) on a selected token is the same
  colour as the selection ring anyway. Fix in `OverviewLocate`
  (DrawSteelActionBar.lua ~3096): the pulse is deferred by
  `OVERVIEW_LOCATE_PAN_TIME` = 0.55 s (immediate when the camera is already on
  the token, |cam - loc| < 0.5), and `OverviewPulseTokens` pairs the engine
  pulse with a sustained coloured ring: `token.bottomsheet:SetClassTree
  ("locate", true)` held for `OVERVIEW_LOCATE_HOLD` = 1.4 s, per-charid
  generation counter so a re-locate restarts the hold instead of being cut
  short. The ring itself is a new generic style on the token bottomsheet in
  `DMHub Token UI/TokenUI.lua` (~2950): selector `locate`, priority 5, 8px
  `#f2b632` border, 0.15 s transition - deliberately not white and thicker
  than select/focus so it reads on an already-selected token. Live: footer
  press on the Monarch -> camera settled at 0.52 s, `locate` class on at 0.62 s,
  still on at 1.58 s; screenshot shows a gold ring on the Monarch beside the
  Stinker's white selection ring. Chip-press locate and the owner-prompt
  `choose` path go through the same `OverviewLocate`. The prompt-row HOVER
  and `armOwnerPrompt` still use the bare engine pulse (no pan there; revisit
  with X4 / on-map pick in Phase 2 if it proves too faint).
- **F3-2 FIXED.** `OverviewClaimGate` (~:195) now returns a third value
  `settled`: true for "No initiative running", "Not in the initiative order",
  "Turn taken - acting now", "Already acted this round" (taking the turn is no
  longer an OPTION this round); false for the transient blocks ("Another
  creature's turn is in progress", "It's the heroes' turn - browse only",
  "Cannot take turns right now"). `LayoutTakeTurn` (~:3548) collapses the
  button AND the reason label when `not ok and settled` - the footer signal
  line already says "acting now" / "acted" - and keeps the greyed button +
  inline reason only for the transient cases. Multi-candidate columns count
  as settled only if EVERY fresh candidate's gate is settled. Also fixed in
  passing: with exactly ONE fresh candidate the button now keys on THAT
  member's entry rather than the representative's (the representative can be
  the member acting now, which would have hidden the button for a column that
  still had a claimable member); `armOwnerPrompt` explicitly un-collapses the
  button when it turns into "Cancel". Live (HasHadTurn monkeypatched locally
  for the Stinker's entry, no data touched, restored after): Stinker column =
  "Stamina: High - acted", button collapsed, reason collapsed; Monarch /
  Assassin / Runner buttons enabled. ChoosingTurn patched false: all four
  buttons visible, disabled, reason "Another creature's turn is in progress".
  OPEN for Ricky: out of combat the button is now hidden too (was: greyed
  "No initiative running" under every column) - say so if the greyed hint was
  wanted there.
- Harness note: `GetChildrenWithClassRecursive("overviewFooterLine")` returns
  the ROLE label first and the signal label second; read both and skip the
  collapsed one.

NEXT: F2-4/F2-5 (footer copy/size/raw numbers) -> action-type visibility ->
F2-7 (grey acted chips - the Stinker "acted" column above shows its chips at
full brightness) -> F2-8 -> F2-9/role prominence -> Get in Here! data fix.
Then Phase 2.

**2026-08-19 (later), F2-4 + F2-5 + F2-3 copy done (agent, live A5 game;
standing regression check passed again: Monarch alone -> Signature Abilities +
Common Abilities, 9 chips, 0 buttons; only console errors are the pre-existing
reload-time `DocumentSystem.lua:7024 GameHud.instance` boolean NRE, not ours).**
- **F2-5 DONE.** `OverviewStaminaBand` -> `OverviewStaminaText` (~:2998):
  raw "13/15" (+ " +T" temp stamina when any), via CurrentHitpoints /
  MaxHitpoints / TemporaryHitpoints; minion squads still read the squad pool.
  `OverviewActedText` (~:3228): "Not yet acted" / "Acted" / "Acting now".
  Header line for a single actor = "80/80 - Not yet acted" (the "Stamina "
  prefix was tried and pushed the state off the 151px text column into the
  ellipsis - the bare current/max readout is what every token nameplate in
  the app shows, so it was dropped); multi-member header = "k of N not yet
  acted" / "All acted", and SILENT when no member has a queue entry (before:
  "2 of 2 not yet acted" about Snipers who were not in the order at all -
  `signals.knownCount` added, `freshCount` now counts only `acted == false`).
- **F2-4 DONE.** Every footer text is now >= 12px (name 13 bold, lines/rows/
  button/reason 12; button 24 tall); name/lines/rows use
  `textOverflow = "ellipsis"`. Mini-rows are TWO lines: name (ellipsized) +
  "18/18 - Not yet acted" (`overviewFooterRowText` vertical panel with
  `overviewFooterRowLabel` + new `overviewFooterRowSignal`; row 30 tall,
  portrait 24). Live: "Goblin Sniper Squad 5 (6)" / "18/18" rows fit inside
  the border.
- **LAYOUT TRAP FOUND + FIXED (record for anyone touching the footer): the
  `abilitySubMenu` style has `flow = vertical, wrap = true` (legacy long menus
  overflow into a second column). Once the footer's auto height passed ~70px
  the engine's single-pass auto-height/wrap resolution misfired and the footer
  of EVERY overview column - even a one-chip Runner column - wrapped to the
  top-RIGHT of its column (screenshot: footers floating beside/above the
  chips). Forcing `selfStyle.height = 70` un-wrapped them; so does
  `selfStyle.wrap = false` with auto height. Fix: `ActionSubMenu`'s
  `setCasterToken` sets `element.selfStyle.wrap = false` while a column is
  bound and `true` when parked (~:3937). An overview kit never needs to wrap.
  The slice-(d) footer had only been safe by ~12px of slack.**
- **F2-3 copy DONE:** `OverviewTakeTurnText(column, memberCount, sharedEntry)`
  -> "Take the Goblin Assassins' turn" when every member TOKEN of the column
  resolves to one initiative id (`OverviewPluralPossessive`: s/x/z/ch/sh ->
  es', consonant+y -> ies', else s'). Counted over every token, not the
  representatives: in A5 the first "Squad 4" Sniper carries Squad 5's
  grouping id, so representatives alone said "shared" for a column that
  spans two entries ("Take a Goblin Sniper's turn" is correct there).
- F3-2 REFINEMENT: "Not in the initiative order" moved from settled (hidden)
  to transient (greyed button + reason). Reinforcements parked in "Ready
  Monsters" are a real in-play state (the 12 A5 Snipers) and the Director can
  change it by dragging them into the order - the greyed reason is the hint.
  Out-of-combat ("No initiative running") stays hidden.
- Visual check of this state (16 tokens, 5 columns): Monarch "80/80 - Not yet
  acted", Stinker "9/10", Assassin "14/15", Runner "4/4", Sniper x12 with two
  rows + greyed "Take a Goblin Sniper's turn" / "Not in the initiative order".

NEXT: action-type text on chips + main/maneuver hairline -> F2-7 grey ALL
chips when acted (verify the `acted` class actually reaches the chips) ->
F2-8 dismiss-x per column -> F2-9 role prominence -> Get in Here! data fix.
Then Phase 2.

**2026-08-19 (later still), ACTION TYPE ON CHIPS + HAIRLINE GROUPING done
(agent, live A5; classic Main Action / Maneuver / Malice menus re-checked on a
single Monarch: Signature + Common / Signature + Common / Malice Abilities, no
overview labels or dividers leak into them; only console errors are the same
pre-existing DocumentSystem.lua:7024 reload NRE).**
- `OverviewActionType(ability)` (~:235) -> group, label from
  `actionResourceId`: main action = group 0, "" (unmarked); maneuver /
  free maneuver / "none" = group 1, "Maneuver" / "Free Maneuver" / "Free
  Action"; any other resource = group 1 with the resource's own name.
- `AbilityHeading` gained a pooled `overviewActionType` label under the
  keywords line (12px bold gold, `OVERVIEW_FOOTER_RULES`), populated ONLY
  when `args.overviewPress` is set (i.e. an overview column chip) - ordinary
  menus never show it, the drawer already names the action.
- `ActionSubMenu` now keeps its chips in a separate `m_chips` pool plus a
  pooled `m_divider` (`overviewActionDivider`: 2px gold hairline, 181 wide)
  and REBUILDS `m_children` on every populate: chips (spares collapsed at the
  end), divider at its slot (parked collapsed before the tail when unused),
  heading, footer; re-assigns `element.children` only when the order
  changed. Every pooled panel stays in the list (fa2053b7 rule).
- Overview sort (only when `m_column`/`m_casterToken` are set): group 0
  first, then Signature Ability first, then cost, then name. Ordinary menus
  keep the old cost/name sort byte-for-byte. Divider shows only when the
  column has chips on both sides.
- Live: Monarch = Handaxe, Handaxe | hairline | Get in Here! [Maneuver];
  Stinker = Toxic Winds | hairline | Swamp Gas [Maneuver]; Assassin = Sword
  Stab, Shadow Chains (no divider); Runner = Club Charge. Screenshot: the
  "one above + one below" structure reads at a glance. Maneuver chips are a
  line taller than main-action chips (3 text lines) - cross-column row
  alignment was never promised (field note (i)).

NEXT: F2-7 grey ALL chips when acted (verify the `acted` class reaches the
chips - the F3-2 test screenshot showed an "acted" Stinker column with chips
at full brightness) -> F2-8 dismiss-x per column -> F2-9 role prominence ->
Get in Here! data fix (categorization "Signature Ability" on a maneuver in
data/). Then Phase 2.

**2026-08-19, F2-7 done (agent, live A5, HasHadTurn monkeypatched locally for
the Stinker entry, restored after).** The slice-(d) rule
`{abilityHeading, parent:acted} opacity 0.5` DID match (column had the class)
but was invisible in play - the chips are dark translucent panels on a dark
menu, so halving their opacity barely moves the text. Replaced by an "acted"
CLASS TREE on every chip of an all-acted column (`m_chips[i]:SetClassTree
("acted", overview and allActed)` at populate, always cleared for ordinary
menus - same mechanism as "expended") with explicit rules in
`OVERVIEW_FOOTER_RULES`: `{abilityHeading, acted}` opacity 0.55 + dark border,
`{abilityTitle|abilityInfoLabel|overviewActionType, acted}` color #8a8a8a,
`{abilityIconPanel, acted}` saturation 0 / opacity 0.6. Live: Stinker column
(acted) = grey Toxic Winds / Swamp Gas with desaturated icons beside bright
Monarch / Assassin chips; chips remain hoverable/pressable (Decision 4).

NEXT: F2-8 dismiss-x per column -> F2-9 role prominence -> Get in Here! data
fix. Then Phase 2.

**2026-08-19, F2-8 done (agent, live A5; regression check passed: Monarch
alone -> Signature + Common, 9 chips, 0 buttons, 0 dismiss x).**
- Footer gained a floating 14px `overviewDismiss` "x" (ui-icons/close.png)
  at its top-right (name label now `100%-16` wide to leave room); press =
  `dmhub.selectedTokens` minus the column's tokens. Deliberately a plain panel,
  not `gui.Button{kind="closeButton"}`, whose kind binds Escape (Esc must keep
  closing the menu). Tooltip "Remove from the overview (deselects on the map)".
- The root selection poll now fires `refreshOverview` after `refresh`, so an
  OPEN Unique Abilities menu follows the selection live (dismiss, shift-click
  on the map) instead of going stale; no-op unless that menu is up.
- Root `refresh` fires `closemenu` with reason "primary" when only the primary
  token changed; the unique drawer and the actionMenu ignore that reason while
  overview mode persists (the menu's columns come from the whole selection, the
  primary is irrelevant to it) - only the owner prompts are disarmed, since
  the columns repopulate. Every other menu closes on a primary change exactly
  as before. Live: 4 columns -> dismiss Stinker -> 3 columns, menu open ->
  dismiss Monarch (the PRIMARY) -> primary became the Assassin, menu still
  open with 2 columns, unique drawer active -> dismiss Assassin -> 1 token,
  overview mode ends, menu closed, classic strip.

NEXT: F2-9 role prominence -> Get in Here! data fix. Then Phase 2.

**2026-08-19, F2-9 done (agent, live A5; regression check passed).**
- `OverviewRoleLine` -> `OverviewRoleInfo(tok)` (~:3215) returning `plain`
  (the stat block's "Level 1 Horde Controller"), `line` (rich text with the
  ROLE WORD first, bold, gold `#C9A86A`: "Controller  Level 1 Horde"; a
  Leader/Solo has only the organization so that leads: "Leader  Level 1";
  minions read "Harrier  Level 1 Minion") and `prose` (hover text). Uses
  `monster:Role()` / `monster:Organization()`.
- `OVERVIEW_ROLE_PROSE` (~:3193): one-line PLAY PATTERN per role (ambusher,
  artillery, brute, controller, defender, harrier, hexer, mount, skirmisher,
  support) and per organization (leader, solo, minion, horde, platoon,
  elite) - paraphrased guidance, not book text. Hover on the footer role
  line = `plain` + the role line + the organization line (Decision 15's
  "role description on hover"). The table lives in Lua for now; Ricky's
  brief wanted it as data eventually - move to data/ when the copy pass
  (X13) settles the wording.
- Live: Monarch "Leader  Level 1", Stinker "Controller  Level 1 Horde",
  Runner "Harrier  Level 1 Minion"; hover on the Monarch's role line showed
  "Level 1 Leader / Leader: Commands the battle with villain actions...".

**2026-08-19, fourth user field test (Ricky, live): "- Not yet acted" on the
footer line is redundant.** Not having acted is the default and needs no
label; only the acted state must be unmissable. FIXED same session:
`OverviewActedText` returns nil for not-yet-acted (footer line reads just
"80/80"), red (#E06464, rich-text colour) "Turn already taken" once acted - on
top of the F2-7 greyed chips - and plain "Acting now" mid-turn; the
multi-member header is silent until someone has acted, then red "2 of 3
already acted" / "Turn already taken". Design rule recorded for the copy pass
(X13): never label the default state; reserve text + colour for the
exception the Director must not miss.

NEXT: Get in Here! data fix (Goblin Monarch maneuver filed as
categorization "Signature Ability" in data/). Then Phase 2 - and F2-5(c) /
the 2026-08-18 play observation say the first Phase 2 items should be the
Marked/condition threat flags and the whole-turn threat estimate, not the
lenses.

**2026-08-19, fifth user field test (Ricky, live) - all items fixed same
session, live-verified; zero console errors; regression check passed.**
- **"Select All"**: the Director's monster-side initiative label now reads
  "Select All" (creation AND the runtime rewrite at MCDMInitiativeBar ~:4822
  that was clobbering the first fix); players/hero side keep "Ready Heroes" /
  "Ready Monsters".
- **Select-all scope**: `SelectReadyMonsters` now requires the monster's
  entry to be IN `q.entries` while a queue runs - reinforcements parked in
  "Ready Monsters" (the 12 A5 Snipers) are no longer selected. Live: 6
  selected, Snipers excluded.
- **Squad locate**: `OverviewLocate` on a multi-token member now pans to the
  member nearest the GROUP CENTROID, not tokens[1]. Could not reproduce the
  reported wrong-squad pan today (both squads geographically coherent, press
  on "Squad 4 (6)" landed at (12,-21) = squad 4) - the centroid guard also
  covers a stray mis-squadded token; watch for recurrence.
- **Readability**: footer fonts +1 across the board (name 14 bold, all lines
  and rows 13, take-turn 13/26 tall, rows 32 tall).
- **Threat de-duplication** (Ricky: icon + red text was saying it twice):
  the status STRIP now shows only statuses that are NOT threat flags;
  hero-applied effects appear exactly once, as the red text on the signal
  line ("14/15 - Judged"), with the caster in the tooltip. My call and the
  reasoning: text is the clearer single channel (the icon needed a legend;
  the word does not), and the strip stays for statuses that have no text
  mirror.
- **Zero reach pops**: "No hero in reach" / "0 in reach" now amber
  (#E0A050) bold - the "rule this monster out this turn" cue, mirroring red
  "Turn already taken" (the signal vocabulary is now: silent = fine, amber =
  cannot contribute, red = spent/marked).
- **Community action-type colours** (Ricky): "Maneuver"/"Free Maneuver" on
  chips render BLUE (#5B9BD5), "Free Action" grey; the word remains the
  colour-blind channel (X12), colour is reinforcement. Main-action red is NOT
  applied to titles (every chip title turning red would drown the palette);
  revisit in the copy pass if wanted.
- **Lens match emphasis** (sixth-test note: Toxic Winds vs Swamp Gas did not
  separate enough): onLens chips now get 2.5px gold border + brightness
  1.15; offLens keeps opacity .45 (X3 floor) + saturation .5.
- **LENS BAR REDESIGNED** (Ricky rejected the boxy fixed-width bar + arrows;
  wanted the flat icon-rail aesthetic): now ONE quiet row of six text tabs
  ("All 8 | Damage 6 | ... ") on a translucent black rounded strip, active
  tab gold + 2px underline, zero-count tabs dimmed but pressable, hover
  brightens. NO arrows, NO dropdown - both are GONE: with real mouse clicks
  the arrow press closed the menu and the ContextMenu died instantly with
  it (never reproducible with synthetic FireEvent presses - suspected
  click-through/dim-out interaction; eliminated by construction instead of
  diagnosed). Tabs are plain panels with bgimage (the chips' own proven
  construction). Columns center under the bar (`m_containerPanel` halign).
  SIZING TRAP for the future: a width="100%" child (the underline) inside a
  width="auto" tab inflated every tab to 219px and the row to the full menu
  width - tabs are fixed 96px, underline "100%-8".
- **Copy**: "Everyone can:" -> "Common <lens> abilities:" ("Common forced
  move abilities: Knockback").
- Cross-session note: the working tree gained MORE unrelated hunks from the
  other session mid-run (ShowMovementDiagram textOverride + summon placement
  wording ~:825/:9273, on top of the chooser caster-push ~:8766) - keep
  committing with add -p only.
- STILL OPEN from this test: portraits of the in-reach heroes on the footer
  (Ricky floated it, flagged the density risk himself - design it with P2-e
  rather than bolt on); P2-e threat estimate awaiting his answers to the
  three questions in the P2-e row; sub-filter chips; hotkeys (X4).

**2026-08-19, thirteenth user field test (Ricky, "really like how the damage
icon is working") - multi-target and summon chip badges. Live-verified.**
- The chip badge is now a BADGE ROW (floating right edge, presses bubble
  through): [green summon] [twin persons] [red surge]. Icons from the
  "Provided By MCDM" image library - the person silhouette is asset
  e2345ee0-e8e3-412c-bebc-d0dddbafad93 (identified by rendering the whole
  library in-app; Ricky's screenshot-inspector had grabbed the pencil
  edit-button instead).
- **Multi-target badge**: TWO overlapped person silhouettes when
  numTargets > 1 or targetType == "all"; RED (#E06464) when the ability
  does damage, off-white otherwise. Tooltip "Targets more than one
  creature".
- **Summon badge**: person + green "+" (#7AC77A - friendly, not
  adversarial) when any behavior typeName contains "Summon". Tooltip
  "Brings a new creature into the encounter". PRECEDENCE: a summon never
  also wears the multi badge (Get in Here! targets 2 empty squares but
  reads as summon only).
- Facets gained `multiTarget` and `summon`; badges ride every lens but
  never on a dimmed off-lens chip (the DMG surge keeps its stricter
  All/Damage gating from field test 10).
- Live: Handaxe x2 = red twins + surge; Get in Here! = green person+;
  Shadow Chains = red twins; area abilities (Toxic Winds / Swamp Gas)
  correctly carry nothing (the green grid icon already says area).
- FOLLOW-UP same session (fourteenth report): the center-right float
  collided with the malice cost diamond (Get in Here!, Shadow Chains) and
  two badges grazed the "Weapon" keyword. Badge row moved to the chip's
  TOP-RIGHT corner (valign top, tmargin 3) - the title row's right side is
  reliably empty for monster kit names; the diamond owns the vertical
  center, the keywords own the bottom, the novel pip owns the top-left.
  CHIP CORNER MAP for anyone adding decorations: top-left = novel pip,
  top-right = badge row, center-right = cost diamond, bottom span =
  keywords/action type/condition glyphs. Second nudge (Ricky): on a SHORT
  chip (2 lines, e.g. Get in Here!) the centered diamond rides high enough
  to reach the top corner - badge row rmargin is 18 because the diamond
  (30px, hmargin -15) intrudes exactly 15px into the chip. Not re-verified
  on screen: Ricky restarted into a different live game (Gorek/Targon
  demo) mid-fix; geometry is deterministic. Note: overview confirmed
  correctly ABSENT for a mixed monster+hero selection in that game (F2-1
  holds outside A5).

**2026-08-19, fifteenth report (Ricky, Rival monsters - first full test
outside the goblin bed) - long titles vs badges, SOLVED STRUCTURALLY.**
Rival kit names ("Dual Targeting Shot", "The Writhing Green", "Thunder of
Heavens") reach the chip's top-right corner, so floating placement can never
guarantee no overlap. Fix: the TITLE reserves the badge zone - AbilityHeading
sets a "badges1"/"badges2" class tree from the visible badge count and
`{abilityTitle, badgesN}` rules (priority 5) narrow the title to 100%-46 /
100%-68, wrapping it a line early (commit c4743b7c). Verified live in Ricky's
Rival game: all long titles wrap cleanly, badges own the corner, and the
overview's whole signal stack works on non-goblin content (Fury amber "Can't
reach any hero", Tactician gold "High damage dealer").

**2026-08-19, generality check (Ricky: "this has to work for all monsters").**
The chip layout is now INVARIANT-based, not tuned per monster: every
decoration owns a reserved zone (top-left novel pip, top-right badge row,
center-right cost diamond at a fixed 15px intrusion, bottom rows for
keywords/action type/condition glyphs/lens key), and the single
variable-length element - the title - yields by MEASURED badge count
(badges1/badges2 class tree), never by hand-tuned offsets. Stress-tested
against the whole bestiary: the longest ability name in data/monsters
("The Iron Saint Does Not Recognize Retreat", 42 chars; only ~4 abilities
exceed 35) was forced onto a live chip with BOTH badges - it wrapped to five
lines, the chip grew, nothing overlapped. No per-monster positioning exists
anywhere in the overview.

**2026-08-19, sixteenth report (Ricky, live Rival game): "no Select All
button under the initiative".** Cause: the reused initiative-bar label only
shows while ITS side is choosing (pre-existing rule), so during a hero's
turn the Director's "Select All" was hidden - precisely the prep moment.
Fix (MCDMInitiativeBar SizeBar): the Director's monster-side unmoved label
shows whenever unmovedCount > 0, regardless of whose turn it is; hero side
and player clients keep the old gate. Safe because browsing the overview
off-turn never claims (Decisions 24/47). Live: heroes' turn, round 4 -
"Select All" visible under the Rival cards.

**2026-08-19, seventeenth report (Ricky, Rival game): Select All + Unique
Abilities threw `bad argument #1 to 'gsub' (string expected, got
function)` in OverviewStatusName.** A registered token-HUD status icon may
carry `hoverText` as a FUNCTION(creature) computed live on hover - the
wounded/Winded icon in DrawSteelTokenHud does - and the Rival Fury was
winded. `OverviewStatusEntries` now resolves it once via
`OverviewStatusHoverText(icon, tok)` (pcall the function with the
creature; anything non-string -> nil) before naming/tooltips. Live: Fury
shows Mark + Winded glyphs, Conduit Weakened + Bleeding, no error. Note for
anyone reading TokenUI.CalculateStatusIcons output: hoverText is string OR
function.

**2026-08-19, eighteenth field test (Ricky, D3 Delian Tomb playtest) - THE
RISK MODEL SIMPLIFIED TO ONE STATE. Live-verified both ways.**
Playtest verdict on the two-tier model: "At Risk / Consider using turn soon"
on every creature was NON-INFORMATIVE (a monster in combat is always at
risk), and the Skeleton-red vs Zombie-amber split was invisible arithmetic
(10 vs 20 stamina against burst+4). Redesign, per Ricky:
- **ONE state: "Near Death" (red)** - replaces both "High Death Risk" and
  the green guidance lines ("Use turn/squad before they die" and "Consider
  using turn soon" are GONE; amber tier deleted everywhere incl. row tags).
- **Criteria (simple, legible - accepted trade-off recorded: combos/crits/
  heroics can beat it)**: an UNSPENT hero within striking range whose
  SIGNATURE ability tier-2 damage >= current stamina. Spent heroes excluded
  entirely (they cannot act before the Director's next turn; the x0.5
  Strike-Now weighting is gone). Hero profiles gained sigBurst/sigForced
  (fallback to best-any when no signature parses).
- **Cheap forced-movement flag (no wall physics)**: signature misses but
  signature + its push distance covers the stamina -> still Near Death with
  bullet "A push could finish it". Full collision geometry deliberately NOT
  built (hero picks push direction after moving; map raycasts per pair too
  heavy) - revisit only if playtests demand.
- **Bullets = plain reasons** ("Low Stamina", "Mark by High Elf Tactician");
  killer names + arithmetic live in the TOOLTIP only ("Tactician's
  signature hits ~8 vs 7 Stamina...").
- **"N heroes within striking range" bullet DELETED; inverted to a green
  exception line** "Outside reach of heroes" (hover "Relatively safe...")
  shown only when NO UNSPENT hero has the monster in striking range -
  Ricky overruled counting all heroes: the line informs THIS turn.
  RECORDED EXCEPTION for later: on the Director's last turn of a round,
  next round's refreshed heroes are the real threat set.
- **DMG badge rules 1+2 refined**: rule 1 tooltip "Highest damage amongst
  selected monsters"; rule 2 tooltip "Highest damage amongst near-death
  monsters - use it before it's lost", and rule 2 (badge AND footer bullet)
  fires ONLY when >= 2 creatures are Near Death AND the among-the-dying best
  differs from the overall best (rule2Active in PopulateUniqueColumns).
- Live D3 verification: full-health round-1 board shows NO risk boxes (party
  best signature tier-2 = 8 vs 10+ stamina - the old model called Skeletons
  red here); damaging a Skeleton to 7 flipped its column to "Near Death -
  Low Stamina, Mark by High Elf Tactician, High damage dealer" and reverted
  cleanly.

**RECORDED IDEA (Ricky, not for now): skull-scale risk indicator** - replace
the bullet case with "Death Risk" + 1 yellow / 2 amber / 3 red skulls, WHY in
the hover only. Hodent-lens assessment (given in chat): skull COUNT is a
good encoding (1-3 subitizes at a glance; count+colour double-coding is
colour-blind-safe, matching the community-colour concern), but a 3-tier
scale RESURRECTS the just-deleted uninformative middle tier, and moving the
WHY into hover raises interaction cost for the core decision loop (the
current design's bullets answer "why" ambiently). If ever revisited: two
states max (present/absent), or skulls encoding something crisper than
graded risk.

**2026-08-19, nineteenth field test (Ricky killed three "safe" Skeletons in
three hero turns) - NEAR DEATH v2: best affordable hit, engine-resolved.**
The signature-only rule failed live for three stacked reasons, each found by
walking Ricky's kills: (1) I had mislabelled Viscous Fire / Your Allies
Cannot Save You as heroics - both are SIGNATURES (confirmed in data); (2)
the raw-text damage parser DROPPED "+R"/"+A" characteristic bonuses (read 5
from "5 + R fire damage"); (3) surges in hand and affordable heroics were
ignored. v2 model (commit below):
- Damage numbers come from the ENGINE's caster-resolved tier text
  (`ActivatedAbilityDrawSteelCommandBehavior.DisplayRuleTextForCreature`) -
  characteristic and text bonuses included; never parse raw tiers for hero
  threat again.
- Best AFFORDABLE ability: signatures/commons always; heroics when cost <=
  heroic resource held + 2 (assumed start-of-turn gain, tunable - Ricky's
  Tactician-focus forecast).
- Plus held surges: min(2, surges) x HighestCharacteristic().
- Push flag now rides the best pushing ability (bestPush = resolved + push
  distance).
- Tooltip names the ability and terms: "Shadow's I Work Better Alone hits
  ~9 +4 from surges vs 10 Stamina."
- ACCEPTED remaining gaps (recorded): roll-time modifiers (Elementalist
  fire specialization +2 - confirmed live as the source of Ricky's 9 vs the
  sheet's 7), trait immunities (ARISE saved a skeleton from a knockback
  kill), crit/tier-3 upside.
Live D3 verification with real pools: Shadow 9+4=13, Elementalist Flesh-a-
Crucible 10 (3 essence held), Censor Arrest 11 -> Skeletons (10) NEAR DEATH,
Zombies (20) quiet, Ghouls (15) quiet. Matches the table reality that
motivated the change.

**2026-08-24, twentieth report (Ricky): the Near Death tooltip was "far too
technical".** COPY RULE recorded for every overview tooltip: say the
CONCLUSION, never the homework. The tooltip is now one sentence - "A ready
hero nearby could kill this with a single ability." / "...by pushing it into
something." (ability names, arithmetic and methodology all removed); the
damage-dealer tooltips likewise de-jargoned ("Hits hardest of everyone
selected." / "Hits hardest of the dying - use it before it is lost.").

**2026-08-24, twenty-first report (Ricky) - tooltip copy principles locked:**
minimalist information only, NO imperatives (the Director decides, the UI
never instructs) and no dash-joined explainer clauses. Applied: footer
damage tooltips are now "Highest damage of all selected monsters" /
"Highest damage of selected monsters near death"; the chip DMG badge
tooltips aligned to the same two strings (their old copy had the same
dash+imperative pattern). These principles extend the conclusion-not-
homework rule and govern the P2-f copy pass.

**2026-08-24, twenty-second report (Ricky, D3 live) - skulls, maneuver
alignment, nested-rule conditions, Select All double-click (commit
0090fef8). All five items live-verified.**
- **Headline skull**: the villain-action skull from the "Provided By MCDM"
  library (asset e31d918b-16a8-45bb-8c03-be039e0d5236, tinted #E06464,
  16px) sits left of the "Near Death" headline via a new riskRow
  (riskLabel width "100%-19"). NOTE for the next session: e31d918b is the
  skull-with-"!" variant; the plain skull-crossbones is ebc8b529 - swap is
  a one-line change if Ricky prefers it after seeing it live.
- **Row skulls replace row text**: near-death member rows carry a small
  13px floating-right skull on the SAME LINE as the name; the per-row
  "near death" text tag is gone (chip shrink was the goal). Verified: all
  three full-health Skeletons wear it (correct - Shadow's 13 covers their
  10), Zombies/Ghouls clean.
- **Maneuver chips align on the vertical axis across columns** (Ricky:
  max one maneuver per monster, alignment aids comparison). Mechanism:
  columns are bottom-anchored, so equal footer heights align everything
  above - PopulateUniqueColumns resets each overviewFooter minHeight to 0,
  then a TWO-PASS deferred measure (dmhub.Schedule 0.15s AND 0.5s, shared
  EqualizeFooters closure) applies the max renderedHeight to all visible
  footers. Two passes because a single early pass caught the footers
  MID-LAYOUT: one frame after populate all three measured ~100px, the max
  (100) was applied, and the footers then grew naturally past it -
  minHeight must be re-measured after layout settles. Verified live:
  288/191/230 -> all 304; Bone Spur / Zombie Dust / Leap on one band.
- **Conditions hiding in nested rules found**: Ghoul Leap showed no prone
  glyph because its "1 damage; prone" lives in a
  DrawSteelCommandBehavior.rule INSIDE an InvokeAbilityBehavior
  customAbility. OverviewAbilityFacets now scans behaviors recursively
  (scanBehaviors, depth < 3): reads each DrawSteelCommandBehavior's rule
  text and descends into InvokeAbilityBehavior:try_get("customAbility").
  Verified: Leap = Prone, Razor Claws = Bleeding.
- **Select All double-click opens the overview** (Ricky: "clicking it
  again will then open the unique abilities action bar menu"). New export
  DrawSteelActionBar.OpenUniqueMenu() presses the unique drawer when it is
  visible and inactive; MCDMInitiativeBar's Select All press snapshots the
  selection set, calls SelectReadyMonsters(), and when the set comes back
  unchanged and non-empty opens the menu. First click still only selects.
- Regression check rerun: single-monster selection keeps the classic strip
  (unique drawer collapsed - Decision 43 gate is #selected >= 2 in
  InOverviewMode, untouched by this slice).
- Harness notes: GameHud.instance has no SelectToken and map has no
  SelectTokens - `dmhub.selectedTokens = {tok}` remains the only scripted
  selection route. mcp screenshot_panel takes panel_name and cannot find
  "actionMenu"; use full screenshot + PIL crop.

**2026-08-24, twenty-third report (Ricky) - skull refinements + Zombie Dust
self-prone bug (commit ea58afb5). Live-verified.**
- **Plain crossbones**: skull asset swapped to ebc8b529-f450-4bee-9466-
  86374c26dc13 (Ricky did not want the "!" variant) on headline AND rows.
- **Row skull inline, not floating right**: it now sits BEFORE the member
  name (mirrors the headline's skull-then-text format), valign center on
  the name line (Ricky: the floating one rode slightly high), and hovering
  it shows "Near Death" (gui.Tooltip). Layout: rowNameLine horizontal
  wrapper {rowSkull, rowLabel}; the name label narrows to "100%-16" via a
  withSkull class so skull + ellipsized name never collide. The headline
  skull also answers hover with the risk tooltip now.
- **BUG from the recursive scanner (Ricky spotted a mystery third glyph +
  "+1" on Zombie Dust)**: the top-level DrawSteelCommandBehavior rule
  "prone" on Zombie Dust is a SELF-effect ("The zombie falls prone...")
  with applyto="caster". RULE for the facet scanner: skip any
  DrawSteelCommandBehavior whose applyto is "caster" - its rule text
  describes the caster, not the targets. (Ghoul Leap still works: there
  the INVOKE has applyto="caster" but the nested command behavior's
  applyto is nil = the nested ability's own targets.) Verified: Zombie
  Dust = Weakened, Dazed only.
- **Bone Spur chip taller than Zombie Dust/Leap** (Ricky asked if anything
  can be done): it is content-driven - Bone Spur carries a keyword line
  ("Area, Weapon") the others lack. Could be equalized with the same
  minHeight trick as the footers, at the cost of blank space inside the
  shorter chips; Ricky ruled "padding with blank space is not a winning
  move" - LEAVE AS IS.

**2026-08-24, twenty-fourth report (Ricky: skulls approved, "I want to ship
it") - headline alignment + rebuild guard (commit d89e05b7).**
- Headline skull was valign top/tmargin 1 and the text read as riding
  high; now valign center like the row skulls. (Committed while Ricky was
  at the campaign screen - eyeball on next game entry.)
- OpenUniqueMenu raised "unknown field actionBarPanel in type Hud" when
  called mid-rebuild (Hud instance exists, field unassigned; unset-field
  reads on game-typed instances RAISE). Now GameHud.instance:try_get
  ("actionBarPanel") + .valid check. try_get IS available on the Hud type
  (verified live).
- Next validation step chosen by Ricky: simulate the Fall of Blackbottom
  "To the Skies" encounter (6 unique statblocks) on the Delian Tomb map as
  the pre-ship stress test. All six exist in data/monsters (demon-muceron,
  demon-pitling, war-dog-neuronite, war-dog-subcommander, war-dog-
  tetherite, demon-chorogaunt); "lesser chorogaunt" is an
  adventure-specific variant not in data/ - the Book Two Chorogaunt
  stands in. Bonus: the subcommander carries "The Iron Saint Does Not
  Recognize Retreat", the longest ability name in the bestiary (the chip
  layout's stress-test case) - it will appear organically.

**2026-08-24, twenty-fifth field test (Ricky, FoBB "To the Skies" roster on
the Delian Tomb map) - the stress test paid for itself (commit a7110f03).**
- **Take-turn button is ALWAYS "Take turn"** (Ricky's call after "Take War
  Dog Subcommander's turn" broke the footer border). Root cause: the
  32-char fallback threshold kept 32-char strings that render ~224px in
  the 189px box (that name is exactly 32). The "Take <Name>'s turn"
  phrasing lives in the hover tooltip, which was already always set.
- **Button centered**: overviewTakeTurn had no halign, engine default is
  LEFT, and its "100%" width resolves to 189px inside the 205px padded
  footer - all 16px of slack sat on the right ("slightly to the left of
  centre" on every column). halign = center. LESSON for the footer: any
  child narrower than the content area needs an explicit halign.
- **Multi-target twins OFF Area abilities** (Ricky: area implies several
  targets; the green grid icon already says area; the twins are for
  STRIKES that hit more than one creature, e.g. Tongue Pull). Facet gate:
  HasKeyword("Area") clears multiTarget. Live: of the whole FoBB roster
  only Tongue Pull keeps the twins. PROBE TRAP recorded: checking
  badge:HasClass("collapsed") alone gave false positives - the badge ROW
  ancestor can be the collapsed one; walk ancestors to the chip.
- **Neuronite has THREE maneuvers** - contradicts the one-maneuver
  assumption behind the alignment discussion (recorded, no change: the
  bottom-anchored equal-footer mechanism aligns the maneuver BAND, extra
  maneuvers stack upward).
- **Pitlings not Near Death - answered, working as locked**: a minion
  squad is measured by its SHARED POOL (8 pitlings selected = two squads
  of 4, pool 12/12 each; single-minion stamina would flag every squad
  always - the uninformative default). And the only hero who could reach
  12+ (Shadow, 9 + 4 surge) had ALREADY ACTED (hasHadTurn true), and
  spent heroes are excluded by Ricky's own field-test-18 rule; the two
  unspent heroes (Tactician, Talent) held 0 surges and top out below 12.
- **Two "highest damage" badges - answered, working as designed**: the
  comparison stat is TIER-2 damage; Barbed Tongues (5/7/8) and Agonizing
  Harmony (4/7/10) tie at 7, and ties share the badge (field test 10
  decision). Tier-3 upside is an accepted gap (recorded field test 19).

**2026-08-24, twenty-sixth report (Ricky) - PDF role colours + positional
area twins (commit 0aab0573). Live-verified on the FoBB roster.**
- **Role line takes the PDF's visual language** (Ricky: each role has a
  unique colour in the stat block; matching it helps users correlate).
  The colour in the book is the stat block HEADER BANNER, sampled
  directly from Draw_Steel_Monsters_v1.01 with pdftotext -bbox +
  pdftoppm pixel sampling (the montage: scratchpad role-colors.png that
  session): Ambusher #FBE48C yellow, Artillery #D8D4E5 lavender, Brute
  #B3C9E6 blue, Controller #F8ADA9 salmon, Defender #D6D2B9 khaki,
  Harrier #EED0D2 rose, Hexer #E2E9D3 pale green, Mount #CEE6EF sky,
  Support #F7E2D1 peach. Role-less headers (Ajax "Level 11 Solo",
  Daybringer "Level 1 Leader") are NEUTRAL GREY in the book - #D7D9DA is
  the fallback. The whole "Minion Artillery" line wears the colour, role
  word stays bold. Palette on OVERVIEW.ROLE_COLORS (200-locals ceiling).
  SAMPLING TRAPS recorded: the subtitle TEXT in the PDF is black (the
  colour is the banner); two-column pages need the NEAREST "Level" word
  as anchor and a stop-at-white-gutter walk or the sampler reads the
  neighbouring stat block.
- **Area chips earn the twins positionally** (Ricky: a Neuronite can move
  into range and catch several heroes with The Voice - Taunt; wanted a
  symbol for "effectively usable against a group"). Rule:
  OverviewAreaCatch - envelope = speed + cast range + area size, a hero
  PAIR must fit the area diameter (2x size); Chebyshev, no walls/LoS
  (same approximation as the reach line, deliberately necessary-not-
  sufficient); burst-style abilities store size in range with no radius.
  Recomputed each populate so it follows token movement. ICON CHOICE:
  reused the twin silhouettes so the language stays "this will hit more
  than one hero" - static for strikes (Tongue Pull), positional for
  areas; distinct tooltips ("Targets more than one creature" / "Can
  catch more than one hero this turn"). Ricky's two candidate-symbol
  element grabs both came through as an unrelated "Talent" label, so the
  twins were my call - flagged for his sign-off, swap is one bgimage.

**2026-08-24, twenty-seventh field test (Ricky, mid-battle on the FoBB
roster) - THE MINION MODEL + guidance philosophy (commit 3635f142). All
live-verified in one frame (footer-zoom5).**
Ricky's design intent, recorded: an unprepared Director facing 6 statblock
choices needs NUDGES for turn one - (1) minions fall fast, spend them
early; (2) who hits hardest; (3) which area ability has a window right
now. He always runs minions first himself. Live proof mid-session: his
Tactician's Two Shot killed 3 of 4 Tetherites in one action.
- **"Squishy" (red + skull) on minion columns, ALWAYS** - unless the
  stronger signal (Near Death = a full pool wipe is available) applies;
  Near Death outranks Squishy in the aggregation. One label per COLUMN
  headline; squad mini-rows do NOT repeat it (skulls there = real
  near-death of that squad only). Squishy does not count as "dying" for
  DMG badge rule 2. Tooltip: "Even small hits kill minions and cut the
  squad's damage output."
- **Squad-pool threat math (the Two Shot correction)**: my pitling answer
  had ruled the Tactician out on damage - WRONG, because a multi-target
  strike hits the shared pool once per target. Hero profiles now carry
  bestSquad = max(tier-2 x numTargets) over target-type strikes, used in
  place of bestBurst when the monster is a minion. Verified: with it, the
  12-pool squads read Near Death exactly when a Two Shot-class hit
  covers the pool.
- **Captain + own squad = overview** (was: classic strip). The same-squad
  exception now requires EVERY token to be a minion of one squad; the
  Subcommander/Muceron reported the squad id and killed the overview.
- **High damage dealer standalone line: RED** (#E06464 via
  g_overviewRisk.red; gold "did not stand out").
- **Lens bar relocated to the BOTTOM of the menu** (menu children order:
  container then lens bar; menu is bottom-anchored so the bar now sits at
  a FIXED position directly above the action bar, beneath chips/footers -
  Ricky: the top placement moved with column height and "got lost").
- **Area alert = the MCDM trigger "!" tile** (asset
  e7d55d80-630d-432d-8d3d-33051478bcd9, gold #E9B86F - opportunity
  channel, deliberately NOT the red damage/death channel), replacing the
  twins on area chips. Tooltip = Ricky's exact wording with the exposed
  heroes NAMED: "Human Talent and Polder Elementalist are positioned
  vulnerably to this ability" (OverviewAreaCatch returns every hero in a
  catchable pair). Twins stay on multi-target STRIKES only.
- **Twins colour question answered**: red twins = the ability deals
  damage, off-white = it does not (field test 13 rule). Tongue Pull is
  WHITE correctly - it is "pull 5" with no damage; Synlirii Grafts /
  Agonizing Harmony were red because they damage. (Moot for areas now -
  they wear the gold "!" instead.)
- Asset note: the two plain "trigger" images in Provided By MCDM are
  6ee6ea36 (dark tile) and e7d55d80 (light tile, knocks out cleanly when
  tinted - the one used). Library keyword map lives in
  data/images/<id>.yaml keywords, not the library copies.

**2026-08-24, twenty-eighth report (Ricky: "the badge changes are looking
really good") - minions NEVER read Near Death + the area-window column
line (commit 3f1b6a1d). Live-verified: Tetherite + Pitling columns read
Squishy (the battered Tetherite squad no longer flips to Near Death); the
Chorogaunt column shows BOTH red lines; the Neuronite column shows the
area line alone.**
- **Minion columns ALWAYS read "Squishy", never "Near Death"** - Ricky's
  call, recorded as revisitable in his own words ("possible this is a bad
  call on my part and I'll revert it in the future"): a squishy monster
  is almost always near death anyway (exception he named: a
  much-higher-level minion, e.g. a troll minion vs level-1 heroes), so
  one word carries the signal. Implementation: OverviewThreatEstimate
  short-circuits to the Squishy risk for any minion regardless of the
  pool-wipe computation; the Near-Death-outranks-Squishy aggregation
  preference from the 27th test is now inert but left in place for the
  possible revert. bestSquad (Two Shot pool math) also stays - it only
  fed minion Near Death, so it is currently dormant for display but
  correct if reverted.
- **Red column line "Heroes vulnerable to area abilities"** beneath the
  name whenever ANY of the kit's area abilities currently has the gold
  "!" window (column.areaWindow, computed per populate). Pairs with
  "High damage dealer" as the twin turn-one cue - Ricky's scenario: the
  Chorogaunt showing BOTH tells the Director to use it right now.
  Standalone red bold when the column is otherwise quiet; appended as
  its own red line under an existing risk box; tooltip line "An area
  ability in this kit could catch several heroes right now".

**2026-08-24, captain+squad fix click-verified (resumed session, no code
change).** Selected War Dog Subcommander 1 + the surviving Tetherite (the
exact pair that used to kill the overview via the shared squad id): unique
drawer up, action/maneuver/move collapsed, menu shows both columns -
Subcommander (crown, Horde Support role line, red High damage dealer,
green Outside reach) and Tetherite (Minion Brute, red skull Squishy).
Standing regression check rerun after the menu close: single Neuronite ->
classic strip, Main Action menu shows Signature Abilities (Synlirii
Grafts) + Common Abilities columns. Zero Lua console errors. Remaining
sign-off is Ricky's own eyeball; SHIP (fork push + PR) is his call.

**2026-08-24, twenty-ninth report (Ricky) - icon bullets on the cue lines +
skull/text alignment (commit 68d5ba23). Live-verified on Subcommander +
Tetherite + Chorogaunt.**
- **The two column cue lines wear the SAME glyph as the chip badge that
  earned them, as an icon bullet**: surge (game-icons/surge.png, #E06464,
  16px) before "High damage dealer"; the gold trigger "!" tile (e7d55d80,
  #E9B86F, 15px) before "Heroes vulnerable to area abilities". Ricky's
  intent: "it's trying to marry up the creature to the relevant abilities
  so the user understands why this is showing." Implementation: the two
  lines are no longer text appended into riskLabel - each is its own
  pooled row (dmgRow/areaRow, overviewRiskRow + overviewRiskIcon classes)
  after riskRow in the footer text column, toggled by column.highDamage /
  column.areaWindow, with its own hover tooltip (same strings as before;
  the dmg tooltip still picks all-selected vs near-death by risk
  presence). riskRow itself now collapses when there is no risk text.
- **Risk text seated 1px lower** (tmargin 1 on overviewFooterRisk):
  Ricky's eyeball was right - "Squishy" sat a hair high against the
  skull; the nudge levels the text with all three 16px icon bullets.
- **Debuff bullets on safe creatures - answered, no code change (yet)**:
  Ricky asked why the Subcommander's mark/edge and the Chorogaunt's
  "judged" no longer print as bullets. His own earlier calls removed the
  text channels: field test 10 took threat/stamina text off the signal
  lines (acted state only) and field test 18's one-state redesign deleted
  the amber tier - named-debuff bullets now render ONLY inside a red risk
  box (Near Death / Squishy). Hero-applied statuses still show as
  red-ringed glyphs in the status strip under the portrait (field test
  11's channel), with the caster named on hover. Options offered if he
  wants the text back: an icon-bulleted debuff line in the new style, or
  leave the glyph strip as the only channel.

**2026-08-24, thirtieth field test (Ricky) - Synlirii Grafts false "!"
window: area-catch movement leg now uses REAL pathfinding (commit
1ffbc350). Live-verified: Synlirii Grafts chips lose the "!", both The
Voice chips keep it (correctly), zero errors.**
- **Ricky's report was exactly right**: Synlirii Grafts (1 burst) wore the
  gold "!" naming Polder Elementalist + Polder Shadow, but no Neuronite
  could legally reach a square adjacent to both. Evidence: the only
  covering square for that pair is (0,-5) - a straight-line 5 away, so the
  old envelope test passed - and tok:CalculatePathfindingArea(50) showed
  it is NOT legally reachable for any of the three (walls/occupancy);
  zero reachable squares cover 2+ heroes in a 1 burst.
- **Fix**: OverviewAreaCatch's MOVEMENT leg = the engine's real
  pathfinding, tok:CalculatePathfindingArea(speed x 10 decis) + the
  current squares, cached per frame per token on g_overviewRisk.pathCache
  (badge pass + column pass both ask per area ability). A pair now counts
  only when ONE legal end square has both heroes within cast range + area
  size. The cast/area legs stay Chebyshev, no walls/LoS - a per-axis
  interval argument makes the pair test EXACT in open field, so the
  remaining optimism is only cast-leg walls/LoS. Straight-line envelope
  kept as fallback when pathfinding errors.
- **The Voice (5 burst) keeps its "!" legitimately**: pathfinding found 38
  legal Neuronite 3 squares covering 2+ heroes (e.g. (4,-3), 2 squares of
  movement, covers Shadow+Elementalist+Talent).
- **TRAP recorded**: g_overviewRisk was declared BELOW OverviewAreaCatch;
  the new reference resolved to an uninitialized GLOBAL and raised on
  first menu open (engine raises on uninitialized global reads). The
  declaration moved above its first reader. luac -p cannot catch this -
  it is a runtime scoping fact, not a syntax error.
- **Ricky's decision recorded**: NO debuff bullets on safe creatures for
  now ("There's a lot built in and I may change decision on this at a
  later date") - the red-ringed status glyphs remain the only channel.
  Revisitable. [REVERSED same day - see field test 31.]

**2026-08-24, thirty-first report (Ricky, reversing the hold above) -
amber "Likely Target" line (commit 82aa7eed). Live-verified: Subcommander
shows mark + edge glyphs, Chorogaunt shows judged.**
- **Amber (not red) "Likely Target"** on a single-actor column whose
  creature carries hero-applied debuffs, when no red risk box already
  names them in its bullets (Near Death / Squishy still own that case).
  The debuff STATUS GLYPHS themselves ride the line as its icon bullets
  (up to 3, pooled, tinted by the status's own style like the strip) -
  same icon-bullet grammar as the skull/surge/"!" rows. Hover:
  "[conditions] make this creature a likely target" (names joined with
  "and", makes/make by count) - e.g. "Marked and Next Attack Against Has
  Edge make this creature a likely target". Label is width-auto
  ("likely" class variant) so several glyphs fit before it.
- **ENGINE FIX that made it work (TokenUI.CalculateStatusIcons)**: an
  ongoing effect with NO linked charCondition dropped its casterid even
  when the instance recorded casterInfo - the Subcommander's "Next
  Attack Against Has Edge" (cast by Human Talent) was invisible to
  threat detection. casterid is now set from casterInfo regardless of
  condition linkage; side effects are all wins - the strip's red ring
  and the token HUD's hover highlight-line to the caster now work for
  such effects too.
- **Flagged for Ricky's eyeball**: on a single-actor column the status
  strip (under the portrait) and the Likely Target row sit side by side,
  so the threat glyphs appear twice in close proximity (strip red-ringed
  + row bullets). Field test 11 locked the strip at ALL statuses, so
  both channels are by design - but the adjacency is new; his call
  whether it reads as clutter. [He called it: duplication - see 32.]

**2026-08-24, thirty-second report (Ricky: "looks good except the symbols
are duplicated") - strip de-dup + hoverable Likely glyphs (commit
c399eda0). Written and luac-clean; the MCP bridge dropped right before
the reload - NOT yet live-verified; the repo IS the gitfolder so the next
app launch (or reload) picks it up. VERIFY ON RETURN: Subcommander =
glyphs ONLY beside Likely Target (none under the portrait), each glyph
hovers its own debuff text, the label hovers the explainer.**
- **De-dup rule**: when the Likely Target row is showing, the strip under
  the portrait drops the threat entries and keeps only the OTHER statuses
  (fly arrow etc.). When a red risk box shows instead (no Likely row) the
  strip still carries every status, threats red-ringed - field test 11's
  twin-channel pairing with the text bullets survives for that case.
  Mechanism: the single-actor setStatuses call moved BELOW the risk/
  likely computation and filters entry.threat when likely ~= nil.
- **Hover**: each Likely glyph is interactable and answers with its own
  debuff hoverText (the same strings the strip icons used - condition
  name + caster/description); the amber label and the row's bare ground
  answer with "[conditions] make this creature a likely target". The
  dmg/area labels also gained direct hovers (they relied on row-level
  hover only, unproven). No swallowPress needed on any of them: the
  footer root swallows presses (its comment: last stop before the drawer
  toggle).
- LIVE-VERIFIED 2026-08-25 (goblin encounter, staged edge effect on the
  Bugbear Channeler): glyph appears ONLY beside the amber Likely Target
  line, none under the portrait. FT32 closed.

**2026-08-25, thirty-third field test (Ricky, goblin/bugbear encounter) -
mini-row names + itemisation order (commits ef71bbd0). All live-verified
in one frame: "Spinecleaver Squad 1 (4)" / "Squad 4 (4)" fit, near-death
Warriors 2 + 8 skull-sorted to the top of the x8 column, Warrior 8 named
correctly. Zero errors.**
- **Band prefix dropped when the name cannot fit** ("Goblin Spinecleaver
  Squad 1" ellipsized the squad NUMBER - the important bit). Rule: when
  name + "(N)" exceeds OVERVIEW.ROW_NAME_CHARS (22), strip the bestiary
  monster-group name off the front (props:MonsterGroup().name - "Goblin",
  "Bugbear"; singular fallback if the group name is plural), EXCEPT when
  props:Organization() == "solo" (the band usually IS a solo's name -
  Arrix). Group names verified singular in data; org words lowercase.
- **Members with a note sort to the top of the mini-rows** (Ricky: "I
  want to be able to see specifically which monster is Near Death" - the
  flagged Warrior 8 hid behind "+5 more"). LayoutRows now splits the
  signals view into flagged (member.risk non-squishy = the skull) then
  the rest, stable within each; the owner-prompt view keeps its own
  fresh-candidate order.
- **DATA FIND + rule fix in OverviewColumnSignals**: Goblin Warriors 7
  and 8 carry Spinecleaver SQUAD ids - they are squad CAPTAINS. The
  member key/name rule (name = squad or tok.name) predated field test
  27's captain rule and displayed Warrior 8 as "Spinecleaver Squad 4"
  inside the Warrior column. Squad identity now substitutes ONLY for
  minions (tok.properties.minion == true); a captain keeps its own name
  and its own member row and never folds into a squad entry.

**2026-08-25, thirty-sixth report (Ricky: "where did this text come from?
is it from the source material?") - role hover prose was INVENTED; now
book text (commit 2a493b23, reloaded live). This closes the risky half of
the P2-f copy pass.**
- The F2-9 OVERVIEW_ROLE_PROSE strings were authored play-pattern copy,
  not source text - and Ricky caught them contradicting real kits (his
  Human Scoundrel ambusher has no "slips away" tool; Artillery mismatched
  too). The table also carried "Skirmisher", which is not a Draw Steel
  role at all. LESSON, recorded: overview copy that claims to describe
  the RULES must be sourced, not composed - invented tactics read as
  authority and mislead at the table.
- All role AND organization entries are now the Monster Basics
  descriptions from Draw Steel: Monsters p4-5 (lightly trimmed to
  tooltip length; Brute/Controller/Solo/Horde/Platoon/Elite compressed
  without changing meaning; Minion kept to its defining first sentence).
  Skirmisher removed. The "Role: " prefix in OverviewRoleInfo's prose
  builder is gone - the book text opens with the role word itself.
- Source extraction: pdftotext over "Draw Steel Monsters v1.pdf" (iCloud
  iBooks path recorded in the session log); the Creature Roles section
  sits near line 930 of the raw text dump.

**2026-08-25, thirty-fifth report (Ricky, post-merge testing: only 3 of 7
warriors visible) - "+N more" is now a control (commit 98d79a75, on the
MERGED main). Reloaded clean, zero errors; press verified programmatically
(label read "+4 more", LayoutRows re-ran) but the expanded render was not
screenshot-verified - Ricky was mid-play (Arixx's turn) and the menu
closed under the harness. HIS CLICK IS THE VERIFICATION.**
- Press "+N more" under a multi-member column to show EVERY member row in
  place (each row press already locates + pulses that token on the map -
  the find-them-on-the-map ask); press again ("Show fewer") to fold back
  to the first three. Amber bold on hover is the affordance; tooltips
  "Show every member" / "Show fewer". Expansion resets when the pooled
  footer binds a different column; the owner prompt view is unchanged.
- FOOTER_ROW_POOL raised 6 -> 12 (pooled, collapsed when unused). A
  column with more than 12 members still tails "+N more" - pressing it
  folds back (accepted rarity). Chose expand-in-place over pagination or
  a scrollbar: fewest moving parts, and the equal-footer band alignment
  is only disturbed while a column is deliberately expanded.
- LayoutRows became a forward-declared assignment (the press handler
  closes over it) - the file's standard forward-declare pattern.

**2026-08-25, thirty-fourth report (Ricky) - risk-box facts bind to their
owners by SYMBOL (commit 93aa1de3). Code loads clean (reload + zero Lua
errors) but the staged visual check was interrupted - the app came back
into use mid-verification (selection replaced under the harness, a test
mark applied to Warrior 7 was REMOVED again, no residue). VISUAL
VERIFICATION PENDING: multi-member column w/ one marked member + one
low-stamina member -> box shows "Near Death / - Low Stamina / [mark
glyph] Marked by <hero>" and the marked member's mini-row wears the same
glyph after its name.**
Ricky's report: the Warrior x8 box read "Near Death - Low Stamina -
Marked by High Elf Tactician", but the mark was Warrior 8's and the low
stamina Warrior 2's - one member's box masqueraded as the column's.
His design: print each fact ONCE in the box, with the condition's SYMBOL
in place of the "- " for debuffs, and repeat the same symbol on the
owning member's mini-row.
- OverviewThreatEstimate now returns risk.headline + risk.bullets
  (structured: {text, icon, bgcolor, hoverText}; plain bullets like Low
  Stamina/push have no icon). risk.text is GONE - the footer renders the
  headline label + up to 4 pooled bullet rows (overviewRiskRow+bullet,
  lmargin 19 = the headline text indent; glyph 14px or "- " prefix;
  glyphs hover their own debuff text).
- The box's bullets are the UNION over every member's risk bullets,
  deduped by text (was: the single worst member's prebuilt text - the
  root cause of Ricky's confusion).
- Mini-rows: up to 2 trailing 13px debuff glyphs (overviewRowStatusIcon)
  after the name, tinted by the status style, hover = the debuff's own
  text; rowLabel width now set per populate ("100%-N") to reserve skull
  + glyph space.









**2026-08-19, twelfth user field test (Ricky) - map clutter under the lens
bar + minion copy.**
- **On-map multi-select buttons yield to the open overview menu**: the
  worldspace "Group Initiative" / "Make Captain" buttons (MCDMMinion.lua)
  trigger on exactly the overview's multi-selection and drew OVER the lens
  bar. While the Unique Abilities menu is open
  (`DrawSteelActionBar.uniqueMenuOpen`, set by the unique drawer's
  menuStatus) the buttons collapse; they return the moment the menu closes.
  The menu IS the multi-select surface while it is up. Lens row backing also
  bumped #000000AA -> #000000D9 against general map noise.
- **Minion guidance copy**: red guidance reads "Use squad before they die"
  when the member is a minion squad (verified in code; the live A5 Runner
  died mid-session before it could be re-checked on screen).

**2026-08-19, eleventh user field test (Ricky) - "clicking on a lens now
works as I would expect" (swallowPress fix CONFIRMED with a real mouse;
OVERVIEWDBG diagnostics removed). Three refinements, live-verified.**
- **DMG badge is symbol-only**: the "DMG" word crowded the keywords; the red
  surge glyph alone carries it (tooltip unchanged, badge 18px).
- **Status glyphs sit DIRECTLY UNDER THE PORTRAIT** (Ricky: deliberate
  duplication with the risk bullets - "images are more powerful than text").
  The P2-a strip moved into a portrait column (34px, vertical), now shows
  ALL statuses again including threats (red-ringed), 2 glyphs + "+N". Live:
  Dazed under the Monarch, Judged under the Assassin. ("Judged" is the
  Censor's class effect, not a core condition - the strip mirrors whatever
  art the token HUD shows.)
- **Reach line is exception-only** (Ricky's silent-default rule applied to
  his own feature): "Can reach 5 heroes" on every chip was repeated noise
  and near-collided with "5 heroes within striking range". The line now
  prints ONLY at zero - amber "Can't reach any hero" / rows "can reach no
  hero" - the rule-this-monster-out cue. The risk bullet keeps the heroes'
  side of the story.

**2026-08-19, tenth user field test (Ricky) - stamina numbers removed, DMG
chip badge added. Live-verified.**
- **Stamina numbers REMOVED from the footer** (Ricky: not needed; also the
  "50/80 - Dazed" line duplicated the risk box's named bullets). The signal
  line now carries ONLY the acted state ("Turn already taken" / "Acting
  now"); mini-rows likewise. Stamina survives only as the "Low Stamina" risk
  bullet. Arc note for the copy pass: F2-5 raw numbers -> field test 6 amber
  label -> field test 7 raw only -> field test 10 REMOVED; the number
  earned no decision the risk box did not already make.
- **DMG chip badge**: red (#E06464) surge glyph (game-icons/surge.png) +
  bold "DMG" beneath, floating at the chip's right edge, tooltip "This
  ability does high damage" (opens above). Shown ONLY on overview monster
  chips (never hero menus - only the overview path sets it), ONLY under the
  All / Damage lenses, and ONLY on (1) the highest-tier-2-damage ability
  displayed and (2) the highest among creatures at red death risk - ties
  share the badge. Thresholds ride the column records
  (column.dmgMax/dmgRedMax from PopulateUniqueColumns); chips get a
  setDamageBadge event; presses bubble through the badge so clicking it
  still casts. Live: both Monarch Handaxes (tied selection best) + Sword
  Stab (best among reds); 0 badges under Forced Move, back under Damage/All.

**2026-08-19, ninth user field test (Ricky) - the risk box speaks in real
names and actions, and calls out the damage dealers. Live-verified.**
- **Threat bullets name the ACTUAL effect and caster** ("Dazed by High Elf
  Tactician", "Judged by Human Censor"), never the generic "Marked by
  heroes" - Marked is a specific mechanic and the Monarch was Dazed. Up to
  two named, then "+N more"; `OverviewThreatEstimate` now takes the threat
  ENTRY LIST, not a boolean.
- **Amber answers "what do I do?"**: green guidance "Consider using turn
  soon" under "At Risk" (red keeps "Use turn before they die"); both
  suppressed once the turn is spent. Semantics recorded: amber = heroes
  have intent+access or combined attacks threaten it, no single hero turn
  likely kills it; red = one hero turn could.
- **"High damage dealer" bullet** (Ricky's ask): flagged for (a) the
  column(s) whose kit has the selection's best tier-2 damage AND (b) the
  best among columns already at red death risk - so when several are dying
  the Director knows which to burn for damage first. Computed
  cross-column in `PopulateUniqueColumns` (`column.highDamage`); rendered
  as a bullet above the green guidance, or as a standalone gold line when
  the creature is otherwise safe. Live: Monarch (Handaxe 10, selection
  best) and Assassin (best among reds) both flagged - exactly the two
  Ricky named.

**2026-08-19, eighth user field test (Ricky, rapid-fire) - LENS-CLICK ROOT
CAUSE FOUND AND FIXED via the OVERVIEWDBG instrumentation, plus seven
refinements. All live-verified except the real-click fix (needs Ricky's
mouse; diagnostics left in for one more round).**
- **LENS CLICK CLOSING THE MENU - ROOT CAUSE (third report, first evidence)**:
  the log showed a real click firing `lens tab press` AND TWO raw `drawer
  press (toggle)` events - engine input presses BUBBLE to every ancestor
  (Panel.swallowPress docs), and the Unique drawer is an ancestor of the
  menu; the same-frame reopen was swallowed by the shownMenuTime guard, so
  the menu ended closed. `FireEvent("press")` never bubbles - THAT is why
  every synthetic test passed while every real click failed. FIX:
  `swallowPress = true` on the lens tabs, tab row, footer, mini-rows,
  take-turn button and dismiss-x (the footer swallow also stops a mini-row
  click from double-firing the footer's locate). RULE FOR THIS FILE: any
  interactive panel inside the action menu MUST set swallowPress = true.
- Role line drops the level: "Horde <b>Controller</b>", "Minion Harrier",
  plain "Leader" (tooltip keeps the full stat-block line).
- Lens tab labels read "All (7)" / "Damage (5)" (brackets); tabs widened
  96 -> 106 so "Forced Move (1)" fits; hover tooltip is Ricky's copy "Shows
  only creatures with Malice abilities (2 creatures)" - CREATURE counts
  (columns with a match), computed beside the ability counts - and opens
  ABOVE the bar (valign top; below, it covered the chips).
- "Common <lens> abilities:" line is CENTERED directly beneath the active
  tab (full-row-width label shifted by selfStyle.x; numeric widths only - a
  %-width child of the auto-width bar collapses to one char per line).
- Lens RESETS to All whenever the unit selection changes (a lens is a
  question about THIS selection) - root refresh compares SelectionSignature.
- Naming: stays "Forced Move" (rules term is "forced movement"; "Force
  Move" reads as a command).
- "At Risk" semantics (Ricky asked): amber = heroes have INTENT+ACCESS
  (marked with someone in reach) or combined attacks could drop it, but no
  single hero turn likely kills it - urgency without a death call; red =
  one hero turn could. Explained in the tab tooltip question - if amber
  proves noisy in play, the cut is to require the two-best-bursts math and
  drop the marked-floor.
- The "Error indexing userdata ... [string "code"]" dialog Ricky reported
  was MY diagnostic probe reading an unset selfStyle field over the bridge -
  not app code; harness rule: never read selfStyle fields you did not set.

**2026-08-19, seventh user field test (Ricky, "loving your changes") - four
refinements, live-verified.**
- **Squad-captain crown moved beside the NAME** (it was sitting in the P2-a
  status strip): `OverviewStatusEntries` splits out status id "captain"
  (DrawSteelTokenHud TokenUI.RegisterIcon, panels/hud/crown.png, squad-colour
  bgcolor preserved); the footer name is now a `overviewFooterNameRow`
  (name + 16px `overviewCaptainIcon`, tooltip "Squad captain"), crown shown
  only for single-actor columns. Identity, not status.
- **Risk bands made honest (Ricky: a marked 50/80 Monarch is NOT "High Death
  Risk")**: RED is now strictly the stamina-vs-damage verdict
  (stamina <= best adjusted burst + allowance); a MARK no longer grants red
  by itself - it DOUBLES the allowance (mark benefits are extra damage) and
  guarantees at least amber while anyone is in reach. Low stamina alone also
  guarantees at least amber, so the fact survives when nobody is currently
  in reach. Live: marked 50/80 Monarch = amber "At Risk - Marked by heroes,
  5 heroes within striking range", no guidance; 14/15 Judged Assassin still
  red (14 <= 10 + 8).
- **Low Stamina exactly once**: the field-test-6 amber stamina-line label is
  GONE (line back to plain raw "9/10"); "Low Stamina" lives only as a risk
  bullet - Ricky's preference. (Net of tests 5-7: raw number on the stamina
  line, the WORD only in the risk box.)
- Copy: guidance is "Use turn before they die" (was Spend).

**2026-08-19, sixth user field test (Ricky) - risk box redesign + copy fixes,
live-verified. LENS-CLICK BUG STILL OPEN, now instrumented.**
- **Risk box redesigned to Ricky's spec**: red "<b>High Death Risk</b>"
  headline, then WHY as "- " bullets (Marked by heroes / Low Stamina / 5
  heroes within striking range), then GREEN (#7AC77A) guidance "Spend turn
  before they die". Guidance only when the turn is NOT already spent (an
  acted/acting monster keeps tag+bullets - still useful for planning - but
  no call to action). Amber tier = "At Risk", no guidance.
- **LOW STAMINA replaces the bare raw number (reverses F2-5b, Ricky's call)**:
  amber "<b>Low Stamina</b> (9/10)" on the stamina line - raw number kept in
  parentheses. Definition: a typical TIER-2 hit from the hardest-hitting hero
  on the map (any hero, not just in reach) would drop it - roughly "2 rolls
  in 3 kill it", standing in for Ricky's 65% intuition without a probability
  model (OverviewLowStamina, from the P2-e hero profiles). Also feeds the
  "Low Stamina" bullet. Above the threshold the line stays a plain raw
  number (silent default).
- **Reach copy de-collided**: "5 heroes in reach" (monster's OFFENSE) read
  like the risk box's "within striking range" (threat TO it). Now "Can reach
  5 heroes" / amber "Can't reach any hero"; rows "can reach 3" / "can reach
  no hero".
- **Lens tab counts explained** (new-user confusion): per-tab hover tooltip
  "Show only damage abilities - this selection has 3. Columns without one
  hide; other abilities dim." Tabs stay all-visible (Ricky prefers this over
  the original cycle control for now).
- **Mid-reload crash fixed in passing**: actionMenu destroy -> dehover called
  `CharacterPanel.HideAbility` while that module was mid-reload (nil) if a
  hover card was up when Lua reloaded; now guarded. (Reported by Ricky as an
  error dialog; only reachable around reloads.)
- **LENS TAB CLICK STILL CLOSES THE MENU with a real mouse click** (synthetic
  FireEvent("press") never reproduces it; hover DOES reach the tab - Ricky's
  inspector showed the row with the hover class). TEMP `OVERVIEWDBG::` prints
  are now in every close path (drawer press toggle / escape / closemenu with
  reason, lens tab press) - next session: have Ricky click a lens tab once,
  then grep the Player log for OVERVIEWDBG to see WHICH path fired; remove
  the prints after. Candidate theories if press+toggle both log: the real
  click hits the drawer's mappress (click-through to map), or the press
  propagates to a toggle.

**2026-08-19, "Get in Here! made it the Runners' turn" report - INVESTIGATED,
NOT an overview bug; claim path CORRECT (third live proof of Decision 47).**
Log: exactly one `OVERVIEW:: claiming turn for cead488d...` at the cast
commit; `q.currentTurn` = cead488d = the MONARCH's entry; the entry's own
`description` is "Goblin Monarch"; `HasHadTurn` false (turn in progress).
What Ricky saw: in this A5 game the Monarch and the Goblin Runners share ONE
group initiative entry (cead488d - predates the summon; the original Runner
had the same id at session start), and the two summoned Runners joined that
entry (RAW: summons act on the summoner's turn). The initiative bar picks
the group's display token via GetTokensForInitiativeId()[1] = a Runner by
token iteration order, so the turn card wears a Runner face even though the
entry is the Monarch's. PRE-EXISTING group-entry display quirk, out of
overview scope. Candidate fix if wanted (separate slice, MCDMInitiativeBar):
prefer the non-minion / leader / the entry.description-matching token as a
group entry's display representative.

**2026-08-19, cross-session hazard inherited from the "VA1 marks allies moved"
fix (PR #253, token-hud-pick-not-claim):** While ANY targeting prompt or chooser
is active and the acting side has unmoved creatures, each unmoved ally's token
HUD shows the pulsing claim-turn SWORDS (16x16 hit area at token centre) and a
clickable NAMEPLATE above the token; both swallow a pick click and their press
runs `SelectTurn` + `BeginTurn` (DrawSteelTokenHud.lua ~:583) - i.e. picking a
token can silently CLAIM ITS TURN. PR #253 masks the swords and routes both
presses to `token.sheet:FireEvent("tokenClick", false)` whenever
`token.sheet.data.targetInfo ~= nil` (the action bar stamps that on every
candidate of an active prompt).
RELEVANCE TO THIS DESIGN: the slice-(e) owner prompt (Decision 32/36) says "the
matching creatures are also highlighted on the map for direct clicking", and
Decision 47's whole premise is that nothing claims except target-confirm. If
the overview's on-map pick path ever relies on clicking the token itself, it
MUST use the same targetInfo stamping (so PR #253's routing applies) - a raw
token click on an unmoved monster would hit the swords and claim. ACTION: when
the on-map pick for the owner prompt is implemented (currently the prompt is
mini-rows in the footer, which is safe), stamp candidates via the action bar's
targetInfo mechanism, never a bespoke click handler. Also a good regression
test for Phase 2: open the owner prompt, click a highlighted unmoved monster on
the map, assert currentTurn unchanged.

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
