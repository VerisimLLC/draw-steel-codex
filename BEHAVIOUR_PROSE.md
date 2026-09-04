# Behaviour Prose Worksheet

Companion to [TRIGGERED_ABILITY_EDITOR_DESIGN.md](TRIGGERED_ABILITY_EDITOR_DESIGN.md) and [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md). This is the launch-scope enumeration for the proposed opt-in #5 (behaviour prose templates) that powers the "Then" clause of the Mechanical View's Trigger Summary.

**Your job:** review the proposed template, example rendered prose, and fallback for each behaviour. Edit freely. Status column on the right: `OK`, `EDIT`, `DEFER`, `FALLBACK` (use `FALLBACK` if you'd rather this behaviour use a bare type name than the template I proposed).

**Scope rules applied:**
- Only DS-active behaviour types. 5e-only / suppressed types listed first under "Excluded" for reference only, no prose work.
- Behaviour types grouped by prose complexity to help you batch-review. Trivial/Easy are quick passes; Recursive/Hard deserve closer read.
- Where `SummarizeBehavior()` already exists in the behaviour file, flagged as **Existing method available** -- the prose engine should prefer that method and fall through to the template only if it's missing.

**Codebase bugs flagged during enumeration** (fix alongside implementation):
- `AbilityRoutineCast.lua` registers its type id as `rouitineControl` -- typo for `routineControl`. Existing content references this typo'd id, so renaming is a migration. Flag for dev team.

**Chaining convention:** when a trigger has multiple behaviours, their prose joins with `", then "` for the last two and `", "` for earlier ones. Example: *"Deals 2d6 damage, pushes the attacker 4 squares, then applies Prone."*

**Formula-field rendering convention:** GoblinScript formula fields (damage rolls, heights, heal amounts, filter expressions) render **literally** in prose -- no evaluation. E.g. `roll = "2d6 + creature.level"` renders as `"2d6 + creature.level"`. Author wrote the formula; author can read it back.

**Complexity tiers** (from per-behaviour analysis):
- `TRIVIAL` -- no fields or fields are all enums; template is a few words
- `EASY` -- 2-4 simple fields, linear template
- `MODERATE` -- conditional phrasing based on enum / optional fields
- `RECURSIVE` -- contains nested behaviours, effects, or modifier objects; engine recurses
- `HARD` -- contains freeform GoblinScript code fields (rules, filters, macros); prose will be technical
- `IMPOSSIBLE` -- UI-driven modal behaviours with no meaningful declarative fields; use bare-type fallback

---

## Excluded from DS (5e-only, suppressed at runtime)

No prose work for any of these -- they're removed from the DS behaviour picker via `AbilityEditor.SuppressType(...)` at `Draw Steel Core Rules\MCDMRules.lua:1262-1266`. Listed here so you can verify the exclusion list matches expectations.

| Type id | Why excluded |
|---|---|
| `attack` | 5e attack-roll system; DS uses power rolls |
| `castspell` | 5e spell system; not applicable to DS |
| `contestedattack` | Replaced by `power_roll` |
| `forcedmovement` | Replaced by DS-specific movement behaviours |
| `savingthrow` | Replaced by `draw_steel_save` |

---

## TRIVIAL (7 types) -- fixed or near-fixed output

### `destroy` ("Destroy")
- **File:** `Draw Steel Ability Behaviors\AbilityDestroyCreature.lua`
- **Fields:** none
- **Existing method:** none
- **Template:** `destroys the targeted creatures`
- **Example:** *"destroys the targeted creatures"*
- **Status:** `OK`

### `fall` ("Fall")
- **File:** `Draw Steel Ability Behaviors\AbilityFall.lua`
- **Fields:** none
- **Existing method:** none
- **Template:** `forces the targets to fall`
- **Example:** *"forces the targets to fall"*
- **Status:** `OK`

### `pay_ability_cost` ("Pay Ability Cost")
- **File:** `Draw Steel Ability Behaviors\AbilityPayCost.lua`
- **Fields:** none
- **Existing method:** none
- **Template:** `pays the ability's cost`
- **Example:** *"pays the ability's cost"*
- **Status:** `OK` (debatable whether to include in Trigger Summary prose -- cost payment is bookkeeping; may read noisy)

### `raise_corpse` ("Raise Corpse")
- **File:** `Draw Steel Ability Behaviors\AbilityRaiseCorpse.lua`
- **Fields:** `restoreStamina` (boolean)
- **Existing method:** `SummarizeBehavior` returns `"Raise Corpse"` -- too terse for prose, prefer template below.
- **Template:** `raises the corpse[if restoreStamina: ' and restores their stamina']`
- **Example:** `{restoreStamina=true}` -> *"raises the corpse and restores their stamina"*
- **Status:** `OK`

### `forcedmovementloc` ("Forced Movement Origin")
- **File:** `Draw Steel Ability Behaviors\AbilityForcedMovementLoc.lua`
- **Fields:** `type` (enum: "aura")
- **Existing method:** `SummarizeBehavior` returns `"Forced Movement Origin"` -- fine.
- **Template:** `sets the forced-movement origin to the aura`
- **Example:** *"sets the forced-movement origin to the aura"*
- **Status:** `OK` (note: only "aura" mode is implemented today; template assumes it)

### `terraform_terrain` ("Terraform Terrain")
- **File:** `Draw Steel Ability Behaviors\AbilityChangeTerrain.lua`
- **Fields:** `shape` (enum: circle/square), `radius` (number), `tileid` (enum terrain id, or "none")
- **Existing method:** none
- **Template:** `paints a [shape] of radius [radius] with [tileid] terrain`
- **Example:** `{shape="circle", radius=2, tileid="grass_patch"}` -> *"paints a circle of radius 2 with grass_patch terrain"*
- **Status:** `OK` (the tile id is an internal asset key, not a display name -- may read opaque)

### `manipulate_target_locs` ("Manipulate Target Locations")
- **File:** `Draw Steel Ability Behaviors\AbilityTargetLocs.lua`
- **Fields:** `mode` (enum: floor_down / floor_up)
- **Existing method:** none
- **Template:** `shifts target locations [mode: 'down one floor' | 'up one floor']`
- **Example:** `{mode="floor_down"}` -> *"shifts target locations down one floor"*
- **Status:** `OK`

### `character_speech` ("Character Speech")
- **File:** `Draw Steel Ability Behaviors\AbilityCharacterSpeech.lua`
- **Fields:** `variations` (string list), `fallbackText` (string, optional)
- **Existing method:** none
- **Template:** `makes the creature speak`
- **Example:** *"makes the creature speak"*
- **Status:** `OK` (variation count / text probably too noisy for Trigger Summary; kept minimal)

### `create_object` ("Create Object")
- **File:** `Draw Steel Ability Behaviors\AbilityCreateObject.lua`
- **Fields:** `objectid` (asset id), `randomize` (boolean)
- **Existing method:** none
- **Template:** `spawns a [objectid][if randomize: ' with randomised appearance']`
- **Example:** `{objectid="campfire", randomize=true}` -> *"spawns a campfire with randomised appearance"*
- **Status:** `OK` (objectid is an internal asset key; may want human-readable lookup if registry supports it)

---

## EASY (5 types) -- 2-4 simple fields, linear template

### `play_sound` ("Play Sound")
- **File:** `Draw Steel Ability Behaviors\AbilityPlaySound.lua`
- **Fields:** `soundEvent` (asset id), `volume` (number 0.0-2.0), `delay` (number seconds)
- **Existing method:** none
- **Template:** `plays the [soundEvent] sound`
- **Example:** `{soundEvent="fireball_impact", volume=1.0, delay=0}` -> *"plays the fireball_impact sound"*
- **Status:** `OK` (volume/delay probably too noisy for Trigger Summary; kept minimal)

### `terraform_elevation` ("Terraform Elevation")
- **File:** `Draw Steel Ability Behaviors\AbilityChangeElevation.lua`
- **Fields:** `shape` (enum), `radius` (number), `height` (formula-string), `recalculateElevation` (boolean), `testFalling` (boolean)
- **Existing method:** none
- **Template:** `changes the elevation of a [shape] of radius [radius] by [height]`
- **Example:** `{shape="circle", radius=2, height="self.Level"}` -> *"changes the elevation of a circle of radius 2 by self.Level"*
- **Status:** `OK` (recalculateElevation / testFalling dropped from prose as implementation detail)

### `disguise` ("Disguise")
- **File:** `Draw Steel Ability Behaviors\AbilityDisguise.lua`
- **Fields:** `mode` (enum: target/bestiary), `monsterType` (conditional on bestiary), `appearanceName` (optional)
- **Existing method:** none
- **Template:** `disguises the creature as [if mode=target: 'the target' | mode=bestiary: a [monsterType]]`
- **Example:** `{mode="bestiary", monsterType="Goblin"}` -> *"disguises the creature as a Goblin"*
- **Status:** `OK`

### `setstamina` ("Set Stamina")
- **File:** `DMHub Game Rules\ActivatedAbility.lua` (base type)
- **Fields:** `roll` (formula-string)
- **Existing method:** none
- **Template:** `sets the target's stamina to [roll]`
- **Example:** `{roll="self.MaxHitpoints"}` -> *"sets the target's stamina to self.MaxHitpoints"*
- **Status:** `OK`

### `heal` ("Healing")
- **File:** `DMHub Game Rules\ActivatedAbility.lua` (base type)
- **Fields:** `roll` (formula-string)
- **Existing method:** none
- **Template:** `restores [roll] stamina to the target`
- **Example:** `{roll="2d6 + 2"}` -> *"restores 2d6 + 2 stamina to the target"*
- **Status:** `OK`

---

## MODERATE (5 types) -- conditional / enum-driven phrasing

### `damage` ("Damage")
- **File:** `Draw Steel Ability Behaviors\AbilityDamage.lua`
- **DS-visible fields:** `roll` (formula), `damageType` (string, empty=untyped), `separateRolls` (boolean), `cannotBeReduced` (boolean), `doesNotTrigger` (boolean), `titleText` (string, custom dialog title), `chatMessage` (string, custom chat message).
- **Fields on the Lua object but NOT surfaced in the DS editor** (5e leftovers, confirmed 2026-04-24): `dcsuccess`, `dc`, `magicalDamage`. `DCEditor` in `ActivatedAbilityEditor.lua:4004-4026` is a stubbed function that builds an options list and never renders it; `magicalDamage` has no editor hook. Existing migrated content may have these set but DS authors cannot edit them. **Excluded from prose template.**
- **Existing method:** `SummarizeBehavior` returns `"[roll] Damage"` -- serviceable but drops type info; prefer template.
- **Template:** `deals [roll][if damageType: ' [damageType]'] damage[if cannotBeReduced: ', ignoring resistance'][if doesNotTrigger: ', without triggering reactions']`
- **Example:** `{roll="2d6 + 2", damageType="fire"}` -> *"deals 2d6 + 2 fire damage"*
- **Example 2:** `{roll="1d10", damageType="", cannotBeReduced=true}` -> *"deals 1d10 damage, ignoring resistance"*
- **Status:** `OK` (post-edit 2026-04-24: 5e fields dropped per codebase verification)

### `opposed` ("Opposed Power Roll")
- **File:** `Draw Steel Ability Behaviors\AbilityOpposedPowerRoll.lua`
- **Fields:** `attackAttributes` (array of {attribute, skill}), `defenseAttributes` (array of {attribute, skill}), `silent` (boolean)
- **Existing method:** none
- **Template:** `makes an opposed [attackAttr][if attackSkill: ' ([attackSkill])'] vs [defenseAttr][if defenseSkill: ' ([defenseSkill])'] roll`
- **Example:** `{attackAttributes=[{attribute="mgt"}], defenseAttributes=[{attribute="mgt"}]}` -> *"makes an opposed Might vs Might roll"*
- **Example 2:** `{attackAttributes=[{attribute="agi", skill="sleight_of_hand"}], defenseAttributes=[{attribute="ins"}]}` -> *"makes an opposed Agility (Sleight of Hand) vs Instinct roll"*
- **Status:** `OK` (multi-attr arrays exist but are rare; template takes the first pair and notes if more than one)

### `draw_steel_save` ("Draw Steel Save")
- **File:** `Draw Steel Core Rules\MCDMAbilitySaveBehavior.lua`
- **Fields:** `conditionsMode` (enum: all/one), `rollMode` (enum: roll/purge), `includeProne` (boolean, optional)
- **Existing method:** `SummarizeBehavior` returns `"Save"` -- too terse.
- **Template:** `[if rollMode=roll: 'makes a save against' | rollMode=purge: 'automatically clears'] [if conditionsMode=all: 'all conditions' | conditionsMode=one: 'one chosen condition']`
- **Example:** `{conditionsMode="all", rollMode="roll"}` -> *"makes a save against all conditions"*
- **Example 2:** `{conditionsMode="one", rollMode="purge"}` -> *"automatically clears one chosen condition"*
- **Status:** `OK`

### `remember` ("Remember Value")
- **File:** `Draw Steel Ability Behaviors\AbilityMemory.lua`
- **Fields:** `memoryName` (string), `calculation` (formula-string)
- **Existing method:** `SummarizeBehavior` returns `"Remember Value"` -- too generic.
- **Template:** `stores [calculation] as [memoryName]`
- **Example:** `{memoryName="damage_dealt", calculation="self.Level * 2"}` -> *"stores self.Level * 2 as damage_dealt"*
- **Status:** `OK` (note: value is summed across targets; dropped from template for brevity)

### `modify_cast` ("Modify Cast")
- **File:** `Draw Steel Core Rules\MCDMAbilityModifyCast.lua`
- **Fields:** `paramid` (enum), `name` (string), `value` (formula-string), `description` (string)
- **Existing method:** `SummarizeBehavior` returns `"Modify Cast"` -- too generic.
- **Template:** `modifies [paramid] by [value][if name: ' ([name])']`
- **Example:** `{paramid="ability_damage", name="Bonus Damage", value="self.Level * 2"}` -> *"modifies ability_damage by self.Level * 2 (Bonus Damage)"*
- **Status:** `OK` (paramid is an internal key; consider lookup to display string if registry supports)

### `manipulate_targets` ("Manipulate Targets")
- **File:** `Draw Steel Ability Behaviors\AbilityAddNewTargets.lua`
- **Fields:** `targetMode` (enum: add/replace), `promptText` (formula-string), `allowDuplicates` (boolean), `targetingAbility` (nested ActivatedAbility)
- **Existing method:** none
- **Runtime behaviour (verified 2026-04-24):** at cast time, the behaviour clones the embedded `targetingAbility` and runs it via `ExecuteInvoke(..., "prompt", ...)` -- this opens the action-bar target picker for the **caster** (the creature that owns the trigger/ability). The caster picks the additional targets interactively, constrained by the `targetingAbility`'s range / shape / numTargets settings. Not the author.
- **Template:** `[if targetMode=add: 'prompts the caster to add' | targetMode=replace: 'prompts the caster to choose replacement'] targets`
- **Example:** `{targetMode="add"}` -> *"prompts the caster to add targets"*
- **Example 2:** `{targetMode="replace"}` -> *"prompts the caster to choose replacement targets"*
- **Status:** `OK` (post-edit 2026-04-24: "author" replaced with "caster" per runtime verification; "selected by" replaced with "prompts the caster to" to make the interactive nature explicit)

---

## RECURSIVE (7 types) -- nested behaviours, effects, or modifier objects

### `power_roll` ("Roll on Power Table")
- **File:** `Draw Steel Core Rules\MCDMAbilityRollBehavior.lua`
- **Fields:** `rule` (formula-string, may be empty); power-table tiers edited via sub-dialog, each tier contains sub-behaviours
- **Existing method:** none
- **Template:** `rolls on the power table[if rule: ' with rule [rule]']`. Then, if tiers are configured and engine can enumerate them: append `. Tier 1: [sub-behaviour prose]. Tier 2: [sub-behaviour prose]. Tier 3: [sub-behaviour prose].`
- **Example (no tiers resolved):** *"rolls on the power table"*
- **Example (with tiers):** *"rolls on the power table. Tier 1: deals 1d6 damage. Tier 2: deals 3d6 damage. Tier 3: deals 5d6 damage and pushes 2 squares."*
- **Status:** `OK` (key recursion case -- engine enumerates tier sub-behaviours and renders each with the same template set; tier unreachable/empty -> skip that clause)

### `draw_steel_command` ("Power Table Effect")
- **File:** `Draw Steel Core Rules\MCDMAbilityBehavior.lua`
- **Fields:** `rule` (formula-string, power-table rule), `promptWhenResolving` (boolean), `promptWhenResolvingText` (string)
- **Existing method:** `SummarizeBehavior` returns `"Rule: [rule]"` -- this is actually better than what the template can produce, since the rule string IS the substantive content. Prefer the existing method.
- **Template:** `resolves power-table effect: [rule]` (or fall through to `SummarizeBehavior`)
- **Example:** `{rule="Damage 2d6 force + 1d6 per tier"}` -> *"resolves power-table effect: Damage 2d6 force + 1d6 per tier"*
- **Status:** `OK` (treat this as HARD + existing method: the rule is author-written GoblinScript, so literal display is the correct approach)

### `temporary_effect` ("Ability Duration Effect")
- **File:** `Draw Steel Ability Behaviors\AbilityTemporaryEffects.lua`
- **Fields:** `name` (string), `momentaryEffect` (nested CharacterOngoingEffect), `lingerTime` (number), `instant` (boolean)
- **Existing method:** `SummarizeBehavior` returns `"Apply Ability Duration Effect"` -- too generic.
- **Template:** `applies [name][if momentaryEffect has duration: ' for [duration]']`
- **Example:** `{name="Bright Light", momentaryEffect={duration="end of turn"}}` -> *"applies Bright Light until end of turn"*
- **Status:** `OK` (nested effect object can have its own sub-prose -- engine could recurse for richer output; keeping flat for launch simplicity)

### `ongoingEffect` ("Apply Ongoing Effect")
- **File:** `DMHub Game Rules\ActivatedAbility.lua` (base type)
- **Fields:** `ongoingEffectSource` (enum), `ongoingEffectFormula` (formula-string), `repeatSave` (boolean), `hasTemporaryHitpoints` (boolean), `temporaryHitpoints` (formula-string), `stacks` (string), `inheritDuration` (boolean)
- **Existing method:** none
- **Template:** `applies [if ongoingEffectSource=specific: '[effectName]' | ongoingEffectSource=formula: 'an ongoing effect chosen by [ongoingEffectFormula]'][if repeatSave: ' (save ends)'][if hasTemporaryHitpoints: ' granting [temporaryHitpoints] temporary stamina']`
- **Effect name lookup (confirmed 2026-04-24):** engine resolves `effectid` to the effect's display name via `dmhub.GetTable("characterOngoingEffects")[effectid].name` (or equivalent). Falls back to the raw id if lookup fails (missing table, deleted effect).
- **Example:** `{ongoingEffectSource="specific", effectid="poisoned_id_123", repeatSave=true}` -> *"applies Poisoned (save ends)"*
- **Example 2:** `{ongoingEffectSource="formula", ongoingEffectFormula="Target.Keywords has 'Undead'"}` -> *"applies an ongoing effect chosen by Target.Keywords has 'Undead'"*
- **Status:** `OK` (post-edit 2026-04-24: effect name lookup elevated from "defer" to confirmed for launch)

### `aura` ("Create Aura")
- **File:** `DMHub Game Rules\ActivatedAbility.lua` (base type)
- **Fields:** `auraObject` (nested Aura with `.name`, `.radius`, `.triggers[]`)
- **Existing method:** none
- **Template:** `creates an aura [auraname] with radius [auraradius]`
- **Example:** `{auraObject={name="Protection", radius=3}}` -> *"creates an aura Protection with radius 3"*
- **Status:** OK (aura's own triggered abilities could be recursed for fuller prose, but that's likely too verbose for Trigger Summary; flat name+radius is sufficient)

### `mod_power_roll` ("Modify Power Roll")
- **File:** `Draw Steel Core Rules\MCDMAbilityModBehavior.lua`
- **Fields:** `modifier` (nested CharacterModifier with behavior="power")
- **Existing method:** none
- **Template:** `applies a power-roll modifier: [modifier.name]`
- **Example:** `{modifier={name="Bonus Damage"}}` -> *"applies a power-roll modifier: Bonus Damage"*
- **Status:** `OK`

### `augmentedability` ("Augmented Ability")
- **File:** `DMHub Game Rules\ActivatedAbility.lua` (base type, mono=true)
- **Fields:** `modifier` (nested CharacterModifier with behavior="modifyability")
- **Existing method:** none
- **Template:** `augments the ability via [modifier.name]`
- **Example:** `{modifier={name="Extended Range"}}` -> *"augments the ability via Extended Range"*
- **Status:** `OK`

---

## HARD (3 types) -- freeform GoblinScript rules; use literal display

These behaviours contain freeform GoblinScript code written by the author. Prose renders the code literally (not evaluated). Authors understand what they wrote; non-authors see the formula / rule verbatim.

### `Macro` ("Macro Execution")
- **File:** `Draw Steel Ability Behaviors\AbilityMacro.lua`
- **Fields:** `macro` (freeform DMHub command string with GoblinScript interpolation)
- **Existing method:** none
- **Template:** `executes the macro: [macro]`
- **Example:** `{macro='/say "Attack!"'}` -> *"executes the macro: /say \"Attack!\""*
- **Fallback (if literal display reads too noisy):** `executes a custom macro`
- **Status:** OK

### `recast` ("Recast Ability")
- **File:** `Draw Steel Ability Behaviors\AbilityRecastAbility.lua`
- **Fields:** `abilityFilter` (formula-string, GoblinScript boolean)
- **Existing method:** none
- **Template:** `[if abilityFilter: 'recasts an ability matching: [abilityFilter]' | else: 'recasts the last ability']`
- **Example:** `{abilityFilter="Ability.Keywords has 'Strike'"}` -> *"recasts an ability matching: Ability.Keywords has 'Strike'"*
- **Example (no filter):** *"recasts the last ability"*
- **Fallback:** `allows recasting an eligible ability`
- **Status:** `FALLBACK` (filter string may be long and read technical; fallback recommended if author-visibility isn't the goal)

### `stealAbility` ("Steal Ability")
- **File:** `Draw Steel Ability Behaviors\AbilityStealAbility.lua`
- **Fields:** `abilityFilter` (formula-string), `ongoingEffect` (id), `duration` (string), `durationUntilEndOfTurn` (boolean)
- **Existing method:** none
- **Template:** `steals an ability[if abilityFilter: ' matching [abilityFilter]'][if ongoingEffect: ' and applies [ongoingEffect]'][if durationUntilEndOfTurn: ' until end of turn' | else if duration: ' for [duration]']`
- **Example:** `{abilityFilter="Ability.Keywords has 'Spell'", ongoingEffect="enhanced_magic", durationUntilEndOfTurn=true}` -> *"steals an ability matching Ability.Keywords has 'Spell' and applies enhanced_magic until end of turn"*
- **Fallback:** `steals an ability`
- **Status:** `OK`

---

## IMPOSSIBLE (3 types) -- UI-driven modals, no declarative prose

These behaviours drive interactive UI modals with no meaningful declarative configuration. Use bare type name as prose.

### `persistenceControl` ("Persistence Control")
- **File:** `Draw Steel Ability Behaviors\AbilityPersistentCast.lua`
- **Fields:** none (UI-driven)
- **Existing method:** none
- **Template:** `prompts for a persistent-cast selection`
- **Status:** `OK`

### `recoverySelection` ("Recovery Selection")
- **File:** `Draw Steel Ability Behaviors\AbilityRecoverSelection.lua`
- **Fields:** none (UI-driven)
- **Existing method:** none
- **Template:** `prompts for a recovery selection`
- **Status:** `OK`

### `rouitineControl` ("Routine Control") -- NOTE typo'd type id
- **File:** `Draw Steel Ability Behaviors\AbilityRoutineCast.lua`
- **Fields:** none (UI-driven)
- **Existing method:** none
- **Template:** `prompts for a routine-cast selection`
- **Status:** `OK`
- **Note:** type id in the codebase is `rouitineControl` (misspelled). Renaming it is a data migration since existing content references the typo; flag for dev team separately.

### `revertloc` ("Revert Location")
- **File:** `Draw Steel Ability Behaviors\AbilityRevertLocation.lua`
- **Fields:** `distance` (number)
- **Existing method:** `SummarizeBehavior` returns `"Revert Location for [abilityname]"` -- fine, but parent-ability-dependent; prefer template.
- **Template:** `reverts targets to their prior location`
- **Example:** *"reverts targets to their prior location"*
- **Status:** ``OK`` (distance field is a search depth limit -- implementation detail, dropped from prose)

---

## ADDITIONAL DS-active types (added 2026-04-24 from real-bestiary sweep)

These seven types were missing from the original enumeration but appear heavily in real compendium content. All landed in `GoblinScriptProse.lua` alongside the original 34 templates.

### `invoke_ability` ("Invoke Ability")
- **File:** `DMHub Game Rules\AbilityInvokeAbility.lua`
- **Fields:** `customAbility` (nested ActivatedAbility), `namedAbility` (string), `standardAbility` (string), `abilityType` (enum), `targeting` (enum), `inheritRange` (bool), `invokeOnCaster` (bool)
- **Template:** `invokes [customAbility.name | namedAbility | standardAbility | "an ability"]`
- **Example:** *"invokes Relentless Free Strike"*
- **Status:** OK (real content frequently leaves the default `"Invoked Ability"` placeholder; renders verbatim because that's what the author wrote)

### `floattext` ("Float Text")
- **File:** `DMHub Game Rules\AbilityFloatText.lua`
- **Fields:** `text` (string), `color` (hex string)
- **Template:** `floats the text "[text]"`
- **Example:** *"floats the text \"Endless Knight!\""*
- **Status:** OK

### `change_initiative` ("Manipulate Combat Order")
- **File:** `DMHub Game Rules\AbilityInitiative.lua`
- **Fields:** `mode` (enum: begin_turn / ...)
- **Template:** `changes the combat order`
- **Example:** *"changes the combat order"*
- **Status:** OK (mode variations dropped for brevity; sub-options are scene-specific)

### `purge_effects` ("Purge Ongoing Effects")
- **File:** `DMHub Game Rules\AbilityPurgeEffects.lua`
- **Fields:** `conditions` (string list of condition ids; empty means purge all)
- **Template:** `[if #conditions > 0: 'purges [name1], [name2], ...' | else: 'purges ongoing effects']`
- **Example:** *"purges Grabbed, Slowed"* / *"purges ongoing effects"*
- **Status:** OK (conditions resolved via `dmhub.GetTable("charConditions")[id].name`; falls back to raw id)

### `replenish_resources` ("Replenish Resources")
- **File:** `DMHub Game Rules\AbilityReplenish.lua`
- **Fields:** `mode` (enum: replenish / expend), `resourceid` (CharacterResource id), `quantity` (formula-string)
- **Template:** `[if mode=replenish: 'restores' | mode=expend: 'expends'] [quantity] [resourceName]`
- **Example:** *"restores 2 Heroic Resource"* / *"expends 1 Malice"*
- **Status:** OK (resource name resolved via `dmhub.GetTable("characterResources")[id].name`; falls back to raw id)

### `remove_creature` ("Remove Creature")
- **File:** `DMHub Game Rules\AbilityRemoveCreature.lua`
- **Fields:** `dropsLoot` (bool), `leavesCorpse` (bool), `waitForAbilitiesToFinish` (bool), `waitForTriggers` (bool)
- **Template:** `removes the targeted creatures from play[if leavesCorpse: ', leaving a corpse']`
- **Example:** *"removes the targeted creatures from play, leaving a corpse"*
- **Status:** OK (drop loot / wait-for fields are runtime sequencing -- dropped from prose)

### `conditionriders` ("Add Condition Riders")
- **File:** `DMHub Game Rules\AbilityApplyRiders.lua`
- **Fields:** `conditionid` (id, "none" allowed), `riderid` (id, "none" allowed)
- **Template:** `adds [riderid | "a rider"] to [conditionName | "the applied condition"]`
- **Example:** *"adds fire_rider to Bleeding"*
- **Status:** OK

---

## Summary at a glance

| Bucket | Count | Notes |
|---|---|---|
| Excluded (5e) | 5 | No work. |
| Trivial | 9 | Quick review. |
| Easy | 5 | Quick review. |
| Moderate | 6 | Medium review. |
| Recursive | 7 | Close review -- engine recursion into nested behaviours / effects. |
| Hard | 3 | Freeform GoblinScript; literal display or fallback choice. |
| Impossible | 4 | Bare type-name prose; no richer output possible. |
| Additional (post-sweep) | 7 | Surfaced 2026-04-24 by real-bestiary sweep; templates landed. |
| **Total active** | **41** | |

## Launch-tier recommendation

**If shipping a tight launch prose set:** prioritise Trivial + Easy + `damage` (the single most-common behaviour by far). That's ~15 behaviour types with the highest authoring frequency, written in ~1-1.5 critical-path days. The remaining ~19 behaviours use `SummarizeBehavior` where available, bare type-name fallback otherwise -- identical to pre-launch baseline quality.

**Post-launch backfill:** Moderate and Recursive tiers. Hard stays as literal-formula display. Impossible stays as bare type names permanently.

## Summary for bake-in

Once reviewed:
1. Wire prose templates into a new `DMHub Utils\BehaviourProse.lua` module (or a method on each behaviour type, if the team prefers attaching them to the behaviour itself).
2. Update `TRIGGERED_ABILITY_EDITOR_DESIGN.md` opt-in list to add opt-in #5 for behaviour prose (currently missing), marked landed for the shipped tier.
3. File the `rouitineControl` typo for a separate migration ticket (data-carrying rename).
