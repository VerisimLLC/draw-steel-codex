# Text-only class features: audit

Audit date: 2026-11-25. The audit covers the 97 top-level features in `text-only-features.json`. These are saved with no modifiers, so the class builder shows them as plain grey cards. Each feature was checked against every record of its class and subclasses in `class-builder/core-classes.js`: level tables, `Level >= N` filters, ability records, growing tables and the heroic-resource checklist. Where needed, the engine Lua was checked too.

## Summary

| Category | Count | Meaning |
|---|---|---|
| A | 50 | Already applied elsewhere |
| B | 14 | Could be built with existing blocks |
| C | 7 | Needs a new block |
| D | 25 | Narrative / not automated |
| Unsure | 1 | Unsure |
| **Total** | **97** | |

How the A count breaks down:
- 20 are Summoner circle headings: "Summoner's Dominion", "New Portfolio Minion" (x2), "8th-Level Circle Feature" and "Portfolio Champion", for each of the 4 circles. The real rule is in the record right next to the heading.
- 20 are level steps of an earlier feature: rows in heroic-resource gain tables, `when level >= N` formulas, and growing-table filters.
- 6 are built into an ability as a level-gated mode, step or table, or as a subclass ability: There For Each Other, I Can Take It, Elemental Absorption, Appeal to the Muses, Mantle of Essence and Mantle of Quintessence.
- 2 are elsewhere: Chaos Incarnate (subclass records) and Field Arsenal (a class setting, `numKits: 2`).
- 2 rest only on a note in the record and point to data this export does not contain: Become the Beast (companion templates) and Improved Umbral Form (an ongoing effect).
- 4 are applied only in part (Mantle of Quintessence, Chaos Incarnate, Psion, and the Berserker half of the Growing Ferocity 4 improvement). Their rows name the gaps.

## Data problems found along the way

- **Berserker, Growing Ferocity, 8-ferocity row:** the push-surge trigger quantity is `"2 When Level >= 4 else 1"` and its filter is only `>= 4` ferocity. At level 4 and up it gives 2 surges from 4 ferocity. Reaver and all three Null traditions check `>= 8` correctly.
- **Talent, Psion:** the checklist start-of-turn row has `1d3 + 2` at level 10, but the Clarity feature's "Start of Turn Clarity" trigger table stops at level 7.
- **Beastheart:** the other way round. The "Start of Turn Ferocity" trigger has a level-10 row `(2d ...) + 1` that the checklist lacks.
- **Null, Discipline Mastery at 12:** the row exists only as display text in the growing table; nothing applies it.
- **Elementalist level-7 mantles:** Fire, Green and Void re-grant the mantle ability without `suppressOthers` (Earth sets it), so a level-7 hero may see two copies. Green's mantle modifiers are named "Burning Ground", copied from Fire.

## Feature by feature

Level "1 (slow start, enc. N)" means a `tutoriallevel-N` lane.

### Beastheart

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Beastheart | 2 | Everyone's Best Friend | C | Needs a montage-aware reaction: once per round, raise the tier of *any* character's test while a montage is running. No Logic test or roll target covers "during a montage" or other heroes' tests. |
| Beastheart | 4 | Unleash the Beast | A | Ferocity feature > modcompanion "Adjacent to Companion Damaged" trigger: quantity table `2` (Level 1) / `3` (Level 4). The record text already says so. |
| Beastheart | 6 | Become the Beast | A | Record note: "implemented on each companion's template". The companion templates are not in core-classes.js, so this could not be checked here. |
| Beastheart/Guardian | 5 | There For Each Other | A | The Pack Defends > "+1 Ferocity" cost step: `"There For Each Other - you regain Stamina"`, `filterTarget: "Subject.Level >= 5"`, roll `Subject.Recovery Value`. |
| Beastheart/Punisher | 5 | I Can Take It | A | Thunderclap trigger (hero and companion copies): mode "I Can Take It", `condition: "Level >= 5"`, caster takes `Raw Damage * 0.5`. |

