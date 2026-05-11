# Hero Character YAML Format Reference

Hero characters in the bestiary use a different `__typeName` and carry significantly
more data than monsters. This document describes every field that differs from the
monster format, using the three existing hero files as the source of truth:

- `5b1300cf-...yaml` -- Human Null (level 2)
- `c24a2f78-...yaml` -- Polder Elementalist (level 2)
- `35d86a42-...yaml` -- Dwarf Fury (level 1)

See also: [MONSTERS.md](MONSTERS.md) for the base monster YAML structure.
See also: [CORE.md](CORE.md) for UUID maps and table names.

---

## Key Difference: `__typeName`

```yaml
# Monster
properties:
  __typeName: monster

# Hero
properties:
  __typeName: character
```

This is the single most critical distinction. The engine uses `__typeName` to
determine which game type to instantiate. A `character` gets the full hero rules
pipeline (class features, kit, ancestry, culture, character builder state, heroic
resources, etc.). A `monster` gets the simplified monster stat block.

---

## Top-Level Structure (Shared With Monsters)

The outer envelope is identical to monsters:

```yaml
info:
  locInfo: null
  appearance:
    portraitId: <uuid>
    offtokenPortraitId: <uuid>
    portraitFrameId: <uuid>
    portraitRibbon: null
    backgroundId: <uuid>
    anthem: null
    anthemVolume: 1
    tokenScaling: 1
    tokenZoom: 1
    portraitOffset: { x: 0, y: 0 }
    frameHueShift: 0
    frameSaturation: 1
    frameBrightness: 1
    popoutScale: 0.99           # Optional, controls popout size
    characterName: "Dwarf Fury"  # Display name (can be null for unnamed)
    characterNamePrivate: false
    flip: false
    saddlePositions: []
  disguise:                     # Heroes always have this block (can be all nulls)
    portraitId: null
    offtokenPortraitId: null
    portraitFrameId: null
    portraitRibbon: null
    backgroundId: null
    anthem: null
    anthemVolume: 1
    tokenScaling: 1
    tokenZoom: 1
    portraitOffset: { x: 0, y: 0 }
    frameHueShift: 0
    frameSaturation: 1
    frameBrightness: 1
    characterName: null
    characterNamePrivate: false
    flip: false
    saddlePositions: []
  settings: { ... }             # Same as monsters
  mountedBy: {}
  updateid: <uuid>
  properties:
    __typeName: character
    # ... hero-specific fields below ...
  tokenType: null
  bestiaryId: <uuid>            # Must match the manifest key and filename
  summonerid: null
  ownerId: PARTY                # "PARTY" for heroes; "" for monsters
  partyid: <uuid>               # Party UUID; null for monsters
  size: -1                      # -1 for heroes (size comes from ancestry); >0 for monsters
  createdTimestamp: <epoch_ms>
description: null                # null for heroes; monster_type string for monsters
parentFolder: null               # null for heroes; folder UUID for monsters
artist: null
ord: 0
ctime: <epoch_ms>
mtime: <epoch_ms>
hidden: false
```

### Top-Level Fields That Differ From Monsters

| Field | Monster | Hero |
|-------|---------|------|
| `ownerId` | `""` | `"PARTY"` |
| `partyid` | `null` | `<party-uuid>` |
| `size` | Positive int (e.g. `2`) | `-1` (derived from ancestry) |
| `description` | Monster name string | `null` |
| `parentFolder` | Folder UUID | `null` |
| `appearance.characterName` | Usually `null` | Character name string |
| `appearance.disguise` | Usually `null` | Always present (all-null block) |

---

## Hero-Only Properties

These fields exist under `properties:` ONLY for heroes (`__typeName: character`),
never for monsters.

### Class Selection: `classes`

```yaml
classes:
- level: 1
  classid: ce18b1ba-363b-4403-945b-34a3ce08a465   # Fury class UUID
```

An array of class entries. Each entry has:
- `level` -- The level in this class (integer).
- `classid` -- UUID referencing the class definition in the `classes` data table.

Known class UUIDs (from `compendium/tables/classes/`):
- Fury: `ce18b1ba-363b-4403-945b-34a3ce08a465`
- Null: `4203e447-4531-467b-b270-c952806ce67f`
- Elementalist: `c1e1c512-6092-423f-85b2-324547f7f390`
- Shadow: look up from `compendium/tables/classes/shadow.yaml`
- Tactician: look up from `compendium/tables/classes/tactician.yaml`
- Conduit: look up from `compendium/tables/classes/conduit.yaml`
- Talent: look up from `compendium/tables/classes/talent.yaml`

