# Feature Metadata Incremental Improvements -- Design Brief

Status: LOCKED 2026-08-12 (James). Chunk order amended: internal-marking
content sweep pulled forward ahead of display work -- it blocks the
draw-steel-companion monster builder. Core-mechanic feature-level-vs-class
question closed same day: subclass precedent confirmed in content (Paragon
Congregation, Stormwight Furious Change, doctrine Mark-riders); feature-level
boolean stands.
Owner: James. Loop: feature-design-personal.

## Framing

The character sheet/builder/tac panel redesign exploration (see
docs/character-sheet-redesign/) was reviewed by James and external reviewers.
Verdict: some aspects arguably better and the stated problems "solved", but
the overall direction was not "it". The concept package is SHELVED; we salvage
the decided, liked pieces as incremental step-changes to the LIVE surfaces
while the end-state design continues to marinate.

Scope guard (James 2026-08-12): work into the live sheet, character panel,
tac panel, and builder as they exist today. No layout redesign. Small
opportunistic tweaks allowed only where clearly BETTER than current, not just
different. If something clearly better surfaces mid-design we may explore it.

Personas: power user / director (density, control, editing monsters) and
set-and-forget player (sheet just works). Developers are an explicit
sub-persona for the internal-feature toggle.

## Workstreams (sequenced 2026-08-12)

1. **Internal feature flag** -- feature-level flag hiding non-book "plumbing"
   features from sheet/panel display. Also needed by the draw-steel-companion
   monster builder. Includes a bulk marking sweep of existing content.
2. **Core mechanic flag** -- mark a feature as a class core mechanic; its
   rules appear pinned toward the top of sheet and character panel (Tactician
   Mark, Censor Judgment get the first-class treatment Fury/Troubadour already
   have via bespoke widgets). Was F35 in the shelved redesign; prior finding:
   heroic-resource blocks derivable, Mark-like mechanics need a per-class
   authored flag (~11 classes, one-time).
3. **Game-mode tags** -- tag features (and via features, abilities) with game
   modes; sheet + tac panel filterable by mode; later auto-filter tied to
   actual game mode with easy manual override.
4. **Skills collection step** -- builder gains a Skills entry (last selection
   under class) collecting ALL skill choices in one place; skill choices
   removed from inline feature presentation in the builder. Backend grant
   structure unchanged; presentation only. Matrix-smart: only valid choices
   shown, recalculates, tooltip explains what to trade to free a wanted skill.
5. **Titles to sheet** -- title management moves from builder to sheet;
   button + menu under the Grant Title dropdown (Appearance tab area).

Data-model note: workstreams 1-3 are all metadata on CharacterFeature plus a
small editor affordance; design the data model once, ship display work
incrementally.

Related queued items (NOT this scope):
- Character panel monster presentation redesign (stat-block-like, features
  auto-expanded, no popup hiding) -- own design pass later.
- Downtime/Respite mode consolidation in the app.
- Character panel feature list: once internal flag exists, panel shows ALL
  book features instead of today's curated list, auto-expanded. (Display-rule
  change belonging to workstream 1/later panel pass -- confirm placement.)

## Decision ledger

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-12 | Sequencing = internal flag, core mechanic, tags, skills step, titles | Internal flag unblocks monster builder + tag sweep benefits from exclusions |
| 2026-08-12 | Tag vocabulary = Combat / Exploration / Montage / Negotiation / Respite | Test dropped: tests span modes, skills have dedicated region + skills stay exempt from pillar tags (prior ruling). Montage kept: features reference montage tests specifically. Respite absorbs downtime until mode consolidation. |
| 2026-08-12 | Field/copy = "Internal Feature", tooltip "This feature will be hidden on the character sheet and panel" | Accurate; "hidden" implies GM secrecy |
| 2026-08-12 | Show-internal toggle exists on the SHEET only; the character panel only ever shows book features | Panel is a play surface |
| 2026-08-12 | Players may see their own internal features; monster sheets already director-only -- no further lockdown | Existing permissions sufficient |
| 2026-08-12 | Default = unchecked (book feature); marking internal is a deliberate act | Majority of content is book features |
| 2026-08-12 | Bulk sweep = Claude classifies vs Heroes/Monsters book references; buckets confident-internal / confident-book / unsure; James reviews unsure + samples confident-internal before write-back | Same shape as validated tag experiment |
| 2026-08-12 | Show-internal toggle = small eye icon on the sheet features section header writing a remembered per-user preference (storage="preference"); revealed internal features get dimmed treatment + "Internal" chip | One flip for devs, invisible to players; revealed sheet never reads as extra features |
| 2026-08-12 | Internal Feature checkbox sits as a row in the feature FORM (with Name/Source/Implementation), not the modifier card header | James's intended placement; Implementation row is the precedent |

