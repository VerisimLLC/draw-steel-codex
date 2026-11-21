# Ability Blocks: Scratch-style authoring for abilities and triggers

**Status:** DISCOVERY / DRAFT, 2026-11-20. Nothing here is decided until it appears in the
Decision ledger. Prototype: [`ui-mockup/ability-blocks-prototype.html`](ui-mockup/ability-blocks-prototype.html)
(open it in any browser; no build step).

---

## 1. Frame

**Problem.** Authoring an ability or trigger today means filling a long form of behaviours, each
with its own fields, plus free-text GoblinScript in many of those fields. Authors cannot see the
shape of the logic ("if this, then that, otherwise...") and only find formula mistakes at play
time. GoblinScript has real traps, e.g. `Has Cover > 0` silently parses `has` as an operator
(GoblinScript_Guide.md, "Evaluation Context and Symbols").

**For whom.**
- *Power user / content author* (us, homebrewers writing monsters and classes): wants speed,
  density, and to see the whole ability at once. Must never be slower than today.
- *Set-and-forget user* (a director tweaking one monster): wants it to be impossible to write
  something broken, and to read an ability back in plain words.

**What "done" looks like.** An author can build or read any common ability as a stack of
blocks, with values and tests as snap-in pieces that only fit where they are valid, and the
result saves as the exact same data the engine runs today.

**Inherited constraints.**
- The Triggered Ability Editor work (TRIGGERED_ABILITY_EDITOR_DESIGN.md) already shipped prose
  rendering, typed trigger symbols and a Test Trigger panel. This design builds on it; it does
  not replace it.
