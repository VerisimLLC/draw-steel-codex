# Trigger Symbol Prose Worksheet

Companion to [TRIGGERED_ABILITY_EDITOR_DESIGN.md](TRIGGERED_ABILITY_EDITOR_DESIGN.md). This is the launch-scope backfill list for opt-in #1 (symbol prose templates) in the Condition Prose Engine, specifically scoped to symbols that can appear in a TriggeredAbility's `conditionFormula`.

**Your job:** review the proposed prose fragment and example rendered sentence for each symbol. Edit freely. Status column on the right lets you mark progress: `OK`, `EDIT`, `DEFER`. When done, the final prose values get baked into each symbol's `prose = "..."` field on its `RegisterSymbol` / inline symbol table (see design doc opt-in #1 for the code pattern).

**Scope rules:**
- Symbols valid inside a trigger's `conditionFormula`. Three categories:
  1. Ambient role tokens (`Subject`, `Caster`) -- always available.
  2. Per-trigger event-payload symbols -- exposed by the firing event.
  3. Dot-accessed properties on typed objects (`Ability.X`, `Cast.X`, `Path.X`) -- accessed through a top-level symbol. Top-by-usage subset listed in the new sections at the bottom; long tail deferred as backfill.
- Creature property symbols (`Hitpoints`, `Level`, `Movement Speed`, etc. -- ~50 of them) are excluded here. They already have `desc` fields and can use a default template (`"the [name]"`) or be backfilled as a separate pass post-launch.
- 14 triggers expose NO event-payload symbols and need no prose work (listed at the bottom).
- ~~One codebase bug flagged during the crawl: `forcemove` trigger declares `hasattacker` as type `creature` but should be `boolean`.~~ **FIXED 2026-04-28** (confirmed by lead dev; one-line edit in `DMHub Game Rules\TriggeredAbility.lua`).

**5e / hidden / deprecated triggers EXCLUDED from this scope** (audit 2026-04-23, revised 2026-04-24):
- `hit` - deregistered in DS at `MCDMRules.lua:1277`
- `miss` - hidden in DS (conditional `hide = function()` at `TriggeredAbility.lua:338-350`); 5e-only outcome model
- `fumble` - hidden in DS (same predicate as miss); DS power rolls don't emit fumbles
- ~~`attacked`~~ - **retained in scope** (per user decision 2026-04-24). Registered only in `dnd5e.lua:864-901` and not in DS trigger files, but 7 compendium entries reference it (bestiary\angulotl-hopper.yaml, characterongoingeffects\the-voice-ally.yaml, complications\wrathful-spirit.yaml, kits\boren.yaml, plus associated `_table.yaml` files). **Orphan-content concern:** whether those 7 entries fire at runtime in DS depends on whether `dnd5e.lua` is actually loaded by DS. Needs a separate dev ticket to confirm runtime state and, if non-functional, migrate the content to a valid DS trigger.

Symbols that were previously scoped out on the assumption `attacked` was dead and are now **back in scope**: `outcome`, `attack` (both attacked-only), plus `roll` (which is actually `Cast.roll`, a property -- covered in the Cast properties section below). `degree` remains out of scope (miss-only).

**Prose fragment conventions:**
- Write the fragment as a noun phrase or short clause fits into sentences like `"the [fragment] is/has/..."` or `"[role fragment] [verb]s ..."`.
- For numeric / string symbols: use "the X" phrasing (e.g. `the damage`, `the damage type`).
- For boolean symbols: use "has a X" or "is X" phrasing (e.g. `has an attacker`, `is a critical`).
- For creature-typed role symbols: use bare noun with article (e.g. `the attacker`, `the target`).
- Set symbols: "the X" (e.g. `the damage keywords`).

The "Example rendered" column shows how the fragment fits into a plain-English sentence when the pattern-match engine recognises the formula. Adjust both the fragment AND the example if the engine would have to produce different phrasing.

---

## Ambient role tokens

Available in every trigger's condition regardless of event.

### `Subject` (creature) -- DYNAMIC PROSE
- **Trigger availability:** Ambient. Always present. (Also aliased as `Self` in formulas; same mapping applies.)
- **Engine description:** The creature the event occurred on -- a specific creature resolved at trigger time from the author's chosen Trigger Subject filter.
- **Proposed prose rendering:** NOT a static string. The engine renders this symbol based on the ability's `subject` field value. Two-column lookup table: `role` is the noun phrase plugged into event templates (e.g. `{subject} takes damage`); `possessive` is the form used when Subject is dot-accessed as a property owner (e.g. `Subject.Stamina` -> `<possessive> stamina`).

| `subject` id | Trigger Subject form label | `role` (in-clause) | `possessive` |
|---|---|---|---|
| `self` | Self | you | your |
| `any` | Self or Any Creature | any creature | that creature's |
| `selfandheroes` | Self or a Hero | you or any hero | that creature's |
| `otherheroes` | Any Hero (Not Self) | another hero | that hero's |
| `selfandallies` | Self or an Ally | you or any ally | that creature's |
| `allies` | Any Ally (Not Self) | any ally | that ally's |
| `enemy` | Any Enemy | any enemy | that enemy's |
| `other` | Any Creature (Not Self) | another creature | that creature's |

