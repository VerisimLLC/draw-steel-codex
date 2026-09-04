# Test Trigger Panel — Test Plan

Use this as a checklist to validate the Phase 6 Test Trigger panel against real bestiary content. Pair with a scene that has a mix of hero and monster tokens so the Caster / Subject / Attacker slots all have sensible defaults.

## Setup

1. Open a scene with **at least 3 tokens**, ideally including:
   - One hero token (for Caster when testing heroes)
   - One monster the test case is about
   - One other monster or hero, different allegiance to the caster (for Attacker auto-fill)
2. Open the compendium browser (Codex menu) and navigate to the monster listed in each row.
3. Edit the monster, find the named triggered ability under Features / Abilities, open its editor.
4. The Test Trigger pane sits at the bottom of the preview column on the right.

---

## General checklist (run once)

Tick each once before moving to per-entry testing.

- [x] Collapsed strip shows "Test Trigger" + "Not yet run" chip + "Run Test" button
- [x] Clicking Run Test expands the card; clicking Close collapses it back to the strip
- [x] Modal picker opens when a role slot is clicked; each row shows portrait + name
- [x] Selected token in the modal renders with a brighter gold border and bold name
- [x] Clicking a token in the modal closes the modal and updates the picker button
- [x] Editing the condition formula in the Trigger section auto-refreshes the Test Trigger panel (within ~0.25s, no click needed)
- [ ] Editing the condition also re-applies pre-fill — stale symbol values from the previous formula are cleared
- [x] Rollup chip in the "How This Triggers" heading aligns with the card's right border (not overhanging into the scrollbar)
- [x] Passes chip renders green, Fails chip renders orange-red
- [ ] Caster slot is hidden when the scene has exactly 1 token (auto-fills silently)
- [ ] Opening the editor with no active scene shows the "Open a map" tip

---

## Per-entry test cases

Each row has an expected default state (what the panel should show on first expand). If anything deviates, note it.

### Pass 1: First sample (entries 1-11)

| # | Monster | Ability | Trigger | Subject | Condition | Expected default | What to verify |
|---|---|---|---|---|---|---|---|
| 1 | Abyssal Hyena | Death Snap | creaturedeath | self | *(empty)* | **Passes** (no condition) | No symbol inputs. Only Caster slot if scene >1 token. Behaviour preview reads sensibly. |
| 2 | Angulotl Hopper | Toxiferous (melee) | attacked | self | `Self.Distance(Attacker) <= 1` | **Passes/Fails** depends on live token positions | Attacker role slot present. Distance() resolves against real positions. Move the Attacker token adjacent to Caster -> Passes. Move further -> Fails. |
| 3 | Angulotl Hopper | Toxiferous (grab) | inflictcondition | attacker | `Has Attacker and Condition is grabbed and Self.Distance(Attacker) <= 1` | **Depends on live positions + condition** | 3-clause AND. Pre-fill: Has Attacker=true, Condition="grabbed". Distance() is map-derived. Attribution names the FIRST failing clause. |
| 4 | Basilisk | Basilisk Venom | dealdamage | target | `Damage Type has "Poison"` | **Passes** via pre-fill | Damage Type input pre-filled to "Poison" (set membership). Target role slot present. |
| 5 | Decrepit Skeleton | Bonetrops | creaturedeath | self | *(empty)* | **Passes** | No condition; behaviour preview should describe the aura created on death. |
| 6 | Devil Jurist | Devilish Charm | attacked | triggering | *(empty)* | **Passes** | Role slot for the attacking creature shows (subject=triggering is non-self). |
| 7 | Skeleton | Arise | zerohitpoints | self | `Damage Type != "Fire" And Damage Type != "Holy"` | **Fails or Passes on blank** — known prefill gap | `!=` is not handled by prefill (no canonical satisfying value). Damage Type input stays blank. GoblinScript treats blank as non-equal, so default should Pass. Set Damage Type = "Fire" -> Fails. |
| 8 | Human Knave | I'm Your Enemy | dealdamage | other | *(empty)* + Requires Condition filter | **Passes or Fails** depending on "taunted" condition | Subject role slot (subject=other). Requires Condition checkbox affects runtime filter but the Test Trigger panel doesn't simulate that yet — flag if misleading. |
| 9 | Human Knave | Overwhelm | beginturn | enemy | `Distance(Subject) <= 1` | **Depends on live positions** | Subject role slot filtered to enemy of caster. Distance() map-function. |
| 10 | Shambling Mound | End Effect | endturn | self | *(empty)* | **Passes** | Strip should immediately show green chip on first expand. |
| 11 | Orc Godcaller | Relentless | zerohitpoints | self | *(empty)* | **Passes** | Same shape as #10; different behaviour list — verify prose renders well. |

### Pass 2: Extended coverage (entries 12-25)

