---
name: class-ability
description: >-
  Orchestrates implementing a NEW or reworked ability for a hero CLASS from a
  rules write-up -- "add this ability to the Beastheart", "implement this
  heroic ability for the Shadow", "here is the write-up for a new Fury
  signature ability". Runs the full loop: decompose the write-up, research
  existing mechanisms so nothing gets re-coded, one compact clarification
  round, YAML (rarely Lua) implementation, adversarial review agents, then
  validate + import. Use EVERY time a class gains or changes an ability, even
  when the write-up looks trivial. Do NOT use for: monster or item content
  with no class wiring (implement-content), deciding what an ability should DO
  in game-design terms (feature-design), or diagnosing a malfunctioning
  existing ability (debug-discipline).
---

# Class Ability Implementation Loop

This skill is a thin orchestrator: the how-to lives in the referenced skills
and reference docs, and you point at them instead of restating them. What this
loop adds is the ORDER and the GATES. The failure modes it exists to prevent:
(1) coding a new behavior/symbol/effect that the engine already has, (2)
implementing on top of guessed assumptions, (3) burying the user in a wall of
questions, (4) a plausible-but-wrong MECHANISM that nobody attacked -- killed
at the DESIGN stage before any YAML exists (primary), and re-checked before
import (backstop), and (5) jumping straight to YAML before the write-up is
decomposed.

## Where the how-to lives (reference, do not restate)

| Need | Go to |
|---|---|
| ActivatedAbility YAML fields, behavior catalog, TriggeredAbility, filterTarget | `activated-ability` skill |
| File placement, validation, MCP auto-import, automation tiers, Explore delegation rules, Lua handoff protocol | `implement-content` skill |
| The 4-layer class nesting (ClassLevel -> CharacterFeatureChoice -> CharacterFeature -> CharacterModifier -> ActivatedAbility) | `compendium/reference/CLASS-ABILITY-TEMPLATE.md` |
| Heroic resources, level progression, class feature wiring | `compendium/reference/CLASS-IMPLEMENTATION.md` |
| Class/subclass/feature structures broadly | `compendium/reference/CHARACTERS.md` |
| Pitfalls, table names, UUID reference maps | `compendium/reference/CORE.md` |
| GoblinScript formulas (which symbols exist WHERE) | `compendium/reference/GOBLINSCRIPT-CONTEXTS.md`, `GOBLINSCRIPT-SYMBOLS.md`, `goblinscript` skill |

Read these selectively, at the stage that needs them -- not all upfront.

## Stage 1: Decompose the write-up

Think the problem through before touching anything. Produce a decomposition
table from the write-up: one row per mechanical primitive -- action cost,
resource cost, keywords, targeting (the exact "Target:" line), power roll and
tiers, damage, conditions and durations, forced movement, triggers, class
mechanic interactions (companion, heroic resource, kit), and where it slots
into the class (level, choice group, cost tier).

- The write-up is the contract. Every clause must land somewhere by the end:
  automated, creative workaround, or text-only WITH the user's sign-off.
- Note every ambiguity in a running list as you go. Do NOT ask about them
  yet -- Stage 2 usually answers half of them.

## Stage 2: Reuse recon -- evidence before authoring

Cheap to gather, expensive to skip. For each primitive, find what already
expresses it, in this order of preference:

1. **Sibling precedent**: the class's own YAML, then the closest ability in
   any class (`compendium/tables/classes/`). A near-clone with changed
   numbers is the ideal implementation -- study the sibling's exact pattern.