- **Voice decision (2026-04-24):** `self` renders as second person (`you` / `your`) rather than third person (`this creature`) to match Draw Steel's player-facing card voice. Every real card in the compendium uses second person for the ability owner; the editor's auto-derivation should produce the same idiom so phase-7 Display overrides are rarely needed. Every other subject id stays third person because those refer to creatures other than the ability owner.
- **Compound subjects keep the "Self or" qualifier** (`selfandheroes`, `selfandallies`, and `any` implicit). `"When you or any ally takes damage"` correctly surfaces both branches of the filter; the earlier "drop the qualifier" simplification misled authors when the filter actually includes self.
- **Possessive splits by specificity.** Single-filter ids use the specific role form (`that enemy's`, `that ally's`, `that hero's`). Compound ids fall back to the generic `that creature's` because at authoring time the filter could resolve to any one of several types, and a specific possessive would be wrong in runtime cases. `self` is the only non-derivable special case (`your`, not `you's`) -- Option 1 from the engine discussion puts this as an explicit field on the subject entry rather than a regex-rewrite hack.
- **Example formulas and rendered:**
  - Ability with Trigger Subject = `enemy`, condition `Subject.Stamina < 10` -> "that enemy's stamina is less than 10"
  - Ability with Trigger Subject = `self`, condition `Subject.Conditions has "Grabbed"` -> "your conditions include Grabbed" (after phase 5 Conditions backfill; today this sub-expression falls through to raw formula)
  - Ability with Trigger Subject = `selfandallies`, condition `Self.Level > 3` -> "that creature's level is more than 3" (Self alias resolves to same mapping)
- **Implementation note:** engine special-cases this symbol. The `prose` field on the registration is NOT a single string -- it carries both `role` and `possessive` forms. Role prose feeds event templates (TRIGGER_EVENT_PROSE.md) and bare-subject bool checks; possessive feeds the `<creature>.<property>` dotted-access fallback. ~8 entries, ~12 lines of code.
- **Status:** `OK` (voice rewrite locked 2026-04-24)

### `Caster` (creature)
- **Trigger availability:** Ambient, aura-triggered abilities only. Absent for standalone triggers.
- **Engine description:** The creature that controls the aura that fired this trigger.
- **Proposed prose fragment:** the aura caster
- **Example formulas and rendered:**
  - `Caster.Distance(Subject) > 10` -> "the distance from the aura caster to the subject is more than 10"
- **Status:** `OK`

---

## Event-payload symbols -- Damage-themed

Appear in: `losehitpoints` (Take Damage), `zerohitpoints` (Drop to Zero), `winded`, `dying`, `dealdamage` (Damage an Enemy), `fallenon`, `fall`.

### `Damage` (number)
- **Exposed by:** losehitpoints, zerohitpoints, winded, dying, dealdamage, fallenon, fall
- **Engine description:** Amount of damage dealt or taken (context-dependent).
- **Proposed prose fragment:** the damage
- **Example formulas and rendered:**
  - `Damage >= 5` -> "the damage is at least 5"
  - `Damage > 10 and Damage Type is "fire"` -> "the damage is more than 10 and the damage type is fire"
- **Status:** `OK`

### `Raw Damage` (number)
- **Exposed by:** losehitpoints
- **Engine description:** Damage before immunity/resistance/vulnerability reductions.
- **Proposed prose fragment:** the raw damage (before immunity)
- **Example formulas and rendered:**
  - `Raw Damage >= 20` -> "the raw damage (before immunity) is at least 20"
- **Status:** `OK`

### `Damage Type` (text)
- **Exposed by:** losehitpoints, zerohitpoints, winded, dying, dealdamage
- **Engine description:** Damage type string. DS canonical values (from `compendium/tables/damagetypes/`): `acid`, `cold`, `corruption`, `fire`, `holy`, `lightning`, `poison`, `psychic`, `sonic`, `untyped`. (5e-only types like `slashing` / `piercing` are not valid DS values.)
- **Proposed prose fragment:** the damage type
- **Example formulas and rendered:**
  - `Damage Type is "fire"` -> "the damage type is fire"
  - `Damage Type is "acid" or Damage Type is "poison"` -> "the damage type is acid or poison"
- **Status:** `OK`

### `Damage Immunity` (boolean)
- **Exposed by:** losehitpoints
- **Engine description:** True if damage was reduced or increased by immunity / weakness.
- **Proposed prose fragment:** the damage was modified by immunity or weakness
- **Example formulas and rendered:**
  - `Damage Immunity` -> "the damage was modified by immunity or weakness"
  - `not Damage Immunity` -> "the damage was not modified by immunity or weakness"
- **Status:** `OK`

