# Character Options Reference

Character creation content types: classes, subclasses, ancestries, kits, complications,
titles, treasure/equipment, and feature types.

## Key Pitfall: CharacterFeatureChoice Required Fields

Every `CharacterFeatureChoice` MUST include `allowDuplicateChoices: false` (or true).
This field is NOT set as a type default -- it's only set in the `CreateNew()` constructor.
If omitted from YAML, the engine crashes with "Attempt to read unknown field
allowDuplicateChoices in type CharacterChoice" when the character builder tries to
display the choice.

See also: [CORE.md](CORE.md) for UUID maps, table names, and common pitfalls.
See also: [MONSTERS.md](MONSTERS.md) for modifier and behavior type details.

---

## Shared Concepts

### CharacterFeature

The fundamental building block for class features, ancestry traits, feat effects, etc.
Both classes and ancestries deliver their mechanical effects through lists of
`CharacterFeature` objects.

```yaml
__typeName: CharacterFeature
guid: <uuid>
name: "Feature Name"
source: "Shadow Class Feature"    # human-readable origin
description: "Rules text here"
implementation: 1                  # see Implementation Tiers below
modifiers:                         # array of CharacterModifier objects
  - behavior: "attribute"
    attribute: mgt
    formula: "2"
    # ...
domains:
  "class:<class-uuid>": true       # tracks which class/race owns this feature
```

Key points:
- `modifiers` is an array of `CharacterModifier` objects (same types documented in
  MONSTERS.md CharacterModifier Types section).
- `source` propagates to all child modifiers automatically on deserialization.
- `implementation` tracks the automation tier of a feature. See "Implementation Tiers" below.
- `domains` is a map of domain strings to `true`. The engine uses these to associate
  features with their owning class or ancestry for filtering and display.

### CharacterFeatureChoice

A choice node that presents the player with options during character creation.

```yaml
__typeName: CharacterFeatureChoice
guid: <uuid>
name: "Choose a Trait"
description: "Pick one of the following"
numChoices: 1                       # number or GoblinScript formula
allowDuplicateChoices: false
costsPoints: false                  # if true, uses point-buy system
pointsName: "Points"               # label for the point currency
options:                            # array of CharacterFeature or nested choices
  - __typeName: CharacterFeature
    guid: <uuid>
    name: "Option A"
    pointsCost: 1                   # cost if costsPoints is true
    modifiers: [...]
  - __typeName: CharacterFeature
    guid: <uuid>
    name: "Option B"
    pointsCost: 2
    modifiers: [...]
```

When `costsPoints: true`, the player spends points from a budget equal to `numChoices`.
Each option has a `pointsCost` (default 1). The player picks options until their points
are spent.

### ClassLevel

A wrapper that holds the features and choices granted at a specific level (or the
"primary" entry, tutorial levels, etc.). Used by classes, ancestries, kits, titles,
and complications.

```yaml
__typeName: ClassLevel
features:                           # array of CharacterFeature, CharacterFeatureChoice,
                                    # CharacterSubclassChoice, CharacterSkillChoice, etc.
  - __typeName: CharacterFeature
    name: "Rage"
    modifiers: [...]
  - __typeName: CharacterFeatureChoice
    name: "Fighting Style"
    options: [...]
domains:
  "class:<uuid>": true
```

### Domain Conventions

Domains are strings that tag features with their source. Format: `"<type>:<uuid>"`.

| Domain pattern | Used by |
|---|---|
| `class:<class-uuid>` | Class features, subclass features |
| `race:<ancestry-uuid>` | Ancestry features |
| `CharacterFeature:<feature-uuid>` | Standalone features |
| `CharacterOngoingEffect:<uuid>` | Ongoing effect features |
| `item:<uuid>` | Item-granted features |

Subclass features get TWO domains: their own `class:<subclass-uuid>` AND the parent
class domain `class:<parent-class-uuid>`.

### Source Naming Conventions

