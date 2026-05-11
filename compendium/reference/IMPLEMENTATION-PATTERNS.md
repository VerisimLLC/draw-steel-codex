# Implementation Patterns Reference

Quick-lookup reference for reusable YAML implementation patterns.
Each pattern: description, key fields, real example, when to use.

---

## Ability Chaining

### Shift+Attack Sequence
Chain multiple InvokeAbilityBehavior entries to build multi-step villain actions.
```yaml
behaviors:
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  abilityType: standard
  standardAbility: 14c386b6-...  # Shift
  standardAbilityParams: { distance: "<<Movement Speed>>" }
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  abilityType: named
  namedAbility: Agonizing Harmony
# repeat as needed
```
**Example:** Demon Chorogaunt "Running Cacophony", Orc Warleader "I'll Do This Myself"
**When:** Any multi-attack villain action with movement between strikes.

### Named Ability Invocation
Reference a creature's own ability by name instead of embedding it inline.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  abilityType: named
  namedAbility: Black Ash Teleport
  invokeOnCaster: true
```
**Example:** Shadow "Trail of Cinders" (trigger on kill -> teleport)
**When:** Triggered abilities that invoke an existing ability on the character.

### Standard Ability with Parameters
Invoke parameterized standard abilities (Shift, Teleport, Push, etc.) with dynamic values.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  standardAbility: 14c386b6-...  # Shift
  abilityType: standard
  standardAbilityParams:
    distance: "<<Target.Walking Speed>>"
  runOnController: true
```
**Example:** Chorogaunt "Agonizing Harmony" (ally shifts), Dame Cornelia VA3 (ally free strike)
**When:** Making another creature shift, teleport, or use a standard action. Use `runOnController: true` to hand control to the target's player.

### Ability Augmentation (AugmentedAbilityBehavior)
Inject extra behaviors into an existing named ability during resolution.
```yaml
- __typeName: ActivatedAbilityAugmentedAbilityBehavior
  modifier:
    behavior: modifyability
    filterAbility: Ability.Name = "Melee Free Strike"
    cannotModifyAction: true
    ability:
      abilityModification: true
      behaviors:
      - __typeName: ActivatedAbilityDrawSteelCommandBehavior
        rule: M<2 prone
```
**Example:** Werewolf "Wall Leap" (adds prone to free strike), Orc Warleader "Lockdown" (augments Grab)
**When:** A context where a free strike or maneuver should gain bonus effects. Use `filterAbility` to match by name, `cannotModifyAction: true` to avoid consuming an action.

### Nested Custom Ability for Ally Targeting
Two-level nesting: outer picks an ally, inner invokes an action on that ally.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  abilityType: custom
  customAbility:
    targetAllegiance: ally
    targetType: target
    range: "10"
    behaviors:
    - __typeName: ActivatedAbilityInvokeAbilityBehavior
      standardAbility: 14c386b6-...  # Shift
      standardAbilityParams: { distance: "<<Target.Walking Speed>>" }
      runOnController: true
```
**Example:** Chorogaunt "Agonizing Harmony" (choose ally, that ally shifts)
**When:** "Choose an ally, then that ally does something" effects.

---

## Damage Modification

### Damage Halving (powertabletrigger)
Reactive halving of incoming damage via a power roll modifier.
```yaml
behavior: powertabletrigger
trigger: takedamage          # or "strike" for strike-only
targetType: selforally       # self, selforally, ally
range: "1"
powerRollModifier:
  damageMultiplier: half
  rollType: ability_power_roll
```
**Example:** Dame Cornelia "Parry!" (self or adjacent ally), Guardian "Don't Worry, I'm Here"
**When:** Any reactive damage reduction. Use `trigger: takedamage` for all damage, `trigger: strike` for strikes only.

### Damage Halving + Custom Trigger Chain
Halve damage AND chain a secondary effect (buff, heal, etc.).
```yaml
powerRollModifier:
  damageMultiplier: half
  hasCustomTrigger: true
  customTrigger:
    castImmediately: true
    behaviors:
    - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
      ongoingEffect: <buff-id>
