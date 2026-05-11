# Class Ability YAML Template

Definitive reference for structuring class abilities in compendium YAML.
Derived from analysis of working Fury and Shadow class files.

---

## Layer Structure Overview

Class abilities are nested four layers deep:

```
ClassLevel
  -> CharacterFeatureChoice    (the choice group: "Signature Ability", "3-Rage Heroic Abilities")
    -> CharacterFeature        (each option: "Brutal Slam", "Hit and Run")
      -> CharacterModifier     (behavior: activated)
        -> ActivatedAbility    (the actual ability with behaviors, targeting, etc.)
```

---

## 1. CharacterFeatureChoice (the choice wrapper)

Lives inside a ClassLevel's `features` array.

```yaml
- __typeName: CharacterFeatureChoice
  name: "Signature Ability"                     # REQUIRED - Display name for the choice group
  description: "Choose one signature ability..." # REQUIRED - Shown in builder UI
  classid: <class-uuid>                         # REQUIRED - UUID of the parent class
  numChoices: 1                                 # REQUIRED - How many options the player picks (usually 1)
  allowDuplicateChoices: false                  # REQUIRED - Can the same option be picked twice
  source: "Fury Class Feature"                  # OPTIONAL - Source label for the feature
  imported: <import-uuid>                       # OPTIONAL - UUID linking to import batch
  guid: <unique-uuid>                           # REQUIRED - Unique identifier for this choice
  options:                                      # REQUIRED - Array of CharacterFeature objects
    - ...
  domains:                                      # OPTIONAL - Domain visibility
    class:<class-uuid>: true
```

### Key notes:
- `numChoices` is always an integer (usually 1)
- `allowDuplicateChoices` is always present and always `false` for class abilities
- `imported` is present when abilities were batch-imported; can be omitted for hand-authored content

---

## 2. CharacterFeature (each ability option)

Each element in the `options` array.

```yaml
- __typeName: CharacterFeature
  name: "Brutal Slam"                          # REQUIRED - Display name
  description: ""                              # REQUIRED - Can be empty string or descriptive text
  classid: <class-uuid>                        # REQUIRED - Parent class UUID
  source: "Fury Class Feature"                 # OPTIONAL - Source label
  importOverride: true                         # OPTIONAL - Present on imported content
  ctime: 1715748063870                         # OPTIONAL - Creation timestamp (epoch ms)
  mtime: 1715748063870                         # OPTIONAL - Modification timestamp (epoch ms)
  imported: <import-uuid>                      # OPTIONAL - Import batch UUID
  implementation: 3                            # REQUIRED - Implementation level (3 = fully implemented)
  guid: <unique-uuid>                          # REQUIRED - Unique identifier
  id: <unique-uuid>                            # REQUIRED - Can differ from guid
  modifiers:                                   # REQUIRED - Array with exactly ONE CharacterModifier
    - ...
  domains:                                     # OPTIONAL
    class:<class-uuid>: true
```

### Key notes:
- `implementation` is always `3` for working abilities
- `guid` and `id` are both present; they CAN be different UUIDs
- `description` at this level is often empty (`""`) -- the real description goes on the ActivatedAbility
- The `modifiers` array contains exactly ONE CharacterModifier with `behavior: activated`

---

## 3. CharacterModifier (the ability container)

Single element inside the CharacterFeature's `modifiers` array.

```yaml
- __typeName: CharacterModifier
  name: "Ability"                              # REQUIRED - Almost always "Ability" (or the ability name)
  description: ""                              # REQUIRED - Usually empty string
  guid: 5031d4be-028d-4e9a-bb4c-8eca657864b3  # REQUIRED - Reuses this WELL-KNOWN UUID across all abilities
  behavior: activated                          # REQUIRED - MUST be "activated"
  sourceguid: f09da83c-5843-497a-8316-d5fdca4349aa  # REQUIRED - WELL-KNOWN UUID for ability source
  source: "Fury Class Feature"                 # OPTIONAL - Source label
  activatedAbility:                            # REQUIRED - The ActivatedAbility object
    ...
  domains:                                     # OPTIONAL
    class:<class-uuid>: true
```

### CRITICAL well-known UUIDs:
These two UUIDs are reused across virtually ALL class ability modifiers:

| Field | UUID | Meaning |
|---|---|---|
| `guid` | `5031d4be-028d-4e9a-bb4c-8eca657864b3` | Standard modifier GUID |
| `sourceguid` | `f09da83c-5843-497a-8316-d5fdca4349aa` | Standard ability source GUID |

