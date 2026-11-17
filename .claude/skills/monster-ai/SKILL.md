---
name: monster-ai
description: Implement or extend Draw Steel Monster AI behavior in DMHub for a named monster, set of monsters, family, faction, or monster band. Use when asked to create monster combat AI, make monsters use an ability or Malice feature, register monster moves, targeting and positioning priorities, prompt handlers, start-of-turn Malice abilities, villain actions, or triggered-ability decisions in draw-steel-codex. Prefers one Lua module per monster band, follows current repository examples, and proposes-but-does-not-implement Monster AI framework extensions unless the user explicitly authorizes framework work.
metadata:
  author: draw-steel-codex
  version: "1.0.0"
  argument-hint: <monster, band, or ability>
---

# Monster AI

Implement production-ready AI registrations for the requested Draw Steel
monsters. Preserve the distinction between monster behavior and the shared
Monster AI framework.

Paths below are relative to the `draw-steel-codex/` repository root (a nested
git repo inside `C:\dev\dmhub`; its default branch is `main`).

## Scope gate

Treat these as authorized behavior work:

- Add or update band-specific Lua modules.
- Register moves, prompts, triggers, Malice abilities, villain actions, and
  monster-filtered tactics through existing public interfaces.
- Register a new band module in the Monster AI CodeMod (see below).
- Refactor only the requested band's existing registrations into its band
  module when needed to maintain one-file ownership, without changing behavior
  accidentally.

Do not modify the core AI engine (`Monster AI/MonsterAI.lua`), turn/trigger
dispatch loop (`MonsterAIPanel.lua`), pathfinding, scoring helpers, registry
interfaces, or generic cross-monster behavior unless the user explicitly asks
for a framework extension. A general request such as "implement AI for this
monster" is not framework authorization.

When a mechanic cannot be represented by the existing framework:

1. Implement the remaining supported behavior.
2. Identify the exact unsupported decision or action and the evidence for it.
3. Suggest a minimal reusable framework extension, its proposed interface, and
   affected files.
4. Do not implement that extension until explicitly told to do so.

Do not edit monster compendium YAML merely to make AI easier. If the content
itself is incorrect or insufficiently automated, distinguish that content gap
from the AI gap and report it. Use the `implement-content` skill as well if the
user asks to change compendium content.

## Inspect before editing

1. Read `CLAUDE.md` at the codex root and `Monster AI/CLAUDE.md` completely.
   Treat current code as authoritative when documentation and implementation
   differ, and flag meaningful drift.
2. Run `git status` inside `draw-steel-codex/`. Preserve unrelated user changes.
3. Locate every requested monster's YAML under `data/monsters/`. Confirm the
   exact case-sensitive `monster_type`, `groupid`, `minion`, keywords, role,
   abilities, action resources, costs, targets, ranges, triggers, and nested
   behaviors.
4. Group-wide Malice features live on the monster group, not the stat block:
   `data/objectTables/monstergroup/<group>.yaml` under `maliceAbilities`. The
   group's `name` is what `monsterGroups = {...}` matches; stat blocks point to
   it through `groupid`. Ongoing effects they apply are in
   `data/objectTables/characterongoingeffects/`.
5. Read the source/reference rules when available (`monster-reference.md`,
   `data/docs/reference/MONSTER_PATTERNS.md`). Do not infer tactical intent
   solely from rendered text or an inactive placeholder ability.
6. Trace relevant runtime behavior when necessary: affordability, target
   filters, active-trigger shape, prompt names, nested abilities, conditions,
   and movement effects. Use the DMHub MCP `execute_lua` tool to inspect live
   state when the app is running.
7. Search the current Monster AI code for the closest mechanical examples.
   Prefer a proven local pattern over inventing a new one. Other bands
   (`MonsterAIHobgoblins.lua`, `MonsterAIDwarves.lua`, `monsterai-devils.lua`,
   `MonsterAIArixx.lua`, `MonsterAIChimera.lua`, `shadow-elves.lua`) are the
   best references.

