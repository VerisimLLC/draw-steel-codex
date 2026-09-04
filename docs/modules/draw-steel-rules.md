# Draw Steel Rules

The `Draw Steel Core Rules/` directory implements the **Draw Steel (MCDM) game system** on top of the foundation layer. It contains **63 Lua files** that override base types, rename concepts, define DS-specific mechanics, and wire up the 2d10 power roll system.

## How it overrides the foundation

The very first thing `MCDMRules.lua` does is wipe the slate clean:

```lua
GameSystem.ClearRules()
```

Then it immediately re-establishes all naming and configuration for Draw Steel:

```lua
GameSystem.HitpointsName      = "Stamina"
GameSystem.AttributeName       = "Characteristic"
GameSystem.SavingThrowName     = "Resistance"
GameSystem.BackgroundName      = "Career"
GameSystem.RaceName            = "Ancestry"
GameSystem.CRName              = "LVL"
GameSystem.BaseAttackRoll      = "2d10"
GameSystem.BaseSkillRoll       = "2d10"
GameSystem.LowerInitiativeIsFaster = true
```

!!! note "Terminology mapping"
    | Foundation term | Draw Steel term |
    |----------------|----------------|
    | Hit Points | Stamina |
    | Attribute | Characteristic |
    | Saving Throw | Resistance |
    | Background | Career |
    | Race | Ancestry |
    | Challenge Rating | Level |
    | d20 rolls | 2d10 Power Rolls |

## Extending base types

Draw Steel files extend existing types by saving the original method, then replacing it. `MCDMCreature.lua` demonstrates this pattern:

```lua
creature.minion = false
creature.initiativeGrouping = false

local g_baseInvalidate = creature.Invalidate
function creature:Invalidate()
    g_baseInvalidate(self)
    if mod.unloaded then return end
    self._tmp_calculatedAttributes = nil
    self._tmp_highestCharacteristic = nil
    -- ... clear DS-specific caches
end
```

This same file adds DS concepts like minion squads, potency, and stamina calculations:

```lua
function creature:SingleMinionMaxStamina()
    return g_creatureSingleMaxHitpoints(self)
end

function creature:Potency()
    return self:HighestCharacteristic()
end
```

!!! tip "The override pattern"
    Throughout the codebase, you will see this idiom:
    ```lua
    local g_base = someType.SomeMethod
    function someType:SomeMethod()
        g_base(self)
        -- DS-specific additions
    end
    ```
    The local `g_base` captures the original, then the new function calls it before adding game-specific behavior.

## Power Rolls and Boons

Draw Steel replaces d20 rolls with **2d10 Power Rolls** and uses a boon/bane system. `MCDMRules.lua` configures this:

```lua
GameSystem.UseBoons = true
GameSystem.CombineNegativesForRolls = true

GameSystem.AllowBoonsForRoll = function(options)
    return string.find(options.type, "power_roll") ~= nil
end
```

The `GameSystem.ApplyBoons` function modifies roll strings by adjusting the boon/bane count through the engine's `dmhub.ParseRoll` / `dmhub.RollToString` API.

## Key files

| File | Description |
|------|-------------|
| `MCDMRules.lua` | Core rules reset and DS configuration (naming, rolls, initiative) |
| `MCDMCreature.lua` | DS creature extensions (minions, potency, characteristics) |
| `MCDMClass.lua` | Draw Steel class system and subclass handling |
| `MCDMKit.lua` | Kit system (equipment/ability packages) |
| `MCDMAttack.lua` | DS attack mechanics and power roll integration |
| `MCDMActivatedAbility.lua` | DS-specific ability overrides |
| `MCDMActivatedAbilityCast.lua` | Casting flow for DS abilities |
| `MCDMAbilityRollBehavior.lua` | Power roll behavior within abilities |
| `MCDMMonster.lua` | Monster stat block extensions |
| `MCDMMinion.lua` | Minion squad mechanics |
| `MCDMInitiativeQueue.lua` | DS initiative (lower-is-faster, grouping) |
| `MCDMSkills.lua` | Draw Steel skill definitions |
| `MCDMSymbols.lua` | GoblinScript symbols for DS formulas |
| `DSResources.lua` | DS-specific action resources |
| `DSConditionRider.lua` | Condition rider system |
| `DSCulture.lua` | Culture definitions and bonuses |
| `DSCareer.lua` | Career (background) definitions |
| `DSComplications.lua` | Character complication system |
| `DSPowerRollTables.lua` | Power roll tier tables (T1/T2/T3) |
| `DSFollower.lua` | Follower/retainer system |
| `MCDMCustomRules.lua` | Homebrew rule toggles |

## File naming conventions

- **`MCDM*.lua`** -- Core type overrides and major systems
- **`DS*.lua`** -- Draw Steel feature implementations (culture, career, resources)
- **`MCDModify*.lua`** -- Modifier implementations specific to DS
- **`PowerTableTriggers.lua`** -- Trigger logic for tiered power roll results
