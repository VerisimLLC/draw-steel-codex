# Monster Reference

Monster-specific structures: YAML format, abilities, behaviors, power rolls, auras,
modifiers, triggers, ongoing effects, and rules engine commands.

See also: [CORE.md](CORE.md) for UUID maps, table names, and common pitfalls.
See also: [../../GoblinScript_Guide.md](../../GoblinScript_Guide.md) for GoblinScript syntax.
See also: [MONSTER_PATTERNS.md](MONSTER_PATTERNS.md) for proven implementation patterns (targeting, terrain, triggers, summoning, death effects, damage modification, faction buffs).
See also: [POWER_TABLE_PARSING.md](POWER_TABLE_PARSING.md) for what tier text is auto-handled by the power roll parser.

---

## Monster YAML Structure

Monster files are serialized `MonsterAsset` C# objects. Top-level structure:

```yaml
info:
  locInfo: null
  appearance:
    portraitId: <uuid>          # Portrait image ID
    offtokenPortraitId: null
    portraitFrameId: <uuid>     # Frame style
    portraitRibbon: null
    backgroundId: null
    anthem: null
    anthemVolume: 1
    tokenScaling: 1             # Token size on map
    tokenZoom: 1
    portraitOffset: { x: 0, y: 0 }
    frameHueShift: 0
    frameSaturation: 1
    frameBrightness: 1
    characterName: null
    characterNamePrivate: false
    flip: false
    saddlePositions: []
  disguise: null
  settings:
    canRotate: false
    useLight: false
    lightColor: { r: 1, g: 1, b: 1, a: 1 }
    lightIntensity: 0.1
    lightRadius: 10
    lightFalloff: 0.1
    lightAngle: 360
  mountedBy: {}
  updateid: <uuid>
  properties:
    __typeName: monster
    titles: []
    characterFeatures: [...]    # Array of CharacterFeature
    type: monster
    size: 1                     # 1, 2, 3, 4, 5...
    sizeCategory: M             # T, S, M, L (for size 1 only)
    innateActivatedAbilities: [...]  # Array of ActivatedAbility
    skills: {}
    speed: 5
    stamina: 10
    attributes: { mgt: 2, agl: 1, rea: 0, inu: 0, prs: 0 }
    monster_type: "<monster name>"
    monster_role: "<role>"      # Ambusher, Artillery, Brute, etc.
    monster_subrole: "<subrole>"
    monster_organization: "<org>"  # Minion, Horde, Platoon, Elite, Leader, Solo
    monster_level: 1
    monster_ev: 6
    minion: false
    captain: false
    keywords: { Humanoid: true }
    freestrike: 2               # Static free strike damage
    stability: 0
    conditionImmunities: {}     # Map of condition UUID -> true
    damageImmunities: []        # Array of {apply: "all", damageType: <uuid>, dr: 5}
    damageWeaknesses: []
    monsterGroupId: "<group uuid>"
    villainActions: 0           # 0 or 3
description: "<monster display name>"
hidden: false
id: <uuid>
```

---

## ActivatedAbility Fields

The base `ActivatedAbility` type used for all abilities. Default values shown are from code.

```yaml
__typeName: ActivatedAbility
name: "Ability Name"               # default: ""
description: "What this ability does"
flavor: ""                          # Optional flavor text
guid: <uuid>

# Targeting
targetType: target                  # See targetType table below
targetAllegiance: enemy             # false (any), "ally", "enemy", "none", "dead"
numTargets: "1"                     # GoblinScript formula
targetFilter: ""                    # GoblinScript filter (see note on reasonedFilters)
selfTarget: false                   # Include caster as valid target
objectTarget: false                 # Allow targeting map objects
targeting: direct                   # For space targets: direct, pathfind, etc.

# Range
range: 1                           # In squares (1 = melee 1)
lineDistance: 1                     # For line/wall targeting
canChooseLowerRange: false

# Action Cost
actionResourceId: "<resource uuid>"  # See UUID reference in CORE.md
actionNumber: 1
resourceCost: "none"                # Resource UUID for secondary cost (e.g., Malice)
resourceNumber: 1                   # Amount of secondary resource

# Keywords
keywords:
  Melee: true
  Strike: true
  Weapon: true

# Behaviors (executed in order)
behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    ...

# Display
iconid: <uuid>
display:
  saturation: 1
  hueshift: 0
  bgcolor: "#ffffffff"
  brightness: 1
categorization: "none"              # See categorization values below
displayOrder: 1

# Duration
durationType: instant               # instant, round, save, concentration
durationLength: 0

# Casting
castImmediately: false
silent: false
multipleModes: false

# Usage Limits
usageLimitOptions:
  resourceRefreshType: "none"       # none, encounter, turn, round
  charges: "0"
  resourceid: "none"

# Modifiers (applied to caster during cast)
modifiers: []
```

### categorization Values (code-verified from RegisterAbilityCategorization)

| Value | Grouping |
|-------|----------|
| `"none"` | Default (no category) |
| `"Heroic Ability"` | Heroic Abilities |
| `"Villain Action"` | Villain Actions |
| `"Malice"` | Malice Abilities |
| `"Signature Ability"` | Signature Abilities (a.k.a. `signature`) |
| `"Ability"` | Common Abilities |
| `"Trigger"` | Triggers |
| `"Skill"` | Common Abilities |
| `"Basic Attack"` | Common Abilities |
| `"Move"` | Move |
| `"Hidden"` | Hidden (not shown on action bar) |
| `"Triggered Ability"` | (for TriggeredAbility type) |

---

## Targeting System

### targetType (code-verified from ActivatedAbility.TargetTypes)

| Value | Description |
|-------|-------------|
| `self` | No targeting; affects caster (or self-centered area) |
| `target` | Select creature(s). Use with `targetAllegiance` and `numTargets` |
| `all` | Burst: all creatures in radius from caster |
| `line` | Line area of effect |
| `cube` | Cube area of effect |
| `emptyspace` | Select empty map locations |
| `emptyspacefriend` | Select empty locations OR allied creatures |
| `anyspace` | Select any map location (empty or occupied) |
| `map` | All creatures in the encounter |
| `areatemplate` | Place area template on map |
| `sphere` | Sphere (hidden in editor, but valid) |
| `cylinder` | Cylinder (hidden in editor, but valid) |
| `cone` | Cone (hidden in editor, but valid) |

**WARNING:** `enemies` is NOT a valid targetType. Use `targetType: target` with
`targetAllegiance: enemy` to target enemies.

### targetAllegiance (only for targetType=target)

| Value | Description |
|-------|-------------|
| `false` | Any creature (default -- omit field or set to false) |
| `"ally"` | Only allied creatures |
| `"enemy"` | Only enemy creatures |
| `"none"` | Objects only (requires `objectTarget: true`) |
| `"dead"` | Only dead creatures |

### selfTarget

When `true`, the caster can be selected as a target. Commonly used with
`targetAllegiance: "ally"` for "self or one ally" abilities.

Display logic:
- `selfTarget: true` + `targetAllegiance: "ally"` = "Self and each ally"
- `selfTarget: false` + `targetAllegiance: "ally"` = "Each ally"

### objectTarget

When `true`, map objects (doors, barrels, etc.) can be selected as targets alongside
creatures. Use `Target.Object` in GoblinScript to detect objects.

### targetFilter

GoblinScript formula to filter valid targets. Available symbols include `Target`
(the candidate creature). Examples:

```yaml
targetFilter: "Keywords has \"Elemental\""           # Only elementals
targetFilter: "enemy"                                 # Only enemies
targetFilter: "not dead"                              # Only living
targetFilter: "Target.Keywords has \"Demon\""         # Only demons
```

### targeting (for space-based targetTypes)

| Value | Description |
|-------|-------------|
| `direct` | Click directly on target square |
| `pathfind` | Navigate via pathfinding |
| `straightline` | Straight line (for forced movement) |
| `straightpath` | Straight path (respects walls/creatures) |
| `straightpathignorecreatures` | Straight path ignoring creatures |
| `vacated` | Only previously-occupied spaces |
| `contiguous` | Selected spaces must be adjacent |
| `contiguous_wall` | For placing walls |

### reasonedFilters (Targeting Feedback)

When a target is invalid, `reasonedFilters` provides explanatory text to the user
instead of silently preventing targeting:

```yaml
reasonedFilters:
  - reason: "This creature is too large for you to knockback."
    formula: "Target.Knockback Target Size <= Caster.Knockback Caster Size"
  - reason: "Grabbed creatures cannot be force moved, except by the grabber."
    formula: '(Not (target.conditions has "Grabbed")) or (ConditionCaster("Grabbed") = Caster)'
```

Each entry has:
- `formula` -- GoblinScript evaluated against the target. If **false**, the target is invalid.
- `reason` -- text shown to the user explaining why they can't target this creature.

Multiple entries are checked in order. The first failing formula's reason is displayed.
This is much better UX than silently filtering targets via `targetFilter`, since players
can see WHY a target is invalid. Use `reasonedFilters` for restrictions that aren't obvious.

**IMPORTANT:** Do NOT use `targetFilter` and `reasonedFilters` for the same restriction.
`targetFilter` silently removes targets from the list entirely, so the `reasonedFilters`
reason text will never be shown. If you want feedback, use `reasonedFilters` INSTEAD OF
`targetFilter`, not in addition to it.

**Examples:**
```yaml
# Only target elementals
reasonedFilters:
  - reason: "This ability can only target elementals."
    formula: 'Keywords has "Elemental"'

# Only target grabbed creatures
reasonedFilters:
  - reason: "Target must be grabbed."
    formula: 'target.conditions has "Grabbed"'

# Size restriction
reasonedFilters:
  - reason: "Target is too large."
    formula: "Target.Size <= Caster.Size + 1"
```

### Common Targeting Patterns