| #   | Monster                  | Ability             | Trigger           | Subject       | Condition                                                                                                                                                  | Expected default                                            | What to verify                                                                                                                                                                               |
| --- | ------------------------ | ------------------- | ----------------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 12  | Orc Warleader            | Courtesy Call       | rollpower         | subject       | `Tier One`                                                                                                                                                 | **Passes** (bare boolean prefill sets Tier One = true)      | Bare boolean symbol; prefill sets it true. Subject role slot visible.                                                                                                                        |
| 13  | Minotaur                 | (Potency +1)        | useability        | self          | `Ability.Name is "charge"`                                                                                                                                 | **Passes** via prefill                                      | Pre-fill: Ability.Name = "charge". Dotted access on Ability role; verify slot surfaces correctly.                                                                                            |
| 14  | Fossil Cryptic           | Shatterstone        | useability        | (auto-target) | `Used Ability.name is "Dig"`                                                                                                                               | **Passes** via prefill                                      | Pre-fill: Used Ability.name = "Dig". Verify name capitalisation preserved.                                                                                                                   |
| 15  | Sudden Downpour          | See Through         | useability        | (auto-target) | *(empty)*                                                                                                                                                  | **Passes**                                                  | No condition. Confirms `useability` with no filter fires.                                                                                                                                    |
| 16  | Bugbear Channeler        | Catcher             | finishmove        | subject       | `((Not Friends(self, Subject)) and Path.DistanceToCreature(Self) <= 1 and path.Forced) or (Friends(self, subject) and Path.DistanceToCreature(Self) <= 1)` | **Complex** — depends on live state                         | Mixed AND/OR with parentheses. Function call `Friends()`, dotted `path.Forced`, `Path.DistanceToCreature`. Prose engine should not crash; raw fallback acceptable if patterns don't compose. |
| 17  | Orc Juggernaut           | Blood in the Water  | finishmove        | self          | `Count Nearby Creatures(100, "prone") > 0`                                                                                                                 | **Depends on scene**                                        | Function-call comparison. No prefill (function RHS unsupported by ExtractSatisfyingValues). Real token state determines pass/fail.                                                           |
| 18  | Bugbear Roughneck        | Flying Sawblade     | forcemove         | (auto-target) | `Vertical`                                                                                                                                                 | **Passes** (bare boolean)                                   | Bare-boolean prefill to true.                                                                                                                                                                |
| 19  | Gummy Ball               | Rolling             | forcemove         | (auto-target) | *(empty)*                                                                                                                                                  | **Passes**                                                  | No condition.                                                                                                                                                                                |
| 20  | War Dog Ground Commander | Final Orders        | forcemove         | subject       | (verify in YAML)                                                                                                                                           | **TBD**                                                     | Cross-check the YAML at the file path. If no formula, expect Passes.                                                                                                                         |
| 21  | Angulotl Cleaver         | (Melee reaction)    | targetwithability | subject       | `target = self and (Used Ability.Keywords has "Melee")`                                                                                                    | **Passes** if Used Ability role slot provides Melee keyword | Pre-fill: target=? and Used Ability.Keywords = {Melee=true}. Verify Keywords set input pre-fills.                                                                                            |
| 22  | Wode Elf Green Seer      | Foreseen Punishment | targetwithability | subject       | `not Subject.YourTurn`                                                                                                                                     | **Passes** via negation prefill                             | `not X` prefill sets X=false. Dotted access (Subject.YourTurn) -> pre-fill targets "YourTurn" key. May not land cleanly; flag if it doesn't.                                                 |
| 23  | Ghoul                    | Hunger              | custom            | (auto-target) | `Trigger Name = "BeginCharge"`                                                                                                                             | **Passes** via prefill                                      | Pre-fill: Trigger Name = "BeginCharge". Custom trigger id.                                                                                                                                   |
| 24  | Thorn Dragon             | Prickly Situation   | custom            | subject       | `Trigger Name = "madesaveDragonsealedThorn" and (Trigger Value >= Save Ends)`                                                                              | **Partial pre-fill**                                        | Pre-fill: Trigger Name = "madesaveDragonsealedThorn". `Trigger Value >= Save Ends` has symbol RHS; no prefill. Verify Subject role slot.                                                     |
| 25  | Divine Dragon            | Summoner is Dying   | dying             | self          | `Subject = Summoner`                                                                                                                                       | **Depends on Summoner symbol**                              | Symbol=symbol comparison (no literal). Prefill skipped. Runtime needs a summoned token scenario to test meaningfully — may fail unless scene is set up.                                      |

### Triggers with no bestiary representatives

These trigger ids have no real compendium examples. Build synthetic test cases if coverage is needed:

- `attack` — when attacking an enemy
- `kill` — when killing a creature
- `fall` — when landing from a fall
- `finishability` — after finishing an ability

Synthetic test approach: create a new ability on a throwaway monster, set the trigger, write a simple condition (`damage >= 5` or similar), verify the Test Trigger panel renders correctly.

---

## Known limitations to verify during testing

These are expected behaviors, not bugs. Flag any case where the panel behaves WORSE than described:

1. **Prefill gap for `X != Y`** — no canonical satisfying value; input stays blank. User must manually set a non-matching value to pass.
2. **Prefill gap for symbol-vs-symbol comparisons** — `Subject.Stamina < Attacker.Level` cannot derive a literal; inputs stay at defaults.
3. **Map functions (Distance, Line of Sight, Count Nearby)** — resolve against real token positions only. No input override. The Resolved Values grid currently does NOT show computed function results — known polish item.
4. **creaturelist / path / loc typed symbols** — show a "not yet supported" tip instead of an input.
5. **Requires Condition filter** — the Test Trigger panel evaluates the `conditionFormula` only. It does NOT simulate the "Requires Condition" or "When Target Despawns" runtime gates. Those fire before the condition formula at runtime but aren't part of the test.
6. **Behaviours don't actually execute** — the behaviour preview is prose-only. Nothing hits the map, tokens, or dice.

---

## Reporting format

For each failing entry, capture:

- Entry number from the tables above
- What you expected (from the "Expected default" column)
- What you observed
- Screenshot of the expanded Test Trigger card if visually wrong
- Console log if any errors appeared (MCP `get_console_log` with `pattern = "NewTriggered"` is a good starting filter)
