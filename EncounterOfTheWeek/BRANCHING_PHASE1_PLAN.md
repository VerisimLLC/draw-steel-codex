# EotW Branching Scripts -- Phase 1 Implementation Plan

Status: ALL WORK PACKAGES BUILT 2026-11-24 (uncommitted, not run in the
app; see "Verification in the app" at the end). Was: PLAN, 2026-11-24. Implements phase 1 of `BRANCHING_DESIGN.md` (LOCKED;
decisions B1-B23). Phase 1 = grammar and runtime, testable without the
builder. Nothing here re-opens a design decision; where the plan had to pick an
implementation detail the design left open, it says so under "Plan choices".

All paths are under `EncounterOfTheWeek/` unless they start with another
folder. ES = `EncounterScript.lua`, EM = `EncounterMontage.lua`,
EG = `EncounterGauntlet.lua`, EOTW = `EncounterOfTheWeek.lua`,
EN = `EncounterNegotiation.lua`, ER = `EncounterReinforcements.lua`,
EV = `EncounterScriptValidator.lua`, EAT = `EncounterAuthoringText.lua`.

## Ground rules

- **No new Lua files.** Every change lands in an existing, registered file, so
  nothing needs CodeMod registration.
- **Linear scripts must not change.** Every work package keeps the existing
  test suites green before it adds checks: `tests/encounter_script_test.lua`,
  `tests/encounter_script_edit_test.lua`, `tests/encounter_negotiation_test.lua`
  (run from the codex root with `../dependencies/lua/bin/lua.exe <file>`).
- **Gates per package:** `luac -p` on changed files, the three test suites,
  `../tools/lua-typing/check.ps1 -Changed`, ASCII only. New player/author
  strings go through `T()` keys in EAT / `EncounterText.lua`.
- **No deploy, no commit** by Claude: the user deploys and commits. Each work
  package ends at a clean point the user can commit.
- Pure logic goes in ES (no engine globals) so it is unit-tested with the
  bundled interpreter; the runtime only calls it.

## Work packages, in order

Each package depends on the ones above it. WP1-WP2 are pure parser work and
carry most of the unit tests; WP3-WP6 are runtime and need the app.

### WP1 -- Parser: names, conditions, headers (ES; pure) -- DONE 2026-11-24

Built as planned, uncommitted. luac + type check clean; script tests 1332
(was 1250), edit 1006, negotiation 56. Changed two old tests on purpose:
`Track:` outside a part no longer warns (B4), and a montage `Go to:` is the
beat's exit instead of a warning (B22/P4). Pulled forward from WP2.1: every
beat exit and narrative route that names no section is checked against the
beat names once the parse ends (V6 for beat / offer exits; the existing
"names no section" text for narrative routes). Not yet read by the runtime:
`beat.playIf`, `beat.exit`, `offer.exit` and narrative routes to beats parse
but play as before until WP3-WP4.

1. **Beat names.** `# Montage: The Ambush`, `# Narrative: ...`,
   `# Encounter: ...` set `beat.name` (today only `Negotiation:` and
   `Delve:` take a name; `# Montage: X` currently parses as an unknown beat,
   ES:5711-5730). A beat in a journal of its own with no heading name takes
   the journal's name (needs WP1.3 spans). Unnamed beats keep working.
2. **Quoted tokens in `ParseCondition`** (ES:4226-4267): a `"..."` run is one
   token, so `"Fight or flee"` is not an `or`.
3. **Include spans.** `ExpandIncludes` (ES:4791) also returns
   `spans = { {first, last, docid, name}, ... }`; `ParseExpanded` passes them
   to `Parse`. At a span's first line the parser closes the open
   section/beat and reads the journal's header (`Only if:`). A link line
   inside a section warns.
4. **`Only if:`** under a beat heading (beside `TakeWhenLines`, ES:5068) and
   as a journal header -> `beat.onlyIf` (journal and beat conditions ANDed).
5. **Beat exits.** A `Go to:` as a beat's last line sets `beat.exit` for
   montage, negotiation and encounter beats (montages warn on `Go to` today,
   ES:5535-5544: change to "only as the last line"). In a Narrative, a
   section or option `Go to` may name a beat: resolve against the beat's own
   sections first, then beats (name clashes are errors, so this is never
   ambiguous). A result clause `go to X` may name a beat the same way.