The `source` field on features follows these patterns:
- Classes: `"<ClassName> Class Feature"` (e.g. `"Shadow Class Feature"`)
- Ancestries: `"<AncestryName> Race Feature"` (e.g. `"Human Race Feature"`)
- Kits: `"<KitName> Kit Feature"` (e.g. `"Panther Kit Feature"`)
- The source auto-propagates to all modifiers within the feature.

### Implementation Tiers

The `implementation` field on `CharacterFeature` tracks how automated a feature is.
The engine uses this to control UI display and mechanical processing. Features at
Bronze or higher get mechanical rule processing; Unimplemented features show raw
description text only.

| Value | Enum Key | Display Name | Color | Meaning |
|-------|----------|-------------|-------|---------|
| 0 | `WontImplement` | Narrative | Pink `#f82fcd` | Purely narrative/flavor -- no mechanical automation planned or possible |
| 1 | `Unimplemented` | Unimplemented | Red `#ff0000` | No automation yet (default when field is absent) |
| 2 | `Bronze` | Bronze | Bronze `#cd7f32` | Basic rules implemented -- core mechanics work but nothing advanced |
| 3 | `Silver` | Silver | Silver `#c0c0c0` | Mostly working -- minor things may not be automated |
| 4 | `Gold` | Gold | Gold `#ffd700` | Fully automated -- all mechanics work as intended |

**Lua constants** (defined in `DMHub Core UI/Gui.lua`):
```lua
gui.ImplementationStatus.WontImplement  -- 0
gui.ImplementationStatus.Unimplemented  -- 1
gui.ImplementationStatus.Bronze         -- 2
gui.ImplementationStatus.Silver         -- 3
gui.ImplementationStatus.Gold           -- 4
```

**How it affects behavior:**
- `>= Bronze (2)`: Power roll tier text is parsed mechanically (not shown as raw text).
  Ability roll behaviors execute mechanical processing.
- `~= Unimplemented (1)`: Feature is considered "implemented" for display filtering in
  the character panel.
- `== WontImplement (0)`: Feature is shown with a pink "Narrative" badge. No mechanical
  processing expected.

**YAML usage:**
```yaml
__typeName: CharacterFeature
name: "My Feature"
implementation: 4          # Gold -- fully automated
modifiers: [...]

# Or for narrative-only features:
implementation: 0          # Narrative -- won't implement
```

---

## Class Structure

Classes are stored in the `classes` data table. `__typeName: Class`.

### Top-level Class Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"Unnamed Class"` | Display name |
| `details` | string | `""` | Lore/description text |
| `portraitid` | string | `""` | Asset ID for class portrait |
| `tableName` | string | `"classes"` | Data table name (always "classes") |
| `isSubclass` | boolean | `false` | `false` for base classes |
| `primaryClassId` | string | `""` | Empty for base classes |
| `hit_die` | integer | `8` | Hit die size (legacy from D&D support) |
| `savingThrows` | string[] | `{}` | Attribute IDs for saving throw proficiency |
| `spellcastingAttr` | string | `"none"` | Spellcasting attribute (`"none"` for DS) |
| `hitpointsCalculation` | string | `""` | GoblinScript formula for stamina (DS-specific) |
| `numKits` | integer | `1` | Number of kits this class can equip |
| `heroicResourceName` | string | `"Heroic Resource"` | Display name for heroic resource |
| `epicResourceName` | string | `"Epic Resource"` | Display name for epic resource |
| `baseCharacteristics` | table | (see below) | Characteristic array configuration |

### Characteristic Arrays (baseCharacteristics)

The `baseCharacteristics` field defines how the class distributes characteristic bonuses.
It contains fixed-value characteristics and choosable arrays:

```yaml
baseCharacteristics:
  agl: 2                           # fixed characteristic values
  rea: 2
  arrays:                           # choosable arrays for remaining characteristics
    - [2, -1, -1]                   # array option 1
    - [1, 1, -1]                    # array option 2
    - [1, 0, 0]                     # array option 3
```

The fixed values (like `agl: 2`) are always applied. The player then picks one of the
`arrays` options and assigns those values to the remaining characteristics.

