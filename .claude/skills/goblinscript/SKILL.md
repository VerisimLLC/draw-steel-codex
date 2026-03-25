---
name: goblinscript
description: |
  Help users understand, write, and debug GoblinScript formulas, or expose new fields to GoblinScript from Lua.
  Use when the user mentions GoblinScript, creature formulas, damage formulas, target filters, ability costs,
  prerequisite expressions, custom attributes, RegisterGoblinScriptField, RegisterSymbol, EvalGoblinScript,
  ExecuteGoblinScript, or the Character Inspector panel.
  Also trigger when the user asks "how do I make a formula for...", "how does the damage calculation work",
  "what symbols can I use in...", or wants to add a new computable field to creatures or abilities.
metadata:
  author: draw-steel-codex
  version: "1.0.0"
  argument-hint: <formula-or-field-description>
---

# GoblinScript Skill

GoblinScript is the domain-specific expression language used throughout DMHub for game math: damage rolls, ability costs, target filters, prerequisites, custom attributes, and more. It looks like natural-language formulas -- e.g. `2d6 + Might` or `Stamina <= Maximum Stamina / 2`.

## Quick Reference: Syntax

### Operators
| Category | Operators |
|---|---|
| Arithmetic | `+`, `-`, `*`, `/`, `%` |
| Comparison | `=`, `!=`, `<`, `>`, `<=`, `>=` |
| String comparison | `is`, `is not` |
| Logical | `and`, `or`, `not` |
| Conditional | `EXPR when COND`, `EXPR when COND else EXPR` |
| Set membership | `SET has "value"`, `SET has not "value"` |
| Local binding | `EXPR where VAR = EXPR` |
| Dice (non-deterministic only) | `NdM` (e.g. `2d6`, `1d10`) |

### Built-in Functions
| Function | Description |
|---|---|
| `min(a, b, ...)` | Minimum of values |
| `max(a, b, ...)` | Maximum of values |
| `floor(x)` | Round down |
| `ceiling(x)` | Round up |
| `friends(a, b)` | True if creatures a and b are friendly |
| `lineofsight(a, b)` | Line of sight modifier (0-1) |
| `substring(haystack, needle)` | True if needle is found in haystack |

### Key Rules
- **Case-insensitive**: `Stamina`, `stamina`, and `STAMINA` are equivalent.
- **Spaces in names are ignored for lookup**: `Walking Speed` and `walkingspeed` resolve to the same symbol.
- **Unresolved symbols silently return 0** (or false for booleans). Check spelling carefully.
- **`self.` prefix** references the subject creature explicitly: `self.Stamina`, `self.Conditions has "Poisoned"`.
- **Boolean results**: true evaluates to 1, false to 0 in numeric contexts.

## Deterministic vs Non-Deterministic

| Type | Contains dice? | Evaluation function | Returns |
|---|---|---|---|
| Deterministic | No | `ExecuteGoblinScript()` or `dmhub.EvalGoblinScriptDeterministic()` | number |
| Non-deterministic | Yes (e.g. `2d6`) | `dmhub.EvalGoblinScript()` | string (e.g. "1d10+5") |

Most GoblinScript fields are deterministic (costs, prerequisites, attribute values). Damage rolls and quantity formulas can be non-deterministic.

## Example Formulas

```
-- Simple constant
3

-- Arithmetic with creature stats
2 * Might + 4

-- Conditional
5 when Level >= 5 else 3

-- Complex conditional
2 + 5 when Stamina > 5 and Level = 1 else 12

-- Set membership (conditions, keywords)
self.Conditions has "Poisoned"

-- Dice roll (non-deterministic)
2d6 + Might

-- Using max/min
Max(1, Max(Might, Agility))

-- Local variable binding
Stamina + x where x = 7

-- Checking winded status
Stamina <= Maximum Stamina / 2

-- Resource check
Resources.Heroic Resource < 0

-- Function call symbol
AdjacentAlliesWithFeature('Captain') >= 1

-- Potency check (on ActivatedAbilityCast)
PassesPotency('2')
```

## Common Creature Symbols

These are available on any creature via `self.SYMBOL` or just `SYMBOL`:

| Symbol | Type | Description |
|---|---|---|
| `Name` | text | Creature name |
| `Type` | text | Monster type (e.g. "Undead") |
| `Subtype` | text | Monster subtype |
| `Level` | number | Creature level |
| `Stamina` | number | Current stamina (hit points) |
| `Maximum Stamina` | number | Max stamina |
| `Armor Class` | number | AC value |
| `Size` | number | Creature size |
| `Walking Speed` | number | Walking movement speed |
| `Might` | number | Might characteristic |
| `Agility` | number | Agility characteristic |
| `Reason` | number | Reason characteristic |
| `Intuition` | number | Intuition characteristic |
| `Presence` | number | Presence characteristic |
| `Conditions` | set | Active conditions -- use `has` operator |
| `Weapons Wielded` | number | Number of weapons wielded |
| `Two Handed` | boolean | Wielding a two-handed weapon? |
| `Victories` | number | Hero victories count |
| `Hero` | boolean | Is this a hero (PC)? |

### Ability Symbols (on ActivatedAbility)
| Symbol | Type | Description |
|---|---|---|
| `Maneuver` | boolean | Is this a maneuver? |
| `Trigger` | boolean | Is this a trigger ability? |
| `Heroic` | boolean | Costs heroic resources? |
| `HeroicResourceCost` | number | Number of heroic resources |
| `MaliceCost` | number | Malice cost |
| `Categorization` | text | Category name |
| `Keywords` | set | Ability keywords -- use `has` operator |

### Cast Symbols (on ActivatedAbilityCast)
| Symbol | Type | Description |
|---|---|---|
| `Boons` | number | Number of boons on this cast |
| `Banes` | number | Number of banes on this cast |
| `HighestNumberOnAttackDice` | number | Highest die result |
| `PassesPotency` | function | Check potency tier: `PassesPotency('2')` |

## Custom Attributes

Custom Attributes are user-definable creature fields visible in GoblinScript and editable via Character Modifiers. They live in `userdata/tables/customattributes/`.

### YAML format
```yaml
__typeName: CustomAttribute
name: Forced Movement Bonus
baseValue: "0"
id: "b92d0101-f9a6-4c66-81e4-cdad46e6f1bb"
documentation: The amount of additional spaces this creature can move another creature when it inflicts forced movement.
category: Forced Movement
mtime: 1755646514511
ctime: 1755646514511
```

Fields:
- `name` -- The GoblinScript symbol name (case-insensitive, spaces removed for lookup)
- `baseValue` -- Default value; can itself be a GoblinScript formula (e.g. `Max(0, Agility)`, `Stamina <= Maximum Stamina/2`, `Might`)
- `documentation` -- Optional description shown in Character Inspector
- `category` -- Optional grouping for UI display
- `attributeType` -- Optional: `number` (default), `stringset`, `creatureset`
- `possibleValues` -- For `stringset` type: array of allowed string values

### Examples from the compendium
| Custom Attribute | Base Value | Purpose |
|---|---|---|
| `Winded` | `Stamina <= Maximum Stamina/2` | Boolean: is creature below half stamina? |
| `Fall Reduction` | `Max(0, Agility)` | Squares of fall damage reduction |
| `SummonerRange` | `5 + Reason` | Max distance for summoning |
| `Jump Distance` | `Max(1, Max(Might, Agility))` | Long jump distance in squares |
| `Dying Value` | `Maximum Stamina/2` | Stamina threshold for death |
| `Charging Speed` | `Walking Speed` | Speed during Charge maneuver |
| `Grab Characteristic` | `Might` | Characteristic used for grab checks |
| `Save Ends` | `6` | Target number for save-ends rolls |
| `Maximum Surges` | `3` | Max recovery surges |

## Evaluating GoblinScript from Lua

### Deterministic (no dice)
```lua
-- ExecuteGoblinScript is the high-level wrapper (caches compiled formulas)
local result = ExecuteGoblinScript(
    formula,        -- string: the GoblinScript expression
    symbols,        -- function: symbol lookup (from GenerateSymbols or LookupSymbol)
    defaultValue,   -- number: returned if evaluation fails
    contextMessage  -- string: description for debugging
)

-- Example: evaluate an ability prerequisite
local available = ExecuteGoblinScript(
    "Level >= 5 and Stamina >= 20",
    hero:LookupSymbol(),
    0,
    "Check prerequisite"
)
if available > 0 then
    -- prerequisite met
end
```