- `Trigger Subject` is a label-only rename; data field `subject` and symbol `Subject` stay
  (that doc's gotcha 1).
- Compendium content is authored as YAML and imported; any design must keep that path working.

## 2. The core idea: blocks are a view, not a new language

The prototype's central finding: **almost everything an author writes today already has a block
shape**, so the block editor can be a *projection* over the existing data rather than a new
runtime.

| Today's data | Block shape (Scratch grammar) |
|---|---|
| `ActivatedAbility` header (name, action, targeting, range, keywords) | **Hat**: "When Gouge is used" |
| `TriggeredAbility.trigger` + target type | **Hat**: "When Retaliate triggers on Lose Stamina" |
| `behaviors` list (ordered) | **Stack** of notched step blocks |
| `ActivatedAbilityPowerRollBehavior` with `tiers[3]` | **C-block with three mouths** (11 or lower / 12-16 / 17+) |
| Tier text `"9 damage; bleeding (save ends)"` | Step blocks inside a tier mouth |
| Tier potency prefix `"M<2 ..."` | An **if** whose test is a potency block, inside a tier |
| `filterTarget` on a behaviour | An **if** C-block wrapped around that behaviour |
| `TriggeredAbility.conditionFormula` | An **if** that is the only block under a trigger hat |
| GoblinScript number expression | **Round** reporter blocks (number, stat, math, distance) |
| GoblinScript boolean expression | **Pointed** test blocks (compare, and/or/not, has condition) |
| Trigger `symbols` (typed: number/boolean/creature/text/set) | Context-aware value blocks; the palette only offers what this trigger provides |

Consequences:
1. **No migration.** Stored data stays text and behaviour records. YAML import, the form
   editor and the runtime are untouched.
2. **Round-tripping is the hard requirement.** Text -> blocks -> text must keep meaning. The
   prototype's Formula lab does this for the common shapes and falls back to a grey *raw formula*
   block for anything else, so nothing is ever unrepresentable, only less friendly.
3. **Shape carries type.** A round block only fits a round hole. This removes a whole class of
   mistakes (a number where a test belongs, `Attacker` used in a trigger that has no attacker)
   at edit time instead of at the table.

## 3. What the prototype proved, and where it hit walls

**Fits today's data (no engine change):** behaviour stacks; power roll tiers carrying damage,
conditions, forced movement and potency; `if` / `if-else` around behaviours (compiles to
`filterTarget`, with `not (...)` for the else branch); trigger conditions; all common
GoblinScript shapes from the guide's quick reference.

**Does not fit (needs a runtime extension):**
- *General logic inside a tier.* Tier text only carries damage, conditions, forced movement and
  potency. "On 17+, heal 3" or "on 17+, if prone, push 2" has no stored form today.
- *Loops and variables.* GoblinScript is a pure expression language and behaviour lists run
  top to bottom once. `repeat` and `remember` have no target (AbilityMemory is the nearest).
- *Branch-level state.* `if` compiles to a per-behaviour target filter, which is evaluated per
  target. "If the roll was a crit, do X once" is a different meaning and needs a real branch
  behaviour.

The prototype marks these with a purple **+** badge and a "Needs engine extension" banner
instead of silently dropping them.

**UX findings from building it:**
- Long `and` chains get very wide. Scratch has the same problem. Proposal: an n-ary
  **all of / any of** test block that grows downward.
- Context matters: the same `Attacker` block is valid under Lose Stamina and an error under
  Start of Turn. Typed trigger symbols (already in `TriggeredAbility.triggers[].symbols`) make
  this checkable for triggers; activated abilities and modifiers have no equivalent schema yet.
- The GoblinScript spaced-identifier trap reproduces in a faithful parser (`Has Attacker and ...`
  fails to parse). Blocks fix it by construction because they always emit `HasAttacker`.

## 4. Feasibility in DMHub

| Need | Engine reality | Anchor |
|---|---|---|
| Drag and drop | Supported: `draggable`, `dragTarget`, `canDragOnto`, `drag` | `DMHub Core UI/CommandBuilder.lua:1641-1700` (a no-code step builder with reorderable steps; closest precedent) |
| GoblinScript AST | Engine compiler is closed and exposes no AST. A Lua mini-parser exists with a partial grammar (8 shapes) | `DMHub Utils/GoblinScriptProse.lua:15-18, 284-460` |
| Prose from formulas / behaviours | Exists | `GoblinScriptProse.Render`, `RenderBehaviourList` (`GoblinScriptProse.lua:1118, 2710`) |
| Typed trigger symbols | Exists for triggers | `TriggeredAbility.lua:259+`, `MCDMRules.lua:1352+` |
| Behaviour registry | ~110 `ActivatedAbility*Behavior` types, registered via `ActivatedAbility.RegisterType`, each with a hand-built `EditorItems` | `ActivatedAbility.lua:687` |
| Existing editors | `AbilityEditor.lua` (5.8k lines), `NewTriggeredAbilityEditor.lua` (7.3k lines) | `Draw Steel Ability Editor/` |

**Verdict: feasible, if built in layers.** The risky parts are (a) a complete GoblinScript
parser/printer in Lua, (b) giving ~110 behaviour types a block description, and (c) canvas
performance in the gui framework with deeply nested panels. All three can be de-risked before
any editor UI is built (see plan, steps 1-3).

Behaviour coverage strategy: hand-design blocks for the ~15 behaviours that cover most content
(power roll, damage, command, apply ongoing effect, heal, forced movement, invoke ability, float
text, aura, summon...). Every other behaviour gets a generic **opaque block**: its summary
text, and a cog that opens the existing `EditorItems` form. Nothing is ever unsupported.

## 4b. GoblinScript in the ability editor today (evidence for D2)

Formula fields in the ability editor itself (`Draw Steel Ability Editor/AbilityEditor.lua`), each a
`gui.GoblinScriptInput`:

| Field | Output | Line |
|---|---|---|
| Mode condition, mode target condition | boolean | 2353, 2413 |
| Resource cost (`resourceNumber`) | number | 2691 |
| Max channel (`maxChannel`) | number | 2771 |
| Range, radius, line distance, number of targets, proximity range | number | 3442, 3476, 3502, 3545, 3641 |
| Target filter (`targetFilter`) | boolean | 3886 |
| Ability filters, reasoned filters (formula + reason lists) | boolean | 3957, 3969 |

Behaviour editors add more (`filterTarget` on every behaviour, damage/heal `roll`, the power
roll formula; 20 inputs in `DMHub Compendium/ActivatedAbilityEditor.lua`, 63 files use
`GoblinScriptInput` in total). Power roll tier text is a separate mini-language
(DrawSteelCommand) with the same authoring problem.

**Key finding:** every `GoblinScriptInput` is already given a `documentation` object with
`output` (boolean / number / roll), `subject` (e.g. `creature.helpSymbols`, every creature field
with its type), `symbols` (named, typed extras such as `Caster`, `Enemy`, `Target Number`) and
worked `examples` (e.g. `_targetFilterDocs`, `AbilityEditor.lua:3079`). That is exactly the
schema a block palette needs: the right blocks for each field can be generated from data the
codebase already maintains, so plan step 2's "symbol schemas" largely exist.

## 4c. Option C prototype: the simplified ability editor

[`ui-mockup/ability-blocks-stack.html`](ui-mockup/ability-blocks-stack.html). One top-to-bottom stack
in four sections (*What is it*, *Who it targets*, *Can be used when*, *What happens*) beside a live
Draw Steel ability card.

What it tries out:
- **Formula slots driven by field descriptions.** Each slot carries a description mirroring the
  real `documentation` objects (range, number of targets, cost, target filter, requirement,
  step filter, damage, tier damage, heal). The `fx` button / empty test opens a picker built from
  it: the field's help text, its own examples, whose stats it can read (e.g. *Your* vs
  *Target's*), and its extra symbols (`Enemy`, `Target Number`...). Search narrows it.
- **"Type a formula instead"** in every picker: live parse with plain-English feedback, including
  the engine's spaced-name trap (`Has Cover`), then converts to blocks.
- **Existing formulas open as blocks.** *Reaving Cleave* is loaded from stored formula text
  (`1 + 1 when Level >= 5`, `Enemy and Stamina <= MaximumStamina / 2`, an `or` requirement) and
  saves back identically. Unknown shapes stay as raw formula blocks with a convert button.
- **"all of / any of" list blocks** replace nested and/or, so long conditions grow down, not across.
- **Only storable steps are offered.** Tier menus offer damage, condition, forced movement and
  potency checks only (what tier text can hold); the main list offers the rest. Invalid structures
  cannot be built, so the extension warnings of the canvas prototype disappear.
- **Card as the primary feedback.** Formula-derived text is dotted; hovering shows the
  GoblinScript. "Show GoblinScript" reveals the text under each slot for authors learning it.
- **Non-drag paths everywhere.** Steps drag by a grip handle, and the `...` menu offers move
  up/down, wrap in *Only if* / potency, unwrap, duplicate and delete. Formula blocks can be
  dragged between slots of the same type, and removed with their x.

Findings:
- Number slots read best as an inline value box plus `fx`: most fields are a plain number most
  of the time, and the formula only appears when asked for.
- Nested controls (x, fx) are shown on hover or keyboard focus only, otherwise deep formulas
  become noise. This is a hover-gated affordance, with the picker and step menu as the visible path.
- Stat names in GoblinScript are not card language ("Heroic Resources Available to Spend").
  The card needs a friendly-name table per symbol; `BEHAVIOUR_PROSE.md` / `TRIGGER_SYMBOL_PROSE.md`
  already hold much of it.

## 4d. Corpus test against the real compendium (2026-11-20)

Source: the GitHub copy of `VerisimLLC/draw-steel-data` (5,820 YAML files; monsters, objectTables,
objects). Scripts: [`ui-mockup/ability-blocks-corpus/`](ui-mockup/ability-blocks-corpus/). Activated
abilities only (triggered abilities excluded per the scope decision).

**Formulas** (14,308 formula fields on activated abilities and their behaviours):

| Measure | Result |
|---|---|
| Plain numbers (no formula at all) | 10,577 (74%) |
| Real formulas | 3,731 |
| Parse with the prototype parser | 3,705 (99.3%) |
| Text -> blocks -> text keeps the meaning | all 3,705 that parse: 3,629 identical, 76 equivalent rewrites (`else 0` dropped, `Self.` implied, condition name capitalised) |
| Become blocks with no raw part, prototype vocabulary | 2,102 (56%) |
| ...projected, once boxes get their real symbol lists plus the planned intent blocks below | 3,446 (92%) |

Hardest boxes today, by share needing raw parts: behaviour *Only if* (`filterTarget`, 653 of 860),
requirements (170 of 259), target filter (218 of 524).

Most-needed new intent blocks (raw-part counts): **potency check** `Cast.PassesPotency(...)` (200),
**has ongoing effect** (157), **mode** (157), **parameter from the invoking ability** `<<x>>` (142),
**allies / enemies** `Friends(...)` (134), **higher of** (`Might or Agility` on numbers, 89),
**has keyword** (80), **distance** (33). Remaining raw parts are long-tail functions
(`ConditionCaster`, `Cast.NumAttackers`, `Stacks`, `Cast.Memory`...), which stay raw blocks.

Parser fixes the corpus forced (now in the prototype): chained `a when x else b when y else c`,
field access after a call `f(x).y`, and the `<<parameter>>` pipe. Still unsupported: dice
modifiers (`1d6 minroll 3`) and `{...}` text (21, mostly comments inside formulas).

**Likely content bugs found** (fail to parse; the engine probably mis-reads them too):
- `objectTables/classes/conduit.yaml`, *Our Hearts, Your Strength*: range `1o`.
- `objectTables/classes/conduit.yaml`, invoked ability: range `(6 when "<<tierresult>>" = 3 else ...` has an unclosed bracket.
- `objectTables/classes/elementalist.yaml`, *Translated Through Flame*: `not Target.Is Friend(Caster)` (spaced name containing `is`).
- `objectTables/classes/null.yaml`, *A Squad Unto Myself*: a mode condition holds rules prose, not a formula.
- `monsters/demon-bale-eye.yaml` and `d3-hall-of-the-brave.yaml` contain a control character (U+000B) and are not valid YAML.

**Behaviours** (3,444 activated abilities that have at least one; 1,612 are hero/item abilities):

| Hand-designed steps | Abilities with no Advanced block |
|---|---|
| 5 core (power roll, command, damage, heal, use ability) | 44% |
| + apply ongoing effect, relocate creature, ability duration effect (8) | 69% |
| + modify power roll, replenish, riders, purge effects, augmented ability, summon, aura (15) | 90% |

**Power roll tiers** (4,878 tier strings): 80% are fully expressible with the four tier steps.
Misses: custom conditions (burning, hexed, seared, dragonsealed), several conditions at once
("dazed and restrained"), forced movement with a direction ("slide 2 squares away from the
target"), resource effects ("gains 2 rage"), and free text. Potency is written two ways: heroes
use words (`M<strong`, 446 uses), monsters use numbers (`M<3`, 1,342 uses); the prototype now
supports both.

**What this means for the design**
- Plan step 1 is largely de-risked: the grammar and round-trip hold on real content. The Lua port
  remains, and the same test should run against it.
- Most formula boxes hold a plain number, so the inline value box with `fx` is the right default.
- Block vocabulary priorities come from data: the intent blocks above, in that order.
- The condition dropdown must come from the conditions table (custom conditions), and the
  condition step should allow more than one condition.
- Step priorities: apply ongoing effect is the biggest gap after the core five.
- New open question: Invoke steps often carry a nested custom ability (over 500 nested
  "Invoked Ability" records in monster files alone). How the simple editor edits a nested ability needs a decision.

## 4e. Passing information to a follow-up ability (hand-offs)

**How it works today** (`DMHub Game Rules/AbilityInvokeAbility.lua`, `AbilityUtils`): the child
ability contains `<<name>>` or `<<name=default>>` anywhere in its text. The parent's Invoke step
stores `standardAbilityParams = {name = "value"}`, and inside that value `<<expression>>` means
"evaluate this GoblinScript now, in the parent's cast" (with `Target`, `Invoker`, `ParentTarget`).
At cast time the child's `<<name>>` is replaced textually; anything not set falls back to its
default or to empty text. In content (1,738 Invoke steps with a built-in ability), hand-offs carry
numbers (damage dealt, tier result, squares moved, a characteristic) or a creature (an id, tested
with `Target.ID = <<targetid>>`). **8 children use a name their parent never sets**, which fails
silently.

**Design in the prototype** (examples: *Draining Strike* and *Gorge*, both loaded from today's stored format):
- The follow-up ability is built inline under a **Then use a new ability: <name>** step, with its
  own targets row (*the same targets* / *you* / *new targets*), target filter and steps.
- Inside the follow-up, every formula picker starts with **From <parent>**: *Draining Strike's
  tier result*, *Draining Strike's damage dealt*... as values, and "the target is Draining
  Strike's first target" as tests. They are dashed teal blocks so they read as "from outside".
- **No wiring.** On save, each parent-information block becomes `<<id>>` in the child and
  `id = "<<Cast.DamageDealt>>"` (etc.) in the parent's `standardAbilityParams`, generated from
  what the follow-up actually uses. Nothing can be passed but unused, or used but not passed.
- **Existing content opens as these blocks** when the parent's value is a known source; existing
  parameter names are kept on save (no churn in content). A value the parent works out with some
  other formula opens as *value from <parent>* showing that formula.
- **The silent bug becomes visible.** *Gorge* models a real monster whose follow-up heals by
  `<<total>>` that the parent never sets: the block is red ("Gorge never sets this value, so it is
  always empty") and a dropdown on the block fixes it in one click.
- With *Show GoblinScript* on, the follow-up step shows the generated plumbing
  ("Passed to it: damagedealt = <<Cast.DamageDealt>>, ...") for authors learning the engine.

**Engine finding: nesting.** `AbilityUtils.ExtractAbilityParameters`, `SetDefaultParameters` and
`DeepReplaceAbility` walk the *whole* copied child, including follow-ups nested inside it. So the
outermost Invoke step fills every `<<name>>` at every depth, and blanks any name it does not set,
before an inner Invoke step ever runs. Direct-parent piping for nested follow-ups therefore needs a
small engine change: stop those three walks at a nested Invoke behaviour's `customAbility`. Only
one existing ability nests parameters (`monsters/high-elf-zephyr.yaml`, *Sweeping Blade*: the
innermost ability's `<<targetid>>` is filled by the outermost step); it would need its inner step to
pass `targetid` after the change. Single-level follow-ups, nearly all content, work today. The
prototype shows a non-blocking note when a nested follow-up uses parent information.

Not yet covered: defaults (`<<name=3>>`), hand-offs into named or standard abilities (not built
inline), and showing what a hand-off will be in the Test panel.

## 4f. Potency checks

**The two functions** (both kept):

| | `Target.PassesPotency("M", v)` / `Passes Potency("M", v)` (creature) | `Cast.PassesPotency(Target, "M", v)` (cast) | Tier text `M<2` |
|---|---|---|---|
| Compares | the creature's Might with `v` | the target's Might with the caster's potency | the target's Might with the gate |
| Power roll potency changes (`potencymod`, per target) | no | **yes** | yes (gate text rewritten) |
| No `v` | not allowed | follows the tier rolled: weak / average / strong | n/a |
| Caster's Potency Bonus | only through `Caster.Strong` etc. | only when `v` is a word; **not for numbers or "follows the tier"** | yes |
| Monster level scaling (`ScaledPotencyGateBonus`) | no | **no** | yes |
| Target resistance formulas | no | **no** | yes |
| A word as `v` (`"Average"`) | **counts as 0** | caster's potency for that word | n/a |

Sources: `MCDMCreature.lua` `passespotency` and `CalculatePotencyValueSelf`;
`MCDMActivatedAbilityCast.lua` `PassesPotency`; `MCDMAbilityBehavior.lua:2039-2075` (tier gate).
"Passes" means the target resists; about 80% of content writes `not Cast.PassesPotency(...)`.

**Block** (`potencyTest`): `[Target] [is affected: | resists:] [Might] below [your strong potency |
potency for the tier rolled | a number | a formula] [including power roll modifiers |
excluding power roll modifiers]`. A *Check potency* group sits near the top of every true/false picker. The card
shows the DS shorthand ("(M<STRONG)"). Saved formulas keep the author's spelling (`"Strong"` vs
`Caster.Strong`). A non-blocking note explains that a plain number with roll changes ignores the
Potency Bonus and level scaling.

**Corpus:** 169 of 172 potency calls in activated abilities become this block; the round trip keeps
meaning for all of them. Content bugs it surfaces, each with a one-click repair in the editor:
- Devil Notary, *Importunity*: `not Cast.PassesPotency(R, 2)` (twice): no creature, unquoted characteristic.
- Twisted Bengrul, *Mind Twist*: `Cast.PassesPotency(target, p)`: unquoted characteristic.
- Creature form with a word, e.g. `not Passes Potency("I", "Average")`: the word counts as 0.
- The engine's own help example is misspelled `Cast.PassessPotency`.

**Engine findings to decide on** (not changed here):
1. The three potency paths disagree on Potency Bonus, level scaling and resistance formulas.
   Recommend one shared potency function used by all three.
2. A step's *Only if* (`filterTarget`) runs with the target as subject in the main path
   (`ActivatedAbility.lua:5183`) but with the **caster** as subject in the damage-checkbox path
   (`ActivatedAbility.lua:5739`), so bare names mean different creatures in the two paths.
   The prototype now treats the target as the subject (it had this backwards before).

## 4g. Prototype for hands-on testing

The prototype opens on a blank **New ability**; the examples moved under *Examples* in the
*Open* menu. Work in progress is kept as a draft in the viewer's own browser (localStorage), so a
reload does not lose it; it is never shared. *Saved data* has a Copy button.

Real compendium tables are embedded (names and ids from draw-steel-data): 27 conditions (the nine
core ones first), 1,034 ongoing effects (searched by typing, never a plain dropdown) and 19
resources. Field mappings for the five new steps follow content usage; their less common options
(duration rounds, stacks, relocate vicinity, purge by duration) are not modelled yet.

## 4h. Triggered abilities and power roll triggers in one editor

**Today they are two different modifier types** (content counts from draw-steel-data):

| | Triggered Ability | Power Roll Trigger |
|---|---|---|
| Stored as | `CharacterModifier` behaviour `trigger` with `triggeredAbility` (a `TriggeredAbility`) | `CharacterModifier` behaviour `powertabletrigger` with `powerRollModifier` (a `power` modifier) |
| In content | 1,532 | 152 |
| When it acts | after an event (`TriggeredAbility.triggers`: losehitpoints, beginturn, creaturedeath...) | while another creature's power roll is open (`PowerTableTriggers.lua` g_triggerChoices: takedamage, strike, powerroll, dealdamage, forcemoved, forcemove, casting) |
| What it does | behaviours (the same steps as an ability) | changes the roll: `damageMultiplier: half` (66), `changeTarget` (41), `modtype` edge/bane/tier (bane 6, tier 7), `damageModifier`, `potencymod`; plus optional behaviours in `powerRollModifier.customTrigger` (61) and `triggerBefore` (27), both `TriggeredAbility` |
| Who sets it off | `subject`: self, selfandallies, allies, enemy, any, other... (+ `subjectRange`) | `targetType`: self, selforally, ally, enemy, anycreature (+ `range`) |
| Action cost | action resource on the TriggeredAbility | `type`: trigger / free / passive |
| Extra condition | `conditionFormula` | `filterCondition`, `targetFilter`, `abilityFilter` |
| Triggering creature in formulas | `Subject` (plus event symbols such as `Attacker`, `Damage`) | `Triggerer` |

Key observation: a Power Roll Trigger already contains `TriggeredAbility` objects for its ordinary
effects (`customTrigger`), so "the steps" are the same kind of data in both. Converting is mostly
moving one `TriggeredAbility` between `modifier.triggeredAbility` and
`modifier.powerRollModifier.customTrigger`, mapping the event and the "who", and writing or
clearing the roll-change fields.

**Design in the prototype** (examples *Deflect* and *Retaliate*):
- "This is an ability / a triggered ability" at the top.
- *What sets it off*: "When [you / you or an ally / an ally / an enemy / any creature] within [10]
  squares [event]" with one merged, plain-language event list. Five events exist in both systems
  (takes damage, is targeted by a strike, makes a power roll, deals damage, is force moved); the
  rest exist only as Triggered Abilities.
- A *Change the roll* palette group (halve the damage, change the damage, edge or bane, change
  potency, change the target) appears for triggered abilities. Its blocks are only allowed in the
  top list and only for events that happen during a roll; otherwise they are dimmed with the reason.
- Storage is decided on save: any roll-change step means Power Roll Trigger, with the other steps
  in `customTrigger`; none means Triggered Ability. Removing the last roll-change step turns it back.
- *Who its steps affect*: the triggering creature, you, or the attacker (where the event has one).

**Coding work this would need** (planning only; nothing has been changed):
1. **One in-memory model and a two-way converter** (`TriggerModel` or similar, Lua): load from either
   modifier type, save to the one the steps require. Tables: event mapping (above), who mapping
   (`self/selfandallies/allies/enemy/any` to `self/selforally/ally/enemy/anycreature`), range
   (`subjectRange` to `range`), action cost (action resource to `type`), condition
   (`conditionFormula` to `filterCondition`).
2. **Switch the modifier type in place, keeping its `guid`.** Set `behavior`, run the target type's
   `TypeInfo.init` defaults, copy mapped fields, and remove the other type's fields so no dead data
   is saved. Check everything that finds a modifier by guid or by behaviour: `sourceguid` links,
   `TriggeredAbilityDisplay` (`triggerdisplay`, 345 in content) cards on the character sheet, the
   character builder's filter on `activated/triggerdisplay/routine`, and the action bar.
3. **Rewrite formulas when the type changes.** Blocks compile the triggering creature as `Subject.`
   or `Triggerer.` automatically (the prototype does this); raw formulas cannot be rewritten safely
   and need a warning. Event-only symbols (`Attacker`, `Damage`, `Used Ability`) must be mapped or
   flagged, because a Power Roll Trigger's filters do not have them.
4. **Fill parity gaps or block the switch.** Events that exist on one side only (Power Roll
   Trigger `casting`, `forcemove` "target force moves another"; every after-only Triggered Ability
   event) must disable roll-change steps with a reason, as the prototype does. Power-roll-only
   settings with no block yet (`triggerBefore`, `multitarget`, `abilityFilter`, `rollType`,
   `additionalCostModifiers`, `armEffect`) open as Advanced settings and keep their values.
5. **Verify before building**, by reading the engine and testing in the app: which symbols
   `filterCondition` sees, how `rollType` (`ability_power_roll` vs `enemy_ability_power_roll`)
   relates to the event and the "who", and whether `subject` "other" and "any" both map to `anycreature`.
6. **Round-trip test against the corpus**: open all 1,532 + 152 records in the model and save them
   back unchanged, before any conversion is allowed.

## 5. Plan

Each step ends in something testable and is a go/no-go gate for the next.

| Step | What | Gate / exit test |
|---|---|---|
| **0. HTML prototype** (done) | Palette, drag-drop canvas, typed slots, compiler to today's records, prose, Formula lab round-trip | Authors try it; decide the open questions below |
| **1. Formula corpus test** | Port the prototype parser/printer to Lua as `GoblinScriptAst` (extending `GoblinScriptProse`'s parser to the full grammar: `where`, dice modifiers, `{}` substitution, category tags). Run parse -> print over **every** formula in the compendium and bestiary | >= 99% round-trip with identical meaning; report % that map to real blocks vs raw blocks. If too many land in raw, add block types before going on |
| **2. Block registry** | `ActivatedAbility.RegisterType{ ..., blocks = {...} }` optional descriptor; generic opaque block for types without one. Symbol schemas for ability and modifier contexts (mirroring trigger `symbols`) | Every behaviour in the compendium renders as a block (real or opaque) |
| **3. Read-only block view** | A "Blocks" tab in the Ability Editor and Triggered Ability Editor that renders the current ability as blocks, no editing | Renders the 20 most complex bestiary abilities with no frame hitch; authors find it easier to read than the form |
| **4. Editable canvas** | Drag, snap, delete; click-to-add and keyboard as non-drag paths; undo; validation badges; live prose (reuse `RenderBehaviourList`) | Build 10 real abilities from scratch in blocks; output identical to the form-built versions |
| **5. Runtime extensions (optional)** | Only if step 4 shows demand: branch behaviour (real if/else on cast state), tier steps beyond the tier text grammar, n-ary tests. Each is a cast-pipeline change and gets its own design | Per extension |

Steps 1 and 2 are pure Lua with no UI and can run in parallel.

## 6. Decision map

| # | Category | Question | Recommendation (not yet decided) |
|---|---|---|---|
| D1 | Role | Blocks as a third view next to Form and Formula, or a replacement editor? | Third view over the same data. Replacing 13k lines of editor is high risk; a view can ship incrementally |
| D2 | Scope order | Formula blocks first, behaviour stacks first, or both? | Formula blocks first (inside today's formula fields): GoblinScript is where errors hide, and step 1 serves it directly |
| D3 | Storage | Keep text canonical, or store a block tree? | Text canonical. Block layout (positions) is not saved; it is regenerated from the data |
| D4 | Language ceiling | Stay inside today's data, or extend the runtime for loops/variables? | Stay inside it for v1; mark unsupported blocks clearly; decide on step 5 after real use |
| D5 | Surface | Inside the existing editor dialogs, or a large floating LaunchablePanel canvas? | Inside the existing editors as a tab; a canvas needs width the dock does not have |
| D6 | Audience | Director/author only, or players editing their own homebrew too? | Same audience as today's editors |
| D7 | Accessibility | Non-drag paths | Click-to-add (prototyped), keyboard navigation of the stack, category glyphs as well as colours (prototyped) |
| D8 | Copy | Block wording ("target is Slowed (save ends)", tier labels) | Needs a copy pass with Draw Steel rules voice; reuse BEHAVIOUR_PROSE.md templates |
| D9 | Regression surface | Capabilities of today's form that a block view must keep | Every field reachable (opaque block cog guarantees it); Test Trigger panel stays reachable from the block view |

## 7. Decision ledger

| Date | Decision | Why |
|---|---|---|
| 2026-11-20 | **D1:** Build a new *simplified* ability editor alongside the existing one. Do not replace the old editor. | The full editor stays the power-user surface and the fallback for anything the simplified one cannot show. |
| 2026-11-20 | **D2/scope:** Activated abilities first; triggered abilities later. GoblinScript is the main focus. | Users report GoblinScript as the hardest part of authoring. |
| 2026-11-20 | **D1/surface:** Simplified editor takes option C: one auto-laid-out block stack with a live ability card, no free-form canvas. | Keeps Scratch's visible logic and shape-checked slots; an ability is one script, so a canvas only adds tidying. |
| 2026-11-20 | **Picker:** organised by intent (check a condition, check health, check what kind of creature, compare a number, combine tests; use a stat, scale with level, do math, roll dice), not by source. **Who** is preset per formula box and explained in the picker header, never asked up front; every block keeps a dropdown to change it. | Who is being considered is what authors trip over most; asking them to choose it first makes that worse. |
| 2026-11-20 | **D9/regression:** Abilities using behaviours the simple editor does not model still open in it. Each such behaviour is a grey striped **Advanced** block showing its summary and an **Edit in full editor** button; its record is saved back untouched. It can be moved, and wrapped in *Only if* (AND-ed onto its own `filterTarget`). | The simple editor must never take away editing an ability could already have; no ability becomes uneditable here. |
| 2026-11-20 | **Nested abilities: exploring A (inline)** before deciding. B (open with a breadcrumb) is a fallback; it confuses many users. | Seeing the follow-up in place keeps the whole ability readable in one stack. |
| 2026-11-20 | ~~Hand-offs: a *Passes along* row on the follow-up step.~~ Superseded the same day by the row below. | |
| 2026-11-20 | **Parent information is just available inside a follow-up.** No hand-off step: a follow-up's pickers offer *From <parent>* (its tier result, damage dealt, squares moved, number of targets; its first target, its target). The `<< >>` parameters are generated on save from whatever the follow-up uses. Authors never see the piping unless *Show GoblinScript* is on. | `<< >>` confuses people endlessly; the cleanest fix is that there is nothing to wire. |
| 2026-11-20 | **Direct parent only.** A follow-up offers only its direct parent's information; the UI names it after that parent ("From Share the Spoils"). **Saved parameter names never use ability names:** they name the information (`tierresult`, `damagedealt`, `firsttarget`), and existing content keeps its own names. | Renaming an ability must not break anything stored; the label is display only. |
| 2026-11-20 | **One potency block for both functions.** Reads "the target is affected: Might below your strong potency, with this roll's potency changes". "Affected" hides the `not` (passes = resists); "with this roll's potency changes" picks `Cast.PassesPotency`, "base potency only" picks the creature form. Potency can be weak / average / strong, follows the tier rolled, a number, or a formula. | Users constantly stumble over the double negative and over which function counts power roll modifiers. Both functions are kept. |
| 2026-11-20 | **Potency wording:** the function choice reads "including power roll modifiers" / "excluding power roll modifiers". | Shorter, and uses the term players already know. |
| 2026-11-20 | **Five more steps** (most-used after the core five): apply an effect (searchable over the compendium's ongoing effects; also allowed in tiers as tier text), gain or spend a resource, temporary Stamina, end conditions or effects, move a creature. Each has a "The target / You" choice saved as `applyto`. | Content uses these 1,666 / 355 / 81 / 570 / 166 times; most target the user ("caster"). |
| 2026-11-21 | **Step palette (exploring).** A column of step blocks grouped and coloured by what they do: Harm, Hinder, Effects, Help, Move, Resources, Rolls, Logic. Drag a block into any list it is allowed in, or click it to add it to the selected list (outlined in gold; click inside a list or tier to select it). Blocks that cannot go in the selected list are dimmed for clicking but can still be dragged elsewhere. The "+ add step" menu stays as the keyboard path. Step colours in the stack match their palette group. | Building by picking up blocks is more direct than a dropdown, and colour by purpose shows the shape of an ability at a glance. |
| 2026-11-21 | **Palette sits directly right of the stack** (stack, palette, card). On narrow windows it moves above the stack. | Shorter drag distance from palette to stack. |
| 2026-11-21 | **Triggered abilities use the same editor (exploring).** The first choice is "This is an ability / a triggered ability". The author never picks between a Triggered Ability and a Power Roll Trigger: the editor stores it as a Power Roll Trigger exactly when it contains a "Change the roll" step, otherwise as a Triggered Ability, and switches silently as steps are added or removed. The only visible sign is a timing chip: "Happens during the roll" / "Happens after the event". | The two types are one idea to authors; the split is an engine detail. Timing is the part that matters to the rules, so that is what is shown. |

- Picker detail (2026-11-20): each intent shows its first three choices with "Show N more" so every
  intent stays visible; search spans intents. Draw Steel "winded" is its own test block, and the
  parser recognises `X.Stamina <= X.MaximumStamina / 2` as winded when opening existing content.

## 8. Out of scope / rejected

- *A new scripting language that replaces GoblinScript.* Rejected: thousands of formulas in
  content and a closed engine compiler; a projection gets the benefit without the migration.
- *Storing block positions in ability data.* Rejected for v1: adds noise to YAML diffs and
  sync for no gameplay value.

## 9. Open questions

- How many compendium formulas fall outside the block vocabulary? (Answered by plan step 1.)
- Is `filterTarget` the right compile target for every `if`, or do some authors mean a
  once-per-cast branch? (Look at real content during step 3.)
- Should the opaque block show the existing form inline (expand in place) or in a popup?

## Appendix: prototype notes

- Trigger ids, names and symbol sets in the prototype are copied from `TriggeredAbility.lua`
  and `MCDMRules.lua`. Behaviour `__typeName`s are real; their field sets are trimmed.
- The parser follows the precedence table in GoblinScript_Guide.md exactly, including its
  treatment of `has`/`is`/`not` inside spaced names.
- Potency blocks compile to the `M<N` tier prefix. Used outside a tier they emit an
  illustrative `PotencyWeak/Average/Strong` symbol and a warning; that symbol is not real.
