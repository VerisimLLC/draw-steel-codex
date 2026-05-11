# Opportunity Attack Filter Pattern

## When to Use

Use this pattern when a creature should be immune to opportunity attacks from specific
creatures, not from all creatures. Common rules text:

- "This creature doesn't provoke opportunity attacks from that creature this turn"
- "The target can't make opportunity attacks against the [monster] until..."
- "Enemies damaged by this creature can't make opportunity attacks against it"

If the creature should be immune to ALL opportunity attacks (like the Goblin "Crafty"
trait), just use the `Immunity from Opportunity Attack` custom attribute
(`e2773895-411c-404e-a7f4-1aa50cd87710`) directly. This pattern is for per-target scoping.

## How It Works

The engine checks `creature:TargetPassesFilter("opportunityattack", movingCreature)`
before allowing an opportunity attack. A `behavior: filter` modifier with
`filterid: "opportunityattack"` can intercept this check. The filter is a GoblinScript
expression where:

- **Self** = the creature that would make the OA (the potential attacker)
- **Target** = the creature that is moving (the one that would be attacked)

If the filter returns **false**, the OA is blocked.

## YAML Pattern

### Step 1: Create the Ongoing Effect

This goes on the creature that should NOT be able to make OAs against a specific target.
It uses `casterTracking: one` so the engine remembers who applied it.

```yaml
# File: compendium/import/my-oa-filter.yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: <uuid>
guid: <uuid>
name: My OA Filter
iconid: bc90bb09-9e3c-46d4-bf16-0e5c0134dbf8
source: Ongoing Effect
custom: true
casterTracking: one                   # KEY: tracks who applied this effect
hiddenOnToken: true                   # Don't clutter the token display
description: "This creature cannot make opportunity attacks against the creature that applied this effect."
modifiers:
- __typeName: CharacterModifier
  guid: <modifier-uuid>
  filter: 'Target != ConditionCaster("My OA Filter")'   # Block OAs against caster
  source: Ongoing Effect
  behavior: filter                    # KEY: filter behavior type
  filterid: opportunityattack         # KEY: intercepts OA checks
  description: "Cannot make opportunity attacks against the effect caster."
  domains:
    CharacterOngoingEffect:<effect-uuid>: true
  name: My OA Filter
  sourceguid: <effect-uuid>
display:
  saturation: 1
  bgcolor: '#ffffffff'
  brightness: 1
  hueshift: 0
association: []
```

### Step 2: Apply the Effect via a Trigger

Add a trait on the monster with a `dealdamage` trigger that applies the effect to the
**target** (the damaged creature -- the one whose OAs should be blocked).

```yaml
- __typeName: CharacterFeature
  source: Trait
  name: Agile Predator
  guid: <feature-uuid>
  domains:
    CharacterFeature:<feature-uuid>: true
  description: "When this creature deals damage, the target can't make OAs against it."
  modifiers:
  - __typeName: CharacterModifier
    behavior: trigger
    name: Agile Predator
    guid: <modifier-uuid>
    sourceguid: <feature-uuid>
    source: Trait
    domains:
      CharacterFeature:<feature-uuid>: true
    triggeredAbility:
      __typeName: TriggeredAbility
      name: Apply OA Filter
      guid: <ability-uuid>
      trigger: dealdamage
      targetType: target              # Apply to the damaged creature
      mandatory: true
      castImmediately: true
      whenActive: combat
      abilityType: none
      range: 1
      numTargets: '1'
      repeatTargets: false
      description: ''
      behaviors:
      - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
        ongoingEffect: <effect-uuid>  # The OA filter effect
        duration: 0
        durationUntilEndOfTurn: true  # Lasts until end of this turn
      display:
        bgcolor: '#ffffffff'
        saturation: 1
        brightness: 1
        hueshift: 0
      iconid: ui-icons/skills/1.png
```

## Key Fields

| Field | Value | Purpose |
|-------|-------|---------|
| `behavior` | `filter` | Modifier type that intercepts target-pass checks |
| `filterid` | `opportunityattack` | Specifically intercepts OA checks |
| `filter` | GoblinScript | Expression evaluated to allow/block the OA |
| `casterTracking` | `one` | On the ongoing effect -- tracks who applied it |
| `ConditionCaster("Name")` | GoblinScript function | Returns the creature that applied the named effect |

## Filter Expression

The filter runs on the **potential OA-maker** (Self) with the **moving creature** as Target.

| Expression | Meaning |
|-----------|---------|
| `Target != ConditionCaster("Effect")` | Block OAs only against the creature that applied this effect |
| `not (Target.Keywords has "Beast")` | Block OAs against all Beasts |
| `0` | Block all OAs from this creature (equivalent to "Cannot Make OA" attribute) |

## How the Flow Works (Example: Manticore)

1. Manticore deals damage to the Fury
2. `dealdamage` trigger fires, applies "Agile Predator" effect to the Fury
3. `casterTracking: one` records the Manticore as the caster
4. Manticore moves away from the Fury
5. Engine checks: `fury.TargetPassesFilter("opportunityattack", manticore)`
6. Filter evaluates: `Target != ConditionCaster("Agile Predator")`
7. Target (Manticore) IS the ConditionCaster -> expression is false -> OA blocked
8. Manticore moves away from the Shadow (no effect on Shadow) -> OA allowed

## Real Examples

### Manticore -- "Agile Predator"
- **Rules:** "Whenever the manticore deals damage to a creature, they don't provoke
  opportunity attacks from that creature during that turn."
- **Effect:** `agile-predator.yaml` with `filter: 'Target != ConditionCaster("Agile Predator")'`
- **Trigger:** `dealdamage` on the manticore, applies to target, duration until end of turn

### Existing Engine Effect -- "Ignore Opportunity Attacks against Attacker"
- **File:** `compendium/tables/characterongoingeffects/ignore-opportunity-attacks-against-attacker.yaml`
- **Same pattern** but with a hardcoded creature name in the filter

## Related: Blanket OA Immunity

If a creature should be immune to ALL opportunity attacks (not per-target), use the
simpler approach:

```yaml
# As a trait modifier:
- __typeName: CharacterModifier
  attribute: e2773895-411c-404e-a7f4-1aa50cd87710    # Immunity from Opportunity Attack
  behavior: attribute
  value: 1
```

This is used by the Goblin "Crafty" trait and similar permanent OA immunities.
