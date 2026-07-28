---
name: implement-crows-content
description: Implement compendium content for the Crows game system in DMHub -- monsters, items, backgrounds, skills, conditions, ongoing effects, and other Crows game data. Use when asked to "implement a Crows monster", "create a Crows item", "add a Crows background", or generate any MCDM Crows playtest content as importable YAML.
metadata:
  author: draw-steel-codex
  version: "1.0.0"
  argument-hint: <content-description>
---

# Crows Compendium Content Implementation

You implement **Crows** game content as importable YAML files for DMHub. Crows is MCDM's
post-apocalyptic survival-horror dungeon game (May/June 2026 playtest), implemented as the
`Crowdex/` module layered on top of the Draw Steel codex. It is NOT Draw Steel -- different
characteristics, different health model, no classes, no levels, no heroic resources.

## Sources of Truth

| Source | What it is |
|---|---|
| `Crowdex/01 MCDM Crows The Rules Booklet...md` | Core rules: tests, combat, damage, conditions, dungeon turns |
| `Crowdex/02 MCDM Crows Characters Booklet...md` | Backgrounds, skills, traits, advancement, gear, village |
| `Crowdex/03 MCDM Crows Monsters Booklet...md` | Monster stat blocks |
| `Crowdex/04 MCDM Crows Blood Dungeon Booklet...md` | The Blood Library adventure |
| `Crowdex/05/06 ... Inventory/Loot Cards...md` | Item cards (authoritative for item stats; cards win over the price table) |
| `Crowdex/MCDM Crows Cheat Sheet...md` | One-page rules summary |
| `Crowdex/Crowdex*.lua` | The system implementation (rules overrides, inventory, builder, sheet) |
| `compendium/import/crows-*.yaml` | **Canonical YAML patterns -- copy these, not Draw Steel files** |

When rules text and an existing YAML disagree, raise it with the user; the booklets are the
rules authority, but existing YAML may encode deliberate adaptation decisions.

## CRITICAL: Draw Steel Data Boundary

The rest of the compendium is **Draw Steel data**:

- `compendium/tables/`, `compendium/bestiary/`, `compendium/reference/` examples = Draw Steel.
  Use them as **structural reference and automation ideas only** -- to learn YAML shapes,
  behavior types, and modifier patterns. NEVER reference Draw Steel content UUIDs (conditions,
  ongoing effects, abilities, items, skills) from Crows YAML, and never "fix" or import
  Draw Steel files as part of Crows work.
- Crows already has its own conditions (Grabbed, Prone, Unconscious), effects (Blessed, Boned),
  skills, resources, and equipment categories in `compendium/import/crows-*.yaml`. Reference
  THOSE UUIDs.
- **Deliberately shared GUIDs** (the only Draw Steel IDs Crows reuses -- see
  `crows-resources.yaml` header):

| Shared ID | Value |
|---|---|
| Action resource | `d19658a2-4d7b-4504-af9e-1a5410fb17fd` |
| Maneuver resource | `a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b` |
| Reaction (trigger) resource | `b9bc06dd-80f1-4f33-bc55-25c114e3300c` |
| Malice (monster resource) | `101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8` |
| Default condition/effect icon | `bc90bb09-9e3c-46d4-bf16-0e5c0134dbf8` |

These are reused verbatim so the engine's `CharacterResource.*` Lua constants resolve.
Do not invent new action-economy resources.

All new Crows content goes to `compendium/import/` named `crows-<type>-<name>.yaml`
(e.g. `crows-background-pyromancer.yaml`, `crows-items-weapons.yaml`), with `crows-<type>s-all.yaml`
manifest bundles for batch import. Never edit `compendium/tables/` directly.

## Workflow

1. **Discuss**: Talk through the design first. What should the content do mechanically?
   What is the best player experience? Which behaviors/modifiers achieve the automation?
2. **Generate**: Write YAML to `compendium/import/crows-<type>-<name>.yaml`. Use
   `compendium/temp/` for working files (analysis, extraction, plans).
3. **Validate**: Run `python validate_yaml.py <name>.yaml` from the repo root. It covers
   all the Crows tables (`careers`, `Skills`, `tbl_Gear`, `charConditions`,
   `characterOngoingEffects`, `characterResources`, `equipmentCategories`, monsters).
   Fix ALL errors before importing. Note: it validates structure, not Crows semantics --
   it will not catch a wrong `crowsAD` value or a Draw Steel UUID leak.
