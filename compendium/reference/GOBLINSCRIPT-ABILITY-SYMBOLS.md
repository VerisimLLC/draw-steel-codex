# GoblinScript Symbols: Non-Creature Types

This document catalogs all GoblinScript symbols available on non-creature types
in the Draw Steel Codex. For creature symbols, see the creature/character lookup
tables in `DMHub Game Rules/Creature.lua` and `Draw Steel Core Rules/MCDMCreature.lua`.

---

## ActivatedAbility (datatype: "ability")

Symbols available when referencing an ability object in GoblinScript (e.g., `Ability.Name`,
`Ability.Keywords`).

### Base Symbols (DMHub Game Rules/ActivatedAbility.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `name` | text | The name of the ability. |
| `action` | text | The name of the action resource this ability consumes. |
| `self` | ability | The ability itself. |
| `spell` | boolean | True for abilities that are spells. |
| `freestrike` | boolean | Whether this is a free strike (categorized as "Basic Attack"). |
| `usableasfreestrike` | boolean | Whether this ability can be used as a free strike. |
| `usableassignatureability` | boolean | Whether this ability can be used as a signature ability. |
| `remainhidden` | boolean | Whether creature should remain hidden when using this ability. |
| `level` | number | The level of the spell. 0 for non-spells. |
| `cantrip` | boolean | True for spells at level 0. |
| `school` | text | The school of the spell, if any. |
| `keywords` | set | The keywords the ability has. Example: `Ability.Keywords Has 'Fire'` |
| `numberoftargets` | number | The number of targets this ability targets. |
| `range` | number | The range of this ability, in feet. |
| `weaponattack` | boolean | True for abilities that include a weapon attack. |
| `hasattack` | boolean | True for abilities that include an attack. |
| `hasheal` | boolean | True for abilities that include healing. |
| `attack` | attack | The attack this ability uses (only valid if Has Attack is true). |
| `damagetypes` | set | The set of damage types this ability can inflict. Example: `Ability.Damage Types Has "Fire"` |
| `inflicts` | function | Returns whether this ability inflicts a given condition. Example: `Ability.Inflicts("Frightened")` |

**File:** `DMHub Game Rules/ActivatedAbility.lua` (lines 4696-4989)

### Casting-Context Symbols (available during ability execution)

These symbols are available in the `helpCasting` table, accessible while an ability
is being cast.

| Symbol | Type | Description |
|--------|------|-------------|
| `charges` | number | Number of charges used (for multi-charge abilities). Example: `1d6 + 2*charges` |
| `mode` | number | Which mode the player chose (1-indexed). Always 1 for non-modal abilities. |
| `cast` | spellcast | Information about what has happened while casting (see ActivatedAbilityCast below). |
| `invoker` | creature | The creature that caused this ability to be invoked (only valid for invoked abilities). |

**File:** `DMHub Game Rules/ActivatedAbility.lua` (lines 4849-4871)

### Draw Steel Symbols (Draw Steel Core Rules/MCDMActivatedAbility.lua)

These override or extend the base symbols with Draw Steel-specific behavior.

| Symbol | Type | Description |
|--------|------|-------------|
| `keywords` | set | The keywords this ability has (Draw Steel version). Examples: `Ability.Keywords has 'Ranged'`, `Ability.Keywords has 'Attack'` |
| `doesdamage` | boolean | Whether this ability does rolled damage (checks power roll tiers for "damage" text). |
| `haspotency` | boolean | Whether this ability has potency (checks for `<` in tier text). |
| `hasforcedmovement` | boolean | Whether this ability has forced movement (checks for push/pull/slide behaviors or tier text). |
| `damagetypes` | set | The damage types this ability does (Draw Steel version, parsed from power roll tiers). |
| `action` | boolean | Is this ability an action? (Checks action resource ID) |
| `mainaction` | boolean | Returns true if this ability is a main action. (Alias for `action`) |
| `maneuver` | boolean | Returns true if this ability is a maneuver. |
| `allegiance` | string | Target allegiance for the ability. Possible values: 'ally', 'enemy', 'dead', 'all'. |

**File:** `Draw Steel Core Rules/MCDMActivatedAbility.lua` (lines 249-408)

### Additional Draw Steel Symbols (Draw Steel Core Rules/MCDMAbilityRollBehavior.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `haspotency` | boolean | Whether this ability includes potency. Example: `Ability has Potency` |

**File:** `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua` (line 613)

### Dynamic Custom Field Symbols

Custom fields defined through the `CustomFieldCollection` table ("spells" collection) are
dynamically registered as symbols on ActivatedAbility at runtime. Each custom field becomes
a symbol with its sanitized name, returning a number.