### Alternate patterns:
- Some abilities (e.g. Shadow's "Dancer") use custom GUIDs for the modifier
- The `name` field is sometimes "Ability" and sometimes the ability's actual name (e.g. "Dancer")

---

## 4. ActivatedAbility (the core ability)

This is where all the real data lives.

```yaml
activatedAbility:
  __typeName: ActivatedAbility
  name: "Brutal Slam"                          # REQUIRED - Ability display name
  description: ""                              # REQUIRED - Effect text (can be "" if tiers explain everything)
  flavor: "The heavy impact..."                # OPTIONAL - Flavor text shown in ability card
  guid: <unique-uuid>                          # REQUIRED - Unique identifier

  # --- Action Economy ---
  actionResourceId: <action-resource-uuid>     # REQUIRED - What action type it costs
  abilityType: none                            # REQUIRED - Always "none" for class abilities
  resourceCost: <resource-uuid>                # CONDITIONAL - Heroic resource UUID (omit for signature abilities)
  resourceNumber: 3                            # CONDITIONAL - How much heroic resource to spend (omit for signatures)

  # --- Categorization ---
  categorization: "Signature Ability"          # REQUIRED - "Signature Ability" or "Heroic Ability"

  # --- Targeting ---
  targetType: target                           # REQUIRED - See targeting reference below
  numTargets: 1                                # REQUIRED - Number or string formula (e.g. "2 + Charges")
  range: 1                                     # REQUIRED - Range in squares (number or string)
  repeatTargets: false                         # REQUIRED - Always false for standard abilities
  targetAllegiance: enemy                      # OPTIONAL - "enemy" or "ally"; omit for default
  targetFilter: ""                             # OPTIONAL - GoblinScript filter for valid targets
  objectTarget: true                           # OPTIONAL - Can target objects (true/false)
  targetTextOverride: "One creature..."        # OPTIONAL - Custom target line text
  rangeTextOverride: ""                        # OPTIONAL - Custom range text
  meleeRange: 1                                # OPTIONAL - Separate melee range for Melee+Ranged abilities

  # --- Keywords ---
  keywords:                                    # REQUIRED - Map of keyword names to true
    Melee: true
    Strike: true
    Weapon: true

  # --- Display ---
  iconid: <icon-uuid-or-path>                  # REQUIRED - Icon asset reference
  display:                                     # REQUIRED - Visual display settings
    bgcolor: "#ffffffff"                       #   Simple color string format
    saturation: 1
    brightness: 1
    hueshift: 0

  # --- Source Reference ---
  sourceReference:                             # OPTIONAL - Page reference in rulebook
    __typeName: SourceReference
    page: 148
    docid: a623e586-b67d-4563-a5b8-62744d648c31

  # --- Implementation ---
  implementation: 3                            # REQUIRED - Always 3 for working abilities

  # --- Behaviors ---
  behaviors:                                   # REQUIRED - Array of behavior objects (the action chain)
    - ...

  # --- Other ---
  modifiers: []                                # REQUIRED - Usually empty array
  strain: []                                   # REQUIRED - Usually empty array; or {enabled: true} for strain abilities
  persistence: []                              # REQUIRED - Usually empty array

  # --- Channeled Resource (optional) ---
  channeledResource: "2d3d5511-..."            # OPTIONAL - Heroic resource UUID, or "none"
  channelDescription: "Target additional..."   # OPTIONAL - Text explaining the channel spend
  channelIncrement: 2                          # OPTIONAL - How much resource per channel step
  maxChannel: "5"                              # OPTIONAL - Max amount that can be channeled (string/formula)

  # --- Target Filters (optional) ---
  reasonedFilters:                             # OPTIONAL - Array of filter rules with user-facing reason
    - reason: "Target must be your size or smaller"
      formula: "Target.Size <= Caster.Size"

  domains:                                     # OPTIONAL
    class:<class-uuid>: true
```

---

## 5. Action Resource UUIDs

These are the well-known UUIDs for `actionResourceId`:

| UUID | Action Type | Used For |
|---|---|---|
| `d19658a2-4d7b-4504-af9e-1a5410fb17fd` | Main Action | Signature abilities, most heroic abilities |
| `a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b` | Maneuver | Heroic abilities that cost a maneuver |
| `5e551b7d-17fb-4099-a303-bafb3c146f98` | Free Triggered Action | Triggered/free abilities |

The heroic resource cost UUID (for `resourceCost`):

| UUID | Meaning |
|---|---|
| `2d3d5511-4b80-46d1-a8c6-4705b9aa45ca` | Heroic Resource (Rage, Insight, etc.) |

---

## 6. targetType Values

| Value | Meaning |
|---|---|
| `target` | Single creature/object target |
| `self` | Caster only |
| `all` | All creatures in area |
| `emptyspace` | Empty square on the map |
| `anyspace` | Any square |
| `attacker` | The creature that attacked (for triggered abilities) |

---

## 7. categorization Values

| Value | Meaning |
|---|---|
| `Signature Ability` | Free at-will ability (no heroic resource cost) |
| `Heroic Ability` | Costs heroic resource to use |
| `Hidden` | Not shown in ability list (sub-abilities, invoked abilities) |

---

## 8. Behavior Types Reference

### ActivatedAbilityPowerRollBehavior (attack roll + tiered results)

```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "2d10 + Might"                        # REQUIRED - The dice formula (MUST NOT be empty)
  tiers:                                       # REQUIRED - Exactly 3 tiers (array of strings)
    - "3 + M damage; push 1"                  #   Tier 1 (11 or lower)
    - "6 + M damage; push 2"                  #   Tier 2 (12-16)
    - "9 + M damage; push 4"                  #   Tier 3 (17+)
```

**CRITICAL:** The `roll` field MUST be a non-empty string like `"2d10 + Might"` or `"2d10 + Agility"`.
An empty `roll` field will cause runtime errors.

Optional fields on PowerRollBehavior:
- `resistanceRoll: false` -- Whether this is a resistance roll (target rolls instead)
- `attrid: prs` -- Attribute override for resistance rolls (e.g., `prs`, `mgt`, `agl`)
- `applyto: caster` -- Apply the roll results to caster instead of target

### ActivatedAbilityApplyOngoingEffectBehavior

```yaml
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  ongoingEffect: <effect-uuid>                 # REQUIRED - UUID of the ongoing effect
  ongoingEffectCustom: <effect-uuid-or-false>  # OPTIONAL - Custom effect UUID, or "false"
  duration: eoe                                # OPTIONAL - "eoe" (end of encounter), "eoe_or_dying"
  applyto: caster                              # OPTIONAL - "caster" to apply to self
  filterTarget: "not leader and not solo"      # OPTIONAL - GoblinScript filter
```

### ActivatedAbilityInvokeAbilityBehavior

```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  abilityType: standard                        # REQUIRED - "standard" (built-in) or "custom"
  standardAbility: <ability-uuid>              # CONDITIONAL - UUID of standard ability (when abilityType=standard)
  standardAbilityParams:                       # OPTIONAL - Parameters passed to the standard ability
    distance: "1"
    targetid: "<<Cast.Primary Target.id>>"
  promptText: "Make a free strike..."          # OPTIONAL - Text shown to the player
  autoTarget: false                            # OPTIONAL - Auto-select target
  applyto: caster                              # OPTIONAL - Who the invoked ability targets
  target_proximity_range: "5"                  # OPTIONAL - Range for target selection
  filterTarget: ""                             # OPTIONAL - Filter for valid targets
  customAbility:                               # REQUIRED - Nested ActivatedAbility (even for standard)
    __typeName: ActivatedAbility
    description: ""
    guid: <unique-uuid>
    name: "Invoked Ability"
    modifiers: []
    targetType: self
    numTargets: "1"
    iconid: ui-icons/skills/1.png
    repeatTargets: false
    range: 1
    behaviors: []
    display:
      bgcolor: "#ffffffff"
      saturation: 1
      brightness: 1
      hueshift: 0
    abilityType: none
```

**NOTE:** The `customAbility` block is ALWAYS present, even when `abilityType: standard`.
When `abilityType: standard`, the `customAbility` is a minimal stub.
When `abilityType: custom`, the `customAbility` contains the full sub-ability with its own behaviors.

### ActivatedAbilityReplenishBehavior (grant surges/resources)

```yaml
- __typeName: ActivatedAbilityReplenishBehavior
  quantity: "2"                                # REQUIRED - How many to grant (string)
  resourceid: 8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d  # OPTIONAL - Resource UUID (surges by default)
  chatMessage: "To the Death!"                 # OPTIONAL - Chat message when triggered
  applyto: caster                              # OPTIONAL - Who receives the resource
  filterTarget: "not leader and not solo"      # OPTIONAL - GoblinScript filter
```

### ActivatedAbilityDrawSteelCommandBehavior (apply conditions/effects via rule string)

```yaml
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  rule: "Taunted (EoT)"                       # REQUIRED - Rule string to execute
  applyto: proximity_only                      # OPTIONAL - Targeting override
  filterTarget: "not Friends(Target, Caster)"  # OPTIONAL - GoblinScript filter
```

### ActivatedAbilityGrantTemporaryStaminaBehavior

```yaml
- __typeName: ActivatedAbilityGrantTemporaryStaminaBehavior
  stamina: "20"                                # REQUIRED - Amount (string formula)
  applyto: caster                              # OPTIONAL - Who receives the temp stamina
```

### ActivatedAbilityModifyPowerRollBehavior (conditional roll modifiers)

```yaml
- __typeName: ActivatedAbilityModifyPowerRollBehavior
  modifier:                                    # REQUIRED - CharacterModifier with power roll mod details
    __typeName: CharacterModifier
    description: "..."
    guid: <unique-uuid>
    name: "Modifier Name"
    activationCondition: "target.CountNearbyEnemies(1, caster)"
    keywords: []
    rollType: ability_power_roll
    behavior: power
    modtype: none
    sourceguid: <unique-uuid>
    surges: "1"                                # OPTIONAL - Surges granted
    surgesCanBeKept: true                      # OPTIONAL
    damageModifier: "charges d6"               # OPTIONAL - Extra damage formula
    filterCondition: "Winded and not Dying"    # OPTIONAL - When this modifier applies
    resourceCostType: multicost                # OPTIONAL - For channeled resource costs
    hasCustomTrigger: true                     # OPTIONAL - Whether a custom trigger exists
    customTrigger: ...                         # OPTIONAL - Nested TriggeredAbility
    displayCondition: "1"                      # OPTIONAL
    domains: []
  guid: <unique-uuid>
```

### ActivatedAbilityDamageBehavior (flat damage, usually self-damage)

```yaml
- __typeName: ActivatedAbilityDamageBehavior
  roll: "1d6"                                  # REQUIRED - Damage formula
  titleText: "Blood for Blood: damage to self" # OPTIONAL - Chat message title
```

### ActivatedAbilityDelayBehavior (timing marker)

```yaml
- __typeName: ActivatedAbilityDelayBehavior    # No fields -- just a marker in the behavior chain
```

### ActivatedAbilityConditionSourceBehavior (apply a condition)

```yaml
- __typeName: ActivatedAbilityConditionSourceBehavior
  condid: <condition-uuid>                     # REQUIRED - UUID of the condition to apply
```

### ActivatedAbilityRelocateCreatureBehavior (move a creature)

```yaml
- __typeName: ActivatedAbilityRelocateCreatureBehavior
  movementType: move                           # REQUIRED - "move", "teleport", "shift", etc.
```

### ActivatedAbilityPurgeEffectsBehavior

```yaml
- __typeName: ActivatedAbilityPurgeEffectsBehavior
  purgeType: chosen                            # REQUIRED - "chosen" or other purge modes
```

---

## 9. Complete Examples

### Signature Ability (no resource cost, with power roll)

"Brutal Slam" from Fury -- a basic melee strike with tiered damage:

```yaml
- __typeName: CharacterFeatureChoice
  name: "Signature Ability"
  description: "Choose one signature ability from the following options."
  classid: ce18b1ba-363b-4403-945b-34a3ce08a465
  numChoices: 1
  allowDuplicateChoices: false
  source: "Fury Class Feature"
  guid: ba76011e-4a58-4304-bf74-408fc14868c6
  options:
    - __typeName: CharacterFeature
      name: "Brutal Slam"
      description: ""
      classid: ce18b1ba-363b-4403-945b-34a3ce08a465
      source: "Fury Class Feature"
      ctime: 1715748063870
      mtime: 1715748063870
      implementation: 3
      guid: b08dde4a-a760-404d-b293-ec4a04e83b97
      id: 7c88034b-ba7d-4e90-884b-96c18c3ec580
      modifiers:
        - __typeName: CharacterModifier
          name: "Ability"
          description: ""
          guid: 5031d4be-028d-4e9a-bb4c-8eca657864b3
          behavior: activated
          sourceguid: f09da83c-5843-497a-8316-d5fdca4349aa
          source: "Fury Class Feature"
          activatedAbility:
            __typeName: ActivatedAbility
            name: "Brutal Slam"
            description: ""
            guid: 834ef027-a400-4538-b87c-04a850a99a11
            actionResourceId: d19658a2-4d7b-4504-af9e-1a5410fb17fd
            abilityType: none
            categorization: Signature Ability
            # NOTE: No resourceCost or resourceNumber for signatures
            targetType: target
            numTargets: 1
            range: 1
            repeatTargets: false
            objectTarget: true
            keywords:
              Melee: true
              Strike: true
              Weapon: true
            iconid: 516f1bc6-09d4-4107-9ddb-0940f7d51a81
            flavor: "The heavy impact of your weapon attacks drives your foes ever backward."
            display:
              bgcolor: "#ffffffff"
              saturation: 1
              brightness: 1
              hueshift: 0
            implementation: 3
            modifiers: []
            strain: []
            persistence: []
            behaviors:
              - __typeName: ActivatedAbilityPowerRollBehavior
                roll: "2d10 + Might"
                tiers:
                  - "3 + M damage; push 1"
                  - "6 + M damage; push 2"
                  - "9 + M damage; push 4"
            sourceReference:
              __typeName: SourceReference
              page: 148
              docid: a623e586-b67d-4563-a5b8-62744d648c31
            domains:
              class:ce18b1ba-363b-4403-945b-34a3ce08a465: true
          domains:
            class:ce18b1ba-363b-4403-945b-34a3ce08a465: true
      domains:
        class:ce18b1ba-363b-4403-945b-34a3ce08a465: true
```

### Heroic Ability (costs heroic resource, with power roll)

"Back!" from Fury -- costs 3 Rage, area attack:

```yaml
- __typeName: CharacterFeature
  name: "Back!"
  description: "You hew about you with your mighty weapon, hurling enemies backward."
  classid: ce18b1ba-363b-4403-945b-34a3ce08a465
  source: "Fury Class Feature"
  importOverride: true
  ctime: 1715748063870
  mtime: 1715748063870
  implementation: 3
  guid: 91f1c291-1857-4632-bef5-66112d599a06
  id: 2461fef8-194e-4d44-8112-8240495e3782
  modifiers:
    - __typeName: CharacterModifier
      name: "Ability"
      description: "You hew about you with your mighty weapon, hurling enemies backward."
      guid: 5031d4be-028d-4e9a-bb4c-8eca657864b3
      behavior: activated
      sourceguid: f09da83c-5843-497a-8316-d5fdca4349aa
      source: "Fury Class Feature"
      activatedAbility:
        __typeName: ActivatedAbility
        name: "Back!"
        description: ""
        guid: f427bc74-979f-47d6-9042-978f800aae98
        actionResourceId: d19658a2-4d7b-4504-af9e-1a5410fb17fd
        abilityType: none
        resourceCost: 2d3d5511-4b80-46d1-a8c6-4705b9aa45ca    # Heroic resource
        resourceNumber: 3                                       # Costs 3 Rage
        categorization: Heroic Ability
        targetType: all                                         # Area effect
        targetAllegiance: enemy                                 # Enemies only
        numTargets: 1
        range: 1
        repeatTargets: false
        objectTarget: false
        targetFilter: ""
        targetTextOverride: "Each enemy in the area"
        keywords:
          Melee: true
          Area: true
          Weapon: true
        iconid: 69765e23-5ca6-4acd-ba46-6e0aa125c6af
        flavor: "You hew about you with your mighty weapon, hurling enemies backward"
        display:
          bgcolor: "#ffffffff"
          saturation: 1
          brightness: 1
          hueshift: 0
        implementation: 3
        modifiers: []
        strain: []
        persistence: []
        behaviors:
          - __typeName: ActivatedAbilityPowerRollBehavior
            roll: "2d10 + Might"
            tiers:
              - "5 damage"
              - "8 damage; push 1"
              - "11 damage; push 3"
        sourceReference:
          __typeName: SourceReference
          page: 148
          docid: a623e586-b67d-4563-a5b8-62744d648c31
        domains:
          class:ce18b1ba-363b-4403-945b-34a3ce08a465: true
      domains:
        class:ce18b1ba-363b-4403-945b-34a3ce08a465: true
  domains:
    class:ce18b1ba-363b-4403-945b-34a3ce08a465: true
```

### Heroic Ability (no power roll, self-targeting effect)

"Demon Unleashed" from Fury -- costs 7 Rage, applies ongoing effect to self:

```yaml
activatedAbility:
  __typeName: ActivatedAbility
  name: "Demon Unleashed"
  description: "Until the end of the encounter..."
  guid: d71e4e17-e5ab-492a-bbf5-28c2e59aa060
  actionResourceId: a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b   # Maneuver (not Main Action)
  abilityType: none
  resourceCost: 2d3d5511-4b80-46d1-a8c6-4705b9aa45ca
  resourceNumber: 7
  categorization: Heroic Ability
  targetType: self
  numTargets: "1"
  range: 1
  repeatTargets: false
  targetTextOverride: "Self"
  keywords:
    Magic: true
  behaviors:
    - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
      duration: eoe_or_dying
      ongoingEffect: 482fe897-fd9d-440c-9368-baadd30d7de3
      ongoingEffectCustom: 482fe897-fd9d-440c-9368-baadd30d7de3
  # ... standard fields ...
```

### Channeled Resource Ability

"Artful Flourish" from Troubadour -- signature with optional drama spending:

```yaml
activatedAbility:
  __typeName: ActivatedAbility
  name: "Artful Flourish"
  # ... standard fields ...
  categorization: Signature Ability
  numTargets: "2 + Charges"                    # Formula using Charges (= channeled amount)
  channeledResource: 2d3d5511-4b80-46d1-a8c6-4705b9aa45ca  # Heroic resource UUID
  channelDescription: "Target additional creatures"
  channelIncrement: 2                          # Costs 2 drama per extra target
  # maxChannel not present = unlimited
```

"To the Uttermost End" from Fury -- channeled with conditional activation:

```yaml
activatedAbility:
  __typeName: ActivatedAbility
  name: "To the Uttermost End"
  # ... standard fields ...
  channeledResource: none                      # "none" = uses a custom channeling system
  channelDescription: ""
  maxChannel: "100 when winded else 0"         # GoblinScript formula for max channel
```

---

## 10. Common Bugs to Avoid

### Empty `roll` field on PowerRollBehavior
**WRONG:**
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: ""           # BUG: Will cause runtime crash
  tiers: [...]
```
**RIGHT:**
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "2d10 + Might"
  tiers: [...]
```

### Missing `tiers` on PowerRollBehavior
**WRONG:**
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "2d10 + Might"
  # BUG: Missing tiers array
```
**RIGHT:** Always provide exactly 3 tier strings.

### Wrong `__typeName` on feature
**WRONG:**
```yaml
- __typeName: CharacterModifier    # BUG: Should be CharacterFeature
  name: "Brutal Slam"
```

### Missing `behavior: activated` on the modifier
**WRONG:**
```yaml
- __typeName: CharacterModifier
  name: "Ability"
  # BUG: Missing behavior field
  activatedAbility: ...
```

### `resourceCost` on signature abilities
Signature abilities should NOT have `resourceCost` or `resourceNumber`. These fields
are only for Heroic Abilities.

### `numTargets` type inconsistency
`numTargets` can be either a bare integer (`1`) or a quoted string (`"1"` or `"2 + Charges"`).
Both work, but formulas MUST be strings.

### Missing `modifiers: []` on ActivatedAbility
The `modifiers` field on the ActivatedAbility itself (not the CharacterModifier wrapper)
must be present and is almost always `[]`.

### Missing `strain: []`
Must be present. Use `[]` for abilities without strain. Use `enabled: true` for abilities
that cost strain (stamina).

### Missing `persistence: []`
Must be present. Almost always `[]`.

---

## 11. display.bgcolor Formats

Two formats exist in production data:

**Simple string (most common):**
```yaml
display:
  bgcolor: "#ffffffff"
  saturation: 1
  brightness: 1
  hueshift: 0
```

**LuaColor object (for colored ability cards):**
```yaml
display:
  bgcolor:
    __usertype: LuaColor
    h: 0.0510204024612904
    s: 0.604938268661499
    v: 0.317647069692612
    a: 1
  saturation: 1
  brightness: 1
  hueshift: 0
```

Use `"#ffffffff"` (white/default) unless you specifically want a colored ability card.

---

## 12. Signature vs Heroic Quick Comparison

| Field | Signature | Heroic |
|---|---|---|
| `categorization` | `Signature Ability` | `Heroic Ability` |
| `actionResourceId` | Main Action UUID | Main Action or Maneuver UUID |
| `resourceCost` | OMITTED | Heroic resource UUID |
| `resourceNumber` | OMITTED | Integer (3, 5, 7) |
| Power roll | Usually yes | Sometimes (effect abilities may not have one) |