6. **Negotiation offers:** `|Go to: X` inside `## Offer: ...` -> `offer.exit`
   (negotiation parse near ES:2440-2490).
7. **New condition atoms** (beside `ParseStoryAtom`, ES:4046; registered in
   `IsStoryAtom`, ES:4112, so every condition place can read them):
   `the party chose "<o>"` [`at "<section>"`]; `a hero` / `every hero` /
   `most heroes chose "<o>"`; `the party went to "<beat>"`;
   `"<montage>" was a failure / a partial success / a total success`;
   `the party took the "<offer>" deal`; `<N> or more heroes` (all
   comparisons); `there was no fight`; `Part <N> ended without a fight`.
   Atoms carry the raw names; resolution is WP2.
8. **Start-only clause (G7)** beside `ParseStartZoneClause` (ES:1245):
   `{ kind = "startzone", zone = z, only = true }`.
9. **`Track:` outside a series part** no longer warns (ES:6964).

Tests: one block per item in `encounter_script_test.lua`, plus a check that
the existing SAMPLE parses to the same beats as before.

### WP2 -- Parser: the beat graph and its checks (ES; pure) -- DONE 2026-11-24

Built, uncommitted. luac + type check clean; script tests 1368, edit 1006,
negotiation 56. New in ES (after `Parse`): `BeatLabel`, `BeatIndexByKey`,
`ResolveBeatTarget`, `LandOnBeat`, `NextBeat`, `BeatExits` (narrative exits
walk the section routes), `ScriptBranches`, `BeatPaths`, `DescribeBeatPath`,
`CheckBranches`. `parse.errors` lists the warnings that are errors (V1, V2,
V6, V7, V9, V10, V11) and keeps their journal names through `ParseExpanded`.
`ForEachCondition` now visits `Only if:` conditions ("onlyif").
Implementation calls made here:
- Path checks (V1-V5, V8, V11) run only in a script that branches, so an old
  linear two-fight script gets no V2 (K9).
- V4 = two or more gated versions of a beat in a row; the fix is to leave the
  last one ungated, as with gated islands.
- V11 fires for `Go to: Defeat` after a fight, not `Go to: Conclusion`
  (ending the aftermath early does not change the result). Confirmed by the
  user: B24.
- Not yet checked: a `went to` / `was a failure` condition naming no beat,
  and a hero (`PC ...`) condition inside `Only if:` (always false there).
  Both need a new string.

### WP2 plan (as written)

1. **Resolve every beat target** to an index or to `conclusion` / `defeat`;
   `End` keeps its Narrative meaning. Errors: no matching beat (V6), a quoted
   option that matches nothing (V7), a section / beat / delve name used
   twice, a beat named End / Conclusion / Defeat. Warning: an unqualified
   option name matching several options.
2. **`EncounterScript.NextBeat(parse, fromIndex, exitTarget, story)`** --
   the one "what plays next" function (B11): take `exitTarget` if given,
   else the next written beat; skip beats whose `onlyIf` is false against
   `story`; return an index, `"conclusion"`, `"defeat"` or nil (script end).
   Host, stage and validator all call it.
3. **`EncounterScript.BeatPaths(parse, cap)`** -- every start-to-finish path,
   treating each condition as unknown (both outcomes), with fallthrough
   edges, capped at 50. Built on the shape of `GauntletRoutes` (ES:3570).
4. **Checks on those paths** (into `parse.warnings` / errors):
   loop incl. fallthrough (V1); two fights on one path (V2, reworded);
   unreachable beat (V3); every version of a beat skippable (V4); a path
   with no fight (V5); the fallthrough leak into a sibling choice's target;
   one fork mixing `End` with `Conclusion` / `Defeat`; an ending `Go to`
   after a fight. Errors must not block publishing an existing two-fight
   script (it plays as today).

Tests: the brief's three examples and the three critique encounters as
fixtures; one fixture per check; `NextBeat` truth table.

### WP3 -- Runtime memory (EM, EG, EN) -- DONE 2026-11-24 (not run in the app)