**Single enemy strike:**
```yaml
targetType: target
targetAllegiance: enemy
numTargets: "1"
```

**Self or one ally:**
```yaml
targetType: target
targetAllegiance: ally
selfTarget: true
numTargets: "1"
```

**Two creatures or objects:**
```yaml
targetType: target
numTargets: "2"
objectTarget: true
```

**Area burst (enemies only):**
```yaml
targetType: all
range: 3                 # Burst radius
```

**Cube area (enemies in range):**
```yaml
targetType: cube
range: 5                 # How far away the cube can be placed
```

---

## Behavior Types

All behavior types inherit from `ActivatedAbilityBehavior`. Common base fields:

```yaml
__typeName: <BehaviorTypeName>
applyto: targets        # See applyto values below
filterTarget: ""        # GoblinScript: skip targets where this is falsy
summary: "None"         # Editor display name
instant: false          # If true, executes immediately (not in coroutine)
```

### applyto Values (code-verified)

Built-in values (always available):
- `targets` -- All targets of the ability
- `caster` -- The caster only
- `caster_and_targets` -- Caster and all targets
- `caster_riders` -- Creatures riding the caster
- `caster_including_squad` -- Caster and their squad
- `caster_minions` -- Caster's minions
- `first_target` -- Only the first target
- `other_than_first_target` -- All targets except the first
- `target_proximity` -- Targets and creatures in proximity
- `proximity_only` -- Only creatures in proximity
- `original_targets` -- Original targets (before modifications)
- `subject` -- Trigger subject
- `winner_opposed` -- Winner of an opposed roll
- `none` -- Nobody

Draw Steel additional values:
- `selfandheroallies` -- Self and hero allies
- `heroallies` -- Hero allies only
- `all` -- All creatures
- `allother` -- All other creatures
- `selfandfriends` -- Self and friends
- `friends` -- Friends only
- `enemies` -- Enemies only

### Core Behaviors

#### ActivatedAbilityPowerRollBehavior
**Purpose**: Execute a Draw Steel power roll with tier-based outcomes.
```yaml
__typeName: ActivatedAbilityPowerRollBehavior
rule: ""                # GoblinScript rules for power table effects
roll: "2d10 + 2"        # Dice formula
attrid: mgt             # Characteristic used for the roll
resistanceRoll: false   # If true, target rolls (tiers are reversed)
tiers:                  # Array of 3 strings: tier 1/2/3 outcomes
  - "5 damage"
  - "9 damage"
  - "12 damage"
applyto: targets
```

#### ActivatedAbilityDamageBehavior
**Purpose**: Deal damage to targets.
```yaml
__typeName: ActivatedAbilityDamageBehavior
roll: "2d6 + 2"        # Dice expression
damageType: force       # Damage type ID or "force" for untyped
separateRolls: false    # Roll separately per target
chatMessage: ""         # Optional message in chat
dcsuccess: false
applyto: targets
```

#### ActivatedAbilityHealBehavior
**Purpose**: Heal targets.
```yaml
__typeName: ActivatedAbilityHealBehavior
roll: "1d8 + 4"        # Dice expression
applyto: targets
```

#### ActivatedAbilityGrantTemporaryStaminaBehavior
**Purpose**: Grant temporary stamina (temp HP).
```yaml
__typeName: ActivatedAbilityGrantTemporaryStaminaBehavior
stamina: "5"            # GoblinScript formula
chatMessage: ""
applyto: targets
```

#### ActivatedAbilityForcedMovementBehavior
**Purpose**: Push/pull/slide targets.
```yaml
__typeName: ActivatedAbilityForcedMovementBehavior
distance: 3             # Number of squares
applyto: targets
```
Note: The type of forced movement (push/pull/slide) is typically set via the power roll rules
or through the ActivatedAbilityForcedMovementLocBehavior.

#### ActivatedAbilityForcedMovementLocBehavior
**Purpose**: Set the origin point for forced movement.
```yaml
__typeName: ActivatedAbilityForcedMovementLocBehavior
type: aura              # aura, caster, target
applyto: targets
```

#### ActivatedAbilityApplyOngoingEffectBehavior
**Purpose**: Apply an ongoing effect to targets.
```yaml
__typeName: ActivatedAbilityApplyOngoingEffectBehavior
ongoingEffect: <effect-uuid>         # UUID from characterOngoingEffects table
ongoingEffectCustom: <effect-uuid>   # Editor tracking: same UUID if custom, false if pre-existing
duration: eoe                        # See duration values below
stacks: "1"                          # Number of stacks to apply
repeatSave: false
durationUntilEndOfTurn: false
applyto: targets
tiersSelected:                       # Which tiers apply this effect (1-indexed)
  - 1                                # Tier 1 (<=11)
  - 2                                # Tier 2 (12-16)
  - 3                                # Tier 3 (17+)
potencyAttr: inu                     # Characteristic for potency gate (mgt/agl/rea/inu/prs)
```

**Potency with ongoing effects:** When an ability applies a custom ongoing effect gated
by potency (e.g., "I<2 cursed (save ends)"), use the two-part pattern:

1. **Tier text includes the full potency + effect text** for display in the power table:
   ```yaml
   tiers:
     - "3 corruption damage; I<1 cursed (save ends)"
     - "5 corruption damage; I<2 cursed (save ends)"
     - "7 corruption damage; I<3 cursed (save ends)"
   ```
   The power table parser auto-recognizes the potency gate (`I<1`, `I<2`, `I<3`) and
   the condition name. The escalating potency values across tiers reflect that higher
   tiers are harder to resist.

2. **`ApplyOngoingEffectBehavior` handles actual application** with `potencyAttr` set
   to the gating characteristic. The behavior reads the potency threshold from the
   tier text and checks it against the target's characteristic:
   ```yaml
   - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
     ongoingEffect: <effect-uuid>
     duration: save_ends
     potencyAttr: inu              # Checks target's Intuition vs threshold
     tiersSelected: [1, 2, 3]      # Apply on all tiers (1-indexed)
   ```
   On Tier 1, the target must have Intuition < 1 to be cursed. On Tier 2, < 2.
   On Tier 3, < 3. The behavior automatically extracts the correct threshold
   from each tier's text.

**Important:** The potency values in the tier text (`I<1`, `I<2`, `I<3`) are NOT just
display -- they are the actual thresholds used by the behavior. The `potencyAttr` field
tells the system WHICH characteristic to check, and the tier text tells it WHAT VALUE
to check against. Do not omit the potency text from tier strings when using `potencyAttr`.

**`tiersSelected`:** Controls which power roll tiers trigger this behavior. Values are
**1-indexed**: `[1]` = Tier 1 only, `[1, 2]` = Tiers 1 and 2, `[1, 2, 3]` = all tiers.
If omitted, the effect applies on all tiers.

**Valid duration values for ongoing effects (code-verified from OngoingEffect.durationOptions):**
- `end_of_next_turn` -- until end of affected creature's next turn
- `eoe` -- end of encounter
- `save_ends` -- until saving throw
- `eoe_or_dying` -- end of encounter or when dying
- `endround` -- end of current round
- `endnextround` -- end of next round
- `until_rest` -- until respite
- `until_long_rest` -- until long rest
- `momentary` -- momentary (immediate, for ApplyMomentaryEffect)
- `turn` -- until end of turn
- `rounds` -- rounds (from start of turn) - requires numeric durationLength
- `rounds_end_turn` -- rounds (from end of turn) - requires numeric durationLength
- `indefinite` -- indefinitely
- A number -- specific number of rounds

**WARNING:** `nextturn` and `endnextturn` are NOT valid for ongoing effect durations
(those are aura duration values). Using invalid strings causes runtime errors.

#### ActivatedAbilityRemoveOngoingEffectBehavior
**Purpose**: Remove an ongoing effect from targets.
```yaml
__typeName: ActivatedAbilityRemoveOngoingEffectBehavior
applyto: targets
```

#### ActivatedAbilityPurgeEffectsBehavior
**Purpose**: Remove specific or all ongoing effects/conditions.
```yaml
__typeName: ActivatedAbilityPurgeEffectsBehavior
conditions: []          # List of condition IDs to purge (empty = all)
applyto: targets
```

#### ActivatedAbilityInvokeAbilityBehavior
**Purpose**: Invoke another ability from within this ability. Key for complex multi-step abilities.
```yaml
__typeName: ActivatedAbilityInvokeAbilityBehavior
applyto: targets
```
Contains an `AbilityInvocation` sub-object that specifies which ability to invoke and with what parameters. This is how abilities like "attack, then let an ally move and attack" are implemented.

#### ActivatedAbilityRelocateCreatureBehavior
**Purpose**: Move/teleport a creature to a new location.
```yaml
__typeName: ActivatedAbilityRelocateCreatureBehavior
targetMoveVicinity: false
vicinity: 0
applyto: targets
```

#### ActivatedAbilitySummonBehavior
**Purpose**: Summon creatures onto the map.
```yaml
__typeName: ActivatedAbilitySummonBehavior
numSummons: "1"
allCreaturesTheSame: false
bestiaryFilter: "beast.cr = 1 and beast.type is beast"
monsterType: custom     # custom, specific
hasReplaceCaster: true
replaceCaster: false
casterControls: true
casterChoosesCreatures: true
groupInitiativeWithCaster: true
applyto: targets
```

#### ActivatedAbilityAuraBehavior
**Purpose**: Create a persistent zone on the map with terrain effects, modifiers, and triggers.
Auras are the primary way to create difficult terrain, hazardous zones, walls, and
persistent area effects. The ability's targeting shape (cube, burst, line, etc.) defines
the aura's area.

