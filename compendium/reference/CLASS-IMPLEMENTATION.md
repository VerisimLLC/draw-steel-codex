# Class Implementation Reference

How heroic resources, level progression, and class features are implemented in DMHub.

## Heroic Resource Implementation

### Class-Level Fields

```yaml
heroicResourceName: "Thirst"        # Display name
heroicResourceChecklist:             # UI display + trigger linkage
  - guid: <uuid>                     # Links to ReplenishBehavior.checklistid
    name: "Start of Combat"          # Short label
    details: "Description text"      # Tooltip
    quantity: "Victories"            # Amount (string, GoblinScript, or GoblinScriptTable)
    mode: encounter                  # Optional: "round" (1/round), "encounter" (1/encounter)
```

### Three Required Modifiers

Every heroic resource needs these three modifiers in a CharacterFeature:

**1. Resource Declaration:**
```yaml
- __typeName: CharacterModifier
  behavior: resource
  resourceType: "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"  # ALWAYS this UUID
  num: 0
  name: "Thirst"
  source: "Vampire Class Feature"
```

**2. Gain-at-Start Attribute** (die size for per-turn roll):
```yaml
- __typeName: CharacterModifier
  behavior: attribute
  attribute: "4d6eb7b5-85d1-41c0-a462-05cff692749a"  # "Heroic Resource Gain at Start"
  value: 3                                              # d3 = 3, d6 = 6, etc.
  name: "Thirst"
  source: "Vampire Class Feature"
```

**3. Trigger Modifiers** (one per gain event):

### Trigger Patterns

**Start of Combat** (gain = Victories):
```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: rollinitiative
    mandatory: "game:heroicresourcetriggers"
    targetType: self
    conditionFormula: "Victories > 0"
    triggerPrompt: "Gain Thirst equal to Victories."
    behaviors:
      - __typeName: ActivatedAbilityReplenishBehavior
        checklistid: <matching-checklist-guid>
        chatMessage: "Draw Steel"
        resourceid: "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"
        quantity: "Victories"
        applyto: caster
```

**Start of Turn** (gain = 1dN, level-scaling):
```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: beginturn
    whenActive: combat
    mandatory: "game:heroicresourcetriggers"
    targetType: self
    conditionFormula: "Heroic Resource Gain at Start > 0"
    behaviors:
      - __typeName: ActivatedAbilityReplenishBehavior
        checklistid: <matching-checklist-guid>
        chatMessage: "Start of Turn"
        resourceid: "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"
        quantity:
          __typeName: GoblinScriptTable
          editableField: true
          entries:
            - threshold: 1
              script: "1d Heroic Resource Gain at Start"
            - threshold: 7
              script: "(1d Heroic Resource Gain at Start) + 1"
          field: Level
          id: table
        applyto: caster
```

**Once-per-round conditional** (e.g., on damage/condition):
```yaml
- __typeName: CharacterModifier
  behavior: trigger
  resourceRefreshType: round           # MUST match usageLimitOptions
  resourceCostId: <own-modifier-guid>  # Points to self for charge tracking
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: dealdamage                # or inflictcondition, losehitpoints, etc.
    whenActive: combat
    mandatory: "game:heroicresourcetriggers"
    targetType: self
    conditionFormula: "Target.Winded or Target.Conditions has \"Bleeding\""
    usageLimitOptions:
      resourceid: <own-modifier-guid>
      charges: "1"
      resourceRefreshType: round
    behaviors:
      - __typeName: ActivatedAbilityReplenishBehavior
        checklistid: <matching-checklist-guid>
        quantity: "1"
        resourceid: "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"
        applyto: caster
```

**Condition Applied** (trigger: inflictcondition):
Available symbols: `Condition` (name string), `Attacker`, `Has Attacker`.
```yaml
trigger: inflictcondition
conditionFormula: 'Condition is Bleeding'
subject: any                         # Fires when ANY creature gets the condition
subjectRange: "10"                   # Within 10 squares
```

### Key UUIDs

| UUID | Purpose |
|------|---------|
| `2d3d5511-4b80-46d1-a8c6-4705b9aa45ca` | Heroic Resource type (ALL classes) |
| `4d6eb7b5-85d1-41c0-a462-05cff692749a` | "Heroic Resource Gain at Start" attribute |
| `5bd90f9b-46be-4cf2-8ca6-a96430d62949` | Recovery resource type |

### GoblinScript Symbols

| Symbol | Type | Description |
|--------|------|-------------|
| `Heroic Resources Available to Spend` | Number | Current resource count |
| `Heroic Resources This Turn` | Number | High-water mark this turn |
| `Heroic Resource Gain at Start` | Number | Die size for per-turn roll |
| `Victories` | Number | Current victories |

### Growing Resources (Insatiable Thirst Pattern)

For benefit/drawback tables keyed to resource thresholds, use `behavior: growingresources`:
```yaml
- __typeName: CharacterModifier
  behavior: growingresources
  progression:
    - level: 0
      resources: 2
      description: "+Presence to speed and disengage."
      tooltip: "Full description..."
    - level: 0
      resources: 4
      description: "Gain 1 surge on damage to bleeding/winded/dying."
    - level: 4
      resources: 8
      description: "Might and Agility +1 for resisting potencies."
```
The `level` field gates by character level. `resources` is the threshold.
This drives the UI display. The actual mechanical effects need separate modifiers
with `filterCondition: "Heroic Resources This Turn >= 2"` etc.

## Variable Resource Spending (channeledResource)

For abilities where the player chooses how much heroic resource to spend:

```yaml
channeledResource: "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca"  # Heroic resource UUID
channelIncrement: 1                    # Cost per charge (1 = spend 1 at a time)
channelDescription: "Spend Thirst for enhanced effects"
maxChannel: "Heroic Resources Available to Spend"  # Max spendable
```

Behaviors can reference `Charges` to scale effects:
```yaml
behaviors:
  - __typeName: ActivatedAbilityDamageBehavior
    roll: "Level + 2 + Charges * 2"    # Scales with Thirst spent
    cannotBeReduced: true               # Damage bypasses immunities
```

Conditional effects at thresholds:
```yaml
  - __typeName: ActivatedAbilityDrawSteelCommandBehavior
    filterTarget: "Charges + Target.ConditionCount >= 3"
    rule: "N8 weakened (save ends)"
```

## Unreducible Damage (cannotBeReduced)

Set `cannotBeReduced: true` on `ActivatedAbilityDamageBehavior` to bypass
numeric damage immunities. Used by Bleeding condition, Bloodbound, and Drink Most Exquisite.

```yaml
- __typeName: ActivatedAbilityDamageBehavior
  cannotBeReduced: true
  roll: "Level + 2"
  damageType: corruption
```

### Insatiable Thirst Benefits/Drawbacks Pattern

Each benefit/drawback is a separate CharacterModifier with filterCondition:
```yaml
# Thirst 2+ benefit: speed bonus
- __typeName: CharacterModifier
  behavior: attribute
  attribute: speed
  value: "Presence"
  filterCondition: "Heroic Resources This Turn >= 2"
  name: "Insatiable Thirst: Speed"
```

For the drawback suppression mechanic, create a custom ongoing effect
"Drawbacks Suppressed" and check `not (Ongoing Effects has "Drawbacks Suppressed")`
in each drawback modifier's filterCondition.