Heroes do NOT have `innateActivatedAbilities` -- abilities come from class/kit instead.

### Kit Selection: `kitid`

```yaml
kitid: b0cedbc1-3830-448b-a2ee-172104e90e9e
```

Optional. UUID referencing a kit from the `kits` data table. Present on the Dwarf Fury,
absent on the Null and Elementalist (those classes may not use kits or the kit is
embedded in class choices).

### Ancestry: `raceid`

```yaml
raceid: a9f3759d-be9f-4c40-b610-e7a656425303   # Dwarf
```

UUID referencing an ancestry from the `races` data table.

Known ancestry UUIDs:
- Human: `6f995f3d-a4e3-456a-9294-ff2c9ec5cb95` (Human Null)
- Polder: `4f1ecd6c-a675-4d64-b7e5-b544d06c5fd8` (Polder Elementalist)
- Dwarf: `a9f3759d-be9f-4c40-b610-e7a656425303` (Dwarf Fury)

### Culture: `culture`

```yaml
culture:
  __typeName: Culture
  aspects:
    upbringing: <uuid>       # Upbringing aspect from culture table
    organization: <uuid>     # Organization aspect
    environment: <uuid>      # Environment aspect
```

Three aspects, each a UUID referencing culture aspect data. Example values:
- Upbringing `96478e46-...` (Polder Elementalist, Dwarf Fury)
- Upbringing `2ef328d9-...` (Human Null)
- Organization `8fb4c210-...` (shared across examples)
- Environment varies per character

### Background: `backgroundid`

```yaml
backgroundid: 09ed87b8-d480-48f3-80c2-104e3e229ce1
```

UUID referencing a background from the backgrounds data table.

### Complications: `complications`

```yaml
complications:
  b681b614-e00a-42a8-bdbc-258dc5d31893: true
```

Optional. A map of complication UUIDs to `true`. Only present on the Human Null.

### Character Type: `chartypeid`

```yaml
chartypeid: be5f5f52-b2cc-4033-ae16-6a4d25e10c2e
```

All three heroes share this same UUID. This identifies the character as a "Hero"
type (as opposed to companion, follower, etc.).

### Level Override: `levelOverride`

```yaml
levelOverride: 2
```

Integer. The character's effective level, independent of class level sums. Used
for pre-built heroes to set the level directly.

---

## Attribute System

Heroes use the same `attributes` block as monsters:

```yaml
attributes:
  prs:
    __typeName: CharacterAttribute
    baseValue: 1
    id: prs
  mgt:
    __typeName: CharacterAttribute
    baseValue: 2
    id: mgt
  agl:
    __typeName: CharacterAttribute
    baseValue: 2
    id: agl
  inu:
    __typeName: CharacterAttribute
    baseValue: 1
    id: inu
  rea:
    __typeName: CharacterAttribute
    baseValue: -1
    id: rea
```

The five Draw Steel characteristics: `mgt` (Might), `agl` (Agility), `rea` (Reason),
`inu` (Intuition), `prs` (Presence). `baseValue` is the raw score.

### `attributeBuild` (Hero-Only)

```yaml
attributeBuild:
  rea: 3
  array: 2
  inu: 1
  prs: 2
```

Records which attribute array was chosen during character creation and how points
were assigned. The `array` field is an index (0-based or 1-based) selecting from
the available standard arrays. The characteristic keys record which slot each
attribute was assigned to.

---

## Level-Up Choices: `levelChoices`

This is the most complex hero-specific field. It is a map (not an array) where
each key is a choice-point UUID and each value is an array of selected option UUIDs.

```yaml
levelChoices:
  raceid: a9f3759d-be9f-4c40-b610-e7a656425303     # Echoes the ancestry choice
  cultureLanguageChoice:
  - e110c3b1-3799-4179-b542-f842079b77f1           # Selected language
  duplicate-skills-choice:                           # Resolves duplicate skills
  - cb214a42-7f8c-4d02-b6ac-1399724a8b5f
  - 0c7d0c53-2056-4579-8c83-1bec3098cc56
  99e5f5d9-35b4-4e82-9576-b15b4ee7aff6:            # Some class/ancestry choice
  - 50ca6145-2d22-4496-a355-c7b2df2cf0de
  663496f0-1444-4d21-9ea9-7d8c1a70ef6e:
  - 7e7efb1d-4627-44ab-9407-11daff1a15cf
  # ... many more UUID -> [UUID] entries
```