Useful discovery searches (use the Grep tool):

- `monster_type:|name:|categorization:|targetType:|actionResourceId:|trigger:`
  in `data/monsters/<monster>.yaml`
- `MonsterAI:Register(Move|Prompt|Trigger|Tactic|MaliceAbility|VillainAction)`
  and the ability name in `Monster AI/`
- the ability name across `data/objectTables/monstergroup/`

## Plan coverage

Build a compact ability coverage list before coding. Classify each relevant
monster feature as one of:

- Already automatic in game rules; no AI registration needed.
- Already covered by generic AI.
- On-turn move requiring scoring and execution.
- Start-of-turn Malice ability.
- Villain action.
- Secondary prompt requiring a registered prompt handler.
- Optional triggered ability requiring a registered trigger decision.
- Minion signature already handled by squad-strike logic.
- Content automation gap rather than an AI gap.
- Unsupported by the current AI framework.

Account for the monster's whole combat loop, not just its signature strike:
movement and range, action economy, resource costs, area targeting, friendly
fire, repeat-use conditions, setup/payoff combinations, triggered actions, and
retreat or defensive behavior where the rules support them.

When the user states the tactical rule for an ability ("use X if Y"), implement
that rule as stated and report any consequence of it you think they may not
have considered, rather than silently substituting your own heuristic.

## Organize by monster band

Prefer exactly one behavior module for each band or cohesive monster family.
First reuse an existing band module. If none exists, follow any newer
repository naming convention; otherwise create:

```text
Monster AI/MonsterAI<BandName>.lua
```

Use a short ASCII PascalCase band name, for example `MonsterAIGoblins.lua`. Put
the band's move, prompt, trigger, Malice, villain-action, and monster-filtered
tactic registrations together in that file. Do not create separate files by
registration type for the same band unless explicitly requested. Band-local
helpers stay `local` to the file; do not reach into another band's locals.

Register every new top-level band module through the running DMHub CodeMod MCP
before substantive editing when possible:

1. Call `mcp__dmhub__check_connection` and confirm DMHub is fully loaded.
2. Call `mcp__dmhub__register_lua_file` with
   `path: "Monster AI/MonsterAI<BandName>.lua"`. Use its optional `before` or
   `after` argument only when an explicit load-order dependency requires it.
3. Confirm the result names the Monster AI CodeMod position and says Firebase
   persistence was confirmed.

The registration is idempotent and preserves an existing local file, so use it
even if implementation has already started. Do not manually add a `require` to
`main.lua`; that file is an informational index the engine never runs, and
editing it is not CodeMod registration. If the MCP bridge is unavailable, stop
and ask the user instead of substituting a filesystem-only file or hand-written
require.

If the requested band's behavior still lives in `MonsterAIMonsters.lua`, prefer
moving only that band's registrations into the band module as a focused,
semantics-preserving extraction. Do not migrate other bands opportunistically.
If the band's grouping is ambiguous, ask before choosing a permanent module
name.

## Implement with existing interfaces

### Moves

Use `MonsterAI:RegisterMove{}` for scoreable on-turn actions and combos.

- Give every registration a stable unique `id`, useful `description`, correct
  `category`, exact `monsters`, and exact `abilities` names.
- Use `GenerateStandardStrikeScoreFunction` and
  `GenerateStandardStrikeExecuteFunction` for ordinary strikes.
- Use `FindBestMoveToUseStrike`, `FindBestMoveToUseBurst`, or
  `FindBestLinePlan` for custom targeting and positioning.
- Make scoring pure: evaluate and return `nil` when unusable (optionally with a
  second string return giving the rejection reason for the decision log); do
  not mutate game state.
- Put calculated locations, targets, modes, or combo state in the scoring-info
  table for execution.