| 2026-08-12 | Core mechanic = boolean `coreMechanic` flag on the feature (display promotion for stateful-less signature rules prose; stateful mechanics keep their widgets) | Works for class/subclass/monster/homebrew; bulk sweep can set the ~11 class flags |
| 2026-08-12 | Sheet: pinned card above group headers, rendered once (removed from source group), default collapsed | F45 reasoning transfers; single-source |
| 2026-08-12 | Panel: own collapsible section per flagged feature, user-reorderable | Header space sacred; buried-in-features rejected |
| 2026-08-12 | Section/card title = the FEATURE NAME (e.g. "MARK"), never the label "Core Mechanic" | James: label hurts immersion; placement communicates the promotion |
| 2026-08-12 | Placement must not outrank regularly-interacted sections (heroic resources etc) | James ruling; default slot below resource sections |
| 2026-08-12 | Multiple flagged features stack; Core + Internal independent, core display wins if both set (documented, not enforced) | |
| 2026-08-12 | [COPY] signed: checkbox "Core Mechanic", tooltip "Pin this feature's rules to the top of the character sheet and panel" | Editor copy only; player surfaces never show the term |

| 2026-08-12 | Core-mechanic panel section defaults directly UNDER conditions (after statistics..resources..conditions), above skills/languages/features | Current conditions = important game state, must stay above reference prose |
| 2026-08-12 | Tags data model = new `modes` set-of-strings on CharacterFeature, closed vocabulary, Multiselect editor row | Feat `tag` string keys choice pools -- reuse would be a trap |
| 2026-08-12 | Untagged features stay visible under any mode filter (filter hides only features tagged exclusively for other modes) -- conditional on a thorough tagging job | Untagged = mode-agnostic; never punish incomplete tagging |
| 2026-08-12 | Mode tagging/filtering is HERO-FACING only at this stage; monsters excluded (combat-only, few features); check retainers/followers state of play but same approach expected fine | James ruling |
| 2026-08-12 | Mode filter chips on BOTH sheet Features tab and tac panel Features section | Prior sheet-only ruling died with the shelved concepts |
| 2026-08-12 | Feature tags flow down to granted abilities; ability regions filter too; action bar untouched | Catches respite-activity-style abilities |

| 2026-08-12 | Auto-filter: app HAS game modes for Combat, Exploration, Respite, Downtime -- chips auto-select from mode (Downtime mode -> Respite tag); Negotiation/Montage manual-only until modes exist; auto-selection always one click to clear | James corrected stale no-engine-state claim; verify mode state location in code |
| 2026-08-12 | Perks tagged individually from descriptions (some name montage/respite use explicitly); NO wholesale category->mode mapping | Interpersonal does not always equal Negotiation |
| 2026-08-12 | Sweep scope = hero-facing: classes, subclasses, ancestries, kits, complications, titles, perks, item/treasure features; skills+languages exempt; monsters excluded | |

| 2026-08-12 | Skills step = its own rail entry at the END of the builder options, before where Titles is today (Titles departs); owns ALL skill choices regardless of source | "After class" was a misstep |
| 2026-08-12 | Feature cards show read-only grant line jumping to Skills step (copy ASCII, no emdashes, [COPY] at implementation) | Provenance breadcrumb |
| 2026-08-12 | Fixed skill grants appear in Skills step as locked entries with source | Step = complete skills picture |
| 2026-08-12 | Three tiers: valid = normal; reachable-via-trade = dimmed + computed trade tooltip; unreachable = collapsed "Unavailable based on choices" group, but SELECTABLE as an explicit clearly-marked override (director-agrees swap rule) -- inform not enforce | James ruling; group name [COPY] |

