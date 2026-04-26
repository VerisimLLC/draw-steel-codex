---
name: implement-content
description: Implement compendium content for DMHub -- monsters, items, ongoing effects, abilities, and other game data. Use when asked to "implement a monster", "create a creature", "build an item", "add a compendium entry", or generate any Draw Steel game content as importable YAML.
metadata:
  author: draw-steel-codex
  version: "1.0.0"
  argument-hint: <content-description>
---

# Compendium Content Implementation

You implement Draw Steel game content as importable YAML files for DMHub. This includes monsters, ongoing effects, items, conditions, abilities, and anything else stored in the compendium.

## Workflow

1. **Discuss**: When the user asks to implement content, first discuss the design. What should the abilities do? What's the best player experience? What behaviors/modifiers will achieve the desired automation?
2. **Generate**: Write YAML files to `compendium/import/<name>.yaml` for all importable
   content. Use `compendium/temp/` for working files like extracted PDF content, analysis
   reports, and implementation plans that aren't meant for direct import.
3. **Validate**: Run `python validate_yaml.py <name>.yaml` from the repo root to check for
   errors. Fix ALL errors before proceeding. The validator catches missing required fields,
   wrong table names, malformed UUIDs, and structural issues. Zero errors required.
4. **Instruct**: Tell the user to type `/import <name>.yaml` in DMHub to load it.
   The in-app `/import` also validates and refuses to import if errors are found.
5. **Iterate**: The user tests in-app, reports issues, and you refine the YAML

## File Placement Rules

**CRITICAL: Always write importable YAML to `compendium/import/`, never edit files in
`compendium/tables/` directly.** The `tables/` directory is the canonical export of what's
already in the cloud database. The `import/` directory is the staging area for new or
updated content that gets loaded via `/import`.

- **New content**: Write to `compendium/import/<name>.yaml`
- **Updates to existing content**: Copy the file from `compendium/tables/<category>/<name>.yaml`
  to `compendium/import/<name>.yaml`, make changes there, then import
- **Batch imports**: Create a manifest file (e.g., `complications-all.yaml`) using `_bundle`
  with `_include` directives referencing other files in `import/`
- **Working files**: Use `compendium/temp/` for PDFs, analysis, plans, drafts

**Bundle include syntax** (for manifest files that pull in multiple YAML files):
```yaml
_bundle:
  - _include: "outlaw.yaml"
  - _include: "mundane.yaml"
  - _include: "vow-of-duty.yaml"
```

Each `_include` resolves relative to `compendium/import/`. The included file can be a
single entry or a bundle itself. Circular includes are detected and skipped.

**The `/import` macro** supports multiple space-separated files:
```
/import outlaw.yaml mundane.yaml vow-of-duty.yaml
```
Or use a manifest:
```
/import complications-all.yaml
```

## Automation Principle

**AUTOMATE EVERYTHING.** The goal is video-game-level automation. Every ability should
resolve mechanically -- damage dealt, conditions applied, forced movement executed, resources
tracked. Text-only descriptions are a last resort when no behavior can express the mechanic.
Always look for creative ways to use existing behaviors (DrawSteelCommandBehavior, InvokeAbility,
powertabletrigger, stackable ongoing effects, multi-mode abilities) before falling back to text.

### Automation Tier Definitions

When assessing implementation quality, use these strict tier definitions. The key
principle: **if the system doesn't actually DO the thing, it's not automated.**
Floating text that says "Artifact Appears" is not automation -- it's a sticky note.