```
**Example:** Demon Chorogaunt "I Thrive on Pain" (halve + gain +3 damage)
**When:** Damage reduction that also grants a counter-buff.

### Damage Type Conversion (damageTypeMappings)
Convert all outgoing damage of one type to another.
```yaml
behavior: power
rollType: ability_power_roll
damageTypeMappings: { untyped: cold, fire: cold }
modtype: none
```
**Example:** Blade of Quintessence (choose element), Frostheart complication (untyped -> cold)
**When:** Elemental weapons, elemental affinity traits.

### Conditional Damage Bonus (damageModifier)
Add bonus damage to power rolls under specific conditions.
```yaml
behavior: power
damageModifier: Might           # or "1d3", "5", etc.
activationCondition: Target.Object
keywords: { Weapon: true }
rollType: ability_power_roll
modtype: none
```
**Example:** Berserker "Primordial Strength" (bonus vs objects), Wode Hag "Open the Oven" (aura damage buff)
**When:** Passive damage bonuses gated by target type, condition, or keyword.

### Malice-Gated Enhanced Attack (ModifyPowerRollBehavior)
Optional resource spend to add damage and/or riders to a power roll.
```yaml
- __typeName: ActivatedAbilityModifyPowerRollBehavior
  modifier:
    resourceCostAmount: "2"
    resourceCostType: cost
    activationCondition: false     # optional
    damageModifier: 1d3
    addText: A<2 bleeding (save ends)
    modtype: none
```
**Example:** Thorn Dragon "Spinous Tail Swing" (2 Malice for +1d3 + bleeding)
**When:** "Spend resource for enhanced attack" mechanics.

### Unreducible Damage (cannotBeReduced)
Damage that ignores all damage reduction.
```yaml
- __typeName: ActivatedAbilityDamageBehavior
  cannotBeReduced: true
  roll: 1d6+Level
```
**Example:** Bleeding condition (action damage)
**When:** Bleed effects, true damage, or any damage that should bypass DR.

### Dynamic Damage Scaling (Count Nearby Creatures)
Damage formula that scales with board state.
```yaml
- __typeName: ActivatedAbilityDamageBehavior
  roll: 2*Target.Count Nearby Creatures(1,"Goblin")
  separateRolls: true
```
**Example:** Goblin Monarch "Kill!", Mystic Queen Bargnot "Kill Them All!"
**When:** Swarm synergy or positional scaling. Use `separateRolls: true` so each target evaluates independently.

---

## Targeting and Retargeting

### Strike Redirection (changeTarget)
Redirect an incoming strike to an adjacent ally.
```yaml
behavior: powertabletrigger
trigger: strike
powerRollModifier:
  changeTarget: true
  changeTargetFilter: Friends(triggerer, target)
  changeTargetRange: distance
  changeTargetDistance: 1
```
**Example:** Goblin Monarch "Meat Shield", Mystic Queen Bargnot "Show Them Your Might!"
**When:** Bodyguard or "interpose" abilities that swap the target of an incoming attack.

### Reasoned Filters for Targeting Feedback
Provide user-facing explanations when targeting fails.
```yaml
reasonedFilters:
- reason: You cannot grab creatures larger than you.
  formula: caster.size >= target.size
```
**Example:** Grab maneuver
**When:** Any ability with complex targeting restrictions. Much better UX than silent rejection.

### Variation Modes (Target Chooses)
Present the choice to the affected target, not the caster.
```yaml
multipleModes: variations
modeList:
- text: Take 5 Damage
- text: Knocked Prone
  condition: Self.Conditions has not "prone"
behaviors:
- __typeName: ActivatedAbilityDamageBehavior
  roll: "5"
  modesSelected: [1]
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  modesSelected: [2]
```
**Example:** Striped Condor Griffon "Bound Ahead", Chorogaunt "Frightening Tones"
**When:** "Choose your punishment" abilities. Use `multipleModes: variations` (not `true`).

### Per-Target Choice with Target ID Passing
Each target independently chooses between options in a multi-target ability.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  applyto: targets
  standardAbilityParams: { targetid: "<<Target.ID>>" }
  customAbility:
    multipleModes: variations
    modeList:
    - text: Option A
      variation:
        targetFilter: Target.ID = <<targetid>>
        behaviors: [...]
```
**Example:** Chorogaunt "Frightening Tones" (each target: damage OR frightened)
**When:** Multi-target abilities where each target gets their own choice.