| 2026-08-12 | Titles: GRANT moves inside the Manage Titles menu (with benefit choice + remove); granted-title chips keep showing as today | One home for all title actions |
| 2026-08-12 | Players manage their own titles (benefit choice + removal); no lockdown | Inform not enforce; benefit choice is the player's per book |
| 2026-08-12 | Builder Titles rail entry removed entirely | Fixes today's disjointed grant-on-sheet-then-choose-in-builder flow |

### Critique round (2026-08-12; 3 lenses: Hodent, DS director domain, accessibility; claims code-verified)

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-12 | Core-mechanic sweep flags only classes/subclasses with a genuinely stateless prose mechanic (Tactician Mark, Censor Judgment, likely 3-6 total pending per-class read) -- "~11" retired, no quota | Most signature mechanics are stateful and keep widgets |
| 2026-08-12 | Sweep guard: non-trivial book-verbatim description text force-routes to "unsure" regardless of classifier confidence | Trigger-carriers often HOLD the book text; must never vanish on a sampled review |
| 2026-08-12 | Skills step surfaces the Quick Build hint per choice (hints live as plain text in choice descriptions) | Set-and-forget player keeps the one-glance default |
| 2026-08-12 | Trade info never hover-only: always-visible trade marker on dimmed skills; click opens explanation + swap action; override tier gets identical trade-preview; collapsed group header carries count badge | No-hover-only rule |
| 2026-08-12 | Eye toggle: state-aware icon (open/closed), tooltip in [COPY]; "Internal" chip contrast-checked in dimmed-row context; dimming always paired with reason-specific marker | Dimming now carries two meanings |
| 2026-08-12 | Core pinned card/section gets accent-edge treatment | Promotion legible without a label |
| 2026-08-12 | Manage Titles button shows existing unspent-choice badge when a granted title has an unmade benefit choice | Director grants must not land silently |
| 2026-08-12 | Mode chips get plain-English gloss tooltips [COPY]; Respite gloss names the downtime overlap | Vocabulary is rules jargon |
| 2026-08-12 | Curated->all-book-features panel risk downgraded: users frequently ask to see everything; internal features excluded and abilities live on the action bar, so list stays reasonable. Eyeball a dense character anyway | James: frequent see-everything feedback |
| 2026-08-12 | WS1 sweep (Heroes+Monsters books, monsters in scope) vs WS3 sweep (hero-only) are deliberately different scopes | Stated to prevent shared-file-list assumption |
| 2026-08-12 | NO builder redirect/tombstone for departed Titles step or moved skill pickers | Early access; one-time impact; don't memorialize the old way |
| 2026-08-12 | Auto-filter: brief accent pulse + visually distinct "auto" chip state, no toast; MANUAL WINS -- auto-selection applies only when current filter state is auto or empty; one click clears either | |
| 2026-08-12 | Chips render for hero characters only in phase 1; retainers (now implemented to echelon 4) get an example-sheet check -- gut: too few features to warrant filtering | |
| 2026-08-12 | Downtime->Respite mapping stands; cross-surfacing recorded as low, accepted risk; ambiguous features get a per-feature call during sweep; revisit at mode consolidation | James: unlikely to matter much |

## Decided design (summary; ledger is authoritative on conflicts)

### WS1: Internal feature flag
- Field: boolean on CharacterFeature, class-level default false, written only
  when true. Editor: checkbox row "Internal Feature" in the feature form
  (alongside Name/Source/Implementation), tooltip "This feature will be
  hidden on the character sheet and panel". Default unchecked.
- Display: internal features excluded from sheet Features index and tac panel
  index. Sheet-only reveal: eye icon on the features section header writing a
  remembered per-user preference; revealed internal features dimmed + chip.
  Panel NEVER shows internal features. Compendium editors always show all.
- Panel display-rule change (same workstream family): tac panel features
  section moves from curated index to ALL book features, auto-expanded
  consideration belongs to the later monster-presentation pass.
- Bulk sweep: classify all existing features vs Heroes/Monsters book
  references; confident-internal / confident-book / unsure buckets; James
  reviews unsure + samples before write-back.
- Also consumed by draw-steel-companion monster builder (field flows through
  monster YAML/export).

### WS2: Core mechanic flag
- Boolean on CharacterFeature; display promotion for signature rules prose
  with no state (stateful mechanics keep bespoke widgets). Editor checkbox
  "Core Mechanic", tooltip "Pin this feature's rules to the top of the
  character sheet and panel".
