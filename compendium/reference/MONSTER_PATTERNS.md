# Monster Implementation Patterns Reference

Proven YAML patterns for implementing monster abilities, malice features, traits,
and triggered reactions. Every pattern listed here has working examples in the codebase.

---

## Table of Contents

1. [Targeting Patterns](#targeting-patterns)
2. [Terrain and Zone Creation](#terrain-and-zone-creation)
3. [Triggered Reactions](#triggered-reactions)
4. [Death Triggers](#death-triggers)
5. [Recurring Per-Turn Effects](#recurring-per-turn-effects)
6. [Creature Summoning and Transformation](#creature-summoning-and-transformation)
7. [Damage Modification (Halving, Redirection)](#damage-modification)
8. [Faction-Wide Buffs and Actions](#faction-wide-buffs-and-actions)
9. [Power Roll Tier Text Auto-Parsing](#power-roll-tier-text-auto-parsing)
10. [Solo Monster Patterns](#solo-monster-patterns)
11. [Genuinely Novel Mechanics (Lua Required)](#genuinely-novel-mechanics)

---

## Targeting Patterns

### Target all creatures of a type on the map (buff/debuff)

Use `targetType: map` with `targetFilter` to affect every creature matching a keyword.

```yaml
# Example: Goblin Mode -- +2 speed to all goblins
targetType: map
targetFilter: target.keywords has "Goblin"
selfTarget: true
behaviors:
  - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
    ongoingEffect: <uuid>
    duration: endround
```

**Used by**: Goblin Mode, Exploit Opening (Humans), Forest Network (Wode Elves),
Punishing Regrowth (Wode Elves), We Just Do It Better (Rivals), In Defiance of
Time (High Elves), Shield Wall (Kobolds), Tiny Stabs (Goblins), Swamp Stink (Goblins)

### Target all creatures of a type and make them take actions

Combine `targetType: map` + keyword filter with `InvokeAbilityBehavior` using
`runOnController: true` to prompt each ally to act.

```yaml
# Example: Overwhelming March -- each orc shifts up to speed
targetType: map
targetFilter: target.keywords has "Orc"
selfTarget: true
behaviors:
  - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
    ongoingEffect: <uuid>
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    standardAbility: 14c386b6-...          # standard Shift ability
    standardAbilityParams:
      distance: "Movement Speed"
    promptWhenResolving: true
    promptText: "Each orc shifts up to their speed."
    runOnController: true
```

**Used by**: Overwhelming March (Orcs), Dread March (Undead), Rappelling Barrage (Dwarves)

### Select N specific allies of a type

Use `targetType: target` with `targetAllegiance: ally` and `targetFilter`.

```yaml
# Example: Maniple Tactics -- select up to 3 kobolds
targetType: target
targetFilter: target.type = "Kobold"
targetAllegiance: ally
numTargets: "3"
```

**Used by**: Maniple Tactics (Kobolds), Set the Initiative (Kobolds), Bull Rush
(Minotaurs), Bloodpool (Gnolls)

### Scaling target count with channeled malice

Use `channeledResource` + `numTargets` with `Charges` to scale.

```yaml
# Example: Bull Rush -- 1 minotaur per 3 malice
numTargets: "1 * Charges"
channeledResource: <malice-uuid>
channelIncrement: 3
```

**Used by**: Bull Rush (Minotaurs), Dread March (Undead), Gush (Ooze)

### All allies in range (any type)

Use `targetType: all` with `targetAllegiance: ally`.

```yaml
# Example: Shoot! -- each artillery ally makes a ranged free strike
targetType: all
targetAllegiance: ally
targetFilter: role is artillery
range: 10
behaviors:
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    standardAbility: <free-strike-uuid>
    runOnController: true
```

**Used by**: Shoot! (Human Bandit Chief), Form Up! (Human Bandit Chief),
What Are You Waiting For? (Goblin Monarch)

### Different effects on different creature types in same ability

Use `filterTarget` on individual behaviors within the same ability.

```yaml
# Example: Mohler Cavity -- orcs shift out, non-orcs make test
behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    filterTarget: target.type != "Orc"     # only non-orcs test
    ...
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    filterTarget: target.type = "Orc"      # only orcs shift
    ...
```

**Used by**: Mohler Cavity (Orcs)

---

## Terrain and Zone Creation

### Persistent difficult terrain zone (AuraBehavior)

```yaml
- __typeName: ActivatedAbilityAuraBehavior
  duration: eoe                    # nextturn, endturn, endround, eoe, none (permanent)
  aliveafterdeath: true            # persists after caster dies
  aura:
    __typeName: Aura
    name: "Zone Name"
    guid: <uuid>
    objectid: <visual-object-uuid>
    difficult_terrain: true
    applyto: enemies               # enemies, all, selfandfriends, sametype, othertype
    modifiers: []
    triggers: []
```

**Used by**: Swamp Stink (Goblins), Mohler Trench/Cavity (Orcs), Gravity Well
(Time Raiders), Web (War Spider, Glass Spider), Death Grasp (Rotting Zombie)

### Damage zone (per-square or on-enter damage)

Two approaches for damage zones:

**Approach A: `damage` + `movedamage` fields on the aura**
```yaml
aura:
  damage: 4                        # damage on enter/start of turn
  movedamage: fire                 # damage type per square moved
  difficult_terrain: true
  applyto: enemies
```

**Used by**: Flow of Magma (Eruption), Fire Plume (Pyre), Goblin Toxinaut (Swamp Gas),
Demon Torlas (Floor to Flesh)

**Approach B: `triggers` array with `onenter` trigger**
```yaml
aura:
  applyto: enemies
  triggers:
  - trigger: onenter
    ability:
      __typeName: TriggeredAbility
      trigger: onenter
      behaviors:
      - __typeName: ActivatedAbilityDamageBehavior
        roll: "3"
        damageType: acid
```

**Used by**: Ooze (Gush), War Dog Crucibite (Flamebelcher), War Dog Pestilite
(Pestilite Aura)

### One-shot trap zone (destroys after triggering)

```yaml
aura:
  applyto: enemies
  creatureFilter: "Might Potency Resistance < 2"    # optional potency gate
  triggers:
  - destroyaura: true              # KEY: aura self-destructs after first trigger
    trigger: onenter
    ability:
      __typeName: TriggeredAbility
      trigger: onenter
      behaviors:
      - __typeName: ActivatedAbilityDrawSteelCommandBehavior
        rule: "Slowed (save ends)"
```

**Used by**: Iron Jaws (Gnolls), Bonetrops (Decrepit Skeleton), Death Grasp (Rotting Zombie)

### Line-of-effect blocking zone

```yaml
aura:
  blocks_line_of_effect: true
  difficult_terrain: true          # optional
  objectid: <wall-object-uuid>
  applyto: enemies
```

**Used by**: Walking Boulder (Pile Up death trait, Obstruct passive trait),
Crux of Ash (Ashen Cloud death trait)

### Growing aura (expands each round)

```yaml
aura:
  grow: 1                          # grows by 1 square each round
  applyto: all
duration: none                     # permanent
aliveafterdeath: true
```

**Used by**: The Grasping, The Hungry (Undead)

### Relocatable aura

```yaml
aura:
  canrelocate: true
  relocateResource: none           # or a resource UUID
  relocateRange: 1
```

**Used by**: Flow of Magma (Eruption)

### Conditional aura (active only when condition met)

```yaml
# Aura only active while creature is burrowing
conditionFormula: Movement Type = "Burrow"
radius: "1"
aura:
  difficult_terrain: true
```

**Used by**: Mohler (Ground Grinder)

### Elevation changes (pits and pillars)

```yaml
# Lower terrain (pit)
- __typeName: ActivatedAbilityChangeElevationBehavior
  shape: square
  radius: 5
  height: "-5"
  testFalling: false

# Raise terrain (pillar)
- __typeName: ActivatedAbilityChangeElevationBehavior
  shape: square
  height: "3"
  recalculateElevation: true       # recalculates at final height
```

**Used by**: Mohler Trench/Cavity (Orcs, pits), Stone Pillars (Fossil Cryptic, pillars)

### Terrain tile painting

```yaml
- __typeName: ActivatedAbilityChangeTerrainBehavior
  tileid: "-MBVQqKrE73ix3K9-MjS"  # terrain tile asset ID
  shape: square
  radius: 5
```

**Used by**: Mohler Trench/Cavity (Orcs), Stone Pillars (Fossil Cryptic)

### Wall/object creation

```yaml
- __typeName: ActivatedAbilityCreateObjectBehavior
  objectid: <summonable-object-uuid>
  randomize: true                  # randomize rotation
```

Pair with `targeting: contiguous` or `targeting: contiguous_wall` for wall placement.

**Used by**: Bramble Barricade (Thorn Dragon), The Grasping, The Hungry (Undead)

---

## Triggered Reactions

### Available trigger types

The engine supports 30+ trigger types. The most useful for monster abilities:

| Trigger ID | Fires When | Key Symbols |
|------------|-----------|-------------|
| `losehitpoints` | Creature takes damage | `damage`, `damagetype`, `keywords`, `attacker` |
| `attacked` | Creature is attacked | `outcome`, `attacker` |
| `targetwithability` | Creature is targeted by an ability | `Used Ability` (ability object) |
| `move` | Creature begins movement | -- |
| `finishmove` | Creature completes movement | `path` |
| `movethrough` | Creature moves through another | -- |
| `leaveadjacent` | Creature moves away from adjacent | -- |
| `forcemove` | Creature is force moved | `type`, `attacker`, `vertical` |
| `inflictcondition` | Condition is applied | `Condition`, `attacker` |
| `creaturedeath` | Creature dies | fires on self AND dispatches to all others |
| `zerohitpoints` | Creature drops to 0 stamina | -- |
| `beginturn` | Start of creature's turn | `order` |
| `endturn` | End of creature's turn | -- |
| `beginround` | Start of combat round | -- |
| `dealdamage` | Creature deals damage to another | -- |
| `winded` | Creature becomes winded | -- |
| `collide` | Creature collides with object/creature | `speed`, `movementtype` |

### Reactive damage when targeted by melee (Toxiferous pattern)

```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: targetwithability
    subject: enemy
    targetType: subject
    conditionFormula: target = self and (Used Ability.Keywords has "Melee")
    mandatory: true
    behaviors:
    - __typeName: ActivatedAbilityDamageBehavior
      roll: "2"
      damageType: poison
    name: Toxiferous
```

**Used by**: 7+ angulotl monsters (Toxiferous trait)

### Reactive damage when creature moves through (Corruptive Phasing)

```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: movethrough
    repeatTargets: false           # once per creature per round
    targetType: target
    behaviors:
    - __typeName: ActivatedAbilityDamageBehavior
      roll: "2"
      damageType: corruption
    name: Corruptive Phasing
```

**Used by**: Specter, Stalker Shade (Corruptive Phasing)

### Reactive ability when force moved (Flying Sawblade)

```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: forcemove
    conditionFormula: Vertical      # only on vertical force movement
    targetType: self
    behaviors:
    - __typeName: ActivatedAbilityInvokeAbilityBehavior
      namedAbility: Haymaker       # invokes creature's own ability by name
    name: Flying Sawblade
```

**Used by**: Bugbear Roughneck (Flying Sawblade)

### Free strike after completing movement (Opportunity Attack pattern)

```yaml
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: finishmove
    subject: enemy
    subjectRange: "1"
    targetType: subject
    mandatory: true
    behaviors:
    - __typeName: ActivatedAbilityInvokeAbilityBehavior
      namedAbility: Free Strike
    name: Opportunity Attack
```

**Used by**: Multiple goblins, bugbears, orcs, werewolves

### React to ally being force moved (Final Orders)

```yaml
triggeredAbility:
  trigger: forcemove
  subject: allies
  subjectRange: "10"
  targetType: subject
  name: Final Orders
  behaviors:
    - __typeName: ActivatedAbilityInvokeAbilityBehavior
      ...
```

**Used by**: War Dog Ground Commander (Final Orders)

### React to OTHER creature's death

```yaml
triggeredAbility:
  trigger: creaturedeath
  subject: other
  conditionFormula: subject.type is Gnoll    # filter whose death triggers it
  behaviors:
    - ...
```

**Used by**: Echoes of Laughter (Gnoll ongoing effect), Taunted condition purge

---

## Death Triggers

### Death explosion (damage burst on death)

```yaml
# In characterFeatures
- __typeName: CharacterFeature
  modifiers:
  - __typeName: CharacterModifier
    behavior: trigger
    triggeredAbility:
      __typeName: TriggeredAbility
      trigger: creaturedeath
      targetType: all              # or self for self-only
      targetFilter: Enemy
      range: 1
      behaviors:
      - __typeName: ActivatedAbilityDamageBehavior
        roll: "1d6"
```

**Used by**: War Dog Loyalty Collar (12+ war dogs)

### Persistent hazard zone on death

```yaml
triggeredAbility:
  trigger: creaturedeath
  targetType: self
  behaviors:
  - __typeName: ActivatedAbilityAuraBehavior
    aliveafterdeath: true          # KEY: aura outlives the creature
    aura:
      damage: 2
      movedamage: fire
      difficult_terrain: true
      applyto: enemies
```

**Used by**: Fire Plume (Pyre), Flow of Magma (Eruption), Rotting Zombie (Death Grasp),
Decrepit Skeleton (Bonetrops), Walking Boulder (Pile Up)

### Free strike before dying

```yaml
triggeredAbility:
  trigger: creaturedeath
  targetType: self
  behaviors:
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    namedAbility: Free Strike
```

**Used by**: Orc Bloodfire Burn (multiple orcs)

### Revive at 0 HP (Arise)

```yaml
triggeredAbility:
  trigger: zerohitpoints
  targetType: self
  behaviors:
  - __typeName: ActivatedAbilityHealBehavior
    roll: "1"                      # heal to 1 HP
  - __typeName: ActivatedAbilityDrawSteelCommandBehavior
    rule: "prone"
```

**Used by**: Armored Soulwight, various undead (Arise trait)

### Self-destruct + summon replacement

```yaml
behaviors:
  - __typeName: ActivatedAbilitySummonBehavior
    monsterType: <replacement-uuid>
    replaceCaster: true
  - __typeName: ActivatedAbilityRemoveCreatureBehavior
    applyto: caster
```

**Used by**: Kobold Signifier (death-triggered replacement)

### Death timing

All `trigger: creaturedeath` abilities fire BEFORE the creature is removed from the map.
The global Monster Death rule has a built-in delay (~1 second for non-minions) plus a
`proceedCondition: Cannot be Removed = 0` gate. This gives death triggers time to resolve.

---

## Recurring Per-Turn Effects

### Start-of-turn damage (aura modifier)

```yaml
# Inside a CharacterFeature modifier
- __typeName: CharacterModifier
  behavior: trigger
  triggeredAbility:
    __typeName: TriggeredAbility
    trigger: beginturn
    targetType: all
    targetFilter: Enemy
    range: 3
    behaviors:
    - __typeName: ActivatedAbilityDamageBehavior
      roll: "2"
      damageType: acid
```

**Used by**: Black Ichor (aura damage), Font of Wrath (Spirit Aura),
Tomb Horror (Enervating Horror)

### End-of-turn self-damage to end save-ends (End Effect)

```yaml
triggeredAbility:
  trigger: endturn
  targetType: self
  behaviors:
  - __typeName: ActivatedAbilityPurgeEffectsBehavior
    damageToSelf: "5"              # or "10", "20" for stronger monsters
    targetDuration: save
    purgeType: one
  name: End Effect
```

**Used by**: Dame Cornelia, Demon Chorogaunt, Goblin Monarch, Human Bandit Chief,
Human Blackguard, Kobold Centurion, Lord Relg (20 damage), War Dog Ground Commander,
all solo monsters (varying damage amounts)

### End-of-caster-turn aura effect

```yaml
# Inside an Aura's triggers array
aura:
  triggers:
  - trigger: casterendturnaura
    ability:
      __typeName: TriggeredAbility
      trigger: casterendturnaura
      targetType: aura             # targets all creatures in the aura
      behaviors:
      - __typeName: ActivatedAbilityDamageBehavior
        roll: "5"
        damageType: corruption
```

**Used by**: Virtuoso Tough Crowd, Vampire Shadowflame Mantle

### Begin-round effects (once per round, not per turn)

```yaml
triggeredAbility:
  trigger: beginround
  castImmediately: true
  behaviors:
  - ...
```

**Used by**: Black Ichor (Malice Emitter -- +1 malice per round),
Mohler (Ground Grinder -- invoke Dig each round)

### Auto-removal of ongoing effects via endTrigger

```yaml
# On a CharacterOngoingEffect -- auto-removes when event fires
endTrigger: beginturn              # or endturn, attack, attacked, useability
```

This removes the ongoing effect (not a triggered action). Used for "until next attack"
or "until start of next turn" type effects.

---

## Creature Summoning and Transformation

### Summon by bestiary UUID

```yaml
- __typeName: ActivatedAbilitySummonBehavior
  monsterType: <bestiary-uuid>
  numSummons: "2"
  allCreaturesTheSame: true
  casterControls: false
  casterChoosesCreatures: false
  groupInitiativeWithCaster: false
```

**Used by**: Ravenous Horde (Undead -- summons zombies), Abyssal Rift (Demons),
House Call (Hag -- summons hut), various hero class abilities

### Summon by bestiary filter

```yaml
- __typeName: ActivatedAbilitySummonBehavior
  bestiaryFilter: 'beast.Name = "goblin runner"'
  numSummons: "1"
  allCreaturesTheSame: true
```

**Used by**: Goblin Monarch (Get in Here!), Summoner class, Elementalist subclasses

### Summon copy of self (ooze split)

```yaml
- __typeName: ActivatedAbilitySummonBehavior
  bestiaryFilter: Beast.Name = Invoker.Name
  groupInitiativeWithCaster: false
  casterControls: false
```

**Used by**: Creeping Sludge, Gummy Ball, Imit Putty (Split)

### Transform creature (swap stat block)

```yaml
- __typeName: ActivatedAbilityTransformBehavior
  bestiaryFilter: 'beast.name = "Demon Ruinant" or beast.name = "Demon Torlas"'
  ongoingEffect: <transform-effect-uuid>
  applyto: none
  replaceCaster: false
```

Usually combined with `DestroyBehavior` (kill original) + `SummonBehavior` (spawn new).

**Used by**: Abyssal Evolution (Demons), Druid Green (Animal Forms)

### Destroy creature (instant kill)

```yaml
- __typeName: ActivatedAbilityDestroyBehavior
  applyto: caster                  # or targets
```

**Used by**: War Dog Posthumous Promotion (detonate loyalty collar -- 9+ war dogs),
Summoned Elemental Mote (self-destruct after catalyzing), Fodder Run (War Dogs)

### Remove creature (despawn with options)

```yaml
- __typeName: ActivatedAbilityRemoveCreatureBehavior
  applyto: caster
  leavesCorpse: true               # optional
  dropsLoot: true                  # optional
```

**Used by**: Kobold Signifier (self-removal after replacement), Divine Dragon (summoner
death cleanup), various class abilities

### Create map object (not creature)

```yaml
- __typeName: ActivatedAbilityCreateObjectBehavior
  objectid: <summonable-object-uuid>
  randomize: true
```

Objects must have the "summonable" keyword in DMHub to be spawnable. Pair with
`targeting: contiguous` or `targeting: contiguous_wall` for wall-style placement.

**Used by**: Bramble Barricade (Thorn Dragon), The Grasping The Hungry (Undead),
College of Caustic Alchemy

---

## Damage Modification

### Halve incoming damage (powertabletrigger)

```yaml
- __typeName: CharacterModifier
  behavior: powertabletrigger
  trigger: takedamage              # or strike
  targetType: self                 # or selforally
  type: trigger                    # or passive
  powerRollModifier:
    __typeName: CharacterModifier
    damageMultiplier: half
    rollType: ability_power_roll
    behavior: power
    name: "Parry!"
```

Optionally chain a triggered action (e.g., shift after halving):
```yaml
    hasCustomTrigger: true
    customTrigger:
      __typeName: TriggeredAbility
      trigger: d20roll
      targetType: self
      castImmediately: true
      behaviors:
      - __typeName: ActivatedAbilityInvokeAbilityBehavior
        standardAbility: <shift-uuid>
        standardAbilityParams:
          distance: "2"
        runOnController: true
```

**Used by**: Glass Spider/War Spider (Skitter), Dame Cornelia (Parry!),
Human Blackguard (Parry!), Bugbear Channeler (Shadow Veil), Kobold Centurion (Testudo!)

### Redirect attack to different target

```yaml
- __typeName: CharacterModifier
  behavior: powertabletrigger
  trigger: strike
  targetType: selforally
  powerRollModifier:
    changeTarget: true
    changeTargetFilter: Friends(triggerer, target)
    changeTargetDistance: 1
    rollType: ability_power_roll
```

**Used by**: Goblin Monarch (Meat Shield), Goblin Mastermind (Goad),
Mystic Queen Bargnot (Show Them Your Might!)

---

## Faction-Wide Buffs and Actions

### Buff all creatures of a type (ongoing effect)

Pattern: `targetType: map` + `targetFilter` + `ApplyOngoingEffectBehavior`

```yaml
targetType: map
targetFilter: target.keywords has "Goblin"
selfTarget: true
behaviors:
  - __typeName: ActivatedAbilityApplyOngoingEffectBehavior
    ongoingEffect: <buff-effect-uuid>
    duration: endround
```

The ongoing effect contains modifiers that grant the actual buff (speed, damage, edge, etc.).

**Used by**: Goblin Mode (+2 speed), Exploit Opening (+edge for Humans),
Soulburn (+double edge for Demons), Bull Rush (+4 speed for Minotaurs)

### All creatures of a type take an action (shift + free strike)

Pattern: `targetType: map` + `targetFilter` + `InvokeAbilityBehavior`

```yaml
targetType: map
targetFilter: target.keywords has "Orc"
selfTarget: true
behaviors:
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    standardAbility: <shift-uuid>
    standardAbilityParams:
      distance: "Movement Speed"
    runOnController: true
    promptWhenResolving: true
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    standardAbility: <free-strike-uuid>
    runOnController: true
```

**Used by**: Overwhelming March (Orcs -- shift), Dread March (Undead -- move + free strike),
Fodder Run (War Dogs -- free strike + self-destruct), Shoot! (Human Bandit Chief)

### Initiative manipulation

```yaml
- __typeName: ActivatedAbilityInitiativeBehavior
  mode: set_priority               # makes target go next
```

**Used by**: Set the Initiative (Kobolds)

---

## Power Roll Types (Ability vs Test vs Resistance)

`ActivatedAbilityPowerRollBehavior` supports 3 roll types that control WHO rolls and
how tiers are interpreted:

### Ability Roll (default) -- Caster rolls against targets

```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: "2d10 + 2"           # caster's roll formula
  attrid: mgt                # characteristic for the roll
  tiers:
  - "5 damage"               # Tier 1 (<=11) -- worst for caster
  - "9 damage"               # Tier 2 (12-16)
  - "12 damage"              # Tier 3 (17+) -- best for caster
```

The CASTER rolls once. Result applies to all targets. Tier 1 = worst, Tier 3 = best
(for the caster). This is the standard attack pattern.

### Test Roll (`isTest: true`) -- Caster rolls a single test

```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  isTest: true
  attrid: mgt                # characteristic tested
  roll: "2d10 + Might"       # caster's roll formula
  resistanceRoll: false
  tiers:
  - "12 damage; dazed (EoT)" # Tier 1 (<=11) -- best for targets (worst result)
  - "10 damage"              # Tier 2 (12-16)
  - "6 damage"               # Tier 3 (17+) -- worst for targets (best result)
```

The CASTER rolls once. Result applies to all targets. **Tiers are INVERTED**: Tier 1 is
the WORST outcome for targets (highest damage/conditions), Tier 3 is the BEST for targets.
The roll type is `test_power_roll`. Used when "the monster makes a Might test" and one
roll determines the outcome for everyone.

**Used by**: Troll Foul Spew, Fossil Cryptic Choking Dust, Wyvern Overflowing Rage

### Resistance Roll (`resistanceRoll: true`) -- Each target rolls individually

```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  resistanceRoll: true
  resistanceAttr: mgt        # attribute targets roll with
  roll: "2d10 + Might"       # formula each TARGET uses
  tiers:
  - "5 damage; slowed (EoT)" # Tier 1 (<=11) -- worst for target
  - "3 damage"               # Tier 2 (12-16)
  - "No effect"              # Tier 3 (17+) -- best for target
```

Each TARGET rolls individually using their own characteristic. Results vary per target.
**Tiers are INVERTED** (same as test): Tier 1 = worst for the rolling creature.
The `roll` field is the formula each target uses (typically `2d10 + Characteristic`).
The `resistanceAttr` specifies which characteristic to use.

Targets are prompted to roll via `RequireSavingThrowsCo` (similar to a saving throw).

**Used by**: Goblin Swamp Stink (Might), War Dog Fire for Effect (Agility),
War Dog Alchemical Cloud (Might), Ogre Shockwave (Might), Orc Mohler Cavity (Agility)

### When to use which

| Scenario | Roll Type | Fields |
|----------|-----------|--------|
| Monster attacks targets | Ability (default) | `roll: "2d10 + X"` |
| "The monster makes a X test" (one roll, all targets) | Test | `isTest: true`, `resistanceRoll: false` |
| "Each enemy/creature makes a X test" (individual rolls) | Resistance | `resistanceRoll: true`, `resistanceAttr: xxx` |

---

## Power Roll Tier Text Auto-Parsing

See `compendium/reference/POWER_TABLE_PARSING.md` for the complete reference of what
tier text is automatically handled. Key patterns:

**Auto-parsed from tier text (no additional behaviors needed):**
- `X damage` / `X type damage` / `X damage (half)`
- `push/pull/slide X` / `vertical push/pull/slide X`
- `dazed/slowed/bleeding/frightened/etc. (eot/save ends/eoe)`
- `M<2 prone (save ends)` (potency gates)
- `prone` / `grabbed` (bare conditions)
- `shift X` / `teleport X` / `jump X` (caster movement)
- `gain X piety/essence/etc.` (heroic resources)
- `the director gains X malice`
- `swap places with the target`
- Various patterns from 42 importerPowerTableEffects entries

**NOT auto-parsed (need additional behaviors or `#` marking):**
- Summoning creatures
- Creating terrain/zones
- Self-healing / ally healing
- Multi-ability combos
- Custom conditions not in the standard set
- Movement mode changes
- Counting mechanics

Use `#` to mark unimplemented text that should display but not execute:
```
8 damage; push 3 # and the target drops whatever it's holding
```

---

## Solo Monster Patterns

### Solo Action (extra main action)

```yaml
- __typeName: ActivatedAbility
  name: Solo Action
  categorization: "Ability"
  castImmediately: true
  behaviors:
  - __typeName: ActivatedAbilityReplenishBehavior
    resourceid: <main-action-resource-uuid>
  resourceCost: <malice-resource-uuid>
  resourceNumber: 5
```

**Used by**: Every solo monster (Arixx, Chimera, Thorn/Gloom/Crucible/Omen/Meteor Dragons,
Fossil Cryptic, Hag, Kingfissure Worm, Manticore, Medusa, Shambling Mound, Werewolf,
Xorannox, Ajax, Ashen Hoarder, Bredbeddle, Count Rhodar, Lich, Lord Syuul, Olothec)

### End Effect (self-damage to end save-ends)

See [Recurring Per-Turn Effects > End-of-turn self-damage](#end-of-turn-self-damage-to-end-save-ends).

Standard damage values by tier: 5 (level 1-3), 10 (level 4-6), 15 (level 7-9), 20 (level 10+).

---

## Genuinely Novel Mechanics (Lua Required)

These mechanics have NO existing YAML pattern and would require Lua implementation:

1. **Chaincast** (High Elves) -- Cast an ability from another ally's position.
   Requires overriding the ability's origin point in the casting system.

2. **Mind control / forced ability use** (Lich Cloud of Deceit, Lord Syuul Do It for Me) --
   Force a target to use their own signature ability against a chosen target.
   Requires programmatic ability invocation on a hostile creature.

3. **Line-of-effect restriction** (Chimera Ashen Clouds "LoE only within 3 squares",
   Minotaur Bullseye) -- Limit a creature's line of effect to a radius.
   No existing modifier type restricts LoE distance.

4. **Phasing movement** (move through solid walls/terrain) -- Count Rhodar Slip,
   Demon Abyssal Jaunt. Movement through walls is engine-level collision.

5. **Ability-copying** (Bredbeddle Envious Imitation) -- Copy and use an enemy's
   ranged strike. Requires reading another creature's ability list and invoking it.

6. **Dynamic potency scaling per use** (Chimera Ashen Clouds, Manticore Uncanny Mimicry) --
   Potency gate value that increases each time the ability is used. Needs a use counter
   that modifies the potency formula.

7. **Expanding map-edge zones** (Omen Dragon Burn It Right Down) -- Fire zone that grows
   inward from map edges each round. The `grow` field on auras expands outward from
   a center point, not inward from edges.

8. **Per-square-of-movement-through damage** with dynamic distance (Bugbear Grab Iron Ball,
   Grab Javelin) -- Damage that scales with throwing distance. The `movedamage` field
   on auras handles per-square damage within a zone, but not projectile distance scaling.

9. **Ally action grants** (Valok I Was Not Commanded to Wait, Devil Underhanded Tactics) --
   Grant individual allies a triggered end-of-turn action for the rest of the round.
   The "each ally gets an end-of-turn action" pattern differs from the existing
   "all allies act now" pattern.