### Sequential Target Selection (emptyspace targeting)
Let the user place objects or creatures interactively, one at a time.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  promptText: "Choose the first square..."
  customAbility:
    targetType: emptyspace
    range: 1
    behaviors:
    - __typeName: ActivatedAbilityCreateObjectBehavior
      objectid: <wall-id>
```
**Example:** Brambleguard "Wall of Roses" (place wall segments)
**When:** Multi-tile terrain features requiring user placement.

### proximity_only Targeting
Target creatures near the ability's area rather than in it.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  applyto: proximity_only
  target_proximity_range: "5"
  filterTarget: friends(target, caster) and target != caster
```
**Example:** Dame Cornelia VA3 (allies within 5 of area make free strikes)
**When:** "Allies near the area can do X" effects.

---

## Resource Spending

### Channeled Resource (Variable Spending)
Spend extra resource for enhanced effect.
```yaml
channeledResource: <resource-guid>
channelIncrement: 2              # cost per extra tick
maxChannel: 10                   # cap
channelDescription: +1 ally per 2 Malice spent.
# Reference in formulas:
standardAbilityParams:
  count: "<<1 + Charges>>"
```
**Example:** Kobold Signifier "Signum" (Malice for more allies), Tactician "Strike Now!" (Focus for extra target)
**When:** Any "spend more for more" ability. `<<Charges>>` = number of ticks purchased.

### Conditional Channeling
Channel only available under certain conditions.
```yaml
maxChannel: 100 when winded else 0
behaviors:
- __typeName: ActivatedAbilityModifyPowerRollBehavior
  modifier:
    filterCondition: Winded and not Dying
    damageModifier: charges d6
```
**Example:** Fury "To the Uttermost End" (channel only when winded, d6 vs d10 by state)
**When:** State-dependent resource spending.

### Multi-Mode with Malice Gating
Different modes available at different resource thresholds.
```yaml
modeList:
- text: Standard
  condition: ""
- text: 1 Malice
  condition: Heroic Resources Available to Spend.malice > 1
- text: 3 Malice
  condition: Heroic Resources Available to Spend.malice > 3
```
**Example:** Orc Warleader "Go." (three escalating modes)
**When:** Leader/commander abilities with tiered enhancement options.

### Blood Toll (Self-Damage to Enhance)
Damage yourself as part of an enhanced ability.
```yaml
# Strain pattern:
- __typeName: ActivatedAbilityDamageBehavior
  strainSelection: strained
  applyto: caster
  roll: 2d6
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  strainSelection: strained
  applyto: caster
  rule: weakened (save ends)
```
**Example:** Telekinesis "Greater Kinetic Grip" (strained version adds self-damage + weakened)
**When:** Talent strain mechanics. Use `strainSelection: strained`/`unstrained` to gate behaviors.

---

## Persistent Effects

### Aura with Terrain/Damage
Create a persistent zone with movement damage.
```yaml
- __typeName: ActivatedAbilityAuraBehavior
  aura:
    difficult_terrain: true
    damage: 4
    movedamage: fire
    applyto: enemies
    objectid: <visual-object>
  duration: eoe
```
**Example:** Flow of Magma "Eruption" (fire + difficult terrain), Abyssal Rift (corruption on entry)
**When:** Hazardous zones. `movedamage` sets the damage type for entry/start-of-turn damage.

### Death-Triggered Persistent Zone
Creature leaves a hazard on death that persists after removal.
```yaml
trigger: creaturedeath
behaviors:
- __typeName: ActivatedAbilityAuraBehavior
  aliveafterdeath: true          # KEY: survives creature removal
  aura:
    blocks_line_of_effect: true  # or difficult_terrain, damage, etc.
    objectid: <visual-id>
```
**Example:** Fire Plume "Pyre", Crux of Ash, Desolation of Sand
**When:** Minion death zones. `aliveafterdeath: true` is essential -- without it, the aura is cleaned up.

### Single-Use Pickup Aura
Aura left by a dying creature that transforms the first creature to enter.
```yaml
aura:
  creatureFilter: minion
  triggers:
  - trigger: onenter
    destroyaura: true            # one-time use
    ability:
      behaviors:
      - __typeName: ActivatedAbilitySummonBehavior
        replaceCaster: true
      - __typeName: ActivatedAbilityRemoveCreatureBehavior
```
**Example:** Kobold Signifier "Upholding High Standards" (minion picks up standard, becomes signifier)
**When:** Relics, standards, power transfers. `destroyaura: true` for single use.