### Non-deterministic (with dice)
```lua
-- Returns a string like "1d10+5" or a resolved number
local rollExpr = dmhub.EvalGoblinScript(
    "2d6 + Might",
    casterToken.properties:LookupSymbol(options.symbols),
    "Damage roll"
)
```

### Symbol lookup functions
```lua
-- From a creature (most common)
local symbols = myCreature:LookupSymbol()

-- With additional custom symbols merged in
local symbols = myCreature:LookupSymbol(options.symbols)

-- From GenerateSymbols directly (for non-creature objects)
local symbols = GenerateSymbols(myObject, extraSymbolTable)
```

### Explaining a formula (debugging)
```lua
dmhub.ExplainDeterministicGoblinScript(
    formula,
    lookupFunction,
    function(explanation)
        -- explanation is a breakdown of how the formula was evaluated
    end
)
```

## Exposing New Fields to GoblinScript

There are two ways to register new symbols.

### Method 1: GameSystem.RegisterGoblinScriptField (preferred for non-creature types)

Works for any type (creature, ActivatedAbility, ActivatedAbilityCast, etc.). Defaults to creature if no target specified.

```lua
GameSystem.RegisterGoblinScriptField{
    target = ActivatedAbility,  -- omit for creature
    name = "My Field Name",     -- display name (becomes symbol)
    type = "number",            -- "number", "boolean", "text", "set", "function"
    desc = "Description of what this field returns.",
    seealso = {"Related Field"},
    examples = {"self.My Field Name > 5"},
    calculate = function(obj)
        -- obj is the target type instance (creature, ability, etc.)
        return obj:try_get("myData", 0)
    end,
}
```

Implementation (in `DMHub Game Rules/GameSystem.lua`):
```lua
function GameSystem.RegisterGoblinScriptField(args)
    RegisterGoblinScriptSymbol(args.target or creature, args)
end
```

### Method 2: creature.RegisterSymbol (creature-only, propagates to character + monster)

Registers on creature, character, and monster simultaneously.

```lua
creature.RegisterSymbol{
    symbol = "myfieldname",     -- lowercase lookup key
    help = {
        name = "My Field Name",
        type = "number",
        desc = "Description of what this field returns.",
        seealso = {},
        examples = {"self.myfieldname > 5"},
    },
    lookup = function(c)
        -- c is the creature
        return c:try_get("myData", 0)
    end,
}
```

### Function-type symbols (callable from GoblinScript)

```lua
creature.RegisterSymbol{
    symbol = "adjacentallieswithfeature",
    help = {
        name = "AdjacentAlliesWithFeature",
        type = "function",
        desc = "Given the name of a feature, returns the number of adjacent allies with that feature.",
    },
    lookup = function(c)
        return function(featurename)
            local token = dmhub.LookupToken(c)
            if token == nil then return 0 end
            local count = 0
            local nearbyTokens = token:GetNearbyTokens(1)
            for i, nearby in ipairs(nearbyTokens) do
                if nearby:IsFriend(token) and (not nearby.properties:IsDownCached()) then
                    local features = nearby.properties:try_get("characterFeatures", {})
                    for _, feature in ipairs(features) do
                        if string.lower(feature.name) == string.lower(featurename) then
                            count = count + 1
                        end
                    end
                end
            end
            return count
        end
    end,
}
```

Usage in GoblinScript: `AdjacentAlliesWithFeature('Captain') >= 1`

### Internal mechanics

`RegisterGoblinScriptSymbol` (in `DMHub Game Rules/Creature.lua`) does two things:
1. Stores the calculate/lookup function in `targetType.lookupSymbols[normalizedKey]`
2. Stores help metadata in `targetType.helpSymbols[normalizedKey]`

The key is derived by lowercasing and stripping spaces from the name.

If the target type has `derivedTypes`, the symbol is automatically registered on all derived types too.

## GoblinScript in UI (gui.GoblinScriptInput)

The editor widget for GoblinScript formulas supports autocomplete and inline help.