4. **Auto-import**: Import via the DMHub MCP server (`mcp__dmhub__execute_lua`) with
   `dmhub.ImportFile(filename)` (basename only; resolves relative to `compendium/import/`).
   Report `monstersImported`, `itemsImported`, and any `errors`. Do NOT ask the user to
   type `/import` -- use the MCP tool. Only fall back to `/import <files>` if MCP is down.
5. **Iterate**: The user tests in-app and reports issues; refine and re-import.

### Auto-Import Pattern

```lua
local files = {
    "crows-items-weapons.yaml",
    "crows-condition-prone.yaml",
}

local totalMonsters, totalItems, totalErrors = 0, 0, {}

for _, filename in ipairs(files) do
    print("Importing:", filename)
    local result = dmhub.ImportFile(filename)
    if result == nil then
        print("  FAILED to resolve:", filename)
        totalErrors[#totalErrors+1] = "Failed to resolve: " .. filename
    else
        print("  monstersImported =", result.monstersImported or 0,
              "itemsImported =", result.itemsImported or 0)
        totalMonsters = totalMonsters + (result.monstersImported or 0)
        totalItems = totalItems + (result.itemsImported or 0)
        for _, err in ipairs(result.errors or {}) do
            print("  ERROR:", tostring(err))
            totalErrors[#totalErrors+1] = tostring(err)
        end
    end
end

print("--- SUMMARY ---")
print("Monsters:", totalMonsters, "Items:", totalItems, "Errors:", #totalErrors)
```

**Bundle/manifest syntax** (resolves relative to `compendium/import/`):

```yaml
_bundle:
  - _include: "crows-background-pyromancer.yaml"
  - _include: "crows-background-soldier.yaml"
```

**Import-by-description warning**: `dmhub.ImportFile` matches monsters by description
(display name), not id. A Crows monster whose name collides with an existing entry
OVERWRITES it. Check names before importing.

## Crows Rules Crash Course (content-relevant)

Read the booklets for detail; these are the facts that shape YAML:

- **Tests**: 2d10 + characteristic (+ skill bonus, skills capped at +2). Tier 1 = 11 or
  less (failure), Tier 2 = 12-16 (partial/costly success), Tier 3 = 17+ (clean success).
  Natural 19-20 = critical; natural 2-3 = **doom** (auto Tier 1 + setback). This matches
  the Draw Steel power-roll tier brackets, which is why `ActivatedAbilityPowerRollBehavior`
  works unchanged for Crows attacks.
- **Resistance Rolls (RR)**: tests made in response to danger; skill bonuses do NOT apply.
  Crows has NO separate saving throws (`creature.ClearAttributes()` cleared them).
- **Characteristics**: exactly three, registered in `CrowdexRules.lua`:

| Characteristic | attrid | Governs |
|---|---|---|
| Agility | `agility` | dodging, ranged attacks, acrobatics, thievery |
| Mind | `mind` | spellcasting, magic resistance, lore, perception |
| Strength | `strength` | melee attacks, poison resistance, climbing, lifting |

  PC scores run -1 to +1 at creation, max +3. Use these attrids everywhere a Draw Steel
  file would use `mgt`/`agl`/`rea`/`inu`/`prs`.
- **Action economy**: per turn, 1 action + 1 maneuver OR 2 maneuvers; 1 reaction per round.
  Move is the Move Speed maneuver (no separate move resource). Resources are granted by
  GUID to ALL creatures (monsters too) via the `GameSystem.BaseCreatureResources` override.
- **Health model**: **Stamina** maps to the `hitpoints` attribute. **Armor Defense (AD)**
  absorbs damage before Stamina (worn armor + wielded shields/Parry weapons, via `crowsAD`).
  **Piercing** damage bypasses AD. At 0 Stamina a PC takes **Wounds** that fill backpack
  slots; a PC dies only when all 10 backpack slots hold wounds (`character:IsDead` override).
  PCs at 0 Stamina are still up and fighting. **Monsters have no AD and no wounds -- they
  die at 0 Stamina.**
