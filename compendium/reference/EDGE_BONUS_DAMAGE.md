# Edge Bonus Damage Pattern

## When to Use

Many monster abilities have an **Effect** line like:

> "This strike deals an extra N damage if it gains an edge or has a double edge."

This is implemented using `ActivatedAbilityModifyPowerRollBehavior` with `rollRequirement: edge`.

## YAML Pattern

Add this behavior after the `ActivatedAbilityPowerRollBehavior`:

```yaml
- __typeName: ActivatedAbilityModifyPowerRollBehavior
  modifier:
    __typeName: CharacterModifier
    damageModifier: '3'              # The bonus damage amount
    name: Bonus Edge Damage
    domains: []
    description: This strike deals an extra 3 damage if it gains an edge or has a double edge.
    modtype: none
    rollType: ability_power_roll
    guid: <unique-uuid>              # Fresh UUID for the modifier
    sourceguid: <behavior-guid>      # Must match the behavior's guid below
    behavior: power
    rollRequirement: edge            # KEY: only applies when roll has an edge
    keywords: []
    activationCondition: true
  guid: <behavior-guid>              # Must match sourceguid above
```

## Key Fields

| Field | Value | Purpose |
|-------|-------|---------|
| `rollRequirement` | `edge` | Only applies the modifier when the power roll has an edge or double edge |
| `damageModifier` | GoblinScript string | The bonus damage amount (e.g., `'3'`, `'2'`) |
| `modtype` | `none` | No edge/bane modification -- just damage |
| `rollType` | `ability_power_roll` | Applies to the ability's own power roll |
| `activationCondition` | `true` | Always eligible (the `rollRequirement` handles the conditional) |

## Monsters Using This Pattern

| Monster | Ability | Bonus |
|---------|---------|-------|
| Goblin Assassin | Sword Stab | +2 |
| Human Scoundrel | Dagger Dance | +2 |
| Chimera | Bite | +3 |
| Lightbender | Flash Swipe | +4 |
| Orc Garroter | Garrote | +4 |

## How to Find Candidates

Search `monster-reference.md` for abilities with effect text mentioning edge + extra damage:

```
grep -i "extra.*damage.*edge\|additional.*damage.*edge" monster-reference.md
```

Then check whether the corresponding import YAML has `rollRequirement: edge`. If not, add
the `ActivatedAbilityModifyPowerRollBehavior` block above with the correct damage amount,
and set `implementation: 3` on the ability.