Built, uncommitted. luac + type check clean; script tests 1368, edit 1006,
negotiation 59 (stubs for the new calls, checks that a deal and the path are
remembered and a rehearsed deal is not). New in EM: `NotePathBeat`,
`RememberChoice`, `RememberBeatResult`, `RememberDeal` (script-document
fields `path`, `choices`, `beatResults`, `deals`, `fought`, all cleared by
`ResetTest`); `Story()` returns them plus `heroCount` and each part's
`fought`; `data.montage.beatName`. Wired into: `EncounterMontage.Begin`
(path), the montage-end totals (that montage's own outcome against the part's
bars), `ResolveVote` / `ResolveIndividual` (a together vote's picks are the
players' votes; `asked` = the voters), `EncounterNegotiation.Begin` (path,
not in a rehearsal) and its `Finish` (the deal, including an interest-0
"No, and"), and `ReadyBattlefield` (the fight on the path, `fought`).
NOT verified in the app: needs a restart and a playthrough (WP7 command).

### WP3 plan (as written)

1. **Record choices** when a vote / individual choice resolves
   (`ResolveVote` EG:929, `ResolveIndividual` EG:865), before
   `EnterSection` (EG:598) or `Begin` (EM:6956) wipe them:
   `data.choices[#+1] = { beat, section, option, heroes = {charid = option},
   asked = n }`.
2. **Record beat results:** montage done -> `data.beatResults["b"..i] =
   OutcomeFor(per-hero score of that montage, bars)` (EM:430, totals at
   EM:7327); negotiation finish -> the deal's offer title, or
   `refused` / `left` (EN `Finish`, EN:104).
3. **`data.path`**: the host appends each beat index as it begins.
4. **`Story()`** (EM:252) exposes `choices`, `path`, `beatResults`,
   `heroCount`, `fought`; `EvalStoryCondition` evaluates the WP1.7 atoms.
5. **`ResetTest`** (EM:8195-8228) clears the new fields (it also serves
   `Series.StartNextPartNow`).

### WP4 -- Beat sequencing (EOTW, EG, stage) -- DONE 2026-11-24 (not run in the app)

Built, uncommitted. luac + type check clean; script tests 1376, edit 1006,
negotiation 59. What changed:
- ES `GauntletLeave` + `beat.leavesTo`: a narrative route naming another
  beat (or Conclusion / Defeat) ends the narrative; EG `MoveOn` records it as
  `m.exitTarget`, and `NextAfter` / `UpcomingSection` / `ProceedEnds` treat it
  as the narrative's end.