```yaml
__typeName: ActivatedAbilityAuraBehavior
duration: endnextturn       # See aura duration options below
aliveafterdeath: false      # If true, persists after caster dies
aura:
  __typeName: Aura
  name: "Aura Name"
  description: "What this aura does"
  guid: <uuid>
  objectid: <asset-uuid>     # Visual object on map (see below)

  # --- Terrain Effects ---
  difficult_terrain: false   # Makes area difficult terrain
  blocks_line_of_effect: false  # Blocks LOS, provides cover
  blocks_movement: false     # Blocks creature movement (wall)
  concealment: false         # Offers concealment to creatures in aura

  # --- Movement Damage ---
  movedamage: "none"         # Damage type per square: "none", "fire", "poison", "acid", etc.
  damage: 0                  # Damage amount per square moved
  movementDamageFilter: "all"  # "all", "nonshift" (shifting avoids), "forced" (forced only)

  # --- Creature Filtering ---
  applyto: all               # Who is affected (see Aura.ApplyOptions below)
  creatureFilter: ""         # Additional GoblinScript filter

  # --- Flags ---
  flags:                     # Optional flags
    zerocost: true           # Zero movement cost (allies move freely through)

  # --- Modifiers applied to creatures inside ---
  modifiers: []              # Array of CharacterModifier

  # --- Triggers ---
  triggers: []               # Array of trigger entries (see below)

  # --- Relocation ---
  canrelocate: false         # If true, caster can move the aura
  relocateResource: "standardAction"  # Action resource for relocation
  relocateRange: 30          # Max range for relocation

  display:
    saturation: 1
    hueshift: 0
    bgcolor: "#ffffffff"
    brightness: 1
```

**Aura duration options** (on the behavior, NOT the aura -- code-verified from AuraInstance):
- `endnextturn` -- until end of caster's next turn (internally converted to `endturn` + durationRound)
- `eoe` -- end of encounter (never expires during encounter)
- `endround` -- end of current round
- A number -- specific number of rounds (compared via `RoundsSince()`)
- `"none"` or omit -- permanent (until explicitly removed)

**WARNING:** These are DIFFERENT from ongoing effect durations. Do NOT use `end_of_next_turn`,
`save_ends`, `until_rest`, etc. for aura durations.

**Aura `applyto` filter options (code-verified from Aura.ApplyOptions):**

| ID | Description |
|----|-------------|
| `all` | All creatures |
| `allother` | All creatures except caster |
| `selfandfriends` | Friends, including self |
| `friends` | Friends, excluding self |
| `enemies` | Enemies only |
| `sametype` | Same type creatures |
| `othertype` | Other type creatures |

**`creatureFilter`**: Additional GoblinScript filter evaluated per creature. Available
symbols: `Self` (the creature being tested), `Target` (synonym for Self), `Aura` (the aura).

**Visual objects (`objectid`):**
- `c994501f-85ec-475e-b9f6-8113a814f8d1` -- **Blank** (invisible, use as default)
- Users can add custom aura objects to the Auras folder in DMHub and update the UUID.
  Always remind the user that they can customize the visual.

**Aura trigger conditions (code-verified from Aura.TriggerConditions):**

| ID | Description |
|----|-------------|
| `onenter` | When a creature enters the aura |
| `casterendturnaura` | At the end of the caster's turn |

**Trigger structure:**

```yaml
triggers:
  - trigger: onenter              # When creature enters the aura
    destroyaura: false            # If true, aura is destroyed after trigger fires
    ability:
      __typeName: TriggeredAbility
      name: "On Enter Effect"
      guid: <uuid>
      range: 1
      targetType: self
      silent: true
      numTargets: "1"
      trigger: losehitpoints      # Required field but ignored for aura triggers
      behaviors:
        - __typeName: ActivatedAbilityDrawSteelCommandBehavior
          rule: "2 fire damage"
      description: ""
      modifiers: []
      persistence: []
      repeatTargets: false
      display: { saturation: 1, hueshift: 0, bgcolor: "#ffffffff", brightness: 1 }
      iconid: ui-icons/skills/1.png
      strain: []
```

**Common aura patterns:**

| Pattern | Fields |
|---------|--------|
| Difficult terrain | `difficult_terrain: true` |
| Hazardous zone | `difficult_terrain: true`, `movedamage: fire`, `damage: 3` |
| Damage on entry | `triggers: [{trigger: onenter, ability: ...}]` |
| Wall | `blocks_movement: true`, `blocks_line_of_effect: true` |
| Concealment zone | `concealment: true` |
| Cover zone | `blocks_line_of_effect: true` |
| Buff zone for allies | `applyto: selfandfriends`, `modifiers: [...]` |
| Debuff zone for enemies | `applyto: enemies`, `modifiers: [...]` |
| Free movement for allies | `flags: {zerocost: true}`, `applyto: selfandfriends` |

#### ActivatedAbilityMoveAuraBehavior
**Purpose**: Move an existing aura to a new location.
```yaml
__typeName: ActivatedAbilityMoveAuraBehavior
applyto: targets
```

#### ActivatedAbilityModifyCastBehavior
**Purpose**: Modify casting parameters (damage, edges, banes, surges).
```yaml
__typeName: ActivatedAbilityModifyCastBehavior
paramid: "none"         # Parameter to modify
value: ""               # GoblinScript formula
name: ""
description: ""
applyto: targets
```

#### ActivatedAbilityModifyPowerRollBehavior
**Purpose**: Inject a temporary power-roll modifier.
```yaml
__typeName: ActivatedAbilityModifyPowerRollBehavior
guid: <uuid>
modifier:               # Embedded CharacterModifier with behavior="power"
  __typeName: CharacterModifier
  behavior: power
  ...
applyto: targets
```

#### ActivatedAbilityLimitBehavior
**Purpose**: Limit ability uses per encounter/turn/round.
```yaml
__typeName: ActivatedAbilityLimitBehavior
key: <uuid>
refresh: encounter      # encounter, turn, round, longrest, shortrest
keyOverride: ""
applyto: targets
instant: true
```

#### ActivatedAbilitySaveBehavior
**Purpose**: Draw Steel end-of-turn saving throw.
```yaml
__typeName: ActivatedAbilitySaveBehavior
conditionsMode: all     # all, specific
rollMode: roll          # roll, auto
includeProne: false
applyto: targets
```

#### ActivatedAbilityApplyMomentaryEffectBehavior
**Purpose**: Apply a temporary effect during ability execution only.
```yaml
__typeName: ActivatedAbilityApplyMomentaryEffectBehavior
instant: true
momentaryEffect:        # Embedded CharacterOngoingEffect
  __typeName: CharacterOngoingEffect
  ...
applyto: targets
```

#### ActivatedAbilityApplyAbilityDurationEffect
**Purpose**: Apply an effect lasting for the ability's duration.
```yaml
__typeName: ActivatedAbilityApplyAbilityDurationEffect
instant: true
lingerTime: 0
momentaryEffect:
  __typeName: CharacterOngoingEffect
  ...
applyto: targets
```

#### ActivatedAbilityAugmentedAbilityBehavior
**Purpose**: Create augmented versions of abilities with a modifier applied.
```yaml
__typeName: ActivatedAbilityAugmentedAbilityBehavior
modifier:               # CharacterModifier to augment with
  __typeName: CharacterModifier
  ...
hasCast: false
mono: true
applyto: targets
```

#### ActivatedAbilitySetStaminaBehavior
**Purpose**: Set stamina to a specific value.
```yaml
__typeName: ActivatedAbilitySetStaminaBehavior
roll: "10"              # GoblinScript expression
applyto: targets
```

#### ActivatedAbilityTransformBehavior
**Purpose**: Transform into another creature.
```yaml
__typeName: ActivatedAbilityTransformBehavior
allCreaturesTheSame: false
monsterType: custom
bestiaryFilter: ""
casterChoosesCreatures: true
replaceCaster: true
hasReplaceCaster: true
applyto: targets
```

#### ActivatedAbilityRemoveCreatureBehavior
**Purpose**: Remove (despawn) a creature from the map.
```yaml
__typeName: ActivatedAbilityRemoveCreatureBehavior
dropsLoot: false
leavesCorpse: false
waitForAbilitiesToFinish: true
applyto: targets
```

#### ActivatedAbilityDestroyBehavior
**Purpose**: Destroy target creatures.
```yaml
__typeName: ActivatedAbilityDestroyBehavior
applyto: targets
```

#### ActivatedAbilityFloatTextBehavior
**Purpose**: Show floating text above targets.
```yaml
__typeName: ActivatedAbilityFloatTextBehavior
text: "Text"
color: "#ffffffff"
applyto: targets
```

#### ActivatedAbilityDelayBehavior
**Purpose**: Pause execution.
```yaml
__typeName: ActivatedAbilityDelayBehavior
delay: 1                # Seconds
proceedCondition: ""    # Optional GoblinScript
applyto: targets
```

#### ActivatedAbilityInitiativeBehavior
**Purpose**: Manipulate combat/initiative order.
```yaml
__typeName: ActivatedAbilityInitiativeBehavior
mode: begin_turn
applyto: targets
```

#### ActivatedAbilityReplenishBehavior
**Purpose**: Restore a resource.
```yaml
__typeName: ActivatedAbilityReplenishBehavior
resourceid: <uuid>
quantity: "1"           # GoblinScript
applyto: targets
```

#### ActivatedAbilityScriptBehavior
**Purpose**: Execute arbitrary Lua code (advanced, rarely needed).
```yaml
__typeName: ActivatedAbilityScriptBehavior
name: Script
code: "-- lua code here"
applyto: targets
```

#### ActivatedAbilityCustomTriggerBehavior
**Purpose**: Dispatch a custom trigger event.
```yaml
__typeName: ActivatedAbilityCustomTriggerBehavior
triggerName: ""
value: ""               # GoblinScript
applyto: targets
```

#### ActivatedAbilityConditionSourceBehavior
**Purpose**: Set the source creature for a condition (e.g., frightened source).
```yaml
__typeName: ActivatedAbilityConditionSourceBehavior
condid: <condition-uuid>
conditionMode: ability  # ability, caster
applyto: targets
```