### Censor

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Censor | 10 | Templar | B | Gain a triggered ability (on using Judgment) that invokes the chosen domain's effect, with one option per domain (Choose from options or Logic on domain). The respite portal, questions and priority targets are narrative (D). |
| Censor | 4 | Wrath Beyond Wrath | A | Wrath feature > "Damage to the Judged" trigger: quantity table `1` (Level 1) / `2` (Level 4). Checklist row: `"1 + 1 when level >= 4"`. |
| Censor/Oracle | 5 | Prophecy | C | Needs a "stored rolls" pool: bank 2d10 results when Victories are earned, then a free triggered action replaces any nearby power roll's dice total with the next banked roll. |
| Censor/Paragon | 8 | Vow | D | Oath enforcement is roleplay. |

### Conduit

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Conduit | 10 | Avatar | B | Prayers is a choice with `numChoices: 1`; a level-10 Choose from options (2 more prayers) adds the extra prayers. Gain an ability (maneuver) activates a domain effect. The respite portal is narrative (D). |
| Conduit | 3 | Minor Miracle | D | Respite ritual to raise the dead; Recovery cost at respite end is table bookkeeping. |
| Conduit | 4 | Blessed Domain | A | Every domain's piety trigger has the +1 built in: e.g. Death/Fate/Knowledge/Life/Love/Sun/War `"2 + 1 when level >= 4"`, Creation/Trickery `"3 when level >= 4 else 2"`, Nature/Protection/Storm `"2 + 1 when level >=4"`. |

### Elementalist

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Elementalist | 4 | Font of Essence | A | Triggered Essence > "Creature Takes Typed Damage": `quantity "2 when level >= 4 else 1"`. The same formula is in the checklist. |
| Elementalist | 4 | Mantle of Essence | A | Each specialization's level-4 record (Quaking Earth / Burning Grounds / Flowering Bed / Veiling Bed) is an activated aura with `filterCondition "Heroic Resources Available to Spend >=3"`. |
| Elementalist | 6 | Wyrding | D | Out-of-combat freeform utility magic. |
| Elementalist | 7 | Mantle of Quintessence | A | Each specialization's level-7 record re-grants the mantle ability without the essence filter (Earth also sets `suppressOthers`). The patience bonus and Handle Animals edge are only text: B to finish (Aura > Edge on tests, Handle Animals, with Logic on Victories >= 5 for a double edge). |
| Elementalist/Fire | 3 | A Conversation with Fire | D | Remote conversation through a fire. |
| Elementalist/Green | 8 | Chimeric Manifestation | C | Needs a block that merges two shapeshift forms: both forms' benefits, the higher speed, all movement types, level sum 12 or less. Disciple of the Green is a single-form activated ability. |
| Elementalist/Green | 1 (slow start, enc. 1) | It Is the Soul Which Hears | D | Speaking with animals and plants is narrative. Using Reason instead of Presence on influence tests would need a characteristic-swap block (C). |
| Elementalist/Void | 3 | Distance Is Only Memory | D | Respite travel portal. |

