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

## 4i. Critique round 1: Hodent lens (2026-11-21)

An independent reviewer worked through the prototype (four tasks, desktop and phone width);
findings below are merged with the designer's own pass. **Proposals, not decisions.**

| Pillar | Rating |
|---|---|
| Signs and feedback | Mixed: card and status panel strong; list selection and trigger timing switch are silent |
| Clarity | Mixed: card reads well; potency block and nested pills are hard to decode |
| Form follows function | Mixed: actions ("Target is Slowed") read like tests ("Target is Prone") |
| Consistency | Weak: potency has four names and two colours; four phrasings for conditions |
| Minimum workload | Mixed: about 18 clicks for a standard strike |
| Error prevention and recovery | Weak: easy to nest in the wrong place; no undo |
| Flexibility and accessibility | Mixed: menus exist; narrow width, tab order, close hues and colour-only categories weak |
| Motivation | Good: GoblinScript hidden, card language |
| Emotion | Mixed: polished, a few glitches (off-screen picker, drag ghost) |
| Flow | Mixed: selection mode and scrolling to pickers interrupt |

Ranked problems:
1. **Click-to-add goes to an invisible "selected list"** that does not follow new wrappers: a
   condition added after "If potency fails" lands beside it, not inside, and the card shows it
   ungated. The palette hint names the wrong list inside an Only if.
2. **Potency has four names and two colours** ("If potency fails" purple in the palette, orange in
   the stack; "is affected: ... below ..." in tests; "M<AVERAGE" on the card).
3. **The potency test is 6-7 dropdowns long** and wraps badly; its warning note is engine jargon.
4. **Trigger timing switches silently and changes the rules** (deleting "Halve the damage" moves the
   shift from during to after the strike). Status text still says "ordinary ability".
5. **No undo**, no confirmation on delete.
6. **Actions and tests look alike** in words ("Target is Slowed" vs "Target is Prone").
7. **Picker:** opens off-screen, never flips up; Prone hidden behind "Show 24 more"; the
   spaced-name trap error is not plain English.
8. **Narrow width and keyboard:** palette sits far above the stack; tab passes 14 palette buttons
   first; "Who its steps affect" overlaps each step's own You/The target choice.
9. (Designer) **Too many hues and too much chrome:** about ten colours and white dropdown chips on
   every token make a finished ability noisy; categories are shown by colour only once in the stack.
10. (Designer) **The most common shape costs the most work:** a strike's three tiers are three stacked
    mouths, though the card shows them as one three-row table.

Keep: the live card, plain-language status with one-click repairs, parent information without
wiring, dimmed blocks with reasons, the value box plus fx, the ... menu.

More elegant alternatives considered:
- **A. Card as editor** (edit the card's lines in place, blocks as a structure view). Failure: nesting
  and follow-ups do not fit card prose; edits map ambiguously back to data.
- **B. Insertion points instead of a selection mode:** a "+" between steps and inside every tier and
  wrapper opens a type-ahead list of only the steps valid there; the palette becomes a collapsible
  drag shelf. Fixes 1 and 8. Failure: less browsable (the shelf covers that).
- **C. Explicit timing for triggers:** "Changes the roll as it happens / Reacts after" chosen first,
  pre-filled from the event, filtering events and steps. Fixes 4. Failure: one more decision.
- **D. Formulas as a typed line with chips** for power users. Failure: brings parse errors back for
  directors; offer it only as a mode of the existing "Type a formula" box.
- **E. (Designer) Read mode:** finished blocks render as plain sentences with underlined editable
  tokens ("Deal **3 + your Might** damage"); the dropdowns appear only on the token being edited.
  Fixes 3 and 9. Failure: editing needs one more click; tokens must look clickable.
- **F. (Designer) Power roll as a tier table:** three columns or rows matching the card, each a
  drop zone, plus "starter" templates (Strike, Area, Reduce damage trigger). Fixes 10.

## 4j. Generated card text with overrides (replacing the Triggered Ability Display)

**Today:** a triggered ability's book-style card is a separate modifier, behaviour `triggerdisplay`
(`Draw Steel Core Rules/DSModifyTriggerDisplay.lua`), holding hand-written text fields: name, cost,
keywords, flavor, type, distance, target, trigger, effect. It finds the trigger it describes only by
**matching names** (`TriggeredAbilityDisplay:FindLivePartner`, line 322), to show range changes.
In content: 345 displays for 1,675 triggers (Triggered Abilities plus Power Roll Triggers); 271 have a
trigger of the same name in the same file and **74 do not** (text-only displays for unimplemented
triggers, missing names, or renamed triggers). The text can drift from what the trigger does, and a
rename silently breaks the link. Abilities generate most of their card already, but their Effect
prose (`description`) is typed by hand.

**Design (prototype):**
- The card is the ability's rendering in game (tooltip, sheet, action bar), generated from the
  blocks: flavor, distance, target, each tier, trigger, effect.
- Click any line to reword it; Enter saves, Esc cancels, saving the generated text unchanged removes
  the override. Reworded lines are marked "custom wording" with Reset.
- Each override stores the generated text it replaced (`basis`). When the rules change and the
  generated text no longer matches, the line is flagged **"rules changed"** with "Use new wording".
- Flavor has no generated text; it is always author-written.
- Saved as a proposed field on the ability or trigger itself: `displayOverrides: {t3: "...", flavor: "..."}`.

**Engine work this would need** (planning only; nothing changed):
1. A `displayOverrides` field (plus the stored `basis` per line) on `ActivatedAbility` /
   `TriggeredAbility` / power roll triggers, and the card renderer using an override when present.
2. One renderer that generates book-style text from the data for both abilities and triggers, so
   the sheet, tooltip and action bar no longer need a `triggerdisplay` record.
3. Migration: for each display with a same-named trigger in the same owner, move its text into that
   trigger's overrides (only where it differs from the generated text) and delete the display.
   Displays with no partner (74) stay as they are until someone links them, and get listed for review.
4. Update what currently reads displays: the character builder's filter on
   `activated/triggerdisplay/routine` (`MCDMCharacterBuilder.lua:95`), the sheet and action bar
   listings, and `FindLivePartner` range-modification lookups (no longer needed once the card is the
   trigger's own).

## 4k. Real test: Raise Hell (2026-11-21)

A user asked for help implementing this ability (5 Insight, Magic/Melee/Weapon, main action, Self; see
below): "You shift up to your speed in a straight line, and enemy squares are not difficult terrain for
this movement. You make one power roll that targets each enemy whose space you move through. Power Roll +
Agility: 3 / 5 / 8 fire damage. Effect: Each space you enter or leave during this movement is burning
with hellfire." It is not in the compendium. The user's working setup: Relocate Creature with **Target
Creatures in Move Vicinity** and **Target Passed Squares** checked.

In the simple editor (example "Raise Hell"):
1. *You shift up to your speed in a straight line through enemies' spaces -> targets each enemy whose
   space it moves through and marks the squares it passes.* Saves as Relocate Creature
   (`movementType: shift`, `targetMoveVicinity`, `vicinity: 0`, `vicinityFilter: Enemy`,
   `targetPassedSquares`) and sets the ability's `targeting: straightpathignorecreatures`,
   `targetType: emptyspace`, `range: MovementSpeed`, as content does (Writ of Execution, Crash Through).
2. *Power roll 2d10 + Agility: 3 / 5 / 8 fire damage.* Its targets are the enemies the move reached.
3. *Leave Hellfire on the squares the move passed.* Create Aura on the trail.
4. Card: flavor, "Self; see below", and the two Effect paragraphs are the book's wording as overrides.

Findings:
- The two checkboxes that made this work are invisible in today's editor unless you know them; as words on
  the Move block they are the obvious next choice.
- "Who it targets" reads "1 self within Self" when targets come from a step. It should say "set by
  Move a creature" (proposal).
- Heroic Resource should show the class's name (Insight) on the card (proposal).
- "Burning with hellfire" is an aura effect: it is authored inside the Create Aura block ("When a
  creature enters it: ..."). Hellfire is not defined in the compendium, so the example leaves its
  section empty and flags it for the author.
- To verify in the app: `straightpathignorecreatures` is supported in code (`IsStraightLineMove`) but no
  content uses it yet.

## 4l. Paste ability text to build blocks (2026-11-21)

The author pastes the ability as printed (book, PDF, Forge Steel export, statblock) and the editor
builds what it can read. This reuses the monster importer's approach
(`Draw Steel Importers/DrawSteelMonsterImporter.lua`), not new rules:

- **Header lines:** "Name N Resource" gives the name and cost. An unlabelled line before the keyword line is
  flavor. "Keywords... Action" gives the keyword chips and the action type. The distance/target line gives
  range and targets. Text the blocks cannot say ("Self; see below") is kept as the card's wording.
- **Power roll tiers** use the tier grammar the importer already has (`importerPowerTableEffects`):
  damage with a type and a characteristic, conditions with (save ends)/(EoT), push/pull/slide N, and
  potency `M<weak ...` with what follows nested inside the potency block.
- **Effect sentences** are matched one by one against sentence patterns. In the app, these are the
  importer's `importerAbilityEffects` templates (importMatch with `<<param>>`). Patterns can change a
  block an earlier sentence built: "...targets each enemy whose space you move through" sets the move's
  catch option, and "each space you enter or leave... is burning with X" turns on the trail and adds an aura.
- **What it cannot read** becomes a "To build" block that quotes the sentence. The author drops blocks
  inside it, and the ability won't save until each one is built. Once built, **Save as pattern** turns that
  sentence (numbers become parameters) plus its blocks into a new importer template, so the next paste of
  the same wording builds itself. This is the teach loop: every hand-built sentence shrinks future work.
- **The pasted wording is the card's text** (overrides with no generated basis), so the card reads exactly
  like the book even where the blocks are rough.

Tests in the prototype: the Raise Hell text builds the move with its catch and trail options, the power roll
and the Hellfire aura, and leaves only the aura's own effect to fill in (the card doesn't say what hellfire
does). A monster strike with "M<3 prone; the target can't stand (EoT)" and an ally free-strike sentence
builds everything except those two clauses.

**Messy copies (third-party PDF test, Instant Cement).** Copying from a PDF loses the icons, and the icons
carry meaning: the tier markers (the three result lines arrive bare), the distance and target icons, and
sometimes the potency ("2 poison damage; , slowed (save ends)"). The reader now:
- turns icons and odd spaces into plain spaces, and reads "Name (5-Wonder)" as well as "Name 5 Insight";
- treats the first three bare lines after "Power Roll + X" as tiers 1-3;
- reads a lone comma before a condition as a lost potency and **guesses** it (the roll's characteristic,
  weak/average/strong by tier, as cards do), marking the block **check** so the author confirms it;
- keeps a resource no core class has (Wonder) as the card's word;
- builds "The area is difficult terrain for your enemies" as an aura on the target area, and "Each enemy who
  ends their turn in the area and has M < AVERAGE slowed (save ends)" as a section of that aura with an
  "Only if M < average" test.

Finding: auras have no "end of the affected creature's turn" trigger (`Aura.TriggerConditions` has enter,
first enter each round, start of the affected creature's turn, and start/end of the caster's turn). The
prototype shows the section and blocks saving with "engine work: a new aura trigger".


Engine work if adopted: a JS-free Lua path. The paste dialog calls the importer's parsing functions on one
ability's text, maps the resulting behaviours to blocks (the same mapping the editor uses to open saved
abilities), and "Save as pattern" writes an `importerAbilityEffects` row.

## 4m. Random poll of class abilities (2026-11-21)

55 abilities, drawn at random (fixed seed) from every class and subclass: one per level band (1, 2-3,
4-6, 7-10) per class, plus one player-facing trigger each. Each was checked two ways: its saved setup
against what the editor can show as blocks, and its book text pasted into the reader. Scripts and results:
`ui-mockup/ability-blocks-corpus/poll/`.

**15 of 55 map onto blocks with nothing missing** (e.g. Brutal Slam, Meteoric Introduction, Conflagration,
Impart Force, Mark, Sacred Bond, Oracular Warning, Equal Billing, and the power roll triggers Synaptic
Anchor, Advanced Tactics and Stasis Shield as far as their fields go). The other 40 hit one or more of:

| Issue | Abilities | Examples | What the editor needs |
|---|---|---|---|
| Nested / invoked abilities | 14 | Get In Get Out (3 deep), Blot Out the Sun!, Pierce the Veil (2 deep), Feral Strike | Works with "Use a new ability", but depth 2-3 is hard to read. A collapsed summary per nested ability. |
| **Modes** (choose one when using it) | 12 | Banshee Howl "Standard / Spend 1 Ferocity", Elemental Fury and Grand Wyrding (7 damage types), Sanctified Weapon, Coat the Blade, Optic Blast (numTargets = Mode) | **Not modelled at all.** Biggest gap. Needs a "When you use it, choose:" block with one branch per option, and "spend N more" options as their own pattern. |
| Advanced behaviours | 12 | Ability Duration Effect (4), Condition Riders (2), Summon, Recast, Modify Power Roll (2), Forced Movement Origin | Ability Duration Effect and Riders are common enough to deserve sentence blocks. |
| Distance written as text (`rangeTextOverride`) | 11 | "Melee 1 or ranged 5" (content uses the override, not meleeRange), "2 aura", "5 aura", "3 burst" on a self ability whose nested ability does the targeting | Add **N aura** as a distance form. Generated card text replaces the other overrides. |
| Tier text the tier grammar can't read | 11 | "P < Weak, jaws of death (save ends)" (multi-word effect), "#the target is suppressed (save ends)" (custom effect text), "vertical push straight up 5", "the target gains two surges", "M < Strong prone and can't stand (EoT)", "bleeding (EoT), or if M < Strong, bleeding (save ends)", narrative tiers (Dead Men Tell All Tales) | Multi-word effect names, surges, "vertical push", "can't stand", and a text-only tier result. |
| Formulas with symbols the editor doesn't know | 9 | SummonerRange, Mode, Resources.Rampage, Resources.Recovery, Caster.Recovery Value, Cast.Damage Dealt, Used Ability.keywords has "Void", Friends(Caster, Target) | Add these symbols to the field descriptions; "Friends" and "Used Ability has keyword" as tests. |
| Display-only power roll hack | 2 | Feral Strike, Get In Get Out: a power roll with `filterTarget: 0 {Display only}` so the card shows the table while the real roll runs in a nested ability | Generated card text with overrides makes this hack unnecessary. |
| Trigger targets | 2 | Blessing of Life (targetType subject), Snare Ward (attacker) | The trigger header needs "affects the triggering creature / the attacker". |
| Power roll trigger fields | 3 | surges (Advanced Tactics), activationCondition and custom trigger (Synaptic Anchor), changeTargetEffect / changeTargetFilter (Stasis Shield), rollType and keywords filters | Add "gain surges" to Change the roll, and a "which rolls" filter (roll type, keywords). |

**Paste from the book PDF: 3 of 33 came out clean.** The rulebook's PDF text has its own copy artefacts,
different from the third-party PDF:
- tier markers come through as the letters **a / e / i** ("a 3 + M damage"), distance and target as
  **o** and **x** ("o Melee 1 or ranged 5", "x One creature"), and potency as **m<w / m<v / m<s**
  (weak / average / strong);
- the action ("Main action") is on its own line after the keywords;
- lines wrap mid-word with a stray space ("encoun ter", "crea ture", "dupli cate");
- bullets come through as **Y**;
- a tier's text can wrap onto a second line ("the target is suppressed" / "(save ends)").
The markdown reference format (Beastheart) wasn't read at all: "**Name (7 Ferocity)** *(keywords -- Main
Action)*", "- Distance: ... | Target: ...", and a table for the tiers. Each copy source needs its own small
set of rules, so the reader should keep a list of known formats and say which one it recognised.

