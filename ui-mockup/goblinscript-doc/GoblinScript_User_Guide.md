# GoblinScript: Writing Formulas

GoblinScript is the little formula language you type into DMHub's formula boxes. If you have ever written `=B2*2` in a spreadsheet, you already know most of it.

Most of the time you will not need it. The block editors let you pick common tests from a menu. When the menu does not have what you want, choose **Type a formula instead** and write it yourself. This page shows you how.

## Contents

- [What a formula is](#what-a-formula-is)
- [Where you will type one](#where-you-will-type-one)
- [Copy-paste examples](#copy-paste-examples)
- [Who is who](#who-is-who)
- [Numbers and math](#numbers-and-math)
- [Comparing values](#comparing-values)
- [Combining tests with and or not](#combining-tests-with-and-or-not)
- [Choosing a value with when and else](#choosing-a-value-with-when-and-else)
- [Text conditions and keywords](#text-conditions-and-keywords)
- [Dice](#dice)
- [Showing a formula in card text](#showing-a-formula-in-card-text)
- [Common mistakes](#common-mistakes)
- [Reference: creature fields](#reference-creature-fields)
- [Reference: ability fields](#reference-ability-fields)
- [Reference: cast fields](#reference-cast-fields)
- [Reference: functions](#reference-functions)

## What a formula is

A formula is one line that works out a single answer from the current game. The answer is one of these:

- **A number**, such as the damage an ability deals: `2 + Might`.
- **Yes or no**, such as "is the target winded?": `Target.Winded`.
- **Text**, such as a creature's role: `Role`.

A formula only reads the game. It never changes anything by itself. The ability or modifier the box belongs to decides what to do with the answer.

## Where you will type one

Formula boxes come in two main kinds.

**Boxes that want a number.** Damage, healing, a bonus, a quantity, a cost, a number of targets. Their labels are things like *Roll*, *Value*, *Quantity* or *Damage Modifier*. Boxes that roll (damage and healing) also accept [dice](#dice).

**Boxes that want yes or no.** These decide whether something happens or who it affects. Their labels are things like *Target Filter*, *Activation Condition*, *Display Condition*, *Prerequisite* or *Condition*. Any number above 0 counts as yes. Zero or less counts as no.

Some text boxes, such as an ability's *Description* or *Effect*, can also show a formula's result inside the words. See [Showing a formula in card text](#showing-a-formula-in-card-text).

## Copy-paste examples

These do real Draw Steel things. Copy one, then change the names and numbers.

**Deal 2 + Might damage.** In a damage box:

```
2 + Might
```

**Only if the target is winded.** In a condition box:

```
Target.Winded
```

**Only affect enemies.** In a target filter:

```
not Friends(Caster, Target)
```

**Only once you have 3 Victories.** In a condition or prerequisite box:

```
Victories >= 3
```

**Gain an edge when the target is concealed.** In the condition box of a power roll modifier that grants an edge:

```
Target.Concealed
```

**Extra damage when the ability has the Strike keyword.** In the condition box of a damage bonus modifier:

```
Ability.Keywords has "Strike"
```

A few more you will reach for often:

| You want | Type |
|---|---|
| Your usual power roll | `2d10 + HighestCharacteristic` |
| Damage that grows at level 4 | `3 + (1 when Level >= 4)` |
| Only if the target is grabbed | `Target.Conditions has "Grabbed"` |
| Only if an enemy is adjacent to you | `CountNearbyEnemies(1) >= 1` |
| Only on a tier 3 result | `Cast.Tier = 3` |
| Half the damage you just dealt, rounded down | `Cast.DamageDealt / 2` |
| Only on your own turn | `YourTurn` |
| Only during the first round of combat | `CombatRound = 1` |
| Only if the Director has 2 or more Malice | `Malice >= 2` |
| Only if the target is not a leader or solo | `not (Target.Leader or Target.Solo)` |

## Who is who

Every formula is worked out *from someone's point of view*. That someone is called **Self**, and the cards call them **you**.

You can leave Self out. `Stamina` means "your Stamina" and is exactly the same as `Self.Stamina`. To read someone else's value, put their name and a dot in front: `Target.Stamina`.

| Name | Who or what it is |
|---|---|
| `Self` | You: the creature that owns the ability, modifier or aura. This is the default, so you rarely type it. |
| `Caster` | The creature using the ability right now. Usually the same creature as Self. |
| `Target` | The creature being targeted or affected. A target filter is checked once for each creature in the area, with Target set to each one in turn. |
| `Attacker` | The creature attacking you, in triggers that react to being attacked or damaged. |
| `Subject` | In a triggered ability, the creature the trigger watches (for example "an ally" or "an enemy"). When the trigger watches you, Subject is you. |
| `Ability` | The ability this formula belongs to. Use it to ask about keywords, costs and so on. |
| `UsedAbility` | In "when a creature uses an ability" triggers, the ability that was just used. |
| `Cast` | This one use of the ability: the power roll, the tier, the damage dealt, who was targeted. |
| `Aura` | Inside an aura's formulas, the aura itself. `Aura.Caster` is the creature projecting it. |
| `Path` | Inside movement formulas, the move being made (how far, whether it is a shift or forced). |

**Which names exist depends on the box you are typing in.** A target filter knows about Target and Caster. A damage box on an ability knows about Cast and Ability. A plain prerequisite on a feature may only know about Self. If a name does not belong in that box, the formula will not work. When in doubt, stick to Self, then add others only where the box is clearly about them.

All creatures share the same set of fields. Anything you can ask about yourself you can also ask about Target, Caster, Attacker or Subject.

## Numbers and math

Use the usual symbols:

| Symbol | Meaning | Example |
|---|---|---|
| `+` | add | `2 + Might` |
| `-` | subtract | `MaximumStamina - Stamina` |
| `*` | multiply | `Might * 2` |
| `/` | divide, rounded down | `Stamina / 2` |
| `( )` | do this part first | `(Level + 1) * 2` |

A minus sign in front flips a number: `-Might`.

Division always rounds down. `7 / 2` is `3`.

You can also use [min, max, floor and ceiling](#reference-functions) to cap or round a value. For example, `min(Victories, 3)` never goes above 3.

## Comparing values

A comparison gives yes or no.

| Symbol | Meaning | Example |
|---|---|---|
| `=` | equal to | `CombatRound = 1` |
| `~=` or `!=` or `<>` | not equal to | `Level ~= 1` |
| `>` | greater than | `Victories > 0` |
| `<` | less than | `Cast.TargetCount < 2` |
| `>=` | greater than or equal to | `Victories >= 3` |
| `<=` | less than or equal to | `Stamina <= MaximumStamina / 2` |

When you compare text, capitals and spaces are ignored. `Role = "artillery"` matches a creature whose role is *Artillery*.

## Combining tests with and or not

- `and`: both tests must pass. `Target.Winded and Victories >= 3`
- `or`: at least one test must pass. `Target.Leader or Target.Solo`
- `not`: flips the test. `not Target.Minion`

When you mix `and` with `or`, always use brackets to say what you mean:

```
Target.Winded and (Target.Leader or Target.Solo)
```

Put brackets after `not` when it should cover more than one test:

```
not (Target.Leader or Target.Solo)
```

## Choosing a value with when and else

`when` gives a value only if a test passes. If the test fails, you get 0.

```
5 when Target.Flanked
```

Add `else` to choose a different value when the test fails:

```
3 when Cast.Tier = 3 else 1
```

This is how you add a bonus on top of a base number. Put the bonus in brackets:

```
1 + (1 when Level >= 4) + (1 when Level >= 7)
```

You can chain choices. Brackets keep them readable:

```
(2 + Might) when Level >= 7 else (1 + Might)
```

## Text conditions and keywords

Text always goes inside double quotes: `"Grabbed"`, `"Strike"`, `"Undead"`.

Use `has` to check whether a list contains something, or whether text contains a word:

| You want | Type |
|---|---|
| The target is grabbed | `Target.Conditions has "Grabbed"` |
| You are under an ongoing effect | `OngoingEffects has "Heart of the Wode"` |
| The ability is a Strike | `Ability.Keywords has "Strike"` |
| The ability is magic or psionic | `Ability.Keywords has "Magic" or Ability.Keywords has "Psionic"` |
| The target has a creature keyword | `Target.Keywords has "Troll"` |
| You have a complication | `Complications has "Primordial Sickness"` |

Use `has not` for the opposite: `Target.Conditions has not "Prone"`. You can also write `not (Target.Conditions has "Prone")`.

Use `is` and `is not` to check that text matches exactly: `Target.Role is "Brute"`, `Target.Type is not "Undead"`. Capitals and spaces are ignored here too.

For text, `has` matches part of the text. `Target.Keywords has "Goblin"` is yes for any creature whose keywords include the word Goblin.

## Dice

Dice only work in boxes that roll, such as damage and healing. Tests and filters cannot roll dice.

Write dice as *count* `d` *sides*, then add numbers or fields:

```
2d10 + HighestCharacteristic
```

| Type | Meaning |
|---|---|
| `2d6` | roll two six-sided dice and add them |
| `1d6 + Might` | add a number or field to the roll |
| `4d6 keep 3` | keep the highest 3 (short form `4d6k3`) |
| `4d6 drop 1` | drop the lowest 1 |
| `4d6 keep low 3` | keep the lowest 3 (short form `4d6kl3`) |
| `3d6 reroll 2` | reroll any die showing 2 or less, once |
| `2d10 minroll 4` | any die below 4 counts as 4 |
| `2d6 exploding` | a die that rolls its highest face is rolled again and added |

## Showing a formula in card text

In text boxes such as *Description* or *Effect*, put a formula in curly brackets and the card shows its result:

```
The target can shift {Reason} squares.
```

Add a `|` and some words to show those words when the number cannot be worked out, for example on a card that is not on the map yet:

```
The target can shift {Reason|a number of squares equal to your Reason score}.
```

## Common mistakes

**Spaces and capitals in names.** GoblinScript ignores both. `MaximumStamina`, `Maximum Stamina` and `maximumstamina` all mean the same thing. Prefer writing names without spaces. A name that contains a word like *has*, *is*, *not*, *and*, *or*, *when* or *else* breaks when you add spaces: `Has Cover` is read as the word *has* followed by *Cover*. Write `HasCover` instead.

**Forgetting quotes around text.** `Conditions has Grabbed` treats *Grabbed* as the name of a field, not the word. Write `Conditions has "Grabbed"`.

**Using `==`.** A single `=` checks equality. For text you can also use `is`.

**Adding inside a comparison.** `+` and `-` are worked out *after* comparisons. `Stamina - 5 > 0` does not mean what it looks like. Bracket the math: `(Stamina - 5) > 0`. Multiply and divide are fine: `Stamina <= MaximumStamina / 2` works as written.

**Adding next to `when`.** `when` only grabs the part after the last `+` or `-`. `2 + 3 when Target.Winded` gives 2, or 5 if the target is winded. If you want all of it to depend on the test, bracket it: `(2 + 3) when Target.Winded`. When unsure, add brackets.

**Mixing `and` with `or` without brackets.** GoblinScript does not give `and` priority over `or` the way some tools do. Bracket the group you mean.

**Yes and no are 1 and 0.** A yes counts as 1 and a no as 0. So `Target.Winded = 1` and `Target.Winded` mean the same thing. You can even add them: `2 + Target.Winded` is 3 against a winded target.

**Zero is no.** In a yes-or-no box, any number at or below 0 is no. `Victories` alone means "has at least one Victory".

**`or` between two numbers gives the larger one.** `Might or Agility` is whichever is higher. This works, but `max(Might, Agility)` is clearer.

**Dice in a test box.** Filters and conditions cannot roll. Use dice only in damage, healing and other roll boxes.

**A name the box does not know.** If you use `Cast` or `Target` in a box that has no cast or target, the formula will not work. See [Who is who](#who-is-who).

## Reference: creature fields

Use these on yourself (`Stamina`), or on another creature with a dot (`Target.Stamina`, `Caster.Level`, `Attacker.Minion`). Yes-or-no fields give 1 or 0.

### Stamina and health

| Field | Meaning |
|---|---|
| `Stamina` | Current Stamina. |
| `MaximumStamina` | Maximum Stamina. |
| `TemporaryStamina` | Current temporary Stamina. |
| `Winded` | Yes if Stamina is at or below half of maximum. |
| `Dying` | Yes if the creature is dying. |
| `Dead` | Yes if the creature is dead. |
| `RecoveryValue` | How much Stamina one Recovery restores. |
| `RecoveriesAvailableToSpend` | Recoveries left. |

### Level, characteristics and potency

| Field | Meaning |
|---|---|
| `Level` | Creature level. |
| `Might`, `Agility`, `Reason`, `Intuition`, `Presence` | That characteristic score. |
| `HighestCharacteristic` | The highest of the five. |
| `Weak`, `Average`, `Strong` | This creature's potency values for its abilities. |
| `PassesPotency("M", 2)` | Yes if this creature's characteristic (by first letter: M, A, R, I, P) is at or above the potency. Usually `Target.PassesPotency("M", Caster.Strong)`. |
| `PowerRollBonus` | Bonus to power rolls. |

### Heroic resources, Victories and Malice

| Field | Meaning |
|---|---|
| `Victories` | The hero's Victories. 0 for creatures that are not heroes. |
| `HeroicResourcesAvailableToSpend` | Heroic resource the creature can spend right now. |
| `HeroicResourcesThisTurn` | The most heroic resource the creature has held at any point this turn. It does not drop when spent, until next turn. |
| `HeroTokens` | Hero tokens the party has available. |
| `Malice` | Malice the Director has available. |
| `Resources.Surges` | How much of a named resource the creature has, such as `Resources.Surges` or `Resources.Recovery`. |

### Conditions and effects

| Field | Meaning |
|---|---|
| `Conditions` | The creature's conditions. Use `has`: `Conditions has "Frightened"`. |
| `OngoingEffects` | Names of ongoing effects on the creature. Use `has`. |
| `Stacks("Name")` | How many stacks of a named condition or effect the creature has. |
| `ConditionCount` | How many different conditions the creature has. |
| `SaveEndsEffects` | How many save-ends effects are on the creature. |
| `ConditionImmunities` | Conditions the creature is immune to. Use `has`. |
| `ConditionCaster("Grabbed")` | The creature that applied the named condition. |
| `AurasAffecting` | Names of auras affecting the creature. Use `has`. |

### Combat and position

| Field | Meaning |
|---|---|
| `YourTurn` | Yes if it is this creature's turn. |
| `CombatRound` | Current round. 0 outside combat. |
| `FirstTurnOfEncounter` | Yes if it is this creature's turn and the first turn of the combat encounter. |
| `GameMode` | Text such as "Combat" or "Respite". |
| `Flanked` | Yes if the creature is flanked. |
| `Concealed` | Yes if the creature is concealed. |
| `HasCover` | Yes if the creature has cover. |
| `Charging` | Yes while charging. |
| `HiddenThisTurn` | Yes if the creature was hidden this turn. |
| `MovedThisTurn` | Squares moved this turn. |
| `Mounted` | Yes if riding a mount. |
| `NumberOfCreaturesGrabbed` | How many creatures this creature is grabbing. |

### Size and movement

| Field | Meaning |
|---|---|
| `Size` | Size as a number: 1 Tiny (1T), 2 Small (1S), 3 Medium (1M), 4 Large (1L), 5 for size 2, 6 for size 3, and so on. |
| `Reach` | Reach in squares. |
| `WalkingSpeed` | Walking speed in squares. |
| `FlyingSpeed` | Flying speed. 0 if it cannot fly. |
| `BurrowingSpeed` | Burrowing speed. 0 if it cannot burrow. |
| `MovementSpeed` | Total movement per round. |
| `Altitude` | Squares above the ground. |

### What kind of creature

| Field | Meaning |
|---|---|
| `Hero` | Yes for a hero. |
| `Minion`, `Captain`, `Leader`, `Solo` | Yes if the creature has that role. |
| `Role` | Role as text: "Artillery", "Brute" and so on. |
| `Type` | Creature type as text. |
| `Keywords` | Creature keywords. Use `has`. |
| `Name` | The monster's name (monsters only). |
| `Object` | Yes for an object. |
| `Retainer` | Yes for a retainer. |
| `Summoned` | Yes if the creature was summoned. `Summoner` is the creature that summoned it. |
| `Kit` | Name of the equipped kit. |
| `Complications` | The hero's complications. Use `has`. |
| `FreeStrikeDamage` | A monster's free strike damage. |
| `EV` | A monster's encounter value. |

Any custom attribute set up in the compendium, such as `CriticalThreshold`, can also be used by name.

## Reference: ability fields

Use these with `Ability.` (the ability this formula belongs to) or `UsedAbility.` (the ability that set off a trigger).

| Field | Meaning |
|---|---|
| `Name` | The ability's name. |
| `Keywords` | Its keywords. Use `has`: `Ability.Keywords has "Melee"`. |
| `Distance` | Its distance as shown on the card, such as "Melee 1" or "Ranged 10". |
| `Categorization` | Text such as "Signature Ability" or "Heroic Ability". |
| `Heroic` | Yes for a heroic ability. |
| `HeroicResourceCost` | Its heroic resource cost. 0 if none. |
| `MaliceCost` | Its Malice cost. 0 if none. |
| `Action` | Yes if it uses an action. |
| `Maneuver` | Yes if it is a maneuver. |
| `Trigger` | Yes if it is a triggered action. |
| `FreeStrike` | Yes if it is a free strike. |
| `HasAttack` | Yes if it includes a power roll. |
| `DoesDamage` | Yes if it deals damage. |
| `HasHeal` | Yes if it heals. |
| `HasForcedMovement` | Yes if it includes forced movement. |
| `HasPotency` | Yes if it has a potency effect. |
| `NumberOfTargets` | The most creatures it can target. |
| `Level` | The level at which it is gained. |

## Reference: cast fields

Use these with `Cast.` while an ability is being resolved: after the power roll and while its effects apply.

| Field | Meaning |
|---|---|
| `Tier` | The power roll's tier: 1, 2 or 3. |
| `TierForTarget(Target)` | The tier against one target. |
| `Roll` | The power roll total with all bonuses. |
| `NaturalRoll` | The dice total before any bonuses. |
| `HighRoll`, `LowRoll` | The higher and lower of the two d10s. |
| `Edges`, `Banes` | How many edges or banes were applied. |
| `TargetCount` | How many creatures are targeted. |
| `PrimaryTarget` | The first target. Use with a dot: `Cast.PrimaryTarget.Stamina`. |
| `HasTarget(Target)` | Yes if that creature is one of the targets. |
| `DamageDealt` | Total damage dealt so far by this use. |
| `DamageDealtAgainst(Target)` | Damage dealt to one creature. |
| `Kills` | Creatures killed so far. Each minion counts as one. |
| `Killed(Target)` | Yes if this ability's damage killed that creature. |
| `Healing` | Total healing done. |
| `SpacesMoved` | Squares moved during the ability. |
| `ForcedMovementDistance` | Total squares of forced movement caused. |
| `ForcedMovementCollision` | Yes if forced movement caused a collision. |
| `PassesPotency(Target, "M")` | Yes if the target resists the potency for this tier. Add a third value to name the potency: `Cast.PassesPotency(Target, "M", "Strong")`. |

## Reference: functions

Functions take values in brackets, separated by commas.

| Function | Meaning | Example |
|---|---|---|
| `min(a, b)` | The smaller value. | `min(Victories, 3)` |
| `max(a, b)` | The larger value. | `max(Might, Agility)` |
| `floor(x)` | Round down. | `floor(Cast.DamageDealt / 2)` |
| `ceiling(x)` | Round up. | `ceiling(Cast.DamageDealt * 0.5)` |
| `Friends(a, b)` | Yes if both creatures are on the same side. | `not Friends(Caster, Target)` for enemies |
| `Distance(creature)` | Squares from this creature to another. | `Target.Distance(Caster) <= 1` |
| `CountNearbyEnemies(n)` | Living enemies within n squares. | `CountNearbyEnemies(1) >= 2` |
| `CountNearbyFriends(n)` | Living allies within n squares. | `CountNearbyFriends(5) > 0` |
| `CountNearbyCreatures(n)` | All living creatures within n squares. | `CountNearbyCreatures(3)` |
| `LineOfSight(a, b)` | 1 for a clear view, 0.5 for half cover, 0.25 for three-quarter cover, 0 for blocked. | `LineOfSight(Self, Target) < 1` |
| `Stacks("Name")` | Stacks of a named condition or effect. | `Stacks("Essence Transfer") > 0` |
| `Substring(text, word)` | Yes if the word appears in the text. | `Substring(Target.Name, "Goblin")` |
