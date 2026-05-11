# Deal Damage Trigger Pattern

## When to Use

Use this pattern when a monster has an ability or trait that says something like:
- "This ability gains an edge against targets the creature has previously dealt X damage to"
- "Whenever this creature deals X damage, apply Y effect to the target"
- "After dealing X damage, the target is marked/poisoned/etc."

The key insight: instead of adding `ApplyOngoingEffectBehavior` to each individual ability,
use a **trait with a `dealdamage` trigger** on the monster. This catches ALL sources of
that damage type -- including free strikes, which the engine auto-generates from the
signature ability.

## The Trigger

The `dealdamage` trigger fires on the creature that DEALS damage. It provides these
GoblinScript symbols:

| Symbol | Type | Description |
|--------|------|-------------|
| Damage | number | Amount of damage dealt |
| Damage Type | set | Damage type(s) dealt (e.g., "Poison", "Fire") |
| Keywords | set | Ability keywords |
| Target | creature | The creature that was damaged |
| Surges | number | Number of surges on the roll |
| Edges | number | Number of edges |
| Banes | number | Number of banes |
| HasAbility | boolean | Whether damage came from an ability |
| Ability / Used Ability | ability | The ability that dealt damage |

## YAML Pattern

### Step 1: Create a Marker Ongoing Effect

A simple ongoing effect with no modifiers -- just a flag on the target.

```yaml
# File: compendium/import/my-marker.yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: <marker-uuid>
guid: <marker-uuid>
name: My Marker
iconid: bc90bb09-9e3c-46d4-bf16-0e5c0134dbf8
source: Ongoing Effect
custom: true
description: "Description visible to players."
modifiers: []
display:
  saturation: 1
  bgcolor: "#ffffffff"
  brightness: 1
  hueshift: 0
association: []
```

### Step 2: Add a Trait to the Monster

Add a `CharacterFeature` with a `dealdamage` trigger that applies the marker.

```yaml
- __typeName: CharacterFeature
  source: Trait
  name: Venomous
  guid: <feature-uuid>
  domains:
    CharacterFeature:<feature-uuid>: true
  description: "Whenever the creature deals poison damage, the target is marked."
  modifiers:
  - __typeName: CharacterModifier
    behavior: trigger
    name: Venomous
    guid: <modifier-uuid>
    sourceguid: <feature-uuid>
    source: Trait
    domains:
      CharacterFeature:<feature-uuid>: true
    triggeredAbility:
      __typeName: TriggeredAbility
      name: Apply Marker
      guid: <ability-uuid>
      trigger: dealdamage
      conditionFormula: 'Damage Type has "Poison"'   # Filter by damage type
      targetType: target          # Apply to the damaged creature
      mandatory: true             # Auto-fire, no prompt
      castImmediately: true       # Don't wait for user confirmation
      whenActive: combat
      abilityType: none
      range: 1
      numTargets: '1'
      repeatTargets: false
      description: ''
      behaviors:
      - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
        ongoingEffect: <marker-uuid>    # References the ongoing effect
        duration: eoe                    # End of encounter
      display:
        bgcolor: '#ffffffff'
        saturation: 1
        brightness: 1
        hueshift: 0
      iconid: ui-icons/skills/1.png
  implementation: 3
```

### Step 3: Add an Edge Modifier to the Ability

On the specific ability that benefits from the marker, add a `ModifyPowerRollBehavior`
that checks for the marker on the target.

```yaml
- __typeName: ActivatedAbilityModifyPowerRollBehavior
  modifier:
    __typeName: CharacterModifier
    damageModifier: '0'           # Or omit -- just granting an edge
    name: Edge vs Marked
    domains: []
    modtype: edge
    rollType: ability_power_roll
    guid: <modifier-uuid>
    sourceguid: <behavior-uuid>
    behavior: power
    keywords: []
    activationCondition: 'Target.Ongoing Effects has "My Marker"'
  guid: <behavior-uuid>
```

## Key Fields on the Trigger

| Field | Value | Purpose |
|-------|-------|---------|
| `trigger` | `dealdamage` | Fires when this creature deals damage |
| `conditionFormula` | GoblinScript filter | e.g., `Damage Type has "Poison"` |
| `targetType` | `target` | Apply behaviors to the creature that was damaged |
| `mandatory` | `true` | Auto-fires without prompting |
| `castImmediately` | `true` | Resolves instantly without UI delay |

## Common conditionFormula Filters

| Filter | Meaning |
|--------|---------|
| `Damage Type has "Poison"` | Only when dealing poison damage |
| `Damage Type has "Fire"` | Only when dealing fire damage |
| `HasAbility and Ability.Keywords has "Strike"` | Only on strikes |
| `Surges >= 1` | Only when the roll had at least one surge |
| `Target.Conditions has "Bleeding"` | Only vs bleeding targets |

## Real Examples

### Basilisk -- "Venomous" Trait
- **Trigger:** `dealdamage` with `Damage Type has "Poison"`
- **Effect:** Applies "Basilisk Venom" marker to target (eoe)
- **Benefit:** Noxious Bite gets an edge vs marked targets via `ModifyPowerRollBehavior`
- **Why trait instead of per-ability:** Catches free strikes too

### Conduit -- "Thunderstruck" Class Feature
- **Trigger:** `dealdamage` with `Damage Type has "Sonic" or Damage Type has "Lightning"`
- **Effect:** Grants 1 surge to self
- **File:** `compendium/tables/classes/conduit.yaml`

### Wolf -- "Blood Frenzy" Trait
- **Trigger:** `dealdamage` with `Target.Conditions has "Bleeding"`
- **Effect:** Grants a surge to self
- **File:** `compendium/import/wolf.yaml`

## Why Not Per-Ability ApplyOngoingEffectBehavior?

Adding `ApplyOngoingEffectBehavior` directly to each ability works, but misses:
- **Free strikes** -- auto-generated by the engine from the signature ability
- **Future abilities** -- if the monster gets new poison abilities, they auto-apply the marker
- **Triggered attacks** -- opportunity attacks, reaction abilities, etc.

The trait-based trigger approach is more robust and requires less maintenance.