#### ActivatedAbilityApplyRidersBehavior
**Purpose**: Attach rider conditions to an inflicted condition.
```yaml
__typeName: ActivatedAbilityApplyRidersBehavior
conditionid: "none"
riderid: "none"
applyto: targets
```

#### ActivatedAbilityRollBehavior
**Purpose**: Show a dice roll dialog.
```yaml
__typeName: ActivatedAbilityRollBehavior
roll: ""
rollDescription: "Roll Dice"
consequenceText: ""
applyto: targets
```

#### ActivatedAbilitySkillCheckBehavior
**Purpose**: Prompt a skill/attribute check.
```yaml
__typeName: ActivatedAbilitySkillCheckBehavior
rollType: attribute
consequenceText: ""
applyto: targets
```

#### ActivatedAbilityTableRollBehavior
**Purpose**: Roll on a random table.
```yaml
__typeName: ActivatedAbilityTableRollBehavior
tableType: custom
tableid: "none"
resourceAction: "none"
interpretResultAsGameRule: false
customTable: {}
applyto: targets
```

#### ActivatedAbilityCreateItemBehavior
**Purpose**: Create an item in target's inventory.
```yaml
__typeName: ActivatedAbilityCreateItemBehavior
itemid: "none"
quantity: "1"
applyto: targets
```

#### ActivatedAbilityDropItemsBehavior
**Purpose**: Drop/discard equipped items.
```yaml
__typeName: ActivatedAbilityDropItemsBehavior
slotTarget: hands
number: "all"
applyto: targets
```

#### ActivatedAbilityChangeMovementTypeBehavior
**Purpose**: Change movement type.
```yaml
__typeName: ActivatedAbilityChangeMovementTypeBehavior
movementType: fly
applyto: targets
```

#### ActivatedAbilityOrderTargetsBehavior
**Purpose**: Sort targets by formula before subsequent behaviors.
```yaml
__typeName: ActivatedAbilityOrderTargetsBehavior
orderFormula: ""        # GoblinScript
applyto: targets
```

#### ActivatedAbilityResetRollStatusBehavior
**Purpose**: Clear hit/crit status from earlier behaviors.
```yaml
__typeName: ActivatedAbilityResetRollStatusBehavior
applyto: targets
```

#### ActivatedAbilityCharacterSpeechBehavior
**Purpose**: Make the token speak random text.
```yaml
__typeName: ActivatedAbilityCharacterSpeechBehavior
variations: []
fallbackText: ""
applyto: targets
```

#### ActivatedAbilityRememberBehavior
**Purpose**: Store a computed value for later use in the cast.
```yaml
__typeName: ActivatedAbilityRememberBehavior
memoryName: "value"
calculation: "0"        # GoblinScript
applyto: targets
```

#### ActivatedAbilityOpposedRollBehavior
**Purpose**: Opposed power roll (attacker vs defender).
```yaml
__typeName: ActivatedAbilityOpposedRollBehavior
attackAttributes:
  attribute: mgt
defenseAttributes:
  attribute: mgt
silent: true
applyto: targets
```

#### ActivatedAbilityFallBehavior
**Purpose**: Force targets to fall.
```yaml
__typeName: ActivatedAbilityFallBehavior
applyto: targets
```

#### ActivatedAbilityRaiseCorpseBehavior
**Purpose**: Revive a dead creature.
```yaml
__typeName: ActivatedAbilityRaiseCorpseBehavior
restoreStamina: true
applyto: targets
```

#### ActivatedAbilityDisguiseBehavior
**Purpose**: Change appearance.
```yaml
__typeName: ActivatedAbilityDisguiseBehavior
mode: target            # target, specific
monsterType: "none"
appearanceName: ""
applyto: targets
```

#### ActivatedAbilityCreateObjectBehavior
**Purpose**: Spawn a map object.
```yaml
__typeName: ActivatedAbilityCreateObjectBehavior
objectid: false
randomize: false
targetFloor: 0
applyto: targets
```

#### ActivatedAbilityChangeElevationBehavior
**Purpose**: Modify map elevation.
```yaml
__typeName: ActivatedAbilityChangeElevationBehavior
shape: circle
radius: 1
height: "2"             # GoblinScript
recalculateElevation: true
testFalling: false
applyto: targets
```

#### ActivatedAbilityChangeTerrainBehavior
**Purpose**: Paint terrain tiles.
```yaml
__typeName: ActivatedAbilityChangeTerrainBehavior
shape: circle
radius: 1
tileid: "none"
applyto: targets
```

#### ActivatedAbilityMacroBehavior
**Purpose**: Execute a macro command.
```yaml
__typeName: ActivatedAbilityMacroBehavior
macro: ""
applyto: targets
```

#### ActivatedAbilityPayAbilityCostBehavior
**Purpose**: Force immediate payment of ability cost.
```yaml
__typeName: ActivatedAbilityPayAbilityCostBehavior
applyto: targets
```

#### ActivatedAbilityRoutineControlBehavior
**Purpose**: Present routine selection dialog.
```yaml
__typeName: ActivatedAbilityRoutineControlBehavior
triggerOnly: true
applyto: targets
```

#### ActivatedAbilityPersistenceControlBehavior
**Purpose**: Manage persistent abilities.
```yaml
__typeName: ActivatedAbilityPersistenceControlBehavior
triggerOnly: true
mono: false
applyto: targets
```

#### ActivatedAbilityRecastBehavior
**Purpose**: Re-cast a previously used ability.
```yaml
__typeName: ActivatedAbilityRecastBehavior
hasCast: false
mono: true
abilityFilter: ""       # GoblinScript
applyto: targets
```

#### ActivatedAbilityRecoverySelectionBehavior
**Purpose**: UI for choosing recoveries and effect removal.
```yaml
__typeName: ActivatedAbilityRecoverySelectionBehavior
applyto: targets
```

#### ActivatedAbilityStealAbilityBehavior
**Purpose**: Steal an ability from target.
```yaml
__typeName: ActivatedAbilityStealAbilityBehavior
stacks: 1
abilityFilter: ""       # GoblinScript
applyto: targets
```

#### ActivatedAbilityDrawSteelCommandBehavior
**Purpose**: Execute GoblinScript rules during power table resolution.
```yaml
__typeName: ActivatedAbilityDrawSteelCommandBehavior
rule: ""                # GoblinScript rule text
promptWhenResolving: false
promptWhenResolvingText: ""
applyto: targets
```

#### ActivatedAbilitySummonCompanionBehavior
**Purpose**: Summon a beastheart companion.
```yaml
__typeName: ActivatedAbilitySummonCompanionBehavior
applyto: targets
```

#### ActivatedAbilityRevertLocBehavior
**Purpose**: Move creature back along movement path.
```yaml
__typeName: ActivatedAbilityRevertLocBehavior
distance: 1
applyto: targets
```

#### ActivatedAbilityFizzleBehavior
**Purpose**: Cancel/remove targets from ability.
```yaml
__typeName: ActivatedAbilityFizzleBehavior
applyto: targets
```

#### ActivatedAbilityModifiersBehavior
**Purpose**: Inject modifiers into the current ability.
```yaml
__typeName: ActivatedAbilityModifiersBehavior
instant: true
applyto: targets
```

#### ActivatedAbilityManipulateTargetLocs
**Purpose**: Shift target locations to a different floor.
```yaml
__typeName: ActivatedAbilityManipulateTargetLocs
mode: floor_down
applyto: targets
```

---

## CharacterModifier Types

All use `__typeName: CharacterModifier`. The `behavior` field selects the sub-type.

### Common Fields (all modifier types)

```yaml
__typeName: CharacterModifier
name: "Modifier Name"
description: ""
guid: <uuid>
sourceguid: <uuid>          # UUID of parent feature/ability
source: "Trait"             # Human-readable source category
behavior: "<type-id>"       # Selects modifier sub-type
domains:                    # Ownership tracking
  "CharacterFeature:<uuid>": true
filterCondition: ""         # GoblinScript: when modifier is active
displayCondition: ""        # GoblinScript: when modifier is visible
numCharges: "1"             # GoblinScript
resourceRefreshType: "none" # none, encounter, turn, round, longrest, shortrest
resourceCost: "none"
deletable: false
```

### behavior: "attribute"
Modify a numeric attribute.
```yaml
behavior: attribute
attribute: speed            # See attribute IDs below
value: 3                    # Numeric value or GoblinScript formula
operation: add              # "add" (default), "set", "max", "min"
```

**Standard attribute IDs** (not always matching the display name!):

| ID | Display Name |
|----|-------------|
| `speed` | Speed |
| `forcedmoveresistance` | Stability |
| `creatureSize` | Size |
| `armorClass` | Armor Class |

For custom attributes, use the attribute UUID (e.g.,
`attribute: b6c7c0b4-4584-4889-a2de-1f62aa9df2ce` for Ignore Difficult Terrain).

**WARNING:** `stability` is NOT a valid attribute ID -- use `forcedmoveresistance` instead.

**Operation values (code-verified):**
- `add` -- add value to current (default)
- `set` -- set attribute to exact value
- `max` -- set to max(current, value)
- `min` -- set to min(current, value)

### behavior: "resistance"
Grant damage immunity/resistance/weakness.
```yaml
behavior: resistance
resistances:
  - apply: all              # all, nonmagic
    damageType: <uuid>      # Damage type UUID (or "all")
    dr: 5                   # Reduction amount
    nonmagic: false
```

### behavior: "conditionimmunity"
Grant immunity to conditions.
```yaml
behavior: conditionimmunity
conditions:
  <condition-uuid>: true
```

### behavior: "trigger"
Grant a triggered ability.
```yaml
behavior: trigger
triggeredAbility:
  __typeName: TriggeredAbility
  ...                       # Full TriggeredAbility object
```