- EOTW `BeatExitTaken` (narrative route out, negotiation deal's or own exit,
  else the beat's exit), `NextBeatAfter`, `RequestScriptEnding`, `SkipBeat`,
  `BeatBegun`, `FightBeatIndex`. `AdvanceFromStageBeat` lands on
  `NextBeatAfter`; the skip branches use `SkipBeat`; a gated beat not yet
  begun is skipped at the top of `RunScriptBeat` (and the opening montage is
  not pre-presented when beat 1 is gated).
- After the fight: `AfterEncounterBeat` follows the fight beat reached;
  `AfterEncounterPending` waits while the index is still on that fight.
- `FightFollows(script, index[, beat, section])` reads the real next beat;
  the stage's two "Draw Steel!" Proceed labels pass their section.
- Skip to Combat follows the path with the story so far, else the first
  fight written after the current beat (with a console line).
Plan choice: no separate host-stamped `nextBeat`. Host and clients both
compute it from the shared script document (`NextBeatAfter`), so they agree;
the one input that is not in the document is `heroCount` (from `Heroes()`),
read only by a `N or more heroes` condition.
Until WP6: `Go to: Conclusion` / `Defeat` before the fight stamps
`scriptEnding` and stops the script, but nothing plays the ending yet.

### WP4 plan (as written)

1. `AdvanceFromStageBeat` (EOTW:6501) calls `NextBeat` with the exit the beat
   took (narrative route to a beat, offer exit, beat exit) and **stamps**
   `data.nextBeat` before `SetBeatIndex`.
2. `FightFollows` / `HoldDone` / `ProceedEnds` (EG:773-795) and the stage
   (stage :7754, :7812, :8411) read the stamp or the shared `NextBeat`, so the
   Draw Steel button is right on every client.
3. `AfterEncounterBeat` / `AfterEncounterPending` (EOTW:6408, :6476): the
   host stamps the first after-fight beat via `NextBeat`; clients stop
   comparing indexes. An all-skipped aftermath ends at once.
4. `SkipToCombatTarget` (EOTW:6843): walk `NextBeat` with the current story;
   where a later choice decides, the first fight in written order, with a
   console line saying so.

### WP5 -- The fight beat and start areas -- DONE 2026-11-24 (not run in the app)

Built, uncommitted. luac + type check clean; suites unchanged (1376 / 1006 /
59: this package is all engine-side, no new pure logic). What changed:
- The fight beat is worked out, not stamped: `FightBeatIndex` = the last
  encounter on `data.path`, else the current beat if it is an encounter,
  else the first encounter written; `FightBeat(script)` returns the beat.
- `Series.GatedIslandEntry` reads the fight beat's islands, and in a script
  with two or more fights uses them even when none is gated (so
  `FindMapEncounter`, the play area and the spawn follow the fight reached).
- `EncounterReinforcements.EncounterBeat` (waves, marks, `Victory:` /
  `ClearMapVictory`), bystander names and AI behaviours read the fight beat;
  so do the `/eotwzones setup`, encounter and preparation dev commands.
  `StartAtCombat` (combat-only) keeps the first fight written.
- `PlayArea` is cached per fight beat too. Reaching a fight beat in a script
  with several fights re-bounds the map and re-shares the play area
  (`ApplyPlayRegion`) once.
- Start-only clause: stored as `startZones[zone].only`; new
  `EncounterZones.OnlyStartZones`; `StartZoneLocs` then uses only those
  zones (not Start, not the builder's start tiles, P12). The stray-hero
  repair is keyed by the fight beat and the start-only zones, so heroes are
  moved into the new area before combat (about 5 s after it changes).
Not done here: the validator warning when a start-only clause and island
start tiles meet (V14) is WP7.

### WP5 plan (as written)

1. Host stamps `data.fightBeat` when an encounter beat is reached;
   `StartAtCombat` (EOTW:6884) uses the first fight in written order.
2. `FindMapEncounter` (EOTW:4371-4437) and `Series.GatedIslandEntry`
   (EOTW:4335) look up islands only inside the fight beat's source span.
3. `ER.EncounterBeat` (ER:48), `ClearMapVictory` (ER:969), `BystanderNames`
   (EOTW:5462) and the AI behaviour list (EOTW:5515) read the fight beat.
4. Start-only clause: `data.startZones[zone] = {only = true}`; the
   confinement drops the default Start zone; the host re-runs hero placement
   and re-shares the play area (EOTW:4463-4528, :7179) before prep. If the
   island has its own start tiles, the clause wins (validator warns, WP6).

### WP6 -- Endings without a fight -- DONE 2026-11-24 (not run in the app)

Built, uncommitted. luac + type check clean; suites unchanged. How it works:
- WP4's `RequestScriptEnding` stamps `eotwscript.data.scriptEnding = {kind,
  fought}` and moves the beat index past the end.
- Host (`MapScriptHostThink`, before combat, once every player is in):
  `HostFinishScriptEnding` dismisses the stage; for a victory runs
  `DecideSeriesResult(script, true, heroes, nil, false)` (so `# Results`
  runs; the stamp records `fought = false`); sends the analytics phase; marks
  the stamp `handled` with its `outcome`; the stage goes "complete". After a
  won fight (`fought = true`) it only marks it handled.
- Every client (`UpdateEncounterConclusion`): a handled, fightless stamp sets
  the outcome, seen and proceeded -- tests included -- so the existing path
  runs: the Conclusion / Defeat story screen, `RecordPendingOutcomes` and
  `OfferAbsentOutcomes` (a full victory, B23: Victories and treasure via
  `OutcomesFor`), the debrief and survey, the next-part offer. A resume reads
  the same stamp (it lives in the script document; `ResetTest` clears it).
- `AfterEncounterPending` is false when the part never fought.
- `SeedStory` carries each earlier part's `fought` into `story.parts`, so
  `Part N ended without a fight` works for a part played on in the same
  game. Across games it needs the City to keep the field (its series
  handoff is still unbuilt, PR 410).
Not covered: the in-game Victory count on the character sheet
(`DSVictoryScreen.AwardVictories` runs from the victory screen, which a
fightless ending never shows); the town record is what carries Victories.

### WP6 plan (as written)

1. `Go to: Conclusion` / `Defeat` before a fight: the host stamps
   `eotwstate.data.scriptEnding = { runId, kind, fought = false }`.
2. Victory: the host runs the award path as a fought victory (B23) without a
   combat queue: `DecideSeriesResult(..., rounds = nil)` (today only from
   `HostAwardOutcome`, EOTW:6257-6273), outcome records, `# Results`.