2. **Rule strings first**: most damage/conditions/movement/potency effects
   are tier strings or DrawSteelCommand rules, not bespoke behaviors (see
   implement-content's movement and power-table sections).
3. **Existing catalog**: behaviors (`activated-ability` skill), standard
   abilities, ongoing effects, custom attributes (UUID maps in CORE.md).
4. **Engine mechanisms not in the docs**: delegate open-ended questions to
   the `Explore` subagent per implement-content's "Investigating Automation
   Paths" question-shaping rules. Run independent questions as parallel
   agents. Keep your own context on YAML and rules logic.

Output: a **reuse map** -- each primitive resolved to {existing mechanism
(named, with file/pattern/UUID) | creative workaround | genuine gap}. A
"genuine gap" claim must state what was searched and not found. Only genuine
gaps justify Lua, and Lua goes through implement-content's handoff protocol --
never inline.

## Stage 3: Adversarial DESIGN review -- GATE, before authoring (PRIMARY)

The reuse map IS the design; attack it BEFORE writing any YAML. A wrong
mechanism caught here costs nothing -- caught after authoring + import it costs
a play-test, a shipped bug, and re-work. This is the PRIMARY adversarial gate;
the pre-import pass (Stage 6) is only a backstop.

Spawn two agents IN PARALLEL, each prompted to ATTACK the reuse map, not affirm
it. Give each the decomposition and the reuse map (each primitive -> chosen
mechanism, with file/UUID) and a capped return contract.

- **Correctness skeptic**: "Prove a chosen mechanism does NOT do what the text
  needs." For each reused effect/behavior/symbol, confirm it actually produces
  the described outcome for the described SUBJECT -- read the consuming Lua and
  a real WORKING precedent, not just a same-named object. High-value red flags:
  an effect that is defined but applied by NO shipping content (likely
  untested); a rollType/field aimed at the wrong creature (e.g.
  `ability_power_roll` on a defender does NOT reach the attacker --
  `enemy_ability_power_roll` does); duration/symbol/keyword vocab that is not in
  the engine's option list.
- **Reuse skeptic**: "Prove a closer-fit existing mechanism exists" -- a nearer
  sibling / standard ability / ongoing effect that expresses the primitive more
  faithfully than the chosen one.

Fold findings into the reuse map BEFORE you present it (Stage 4) or author
(Stage 5). A finding that flips the reuse-vs-build split is the whole point --
it changed before any code existed. If you genuinely cannot review the design
(the mechanism only becomes concrete during authoring), say so and lean on the
Stage 6 backstop -- but that is the exception, not the default.

## Stage 4: One compact clarification round

ONE round, before implementation -- not zero (guessing) and not a drip-feed.

- Present, briefly: where the ability slots in, the reuse map summary, the
  expected automation tier (implement-content's tier definitions), and any
  gaps with ranked options -- gaps surface NOW, not mid-implementation.
- Ask only decision-changing questions, each with a recommendation. Use
  AskUserQuestion when the options are enumerable; four questions maximum.
- Do not ask what recon or the references already answered, and do not
  restate the write-up back at the user.
- If nothing is ambiguous and there are no gaps, say so in one line and
  proceed -- the summary still gets shown, the questions don't.

## Stage 5: Implement

- Author per CLASS-ABILITY-TEMPLATE.md's nesting; wire heroic-resource or
  level mechanics per CLASS-IMPLEMENTATION.md.
- Placement, ASCII, UUID discipline, and update flow: implement-content's
  File Placement Rules. Write to `compendium/import/`; never edit
  `compendium/tables/` directly.
- Before writing ANY formula, check GOBLINSCRIPT-CONTEXTS.md for that field's
  symbols. Never guess symbol names.
- Lua only for evidenced gaps, via the Lua Handoff Protocol. **Caution --
  this overrides the note at the end of the `activated-ability` skill: do NOT
  create new Lua files and do NOT edit `main.lua` (it is game-managed). New
  behavior/symbol code goes into an existing file in the right module; if a
  new file is truly necessary, the user must create and register it through
  DMHub.**

## Stage 6: Adversarial review backstop + review marker -- before import, every time

The DESIGN was attacked in Stage 3; here you confirm the authored YAML
faithfully implements that reviewed design, and you re-attack anything the
design review could not have seen (a mechanism that only became concrete while
authoring). This stage ALWAYS runs before import -- even when nothing new turns
up, it is what WRITES the review marker the import gate requires.

Spawn two review agents IN PARALLEL, each prompted to attack, not to affirm.
Give each: the write-up verbatim, the authored file paths, pointers to the
relevant reference docs, and a return contract (findings with evidence,
capped length).

- **Reuse skeptic**: "Prove any custom mechanism here is unnecessary." Given
  the decomposition and the diff, hunt for standard abilities, existing
  ongoing effects, rule-string commands, or existing GoblinScript symbols
  that already express anything implemented as a custom effect, inline
  custom ability, workaround, or new Lua. Report each replaceable item with
  the existing mechanism's name and evidence (file, pattern, or UUID).
- **Correctness skeptic**: "Prove the YAML does not do what the text says."
  Verify targeting against the exact "Target:" line, tier-string separators
  (no `:`; `;` vs `,` semantics), symbol validity in each field's context,
  UUID resolution, modifier-name-matches-feature, duration vocabulary, and
  that nothing is float-text-faked (Bronze masquerading as Gold).

Fold confirmed findings back into the YAML. Every dismissed finding needs a
stated reason in your report to the user -- silent dismissal is how wrong
implementations survive. If a finding changes the reuse-vs-build split,
surface that to the user before proceeding.

For a large batch (a whole class's ability set at once), offer a Workflow
fan-out instead of serial agent pairs -- that requires the user's explicit
opt-in, so ask.

When (and only when) the review has cleared the authored files -- findings
folded in, or dismissed with a stated reason -- record it by touching the
marker `compendium/import/.review-passed`. The Stage 7 import hook DENIES any
import whose target file is newer than this marker, so if you edit a file after
reviewing it you MUST re-review and re-touch. Never touch the marker to
"unblock" an import you did not actually review -- that defeats the only
skip-proof part of this loop.

## Stage 7: Validate, import, verify

0. **Review gate.** Confirm the Stage 6 review marker
   (`compendium/import/.review-passed`) exists and is newer than every file you
   are about to import; if not, STOP and go back to Stage 6. A `PreToolUse`
   settings hook enforces this independently -- it DENIES the import command
   when the marker is missing or stale -- so a skipped review cannot reach the
   game even if you forget.
1. `python validate_yaml.py <files>` from the repo root -- zero errors,
   mandatory before import (the MCP path skips pre-validation).
2. Auto-import via MCP per implement-content's Auto-Import Pattern; surface
   every import error verbatim.
3. Verify what the bridge can see (the ability appears on the class, a
   formula evaluates); the user play-tests the rest. Report honestly: which
   clauses are automated at which tier, what is text-only, what was skipped.
4. If it malfunctions in-app, switch to `debug-discipline` -- do not stack
   patches on an unevidenced cause.