| Tier | Definition | Examples |
|------|-----------|----------|
| **GOLD** | **FULLY automated.** Every mechanical effect described in the rules text actually happens at runtime without ANY manual intervention. Stats change, damage is dealt, conditions are applied, resources are spent, items appear, rolls are modified -- all by the system. The player/Director never has to remember to do anything manually. If the rules say "you gain a treasure," the treasure actually appears in inventory. If it says "deal 5 damage," damage is actually dealt. | A modifier that actually changes a roll result. A trigger that actually deals damage. An ability that actually applies a condition. |
| **SILVER** | **Core combat/mechanical effects are automated**, but some non-combat or narrative elements require manual handling. The distinction: if it matters during a combat round or on the character sheet, it MUST be automated to qualify for Silver. Narrative flavor, Director-driven story beats, and out-of-combat social consequences can be text-only. | Combat modifier works, but "Director determines when cult finds you" is narrative. Ability deals damage automatically, but "you can cook meals during respite" is flavor text. |
| **BRONZE** | **Some mechanics are implemented but key rules-text effects are missing or faked.** This includes: floating text that SAYS something happens but doesn't actually do it, abilities that fire but don't produce the described outcome, triggers that notify but don't execute the mechanic. If a behavior shows "Artifact Appears!" as float text but no artifact actually appears, that's Bronze. | Float text saying "effect happens" without the effect. A trigger that fires but only displays a message. A modifier that exists but doesn't cover the main use case. |
| **NARRATIVE** | **No meaningful mechanical automation.** The complication is essentially a text description that the Director and players must manually adjudicate. May have a skill grant or basic attribute, but the core benefit and drawback are both unautomated. | Pure description text. "Director decides" mechanics. Manual token/resource tracking with no system support. |

**Key rules for tier assessment:**
- **Float text is NOT automation.** If a behavior's only runtime effect is displaying
  a message, that mechanic is unautomated. The tier should reflect what actually happens
  in the game engine, not what text appears on screen.
- **"Implementation: 0" or "implementation: 2" markers** in the YAML indicate the original
  author already flagged this as unimplemented or partially implemented. Respect those flags.
- **`effectImplemented` is DEPRECATED and must be completely ignored.** Do NOT read it, set
  it, or reference it in any YAML output. Use the `implementation` field exclusively
  (0 = unimplemented, 1 = narrative, 2 = partial, 3 = full). If you encounter
  `effectImplemented` in existing YAML, ignore it -- the `implementation` field is
  authoritative.
- **Assess benefit AND drawback separately.** A complication with a fully automated drawback
  but a text-only benefit (or vice versa) is at best SILVER, not GOLD.
- **Conditional modifiers count as automated** only if the condition can actually be evaluated
  by the system. A modifier with `activationCondition: "Director says so"` is not automated.
- **Skill grants and basic attribute changes alone don't make something SILVER.** If the
  interesting mechanic is the benefit/drawback beyond the skill, and that's text-only,
  it's still BRONZE or NARRATIVE.

### Implementation Plans Must Address Automation Gaps Upfront

When presenting an implementation plan for a batch of content, assess EVERY item and
flag automation gaps BEFORE implementation begins. For each item rated PARTIAL or TEXT-ONLY,
immediately present the user with:

1. What EXACTLY is the gap (which mechanic can't be automated)
2. WHY it can't be automated (what's missing from the engine)
3. What the OPTIONS are (ranked by effort), including Lua solutions
4. Ask the user what approach they want BEFORE implementing

Do NOT implement partial content and discover blockers later. The user should know upfront
what will be fully automated, what needs workarounds, and what needs Lua -- so they can
make informed decisions about where to invest effort.

### Systemic Changes Feasibility Report

When a batch of content reveals **recurring engine gaps** that block multiple items, produce
a **Systemic Changes Feasibility Report** for the user. This is especially valuable when
implementing large content sets (all complications, all titles, a full class) where the same
blocker appears across many items.

**When to offer this report:**
- When 3+ items in a batch share the same automation gap
- When the user asks about improving automation across a content category
- When a Lua change would upgrade multiple items from Bronze/Narrative to Silver/Gold

**Report format for each systemic change:**