**File:** `DMHub Game Rules/ActivatedAbility.lua` (lines 4991-5030)

---

## ActivatedAbilityCast (datatype: "cast")

Symbols available on the cast object during and after ability execution. Accessed via
`Cast.DamageDealt`, `Cast.Tier`, etc.

### Base Symbols (DMHub Game Rules/ActivatedAbilityCast.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `mode` | number | The mode the ability was cast with. |
| `memory` | function | Returns a stored memory value by name. Example: `memory('Damage at Start')` |
| `firsttarget` | creature | The first target of this ability (only valid if there is at least one target). |
| `opportunityattackstriggered` | number | The number of opportunity attacks triggered while using this ability. |
| `heroicresourcesgained` | number | The amount of heroic resources gained while using this ability. |
| `numberofaddedcreatures` | number | The number of creatures added to creature lists. Example: `Number of Added Creatures > 0` |
| `creaturelistsize` | number | The number of creatures in manipulated creature lists. Example: `Creature List Size = 3` |
| `damagedealt` | number | The amount of damage dealt. Example: `Damage Dealt > 5` |
| `damageraw` | number | The raw damage (before resistance modifiers). Example: `Damage Raw > 5` |
| `damagedealtagainst` | function | Damage dealt against a specific target. Example: `Damage Dealt Against(self) > 5` |
| `damagerawagainst` | function | Raw damage against a specific target. Example: `Damage Raw Against(self) > 5` |
| `naturalroll` | number | The unmodified total of the dice rolled during the power roll. |
| `highroll` | number | The highest result of the 2d10 rolled during the power roll. |
| `lowroll` | number | The lowest result of the 2d10 rolled during the power roll. |
| `healing` | number | The amount of healing made while using this ability. |
| `healroll` | number | The healing roll made while using this ability. |
| `ability` | ability | The ability that is being cast. |
| `roll` | number | The roll made (only valid for abilities with the Roll Behavior). |
| `hastarget` | function | Returns true if this ability has the given creature as a target. |
| `targetcount` | number | The number of creatures this ability is targeting. |
| `spacesmoved` | number | The number of spaces moved while using this ability. |
| `hasprimarytarget` | boolean | True if this ability has at least one target. |
| `primarytarget` | creature | The primary (first) target of this ability. |
| `tier` | number | The tier for the result. |
| `tierfortarget` | function | Given a target, returns the tier of the result against that target. |
| `inflictedconditions` | boolean | True if this ability cast has inflicted conditions on creatures. |
| `purgedconditions` | number | The number of conditions purged by this ability cast. |
| `forcedmovementdistance` | number | The total distance of forced movement caused by this ability. |
| `forcedmovementcollision` | boolean | True if any forced movement collided with a creature or object. |
| `forcedmovementcreaturecount` | number | Number of unique creatures that were force moved (excludes resisted). |

**File:** `DMHub Game Rules/ActivatedAbilityCast.lua` (lines 52-471)

### Draw Steel Symbols (Draw Steel Core Rules/MCDMActivatedAbilityCast.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `boons` | number | The number of boons applied while using this ability. |
| `banes` | number | The number of banes applied while using this ability. |
| `passespotency` | function | Given a target, characteristic ID, and optional potency value, returns true if the creature passes the potency check. Examples: `Cast.PassesPotency(Target, "P", "Strong")`, `Cast.PassesPotency(Target, "M")` |
| `ongoingeffectspurgedchosen` | table | List of ongoing effect IDs the player chose to purge during this ability cast. |

**File:** `Draw Steel Core Rules/MCDMActivatedAbilityCast.lua` (lines 12-89)

### Draw Steel Symbols (Draw Steel Core Rules/MCDMAttack.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `highestnumberonattackdice` | number | The highest number rolled on the d6 attack dice. |

**File:** `Draw Steel Core Rules/MCDMAttack.lua` (lines 5-15)

---

## Attack (datatype: "attack")

Symbols available on attack objects, accessed via `Attack.Finesse`, `Attack.Melee`, etc.

### Base Symbols (DMHub Game Rules/Attack.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `name` | text | The name of the attack. |
| `ammo` | boolean | True if this attack uses a weapon with the "ammo" property. |
| `thrown` | boolean | True if this attack uses a weapon with the "thrown" property. |
| `finesse` | boolean | True if this attack is made with a finesse weapon. |
| `meleerange` | number | The range within which the attack is considered melee. Thrown weapons beyond this range become ranged. |
| `melee` | boolean | True if this is a melee attack. Thrown weapons count as melee. |
| `ranged` | boolean | True if this is a ranged attack. |
| `range` | number | The range of the attack in feet. |
| `spell` | boolean | True if this is a spell attack. |
| `attribute` | text | The attribute used to modify this attack. |
| `magical` | boolean | True if this attack does magical damage. |
| `damagetypes` | set | The set of damage types this attack does. Example: `Attack.Damage Types Has "Fire"` |
| `hands` | number | The number of hands used (1 or 2). Example: `Attack.Hands = 2` |
| `properties` | set | The names of any weapon properties. Example: `Attack.Properties Has "Finesse"` |
| `propertyvalue` | function | Returns the value of a given weapon property. Example: `Attack.PropertyValue("Fatal")` |