Sentence patterns: none of the effect sentences in the sample matched an existing pattern, so they all
became "To build". The common ones are good candidates for the importer's pattern table: "You gain N surges",
"Each target gains N surges", "You can shift up to N squares", "You or one ally within distance can spend a
Recovery", "You gain an edge on this ability", "Until the end of the encounter, ...", and "Spend N+ Resource:"
paragraphs (which are modes).

## 4n. Modes, tier grammar additions and two new sentence blocks (2026-11-21)

Built from the poll's findings (4m), items 1, 3 and 4.

**Choose one when used (modes).** A Logic block: "When you use it, choose one [before picking targets /
after picking the target]", then one section per option with its name and an extra cost ("no extra cost /
costs 1-3 more"). Steps inside an option only happen with that option; steps outside the block happen in
every mode. Saved the way content does it: `multipleModes: true`, `modeList: [{text, condition, rules}]`
and `modesSelected: [n]` on each behaviour inside option n. An option with an extra cost gets
`condition: "Heroic Resources Available to Spend >= N"` and a spend-Heroic-Resource step, as Banshee Howl
does. The option's card line is labelled with its name ("Spend 1 Ferocity: ...") and its text is also saved
as the mode's `rules`. One per ability, at the top level; not yet on triggered abilities. 288 compendium
abilities use modes. Pasted "Spend N Resource:" paragraphs become options.

**Modes vs Ability Variations (decided 2026-11-21).** The engine has two kinds of modes, and the author
never picks between them: the editor decides how to save, as it does for triggers.
- Each option has "same targets / targets differently". When every option uses the ability's targets, the
  block saves as Multiple Modes (`multipleModes: true`, steps gated by `modesSelected`).