### behavior: "activated"
Grant an activated ability.
```yaml
behavior: activated
activatedAbility:
  __typeName: ActivatedAbility
  ...                       # Full ActivatedAbility object
multicharge: false
suppressOthers: false
```

### behavior: "power"
Modify power rolls (the core Draw Steel modifier).
```yaml
behavior: power
rollType: ability_power_roll  # See rollType values below
modtype: edge                 # See modtype values below
keywords:                     # Only apply when ability has these keywords
  Strike: true
activationCondition: ""       # GoblinScript condition
rules: ""                     # GoblinScript rules (for customrule modtype)
damageModifier: ""            # GoblinScript formula for flat damage bonus
damageModifierType: "none"    # "none" = add to existing, or damage type UUID
damageMultiplier: "full"      # "full" (default), "half", "none"
potencymod: "none"            # Potency modifier: "none", "1", "2", "-1", "-2", "custom"
```

#### rollType Values (code-verified from g_powerRollTypes)

| Value | Description |
|-------|-------------|
| `all` | All our power rolls (except enemy rolls) |
| `ability_power_roll` | Ability rolls |
| `test_power_roll` | Tests |
| `opposed_power_roll` | Opposed tests |
| `resistance_power_roll` | Resistance rolls |
| `project_roll` | Project rolls |
| `enemy_ability_power_roll` | Enemy ability rolls vs us |

#### modtype Values (code-verified from s_modificationTypes -- 28 values)

| ID | Description |
|----|-------------|
| `none` | No modification (useful for pure damageModifier/damageMultiplier) |
| `edge` | +1 Edge |
| `double_edge` | +2 Edges |
| `bane` | +1 Bane |
| `double_bane` | +2 Banes |
| `edge_bane` | Edge becomes Bane |
| `bane_edge` | Bane becomes Edge |
| `bane_double_edge` | Bane becomes Double Edge |
| `remove_edge` | Remove Edge |
| `remove_bane` | Remove Bane |
| `ignore_edges` | Ignore all Edges |
| `ignore_banes` | Ignore all Banes |
| `tier3` | Automatic Tier 3 (auto-success) |
| `tier1` | Automatic Tier 1 (auto-failure) |
| `nottierthree` | Cannot roll Tier 3 |
| `nottierone` | Cannot roll Tier 1 |
| `tierup` | Tier Up (improve result by one tier) |
| `tierdown` | Tier Down (worsen result by one tier) |
| `plusone` | +1 to roll |
| `plustwo` | +2 to roll |
| `plusthree` | +3 to roll |
| `minusone` | -1 to roll |
| `minustwo` | -2 to roll |
| `minusthree` | -3 to roll |
| `suppresseffects` | Suppress effects |
| `appendroll` | Append to roll (hideText) |
| `replaceroll` | Replace roll (hideText) |

**NOTE:** The old reference listed `doubleedge`, `doublebane`, `autotier1`, `autotier2`,
`autotier3`, `customrule`, `bonus`, `penalty` -- these are WRONG. Use the exact IDs above.

#### All Optional Fields on behavior: "power"

Beyond the core fields shown above, the power modifier supports many optional fields:

**Targeting/Filtering:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `activationCondition` | bool/string | `false` | `false`=never, `true`=always, string=GoblinScript. Unquoted YAML `true`/`false` = boolean. Quoted `"1"`/`"0"` = GoblinScript. |
| `displayCondition` | string | `""` | Controls display separately from activation |
| `keywords` | table | `{}` | `{Strike: true}` -- only for abilities with these keywords |
| `matchAnyKeywords` | boolean | `false` | `false`=AND (all keywords), `true`=OR (any keyword) |
| `attribute` | string | `"all"` | For tests: filter to specific characteristic |
| `skills` | string[] | `{}` | For tests: filter to specific skill IDs |
| `rollRequirement` | string | `"none"` | Pre-condition on the roll state (see table below) |

**Damage Modification:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `damageModifier` | string | `""` | GoblinScript for flat damage bonus (e.g., `"6"`, `"Stacks * 3"`) |
| `damageModifierType` | string | `"none"` | `"none"` = add to existing type, or a damage type name for separate typed damage |
| `damageMultiplier` | string | `"full"` | `"full"`, `"half"`, `"none"` |
| `damageTypeMappings` | table | -- | `{fromType: toType}` for damage type conversion. `"all"` key converts all. |

**Potency:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `potencymod` | string | `"none"` | `"none"`, `"1"`, `"2"`, `"-1"`, `"-2"`, `"custom"` |
| `customPotency` | string | `""` | GoblinScript when potencymod is `"custom"` |
| `resistanceFormula` | string | `""` | GoblinScript for modified resistance value |

**Surges:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `surges` | string | `""` | GoblinScript for surges to add |
| `surgesCanBeKept` | boolean | `false` | Whether surges are preserved |
| `surgeDamageType` | string | `"none"` | Override surge damage type |

**Tier Text Modification:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `addText` | string | `""` | Text appended to all tiers. Supports `X/Y/Z` per-tier syntax. |
| `replacePattern` | string | `""` | Regex pattern to find in tier text |
| `replaceText` | string | `""` | Replacement text. Supports `X/Y/Z` per-tier. Also used by `appendroll`/`replaceroll` modtypes. |

**Forced Movement Adjustments:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `adjustments` | table[] | `{}` | Each: `{type: "push"/"pull"/"slide"/"jump", value: GoblinScript}` |

**Trigger Integration (used within powertabletrigger context):**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `hasTriggerBefore` | boolean | `false` | Whether a trigger fires before the modifier applies |
| `triggerBefore` | TriggeredAbility | -- | The pre-modifier trigger ability |
| `triggerBeforeCondition` | string | `""` | GoblinScript condition for pre-trigger |
| `hasCustomTrigger` | boolean | `false` | Whether a trigger fires after the modifier applies |
| `customTrigger` | TriggeredAbility | -- | The post-modifier trigger ability |
| `changeTarget` | boolean | `false` | Whether to retarget the ability |
| `changeTargetRange` | string | `"none"` | Retarget range mode (see below) |
| `changeTargetDistance` | number | `0` | Distance for retargeting |
| `changeTargetFilter` | string | `""` | GoblinScript filter for retarget candidates |
| `changeTargetEffect` | string | `"all"` | What carries over: `"all"`, `"forcemove"`, `"none"` |

**Resource Cost:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `resourceCostType` | string | `"none"` | Cost type (see values below) |
| `resourceCostAmount` | string | `"1"` | GoblinScript for cost amount |
| `overrideCost` | boolean | `false` | Override the ability's cost |

**Chaining:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `baseModifier` | CharacterModifier | -- | Base modifier this extends (set at runtime) |
| `overrideBase` | boolean | `false` | Override base modifier instead of chaining |
| `gobefore` | boolean | `false` | Fire before the base trigger |

#### rollRequirement Values

Optional field. If set, the modifier only applies when the roll's edge/bane state matches:

| Value | Description |
|-------|-------------|
| `none` | No requirement (default) |
| `bane` | Only when has bane and few edges |
| `doublebane` | Only when has double bane and no edges |
| `edge` | Only when has edge and few banes |
| `doubleedge` | Only when has double edge and no banes |
| `nobane` | Only when has no banes |
| `noedge` | Only when has no edges |
| `skilled` | Only when has Skilled modifier |
| `unskilled` | Only when does not have Skilled modifier |
| `surges` | Only when surges are present |

#### resourceCostType Values (for power modifiers)

| Value | Description |
|-------|-------------|
| `none` | No cost |
| `cost` | Costs a resource |
| `multicost` | Costs multiple resources |
| `surges` | Costs surges |
| `epicresource` | Costs epic resource |

#### damageMultiplier Values

| Value | Description |
|-------|-------------|
| `full` | Normal damage (default) |
| `half` | Halve the damage |
| `none` | No damage |

#### changeTargetRange Values

| Value | Description |
|-------|-------------|
| `none` | No change (default) |
| `ability` | Use ability range |
| `distance` | Use specific distance |

### behavior: "powertabletrigger"
Triggered ability that adds a power roll modifier when a trigger condition is met.
```yaml
behavior: powertabletrigger
type: trigger               # trigger (costs triggered action), free, passive
targetType: self            # self, selforally, ally, enemy, anycreature
trigger: takedamage         # See trigger values below
range: 10                   # GoblinScript range (only when target is not self)
rules: ""                   # GoblinScript display rules text
powerRollModifier:          # Embedded CharacterModifier with behavior="power"
  __typeName: CharacterModifier
  behavior: power
  ...
```

**powertabletrigger `type` values:**
- `trigger` -- costs a triggered action resource
- `free` -- free triggered action (no resource cost)
- `passive` -- always active (no action required)

**powertabletrigger `targetType` values** (different from ActivatedAbility targetType!):
- `self` -- only affects self
- `selforally` -- self or ally
- `ally` -- ally only
- `enemy` -- enemy only
- `anycreature` -- any creature

**powertabletrigger `trigger` values** (different from TriggeredAbility triggers!):

| Value | Description | Who triggers |
|-------|-------------|-------------|
| `powerroll` | Makes a Power Roll | Caster |
| `takedamage` | Target Takes Damage | Target |
| `dealdamage` | Target Deals Damage | Caster |
| `strike` | Targeted by Strike | Target (ability must have Strike keyword) |
| `forcemove` | Target Force Moves Another | Caster |
| `forcemoved` | Target is Force Moved | Target |
| `casting` | Target is Casting | Caster (modifies at cast time) |

**Optional powertabletrigger fields:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `damageType` | string | `"all"` | Filter: `"all"`, `"typed"`, `"untyped"` |
| `targetFilter` | string | `""` | GoblinScript with Caster, Target, Triggerer, Ability, Cast |
| `forceReroll` | boolean | `false` | Force re-roll of the power roll |
| `multitarget` | string | `"one"` | `"one"` or `"all"` (apply to one target or all) |
| `additionalCostModifiers` | CharacterModifier[] | `{}` | Extra power modifiers offered as options |