### Special String Keys

| Key | Meaning |
|-----|---------|
| `raceid` | Stores the ancestry UUID (same as `properties.raceid`) |
| `cultureLanguageChoice` | Language selected from culture options |
| `duplicate-skills-choice` | Resolution when multiple sources grant the same skill |

### UUID Keys

All other keys are UUIDs that correspond to `ChoicePoint` objects defined in class,
ancestry, kit, culture, or background data. The values are arrays of UUIDs
representing the selected options. For single-select choices the array has one
element. For multi-select it can have multiple.

Empty arrays (`[]`) indicate a choice point was encountered but no selection was
made (or a choice with no options).

The choice UUIDs are stable across characters of the same build -- they come from
the class/ancestry/kit data, not from the character itself.

---

## Resources

Heroes track resources differently from monsters:

```yaml
resources:
  d19658a2-4d7b-4504-af9e-1a5410fb17fd:     # Action resource
    __typeName: CharacterResource
    used: 1
    refreshid: <combat-round-id>
  2d3d5511-4b80-46d1-a8c6-4705b9aa45ca:     # Heroic resource (e.g. Essence, Rage)
    __typeName: CharacterResource
    combatid: <combat-id>
    used: 0
    refreshid: ""
    unbounded: 3
  8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d:     # Another resource (e.g. Recoveries)
    __typeName: CharacterResource
    combatid: <combat-id>
    used: 0
    refreshid: ""
    unbounded: 2
```

Key resource UUIDs:
- `d19658a2-4d7b-4504-af9e-1a5410fb17fd` -- Action (shared with monsters)
- `2d3d5511-4b80-46d1-a8c6-4705b9aa45ca` -- Heroic Resource (class-specific name)
- `a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b` -- Malice/Villain Power (if applicable)

Resource fields:
- `used` -- How many uses consumed
- `combatid` -- Links to current combat instance
- `refreshid` -- Links to the refresh event that last restored this
- `unbounded` -- Current value for unbounded resources (heroic resource)

### Resource Histories

Heroes also have `<resource-uuid>_history` fields that track usage over time:

```yaml
d19658a2-4d7b-4504-af9e-1a5410fb17fd_history:
  __typeName: StatHistory
  entries:
    <entry-uuid>:
      note: "Melee Free Strike"
      refreshid: <id>
      userid: <user-id>
      set: "0/1"
      timestamp: <epoch_ms>
```

These are runtime state and can be empty for a fresh character.

### `heroicResourceRecord`

```yaml
heroicResourceRecord:
  746e467d-0775-40c3-b5c0-202f861691e7: 8e048842-0879-4223-aa5a-8152bbd11b11-1
```

Maps triggered ability UUIDs to combat round IDs. Tracks which heroic resource
triggers have fired in the current combat. Can be empty `{}` for fresh characters.

---

## Other Hero-Only Fields

### `inventory`

```yaml
inventory: []
```

Array of inventory item objects. Empty for pre-built test characters.

### `equipment`

```yaml
# Monster format:
equipment: []

# Hero format (can be a map):
equipment:
  mainhand1: bb699811-7a13-44e1-960f-c1deed366684  # Weapon UUID
```

For heroes, `equipment` is a map of slot names to item UUIDs. Slots include
`mainhand1`, `offhand1`, etc. The Dwarf Fury has a weapon equipped; the others
have `equipment: []`.

### `equipmentMeta`

```yaml
equipmentMeta:
  trinket9: []
  trinket8: []
  trinket5: []
  # ... up to trinket10
  leveled1: []
  leveled2: []
  # ... up to leveled5
  trinket1: []
```

Metadata for equipment slots. Each slot has an array of modifier/enhancement data.
Empty arrays for unenhanced slots. Present on Polder Elementalist and Dwarf Fury,
absent on Human Null (which lacks equipped items).

### `selectedLoadout`

```yaml
selectedLoadout: 0
```

Integer index of the active equipment loadout. Only present on Dwarf Fury.

### `characterDescription`

```yaml
characterDescription:
  __typeName: CharacterDescription
```

Always present on heroes. Can be empty (just the typeName).

### `downtimeInfo`

```yaml
downtimeInfo:
  __typeName: DTInfo
  downtimeProjects: []
  availableRolls: 0
  followerRolls: []
```

Downtime project tracking. Always present on heroes, absent on monsters.

### `followers`

```yaml
followers: []
```

Array of follower references. Empty for basic heroes.

### `innateLanguages`

