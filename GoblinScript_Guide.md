# GoblinScript Reference Guide

> **Note:** This document is technically dense and designed for AI consumption. It prioritizes
> precise semantics and compact reference tables over tutorial-style explanation.

---

## Table of Contents

1. [Language Overview](#language-overview)
2. [Syntax Quick Reference](#syntax-quick-reference)
3. [Subjects](#subjects)
4. [Creature Fields](#creature-fields)
5. [Custom Attribute Symbols](#custom-attribute-symbols)
6. [Ability Fields](#ability-fields)
7. [Cast Fields](#cast-fields)
8. [Path Fields](#path-fields)
9. [Aura and Ongoing Effect Fields](#aura-and-ongoing-effect-fields)
10. [Global Functions](#global-functions)
11. [Dice Notation](#dice-notation)
12. [Special Syntax](#special-syntax)
13. [Formula Field Types](#formula-field-types)

---

## Language Overview

GoblinScript is a pure functional expression language embedded in the DMHub engine. It has no
statements, no loops, no side effects, and no mutable variables. Every GoblinScript formula is
a single expression that evaluates to a number, boolean, text string, or object reference.

### Purpose

GoblinScript bridges game content and live game state. Whenever the engine needs a runtime-
dependent value -- ability damage, modifier activation, target validity, inline display text --
it evaluates a GoblinScript expression.

### Evaluation Context and Symbols

Every expression is evaluated within a **context** that determines the available **symbols**
(named values). Each context has a **subject** -- almost always a creature -- whose fields are
loaded directly into the symbol table. The subject can be referred to as `Self`. Writing
`Stamina` is equivalent to `Self.Stamina`.

Additional named symbols depend on the formula's location: `Caster`, `Target`, `Cast`,
`Ability`, etc. Each symbol resolves to an object whose fields are accessed via dot notation:
`Target.Stamina`, `Cast.Natural Roll`, `Ability.Keywords`.

Symbol lookup is case-insensitive and ignores spaces in names.

### Expression Types

**Literals:** Numbers (`42`, `3.5`) and quoted strings (`"Artillery"`).

**Symbol references:** Bare identifiers. Multi-word identifiers are merged (`Maximum Stamina`).

**Dot access:** `Subject.Field` -- resolves left side to an object, looks up right side on it.

**Arithmetic:** `+`, `-`, `*`, `/`. Division is integer (always floored).

**Comparisons:** `=`, `~=`/`!=`/`<>`, `>`, `<`, `>=`, `<=`. String comparisons are
case-insensitive and space-insensitive.

**Text operators:** `is`/`is not` (exact equality), `has`/`has not` (substring containment).
Also work on set objects via `__is__` lookup (e.g. `Conditions has "Grabbed"`).

**Logical:** `and`, `or`, `not`. Falsy: `false`, `nil`, numbers <= 0. When both sides of `or`
are numbers, it returns the larger value (acts as max).

**Conditionals:** `value when condition` (returns 0 if false). `value when condition else fallback`.

**Variable binding:** `expr where x = sub-expr` -- textual substitution before evaluation.

**Function calls:** `fn(arg1, arg2)`. Built-ins: `min`, `max`, `floor`, `ceiling`, `Friends`,
`Line of Sight`, `Substring`. Symbol-provided: `Distance(Target)`, `Count Nearby Enemies(5)`,
`Stacks("Grabbed")`, etc.

**Unary:** `-x` negates, `+x` is identity.

**Dice notation** (non-deterministic only): `NdF` with modifiers `keep`, `drop`, `reroll`,
`minroll`, `exploding`, `extradie`, `dicecount`, `alter`.

**Category tags:** `expression [category]` attaches metadata (e.g. `2d6 [fire]`).

### Operator Precedence (lowest to highest)

1. `where`
2. `+`, `-`
3. `when`/`else`
4. `or`, `and`
5. `=`, `~=`, `>`, `<`, `>=`, `<=`
6. `*`, `/`
7. `is`, `is not`, `has`, `has not`
8. Function calls
9. `d`, dice keywords
10. `.` (dot access)

Parentheses override precedence.

### Type Coercion

- Boolean to number: `true` -> 1, `false` -> 0
- Number to boolean: <= 0 is false, > 0 is true
- Non-numeric values default to 0 in arithmetic
- All string comparisons are case-insensitive, space-insensitive

### Two Evaluation Paths

- **Deterministic** (filters, conditions, activation checks): Reduces to a concrete value.
  No dice notation. Result is a number or boolean.
- **Non-deterministic** (roll fields): Deterministic parts are reduced; remaining dice
  expressions are emitted as text for the roll parser.

Parsed expressions are cached.

---

## Syntax Quick Reference

```
2 + 3                                    -- arithmetic
Might * 2                                -- symbol in arithmetic
Stamina / 2                              -- integer division (floored)
2d10 + Might                             -- dice + symbol
Stamina <= Maximum Stamina / 2           -- comparison
Role = "Artillery"                       -- string equality
Keywords has "Strike"                    -- substring/set containment
not Friends(Target, Caster)              -- logical negation + function
condition1 and condition2                -- logical and
5 when Target.Flanked                    -- conditional (0 if false)
(1d3 + 1) when Level >= 7 else (1d3)    -- conditional with fallback
1 + (1 when Level >= 4)                  -- additive level scaling
Stamina + x where x = 7                 -- variable binding
min(a, b)  max(a, b)                     -- built-in functions
floor(x)   ceiling(x)                    -- rounding
Target.Stamina                           -- dot access
{2 * Reason}                             -- inline text substitution
{Reason|fallback text}                   -- substitution with fallback
```

---

## Subjects

| Subject | Type | When available |
|---|---|---|
| `Self` | Creature | Always -- the creature that owns the ability, modifier, or aura |
| `Caster` | Creature | Always -- the creature currently using the ability |
| `Target` | Creature | Targeting and effect formulas |
| `Attacker` | Creature | Defensive trigger contexts |
| `Moving Creature` | Creature | Movement trigger contexts |
| `Ability` | Ability | Formula fields on activated abilities |
| `UsedAbility` | Ability | Event trigger contexts ("when you use a maneuver...") |
| `Cast` | Cast | During ability resolution |
| `Aura` | Aura | Inside aura effect formulas |
| `Path` | Path | Movement formula fields |

`Self` is the creature that *owns* the ability/modifier. `Caster` is the creature actively
*using* it. Usually the same, but can differ in shared or triggered contexts. All creature-
typed subjects share the same field pool.

---

## Creature Fields

Available on `Self`, `Target`, `Caster`, `Attacker`, `Moving Creature`.

### Identity and Role

| Field | Type | Description |
|---|---|---|
| Name | Text | Monster type name (monsters only) |
| ID | Text | Unique internal identifier |
| Type | Text | Creature type (e.g. Goblin, Elf) |
| Subtype | Text | Creature subtype (empty if none) |
| Level | Number | Creature level |
| Role | Text | Role: "Artillery", "Brute", "Leader", etc. |
| Keywords | Text | Creature keywords (use `has` to check) |
| Subclasses | Set | Character subclasses (none for monsters) |
| Minion | Boolean | Is a minion |
| Captain | Boolean | Is a captain |
| Solo | Boolean | Is a solo |
| Leader | Boolean | Is a leader |
| HasCaptain | Boolean | Has a captain nearby |
| SquadCaptain | Boolean | Is a squad captain |
| Hero | Boolean | Is a player character |
| Object | Boolean | Is an object |
| PlayerAllied | Boolean | Allied with players |
| Retainer | Boolean | Is a retainer |
| Mentor | Boolean | Is a mentor |

### Health and Resources

| Field | Type | Description |
|---|---|---|
| Stamina | Number | Current stamina |
| Maximum Stamina | Number | Maximum stamina |
| Temporary Stamina | Number | Current temporary stamina |
| Recovery Value | Number | Recovery value |
| Recoveries Available to Spend | Number | Remaining recoveries |
| Heroic Resources Available to Spend | Number | Total heroic resources available |
| Heroic Resources This Turn | Number | Heroic resources gained this turn |
| Malice | Number | Current malice |
| Power Roll Bonus | Number | Bonus to power rolls |
| Dying | Boolean | Is dying |
| Dead | Boolean | Is dead |
| Resources | Resources | Available resource pools |

### Combat Status

| Field | Type | Description |
|---|---|---|
| Flanked | Boolean | Is flanked |
| FlankedBy | Text | ID of flanking creature |
| InWater | Boolean | Is in water |
| Concealed | Boolean | Is concealed |
| TakeTurn | Boolean | Has taken turn this round |
| TurnBeingChosen | Boolean | Turn is being chosen |
| End Turn Timestamp | Number | Last end-of-turn timestamp |
| Last Damaged By | Text | ID of last damage dealer |
| Your Turn | Boolean | Is this creature's turn |
| Combat Round | Number | Current round (0 if not in combat) |
| Hidden This Turn | Boolean | Was hidden this turn |

### Characteristics and Potency

| Field | Type | Description |
|---|---|---|
| Weak | Number | Weak characteristic score |
| Average | Number | Average characteristic score |
| Strong | Number | Strong characteristic score |
| Highest Characteristic | Number | Highest characteristic score |
| Passes Potency | Function | `Passes Potency(target, characteristic, potency)` |

### Size and Movement

| Field | Type | Description |
|---|---|---|
| Size | Number | Size (1=Tiny, 2=Small, 3=Medium, 4=Large, 5=2, 6=3, 7=4, 8=5) |
| Tile Size | Number | Tiles occupied on map |
| Height | Number | Stature in tiles |
| Altitude | Number | Tiles above ground |
| AltitudeInDeciTiles | Number | Tenths of a tile above ground |
| SizeWhenForceMoved | Number | Effective size when force moved |
| Reach | Number | Reach in squares |
| Walking Speed | Number | Walking speed in squares |
| Flying Speed | Number | Flying speed (0 if cannot fly) |
| Burrowing Speed | Number | Burrowing speed (0 if cannot burrow) |
| Movement Speed | Number | Total movement per round |
| Moved This Turn | Number | Distance moved this turn |
| Charge Distance | Number | Straight-line distance this turn |
| Movement Type | Text | Current type: "Walk", "Swim", "Fly", etc. |
| Movement Multiplier | Number | Movement distance multiplier |
| Mounted | Boolean | Is mounted |
| Mount | Creature | Creature being ridden |
| Number of Creatures Grabbed | Number | Grabbed creature count |

Additional movement types (Climbing, Swimming, Teleport, etc.) generate speed fields with the same naming pattern.

### Auras

| Field | Type | Description |
|---|---|---|
| Auras Affecting | Text set | Active aura names (use `has`) |
| AurasCaster | Function | `AurasCaster("Aura Name")` -- returns projecting creature |

### Conditions and Effects

| Field | Type | Description |
|---|---|---|
| Conditions | Set | Condition names (use `has`: `Conditions has "Grabbed"`) |
| Ongoing Effects | Set | Ongoing effect names (use `has`) |
| Save Ends Effects | Number | Active save-ends effect count |
| Condition Stacks | Number | Total condition stacks |
| Condition Count | Number | Distinct condition count |
| Stacks | Function | `Stacks("Condition Name")` -- stack count |
| Condition Immunities | Set | Immune conditions |
| Effect Caster | Text | ID of condition/effect applier |
| ConditionCaster | Function | `ConditionCaster("Grabbed")` -- returns applier creature |
| CasterSet | Function | Returns set of creatures that applied an ongoing effect |
| Last Caster | Creature | Last saving throw trigger creature |

### Squad and Summoning

| Field | Type | Description |
|---|---|---|
| Bound Creatures | Number | Bound creature count |
| Bound Ongoing Effect | Text | Binding effect ID |
| Complications | Number | Complication count |
| AdjacentAlliesWithFeature | Function | Count of adjacent allies with named feature |
| Summoned | Boolean | Was summoned |
| Summoner | Creature | Summoning creature |
| SquadCaster | Function | Squad that applied named ongoing effect |
| SquadLiveMembers | Function | Living member count of named squad |

### Monster-Only Fields

| Field | Type | Description |
|---|---|---|
| Free Strike Damage | Number | Free strike damage value |
| Free Strike Range | Number | Free strike range |
| EV | Number | Encounter value |

### Other

| Field | Type | Description |
|---|---|---|
| Victories | Number | Party victory count |
| Kit | Text | Equipped kit name |
| Game Mode | Text | "Combat", "Respite", etc. |
| Routine Distance | Number | Monster routine calculation distance |
| Num Dead Languages | Number | Known dead language count |
| Dead Languages | Text | Known dead languages |
| Languages | Set | Known languages |

### Creature Functions

| Field | Type | Description |
|---|---|---|
| Distance | Function | `Distance(Target)` -- distance in squares |
| Count Nearby Enemies | Function | `Count Nearby Enemies(5)` -- live enemies in range. Optional filters: group names, feature names, creatures to exclude. |
| Count Nearby Friends | Function | `Count Nearby Friends(5)` -- live allies in range. Same filters. |
| Count Nearby Creatures | Function | `Count Nearby Creatures(5)` -- all live creatures. Accepts `"ally"`, `"enemy"`, group/feature/creature filters. |
| Count Riders | Function | `Count Riders("goblin")` -- riders matching filter |

---

## Custom Attribute Symbols

Every custom attribute in the compendium automatically becomes a GoblinScript symbol on all
creatures. Example: `Cast.Natural Roll >= Caster.Critical Threshold`.

| Symbol | Type | Default | Description |
|---|---|---|---|
| Winded | Boolean | Calculated | `Stamina <= Maximum Stamina / 2` |
| Charging | Boolean | 0 | In charging state during ability use |
| Has Cover | Boolean | 0 | Has cover |
| Can Fly | Number | 0 | Non-zero if can fly |
| Can Burrow | Number | 0 | Non-zero if can burrow |
| Grab Characteristic | Value | Might | Characteristic for grab checks |
| Critical Threshold | Number | 19 | Minimum natural roll for critical hit |
| SummonerRange | Number | 5 + Reason | Max summoner ability distance |
| MaximumMinions | Number | 8 | Max active minions |
| Ignore Concealment Within Range | Number | 0 | Range within which concealment is ignored |

Custom attributes from classes or homebrew also become symbols automatically.

---

## Ability Fields

Available on `Ability` and `UsedAbility` subjects.

| Field | Type | Description |
|---|---|---|
| Name | Text | Ability name |
| Keywords | Text | Keywords (use `has`: `Ability.Keywords has "Strike"`) |
| Range | Number | Range in squares |
| Level | Number | Acquisition level |
| Categorization | Text | "Signature Ability", "Heroic Ability", etc. |
| Allegiance | Text | `"ally"`, `"enemy"`, `"dead"`, or `"all"` |
| Action | Boolean | Consumes an Action |
| Maneuver | Boolean | Consumes a Maneuver |
| Main Action | Boolean | Is a main action |
| Heroic | Boolean | Is a Heroic Ability |
| Trigger | Boolean | Has a trigger |
| Heroic Resource Cost | Number | Heroic resource cost (0 if none) |
| Malice Cost | Number | Malice cost (0 if none) |
| Has Attack | Boolean | Includes a power roll attack |
| Has Heal | Boolean | Includes healing |
| Does Damage | Boolean | Deals damage |
| Has Forced Movement | Boolean | Includes forced movement |
| Has Potency | Boolean | Has potency |
| Spell | Boolean | Is a spell |
| Free Strike | Boolean | Is a free strike |
| Usable As Free Strike | Boolean | Can be used as free strike |
| Usable As Signature Ability | Boolean | Can be used as signature ability |
| Damage Types | Text | Damage types dealt |
| Inflicts | Text | Conditions/effects inflicted |
| Number Of Targets | Number | Max target count |
| Weapon Attack | Boolean | Uses weapon attack |

---

## Cast Fields

Available during ability resolution (after power roll, while applying effects).

| Field | Type | Description |
|---|---|---|
| High Roll | Number | Higher d10 result |
| Low Roll | Number | Lower d10 result |
| Natural Roll | Number | Raw d10 total before bonuses |
| Roll | Number | Final power roll with all bonuses |
| Tier | Number | Power roll tier (1, 2, or 3) |
| Tier For Target | Number | Tier for a specific target |
| Target Count | Number | Creatures targeted |
| Spaces Moved | Number | Squares moved during ability |
| Damage Dealt | Number | Total damage dealt |
| Damage Raw | Number | Damage before reductions |
| Healing | Number | Total healing done |
| Heal Roll | Number | Raw healing roll |
| First Target | Creature | First targeted creature |
| Primary Target | Creature | Primary target |
| Has Primary Target | Boolean | Primary target selected |
| Has Target | Boolean | At least one target hit |
| Ability | Ability | Ability being cast |
| Memory | Text | Stored value for multi-step execution |
| Mode | Text | Cast mode identifier |
| Inflicted Conditions | Text | Conditions inflicted |
| Purged Conditions | Text | Conditions removed |
| Forced Movement Distance | Number | Total forced movement |
| Forced Movement Collision | Boolean | Forced movement collision occurred |
| Opportunity Attacks Triggered | Boolean | Opportunity attack triggered |
| Heroic Resources Gained | Number | Heroic resources gained |
| Number Of Added Creatures | Number | Creatures added to encounter |
| Creature List Size | Number | Creature list size |
| Passes Potency | Function | `Passes Potency(target, characteristic, potency)` |

---

## Path Fields

Available in movement formula fields and movement trigger contexts.

| Field | Type | Description |
|---|---|---|
| Squares | Number | Squares moved |
| Shift | Boolean | Is a shift |
| Forced | Boolean | Is forced movement |
| Vertical Only | Boolean | Is vertical only |
| Distance To Creature | Function | Distance from path to a creature |

---

## Aura and Ongoing Effect Fields

| Field | Type | Description |
|---|---|---|
| Caster | Creature | Creator of the aura or ongoing effect. Access fields: `Aura.Caster.Level` |

---

## Global Functions

| Function | Description |
|---|---|
| `Friends(creatureA, creatureB)` | True if same side. `not Friends(Target, Caster)` for enemies. |
| `Line of Sight(creatureA, creatureB)` | 1 = clear, 0.5 = half cover, 0.25 = three-quarter cover, 0 = blocked. |
| `Substring(haystack, needle)` | True if needle is found within haystack (case-insensitive). |

---

## Dice Notation

Available in roll fields (damage, healing, resources). Combines freely with GoblinScript: `2d10 + Might`.

| Syntax | Effect |
|---|---|
| `NdF` | Roll N dice with F faces |
| `NdF + M` / `NdF - M` | Flat modifier |
| `4d6 keep 3` / `4d6k3` | Keep highest 3 |
| `4d6 drop 1` | Drop lowest 1 |
| `4d6 keep low 3` / `4d6kl3` | Keep lowest 3 |
| `3d6 reroll 2` | Reroll dice showing <= 2 (once each) |
| `2d10 minroll 4` | Each die counts as at least 4 |
| `2d8 extradie` | Add one die matching highest-face die |
| `3d8 + dicecount` | `dicecount` = number of dice (here 3) |
| `2d6 exploding` | Max value dice reroll and add (recursive) |
| `2d6 + 4 alter "(count*2) d faces + modifier"` | Transform dice pool. Variables: `count`, `faces`, `modifier`, `index`. |

---

## Special Syntax

### Inline Text Substitution: `{expression}`

In text fields, `{expression}` is replaced with the evaluated result. With fallback:
`{expression|fallback text}` shows fallback when expression cannot evaluate.

```
The target can shift {Reason|a number of squares equal to your Reason score}.
```

### Parameter Pipe: `<<expression>>`

In Standard Abilities, `<<parametername>>` marks a parameter slot. In Invoke Ability
behaviors, `<<expression>>` passes a runtime value:

```
targetid: "<<Cast.Primary Target.ID>>"
```

---

## Formula Field Types

### Filter/Condition Fields (return boolean)

`Target Filter`, `Filter Target`, `Activation Condition`, `Display Condition`,
`Filter Condition`, `Filter Ability`, `Prerequisite`, `Sustain Formula`, `Condition Formula`

### Value/Calculation Fields (return number)

`Value`, `Num`, `Roll` (supports dice), `Stacks`, `Calculation`, `Formula`, `Quantity`,
`Damage Modifier`, `Potency Mod`

### Text Fields with `{expression}` Substitution

`Description`, `Effect`, `Rule`, `Trigger Prompt`, `Prompt Text`, `Add Text`, `Replace Text`
