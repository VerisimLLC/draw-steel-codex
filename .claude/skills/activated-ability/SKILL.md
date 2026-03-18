---
name: activated-ability
description: Build, edit, or debug ActivatedAbility objects for monsters, heroes, or items. Use when asked to "create an ability", "add a strike", "implement a monster ability", "build an activated ability", or work with ability behaviors.
metadata:
  author: draw-steel-codex
  version: "1.0.0"
  argument-hint: <ability-description-or-monster-name>
---

# Activated Ability Builder

Create and edit ActivatedAbility objects for the Draw Steel Codex. Abilities appear in monster bestiary entries (`innateActivatedAbilities`), in CharacterModifier objects (behavior: "activated"), and in data tables.

## Key References

Read these files as needed when building abilities:

| File | What it contains |
|---|---|
| `DMHub Game Rules/ActivatedAbility.lua` | Base ActivatedAbility and ActivatedAbilityBehavior types, casting pipeline, RegisterType system |
| `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua` | ActivatedAbilityPowerRollBehavior -- power roll + tier resolution |
| `Draw Steel Core Rules/MCDMAbilityBehavior.lua` | ActivatedAbilityDrawSteelCommandBehavior -- text-parsed rule commands |
| `Draw Steel Core Rules/MCDMAbilitySaveBehavior.lua` | Saving throw behaviors |
| `Draw Steel Core Rules/MCDMActivatedAbility.lua` | Draw Steel extensions to ActivatedAbility (keywords, rendering, targeting) |
| `DMHub Game Rules/AbilityInvokeAbility.lua` | ActivatedAbilityInvokeAbilityBehavior -- invoke other abilities |
| `DMHub Game Rules/AbilityApplyRiders.lua` | ActivatedAbilityApplyRidersBehavior -- condition riders |
| `DMHub Game Rules/AbilitySummon.lua` | ActivatedAbilitySummonBehavior |
| `DMHub Game Rules/AbilityFloatText.lua` | ActivatedAbilityFloatTextBehavior |
| `DMHub Game Rules/AbilityPurgeEffects.lua` | ActivatedAbilityPurgeEffectsBehavior |
| `DMHub Game Rules/AbilityRelocateCreature.lua` | Forced movement / teleportation |
| `Draw Steel Ability Behaviors/` | 22 additional behavior implementations |
| `userdata/bestiary/CLAUDE.md` | Full bestiary YAML format documentation |

## ActivatedAbility YAML Structure

Every ActivatedAbility object in YAML follows this structure. Only include fields that differ from defaults.

```yaml
__typeName: ActivatedAbility
guid: "uuid"                        # unique id -- generate with a new UUID
name: "Slam"
description: "A powerful melee attack."

# Targeting
targetType: target                   # target, self, all, emptyspace, line, cone, cube, sphere, cylinder, anyspace
targetAllegiance: enemy              # enemy, ally, or omit for any
range: "5"                           # string -- can be GoblinScript formula
numTargets: "1"                      # string -- can be GoblinScript formula
objectTarget: false
selfTarget: false
repeatTargets: false

# Action cost
actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"  # standard action resource UUID
resourceCost: "none"                 # "none" or a resource UUID for secondary cost
resourceNumber: "1"                  # amount of secondary resource

# Classification
abilityType: none                    # none, standard, named
categorization: "Signature Ability"  # "Signature Ability", "Heroic Ability", "Villain Action", etc.
villainAction: ""                    # "Villain Action 1", "Villain Action 2", etc. (for villain actions only)

# Keywords
keywords:
  Strike: true
  Melee: true
  Weapon: true
  # Other keywords: Ranged, Magic, Area, Psionic, etc.

# Display
display:
  bgcolor: "#ffffffff"
  saturation: 1
  brightness: 1
  hueshift: 0
iconid: "uuid"                       # icon asset id (or "ui-icons/skills/1.png")

# Multiple modes (optional)
multipleModes: false
modeList:                            # only if multipleModes: true
  - text: "Untyped"
  - text: "Fire"

# Limited use (optional)
usageLimitOptions:
  charges: "1"
  resourceRefreshType: encounter     # encounter, turn
  resourceid: "uuid"

# Behaviors -- the ordered list that defines what the ability does
behaviors: [ ... ]

# Usually empty/default
persistence: []
modifiers: []
strain: []
displayOrder: 0
```

## Behavior Types Reference

Behaviors are the core of what an ability does. They execute in order when the ability is cast. Each has `__typeName` and type-specific fields.