### Level Progression Keys

Class features are stored in a `levels` map with string keys:

| Key | When Applied |
|---|---|
| `primary` | When selected as primary class |
| `multiclass` | When selected as multiclass (legacy) |
| `tutoriallevel-1` through `tutoriallevel-4` | Tutorial/encounter progression levels |
| `level-1` through `level-15` | Standard level progression |

Each key maps to a `ClassLevel` object containing the features for that level.

```yaml
levels:
  primary:
    __typeName: ClassLevel
    features:
      - __typeName: CharacterFeature
        name: "Starting Proficiencies"
        modifiers: [...]
  tutoriallevel-1:
    __typeName: ClassLevel
    features: [...]
  level-1:
    __typeName: ClassLevel
    features:
      - __typeName: CharacterSubclassChoice
        guid: <uuid>
      - __typeName: CharacterFeature
        name: "Rage"
        modifiers: [...]
  level-3:
    __typeName: ClassLevel
    features:
      - __typeName: CharacterFeatureChoice
        name: "Choose an Ability"
        options: [...]
```

### How to Add Abilities at Levels

To give a class an activated ability at a specific level, add a `CharacterFeature`
with a modifier whose `behavior` is `"activated"`:

```yaml
# Inside a ClassLevel's features array:
- __typeName: CharacterFeature
  guid: <uuid>
  name: "Devastating Rush"
  source: "Shadow Class Feature"
  modifiers:
    - __typeName: CharacterModifier
      behavior: activated
      activatedAbility:
        __typeName: ActivatedAbility
        name: "Devastating Rush"
        # ... full ability definition
```

To add triggered abilities, use `behavior: "trigger"`.
To add resources, use `behavior: "resource"`.

### Heroic Resource Checklist

Classes can define a `heroicResourceChecklist` array that tracks events for gaining
heroic resource:

```yaml
heroicResourceChecklist:
  - guid: <uuid>
    name: "Kill an Enemy"
    details: "Gain 1 resource when you reduce an enemy to 0 stamina"
    quantity: 1
    mode: "encounter"               # "encounter", "recurring", or "round"
```

### Minimal Class YAML Template

```yaml
_table: classes
__typeName: Class
id: <generate-uuid>
name: "My Class"
details: "Class description."
tableName: "classes"
isSubclass: false
primaryClassId: ""
hitpointsCalculation: "18 + 8 * Level"
numKits: 1
heroicResourceName: "Focus"
epicResourceName: ""
baseCharacteristics:
  mgt: 2
  agl: 2
  arrays:
    - [2, -1, -1]
    - [1, 1, -1]
    - [1, 0, 0]
levels:
  primary:
    __typeName: ClassLevel
    features: []
  level-1:
    __typeName: ClassLevel
    features: []
```

---

## Subclass Structure

Subclasses use the SAME `__typeName: Class` but with `isSubclass: true`.
They are stored in the `subclasses` data table (NOT in `classes`).

### Key Differences from Base Classes

| Field | Value for Subclass |
|---|---|
| `isSubclass` | `true` |
| `primaryClassId` | UUID of the parent class |
| `tableName` | `"subclasses"` (though stored in the subclasses table) |

Subclasses do NOT define:
- `baseCharacteristics` (inherited from parent)
- `hitpointsCalculation` (inherited from parent)
- `numKits` (inherited from parent)

Subclasses DO define:
- Their own `levels` map with features at specific levels
- Their own `heroicResourceName` / `epicResourceName` if they override the parent
- Their own `heroicResourceChecklist` entries

### Domain Assignment

Subclass features receive TWO domains:
1. `class:<subclass-uuid>` -- their own identity
2. `class:<parent-class-uuid>` -- the parent class identity

This allows features to be filtered by either the specific subclass or the parent class.

### CharacterSubclassChoice in Parent Class

The parent class includes a `CharacterSubclassChoice` at the level where the player
picks their subclass:

```yaml
# In the parent class's level-1 features:
- __typeName: CharacterSubclassChoice
  guid: <uuid>
```

