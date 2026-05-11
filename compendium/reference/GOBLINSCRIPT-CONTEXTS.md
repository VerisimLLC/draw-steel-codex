# GoblinScript Evaluation Contexts Reference

This document catalogs every GoblinScript evaluation site in the Draw Steel Codex
Lua codebase, grouped by the formula field name. For each context it lists:
- What the formula controls
- Which creature is the **subject** (Self) of the lookup
- What **additional symbols** are injected into the symbol table
- Key source files

---

## How Symbols Work

All GoblinScript evaluation goes through `GenerateSymbols(creature, symbolTable)` in
`DMHub Game Rules/Creature.lua:8108`. This creates a lookup function that:

1. First checks the **symbolTable** (extra symbols passed as a Lua table)
2. Then falls back to `creature.lookupSymbols[symbol]` (creature's own properties)

`creature:LookupSymbol(extraSymbols)` is a convenience wrapper that calls
`GenerateSymbols(self, extraSymbols)`.

**Subject (Self):** The creature whose `lookupSymbols` are queried. In formulas,
bare symbol names like `Level`, `Hitpoints`, `Stamina`, `Speed`, etc. resolve
against this creature. The `creature.helpSymbols` table documents all available
creature-level symbols.

**Additional Symbols:** Extra keys injected into the symbolTable parameter.
These are accessed via `SymbolName` in GoblinScript (e.g., `Target.Level`,
`Ability.Name`, `Cast.Damage Dealt`). Each additional symbol that is a creature
provides the full set of creature symbols as sub-fields.

---

## Symbol Type Reference

The following types can appear as additional symbols. Each type has its own
set of sub-fields accessible via dot notation (e.g., `Ability.Level`):

| Type | helpSymbols Location | Key Fields |
|------|---------------------|------------|
| creature | `Creature.lua:6712` | Level, Stamina, Hitpoints, Speed, Type, Subtype, Size, Altitude, all Characteristics, custom attributes, conditions, resources |
| ability | `ActivatedAbility.lua:4873` | Name, Level, Action, Spell, Keywords, Range, Number of Targets, Damage Types, Has Attack, Attack, Free Strike, Weapon Attack |
| attack | `Attack.lua:278` | Name, Finesse, Melee, Ranged, Range, Attribute, Spell, Magical, Damage Types |
| weapon | `Equipment.lua:743` | Finesse, Melee, Ranged, Thrown, Two Handed, Heavy, Martial, Simple |
| equipment | `Equipment.lua:669` | Name, Is Weapon, Properties, Property Value |
| spellcast (Cast) | `ActivatedAbilityCast.lua:52` | Mode, Damage Dealt, Damage Raw, Healing, Natural Roll, High Roll, Low Roll, Tier, Target Count, Spaces Moved, Ability, Roll, Memory, First Target, Primary Target, Inflicted Conditions |
| aura | `Aura.lua:718` | Caster |
| ongoingeffect | `OngoingEffect.lua:641` | Caster |
| resources | `Resource.lua:1052` | Dynamic -- one field per resource type (e.g., `Resources.Recoveries`) |
| path | `Creature.lua:5962` | Squares, Shift, Forced, Vertical Only, Distance to Creature |

---

## Contexts Grouped by Formula Field

### 1. filterCondition (CharacterModifier general filter)

**Purpose:** Determines if a modifier should apply at all to a creature.

**Self:** The creature the modifier is on.

**Additional Symbols:** `_tmp_symbols` from the modifier context (varies by source -- may include `aura`, `ongoingeffect`, `stacks`).

**Source:** `CharacterModifier.lua:3628`
```
ExecuteGoblinScript(self.filterCondition, creature:LookupSymbol(self:try_get("_tmp_symbols", {})), ...)
```

**Available Symbols:**
- Self (creature) -- all creature fields
- Aura (type: aura) -- if modifier comes from an aura
- Ongoing Effect (type: ongoingeffect) -- if modifier comes from an ongoing effect
- Stacks (number) -- stack count of the ongoing effect

---

### 2. value (CharacterModifier attribute modifier)

**Purpose:** Calculates the numeric value of an attribute modifier (e.g., +2 to Speed).

**Self:** The creature being modified.

**Additional Symbols:** `_tmp_symbols` from context.

**Source:** `CharacterModifier.lua:552`
```
ExecuteGoblinScript(self.value, GenerateSymbols(creature, self:try_get("_tmp_symbols")), ...)
```

**Available Symbols:**
- Self (creature)
- Aura, Ongoing Effect, Stacks (if from aura/ongoing effect)

---

### 3. activationCondition (Power Roll Modifier)

**Purpose:** Determines if a power roll modifier should activate.

**Self:** The creature making the roll.

**Additional Symbols:** Ability, Target, Title, plus modifier's own `_tmp_symbols`.

**Source:** `MCDModifyPowerRolls.lua:280-289`
```
creature:LookupSymbol(self:AppendSymbols{
    ability = GenerateSymbols(options.ability),
    target = GenerateSymbols(options.target),
    title = options.title or "",
})
```

**Available Symbols:**
- Self (creature) -- the roller
- Ability (type: ability) -- the ability being used
- Target (type: creature) -- the target creature
- Title (text) -- the title/name of the roll context
- Cast (type: spellcast) -- casting info (in displayCondition context)
- Caster (type: creature) -- in displayCondition context
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 4. displayCondition (Power Roll Modifier)

**Purpose:** Determines if a power roll modifier should even appear in the roll dialog.

**Self:** The creature making the roll.

**Additional Symbols:** Ability, Target, Caster, Cast, Title.

**Source:** `MCDModifyPowerRolls.lua:356-364`

**Available Symbols:** Same as activationCondition, plus Caster and Cast.

---

### 5. damageModifier (Power Roll Modifier)

**Purpose:** GoblinScript for extra damage to add/modify on a power roll result.

**Self:** The creature making the roll.

**Additional Symbols:** Triggerer, Target, plus modifier's `_tmp_symbols`.

**Source:** `MCDModifyPowerRolls.lua:638-646`
```
creature:LookupSymbol(self:AppendSymbols{
    triggerer = triggerer,
    target = GenerateSymbols(targetCreature),
})
```

**Available Symbols:**
- Self (creature)
- Target (type: creature)
- Triggerer (type: creature) -- if triggered by another creature
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 6. conditionFormula (TriggeredAbility)

**Purpose:** Determines whether a triggered ability should fire.

**Self:** The creature the trigger is on.

**Additional Symbols:** Trigger-specific symbols (vary by trigger type) + `subject`, `mode`.

**Source:** `TriggeredAbility.lua:826`
```
ExecuteGoblinScript(self.conditionFormula, creature:LookupSymbol(symbols), ...)
```

**Always Available Symbols:**
- Self (creature)
- Subject (creature) -- the creature the event occurred on (same as Self for self-triggers)
- Caster (creature) -- only for aura-triggered abilities
- Mode (number) -- the current mode

**Trigger-Specific Symbols (by trigger id):**

| Trigger | Additional Symbols |
|---------|--------------------|
| `losehitpoints` (Take Damage) | Damage (number), Raw Damage (number), Damage Type (text), Damage Immunity (boolean), Keywords (set), Surges (number), Edges (number), Banes (number), Attacker (creature), HasAttacker (boolean), HasAbility (boolean), Ability (ability) |
| `dealdamage` (Damage an Enemy) | Damage (number), Damage Type (text), Keywords (set), Target (creature), Surges (number), Edges (number), Banes (number), HasAbility (boolean), Ability (ability), Used Ability (ability) |
| `winded` (Become Winded) | Damage (number), Damage Type (text), Keywords (set), Attacker (creature) |
| `dying` (Become Dying) | Damage (number), Damage Type (text), Keywords (set), Attacker (creature) |
| `rollpower` (Roll Power) | Natural Roll (number), High Roll (number), Low Roll (number), Surges (number), Tier One (boolean), Tier Two (boolean), Tier Three (boolean), Ability (ability) |
| `inflictcondition` (Condition Applied) | Condition (string), Attacker (creature), Has Attacker (boolean) |
| `movethrough` (Move Through Creature) | Target (creature) |
| `leaveadjacent` (Creature Moved Away From) | Moving Creature (creature) |
| `targetwithability` (Target With Ability) | Used Ability (ability), Target (creature) |
| `useresource` (Use Resource) | Resource (string), Quantity (number) |
| `gainresource` (Gain Resource) | Resource (string), Quantity (number) |
| `useability` (Use an Ability) | Used Ability (ability), Cast (spellcast) |
| `castsignature` (Use Signature Attack or Area) | Used Ability (ability), Cast (spellcast) |
| `custom` (Custom Trigger) | Trigger Name (text), Trigger Value (number) |
| `endrespite` (End Respite) | XP Gained (number) |
| `teleport` (Teleport) | (none) |
| `gaintempstamina` (Gain Temporary Stamina) | (none) |
| `prestartturn` (Before Start of Turn) | (none) |

---

### 7. roll / damage roll (AbilityDamage, AbilityHeal, etc.)

**Purpose:** Calculates the damage or healing roll string for an ability behavior.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (from cast context), may include `target`, `cast`.

**Source (Damage):** `AbilityDamage.lua:30`, `ActivatedAbility.lua:3462`
```
dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(options.symbols or {}), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Target (creature) -- when targeting a single creature (added in healing and set-stamina contexts)
- Cast (type: spellcast) -- casting context if available in options.symbols
- Mode (number) -- the ability mode

---

### 8. targetFilter / filterTarget (ActivatedAbility target filtering)

**Purpose:** Determines if a specific creature is a valid target for an ability.

**Self:** The target creature being evaluated.

**Additional Symbols:** `caster`, `target` (itself), `ability`, and cast symbols.

**Source:** `ActivatedAbility.lua:1241`
```
ExecuteGoblinScript(filter, targetToken.properties:LookupSymbol(symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the potential target
- Caster (creature) -- the creature using the ability (via symbols)
- Ability (ability) -- in some contexts
- Cast (spellcast) -- in some contexts

Note: For `ActivatedAbility.lua:1112` (targetFilter for location), Self is the **caster**, with `target = location`.

---

### 9. numTargets (ActivatedAbility)

**Purpose:** Calculates how many targets an ability can have.

**Self:** The caster creature.

**Additional Symbols:** Cast symbols.

**Source:** `ActivatedAbility.lua:927`
```
ExecuteGoblinScript(self.numTargets, casterToken.properties:LookupSymbol(symbols))
```

**Available Symbols:**
- Self (creature) -- the caster
- Mode (number)

---

### 10. range / proximityRange / lineDistance (ActivatedAbility)

**Purpose:** Calculates the range of an ability.

**Self:** The caster creature.

**Additional Symbols:** Cast symbols.

**Source:** `ActivatedAbility.lua:888`, `MCDMActivatedAbility.lua:2599`
```
ExecuteGoblinScript(selfRange, caster:LookupSymbol(symbols))
```

**Available Symbols:**
- Self (creature) -- the caster
- Mode (number)

---

### 11. resourceNumber (ActivatedAbility / CharacterModifier)

**Purpose:** Calculates the resource cost of an ability (e.g., Heroic Resource cost).

**Self:** The caster creature.

**Additional Symbols:** `mode` (number).

**Source:** `ActivatedAbility.lua:1644`, `MCDMActivatedAbility.lua:787`
```
ExecuteGoblinScript(self.resourceNumber, casterToken.properties:LookupSymbol{mode = mode}, ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Mode (number)

---

### 12. resourceCostAmount (CharacterModifier)

**Purpose:** Calculates the resource cost for a modifier-based feature.

**Self:** The creature with the modifier.

**Additional Symbols:** `_tmp_symbols` from modifier context.

**Source:** `CharacterModifier.lua:3190-3298` (multiple sites)
```
ExecuteGoblinScript(self:try_get("resourceCostAmount", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), ...)
```

**Available Symbols:**
- Self (creature)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 13. quantity (AbilityReplenish / AbilityCreateItem)

**Purpose:** Calculates how many resources to grant or items to create.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `AbilityReplenish.lua:126`, `AbilityCreateItem.lua:43`
```
dmhub.EvalGoblinScript(self.quantity, casterToken.properties:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast (spellcast) -- if available
- Mode (number)

---

### 14. stamina (DSTemporaryHitpoints)

**Purpose:** Calculates temporary stamina to grant.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `DSTemporaryHitpoints.lua:185`
```
dmhub.EvalGoblinScript(self.stamina, casterToken.properties:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast (spellcast) -- if available
- Mode (number)

---

### 15. distance (Ability Forced Movement / Relocate)

**Purpose:** Calculates forced movement distance.

**Self:** The caster creature.

**Additional Symbols:** Cast symbols.

**Source:** `ActivatedAbility.lua:4485`
```
ExecuteGoblinScript(self.distance, casterToken.properties:LookupSymbol(symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast (spellcast) -- if available
- Target (creature) -- if available in symbols
- Mode (number)

---

### 16. stacks / temporaryHitpoints (ActivatedAbility ongoing effect application)

**Purpose:** Calculates how many stacks of a condition/effect to apply, or temp HP to grant.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `ActivatedAbility.lua:4081`, `ActivatedAbility.lua:3978`
```
dmhub.EvalGoblinScript(self.stacks, casterToken.properties:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast (spellcast)
- Target (creature) -- if available
- Mode (number)

---

### 17. dcvalue (ActivatedAbility save DC)

**Purpose:** Calculates the DC for a saving throw behavior.

**Self:** The caster creature.

**Additional Symbols:** Cast symbols.

**Source:** `ActivatedAbility.lua:722`
```
ExecuteGoblinScript(behavior.dcvalue, casterToken.properties:LookupSymbol(symbols), ...)
```

**Available Symbols:**
- Self (creature)
- Mode (number)

---

### 18. calculation (Armor Class Calculation modifier)

**Purpose:** Calculates an alternative armor class value.

**Self:** The creature being calculated.

**Additional Symbols:** `_tmp_symbols` from modifier context.

**Source:** `CharacterModifier.lua:1568`
```
ExecuteGoblinScript(modifier.calculation, symbols, ...)
```

**Available Symbols:**
- Self (creature)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 19. weaponFilterCondition (Attack Attribute modifier)

**Purpose:** Determines if an alternate attack attribute applies to a weapon.

**Self:** The creature.

**Additional Symbols:** Weapon.

**Source:** `CharacterModifier.lua:1653-1657`
```
creature:LookupSymbol{
    weapon = GenerateSymbols(weapon),
}
```

**Available Symbols:**
- Self (creature)
- Weapon (type: weapon)

---

### 20. filterRoll (Rolls Attacking Us / Damage modifier)

**Purpose:** Determines if a modifier applies to attack/damage rolls against the creature.

**Self:** The attacking creature.

**Additional Symbols:** Attack, Target (the defender).

**Source:** `CharacterModifier.lua:1392-1397`
```
self:AppendSymbols{
    attack = GenerateSymbols(attack),
    target = GenerateSymbols(defenderCreature),
}
```

**Available Symbols:**
- Self (creature) -- the attacker
- Attack (type: attack)
- Target (creature) -- the defender
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 21. modifyRoll / damageFilterCondition / filterCondition (ModifierDamageRolls)

**Purpose:** Determines if a damage modifier should apply; modifies the damage roll.

**Self:** The creature with the modifier (attacker).

**Additional Symbols:** Attack, Ability, Target, Damage Types, Have Advantage/Disadvantage, Dice Faces.

**Source:** `ModifierDamageRolls.lua:110-121`
```
self:AppendSymbols{
    attack = attackSymbols,
    ability = abilitySymbols,
    damagetypes = damageTypes,
    target = targetSymbols,
    haveadvantage = rollInfo.advantage,
    havedisadvantage = rollInfo.disadvantage,
    dicefaces = ...,
}
```

**Available Symbols:**
- Self (creature) -- the attacker
- Attack (type: attack)
- Ability (type: ability)
- Target (creature) -- the target
- Damage Types (set)
- Have Advantage (boolean)
- Have Disadvantage (boolean)
- Dice Faces (number) -- resource die faces
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 22. filter (ModifierD20Rolls condition)

**Purpose:** Determines if a d20/power roll modifier applies.

**Self:** The creature making the roll.

**Additional Symbols:** Varies by roll type.

**Source:** `ModifierD20Rolls.lua:37-55`
```
-- For attack rolls:
creature:LookupSymbol(self:AppendSymbols{
    attack = GenerateSymbols(options.attack),
    target = GenerateSymbols(options.target),
    dicefaces = ...,
})

-- For skill/save rolls:
creature:LookupSymbol(self:AppendSymbols{
    proficient = options.proficient,
    dicefaces = ...,
})
```

**Available Symbols (attack context):**
- Self (creature)
- Attack (type: attack)
- Target (creature)
- Dice Faces (number)
- Aura, Ongoing Effect, Stacks

**Available Symbols (skill/save context):**
- Self (creature)
- Proficient (boolean)
- Dice Faces (number)
- Aura, Ongoing Effect, Stacks

---

### 23. creatureFilter (Aura)

**Purpose:** Determines which creatures are affected by an aura.

**Self:** The creature entering/in the aura (potential target).

**Additional Symbols:** Caster, Target (same as Self), Aura.

**Source:** `Aura.lua:157`
```
c:LookupSymbol { caster = caster, target = c, aura = auraInstance }
```

**Available Symbols:**
- Self (creature) -- creature entering the aura
- Caster (creature) -- the aura controller
- Target (creature) -- same as Self (synonym)
- Aura (type: aura)

---

### 24. conditionFormula / radius (ModifierAura)

**Purpose:** Determines if an aura should be active; calculates aura radius.

**Self:** The creature with the aura.

**Additional Symbols:** `_tmp_symbols` from modifier context.

**Source:** `ModifierAura.lua:14`, `ModifierAura.lua:42`
```
GenerateSymbols(creature, modifier:try_get("_tmp_symbols"))
```

**Available Symbols:**
- Self (creature)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 25. sustainFormula (Condition / Ongoing Effect)

**Purpose:** Determines if a condition/ongoing effect continues to apply. Returns false/0 to end.

**Self:** The creature the condition is on.

**Source:** `Creature.lua:4480`, `Creature.lua:4507`
```
ExecuteGoblinScript(conditionInfo.sustainFormula, GenerateSymbols(self), ...)
```

**Available Symbols:**
- Self (creature)

---

### 26. maxInstancesFormula (Condition)

**Purpose:** Maximum instances of a condition from a single caster.

**Self:** The caster creature (applying the condition).

**Source:** `Creature.lua:6370`
```
ExecuteGoblinScript(conditionInfo.maxInstancesFormula, casterToken.properties:LookupSymbol{}, ...)
```

**Available Symbols:**
- Self (creature) -- the caster

---

### 27. hitpointsCalculation (MCDMCreature)

**Purpose:** Calculates base stamina (hit points) for a creature.

**Self:** The creature.

**Source:** `MCDMCreature.lua:2395`
```
ExecuteGoblinScript(c.hitpointsCalculation, self:LookupSymbol {}, ...)
```

**Available Symbols:**
- Self (creature)

---

### 28. prerequisite (Feat / Complication / Subclass)

**Purpose:** Determines if a character meets the prerequisites for a feat, complication, or subclass.

**Self:** The creature being evaluated.

**Source:** `MCDMCharacterBuilder.lua:512`, `CharComplicationChoice.lua:87`, `Class.lua:1062`
```
ExecuteGoblinScript(choice.prerequisite, g_creature:LookupSymbol(), ...)
```

**Available Symbols:**
- Self (creature)

---

### 29. filter (MCDMPrerequisite)

**Purpose:** Generic prerequisite filter on a creature.

**Self:** The creature.

**Source:** `MCDMPrerequisite.lua:150`
```
ExecuteGoblinScript(self:try_get("filter", ""), creature:LookupSymbol(), ...)
```

**Available Symbols:**
- Self (creature)

---

### 30. filterAbility / filterTarget (ModifierModifyAbilities)

**Purpose:** Determines if a modifier should modify a specific ability; filters targets.

**Self:** The creature with the modifier.

**Additional Symbols:** Ability.

**Source:** `ModifierModifyAbilities.lua:496`
```
modifier._tmp_symbols.ability = GenerateSymbols(ability)
ExecuteGoblinScript(modifier.filterAbility, GenerateSymbols(creature, modifier._tmp_symbols), ...)
```

**Available Symbols:**
- Self (creature)
- Ability (type: ability)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 31. abilityFilter (DSSuppressAbilities)

**Purpose:** Determines if an ability should be suppressed.

**Self:** The creature with the modifier.

**Additional Symbols:** Ability.

**Source:** `DSSuppressAbilities.lua:132-133`
```
creature:LookupSymbol{ability = ability}
```

**Available Symbols:**
- Self (creature)
- Ability (type: ability)

---

### 32. filter (ModifierFilter -- target filter for modifiers)

**Purpose:** Filters whether a modifier's effects apply to a specific target.

**Self:** The target creature.

**Additional Symbols:** From modifier context symbols.

**Source:** `ModifierFilter.lua:105`
```
ExecuteGoblinScript(mod.mod.filter, self:LookupSymbol(symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the target being evaluated
- Additional context symbols from the modifier

---

### 33. castingFilter / castingCostOverride / abilityTargets / targetFilter (PowerTableTriggers)

**Purpose:** Various filters and calculations for power roll table triggers.

**Self:** The triggering creature.

**Additional Symbols:** Caster, Target, Triggerer, Ability, Cast (for targetFilter).

**Source:** `PowerTableTriggers.lua:170, 180, 208, 326`

**Available Symbols (castingFilter/castingCostOverride/abilityTargets):**
- Self (creature) -- the triggering creature
- Additional trigger symbols

**Available Symbols (targetFilter):**
- Self (creature) -- the triggering creature
- Caster (creature)
- Target (creature)
- Triggerer (creature)
- Ability (ability)
- Cast (spellcast)

---

### 34. changeTargetFilter (Power Roll Retarget)

**Purpose:** Filters potential new targets for power roll retargeting.

**Self:** The triggering creature.

**Additional Symbols:** Current, Target, Triggerer, Caster.

**Source:** `MCDModifyPowerRolls.lua:1424-1527`

**Available Symbols:**
- Self (creature) -- the triggering creature
- Current (creature) -- the current target
- Target (creature) -- the potential new target
- Triggerer (creature) -- the creature triggering the modification
- Caster (creature) -- the caster of the power roll

---

### 35. height (AbilityChangeElevation)

**Purpose:** Calculates height change for an elevation ability.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `AbilityChangeElevation.lua:24`

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 36. calculation (AbilityMemory)

**Purpose:** Calculates a value to remember for later use in an ability.

**Self:** The target creature.

**Additional Symbols:** Cast context symbols.

**Source:** `AbilityMemory.lua:32`
```
ExecuteGoblinScript(self.calculation, target.token.properties:LookupSymbol(symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the target
- Cast, Mode, Caster (from cast context)

---

### 37. value (AbilityCustomTrigger)

**Purpose:** Calculates a custom trigger value.

**Self:** The target creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `AbilityCustomTrigger.lua:29`

**Available Symbols:**
- Self (creature) -- the target
- Cast, Mode (from cast context)

---

### 38. value (MCDMAbilityModifyCast)

**Purpose:** Calculates a parameter value that modifies the ability cast.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `MCDMAbilityModifyCast.lua:46`

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 39. roll (MCDMAbilityRollBehavior -- Power Table Roll)

**Purpose:** Calculates the power roll formula for a power table ability.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `MCDMAbilityRollBehavior.lua:697`
```
dmhub.EvalGoblinScript(self.roll, casterToken.properties:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 40. delay / proceedCondition (AbilityDelay)

**Purpose:** Calculates delay duration or checks if ability should proceed.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `AbilityDelay.lua:22, 36`

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 41. orderFormula (AbilityOrderTargets)

**Purpose:** Calculates an ordering value for sorting targets.

**Self:** The caster creature.

**Additional Symbols:** Cast context symbols (including target reference).

**Source:** `AbilityOrderTargets.lua:27`

**Available Symbols:**
- Self (creature) -- the caster
- Target (creature) -- the target being evaluated
- Cast, Mode (from cast context)

---

### 42. expression (AbilityCreatureSet)

**Purpose:** Evaluates to a creature object to add to a creature set.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `AbilityCreatureSet.lua:23`
```
dmhub.EvalGoblinScriptToObject(self.expression, casterToken.properties:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 43. bestiaryFilter (AbilitySummon / AbilityTransform)

**Purpose:** Filters which bestiary entries are valid for summoning/transforming.

**Self:** The caster creature.

**Additional Symbols:** `args.symbols` (cast context).

**Source:** `AbilitySummon.lua:277`, `AbilityTransform.lua:54`
```
ExecuteGoblinScript(self.bestiaryFilter, GenerateSymbols(casterToken.properties, args.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 44. numSummons (AbilitySummon)

**Purpose:** Calculates the number of creatures to summon.

**Self:** The caster creature.

**Additional Symbols:** `args.symbols` (cast context).

**Source:** `AbilitySummon.lua:249`

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 45. fromCaster (AbilityPurgeEffects)

**Purpose:** Evaluates to a creature object -- the caster whose effects should be purged.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `AbilityPurgeEffects.lua:214`
```
dmhub.EvalGoblinScriptToObject(self.fromCaster, casterToken.properties:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 46. stacksFormula (AbilityPurgeEffects)

**Purpose:** Calculates how many stacks of an effect to remove.

**Self:** The caster creature.

**Source:** `AbilityPurgeEffects.lua:412`
```
ExecuteGoblinScript(self.stacksFormula, GenerateSymbols(casterToken.properties), ...)
```

**Available Symbols:**
- Self (creature) -- the caster

---

### 47. actionNumber / maxChannel (ActivatedAbility)

**Purpose:** Calculates the action cost or max channel uses of an ability.

**Self:** The caster creature.

**Additional Symbols:** Mode.

**Source:** `ActivatedAbility.lua:1462, 1491`
```
ExecuteGoblinScript(self.actionNumber, caster:LookupSymbol(symbols or {mode = 1}), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Mode (number)

---

### 48. charges (ActivatedAbility usage limit)

**Purpose:** Calculates how many charges an ability has.

**Self:** The creature with the ability.

**Source:** `ActivatedAbility.lua:1618`
```
ExecuteGoblinScript(self.usageLimitOptions.charges, creature:LookupSymbol(), ...)
```

**Available Symbols:**
- Self (creature)

---

### 49. numCharges (CharacterModifier)

**Purpose:** Number of uses for a modifier-based feature.

**Self:** The creature with the modifier.

**Source:** `CharacterModifier.lua:108`
```
ExecuteGoblinScript(self:try_get("numCharges", "1"), creature:LookupSymbol(self:try_get("_tmp_symbols", {})), ...)
```

**Available Symbols:**
- Self (creature)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 50. numChoices / quantity (Class features)

**Purpose:** Calculates the number of choices available for a class feature.

**Self:** The creature.

**Source:** `Class.lua:801, 871, 953`
```
ExecuteGoblinScript(self.numChoices, GenerateSymbols(creature), ...)
```

**Available Symbols:**
- Self (creature)

---

### 51. baseValue (CustomAttribute)

**Purpose:** Calculates the base value of a custom attribute.

**Self:** The creature.

**Source:** `CustomAttribute.lua:321`
```
ExecuteGoblinScript(self.baseValue, GenerateSymbols(creature), ...)
```

**Available Symbols:**
- Self (creature)

---

### 52. costFormula / maxLevel (ModifierAltSpells)

**Purpose:** Calculates spell costs for alternative spellcasting.

**Self:** The creature.

**Additional Symbols:** spelllevel, spell.

**Source:** `ModifierAltSpells.lua:36`
```
creature:LookupSymbol{ spelllevel = spell.level, spell = GenerateSymbols(spell) }
```

**Available Symbols:**
- Self (creature)
- Spell Level (number)
- Spell (type: ability)

---

### 53. mode.condition (Ability/Trigger mode condition)

**Purpose:** Determines if an ability mode is available.

**Self:** The caster creature.

**Source:** `MCDMActivatedAbility.lua:1572`, `DrawSteelActionBar.lua:2762`
```
ExecuteGoblinScript(mode.condition, options.caster.properties:LookupSymbol(), ...)
```

**Available Symbols:**
- Self (creature)

---

### 54. hit / hitAppend (ActivatedAbility attack hit modifier)

**Purpose:** Calculates hit bonus for an ability's attack.

**Self:** The caster creature.

**Additional Symbols:** `options.symbols` (cast context).

**Source:** `ActivatedAbility.lua:3606`
```
dmhub.EvalGoblinScript(hit, creature:LookupSymbol(options.symbols), ...)
```

**Available Symbols:**
- Self (creature) -- the caster
- Cast, Mode (from cast context)

---

### 55. startOfTurnHeroicResource (AbilityPersistentCast)

**Purpose:** Calculates heroic resources gained at start of turn from a persistent ability.

**Self:** The caster creature.

**Source:** `AbilityPersistentCast.lua:81`
```
dmhub.EvalGoblinScript(startOfTurnHeroicResource, caster:LookupSymbol(), ...)
```

**Available Symbols:**
- Self (creature) -- the caster

---

### 56. surges / customPotency / adjustments.value (Power Roll Modifier modifiers)

**Purpose:** Calculates extra surges, custom potency, or tier adjustments.

**Self:** The creature making the roll.

**Additional Symbols:** Triggerer, Target, modifier `_tmp_symbols`.

**Source:** `MCDModifyPowerRolls.lua:717-737`
```
ExecuteGoblinScript(adjustment.value, lookupFunction, ...)
```

**Available Symbols:**
- Self (creature)
- Target (creature)
- Triggerer (creature)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 57. Spellcasting formulas (ModifierSpellcasting)

**Purpose:** Various spellcasting calculations (known cantrips, known spells, spellbook size, custom level).

**Self:** The creature.

**Source:** `ModifierSpellcasting.lua:110-134`

**Available Symbols:**
- Self (creature)

---

### 58. level / num (CharacterModifier innate spell and resource level)

**Purpose:** Calculates the level for innate spellcasting or the number of resources to grant.

**Self:** The creature.

**Source:** `CharacterModifier.lua:1951, 2371, 2378`

**Available Symbols:**
- Self (creature)
- Aura, Ongoing Effect, Stacks (from modifier context)

---

### 59. text (ModifierMovementText)

**Purpose:** String interpolation for movement description text.

**Self:** The creature.

**Source:** `ModifierMovementText.lua:56`
```
StringInterpolateGoblinScript(modifier.text, creature:LookupSymbol{...})
```

**Available Symbols:**
- Self (creature)

---

## Common "options.symbols" Contents

Many ability behavior contexts receive `options.symbols` which is built up during
ability casting. The typical contents include:

| Key | Type | Description |
|-----|------|-------------|
| `mode` | number | The mode the ability was cast with (1 = default) |
| `cast` | spellcast (via GenerateSymbols) | The ActivatedAbilityCast tracking object |
| `caster` | creature (via GenerateSymbols) | The casting creature |
| `target` | creature (via GenerateSymbols) | The current target (when iterating targets) |

---

## CharacterModifier Default Additional Symbols

All CharacterModifier formula fields get these symbols from `defaultHelpSymbols`
(`CharacterModifier.lua:3696`):

| Symbol | Type | Description |
|--------|------|-------------|
| Aura | aura | The aura generating this modifier (only for aura-sourced modifiers) |
| Ongoing Effect | ongoingeffect | The ongoing effect generating this modifier |
| Stacks | number | Stack count of the ongoing effect |

---

## Trigger Target/Filter Symbols in Action Bar

When the trigger panel evaluates power roll trigger filters during combat
(in `DrawSteelTriggerPanel.lua` and `DSActionBar.lua`), the following symbols
are constructed:

| Symbol | Type | Description |
|--------|------|-------------|
| Current | creature | The current target of the power roll |
| Triggerer | creature | The creature that triggered the event |
| Caster | creature | The caster making the power roll |
| Target | creature | The potential new/filtered target |