| Field | Description |
|---|---|
| **Feature name** | Short name (e.g., "Victory Event Trigger") |
| **Goal** | What it enables in one sentence |
| **Unlocks** | Which content items benefit (with count) |
| **Confidence** | 1-10 score based on codebase research |
| **Effort** | TRIVIAL / LOW / MEDIUM / HIGH |
| **Key files** | Which Lua files need modification |
| **Approach** | Brief description of the implementation strategy |
| **Risks** | Top 1-3 unknowns or concerns |

**Confidence scoring guidelines:**
- **9-10**: Trivial change, clear pattern exists, ~3-15 lines of code
- **7-8**: Clear path, moderate changes, well-understood existing infrastructure
- **5-6**: Feasible but significant work, some unknowns in the code path
- **3-4**: Major feature, many unknowns, may require engine-level changes
- **1-2**: Speculative, may not be possible without C# engine changes

**The report should:**
1. Research the actual Lua codebase (not just reference docs) for each change
2. Identify the specific functions, files, and mechanisms involved
3. Find existing patterns that prove the approach works (or highlight why it might not)
4. Rank changes by effort-to-impact ratio so the user can prioritize
5. Recommend an implementation order (quick wins first)

### Always Offer Full Automation

When a feature can't be fully automated with existing YAML behaviors, **always offer** to
investigate a Lua implementation. Present three tiers:

1. **YAML-only** (fastest): What can be done with existing behaviors. State limitations.
2. **YAML + creative workaround**: Approximate the mechanic using existing tools (e.g.,
   `Ability.HasPotency and Ability.Inflicts("Frightened")` as an activation condition
   to approximate "when an ability inflicts frightened via potency").
3. **Lua implementation** (most complete): Offer to implement a new GoblinScript symbol,
   behavior, or modifier type. State the effort level (small = new RegisterSymbol,
   medium = new behavior type, large = engine change). Ask the user if they want to
   proceed with the Lua approach.

### Proactively Investigate the Codebase for Automation Paths

Before declaring something PARTIAL or TEXT-ONLY, **always search the Lua codebase** for
existing mechanisms that might solve the problem. The reference docs may not cover
everything -- the engine has many features that are only discoverable by reading code.

**When you hit an automation gap, follow this investigation checklist:**

1. **Search for existing triggers** that might fire at the right time:
   ```
   grep for "RegisterTrigger" in Draw Steel Core Rules/*.lua and DMHub Game Rules/*.lua
   ```
   Every `RegisterTrigger{id = "...", symbols = {...}}` defines a trigger with its
   available GoblinScript symbols. There may be a trigger you don't know about that
   solves your problem (e.g., `targetwithability` fires per-target with the ability
   and target as symbols).

2. **Search for existing GoblinScript symbols** on the relevant object:
   ```
   grep for "RegisterSymbol" or "RegisterGoblinScriptSymbol" or "helpSymbols" in *.lua
   ```
   Check `help` tables in registrations -- they document name, type, and description.
   Key files:
   - Abilities: `MCDMActivatedAbility.lua`, `ActivatedAbility.lua`
   - Creatures: `MCDMCreature.lua`, `Creature.lua`
   - Cast context: `ActivatedAbilityCast.lua`, `MCDMActivatedAbilityCast.lua`
   - Power rolls: `MCDMAbilityRollBehavior.lua`
   - Conditions: `Condition.lua`

3. **Search for existing custom attributes** that control the mechanic:
   ```
   grep for the mechanic name in compendium/tables/customattributes/_table.yaml
   ```
   Many mechanics are controlled by custom attributes (e.g., `cannotregainstamina`,
   `ignoredifficultterrain`, `immunityfromopportunityattack`).

4. **Search for how similar existing content solves the same problem:**
   ```
   grep for the mechanic in compendium/bestiary/ or compendium/tables/
   ```
   If another monster or class feature does something similar, study its YAML.

5. **Check the DispatchEvent calls** in the Lua code:
   ```
   grep for "DispatchEvent" in DMHub Game Rules/*.lua
   ```
   Every DispatchEvent creates an event that triggers can listen for. The event name
   maps to a trigger ID.