### Fury

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Fury | 10 | Chaos Incarnate | A | Berserker and Reaver each have a level-10 "Chaos Incarnate" record with 7 resistance modifiers (`dr: "Might*2"`). The text says the Stormwight version is in the Stormwight kits (not in this export). The frightened effect and the "spend up to 3 ferocity for surges on Primordial Strike" part are not applied anywhere (B: Add to an ability / Extra surges for a cost). |
| Fury | 10 | Growing Ferocity Improvement | A | Berserker/Reaver Growing Ferocity: `filterCondition "Level >= 10 and Heroic Resources This Turn >= 12"` (Vuken forced-movement bonus, Boren 10 temporary Stamina) plus a growing-table row with level 10 and 12 ferocity. Stormwight's rows are in its kits (not checked). |
| Fury | 10 | Primordial Ferocity | A | Ferocity feature take-damage trigger (`losehitpoints`): quantity table 1 / 2 (Level 4) / 3 (Level 10); same in the checklist "Take Damage". |
| Fury | 4 | Damaging Ferocity | A | Same take-damage table: `{"script": "2", "threshold": 4}`. |
| Fury | 4 | Growing Ferocity Improvement | A | Growing-table row with level 4 and 8 ferocity; push-surge trigger quantity. Reaver: `"2 When Level >= 4 and Heroic Resources This Turn >= 8 else 1"`. **Berserker bug:** `"2 When Level >= 4 else 1"` has no `>= 8` check, so it gives 2 surges from 4 ferocity. |
| Fury | 4 | Primordial Attunement | D | Sensing immunities and elemental sources is information for the player (a reveal block could do it, but nothing tracks it now). |
| Fury | 6 | Primordial Portal | D | Travel portals to Quintessence. |
| Fury | 7 | Greater Ferocity | A | Ferocity "Start of Turn Ferocity" trigger table: `(1d ...) + 1` at threshold 7; the checklist has the same. |
| Fury | 7 | Growing Ferocity Improvement | A | Berserker/Reaver Growing Ferocity: `filterCondition "Heroic Resources This Turn >= 10 and level >= 7"` (double edge) plus a growing-table row with level 7 and 10 ferocity. |
| Fury | 9 | Harbinger of the Primordial Chaos | D | Respite activity that creates a portal source. |
| Fury/Stormwight | 3 | Nature’s Knight | D | Speaking with animals, sensing creatures and Renown in negotiation are not tracked by the hero (the Negotiation panel does not read class bonuses). |
| Fury/Stormwight | 5 | Stormborn | B | The "use Blessing of Fortunate Weather" half can copy the working Storm Domain record (Censor/Conduit 1st-level "Blessing of Fortunate Weather" activated ability with weather aura) as Gain an ability. The weather immunity aura is mostly narrative. |
| Fury/Stormwight | 5 | Blessing of Fortunate Weather | B | Gain an ability: copy the Storm Domain "Blessing of Fortunate Weather" activated ability (weather options, aura that gives edges on Search/Navigate/Hide/Endurance/Track). |

### Null

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Null | 10 | Discipline Mastery Improvement | B | The level 10, 12-discipline row appears only as display text in each tradition's growing table; no modifier checks `>= 12` in any Null record. Logic (Level >= 10, most resource this turn >= 12): Forced movement bonus +Intuition, plus Gain a triggered ability (use a heroic ability: 10 temporary Stamina). |
| Null | 10 | Manifold Resonance | B | Logic (Null Field active) > Aura > Edge or bane: banes ignored on power rolls. The 1 discipline usable only for Psi Boost needs a new restricted-resource block (C). The respite teleport is narrative. |
| Null | 4 | Discipline Mastery Improvement | A | Each tradition's 8-row triggers: `"2 when Heroic Resources This Turn >= 8 and level >= 4 else 1"` (Chronokinetic, Cryokinetic x2, Metakinetic x2), plus a growing-table row with level 4 and 8 discipline. |
| Null | 4 | Enhanced Null Field | C | Needs a block that removes or suppresses supernatural terrain/aura effects of your level or lower where your aura overlaps them. (The Null Field ongoing effect is not in this export; check there first.) |
| Null | 4 | Regenerative Field | A | Discipline feature trigger (enemy in Null Field uses a main action): `quantity "2 when level >= 4 else 1"`; same in the checklist. |
| Null | 6 | Elemental Absorption | A | Inertial Shield > `triggerBefore` "Elemental Absorption": `conditionFormula "Level >= 6"`, 7 damage reductions of `Intuition`. |
| Null | 7 | Discipline Mastery Improvement | A | Each tradition's `filterCondition "Heroic Resources This Turn >= 10 and level >= 7"` (double edge) plus a growing-table row with level 7 and 10 discipline. |
| Null/Disciple of the Chronokinetic | 2 | Rapid Processing | D | Reading speed and an extra respite activity are downtime bookkeeping. |
| Null/Disciple of the Cryokinetic | 8 | Synaptic Triage | B | Gain an ability: free maneuver, cost 1d6 Stamina, remove one effect from self and chosen creatures in the Null Field area. |
| Null/Disciple of the Metakinetic | 8 | Inertial Dampener | B | Logic (Null Field active) > Aura (chosen creatures) > Change a stat: stability + Intuition, plus Gain a triggered ability (when force moved: psychic damage equal to Intuition to the mover). |

