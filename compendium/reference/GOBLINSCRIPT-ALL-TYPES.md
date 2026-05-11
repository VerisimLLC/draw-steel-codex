# GoblinScript Types -- Complete Reference

This document catalogs every type exposed to GoblinScript in the Draw Steel Codex,
including all fields from `helpSymbols`, `lookupSymbols`, `RegisterGoblinScriptSymbol`,
`RegisterGoblinScriptField`, and `creature.RegisterSymbol` calls.

---

## Table of Contents

1. [Creature](#creature)
2. [ActivatedAbility (Ability)](#activatedability)
3. [ActivatedAbilityCast (Cast / Spellcast)](#activatedabilitycast)
4. [Attack](#attack)
5. [Equipment](#equipment)
6. [Weapon](#weapon)
7. [Kit](#kit)
8. [Deity](#deity)
9. [CharacterOngoingEffectInstance (Ongoing Effect)](#characterongoingeffectinstance)
10. [AuraInstance (Aura)](#aurainstance)
11. [CharacterResourceCollection (Resources)](#characterresourcecollection)
12. [Loc (Location)](#loc)
13. [PathMoved (Path)](#pathmoved)
14. [CreatureSet](#creatureset)
15. [StringSet](#stringset)
16. [TierSymbols](#tiersymbols)
17. [CharacterModifier Context Symbols](#charactermodifier-context-symbols)
18. [Casting Context Symbols](#casting-context-symbols)
19. [Trigger Context Symbols](#trigger-context-symbols)
20. [Built-in Functions](#built-in-functions)

---

## Creature

**GoblinScript name:** `creature`
**Source:** `DMHub Game Rules/Creature.lua`, `Draw Steel Core Rules/MCDMCreature.lua`, `MCDMSymbols.lua`, `MCDMDeities.lua`, `AbilityPersistentCast.lua`, `MCDMRules.lua`

Creature is the primary GoblinScript type. `monster` and `character` inherit all creature symbols and override `Level` and `CR`. Attributes (Might, Agility, etc.) are registered dynamically and appear as `<attribute>` and `<attribute> Modifier`. Class levels appear as `<ClassName> Level`.

### Core Identity

| Field | Type | Description |
|-------|------|-------------|
| Self | creature | The creature this GoblinScript is running on. |
| Name | text | The monster type (e.g. Bandit, Goblin). Only valid for monsters. |
| ID | text | A unique identifier for the creature. Not human-readable. |
| Type | text | The type/ancestry (e.g. goblin, Elf, Human). |
| Subtype | text | The subtype (e.g. Goblinoid, High Elf). Empty if none. |
| Role | string | The role of the creature (e.g. "soldier", "hero", "none"). |
| Keywords | set | The keywords associated with this creature. |
| Object | boolean | True if this "creature" is actually an object. |

### Combat Status

| Field | Type | Description |
|-------|------|-------------|
| Stamina | number | Current stamina (hitpoints). |
| Maximum Stamina | number | Maximum stamina. |
| Temporary Stamina | number | Current temporary stamina. |
| Hitpoints | number | (Deprecated) Current hitpoints. Alias of Stamina. |
| Maximum Hitpoints | number | (Deprecated) Maximum hitpoints. Alias of Maximum Stamina. |
| Recovery Value | number | The recovery value of the creature. |
| Recoveries Available to Spend | number | Recoveries available, accounting for sharing (e.g. Bloodbound Band). |
| Dead | boolean | True if the creature is dead. |
| Dying | boolean | True if the creature is dying (heroes only). |
| Your Turn | boolean | True if it is this creature's turn in combat. |
| Combat Round | number | Current combat round number. 0 if not in combat. |
| Taken Turn | boolean | Has this creature taken its turn this round? |
| Taken Turn This Round | boolean | (same as Taken Turn) |
| Turn Being Chosen | boolean | Is the next initiative turn being chosen? |
| Hidden This Turn | boolean | True if the creature has hidden this turn. |
| Concealed | boolean | True if the creature is in a concealed area. |
| Bloodied | boolean | (via Winded -- see custom attributes) |

### Movement & Position

| Field | Type | Description |
|-------|------|-------------|
| Movement Speed | number | Distance the creature can move per round, in squares. |
| Moved This Turn | number | Distance moved this turn, in squares. |
| Movement Multiplier | number | Current movement multiplier. |
| Movement Type | text | Current movement type ("Walk", "Swim", "Fly", etc.). |
| Charge Distance | number | Distance moved in a straight line this turn, in squares. |
| Size | number | Creature size number (1=1T, 2=1S, 3=1M, 4=1L, 5=2, etc.). |
| Tile Size | number | Size in tiles occupied. |
| SizeWhenForceMoved | number | Effective size when being force moved. |
| Altitude | number | Altitude in tiles above ground zero. |
| AltitudeInDeciTiles | number | Altitude in tenths of a tile. |
| Height | number | Stature of the creature in tiles. |
| Distance | function | `Distance(otherCreature)` -- distance in squares to another creature. |
| InWater | boolean | True if the creature is in water (swim move type). |
| Stability | number | The stability of this creature. |
| Reach | number | The reach of the creature. |
| Weight | number | The weight of the creature. |

#### Movement Speeds (dynamically registered per movement type)

| Field | Type | Description |
|-------|------|-------------|
| Walk Speed | number | Walk speed in squares. 0 if none. |
| Fly Speed | number | Fly speed in squares. 0 if none. |
| Swim Speed | number | Swim speed in squares. 0 if none. |
| Burrow Speed | number | Burrow speed in squares. 0 if none. |
| Teleport Speed | number | Teleport speed in squares. 0 if none. |
| Climb Speed | number | Climb speed in squares. 0 if none. |

### Counting Nearby Creatures

| Field | Type | Description |
|-------|------|-------------|
| Count Nearby Enemies | function | `CountNearbyEnemies(distance, ...criteria)` -- live enemies within distance. Criteria: monster groups, feature names, "ally"/"enemy", or creature objects to exclude. |
| Count Nearby Friends | function | `CountNearbyFriends(distance, ...criteria)` -- live allies within distance. |
| Count Nearby Creatures | function | `CountNearbyCreatuers(distance, ...criteria)` -- all live creatures within distance. |
| Count Riders | function | `CountRiders(...criteria)` -- how many riders match the given criteria. |

### Attributes (Dynamically Registered)

For each characteristic (Might, Agility, Reason, Intuition, Presence):
| Field | Type | Description |
|-------|------|-------------|
| `<Attribute>` | number | The attribute score (e.g. `Might`). |
| `<Attribute> Modifier` | number | The attribute modifier (e.g. `Might Modifier`). |

### Equipment (Deprecated in Draw Steel)

| Field | Type | Description |
|-------|------|-------------|
| Weapons Wielded | number | (Deprecated) Number of weapons wielded. |
| Two Handed | boolean | (Deprecated) Wielding a two-handed weapon. |
| Has Main Hand Item | boolean | (Deprecated) Wielding an item in primary hand. |
| Has Off Hand Item | boolean | (Deprecated) Wielding an item in off hand. |
| Main Hand Item | equipment | (Deprecated) The main hand item. |
| Off Hand Item | equipment | (Deprecated) The off hand item. |
| Has Shield | boolean | (Deprecated) Has a shield. |
| Shield | equipment | (Deprecated) The shield. |
| Shield Bonus | number | (Deprecated) AC increase from shield. |
| Has Armor | boolean | (Deprecated) Wearing armor. |
| Armor | equipment | (Deprecated) The armor. |
| Light Armor | boolean | Wearing light armor. |
| Medium Armor | boolean | Wearing medium armor. |
| Heavy Armor | boolean | Wearing heavy armor. |
| Unarmored | boolean | Not wearing armor. |
| Armor Class | number | (Deprecated) Armor class. |
| Inventory Weight | number | (Deprecated) Total inventory weight. |
| Dueling | boolean | Wielding exactly one weapon in one hand. |

### Class & Level

| Field | Type | Description |
|-------|------|-------------|
| Level | number | Character level. For monsters: spellcasting level. |
| Challenge Rating / CR | number | Challenge rating. For characters: character level. |
| Proficiency Bonus | number | (Deprecated) Proficiency bonus. |
| Proficiency Modifier | number | (Deprecated) Synonym of Proficiency Bonus. |
| Multiclass | boolean | (Deprecated) Has levels in multiple classes. |
| Subclasses | set | The subclasses this character has taken. |
| `<ClassName> Level` | number | Levels in a specific class (dynamically registered per class). |

### Conditions & Effects

| Field | Type | Description |
|-------|------|-------------|
| Conditions | set | Names of conditions affecting the creature. |
| Ongoing Effects | set | Names of ongoing effects affecting the creature. |
| Stacks | function | `Stacks("effectName")` -- stacks of a named ongoing effect. |
| Condition Stacks | function | `ConditionStacks("condName")` -- stacks of a named condition. |
| ConditionCount | number | Total number of active conditions. |
| Effects Count | number | Total number of conditions + ongoing effects. |
| ConditionCaster | function | `ConditionCaster("condName")` -- creature that cast the condition. |
| Effect Caster | function | `EffectCaster("effectName", creature)` -- true if creature cast that effect. |
| CasterSet | function | `CasterSet("effectName")` -- CreatureSet of all casters of the effect. |
| SquadCaster | function | `SquadCaster("effectName")` -- squad that cast the effect. |
| SquadLiveMembers | function | `SquadLiveMembers("squadName")` -- live members in squad. |
| Condition Immunities | set | Conditions this creature is immune to. |
| Save Ends Effects | boolean | Does this creature have any save-ends effects? |
| Last Caster | creature | Last creature to cast a spell causing a saving throw on this creature. |
| Auras Affecting | set | Names of auras affecting this creature. |
| AurasCaster | function | `AurasCaster("auraName")` -- creature controlling the named aura. |
| BoundCreatures | function | `BoundCreatures("effectName")` -- CreatureSet of creatures bound by the effect. |
| BoundOngoingEffect | function | `BoundOngoingEffect(other, "effectName")` -- is this creature bound to another by the effect? |

### Resources & Actions

| Field | Type | Description |
|-------|------|-------------|
| Resources | resources | The resources collection for this creature. Access as `Resources.<ResourceName>`. |
| Heroic Resources Available to Spend | number | Heroic resources available, accounting for negative allowance. |
| Heroic Resources This Turn | number | High water mark of heroic resources this turn. |
| HeroTokens | number | Number of hero tokens the party has. |
| Malice | number | Director's current malice. |

### Summoning & Mounting

| Field | Type | Description |
|-------|------|-------------|
| Summoned | boolean | True if summoned by another creature. |
| Summoner | creature | The creature that summoned this one. |
| Mounted | boolean | True if mounted on another creature. |
| Mount | creature | The mount this creature is riding. |
| Number of Creatures Grabbed | number | Creatures currently grabbed. |

### Draw Steel-Specific

| Field | Type | Description |
|-------|------|-------------|
| Hero | boolean | True if this creature is a hero (character). |
| Player Allied | boolean | True if player-controlled or allied. |
| Retainer | boolean | True if this creature is a retainer. |
| Mentor | creature | The mentor of this retainer. |
| Minion | boolean | Is this creature a minion? |
| Captain | boolean | Is this creature a captain of a squad? |
| HasCaptain | boolean | Is this minion's squad captain alive? |
| Squad Captain | creature | The captain of this minion's squad. |
| Solo | boolean | Is this creature a solo? |
| Leader | boolean | Is this creature a leader? |
| Flanked | boolean | Is this creature currently being flanked? |
| Flanked By | function | `FlankedBy(creature1, creature2?)` -- is this creature flanked by the given creature(s)? |
| Weak | number | Weak potency (highest characteristic - 2). |
| Average | number | Average potency (highest characteristic - 1). |
| Strong | number | Strong potency (highest characteristic). |
| Highest Characteristic | number | The highest of the creature's characteristics. |
| Passes Potency | function | `PassesPotency("CharId", value)` -- does this creature pass the potency check? |
| Power Roll Bonus | number | Monster power roll bonus. Zero for heroes. |
| Victories | number | Number of victories (heroes only). |
| Kit | kit | The current kit of this creature, if any. |
| Deities | set | Deities this creature worships. |
| Domains | set | Chosen domains of the creature's deities. |
| Deity | deity | The primary deity. |
| Complications | set | Complications the creature has. |
| Magic Treasure Count | number | Number of magic treasures equipped or carried. |
| Number Dead Languages | number | Number of dead languages known. |
| Dead Languages | set | Dead languages known. |
| Immunities | function | `Immunities("damageType")` -- total immunity value for a damage type. Negative = weakness. |
| LastDamagedBy | function | `LastDamagedBy("attackerId")` -- timestamp of last damage from that attacker. |
| End Turn Timestamp | number | Timestamp when creature last ended its turn. |
| Temporary Stamina | number | Current temporary stamina. |
| AdjacentAlliesWithFeature | function | `AdjacentAlliesWithFeature("featureName")` -- count of adjacent allies with the feature. |
| Has Adjacent Enemy Other Than Us | function | `HasAdjacentEnemyOtherThanUs(self)` -- true if target has another adjacent enemy. |
| NumberOfPlayers | number | Number of players (not counting followers). |
| Game Mode | string | Current game mode: "exploration", "combat", "respite", or "downtime". |
| Taken Turn | boolean | Has this creature taken its turn this round? |
| Turn Being Chosen | boolean | Is the next turn currently being chosen? |
| Number of Persistent Abilities | number | Number of persistent abilities active. |
| Persistent Abilities | set | Names of active persistent abilities. |

### Skills & Proficiency (Deprecated in Draw Steel)

| Field | Type | Description |
|-------|------|-------------|
| Proficient | function | (Deprecated) `Proficient("name")` -- proficiency with skill/item/category. |
| Skill Modifier | function | (Deprecated) `SkillModifier("name")` -- modifier for a skill. |
| Save Modifier | function | (Deprecated) `SaveModifier("attr")` -- saving throw modifier. |
| Spell Save DC | number | (Deprecated) Spellcasting save DC. |
| Spellcasting Ability Modifier | number | (Deprecated) Spellcasting ability modifier. |
| Spellcasting Classes | number | (Deprecated) Number of spellcasting classes. |
| Languages | set | Languages this creature knows. |
| Ongoing DC | text | (Deprecated) DC of current ongoing effect. |
| Passive | text | (Deprecated) Passive modifier. |

---

## ActivatedAbility

**GoblinScript name:** `ability`
**Source:** `DMHub Game Rules/ActivatedAbility.lua`, `Draw Steel Core Rules/MCDMActivatedAbility.lua`, `MCDMAbilityRollBehavior.lua`

| Field | Type | Description |
|-------|------|-------------|
| Name | text | The name of the ability. |
| Action | text | The name of the action resource consumed. |
| Spell | boolean | True if this is a spell. |
| Free Strike | boolean | True if this is a free strike (Basic Attack categorization). |
| Usable as Free Strike | boolean | Can be used where a free strike can. |
| Usable as Signature Ability | boolean | Can be used where a signature ability can. |
| Remain Hidden | boolean | Whether the creature stays hidden when using this. |
| Level | number | The spell level. 0 for non-spells. |
| Keywords | set | The keywords the ability has. |
| Number of Targets | number | How many targets this ability targets. |
| Range | number | The range of this ability. |
| Weapon Attack | boolean | True if it includes a weapon attack. |
| Has Attack | boolean | True if it includes any attack. |
| Has Heal | boolean | True if it includes healing. |
| Attack | attack | The attack object. Only valid if Has Attack is true. |
| Damage Types | set | Damage types this ability inflicts. |
| Inflicts | function | `Inflicts("conditionName")` -- does this ability inflict the condition? |
| Does Damage | boolean | Whether this ability does rolled damage. |
| Has Potency | boolean | Whether this ability includes potency. |
| Has Forced Movement | boolean | Whether this ability has forced movement. |
| Maneuver | boolean | True if this is a maneuver. |
| Main Action | boolean | True if this is a main action. |
| Trigger | boolean | True if this ability is a triggered ability. |
| Heroic | boolean | True if this is a heroic ability. |
| HeroicResourceCost | number | Number of heroic resources it costs. |
| MaliceCost | number | Number of malice resources it costs. |
| Categorization | text | The categorization (e.g. "Signature Ability", "Heroic Ability"). |
| Allegiance | string | Target allegiance: "ally", "enemy", "dead", or "all". |
| Use as Free Strike | boolean | (Property) Can be used as a free strike. |
| Use as Signature Ability | boolean | (Property) Can be used as a signature ability. |

### Casting Context (available during ability execution)

| Field | Type | Description |
|-------|------|-------------|
| Charges | number | Number of charges used for multi-charge abilities. |
| Mode | number | The mode chosen for multi-mode abilities (1-based). |
| Cast | spellcast | The ActivatedAbilityCast object for the current casting. |
| Invoker | creature | Creature that caused invocation (for invoked abilities). |

---

## ActivatedAbilityCast

**GoblinScript name:** `spellcast` / `cast`
**Source:** `DMHub Game Rules/ActivatedAbilityCast.lua`, `Draw Steel Core Rules/MCDMActivatedAbilityCast.lua`, `MCDMAttack.lua`

| Field | Type | Description |
|-------|------|-------------|
| Mode | number | The mode the ability was cast with. |
| Memory | function | `Memory("name")` -- returns the value of a named memory. |
| First Target | creature | The first target. Only valid if there is one. |
| Opportunity Attacks Triggered | number | Number of opportunity attacks triggered. |
| Heroic Resources Gained | number | Heroic resources gained during this cast. |
| Number of Added Creatures | number | Creatures added to creature lists. |
| Creature List Size | number | Size of creature lists manipulated. |
| Damage Dealt | number | Total damage dealt. |
| Damage Raw | number | Raw damage before resistance. |
| Damage Dealt Against | function | `DamageDealtAgainst(target)` -- damage dealt to a specific target. |
| Damage Raw Against | function | `DamageRawAgainst(target)` -- raw damage to a specific target. |
| Natural Roll | number | Unmodified total of dice rolled during power roll. |
| High Roll | number | Highest d10 result from the 2d10 power roll. |
| Low Roll | number | Lowest d10 result from the 2d10 power roll. |
| Healing | number | Amount of healing done. |
| Heal Roll | number | The healing roll result. |
| Ability | ability | The ability being cast. |
| Roll | number | The roll result (for Roll Behavior abilities). |
| HasTarget | function | `HasTarget(creature)` -- true if creature is a target. |
| Target Count | number | Number of creatures targeted. |
| Spaces Moved | number | Spaces moved during the ability. |
| Has Primary Target | boolean | True if there is at least one target. |
| Primary Target | creature | The first/primary target. |
| Tier | number | The tier result. |
| Tier for Target | function | `TierForTarget(target)` -- tier result for a specific target. |
| Inflicted Conditions | boolean | True if conditions were inflicted. |
| Purged Conditions | number | Number of conditions purged. |
| Forced Movement Distance | number | Total forced movement distance caused. |
| Forced Movement Collision | boolean | True if forced movement caused a collision. |
| Forced Movement Creature Count | number | Unique creatures actually force moved. |
| Boons | number | Number of boons applied. |
| Banes | number | Number of banes applied. |
| PassesPotency | function | `PassesPotency(target, "CharId", potencyValue?)` -- does target pass potency? |
| OngoingEffectsPurgedChosen | table | List of ongoing effect IDs the player chose to purge. |
| Highest Number on Attack Dice | number | Highest number rolled on the d6 attack dice. |

---

## Attack

**GoblinScript name:** `attack`
**Source:** `DMHub Game Rules/Attack.lua`, `Draw Steel Core Rules/MCDMAttack.lua`

| Field | Type | Description |
|-------|------|-------------|
| Name | text | Name of the attack. |
| Finesse | boolean | True if made with a finesse weapon. |
| Melee Range | number | Range within which the attack is melee. |
| Melee | boolean | True if this is a melee attack. |
| Ranged | boolean | True if this is a ranged attack. |
| Range | number | Attack range in feet. |
| Attribute | text | Attribute used for this attack. |
| Spell | boolean | True if this is a spell attack. |
| Magical | boolean | True if this does magical damage. |
| Damage Types | set | Set of damage types. |
| Hands | number | Number of hands used (1 or 2). |
| Properties | set | Names of weapon properties. |
| Property Value | function | `PropertyValue("name")` -- numeric value of a property. |
| Ammo | boolean | True if this attack uses ammo. |
| Thrown | boolean | True if this is a thrown weapon attack. |

---

## Equipment

**GoblinScript name:** `equipment`
**Source:** `DMHub Game Rules/Equipment.lua`

| Field | Type | Description |
|-------|------|-------------|
| Name | text | Name of the item. |
| Is Weapon | boolean | True if this item is a weapon. |
| Properties | set | Names of item properties. |
| Property Value | function | `PropertyValue("name")` -- numeric value of a property. |

---

## Weapon

**GoblinScript name:** `weapon`
**Source:** `DMHub Game Rules/Equipment.lua`

Inherits all Equipment fields plus:

| Field | Type | Description |
|-------|------|-------------|
| Finesse | boolean | True if this is a finesse weapon. |
| Melee | boolean | True if this is a melee weapon. |
| Ranged | boolean | True if this is a ranged weapon. |
| Thrown | boolean | True if this is a thrown weapon. |
| Heavy | boolean | True if this is a heavy weapon. |
| Twohanded | boolean | True if this is a two-handed weapon. |
| Simple | boolean | True if this is a simple weapon. |
| Martial | boolean | True if this is a martial weapon. |

---

## Kit

**GoblinScript name:** `kit`
**Source:** `Draw Steel Core Rules/MCDMKit.lua`

Accessed from creature via `Kit.speed`, `Kit.Stamina`, etc.

| Field | Type | Description |
|-------|------|-------------|
| Name | string | Name of the kit. |
| Stamina | number | Stamina bonus from the kit. |
| Speed | number | Speed bonus from the kit. |
| Distance | number | Distance (range) bonus from the kit. |
| Reach | number | Reach bonus from the kit. |
| Area | number | Area bonus from the kit. |
| Disengage | number | Disengage bonus from the kit. |
| Stability | number | Stability bonus from the kit. |
| Damage Bonus | function | `DamageBonus(tier, "type"?)` -- damage bonus for tier and optional type ("melee", "ranged", "supernatural"). Returns highest if no type given. |

---

## Deity

**GoblinScript name:** `deity`
**Source:** `Draw Steel Core Rules/MCDMDeities.lua`

Accessed from creature via `Deity.Name`, `Deity.Domains`.

| Field | Type | Description |
|-------|------|-------------|
| Name | text | The name of the deity. |
| Domains | set | The domains associated with the deity. |

Custom fields can be added via the Custom Fields system; they appear dynamically.

---

## CharacterOngoingEffectInstance

**GoblinScript name:** `ongoing effect` / `ongoingeffect`
**Source:** `DMHub Game Rules/OngoingEffect.lua`

| Field | Type | Description |
|-------|------|-------------|
| Caster | creature | The creature that cast this ongoing effect. |

---

## AuraInstance

**GoblinScript name:** `aura`
**Source:** `DMHub Game Rules/Aura.lua`

| Field | Type | Description |
|-------|------|-------------|
| Caster | creature | The creature that controls this aura. |

---

## CharacterResourceCollection

**GoblinScript name:** `resources`
**Source:** `DMHub Game Rules/Resource.lua`

Accessed via `Resources.<ResourceName>` on a creature. Each resource defined in the
`characterResources` data table becomes a field:

| Field | Type | Description |
|-------|------|-------------|
| `<ResourceName>` | number | The available quantity of that resource (total minus used). |

Examples: `Resources.Recoveries`, `Resources.Action`, `Resources.Surges`

---

## Loc

**GoblinScript name:** `location`
**Source:** `DMHub Game Rules/BasicRules.lua`

| Field | Type | Description |
|-------|------|-------------|
| X | number | The x coordinate of the location. |
| Y | number | The y coordinate of the location. |
| Floor | number | The floor the location is on. |
| Valid | boolean | True if the location is valid and within map bounds. |
| Distance | function | `Distance(otherLocOrCreature)` -- distance in tiles. |

---

## PathMoved

**GoblinScript name:** `path`
**Source:** `DMHub Game Rules/Creature.lua`, `DMHub Game Rules/Path.lua`

Available as a symbol during movement triggers (`finishmove`, `move`).

| Field | Type | Description |
|-------|------|-------------|
| Squares | number | The number of squares this path has moved. |
| Shift | boolean | Whether this path was a shift. |
| Forced | boolean | Whether this path was a forced move. |
| Vertical Only | boolean | Whether this path only moved vertically. |
| Distance to Creature | function | `DistanceToCreature(creature)` -- minimum distance in tiles from any point on the path to the creature. |

---

## CreatureSet

**GoblinScript name:** (no explicit name -- used as a return type)
**Source:** `DMHub Game Rules/CustomAttribute.lua`

Returned by `CasterSet()`, `BoundCreatures()`, etc. Supports `has` operator.

| Field | Type | Description |
|-------|------|-------------|
| Size | number | Number of creatures in the set. |
| Highest | function | `Highest("formula")` -- evaluates formula on each creature, returns the max result. |

Also supports `is` comparison: `set is creature` returns true if creature is in the set.

---

## StringSet

**GoblinScript name:** (no explicit name -- used as a return type)
**Source:** `DMHub Game Rules/CustomAttribute.lua`

Returned by `Conditions`, `Keywords`, `Languages`, etc. Supports the `has` operator:
`Conditions has "Poisoned"`.

---

## TierSymbols

**GoblinScript name:** (inline during power roll tier resolution)
**Source:** `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua`

Available when resolving tier text during power rolls.

| Field | Type | Description |
|-------|------|-------------|
| Includes Forced Movement | boolean | True if the tier text contains push/pull/slide. |
| Push | number | The push distance from the tier text. 0 if no push. |
| Pull | number | The pull distance from the tier text. 0 if no pull. |
| Slide | number | The slide distance from the tier text. 0 if no slide. |

---

## CharacterModifier Context Symbols

**Source:** `DMHub Game Rules/CharacterModifier.lua`

These symbols are injected into the `_tmp_symbols` table of a CharacterModifier when
it is being evaluated. They are available in modifier filter conditions and value formulas.

| Field | Type | Description |
|-------|------|-------------|
| Aura | aura | The aura generating this modifier. Only for aura-sourced modifiers. |
| Ongoing Effect | ongoingeffect | The ongoing effect generating this modifier. Only for effect-sourced modifiers. |
| Stacks | number | The number of stacks of the ongoing effect. Only for effect-sourced modifiers. |

---

## Casting Context Symbols

**Source:** `DMHub Game Rules/ActivatedAbility.lua`

These symbols are available in the symbol table during ability casting (in addition to the
creature symbols and ability symbols):

| Field | Type | Description |
|-------|------|-------------|
| Target | creature | The current target creature (set per-target during multi-target resolution). |
| Cast | spellcast | The ActivatedAbilityCast tracking damage, healing, etc. |
| Charges | number | Number of charges used. |
| Mode | number | Mode chosen for multi-mode abilities. |
| Invoker | creature | The creature that invoked this ability (for invoked abilities). |

---

## Trigger Context Symbols

**Source:** `DMHub Game Rules/TriggeredAbility.lua`, `Draw Steel Core Rules/MCDMRules.lua`

Each trigger type provides a different set of context symbols in addition to the creature's
own symbols. These are the symbols for each registered trigger.

### Take Damage (`losehitpoints`)
| Field | Type | Description |
|-------|------|-------------|
| Damage | number | Amount of damage taken. |
| Raw Damage | number | Damage before immunities/reduction. |
| Damage Type | text | Type of damage taken. |
| Damage Immunity | boolean | True if immunity/weakness applied. |
| Keywords | set | Keywords used to apply the damage. |
| Surges | number | Number of surges used. |
| Edges | number | Number of edges used. |
| Banes | number | Number of banes used. |
| Attacker | creature | The attacking creature. |
| HasAttacker | boolean | True if damage has a known attacker. |
| HasAbility | boolean | True if damage has an associated ability. |
| Ability | ability | The ability used. |

### Damage an Enemy (`dealdamage`)
| Field | Type | Description |
|-------|------|-------------|
| Damage | number | Amount of damage dealt. |
| Damage Type | text | Type of damage dealt. |
| Keywords | set | Keywords used. |
| Target | creature | The target creature. |
| Surges | number | Number of surges. |
| Edges | number | Number of edges. |
| Banes | number | Number of banes. |
| HasAbility | boolean | True if an ability was used. |
| Ability | ability | The ability used. |
| Used Ability | ability | Alias for Ability. |

### Become Winded (`winded`)
| Field | Type | Description |
|-------|------|-------------|
| Damage | number | Damage dealt. |
| Damage Type | text | Damage type. |
| Keywords | set | Keywords used. |
| Attacker | creature | The creature that caused it. |

### Become Dying (`dying`)
Same symbols as Winded.

### Roll Power (`rollpower`)
| Field | Type | Description |
|-------|------|-------------|
| Natural Roll | number | Dice roll without modifiers. |
| High Roll | number | Highest d10 result. |
| Low Roll | number | Lowest d10 result. |
| Surges | number | Total surges used. |
| Tier One | boolean | True if any target got tier 1. |
| Tier Two | boolean | True if any target got tier 2. |
| Tier Three | boolean | True if any target got tier 3. |
| Ability | ability | The ability used. |

### Use an Ability (`useability`) / Use Signature (`castsignature`)
| Field | Type | Description |
|-------|------|-------------|
| Used Ability | ability | The ability used. |
| Cast | spellcast | Casting information. |

### Target With Ability (`targetwithability`)
| Field | Type | Description |
|-------|------|-------------|
| Used Ability | ability | The ability used. |
| Target | creature | The target creature. |

### Begin Movement (`move`) / Complete Movement (`finishmove`)
| Field | Type | Description |
|-------|------|-------------|
| Path | path | The PathMoved object for the movement. |

### Force Moved (`forcemove`)
| Field | Type | Description |
|-------|------|-------------|
| Type | string | Type of forced movement: "push", "pull", or "slide". |
| Has Attacker | boolean | True if a creature is causing the move. |
| Attacker | creature | The creature causing the forced move. |
| Vertical | boolean | True if the forced movement is vertical. |

### Condition Applied (`inflictcondition`)
| Field | Type | Description |
|-------|------|-------------|
| Condition | string | Name of the condition applied. |
| Attacker | creature | The attacking creature. |
| Has Attacker | boolean | True if a known creature inflicted it. |

### Move Through Creature (`movethrough`)
| Field | Type | Description |
|-------|------|-------------|
| Target | creature | The creature being moved through. |

### Creature Moved Away From (`leaveadjacent`)
| Field | Type | Description |
|-------|------|-------------|
| Moving Creature | creature | The creature moving away. |

### Use Resource (`useresource`) / Gain Resource (`gainresource`)
| Field | Type | Description |
|-------|------|-------------|
| Resource | string | The resource name. |
| Quantity | number | The amount used/gained. |

### Start of Turn (`beginturn`)
| Field | Type | Description |
|-------|------|-------------|
| Order | number | Position within the group taking their turn (1 = first). |

### Before Start of Turn (`prestartturn`)
No additional symbols.

### End Turn (`endturn`)
No additional symbols.

### Collide (`collide`)
| Field | Type | Description |
|-------|------|-------------|
| Speed | number | Remaining speed when colliding. |
| Movement Type | text | Type of forced movement: "push", "pull", or "slide". |
| Pusher | creature | The creature that pushed us. |
| With Object | boolean | True if collision is with an object. |
| With Creature | boolean | True if collision is with a creature. |

### Break Through a Wall (`wallbreak`)
| Field | Type | Description |
|-------|------|-------------|
| Speed | number | Stamina cost of breaking through. |
| Wall Type | text | "Thin" or "Solid". |
| Location | loc | Where the wall was broken. |

### Pressure Plate (`pressureplate`)
| Field | Type | Description |
|-------|------|-------------|
| Target | creature | The creature that stepped on the plate. |

### Custom Trigger (`custom`)
| Field | Type | Description |
|-------|------|-------------|
| Trigger Name | text | Name of the trigger. |
| Trigger Value | number | Numeric value associated with the trigger. |

### End Respite (`endrespite`)
| Field | Type | Description |
|-------|------|-------------|
| XP Gained | number | Experience gained from the respite. |

### Other Triggers (no additional symbols)
- Teleport (`teleport`)
- Gain Temporary Stamina (`gaintempstamina`)
- End of Combat (`endcombat`)
- Draw Steel / Roll Initiative (`rollinitiative`)
- Attack an Enemy (`attack`)
- Land from a Fall (`fall`)

---

## Built-in Functions

**Source:** `DMHub Utils/GoblinScript.lua`

These functions are available in all GoblinScript formulas:

| Function | Description |
|----------|-------------|
| `min(a, b, ...)` | Returns the minimum of all arguments. |
| `max(a, b, ...)` | Returns the maximum of all arguments. |
| `floor(x)` | Rounds down to the nearest integer. |
| `ceiling(x)` | Rounds up to the nearest integer. |
| `friends(a, b)` | Returns true if creatures a and b are friends/allies. |
| `lineofsight(a, b)` | Returns 0 to 1 line-of-sight factor between creatures. |
| `substring(haystack, needle)` | Returns true if needle is found in haystack. |

---

## Notes

- **Custom Attributes:** `CustomAttribute.RegisterAttribute` creates modifiable attributes
  that appear on creatures. These are evaluated via `CalculateAttribute` and don't directly
  become GoblinScript symbols unless also registered with `RegisterGoblinScriptSymbol`.
  However, custom attributes defined in the Compendium UI do get registered as creature
  symbols automatically.

- **Custom Fields:** Both ActivatedAbility and Deity support custom fields added through the
  CustomFieldCollection system. These appear as dynamically-registered symbols.

- **`self` accessor:** Most types support `self.<field>` syntax to access their own fields,
  and `OBJ.<field>` is equivalent to accessing the current context object's field.

- **The `is` operator:** Creatures support `creature is "keyword"` which calls `MatchesString`
  to check monster groups, features, roles, etc. CreatureSets support `set is creature`.

- **The `has` operator:** StringSet and CreatureSet types support `set has "value"`.

- **`where` clause:** GoblinScript supports `formula where x = expr` for local variables.

- **`when`/`else`:** Conditional expressions: `5 when condition else 0`.