### behavior: "powertableadditional"
Add extra options to an existing power roll trigger.
```yaml
behavior: powertableadditional
original: "<trigger name>"  # Name of trigger to attach to
additionalModifier:         # CharacterModifier with behavior="power"
  __typeName: CharacterModifier
  behavior: power
  ...
gobefore: false             # If true, this fires before the original
```

### behavior: "bestowcondition"
Automatically bestow a condition.
```yaml
behavior: bestowcondition
conditionid: <condition-uuid>
explanation: ""
```

### behavior: "suppressabilities"
Disable abilities matching a filter.
```yaml
behavior: suppressabilities
abilityFilter: ""           # GoblinScript filter
explanation: ""
```

### behavior: "icon"
Show a status icon on the token.
```yaml
behavior: icon
statusIcon: "none"
iconColor: "#ffffffff"
```

### behavior: "resource"
Grant a resource.
```yaml
behavior: resource
resourceType: "none"
num: 1                      # Number or GoblinScript
level: ""                   # Optional GoblinScript
```

### behavior: "aura"
Create a persistent aura.
```yaml
behavior: aura
```

### behavior: "light"
Grant a light source.
```yaml
behavior: light
itemid: false
```

### behavior: "suspended"
Make creature hover.
```yaml
behavior: suspended
altitude: 1
```

### behavior: "invisibility"
Make creature invisible.
```yaml
behavior: invisibility
altitude: 1
```

### behavior: "forcedmovement"
Convert forced movement types.
```yaml
behavior: forcedmovement
movementTypes:
  - from: push
    to: slide
```

### behavior: "filter"
Apply a creature filter.
```yaml
behavior: filter
filterid: "none"
filter: ""                  # GoblinScript
```

### behavior: "modifyability"
Modify existing abilities.
```yaml
behavior: modifyability
```

### behavior: "alternateappearance"
Grant alternate visual appearance.
```yaml
behavior: alternateappearance
appearance: "Alternate Appearance"
monsterDefault: "none"
```

### behavior: "modrider"
Apply modifiers to mount riders.
```yaml
behavior: modrider
feature:                    # CharacterFeature with sub-modifiers
  __typeName: CharacterFeature
  modifiers: [...]
```

### behavior: "modcaptain"
Apply modifiers to squad captain.
```yaml
behavior: modcaptain
feature:
  __typeName: CharacterFeature
  modifiers: [...]
```

### behavior: "triggerdisplay"
Display-only triggered ability (for character sheet rendering).
```yaml
behavior: triggerdisplay
ability:
  __typeName: TriggeredAbilityDisplay
  name: "Triggered Ability"
  cost: ""
  keywords: {}
  flavor: ""
  type: trigger
  distance: "Ranged 10"
  target: "One creature"
  trigger: ""
  effect: ""
```

### behavior: "routine"
Display-only routine.
```yaml
behavior: routine
ability:
  __typeName: RoutineDisplay
  ...
```

### behavior: "modifyresourcechecklist"
Add entries to heroic resource checklist.
```yaml
behavior: modifyresourcechecklist
resourceChecklist:
  - guid: <uuid>
    name: "Entry Name"
    details: "Description"
    quantity: "1"
```

### behavior: "growingresources"
Level-based resource progression.
```yaml
behavior: growingresources
progression:
  - level: 1
    resources: 2
  - level: 5
    resources: 4
```

### behavior: "proficiency"
Grant skill proficiency or language.
```yaml
behavior: proficiency
```

### behavior: "movementtext"
Show reminder text on character sheet.
```yaml
behavior: movementtext
```

### behavior: "kitaccess"
Grant access to new types of kits (Draw Steel specific).
```yaml
behavior: kitaccess
```

### behavior: "creaturetype"
Modify creature type.
```yaml
behavior: creaturetype
```

### behavior: "conditionsourcebestow"
Reciprocal condition (bestow condition back on source).
```yaml
behavior: conditionsourcebestow
```

### behavior: "none"
No-op placeholder.
```yaml
behavior: none
```

### All Registered Behavior IDs (Draw Steel active set)

These are all behavior IDs available in Draw Steel mode after deregistrations:

`none`, `icon`, `attribute`, `resistance`, `conditionimmunity`, `trigger`, `activated`,
`resource`, `power`, `powertabletrigger`, `powertableadditional`, `bestowcondition`,
`suppressabilities`, `aura`, `light`, `suspended`, `invisibility`, `forcedmovement`,
`filter`, `modifyability`, `alternateappearance`, `modrider`, `modcaptain`,
`triggerdisplay`, `routine`, `modifyresourcechecklist`, `growingresources`,
`proficiency`, `movementtext`, `kitaccess`, `creaturetype`, `conditionsourcebestow`,
`transform`

Deregistered in Draw Steel (NOT available):
`d20`, `armorclasscalculation`, `attackattribute`, `altspells`, `modifydamageaftersave`,
`grantSpellList`, `grantSpells`, `spell`, `damage`, `multiattack`, `rollsattacking`,
`spellcasting`

---

## TriggeredAbility Fields

Extends ActivatedAbility with trigger-specific fields.

```yaml
__typeName: TriggeredAbility
name: "Ability Name"
# ... all ActivatedAbility fields ...

# Trigger-specific fields
trigger: takedamage         # See trigger list below
mandatory: true             # true=auto, false=prompt, "local"=auto/local
conditionFormula: ""        # GoblinScript condition for trigger to fire
subject: self               # See subject values below
subjectRange: ""            # GoblinScript range formula
targetType: self            # self, all, attacker, target, subject, aura
characterConditionRequired: "none"  # Optional condition that must be present
characterConditionInflictedBySelf: false
triggerPrompt: ""           # Text shown when prompting
despawnBehavior: remove     # remove, corpse
categorization: "Triggered Ability"
```

### subject Values (code-verified from GenerateManualVersion)

| Value | Description |
|-------|-------------|
| `self` | The creature with this trigger (default) |
| `any` | Any creature |
| `selfandheroes` | Self and hero allies |
| `otherheroes` | Other hero allies (not self) |
| `selfandallies` | Self and all allies |
| `allies` | All allies (not self) |
| `enemy` | Enemies |
| `other` | Other (custom) |

### TriggeredAbility targetType Values

These are different from ActivatedAbility targetType values:

| Value | Description |
|-------|-------------|
| `self` | The triggered creature itself |
| `all` | All creatures |
| `attacker` | The attacking/triggering creature |
| `target` | Select a target |
| `subject` | The trigger subject |
| `aura` | Creatures in the aura (for aura triggers) |

### Available Triggers (code-verified)

#### Base Triggers (TriggeredAbility.lua)

| Trigger ID | When It Fires |
|-----------|--------------|
| `regainhitpoints` | Creature regains stamina |
| `losehitpoints` | Creature takes damage |
| `zerohitpoints` | Creature drops to zero stamina |
| `kill` | Creature kills another |
| `creaturedeath` | Creature dies |
| `saveagainstdamage` | Made reactive roll against damage |
| `move` | Creature begins movement |
| `finishmove` | Creature completes movement |
| `forcemove` | Creature is force moved |
| `teleport` | Creature teleports |
| `beginturn` | Start of creature's turn |
| `endturn` | End of creature's turn |
| `beginround` | Start of combat round |
| `endcombat` | End of combat encounter |
| `rollinitiative` | Draw Steel (initiative rolled) |
| `attack` | Creature attacks an enemy |
| `fumble` | Fumble an attack (hidden if no fumble outcome) |
| `collide` | Creature collides with creature or object |
| `wallbreak` | Creature breaks through a wall |
| `fall` | Creature lands from a fall |
| `pressureplate` | Stepped on a pressure plate |
| `custom` | Custom trigger (use triggerName) |

#### D&D/Legacy Triggers (dnd5e.lua -- also active)

| Trigger ID | When It Fires |
|-----------|--------------|
| `attacked` | Creature is attacked |
| `miss` | Creature misses an attack |
| `hit` | Creature is hit by attack |

#### Draw Steel Triggers (MCDMRules.lua)

| Trigger ID | When It Fires |
|-----------|--------------|
| `dealdamage` | Damage an enemy (overrides base with more symbols) |
| `losehitpoints` | Take damage (overrides base with attacker symbols) |
| `winded` | Become winded |
| `dying` | Become dying (heroes only) |
| `endrespite` | End respite |
| `inflictcondition` | Condition applied |
| `movethrough` | Move through creature |
| `leaveadjacent` | Creature moved away from |
| `gaintempstamina` | Gain temporary stamina |
| `castsignature` | Use signature attack or area |
| `useresource` | Use a resource |
| `gainresource` | Gain a resource |
| `useability` | Use an ability |
| `targetwithability` | Target with ability |
| `prestartturn` | Before start of turn |
| `rollpower` | Roll power |

**Key trigger distinction -- `useability` vs `targetwithability`:**
- `useability`: Fires on the CASTER when they use an ability. Symbols: `Used Ability` (ability).
  Use for: "when you use ability X, gain a surge" (self-effect).
- `targetwithability`: Fires on the CASTER for EACH TARGET of an ability. Symbols: `Used Ability`
  (ability), `Target` (the targeted creature). Use for: "when you target a creature with ability X,
  apply effect to the target." The `targetType` on the triggered ability should be `target` to
  apply behaviors to the targeted creature.

Example: Apply weakness to targets of Drink Most Exquisite:
```yaml
trigger: targetwithability
conditionFormula: 'Used Ability.Name is "Drink Most Exquisite"'
targetType: target
behaviors:
  - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
    ongoingEffect: <weakness-effect-uuid>
    duration: save_ends
```

---

## CharacterOngoingEffect Fields

