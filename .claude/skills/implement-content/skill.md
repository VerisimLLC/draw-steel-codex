---
name: implement-content
description: Implement compendium content for DMHub -- monsters, items, ongoing effects, abilities, and other game data. Use when asked to "implement a monster", "create a creature", "build an item", "add a compendium entry", or generate any Draw Steel game content as YAML data.
metadata:
  author: draw-steel-codex
  version: "1.0.0"
  argument-hint: <content-description>
---

# Compendium Content Implementation

You implement Draw Steel game content as YAML files in DMHub's live `data/` content store.
This includes monsters, ongoing effects, items, conditions, abilities, and anything else
stored in the compendium.

## Workflow

1. **Discuss**: When the user asks to implement content, first discuss the design. What should the abilities do? What's the best player experience? What behaviors/modifiers will achieve the desired automation?
2. **Implement directly in `data/`**: `data/` is the live content store (see "Where Content
   Lives" below). Create or edit the YAML file directly in the correct `data/` subfolder.
   There is NO import step -- the file you write IS the content.
3. **Validate**: Run `python validate_yaml.py --base-dir . data/<path>/<file>.yaml` from the
   repo root to check for errors. Fix ALL errors before proceeding. The validator catches
   missing required fields, wrong table names, malformed UUIDs, and structural issues. Zero
   errors required.
4. **It applies live**: Editing a file in `data/` takes effect in the running DMHub instance
   automatically -- no `/import`, no `dmhub.ImportFile`, no upload. Do NOT tell the user to
   import anything.
5. **Iterate**: The user tests in-app, reports issues, and you refine the same file in
   `data/`, then they test again.

## Where Content Lives: the `data/` Submodule

`data/` is a **git submodule** (the standalone `draw-steel-data` repo -- the export of the
master "Great Library" game). It holds ALL compendium content as human-readable YAML, and
the running dev instance reads it live. **Editing a file here is completely safe:** because
it is its own git repo, any change can be reverted with `git -C data checkout <file>` (or
inspected with `git -C data diff`). Edit freely.

**Layout:**

| Content | Location |
|---|---|
| Monsters/creatures | `data/monsters/<uuid>.yaml` (one MonsterAsset per file) |
| Table entries (conditions, ongoing effects, items, abilities, classes, kits, titles, etc.) | `data/objectTables/<tablefolder>/<slug-or-uuid>.yaml` |
| Reference documentation | `data/docs/` (see "Key References" below) |

**Folder name vs `_table:` casing.** Under `data/objectTables/`, folder names are
**lowercased** (e.g. `characterongoingeffects/`, `charconditions/`, `tbl-gear/`), but the
`_table:` metadata field inside each file keeps the **canonical mixed-case** name
(`characterOngoingEffects`, `charConditions`, `tbl_Gear`). Always set `_table:` to the
canonical name from `data/docs/reference/CORE.md`, not the lowercased folder name.

**Creating vs editing:**
- **New content**: The most reliable way is to **copy the nearest existing file in the
  target folder as a template** and modify it (fresh `id`, name, stats, behaviors) -- this
  guarantees you carry the full envelope (all required fields) correctly. Name the new file
  with a human slug (`my-monster.yaml`) or a UUID; the authoritative id is the `id:` field
  inside, not the filename.
- **Editing existing content**: Find the file in `data/` (by slug filename, or grep for its
  `id:`/name) and edit it in place. It is already the live content.

**Working files** (extracted PDF text, analysis, implementation plans -- NOT content): keep
these OUT of the `data/` submodule. Use `compendium/temp/` or your scratchpad.

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
1. **Delegate research to the `Explore` subagent** -- give it the list of
   candidate changes and ask it to return, per change: specific
   functions/files/mechanisms involved, an existing pattern that proves the
   approach works (or a note on why it might not), and any risks. Your job
   is to synthesize Explore's findings into the report -- do not read the
   Lua files yourself. See "Investigating Automation Paths" below for how
   to shape the Explore prompt.
2. Identify the specific functions, files, and mechanisms involved (from Explore).
3. Find existing patterns that prove the approach works -- or highlight why
   it might not -- from Explore's findings.
4. Rank changes by effort-to-impact ratio so the user can prioritize.
5. Recommend an implementation order (quick wins first).

### Always Offer Full Automation

When a feature can't be fully automated with existing YAML behaviors, **always offer** to
investigate a Lua implementation. Present three tiers:

1. **YAML-only** (fastest): What can be done with existing behaviors. State limitations.
2. **YAML + creative workaround**: Approximate the mechanic using existing tools (e.g.,
   `Ability.HasPotency and Ability.Inflicts("Frightened")` as an activation condition
   to approximate "when an ability inflicts frightened via potency").
3. **Lua implementation** (most complete): Offer to extend the engine -- a new
   GoblinScript symbol, behavior type, modifier type, trigger, or custom attribute.
   State the effort level (small = new RegisterSymbol, medium = new behavior type,
   large = engine change). If the user accepts, delegate the Lua work to a subagent
   per the "Lua Implementation Handoff Protocol" below -- do NOT implement it inline.
   Your context should stay focused on YAML and rules logic.

### Lua Implementation Handoff Protocol

When the user accepts a Tier-3 Lua implementation, hand the work off to a subagent.
Your context should stay focused on YAML and rules logic -- do not read or edit
Lua source files yourself.

**Use the `general-purpose` Agent** with a prompt that explicitly directs it to
invoke the right existing skill:
- **New GoblinScript symbol** (most common case) -- direct the agent to invoke
  the `goblinscript` skill.
- **New behavior, modifier, trigger, custom attribute, or anything else** --
  direct the agent to invoke the `codexmod` skill.

**The handoff prompt MUST include:**

1. **Blocker**: the YAML feature that's currently inexpressible, in one sentence.
2. **Proposed extension shape**: what kind of Lua addition you're requesting
   (new symbol with a specific name and arguments / new behavior `__typeName` /
   new trigger id / new custom attribute key).
3. **Acceptance criteria**: a YAML snippet showing what should work after the
   change. This is the contract.
4. **Skill instruction**: "Invoke the `goblinscript` skill" or "Invoke the
   `codexmod` skill" depending on the kind of work.
5. **Return contract**: tell the subagent what to report back -- the final
   symbol name and arguments (or behavior `__typeName` and fields), and any
   caveats or naming differences from what you proposed.

**Example handoff prompt:**

> Blocker: a power-roll modifier needs to check whether an ability inflicted a
> named condition via a potency check that succeeded, not just whether the
> ability lists the condition.
>
> Proposed extension: a new GoblinScript symbol on `Ability` named
> `InflictsBasedOnPotency(conditionName)` returning boolean.
>
> Acceptance criteria -- this YAML should work after your change:
> ```yaml
> activationCondition: 'Ability.InflictsBasedOnPotency("Frightened")'
> ```
>
> Invoke the `goblinscript` skill to implement this. When done, report: the
> final symbol name (in case it had to differ), its argument signature, and
> any edge cases the YAML author should know about (e.g., what it returns
> if potency wasn't rolled).

Once the subagent reports back, wire the new API into the YAML and re-run
`python validate_yaml.py`. Trust the subagent's report -- do not re-read the
Lua files to verify. If runtime behavior doesn't match expectations, re-engage
the implementation subagent with the specific failure case, or send a follow-up
Explore query if you need to understand a related mechanic.

### Investigating Automation Paths (Lua Research)

Before declaring something PARTIAL or TEXT-ONLY, investigate whether the engine
already has a mechanism that solves the problem. The reference docs don't cover
everything -- many features are only discoverable in Lua source.

**Delegate Lua research to the `Explore` subagent.** Keep your own context focused
on YAML and rules logic. Inline grep is acceptable only for a single targeted
lookup ("does the symbol `Ability.InflictsBasedOnPotency` exist?"). Anything
beyond ~2 reads, or any open-ended question ("how does push interact with
stability?"), goes to Explore.

**Question-shaping rules for Explore prompts.** A poorly scoped delegation
wastes a round-trip. Each Explore prompt must:

1. State the YAML feature you're trying to express in one sentence (the *blocker*).
2. Ask a specific, answerable question -- not "how does X work" but "is there
   a trigger that fires when a creature is reduced to 0 stamina, and what
   GoblinScript symbols does it expose?"
3. Tell Explore what shape of answer you need: symbol name + arguments, or
   trigger id + symbols, or "the file/line where the existing pattern lives."
4. Cap the response: "report in under 150 words; include only what's needed
   to write the YAML."

**Where to point Explore (pick the one that matches the question -- do not
list all of these in a single prompt):**

| Question | Where Explore should look |
|---|---|
| Is there a trigger for event X? | `RegisterTrigger` calls in `Draw Steel Core Rules/*.lua`, `DMHub Game Rules/*.lua` |
| Is there a GoblinScript symbol Y on object Z? | `RegisterSymbol` / `helpSymbols` in `MCDMActivatedAbility.lua`, `ActivatedAbility.lua`, `MCDMCreature.lua`, `Creature.lua`, `ActivatedAbilityCast.lua`, `MCDMActivatedAbilityCast.lua`, `MCDMAbilityRollBehavior.lua`, `Condition.lua` |
| Does a custom attribute control mechanic X? | `data/objectTables/customattributes/` |
| Does similar content already solve this? | `data/monsters/`, `data/objectTables/` |
| What event fires at point X? | `DispatchEvent` calls in `DMHub Game Rules/*.lua` |
| What symbols are passed to a modifier formula? | `LookupSymbol` calls in the relevant modifier/behavior code |

The Lua codebase is the source of truth -- but it's Explore's job to read it,
not yours. Your job is to ask the right question and translate the answer into
YAML. If Explore's answer reveals that no existing mechanism solves the
problem, that's the cue to offer Tier-3 (see "Always Offer Full Automation")
and, if the user accepts, follow the "Lua Implementation Handoff Protocol".

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

All reference docs live in the `data/` submodule under `data/docs/`.

**Always read:**
| File | What it contains |
|---|---|
| `data/docs/reference/CORE.md` | **READ FIRST.** Common pitfalls, UUID maps, table names, GoblinScript booleans |

**For monsters/abilities:**
| File | What it contains |
|---|---|
| `data/docs/reference/MONSTERS.md` | Monster YAML, all behavior types, targeting, power rolls, auras, modifiers, triggers, ongoing effects, rules engine commands |

**For character options (classes, ancestries, kits, etc.):**
| File | What it contains |
|---|---|
| `data/docs/reference/CHARACTERS.md` | Classes, subclasses, ancestries, kits, complications, titles, treasures -- YAML structures and feature types |

**For GoblinScript formulas:**
| File | What it contains |
|---|---|
| `data/docs/reference/GOBLINSCRIPT-SYMBOLS.md` | **ALL creature symbols** (200+): stats, characteristics, resources, conditions, movement, custom attributes |
| `data/docs/reference/GOBLINSCRIPT-ABILITY-SYMBOLS.md` | **ALL non-creature symbols**: Ability, Cast, Kit, Equipment, Attack (100+ across 14 types) |
| `data/docs/reference/GOBLINSCRIPT-CONTEXTS.md` | **Which symbols are available WHERE**: maps every YAML formula field to its available symbols |
| `data/GoblinScript_Guide.md` | GoblinScript syntax, operators, evaluation model |

**CRITICAL:** When writing ANY GoblinScript formula, ALWAYS:
1. Check GOBLINSCRIPT-CONTEXTS.md to know what symbols are available in that specific field
2. Check GOBLINSCRIPT-SYMBOLS.md for the exact symbol name (with spaces!)
3. Understand what "Self" means in that context (the creature being evaluated, NOT always the caster)
4. NEVER guess symbol names -- always verify against the reference

**Other references (read as needed):**
| File | What it contains |
|---|---|
| `data/docs/RULES_REFERENCE.md` | Draw Steel game rules (combat, conditions, power rolls, monster/encounter building) |
| `data/monsters/<uuid>.yaml` | Example monster files -- study for exact YAML patterns |
| `data/objectTables/<tablefolder>/` | Example compendium entries by type |

## Critical Rules

### Critical Pitfalls (Read First!)

Before generating any YAML, review the "Common Pitfalls" section in `data/docs/reference/CORE.md`.
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

### Modifier Name Must Match Parent Feature

**Every `CharacterModifier`'s `name` field MUST match its parent `CharacterFeature.name`
verbatim.** The character-sheet bonus-listing UI groups modifiers by name. If a feature
"Gift of Elder Sorcery" has children named "Speed Bonus", "Range Bonus", "Stamina Bonus",
they appear as scattered rows in the bonus list instead of one clean block under the
feature heading.

```yaml
# CORRECT
- __typeName: CharacterFeature
  name: Gift of Elder Sorcery
  modifiers:
    - __typeName: CharacterModifier
      behavior: attribute
      name: Gift of Elder Sorcery     # matches feature
      attribute: speed
      value: 1
    - __typeName: CharacterModifier
      behavior: power
      name: Gift of Elder Sorcery     # matches feature
      damageModifier: "2"
      keywords: { Ranged: true }

# WRONG -- separate rows in the bonus listing
- __typeName: CharacterFeature
  name: Gift of Elder Sorcery
  modifiers:
    - __typeName: CharacterModifier
      name: Speed Bonus               # diverges -> ungrouped
    - __typeName: CharacterModifier
      name: Ranged Damage Bonus       # diverges -> ungrouped
```

**Scope and exceptions:**

- Applies to `behavior: attribute`, `behavior: power`, `behavior: resource`,
  `behavior: trigger`, `behavior: activated`, `behavior: proficiency` -- any direct
  child of `CharacterFeature.modifiers[]`.
- For `behavior: trigger`, only the **outer** `CharacterModifier.name` matches the
  feature. The inner `triggeredAbility.name` is a separate display label (used in
  chat / triggerPrompt) and is allowed to differ. Example: feature "Focus" -> outer
  `CharacterModifier.name: Focus` -> inner `triggeredAbility.name: "Draw Steel"`
  (Tactician's start-of-combat trigger).
- For `behavior: activated`, same pattern -- outer modifier name matches the feature,
  the inner `activatedAbility.name` is the ability's display name.
- Modifiers nested deeper (e.g. inline `ActivatedAbility.modifiers[]` for per-ability
  roll-dialog options like a "1 Zeal" damage rider) follow a different convention --
  those surface as roll-dialog checkboxes and are typically labelled descriptively.
  This rule only applies to direct `CharacterFeature.modifiers[]` children.

### ASCII Only
All YAML content must be pure ASCII (bytes 0-127). No em dashes, curly quotes, ellipses, or Unicode. Use `-` not `--`, `"` not curly quotes, `...` not ellipsis.

**Caveat for existing `data/` files:** some exported content already contains Unicode (e.g.
curly apostrophes in ability names), so `validate_yaml.py` may report a non-ASCII error on a
line you never touched when you edit an existing file. That's a pre-existing export artifact,
not something your edit introduced -- keep your OWN additions ASCII, and don't churn unrelated
Unicode lines just to silence the check.

### UUID Generation
Generate fresh UUIDs for all new entities. Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (lowercase hex). Maintain internal consistency -- if an ability references an ongoing effect, the UUIDs must match.

### Reference Existing UUIDs
For standard conditions, damage types, action resources, and common ongoing effects, use the UUIDs from the reference maps in `data/docs/reference/CORE.md`. Never generate new UUIDs for these -- always reference the existing ones.

### Monster YAML Format
Monsters live in `data/monsters/<uuid>.yaml`, one `MonsterAsset` per file, with `info:` at the
top level. **Copy an existing `data/monsters/*.yaml` as a template** for a new monster -- the
envelope has many required fields, and copying guarantees you get them all. Key fields:
- `info.properties.monster_type` -- **the monster's display name** (e.g. `Sprite Olyender`).
  NOTE: in the live `data/` format, the top-level `description` is `null` -- the name is here,
  not in `description`.
- `info.properties.innateActivatedAbilities` -- the monster's abilities
- `info.properties.characterFeatures` -- traits (passive features using CharacterModifier)
- `info.properties.attributes` -- characteristic scores
- `info.properties.keywords` -- creature keywords
- `parentFolder` -- UUID of the containing folder under `data/monsterFolders/` (carry over
  the template's value, or set to an existing monster folder's id)
- `id` -- unique UUID for this monster (also used as the filename when UUID-named)

### Table Entry YAML Format
Table entries (ongoing effects, conditions, items, etc.) must include a `_table:` metadata field.

**CRITICAL: Table names are case-sensitive.** Always look up the exact name from
`data/docs/reference/CORE.md` "Table Names". Do NOT guess from the `data/objectTables/`
folder names (those folders are lowercased, but the `_table:` value has mixed casing).

Common table names: `characterOngoingEffects`, `charConditions`, `standardAbilities`,
`tbl_Gear`, `MonsterGroup`, `Skills`, `globalRuleMods`, `customAttributes`, `Deities`.

```yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: <uuid>
...
```

### Multiple Related Entries
When content requires more than one entry (e.g., a monster plus a custom ongoing effect it
applies), each entry is its **own file in its own `data/` folder** -- there is no `_bundle`
wrapper in the direct-edit workflow. Keep the cross-referenced UUIDs consistent between them:

- Monster -> `data/monsters/<monster-uuid>.yaml` (references the effect's UUID in its ability)
- Custom ongoing effect -> `data/objectTables/characterongoingeffects/<effect-slug>.yaml`
  (with `_table: characterOngoingEffects` and matching `id: <effect-uuid>`)

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

Tier strings (and DrawSteelCommand rule strings) describe outcomes built from clauses joined by separators. **Choose the separator deliberately -- the parser distinguishes them.**

#### Separators (CRITICAL)

| Separator | Meaning | Example |
|---|---|---|
| `;` | **Hard break** between disjoint clauses. Each side resolves independently. | `5 damage; push 3; M<{Weak}, prone` |
| `,` *or* a bare space | **Soft link** binding a potency gate to its conditional effect. | `M < {Weak}, grabbed` or `M<[Weak] prone` |
| `:` | **NEVER use as a separator.** Silently misparses -- the parser treats it as a hard break, severing the gate from its effect, so the condition either fires unconditionally or is dropped. No validation error fires. | WRONG: `M < {Weak}: grabbed` |

**Rule of thumb:** `;` is for "and also" between independent things; `,` (or space) is for "if the gate, then the effect" inside a single potency clause.

#### Difficulty threshold tokens

Inside a potency gate, the threshold value should be one of:
- `{Weak}` / `{Average}` / `{Strong}` -- curly-brace substitution (recommended)
- `[Weak]` / `[Average]` / `[Strong]` -- square-bracket substitution (also valid; matches the Avalanche Rush convention)
- A bare integer like `2` -- only when you want a literal numeric threshold (rare; the named tokens scale with target tier and are what the rules text uses)

**Avoid** bare unbracketed words: `M < Weak prone` may be evaluated as a symbol lookup against `Weak`, which is undefined and silently evaluates to 0. Always wrap difficulty names in `{...}` or `[...]`.

#### Clause vocabulary

- `X damage` -- deal X damage
- `X [type] damage` -- deal typed damage (e.g., `8 fire damage`)
- `push/pull/slide X` -- forced movement
- `vertical push X` -- vertical forced movement
- `[condition] (save ends)` -- apply condition with save ends duration
- `[condition] (EoT)` -- apply condition until end of target's next turn
- `A<X [effect]` -- apply effect only if target's Agility < X (potency check); X is `{Weak}`/`{Average}`/`{Strong}` or a literal int
- `M<X [effect]` -- Might potency check
- `I<X [effect]` -- Intuition potency check
- `P<X [effect]` -- Presence potency check
- `R<X [effect]` -- Reason potency check

#### Worked examples

```
6 + M damage; M < {Weak}, grabbed
```
"Deal 6+M damage, AND if target fails an M<Weak potency check, also grab them."

```
{3 + Might} damage; push 2; M<[Average] prone
```
"Deal 3+Might damage, push 2, AND if target fails M<Average, also knock prone." (Note: same potency clause uses space; could equivalently be `M<[Average], prone`.)

```
9 cold damage; slide 2
```
"Deal 9 cold damage AND slide 2 squares." (No potency gate -- both happen unconditionally.)

```
13 cold damage; slide 4
```
"Tier 3 form -- same shape, escalated numbers."

#### Anti-pattern audit

If you ever write a tier or rule string, sanity-check it does NOT contain `:` -- the parser will accept it without complaining but the gated effect will detach from its gate at runtime.

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
(cover), `blocks_movement` (wall). See `data/docs/reference/MONSTERS.md` for full field list.

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
Interpolated against the **target** of the rule (per `applyto`), so `applyto: caster` evaluates
against the caster, `applyto: caster_companion` against the companion, etc.

**Compound rules:** Separate with `;` -- e.g., `2 damage; A<2 prone; push 3`.

See `data/docs/reference/MONSTERS.md` "Power Table Effect / Rules Engine Commands" for full syntax.

### Movement: ALWAYS Prefer Rule Strings Over RelocateCreatureBehavior / ForcedMovementBehavior

For ANY movement -- shift, teleport, move, push, pull, slide -- default to a
`DrawSteelCommandBehavior` rule string. Do NOT wrap movement in
`InvokeAbility{customAbility{targetType:emptyspace,RelocateCreatureBehavior}}`
boilerplate, and do NOT use `ActivatedAbilityForcedMovementBehavior`. Both reinvent
what the rules engine already does and bypass shift/forced-movement restrictions
(slowed, grabbed, stability, etc.).

| Rule string | Replaces |
|---|---|
| `shift {N}` (with `applyto: caster` or `caster_companion`) | InvokeAbility wrapping a customAbility with `RelocateCreatureBehavior movementType: shift` |
| `teleport {N}` | InvokeAbility wrapping a customAbility with `RelocateCreatureBehavior movementType: teleport` and `targetType: emptyspace` (rule string invokes the standard Teleport ability which already prompts for destination) |
| `move {N}` | RelocateCreatureBehavior with `movementType: move` |
| `push {N}` / `pull {N}` / `slide {N}` (with `applyto: targets`) | `ActivatedAbilityForcedMovementBehavior` |

Interpolation cheat sheet for movement:
- `shift {Intuition}` -- caster's Intuition (when `applyto: caster`)
- `shift {Movement Speed}` -- caster's Movement Speed
- `shift {Cast.Spaces Moved}` -- the slide/push distance from the triggering ability (use in trigger callbacks like Herd the Sheep)
- `push {Caster.Might + 1}` -- caster's Might + 1 (when `applyto: targets`)
- `shift {Caster.Companion.Speed}` -- the caster's companion's Speed (cross-actor lookup)

**Reserve raw `RelocateCreatureBehavior` only for these cases:**
- **Cross-actor relocate to a SPECIFIC creature's loc** (e.g., "your companion teleports
  into your space" -- destination is the summoner's loc, not a player-picked square).
  Use `applyto: caster_summoner` or `caster_companion` on the relocate; the destination
  resolves to that creature's loc.
- **`swapCreatures: true`** -- swap two creatures' positions (no rule string for this).
- **Auto-routed movement to a vicinity/filter** (e.g., `targetMoveVicinity: true,
  vicinityFilter: Enemy` to move adjacent to nearest enemy).

**Reserve raw `ForcedMovementBehavior` only for** behavior-level fields the rule string
can't express (almost never -- `push/pull/slide N` rules cover virtually all cases).

See `feedback_prefer_drawsteelcommand_for_movement.md` for the full rationale and
before/after examples.

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