3. `UpdateEncounterConclusion` and the `m_outcomeSeen` gate (EOTW:3518-3556)
   accept the stamp, tests included; the story screen replaces the victory
   screen's Proceed.
4. Defeat story ending: the `# Defeat` story, a defeat outcome, nobody dies.
5. Downstream readers of "a fight happened": `OutcomesFor` (EOTW:2660),
   the survey / debrief / analytics end, part results (`fought = false` in
   the part row so `Part N ended without a fight` reads it; the City handoff
   for series is still unbuilt, PR 410).
6. Validator error for an ending `Go to` after a won fight (WP2.4) keeps the
   post-victory case out.

### WP7 -- Validator output and the test start -- DONE 2026-11-24 (not run in the app)

Built, uncommitted. luac + type check clean; script tests 1382 (validator
path list), edit 1006, negotiation 59. What changed:
- Validator: the parser's errors are listed first among the problems; a
  "Paths" section (`EncounterScriptValidator.BeatPathRows`) lists every way
  through a branching script, tagged `(no fight)` / `(defeat)`, with the
  "N+ paths" note when capped; V14 (start-only line vs island start tiles);
  V16 (`EncounterMontage.IgnoredScripts`: other playable scripts in a
  non-series map folder).
- `/eotwstartat <beat>; chose <option> [at <section>]; track <name> <value>`
  in EncounterMontage's dev commands: `ResetTest`, then the chosen options
  as party votes, the tracks, and the beat index.
Left for the phase 2 Paths tab: the choices that lead to each path (the
text list shows the beats and the ending only).

### WP7 plan (as written)

1. **Path list** in the validator: extend `GauntletRouteRows` (EV:773) to
   print `BeatPaths` one line per path with the choices that lead to it and
   `(no fight)` / `(defeat)` tags.
2. **Two script documents in one map folder** warning
   (`ChooseMapScript`, EM:1127-1172).
3. **Minimal Start at:** a dev chat command (registered where the other EotW
   dev commands are) `/eotwstartat <beat> [chose "<option>"] ...` that runs
   `ResetTest`, presets `data.choices` / tracks, and sets the beat. The
   builder UI for it is phase 2.

### WP8 -- Words and docs -- DONE 2026-11-24