- **Speed**: all crows have base speed 5. Each backpack slot holding BOTH a wound and an
  item costs 1 speed. Always round down.
- **Conditions**: Grabbed, Prone, Unconscious (in `charConditions`); **Blessed** and
  **Boned** are stacking ongoing effects that cancel 1-to-1 and clear at Dungeon Turn end.
- **Dungeon Turns (DT)**: 30-minute time blocks; Usage Dice for spells/consumables/light
  roll at DT end. DT-based durations have no engine timer -- they are currently manual.
- **Does NOT exist in Crows** (never use these Draw Steel mechanisms): classes, levels,
  echelons, victories, recoveries, heroic resources, surges, potencies/potency gates,
  saving throws, kits, ancestries.

## Content Type Reference

Copy structure from the existing files listed per type. Generate fresh UUIDs for new
entities; keep cross-references internally consistent.

### Items (weapons, armor, gear, consumables)

`_table: tbl_Gear`, `__typeName: equipment`. Pattern files: `crows-items-weapons.yaml`,
`crows-items-armor.yaml`, `crows-items-basic.yaml` (their header comments document the
field semantics -- read them).

Crows-specific fields (read by `CrowdexInventory.lua` / `CrowdexEquipment.lua`):

| Field | Meaning |
|---|---|
| `crowsWeaponType` | Weapon skill applied to attacks (Slashing, Bashing, Bow, ...). Also marks the item as a weapon. |
| `crowsMeleeRange` / `crowsRangedRange` | Reach / range in squares. Both set = thrown weapon (mode chosen before the test). |
| `crowsAttackStat` | Characteristic(s) for the 2d10 test, as printed (`S`, `A`, `A or S`) |
| `crowsTier2` / `crowsTier3` | Damage text at tier 2 (12-16) and tier 3 (17+), as printed (`3 + S`) |
| `crowsQualities` | Quality list as printed, minus the type (Light, Disengage, Parry 4, Dismember, ...) |
| `crowsAD` | AD pool: armor suits, shields, and Parry-X weapons |
| `crowsShield` | true for shields (wielded in a hand slot to absorb) |
| `crowsAmmoType` | Ammo keyword; on a ranged weapon = ammo it fires, on Ammunition = weapons it fits |
| `massQuantity` | Bundle size for ammunition (one record = one arrow; one pull grants this many) |
| `stackLimit` | How many fit in one slot |
| `slotsRequired` | Slots occupied (armor suits take 2-4 backpack slots; two-handed weapons 2 hand slots) |

Standard fields: `name`, `description` (transcribe the card text: attack line, qualities,
craft prereq), `type: Gear`, `category: Gear`, `equipmentCategory` (see GUIDs below),
`costInGold`, `weight`, `iconid`, `domains: { "item:<id>": true }`.

**Equipment category GUIDs** (already imported via `crows-equipment-categories.yaml`;
do not create new ones without discussing):

| Category | id |
|---|---|
| Gear | `f960a9b8-145a-4a8f-a7d2-cd69a54e3e77` |
| Light | `23f3122f-be24-4a27-9877-0400d263d2ff` |
| Weapon (superset) | `18175967-5d9d-460d-a9a1-8e8cc08f663c` |
| Melee Weapon | `ab3f029a-b8f5-4cb3-8560-04d8daf3e04b` |
| Ranged Weapon | `1ad9b15d-48fa-4689-bcba-8f63b9942d31` |
| Thrown Weapon | `4ec7fd08-6477-4370-92eb-2f7c41277284` |
| Ammunition | `41b5fb30-e155-4107-88a7-803cbcb8d1fb` |

Melee-only weapons -> Melee Weapon; melee/thrown -> Thrown Weapon; bows/crossbows ->
Ranged Weapon; arrows/bolts -> Ammunition. The category drives which editor fields appear
and ammo compatibility.

**Icons**: reuse `iconid`s from similar existing Crows or Draw Steel gear YAMLs, or find
candidates with `dmhub.SearchImages` tag hits. Do not pick icons by screenshot.

### Backgrounds

`_table: careers`, `__typeName: Background`. Pattern files: any `crows-background-*.yaml`
(`pyromancer` for a spellcaster, `soldier` for a martial). Structure:

- `modifierInfo: { __typeName: ClassLevel, features: [...] }`
- **Characteristics** feature: a `CharacterFeatureChoice` (numChoices 1) whose options are
  the legal spreads -- "X +1" alone, plus each "X +1, Y +1, Z -1" variant, each option a
  `CharacterFeature` with `behavior: attribute` modifiers on `agility`/`mind`/`strength`.
- **Stamina** feature: `behavior: attribute`, `attribute: hitpoints`, `value: <5-9>`.
  This is the WHOLE base Stamina (Crows `character:BaseHitpoints()` returns 0 for the
  classless crow).
- **Skills** feature: `behavior: proficiency`, `proficiency: proficient`, `subtype: skill`,
  `equate: false`, `skills:` map keyed by the Crows skill UUIDs (look them up in
  `compendium/import/crows-skill-*.yaml` -- never Draw Steel skill ids).
- **Trait** and **Equipment** features: currently text-only (`implementation: 1`,
  `modifiers: []`) -- traits and starting-gear grants are not yet automated (see
  "Not Yet Compendium-Driven" below).

### Skills

`_table: Skills`, `__typeName: Skill`. Pattern: `crows-skill-*.yaml`. Fields: `id`, `name`,
`description`, `attribute` (`agility`/`mind`/`strength`), `category`, `specializations: []`.

Categories (registered in `CrowdexRules.lua`): `general`, `spellcasting`, `weapon`.
The full playtest skill list is already imported -- check `crows-skills-all.yaml` before
adding a new one.

### Conditions

`_table: charConditions`, `__typeName: CharacterCondition`. Pattern: `crows-condition-prone.yaml`
(the richest example: speed multiplier + attack/defense modifiers). Conventions:

- `indefiniteDuration: true`, `powertable: true`, `iconid` + `display` block required.
- Modifiers use the Draw Steel power-modifier machinery: `behavior: power` with
  `rollType: ability_power_roll` (own attacks) / `enemy_ability_power_roll` (attacks
  against you) / `all` (all tests), `modtype: plusone`/`minusone`/`appendroll`, optional
  `keywords: { Melee: true }` / `{ Ranged: true }` filters.
- `behavior: attribute` with `attribute: movementMultiplier, operation: set` for speed
  halving.

The playtest conditions (Grabbed, Prone, Unconscious) exist -- reference their UUIDs from
the existing files rather than re-creating them.

### Ongoing Effects

`_table: characterOngoingEffects`, `__typeName: CharacterOngoingEffect`. Pattern:
`crows-effect-blessed.yaml` / `crows-effect-boned.yaml`. Conventions:

- **`crowsCondition: true`** -- REQUIRED for any effect that should appear in the Crows
  character panel's conditions list (`CrowdexCharacterPanel.lua` filters on it).
- `iconid` and `display` are REQUIRED (import crashes without `iconid`).
- Stacking pair pattern (Blessed/Boned): `stackable: true`, `statusEffect: true`,
  `clearStacksWhenApplying: false`, modifiers using
  `max(0, Stacks - Stacks("<Opposite>"))` formulas so levels cancel 1-to-1.
- DT-end expiry is manual for now -- say so in the description text.

### Resources / Equipment Categories

Already imported (`crows-resources.yaml`, `crows-equipment-categories.yaml`). Do not
re-create or add to these without an explicit design discussion -- the action bar and
inventory UI key off the existing GUIDs.

### Monsters

**No Crows monster YAML exists yet -- the first one you write sets the pattern, so agree
the format with the user before batch-producing.** Use the Draw Steel `MonsterAsset`
envelope (study a simple `compendium/bestiary/*.yaml` for the `info:` structure) with
Crows substitutions:

| Crows stat block field | YAML mapping |
|---|---|
| Stamina | `info.properties.max_hitpoints` (monsters die at 0 -- no wounds/AD) |
| Speed (incl. climb/swim) | `info.properties.walkingSpeed` (+ movement-type modifiers for climb/swim) |
| A / M / S | `info.properties.attributes` keyed `agility`/`mind`/`strength` (CharacterAttribute entries with `baseValue`) |
| Type (Blood Creature, Undead, ...) | `info.properties.keywords` / `monster_type` -- confirm with user |
| Power | No native field -- propose where to record it (e.g. `cr`) and confirm with user |
| Size (Tiny ... "Holy Shit!") | `creatureSize` -- confirm the size-token mapping with user |
| Attack table rows | `info.properties.innateActivatedAbilities` |
| Special traits | `info.properties.characterFeatures` (CharacterFeature + modifiers), or text features when unautomatable |