### Aura Entry Trigger
Fire an ability when creatures enter the aura.
```yaml
aura:
  applyto: enemies
  triggers:
  - trigger: onenter
    ability:
      trigger: onenter
      silent: true
      behaviors:
      - __typeName: ActivatedAbilityDamageBehavior
        roll: "5"
```
**Example:** Fossil Cryptic "Churning Trunk", Abyssal Rift (teleport portal)
**When:** Damage on entry, triggered teleports, etc. Use `silent: true` to avoid chat spam.

### Aura with Damage Modifier
Zone that buffs attacks against creatures inside it.
```yaml
- __typeName: ActivatedAbilityAuraBehavior
  aura:
    modifiers:
    - behavior: power
      damageModifier: "5"
      rollType: enemy_ability_power_roll
      modtype: none
  duration: eoe
```
**Example:** Wode Hag "Open the Oven" (+5 damage in zone)
**When:** "Zone that buffs the monster's attacks" or debuff zones.

### Summoned Objects with HP
Create objects (walls, terrain features) at target locations.
```yaml
- __typeName: ActivatedAbilityCreateObjectBehavior
  objectid: <object-guid>
```
**Example:** Brambleguard "Wall of Roses", Fossil Cryptic fissures
**When:** Wall segments, barriers, terrain features. Chain with InvokeAbility for multi-tile placement.

### Transformation (TransformBehavior)
Transform the caster into another form.
```yaml
- __typeName: ActivatedAbilityTransformBehavior
# or via ongoing effect:
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  duration: eoe_or_dying
  ongoingEffect: <form-id>    # effect with behavior: transform
```
**Example:** Brambleguard "Wall of Roses" (creature -> wall), Werewolf "Full Wolf" (via ongoing effect)
**When:** Polymorphs, rage forms, shapeshifting. For stat changes, use an ongoing effect with `behavior: transform`.

---

## Condition Mechanics

### Bestow Condition (Compound Conditions)
A condition that automatically applies another condition.
```yaml
behavior: bestowcondition
conditionid: <prone-id>
filterCondition: stamina <= Dying Stamina and (Hero or Retainer)
explanation: You are prone because you are unconscious.
```
**Example:** Unconscious bestows Prone, Dying bestows Bleeding
**When:** Conditions that chain other conditions. Use `filterCondition` for conditional bestowing.

### Condition Stacking (ConditionStacks)
Read or apply stack counts on conditions.
```yaml
# Read stacks in a formula:
roll: ConditionStacks("On Fire")
# Apply multiple stacks:
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  stacks: "4"
  filterTarget: Ongoing Effects has "Rage"
```
**Example:** On Fire (damage = stack count), Werewolf "Howl" (add 4 rage stacks)
**When:** DoT conditions, escalating debuffs, resource-like stacking effects.

### Escalating Potency via Condition Stacks
Each failed resistance makes the next attempt harder to resist.
```yaml
filterTarget: not Cast.Passes Potency(Target, "P", Condition Stacks("Accursed Bite Target"))
```
**Example:** Werewolf "Accursed Bite" (Lycanthropy buildup)
**When:** Infection, curse, or poison mechanics where repeated exposure increases severity.

### Condition Riders
Modular attachments to existing conditions that add effects.
```yaml
__typeName: ConditionRider
condition: <restrained-id>
modifiers:
- behavior: bestowcondition
  conditionid: <weakened-id>
- behavior: resistance
  resistances: [{ damageType: all, dr: "-2" }]
```
**Example:** "Also Restrained" rider, "Damage Weakness 2" rider, "Strangle" rider
**When:** Monster-specific upgrades to standard conditions. Keeps base conditions clean.

### sustainFormula (Auto-Removal)
Condition/effect automatically ends when a formula becomes false.
```yaml
sustainFormula: (not Grabber.dead) where Grabber = ConditionCaster("grabbed")
# Other examples:
sustainFormula: Ongoing Effects has "Null Field"
sustainFormula: not self.stamina <= self.Dying Stamina
```
**Example:** Grabbed (ends when grabber dies), Absorption Field (ends when prerequisite lost)
**When:** Any effect tied to another creature's state or a prerequisite condition.

