# Block editors: review of everything proposed (2026-11-25)

Five independent reviewers read the designs, plans, prototypes and Lua mockups and checked them
against the codex: modularity of the Lua plan, engine and data correctness, Lua UI feasibility,
design consistency, and the prototypes as reference code. Their key claims were re-checked
before writing this up (marked **verified**). Nothing here has been fixed yet.

**Verdict.** The core idea holds: blocks as a view over the engine's own records, declared beside
the game types, saved back by claims. But the plan is not ready to build from. The registries sit
in the wrong module, three plan documents disagree, the two prototypes save back in two different
ways, and a few saves are wrong at the table today.

Documents: IMPL = `BLOCK_EDITOR_IMPLEMENTATION_PLAN.md`, CODING = `BLOCK_EDITOR_CODING_PLAN.md`,
FW = `BLOCK_EDITOR_FRAMEWORK.md`, CLASS = `CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md`,
ABILITY = `ABILITY_BLOCKS_DESIGN.md`.

## 0. Fixed in the prototypes (2026-11-25)

The save bugs were fixed in the HTML prototypes so the reference the Lua port copies is right.
Checked by `ui-mockup/tests/run.js` (nine tests, all passing; see section 6 for the invariants).

| Item | Fix |
|---|---|
| B1 usage limits | Ability and trigger blocks write `usageLimitOptions` inside the ability or trigger, keyed by the modifier's guid (new blocks get one), and read the limit from there first. A saved `resourceid` is kept (some core records share one counter), and records that keep the limit only inside stay that way. |
| Gain limits | Every gain trigger, the start-of-turn one included, carries its once-per-round or once-per-encounter limit; changing only "how often" rewrites both the checklist mode and the trigger's limit. |
| Missing checklist mode | Read as once per encounter, as the game reads it. |
| Gain amounts | New and edited gains write the amount as core content does (a formula, or a level table when it grows), so level steps read back. |
| B5 stamina and levels | A Stamina formula the editor can't split is kept and shown whole; unchanged class fields write back verbatim; saved levels 11-20 are kept; no empty levels are added. |
| Surges reader | Uses its own `base` instead of a hard-coded "surges", and leaves "and (A) or (B)" alone. The wrong "spent together" hint is gone. |
| "Who" menu | Adds "another creature" (the engine's `other`). |
| Only if | The audit's allow-list: no slot opens and no menu item is offered where the game ignores the condition (kit access...), and an existing one is flagged in the checks. `modcaptain`/`modrider` stay off until F2. |
| Combining | Keeps `rollRequirement` and the characteristic. |
| Growing tables | A saved row level of 1 stays 1; a table with its own condition opens as an advanced block (kept exactly). |
| Opening menus | The formula picker no longer writes to the block, and "unchanged" checks ignore UI-only state, so opening a picker never marks a block as edited. |
| B3 ability editor | A changed step merges each of its records with the saved record it came from (three-way, as the class builder does), not only single-record steps. With every step forced through the edited path, 1,006 of 1,019 core abilities now save back identical (was 581); unchanged saves are 1,015 of 1,019. The 13 left are steps the reader shows as one block although the saved records differ (e.g. a "spend extra Ferocity" step saved as a command behaviour): a reader-precision issue for the port. |

Still open from this review: B2, B4, B6, B7, B8 and section 2's design and Lua UI items.

**Update 2026-11-26.** Decided and written into the ledger and plans: B2 (registries on `Block`,
declared beside the types; implementation plan section 2), B7 (the ledger is authoritative; the
coding plan is marked historical; the plans agree), B8 (the duplicate half of the class proposal
is removed), the palette and a glyph on every block (plan section 13), "Advanced editor" as the one
name, undo/redo with uploads (plan section 12), keyboard (mouse-first with a word list). The
shelf keeps colour for blocks that don't fit (dashed outline), and stays on the right except on
phones. B4 (a GoblinScript parser instead of regexes) and B6 (the drag ghost) are phase-0 work in
the plan. Phasing and rollout were decided on 2026-11-26 (implementation plan section 7).

## 1. Blockers

| # | Issue | Evidence | Fix |
|---|---|---|---|
| B1 | **"Usable N times per round/encounter" is not enforced.** The editor writes `resourceRefreshType` and `numCharges` on the modifier, but the game reads `usageLimitOptions` on the ability or trigger; only the old editor's change handler copies it there. All 33 core triggers with a limit carry both. A "once per round" ability or reaction built in the editor can be used any number of times. **Verified.** | app.js:890-893, 464, 467; CharacterModifier.lua:2061-2065; ActivatedAbility.lua:2675; TriggeredAbility.lua:2039 | Write `usageLimitOptions = {resourceRefreshType, charges, resourceid = modifier guid}` too, and read it back. |
| B2 | **The registries are in the UI module, which loads last.** IMPL puts `RegisterHost`/`RegisterArea` and every host in `Block Editor/`, so adding a host means editing the editor; CODING instead registers in `DMHub Game Rules`, where `RegisterGameType("BlockEditor")` in the UI mod would later wipe it. | IMPL:62, 65-66, 76; CODING:141, 144 | Put every data registry on the `Block` global in `DMHub Utils/Block.lua` (no gui): `Block.RegisterHost/Group/Wrapper/Recipe/Test/Trigger`, keyed by id, replace on re-register, gathered when an editor opens. The UI module only reads them (plus `RegisterSlotWidget`). Declare hosts beside their types; drop `Hosts.lua`, `Areas.lua` and per-area `*Detail.lua` (THC's split is right for a builder with fixed screens, not for an extensible editor). |
| B3 | **The two prototypes save back differently.** The class builder merges by claims; the ability editor compares fingerprints, replaces multi-record steps outright (losing unknown fields) and `Object.assign` brings back fields the author cleared. | app.js:1301-1318; importer.js:174-183; ability-blocks-stack.html:1538-1556, 1613-1631 | One Lua save-back module built on claims; behaviours declare claims like modifiers do. |
| B4 | **Formulas are compared with regexes, and tests never read back.** Every reader turns a saved condition into a raw formula; `condParts` sorts on top-level `and`, so `A and B or C` equals `B or C and A`; `norm` turns `(a) or (b)` into `a) or (b`; `readGainEvent` ignores its own `base`. | importer.js:20, 27, 146-147, 158, 250, 394, 413-418 | Compare syntax trees with one GoblinScript parser (the ability editor already has one: html 814-1076); `Block.RegisterTest{toScript, fromAst, prose}`; no formula regexes in the port. |
| B5 | **An unusual stamina formula is broken on save.** If the hit-points regex fails, the reader keeps the raw text and the compiler writes `"<raw> + (Level - 1)*"`. Also, the class always writes 20 levels, so saved levels 11+ lose their features. **Verified.** Core classes don't hit it, so the all-class tests passed. | importer.js:315, 323; app.js:1502, 1505-1506 | A raw-formula mode, an "unchanged, write back verbatim" path for the class record itself, and only write lanes the editor shows. |
| B6 | **Drag from the shelf can't reach the drop slots as drawn.** The engine finds targets under the *dragged panel*, so a `dragMove = false` row never touches a slot. **Verified** (the inventory code says so). | HeroSheetInventoryActions.lua:1208-1210; Panel.lua:230 | In `beginDrag` make a small floating ghost and `element:transferDragTo(ghost)` (DockablePanel.lua:1524 does this); engine ask E2 may be unnecessary. |
| B7 | **Three plan documents contradict each other** (phases, rollout setting vs routing, host API shape, "claims" meaning two things, editor state as a game type or not, colours as tokens vs fixed). FW calls itself the source of truth but has no 2026-11-25 entries. | FW D10:484; CODING §9, 191, 509-552, 616, 659; IMPL:74, 112-115, 150, 179-180 | Make FW's ledger the one record; add the 11-25 decisions; mark superseded sections; retire CODING or mark it historical. |
| B8 | **CLASS has sections 13-28 twice.** The second copy (lines 1156-1565) is older and still describes "link existing" subclasses, which were removed; sections 29-31 follow it. **Verified.** CODING:565 also still plans "Link existing". | CLASS:742-1155 vs 1156-1565 | Delete the second copy; strike "Link existing" from CODING. |

## 2. Important

**Engine and data**
- **Gain lines: the trigger still fires when the checklist says no.** The checklist mode limits the amount (AbilityReplenish.lua:349-367) but the trigger runs: with automated gains off, players are prompted for 0, and an advanced gain's other steps run every time. Changing only "how often" rewrites the checklist mode but not the trigger's saved limit (importer.js:436, 451). Fix: write `usageLimitOptions` to match the mode; rewrite both on any change.
- **A missing checklist mode is read as "Whenever"; the engine treats it as once per encounter** (importer.js:393 vs AbilityReplenish.lua:358). Affects all 12 Conduit domain lines. Fix: default to "encounter".
- **"Spends surges" also fires on lost or hand-edited surges**, and a retainer's spend through `ConsumeResource` fires on the mentor; a roll option that costs surges spends separately, so one roll can raise two events (Resource.lua:876-889, 1012-1017; CharacterModifier.lua:3724-3732). Engine side: flagged as F15. The editor's hint "one roll's surges are spent together" is wrong and should go.
- **"Only if" is offered around every block** in the prototype; there is no `supportsFilter` check (app.js:2139, 1340). `kitaccess` ignores it (MCDMCustomRules.lua:126-133). The audit also marks `granttreasure`, `light` (partly) and `monstermodes`, `invisibility` (unsafe). Fix: the audit's allow-list in the editor; engine gaps flagged as F16. `modcaptain`/`modrider` are `true` in the audit but gaps in F2: set them to false until F2 is fixed.
- **Compile/read mismatches**: new gains write a `when/else` amount, edited ones a table (app.js:1489 vs importer.js:437); growing-table level `1` read vs `0` written; filtered growing tables never match; combining drops `rollRequirement` (`ROLL_OPT_KEYS`, app.js:941); `rollCombo` claims `attribute` but never writes it; `mergeSrc` always drops a block's name/description.
- **Opening a menu marks a block as edited**: `fillFx` and some render functions change the model (app.js:192, 443, 887, 914), so an untouched block goes down the merge path. Rendering must not change the model.
- **Trigger lists disagree between the editors**, including the direction of `forcemove` ("force move a creature" vs "are force moved"; the engine says "Force Moved"). Take ids, wording and symbols from `TriggeredAbility.RegisterTrigger`; give triggers a registration family (none of the plans has one). Subject `other` (Beastheart, Tactician, Death) is missing from the gain menu's "who".

**Lua UI**
- **A block-sized "Drop here" slot changes layout mid-drag** and can flicker. Work out the insertion point from cached block midpoints with a little hysteresis; keep slivers 2px (zero-area panels can't be hovered); give them priority above the global `drag-target` rule (DefaultStyles.lua:2526-2548); add auto-scroll near the edges.
- **An inline block colour kills hover and selected states** (inline beats styles). One local rule per block group with a literal hex and a precomputed hover hex; "selected" as a `boxShadow` ring. Theme-tinted children inside fixed-colour blocks (icon buttons, chips) need white overrides or they go dark-on-dark in light schemes.
- **Link words have no hover style of their own**: swap the label text on `hoverLink`/`dehoverLink` (HistoryCard.lua:883-897) without changing text width; labels need a raycast background for `press` to fire. Popups at the word: `popupPositioning = "mouse"`. The ability mockup's "swaps this link region for a gui.Input in place" is wrong: it is a popup.
- **Keyboard access to words has no engine support** (no keydown; link regions can't take focus). Ship mouse-first with a focusable "words in this block" list per block, and raise an engine ask. This conflicts with the 2026-11-24 accessibility rule until then.
- **Width and font size**: three fixed columns can't live in the 364px dock and won't scale with Font Size. Open the editors full-screen or as a modal with a minimum width; size rows in `em`/`sp`.
- **Panel counts**: about 6 panels a block; one level section is ~300, all levels side by side 2,500-3,000. Make cards direct children of the scroll panel for `hideObjectsOutOfScroll`; edit text in place, never rebuild a stack.

**Design**
- **Colour is the only cue for block kind**, though ABILITY D7 and FW §6 promise glyphs or group names. Several hues are near-identical, and pink #d0679e under white text is 3.4:1 (fails AA). Add a group glyph or short label on every block and shelf row.
- **The two prototypes use different palettes** (resources #8a6a20 vs #9a6d1c; purple means "roll change" in one and "power roll" in the other; tests and potency share a colour). One `BlockColors` table keyed by meaning, checked for contrast and colour blindness.
- **How the editor is reached is decided three ways** (alongside, an alternative view behind a setting, or routing), and the old editor is called "full editor" in one and "Advanced editor" in the other. Which editor "Build the trigger yourself..." opens is unstated.
- **Undo is open in IMPL 9.3 but decided in ABILITY and "must build" in CODING**; class and subclass saves are separate uploads, so undo across tabs is undefined.
- **New decisions aren't written down**: the 9-event gain menu (only an app.js comment; it holds both "spends surges" and "spends a resource", which save to the same trigger), shelf in full colour (the ability shelf still greys out blocks that don't fit), shelf on the right (both prototypes still move it below the stack under 760px).
- **Designed features with no phase**: paste text and the Steel Compendium import, card rewording, the scope banner, quick fixes, recipes, and the keyboard path.
- **Hard-coded knowledge to turn into registrations** in the port: the block catalog, claims, readers, defaults, roll and edge lists, gain and trigger lists, test facts, limits/aura/forced-move/kit lists, resource guids, colours and usage counts. Full table in the prototype reviewer's notes, summarised in CODING's registration section once updated.

## 3. Minor

- IMPL cited `dmhub.SetAndUploadObject`, which does not exist; it is `SetAndUploadTableItem` (Definitions/dmhub.lua:676). **Verified; fixed in the plan 2026-11-26.** The root CLAUDE.md and docs/ named the same wrong function; fixed 2026-11-26.
- IMPL uploads on every save; CODING defers the upload until the author leaves the record. Pick one.
- Line references drifted in IMPL/CODING (MainPanel.lua:770, RegisterType, TypeInfo, testGs) and in FOLLOW_UP F3-F5 (corrected there).
- Wording differs between the editors: "+ add step" / "+ add what it does" / "+ add a block"; Remove vs Delete; load order "after Core Rules" vs "after Draw Steel UI"; prototypes use the Unicode ellipsis, Lua text must be ASCII.
- "Automatically selected when [empty test]" saves `""`, which means never; flag it as a problem.
- New "start of combat" gains leave out the core content's `Victories > 0` condition.
- Testing: IMPL dropped CODING's gate G6 ("a second developer adds a block by editing only that type's file") and the plain-Lua tests of `Block.lua`. G6 is the direct test of the modularity requirement; bring it back.
- Typing: ~15 `BE*` game types each need `@class`/`new` annotations; plain tables with `@class` are lighter, since nothing is saved. Block text declared on the rules side is outside the UIText checker.

## 4. What is solid

- Blocks as a view over the existing records, with no migration and the old editors kept as the fallback.
- Declaring blocks inside the `TypeInfo` literals beside each modifier type (verified open tables).
- Claims-based read-back that writes only what the author changed; every core class and subclass opens and saves back unchanged.
- The host interface modelled on `HeroBuilderHost`, with the host passed per controller.
- The rule that the editor knows no block, modifier, behaviour or choice id, enforced by a grep.
- Most of the mockups are buildable: link labels, dashed borders, gradients, popups, context menus, multiselect chips, a drag ghost via `transferDragTo`, fixed colours in a local style table.

## 5. Decisions for the owner

1. **Registries:** all data registries in `DMHub Utils/Block.lua`, hosts declared beside their types, no host-specific UI files (recommended).
2. **One authoritative plan:** FW's ledger, with CODING retired or marked historical.
3. **Palette:** one table keyed by meaning, contrast-checked, plus a glyph or group label on every block.
4. **Reaching the editor:** route vs alongside; one name for the old editor; which trigger editor the advanced gain opens.
5. **Undo:** an editor-owned snapshot stack per tab with redo (recommended), and what happens across class and subclass tabs.
6. **Keyboard:** ship mouse-first with a per-block word list, plus an engine ask; or block the release on it.
7. **Phases** for paste/import, card rewording, recipes storage and the keyboard path.

## 6. Suggested order

1. Fix the prototypes' save bugs (B1, B5, gain limits, missing mode, `rollRequirement`, mutating renders) and add the round-trip invariants below, so the reference is right before it is copied.
2. Resolve the documents (B7, B8, the new decisions in the ledger).
3. Re-plan the module around `Block.*` registries (B2) and one save-back (B3) with a parser (B4).
4. Prove the drag ghost and slot hit-testing in the UI harness (B6) before building blocks on it.

**Minimum invariants for the Lua port:** untouched save is byte-identical for every core class,
subclass and ability; compile -> read -> compile is stable per block; editing one block keeps every
field it doesn't claim and removes a cleared claimed one; opening and closing any menu leaves the
block unchanged; formula comparison handles mixed and/or and brackets; every trigger and modifier id
in the compendium has wording; combine and uncombine keep every roll option.