Attack rows map naturally onto `ActivatedAbilityPowerRollBehavior`:

```yaml
- __typeName: ActivatedAbility
  name: "Bite"
  guid: <uuid>
  actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"   # Action
  targeting: direct
  targetType: enemies
  numTargets: "1"
  range: 1
  keywords: { Melee: true, Strike: true }
  behaviors:
    - __typeName: ActivatedAbilityPowerRollBehavior
      roll: "2d10 + 2"          # 2d10 + the printed attack bonus
      attrid: strength
      tiers:
        - ""                     # Tier 1 (<=11): Crows attacks miss -- no effect
        - "3 damage"             # 12-16 column
        - "4 damage; grabbed"    # 17+ column
```

Crows monster attacks print only 12-16 and 17+ results; tier 1 is a miss, so leave it
empty (verify in-app how an empty tier renders -- if it misbehaves, discuss alternatives
with the user rather than inventing a tier-1 effect).

## Not Yet Compendium-Driven (discuss before inventing schemas)

These Crows systems currently live as **character-local data** edited on the character
sheet, NOT as compendium tables:

- **Spellbooks / spells** (`crowdex_spellbooks` on the character) -- rank, discipline,
  Usage Dice, casting results. Backgrounds only mention them in equipment text.
- **Traits / trait trees** (`crowdex_traits`) -- backgrounds grant them as text features.
- **Crafting** (skill + materials + crafting points) -- text in item descriptions.
- **Usage Dice, Chaos Count, Backlash, Dungeon Turn clock, Miasma, village** -- no engine
  representation.

If asked to implement content touching these, do NOT invent a compendium schema unilaterally.
Present the options (text-only feature now vs. designing the schema + Crowdex Lua support)
and let the user decide. New Lua work goes in `Crowdex/` only -- shared Draw Steel files
stay generic (see CLAUDE.md "Crows" section), and new Lua files must be registered through
the DMHub module system by the user.

## Automation Principle

**AUTOMATE EVERYTHING that the engine can express.** Damage dealt, conditions applied,
attribute changes, stacking effects -- all should resolve mechanically. Text is the last
resort. But Crows is a playtest layered on a Draw Steel engine: when a mechanic has no
engine support (Usage Dice, wounds interactions, DT timers), prefer an honest
`implementation:` rating and a clear description over fake automation.

Use the `implementation` field on features/conditions (0 = unimplemented, 1 = narrative
text, 2 = partial, 3 = full). `effectImplemented` is deprecated -- never read or write it.
Float text that merely SAYS something happened is not automation.

When something can't be fully automated with existing YAML behaviors, offer three tiers:

1. **YAML-only**: what existing behaviors can do; state the limitations.
2. **YAML + creative workaround**: approximate with existing tools.
3. **Lua implementation**: extend the engine (new GoblinScript symbol, behavior, trigger).
   If accepted, hand off to a `general-purpose` agent directed to invoke the
   `goblinscript` skill (new symbols) or `codexmod` skill (behaviors/modifiers/triggers),
   with: the blocker, the proposed extension shape, an acceptance-criteria YAML snippet,
   and a return contract (final symbol/typeName + caveats). Crows-specific Lua belongs in
   `Crowdex/`. Don't read or edit Lua source yourself -- stay focused on YAML.

When 3+ items in a batch share an automation gap, offer a **Systemic Changes Feasibility
Report**: per change, the goal, what it unlocks (count), confidence 1-10, effort, key
files, approach, risks -- researched via the `Explore` subagent, ranked by
effort-to-impact.

## GoblinScript and Behaviors in Crows

The Draw Steel rules engine is still loaded underneath Crows, so most machinery carries
over -- but the reference docs describe Draw Steel, so verify before use:

**Carries over** (safe to use):
- `ActivatedAbilityPowerRollBehavior` (2d10 tier brackets match Crows exactly), `attrid`
  now `agility`/`mind`/`strength`.