### `Keywords` (set)
- **Exposed by:** losehitpoints, zerohitpoints, winded, dying, dealdamage
- **Engine description:** Keyword set attached to the damage instance.
- **Proposed prose fragment:** the damage keywords
- **Example formulas and rendered:**
  - `Keywords has "Melee"` -> "the damage keywords include Melee"
  - `Keywords has "Area"` -> "the damage keywords include Area"
- **Status:** `OK`

### `Has Rolled Damage` (boolean)
- **Exposed by:** losehitpoints, dealdamage
- **Engine description:** True if damage came from a dice roll (not flat damage).
- **Proposed prose fragment:** the damage was rolled
- **Example formulas and rendered:**
  - `Has Rolled Damage` -> "the damage was rolled"
- **Status:** OK

---

## Event-payload symbols -- Ability-themed

Appear in: `dealdamage`, `losehitpoints`, `rollpower`, `useability`, `finishability`, `castsignature`, `targetwithability`.

### `Ability` (ability)
- **Exposed by:** dealdamage, losehitpoints, rollpower, targetwithability
- **Engine description:** The ability driving this event.
- **Proposed prose fragment:** the ability used
- **Example formulas and rendered:**
  - `Ability.Name is "Fireball"` -> "the triggering ability's name is Fireball" (awkward - may need pattern refinement)
- **Status:** `OK` (note: ability field access produces clumsy prose; consider if this symbol should use "the triggering ability" or similar)

### `Used Ability` (ability)
- **Exposed by:** dealdamage, useability, finishability, castsignature
- **Engine description:** Alias for Ability in some triggers. Semantically the same.
- **Proposed prose fragment:** the ability used
- **Example formulas and rendered:** (same patterns as Ability)
- **Status:** `OK` (consider merging with Ability in prose layer - authors can use either name interchangeably)

### `Cast` (spellcast)
- **Exposed by:** useability, finishability, castsignature
- **Engine description:** Casting context data (targets, rolls, modifiers).
- **Proposed prose fragment:** the ability's cast
- **Example formulas and rendered:**
  - Rarely referenced in conditions; usually accessed as `Cast.targets` or `Cast.rolls` which need their own prose patterns.
- **Status:** `DEFER` (low usage; pattern match on `Cast.X` accessors rather than writing prose for Cast itself)

### `Has Ability` (boolean)
- **Exposed by:** losehitpoints, dealdamage
- **Engine description:** True if the event came from an ability (vs an effect/environment).
- **Proposed prose fragment:** the event came from an ability
- **Example formulas and rendered:**
  - `Has Ability` -> "the event came from an ability"
  - `not Has Ability` -> "the event did not come from an ability"
- **Status:** `OK`

---

## Event-payload symbols -- Attacker/Target role tokens

### `Attacker` (creature)
- **Exposed by:** losehitpoints, zerohitpoints, winded, dying, inflictcondition, forcemove
- **Engine description:** The creature that caused the damage / condition / forced move.
- **Proposed prose fragment:** the attacker
- **Example formulas and rendered:**
  - `Attacker.Keywords has "Undead"` -> "the attacker's keywords include Undead"
  - `Attacker.Level >= Subject.Level` -> "the attacker's level is at least the subject's level"
- **Status:** `OK`

### `Has Attacker` (boolean)
- **Exposed by:** losehitpoints, inflictcondition, forcemove
- **Engine description:** True if there is a known attacker creature for this event.
- **Proposed prose fragment:** there is an attacker
- **Example formulas and rendered:**
  - `Has Attacker` -> "there is an attacker"
  - `Has Attacker and Attacker.Keywords has "Melee"` -> "there is an attacker and the attacker's keywords include Melee"
- **Status:** `OK`

### `Target` (creature)
- **Exposed by:** dealdamage, movethrough, targetwithability, pressureplate
- **Engine description:** The creature the event is directed at.
- **Proposed prose fragment:** the target
- **Example formulas and rendered:**
  - `Target.Stamina < 10` -> "the target's stamina is less than 10"
- **Status:** `OK`

---

## Event-payload symbols -- Power roll results

Appear in: `rollpower` (Roll Power).

### `Natural Roll` (number)
- **Exposed by:** rollpower
- **Engine description:** Combined 2d10 result before modifiers.
- **Proposed prose fragment:** the natural roll
- **Example formulas and rendered:**
  - `Natural Roll >= 18` -> "the natural roll is at least 18"
- **Status:** `OK`

### `High Roll` (number)
- **Exposed by:** rollpower
- **Engine description:** Higher of the two d10 results.
- **Proposed prose fragment:** the high die
- **Example formulas and rendered:**
  - `High Roll = 10` -> "the high die is 10"
- **Status:** `OK`

### `Low Roll` (number)
- **Exposed by:** rollpower
- **Engine description:** Lower of the two d10 results.
- **Proposed prose fragment:** the low die
- **Example formulas and rendered:**
  - `Low Roll = 1` -> "the low die is 1"
- **Status:** `OK`

### `Surges` (number)
- **Exposed by:** rollpower, losehitpoints, dealdamage
- **Engine description:** Number of surges applied / used.
- **Proposed prose fragment:** the number of surges
- **Example formulas and rendered:**
  - `Surges >= 2` -> "the number of surges is at least 2"