The engine automatically populates the dropdown with all subclasses whose
`primaryClassId` matches the parent class ID. The `classid` field is set automatically
during deserialization.

Subclasses can have a `prerequisite` field (GoblinScript formula) that must evaluate
to true for the subclass to be available.

### Minimal Subclass YAML Template

```yaml
_table: subclasses
__typeName: Class
id: <generate-uuid>
name: "My Subclass"
details: "Subclass description."
tableName: "subclasses"
isSubclass: true
primaryClassId: "<parent-class-uuid>"
heroicResourceName: "Focus"
levels:
  level-1:
    __typeName: ClassLevel
    features: []
```

---

## Ancestry (Race) Structure

Ancestries are stored in the `races` data table. `__typeName: Race`.

### Top-level Race Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"New Ancestry"` | Display name |
| `details` | string | `""` | Short lore summary |
| `lore` | string | `""` | Long-form lore text |
| `portraitid` | string | `""` | Asset ID for ancestry portrait |
| `tableName` | string | `"races"` | Data table name |
| `subrace` | boolean | `false` | If true, this is a subrace |
| `height` | number | `6` | Default height in feet |
| `weight` | string | `""` | Weight description |
| `lifeSpan` | string | `""` | Life span description |
| `size` | string | `"1M"` | Size string (Draw Steel format) |
| `moveSpeeds` | table | `{walk = 30}` | Movement speeds by type |

Note: In Draw Steel, `size` uses the format `"<tiles><category>"` where tiles is a
number and category is T/S/M/L. The default `"1M"` means 1 tile, Medium.

### Ancestry Feature Storage (modifierInfo)

Unlike classes which use a `levels` map, ancestries store their base features in a
single `modifierInfo` field containing a `ClassLevel`:

```yaml
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      name: "Signature Trait: Darkvision"
      source: "Elf Race Feature"
      modifiers: [...]
    - __typeName: CharacterFeatureChoice
      name: "Ancestry Traits"
      costsPoints: true
      numChoices: 3
      pointsName: "Points"
      options:
        - __typeName: CharacterFeature
          name: "Keen Senses"
          pointsCost: 1
          modifiers: [...]
        - __typeName: CharacterFeature
          name: "Fleet of Foot"
          pointsCost: 2
          modifiers: [...]
  domains:
    "race:<ancestry-uuid>": true
```

### Signature Traits vs Purchased Traits

Ancestry features use two patterns:

1. **Signature traits**: Plain `CharacterFeature` entries at the top level of
   `modifierInfo.features`. These are always granted.

2. **Purchased traits**: A `CharacterFeatureChoice` with `costsPoints: true`.
   The player spends points (default budget = `numChoices`) picking from the
   `options` array. Each option has a `pointsCost` (default 1).

### Level-based Ancestry Features

Ancestries can also have level-gated features via a `levels` array (indexed 1..N):

```yaml
levels:
  - __typeName: ClassLevel          # level 1
    features: [...]
  - __typeName: ClassLevel          # level 2
    features: [...]
```

These are applied up to the character's current level, similar to class level features.

### Former Life (Ancestry Inheritance)

Some ancestries (like Revenant) use the `CharacterAncestryInheritanceChoice` type
as the FIRST feature in their `modifierInfo.features` array. This lets the player
choose another ancestry to inherit traits from:

```yaml
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterAncestryInheritanceChoice
      guid: <uuid>
      ancestryid: <this-ancestry-uuid>    # excluded from choices
    - __typeName: CharacterFeature
      name: "Undead"
      modifiers: [...]
```

When `allowFormerLifeChoices: true` is set on a `CharacterFeatureChoice`, it will
also include point-buy options from the inherited ancestry.

### Minimal Ancestry YAML Template

```yaml
_table: races
__typeName: Race
id: <generate-uuid>
name: "My Ancestry"
details: "Ancestry description."
tableName: "races"
size: "1M"
moveSpeeds:
  walk: 5
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      guid: <generate-uuid>
      name: "Signature Trait"
      source: "My Ancestry Race Feature"
      modifiers: []
    - __typeName: CharacterFeatureChoice
      guid: <generate-uuid>
      name: "Ancestry Traits"
      costsPoints: true
      numChoices: 3
      pointsName: "Points"
      options: []
  domains:
    "race:<same-id-as-above>": true
```