```yaml
innateLanguages:
  5961c0ed-6a39-48fa-ad94-0a4fb4d98b58: true
```

Map of language UUIDs to `true`. Languages the character knows innately (from
ancestry, not culture).

### `extraLevelInfo`

```yaml
extraLevelInfo: []
```

Additional level-up tracking. Empty for standard builds.

### `savingThrowProficiencies`

```yaml
savingThrowProficiencies: []
```

Array of saving throw proficiency data.

### `characterFeatures`

```yaml
characterFeatures: []
```

On heroes this is typically empty -- features come from class/ancestry/kit via the
levelChoices system. On monsters, this is the primary feature list. The Dwarf Fury
has an explicit empty array `[]`.

### `originalid`

```yaml
originalid: a0748893-3487-40a1-9c57-68e543d2ab23
```

Optional. Present only on the Dwarf Fury. References the original character this
was copied/derived from.

### `creatorid`

```yaml
creatorid: 4V4KWXdW7ScFIiEyuknO4bqmQSc2
```

Optional. The user ID who created this character. Only on Dwarf Fury.

### `moveDiag`

```yaml
moveDiag: 0
```

Diagonal movement counter (runtime state). Present on Polder Elementalist and
Dwarf Fury.

### `moveDistance` / `moveDistanceRoundId`

```yaml
moveDistanceRoundId: 4fa6ea12-a5d5-41de-9234-a952a5418ad2-2
moveDistance: 7
```

Runtime movement tracking. Can be omitted for fresh characters.

---

## Fields Heroes Do NOT Have (Monster-Only)

| Monster Field | Purpose |
|---------------|---------|
| `monster_type` | Display name string (e.g. "Abyssal Hyena") |
| `monster_category` | Category string (e.g. "Gnoll", "Monster") |
| `role` | Role string (e.g. "Minion Brute", "Elite Controller") |
| `cr` | Challenge Rating / Level (integer) |
| `ev` | Encounter Value |
| `max_hitpoints` | Static max HP value |
| `max_hitpoints_roll` | HP formula string |
| `opportunityAttack` | Free strike damage value |
| `innateActivatedAbilities` | Ability array (heroes get abilities from class) |
| `minion` | Boolean minion flag |
| `stability` | Stability score |
| `walkingSpeed` | Base walking speed |
| `creatureSize` | Size string like "1M", "2" |
| `keywords` | Keyword map (e.g. `{ Humanoid: true }`) |
| `groupid` | Monster group UUID |
| `import` | Import data block |

Heroes derive speed, size, stability, HP, and abilities from their class, ancestry,
kit, and level choices rather than from static fields.

---

## Token Spawning

To spawn a hero from the bestiary, use:

```lua
local token = game.SpawnTokenFromBestiaryLocally(bestiaryId, loc, {
    fitLocation = true,
})
token.ownerId = "PARTY"
token.partyid = partyId
token:UploadToken("Spawn Hero")
game.UpdateCharacterTokens()
```

The `bestiaryId` must match both:
1. The key in `_manifest.yaml`
2. The `info.bestiaryId` field inside the YAML file

---

## Minimum Viable Hero Definition

To create a working hero character that can be placed on the map, the absolute
minimum required fields are:

```yaml
info:
  locInfo: null
  appearance:
    portraitId: null
    offtokenPortraitId: null
    portraitFrameId: <frame-uuid>
    portraitRibbon: null
    backgroundId: null
    anthem: null
    anthemVolume: 1
    tokenScaling: 1
    tokenZoom: 1
    portraitOffset: { x: 0, y: 0 }
    frameHueShift: 0
    frameSaturation: 1
    frameBrightness: 1
    characterName: "My Hero"
    characterNamePrivate: false
    flip: false
    saddlePositions: []
  disguise: null
  settings:
    canRotate: false
    useLight: false
    lightColor: { r: 1, g: 1, b: 1, a: 1 }
    lightIntensity: 0.1
    lightRadius: 10
    lightFalloff: 0.1
    lightAngle: 360
  mountedBy: {}
  updateid: <new-uuid>
  properties:
    __typeName: character
    classes:
    - level: 1
      classid: <class-uuid>          # REQUIRED: which class
    raceid: <ancestry-uuid>           # REQUIRED: which ancestry
    culture:
      __typeName: Culture
      aspects:
        upbringing: <uuid>
        organization: <uuid>
        environment: <uuid>
    backgroundid: <background-uuid>
    chartypeid: be5f5f52-b2cc-4033-ae16-6a4d25e10c2e  # Hero type constant
    levelOverride: 1
    attributeBuild:
      array: 2
      mgt: 4                          # Slot assignments
      agl: 2
      inu: 1
      prs: 3
    attributes:
      prs: { __typeName: CharacterAttribute, baseValue: 1, id: prs }
      mgt: { __typeName: CharacterAttribute, baseValue: 2, id: mgt }
      agl: { __typeName: CharacterAttribute, baseValue: 2, id: agl }
      inu: { __typeName: CharacterAttribute, baseValue: 1, id: inu }
      rea: { __typeName: CharacterAttribute, baseValue: -1, id: rea }
    levelChoices:
      raceid: <ancestry-uuid>         # Must echo raceid
      cultureLanguageChoice:
      - <language-uuid>
      duplicate-skills-choice: []
      # Class/ancestry/kit choice UUIDs with selections
    resources: {}
    innateAttacks: []
    inventory: []
    titles: []
    inflictedConditions: []
    ongoingEffects: []
    notes:
    - title: Backstory
      text: ""
    equipment: []
    skillProficiencies: []
    savingThrowProficiencies: []
    followers: []
    characterDescription:
      __typeName: CharacterDescription
    downtimeInfo:
      __typeName: DTInfo
      downtimeProjects: []
      availableRolls: 0
      followerRolls: []
    extraLevelInfo: []
    characterFeatures: []
    damage_taken: 0
    deathSavingThrowSuccesses: 0
    deathSavingThrowFailures: 0
    heroicResourceRecord: {}
    stamina_history:
      __typeName: StatHistory
      entries: {}
    innateLanguages: {}
  tokenType: null
  bestiaryId: <new-uuid>             # Must match manifest key and filename
  summonerid: null
  ownerId: PARTY
  partyid: <party-uuid>
  size: -1
  createdTimestamp: <epoch_ms>
description: null
parentFolder: null
artist: null
ord: 0
ctime: <epoch_ms>
mtime: <epoch_ms>
hidden: false
```

### Critical Fields for a Functional Hero

1. `__typeName: character` -- Without this, the engine treats it as a monster.
2. `classes` with valid `classid` -- Determines all class features and abilities.
3. `raceid` -- Ancestry determines size, speed, and ancestry features.
4. `culture` -- Determines skill and language options.
5. `backgroundid` -- Determines background skills.
6. `chartypeid: be5f5f52-...` -- Must be the Hero type constant.
7. `levelOverride` -- Sets effective level.
8. `attributes` with all five characteristics -- Core stats.
9. `levelChoices` -- Without valid choices, class features will not resolve.
10. `ownerId: PARTY` and `size: -1` -- Identifies this as a party member hero.

### Optional But Recommended

- `kitid` -- For classes that use kits (e.g. Fury).
- `attributeBuild` -- Needed for the character sheet to display correctly.
- `complications` -- Only if the character has complications.
- `equipment` -- Weapon/armor if desired.
- `innateLanguages` -- For ancestry languages.

---

## Appendix: Comparison Table

| Field | Monster | Hero |
|-------|---------|------|
| `__typeName` | `monster` | `character` |
| `ownerId` | `""` | `"PARTY"` |
| `partyid` | `null` | `<party-uuid>` |
| `size` (top-level) | `2` (positive) | `-1` |
| `description` (top-level) | Monster name | `null` |
| `classes` | absent | `[{level, classid}]` |
| `raceid` | absent | `<ancestry-uuid>` |
| `culture` | absent | `{aspects: {...}}` |
| `backgroundid` | absent | `<uuid>` |
| `kitid` | absent | `<uuid>` (optional) |
| `chartypeid` | absent | `be5f5f52-...` |
| `levelOverride` | absent | integer |
| `attributeBuild` | absent | `{array, ...}` |
| `levelChoices` | `[]` (empty array) | `{uuid: [uuid], ...}` (map) |
| `heroicResourceRecord` | absent | `{uuid: id}` |
| `downtimeInfo` | absent | `{DTInfo}` |
| `characterDescription` | absent | `{CharacterDescription}` |
| `followers` | absent | `[]` |
| `innateLanguages` | absent | `{uuid: true}` |
| `monster_type` | present | absent |
| `monster_category` | present | absent |
| `role` | present | absent |
| `cr` | present | absent |
| `ev` | present | absent |
| `max_hitpoints` | present | absent |
| `innateActivatedAbilities` | present | absent |
| `walkingSpeed` | present | absent |
| `creatureSize` | present | absent |
| `stability` | present | absent |
| `keywords` | present | absent |
