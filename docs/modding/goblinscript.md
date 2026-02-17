# GoblinScript Reference

GoblinScript is the built-in expression language used throughout DMHub for game formulas — damage calculations, target filters, conditional effects, stamina formulas, and more. It is evaluated at runtime against a **symbol table** (usually derived from a creature's stats).

---

## Syntax Overview

GoblinScript expressions look like natural-language math:

```
18 + (Level - 1) * 6
1d6 + Might Modifier
enemy and distance(self) <= 5
```

Symbols are **case-insensitive**. `Level`, `LEVEL`, and `level` all resolve the same way.

---

## Operators

### Arithmetic

| Operator | Description |
|---|---|
| `+` | Addition |
| `-` | Subtraction / negation |
| `*` | Multiplication |
| `/` | Division |
| `%` | Modulo |
| `( )` | Grouping |

### Comparison

| Operator | Description |
|---|---|
| `=` | Equals |
| `!=` | Not equals |
| `~=` | Not equals (alternate) |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |

Comparisons return `1` (true) or `0` (false).

### Logical

| Operator | Description |
|---|---|
| `and` | Both sides truthy |
| `or` | Either side truthy (returns first truthy value) |
| `not` | Negation |

### Set Membership

```
conditions has "Poisoned"
ongoingeffects has "Blessed"
```

The `has` operator checks whether a `StringSet` or `CreatureSet` contains a value.

### Member Access

```
self.shield
self.shield.armorClassModifier
target.hitpoints
```

Dot notation accesses properties on objects (creatures, equipment, etc.).

---

## Conditionals

### `when` — Conditional Value

```
5 when stamina > 5
```

Returns `5` if `stamina > 5`, otherwise `0`.

### `when ... else` — Ternary

```
2 + 5 when stamina > 5 and level = 1 else 12
```

Returns `2 + 5` if the condition holds, otherwise `12`.

### `or` chains — Fallback Values

```
stamina or level or 4
```

Returns the first truthy (non-zero) value.

---

## Local Bindings

### `where` — Scoped Variables

```
stamina + x where x = 7
```

Introduces a local variable `x` scoped to the expression.

---

## Built-in Functions

| Function | Description |
|---|---|
| `min(a, b, ...)` | Minimum of any number of values |
| `max(a, b, ...)` | Maximum of any number of values |
| `floor(n)` | Round down |
| `ceiling(n)` | Round up |
| `substring(haystack, needle)` | String contains check |
| `friends(a, b)` | Check if two creatures are friends |
| `lineofsight(a, b)` | Line of sight check (returns 0–1) |

```
max(10, 20)                  --> 20
floor(3.7)                   --> 3
ceiling(3.2)                 --> 4
min(stamina, 118, 4, 170)   --> 4
```

---

## Dice Expressions

GoblinScript supports inline dice notation:

```
1d6 + Might Modifier
2d10 + 5
1d6 + level
```

Dice rolls are **non-deterministic**. Use `dmhub.IsRollDeterministic(formula)` to check if a formula contains dice.

---

## Creature Symbols

When evaluated against a creature, the following symbols are available:

### Identity

| Symbol | Type | Description |
|---|---|---|
| `self` | Creature | The creature itself |
| `level` / `characterlevel` | number | Character level |
| `name` | string | Creature/monster name |
| `type` | string | Race or monster type |
| `subtype` | string | Monster subtype |
| `id` | number | Token ID hash |
| `always` | number | Always `1` |
| `never` | number | Always `0` |

### Combat Stats

| Symbol | Type | Description |
|---|---|---|
| `hitpoints` / `hp` | number | Current HP |
| `maximumhitpoints` | number | Maximum HP |
| `temporaryhitpoints` | number | Temporary HP |
| `armorclass` / `ac` | number | Armor class |
| `proficiencybonus` | number | Proficiency modifier |

### Attributes (Draw Steel)

| Symbol | Aliases | Description |
|---|---|---|
| `mgt` | `might` | Might score |
| `mgtmodifier` | `mightmodifier` | Might modifier |
| `agl` | `agility` | Agility score |
| `aglmodifier` | `agilitymodifier` | Agility modifier |
| `rea` | `reason` | Reason score |
| `reamodifier` | `reasonmodifier` | Reason modifier |
| `inu` | `intuition` | Intuition score |
| `inumodifier` | `intuitionmodifier` | Intuition modifier |
| `prs` | `presence` | Presence score |
| `prsmodifier` | `presencemodifier` | Presence modifier |

### Attributes (5e Compatibility)

| Symbol | Aliases | Description |
|---|---|---|
| `strength` | `str` | Strength score |
| `strengthmodifier` | `strmodifier` | Modifier |
| `dexterity` | `dex` | Dexterity score |
| `constitution` | `con` | Constitution score |
| `intelligence` | `int` | Intelligence score |
| `wisdom` | `wis` | Wisdom score |
| `charisma` | `cha` | Charisma score |

### Movement & Position

| Symbol | Type | Description |
|---|---|---|
| `movementspeed` | number | Current movement speed |
| `chargedistance` | number | Charge distance |
| `altitude` | number | Token altitude |
| `height` | number | Token height in tiles |
| `size` | number | Creature size value |
| `tilesize` | number | Tile size occupied |

### Equipment

| Symbol | Type | Description |
|---|---|---|
| `armor` | object | Current armor |
| `shield` | object | Current shield |
| `shieldbonus` | number | Shield AC bonus |
| `mainhanditem` | object | Main hand weapon |
| `offhanditem` | object | Off-hand item |
| `hasshield` | boolean | Has a shield equipped |
| `lightarmor` / `mediumarmor` / `heavyarmor` / `unarmored` | boolean | Armor type checks |

### Conditions & Effects

| Symbol | Type | Description |
|---|---|---|
| `conditions` | StringSet | Active condition names |
| `ongoingeffects` | StringSet | Active ongoing effects |
| `stacks(name)` | function | Stack count of an effect |
| `conditioncaster(name)` | function | Creature that applied a condition |
| `conditionimmunities` | StringSet | Condition immunities |

### Relationships & Context

| Symbol | Type | Description |
|---|---|---|
| `enemy` | boolean | Is this creature an enemy |
| `yourturn` | boolean | Is it this creature's turn |
| `distance(other)` | function | Distance to another creature |
| `summoned` | boolean | Is summoned |
| `summoner` | Creature | The summoner |
| `mounted` | boolean | Is mounted |
| `mount` | Creature | The mount |
| `friends` | function | Check friendship |

### Counts

| Symbol | Type | Description |
|---|---|---|
| `countnearbycreatures` | number | Nearby creatures |
| `countnearbyenemies` | number | Nearby enemies |
| `countnearbyfriends` | number | Nearby allies |
| `countriders` | number | Riders on this creature |
| `numberofcreaturesgrabbed` | number | Grabbed creatures |

### Spellcasting

| Symbol | Type | Description |
|---|---|---|
| `spellsavedc` | number | Spell save DC |
| `spellcastingabilitymodifier` | number | Spellcasting modifier |
| `spellcastingclasses` | number | Number of spellcasting classes |

### Skills & Proficiency

| Symbol | Type | Description |
|---|---|---|
| `proficient(name)` | function | Check proficiency |
| `skillmodifier(name)` | function | Skill modifier value |
| `savemodifier(name)` | function | Saving throw modifier |
| `languages` | StringSet | Known languages |

---

## Data Types

| Type | Description |
|---|---|
| **number** | Integer or float. Booleans convert to `1`/`0`. |
| **string** | Text values. Quoted with `"double quotes"`. |
| **StringSet** | Set of strings. Supports `has` and `.size`. |
| **CreatureSet** | Set of creature token IDs. Supports `has` and `.size`. |
| **object** | Game objects (creatures, abilities, items) with dot-access properties. |

---

## Registering Custom Symbols

### Method 1: `RegisterGoblinScriptSymbol()`

For typed symbols with help documentation:

```lua
RegisterGoblinScriptSymbol(creature, {
    name = "Stability",
    type = "number",
    desc = "The stability of this creature",
    examples = {"Self.Stability >= 3"},
    calculate = function(c)
        return c:Stability()
    end,
})
```

### Method 2: `creature.RegisterSymbol()`

Simpler registration with help:

```lua
creature.RegisterSymbol{
    symbol = "adjacentallieswithfeature",
    lookup = function(c)
        return function(featurename)
            -- count and return
        end
    end,
    help = {
        name = "AdjacentAlliesWithFeature",
        type = "function",
        desc = "Given a feature name, returns count of adjacent allies with it.",
    },
}
```

### Method 3: `creature.RegisterAttribute()`

Automatically creates both `attributename` and `attributenamemodifier` symbols:

```lua
creature.RegisterAttribute("might", { ... })
-- Creates: might, mightmodifier
```

### Method 4: Direct lookup table

```lua
creature.lookupSymbols["mysymbol"] = function(c)
    return 42
end
```

---

## Evaluation API

### From Lua Code

```lua
-- Deterministic evaluation (no dice)
local result = dmhub.EvalGoblinScriptDeterministic(
    "18 + (Level - 1) * 6",   -- formula
    lookupFunction,             -- symbol resolver
    0,                          -- default value on error
    "Stamina"                   -- debug context
)

-- Full evaluation (supports dice)
local result = dmhub.EvalGoblinScript(
    "1d6 + level",
    lookupFunction,
    "damage"
)

-- Evaluate to a Lua object
local obj = dmhub.EvalGoblinScriptToObject("self.weapon", lookupFunction)

-- Compile for repeated evaluation (cached)
local fn = dmhub.CompileGoblinScriptDeterministic("level * 2 + 5")
if fn then
    local result = fn(symbolTable)
end
```

### Symbol Resolution

The `lookupFunction` is typically created from a creature:

```lua
local symbols = creature:GenerateSymbols()
-- or with overrides:
local symbols = creature:GenerateSymbols({ customSymbol = 42 })
```

### Utility Functions

```lua
dmhub.RollInstant("2d10+5", lookup)       -- instant roll, returns number
dmhub.RollExpectedValue("2d10")            -- 11
dmhub.RollMinValue("2d10")                 -- 2
dmhub.RollMaxValue("2d10")                 -- 20
dmhub.NormalizeRoll("2d10+5", nil, "tag")  -- readable string
dmhub.IsRollDeterministic("2d10+5")        -- false (has dice)
dmhub.ParseRoll("2d10+5", lookup)          -- component breakdown

-- Explanation for debugging
dmhub.ExplainDeterministicGoblinScript(
    "level * 2",
    lookupFunction,
    function(symbol, has) return "Level is 5" end
)

-- Autocomplete for editor UIs
dmhub.AutoCompleteGoblinScript("sta", symbols)  -- suggests "stamina"
```

---

## Common Usage Patterns

### Ability Target Filters

```lua
ability.targetFilter = "enemy"
ability.targetFilter = "not enemy"
ability.targetFilter = "distance(self) <= 30"
ability.targetFilter = "target.hitpoints > 0"
```

### Damage Formulas

```lua
"1d6 + dexterity modifier"
"2d6 + (level - 1) / 2"
"floor((level + 10) / 2)"
```

### Conditional Effects

```lua
"5 when stamina > 5"
"damage + 1d6 when enemy and yourturn else 0"
"level or 1"
```

### Stamina / Resource Formulas

```lua
"18 + (Level - 1) * 6"
"max(stamina, 10)"
```

### Custom Attribute Base Values

```lua
customAttribute.baseValue = "level * 2 + strength modifier"
```

---

## Performance

GoblinScript formulas can be **compiled to Lua functions** and cached for repeated evaluation. This is controlled by the `compiledgoblinscript` setting.

```lua
-- Flush the compiled cache (debug command)
/flushcompiledgoblinscript
```

The compilation cache is per-formula. Compiled evaluation is significantly faster than interpreted evaluation for formulas that run every frame (e.g., token status bars).