Required fields for a valid CharacterOngoingEffect (code-verified from OngoingEffect.lua):

```yaml
__typeName: CharacterOngoingEffect
id: <uuid>                          # REQUIRED
name: "Effect Name"                 # default: "New Ongoing Effect"
description: ""
iconid: "ui-icons/skills/1.png"     # REQUIRED - crashes if missing
source: "Ongoing Effect"
modifiers: []                       # Array of CharacterModifier
display:                            # REQUIRED
  saturation: 1
  hueshift: 0
  bgcolor: "#ffffffff"
  brightness: 1

# Stacking
stackable: false                    # Enable stacking
clearStacksWhenApplying: false      # false=additive stacks, true=max stacks

# Duration options (defined on the effect type itself)
durationUntilEndOfTurn: false

# Other fields with defaults
transformation: false
canEndWithAction: false
endActionType: "none"
endEffectRequiresSavingThrow: false
endingEffectSavingThrow: "none"
endingEffectSavingThrowDC: 10
sustainFormula: ""
emoji: "none"
condition: "none"                   # Underlying condition for this effect
statusEffect: true                  # Is this a standard status condition?
hiddenOnToken: false
hiddenFromEnemies: false
endTrigger: "none"
countsTowardInstanceLimit: true
casterTracking: "none"              # "none", "one", "bonded", "multiple"
buffType: "debuff"                  # "debuff", "buff", "neutral"
custom: true                        # Marks as attached to an ability
```

### Stacking Modes

- `stackable: false` (default): Reapplying refreshes, no accumulation
- `stackable: true, clearStacksWhenApplying: false`: Stacks ADD (1+1=2, 2+1=3, ...)
- `stackable: true, clearStacksWhenApplying: true`: Stacks take MAX (max(old, new))

**GoblinScript access to stacks:**
- `Stacks` -- inside modifier formulas, returns the stack count
- `Stacks("Effect Name")` -- in creature context, returns stack count of a named effect

---

## Power Table Effect / Rules Engine Commands

The `ActivatedAbilityDrawSteelCommandBehavior` (registered as "Power Table Effect")
executes text rule strings through the full rules engine. This is **the preferred way**
to apply effects like shift, forced movement, conditions, and damage because the rules
engine handles all game logic (e.g., a shift command respects "can't shift" status).

The same syntax is used in **tier strings** of `ActivatedAbilityPowerRollBehavior`.

### Usage

```yaml
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  rule: "shift 3"          # The rule string to execute
  applyto: targets
```

### GoblinScript Interpolation

Use `{expression}` for dynamic values evaluated against the caster:
```
push {Reason}           # Push distance = caster's Reason
{Might} fire damage     # Damage = caster's Might, fire type
shift {Level}           # Shift distance = caster's level
slide {Reason*2}        # Arithmetic in expressions
```

### Compound Rules

Separate multiple effects with `;`, `,`, `and`, or `then`:
```
2 damage; prone; slowed (eot)        # Three effects in sequence
pull 5; A<2 restrained (EoT)         # Pull then gated condition
slide 12 + R; prone                  # Slide then prone
```

### Complete Command Reference

#### Damage
```
<number> [type] damage [(half)]
```
- `2 damage` -- untyped
- `5 fire damage` -- typed
- `3d6 damage` -- dice notation
- `2 + M damage` -- arithmetic with characteristics
- `damage (half)` -- halved damage

#### Forced Movement
```
[vertical] (push|pull|slide) <distance> [ignoring stability]
```
- `push 3`, `pull 6`, `slide 5`
- `vertical push 4`, `vertical slide 8`
- `push {Reason}` -- GoblinScript distance
- `slide 3 ignoring stability`

#### Shift
```
[you ]shift[s] [up to ]<distance> [squares]
```
- `shift 2`, `shift 5 squares`, `you shift 3`
- Respects "Shift Disabled" and movement speed limits

#### Teleport
```
[you ]teleport[s] [up to ]<distance> [squares]
```
- `teleport 5`, `you teleport 3 squares`

#### Jump
```
jump <distance>
```
- `Jump 3` -- limited by remaining movement speed

#### Conditions
```
<condition> [(eot|eoe|save ends)]
```
- `prone` -- permanent (until stand up)
- `grabbed` -- permanent (until escape)
- `slowed (eot)` -- end of target's next turn
- `frightened (save ends)` -- until saving throw
- `bleeding (EoT)`, `dazed (save ends)`, `restrained (EoT)`
- `weakened (save ends)`, `taunted (eot)`
- `invisible (EoT)`, `hidden (eoe)`
- `slowed and weakened (save ends)` -- multiple conditions

#### Gated Effects (Potency Checks)
```
[MARIP] < [number|weak|average|strong] <effect>
```
Abbreviations: M=Might, A=Agility, R=Reason, I=Intuition, P=Presence

- `M<2 prone` -- if target's Might < 2, knock prone
- `A<3 weakened (save ends)` -- if Agility < 3, weakened
- `P<{Strong} frightened (save ends)` -- GoblinScript potency
- `R < average slowed (eot)` -- word-based potency
- `I < 2 grabbed (save ends)`
- `M < 1, pushed 2` -- gated push (applies if Might < 1)

#### Surges
```
[the|each] target gains <number> surge[s]
```
- `target gains 1 surge`, `target gains 3 surges`

#### Heroic Resources
```
Gain <number> <resource name>
```
- `Gain 1 piety`, `Gain 2 focus`, `Gain 1 essence`

#### Malice
```
the director gains <number> malice
```

#### Swap
```
swap places with the target
```

#### Prone + Can't Stand
```
prone [and] can't stand (<duration>)
```
- `prone and can't stand (eot)`

### Key Notes

1. **Case-insensitive**: All rules are lowercased before matching
2. **Semicolons split effects**: `5 damage; prone` = damage THEN prone
3. **Potency gates**: `M<2 prone` only applies if target's Might < 2
4. **GoblinScript everywhere**: `{expr}` in any value position
5. **Preferred over raw behaviors**: Using `shift 3` as a DrawSteelCommand
   goes through the full rules engine (respects conditions, disabled states, etc.)
   while a raw `ActivatedAbilityRelocateCreatureBehavior` might bypass checks

---

For conditions, see [CONDITIONS.md](CONDITIONS.md).

---

## Global Rules Index

Global rules (`globalRuleMods` table) are features applied automatically to all creatures
(or a subset: heroes, monsters, retainers, companions). They define the baseline game
mechanics -- actions, maneuvers, free strikes, opportunity attacks, etc. Global rules are
applied BEFORE creature-specific features, so creature features can override them.

Understanding global rules is important because:
- They define the standard actions/maneuvers available to all creatures
- Creature abilities may reference or interact with global rule abilities
- New content may need to suppress or modify global rules (e.g., "can't make opportunity attacks")

**Application flags** on each global rule:
- `applyCharacters` -- heroes
- `applyMonsters` -- monsters
- `applyRetainers` -- retainers
- `applyCompanions` -- companions

### Actions and Resources

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `d2f9f92d-4f6d-4b1b-9cba-ff0ecabf9f55` | **Actions** | All | Core action economy: 1 action, 1 maneuver, 1 triggered action per turn. Includes Defend action. |
| `193c0a8b-8e9f-4bf3-8939-9a0a766e257d` | **Move Actions** | All | Disengage (shift 1), Tumble, Shift abilities |
| `883c2fb1-c987-4954-8a05-d90b3412a8af` | **Heroic Resources** | Heroes | Base heroic resource rules |
| `c48b86ce-0da3-483c-b405-441630e7498d` | **Surges** | All | Surge resource + potency surge (spend 2 surges for +1 potency) |
| `fb02522c-2c9a-42e1-8116-01b743d7ad14` | **Malice** | Monsters | Malice resource for monsters |
| `f232412f-23a1-4d64-9173-10f6f3290ec9` | **Villain Actions** | Monsters | Villain action resource |

### Maneuvers

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `4d0ead0e-65af-4cc4-93e0-d6adfe7d06b2` | **Maneuvers** | All | Aid Attack, Hide, Knockback (push 1/2/3), Sprint |
| `9061da45-8fd5-49c7-99bf-c3e98bb6a2e2` | **Catch Breath** | Heroes | Spend Recovery to regain Stamina |
| `1d642117-27c8-49c5-b37b-a8fc94b5ca5b` | **Grab** | All | Grapple maneuver with Aggressive/Safe modes |
| `75fed15a-50f0-45ef-99fe-607e72b87046` | **Charge** | All | Move in straight line + melee free strike |

### Combat Triggers

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `64a0b403-130d-4d7c-a6d6-769b49172322` | **Opportunity Attack** | All | Free strike when enemy leaves adjacent space without shifting |
| `228176cb-87b7-4e06-bf75-67a8d9b9c845` | **Critical Hit!** | All | Natural 19-20 grants extra action |
| `800867b2-86ac-4848-b95f-e147019ef22d` | **End Turn Save** | All | Auto saving throw at end of turn |
| `c2d07fb5-0eeb-4932-ae5f-758d516ded7d` | **Collision** | All | Damage from forced movement collisions |
| `4dd01554-5471-4eb6-aeba-ff42c50343f4` | **Falling** | All | Fall damage (2/square, max 50) + prone |
| `60c3b18d-3186-406f-badb-d3ba656d4766` | **Triggers** | All | Spend Recovery trigger, End Effect trigger |

### Free Strikes

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `a2352c5c-a2d9-4c30-92c2-cba115bfbb72` | **Free Strikes** | Heroes | Melee (2/5/7+M/A) and Ranged (2/4/6+M/A) free strikes |