**File:** `DMHub Game Rules/Attack.lua` (lines 153-358)

---

## Equipment (datatype: "equipment")

Symbols available on equipment items.

### Base Symbols (DMHub Game Rules/Equipment.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `name` | text | Name of the item (uses base item name if available). |
| `isweapon` | boolean | True if this item is a weapon. (Always false for non-weapon equipment.) |
| `properties` | set | The names of any properties the item has. Example: `Armor.Properties Has "Heavy"` |
| `propertyvalue` | function | Returns the value of a given property. Example: `Armor.PropertyValue("CustomRuneBonus")` |

**File:** `DMHub Game Rules/Equipment.lua` (lines 600-696)

---

## Weapon (extends Equipment)

Weapons inherit all equipment symbols and add weapon-specific ones.

### Weapon Symbols (DMHub Game Rules/Equipment.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `isweapon` | boolean | Always true for weapons. |
| `finesse` | boolean | True if this weapon is a finesse weapon. |
| `melee` | boolean | True if this weapon is a melee weapon. |
| `ranged` | boolean | True if this weapon is a ranged weapon. |
| `thrown` | boolean | True if this weapon is a thrown weapon. |
| `twohanded` | boolean | True if this weapon is two-handed. |
| `heavy` | boolean | True if this weapon is a heavy weapon. |
| `simple` | boolean | True if this weapon is a Simple weapon. |
| `martial` | boolean | True if this weapon is a Martial weapon. |

**File:** `DMHub Game Rules/Equipment.lua` (lines 699-801)

---

## Kit (datatype: "kit")

Symbols available on kit objects, accessed via `Kit.Speed`, `Kit.Stamina`, etc.

### Kit Symbols (Draw Steel Core Rules/MCDMKit.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `name` | string | The name of the kit. |
| `stamina` | number | Stamina bonus from the current kit. |
| `speed` | number | Speed bonus from the current kit. |
| `distance` | number | Distance bonus from the current kit. |
| `reach` | number | Reach bonus from the current kit. |
| `area` | number | Area bonus from the current kit. |
| `disengage` | number | Disengage bonus from the current kit. |
| `stability` | number | Stability bonus from the current kit. |
| `damagebonus` | function | Damage bonus from the kit. Returns the bonus for a tier and optional type ("melee", "ranged", "supernatural"). Examples: `kit.damage bonus(1, "melee")`, `kit.damage bonus(2)` |

**File:** `Draw Steel Core Rules/MCDMKit.lua` (lines 1060-1177)

---

## Deity (datatype: "deity")

Symbols available on deity objects, accessed via `Deity.Name`, `Deity.Domains`, etc.

### Deity Symbols (Draw Steel Core Rules/MCDMDeities.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `name` | text | The name of the deity. |
| `domains` | set | The domains associated with the deity. Example: `Deity.Domains has "War"` |

Dynamic custom field symbols can also be added from the `CustomFieldCollection` table
("deities" collection) at runtime.

**File:** `Draw Steel Core Rules/MCDMDeities.lua` (lines 704-787)

---

## CharacterOngoingEffectInstance (datatype: "ongoing effect")

Symbols available on ongoing effect instances.

### Symbols (DMHub Game Rules/OngoingEffect.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `caster` | creature | The creature that cast this ongoing effect. |

**File:** `DMHub Game Rules/OngoingEffect.lua` (lines 612-649)

---

## AuraInstance (datatype: "aura")

Symbols available on aura instances.

### Symbols (DMHub Game Rules/Aura.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `caster` | creature | The creature that controls this aura. |

**File:** `DMHub Game Rules/Aura.lua` (lines 701-727)

---

## CharacterResourceCollection (datatype: "resources")

Symbols are dynamically generated from the `characterResources` data table. Each resource
registered in the game becomes a symbol whose name is the resource name with all
non-alphanumeric characters removed and lowercased.

For example, if a resource named "Heroic Resource" exists, the symbol `heroicresource`
becomes available, returning the creature's current count of that resource.

**File:** `DMHub Game Rules/Resource.lua` (lines 1047-1099)

---

## Loc (datatype: "location")

Symbols available on location objects.