### ActivatedAbilityPowerRollBehavior
The Draw Steel power roll. Rolls 2d10 + attribute, resolves into 3 tiers.

```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "2d10 + 3"                  # the roll formula (usually "2d10 + N")
  tiers:                            # tier 1 (<=11), tier 2 (12-16), tier 3 (17+)
    - "5 damage"                    # each tier is a DrawSteelCommand rule string
    - "9 damage"
    - "12 damage; slowed (save ends)"
  modesSelected:                    # only if parent ability has multipleModes
    - 1                             # 1-indexed mode this roll applies to
```

Tier strings are parsed by ActivatedAbilityDrawSteelCommandBehavior's rule engine. They support:
- Damage: `"5 damage"`, `"9 fire damage"`, `"2d6 + 3 damage"`
- Conditions: `"slowed (save ends)"`, `"restrained (EoT)"`, `"dazed (save ends)"`
- Forced movement: `"slide 3"`, `"push 2"`, `"pull 5"`, `"vertical push 3"`
- Combined: `"9 damage; slowed (save ends)"` (semicolon-separated)
- Conditional on tier: `"M<2 restrained (EoT)"` -- only if power roll >= tier 2 threshold

### ActivatedAbilityDrawSteelCommandBehavior
Executes a text-parsed rule command. Used standalone or as part of power roll tiers.

```yaml
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  rule: "M<2 restrained (EoT)"     # the rule string to execute
  filterTarget: 'Target.Conditions has "Slowed"'  # GoblinScript filter (optional)
  promptWhenResolving: false        # true to prompt for target selection
```

Rule string patterns:
- `"N damage"` or `"NdM + X damage"` or `"N type damage"` (e.g., `"5 fire damage"`)
- `"conditionName (duration)"` -- durations: `(save ends)`, `(EoT)`, `(resistance ends)`
- `"push N"`, `"pull N"`, `"slide N"`, `"vertical push N"`, `"vertical slide N"`
- `"M<N ..."` -- only apply if power roll met tier N threshold
- `"; "` separates multiple effects
- `"taunted by caster (EoT)"` -- condition with "by caster" qualifier
- `"teleport N"` -- teleport the target

### ActivatedAbilityDamageBehavior
Rolls damage dice via a dialog. Use for damage outside of power roll tiers.

```yaml
- __typeName: ActivatedAbilityDamageBehavior
  roll: "2d6 + 3"                   # damage formula (GoblinScript)
  damageType: "fire"                # damage type name (must match a DamageType entry)
  separateRolls: false              # true to roll separately per target
  cannotBeReduced: false            # true to bypass damage reduction
  doesNotTrigger: false             # true to skip damage triggers
  chatMessage: ""                   # optional chat log message
  titleText: ""                     # custom roll dialog title
```

### ActivatedAbilityApplyRidersBehavior
Adds condition riders that modify how conditions are applied by other behaviors.

```yaml
- __typeName: ActivatedAbilityApplyRidersBehavior
  conditionid: "uuid"               # condition this rider attaches to
  riderid: "uuid"                   # the rider effect to add
  filterTarget: ""                  # GoblinScript filter
```

### ActivatedAbilityApplyOngoingEffectBehavior
Applies a persistent ongoing effect (condition, buff, etc.).

```yaml
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  applyto: targets                  # targets, caster
  ongoingEffect: "uuid"             # ongoing effect id from characterOngoingEffects table
  ongoingEffectCustom: false
  filterTarget: ""
```

### ActivatedAbilityAuraBehavior
Creates an aura zone on the map.

```yaml
- __typeName: ActivatedAbilityAuraBehavior
  aura:
    __typeName: Aura
    guid: "uuid"
    name: "Poison Cloud"
    objectid: "uuid"                # map object asset for the aura visual
    applyto: enemies                # enemies, allies, selfandfriends
    damage: 3                       # damage per trigger (0 for none)
    difficult_terrain: false
    display: { bgcolor: "#ffffffff", saturation: 1, brightness: 1, hueshift: 0 }
    modifiers: []                   # CharacterModifier objects applied to affected creatures
    triggers: []                    # TriggeredAbility objects (e.g., onenter triggers)
  applyto: caster                   # who the aura is placed on
  duration: nextturn                # nextturn, none, etc.
  aliveafterdeath: false
```

### ActivatedAbilityInvokeAbilityBehavior
Invokes another ability as part of this one (e.g., forced movement that triggers a free strike).

