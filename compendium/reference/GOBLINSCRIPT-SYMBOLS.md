# GoblinScript Creature Symbols -- Complete Catalog

> Generated from source analysis of `Creature.lua`, `MCDMCreature.lua`, `MCDMSymbols.lua`,
> `MCDMMonster.lua`, `MCDMKit.lua`, `DSModifyRoutine.lua`, and `customattributes/_table.yaml`.
>
> Symbol lookup is **case-insensitive** and **ignores spaces** in names.
> Every symbol listed here is available on creature subjects: `Self`, `Target`, `Caster`,
> `Attacker`, `Moving Creature`.

---

## Table of Contents

1. [Identity and Role](#identity-and-role)
2. [Characteristics](#characteristics)
3. [Health and Resources](#health-and-resources)
4. [Movement and Speed](#movement-and-speed)
5. [Size and Position](#size-and-position)
6. [Combat Status](#combat-status)
7. [Conditions and Effects](#conditions-and-effects)
8. [Auras](#auras)
9. [Squad and Summoning](#squad-and-summoning)
10. [Functions](#functions)
11. [Monster-Only Fields](#monster-only-fields)
12. [Other](#other)
13. [Custom Attributes (from _table.yaml)](#custom-attributes-from-_tableyaml)
14. [Modifiable Attributes (from CustomAttribute.lua)](#modifiable-attributes-from-customattributelua)

---

## Identity and Role

| Symbol | Type | Description | Source |
|---|---|---|---|
| Self | creature | The creature this GoblinScript is running on. | Creature.lua (helpSymbols) |
| Name | text | The monster type of the creature (e.g., Bandit, Goblin). Only valid for monsters. | Creature.lua (helpSymbols) |
| ID | text | A unique identifier for the creature. Not human-readable. | Creature.lua (helpSymbols) |
| Type | text | The type of the creature (e.g., goblin, Elf, Human). | Creature.lua (helpSymbols) |
| Subtype | text | The subtype of the creature (e.g., Goblinoid). Empty if none. | Creature.lua (helpSymbols) |
| Level | number | The Level of the creature. For monsters this is their Spellcasting Level. | Creature.lua (helpSymbols) |
| Challenge Rating | number | The Challenge Rating. For characters this is their Character Level. | Creature.lua (helpSymbols) |
| CR | number | Synonym of Challenge Rating. | Creature.lua (helpSymbols) |
| Role | string | The role of the creature (e.g., "Artillery", "Brute", "hero"). | MCDMCreature.lua |
| Keywords | set | The keywords associated with this creature. Use `has` to check. | MCDMCreature.lua |
| Subclasses | set | The subclasses this character has taken. None for monsters. | Creature.lua (helpSymbols) |
| Hero | boolean | True if this creature is a hero (player character). | MCDMCreature.lua |
| Object | boolean | True if this 'creature' is actually an object. | MCDMCreature.lua |
| Player Allied | boolean | True if this creature is a player or allied with the players. | MCDMCreature.lua |
| Minion | boolean | Is this creature a minion? | MCDMCreature.lua |
| Captain | boolean | Is this creature a captain of a squad? | MCDMCreature.lua |
| Solo | boolean | Is this creature a solo? | MCDMCreature.lua |
| Leader | boolean | Is this creature a leader? | MCDMCreature.lua |
| Retainer | boolean | True if this creature is a retainer. | MCDMCreature.lua |

---

## Characteristics

These are registered dynamically from `creature.RegisterCharacterAttribute()`. In Draw Steel, the five characteristics are Might, Agility, Reason, Intuition, and Presence. Each generates two symbols.

| Symbol | Type | Description | Source |
|---|---|---|---|
| Might | number | The Might of the creature (characteristic score). | Creature.lua (dynamic attribute registration) |
| Might Modifier | number | The Might Modifier of the creature. | Creature.lua (dynamic attribute registration) |
| Agility | number | The Agility of the creature. | Creature.lua (dynamic attribute registration) |
| Agility Modifier | number | The Agility Modifier of the creature. | Creature.lua (dynamic attribute registration) |
| Reason | number | The Reason of the creature. | Creature.lua (dynamic attribute registration) |
| Reason Modifier | number | The Reason Modifier of the creature. | Creature.lua (dynamic attribute registration) |
| Intuition | number | The Intuition of the creature. | Creature.lua (dynamic attribute registration) |
| Intuition Modifier | number | The Intuition Modifier of the creature. | Creature.lua (dynamic attribute registration) |
| Presence | number | The Presence of the creature. | Creature.lua (dynamic attribute registration) |
| Presence Modifier | number | The Presence Modifier of the creature. | Creature.lua (dynamic attribute registration) |
| Weak | number | Weak potency. Equals highest characteristic - 2. | MCDMCreature.lua |
| Average | number | Average potency. Equals highest characteristic - 1. | MCDMCreature.lua |
| Strong | number | Strong potency. Equals highest characteristic. | MCDMCreature.lua |
| Highest Characteristic | number | The highest characteristic score of the creature. | MCDMCreature.lua |

---

## Health and Resources

| Symbol | Type | Description | Source |
|---|---|---|---|
| Stamina | number | The current stamina of the creature. | MCDMCreature.lua |
| Maximum Stamina | number | The maximum stamina of the creature. | MCDMCreature.lua |
| Temporary Stamina | number | The creature's current temporary stamina. | MCDMCreature.lua |
| Recovery Value | number | The Recovery Value of the creature (MaxStamina/3, modified by attributes). | MCDMCreature.lua |
| Recoveries Available to Spend | number | Remaining recoveries (accounts for sharing like Bloodbound Band). | MCDMCreature.lua |
| Heroic Resources Available to Spend | number | Total heroic resources available to spend. Accounts for Talent-style negative resources. | MCDMCreature.lua |
| Heroic Resources This Turn | number | High water mark of heroic resources gained this turn. | MCDMCreature.lua |
| Malice | number | The amount of malice the Director has available. | MCDMCreature.lua |
| HeroTokens | number | The number of hero tokens the party has available. | MCDMCreature.lua |
| Power Roll Bonus | number | Bonus that monsters get to their power rolls. Zero for heroes. | MCDMCreature.lua |
| Resources | resources | The resources this creature has available. Access fields: `Resources.Standard Action > 0`. | Creature.lua (helpSymbols) |
| Dying | boolean | True if this creature is dying. | MCDMCreature.lua |
| Dead | boolean | True if this creature is dead. | MCDMCreature.lua |
| Hitpoints | number | **(Deprecated)** Current hitpoints. Use Stamina instead. | Creature.lua (helpSymbols) |
| Maximum Hitpoints | number | **(Deprecated)** Maximum hitpoints. Use Maximum Stamina instead. | Creature.lua (helpSymbols) |

---

## Movement and Speed

Movement speed symbols are generated dynamically from `creature.movementTypeInfo`. Each movement type produces a `<Verb> Speed` symbol.

| Symbol | Type | Description | Source |
|---|---|---|---|
| Walking Speed | number | Walking speed in squares per round. 0 if the creature does not have one. | Creature.lua (dynamic) |
| Swimming Speed | number | Swimming speed in squares. 0 if none. | Creature.lua (dynamic) |
| Flying Speed | number | Flying speed in squares. 0 if none. | Creature.lua (dynamic) |
| Climbing Speed | number | Climbing speed in squares. 0 if none. | Creature.lua (dynamic) |
| Burrowing Speed | number | Burrowing speed in squares. 0 if none. | Creature.lua (dynamic) |
| Teleporting Speed | number | Teleporting speed in squares. 0 if none. | Creature.lua (dynamic) |
| Movement Speed | number | Total distance this creature can move in a round, in squares. | Creature.lua (helpSymbols) |
| Moved This Turn | number | Distance moved this turn. 0 when not in combat. | Creature.lua (helpSymbols) |
| Charge Distance | number | Straight-line distance moved on the current turn. 0 when not in combat. | Creature.lua (helpSymbols) |
| Movement Type | text | Current movement type: "Walk", "Swim", "Fly", etc. | Creature.lua (helpSymbols) |
| Movement Multiplier | number | Current movement distance multiplier. | Creature.lua (helpSymbols) |
| Mounted | boolean | True if this creature is mounted on another creature. | Creature.lua (helpSymbols) |
| Mount | creature | The mount this creature is riding. Only valid when Mounted is true. | Creature.lua (helpSymbols) |

---

## Size and Position

| Symbol | Type | Description | Source |
|---|---|---|---|
| Size | number | Size number: 1=1T, 2=1S, 3=1M, 4=1L, 5=2, 6=3, 7=4, 8=5. | Creature.lua (helpSymbols) |
| Tile Size | number | Tiles occupied on the map. | Creature.lua (helpSymbols) |
| Height | number | Stature of the creature in tiles. | Creature.lua (helpSymbols) |
| Altitude | number | Altitude in tiles above ground zero. | Creature.lua (helpSymbols) |
| AltitudeInDeciTiles | number | Altitude in tenths of a tile above ground zero. | Creature.lua (helpSymbols) |
| SizeWhenForceMoved | number | Effective size of the creature when being force moved. | MCDMCreature.lua |
| Reach | number | The reach of the creature in squares. | MCDMCreature.lua |
| Weight | number | The weight of the creature (modifiable attribute). | MCDMCreature.lua |

---

## Combat Status

| Symbol | Type | Description | Source |
|---|---|---|---|
| Flanked | boolean | True if this creature is currently being flanked. | MCDMCreature.lua |
| Flanked By | function | `FlankedBy(creature)` or `FlankedBy(creature1, creature2)` -- checks if flanked by specific creature(s). | MCDMCreature.lua |
| InWater | boolean | True if this creature is in water (swim movement type). | MCDMCreature.lua |
| Concealed | boolean | True if the creature is in a concealed area. | MCDMCreature.lua |
| Your Turn | boolean | True if combat is active and it is this creature's turn. | Creature.lua (helpSymbols) |
| Taken Turn | boolean | Has this creature taken its turn this round? | MCDMCreature.lua |
| Taken Turn This Round | boolean | Has this creature taken its turn this round? (alias) | MCDMCreature.lua |
| Turn Being Chosen | boolean | Is the next turn for initiative currently being chosen? | MCDMCreature.lua |
| Combat Round | number | The current combat round number. 0 if not in combat. | Creature.lua (helpSymbols) |
| End Turn Timestamp | number | Numeric timestamp when this creature ended its last turn. | MCDMCreature.lua |
| Last Damaged By | function | `LastDamagedBy(damageType)` -- returns timestamp of last time damaged by that type. | MCDMCreature.lua |
| Hidden This Turn | boolean | True if the creature has been hidden this turn. | Creature.lua (helpSymbols) |
| Game Mode | string | The current game mode: "exploration", "combat", "respite", or "downtime". | MCDMCreature.lua |
| Immunities | function | `Immunities("Fire")` -- returns total immunity/weakness for a damage type. | MCDMCreature.lua |
| Save Ends Effects | boolean | Does this creature have any save ends effects? | MCDMCreature.lua |
| Number of Creatures Grabbed | number | The number of creatures currently grabbed by this creature. | Creature.lua (helpSymbols) |

---

## Conditions and Effects

| Symbol | Type | Description | Source |
|---|---|---|---|
| Conditions | set | Names of active conditions. Use `has`: `Conditions has "Grabbed"`. | Creature.lua (lookupSymbols) |
| Ongoing Effects | set | Names of active ongoing effects. Use `has`: `Ongoing Effects has "Rage"`. | Creature.lua (lookupSymbols) |
| Stacks | function | `Stacks("Effect Name")` -- stack count of a named ongoing effect. | Creature.lua (helpSymbols) |
| Condition Stacks | function | `ConditionStacks("Grabbed")` -- stack count of a named condition. | MCDMCreature.lua |
| Condition Count | number | Number of distinct active conditions on this creature. | MCDMCreature.lua |
| Effects Count | number | Number of conditions and ongoing effects currently active. | MCDMCreature.lua |
| Condition Immunities | set | Conditions this creature is immune to. | Creature.lua (helpSymbols) |
| Effect Caster | function | `EffectCaster("ConditionName", Caster)` -- returns stacks of that effect cast by a specific creature. | MCDMCreature.lua |
| ConditionCaster | function | `ConditionCaster("Grabbed")` -- returns the creature that applied this condition/effect. | Creature.lua (helpSymbols) |
| CasterSet | function | `CasterSet("EffectName")` -- returns set of creatures that applied the effect. | Creature.lua (lookupSymbols) |
| Last Caster | creature | The creature to last cause a saving throw trigger on this creature. | Creature.lua (helpSymbols) |
| Complications | set | Complications the creature has. Use `has`: `Complications has "Coward"`. | MCDMCreature.lua |

---

## Auras

| Symbol | Type | Description | Source |
|---|---|---|---|
| Auras Affecting | set | Names of auras currently affecting this creature. Use `has`. | MCDMCreature.lua |
| AurasCaster | function | `AurasCaster("Aura Name")` -- returns the creature projecting that aura. | MCDMCreature.lua |

---

## Squad and Summoning

| Symbol | Type | Description | Source |
|---|---|---|---|
| HasCaptain | boolean | True if this minion's squad has a living captain. | MCDMCreature.lua |
| Squad Captain | creature | The captain of the squad this minion belongs to. | MCDMCreature.lua |
| Summoned | boolean | True if this creature was summoned by another creature. | Creature.lua (helpSymbols) |
| Summoner | creature | The creature that summoned this creature. Only valid if Summoned is true. | Creature.lua (helpSymbols) |
| SquadCaster | function | `SquadCaster("EffectName")` -- returns the squad that applied a named ongoing effect. | Creature.lua (helpSymbols) |
| SquadLiveMembers | function | `SquadLiveMembers("SquadName")` -- number of living members in a squad. | Creature.lua (helpSymbols) |
| BoundCreatures | function | `BoundCreatures("Bloodbound")` -- set of creatures bound by a named ongoing effect. | MCDMCreature.lua |
| BoundOngoingEffect | function | `BoundOngoingEffect(Target, "Bloodbound")` -- true if this creature is bound to Target by the named effect. | MCDMCreature.lua |
| Mentor | creature | The mentor of this Retainer. Only valid if Retainer is true. | MCDMCreature.lua |

---

## Functions

| Symbol | Type | Description | Source |
|---|---|---|---|
| Distance | function | `Distance(Target)` -- distance in squares to another creature. | Creature.lua (helpSymbols) |
| Count Nearby Enemies | function | `CountNearbyEnemies(5)` -- live enemies in range. Accepts group names, feature names, creatures to exclude. | Creature.lua (helpSymbols) |
| Count Nearby Friends | function | `CountNearbyFriends(5)` -- live allies in range. Same filters. | Creature.lua (helpSymbols) |
| Count Nearby Creatures | function | `CountNearbyCreatures(5)` -- all live creatures in range. Accepts "ally", "enemy", group/feature/creature filters. | Creature.lua (helpSymbols) |
| Count Riders | function | `CountRiders("goblin", "crafty")` -- riders matching filter criteria. | Creature.lua (helpSymbols) |
| Passes Potency | function | `PassesPotency(characteristicId, value)` -- true if creature passes potency check. | MCDMCreature.lua |
| AdjacentAlliesWithFeature | function | `AdjacentAlliesWithFeature("FeatureName")` -- count of adjacent allies with named feature. | MCDMSymbols.lua |
| Proficient | function | **(Deprecated)** `Proficient("Acrobatics")` -- skill/item/category proficiency. | Creature.lua (helpSymbols) |
| Skill Modifier | function | **(Deprecated)** `SkillModifier("Acrobatics")` -- skill check modifier. | Creature.lua (helpSymbols) |
| Save Modifier | function | **(Deprecated)** `SaveModifier("dex")` -- saving throw modifier. | Creature.lua (helpSymbols) |
| Ongoing DC | function | **(Deprecated)** `OngoingDC("Stealth")` -- DC of an ongoing effect. | Creature.lua (helpSymbols) |
| Passive | function | **(Deprecated)** `Passive("perception")` -- passive skill score. | Creature.lua (helpSymbols) |

---

## Monster-Only Fields

These symbols are registered on `monster` only (via `monster.RegisterSymbol`).

| Symbol | Type | Description | Source |
|---|---|---|---|
| Free Strike Damage | number | The free strike damage value of the monster. | MCDMMonster.lua |
| Free Strike Range | number | The free strike range of the monster. | MCDMMonster.lua |
| EV | number | The encounter value of the monster. | MCDMMonster.lua |

---

## Other

| Symbol | Type | Description | Source |
|---|---|---|---|
| Victories | number | The number of victories the hero has. Zero for non-heroes. | MCDMSymbols.lua |
| Kit | kit | The current kit of this creature, if any. Access fields: `Kit.speed`. | MCDMKit.lua |
| Languages | set | Languages this creature knows. Use `has`: `Languages has "Common"`. | Creature.lua (helpSymbols) |
| Num Dead Languages | number | Number of dead languages known. | MCDMCreature.lua |
| Dead Languages | set | Dead languages known. Use `has`: `Dead Languages has "Old Variac"`. | MCDMCreature.lua |
| Magic Treasure Count | number | Number of magic treasures equipped or carried. | MCDMCreature.lua |
| Routine Distance | number | If the creature has a routine, this is the distance of the routine. | DSModifyRoutine.lua |
| NumberOfPlayers | number | The number of players in the game, not counting followers. | MCDMCreature.lua |
| Always | number | Always returns 1 (constant true). | Creature.lua (lookupSymbols) |
| Never | number | Always returns 0 (constant false). | Creature.lua (lookupSymbols) |

### Deprecated / Legacy Symbols

| Symbol | Type | Description | Source |
|---|---|---|---|
| Armor Class | number | **(Deprecated)** The Armor Class. | Creature.lua (helpSymbols) |
| Proficiency Bonus | number | **(Deprecated)** Proficiency Bonus. | Creature.lua (helpSymbols) |
| Proficiency Modifier | number | **(Deprecated)** Synonym of Proficiency Bonus. | Creature.lua (helpSymbols) |
| Spell Save DC | number | **(Deprecated)** Spellcasting Save DC. | Creature.lua (helpSymbols) |
| Spellcasting Ability Modifier | number | **(Deprecated)** Spellcasting Ability Modifier. | Creature.lua (helpSymbols) |
| Spellcasting Classes | number | **(Deprecated)** Number of spellcasting classes. | Creature.lua (helpSymbols) |
| Multiclass | boolean | **(Deprecated)** True for characters with multiple classes. | Creature.lua (helpSymbols) |
| Weapons Wielded | number | **(Deprecated)** Number of weapons wielded. | Creature.lua (helpSymbols) |
| Two Handed | boolean | **(Deprecated)** True if wielding a two-handed weapon. | Creature.lua (helpSymbols) |
| Has Main Hand Item | boolean | **(Deprecated)** True if primary hand has an item. | Creature.lua (helpSymbols) |
| Has Off Hand Item | boolean | **(Deprecated)** True if off hand has an item. | Creature.lua (helpSymbols) |
| Main Hand Item | equipment | **(Deprecated)** Primary hand item. | Creature.lua (helpSymbols) |
| Off Hand Item | equipment | **(Deprecated)** Off hand item. | Creature.lua (helpSymbols) |
| Has Shield | boolean | **(Deprecated)** True if creature has a shield. | Creature.lua (helpSymbols) |
| Shield | equipment | **(Deprecated)** The shield, if any. | Creature.lua (helpSymbols) |
| Shield Bonus | number | **(Deprecated)** AC increase from shield. | Creature.lua (helpSymbols) |
| Has Armor | boolean | **(Deprecated)** True if wearing armor. | Creature.lua (helpSymbols) |
| Armor | equipment | **(Deprecated)** The armor, if any. | Creature.lua (helpSymbols) |
| Light Armor | boolean | True if wearing Light Armor. | Creature.lua (helpSymbols) |
| Medium Armor | boolean | True if wearing Medium Armor. | Creature.lua (helpSymbols) |
| Heavy Armor | boolean | True if wearing Heavy Armor. | Creature.lua (helpSymbols) |
| Unarmored | boolean | True if not wearing armor (shield-only counts as unarmored). | Creature.lua (helpSymbols) |
| Inventory Weight | number | **(Deprecated)** Total inventory weight. | Creature.lua (helpSymbols) |

---

## Custom Attributes (from _table.yaml)

Every custom attribute in `compendium/tables/customattributes/_table.yaml` automatically becomes a GoblinScript symbol on all creatures. The symbol name is the attribute name with spaces removed and lowered for lookup (but display name preserves case and spaces).

### Potency Resistance

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Might Potency Resistance | `Might` | Potency resistance based on Might. |
| Agility Potency Resistance | `Agility` | Potency resistance based on Agility. |
| Reason Potency Resistance | `Reason` | Potency resistance based on Reason. |
| Intuition Potency Resistance | `Intuition` | Potency resistance based on Intuition. |
| Presence Potency Resistance | `Presence` | Potency resistance based on Presence. |

### Forced Movement

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Push Bonus | `0` | Bonus push distance. |
| Pull Bonus | `0` | Bonus pull distance. |
| Slide Bonus | `0` | Bonus slide distance. |
| Toss Bonus | `0` | Bonus toss distance. |
| Forced Movement Bonus | `0` | Additional spaces when inflicting forced movement. |
| Forced Movement Increase | `0` | Increases distance when subject to forced movement. |
| Forced Movement Damage Reduction | `0` | Reduces damage from being force moved. |
| Cannot Be Force Moved | `0` | Non-zero prevents forced movement. |
| No Damage from Forced Movement | `0` | Non-zero prevents forced movement damage. |
| NoDamageFromForcedMovementWithObjects | `0` | No damage from forced movement into objects. |
| Collision Immunity | `0` | Immune to collision damage from forced movement. |
| Fall Reduction | `Max(0, Agility)` | Reduces fall damage. |
| Stop Fall Damage | `0` | Non-zero prevents fall damage entirely. |
| Ignore Stability | `0` | Non-zero ignores target stability when force moving. |
| Knockback Caster Size | `Size` | Effective size when determining if you can knockback. |
| Knockback Target Size | `SizeWhenForceMoved` | Effective size when being knocked back. |
| Knockback Targets | `1` | Number of targets a creature can knockback. |
| Bonus Push Damage Into Objects | `0` | Bonus damage when pushing into objects. |

### Movement

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Disengage Speed | `1` | Speed when disengaging (shifting). |
| Shift Disabled | `0` | Non-zero disables shifting. |
| Ignore Difficult Terrain | `0` | Non-zero ignores difficult terrain. |
| Freely Move Through Enemies | `0` | Non-zero allows moving through enemy spaces. |
| Block Enemy Movement | `0` | Non-zero blocks enemy movement through your space. |
| Can Shift In Difficult Terrain | `0` | Non-zero allows shifting in difficult terrain. |
| Full Speed Grabbing | `0` | Non-zero allows full speed while grabbing. |
| Number of Movement Actions | `1` | Number of move actions per turn. |
| Speed While Slowed | `2` | Speed when slowed. |
| CanMoveThroughWalls | `0` | Non-zero allows moving through walls (incorporeal). |
| Hover | `0` | Non-zero allows hovering while flying. |
| Charging Speed | `Walking Speed` | Speed used for Charge maneuver. |
| Jump Distance | `Max(1, Max(Might, Agility))` | Long jump distance in squares. |
| Ignore Prone Difficulty | `0` | Non-zero prevents extra movement cost while prone. |

### Combat

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Has Cover | `0` | Non-zero means creature has cover. |
| Gives Cover | `0` | Non-zero means creature provides cover to others. |
| Bonus Range | `0` | Bonus to ability range. |
| Spread Bonus | `0` | Bonus to spread abilities. |
| Ignore Concealment | `0` | Non-zero ignores concealment. |
| Ignore Concealment Within Range | `0` | Range within which concealment is ignored. |
| Ignore Cover | `0` | Non-zero ignores cover. |
| Ignore Fire Immunity | `0` | Non-zero ignores fire immunity. |
| Immune to Non Damage Effects | `0` | Non-zero ignores non-damage effects. |
| Cannot Regain Stamina | `0` | Non-zero prevents stamina recovery. |
| Stamina Regain Halved | `0` | Non-zero halves stamina recovery. |
| Cannot Make Opportunity Attacks | `0` | Non-zero prevents opportunity attacks. |
| Immunity from Opportunity Attack | `0` | Non-zero prevents being targeted by opportunity attacks. |
| Cannot Use Triggered Abilities | `0` | Non-zero prevents triggered ability usage. |
| Signature Abilities While Charging | `0` | Non-zero allows signature abilities during charge. |
| Heroic Abilities While Charging | `0` | Non-zero allows heroic abilities during charge. |
| Charging | `0` | Non-zero indicates in charging state during ability use. |
| Grab Range | `1` | Range for grab attacks. |
| Maximum Grabbed Creatures | `1` | Max creatures that can be grabbed simultaneously. |
| SizeWhenGrabbing | `Size` | Effective size when grabbing. |
| Grab Characteristic | `Might` | Characteristic used for grab checks. |
| Compel Attacks Between | `0` | Non-zero compels multi-target attacks to be between caster and first target. |
| Untargetable | `0` | Non-zero makes creature untargetable. |
| Cannot Be Removed | `0` | Non-zero prevents creature from being removed from the board when dead. |
| Delay Death | `0` | Delay monster death by this many seconds for on-death effects. |
| Free Strike Bonus | `0` | Bonus to free strike damage (monsters). |
| Critical Threshold | `19` | Natural roll needed for critical hit. |

### Flanking

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Flanking Immunity | `0` | Non-zero makes creature immune to flanking. |
| Cannot Grant Flanking | `0` | Non-zero prevents creature from granting flanking to allies. |
| Grant Flanking to Allies | `0` | Non-zero grants flanking to all adjacent allies. |
| Count as Ally to Enemies for Flanking | `0` | Non-zero treats this creature as an ally to enemies for flanking purposes. |

### Advancement

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Wealth | `1` | Character wealth level. |
| Renown | `0` | Character renown. |

### Class Specific

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Strained | `Resources.Heroic Resource < 0` | True if Heroic Resource is negative (Talent-specific). |
| SummonerRange | `5 + Reason` | Max distance for summoner abilities. |
| MaximumMinions | `8` | Maximum minions a summoner can have. |
| MaxMinionSquads | `2` | Maximum squads of minions. |
| StartTurnSummon | `3` | Minions summoned at start of turn for free. |
| Heroic Resource Gain at Start | `0` | Heroic Resources gained at start of turn. |
| Heroic Resource Gain Modification | `0` | Modifier to all heroic resource gains. |
| Extra Heroic Resource Available | `0` | Added to heroic resource pool (for ability duration effects). |
| Negative Heroic Resource | `0` | Non-zero allows negative heroic resources. |
| Force Orbs | `0` | Number of force orbs (class-specific). |
| Num Routines | `1` | Number of active routines. |
| Maximum Marks | `1` | Max marked targets (Tactician). |
| Primordial Damage | stringset (cold, fire, corruption, lightning) | Primordial damage types. |
| Maximum Shields | `3` | Maximum shields. |
| Maximum Surges | `3` | Maximum surges. |

### Health Thresholds

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Winded | `Stamina <= Maximum Stamina/2` | True if stamina is at or below half. |
| Dying Value | `Maximum Stamina/2` | Stamina threshold for dying. |
| Dying Stamina | `0` | Stamina when entering Dying state. |
| Save Ends | `6` | Save ends threshold value. |
| Save Bonus | `0` | Bonus to saving throws. |

### Other Custom Attributes

| Symbol (Display Name) | Default Value | Description |
|---|---|---|
| Ignores Bleeding | `0` | Non-zero ignores bleeding effects. |
| Mute | `0` | Non-zero prevents verbal communication. |
| Nullifying Aura Radius | `0` | Radius of nullifying aura. |
| Cannot Stand | `0` | Non-zero prevents standing. |
| Force Remain on Map | `0` | Non-zero forces creature to stay on map. |
| Compel Movement Toward | `0` | Creature ID to compel movement toward. |
| Compel Movement Adjacent | `0` | Creature ID to compel ending movement adjacent to. |
| Initiative Threshold | `6` | Initiative threshold value. |
| Corrupted Mentor | `0` | Non-zero indicates corrupted mentor. |
| Unused | `0` | Unused attribute placeholder. |

---

## Modifiable Attributes (from CustomAttribute.lua)

These are engine-level modifiable attributes that also become GoblinScript symbols (via `CustomAttribute.modifiableAttributes`). Many overlap with symbols above.

| Symbol (Display Name) | Attribute ID | Type | Category |
|---|---|---|---|
| Walking Speed | `speed` | number | Movement |
| Can Swim | `swim` | number | Movement |
| Can Fly | `fly` | number | Movement |
| Can Climb | `climb` | number | Movement |
| Can Burrow | `burrow` | number | Movement |
| Can Teleport | `teleport` | number | Movement |
| Movement Difficulty | `movementDifficulty` | number | Movement |
| Movement Multiplier | `movementMultiplier` | number | Movement |
| Creature Size | `creatureSize` | number | Basic Attributes |
| Disguised | `disguised` | number | Basic Attributes |
| Darkvision | `darkvision` | number | Senses |
| Vision Range | `visionrange` | number | Senses |
| Proficiency Bonus | `proficiencyBonus` | number | Basic Attributes |
| Stability | `forcedmoveresistance` | number | Forced Movement |
| Size When Force Moved | `creaturesizewhenforcemoved` | number | Forced Movement |
| Reach | `reach` | number | Combat |
| Weight | `weight` | number | Basic Attributes |
| Recovery Value | `recoveryvalue` | number | Basic Attributes |
| Extra Turns | `extraturns` | number | Basic Attributes |
| Flank From Any Direction | `flankfromanydirection` | number | Basic Attributes |

---

## Notes

- **Symbol lookup** is case-insensitive and ignores spaces. `maximumstamina`, `Maximum Stamina`,
  and `MAXIMUMSTAMINA` all resolve to the same symbol.
- **Custom attributes** from `_table.yaml` and `CustomAttribute.RegisterAttribute` calls all become
  creature symbols automatically. Their lookup key is the name with spaces removed and lowercased.
- **Dot access** allows chaining: `Target.Stamina`, `Caster.Mount.Level`, `Kit.speed`.
- **`has` operator** works on set-typed symbols: `Conditions has "Grabbed"`, `Keywords has "Strike"`.
- **Functions** are called with parentheses: `Distance(Target)`, `Stacks("Rage")`,
  `CountNearbyEnemies(5, "Goblin")`.