6. **Check what symbols are passed to lookup functions** in modifier evaluation code:
   ```
   grep for "LookupSymbol" in the relevant modifier/behavior code
   ```
   This shows exactly what GoblinScript context is available.

**The reference docs are a starting point, not the final answer.** The Lua codebase is
the source of truth. When the docs say "PARTIAL" or "TEXT-ONLY", that's a prompt to
investigate whether the engine already has a solution that wasn't documented.

### Ability Targeting Must Match Rules Text

**CRITICAL:** Set `targetAllegiance` based on the EXACT rules text "Target:" line:

| Rules Text | targetAllegiance | objectTarget |
|-----------|-----------------|-------------|
| "One creature" | omit (any creature) | false |
| "One creature or object" | omit (any creature) | true |
| "One enemy" or "Each enemy" | enemy | false |
| "One ally" or "Self and one ally" | ally | false (+ selfTarget if self included) |

**"creature" means ANY creature** -- ally, enemy, or neutral. Do NOT set
`targetAllegiance: enemy` unless the rules text explicitly says "enemy."
Most offensive abilities (strikes) say "creature or object" which means the
player CAN target allies or objects if they choose. Let the player decide.

### Movement Between Targets (sequentialTargeting)

When an ability says "movement can be broken up before, after, and between each target",
use `sequentialTargeting: true`. This makes the ability resolve targets one at a time with
movement allowed between each. The player gets "Choose Target 1/N", "Choose Target 2/N"
prompts and can shift/move between each selection.

