# Game Rules -- Foundation Layer

The `DMHub Game Rules/` directory is the **system-agnostic foundation** of the rules engine. It contains **106 Lua files** that define the base types for creatures, abilities, conditions, classes, equipment, and more. This layer knows nothing about Draw Steel specifically -- it provides the scaffolding that any game system can build on.

!!! info "Why system-agnostic?"
    The Game Rules layer uses generic names internally (e.g. "Hitpoints", "Attribute", "Saving Throw"). The Draw Steel layer overrides these with DS-specific terminology (Stamina, Characteristic, Resistance). This separation allows the same engine to support multiple RPG systems.

## Core types

All game types are registered with `RegisterGameType()`, which plugs them into the engine's serialization and networking system:

```lua
CharacterCondition = RegisterGameType("CharacterCondition", "CharacterFeature")
CharacterCondition.name = "New Condition"
CharacterCondition.tableName = "charConditions"
```

The second argument is an optional parent type for inheritance.

### Key type hierarchy

| Type | Parent | Purpose |
|------|--------|---------|
| `GameSystem` | -- | Global rules configuration (roll formulas, naming, initiative) |
| `creature` | -- | Base type for all creatures on the map |
| `Character` | `creature` | Player characters with classes, feats, equipment |
| `Monster` | `creature` | Bestiary entries with CR, legendary actions |
| `ActivatedAbility` | -- | Any usable ability (attacks, spells, maneuvers) |
| `ActivatedAbilityBehavior` | -- | Individual effect within an ability (damage, heal, condition) |
| `CharacterCondition` | `CharacterFeature` | Conditions applied to creatures (stunned, bleeding, etc.) |
| `CharacterModifier` | -- | Passive modifiers that alter stats or rolls |
| `Class` | -- | Character class definitions |
| `Race` | -- | Ancestry/race definitions |
| `Equipment` | -- | Items and gear |

### ActivatedAbility in detail

`ActivatedAbility` is one of the most important types. It represents any action a creature can take -- attacks, spells, maneuvers. Key fields include:

| Field | Type | Description |
|-------|------|-------------|
| `description` | `string` | Rules text shown to players |
| `range` | `number` | Targeting range in world units |
| `behaviors` | `ActivatedAbilityBehavior[]` | List of effects that execute on cast |
| `actionResourceId` | `string` | Resource consumed to use (e.g. action, bonus action) |
| `targetFilter` | `string` | GoblinScript formula filtering valid targets |
| `categorization` | `string` | Category: `"action"`, `"maneuver"`, `"none"` |
| `concentration` | `boolean` | Whether the effect requires concentration |

Behavior subtypes handle specific effects:

- `ActivatedAbilityAttackBehavior` -- attack rolls
- `ActivatedAbilityDamageBehavior` -- damage dealing
- `ActivatedAbilityHealBehavior` -- healing
- `ActivatedAbilityApplyOngoingEffectBehavior` -- applying lasting effects

### CharacterCondition

Conditions are registered in the `"charConditions"` data table and support stacking, immunity, caster tracking, and sustain formulas:

```lua
CharacterCondition.stackable = false
CharacterCondition.immunityPossible = false
CharacterCondition.buffType = "debuff"  -- "debuff", "buff", or "neutral"
```

## Important files

| File | Description |
|------|-------------|
| `Creature.lua` | Base `creature` type, `StatHistory`, `GameSystem` registration |
| `Character.lua` | Player character type with class, level, and equipment slots |
| `Monster.lua` | Monster/NPC type with CR and bestiary integration |
| `ActivatedAbility.lua` | Ability system with behaviors, targeting, and resource costs |
| `Condition.lua` | `CharacterCondition` type and condition-rider system |
| `Class.lua` | Character class definitions and progression |
| `BasicRules.lua` | Default rule values and base calculations |
| `GameSystem.lua` | `GameSystem` global configuration methods |
| `Equipment.lua` | Item types, properties, and inventory management |
| `Skills.lua` | Skill definitions and proficiency |
| `Race.lua` | Ancestry/race definitions |
| `Resource.lua` | Action resources (actions, bonus actions, reactions) |
| `CharacterModifier.lua` | Modifier framework for passive stat changes |
| `InitiativeQueue.lua` | Turn order and initiative tracking |
| `DamageTypes.lua` | Damage type registry |
| `OngoingEffect.lua` | Duration-based effects on creatures |
| `GoblinScriptDocs.lua` | Symbol documentation for the formula language |

## Data storage pattern

Game data lives in named tables accessed through the engine:

```lua
local conditionsTable = dmhub.GetTable("charConditions")
for id, condition in unhidden_pairs(conditionsTable) do
    -- iterate over all conditions
end
```

Write back with `dmhub.SetAndUploadObject("charConditions", id, obj)`.