---

## Kit Structure

Kits are stored in the `kits` data table. `__typeName: Kit`.

Kits provide stat bonuses, damage tier bonuses, a signature ability, equipment, and
optional additional features via `modifierInfo`. When a class equips a kit, its bonuses
are applied to the character: stamina, speed, stability, reach, range, area, disengage,
and tiered damage bonuses on matching abilities.

### Top-level Kit Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"New Kit"` | Display name |
| `type` | string | `"martial"` | Kit type id (see Kit Types below) |
| `description` | string | `""` | Descriptive text |
| `equipmentDescription` | string | `""` | Description of the kit's equipment |
| `portraitid` | string | `""` | Asset ID for the kit portrait |
| `tableName` | string | `"kits"` | Data table name |

### Stat Bonuses

| Field | Type | Default | Description |
|---|---|---|---|
| `health` | integer | `0` | Stamina bonus (scaled by echelon at runtime) |
| `speed` | integer | `0` | Speed bonus |
| `damage` | integer | `0` | Generic damage bonus |
| `range` | integer | `0` | Range bonus (applied to Ranged abilities) |
| `reach` | integer | `0` | Reach bonus (applied to Melee abilities) |
| `area` | integer | `0` | Area bonus (applied to burst/area abilities) |
| `stability` | integer | `0` | Stability bonus |
| `disengage` | integer | `0` | Disengage shift distance bonus |

**Important:** The `health` bonus is multiplied by the character's echelon at runtime.
A kit with `health: 6` grants +6 at echelon 1, +12 at echelon 2, +18 at echelon 3, etc.

### Damage Tier Bonuses (damageBonuses)

Kits provide tiered damage bonuses to matching ability types. The `damageBonuses` field
is a map from damage bonus type ID to an array of 3 numbers (one per tier):

```yaml
damageBonuses:
  melee: [2, 6, 10]          # +2/+6/+10 to Melee Weapon abilities
  ranged: [2, 6, 10]         # +2/+6/+10 to Ranged Weapon abilities
  supernatural: [2, 6, 10]   # +2/+6/+10 to Magic/Psionic abilities
```

**Damage bonus type IDs and their keyword matching:**

| ID | Display Name | Keywords | Match Mode |
|---|---|---|---|
| `melee` | Melee Weapon | Melee + Weapon | AND (both required) |
| `ranged` | Ranged Weapon | Ranged + Weapon | AND (both required) |
| `supernatural` | Supernatural | Psionic or Magic | OR (either matches) |

The tier array `[tier1, tier2, tier3]` maps directly to power roll tiers. These bonuses
are added to the numeric damage values in the `tiers` strings of power roll behaviors.

### Kit Types

Kit types control which classes can equip the kit and what keywords are associated:

| ID | Display Name | Keywords | Locked by Default |
|---|---|---|---|
| `martial` | Martial | Weapon | Yes |
| `caster` | Caster | Magic, Psionic | Yes |
| `stormwight` | Stormwight | Weapon | Yes |
| `null` | Null | Weapon | Yes |

"Locked by default" means a class must explicitly grant access via the `kitaccess`
modifier behavior. The character builder UI only shows kit types the character has
access to.

### Signature Ability

The `signatureAbility` field holds a full `ActivatedAbility` object (or `false` if none).
This ability is granted to the character when they equip the kit.

```yaml
signatureAbility:
  __typeName: ActivatedAbility
  name: "Mountain Stance"
  guid: <generate-uuid>
  # ... full ability definition ...
```

Kits may also have `additionalSignatureAbilities` (an array) or `signatureAbilities`
(for combined abilities).

### Kit Maneuver

The optional `kitManeuver` field holds an `ActivatedAbility` granted as a maneuver:

```yaml
kitManeuver:
  __typeName: ActivatedAbility
  name: "Kit Maneuver"
  # ... full ability definition ...
```

Set to `false` if the kit has no maneuver.

### Equipment

| Field | Type | Default | Description |
|---|---|---|---|
| `weapons` | table | `{}` | Map of weapon type IDs (e.g. `{"Light": true}`) |
| `implement` | boolean | `false` | Whether kit grants an implement |
| `armor` | string | `"None"` | Armor type: `"None"`, `"Light"`, `"Medium"`, `"Heavy"` |

**Valid weapon type IDs:** Light, Medium, Heavy, Bow, Thrown, Unarmed Strike, Net,
Polearm, Whip, Shield

**Valid armor type IDs:** None, Light, Medium, Heavy

### Additional Features (modifierInfo)

Kits can grant additional features (beyond stat bonuses and signature ability) via
`modifierInfo`, which stores a `ClassLevel`:

```yaml
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      guid: <generate-uuid>
      name: "Extra Kit Feature"
      source: "Panther Kit Feature"
      modifiers: [...]
```

### Minimal Kit YAML Template

```yaml
_table: kits
__typeName: Kit
id: <generate-uuid>
name: "My Kit"
type: "martial"
description: "A custom martial kit."
equipmentDescription: "Sword, shield, light armor."
tableName: "kits"
health: 6
speed: 0
damage: 0
range: 0
reach: 0
area: 0
stability: 0
disengage: 0
damageBonuses:
  melee: [2, 6, 10]
weapons:
  Medium: true
  Shield: true
armor: "Light"
implement: false
signatureAbility: false
kitManeuver: false
```

---

## Complication Structure

Complications are stored in the `complications` data table.
`__typeName: CharacterComplication` (inherits from `CharacterFeat`).

Complications provide a benefit and a drawback. They deliver their mechanical effects
through a `modifierInfo` ClassLevel, the same way ancestries do.

### Top-level Complication Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"Complication"` | Display name |
| `description` | string | `""` | Overview text |
| `benefit` | string | `""` | Benefit rules text |
| `drawback` | string | `""` | Drawback rules text |
| `prerequisite` | string | `""` | GoblinScript prerequisite expression |
| `tag` | string | `"complication"` | Comma-separated tags |
| `tableName` | string | `"complications"` | Data table name |

### Mechanical Effects (modifierInfo)

Like kits and ancestries, complications store their mechanical features in `modifierInfo`:

```yaml
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      guid: <generate-uuid>
      name: "Benefit Feature"
      source: "My Complication"
      modifiers:
        - __typeName: CharacterModifier
          behavior: attribute
          attribute: speed
          value: 1
```

The `benefit` and `drawback` fields are display text only. The actual game mechanics
are in the `modifierInfo` features and their modifiers.

### Minimal Complication YAML Template

```yaml
_table: complications
__typeName: CharacterComplication
id: <generate-uuid>
name: "My Complication"
description: "A complication with tradeoffs."
benefit: "You gain +1 speed."
drawback: "You take a bane on Reason tests."
prerequisite: ""
tag: "complication"
tableName: "complications"
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      guid: <generate-uuid>
      name: "Complication Effects"
      modifiers:
        - __typeName: CharacterModifier
          behavior: attribute
          attribute: speed
          value: 1
```

---

## Title Structure

Titles are stored in the `titles` data table.
`__typeName: Title` (inherits from `CharacterFeat`).

Titles are earned rewards with an echelon requirement. They deliver their mechanical
effects through a `modifierInfo` ClassLevel.

### Top-level Title Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"New Title"` | Display name |
| `description` | string | `""` | Description text |
| `prerequisite` | string | `""` | GoblinScript prerequisite expression |
| `effect` | string | `""` | Rules text describing the title's effect |
| `echelon` | string | `"1"` | Echelon tier required (e.g. "1", "2", "3") |
| `tableName` | string | `"titles"` | Data table name |

### Mechanical Effects (modifierInfo)

Like complications, titles store their mechanical features in `modifierInfo`:

```yaml
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      guid: <generate-uuid>
      name: "Title Benefit"
      modifiers:
        - __typeName: CharacterModifier
          behavior: activated
          activatedAbility:
            __typeName: ActivatedAbility
            name: "Title Ability"
            # ... full ability definition ...
```

### Minimal Title YAML Template

```yaml
_table: titles
__typeName: Title
id: <generate-uuid>
name: "My Title"
description: "Earned through great deeds."
prerequisite: ""
effect: "You gain a special ability."
echelon: "1"
tableName: "titles"
modifierInfo:
  __typeName: ClassLevel
  features:
    - __typeName: CharacterFeature
      guid: <generate-uuid>
      name: "Title Feature"
      modifiers: []
```

---

## Treasure / Equipment Structure

Equipment items are stored in the `tbl_Gear` data table. The base type is `equipment`,
with subtypes `weapon`, `armor`, and `shield`.

### Base Equipment Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | -- | Display name |
| `tableName` | string | `"tbl_Gear"` | Data table name |
| `iconid` | string | `"f5475490-..."` | Item icon asset ID |
| `description` | string | `""` | Rules text/description |
| `flavor` | string | `""` | Flavor/lore text |
| `weight` | number | `1` | Item weight |
| `costInGold` | number | `0` | Base cost in gold |
| `unique` | boolean | `false` | If true, only one copy in inventory |
| `isWeapon` | boolean | `false` | Set automatically by subtype |
| `isArmor` | boolean | `false` | Set automatically by subtype |
| `isShield` | boolean | `false` | Set automatically by subtype |

### Weapon Fields (weapon subtype)

| Field | Type | Default | Description |
|---|---|---|---|
| `hands` | string | `"One-handed"` | `"One-handed"`, `"Two-handed"`, or `"Versatile"` |
| `category` | string | `"Simple"` | `"Simple"` or `"Martial"` |
| `damage` | number | `1` | Base damage die value |
| `damageType` | string | `"slashing"` | Damage type name |

### Armor Fields (armor subtype)

| Field | Type | Default | Description |
|---|---|---|---|
| `category` | string | `"Light"` | `"Light"`, `"Medium"`, or `"Heavy"` |
| `armorClass` | number | `10` | Base armor class |
| `stealth` | string | `"None"` | `"None"` or `"Disadvantage"` |

### Shield Fields (shield subtype)

| Field | Type | Default | Description |
|---|---|---|---|
| `armorClassModifier` | number | `2` | AC bonus from equipping |

### Equipment Categories

Equipment categories are stored in the `equipmentCategories` table. Key category UUIDs:

| UUID | Category |
|---|---|
| `95125d91-fe41-4310-8f7b-44386651b0a7` | Consumable |
| `e036b288-416c-4a2e-ac33-95c6a528ed87` | Leveled Treasure |
| `4c9fc2bb-1c17-4072-babe-c2e3a55faa65` | Light Source |
| `659f34f2-14d6-4e71-99c1-89d703d5ba48` | Packs / Trinkets |
| `f8795dac-fda0-48a7-ba63-c2618c812d76` | Imbuement |

Category flags on EquipmentCategory:
- `isTreasure` -- treasure items (leveled gear)
- `isQuantity` -- quantity-based items
- `isLightSource` -- light sources
- `isPacks` -- trinket packs
- `isTool` -- tools
- `isMartial` -- martial weapons
- `isMelee` -- melee weapons
- `isRanged` -- ranged weapons
- `isAmmo` -- ammunition

### Consumable Items

Consumable items have charges that are spent on use:

```yaml
consumable: true
consumableCharges: 3              # Number of uses
consumableChargesConsumed: 0      # How many used so far
```

### Magical Items

```yaml
magicalItem: true                 # Item is magical
```

### Item Features (modifierInfo)

Equipment can grant features via the standard `modifierInfo` ClassLevel pattern.
This is used for magical items that provide abilities, attribute bonuses, etc.

### Minimal Equipment YAML Template