- Sheet: pinned card above group headers, single-source, default collapsed.
- Panel: own collapsible section per flagged feature, default slot UNDER
  conditions, user-reorderable. Title = FEATURE NAME, never "Core Mechanic".
- Multiple stack; Core+Internal independent, core display wins.
- Bulk pass flags only qualifying stateless prose mechanics across classes
  AND subclasses (likely 3-6; no quota).

### WS3: Game-mode tags
- Field: `modes` set-of-strings on CharacterFeature, closed vocabulary
  Combat / Exploration / Montage / Negotiation / Respite; Multiselect editor
  row. Hero-facing only; monsters excluded (check retainers/followers).
- Filtering: mode chips on sheet Features tab + tac panel features section.
  Untagged features stay visible under any filter. Tags flow down to granted
  abilities; ability regions filter; action bar untouched.
- Auto-filter: chips auto-select from real game modes (Combat, Exploration,
  Respite; Downtime mode -> Respite tag); always one click to clear;
  Negotiation/Montage manual until such modes exist.
- Sweep: hero-facing content per ratified tagging policy (characteristic
  increases untagged; choice rows never tagged, only chosen results; skills +
  languages exempt; perks tagged individually from descriptions).

### WS4: Skills collection step
- New rail entry at end of builder options (before departing Titles slot);
  owns ALL skill choices from every source. Grouped by skill group.
- Feature cards show read-only grant line jumping to the step.
- Fixed grants shown as locked entries with source.
- Three tiers: valid normal; reachable-via-trade dimmed + computed trade
  tooltip ("Remove X or Y to take this"); unreachable collapsed in
  "Unavailable based on choices" group but selectable as clearly-marked
  override (director-agrees swap rule).
- Backend grant structure unchanged; presentation only.

### WS5: Titles to sheet
- Builder Titles rail entry removed entirely.
- Sheet Appearance tab: "Manage Titles" button under the current dropdown
  position; menu contains grant, benefit choice per owned title, remove.
  Granted-title chips render as today. Players manage their own titles.

### Post-chunk-1 rulings (2026-08-12, James)

| Date | Decision | Rationale |
|---|---|---|
| 2026-08-12 | Core mechanic STAYS feature-level, governed by ONE-PER-CLASS policy: exactly one pinned feature per qualifying class, the base mechanic only. The earlier stacking rule is STRUCK; subclass features (Congregation, Furious Change) and doctrine Mark-riders render as NORMAL features, never pinned | James dismantled the subclass-precedent examples; pinning riders makes the card a wall of text that gets ignored |
| 2026-08-12 | Editor layout: Internal Feature checkbox right-aligned on the Name row; Core Mechanic right-aligned beneath it (Source row); Tags shares the prerequisite row | Feature form's main work is modifiers -- metadata must not tax vertical space |

### Prerequisite-gate observation (2026-08-12; NO decision taken)

While eyeballing chunk 1, James noticed some features (e.g. Shadow's Careful
Observation) lack the Add Prerequisite dropdown. Diagnosis: pre-existing
behavior, not a chunk-1 regression. The editor gates on a per-feature
canHavePrerequisites flag that only the class editor's plain "Feature"
authoring path sets; prefab clones, pasted features and ability-wrapping
features never get it. Prerequisite EVALUATION never checks the flag. A fix
offering prerequisites on every plain CharacterFeature was committed
(e2029e99) then REVERTED (838348e2) -- James was asking why, not requesting
a change. Open question if it ever matters: what the gate SHOULD be; likely
a lead-dev (David) question since the behavior predates this project.

## Rollout follow-ups

- Once feature metadata ships: update the implement-content skill and/or
  pattern docs so AI-implemented content sets the new metadata -- internal
  flag on plumbing features (especially monsters), coreMechanic where
  applicable, and mode tags on hero-facing content (James 2026-08-12).
- Editor copy as shipped: checkbox "Internal Feature" / "Core Mechanic"
  (signed tooltips), tag row "Tags:" + "Add Tag..." (James 2026-08-12).
  Known collision: feat-choice editor also labels feat tags "Tags:".

## Open questions

- Game-mode state confirmed registered at Draw Steel Core Rules/
  MCDMInitiativeQueue.lua:62-81 (exploration/combat/respite/downtime) --
  wire-up details at implementation.