- Power modifiers (`behavior: power`, `modtype`, `rollType`, keyword filters), attribute
  modifiers, proficiency modifiers, `Stacks` / `Stacks("Name")`.
- `ActivatedAbilityDrawSteelCommandBehavior` rule strings for damage, conditions, and
  forced movement (`3 damage; push 2; prone (eot)`) -- the parser is system-agnostic for
  these. Prefer rule strings for movement (`shift {N}`, `push {N}`) over raw
  Relocate/ForcedMovement behaviors.
- Tier-string separators: `;` = hard break between independent clauses, `,` or space =
  soft link. **NEVER `:`** -- it silently misparses.
- GoblinScript symbols for the Crows characteristics (`Agility`, `Mind`, `Strength`)
  resolve because `creature.RegisterAttribute` registers them.

**Does NOT apply** (Draw Steel-only -- using these silently evaluates to 0/false or
references mechanics Crows lacks):
- Potency gates (`M<{Weak} prone`) -- Crows has no potencies. Tier text is unconditional.
- `Recoveries`, `Heroic Resource`, `Resources.<ClassResource>`, `Surges`, `Victories`,
  `Echelon`, kit/class symbols.
- Draw Steel condition/effect UUIDs and the DS standard-abilities table.

**Never ship speculative GoblinScript.** Verify every symbol against
`compendium/reference/GOBLINSCRIPT-SYMBOLS.md` / `GOBLINSCRIPT-CONTEXTS.md` AND the Lua
`RegisterSymbol` calls (delegate to Explore), or ask. Unknown symbols silently evaluate
to 0/false.

### Where to Point Explore for Crows Questions

| Question | Where Explore should look |
|---|---|
| How does the Crows system override X? | `Crowdex/CrowdexRules.lua`, then the wrapped function in `DMHub Game Rules/` / `Draw Steel Core Rules/` |
| What item fields does the inventory read? | `Crowdex/CrowdexInventory.lua`, `Crowdex/CrowdexEquipment.lua` |
| What character fields exist? | `crowdex_*` reads in `Crowdex/CrowdexCharacterSheet.lua` / `CrowdexCharacterPanel.lua` (inventory, wornSlots, skills, spellbooks, traits, features, woundSlots, woundNotes, background) |
| What does the builder consume? | `Crowdex/CrowdexBuilder.lua` (reads the `careers` table via `Background.tableName`) |
| Is there a trigger/symbol for event X? | `RegisterTrigger` / `RegisterSymbol` in `Draw Steel Core Rules/*.lua`, `DMHub Game Rules/*.lua` |
| Does similar content already solve this? | `compendium/import/crows-*.yaml` first; `compendium/bestiary/`, `compendium/tables/` for structural patterns only |

## Critical Pitfalls

1. **ASCII only** -- all YAML must be bytes 0-127. No em dashes, curly quotes, ellipses.
2. **Fresh UUIDs** for every new entity (`xxxxxxxx-xxxx-...` lowercase hex); internally
   consistent cross-references. Reuse ONLY the shared GUIDs tabled above and existing
   Crows content UUIDs.
3. **Table names are case-sensitive**: `careers`, `Skills`, `tbl_Gear`, `charConditions`,
   `characterOngoingEffects`, `characterResources`, `equipmentCategories`.
4. **`iconid` + `display` are REQUIRED** on conditions and ongoing effects (crash if missing).
   Default icon: `bc90bb09-9e3c-46d4-bf16-0e5c0134dbf8`.
5. **`crowsCondition: true`** on any ongoing effect that should show in the Crows panel.
6. **Modifier `name` must match its parent feature's `name` verbatim** so the bonus-listing
   UI groups them (see the background files -- every modifier repeats the feature name).
7. **Stamina = `hitpoints` attribute**; background Stamina is the whole base value
   (BaseHitpoints returns 0 for classless crows). Do not add a class.
8. **Skill UUIDs in proficiency grants** must be the Crows skill ids from
   `crows-skill-*.yaml`, never Draw Steel skills.
9. **`:` in tier/rule strings** silently misparses -- use `;` between clauses.
10. **Import matches monsters by description/name** -- name collisions overwrite. Check first.