### Symbols (DMHub Game Rules/BasicRules.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `x` | number | The x coordinate of the location. |
| `y` | number | The y coordinate of the location. |
| `floor` | number | The floor the location is on. |
| `valid` | boolean | True if the location is valid and within map bounds. |
| `distance` | function | Distance from another location or creature in tiles. |

**File:** `DMHub Game Rules/BasicRules.lua` (lines 171-255)

---

## CreatureSet

Symbols available on creature set objects (custom attributes that hold sets of creatures).

### Symbols (DMHub Game Rules/CustomAttribute.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `size` | number | The number of creatures in the set. |
| `highest` | function | Find the highest attribute of any creature in the set. Examples: `set.Highest('Recovery Value')`, `set.Highest('Might')` |

CreatureSet also supports `is` comparisons (checking if a creature is in the set).

**File:** `DMHub Game Rules/CustomAttribute.lua` (lines 121-170)

---

## StringSet

Symbols available on string set objects (used for keywords, damage types, domains, etc.).

### Symbols (DMHub Game Rules/CustomAttribute.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `size` | number | The number of strings in the set. |

StringSet supports `has` / `is` comparisons for membership testing (case-insensitive).

**File:** `DMHub Game Rules/CustomAttribute.lua` (lines 208-231)

---

## TierSymbols (datatype: "tier")

Symbols available on power roll tier result objects, used in triggered abilities
and power roll modifications.

### Symbols (Draw Steel Core Rules/MCDMAbilityRollBehavior.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `includesforcedmovement` | boolean | Whether this tier result includes forced movement (push/pull/slide). |
| `push` | number | The push distance in this tier result (0 if none). |
| `pull` | number | The pull distance in this tier result (0 if none). |
| `slide` | number | The slide distance in this tier result (0 if none). |

**File:** `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua` (lines 1884-1911)

---

## CharacterModifier Context Symbols

These are not symbols on a type per se, but additional context symbols available
in GoblinScript expressions within CharacterModifier formulas.

### Default Modifier Symbols (DMHub Game Rules/CharacterModifier.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `aura` | aura | The aura generating this modifier (only for aura-sourced modifiers). |
| `ongoingeffect` | ongoing effect | The ongoing effect generating this modifier (only for ongoing-effect-sourced modifiers). |
| `stacks` | number | The stack count of the ongoing effect generating this modifier. |

**File:** `DMHub Game Rules/CharacterModifier.lua` (lines 3696-3714)

### Power Roll Modifier Symbols (Draw Steel Core Rules/MCDModifyPowerRolls.lua)

Additional symbols available in power roll modification formulas:

| Symbol | Type | Description |
|--------|------|-------------|
| `ability` | ability | The ability being used for this roll. |
| `target` | creature | The creature being targeted with this ability. |
| `caster` | creature | The creature casting the ability. |
| `cast` | spellcast | The cast info for this ability. |
| `title` | text | The title of the roll. |
| `current` | creature | The current target of the power roll (for target-change modifiers). |
| `triggerer` | creature | The creature triggering this modification (for triggered modifiers). |
| `charges` | number | Number of charges used (in adjustment formulas). |

**File:** `Draw Steel Core Rules/MCDModifyPowerRolls.lua` (lines 116-137, 1200-1822)

---

## Monster (extends Creature)

Monsters inherit all creature symbols and add:

### Monster-Specific Symbols (DMHub Game Rules/Monster.lua)

| Symbol | Type | Description |
|--------|------|-------------|
| `level` | number | The spellcasting level of the monster. |
| `cr` | number | The challenge rating of the monster. |
| `challengerating` | number | The challenge rating of the monster (alias for `cr`). |

**File:** `DMHub Game Rules/Monster.lua` (lines 432-448)

---

## Notes on Symbol Registration

### RegisterGoblinScriptSymbol

The function `RegisterGoblinScriptSymbol(targetType, info)` (defined in
`DMHub Game Rules/Creature.lua` line 705) registers a symbol on a type by:
1. Normalizing the name to lowercase with spaces removed
2. Setting `targetType.lookupSymbols[id] = info.calculate`
3. Setting `targetType.helpSymbols[id] = { name, type, desc, ... }`
4. If `info.derived` is set, also registers on derived types

### GameSystem.RegisterGoblinScriptField

`GameSystem.RegisterGoblinScriptField` (defined in `DMHub Game Rules/GameSystem.lua`
line 322) delegates to `RegisterGoblinScriptSymbol`, with an optional `target` parameter
to specify which type receives the symbol (defaults to `creature`).

### Dynamic Symbols

Some types (ActivatedAbility, Deity) support dynamic custom field symbols loaded from the
`CustomFieldCollection` data table at runtime. These are registered during `refreshTables`
events and allow user-defined numeric fields.