### Shadow

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Shadow | 10 | Death Pool | A | Insight "Deal Damage with Surge" trigger table: 1 / 2 (Level 4) / 3 (Level 10); same in the checklist. |
| Shadow | 10 | Improved Umbral Form | A | Record note: "Implemented within Umbral Form Ongoing Effect" (effect `1143575d...`). The effect's contents are not in this export, so this could not be checked here. |
| Shadow | 4 | Keep It Down | D | Conversational secrecy. |
| Shadow | 4 | Surge of Insight | A | Same surge trigger table: `{"script": "2", "threshold": 4}`. |
| Shadow | 7 | Keen Insight | A | "Start of Turn (Insight)" trigger table: `+ 1` at threshold 7; same in the checklist. |
| Shadow | 7 | Ventriloquist | D | Voice throwing is narrative. |

### Summoner

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Summoner | 10 | No Matter the Cost | Unsure | **Unsure.** The note says it is in the "Essence Minion Death trigger", but that trigger only grants `Essence from Minion Death` and has no level-10 logic. Sacrifice runs through the standard ability "Summoner Sacrifice Minions" (MCDMCharacterPanel.lua), which is not in this export. Check that ability. |
| Summoner | 4 | Minion Chain | B | Add to an ability (Minion Bridge, maneuver): extra step letting each minion within Summoner's Range shift up to its speed first. The ladder/rope chain is narrative. |
| Summoner | 6 | Minion Machinations | D | Followers (the record's own note: the Codex does not limit followers). |
| Summoner | 9 | Steward of Two Worlds | D | Negotiation patience with manifold natives: the Negotiation panel does not read class bonuses. |
| Summoner | 1 (slow start, enc. 1) | Minions Outside of Combat | C | Needs an out-of-combat rule: summon up to 4 minions with no essence cost, gated by Victories versus the minion's cost. Minion tasks are narrative. |
| Summoner | 1 (slow start, enc. 1) | Essence Outside of Combat | C | Needs a block for "essence costs are waived outside combat, each ability once until a Victory or respite"; no cost-waiver block exists. |
| Summoner | 1 (slow start, enc. 3) | Summoner Abilities | D | Section heading text with no rule. |
| Summoner | 1 (slow start, enc. 3) | Heroic Abilities | D | Section heading text with no rule. |
| Summoner/Circle of Blight | 2 | Summoner’s Dominion | A | Heading for the sibling level-2 record "Demon Portfolio Fixture" (activated ability). |
| Summoner/Circle of Blight | 2 | New Portfolio Minion | A | Heading for the sibling "Demon Portfolio 5-Essence Minion" choice (3 options, each with a modifier). |
| Summoner/Circle of Blight | 5 | New Portfolio Minion | A | Heading for the sibling "Demon Portfolio 7-Essence Minion" choice (3 options, each with a modifier). |
| Summoner/Circle of Blight | 8 | 8th-Level Circle Feature | A | Heading for the sibling level-8 record "Abyssal Evolution" (activated, trigger, triggerdisplay). |
| Summoner/Circle of Blight | 8 | Portfolio Champion | A | Heading for the sibling "Demon Portfolio Champion" (attribute); the champion is summoned through the class's 9-Essence choice. |
| Summoner/Circle of Blight | 1 (slow start, enc. 3) | Soulsense | D | Soul-trail tracking is exploration narrative. |
| Summoner/Circle of Graves | 2 | Summoner's Dominion | A | Heading for the sibling "Undead Portfolio Fixture" (activated ability). |
| Summoner/Circle of Graves | 2 | New Portfolio Minion | A | Heading for the sibling "Undead Portfolio 5-Essence Minion" choice. |
| Summoner/Circle of Graves | 5 | New Portfolio Minion | A | Heading for the sibling "Undead Portfolio 7-Essence Minion" choice. |
| Summoner/Circle of Graves | 8 | 8th-Level Circle Feature | A | Heading for the sibling level-8 record "Kill the Pain" (attribute). |
| Summoner/Circle of Graves | 8 | Portfolio Champion | A | Heading for the sibling "Undead Portfolio Champion" (attribute). |
| Summoner/Circle of Spring | 2 | Summoner's Dominion | A | Heading for the sibling "Fey Portfolio Fixture" (activated ability). |
| Summoner/Circle of Spring | 2 | New Portfolio Minion | A | Heading for the sibling "Fey Portfolio 5-Essence Minion" choice. |
| Summoner/Circle of Spring | 5 | New Portfolio Minion | A | Heading for the sibling "Fey Portfolio 7-Essence Minion" choice. |
| Summoner/Circle of Spring | 8 | 8th-Level Circle Feature | A | Heading for the sibling level-8 record "Celestial Grace" (resource, modifytrigger). |
| Summoner/Circle of Spring | 8 | Portfolio Champion | A | Heading for the sibling "Fey Portfolio Champion" (attribute). |
| Summoner/Circle of Storms | 2 | Summoner's Dominion | A | Heading for the sibling "Elemental Portfolio Fixture" (activated ability). |
| Summoner/Circle of Storms | 2 | New Portfolio Minion | A | Heading for the sibling "Elemental Portfolio 5-Essence Minion" choice. |
| Summoner/Circle of Storms | 5 | New Portfolio Minion | A | Heading for the sibling "Elemental Portfolio 7-Essence Minion" choice. |
| Summoner/Circle of Storms | 8 | 8th-Level Circle Feature | A | Heading for the sibling level-8 record "Control the Elements" (modifyability). |
| Summoner/Circle of Storms | 8 | Portfolio Champion | A | Heading for the sibling "Elemental Portfolio Champion" (attribute). |
| Summoner/Circle of Storms | 1 (slow start, enc. 3) | Heart of Nature | B | Change the outcome: "can't have a tier 1 outcome" on Intuition tests, offered (not automatic) when dealing with elementals or dragons, the same pattern as Fury's Mighty Leaps. The sensing part is narrative. |

### Tactician

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Tactician | 10 | Warmaster | B | Roll differently: ability rolls use 3d10 keep 2 (`replaceroll` `"3d10k2"`, as in Berserker "Strongest There Is"), offered when the target is marked by you; wrap it in an Aura for allies. The "allies' heroic abilities cost 2 less" part needs a cost-reduction block (C). |
| Tactician | 4 | Focus on Their Weaknesses | A | Focus "Marked Takes Damage" trigger: `quantity "2 when Level >= 4 else 1"`; checklist `"1 + 1 when level >= 4"`. |
| Tactician | 1 (slow start, enc. 1) | Field Arsenal | A | Tactician class record has `numKits: 2` (class editor "Has Two Kits", MCDMClass.lua); MCDMCustomRules.lua `CombinedKit` / `Kit.DamageBonusSelected` handle picking between matching bonuses. |
| Tactician/Insurgent | 1 (slow start, enc. 1) | Covert Operations | B | Aura (allies) > Edge or bane: edge on tests with intrigue skills. Lead assisting is a reminder. |
| Tactician/Vanguard | 1 (slow start, enc. 1) | Imposing Attitude | D | Renown +2 in negotiations and a double edge to stop combat. The Negotiation panel does not read class bonuses; the edge could be a Reminder text or an offered Edge on tests. |

### Talent

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Talent | 10 | Clear Mind | A | Clarity "Forced Movement (Clarity)" trigger table: 1 / 2 (Level 4) / 3 (Level 10); same in the checklist. |
| Talent | 10 | Psion | A | Partial. The checklist has `1d3 + 2` at threshold 10, but the Clarity "Start of Turn Clarity" trigger table stops at threshold 7. Mismatch to fix. Not applied: the Strain Damage trigger is `mandatory: true` with no level-10 opt-out, and there is no "take strained effects while unstrained" option (C). |
| Talent | 7 | Lucid Mind | A | Clarity "Start of Turn Clarity" trigger table: `+ 1` at threshold 7; same in the checklist. |
| Talent/Chronopathy | 2 | Ease the Hours | D | Montage round limits are run by the Director or encounter script. |
| Talent/Chronopathy | 8 | Doubling the Hours | D | Extra respite activity. |
| Talent/Telepathy | 5 | Compulsion | D | Truthful answer from an NPC. |
| Talent/Telepathy | 8 | Universal Connection | D | Telepathy range across a world. |

### Troubadour

| Class | Level | Feature | Cat. | Evidence / how |
|---|---|---|---|---|
| Troubadour | 1 | Scene Partner | D | NPC bonds and negotiation patience/interest: the Negotiation panel does not read class bonuses. |
| Troubadour | 10 | Dramaturgy | B | Logic (Level >= 10) adds +1 to the appeal gain on the Start of Turn Drama trigger (or a row in its appeal table). Change an ability (Performance keyword): distance becomes line of effect across the map. Unsure whether appeal table `fea8816d` already has this; its rows are not in the export. |
| Troubadour | 10 | Greatest of All Time | B | Gain a triggered ability (you succeed on a test) > allies within 3 gain an effect: an edge on their next test. The NPC Impression reduction is negotiation bookkeeping (D). |
| Troubadour | 2 | Appeal to the Muses | A | Drama > "Start of Turn Drama" rolls adventure table `fea8816d...` when `Level >= 2` (versus `0fd2f4bc...` at Level 1), the same pattern as the Conduit's prayer table. The table rows are not in the export. |
| Troubadour/Auteur | 3 | Missed Cue | D | The Director removes a creature until round 2, once per 3 Victories. |
| Troubadour/Duelist | 8 | Masterwork | C | Needs a "pick one of your existing signature abilities" choice that then changes it (edge plus a surge for that ability only, and it stays available when the kit changes). Change an ability cannot let the player pick which ability. |

## Common patterns (and what they suggest for the editor)

1. **Improvement features that are level steps of an earlier feature (20).** Examples: "gain 2 instead of 1" (Damaging Ferocity, Wrath Beyond Wrath, Font of Essence, Regenerative Field, Surge of Insight, Focus on Their Weaknesses, Clear Mind, Blessed Domain), "1d3 + 1 instead of 1d3" (Greater Ferocity, Keen Insight, Lucid Mind) and "Growing Ferocity/Discipline Mastery Improvement". The number lives in a Level table row (`threshold: 4/7/10`), a `"... when level >= 4"` formula, or a growing-table row on the class or subclass. *Editor idea:* let a text card link to the table row or formula that applies it, show "applied by: Ferocity > Take Damage, Level 4 row", and flag mismatches between the checklist and the trigger (see the Psion and Beastheart problems).
2. **Upgrades built into an ability as a level-gated mode or step (6).** There For Each Other, I Can Take It, Elemental Absorption and Appeal to the Muses each sit inside the base ability as a mode or step with a `Level >= N` condition, or as a level-switched table. Mantle of Essence and Mantle of Quintessence sit in each subclass's activated aura. *Editor idea:* the same "applied by" link, pointing into the ability.
3. **Heading cards whose rule is the sibling record (20 Summoner circle cards, plus 2 Summoner section intros counted as D).** *Editor idea:* treat a text-only card followed by a record that carries the real rule as a heading, and fold the two together or mark it "see next card".
4. **Claimed but not visible in the export (3).** Become the Beast, Improved Umbral Form and No Matter the Cost point at companion templates, an ongoing effect or a standard ability. *Editor idea:* allow links to records outside the class (effects, standard abilities, companion templates).
5. **Buildable "while in my aura / for my allies" rules (B).** These are Aura or Logic (Null Field active) around Change a stat or an Edge or bane block: Inertial Dampener, Covert Operations, Manifold Resonance and Warmaster. Blessing of Fortunate Weather and Stormborn can copy the existing Storm Domain record.
6. **Recurring gaps that need new blocks (C).** Montage-aware effects (Everyone's Best Friend; Ease the Hours too, if montages are ever automated), cost changes (outside-combat essence waiver, allies paying less in Warmaster), "pick one of your existing abilities" (Masterwork), stored or banked rolls (Prophecy), merging two shapeshift forms (Chimeric Manifestation) and suppressing terrain effects (Enhanced Null Field).
7. **Negotiation bonuses (patience, Renown, Impression) are a cluster of D items:** Scene Partner, Steward of Two Worlds, Imposing Attitude, Nature's Knight, Greatest of All Time and part of Mantle of Quintessence. The Negotiation panel (`Draw Steel V/NegotiationScene.lua`) only adds language bonuses and does not read hero features. A "negotiation bonus" block would move all of these from D to B.
8. **Pure narrative (25 D):** respite and downtime activities, travel portals, communication and senses. A Reminder text block is all that fits.