- **Status:** OK

### `Edges` (number)
- **Exposed by:** losehitpoints, dealdamage
- **Engine description:** Number of edges applied to the roll / ability.
- **Proposed prose fragment:** the number of edges
- **Example formulas and rendered:**
  - `Edges > 0` -> "the number of edges is more than 0"
- **Status:** `OK`

### `Banes` (number)
- **Exposed by:** losehitpoints, dealdamage
- **Engine description:** Number of banes applied.
- **Proposed prose fragment:** the number of banes
- **Example formulas and rendered:**
  - `Banes >= 2` -> "the number of banes is at least 2"
- **Status:** `OK`

### `Tier One` (boolean)
- **Exposed by:** rollpower
- **Engine description:** True if at least one target got a tier-one result.
- **Proposed prose fragment:** any target got a tier one result
- **Example formulas and rendered:**
  - `Tier One` -> "any target got a tier one result"
- **Status:** `OK`

### `Tier Two` (boolean)
- **Exposed by:** rollpower
- **Engine description:** True if at least one target got a tier-two result.
- **Proposed prose fragment:** any target got a tier two result
- **Example formulas and rendered:**
  - `Tier Two` -> "any target got a tier two result"
- **Status:** `OK`

### `Tier Three` (boolean)
- **Exposed by:** rollpower
- **Engine description:** True if at least one target got a tier-three result.
- **Proposed prose fragment:** any target got a tier three result
- **Example formulas and rendered:**
  - `Tier Three` -> "any target got a tier three result"
- **Status:** `OK`

---

## Event-payload symbols -- Movement-themed

### `Path` (path)
- **Exposed by:** move, finishmove
- **Engine description:** The path taken by the moving creature.
- **Proposed prose fragment:** the movement path
- **Example formulas and rendered:**
  - `Path.length > 3` -> "the movement path's length is more than 3"
- **Status:** `OK` (pattern may need refinement based on real formula shapes in the bestiary) -- lets do a crawl as a next step to identify refinements.

### `Speed` (number) -- MEANING VARIES PER TRIGGER
- **Exposed by:** collide, fall, fallenon, wallbreak
- **Engine description (per-trigger, verbatim):**
  - `collide` (TriggeredAbility.lua:359): *"The remaining speed of the creature when it collided."*
  - `wallbreak` (TriggeredAbility.lua:390): *"The stamina cost of breaking through the wall."*
  - `fall` (TriggeredAbility.lua:411): *"The distance of the fall in squares."*
  - `fallenon` (same meaning as fall -- distance of the fall that landed on the subject)
- **Proposed prose fragment (dynamic per trigger):**
  - In `collide` context: `the remaining speed at collision`
  - In `wallbreak` context: `the stamina cost of the wall break`
  - In `fall` / `fallenon` context: `the fall distance`
- **Example formulas and rendered:**
  - `Speed >= 3` on `fall` trigger -> "the fall distance is at least 3"
  - `Speed > 0` on `collide` trigger -> "the remaining speed at collision is more than 0"
  - `Speed <= 2` on `wallbreak` trigger -> "the stamina cost of the wall break is at most 2"
- **Implementation note:** engine special-cases this symbol like `Subject` -- the prose fragment is looked up from a `{trigger_id -> fragment}` table rather than a static string. Low-cost, ~4-entry table.
- **Status:** `OK`

