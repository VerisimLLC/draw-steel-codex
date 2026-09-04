# Abilities

Abilities in Draw Steel Codex follow a three-stage lifecycle: **definition**, **cast**, and **resolution**. The core types live in `DMHub Game Rules/` while the individual behavior implementations live in `Draw Steel Ability Behaviors/` (24 files).

---

## Lifecycle Overview

```
ActivatedAbility          ActivatedAbilityCast          Behavior execution
(data definition)  --->   (runtime cast state)   --->   (per-target effects)
```

1. **Definition** -- An `ActivatedAbility` object stores everything about *what* an ability does: range, targeting, resource costs, duration, and an ordered list of `behaviors`.
2. **Cast** -- When a creature uses the ability, an `ActivatedAbilityCast` is created. It accumulates runtime state: roll results, damage dealt, targets hit, forced movement paths, and per-target tier outcomes.
3. **Resolution** -- Each behavior in the ability's `behaviors` list executes in order against the cast's targets, applying damage, conditions, forced movement, and other effects.

---

## ActivatedAbility (Definition)

Registered in `DMHub Game Rules/ActivatedAbility.lua`:

```lua
ActivatedAbility = RegisterGameType("ActivatedAbility")
```

Key fields on every ability:

| Field | Type | Purpose |
|---|---|---|
| `description` | string | Rules text shown to players |
| `flavor` | string | Lore text for tooltips |
| `range` | number | Targeting range in world units |
| `selfTarget` | boolean | Always targets the caster |
| `castImmediately` | boolean | Auto-cast when no targeting choices exist |
| `actionResourceId` | string | Resource consumed to cast (e.g. an action) |
| `resourceCost` / `resourceNumber` | string / number | Secondary resource cost |
| `targetFilter` | string | GoblinScript formula filtering valid targets |
| `durationType` | string | `"instant"`, `"rounds"`, `"minutes"`, `"hours"`, or `"days"` |
| `concentration` | boolean | Requires concentration to maintain |
| `behaviors` | list | Ordered list of `ActivatedAbilityBehavior` objects |
| `categorization` | string | Category: `"none"`, `"action"`, `"maneuver"`, etc. |
| `multipleModes` | boolean | Ability has selectable modes |
| `isSpell` | boolean | Treated as a spell |

!!! info "GoblinScript integration"
    Fields like `targetFilter`, `rangeDisadvantage`, and `channelIncrement` accept GoblinScript formula strings. These are evaluated at cast time against the caster and target context.

---

## ActivatedAbilityCast (Runtime State)

Registered in `DMHub Game Rules/ActivatedAbilityCast.lua`:

```lua
ActivatedAbilityCast = RegisterGameType("ActivatedAbilityCast")
```

The cast object tracks everything that happens during resolution:

| Field | Type | Purpose |
|---|---|---|
| `tier` | number | Power roll result tier |
| `damagedealt` | number | Total damage dealt |
| `damageraw` | number | Raw (pre-mitigation) damage |
| `naturalattackroll` | number | Unmodified attack roll |
| `attackroll` | number | Final attack roll |
| `healing` | number | Total healing applied |
| `spacesMoved` | number | Spaces of forced movement applied |
| `targets` | table | List of targeted tokens |
| `tokenToTier` | table | Map of token to tier outcome |
| `inflictedConditions` | table | Conditions applied during the cast |
| `memory` | table or false | Custom per-cast memory for behaviors |
| `forcedMovementDamageDealt` | number | Damage from forced movement collisions |

The cast exposes these fields to GoblinScript via `helpSymbols`, so later behaviors can reference earlier results (e.g. damage dealt by a prior behavior).

---

## The Behavior System

Each `ActivatedAbility` contains an ordered list of **behaviors** -- small, composable units that define what happens when the ability resolves. The base type is:

```lua
ActivatedAbilityBehavior = RegisterGameType("ActivatedAbilityBehavior")
```

### Core Behavior Types (in `ActivatedAbility.lua`)

| Type | Purpose |
|---|---|
| `ActivatedAbilityAttackBehavior` | Make an attack roll |
| `ActivatedAbilityDamageBehavior` | Deal damage |
| `ActivatedAbilityHealBehavior` | Restore stamina |
| `ActivatedAbilitySetStaminaBehavior` | Set stamina to a specific value |
| `ActivatedAbilityApplyOngoingEffectBehavior` | Apply a persistent effect |
| `ActivatedAbilityRemoveOngoingEffectBehavior` | Remove an ongoing effect |
| `ActivatedAbilityForcedMovementBehavior` | Push, pull, or slide targets |
| `ActivatedAbilityModifiersBehavior` | Grant or remove modifiers |
| `ActivatedAbilityAuraBehavior` | Create an aura zone |
| `ActivatedAbilityMoveAuraBehavior` | Reposition an existing aura |
| `ActivatedAbilityTransformBehavior` | Transform the caster |
| `ActivatedAbilityContestedAttackBehavior` | Opposed roll (contested check) |
| `ActivatedAbilityApplyMomentaryEffectBehavior` | Brief visual/mechanical flash |
| `ActivatedAbilityCastSpellBehavior` | Trigger another ability as a sub-cast |
| `ActivatedAbilityAugmentedAbilityBehavior` | Augment or upgrade an ability |

### Extended Behaviors (in `Draw Steel Ability Behaviors/`)

These 24 files add Draw Steel-specific behavior types:

| File | Behavior |
|---|---|
| `AbilityDamage.lua` | DS-specific damage with tier scaling |
| `AbilityForcedMovementLoc.lua` | Location-based forced movement |
| `AbilityTemporaryEffects.lua` | Temporary effect application |
| `AbilityChangeElevation.lua` | Change a creature's elevation |
| `AbilityChangeTerrain.lua` | Alter terrain on the map |
| `AbilityCreateObject.lua` | Spawn a map object |
| `AbilityDestroyCreature.lua` | Remove a creature from play |
| `AbilityDisguise.lua` | Apply a disguise |
| `AbilityFall.lua` | Force a creature to fall |
| `AbilityCharacterSpeech.lua` | Trigger in-character speech |
| `AbilityMacro.lua` | Execute a chat macro |
| `AbilityMemory.lua` | Store data in the cast's memory |
| `AbilityOpposedPowerRoll.lua` | Opposed power roll |
| `AbilityPayCost.lua` | Deduct an additional resource cost |
| `AbilityPersistentCast.lua` | Maintain a persistent casting state |
| `AbilityRaiseCorpse.lua` | Raise a dead creature |
| `AbilityRecastAbility.lua` | Re-trigger another ability |
| `AbilityRecoverSelection.lua` | Recover a previous target selection |
| `AbilityRevertLocation.lua` | Return a creature to a prior location |
| `AbilityRoutineCast.lua` | Routine (automatic success) cast |
| `AbilitySetStamina.lua` | DS stamina manipulation |
| `AbilityStealAbility.lua` | Copy or steal an ability |
| `AbilityTargetLocs.lua` | Target map locations instead of creatures |
| `AbilityAddNewTargets.lua` | Add additional targets mid-resolution |

!!! tip "Adding a new behavior"
    Create a new `RegisterGameType` inheriting from `ActivatedAbilityBehavior`, implement its execution logic, and add it to an existing file in `Draw Steel Ability Behaviors/`. Do not create new Lua files without registering them through the module system.
