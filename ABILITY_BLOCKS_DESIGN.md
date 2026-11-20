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