### Condition-Source Tracking (ConditionCaster)
Reference the creature that imposed a condition.
```yaml
# In activationCondition:
activationCondition: target.ConditionCaster("Frightened") = self
# In targetFilter:
targetFilter: ConditionCaster("Grabbed") = Caster
# In damage formulas:
roll: 2*(ConditionCaster("Arrestor Cycle").Intuition)
```
**Example:** Frightened (bane vs source), Taunted (double bane if not targeting taunter), Grabbed (target only your own grabs)
**When:** Conditions whose effects depend on WHO applied them.

### Suppress Abilities
Disable specific abilities by filter.
```yaml
behavior: suppressabilities
abilityFilter: Ability.action and ability.Maneuver
# or by keyword:
keywords: { Magic: true }
explanation: While grabbed, you can't use magic abilities.
```
**Example:** Unconscious (suppress all actions), Strangle rider (suppress magic)
**When:** Conditions that disable categories of abilities.

### maxInstancesFormula
Limit how many instances of a condition one caster can maintain.
```yaml
maxInstancesFormula: Maximum Marks    # or "Level", a fixed number, etc.
```
**Example:** Mark condition, Vengeance Sigil
**When:** Conditions with limited simultaneous applications per caster.

---

## Movement Patterns

### Shift into Vacated Square
After forcing movement, follow into the square the target left.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  applyto: caster
  customAbility:
    targeting: vacated           # KEY: only squares target just left
    targetType: emptyspace
    range: Movement Speed
    categorization: Hidden
    behaviors:
    - __typeName: ActivatedAbilityRelocateCreatureBehavior
      movementType: shift
```
**Example:** Shadow "Disorienting Strike", Swashbuckler "Fancy Footwork"
**When:** "Move into the space the target left." Use `targeting: vacated`.

### Forced Movement with Potency Check
Apply different forced movement based on potency test.
```yaml
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  filterTarget: Cast.PassesPotency(target, "M")
  rule: slide 4
  tiersSelected: [1]
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  filterTarget: not Cast.PassesPotency(target, "M")
  rule: vertical slide 4
  tiersSelected: [1]
```
**Example:** Wode Hag "Turned Upside Down" (slide vs vertical slide by Reason), Telekinesis abilities
**When:** Forced movement that varies by target's resistance.

### Tier-Dynamic Movement Distance
Movement distance that scales with power roll tier.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  standardAbility: <shift-id>
  standardAbilityParams:
    distance: "<<cast.tier>>+2"   # Tier 1=3, Tier 2=4, Tier 3=5
```
**Example:** Flow of Magma "Molten Strike"
**When:** Post-roll movement that scales with roll outcome.

### Teleport Pattern
Invoke the standard teleport ability with dynamic range.
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  standardAbility: 1de07d8e-...   # Teleport
  standardAbilityParams:
    range: "<<caster.Reason>>"
```
**Example:** Void "Pierce the Veil of Substance", Abyssal Rift portal
**When:** Teleport effects. The standard teleport ability handles LoS and pathfinding.

---

## Triggered Abilities

### powertabletrigger (Reactive Modifier)
Modify an incoming power roll reactively.
```yaml
behavior: powertabletrigger
trigger: strike                    # strike, takedamage, powerroll
targetType: self                   # self, ally, selforally
powerRollModifier:
  damageMultiplier: half           # half, none
  modtype: edge                    # edge, bane, tier3, none
  resourceCostAmount: "3"
  resourceCostType: cost
  activationCondition: false       # false = always prompt
  rollType: ability_power_roll
```
**Example:** Dame Cornelia "Parry!" (halve damage), Insurgent "Coordinated Execution" (force tier 3)
**When:** Reactive damage reduction, forced crits, or conditional modifiers on incoming rolls.

### powertableadditional (Extending Existing Triggers)
Add a secondary modifier to an existing power roll modification.
```yaml
behavior: powertableadditional
additionalModifier:
  damageMultiplier: half
  rollType: enemy_ability_power_roll
  hasCustomTrigger: true
  customTrigger:
    behaviors:
    - __typeName: ActivatedAbilityApplyAbilityDurationEffect
      momentaryEffect: { name: Dissipate, modifiers: [...] }