- Multi-mode abilities: pick the mode in `score`. Check each mode with
  `ability:ModeAvailableForTarget(token, target, modeIndex)` (its `condition`
  and Target Filter), choose among the modes that pass by their tactical value
  for this target (not list order), return `nil` with a reason if none passes,
  and pass it as `ai:ExecuteAbility(token, ability, targets,
  {symbols = {mode = N}})`. Omitted, it runs mode 1; `ExecuteAbility` rejects
  a mode that isn't available rather than picking another.
- Let existing affordability checks handle normal resource costs, but
  explicitly score rule-specific timing, thresholds, and setup/payoff
  constraints.
- Keep generic fallback scores below monster-specific choices. Calibrate new
  priorities against nearby existing examples rather than inventing a separate
  scale.
- Avoid allies and value multiple enemies for area abilities unless the
  monster's actual tactics justify otherwise.
- Execute through existing helpers and include established pacing sleeps where
  appropriate.

### Start-of-turn Malice abilities

Use `MonsterAI:RegisterMaliceAbility{}` for monster-group Malice features that
can only be activated at the start of a monster turn.

- Prefer `monsterGroups = {"Exact Group Name"}` for shared band features; use
  `monsters` only when the feature belongs to specific stat blocks.
- List exactly one group Malice ability in `abilities`.
- Return a normalized score from 0-1. The framework uses a default
  `minimumScore` of 0.65 and selects at most one qualifying Malice ability at
  the start of the initiative. Relative scores decide which of several
  qualifying abilities wins, so rank them deliberately.
- The framework remembers AI Malice casts per initiative queue only to apply a
  0.20 repeat *penalty*; it does not forbid reuse and the history is not
  exposed. If a feature should be used at most once per encounter, keep a
  band-local record keyed by `context.initiativeQueue.guid`, written in
  `execute` after the cast, and reject in `score` when present.
- Treat scoring as pure. Use the supplied `context.actingTokens`,
  `context.groupTokens`, `context.allyTokens`, `context.enemyTokens`,
  `context.round`, and `context.malice` to estimate the whole-turn benefit.
  `ai:CalculateMovementPaths(token, speed*10)` plus
  `ai:ExecuteWithTheoreticalMovementLoc` let a score ask "what could this
  monster reach this turn" without moving anything.
- Let `ability:CanAfford()` and the normal cast pipeline validate and spend
  the shared Malice resource.
- Guard against reapplying ongoing or encounter-long effects when their content
  does not independently prevent duplicate casts.
- Put any secondary use of granted abilities in execution code. For example, a
  Malice feature that grants a free Hide still needs AI execution for that
  granted action; activating the group feature alone is not full support.
- Omit `execute` for a straightforward cast. Provide it for cinematic speech,
  pacing, granted follow-up actions, bookkeeping, or map-wide targeting: a
  `targetType: map` ability needs explicit targets (see the Hobgoblin module's
  `BuildMapArea` / `TokensInArea` / `ExecuteAreaAbility`, or a `DeepCopy` with
  `targetType = "target"` and an explicit target list).
- These registrations are evaluated only once, after start-of-turn triggers and
  before both normal monster moves and minion squad strikes. Do not also
  register the group activation as a normal move.

### Presentation and pacing

Treat readable combat presentation as part of production-ready AI execution.

- Inspect comparable authored AI, especially goblin and hobgoblin moves, for
  pacing and speech conventions.
- Add deliberate `MonsterAI.Sleep` calls or
  `ai:ExecuteAbility(..., {sleep = ...})` pauses between visible beats such as
  movement, summoning, follow-up movement, and attacks. Prefer approximately
  0.5-1.0 seconds per beat, adjusted for the animation involved.
- Give the Director enough time to understand and react to each step of a
  multi-part action; never let a summon, movement, and follow-up strike
  collapse into one visually unreadable burst.
- Add concise, character-appropriate randomized speech to dramatic or signature
  actions when it improves the scene. Avoid making every routine action speak.