- Retainers: check an example echelon-4 retainer sheet before deciding they
  need chips (expected: no).
- James to supply Heroes + Monsters book references for the bulk sweep.
- [COPY] items collected for implementation sign-off: internal checkbox +
  tooltip (signed), core checkbox + tooltip (signed), grant-line copy,
  "Unavailable based on choices" group name, "Manage Titles" button label,
  override marking copy, chip labels.
- New-panel-UI inspiration review: the new tac panel design language
  (STYLE_GUIDE row grammar, chips, section headers) is the vocabulary the
  chips/sections will be built in; no design change identified beyond that
  yet.

## Evidence appendix

- Prior project record: memory project_character_sheet_redesign.md; contracts
  and tag experiment under docs/character-sheet-redesign/.
- Tag experiment (2026-07-17): 117 entries Tactician+Human; post-policy 82
  confident / 31 untagged / 4 internal / 0 unsure. Auto-derivation validated.
- Code grounding of feature model/editor/display surfaces (2026-08-12,
  Explore agent, file:line verified):
  - CharacterFeature registered at DMHub Game Rules/CharacterFeature.lua:20;
    class-level defaults :22-23; Create :28-44; OnDeserialize :46-59. NO
    existing hidden/suppress/internal flag on CharacterFeature ("hidden"
    exists on feats/subclasses/classes only). Serialization is reflective
    (__typeName + set keys) -- a new field round-trips with no schema work.
    Boolean-flag precedent: costsPoints (Class.lua:556 default-false pattern).
  - Feature editor = CharacterFeature:EditorPanel (:351-983). Row order list
    innerRows :823-830 is the single insertion point for a new metadata row;
    Implementation inline row :771-792 is the exact precedent (widget
    gui.ImplementationStatusPanel, Gui.lua:4477). Checkbox-row precedent:
    DSClassEditor.lua:1543-1573 (gui.Check writing booleans). The Copy/up/
    down/trash header in the screenshot is the per-MODIFIER card header
    (:524-654, floating nae-behavior-controls cluster :640-644).
  - Sheet Features tab (DrawSteelChararcterSheet.lua:7992+) already renders
    the FULL provenance index -- FeatureCategoriser.BuildIndex at :8641, NOT
    curated. Rows are inline expandos (description + choices + View ability),
    no popup. Free-text filter only (:8684-8712), no facet chips yet.
    "Sheet shows all book features" is thus already true today; the curated
    list lives ONLY on the tac panel.
  - Tac panel Features section (MCDMCharacterPanel.lua:6067+) uses the
    CURATED FeatureCategoriser.BuildTacIndexCached (:6441); curation logic =
    FeatureCache.lua:1806-2190 (TAC_EXCLUDED_BUCKETS, IsPassiveFeature
    :1958-1987, IsTacPanelEntry :1995-2002). FeatureChip popup :5988-6059
    with Open-on-sheet link. Replacing curation with "all book features,
    auto-expanded" means retiring/adjusting this logic.
  - Monsters: same characterFeatures array, bucketed as "trait"
    (FeatureCache.lua:1491); monster sheets show the inline ListEditor strip
    (DrawSteelChararcterSheet.lua:9011-9028). Editing and play genuinely
    share one surface, confirming the toggle need.
  - Tags precedent: ability keywords = set-of-strings on the object
    (ActivatedAbility.lua:311-336; DS display MCDMActivatedAbility.lua:
    1329-1404; registry GameSystem.abilityKeywords:153). Feat tag =
    comma-separated string with Tags()/HasTag (Feat.lua:15-40) + Multiselect
    editor (DSClassEditor.lua:495-542).
  - Core-mechanic precedent: Fury/Troubadour widgets are driven by
    CharacterModifier behavior types (growingresources, routine) + creature
    accessors + hard-coded tac sections in the TacPanel section registry
    (TACPANEL_DEFAULT_ORDER :9047-9060, RegisterSection :9084). A
    core-mechanic FLAG (surface rules prose pinned) is a new, lighter
    mechanism alongside these, not a replacement.
  - Implementation-status = the metadata-row precedent end-to-end: plain
    `implementation` number field, no registration; widget Gui.lua:4477-4573;
    list-row dot gui.ImplementationStatusIcon :4589.
- New panel UI update in latest app release: to be reviewed for inspiration.