```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  abilityType: standard             # standard (by id), named (by name), custom (inline)
  standardAbility: "uuid"           # for abilityType: standard
  namedAbility: "Ability Name"      # for abilityType: named
  standardAbilityParams:            # parameter overrides
    distance: "3"
  applyto: targets                  # targets, caster
  invokeOnCaster: false
  runOnController: false
```

### ActivatedAbilitySummonBehavior
Summons creatures from the bestiary.

```yaml
- __typeName: ActivatedAbilitySummonBehavior
  monsterType: "uuid"               # specific bestiary entry, or "custom" for filter
  bestiaryFilter: 'beast.cr = 1'    # GoblinScript filter for custom selection
  numSummons: "1"
  allCreaturesTheSame: false
  casterControls: true
  replaceCaster: false
```

### ActivatedAbilityPurgeEffectsBehavior
Removes conditions or ongoing effects.

```yaml
- __typeName: ActivatedAbilityPurgeEffectsBehavior
  conditions: []                    # list of condition ids to purge; empty = all
  mode: conditions                  # conditions, effects
  purgeType: all                    # all, one
  targetDuration: save              # save, eot, etc.
```

### ActivatedAbilityFloatTextBehavior
Shows floating text above a creature.

```yaml
- __typeName: ActivatedAbilityFloatTextBehavior
  text: "Dwoemer Burst"
  color: "#ff0000ff"
  applyto: caster                   # caster, targets
```

### ActivatedAbilityDestroyBehavior
Destroys (removes) the target creature.

```yaml
- __typeName: ActivatedAbilityDestroyBehavior
  applyto: caster                   # caster, targets
```

### ActivatedAbilityMacroBehavior
Executes a DMHub macro command string.

```yaml
- __typeName: ActivatedAbilityMacroBehavior
  macro: "command string"
```

### ActivatedAbilityRememberBehavior
Stores a computed value in the cast's memory for later behaviors to use.

```yaml
- __typeName: ActivatedAbilityRememberBehavior
  memoryName: "storedValue"
  calculation: "2 * Level"          # GoblinScript formula
```

### Other Behavior Types

These are less commonly needed but available:
- `ActivatedAbilityApplyAbilityDurationEffect` (id: `temporary_effect`) -- temporary effect lasting for the ability's duration
- `ActivatedAbilityForcedMovementLocBehavior` (id: `forcedmovementloc`) -- sets origin point for forced movement
- `ActivatedAbilityOpposedRollBehavior` (id: `opposed`) -- opposed power roll checks
- `ActivatedAbilityPayAbilityCostBehavior` (id: `pay_ability_cost`) -- consume resources
- `ActivatedAbilityChangeTerrainBehavior` (id: `terraform_terrain`) -- modify terrain
- `ActivatedAbilityChangeElevationBehavior` (id: `terraform_elevation`) -- modify elevation
- `ActivatedAbilityCreateObjectBehavior` (id: `create_object`) -- spawn map objects
- `ActivatedAbilityDisguiseBehavior` (id: `disguise`) -- disguise creatures
- `ActivatedAbilityFallBehavior` (id: `fall`) -- trigger falling
- `ActivatedAbilityRaiseCorpseBehavior` (id: `raise_corpse`) -- revive creatures
- `ActivatedAbilityRecastBehavior` (id: `recast`) -- recast recently used abilities
- `ActivatedAbilityCharacterSpeechBehavior` (id: `character_speech`) -- creature speech
- `ActivatedAbilityRevertLocBehavior` (id: `revertloc`) -- revert to previous position
- `ActivatedAbilityManipulateTargetLocs` (id: `manipulate_target_locs`) -- move between floors

## TriggeredAbility Structure

TriggeredAbility extends ActivatedAbility and is used inside CharacterModifier objects (behavior: "trigger") for reactive abilities.

```yaml
__typeName: TriggeredAbility
guid: "uuid"
name: "Acidic Retaliation"
description: "When this creature takes damage, adjacent enemies take 3 acid damage."
trigger: takedamage                  # Event triggers -- see list below
targetType: all                      # same as ActivatedAbility
range: 1
numTargets: "1"
mandatory: true                      # true = auto-fires, false = prompts player
castImmediately: true
behaviors: [ ... ]                   # same behavior types as ActivatedAbility

# Trigger conditions (optional)
triggerFilter: ""                    # GoblinScript filter
conditionFormula: ""                 # additional condition type
```

Trigger event types: `takedamage`, `endturn`, `beginturn`, `creaturedeath`, `d20roll`, `onenter`, `losehitpoints`, `zerohitpoints`, `kill`, `attack`, `dealdamage`, `finishmove`, `custom`