```
**Example:** Fossil Cryptic "Dissipate" (halve + ignore riders)
**When:** Adding reactive modifiers without replacing the base powertabletrigger.

### Death Triggers
Fire effects when the creature reaches 0 Stamina or dies.
```yaml
# 0 Stamina (still on the map):
trigger: zerohitpoints
# Actual death/removal:
trigger: creaturedeath
```
**Example:** Dame Cornelia "Death Void" (zerohitpoints -> AoE), Fire Plume "Pyre" (creaturedeath -> aura)
**When:** Death explosions use `zerohitpoints`. Persistent death terrain uses `creaturedeath` + `aliveafterdeath`.

### Movement Triggers
React to creature movement events.
```yaml
# Enemy leaves adjacency:
trigger: leaveadjacent
conditionFormula: not Friends(Moving Creature, Self)
# Enemy finishes voluntary move:
trigger: finishmove
conditionFormula: not path.Forced
# Force movement:
trigger: forcemove
```
**Example:** Opportunity Attack (leaveadjacent), Apex Predator (finishmove)
**When:** Opportunity attacks, reactive chasing, movement-triggered effects.

### Begin/End Turn Triggers
Fire at the start or end of a creature's turn.
```yaml
trigger: beginturn
subject: enemy              # self (default), enemy, other, otherheroes
subjectRange: "1"           # for subject: enemy
targetType: subject         # target the triggering creature
```
**Example:** Brambleguard "Thicket and Thorns" (damage adjacent enemies at start of their turn)
**When:** DoT auras, start-of-turn buffs, end-of-turn saves.

### Condition-Based Triggers
React to ability use, resource use, or damage events.
```yaml
trigger: useability
conditionFormula: Used Ability.keywords has "Void"
# or:
trigger: useresource
conditionFormula: Resource is "main action"
# or:
trigger: losehitpoints
targetType: attacker
```
**Example:** Void "Pierce the Veil" (useability), Bleeding (useresource), Lord Relg "Siphon Memory" (losehitpoints)
**When:** Keyword-triggered bonuses, action-cost effects, damage retaliation.

### Custom Trigger Events
Fire and listen for custom named events.
```yaml
# Fire:
- __typeName: ActivatedAbilityCustomTriggerBehavior
  triggerName: Critical Hit
  value: Cast.Roll
# Listen:
trigger: custom
conditionFormula: Trigger Name is madesave
```
**Example:** Critical Hit (fires event), Banished (listens for save events)
**When:** Inter-ability communication. The save system fires `madesave` + `madesave<condition>`.

---

## Cast Memory

### RememberBehavior for Cross-Behavior Data
Snapshot a value mid-resolution for use in later behaviors.
```yaml
- __typeName: ActivatedAbilityRememberBehavior
  memoryName: StartingDamage
  calculation: Cast.DamageDealt
# Later:
- __typeName: ActivatedAbilityHealBehavior
  roll: Cast.Damage Dealt - Cast.Memory("StartingDamage")
```
**Example:** War Dog Amalgamite "Several Arms" (heal for bonus damage dealt)
**When:** Life-drain, vampiric attacks, or any "heal for damage dealt by this step" logic.

### Cast.DamageDealt / Cast.Target Count
Access cumulative cast state in formulas.
```yaml
# Pass damage dealt as a parameter:
standardAbilityParams:
  damagedealt: "<<cast.damage dealt>>"
# Use target count for scaling:
stamina: 5 * cast.Target Count
```
**Example:** Wode Hag "Soul Steal" (heal half damage), Thorn Dragon "Investiture" (temp HP per target)
**When:** Effects that scale with how much damage was dealt or how many targets were hit.

### Cast.Tier for Tier-Dependent Follow-ups
Reference the power roll tier in subsequent behaviors.
```yaml
standardAbilityParams:
  distance: "<<cast.tier>>+2"
```
**Example:** Flow of Magma "Molten Strike"
**When:** Post-roll behaviors whose parameters depend on the roll outcome.

---

## Map Modification

### ChangeElevationBehavior
Alter map elevation in the targeted area.
```yaml
- __typeName: ActivatedAbilityChangeElevationBehavior
  height: "-2"
  shape: square