```yaml
_table: tbl_Gear
__typeName: equipment
id: <generate-uuid>
name: "My Item"
description: "An item."
tableName: "tbl_Gear"
iconid: "f5475490-42a4-4c1b-b3c2-40949501d5f3"
weight: 1
costInGold: 10
equipmentCategory: "<category-uuid>"
```

---

## Feature Types Reference

All feature types that can appear in a `ClassLevel.features` array:

| __typeName | Parent | Purpose |
|---|---|---|
| `CharacterFeature` | (base) | Static feature with modifiers, always granted |
| `CharacterFeatureChoice` | `CharacterChoice` | Player picks from options list |
| `CharacterSubclassChoice` | `CharacterChoice` | Player picks a subclass |
| `CharacterSkillChoice` | `CharacterChoice` | Player picks skills from categories |
| `CharacterFeatChoice` | `CharacterChoice` | Player picks a feat by tag |
| `CharacterAncestryInheritanceChoice` | `CharacterChoice` | Player picks a former ancestry |
| `CharacterFeatureList` | (standalone) | Container for a list of sub-features |
| `CharacterSkillsChoice` | `CharacterChoice` | Replacement for duplicate skill proficiencies |
| `CharacterToolsChoice` | `CharacterChoice` | Replacement for duplicate tool proficiencies |

### CharacterSkillChoice Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"Skill"` | Display name |
| `description` | string | `"Choose a Skill"` | Prompt text |
| `categories` | table | `{}` | Map of skill category IDs to true |
| `individualSkills` | table | `{}` | Map of specific skill IDs to true |
| `numChoices` | number | `1` | How many skills to pick |

### CharacterFeatChoice Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"Feat"` | Display name |
| `description` | string | `"Choose a Feat"` | Prompt text |
| `tag` | string | `"feat"` | Comma-separated tags filtering available feats |

---

## Comparison Table

| Aspect | Class | Subclass | Ancestry | Kit | Complication | Title |
|---|---|---|---|---|---|---|
| `__typeName` | `Class` | `Class` | `Race` | `Kit` | `CharacterComplication` | `Title` |
| Data table | `classes` | `subclasses` | `races` | `kits` | `complications` | `titles` |
| `isSubclass` | `false` | `true` | N/A | N/A | N/A | N/A |
| `primaryClassId` | `""` | parent UUID | N/A | N/A | N/A | N/A |
| Domain format | `class:<uuid>` | `class:<uuid>` (+ parent) | `race:<uuid>` | N/A | N/A | N/A |
| Feature storage | `levels` map | `levels` map | `modifierInfo` + optional `levels` | `modifierInfo` | `modifierInfo` | `modifierInfo` |
| Level keys | `primary`, `tutoriallevel-N`, `level-N` | Same | Array index | N/A | N/A | N/A |
| Has characteristics | Yes | No (inherited) | No | No | No | No |
| Has stamina formula | Yes | No (inherited) | No | No | No | No |
| Has stat bonuses | No | No | No | Yes (health, speed, etc.) | No | No |
| Has size/speed | No | No | Yes | No | No | No |
| Point-buy traits | No | No | Yes | No | No | No |
| Echelon requirement | No | No | No | No | No | Yes |
| Benefit/drawback text | No | No | No | No | Yes | No |
| Source name pattern | `"<Name> Class Feature"` | `"<Name> Class Feature"` | `"<Name> Race Feature"` | `"<Name> Kit Feature"` | (custom) | (custom) |

### Table Names Reminder

| Content Type | Table Name | __typeName |
|---|---|---|
| Classes | `classes` | `Class` |
| Subclasses | `subclasses` | `Class` (with `isSubclass: true`) |
| Ancestries | `races` | `Race` |
| Kits | `kits` | `Kit` |
| Complications | `complications` | `CharacterComplication` |
| Titles | `titles` | `Title` |
| Equipment | `tbl_Gear` | `equipment` (or `weapon`, `armor`, `shield`) |
| Cultures | `cultures` | (separate system) |
| Feats | `feats` | `CharacterFeat` |
| Skills | `Skills` | `Skill` |