For "move before OR after" (binary choice), use `multipleModes: true` with `variation`
fields on the modeList entries (see Angulotl Hopper's Leapfrog for this pattern).

### Key Ability GoblinScript Fields (for power roll modifier activationCondition)

In power roll modifier context, `Ability` is available with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `Ability.Keywords has "X"` | Set check | Check ability keywords |
| `Ability.Inflicts("X")` | Function | Check if ability inflicts a named condition |
| `Ability.HasPotency` | Boolean | Whether ability uses potency checks |
| `Ability.Does Damage` | Boolean | Whether ability deals rolled damage |
| `Ability.Has Forced Movement` | Boolean | Whether ability includes push/pull/slide |
| `Ability.Free Strike` | Boolean | Whether this is a free strike |
| `Ability.Action` | Boolean | Whether this costs an Action |
| `Ability.Maneuver` | Boolean | Whether this costs a Maneuver |
| `Ability.Heroic` | Boolean | Whether this is a Heroic Ability |
| `Ability.Categorization` | Text | "Signature Ability", "Heroic Ability", etc. |
| `Ability.Damage Types has "X"` | Set check | What damage types the ability deals |
| `Ability.Name` | Text | Ability name |
| `Ability.Range` | Number | Range in squares |

Example: to check if an ability inflicts frightened via potency (approximate):
```
Ability.HasPotency and Ability.Inflicts("Frightened")
```

For exact "inflicts via potency" checking, offer to implement a custom GoblinScript
symbol like `Ability.InflictsBasedOnPotency("Frightened")` via Lua.

## Key References

Read SELECTIVELY based on what you're implementing:

**Always read:**
| File | What it contains |
|---|---|
| `compendium/reference/CORE.md` | **READ FIRST.** Common pitfalls, UUID maps, table names, GoblinScript booleans, import workflow |

**For monsters/abilities:**
| File | What it contains |
|---|---|
| `compendium/reference/MONSTERS.md` | Monster YAML, all behavior types, targeting, power rolls, auras, modifiers, triggers, ongoing effects, rules engine commands |

**For character options (classes, ancestries, kits, etc.):**
| File | What it contains |
|---|---|
| `compendium/reference/CHARACTERS.md` | Classes, subclasses, ancestries, kits, complications, titles, treasures -- YAML structures and feature types |

**For GoblinScript formulas:**
| File | What it contains |
|---|---|
| `compendium/reference/GOBLINSCRIPT-SYMBOLS.md` | **ALL creature symbols** (200+): stats, characteristics, resources, conditions, movement, custom attributes |
| `compendium/reference/GOBLINSCRIPT-ABILITY-SYMBOLS.md` | **ALL non-creature symbols**: Ability, Cast, Kit, Equipment, Attack (100+ across 14 types) |
| `compendium/reference/GOBLINSCRIPT-CONTEXTS.md` | **Which symbols are available WHERE**: maps every YAML formula field to its available symbols |
| `GoblinScript_Guide.md` | GoblinScript syntax, operators, evaluation model |

**CRITICAL:** When writing ANY GoblinScript formula, ALWAYS:
1. Check GOBLINSCRIPT-CONTEXTS.md to know what symbols are available in that specific field
2. Check GOBLINSCRIPT-SYMBOLS.md for the exact symbol name (with spaces!)
3. Understand what "Self" means in that context (the creature being evaluated, NOT always the caster)
4. NEVER guess symbol names -- always verify against the reference

**Other references (read as needed):**
| File | What it contains |
|---|---|
| `compendium/RULES_REFERENCE.md` | Draw Steel game rules (combat, conditions, power rolls, monster/encounter building) |
| `compendium/bestiary/<name>.yaml` | Example monster files -- study for exact YAML patterns |
| `compendium/tables/` | Example compendium entries by type |

## Critical Rules

### Critical Pitfalls (Read First!)

Before generating any YAML, review the "Common Pitfalls" section in `compendium/REFERENCE.md`.
The most common errors:

1. **Table names are case-sensitive** -- `characterOngoingEffects` not `characterongoingeffects`
2. **Aura durations != ongoing effect durations** -- auras use `nextturn`/`endnextturn`/`eoe`;
   ongoing effects use `end_of_next_turn`/`eoe`/`save_ends`
3. **Stability attribute** = `forcedmoveresistance` (NOT `stability`)
4. **GoblinScript booleans** -- use `1`/`0` in quoted strings. YAML boolean `true`/`false`
   (unquoted) works for boolean fields like `activationCondition`, but quoted `"true"` fails.
5. **`iconid` is REQUIRED** on CharacterOngoingEffect -- crashes if missing. Default: `bc90bb09-9e3c-46d4-bf16-0e5c0134dbf8`
6. **`display` table is REQUIRED** on CharacterOngoingEffect
7. **`reasonedFilters` replaces `targetFilter`** -- don't use both for the same restriction
8. **`ongoingEffectCustom`** is editor-only state; has NO runtime effect

### ASCII Only
All YAML content must be pure ASCII (bytes 0-127). No em dashes, curly quotes, ellipses, or Unicode. Use `-` not `--`, `"` not curly quotes, `...` not ellipsis.

### UUID Generation
Generate fresh UUIDs for all new entities. Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (lowercase hex). Maintain internal consistency -- if an ability references an ongoing effect, the UUIDs must match.

### Reference Existing UUIDs
For standard conditions, damage types, action resources, and common ongoing effects, use the UUIDs from the reference maps in `compendium/REFERENCE.md`. Never generate new UUIDs for these -- always reference the existing ones.

### Monster YAML Format
Monsters use the `MonsterAsset` C# struct format with `info:` at the top level. Study existing monsters in `compendium/bestiary/` for exact structure. Key fields:
- `info.properties.innateActivatedAbilities` -- the monster's abilities
- `info.properties.characterFeatures` -- traits (passive features using CharacterModifier)
- `info.properties.attributes` -- characteristic scores
- `info.properties.keywords` -- creature keywords
- `description` -- the monster's display name
- `id` -- unique UUID for this monster

### Table Entry YAML Format
Table entries (ongoing effects, conditions, items, etc.) must include a `_table:` metadata field.

**CRITICAL: Table names are case-sensitive.** Always look up the exact name from
`compendium/REFERENCE.md` "Common Table Names". Do NOT guess from directory names
(directories are lowercased, but table names have mixed casing).

Common table names: `characterOngoingEffects`, `charConditions`, `standardAbilities`,
`tbl_Gear`, `MonsterGroup`, `Skills`, `globalRuleMods`, `customAttributes`, `Deities`.

```yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: <uuid>
...
```

### Bundle Format
For content that requires multiple entries (e.g., a monster + custom ongoing effects):
```yaml
_bundle:
  - info:
      ...
    description: "Monster Name"
    id: <uuid>
  - _table: characterOngoingEffects
    __typeName: CharacterOngoingEffect
    id: <uuid>
    ...
```

## Power Roll Tiers

Draw Steel abilities use power rolls (2d10 + characteristic) with three tiers of outcomes. In the YAML:

```yaml
- __typeName: ActivatedAbilityPowerRollBehavior
  roll: 2d10 + Might
  attrid: mgt
  tiers:
    - "5 damage"                           # Tier 1 (<= 11)
    - "9 damage; push 2"                   # Tier 2 (12-16)
    - "12 damage; push 4; M<2 prone"       # Tier 3 (17+)
```

### Tier String Syntax
Tier strings describe outcomes using semicolons to separate effects:
- `X damage` -- deal X damage
- `X [type] damage` -- deal typed damage (e.g., `8 fire damage`)
- `push/pull/slide X` -- forced movement
- `vertical push X` -- vertical forced movement
- `[condition] (save ends)` -- apply condition with save ends duration
- `[condition] (EoT)` -- apply condition until end of target's next turn
- `A<X [effect]` -- apply effect only if target's Agility < X (potency check)
- `M<X [effect]` -- Might potency check
- `I<X [effect]` -- Intuition potency check
- `P<X [effect]` -- Presence potency check

### Separate Condition Application
For complex conditions, use a separate `ActivatedAbilityApplyOngoingEffectBehavior` with `tiersSelected`:
```yaml
- __typeName: ActivatedAbilityApplyOngoingEffectBehavior
  tiersSelected: [1, 2]        # Apply on tiers 1 and 2 only (1-indexed)
  ongoingEffect: <effect-uuid>
  duration: save_ends
```

## Damage Formulas

### Monster Damage Scaling (from rules)
- **Formula**: (4 + Level + Damage Modifier) x Tier Modifier
- Tier Modifiers: T1 = 0.6, T2 = 1.1, T3 = 1.4
- Strikes: add highest characteristic
- Horde/Minion: divide by 2

### Target Adjustments
- +1 target over expected: damage x 0.8
- +2 or more extra: damage x 0.5
- -1 target: damage x 1.2

## Ability Categorization Values

| Value | Use |
|---|---|
| `Signature Ability` | Core/signature attack ability |
| `Heroic Ability` | Resource-costing special ability |
| `Villain Action` | Villain action (leaders/solos) |
| `Hidden` | Internal helper abilities |
| `Ability` | Generic ability |
| `Trait` | Passive trait (no action cost) |

## Villain Actions

Leaders and Solos have exactly 3 villain actions. Each needs:
```yaml
villainAction: "Villain Action 1"    # or 2, 3
categorization: "Villain Action"
usageLimitOptions:
  resourceid: <unique-uuid>          # Each VA needs its own resource UUID
  charges: "1"
  resourceRefreshType: encounter
```

## Traits (Passive Features)

Traits are stored in `characterFeatures` as `CharacterFeature` objects with modifiers:
```yaml
characterFeatures:
  - __typeName: CharacterFeature
    name: "Trait Name"
    guid: <uuid>
    modifiers:
      - __typeName: CharacterModifier
        behavior: <modifier-type>
        name: "Trait Name"
        guid: <uuid>
        sourceguid: <feature-guid>
        source: Trait
        domains:
          "CharacterFeature:<feature-guid>": true
        ...
```

## Common Patterns

### Melee Strike Ability
```yaml
- __typeName: ActivatedAbility
  name: "Claw"
  guid: <uuid>
  actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
  targeting: direct
  targetType: enemies
  numTargets: "1"
  range: 1
  keywords: { Melee: true, Strike: true, Weapon: true }
  categorization: "Signature Ability"
  behaviors:
    - __typeName: ActivatedAbilityPowerRollBehavior
      roll: "2d10 + 2"
      attrid: mgt
      tiers: ["5 damage", "9 damage", "12 damage"]
```

### Ranged Magic Attack
```yaml
- __typeName: ActivatedAbility
  name: "Fire Bolt"
  guid: <uuid>
  actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
  targeting: direct
  targetType: enemies
  numTargets: "1"
  range: 10
  keywords: { Ranged: true, Strike: true, Magic: true, Fire: true }
  categorization: "Signature Ability"
  behaviors:
    - __typeName: ActivatedAbilityPowerRollBehavior
      roll: "2d10 + 2"
      attrid: rea
      tiers: ["5 fire damage", "9 fire damage", "12 fire damage"]
```

### Area Attack (Burst)
```yaml
- __typeName: ActivatedAbility
  name: "Thunderclap"
  guid: <uuid>
  actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
  targeting: area
  targetType: enemies
  range: 3
  keywords: { Area: true, Magic: true }
  categorization: "Ability"
  behaviors:
    - __typeName: ActivatedAbilityPowerRollBehavior
      resistanceRoll: true
      roll: "2d10 + 2"
      attrid: mgt
      tiers: ["3 sonic damage", "6 sonic damage", "9 sonic damage; M<2 prone"]
```

### Ability That Invokes Another
For complex abilities that chain actions (attack then ally moves, etc.):
```yaml
behaviors:
  - __typeName: ActivatedAbilityPowerRollBehavior
    roll: "2d10 + 2"
    tiers: ["5 damage", "9 damage", "12 damage"]
  - __typeName: ActivatedAbilityInvokeAbilityBehavior
    # Invokes a sub-ability for the secondary effect
```

### Triggered Ability (as Trait)
```yaml
characterFeatures:
  - __typeName: CharacterFeature
    name: "Reactive Strike"
    guid: <uuid>
    modifiers:
      - __typeName: CharacterModifier
        behavior: trigger
        sourceguid: <feature-guid>
        source: Trait
        domains:
          "CharacterFeature:<feature-guid>": true
        triggeredAbility:
          __typeName: TriggeredAbility
          name: "Reactive Strike"
          guid: <uuid>
          trigger: move
          subject: enemy
          subjectRange: "1"
          targetType: subject
          mandatory: true
          behaviors:
            - __typeName: ActivatedAbilityDamageBehavior
              roll: "5"
              damageType: force
```

## Flat Damage Bonuses

Use `damageModifier` on a power modifier to add flat damage:

```yaml
- __typeName: CharacterModifier
  behavior: power
  modtype: none
  rollType: ability_power_roll
  damageModifier: "6"               # GoblinScript formula
  damageModifierType: "none"        # "none" = add to existing damage type
  activationCondition: "Target.Object"  # Only vs objects
  keywords:
    Strike: true                    # Only for strikes
```

## Stackable Ongoing Effects

For effects that accumulate (e.g., increasing weakness each use):

```yaml
__typeName: CharacterOngoingEffect
stackable: true
clearStacksWhenApplying: false     # false = additive stacking
modifiers:
  - __typeName: CharacterModifier
    behavior: power
    modtype: none
    rollType: enemy_ability_power_roll
    damageModifier: "Stacks * 3"   # Scales with stack count
```

Access stacks in GoblinScript: `Stacks` (in modifier formulas) or `Stacks("Effect Name")` (in creature context).

## Auras (Difficult Terrain, Hazards, Zones)

Use `ActivatedAbilityAuraBehavior` to create persistent map zones with terrain effects:

```yaml
- __typeName: ActivatedAbilityAuraBehavior
  duration: eoe                  # nextturn, eoe, or number of rounds
  aliveafterdeath: true          # Persists after caster dies
  aura:
    __typeName: Aura
    name: "Zone Name"
    guid: <uuid>
    objectid: "c994501f-85ec-475e-b9f6-8113a814f8d1"  # Blank (default)
    difficult_terrain: true      # Makes area difficult terrain
    applyto: enemies             # all, allother, enemies, friends, etc.
    modifiers: []
    triggers: []
```

**Note:** The `objectid` specifies the visual representation on the map. Use the Blank object
(`c994501f-85ec-475e-b9f6-8113a814f8d1`) as a default, but tell the user they can add a
custom object to the Auras folder in DMHub and update the ability to use it.

Other aura options: `movedamage`/`damage` (damage per square moved), `blocks_line_of_effect`
(cover), `blocks_movement` (wall). See `compendium/REFERENCE.md` for full field list.

## Power Table Effects (DrawSteelCommandBehavior)

The **preferred way** to apply game effects (shift, forced movement, conditions, damage)
is via `ActivatedAbilityDrawSteelCommandBehavior`. It goes through the full rules engine,
respecting all game state (can't shift while slowed, stability vs forced movement, etc.):

```yaml
- __typeName: ActivatedAbilityDrawSteelCommandBehavior
  rule: "shift 3; prone"    # Shift 3 then knock prone
  applyto: targets
```

**Supported commands:** damage (`5 fire damage`), push/pull/slide (`push 3`),
shift (`shift 2`), teleport (`teleport 5`), conditions (`slowed (eot)`),
potency gates (`M<2 prone`), surges, heroic resources, and more.

**GoblinScript interpolation:** `{expression}` anywhere -- e.g., `push {Reason}`, `{Might} damage`.

**Compound rules:** Separate with `;` -- e.g., `2 damage; A<2 prone; push 3`.

See `compendium/REFERENCE.md` "Power Table Effect / Rules Engine Commands" for full syntax.

## Design Philosophy

When implementing content:

1. **Maximize automation**: Use behaviors and modifiers to automate as much as possible. Players should get the full experience of the ability without manual bookkeeping.

2. **Use existing ongoing effects**: Check the UUID reference maps for standard effects (Bleeding, Slowed, etc.) before creating custom ones.

3. **Study similar existing content**: Before implementing a monster, find a similar one in the bestiary and study its patterns. An Ambusher at level 3 should look similar to other level 3 Ambushers.

4. **Match the damage formulas**: Use the scaling formulas from the rules to ensure damage values are balanced for the monster's level and organization.

5. **Consider the player experience**: Discuss with the user how an ability should feel in play. Should a multi-target ability resolve all at once or one-by-one? Should a villain action have dramatic flair?

6. **Be innovative with behaviors**: Complex abilities can be built by chaining behaviors creatively. The InvokeAbility behavior is especially powerful for multi-step abilities. DrawSteelCommandBehavior can parse rule text like "push 3" or "prone (save ends)".

7. **Use reasonedFilters for targeting restrictions**: When an ability has targeting restrictions (e.g., "only elementals", "only grabbed creatures"), use `reasonedFilters` to show explanatory text instead of silently filtering via `targetFilter`. Do NOT use both for the same restriction -- `targetFilter` silently hides targets, preventing the reason text from ever appearing.
```yaml
# GOOD: user sees "This ability can only target elementals" on invalid targets
reasonedFilters:
  - reason: "This ability can only target elementals."
    formula: 'Keywords has "Elemental"'

# BAD: targetFilter hides non-elementals entirely, reasonedFilters never fires
targetFilter: 'Keywords has "Elemental"'
reasonedFilters:
  - reason: "This ability can only target elementals."
    formula: 'Keywords has "Elemental"'
```