Strings went into `EncounterAuthoringText.lua` with each package. The /eotw
skill's `script-reference.md` has "Branching between beats" (grammar,
conditions, fights, endings, writing advice, `/eotwstartat`, the Paths
list); `EncounterOfTheWeek.md` has a status entry and a "Branching scripts"
section. Strings added without being in the signed lists, for a later
look: the "Only if" placement messages, the name-clash labels ("a beat", "a
section of ...", "a delve") and the validator's "Paths" heading.

### WP8 plan (as written)

1. New `T()` keys in EAT for every WP1-WP2 warning and error (below).
2. `EncounterOfTheWeek.md`: a "Branching scripts" section pointing at the
   brief, and status lines as each package lands.
3. `.claude/skills/eotw/script-reference.md`: the grammar (G1-G12), the
   fight rules, and the guidance "open each branch with a line that names the
   choice" (B22/P10).

## New strings (SIGNED OFF 2026-11-24)

V1-V7 are in the brief's section 6. V8-V16, signed off by the user:

| Key | Draft |
|---|---|
| V8 | `'<Beat>' runs on into '<Other>', the other choice at '<Fork>'. Did you forget a Go to?` |
| V9 | `The name '<Name>' is used twice (<where>, <where>).` (error) |
| V10 | `A beat cannot be named '<End/Conclusion/Defeat>'.` (error) |
| V11 | `After the fight, Go to: <Conclusion/Defeat> cannot change how the part ended.` (error) |
| V12 | `'<Fork>' mixes Go to: End (carry on) with Go to: <Conclusion/Defeat> (end the part). Is that meant?` |
| V13 | `"<Option>" is an option in '<A>' and '<B>'. Add at "<section>" to say which.` |
| V14 | `'<Fight>' has a "start only in" line and its encounter has its own start tiles. The "start only in" line wins.` |
| V15 | `This journal link is inside the section '<Section>'. Put journal links between beats.` |
| V16 | `The map's folder has two scripts, '<A>' and '<B>'. Only '<A>' is played.` |

## Plan choices (implementation details the brief left open)

- Beat exits in a Narrative are the existing section / option `Go to` lines
  naming a beat, not a separate line after the last section.
- `NextBeat` and `BeatPaths` live in ES so the validator, the host and the
  unit tests share them.
- `Start at` in phase 1 is a dev chat command, not a dialog.

## Verified in the app (2026-11-24, single client, authoring test)

Test map `Encounter: Branch Test` (a copy of Inn of Beginnings) with a
`Start` and a `Ridge` zone, a script "Branch Test Script" with a three-way
vote, a peaceful parley, an `Only if:` ambush and two fights (Camp Goblins,
Hilltop Goblins). The parse in the app matched the unit tests (5 paths).
- Vote -> route to another beat: The Crossroads -> The Parley / The Ambush;
  the choice and the path were remembered.
- `Go to: Conclusion` from a vote before any fight: victory without a fight,
  the stage cleared, the Conclusion story and the end of the test.
- `Go to: Defeat`: defeat without a fight, nobody dead, the Defeat story.
- `Only if:` true: The Ambush played; its Proceed is labelled for a fight.
- The fight beat reached: Hilltop Goblins spawned (not the first island);
  the `When` line made Ridge the only start area and the player's hero was
  moved into it. Via the parley's Refuse: The Parley held on "Draw Steel!",
  then The Fight with the Camp Goblins and no start-only zone.
- After the second code review (2026-11-24), Pay the toll again: the ending
  was decided, the stage dissolved (about 2 s after the vote), and only then
  was it marked handled; the Conclusion and the end of the test followed,
  with no "stage never taken down" line (before the fix, a safety net pulled
  the stage down about 10 s late).
- After the second code review, Circle round again: The Ambush played, its
  Proceed was labelled for a fight, the choice was remembered, the path was
  The Crossroads > The Ambush > The Hilltop Fight; the Hilltop Goblins
  spawned, Ridge was the only start area, and the player's hero was moved
  into it. No new console errors.
- After the second code review, Turn back again: a defeat without a fight
  (`fought = false`), decided, the stage dissolved within about 2 s, then
  marked handled; the Defeat story and the end of the test followed; nobody
  died; no "stage never taken down" line. (A Journal panel error,
  `Journal.lua:1893`, appeared around the end of the previous test; that
  file is not part of this change.)
Fixed during the test: `PlayArea` looked the fight beat up before its cache
check, so every per-tile call re-parsed (a PERF log); now only on a cache
miss.
- A won fight leaving by `Go to: Conclusion` (Refuse -> The Fight, victory
  forced, Proceed clicked): no after-fight beats, straight to the
  Conclusion and the end of the test.
- `/eotwstartat The Ambush` with no choice: the test reset, the host skipped
  The Ambush ("its 'Only if' is false") and went on to The Fight.
- `/eotwstartat The Ambush; chose Circle round and strike first at The
  Camp`: The Ambush played.
- A negotiation's exit (in-app probe on a parsed negotiation with a stand-in
  result): "Yes, but" left by its offer's `Go to: Conclusion`; "No, and" and
  a refusal left by the negotiation's own `Go to: The Fight`, passing over
  the beat between.
Not yet seen: resume mid-branch (an F4 reload during a test ends the test
and clears the script document, so it is no stand-in for a resume; this
needs an app restart in the middle of a real game), a second client, a
negotiation played through to a deal. The copied heroes on the test map have no
owner, so they form a "PARTY" voter that no player can vote for and the
stray-hero repair skips them; the test cast that vote directly. That is the
test map, not branching.

## Verification in the app (after WP6, then after WP7)

Needs an app restart after the files are deployed by the user. With the DMHub
bridge (or by hand):
1. A linear script (Goblin Ambush) plays exactly as before.
2. The Crossroads fixture: both vote outcomes reach the right negotiation /
   montage and the right fight version; the Draw Steel button shows on both.
3. A peaceful `Go to: Conclusion` from an offer: Conclusion story, a victory
   recorded with no rounds, Victories and treasure awarded, no victory-screen
   wait.
4. A failed montage routing to `Go to: Defeat`: Defeat story, nobody dies.
5. A start-only clause moves heroes to the new zone.
6. Resume mid-branch and a late joiner: same beat, choices kept.
7. Two clients: the second sees the same stage and Draw Steel button.
8. `/eotwstartat` reaches path 3 directly.