```lua
gui.GoblinScriptInput{
    value = self.formula,
    change = function(element)
        self.formula = element.value
    end,

    documentation = {
        help = "This GoblinScript determines the damage dealt.",
        output = "roll",  -- "number", "roll", or "text"
        examples = {
            {
                script = "2d6 + Might",
                text = "Rolls 2d6 plus the caster's Might.",
            },
        },
        subject = creature.helpSymbols,
        subjectDescription = "The caster",
        symbols = ActivatedAbility.helpCasting,
        domains = ability.domains,  -- optional domain filter
    },
}
```

Documentation fields:
- `help` -- Main help text shown in the editor dialog
- `output` -- Expected output type (`"number"` = deterministic, `"roll"` = allows dice, `"text"`)
- `examples` -- Array of `{script, text}` pairs
- `subject` -- Symbol help table for the primary object (`creature.helpSymbols`)
- `subjectDescription` -- Human-readable label for the subject
- `symbols` -- Additional symbol tables (e.g. `ActivatedAbility.helpCasting`)
- `domains` -- Optional: filters symbols by domain/class

## Debugging GoblinScript

### Character Inspector
Users can open **Developer > Character Inspector** to select a creature and see all GoblinScript fields evaluated live. This is the primary debugging tool.

### Chat command
```
/goblinscriptunittest
```
Runs the built-in GoblinScript test suite.

### Flush compiled cache
```
/flushcompiledgoblinscript
```
Clears the compiled formula cache -- useful if formulas seem stale.

### Common issues
| Problem | Likely cause |
|---|---|
| Formula returns 0 | Unresolved symbol name (typo, wrong case, missing registration) |
| "near 'en'" parse error | Non-ASCII characters in Lua source file (em dash, curly quote, etc.) |
| Formula works for caster but not target | Using wrong symbol context (subject vs target) |
| Dice in a deterministic context | Using `NdM` notation where only a number is expected |

## Where GoblinScript is Used

| Context | Deterministic? | Subject | Examples |
|---|---|---|---|
| Ability damage roll | No | Caster creature | `2d6 + Might` |
| Ability cost/resource number | Yes | Caster creature | `3`, `Mode = 2 then 3 else 1` |
| Target filter (`filterTarget`) | Yes | Target creature | `Target.Conditions has "Slowed"` |
| Prerequisite | Yes | Hero creature | `Level >= 5` |
| Custom attribute base value | Yes | Owner creature | `Maximum Stamina / 2` |
| Ability range | Yes | Caster creature | `5`, `SummonerRange` |
| Number of targets | Yes | Caster creature | `1`, `Level` |
| Aura damage | Yes | Affected creature | `3` |
| Summoning filter | Yes | Bestiary creature | `beast.cr = 1` |
| Potency check | Yes | ActivatedAbilityCast | `PassesPotency('2')` |

## Key Source Files

| File | Contains |
|---|---|
| `DMHub Utils/GoblinScript.lua` | Core evaluation engine, ExecuteGoblinScript, compiled formula cache |
| `DMHub Game Rules/GameSystem.lua` | `GameSystem.RegisterGoblinScriptField` wrapper |
| `DMHub Game Rules/Creature.lua` | `RegisterGoblinScriptSymbol`, `creature.RegisterSymbol`, built-in creature symbols (`helpSymbols`, `lookupSymbols`) |
| `Draw Steel Core Rules/MCDMSymbols.lua` | Draw Steel-specific creature symbols (Victories, AdjacentAlliesWithFeature, etc.) |
| `Draw Steel Core Rules/MCDMActivatedAbility.lua` | Ability-level GoblinScript fields (Keywords, HeroicResourceCost, etc.) |
| `Draw Steel Core Rules/MCDMActivatedAbilityCast.lua` | Cast-level fields (Boons, Banes, PassesPotency, etc.) |
| `DMHub Core Panels/GoblinScriptEditor.lua` | `gui.GoblinScriptInput` widget and editor dialog |
| `Definitions/dmhub.lua` | Engine API stubs for EvalGoblinScript, CompileGoblinScriptDeterministic, etc. |
| `Development Utilities/GoblinScriptDebugger.lua` | Debug panel and formula tracing |
| `userdata/tables/customattributes/` | All custom attribute definitions (YAML) |