- Before implementing new speech, tell the user the exact candidate lines. Keep
  the lines together in a small table or similarly easy-to-revise location, and
  be ready to change them after playtesting.
- Put all pacing and speech in execution code, never in scoring functions.

### Prompts

Use `MonsterAI:RegisterPrompt{}` only when resolution presents a secondary
choice. Reuse an existing generic prompt handler (`MonsterAIPrompts.lua`) when
its semantics match exactly. Otherwise keep the handler in the band module and
qualify its prompt name by monster type whenever possible to avoid affecting
unrelated monsters.

Return only choices valid for the actual prompt shape. Trace the nested ability
to confirm whether it expects token targets, locations, directions, modes, or
another form.

### Triggers

Use `MonsterAI:RegisterTrigger{}` for optional triggered abilities. Prefer the
most stable identifier actually exposed by the runtime `ActiveTrigger`: ability
GUID, monster-qualified ability name, or displayed trigger text. Power-roll
triggers may only expose their display text through `ActiveTrigger:GetText()`.

Make the handler's decision tactical when acceptance is conditional. Return
`{activate = true}`, `{activate = true, mode = N}`, `{dismiss = true}`, or `nil`
according to the current interface. Use `expectedPrompt` only after confirming
the nested prompt's exact target shape.

### Villain actions

Use `MonsterAI:RegisterVillainAction{}` for Leader/Solo villain actions. Return
a normalized 0-1 score; the scheduler handles the one-per-round budget, slot
order, and per-encounter used state.

### Tactics and passive features

Use a monster-filtered registered tactic only when the existing tactic
interface can express a passive target or position preference. Do not add a
global tactic for a band-specific rule. Do not register features whose effects
are already applied automatically by the game rules.

## Validate

Validate in proportion to the change. Do not build DMHub unless explicitly
asked.

1. Parse every changed or new Lua file with the bundled interpreter (run from
   the codex root; there is no Lua on PATH and no other copy to look for):

   ```bash
   ../dependencies/lua/bin/luac.exe -p "Monster AI/MonsterAI<BandName>.lua"
   ```

2. Check types on the changed files (from the parent repo root, ~15 s):

   ```powershell
   .\tools\lua-typing\check.ps1 -Changed
   ```

3. For a new module, verify `mcp__dmhub__register_lua_file` succeeded and
   confirmed Firebase persistence.
4. Run `git diff --check` on the touched paths.
5. Confirm every changed Lua file is ASCII-only, as required by this
   repository (`LC_ALL=C grep -n $'[\x80-\xFF]' <file>` prints nothing;
   plain `grep -P` fails in this shell's locale).
6. Re-read the focused diff for exact monster and ability names, unique IDs,
   CodeMod load order, score/execute agreement, and accidental generic
   behavior.
7. Check that all implementable entries in the coverage list are handled or
   explicitly reported.
8. When a running DMHub instance is available, load the change and check it:
   `mcp__dmhub__reload_lua` then `mcp__dmhub__lua_status`. `reload_lua` re-runs
   what was already read, so if the new registrations do not appear (inspect
   `MonsterAI.maliceAbilities`, `MonsterAI.moves`, etc. via `execute_lua`),
   restart DMHub (`check_connection` first) rather than `dofile`-ing the file.
   Scoring functions can be exercised directly through `execute_lua` against a
   live encounter; the Monster AI panel's analysis view and `AI::` lines in
   `Player.log` show the decision trail.
9. Do not deploy, commit, or include unrelated modified files unless the user
   asks. Follow current repository deployment instructions if deployment is
   requested.

## Report

Lead with what the monster now knows how to do. Include:

- The band module created or updated and the monsters covered.
- Implemented moves, prompts, triggers, Malice abilities, villain actions, and
  tactics.
- Features already handled automatically or generically.
- Remaining content gaps or unsupported mechanics.
- Any proposed framework extensions, clearly marked as not implemented.
- Validation performed and whether changes are uncommitted or undeployed.