```
**Example:** Fossil Cryptic "Final Warning Fissure"
**When:** Creating pits, raising platforms, terrain destruction.

### ChangeTerrainBehavior
Swap map tiles in the targeted area.
```yaml
- __typeName: ActivatedAbilityChangeTerrainBehavior
  tileid: "-MBVQqKrE73ix3K9-MjS"
  shape: square
```
**Example:** Fossil Cryptic "Final Warning Fissure"
**When:** Changing floor appearance (lava, ice, cracks).

### CreateObjectBehavior
Spawn a map object at the target location.
```yaml
- __typeName: ActivatedAbilityCreateObjectBehavior
  objectid: <object-guid>
  applyto: caster               # optional: place at caster's position
```
**Example:** Brambleguard "Wall of Roses"
**When:** Walls, barriers, visual markers. Chain multiple for multi-tile features.

---

## Summoning

### Summon by Bestiary Filter
Summon creatures matching a bestiary query.
```yaml
- __typeName: ActivatedAbilitySummonBehavior
  bestiaryFilter: beast.Name="goblin runner"
  numSummons: "1"
  allCreaturesTheSame: true
targetType: emptyspace
range: "20"
```
**Example:** Goblin Monarch "Get in Here!", Gnoll Summoner "Cackletongue"
**When:** Reinforcement abilities. Use `targetType: emptyspace` for user-placed summons. Repeat the behavior for multiple summons.

### Summoned Creature Lifecycle
Auto-remove summoned creatures under multiple conditions.
```yaml
# End of encounter:
trigger: endcombat
behaviors: [ActivatedAbilityRemoveCreatureBehavior]
# Death:
trigger: creaturedeath
behaviors: [ActivatedAbilityRemoveCreatureBehavior]
# Summoner dying:
trigger: dying
subject: otherheroes
conditionFormula: Subject = Summoner
behaviors: [ActivatedAbilityRemoveCreatureBehavior]
```
**Example:** Divine Dragon (three removal triggers)
**When:** Any summoned creature that should disappear under specific conditions.

### Inherited Stats from Summoner
Set summon's characteristics to match the summoner's values.
```yaml
- __typeName: CharacterModifier
  attribute: agl
  operation: set
  behavior: attribute
  value: Summoner.Agility
```
**Example:** Divine Dragon (all stats from summoner)
**When:** Summoned creatures that scale with their creator. Uses `Summoner.*` GoblinScript namespace.

### Transform via Remove + Resummon
Replace one creature with another at the same location.
```yaml
- __typeName: ActivatedAbilityRemoveCreatureBehavior
  leavesCorpse: false
- __typeName: ActivatedAbilityDelayBehavior
  delay: "0.5"
- __typeName: ActivatedAbilitySummonBehavior
  bestiaryFilter: beast.name="Gnoll Marauder"
```
**Example:** Gnoll Abyssal Summoner "Cackletongue" (hyena -> marauder)
**When:** Creature evolution, transformation, or upgrade mechanics.

---

## Resistance Rolls

### Resistance Roll (Target Defends)
Targets roll instead of the attacker. Tier severity is inverted.
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: 2d6 + Might or Agility
  resistanceRoll: true
  resistanceAttr: inu            # targets roll with this attribute
  tiers:
  - 18 fire damage               # Tier 1 = worst for target
  - 14 fire damage
  - 9 fire damage                # Tier 3 = best for target
```
**Example:** Fire Giant Chief "Roiling Fist", Orc Warleader "Close In" (Intuition test)
**When:** Boss AoE abilities, environmental hazards. Note: uses 2d6 and `resistanceAttr`.

### Test Rolls (isTest)
Tests where the target rolls and tier 3 is the best outcome for them.
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: 2d10 + Reason
  isTest: true
  tiers: [worst outcome, middle, best outcome]
```
**Example:** Abyssal Rift "Destabilize Test", Lord Relg "Siphon Memory"
**When:** Skill tests, resistance checks. `isTest: true` inverts tier display.

---

## Growing Resources and Scaling

### Growing Resources (Threshold Unlocks)
Passive effects that unlock at heroic resource thresholds.
```yaml
behavior: growingresources
levels:
- level: 1
  resources: 4
  description: Bonus Damage