### `Movement Type` (text)
- **Exposed by:** collide
- **Engine description (verbatim, TriggeredAbility.lua:363-364):** *"The type of forced movement that caused the collision: 'push', 'pull', or 'slide'."* (Confirmed 2026-04-24: not movement modes like fly/crawl/swim -- that's a separate creature property, also named Type/Movement Type, scoped inferred from surrounding trigger.)
- **Proposed prose fragment:** the movement type
- **Example formulas and rendered:**
  - `Movement Type is "push"` -> "the movement type is push"
  - `Movement Type is "slide"` -> "the movement type is slide"
- **Status:** `OK` (note: same symbol name also exists as creature property; scope inferred from surrounding trigger)

### `Type` (string)
- **Exposed by:** forcemove
- **Engine description:** Type of forced movement ("push", "pull", "slide"). Semantically identical to `Movement Type` above; exposed under a different name in forcemove. -- can we double check this is correct? If so happy with the prose. 
- **Proposed prose fragment:** the forced movement type
- **Example formulas and rendered:**
  - `Type is "push"` -> "the forced movement type is push"
- **Status:** `OK` (naming collision with creature's Type field; may need engine disambiguation)

### `Vertical` (boolean)
- **Exposed by:** forcemove
- **Engine description:** True if the forced movement was vertical.
- **Proposed prose fragment:** the movement was vertical
- **Example formulas and rendered:**
  - `Vertical` -> "the movement was vertical"
- **Status:** `OK`

### `Pusher` (creature)
- **Exposed by:** collide
- **Engine description:** The creature that caused the collision by pushing.
- **Proposed prose fragment:** the pusher
- **Example formulas and rendered:**
  - `Pusher.Level > Subject.Level` -> "the pusher's level is more than the subject's level"
- **Status:** `OK`

### `With Object` (boolean)
- **Exposed by:** collide
- **Engine description:** True if the collision was with an object (not a creature).
- **Proposed prose fragment:** the collision was with an object
- **Example formulas and rendered:**
  - `With Object` -> "the collision was with an object"
- **Status:** `OK`

### `With Creature` (boolean)
- **Exposed by:** collide
- **Engine description:** True if the collision was with another creature.
- **Proposed prose fragment:** the collision was with a creature
- **Example formulas and rendered:**
  - `With Creature` -> "the collision was with a creature"
- **Status:** `OK`

### `Moving Creature` (creature)
- **Exposed by:** leaveadjacent
- **Engine description:** The creature that moved away from the subject.
- **Proposed prose fragment:** the moving creature
- **Example formulas and rendered:**
  - `Moving Creature.Level > 3` -> "the moving creature's level is more than 3"
- **Status:** OK

### `Falling Creature` (creature)
- **Exposed by:** fallenon
- **Engine description:** The creature that fell onto the subject.
- **Proposed prose fragment:** the falling creature
- **Example formulas and rendered:**
  - `Falling Creature.Keywords has "Flying"` -> "the falling creature's keywords include Flying"
- **Status:** `OK`

### `Landed on Creature` (boolean)
- **Exposed by:** fall
- **Engine description:** True if the falling subject landed on another creature.
- **Proposed prose fragment:** the subject landed on a creature
- **Example formulas and rendered:**
  - `Landed on Creature` -> "the subject landed on a creature"
- **Status:** `OK`

### `Landed on Creatures` (creaturelist)
- **Exposed by:** fall
- **Engine description:** List of creatures landed on.
- **Proposed prose fragment:** the creatures landed on
- **Example formulas and rendered:**
  - Rarely iterated in conditions; usually just checked via `Landed on Creature`.
- **Status:** `DEFER` (low real-world usage)

### `Wall Type` (text)
- **Exposed by:** wallbreak
- **Engine description:** Wall solidity: "Thin" or "Solid".
- **Proposed prose fragment:** the wall type
- **Example formulas and rendered:**
  - `Wall Type is "Solid"` -> "the wall type is Solid"
- **Status:** `OK`

### `Location` (loc)
- **Exposed by:** wallbreak
- **Engine description:** Location of the wall break.
- **Proposed prose fragment:** the wall-break location
- **Example formulas and rendered:**
  - Rarely referenced in conditions.
- **Status:** `DEFER`

---

## Event-payload symbols -- Condition / resource / turn flow

### `Condition` (text)
- **Exposed by:** inflictcondition
- **Engine description:** Name of the condition applied (Grabbed, Prone, etc.)
- **Proposed prose fragment:** the applied condition
- **Example formulas and rendered:**
  - `Condition is "Grabbed"` -> "the applied condition is Grabbed"
- **Status:** `OK`

### `Resource` (text)
- **Exposed by:** gainresource, useresource
- **Engine description:** Name of the resource gained / used.
- **Proposed prose fragment:** the resource
- **Example formulas and rendered:**
  - `Resource is "Focus"` -> "the resource is Focus"
- **Status:** `OK`

### `Quantity` (number) -- MEANING VARIES PER TRIGGER
- **Exposed by:** earnvictory, gainresource, useresource
- **Engine description:** Amount gained / used / earned (context-dependent).
- **Proposed prose fragment (dynamic per trigger):**
  - In `earnvictory` context: `the victories earned`
  - In `gainresource` context: `the amount gained`
  - In `useresource` context: `the amount used`
- **Example formulas and rendered:**
  - `Quantity >= 2` on `earnvictory` -> "the victories earned is at least 2"
  - `Quantity > 0` on `gainresource` -> "the amount gained is more than 0"
  - `Quantity = 1` on `useresource` -> "the amount used is 1"
- **Implementation note:** engine special-cases this symbol like `Subject` and `Speed` -- the prose fragment is looked up from a `{trigger_id -> fragment}` table rather than a static string. 3-entry table.
- **Status:** `OK` (post-edit 2026-04-24: per-trigger override confirmed)

### `XP Gained` (number)
- **Exposed by:** endrespite
- **Engine description:** Experience gained during the respite.
- **Proposed prose fragment:** the XP gained
- **Example formulas and rendered:**
  - `XP Gained >= 5` -> "the XP gained is at least 5"
- **Status:** `OK`

### `Order` (number)
- **Exposed by:** beginturn
- **Engine description:** Position in the turn group (1 = first, 2 = second).
- **Proposed prose fragment:** the turn order position
- **Example formulas and rendered:**
  - `Order = 1` -> "the turn order position is 1"
- **Status:** `OK`

---

## Event-payload symbols -- Custom trigger

### `Trigger Name` (text)
- **Exposed by:** custom
- **Engine description:** Author-supplied custom trigger name.
- **Proposed prose fragment:** the custom trigger name
- **Example formulas and rendered:**
  - `Trigger Name is "my-trigger"` -> "the custom trigger name is my-trigger"
- **Status:** `OK`

### `Trigger Value` (number)
- **Exposed by:** custom
- **Engine description:** Author-supplied numeric value on the custom trigger.
- **Proposed prose fragment:** the custom trigger value
- **Example formulas and rendered:**
  - `Trigger Value >= 3` -> "the custom trigger value is at least 3"
- **Status:** `OK`

---

## Triggers with no event-payload symbols

These triggers evaluate `conditionFormula` against the ambient context only (Subject + creature properties). No trigger-specific symbols to prose.

- attack (Attack an Enemy)
- beginround (Start of Round)
- creaturedeath (Death)
- endcombat (End of Combat)
- endturn (End Turn)
- gaintempstamina (Gain Temporary Stamina)
- kill (Kill a Creature)
- prestartturn (Before Start of Turn)
- regainhitpoints (Regain Stamina)
- rollinitiative (Draw Steel)
- saveagainstdamage (Made Reactive Roll Against Damage)
- startdowntime (Start Downtime)
- startrespite (Start Respite)
- teleport (Teleport)

(`fumble` was in this list in earlier revisions but is DS-hidden; removed 2026-04-23.)

For these, the Trigger Summary's when-clause would render from event phrase + subject phrase + condition phrase (where condition phrase uses only Subject.X accessors, no event-payload symbols). The default "the [creature property name]" phrasing covers those accessors.

---

## Event-payload symbols -- `attacked` trigger (orphan-content scope, see intro)

These symbols appear only in compendium entries that reference the `attacked` trigger id. `attacked` is not in the DS trigger registry; retained in worksheet scope so prose can render existing compendium content if/when dnd5e.lua is confirmed loaded in DS (dev ticket pending).

### `outcome` (text) -- attacked trigger
- **Exposed by:** attacked (5e-only)
- **Engine description:** 5e-style attack-roll outcome: "hit", "miss", "critical", "fumble".
- **Proposed prose fragment:** the attack outcome
- **Example formulas and rendered:**
  - `outcome is "critical"` -> "the attack outcome is critical"
- **Status:** `DEFER`

### `attack` (attack) -- attacked trigger
- **Exposed by:** attacked (5e-only)
- **Engine description:** The attack structure (type, modifiers, damage). Typically accessed via `.X` subfields.
- **Proposed prose fragment:** the attack
- **Example formulas and rendered:**
  - Usually accessed via sub-accessors; pattern matching would render the full expression.
- **Status:** `DEFER` (object-typed symbol; accessors would need their own enumeration if this trigger becomes a priority)

---

## Ability properties -- launch-tier subset (via `Ability` / `Used Ability` dot-access)

Properties of the `ability` type, accessed in conditions as `Ability.X` or `Used Ability.X`. The full enumeration has 37 properties (base + MCDM extensions), defined at `ActivatedAbility.lua:5183-5307` and `MCDMActivatedAbility.lua:261-513`. Listed here are the top compendium-usage properties; the long tail is backfill-incremental post-launch.

**Rendering pattern:** the parent symbol's prose ("the ability used") combines with the property's prose fragment. Engine pattern-matches `<AbilitySymbol>.<property>` and stitches the output together. Example: `Ability.keywords has "Melee"` -> "the ability used's keywords include Melee".

### `Ability.name` (text) -- compendium usage: 200
- **Engine description:** The display name of the ability.
- **Proposed prose fragment:** the used ability's name
- **Example:** `Ability.Name is "Fireball"` -> "the used ability's name is Fireball"
- **Status:** `OK`

### `Ability.keywords` (set) -- compendium usage: 147
- **Engine description:** The keyword set attached to the ability.
- **Proposed prose fragment:** the used ability's keywords
- **Example:** `Ability.Keywords has "Melee"` -> "the used ability's keywords include Melee"
- **Status:** `OK`

### `Ability.doesdamage` (boolean) -- compendium usage: 64
- **Engine description:** Whether this ability does rolled damage (MCDM extension).
- **Proposed prose fragment:** the ability used does damage
- **Example:** `Ability.doesdamage` -> "the ability used does damage"
- **Example:** `not Ability.doesdamage` -> "the ability used does not do damage"
- **Status:** `OK`

### `Ability.categorization` (text) -- compendium usage: 42
- **Engine description:** The categorization of this ability (e.g. "Strike", "Ranged Strike", "Area").
- **Proposed prose fragment:** the used ability's categorization
- **Example:** `Ability.categorization is "Strike"` -> "the used ability's categorization is Strike"
- **Status:** `OK`

### `Ability.heroicresourcecost` (number) -- compendium usage: 26
- **Engine description:** Number of heroic resources this ability costs.
- **Proposed prose fragment:** the used ability's heroic resource cost
- **Example:** `Ability.heroicresourcecost >= 2` -> "the used ability's heroic resource cost is at least 2"
- **Status:** `OK`

### `Ability.hasforcedmovement` (boolean) -- compendium usage: 18
- **Engine description:** Whether this ability has forced movement.
- **Proposed prose fragment:** the ability used has forced movement
- **Example:** `Ability.hasforcedmovement` -> "the ability used has forced movement"
- **Status:** `OK`

### `Ability.heroic` (boolean) -- user-flagged
- **Engine description:** Is this ability a heroic ability?
- **Proposed prose fragment:** the ability used is heroic
- **Example:** `Ability.heroic` -> "the ability used is heroic"
- **Example:** `not Ability.heroic` -> "the ability used is not heroic"
- **Status:** `OK`

### `Ability.malicecost` (number) -- compendium usage: 8
- **Engine description:** Number of malice resources this ability costs.
- **Proposed prose fragment:** the used ability's malice cost
- **Example:** `Ability.malicecost > 0` -> "the used ability's malice cost is more than 0"
- **Status:** `OK`

### `Ability.spell` (boolean)
- **Engine description:** True for abilities that are spells.
- **Proposed prose fragment:** the ability used is a spell
- **Example:** `Ability.spell` -> "the ability used is a spell"
- **Status:** `DEFER` -- non DS used.

### `Ability.freestrike` (boolean)
- **Engine description:** Whether this is a free strike.
- **Proposed prose fragment:** the ability used is a free strike
- **Example:** `Ability.freestrike` -> "the ability used is a free strike"
- **Status:** `OK`

### `Ability.hasattack` (boolean)
- **Engine description:** True for abilities that include an attack.
- **Proposed prose fragment:** the ability used has an attack
- **Example:** `Ability.hasattack` -> "the ability used has an attack"
- **Status:** `OK`

### `Ability.hasheal` (boolean)
- **Engine description:** True for abilities that include healing.
- **Proposed prose fragment:** the ability used heals
- **Example:** `Ability.hasheal` -> "the ability used heals"
- **Status:** `OK`

**Long-tail Ability properties** (included here for completeness; rare in compendium; prose templates to be backfilled as needed):
`action`, `usableasfreestrike`, `usableassignatureability`, `remainhidden`, `level`, `numberoftargets`, `weaponattack`, `range`, `damagetypes`, `inflicts` (function), `powerrollusesmight`, `powerrollusesagility`, `haspotency`, `allegiance`, `strain`, `strain damage`, `strain damage type`, `has rolled damage`, `characteristics`, `stolen`, `test`, `testskills`, `maneuver`, `main action`.

---

## Cast / Spellcast properties -- launch-tier subset (via `Cast.X` dot-access)

Properties of the `spellcast` type, accessed in conditions as `Cast.X`. The full enumeration has 34 properties (base + MCDM), defined at `ActivatedAbilityCast.lua:56-262` + `MCDMActivatedAbilityCast.lua`. Listed here are the top compendium-usage properties.

### `Cast.passespotency` (function(target, characteristic, potency) -> boolean) -- compendium usage: 74
- **Engine description:** Given a target, characteristic, and potency, returns true if the potency check passes (MCDM extension).
- **Proposed prose fragment:** {1} passes the potency check
- **Example:** `Cast.passespotency(Target, "mgt", 2)` -> "the target passes the potency check"
- **Example:** `Cast.passespotency(Subject, "agi", 3)` -> "the subject passes the potency check"
- **Status:** `OK` (post-edit 2026-04-24: simplified -- characteristic and potency args dropped from prose; author sees them in the formula, no need to echo in the English rendering)

### `Cast.primarytarget` / `Cast.primary` (creature) -- compendium usage: 42
- **Engine description:** The primary (first) target of this ability.
- **Proposed prose fragment:** the primary target
- **Example:** `Cast.primarytarget.Stamina < 10` -> "the primary target's stamina is less than 10"
- **Status:** `OK`

### `Cast.tier` (number) -- compendium usage: 31
- **Engine description:** The tier for the result of the power roll.
- **Proposed prose fragment:** the cast's tier
- **Example:** `Cast.tier >= 2` -> "the cast's tier is at least 2"
- **Status:** `OK`

### `Cast.damagedealt` / `Cast.damage` (number) -- compendium usage: 31
- **Engine description:** Amount of damage dealt by the cast.
- **Proposed prose fragment:** the damage dealt by the cast
- **Example:** `Cast.damagedealt > 5` -> "the damage dealt by the cast is more than 5"
- **Status:** `OK`

### `Cast.roll` (number) -- compendium usage: 22
- **Engine description:** The roll made during the cast. Only valid for abilities with the Roll Behavior.
- **Proposed prose fragment:** the cast's roll
- **Example:** `Cast.roll >= 17` -> "the cast's roll is at least 17"
- **Status:** `OK`

### `Cast.memory` (function(name) -> number) -- compendium usage: 18
- **Engine description:** Given a memory name, returns the stored numeric value. Fed by the `remember` behaviour.
- **Proposed prose fragment:** the cast's memory of {1}
- **Example:** `Cast.memory("damage_dealt") > 0` -> "the cast's memory of 'damage_dealt' is more than 0"
- **Status:** `OK` (function-style prose)

### `Cast.tierfortarget` (function(target) -> number)
- **Engine description:** Returns the tier of the result against a specific target.
- **Proposed prose fragment:** the cast's tier against {1}
- **Example:** `Cast.tierfortarget(Subject) >= 2` -> "the cast's tier against the subject is at least 2"
- **Status:** `OK`

### `Cast.hastarget` (function(creature) -> boolean)
- **Engine description:** Returns true if the given creature is a target of this cast.
- **Proposed prose fragment:** the cast targets {1}
- **Example:** `Cast.hastarget(Attacker)` -> "the cast targets the attacker"
- **Status:** `OK`

**Long-tail Cast properties** (backfill-incremental):
`mode`, `firsttarget`, `opportunityattackstriggered`, `heroicresourcesgained`, `numberofaddedcreatures`, `creaturelistsize`, `damageraw`, `damagedealtagainst`, `damagerawagainst`, `naturalroll`, `highroll`, `lowroll`, `healing`, `healroll`, `ability`, `targetcount`, `spacesmoved`, `hasprimarytarget`, `inflictedconditions`, `purgedconditions`, `forcedmovementdistance`, `forcedmovementcollision`, `forcedmovementcreaturecount`, `forcedmovementdamagedealt`, `forcedmovementdamagedealttarget`, `boons`, `banes`, `ongoingeffectspurgedchosen`, `has rolled damage`.

---

## Path properties (via `Path.X` dot-access) -- complete list

The `path` type has only 5 properties (defined at `Creature.lua:6077-6104`); all listed.

### `Path.forced` (boolean) -- compendium usage: 14
- **Engine description:** Whether this path was a forced move.
- **Proposed prose fragment:** the movement was forced
- **Example:** `Path.forced` -> "the movement was forced"
- **Example:** `not Path.forced` -> "the movement was not forced"
- **Status:** `OK`

### `Path.distancetocreature` (function(creature) -> number) -- compendium usage: 7
- **Engine description:** Given a creature, returns distance in tiles that the closest point on the path came to that creature.
- **Proposed prose fragment:** the minimum distance from the path to {1}
- **Example:** `Path.distancetocreature(Subject) <= 1` -> "the minimum distance from the path to the subject is at most 1"
- **Status:** `DEFER`

### `Path.squares` (number) -- compendium usage: 3+ (condition) plus heavy use in damage `roll:` formulas
- **Engine description:** The number of squares this path has moved.
- **Proposed prose fragment:** the distance moved
- **Example:** `Path.squares >= 2` -> "the distance moved is at least 2"
- **Status:** `OK` (post-edit 2026-04-24: prose refined and moved out of DEFER)

### `Path.shift` (boolean)
- **Engine description:** Whether this path was a shift.
- **Proposed prose fragment:** the movement was a shift
- **Example:** `Path.shift` -> "the movement was a shift"
- **Status:** `OK`

### `Path.verticalonly` (boolean)
- **Engine description:** Whether this path only moved vertically (no horizontal movement).
- **Proposed prose fragment:** the movement was vertical-only
- **Example:** `Path.verticalonly` -> "the movement was vertical-only"
- **Status:** `OK`

---

## Summary for bake-in

Once the prose values are locked:
1. Update the `RegisterSymbol` calls in `DMHub Game Rules\TriggeredAbility.lua` (lines 167-436) and `Draw Steel Core Rules\MCDMRules.lua` (1015-1487) to add `prose = "..."` fields on each event-payload symbol.
2. Update the ambient `Subject` / `Caster` registrations similarly.
3. Update the `helpSymbols` blocks on `ability` type (`ActivatedAbility.lua:5183-5307` + `MCDMActivatedAbility.lua:261-513`), `spellcast` type (`ActivatedAbilityCast.lua:56-262` + `MCDMActivatedAbilityCast.lua`), and `path` type (`Creature.lua:6077-6104`) to add `prose` fields on each included property.
4. Engine special-cases (dynamic prose, rendered at display time rather than from static `prose` field):
   - `Subject` -- 8-entry table keyed on ability's `subject` field value.
   - `Speed` -- 4-entry table keyed on trigger id (collide / wallbreak / fall / fallenon).
   - `Quantity` -- 3-entry table keyed on trigger id (earnvictory / gainresource / useresource).
5. `TRIGGERED_ABILITY_EDITOR_DESIGN.md` -> opt-in #1 -> mark as landed, note the backfill count.
6. Flag for dev team:
   - ~~`forcemove.hasattacker` type bug (declared as `creature`, should be `boolean`).~~ **FIXED 2026-04-28.**
   - `attacked` trigger orphan content: 7 compendium entries reference it, but DS trigger registry does not include it. Confirm whether `dnd5e.lua` is loaded by DS at runtime. If not, migrate the 7 entries to a valid DS trigger.