## Common Patterns

### Simple Strike (Melee, Single Target)
```yaml
- __typeName: ActivatedAbility
  name: "Claw"
  targetType: target
  range: "1"
  numTargets: "1"
  actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
  categorization: "Signature Ability"
  keywords: { Strike: true, Melee: true, Weapon: true }
  behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    roll: "2d10 + 3"
    tiers:
    - "5 damage"
    - "9 damage"
    - "12 damage"
```

### Strike with Condition
```yaml
behaviors:
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "2d10 + 2"
  tiers:
  - "4 damage"
  - "7 damage; slowed (save ends)"
  - "10 damage; restrained (save ends)"
```

### Ranged Area Attack (Multiple Targets)
```yaml
- __typeName: ActivatedAbility
  name: "Flame Burst"
  targetType: all
  range: "10"
  numTargets: "3"
  keywords: { Magic: true, Ranged: true, Area: true }
  behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    roll: "2d10 + 4"
    tiers:
    - "3 fire damage"
    - "6 fire damage"
    - "8 fire damage; push 2"
```

### Dual-Mode Ability (Melee or Ranged)
```yaml
- __typeName: ActivatedAbility
  name: "Strike"
  multipleModes: true
  modeList:
  - text: "Melee"
  - text: "Ranged"
  keywords: { Strike: true, Melee: true, Ranged: true, Weapon: true }
  behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    roll: "2d10 + 3"
    modesSelected: [1]
    tiers: ["5 damage", "8 damage", "11 damage"]
  - __typeName: ActivatedAbilityPowerRollBehavior
    roll: "2d10 + 3"
    modesSelected: [2]
    tiers: ["4 damage", "7 damage", "10 damage"]
```

### Villain Action with Forced Movement
```yaml
- __typeName: ActivatedAbility
  name: "Tremor Slam"
  villainAction: "Villain Action 1"
  targetType: all
  range: "3"
  numTargets: "all"
  behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    roll: "2d10 + 5"
    tiers:
    - "6 damage; push 1"
    - "10 damage; push 3"
    - "14 damage; push 5; prone (EoT)"
```

### Passive Trait with Triggered Ability (in characterFeatures)
```yaml
characterFeatures:
- __typeName: CharacterFeature
  guid: "uuid"
  name: "Acidic Blood"
  source: Trait
  description: "When this creature takes damage, adjacent enemies take 3 acid damage."
  modifiers:
  - __typeName: CharacterModifier
    guid: "uuid"
    behavior: trigger
    triggeredAbility:
      __typeName: TriggeredAbility
      guid: "uuid"
      name: "Acidic Blood"
      trigger: takedamage
      targetType: all
      range: 1
      mandatory: true
      castImmediately: true
      behaviors:
      - __typeName: ActivatedAbilityDamageBehavior
        roll: "3"
        damageType: acid
```

## FilterTarget Patterns

The `filterTarget` field on behaviors uses GoblinScript to conditionally apply effects:

```
Target.Conditions has "Slowed"           # target has a specific condition
Target.Conditions has not "Slowed"       # target does not have condition
Target.Stamina < Target.MaxStamina / 2   # target is bloodied
Target.Size <= 1                         # target is size 1 or smaller
```

## Creating New Lua Behavior Types

When an ability needs logic beyond what existing behaviors provide, create a new behavior in `Draw Steel Ability Behaviors/`:

```lua
local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityMyNewBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = 'my_new',
    text = 'My New Behavior',
    createBehavior = function()
        return ActivatedAbilityMyNewBehavior.new{
            -- default fields
        }
    end
}

ActivatedAbilityMyNewBehavior.summary = 'My New Behavior'

function ActivatedAbilityMyNewBehavior:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)
    for _, target in ipairs(targets) do
        target.token:ModifyProperties{
            description = "My Effect",
            execute = function()
                -- apply effect to target.token.properties
            end,
        }
    end
end

function ActivatedAbilityMyNewBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)
    -- add custom editor fields
    return result
end
```

Then add a `require` for the new file in `main.lua` (after the other behavior requires).

## Constraints

- All Lua files must be ASCII-only (no Unicode punctuation).
- New files must start with `local mod = dmhub.GetModLoading()`.
- RegisterGameType result must be assigned to a global: `Foo = RegisterGameType("Foo")`.
- New behavior files must be `require`d in `main.lua` after existing behavior files.