- When any option targets differently, it saves as Ability Variations (`multipleModes: "variations"`). That
  option shows its own Distance and Target rows (the same card-worded rows as the header) and saves as
  `hasAbility: true` plus `variation`: a whole ability with that targeting holding that option's steps only
  (corrected in 4q: the engine swaps it in, so steps outside the block don't run with it), and
  `resourceCost: "none"` so the base ability's cost is kept. Options that keep the same targets stay as gated steps on the base ability,
  which the engine supports in variations mode too.
- "After picking the target" only works with plain modes, so the block shows "before picking targets" as
  fixed text once an option targets differently.
- Switching an option back to "same targets" keeps its steps (now gated) and says so in a toast; Undo restores
  its targeting.
- The option's card line starts with its own distance and target ("Slide a creature: Ranged 30, one
  creature. Slide the target 2.").
- Example: "Reposition" in the Open menu. About 64 compendium abilities use variations (30 monsters).
- Content finding: Coat the Blade (College of Caustic Alchemy) has two modes but `multipleModes: false`, so
  the choice is probably never offered.

**Tier grammar additions** (each saves as tier text the engine's existing patterns already read):
- conditions can carry a **rider**: "prone and cannot stand (EoT)" (the rider list comes from the
  conditionriders table, filtered to the chosen condition);
- conditions can have **no duration** ("prone", "grabbed");
- **vertical push straight up N**;
- **the target gains N surges** (a new "Gain surges" tier block);
- **Card text only**: words with no automation, saved in a tier as "#text" (the engine's do-not-parse marker)
  and in the main list as card text. A "To build" sentence has **Keep as card text** for this;
- multi-word compendium effects in pasted tiers ("jaws of death (save ends)") and potency written
  without a comma ("M < Strong prone ...").
- **N aura** as a distance form. There is no aura target type for an ability, so it saves as a burst of the
  same size, as the importer does, with `rangeTextOverride: "N aura"` so the card keeps the wording.

In the poll, abilities with tier text the reader can't build went from 11 to 3: two narrative tiers (now
"Keep as card text") and "bleeding (EoT), or if M < Strong, bleeding (save ends)", which needs an
"otherwise" form of potency.

**New sentence blocks** (replacing two Advanced/generic entries):
- **While this ability resolves** (Ability Duration Effect): "[You have / Each target has] [name] while this
  ability resolves: [card text]", with Settings for its modifiers (the existing effect editor). Pasted "You
  gain an edge on this ability" and "This ability ignores cover and concealment" build it.
- **Add to a condition** (Condition Riders): "While [Prone] this way, the target is also [cannot stand]".

Also: an unbuilt "To build" sentence now still shows on the card, so its wording isn't lost.

## 4o. Open-and-save test on real class abilities (2026-11-21)

The 45 ActivatedAbility records in the poll sample (4m) were opened as blocks, saved, and compared with the
original, field by field. Triggers (10 CharacterModifiers) were not part of this run. Scripts and results:
`ui-mockup/ability-blocks-corpus/poll/roundtrip.js`, `roundtrip.json`.

**The save rule this needed: anything the author didn't change saves back exactly as it was.**
- Each step opened from saved behaviours remembers them, plus a fingerprint of what it compiled to when
  opened. On save, an unchanged step writes its original records; a changed one writes its new settings
  over the original record, so fields no block shows (Strained, "dealt to you", "can't be reduced", chat
  messages, ids) survive the edit.
- Each power roll tier does the same, so editing tier 1 never rewrites tiers 2 and 3.
- Each formula keeps its saved spelling while unchanged ("enemy" stays "enemy", not "Enemy").
- Each ability-level field keeps its saved value while unchanged; fields the editor never writes ride along.
- Words the blocks can't read (in tiers or formulas) were already working in the saved ability, so they are
  kept as written ("Kept as saved") and don't block saving.

**Results**
| Check | Result |
|---|---|
| Opens without error | 45 of 45 |
| Untouched save is identical to the original | 45 of 45 |
| Rename only changes the name | 45 of 45 |
| Raising one tier's damage changes only that tier | 18 of 18 power rolls |
| Can be saved as opened (nothing the editor blocks) | 45 of 45 |
| Opens entirely as blocks (no Advanced steps, nothing kept as unread words) | 29 of 45 |
| Steps: blocks / Advanced / unread words | 246 / 16 / 7 |
| Has saved settings no block shows (listed in "kept as they are") | 26 of 45 |

**Bugs the test found and fixed** (before the fixes, editing would have damaged content):
- Editing one tier regenerated all three, and **dropped tier text the blocks couldn't read** (Blood on the
  Stage lost "bleeding (EoT), or if M < Strong, bleeding (save ends)"; Applied Chronometrics lost all three
  tiers). Now tiers are kept per tier, and unread words are never dropped.
- Tier damage was written "11 + Might damage"; content (and the card) uses "11 + M damage".
- Apply an effect wrote `ongoingEffectCustom: false`; content stores the effect id there too.
- Effect durations "until the end of the encounter or until you are dying" (`eoe_or_dying`, 12 uses) and
  "until you finish a respite" (`until_rest`, 13) were missing.
- Invoking a **standard** ability (free strikes etc., 8 in the sample) was opened as a "Use a new ability"
  block and would have been resaved as a custom one. Now it opens as an Advanced step.
- A follow-up ability lost the information it was passed (`standardAbilityParams`) when anything inside it
  changed, and its own fields (targeting, keywords). Now kept.
- Card wording overrides for flavor, distance and target now save to the engine's existing fields
  (`flavor`, `rangeTextOverride`, `targetTextOverride`) instead of the proposed `displayOverrides`.
- A saved formula with a `{comment}` (the display-only power roll trick) and a duration effect with no card
  text blocked saving; neither should.

**Follow-up from reviewing Optic Blast (2026-11-21)**
- The card used generated effect text instead of the ability's saved `description`, which holds the book
  wording ("**Strained:** ..." included). An opened ability now shows its description, paragraph by
  paragraph with labels, as its effect text, and edits save back to `description`. Saved wording (flavor,
  distance, target, description) is no longer tagged "custom wording" until the author changes it.
- **If you are Strained** is a Logic container: "If you are [Strained / not Strained]:". Each step inside
  saves `strainSelection` (the engine checks the caster when the ability runs), and the card line is
  labelled "Strained:". Opening groups neighbouring Strained steps into one container (64 compendium
  behaviours use strained, 13 unstrained).
- Damage outside a tier says who takes it and whether it can be reduced: "Deal [Reason] damage [to you]
  [that can't be reduced]" (saved as `applyto: caster`, `cannotBeReduced`).
- Advanced steps read as their full-editor name plus what the record says ("Modify Power Roll: You gain a
  surge, which you can use immediately...").
- Optic Blast's Modify Power Roll is tagged Strained in the saved data (`strainSelection: strained`,
  `displayCondition: Caster.Strained`), not tied to the Reflective Surface mode; the Reflective Surface mode
  works through `numTargets: Mode` and proximity targeting. It now shows inside "If you are Strained".

**Book first, and Strained inside Only if (2026-11-21)**
- Standing rule: **the card always follows how the book displays an ability**, and saved book wording wins
  over generated text. For an opened ability the effect text comes only from its saved `description`
  (paragraphs and "**Label:**" labels); option lines use the saved mode `rules`, after the effect, as the
  book orders them; nothing generated is added. A description that is really an implementation summary
  (it repeats "Power Roll + ...") is kept but not shown; an ability with no usable description shows an
  "Add effect text" line instead of invented wording.
- Generated wording, when there is no saved text, follows the book's phrasing: "The target takes 5 damage",
  "Push the target 2 squares", "You make a free strike", "Trigger: The target takes damage" (when the
  triggering creature is the target) or "an ally within distance ...", "One creature or object",
  "Two creatures or objects". A formula target count of `Mode` shows its usual value ("One").
- Filters and requirements are no longer printed on the card (the book doesn't); they are listed under it.
- **Strained is a test in Only if**, not its own block: the picker has "You are Strained" / "You are not
  Strained" at the top for Only if. An Only if whose test is Strained saves as `strainSelection` on each step
  inside; "you are Strained and <other test>" saves `strainSelection` plus `filterTarget` for the rest. The
  card labels it "Strained:". Opening content turns `strainSelection` into "Only if you are (not) Strained".

**Still open**
- Advanced steps (16): invoking a standard ability 8, Summon 2, Modify Power Roll 2, and one each of
  Relocate Creature, a power roll with a non-2d10 roll, a rule the tier grammar can't read, and a Script.
  "Invoke a standard ability" (free strikes) is the obvious next block.
- Saved settings with no block (26 abilities): mostly effect and ability fields such as `targetAllegiance`
  (11), `objectTarget` (8), `selfTarget` (7), follow-up `standardAbility` / `inheritRange` / `autoTarget`,
  `channeledResource` (4), "Respite Activity" as the action (3), Strained-only and some-tiers-only steps, and
  a power roll's own edge. They are kept and listed; showing the meaningful ones as words is next.
- In an edited tier, potency is rewritten in one spelling ("M<weak, prone" for "M < Weak prone").
- Triggers (CharacterModifier records) still need the same open-and-save test.
- Content question: Dramatic Reversal's "Spend 1 Drama" option has the condition "Resources.Heroic Resource >= 2".

## 4p. Second poll: monsters, new class abilities, triggers, and the book check (2026-11-21)

A fresh random sample (new seed): 25 monster abilities across level bands (one per monster), 25 class
abilities not in the first poll, and 10 player-facing triggers (5 class, 5 monster; 3 are power roll
triggers). Each was opened, saved, edited, and its card compared with the printed text (monster-reference.md,
the rulebook PDF text, the Beastheart reference). Scripts and results: `ui-mockup/ability-blocks-corpus/poll2/`.

**Open and save**
| Check | Result |
|---|---|
| Opens without error | 60 of 60 |
| Untouched save identical to the original | 60 of 60 |
| Rename changes only the name (a trigger's inner record takes the same name, by design) | 60 of 60 |
| Raising one tier's damage changes only that power roll | 28 of 28 |
| Can be saved as opened | 60 of 60 |
| Opens entirely as blocks | monsters 17/25, class 15/25, triggers 4/10 |
| Steps: blocks / Advanced / unread words | 297 / 29 / 1 |

**Editor problems found and fixed in this round**
- Triggers could not be opened at all. Now: trigger and power roll trigger records open into the trigger
  header (event, who, distance, action, condition) and steps; a power roll trigger's roll changes become
  "Change the roll" blocks; an opened trigger keeps its saved record type.
- **The editor saved a power roll trigger's condition as `filterCondition`; the engine reads `targetFilter`**
  (PowerTableTriggers.lua). Fixed.
- The trigger event list had 14 of the engine's ~30 events (e.g. no "attack an enemy", used by Triangulate);
  subjects lacked "another hero" and "you or another hero". Added; any other id opens with its raw name.
- Monster power rolls ("2d10 + 3", "2d10 + Highest Characteristic") opened as Advanced steps, so their cards
  had no tiers. The roll block now takes a flat bonus or "highest characteristic", and the card shows it
  beside the name as monster cards do ("Acid and Claws (2d10 + 3)"). Also "Might or Agility", and a roll
  saved with a trailing space.
- Saved content can list option 2's steps before option 1's; editing anything in the choice block put them
  in option order (one edit rewrote four steps). The saved order is now kept; new steps go last.
- A power roll inside an option or "Only if you are Strained" showed as "make a power roll" instead of its tiers.
- Abilities saved with no steps (text-only villain actions and the like) were blocked from saving.
- "Villain action" was missing from the action list (4 monster abilities opened as "No action").
- Target wording now comes from the saved filter ("Enemy" gives "each enemy in the area"; otherwise
  "creature"), instead of always "enemy" for areas.
- Tier grammar: "push 4 and prone" (two results joined by "and").
- Descriptions with inline labels ("**2 Malice**:", "3 Malice:") split into labelled paragraphs.
- Opened triggers show only saved wording on the card (no generated "Raise Corpse, float Text..." line).

**Book check (44 with printed text)**
| Part | Matches the book |
|---|---|
| Tiers | 77 of 81 |
| Distance | 34 of 44 |
| Target | 26 of 44 |
| Effect paragraphs | 28 of 52 |
| Whole card | 16 of 44 |

None of the remaining mismatches come from the editor rewriting anything; they are what the saved data
holds:
- **Distance and target wording isn't stored for most monsters.** Class abilities carry `rangeTextOverride` /
  `targetTextOverride`; monster records almost never do, so the card has to derive "Self" or "Ranged 5"
  from targeting that is really done by a nested ability ("Five 2 cubes within 20", "The triggering
  creature", "3 x 1 line within 1", "Special"). `objectTarget` is often unset where the book says
  "creature or object", and "Self or one ally" / "Self and each ally" have no field.
- **Effect text is paraphrased in many monster descriptions** ("The target is released from the grab and
  slides 5." for "The target is no longer grabbed by the deathrex, and the deathrex slides them up to 5
  squares."), and **triggered monster abilities' descriptions usually lack the Trigger line**.
- Tier text doubles as automation, so where content adds parse-only words the card shows them too
  (Gravitic Charge: "Vertical slide 5, ignoring stability"; the book puts that in the effect). One tier is a
  placeholder in the data ("5 damage; effect", Rotting Fist).
- 9 of the 24 effect mismatches are the check's own extraction picking up the next feature's text.

**Recommendation from this:** the monster importer already parses the statblock's distance, target, trigger
and effect text; it should store them verbatim (`rangeTextOverride`, `targetTextOverride`, `description`
with "**Trigger:**" and "**N Malice:**" paragraphs). Then book-first cards work for monsters as they do for
heroes. Worth a content pass for existing monsters.

## 4q. Trigger cards, adding paragraphs, and every trigger in the compendium (2026-11-21)

**"+ Add paragraph".** Under the card's effect text, in the same quiet style as "Add flavor text". It adds a
paragraph in editing mode labelled "Effect"; the label renames by click (suggestions: Effect, Special,
Strained, Persistent, Spend N, N Malice). Hovering a paragraph shows up / down / remove. Added paragraphs are
card text only. Adding one to a card still made from the blocks first turns the card into saved paragraphs,
each remembering the generated text it came from, so a later change to the blocks flags it "rules changed"
(with "Use new wording"); a paragraph reworded by hand shows "custom wording". Saved to `description` with
"**Label:**" labels (to the display record for triggers that have one).

**Display toggle.** In a trigger's header: "It [shows a triggered ability card / has no card (works in the
background)]". New triggers default by action (triggered and free triggered: card; no action: none). Opening
sets it from whether a Triggered Ability Display exists. Off: the card preview is marked "No card", and an
opened display is noted as removed on save.

**Display wording is the card.** Opening a trigger finds its Triggered Ability Display (matched by name, as
`FindLivePartner` does) and shows its book wording: Trigger and Effect paragraphs, flavor, distance, target,
cost. Edits save back to the display record (`ability.trigger`, `.effect`, `.flavor`, `.distance`,
`.target`, `.cost`); the trigger itself is untouched. A new trigger with the toggle on gets a display built
from the card. In the data: 1,148 triggers; 328 have a display (triggered 170 of 212, free triggered 45 of 99,
no action 113 of 837).

**Every trigger, opened and saved** (`ui-mockup/ability-blocks-corpus/poll3/`)
| Check | Result |
|---|---|
| Opens without error | 1,148 of 1,148 |
| Trigger saves back identical | 1,148 of 1,148 |
| Its display saves back identical (or stays absent) | 1,148 of 1,148 |
| Rename changes only names (trigger, its inner record, its display, a variation) | 1,148 of 1,148 |
| Can be saved as opened | 1,148 of 1,148 |
| Event has words in the editor | 1,144 (4 rare ids open with their raw name) |
| Opens entirely as blocks | 621 of 1,148 (Advanced steps: invoke a standard ability 240, Remove Creature 90, unread rules 63, Float Text 42, Loyalty Collar 40, Summon 33, Augmented Ability 32, Aura 31) |
| **Trigger condition reads entirely as blocks** | **46 of 571** |
| Card matches the book (display + printed text found) | 100 of 114; Trigger lines 109 of 113, Effect 100 of 114 |

Fixed along the way: triggers can use "Choose one when used" (27 content triggers do), and so can a follow-up
ability (5), each saving its own modeList; a power roll trigger's custom trigger keeps its own name; an
opened follow-up with no steps, and saved formulas with dice in a test, no longer block saving; a saved
"Change the roll" value the wording didn't know no longer crashes the card; 10 more trigger events
(move through a creature, finish using an ability, regain Stamina, use a resource, move away, kill...) and
the "another creature" subject.

**Correction to 4n (variations).** Content's variation abilities hold only that option's steps: when the
option is picked the engine swaps in the variation (`SwitchModes`), so steps outside the choice block don't
run with it. The editor now saves a variation with only that option's steps, and the note says so.

**Display cards beat monster descriptions for book fidelity.** Where a display exists, the card matches the
book 100 of 114 times; the misses are content (Skitter's display says shift 2, the book 3; Final Orders'
display trigger differs from the book; one display is empty).

**The biggest trigger problem left is the condition.** Only 46 of 571 trigger conditions become blocks.
The parts that stay as formula, by count: string comparisons (99), `HasAttacker` (48), `SaveEndsEffects`
(45), `Self.OngoingEffects has "..."` (32), bare `Self` / `Subject` / `Attacker` / `target` (76), damage
type tests (`DamageType is fire`, 45), the used ability's keywords or name (46), `TriggerName` (18),
`Distance(Attacker)` (11), class-specific fields (`Self.DragonsealArmed`, `Self.Rampaging`). Symbols used:
Self 247, Subject 156, Damage 109, Attacker 83, Target 54, Used Ability 63. This is the GoblinScript authors
find hardest; a trigger-condition vocabulary (who set it off, the attacker, the damage, the ability used)
is the next piece of work.

## 4r. Trigger condition blocks (2026-11-22)

"Only triggers if" now speaks the event's language. The engine already describes what each trigger event
provides (`TriggeredAbility` trigger definitions and `RegisterTrigger` calls: name, type, description,
sometimes wording); the editor reads that list for the chosen event:
- **Creatures the event provides become roles beside "you" and "the triggering creature":** the attacker,
  the target, the caster of a failed save. Every creature test works with them ("the attacker is
  prone", "the attacker's Stamina...").
- **Yes/no values become tests** with plain wording ("there is an attacker", "the movement was forced",
  "the roll is tier 3", "it is part of another ability").
- **The picker has an "About this event" group** at the top: those yes/no tests, and for each creature
  "the [attacker] is you", "is within [1] square of you", "is your ally"; for text values "the damage type
  is [fire]", "the condition is [Grabbed]", "the trigger name is [...]"; and "it has the [Strike] keyword".

New readings, each saving back in the content's own form (and unchanged formulas keep their spelling):
| Formula in content | Reads as |
|---|---|
| `HasAttacker` | there is an attacker |
| `Attacker = self`, `Subject = Self` | the attacker is you |
| `Distance(Attacker) <= 1`, `Subject.Distance(Self) > 3` | the attacker is within 1 square of you |
| `Friends(Self, Attacker)`, `not Friends(...)` | the attacker is (not) your ally |
| `Damage Type is acid or ... is cold or ... is fire` | the damage type is acid, cold or fire |
| `Damage Type != "Fire" and Damage Type != "Holy"` | the damage type is not fire or holy |
| `Condition = "Grabbed"`, `TriggerName = "..."`, `EffectName = "..."` | the condition is Grabbed / the trigger name is ... |
| `UsedAbility.Keywords has "Melee"`, `Keywords has "Strike"` | the ability used / the damage has the Melee keyword |
| `UsedAbility.Name is "Hide"`, `UsedAbility.Categorization = "Heroic Ability"` | the ability used's name / category is ... |
| `Self.OngoingEffects has "Lost Tail"` | you have (don't have) the Lost Tail effect |
| `Save Ends Effects`, `Self.Rampaging`, `Victories > 0` | you are affected by an effect a saving throw can end / you are rampaging / your Victories is more than 0 |
| `Path.Forced`, `Path.Shift`, `Used Ability.Free Strike`, `HasAbility` | the movement was forced / was a shift / the ability used is a free strike / the damage came from an ability |

**Result on all 1,148 triggers:** trigger conditions that read entirely as blocks went from **46 to 346 of
571** (8% to 61%); all 1,148 triggers and their displays still save back identical, none blocked. A power
roll trigger's condition uses the matching triggered-ability event's list (the power roll trigger events
have none of their own), and a saved condition naming something the editor doesn't list no longer blocks
saving.

**Still formulas (by count):** class relationships (`Subject = Self.Companion`, `Subject.Summoner = Self`,
`HasCompanion`, `Companion.id`, ~45 together), class fields (`Self.DragonsealArmed`,
`Self.CompanionRampaging`, `HeroicResourceGainatStart`, `Resources.Recovery`, `Summoner.Resources.Epic
Resource`), `Malice`, `Path.DistanceToCreature(Self)`, `CountNearbyCreatures(...)`, `Cast.HasTarget(Self)`.
Next candidates: "your companion" and "your summoner" as roles (Beastheart, Summoner), and "the path passes
within [N] squares of you".

Also: a damage step's "that can't be reduced" phrase shows only when set or while editing, and older steps
without a "who" default to "to the target".

## 4s. The scope line: when to say "use the full editor" (proposed, 2026-11-22)

The simple editor never refuses content: unmodelled parts open as Advanced steps or formula blocks, save
back untouched, and have "Edit in full editor". The standard is about two other decisions.

**When something gets a sentence block** (all three):
1. It appears 20 or more times in content.
2. It is one idea a non-programmer can read as one sentence.
3. It round-trips: opening and saving untouched gives back the original.
Under that rule the next blocks are Modify Power Roll (130), Summon (122), Remove Creature (120), Augmented
Ability (116), Float Text (81), Custom Trigger (62), Destroy (47), Delay (43), Manipulate Targets (30),
Terraform Elevation (25), Remember (24); in conditions, "your companion" / "your summoner" (~45). Lua Script
(26) and Macro never get blocks: code belongs in the full editor. The other 67 step types (318 uses) stay
Advanced.

**When the editor suggests the full editor for the whole ability** (any one; it still opens):
- more than half its steps are Advanced (or words the blocks can't read yet);
- it runs a script or macro;
- follow-up abilities nest more than two deep;
- one condition has three or more parts written as formulas.
Shown as a banner above the header: "Most of this trigger is easier to edit in the full editor", the
reasons, "You can still edit it here: the marked parts are kept exactly as they are when you save", and
"Open in full editor" / "Keep editing here". Advanced steps get a dashed outline.

Today: 56 of 88 sampled abilities open fully as blocks and 5 would show the banner; 605 of 1,132 triggers
open fully as blocks and 278 would show it (mostly monster triggers built from Remove Creature, Float Text
and standard-ability calls, which the next blocks address). Example in the prototype: the Tactician's
*Mark: Benefit* trigger (4 of 6 steps Advanced).

Also from that example: saved wording can contain the engine's interpolation `{2*Reason|double your Reason
score}` and inline " - " bullets. The card now shows the words half (as the engine does without a creature)
and the bullets as a list, without changing what is saved.

**Correction after review (2026-11-22).** Mark: Benefit was flagged for things that are ordinary blocks, and
the fix moved the numbers a lot:
- **Using a standard ability** ("Prompt Spend Recovery", "Shift", "Free Strike"...) is "Use another ability"
  with the ability picked from the standard abilities list (saved by id, with its parameters). It had been
  Advanced only to avoid resaving it as a custom ability.
- **Rule text** (`DrawSteelCommand`) reads like tier text: a formula amount in braces (`{2*Reason} damage`),
  damage "(added)" to the hit that set off the trigger (it joins that damage instance, so immunity isn't applied twice), and several results in one rule ("push 2; prone" shows as results
  that happen together) open as blocks and save back as the same one rule.
- **Float Text** is a Display block: "Show [TAUNTED!] over [the triggering creature]". It changes nothing on
  the card.
- A trigger's condition is now read against its own event when it opens (it was read against the previous
  ability's), so Mark's reads "the damage came from an ability and the ability deals damage".

Updated counts: abilities that open fully as blocks 56 to **69 of 88**, banner **1**; triggers 605 to **823 of
1,132**, banner 278 to **72**. Everything still saves back identical (45/45, 60/60, 1,148/1,148). What still
makes triggers Advanced: Remove Creature 90, Loyalty Collar Explosion 40, Summon 33, Augmented Ability 32,
Aura 31 (the Aura block exists, but opening a saved aura into it isn't built yet), Destroy 14.

## 4t. Damage as rule text, and tiers that hold their own steps ("#") (2026-11-22)

**New damage saves as rule text by default**, like conditions and forced movement ("5 fire damage"), and
switches to the Damage behaviour only when it needs it: dice the player rolls (the behaviour opens the roll
dialog), damage to you, or "can't be reduced in any way" (rule text's "ignores immunity" is a different
rule). Separate rolls per target and "only on some tiers" are the other behaviour-only options (31 and 21
uses). Opened content keeps what it was saved as. In content today: 589 Damage behaviours (100 with dice,
60 not at the target, 51 can't be reduced, 368 with a custom chat line) against 182 damage rules. Engine
checks before adopting, listed for the handoff: rule-text damage fires "deals damage" and damage bonuses
the same way; Monster AI scores it; chat and log lines read the same (`ExecuteDamage` suggests both go
through the same damage call).

**"#" in tiers: steps that only run on one tier.** Content's pattern (62 abilities use "#", 39 of them with
tier-only steps): the tier text after "#" is card wording the rule reader skips, and separate steps with
`tiersSelected: [n]` and an "Only if" do the work, e.g. "if the target is already slowed, they are
restrained instead" (*It Is Justice You Fear*: frightened, or psychic damage if already frightened). In the
editor:
- **An "Only if" (or any other step) can go inside a tier.** It is tagged "this tier only". On save it
  becomes its own step with `tiersSelected` for that tier, after the power roll.
- **The tier's card words** come from a "Card text" block in the tier, saved after "#". With no Card text
  block, the editor writes the steps' own wording there.
- **Opening content puts tier-only steps back inside their tier**, with their "Only if" wrappers; steps for
  several tiers stay where they are. Saved order is kept.
- The card shows the "#" words without the "#", with potency boxes ("M<WEAK").
Examples: *Frostbind* (new, built the way an author would) and *It Is Justice You Fear* (opened from the
compendium; saves back identical).

Found while building it: restoring an unchanged power roll swallowed the tier steps compiled right after it.
They are now added after the power roll's own record is settled. All 1,253 opened abilities and triggers
still save back identical.

**Card-and-steps agreement checks (2026-11-22).** A user rebuilt *It Is Justice You Fear* as a 3-cost copy and
made two easy slips when duplicating an "Only if": the "not frightened" branch dealt psychic damage instead of
making the target frightened, and every potency check used Might while the card said P < WEAK. The editor
now checks each tier whose card words come from a Card text block:
- the card names a condition with a duration ("frightened (save ends)") that nothing on that tier applies
  (conditions, effects whose name includes it, and rule text kept as written all count);
- the card's potency letter (P < WEAK) differs from the characteristic an "Only if" on that tier checks.
These show as "Ready to save, but N things look worth checking" with the list in amber: they never block
saving. Results: the user's copy gets all six flags; the original, Frostbind and the other examples none;
across all 62 content abilities that use "#", none (after counting effect names and kept rule text, which
removed 5 false alarms); all polls still save identically. The one content ability already blocked by an
older check is *Mind Twist* (a potency check with an unquoted letter, a real content bug).
Also: the prototype's own saved data (with "<Main action>" style placeholders) reopens with its action and
cost, and steps shown inside their tier no longer appear in "kept as they are".

## 4u. Pasting Steel Compendium markdown (2026-11-22)

Asked for: paste an ability's markdown page from the Steel Compendium (steelcompendium.io) and get blocks.
The reader now turns markdown into the plain lines it already understands before reading:
- links keep their words ("[frightened](https://...)" reads "frightened");
- the keyword/action table and the distance/target table become plain header lines, separator rows dropped;
- "- **12-16:** ..." becomes a tier line, "**Effect:** ..." an Effect paragraph, "## Name (5 Wrath)" the header;
- an italic first line is the flavor. That page has no name above it, so the ability is called
  "Pasted ability" and the toast says to rename it.

**"If the target is already X, they instead Y."** The page's effect is the "#" pattern from 4t, so the
reader now builds it: for each tier whose potency applies X, the tier keeps its words for the card
("P < WEAK, frightened (save ends)"), and two tier-only "Only if" steps do the work: below potency and not
already X: X; below potency and already X: Y. Y can be damage equal to (twice) a characteristic, a flat
damage amount, or a condition with a duration. The pasted page saves with the same structure as the
compendium's own *It Is Justice You Fear* (tier text after "#", three condition steps, three damage steps)
and no agreement checks fire.

**Pasted paragraphs are the saved description.** Each pasted Effect paragraph is now a card paragraph
saved to `description` (book first), not proposed override text. That also fixed a card bug: a paragraph
whose blocks all sit inside tiers (nothing generated at the top level) was missing from the card.

The same sentence in *Instant Cement* ("If the enemy is already slowed, they are instead restrained") is
left to build: it belongs to an area that reacts to a creature ending its turn there, which needs engine
work first (4l). Paste tests, the agreement checks, and all three open-and-save polls are unchanged
(45/45, 60/60, 1,148/1,148).

## 4v. Bulk paste test: every Steel Compendium class and kit ability (2026-11-22)

The Steel Compendium site is blocked from the test machine, but its markdown is published in the
SteelCompendium/data-md repository, which is readable. All 545 class, kit and common-action pages
(`Rules/Abilities`) were pasted into the reader; 472 match an ability in our data by name (the rest are
mostly triggers, which our data stores as modifiers, and the common actions). Scripts:
`ui-mockup/ability-blocks-corpus/poll4/` (the markdown and full results stay out of git; counts are in
`paste4-summary.json`).

Reader fixes the run found (before -> after, of 472 compared with our data):
- **Tables are read cell by cell.** Distance and target come straight from the table, so any target wording
  works ("Self and each ally", "Two creatures or objects"); the closest target pick does the work and the
  book's words stay on the card. Range 322 -> 420, target type 374 -> 402.
- **An ability with no keywords** ("| - | Maneuver |") now reads its action. Action 450 -> 457.
- **Kit rolls and damage:** "Power Roll + Might, Reason, Intuition, or Presence" and "5 + M or A damage"
  build (a damage block that keeps the book's letters). Roll 440 -> 462, tiers 394 -> 411 (the remaining tier
  differences are mostly the same words: "can't" / "cannot", "you can swap" / "you swap").
- **A page's YAML header** is skipped, and a second heading (a summoned creature's stat block) ends the read.

Results: every tier result builds on 479 of 545 pages; 1,856 blocks built. **52 pages build completely.**
What's left is effect sentences (1,095) and a few tier results (200). The effect sentences group as:

| Group | Count | Example |
|---|---|---|
| Other / clarifications (no blocks needed, card text) | 362 | "You still use the same power roll for both targets." |
| A duration around an effect ("Until the end of ...") | 160 | "Until the end of the target's next turn, they have damage weakness ..." |
| Surges, temporary Stamina, Recoveries, resources | 121 | "Each target gains 3 surges." |
| Movement ("You can shift ...", "You teleport the target ...") | 96 | "You can shift into any square the target leaves after you push them." |
| Extra targets, extra damage to a second creature | 80 | "One creature of your choice within 2 squares of the target takes fire damage ..." |
| Areas that act ("Each ally in the area ...") | 77 | "Each ally in the area can spend a Recovery." |
| Conditions written as sentences | 72 | "The target is taunted until the end of their next turn." |
| Edges, banes, extra damage, weakness | 64 | "The target takes a bane on their next power roll." |
| If / when / the first time | 63 | "The first time the target is winded before the end of the encounter, ..." |

Remaining tier results: vertical pull (18), teleport (8), temporary Stamina (9), "The Director loses N Malice"
(9), a bane on the next roll, weakness N (save ends).

Header differences that are not reader errors: our data adds a "Kit" keyword the book doesn't print (19),
and stores aura and "Self and each ally" abilities with other target types.

**Second pass: durations, resources and conditions as sentences (2026-11-22).** Asked for: build the three
biggest groups and re-run. The reader now reads an effect sentence as "who + what they get":
- **Durations.** "Until the end of the encounter (or until you are dying) / the start of your next turn /
  the end of the target's next turn, <...>" gives the subject an effect with that duration (`eoe`,
  `eoe_or_dying`, 1 round, `end_of_next_turn`). When the compendium already has an effect named after the
  ability, that effect is used (50 of 64); otherwise it's a **new effect** named after the ability whose
  rules are the sentence, flagged "worth checking" (never blocking): it shows on the creature but doesn't
  automate until built in the effect editor (the modifier editor proposal).
- **Resources.** "gains N surges", "gains N temporary Stamina" (or "equal to (twice) your Presence"), "can
  spend a / N / any number of Recoveries" (the standard "May Spend Recovery" ability, as content uses it),
  with several joined by "and" ("gains 20 temporary Stamina and 3 surges").
- **Conditions as sentences.** "You are weakened and slowed (save ends)", "The target is taunted until the
  end of their next turn" (the condition block gained "you or the target"), and "If the target has
  R < AVERAGE, they are slowed (EoT)" (an "Only if" with the potency test).
- **Paragraph labels.** Only "Effect" paragraphs always happen. "Strained:" steps go inside "Only if you
  are Strained" (they used to run every time); "Persistent N:" is one item for the full editor;
  "Trigger:" and "Special:" are card words.

Re-run of all 545 pages (same counting as before): sentences starting "Until ..." left 102 -> 4; resource
sentences 113 -> 91; condition sentences 61 -> 50. Effect sentences left 1,095 -> 943; blocks built
1,856 -> 1,986; **fully built 52 -> 84**; the kinds of steps match our content on 86 -> 135 of 472
(*Exothermic Shield* now comes out with content's own effect, duration and Strained steps). The resource
and condition sentences still left mostly name someone the blocks can't pick ("one ally within distance",
"you and each ally within 3 squares of you") or sit behind a condition ("If this damage kills the
target, ..."). Paste tests and all three open-and-save polls unchanged (45/45, 60/60, 1,148/1,148).

**A different creature is a new ability (2026-11-22).** User rule: an ability that hits one creature and
then has an entirely different creature do something is an invoked ability, so the reader builds "Use a
new ability" with its own targets, as content does:
- "One ally within distance gains ..." -> used by you, prompted, range = the ability's distance;
- "A creature of your choice within 2 squares of the target takes ..." / "One ally adjacent to the target
  can spend a Recovery" -> used from the target (`applyto: first_target`), range 2 / 1.
"1 ally" / "1 enemy" write the target filter themselves (`Friends(Invoker, Target) and Invoker != Target`,
compared with you so it still means your allies when the target uses it). Inside, the sentence's results
build as usual, plus damage ("takes 5 fire damage", "equal to twice your Reason score", kits' "equal to the
characteristic score used for this ability's power roll" -> `Max(...)` of the roll's characteristics) and
"a number of surges equal to the tier outcome" (the tier result, passed to it). Any parent value a step
inside mentions is now passed automatically. *Blessed Light*, *Exploding Arrow*, *Leaping Lightning* and
*Gasping in Pain* come out with content's structure. Only 24 leftover sentences name another creature this
way; of the rest, most need an edge or bane on a later roll. Re-run: fully built 84 -> 90, kinds of steps
matching content 135 -> 141.

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
| 2026-11-21 | **Design value: minimise clicks.** Every flow is judged by clicks and decisions for the common case; defaults and focus should carry the author to the next likely action. | Set by the design lead after critique round 1. |
| 2026-11-21 | **Insertion points replace the "selected list".** A "+" between steps and at every list end opens a type-ahead of only the steps allowed there (Enter adds the first match). A gold "next block goes here" marker shows where palette clicks land; it moves inside a wrapper as soon as one is added, and after a new step otherwise. The shelf names the marker's place. | Fixes critique problem 1 (wrong nesting) and gives keyboard and phone a full path. |
| 2026-11-21 | **Read mode.** Steps and header blocks read as sentences with underlined words; clicking a word opens only that block for editing with that control focused (dropdowns open directly). Done, Esc, Enter or clicking elsewhere returns to reading. Neutral values (untyped, no cost) read faintly; tier damage reads "3 + M". | Fixes noise and the long potency block (problems 3 and 9) without hiding any setting. |
| 2026-11-21 | **Fewer clicks:** starters (Strike, Ranged strike, Area attack, Heal an ally; for triggers Reduce damage, Strike back, Start of turn) fill a blank ability in one click; a new step opens with its first value focused; Enter commits. Measured: the critique's strike task went from about 18 clicks to 6 clicks plus typing. | Design value above. |
| 2026-11-21 | **Potency vocabulary is the card's:** "Potency (M < average)" in the shelf, "If M < average potency:" in tiers, "M < strong" for tests (with incl./excl. power roll modifiers), one colour throughout. | Critique problem 2. |
| 2026-11-21 | **Smaller fixes from the critique:** power roll shown as a tier table; undo (Ctrl+Z and button) plus toasts with Undo after deletes; a toast when a triggered ability's timing flips; pickers flip upward; most-used conditions first; actions use verbs ("Make the target slowed"); status text no longer says "ordinary ability"; shelf after the stack in tab order and collapsed on phones. | Critique problems 4-8. |
| 2026-11-21 | **Shelf always right of the stack**, at every width; on narrower windows the card moves below instead. **Phone layouts are out of scope.** The thin "+" between steps is discoverable enough as is. | Design lead's call after hands-on use. |
| 2026-11-21 | **Clicking one word edits just that value:** choosing a value (dropdown, picker option or typed formula) returns the step to reading automatically. A brand-new step stays open so its values can be typed in a row. | One click fewer per edit (design value: minimise clicks). |
| 2026-11-21 | **One sentence pattern for abilities and triggered abilities:** "[Name] is a [Main action / Triggered action ...]", "which costs [nothing / 3 Heroic Resource]", "and has the keywords [chips]". | Consistent language across both kinds. |
| 2026-11-21 | **Keywords are never typed.** Chips from the registered ability keyword list (`GameSystem.RegisterAbilityKeyword`, see KEYWORDS.md); add by clicking or dragging a chip from the Keywords group at the bottom of the shelf, or "+ keyword" with type-ahead; remove with x. | Free text produced keywords the engine does not know. |
| 2026-11-21 | **The card is generated, with per-line overrides (exploring).** The editor writes the rules text (flavor, distance, target, each tier, trigger, effect) from the blocks; clicking a line rewords it. An override stores the generated text it replaced; if the rules change later the line is flagged "rules changed" with "Use new wording". For triggered abilities this replaces the separate Triggered Ability Display. | The display is a second record kept in sync by hand and found by name; authors still need to adjust wording the way the book prints it. |
| 2026-11-21 | **Effect text is one paragraph per position:** an Effect paragraph before the power roll and one after it. Paragraph labels ("Effect", "Trigger") can be renamed by clicking them, e.g. to "Strained" (suggestions offered). Saved with the overrides as `<line>.label`. | Most effects are one paragraph; some cards label them Strained or similar, and some put effect text before the roll. |
| 2026-11-21 | **Deferred: players rewording the cards of their own characters' abilities.** Revisit after the authoring design settles. | Wanted, but a separate question (whose override wins, per character storage). |
| 2026-11-21 | **Shelf order follows usage.** Power roll first (with Potency inside it, since potency only gates tier results); then groups by total use in the compendium (Harm, Hinder, Other abilities, Effects, Logic, Help, Summon and create, Resources, Move, Show and tell, Other rolls and tests, Scripting); blocks inside each group by use. The "+" type-ahead uses the same order. | Most-used first is fewer clicks and less scanning. |
| 2026-11-21 | **Every registered behaviour has a block** (83 more, from `ActivatedAbility.RegisterType`, minus the five Draw Steel suppresses and Debug). Those without a sentence yet show their name and a Settings button for their own settings panel. Each group shows its four most-used blocks with "Show N more"; a shelf search finds any block; usage counts are shown on the less common ones. | See the full vocabulary in place; nothing needs the full editor just to be added. |
| 2026-11-21 | **Keywords in the shelf only while editing keywords, at the top.** Clicking the keywords line or "+ keyword" opens "editing keywords" (gold outline, Done); the shelf then shows the keyword chips first. Clicking anywhere else closes it. | Keywords are set once; they should not push the step blocks down the rest of the time. |
| 2026-11-21 | **Condensed shelf (critique round 2).** Search pinned at the top; **Common**: the 16 most-used blocks (about 93% of all uses in content) in group order; then **every category as one compact row** (colour, name, count) in two columns, one opening at a time in place with all its blocks by use. Inside a power-roll tier, Common shows only the blocks a tier accepts, headed "Adding to tier N", and folds the rest. The shelf fits one screen at 1000px (was 2.6 screens). Short category names (Abilities, Create, Tests, Display, Scripts). | Hodent critique: fixed per-group quotas spent the first screen on rare blocks; the shelf ignored the marker; too long. |
| 2026-11-21 | **One search for the shelf and the "+" list:** ranks name-starts, word-starts, name-contains, synonyms (push, wait, teleport...), then description; ties by usage. Enter adds the highlighted result at the marker; Esc clears; it clears itself after adding; "/" jumps to it. | The two searches disagreed and Enter could add the wrong block. |
| 2026-11-21 | **The marker advances through the power roll:** after a result is added to a tier, the next empty tier becomes the place for the next block. The shelf stays beside the stack (sticky) at narrower widths, with the card below the stack only. | Two clicks fewer per strike; no scrolling away from the stack. |
| 2026-11-21 | **A "+" only moves the gold marker; the shelf is the one place to choose.** The separate type-ahead popup is gone. Clicking a "+" moves the marker, the shelf briefly glows and re-fits itself to that spot, and the cursor goes to the shelf search, so typing and Enter still add a block without the mouse. | Two places that change at once was redundant; one source of choices is simpler. |
| 2026-11-21 | **"Move a creature" exposes Relocate Creature's targeting options as words:** how far (a square you pick / up to your speed), path (any / straight line), through enemies' spaces, "-> targets each enemy whose space it moves through / it moves next to" (Target Creatures in Move Vicinity: vicinity 0 or 1 plus filter), and "marks the squares it passes" (Target Passed Squares). **Create Aura** is a sentence block: "Leave [name] on the squares the move passed / on the target area / around you". | A real author request (Raise Hell) needed exactly these two checkboxes, which were hard to find. |
| 2026-11-21 | **Create Aura holds its own effect.** A container block: "Leave [Hellfire] on [the squares the move passed] - affects [enemies] [normal / difficult terrain]", then "When a creature enters it:", "When a creature starts its turn in it:" (and the other aura trigger conditions via "+ when...") sections of ordinary steps. Saves as `aura.applyto`, `difficult_terrain` and `aura.triggers = [{trigger, ability: TriggeredAbility{behaviors}}]`, the shape content uses (e.g. Radiant Field). An aura that does nothing is flagged. | "Burning with hellfire" is an aura effect; the aura's behaviour belongs inside the aura, authored with the same blocks. |
| 2026-11-21 | **Paste ability text is an option on the start row and in the header.** It reuses the statblock importer's parsing (header, tiers, effect templates). Read text becomes blocks, the wording becomes the card text, and each unread sentence becomes a "To build" block with "Save as pattern" to teach the importer. | Most abilities are copied from a printed card; building from the text is fewer clicks, and every hand-built sentence teaches the next paste. |
| 2026-11-21 | **Costs use the class's resource name when the ability belongs to a class** ("which costs 5 Insight" on a Shadow ability; the card says the same). It is only wording: the save still points at the Heroic Resource. Pasted text that names a class resource picks the class. Hellfire's own effect is out of scope for the Raise Hell test. | Authors and players think in Insight, Wrath and Piety, not "Heroic Resource". |
| 2026-11-21 | **"Who it targets" stays as the author set it when a block (e.g. Move a creature) picks the targets.** No "set by..." wording. | Abilities with unusual targeting are already labeled Special targeting on the card, so authors expect the row to differ from what the blocks do. |
| 2026-11-21 | **Pasting tolerates lost icons and marks guesses.** Bare tier lines are read in order; a potency lost with its icon is guessed (roll characteristic, weak/average/strong by tier) and marked "check"; unknown resource words (third-party) stay on the card. | Real copies from PDFs and third-party books drop the icons that carry meaning; a marked guess is fewer clicks than a blank. |
| 2026-11-21 | **"Who it targets" uses the card's own wording, as two lines: "Distance: [4] cube within [10]" and "Target: each enemy in the area".** Each form puts its numbers where the card does: Melee N, Ranged N, Melee N or ranged M, N burst, N cube within M, L x W line within D, Self. Area forms only offer "each ... in the area" (and Special) as targets. A plain-words line underneath explains it ("A cube 4 squares on each side, placed anywhere within 10 squares of you."). Saved the way the statblock importer saves them: burst = targetType all with range = size; cube = radius size, range within; line = range length, radius width, lineDistance; melee or ranged = meleeRange. The card shows "One creature", not "1 creature". | The old row ("1 each enemy in the area within Cube 4") didn't match how the book says it and lost the cube's "within" distance. |
| 2026-11-21 | **Class ability poll (55 random abilities, all classes, levels 1-10).** 15 map to blocks fully. The gaps, by count: nested abilities 14, modes 12 (not modelled), advanced behaviours 12, distance as text 11, unreadable tier text 11, unknown symbols 9. Book PDF paste: 3 of 33 clean, because of icon letters (a/e/i, o/x, m<w), split action lines and broken word wraps. | Evidence for what to build next: modes, the aura distance form, tier grammar additions, and copy-format rules. |
| 2026-11-21 | **Modes are a block: "When you use it, choose one".** Options have a name and an optional extra cost; steps inside an option save with modesSelected; extra cost adds the condition and the spend step. Tier grammar gains riders, no-duration conditions, vertical push straight up, surges, card-text-only results, and the N aura distance. Ability Duration Effect and Condition Riders get sentence blocks. | Poll items 1, 3 and 4: modes were the largest gap, and tier text was the most common reason a pasted ability failed. |
| 2026-11-21 | **Modes vs Ability Variations is decided by the editor.** Each option is "same targets" or "targets differently"; any option that targets differently makes the block save as Ability Variations, with that option as a swapped-in ability (its own targeting, the full step list with only its steps from the block, cost kept from the base). Otherwise it saves as Multiple Modes. | Same principle as triggers: authors describe what happens, the editor picks the storage type. |
| 2026-11-21 | **The card preview (tooltip) is styled after the printed card.** Name with cost in brackets ("It Is Justice You Fear (5 Wrath)"); a ruled left edge with diamond marks; italic flavor over a rule; keywords left and action right in bold ("Triggered" for triggers); distance and target with the book's icons; tier badges; characteristics and potencies as black boxes ("8 + [M]", "[P<WEAK], frightened"). Triggers show a distance and target line too ("Ranged 10 / Self or one ally"). Saved potency tier text now has the comma content uses ("P<weak, frightened"). | Asked for: the tooltip should look like the book. |
| 2026-11-21 | **Opening existing content: anything unchanged saves back exactly as it was.** Steps, tiers, formulas and fields that compile to what they compiled to at open keep their saved form; changed steps write over the original record so hidden fields survive; unread words are kept, never dropped. On 45 real class abilities: untouched saves identical 45/45, single-tier edits touch only that tier 18/18. | Ship-safety: the simple editor will mostly be used on existing content, and must never damage what it doesn't understand. |
| 2026-11-21 | **Opened abilities show their saved description as the effect text; Strained is a visible container; damage says who takes it.** Description edits save to `description`; "If you are Strained" saves `strainSelection`; damage gets "to you" and "that can't be reduced". | Review of Optic Blast: the card rewrote existing wording, and Strained and self-damage were invisible. |
| 2026-11-21 | **Book first for the card.** The card always follows how the book displays an ability; saved book wording (description, mode rules, flavor, distance and target text) wins over generated text, and generated text uses the book's phrasing. Filters and requirements move off the card. **Strained is a test inside Only if** ("You are Strained"), saved as `strainSelection`, labelled "Strained:" on the card. | Asked for: "always preference the way the book displays it", and one place for conditions. |
| 2026-11-21 | **Second poll (60: monsters, new class abilities, triggers) passes open-and-save 60/60.** Triggers now open (and the power roll trigger condition field is fixed to `targetFilter`); monster power rolls, villain actions, saved step order in modes, and text-only abilities are handled. The book check shows the remaining card differences come from data that doesn't store the printed wording, mainly monsters: the importer should store distance, target, trigger and effect text verbatim. | Evidence for shipping the editor on existing content, and a concrete content/import task for book-first monster cards. |
| 2026-11-21 | **Triggers: display toggle, display wording as the card, "+ Add paragraph", and all 1,148 triggers open and save identically (trigger and display).** Toggle defaults by action and opens from whether a display exists; display text is the card and edits save to it; added paragraphs are card text that saves to description / the display. Variations corrected to hold only the option's steps. | Asked for (toggle, paragraphs, trigger poll). Next: trigger conditions read as blocks only 46 of 571 times. |
| 2026-11-22 | **Trigger conditions use each event's own symbols** (from the engine's trigger definitions): event creatures become roles, yes/no values become tests, an "About this event" picker group, and readings for attacker, distance, allies, damage type lists, condition / trigger / effect names, keywords, effects, path and free strike. Conditions as blocks: 46 to 346 of 571; all triggers still save identically. | The hardest GoblinScript for trigger authors; follows "minimise clicks" and book-like wording. |
| 2026-11-22 | **Proposed scope line.** A pattern gets a block when it is used 20+ times, reads as one sentence, and round-trips; scripts never do. The editor suggests the full editor (banner, never a refusal) when more than half the steps are Advanced, there is a script, follow-ups nest more than two deep, or a condition has 3+ formula parts. | Asked for: a standard for when to say "use the old editor". Cutoffs to confirm. |
| 2026-11-22 | **Standard abilities, rule text and Float Text are blocks, not Advanced.** "Use another ability" picks standard abilities by name (saved by id); rule text opens like tier text (formula amounts, "(added)", several results); Float Text is a Display block. Triggers fully as blocks 605 to 823 of 1,132; banner cases 278 to 72. | Review of the Mark: Benefit example: these are everyday steps, not advanced ones. |
| 2026-11-22 | **New damage saves as rule text unless it needs the Damage behaviour** (dice, to you, can't be reduced). **Tiers can hold steps** ("Only if the target is already slowed: restrained"): saved as tier-only steps (`tiersSelected`) with the tier's card words after "#"; opening content puts them back in their tier. | Asked for: default to command text; and the "#" pattern for effects the tier text can't express. |
| 2026-11-22 | **Tier agreement checks:** a condition on the card that no step on the tier applies, or a potency letter that differs from the "Only if" check, shows as "worth checking" (never blocks saving). | A real rebuild slipped on both; no false alarms across the 62 "#" abilities in content. |
| 2026-11-22 | **Steel Compendium markdown pastes; "already X, instead Y" builds tier-only steps; pasted paragraphs save to `description`.** An unnamed page is called "Pasted ability". | Asked for: make the compendium's markdown work for pasting; the pattern matches the user's rebuild of *It Is Justice You Fear*. |
| 2026-11-22 | **Bulk paste test on all 545 Steel Compendium class and kit pages.** Tables read by cell (any target wording), kit rolls and "M or A" damage, keyword-less actions. Every tier result builds on 479; 52 build completely; 1,095 effect sentences left, grouped (durations 160, resources 121, movement 96, ...). | Asked for: check pasting at scale; evidence for which sentence patterns to add next. |
| 2026-11-22 | **Effect sentences read as "who + what they get":** durations make an effect on the subject (the ability's existing effect, or a new one whose rules are card text until built); surges, temporary Stamina, Recoveries; conditions as sentences, on you or the target, behind a potency test. "Strained:" paragraphs go inside "Only if you are Strained". Fully built 52 -> 84 of 545. | Asked for: the three biggest groups from the bulk test. |
| 2026-11-22 | **A different creature doing something is "Use a new ability"** (its own targets: from you within distance, or from the target within N squares), with ally/enemy written as the filter and parent values passed automatically. | User rule: hitting one creature and then targeting an entirely different one is an invoked ability. |

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

## 4w. Remember a value (2026-11-23)

A reviewer asked for an easy way to use the engine's **Remember** behaviour. Remember notes a number
partway through an ability, and a later formula reads it back with `Cast.Memory("name")`. Before
this change it was a generic block with raw fields, and reading the value back meant typing the
formula by hand.

- **The step:** "Remember a value" is in the Logic group. It reads **Remember [value] as [name]
  [for each target, added up | for you]**. Its value picker starts with "Common things to
  remember":
  - the damage dealt so far (`Cast.DamageDealt`)
  - the squares moved so far (`Cast.SpacesMoved`)
  - the number of targets (`Cast.TargetCount`)
  - the target's Stamina, or your own
- **Reading it back:** every formula and test picker in the ability now starts with
  **Remembered values**. It lists each name a Remember step uses: a number shows as a
  "remembered damage before" chip, and a test as "The remembered [name] is at least [ ]". When
  nothing is remembered yet, the group says how to add one. On a card the chip reads "the
  remembered damage before"; it saves as `Cast.Memory("damage before")`.
- **Checks:**
  - a Remember step with no name;
  - two steps remembering the same name (soft, because the later one wins);
  - a chip naming something no step remembers.
- **Round trip:** all 23 abilities in draw-steel-data that use Remember (monsters, Fury, Shadow,
  Beastheart, Summoner, Duelist, Vanguard, Caustic Alchemy, the standard Slide) open with a real
  Remember step and save back identical. 13 of them show their memory reads and Cast values as
  chips; the rest read them inside rule text or a follow-up's parameters. Poll 1 (45/45) and
  poll 2 (60/60) are unchanged.
- **Limit:** a memory belongs to one use of one ability. A follow-up made with "Use a new ability"
  has its own memory, so to hand it a value, pass it from the parent as before.

## 4x. Hover text for every shelf block (2026-11-23)

The engine's own 78 behaviours have no ready-made block. Their hover text used to be only "Used N
times in the compendium". Each one now has a plain description, written from its Lua `Cast` and
editor fields and checked against real uses in draw-steel-data, plus a "Note:" line when there is
something to watch out for. The hand-built blocks' hover text was tightened at the same time
(Deal damage, Apply condition, Use a new ability, Use another ability, Temporary Stamina, Logic,
Remember a value).

**Findings worth acting on:**
- **Internal or one-off blocks:** these are on the shelf but are not for general use:
  - Loyalty Collar Explosion (war dogs)
  - Patron (the Acolyte's Patron's Gaze)
  - Shift Wall Voxel (the Wallmaster)
  - Create Lane Object (the Time Raider Helix)
  - Apply Flagged Power Modifiers (added to free strikes automatically)
  - Persistence Control (the Elementalist)
  - Routine Control (the Troubadour)

  They could be hidden behind an "Advanced" toggle.
- **Developer-only:** Lua Script, Macro Execution, Reset Roll Status and Pay Ability Cost.
- **Older systems:** these use the old pop-up roll dialog: Roll Dice, Skill Check and Create Item.
  Summon Companion appears to predate the Beastheart's Call Companion.
- **Looks unfinished:** in Discard Items, the default "Items in Hand" does nothing and "Named
  Items" isn't implemented.
- **Bad defaults:** Summon Creatures and Transform Creatures default their bestiary filter to
  another game's terms ("cr = 1 and type is beast").
- **Engine text is wrong:** the in-app block picker (`Draw Steel Ability Editor/AbilityEditorBehaviorPicker.lua`)
  describes Draw Steel Save as "Force a target to make a resistance roll". It actually makes
  saving throws against save-ends effects. (Recorded only; the codebase is not changed.)

**Revision (same day):** the hover text is now only what the block does. "Used by..." examples
and the notes stay in the table below for developers, but are not shown on the shelf. One-off
blocks moved to a new **Unique** group at the end of the shelf (`UNIQUE_BEHAVIORS`):
- Loyalty Collar Explosion
- Patron
- Shift Wall Voxel
- Create Lane Object
- Persistence Control
- Routine Control
- Apply Flagged Power Modifiers (Free Strike)
- Swing Object
- Recovery Selection

The shelf groups in the table are from before this move.

| Shelf group | Block | Hover text | Note |
|---|---|---|---|
| roll | Apply Flagged Power Modifiers (Free Strike) | Applies any of the striker's power roll bonuses that are marked "apply to free strikes" to a free strike's targets, since free strikes don't go through the normal power roll. | Codex-internal: added to free strikes automatically and hidden from the normal block picker. Designers shouldn't add it by hand. |
| roll | Modify Power Roll | Adds a modifier to this ability's own power roll, such as an edge, extra damage or a rider. Whoever rolls can take it as an option in the roll dialog. Used by options like "Blood for Blood!". | Does nothing alone. It needs a Power Roll block in the same ability. |
| harm | Chain To Nearby Enemies | Spreads the ability from its first target to every enemy within a set number of squares, then from each of those, until nobody new is in reach. The power roll after it hits every creature the chain reached. Used by the Shadow's "Chain Reaction". | Walls and creatures that block line of effect stop a jump. |
| harm | Destroy | Kills the targets outright, whatever their Stamina, without setting off damage triggers. Used when a war dog's loyalty collar goes off. |  |
| harm | Loyalty Collar Explosion | Blows up the caster's war dog loyalty collar for everyone at the table: explosion effect and sound, the creature hidden in the blast, scorch marks on the floor. | Codex-internal, for war dogs only. Visual and sound only: deals no damage and does not kill. Pair it with Destroy or Remove Creature. |
| harm | Remove Creature | Takes the targets off the map without dealing damage, optionally leaving a corpse and dropping their treasure. By default it waits for other abilities, and optionally triggers, to finish first. Used by the war dogs' Loyalty Collar. | Heroes are hidden rather than deleted. If a removed creature was taking its turn, the turn ends. |
| hinder | Forced Movement Origin | Picks the point that later push and pull blocks measure from: the centre of an aura or area, a creature the user chooses, or the first target. Used by Gravitic Well's "pull toward the center of the area". | Moves nothing itself. Put it before the push/pull. |
| hinder | Taunt By Nearest | Makes each target taunted by whichever creature or attackable object is nearest to it, and can apply an extra effect on chosen tiers. Used by the Wyvern malice feature "Overflowing Rage". | "Nearest" can be anyone, including the target's own allies. |
| effect | Confer Conditions | Copies conditions from a source creature (the user by default) onto the targets, keeping their duration and who caused them: all of them, or ones the player picks. The source keeps its conditions. | Copies conditions only, not other ongoing effects. Not used by any content yet. |
| effect | Limit Active Effects | Caps how many creatures can carry one of the user's ongoing effects, removing it from the oldest ones to make room for the new targets. Place it before the block that applies the effect. Used by the Shadow's "Careful Observation" (one observed creature, rising with level). |  |
| effect | Save Ends To End Of Turn | Lets the player pick a "save ends" condition or effect on each target and change it to end at the end of the turn instead. Used by the High Elves' Otherworldly Grace. | Can be set to allow picking several effects at once. |
| effect | Set Source of Condition | Changes who a condition is tied to, so a creature becomes frightened of or taunted by the target instead of the original user. It works on conditions this ability just inflicted or on the user's own conditions; used by the Conduit's "Select Source of Fear" and the Shadow's Misdirecting Strike. | Only conditions that track their source (frightened, taunted, grabbed and similar) can be picked. |
| ctrl | Creature List | Adds a creature to a named list kept on the target, which empties on a chosen schedule (each turn, encounter and so on), so you can count different creatures. Used by the Troubadour's Drama trigger "three or more heroes use an ability on the same turn". | Only useful when other blocks or formulas read the list size. |
| ctrl | Delay | Pauses the ability for a number of seconds (60 at most) before the next block. It can also wait until a condition becomes true. Mostly used to time effects and deaths, e.g. during the Gnoll Carnage's transformation. | Waiting on a condition gives up after 120 seconds and carries on anyway. |
| ctrl | Fizzle | Takes the targets that pass its filter out of the rest of the ability, so later blocks skip them. If it applies to every target, it removes them all. Used by the Censor's Behold the Face of Justice! to drop targets who resist the potency. |  |
| ctrl | Limit Ability Uses | Lets the rest of this ability work only once per chosen period (encounter, round, turn, etc.). Later uses in that period stop at this block. Used by the Fury and several subclass "once per encounter" features. | The ability can still be started again; only the blocks after this one are skipped. Give two abilities the same Unique ID to share one limit. |
| ctrl | Manipulate Target Locations | Moves the ability's targeted squares one floor down or up. Targets with no floor in that direction are dropped. | Not used by any content yet. Affects only targeted squares, not creatures. |
| ctrl | Manipulate Targets | Asks the user to choose more targets, using this block's own targeting settings centred on each current target. The new targets are added to the list or replace it, and later blocks then affect them. |  |
| ctrl | Modify Cast | Adds a bonus to this use of the ability: extra damage, edges, banes, surges, or ignoring damage immunity. Used by the Tactician and the Summoner. | Probably needs to come before the power roll it should affect (not confirmed). It adds the bonus once per target in its list, so it can stack if it has several targets. |
| ctrl | Order Targets | Sorts the targets by a formula, lowest first, so later blocks handle them in that order (for example, closest first). Used by the Fury's Thunder Roar and the water wolf. | Only matters when order is important to later blocks. |
| ctrl | Remember Target | Remembers the ability's first target so a trigger that fires later in the same use can check who it was (through "Stashed Target"). Used by the Shadow's "You Were Watching the Wrong One". | Remembers only one creature per user; the next use overwrites it. |
| ctrl | Reset Roll Status | Clears the record of which targets were hit, failed a save, or won an opposed roll, so later blocks using those target lists start fresh. Useful when one ability makes several separate rolls. | Developer-oriented. It only matters with the older "hit targets" / "failed save" target options. |
| ctrl | Track Stat | Adds an amount (1 by default) to a named per-encounter statistic for a hero, for the end-of-encounter hero stats. Used by the Critical Hit rule to count each hero's criticals. | Only records for heroes in a live encounter. Monsters and out-of-combat uses are ignored without any message. |
| help | Recovery Selection | Opens the healing choice window: for each target, the player picks how many Recoveries to spend and which effects to end. Extra choices cost the heroic resource, and a setting can make some of them free. Used by the Conduit's Healing Grace and Godsworn's Healing Gift. | Written for Healing Grace's cost rules (each extra target, Recovery or ended effect costs 1). |
| help | Set Stamina | Sets each target's Stamina to an exact value instead of healing or damaging them. Used by the Wraith's Stolen Vitality and the elementals' Elemental Swap. |  |
| res | Manifest Treasure | Equips a treasure the hero picked earlier, or removes it again ("vanish"). Used by the Artifact Bonded complication, where the artifact appears and disappears. | Only works together with a Grant Treasure feature set to manifest mode that has the same treasure id. |
| res | Pay Ability Cost | Spends the ability's cost at this exact point instead of when its effects first land, so later steps can't skip or refund it. Used by the Troubadour's "Fake your Death". | Developer-oriented timing control. Has no settings. |
| create | Build Wall | Builds a solid wall one square at a time on the targeted squares. The wall appears while the player picks the squares, and an option can remove the user's previous wall. Used by the Elementalist's Motivate Earth and the stone giant's Castle Stone Shape. | Needs a map object with the "wallvoxel" keyword chosen as the wall piece. Without one it does nothing. |
| create | Create Item | Gives each target a chosen item. The quantity is rolled first and can be a fixed number or dice such as 2d6. | Uses the old pop-up roll dialog, not the newer sidebar roll card. |
| create | Create Lane Object | Places a lane along the targeted line that slides creatures toward its far end when they enter it or start their turn there. Creatures already inside slide right away. Built for the Time Raider Helix's Kinetic Lane. | Made for one monster. Needs a line-shaped area and a suitable lane object. |
| create | Create Object | Places map objects from the object library in the target area, such as walls, brambles or spikes. It puts one on each square or one big object over the whole area, and can first push creatures standing there out of the way. Used by the Thorn Dragon's Bramble Barricade. |  |
| create | Discard Items | Makes each target drop or destroy items from its equipped gear or whole inventory: all of them, or one or several the player chooses. Dropped items appear on the map as loot. | Looks unfinished. The default "Items in Hand" choice has been removed and does nothing, so pick another. "Named Items" isn't implemented. Leaves debug output in the log. |
| create | Portal Transit | When a creature steps onto a portal, it can teleport to an empty square next to any other portal of the same name placed by the same creature. Declining leaves it where it is. Used by the Void Elementalist's There Is No Space Between. | Only works when triggered by a portal aura's "on enter". |
| create | Raise Corpse | Brings a dead creature back onto the map at its corpse, optionally at full Stamina with its conditions cleared. Used by undead "rises again" traits such as the Zombie's Endless Knight. | Must target a corpse object. Brings back full Stamina; to bring it back at a lower amount, add a Set Stamina block. |
| create | Relocate Aura | Moves one of the user's placed auras, found by name, to the targeted spot. Used by the Elementalist's Storm of Sands. | The aura name must match exactly, and the ability must target a spot or area. |
| create | Shift Wall Voxel | Moves a wall square into one of the squares a pushed creature just left. The user picks the square if there are several. Used by the Wallmaster's "Dead End". | Codex-internal: works only inside the Wallmaster's specific setup (wall targets, swap to the pushed creature, push, then this block last). |
| create | Summon Companion | Lets the player pick any Animal Companion creature from the bestiary and places it at the target square (or beside the user) as the user's companion, acting on the user's turn. | Looks like an older version: the Beastheart's Call Companion button uses a different system. This block spawns a new companion each time and doesn't remove the old one. Has no settings. |
| create | Summon Creatures | Brings new creatures onto the map, either a set monster or a choice from a filtered bestiary list. Options cover how many appear, where they are placed, who controls them, their initiative and whether they stay after combat. Used by the Troll Whelp's Lingering Hunger. | The default bestiary filter is a leftover from another game ("cr = 1 and type is beast"). Replace it. Can also replace the caster (Gnoll Carnage's transform). |
| create | Terraform Elevation | Raises or lowers the ground in the target area by a set height, for pits and pillars. Can optionally move creatures to the new height and check whether anyone falls. Used by the Orc Terranova and the Fossil Cryptic's stone pillars. |  |
| create | Terraform Terrain | Paints a ground texture over the target area, such as churned earth. Often paired with Terraform Elevation, as on the Orc Terranova. | Looks visual only. It does not seem to create difficult terrain (abilities use an aura for that). Not fully confirmed. |
| create | Transform Creatures | Turns each target into a monster form for the length of an attached effect, chosen by the player or at random from monsters that match a filter. Used by the Animal Form complication, the Rat Form treasure and Disciple of the Green. | Needs an effect set up, or nothing happens. The default monster filter uses old level/"beast" terms, so replace it. |
| create | Transform Zone | Turns a painted map zone of one type into another type, or removes it, for example lighting Flammable Oil into burning oil with a torch. It can look at the targets' squares, the squares next to them, or the whole area. If no zone is found, the rest of the ability stops. |  |
| move | Assign Movement Carrier | Marks a creature within grab range as a passenger that moves along with the user, like a grabbed creature, by applying a chosen ongoing effect. Using it again on the same passenger lets them go. | The chosen effect must track one caster and must carry a Movement Carrier modifier, or nothing happens. Obeys the maximum grabbed creatures limit. Not used in any content yet. |
| move | Change Movement Type | Switches each target's current way of moving (walk, fly, swim, burrow and so on). Used by Wings' Fly and the Crux of Fire. | Does not give a new way of moving. It only switches between ones the creature can already use. |
| move | Climb Creature | Lets the user climb onto each target, or makes targets get off whatever they are climbing, either sliding down safely or falling (with fall damage and prone). Used by the Climb Creature maneuver, Hold On and Fall Off Creature. |  |
| move | Dig Vertical Movement | The user picks how far to move straight up or down through the ground, up to its size by default, using +/- buttons. Used by the Dig maneuver. | It waits for any reactions to digging to finish before the choice appears. |
| move | Displace Creatures Overlapping Caster | Can first grow the user with a chosen size effect. It then moves every creature caught inside the user's space to the nearest free square (the user picks when several are equally near), and those creatures become the targets. | Not used by any content yet; it looks built for one specific engulf/grow monster ability. |
| move | Fall | Makes the targets fall if nothing is holding them up, using the normal falling rules. It can optionally stop a flying target from flying first ("Drop to Ground"). Used when Levitating ends. |  |
| move | Hop In Place | Makes each target jump up and land back on its own square, with an optional screen shake. It does not move the creature. Used by the ogre's Shockwave. | Visual only. |
| move | Hurl Grabbed Creature | Throws a creature the user is grabbing to the far end of a line ability. The grab ends, the creature lands on the last square of the line (or the nearest free square to it), and it is added to the targets so the power roll that follows hits it too. Used by the Ogre Goon's "People Bowling". | Not forced movement: stability, collisions and push distance don't apply. Needs a line-shaped ability and must come before the power roll. |
| move | Jump (Roll to Target) | The player picks where to land, with rings showing how far each roll result reaches. A roll is made only when the jump goes farther or higher than normal, and a poor roll lands the creature short, which can make it fall. Used by the Jump move action and the Null's Psionic Leap. |  |
| move | Lift Into The Air | Lifts each target straight up a set number of squares. When the ability ends, a target that can no longer fly is put back on the ground or falls. Used by the Levitated effect and the ghost. | The target must already be able to fly. Grant flight earlier in the same ability. |
| move | Pull Into Caster Space | Moves each target straight into the user's own space for free (it counts as forced movement and passes through creatures), with an optional floating label such as "Pulled in!". | Not used by any content yet. Probably meant to be paired with Displace Creatures Overlapping Caster. |
| move | Revert Location | Stops a creature that is moving past the caster at the first square of its path within a set distance, "catching" it there. Used by the Bugbears' Catcher. | Only works in a triggered ability set off by movement. Elsewhere there is no path to read and nothing happens. |
| move | Swing Object | Swings a hanging map object like a pendulum, out in a chosen direction and back the other way. Creatures in its path that pass the filter take the effect once per swing (by default 10 damage and possibly prone, but small prone creatures duck under). Used by the Incense Censer. | Only for abilities a map object gives to creatures. Built for the Incense Censer. |
| move | Teleport To Line End | Teleports the user to the far end of a line ability, or the free square closest to it, after everyone in the line has been hit. Used by the Shadow's "Shadowfall". | Needs a line-shaped ability. Shows "No room to reappear" if every square in the line is occupied. |
| move | Throw Object | Throws the map object that gives this ability to the targeted square. The object counts as force-moved, so effects like "takes damage per square moved" apply. Used by the Candelabra. | Only for abilities a map object gives to creatures (or uses itself). Give the ability a square target and a range. |
| tests | Draw Steel Save | Has each target make saving throws against its "save ends" conditions and effects; end-of-turn ones simply expire. Can be limited to one chosen condition or set to remove them without rolling. Used by the end-of-turn saving throw and by "remove a condition" abilities. | The picker currently describes this as "force a resistance roll", which is wrong. |
| tests | Manipulate Combat Order | Changes the turn order. It can start the target's turn now, make the target act next, add the targets to combat on the caster's side, or skip the target's turn. Used by the Tactician, Troubadour and Chronokinetic. | "Begin Turn" and "Skip Turn" only affect the first target. |
| tests | Opposed Power Roll | The user and each target make opposed power rolls with the chosen characteristic and skill. Targets who roll lower count as hit for the rest of the ability, and ties change nothing. Used by Search for Hidden Creatures and the Duelist's Verbal Duel. |  |
| tests | Roll Dice | Rolls a dice formula for each target, e.g. "2d6+3", and keeps the result so later blocks can read it as the cast's roll. | Uses the old pop-up roll window, not the timeline roll card. |
| tests | Roll on Table | Rolls on a table (one built into the block or an existing one) for each target and applies the row that comes up. The result can also be read as a rules effect. Used by the Conduit's and Troubadour's start-of-turn rolls for Piety and Drama. |  |
| tests | Skill Check | Asks each target to make a pass/fail check against a set difficulty (an attribute, a skill or a flat roll). Targets that fail are recorded so later blocks can apply to them. | Older generic system that uses the old pop-up roll dialog. Draw Steel tests normally use a power roll set up as a test. |
| show | Character Speech | Shows a speech bubble from each target with a random line from a list you write, not repeating until all lines are used. Used by the Troubadour and by effects like Choking. | If the creature currently speaks no language, it shows a fallback line ("..." by default). |
| show | Disguise | Changes how a token looks: the caster takes on a target's appearance, or the targets take the look of a monster picked from the bestiary. Used by the Stormwight Fury's animal forms and the War Dog Lesser Hypokrite. | Changes the look only (plus footprints and blood). Stats stay the same. |
| show | Dramatic Banner | Shows a full-screen banner (heroic or malice style) with a title and subtitle on a creature, and pauses the ability until it finishes. Used by the Shadow's "Hesitation is Weakness" ("{name} steps in and takes their turn"). |  |
| show | Open Character Sheet | Opens the user's character sheet on a chosen tab, such as the Builder. Used by monster templates like "Choose an Ancestry" so the Director can make the template's choices. | Menu shortcut, not a game effect. |
| show | Play Sound | Plays a built-in sound effect or a custom audio file, with optional volume and delay. Used by the Stormwight animal forms. | Not sure custom sounds are heard by everyone. They may play only on the user's own machine. |
| show | Show Journal Entry | Opens a journal document for the player, adding any explanation text from the user's features under extra headings. | Opens only on the screen of the player using the ability. The "Apply To" setting has no effect. Shows nothing if the document and the extra text are both empty. |
| script | Lua Script | Runs custom code written by a developer, for effects no other block can do. Used by the Devil Legate's Devilish Charm. | For developers only. Needs programming, and errors only show in the developer log. |
| script | Macro Execution | Runs a typed app command when the ability is used, such as a screen shake or a visual effect on a creature. Used by the ogre juggernaut and Pillar of Holy Fire for visual effects. | Developer tool. You need to know the app's command syntax, and it has no rules effect. |
| ctrl2 | Augmented Ability | Lets the user pick one of their own existing abilities, usually a strike, and make it as part of this ability with a change applied. The picked ability uses this ability's action and cost. Used by the Gnoll Cackler's "target makes a free strike". | Must be the only block on its ability. |
| ctrl2 | Custom Trigger | Sends a named signal, with an optional number, to each target. Any triggered ability on that creature listening for the same name can respond. Used by the gnolls' Cackletongue. | The name must match the listening trigger exactly. By default the ability carries on without waiting. Tick "Wait for trigger to resolve" to pause until the trigger is used or declined. |
| ctrl2 | Patron | Rolls the Acolyte's Patron's Gaze d10 on a special card. If the roll is at or under the current Gaze, it clears the Gaze, grants 2 Zeal and sets off Patron's Spite. | Codex-internal to the Acolyte's Patron's Gaze; not for general use. The display name is cut short (the full name is "Patron's Gaze Risk Resolve"). |
| ctrl2 | Persistence Control | At the start of the user's turn, ends persistent abilities whose targets are all dead, then asks which of the rest to keep and shows how much Essence is left after paying for them. Used by the Elementalist's Persistent Magic. | Elementalist-specific (Essence wording, start-of-turn resource). Only for triggered abilities. |
| ctrl2 | Recast Ability | Lets the user pick an ability that any creature used since the round began (limited by a filter) and use a copy of it. Used by the Troubadour's Encore and the Reaver's Death Strike. | Turns the ability into a picker when used. Only abilities recorded in this round's chat log are offered. |
| ctrl2 | Routine Control | Opens a picker where the Troubadour chooses which routines are active, up to their routine limit. The oldest selection is dropped when they go over. | Troubadour-specific. Marked as trigger-only. |
| ctrl2 | Steal Ability | Shows the target's abilities, lets the user pick one, and gives the user a copy for the length of an attached effect. An option can use the target's characteristic bonuses in the copy. Used by the Troubadour's College of the Harlequin Mask and the Absorption treasure. | Needs an effect set up, or nothing happens. |

## 4y. Wording pass from review (2026-11-23)

- **Melee targets:** "A creature within 1 square of you that you can reach" now reads "A creature
  within 1 square of you".
- **Target filter:** the label is "Only affects creatures who [+ test]". The card note reads "Only
  affects a creature if ...".
- **Empty tests:** every empty test slot now reads just "+ test". This covers the target filter,
  "Only if", "Only triggers if", a follow-up's filter and new items in an all/any list. The class
  builder's Logic block reads the same way.
- **Section names:** "Can be used when" is now **Can only be used when**, and "What happens" is
  now **When it's used**. The messages that name these sections changed to match.
- **Insertion point:** the "next block goes here" label is gone; the gold outline still marks
  the spot.
- **Side note:** now reads "Hover over dotted text to see its GoblinScript."
- **Class builder:** the "Recoveries, skills and kits are added on a level..." hint is removed.

## 4z. Test picker: one condition entry, combining first (2026-11-23)

These changes come from reviewer feedback, and apply in both editors:

- **Conditions:** the "Check a condition" group no longer lists every condition. It has one
  entry, such as "The target has a condition", and the block's own dropdown picks which
  condition. Searching a condition's name ("slowed") still finds the entry. The class builder
  has "You have a condition", "You don't have a condition" and, on roll options, "The target
  has a condition".
- **Combine tests** (All of these are true, Any of these is true, Not) now lead every test
  picker.

## 4aa. GoblinScript reference from "Type a formula instead" (2026-11-23)

"Type a formula instead" now opens with a **GoblinScript reference ↗** link, in both the
ability editor and the class builder. The reference opens in a panel over the editor, so the
formula menu and everything being edited stay put. Escape or Close shuts it.

- **Source:** the page is `ui-mockup/goblinscript.html`, built from the repo's
  `GoblinScript_Guide.md` by `ui-mockup/goblinscript-doc/build.py`. Re-run the build when the
  guide changes. The guide's opening "written for AI tools" note is left out of the page.
- **No outside site:** the page ships with the artifacts. `class-builder/goblinscript.html`
  links to the same file.

## 4ab. Shared tests added to both pickers (2026-11-23)

These tests are common in the compendium's formulas, but authors used to have to type them:

| Test | Saves as | Ability editor | Class builder |
|---|---|---|---|
| is an enemy / an ally | `not Friends(Caster, Target)` / `Friends(...)` | Kind of creature, in boxes without the "Enemy" fact | The target |
| has the [ ] effect | `Target.Ongoing Effects has "..."` | Check effects | Check effects (you), The target |
| has a save-ends effect | `Save Ends Effects` | Check effects | Check effects, The target |
| has the [Undead] keyword | `Target.Keywords has "..."` | Kind of creature | The target |
| is within [N] squares of you | `Caster.Distance(Target) <= N` / `Distance(Target) <= N` | Check what's nearby | The target |
| is no bigger than you; size is at most N | `Target.Size <= Caster.Size` | Kind of creature | The target; Compare a number |
| there are at least N enemies, allies or creatures within R squares | `Count Nearby Enemies(R) >= N` | Check what's nearby | Check what's nearby |
| an adjacent ally has the [ ] feature | `AdjacentAlliesWithFeature("...")` | Check what's nearby | Check what's nearby |
| it's a free strike | `Ability.Free Strike` | (not a roll box) | The ability |
| the target's [characteristic] | `Target.Might >= N` | already there | The target; Compare a number |

- **Empty names are flagged:** an effect, keyword or feature name left empty is listed in Status.
- **Bug fix (ability editor):** "an ally of" now names you by your role's own prefix. In "Only
  if" that is `Caster`; before the fix it was `Self`, which there means the target.
- **Round trips are unchanged:**
  - poll 1: 45/45
  - poll 2: 60/60
  - poll 3 (triggers): 1,148/1,148
  - Remember: 23/23
- **Left out on purpose:** tests for one class or monster (Rampaging, Summoner level, who
  gave you a condition, monster mode). The formula box covers those.

**Update (same day):** the reference page is now built from a user-facing rewrite,
`ui-mockup/goblinscript-doc/GoblinScript_User_Guide.md`. `GoblinScript_Guide.md` stays as the
technical reference. The rewrite has the following sections:
- what a formula is and where you type one
- copy-paste examples
- "who is who" (Self, Caster, Target...)
- how-to sections
- common mistakes
- lookup tables at the end

Where the old guide and the code disagreed, the rewrite follows the code:
- Heroic Resources This Turn is the turn's highest total, not what was gained.
- `Target.PassesPotency` takes two values.
- `Cast.HasTarget` and `Cast.TierForTarget` take a creature.
- Complications is a list you check with `has`.

Code samples turn off font ligatures, so `>=` shows as typed.

## 4ac. Effect names are searched from the compendium (2026-11-23)

"Has the [ ] effect" tests now pick the effect by searching the compendium's ongoing effects, in
both editors.

- **Ability editor:** a type-to-search box with the same list "Apply an effect" uses (1,034
  effects).
- **Class builder:** a search menu that shows up to 40 matches as you type. Its list is the new
  `effects` table in `class-builder/tables.js` (1,005 unique names), built by
  `class-builder-data/build_data.py`.
- **Custom names:** a typed name that isn't in the compendium is still allowed, because effects
  can be made in play. It is listed as worth checking ("isn't an effect in the compendium").

## 4ad. Everything a follow-up can be passed (2026-11-24)

"Use a new ability" used to offer the follow-up only 6 values from the ability that uses it:
- tier
- damage dealt
- squares moved
- number of targets
- first target
- target

The engine knows 46 (`ActivatedAbilityCast.helpSymbols`). The test and formula pickers inside a
follow-up now have two groups:
- **From [parent]:** the common six, as before.
- **More from [parent]:** the other 27 that can be passed as a value or a creature. Examples are
  high and low roll, natural roll, healing, raw damage, heroic resources gained, forced movement
  distance and collisions, opportunity attacks triggered, mode, and "last creature passed".
  - The group is collapsed to 3 at first ("Show 24 more"), so the picker stays uncluttered, and
    the search box finds any of them.
  - Yes/no values pass as 1 or 0, which their descriptions say.

Functions that need an argument (Has Target, Tier for Target, Memory...) are left out. Memory is
covered by "Remember a value". Saved follow-ups that already pass one of these values now open
with it as a chip instead of a formula. Round trips are unchanged: 45/45, 60/60, 1,148/1,148,
and 23/23.

**Revision (2026-11-24):** the two groups are now one. "From [parent]" lists the values in order
of how often compendium follow-ups use them. A scan of invoked abilities found:

| Value | Uses |
|---|---:|
| primary target | 25 |
| tier | 23 |
| squares moved | 12 |
| damage dealt | 10 |
| forced movement distance | 2 |
| number of targets, roll, damage dealt against | 1 each |

The first three show. The rest open from a "More from [parent] (N)..." button at the foot of the
same group, and search finds any of them. "First target" is no longer listed twice: the engine
has two names for the primary target.

**Revision (2026-11-24): showing where blocks can go.** As in the class builder, a drag now
outlines every place that would take what is being dragged, in dashed gold. For a step, that is
each step list it is allowed into; a power roll, for example, can't go inside a tier result. For
a value block, it is each box of the same kind (number or test). For a keyword, it is the
keyword row. The step list under the pointer opens a "Drop here" slot about the size of the step,
in place of the old white line. Value boxes still turn solid white under the pointer.