- level: 4
  resources: 8
  description: Extra Damage
```
**Example:** Beastheart "Rampage"
**When:** Escalating passive bonuses at resource milestones.

### GoblinScriptTable (Level-Gated Values)
Values that change at specific level breakpoints.
```yaml
value:
  __typeName: GoblinScriptTable
  field: Level
  entries:
  - { threshold: 1, script: "1" }
  - { threshold: 5, script: "2" }
  - { threshold: 9, script: "3" }
```
**Example:** Blade of Quintessence (damage scaling), Shadow (resource gain at level 7)
**When:** Any value that should scale with level. Avoids hardcoded breakpoints.

---

## Utility Patterns

### Tag-Then-Process (Temporary Marker)
Apply a temporary ongoing effect as a marker, then filter later behaviors by it.
```yaml
# Tag:
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  duration: 0
  filterTarget: Target.Conditions has "prone"
  ongoingEffect: <already-prone-marker>
# Process:
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  filterTarget: Target.Ongoing Effects has "already prone"
  tiersSelected: [1]
```
**Example:** Fossil Cryptic "Sand Slam" (upgrade prone to restrained if already prone), Striped Condor Griffon "Violent Thrashing"
**When:** State-dependent escalation. Apply marker BEFORE the power roll, check it AFTER.

### Momentary Effect (Duration-of-Resolution Flag)
Temporary flag that lasts only during ability resolution.
```yaml
- __typeName: ActivatedAbilityApplyAbilityDurationEffect
  momentaryEffect:
    name: Charging
    modifiers:
    - behavior: attribute
      attribute: <flag-id>
      value: 1
```
**Example:** Charge (Charging flag), Fossil Cryptic "Dissipate" (immunity window)
**When:** Flags needed only during a single ability's resolution. Auto-cleaned up afterward.

### Leader/Solo Branching
Different effects for boss-type vs regular enemies.
```yaml
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  filterTarget: not leader and not solo
  ongoingEffect: <instant-kill>
- __typeName: ActivatedAbilityReplenishBehavior
  filterTarget: Cast.Primary Target.leader or Cast.Primary Target.Solo
  quantity: "3"
```
**Example:** Fury "You Are Already Dead"
**When:** Abilities that should have different effects against bosses vs regular creatures.

### PurgeEffectsBehavior (End Effect Trait)
Remove save-ends effects, optionally with a self-damage cost.
```yaml
- __typeName: ActivatedAbilityPurgeEffectsBehavior
  damageToSelf: "5"
  purgeType: one               # one, all
  targetDuration: save         # save, eot, save|eot
  mode: conditions             # conditions, effect
```
**Example:** Chorogaunt/Dame Cornelia "End Effect" trait, Grabbed "Escape Grab"
**When:** Monster "End Effect" traits, condition removal abilities. Use `conditionFormula: Save Ends Effects` to gate the trigger.

### Bidirectional Edge (Self + Enemy Modifier)
Grant edge to own rolls AND enemy rolls simultaneously.
```yaml
# Own rolls:
- behavior: power
  modtype: edge
  activationCondition: self.Winded = 1
  rollType: ability_power_roll
# Enemy rolls:
- behavior: power
  modtype: edge
  activationCondition: Target.Winded = 1
  rollType: enemy_ability_power_roll
```
**Example:** Demon Ruinant/Chorogaunt "Lethe" (edge while winded, but enemies get edge too)
**When:** Traits that simultaneously buff and debuff the creature.

### Destroy Behavior (Instant Kill)
Immediately kill/remove a target.
```yaml
- __typeName: ActivatedAbilityDestroyBehavior
  leavesCorpse: false            # optional
targetFilter: Target has "Loyalty Collar"
```
**Example:** War Dog "Highest Posthumous Promotion" (detonate collared allies), Chorogaunt "Bully the Weak"
**When:** Sacrifice abilities, execute mechanics, or conditional instant kills.

### Fixed Roll (Minions)
Minions use a fixed roll value instead of 2d10.
```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "12"
  tiers: ["4 damage", "4 damage", "4 damage"]
```
**Example:** Desolation of Sand, Fire Plume free strikes
**When:** Minion abilities with flat damage (no roll variance).
