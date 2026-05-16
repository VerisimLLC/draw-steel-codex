# GoblinScript Symbols Catalog (auto-generated from source)

Authoritative listing of every GoblinScript symbol I could find by grepping
`RegisterSymbol`, `RegisterGoblinScriptField`, `RegisterGoblinScriptSymbol`,
and `helpSymbols` definitions across the codex. Each entry cites the source
`file:line` of the registration. Symbol names are case-insensitive and
space-insensitive at lookup time (the lexer merges adjacent identifier
tokens; lookup normalizes to `tolower()` + remove spaces).

When a symbol returns a function, calling it is `Subject.SymbolName(args)`.

The C# parser file `Goblinscript.cs` (asked for) was at
`D:/dev/dmhub/Assets/Scripts/GoblinScript.cs`.

---

## Table of Contents

- [Owner: creature / character / monster](#owner-creature--character--monster)
- [Owner: ActivatedAbility (`Ability.X`)](#owner-activatedability-abilityx)
- [Owner: ActivatedAbilityCast (`Cast.X`)](#owner-activatedabilitycast-castx)
- [Owner: Attack (`Attack.X`)](#owner-attack-attackx)
- [Owner: equipment / weapon (`Armor.X`, `Weapon.X`)](#owner-equipment--weapon-armorx-weaponx)
- [Owner: Kit (`Kit.X`)](#owner-kit-kitx)
- [Owner: PathMoved (`Path.X`)](#owner-pathmoved-pathx)
- [Owner: Loc (`Loc.X`)](#owner-loc-locx)
- [Owner: AuraInstance (`Aura.X`)](#owner-aurainstance-aurax)
- [Owner: CharacterOngoingEffectInstance](#owner-characterongoingeffectinstance)
- [Owner: CharacterResourceCollection (`Resources.X`)](#owner-characterresourcecollection-resourcesx)
- [Owner: Deity (`Deity.X`)](#owner-deity-deityx)
- [Owner: trigger (`Trigger.X`)](#owner-trigger-triggerx)
- [Built-in functions (no owner)](#built-in-functions-no-owner)
- [Dynamic registrations](#dynamic-registrations)

---

## Owner: creature / character / monster

The `creature` lookup-symbols table is shared with `character` and `monster`
via `RegisterSymbol` and direct `lookupSymbols[k] = ...` assignment. Anything
listed here is reachable on `Self`, `Caster`, `Target`, `Summoner`,
`Triggerer`, `Last Caster`, etc.

The `helpSymbols` table at `Creature.lua:6887-7453` is the static base. The
`RegisterSymbol` calls listed below extend it.

### Identity / Role

| Symbol | Type | Source (file:line) | Notes |
|---|---|---|---|
| `Self` | creature | `Creature.lua:6891`, `lookup 7566` | The current creature. |
| `Name` | text | `Creature.lua:6897`, `lookup 7595` | Monster type string (e.g. "Goblin Warrior"). Empty for heroes that have no monster_type. |
| `Short Name` | text | `MCDMCreature.lua:5102` | `Name` with the band/keyword prefix stripped (e.g. "Warrior" instead of "Goblin Warrior"). |
| `ID` | text | `Creature.lua:6905`, `lookup 7578` | Unique stable hash, not human-readable. |
| `Type` | text | `Creature.lua:6911`, `lookup 7599` -> `RaceOrMonsterType()`. |
| `Subtype` | text | `Creature.lua:6919`, `lookup 7603`. | Empty if none. |
| `Role` | string | `MCDMCreature.lua:4928` | Calls `c:Role()`. Returns "hero" for characters, monster role for monsters, "none" for objects. |
| `Hero` | boolean | `MCDMCreature.lua:1179` | `c:IsHero()`, true for `character`. |
| `Object` | boolean | `MCDMCreature.lua:1097` | True if treatAsObject or token isObject. |
| `Player Allied` | boolean | `MCDMCreature.lua:1117` | True if player-controlled or in a player initiative entry. |
| `Minion` | boolean | `MCDMCreature.lua:1550` | |
| `Captain` | boolean | `MCDMCreature.lua:1537` | True for non-minions that have a `_tmp_minionSquad`. |
| `Solo` | boolean | `MCDMCreature.lua:1563` | role contains "solo". |
| `Leader` | boolean | `MCDMCreature.lua:1630` | role contains "leader". |
| `Retainer` | boolean | `MCDMCreature.lua:1219` | `c:IsRetainer()`. |
| `Mentor` | creature | `MCDMCreature.lua:1232` | A retainer's mentor; nil otherwise. |
| `Keywords` | set | `MCDMCreature.lua:4809` | `Self.Keywords has "Magic"`. Includes object component keywords if creature is an object. |
| `Subclasses` | set | `Creature.lua:7280` (helpSymbols only -- no lookup found `[UNVERIFIED]` -- if you depend on this, grep for the lookup; it may be missing) |

### Characteristics (Might / Agility / Reason / Intuition / Presence)

Registered dynamically via `creature.RegisterAttribute()` (at
`Creature.lua:818-855`). For each attribute in `MCDMRules.lua:199-228`
(Might, Agility, Reason, Intuition, Presence) two symbols are created: the
attribute name and `<Name> Modifier`.

| Symbol | Type | Source |
|---|---|---|
| `Might`, `Might Modifier` | number | `MCDMRules.lua:199` + `Creature.lua:818-839` |
| `Agility`, `Agility Modifier` | number | `MCDMRules.lua:206` |
| `Reason`, `Reason Modifier` | number | `MCDMRules.lua:212` |
| `Intuition`, `Intuition Modifier` | number | `MCDMRules.lua:218` |
| `Presence`, `Presence Modifier` | number | `MCDMRules.lua:224` |
| `Highest Characteristic` | number | `MCDMCreature.lua:1525` |
| `Weak` | number | `MCDMCreature.lua:1489` -- highest characteristic - 2 |
| `Average` | number | `MCDMCreature.lua:1501` -- highest characteristic - 1 |
| `Strong` | number | `MCDMCreature.lua:1513` -- highest characteristic |
| `Stability` | number | `MCDMRules.lua:601` `RegisterGoblinScriptSymbol` |

The internal attribute IDs `mgt`, `agl`, `rea`, `inu`, `prs` are also
registered (`Creature.lua:842-849`). So `mgt` and `Might` are the same
symbol.

### Stamina / Health / Resources

| Symbol | Type | Source |
|---|---|---|
| `Stamina` | number | `MCDMCreature.lua:2246` |
| `Maximum Stamina` | number | `MCDMCreature.lua:2259` |
| `Temporary Stamina` | number | `MCDMCreature.lua:2976` |
| `Recovery Value` | number | `MCDMCreature.lua:2233` |
| `Recoveries Available to Spend` | number | `MCDMCreature.lua:1380` -- accounts for sharing (Bloodbound). |
| `Maximum Recoveries` | number | `MCDMCreature.lua:1393` |
| `Heroic Resources Available to Spend` | number | `MCDMCreature.lua:1192` -- handles negative (Talent). |
| `Heroic Resources This Turn` | number | `MCDMCreature.lua:1206` -- high-water mark for the turn. |
| `Malice` | number | `MCDMCreature.lua:1166` -- director resource. |
| `HeroTokens` | number | `MCDMCreature.lua:1153` |
| `Power Roll Bonus` | number | `MCDMCreature.lua:3622` -- monsters only; 0 for heroes. |
| `Resources` | resources | `Creature.lua:7441`, `lookup 7667` -- collection; access fields with `Resources.<resource name>`. See [Resources owner section](#owner-characterresourcecollection-resourcesx). |
| `Dying` | boolean | `MCDMCreature.lua:1140` |
| `Dead` | boolean | `MCDMCreature.lua:1406` |
| `Hitpoints` (deprecated) | number | `Creature.lua:6975`, `lookup 7675` -- alias for Stamina via `CurrentHitpoints()`. |
| `Maximum Hitpoints` (deprecated) | number | `Creature.lua:6984`, `lookup 7679` |

**Not registered as symbols (verified by grep):** `Winded`, `Bloodied`,
`HP Threshold`. The methods `IsWinded()` and `BloodiedThreshold()` exist on
the creature object but are not exposed to GoblinScript. Use a derived
expression: `Stamina <= 0` for "winded" (winded means at or below 0
stamina), and `Stamina < Maximum Stamina/2` for bloodied. **`[FLAG]`** worth
adding `Winded` as a registered symbol for clarity -- see audit doc.

### Movement / Speed

Movement-type speeds are registered dynamically per `creature.movementTypeInfo`
entry (`Creature.lua:8290-8317`).

| Symbol | Type | Source |
|---|---|---|
| `Walking Speed`, `Swimming Speed`, `Flying Speed`, `Climbing Speed`, `Burrowing Speed`, `Teleporting Speed` | number | `Creature.lua:8290-8317` (one per `movementTypeInfo` entry) |
| `Movement Speed` | number | `Creature.lua:7429`, `lookup 7788` |
| `Moved This Turn` | number | `Creature.lua:7435`, `lookup 7792` -- in feet per `DistanceMovedThisTurnInFeet`. |
| `Charge Distance` | number | `Creature.lua:7135`, `lookup 7779` -- straight-line distance moved this turn. |
| `Movement Type` | text | `Creature.lua:7150`, `lookup 7801` -- "Walk", "Swim", "Fly", "Burrow", "Climb", "Teleport". |
| `Movement Multiplier` | number | `Creature.lua:7143`, `lookup 7797`. |
| `In Difficult Terrain` | boolean | `MCDMCreature.lua:2939` -- false if flying/burrowing or `IgnoreDifficultTerrain`. |
| `InWater` | boolean | `MCDMCreature.lua:4941` -- true if currentMoveType == "swim". |
| `OnGround` | boolean | `MCDMCreature.lua:4955` -- true unless flying, burrowing, or climbing. |
| `Mounted` | boolean | `Creature.lua:7389`, `lookup 8152` |
| `Mount` | creature | `Creature.lua:7395`, `lookup 8161` |
| `Routine Distance` | number | `DSModifyRoutine.lua:307` -- distance attribute of selected routine. |

### Position

| Symbol | Type | Source |
|---|---|---|
| `X` | number | `Creature.lua:6934`, `lookup 7616` |
| `Y` | number | `Creature.lua:6941`, `lookup 7624` |
| `Altitude` | number | `Creature.lua:6948`, `lookup 7632` -- in tiles, comparable across floors. |
| `Floor Altitude` | number | `Creature.lua:6955`, `lookup 7641` -- relative to current floor's ground. |
| `AltitudeInDeciTiles` | number | `Creature.lua:6927`, `lookup 7607` -- 1/10 tile precision. |
| `Distance Below Ground` | number | `Creature.lua:6962`, `lookup 7650` |
| `Height` | number | `Creature.lua:6969`, `lookup 7658` -- character stature in tiles. |
| `Size` | number | `Creature.lua:7165`, `lookup 7809` -- 1=1T..8=size 5. |
| `Tile Size` | number | `Creature.lua:7173`, `lookup 7813` -- tiles occupied (e.g. 2 for a Large creature). |
| `SizeWhenForceMoved` | number | `MCDMCreature.lua:2107` |
| `Reach` | number | `MCDMCreature.lua:2191` |

### Combat status

| Symbol | Type | Source |
|---|---|---|
| `Your Turn` | boolean | `Creature.lua:7180`, `lookup 7829` |
| `Taken Turn` | boolean | `MCDMCreature.lua:4863` -- true outside combat. |
| `Taken Turn This Round` | boolean | `MCDMCreature.lua:1448` |
| `Turn Being Chosen` | boolean | `MCDMCreature.lua:4891` |
| `Combat Round` | number | `Creature.lua:7375`, `lookup 8269` -- 0 if not in combat, otherwise 1-indexed. |
| `End Turn Timestamp` | number | `MCDMCreature.lua:3010` |
| `Game Mode` | string | `MCDMCreature.lua:4845` -- "exploration", "combat", "respite", "downtime". |
| `Hidden This Turn` | boolean | `Creature.lua:7401`, `lookup 8170` |
| `Concealed` | boolean | `MCDMCreature.lua:2927` -- reads `_tmp_concealed` (the cached check from `IsConcealed()`). |
| `Flanked` | boolean | `MCDMCreature.lua:1685` |
| `Flanked By` | function | `MCDMCreature.lua:1643` -- `Flanked By(creatureA)` or `Flanked By(creatureA, creatureB)` for co-flanking check. |
| `Has Adjacent Enemy Other Than Us` | function | `MCDMRules.lua:554` -- `Target.Has Adjacent Enemy Other Than Us(Self)`. |
| `Is Friend` | function | `MCDMRules.lua:582` -- `Target.IsFriend(Self)`. (Equivalent to `Friends(Target, Self)`.) |
| `Number of Creatures Grabbed` | number | `Creature.lua:7448`, `lookup 7671` |
| `Save Ends Effects` | boolean | `MCDMCreature.lua:1576` |
| `EoT Effects` | boolean | `MCDMCreature.lua:1603` |
| `Last Caster` | creature | `Creature.lua:7423`, `lookup 8185` |
| `Last Damaged By` | function | `MCDMCreature.lua:2990` -- `Last Damaged By("Fire")` returns timestamp. |
| `Immunities` | function | `MCDMCreature.lua:1699` -- `Immunities("Fire")` returns total damage modifier (negative for weakness). |

### Conditions / ongoing effects

| Symbol | Type | Source |
|---|---|---|
| `Conditions` | set | `Creature.lua:7316`, `lookup 7964` -- includes inflictedConditions and bestowed conditions. Use `has`. |
| `Ongoing Effects` | set | `Creature.lua:7323`, `lookup 8020` |
| `Stacks` | function | `Creature.lua:7330`, `lookup 8037` -- `Stacks("Bleeding")`. |
| `Condition Stacks` | function | `MCDMCreature.lua:3576` -- like Stacks but checks inflictedConditions first, then ongoing effects. |
| `Condition Count` | number | `MCDMCreature.lua:3023` -- distinct conditions only. |
| `Effects Count` | number | `MCDMCreature.lua:3069` -- conditions plus ongoing effects (no underlying condition). |
| `Effect Caster` | function | `MCDMCreature.lua:3519` -- `Effect Caster("Carefully Observed", Caster)` -> boolean (stacks > 0 from that caster). |
| `ConditionCaster` | function | `Creature.lua:7298`, `lookup 7922` -- returns the creature symbols. |
| `CasterSet` | function | `Creature.lua:7337`, `lookup 8054` -- returns CreatureSet of all casters of an ongoing effect on this creature. |
| `Condition Immunities` | set | `Creature.lua:7368`, `lookup 8252` |
| `Complications` | set | `MCDMSymbols.lua:53` (and re-registered at `MCDMCreature.lua:5054`). Both definitions read `complications` via `c:Complications()`/the table; **two registrations exist**, the later one wins. |

### Auras / Squad / Summon

| Symbol | Type | Source |
|---|---|---|
| `Auras Affecting` | set | `MCDMCreature.lua:2134` |
| `AurasCaster` | function | `MCDMCreature.lua:2162` -- `AurasCaster("Aura Name")`. |
| `HasCaptain` | boolean | `MCDMCreature.lua:1419` |
| `Squad Captain` | creature | `MCDMCreature.lua:1433` |
| `Summoned` | boolean | `Creature.lua:7286`, `lookup 7858` |
| `Summoner` | creature | `Creature.lua:7292`, `lookup 7868` -- only valid if Summoned. |
| `SquadCaster` | function | `Creature.lua:7304`, `lookup 7887` |
| `SquadLiveMembers` | function | `Creature.lua:7310`, `lookup 7911` |
| `BoundCreatures` | function | `MCDMCreature.lua:4970` -- `BoundCreatures("Bloodbound")`. |
| `BoundOngoingEffect` | function | `MCDMCreature.lua:5011` -- `BoundOngoingEffect(Target, "Bloodbound")` -> boolean. |
| `Persistent Abilities` | set | `AbilityPersistentCast.lua:23` -- names of currently-active persistent abilities. |
| `Number of Persistent Abilities` | number | `AbilityPersistentCast.lua:12` |

### Functions / Counters

| Symbol | Type | Source |
|---|---|---|
| `Distance` | function | `Creature.lua:7188`, `lookup 7833` -- `Distance(Target)` in squares. |
| `Count Nearby Enemies` | function | `Creature.lua:7195`, `lookup 7846` -- accepts distance + filter args (group names, feature names, creatures-to-exclude). |
| `Count Nearby Friends` | function | `Creature.lua:7202`, `lookup 7850` |
| `Count Nearby Creatures` | function | `Creature.lua:7209`, `lookup 7854` -- `"ally"` and `"enemy"` work as filter args. |
| `Count Riders` | function | `Creature.lua:7216`, `lookup 7856` |
| `AdjacentAlliesWithFeature` | function | `MCDMSymbols.lua:3` -- `AdjacentAlliesWithFeature("FeatureName")` -> count. |
| `Passes Potency` | function | `MCDMCreature.lua:1466` -- `Passes Potency("M", 5)`; `M`/`A`/`R`/`I`/`P` first letter. |
| `Dueling` | boolean | `MCDMRules.lua:541` -- one weapon, not two-handed. (Mostly D&D-era; minimal use in DS.) |

### Languages / Misc

| Symbol | Type | Source |
|---|---|---|
| `Languages` | set | `Creature.lua:7382`, `lookup 8136` |
| `Num Dead Languages` | number | `MCDMCreature.lua:1245` |
| `Dead Languages` | set | `MCDMCreature.lua:1268` |
| `Magic Treasure Count` | number | `MCDMCreature.lua:1295` |
| `NumberOfPlayers` | number | `MCDMCreature.lua:5080` |
| `Victories` | number | `MCDMSymbols.lua:39` |
| `Kit` | kit | `MCDMKit.lua:1165` |
| `Always` | number | `Creature.lua:lookup 7587` (no helpSymbols entry -- only in lookupSymbols) |
| `Never` | number | `Creature.lua:lookup 7591` (no helpSymbols entry) |
| `debuginfo` | text | `Creature.lua:lookup 7570` -- diagnostic only. |
| `datatype` | string | `Creature.lua:lookup 7574` -- returns `"creature"`. Used by GoblinScript for type checks. |

### Dynamic per-class / per-resource symbols

- **`<ClassName> Level`** -- `Class.lua:1209` -- one per non-hidden class
  table entry. `Tactician Level`, `Censor Level`, etc.
- **Custom attributes** -- `CustomAttribute.lua:937-952` -- every attribute
  in `tables/customattributes/_table.yaml` becomes a creature symbol. See
  `GOBLINSCRIPT-SYMBOLS.md#custom-attributes-from-_tableyaml` for the full
  list (~70 entries). Examples: `Push Bonus`, `Recovery Value`, `Critical
  Threshold`, `Strained`, `Charging Speed`, etc.

### Deprecated / D&D leftovers (kept for compat)

These are still registered but marked `deprecated = true` in helpSymbols
(`Creature.lua:6975-7177`). Mostly unused in DS content.

`Hitpoints`, `Maximum Hitpoints`, `Weapons Wielded`, `Two Handed`, `Has
Main Hand Item`, `Has Off Hand Item`, `Main Hand Item`, `Off Hand Item`,
`Has Shield`, `Shield`, `Shield Bonus`, `Has Armor`, `Armor`, `Armor
Class`, `Proficiency Bonus`, `Proficiency Modifier`, `Spell Save DC`,
`Spellcasting Ability Modifier`, `Spellcasting Classes`, `Multiclass`,
`Inventory Weight`, `Proficient`, `Skill Modifier`, `Save Modifier`,
`Ongoing DC`, `Passive`.

### Monster-only

Registered on `monster` only via `monster.RegisterSymbol`. They will
return 0 for heroes.

| Symbol | Type | Source |
|---|---|---|
| `Free Strike Damage` | number | `MCDMMonster.lua:817` |
| `Free Strike Range` | number | `MCDMMonster.lua:834` |
| `EV` | number | `MCDMMonster.lua:851` |

---

## Owner: ActivatedAbility (`Ability.X`)

The base helpSymbols + lookupSymbols at `ActivatedAbility.lua:5030-5202` and
`5229-5353`. Extensions registered via `GameSystem.RegisterGoblinScriptField{
target = ActivatedAbility, ... }` propagate via
`RegisterGoblinScriptSymbol` (`Creature.lua:747-766`).

| Symbol | Type | Source | Notes |
|---|---|---|---|
| `Self` | ability | `ActivatedAbility.lua:5067` | Returns `c` (the ability). |
| `Name` | text | `ActivatedAbility.lua:5234`, `lookup 5039` |
| `Action` | text | `ActivatedAbility.lua:5241`, `lookup 5052` -- the resource name (e.g. "Standard Action"). |
| `Spell` | boolean | `ActivatedAbility.lua:5248`, `lookup 5071` |
| `Free Strike` | boolean | `ActivatedAbility.lua:5254`, `lookup 5079` -- categorization == "Basic Attack". |
| `Usable as Free Strike` | boolean | `ActivatedAbility.lua:5260`, `lookup 5083` |
| `Usable as Signature Ability` | boolean | `ActivatedAbility.lua:5266`, `lookup 5087` |
| `Remain Hidden` | boolean | `ActivatedAbility.lua:5272`, `lookup 5091` |
| `Level` | number | `ActivatedAbility.lua:5278`, `lookup 5075` |
| `Cantrip` | boolean | `lookup 5095` -- (no help entry; type = Spell at level 0) `[UNVERIFIED in helpSymbols]` |
| `School` | text | `lookup 5099` -- D&D leftover. |
| `Keywords` | set | `ActivatedAbility.lua:5284`, `lookup 5043`. **Re-registered** in DS at `MCDMActivatedAbility.lua:2826` -- the DS version wins because it loads later. |
| `Number of Targets` | number | `ActivatedAbility.lua:5291`, `lookup 5103` |
| `Range` | number | `ActivatedAbility.lua:5322`, `lookup 5108` |
| `Damage Types` | set | `ActivatedAbility.lua:5328`, `lookup 5112` |
| `Weapon Attack` | boolean | `ActivatedAbility.lua:5297`, `lookup 5116` |
| `Has Attack` | boolean | `ActivatedAbility.lua:5304`, `lookup 5128` |
| `Has Heal` | boolean | `ActivatedAbility.lua:5310`, `lookup 5132` |
| `Attack` | attack | `ActivatedAbility.lua:5316`, `lookup 5141` -- only valid if Has Attack. |
| `Inflicts` | function | `ActivatedAbility.lua:5335`, `lookup 5151` -- `Ability.Inflicts("Frightened")`. Scans tiers + DSCommand rules text. |
| `Power Roll Uses Might` | boolean | `ActivatedAbility.lua:5342`, `lookup 5182` |
| `Power Roll Uses Agility` | boolean | `ActivatedAbility.lua:5348`, `lookup 5193` |

### DS-specific extensions

| Symbol | Type | Source |
|---|---|---|
| `Maneuver` | boolean | `MCDMActivatedAbility.lua:2746` |
| `Trigger` | boolean | `MCDMActivatedAbility.lua:2758` -- has a `trigger` field. |
| `HeroicResourceCost` | number | `MCDMActivatedAbility.lua:2770` |
| `MaliceCost` | number | `MCDMActivatedAbility.lua:2786` |
| `Heroic` | boolean | `MCDMActivatedAbility.lua:2802` -- categorization == "Heroic Ability" + heroic resource cost. |
| `Categorization` | text | `MCDMActivatedAbility.lua:2814` |
| `Stolen` | boolean | `MCDMActivatedAbility.lua:2846` |
| `Test` | boolean | `MCDMActivatedAbility.lua:2858` -- contains a power roll that is a test. |
| `TestSkills` | set | `MCDMActivatedAbility.lua:2878` |

### Properties registered via `ActivatedAbility.RegisterProperty`

These bool properties become symbols via `MCDMActivatedAbility.lua:3127-3142`:

| Symbol | Source (RegisterProperty call) |
|---|---|
| `Use as Free Strike` | `MCDMActivatedAbility.lua:3148` |
| `Use as Signature Ability` | `MCDMActivatedAbility.lua:3154` |
| `Remain Hidden` (property variant) | `MCDMActivatedAbility.lua:3160` |
| `All Force Move From Caster` | `MCDMActivatedAbility.lua:3166` |
| (additional properties scattered through the file -- grep `RegisterProperty` for the full list) |

### Dynamic spell custom fields

`ActivatedAbility.lua:5359-5398` -- entries in
`tables/customfieldcollection/spells` register one number symbol each.

---

## Owner: ActivatedAbilityCast (`Cast.X`)

`Cast` is the running record of an in-progress ability cast. It is
mutated in real-time during evaluation. Most of these are only meaningful
inside `activationCondition` of a power-roll modifier, tier text, or
post-roll triggers.

helpSymbols block: `ActivatedAbilityCast.lua:56-262`. lookupSymbols:
`ActivatedAbilityCast.lua:264-498`. DS extensions added via
`RegisterGoblinScriptField` at `MCDMActivatedAbilityCast.lua:12-128`.

| Symbol | Type | Source | Notes |
|---|---|---|---|
| `Mode` | number | `ActivatedAbilityCast.lua:60`, `lookup 269` | Which mode the player picked. |
| `Memory` | function | `ActivatedAbilityCast.lua:66`, `lookup 273` | `memory("Damage at Start")`. |
| `First Target` | creature | `ActivatedAbilityCast.lua:73`, `lookup 285` |
| `OpportunityAttacksTriggered` | number | `ActivatedAbilityCast.lua:79`, `lookup 292` |
| `Heroic Resources Gained` | number | `ActivatedAbilityCast.lua:85`, `lookup 296` |
| `Number of Added Creatures` | number | `ActivatedAbilityCast.lua:92`, `lookup 300` -- by AbilityAddNewTargets etc. |
| `Creature List Size` | number | `ActivatedAbilityCast.lua:99`, `lookup 303` |
| `Damage Dealt` | number | `ActivatedAbilityCast.lua:106`, `lookup 332` |
| `Damage Raw` | number | `ActivatedAbilityCast.lua:113`, `lookup 337` |
| `Damage Dealt Against` | function | `ActivatedAbilityCast.lua:120`, `lookup 341` -- `Cast.Damage Dealt Against(Target)`. |
| `Damage Raw Against` | function | `ActivatedAbilityCast.lua:127`, `lookup 360` |
| `Natural Roll` | number | `ActivatedAbilityCast.lua:147`, `lookup 383` -- raw 2d10 sum. |
| `High Roll` | number | `ActivatedAbilityCast.lua:153`, `lookup 387` |
| `Low Roll` | number | `ActivatedAbilityCast.lua:159`, `lookup 391` |
| `Healing` | number | `ActivatedAbilityCast.lua:165`, `lookup 399` |
| `Heal Roll` | number | `ActivatedAbilityCast.lua:170`, `lookup 403` |
| `Ability` | ability | `ActivatedAbilityCast.lua:175`, `lookup 328` |
| `Roll` | number | `ActivatedAbilityCast.lua:180`, `lookup 407` -- only for "Roll Behavior" abilities. |
| `HasTarget` | function | `ActivatedAbilityCast.lua:185`, `lookup 307` -- `Cast.HasTarget(Self)`. |
| `Target Count` | number | `ActivatedAbilityCast.lua:190`, `lookup 426` -- **THIS IS** the answer to "number of targets in this cast". |
| `Spaces Moved` | number | `ActivatedAbilityCast.lua:195`, `lookup 437` -- relocate behaviors set this. Used by Beastheart's `Cast.Spaces Moved` formulas. |
| `Has Primary Target` | creature | `ActivatedAbilityCast.lua:200`, `lookup 411` |
| `Primary Target` | creature | `ActivatedAbilityCast.lua:205`, `lookup 415` |
| `Tier` | number | `ActivatedAbilityCast.lua:210`, `lookup 441` |
| `Tier for Target` | function | `ActivatedAbilityCast.lua:215`, `lookup 445` -- per-target tier when multiple. |
| `Inflicted Conditions` | boolean | `ActivatedAbilityCast.lua:220`, `lookup 460` -- ANY inflicted, not which. |
| `Purged Conditions` | number | `ActivatedAbilityCast.lua:225`, `lookup 464` |
| `Forced Movement Distance` | number | `ActivatedAbilityCast.lua:231`, `lookup 468` |
| `Forced Movement Collision` | boolean | `ActivatedAbilityCast.lua:237`, `lookup 478` |
| `Forced Movement Creature Count` | number | `ActivatedAbilityCast.lua:243`, `lookup 482` |
| `Forced Movement Damage Dealt` | number | `ActivatedAbilityCast.lua:249`, `lookup 491` |
| `Forced Movement Damage Dealt to Targets` | number | `ActivatedAbilityCast.lua:256`, `lookup 495` |

### DS extensions (`MCDMActivatedAbilityCast.lua`)

| Symbol | Type | Source |
|---|---|---|
| `Boons` | number | `MCDMActivatedAbilityCast.lua:12` -- edges applied. |
| `Banes` | number | `MCDMActivatedAbilityCast.lua:24` |
| `PassesPotency` | function | `MCDMActivatedAbilityCast.lua:36` -- `Cast.PassesPotency(Target, "M", "Strong")`. |
| `OngoingEffectsPurgedChosen` | table | `MCDMActivatedAbilityCast.lua:79` |
| `Has Rolled Damage` | boolean | `MCDMActivatedAbilityCast.lua:91` |
| `NumAttackers` | function | `MCDMActivatedAbilityCast.lua:103` -- `Cast.NumAttackers(Target)` for minion squads. |

### Common cast-context wrappers

The above only resolve when `Cast` is in the symbol scope. The casting
pipeline always injects:
- `cast` -> the ActivatedAbilityCast object
- `caster` -> creature
- `ability` -> ActivatedAbility
- `target` -> creature (during per-target evaluation)
- `mode`, `charges`, `upcast` -> numbers (when relevant)

See `GOBLINSCRIPT-CONTEXTS.md` for which fields inject which symbols.

---

## Owner: Attack (`Attack.X`)

helpSymbols at `Attack.lua:278-358`.

| Symbol | Type | Source |
|---|---|---|
| `Name` | text | `Attack.lua:281` |
| `Finesse` | boolean | `Attack.lua:286` |
| `Melee Range` | number | `Attack.lua:291` |
| `Melee` | boolean | `Attack.lua:298` |
| `Ranged` | boolean | `Attack.lua:304` |
| `Range` | number | `Attack.lua:310` |
| `Attribute` | text | `Attack.lua:316` |
| `Spell` | boolean | `Attack.lua:321` |
| `Magical` | boolean | `Attack.lua:326` |
| `Damage Types` | set | `Attack.lua:331` |
| `Hands` | number | `Attack.lua:337` |
| `Properties` | set | `Attack.lua:344` |
| `Property Value` | function | `Attack.lua:351` -- `Attack.PropertyValue("Fatal")`. |

These mostly belong to D&D weapon attacks. Draw Steel uses Attack only for
weapon-attack-style abilities; many fields will be defaults.

---

## Owner: equipment / weapon (`Armor.X`, `Weapon.X`)

equipment.helpSymbols: `Equipment.lua:669-696`. weapon.helpSymbols extends
it: `Equipment.lua:743-793`. weapon copies any missing keys from equipment
(`Equipment.lua:796-801`).

equipment fields: `Name`, `Is Weapon`, `Properties`, `Property Value`.

weapon adds: `Finesse`, `Melee`, `Ranged`, `Thrown`, `Heavy`, `Twohanded`,
`Simple`, `Martial`.

---

## Owner: Kit (`Kit.X`)

helpSymbols + lookup: `MCDMKit.lua:1061-1163`.

| Symbol | Type | Source |
|---|---|---|
| `Name` | string | `MCDMKit.lua:1065` |
| `Stamina` | number | `MCDMKit.lua:1070` |
| `Speed` | number | `MCDMKit.lua:1075` |
| `Distance` | number | `MCDMKit.lua:1080` |
| `Reach` | number | `MCDMKit.lua:1085` |
| `Area` | number | `MCDMKit.lua:1090` |
| `Disengage` | number | `MCDMKit.lua:1095` |
| `Stability` | number | `MCDMKit.lua:1100` |
| `Damage Bonus` | function | `MCDMKit.lua:1105` -- `Kit.Damage Bonus(2, "melee")`; tier + optional damage type. |

---

## Owner: PathMoved (`Path.X`)

helpSymbols + lookup: `Creature.lua:6104-6206`. Used in
`ModifierMovementText` and other forced-movement triggers.

| Symbol | Type | Source |
|---|---|---|
| `Squares` | number | `Creature.lua:6107` |
| `Shift` | boolean | `Creature.lua:6112` |
| `Forced` | boolean | `Creature.lua:6117` |
| `Vertical Only` | boolean | `Creature.lua:6122` |
| `Distance to Creature` | function | `Creature.lua:6127` -- `Path.Distance to Creature(Target)`. |

---

## Owner: Loc (`Loc.X`)

helpSymbols + lookup: `BasicRules.lua:222-256`. Used implicitly by
`Distance(other)` returning the result of a creature-to-loc distance.

| Symbol | Type | Source |
|---|---|---|
| `x` | number | `BasicRules.lua:226` |
| `y` | number | `BasicRules.lua:232` |
| `Floor` | number | `BasicRules.lua:238` |
| `Valid` | boolean | `BasicRules.lua:244` |
| `Distance` | function | `BasicRules.lua:250` |

---

## Owner: AuraInstance (`Aura.X`)

helpSymbols + lookup: `Aura.lua:700-726`.

| Symbol | Type | Source |
|---|---|---|
| `Caster` | creature | `Aura.lua:720`, `lookup 707` -- the creature controlling the aura. |

---

## Owner: CharacterOngoingEffectInstance

helpSymbols + lookup: `OngoingEffect.lua:639-659`. Bound as
`OngoingEffect` in some contexts.

| Symbol | Type | Source |
|---|---|---|
| `Caster` | creature | `OngoingEffect.lua:654`, `lookup ~640` |

---

## Owner: CharacterResourceCollection (`Resources.X`)

Dynamically built from `tables/characterresources` at every refresh
(`Resource.lua:1095-1124`). Each non-hidden resource becomes a symbol whose
name is `string.gsub(string.lower(name), "%W", "")`.

So `Resources.Heroic Resource`, `Resources.heroicresource`,
`Resources.HeroicResource`, `Resources.heroic resource` all hit the same
key. The most common resources (varies by content):
- `Resources.Heroic Resource` (the class's primary resource; named
  internally "Heroic Resource" regardless of class display name e.g.
  Ferocity / Insight / Drama -- see memory file)
- `Resources.Standard Action`, `Resources.Maneuver`, `Resources.Move Action`
- `Resources.Recoveries`
- `Resources.Surge` (Beastheart-specific)
- ... and any custom resource registered by class data

Bare `Heroic Resource` does NOT work outside `Resources.` access (the
identifier resolves to nothing).

---

## Owner: Deity (`Deity.X`)

helpSymbols + lookup: `MCDMDeities.lua:704-746`. Used in domain-related
formulas.

| Symbol | Type | Source |
|---|---|---|
| `Name` | text | `MCDMDeities.lua:708` |
| `Domains` | set | `MCDMDeities.lua:714` |

Plus dynamic custom fields from `tables/customfieldcollection/deities` at
`MCDMDeities.lua:760-787`.

---

## Owner: trigger (`Trigger.X`)

Synthetic owner used inside the new triggered-ability editor. `Triggered`
context exposes `Trigger.Name`, `Trigger.Text`, `Trigger.Rules`,
`Trigger.Free`. Defined at `MCDMModifyTriggers.lua:30-53`.

| Symbol | Type | Source |
|---|---|---|
| `Name` | string | `MCDMModifyTriggers.lua:32` |
| `Text` | string | `MCDMModifyTriggers.lua:36` |
| `Rules` | string | `MCDMModifyTriggers.lua:40` |
| `Free` | boolean | `MCDMModifyTriggers.lua:46` |

---

## Built-in functions (no owner)

C# table at `GoblinScript.cs:3306-3314`, Lua wrappers at
`GoblinScript.lua:225-258`. See LANGUAGE doc Section 7. Quick reference:

`min(...)`, `max(...)`, `floor(x)`, `ceiling(x)`, `Friends(a,b)`,
`Line of Sight(a,b,[pierceSurfaces])`, `Substring(haystack, needle)`.

---

## Dynamic registrations

Several lookup tables are rebuilt on the `refreshTables` event:

- **Class levels** (`Class.lua:1192-1219`): `<ClassName> Level` per class.
- **Resources** (`Resource.lua:1095-1124`): one entry on
  `CharacterResourceCollection` per non-hidden resource.
- **Custom attributes** (`CustomAttribute.lua:919-952`): one entry on
  creature/character/monster per attribute in the
  `customattributes/_table.yaml` (~70 entries).
- **Spell custom fields** (`ActivatedAbility.lua:5359-5398`): one entry on
  ActivatedAbility per field defined in `customfieldcollection/spells`.
- **Deity custom fields** (`MCDMDeities.lua:748-787`): one per
  `customfieldcollection/deities` field.

To inspect the actual live symbol table (with all dynamic registrations),
use the GoblinScript Debug Dialog or the Character Inspector
(`Development Utilities/CharacterInspector.lua`).

---

## Owner: GoblinScriptTestObject (test fixture)

Defined at `GoblinScript.lua:260-291` and used by
`/goblinscriptunittest`. Provides fixed test values for `level`,
`stamina`, `maximumstamina`, `monstertype`, `conditions`. Not relevant for
real content -- noted here for completeness.