### Combat Modifiers

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `71933bef-0d7c-4f84-899b-e72156a9ca34` | **Flanking** | All | Edge on melee strikes when flanking |
| `f55452d8-b1ad-499f-b21e-f69aaad65feb` | **High Ground** | All | Edge when attacking from above |
| `3b312257-2e16-4fc9-a870-ca049fa31a47` | **Hiding** | All | Edge on ability rolls when hidden |
| `534cbec8-5c03-4919-9aa4-b34f5db5e3a0` | **Cover** | All | Bane on damage abilities vs covered target |
| `eef51635-752b-4181-968a-6b957302c470` | **Concealment** | All | Bane on strikes vs concealed target |
| `85913b3a-c2b7-45ae-b2f0-52b32b685395` | **Ranged Strikes** | All | Bane on ranged strikes with adjacent enemy |
| `736d5b7c-288e-45dc-80e3-b168d401231a` | **Tests** | All | Skill proficiency (+2), language penalties |
| `caa94136-426c-48e5-8c73-3c0fc75cd2a3` | **Underwater** | All | Fire immunity 5, lightning weakness 5 in water |

### Death and Status

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `1f00c2e7-6e6a-4f23-bd3c-da4c38e35fbd` | **Dying** | All | At 0 Stamina: auto-bleeding, can't Catch Breath |
| `42a8dd10-c3a1-4d69-b03a-2e18095c2a49` | **Monster Death** | Monsters | Remove monster on death, drop loot, leave corpse |

### Other

| UUID | Name | Applies To | Description |
|------|------|-----------|-------------|
| `6159aea6-6748-4e32-bd20-a953822c60df` | **Hidden Utility Actions** | All | Internal Move Speed ability |
| `6f90ddb0-d311-40d3-afac-8cf235fd1b7b` | **Caelian** | Heroes | All heroes know Caelian language |
| `4eaeb66a-7f42-4145-b096-a21ef63aeb33` | **Retainers** | Retainers | 6 Recoveries for retainers |

---

## Example YAML Patterns

### Simple Monster (Horde, Level 1)

```yaml
info:
  locInfo: null
  appearance:
    portraitId: null
    offtokenPortraitId: null
    portraitFrameId: null
    portraitRibbon: null
    backgroundId: null
    anthem: null
    anthemVolume: 1
    tokenScaling: 1
    tokenZoom: 1
    portraitOffset: { x: 0, y: 0 }
    frameHueShift: 0
    frameSaturation: 1
    frameBrightness: 1
    characterName: null
    characterNamePrivate: false
    flip: false
    saddlePositions: []
  disguise: null
  settings:
    canRotate: false
    useLight: false
    lightColor: { r: 1, g: 1, b: 1, a: 1 }
    lightIntensity: 0.1
    lightRadius: 10
    lightFalloff: 0.1
    lightAngle: 360
  mountedBy: {}
  updateid: <generate-uuid>
  properties:
    __typeName: monster
    titles: []
    characterFeatures: []
    type: monster
    size: 1
    sizeCategory: M
    speed: 5
    stamina: 8
    stability: 0
    freestrike: 3
    minion: false
    captain: false
    monster_type: "Goblin Warrior"
    monster_role: "Harrier"
    monster_subrole: ""
    monster_organization: "Horde"
    monster_level: 1
    monster_ev: 3
    keywords:
      Goblin: true
      Humanoid: true
    attributes:
      mgt: 0
      agl: 2
      rea: 0
      inu: 0
      prs: 0
    conditionImmunities: {}
    damageImmunities: []
    damageWeaknesses: []
    monsterGroupId: "4ac19688-1ab4-40a0-a440-708c0fe6d9f5"
    villainActions: 0
    innateActivatedAbilities:
      - __typeName: ActivatedAbility
        name: "Rusty Sword"
        description: ""
        guid: <generate-uuid>
        actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
        actionNumber: 1
        targeting: direct
        targetType: target
        targetAllegiance: enemy
        numTargets: "1"
        range: 1
        keywords:
          Melee: true
          Strike: true
          Weapon: true
        categorization: "Signature Ability"
        behaviors:
          - __typeName: ActivatedAbilityPowerRollBehavior
            rule: ""
            applyto: targets
          - __typeName: ActivatedAbilityDamageBehavior
            roll: "2 + 2"
            damageType: force
            applyto: targets
        display:
          saturation: 1
          hueshift: 0
          bgcolor: "#ffffffff"
          brightness: 1
    skills: {}
description: "Goblin Warrior"
hidden: false
id: <generate-uuid>
```

### Ongoing Effect (Table Entry)

```yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: <generate-uuid>
guid: <generate-uuid>
name: "Slowed (Custom)"
description: "This creature is slowed."
modifiers:
  - __typeName: CharacterModifier
    behavior: bestowcondition
    conditionid: "68f455f5-135f-495c-822d-40d809d2b15f"
    source: "Ongoing Effect"
    sourceguid: <same-as-parent-id>
    guid: <generate-uuid>
    name: "Slowed"
    description: ""
    domains: {}
source: "Ongoing Effect"
iconid: "ui-icons/skills/1.png"
display:
  saturation: 1
  hueshift: 0
  bgcolor: "#ffffffff"
  brightness: 1
custom: true
```

### Power Roll Tier Patterns

**Simple damage tiers:**
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: 2d10 + 2
  attrid: mgt
  tiers:
    - "7 damage"
    - "11 damage"
    - "14 damage"
```

**Damage with forced movement:**
```yaml
tiers:
  - "8 damage; push 2"
  - "12 damage; push 4"
  - "15 damage; push 8"
```

**Damage with condition (potency check):**
```yaml
tiers:
  - "8 damage; M<1 prone"
  - "13 damage; M<2 prone"
  - "16 damage; M<3 prone"
```

**Typed damage with save-ends condition:**
```yaml
tiers:
  - "5 poison damage"
  - "9 poison damage; dragonsealed (save ends)"
  - "12 poison damage; dragonsealed (save ends)"
```

**Resistance roll (target rolls to resist):**
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  resistanceRoll: true
  roll: 2d10 + Might
  attrid: mgt
  tiers:
    - "12 poison damage; dragonsealed (save ends)"
    - "9 poison damage; dragonsealed (save ends)"
    - "5 poison damage"
```
Note: For resistance rolls, tier 1 is the WORST outcome for the target (highest damage),
tier 3 is the BEST (lowest damage). This is the reverse of normal ability rolls.

**Applying ongoing effects on specific tiers:**
```yaml
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  tiersSelected: [1, 2]         # Apply on tiers 1 and 2 only (1-indexed)
  ongoingEffect: <effect-uuid>
  duration: save_ends
  durationUntilEndOfTurn: false
  ongoingEffectCustom: false
```

**Villain Action example:**
```yaml
- __typeName: ActivatedAbility
  name: "Devastating Strike"
  villainAction: "Villain Action 1"
  categorization: "Villain Action"
  usageLimitOptions:
    resourceid: <unique-uuid>
    charges: "1"
    resourceRefreshType: encounter
  ...
```

### Multi-Mode Abilities (Base + Malice Variant)

Abilities can have multiple modes (e.g., normal + malice-enhanced). Use `multipleModes: true`:

```yaml
- __typeName: ActivatedAbility
  name: "My Ability"
  multipleModes: true
  resourceCost: "101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8"  # Malice
  resourceNumber: "3 when mode = 2 else 0"                 # 0 for mode 1, 3 Malice for mode 2
  modeList:
    - text: "Normal"
    - text: "Malice"
      rules: "Description of malice-enhanced version shown in tooltip."
  behaviors:
    - __typeName: ActivatedAbilityPowerRollBehavior
      modesSelected: [1]         # Only executes in mode 1
      roll: "2d10 + 2"
      tiers: ["5 damage", "9 damage", "12 damage"]
    - __typeName: ActivatedAbilityPowerRollBehavior
      modesSelected: [2]         # Only executes in mode 2
      roll: "2d10 + 2"
      tiers: ["7 damage", "11 damage", "14 damage"]
```

**Key fields:**
- `multipleModes: true` -- enables mode selection UI
- `modeList` -- array of modes with `text` (label) and optional `rules` (tooltip)
- `modesSelected` -- on any behavior, limits execution to listed modes (1-indexed)
- GoblinScript `when mode = X else Y` -- use in fields like `resourceNumber`, `range`
- `mode.condition` -- optional GoblinScript to conditionally enable a mode
- `mode.variation` -- optional complete alternate ActivatedAbility for full swaps

### Damage Halving (powertabletrigger with damageMultiplier)

To halve incoming damage (like Parry or Break Armor), use a `powertabletrigger` modifier:

```yaml
- __typeName: CharacterModifier
  behavior: powertabletrigger
  trigger: takedamage
  targetType: self
  powerRollModifier:
    __typeName: CharacterModifier
    behavior: power
    rollType: ability_power_roll
    damageMultiplier: "half"     # "half" or "none" for no damage
    modtype: edge                # Required but the edge is secondary to damageMultiplier
    name: "Halve Damage"
    guid: <uuid>
```

### Flat Damage Bonuses (damageModifier)

Add flat damage to abilities using the `damageModifier` field on a power modifier:

```yaml
- __typeName: CharacterModifier
  behavior: power
  modtype: none                        # "none" for pure damage addition
  rollType: ability_power_roll
  damageModifier: "6"                  # GoblinScript formula
  damageModifierType: "none"           # "none" = add to existing, or damage type UUID
  activationCondition: "Target.Object" # When to apply
  keywords:
    Strike: true                       # Only for strikes
  name: "Damage Bonus"
```

### Stackable Ongoing Effects

```yaml
__typeName: CharacterOngoingEffect
stackable: true                        # Enable stacking
clearStacksWhenApplying: false         # false=additive, true=max
```

**Example: scaling modifier with stacks:**
```yaml
modifiers:
  - __typeName: CharacterModifier
    behavior: power
    modtype: none
    rollType: enemy_ability_power_roll
    damageModifier: "Stacks * 3"       # 3 per stack: 3, 6, 9, ...
    activationCondition: "1"
```
