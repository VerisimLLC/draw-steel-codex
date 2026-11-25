# EotW Branching Scripts -- Design Brief

Status: **LOCKED 2026-11-24** (feature-design loop 2026-11-23 to 2026-11-24,
critique round folded in). Everything in sections 2-4 is a settled decision
unless it is listed in section 5 (Open questions). The ledger (section 7)
records each decision and why; this brief is the single source of truth.
Changing a decision means a new ledger row, not an edit in place.

## 1. Frame

**Problem.** An EotW author can only write a story that runs in a straight line
between beats. A party's choices and earlier results can change text and routes
inside one Narrative, but not which Narrative, Montage or Encounter comes next.

**Who it serves.**
- The ambitious author (power user): real forks ("parley or ambush") with
  different fights and montages behind them, and earlier choices paying off
  later.
- The casual community author (set-and-forget): a one-path script keeps
  working unchanged, with nothing new to learn.
- Players: choices matter, shown only through what happens.

**Standing constraints this design keeps.**
- Prose markdown in journals; plain words, no symbol-heavy grammar.
- One condition language: `EncounterScript.ParseCondition`.
- No loops (David, 2026-11-07, `D:\DMHub\GAUNTLET_PLAN.md:267`): this
  guarantees every script ends.
- Builder is a list with a "goes to" picker, not a node graph
  (`GAUNTLET_PLAN.md:479`).
- A part is one map; story tracks and series results (D1-D19) are reused, not
  redesigned; new grammar lands in the Narrative runtime (Gauntlet merge).

## 2. The design

### 2.1 Writing a branch (B1, B2, B17)

Two additions, both optional. A script that uses neither plays top to bottom
exactly as today.

- **`Go to: <beat name>`** is the one way to route. It already routes between
  Narrative sections; now it can also name a beat, from an option, a section
  exit, a result clause, a scene `if` branch, a negotiation offer, or a
  beat's own exit. **A beat's exit `Go to:` is its last line** (any beat
  kind), where it takes effect (B22/P4).
- **`Only if: <condition>`** under a beat heading, or at the top of a journal
  (then it covers every beat in that journal; a journal's and a beat's
  conditions must both hold). A beat whose condition is false is skipped and
  play continues with the next written beat. This applies to a beat reached
  by `Go to` too.
- **Names match loosely** (case, a leading "the", trailing punctuation;
  `MatchKey`). A quoted name in a condition is one word, even if it contains
  "or" or "and". A `Go to` or a quoted option that matches nothing is an
  error, and so is a section, beat or delve name used twice, or a beat named
  End, Conclusion or Defeat.
- **Beat names** come from the heading (`# Montage: The Ambush`), or from the
  journal's name when the journal holds one beat.
- **Ending a part:** `Go to: Conclusion` (a victory, with or without a fight)
  and `Go to: Defeat`. `Go to: End` keeps its meaning, "end of this Narrative".

```markdown
# Narrative: The Crossroads
## The Camp
Choose together: How do you approach?
### Walk in under a white flag
Go to: The Parley
### Circle round and strike first
Go to: The Ambush

# Negotiation: The Parley
...
Go to: The Fight

# Montage: The Ambush
...

# Encounter: The Fight
When the party went to "The Parley":
[[encounter]]        <- Skrag stands aside
[[encounter]]        <- the full warband
```

A branch in its own journal (made by **+ Branch**):

```markdown
Only if: the party chose "Walk in under a white flag"

# Negotiation
...
## Offer: Yes
|Go to: Conclusion
## Offer: No, and
|Go to: The Fight

Go to: The Fight
```

Journal links sit between beats; a link inside a section warns.

### 2.2 Remembering choices (B4-B6)

- **Within a part, automatically:** every vote, individual choice and route
  taken is remembered and readable by any later condition in the part:
  `the party chose "<option>"`; `a hero chose` / `every hero chose` /
  `most heroes chose "<option>"` (a tie is not "most");
  `the party went to "<beat>"`. These are distinct from the existing
  `PC chose X`, which still means the current turn only. "Every" and "most"
  count the heroes who were asked.
- **Which option:** when two sections share option text, qualify it:
  `the party chose "Walk away" at "The Camp"`. An unqualified name that
  matches several options warns.
- **Results of beats** are remembered too: `"The Ambush" was a failure` /
  `a partial success` / `a total success` (each montage's own outcome,
  worked out when it ends), and `the party took the "Yes, but" deal` for a
  negotiation.
- **Other new conditions:** `5 or more heroes` (party size, anywhere),
  `there was no fight` (this part) and `Part 1 ended without a fight`.
- **Across parts:** declared story tracks only, as today. `Track:` is now
  allowed in any script, not only series parts.
- Stored in `eotwscript` beside `data.story`; kept on resume; cleared when a
  part starts.

### 2.3 Fights (B7, B8)

- A script may hold several `# Encounter` beats, but **any one path reaches at
  most one**. The one reached is the part's fight, with its own gated islands
  and `When` lines. Victory, award, `# Results` and the Conclusion are
  unchanged.
- An encounter beat's `When` lines may **replace** the starting area: "the
  heroes start only in the Ridge zone" / "the Ridge zone is the only starting
  area". (Today a clause can only add one; the default Start zone stays open.)
  Heroes are moved into the new zone and the play area is shared again
  before prep. When the beat's island also carries its own start tiles, the
  clause wins and the validator warns.
- The host stamps **the fight beat** once it is reached (`data.fightBeat`).
  Islands are looked up only inside that beat, and everything that today reads
  "the first encounter beat" reads it instead (reinforcements, the
  `Victory:` line, combat-only start, bystanders, AI behaviours). A
  combat-only game uses the first fight in written order.

### 2.4 Flow rules (B9, B10)

1. **No loops between beats.** A `Go to` may never reach a beat the party could
   already have passed. Parser error.
2. **Paths may merge** into a shared beat.
3. **A skipped beat** passes play to the next written beat.
4. **After-fight beats** may route forward with `Go to`.
5. **`Go to: Defeat`** ends the part as a defeat with the `# Defeat` story;
   nobody dies.
6. **A path may end without a fight.** `Go to: Conclusion` before any fight is
   a victory with no winning round. The host stamps a script ending
   (`{runId, kind, fought = false}`) in eotwstate and runs the series result
   with no rounds, so `# Results` runs; the Conclusion screen accepts the
   stamp (in tests too), and the story screen replaces the victory screen's
   Proceed. It awards the same as a fought victory (B23).
   The validator warns so it is never an accident.
7. **No ending `Go to` after a won fight.** `Go to: Conclusion` / `Defeat`
   in an after-fight beat is a validator error for `Defeat` only (B24):
   the victory is already recorded; `Conclusion` just ends the aftermath.

### 2.5 Runtime (B11, B12)

- `data.beat` stays the current-beat marker; a `Go to` sets it.
- New `data.path` lists the beats played.
- One "what plays next" function, shared by host and stage, replaces every
  "next is i+1" or "written order" assumption; the host stamps the next beat
  when a beat finishes, and clients (the Draw Steel button) read the stamp.
  Functions that change: `AdvanceFromStageBeat`, `FightFollows`,
  `HoldDone` / `ProceedEnds`, `AfterEncounterBeat`, `AfterEncounterPending`,
  `SkipToCombatTarget`, `StartAtCombat`, `FindMapEncounter`,
  `Series.GatedIslandEntry`, `EncounterReinforcements.EncounterBeat`,
  `BystanderNames`, the AI behaviour list, and the paths that set
  `"complete"` / end the script.
- The loop check includes fallthrough edges, not only `Go to`.
- **Parser:** `ExpandIncludes` returns include spans; at a span start the
  parser closes the open beat and reads the journal's header.
  `ParseCondition` reads a quoted string as one token.
- **Remembered choices** are recorded when a vote resolves (before
  `EnterSection` / `Begin` wipe it), exposed through `Story()` and
  `IsStoryAtom`, and cleared by `ResetTest` along with `data.path`.
- `Start at` goes through `ResetTest` (the "draw-steel" run-once guard is
  per map).
- Per-beat state stays keyed by beat index: with no loops a beat plays at most
  once, so keys never collide even where paths merge.
- Revert Turn: unchanged (`eotwscript` is not registered for checkpoints;
  choices happen outside combat turns). Resume and late join read `data.beat`,
  `data.path` and the choices from the same document.

### 2.6 Players (B13)

Players see nothing of the branching: no recap of choices, no "paths found"
count. Choices show only through what happens next.

### 2.7 Authoring (B14, B15)

- **Script list:** each beat card shows `leads to` and its `only if`.
- **Paths tab** (read-only, beside the list): every start-to-finish route on
  one line with the choices that lead to it, endings tagged `(no fight)` /
  `(defeat)`, problems marked with an icon as well as colour, a click on a
  step opens that beat. Capped at 50 ("50+ paths: showing the first 50").
- **Editing:** the "goes to" picker (GAUNTLET_PLAN step N5) for options,
  section exits and beats; an "only if" field on each beat card, checked as
  you type; **+ Branch** creates a journal in the map's folder with its header
  and links it from the master script.
- **Test Encounter:** `Start at` any beat, with `Choices so far` and tracks
  set first.
- **Validator:**
  - errors: a loop between beats (fallthrough included); a path that
    reaches two fights; a `Go to` that matches no beat; a quoted option that
    matches nothing; a section / beat / delve name used twice, or a beat
    named End / Conclusion / Defeat; an ending `Go to` after a won fight;
  - warnings: a path that falls through into a beat that is the `Go to`
    target of a sibling choice (the forgotten-`Go to` leak); an unreachable
    beat; a beat whose every version may be skipped; a path that ends without
    a fight; one fork mixing `Go to: End` with `Conclusion` / `Defeat`; an
    unqualified option name matching several options; a start-only clause and
    island start tiles on the same fight; a journal link inside a section;
    two script documents in one map folder.
  - Publishing does not block an existing two-fight script on these
    (it plays as today).

### 2.8 Creator feedback (B16)

At game end the host sends `data.path` and the ending (fought victory /
victory without a fight / defeat / story defeat). The creator feedback dialog
(`ShowCreatorFeedbackDialog`) adds **Paths taken (N games)**: one line per
distinct path with a count, never player names. A beat renamed in a later
version splits its counts (accepted).

### 2.9 Accessibility and performance (B18)

- Builder markers carry an icon as well as colour; every builder action works
  by click (picker, field, button), none needs dragging.
- Branch journals are linked from the master script, so the existing parse
  cache signature covers them.
- Path enumeration runs only in the validator and the Paths tab, never in the
  host tick; "what plays next" is a walk of the beat list.

### 2.10 What today's behaviour becomes (B19)

| Today | Under branching |
|---|---|
| `Go to` between Narrative sections | Unchanged |
| Gated `[[encounter]]` islands | Unchanged; read from the fight reached |
| After-fight beats | Start after the fight reached |
| Draw Steel button after a Narrative | Shown when the next beat to play is a fight |
| Skip to Combat (dev) | The fight on the current path; if later choices decide it, the first in written order, and it says so |
| Publishing | Unchanged; **+ Branch** journals are in the map's folder |
| Two fights in a row in an existing script | Validator error, but it plays as today (the second fight ends the path) |
| Two script documents in one map folder | New validator warning |

## 3. Phasing (B20)

1. **Grammar and runtime.** Parser (`Only if`, `Go to` to beats and from
   offers, beat names, include spans, quoted names, remembered choices and the
   new conditions, every error and warning in 2.7), runtime (2.3-2.5: the
   fight beat, fightless and story endings, replacing the start zone, the
   host-stamped next beat), unit tests in `tests/encounter_script_test.lua`.
   Also in phase 1, so it can be tested without the builder: the validator's
   text path list (extending `GauntletRouteRows` to beats) and a minimal
   `Start at` beat with preset choices. The /eotw skill's script reference
   gains the grammar and the guidance to open each branch with a line that
   names the choice.
2. **Builder.** Script-list lines, Paths tab, "goes to" picker, "only if"
   field, + Branch, the full Test Encounter `Start at` / `Choices so far`.
3. **Server (David), and later grammar.** Path feedback for creators (2.8);
   `you chose "<option>"` for riders, knacks and `Allow:`.

## 4. Out of scope (with reasons)

| Rejected or later | Why |
|---|---|
| Several fights in one part | Every end-of-fight system assumes one fight; series already give several (B7) |
| A fork that picks the next series part | City unlocks parts in order; its series handoff is not built (B7) |
| A node graph in the builder | Already rejected for Narratives; 440 px column; drag-only risk; large build (B14) |
| Remembered choices carried across parts | Option renames break silently; new City data; tracks cover it (B4) |
| A recap of choices, or a "paths found" count, for players | Immersion (B13) |
| A per-vote breakdown for creators | Paths show most of it; noisy on renames (B16) |
| Revert Turn rolling back the script | Choices happen outside combat turns; risk to host stage state (B12) |
| A journal header `Next:` | `Go to:` at the top of a journal does the same; one word per concept (B1) |
| A journal's exit `Go to` at the top of the journal | It would fire at the end; exits are a beat's last line (B22/P4) |
| `you chose "<option>"` (a hero's own choice following them) | Later phase: touches riders, knacks and `Allow:` (B22/P8) |
| `When:` as the "play only if" header | Already means "apply these clauses when" under a beat heading (B3) |

## 5. Open questions

None. Q1 (the award for a victory without a fight) was closed by B23.

## 6. Copy manifest (SIGNED OFF 2026-11-24)

### Script grammar (authors type these)
| Key | String | Notes |
|---|---|---|
| G1 | `Only if: <condition>` | under a beat heading or at the top of a journal |
| G2 | `Go to: <beat name>` | existing word, now also beats |
| G3 | `Go to: Conclusion` / `Go to: Defeat` | end the part; `Go to: End` still means end of this Narrative |
| G4 | `the party chose "<option>"` | remembered choice |
| G5 | `a hero chose "<option>"` / `every hero chose "<option>"` / `most heroes chose "<option>"` | individual choices |
| G6 | `the party went to "<beat>"` | route taken |
| G7 | `the heroes start only in the <Zone> zone` / `the <Zone> zone is the only starting area` | replace start area |
| G8 | `the party chose "<option>" at "<section>"` | qualifier (P5) |
| G9 | `"<montage beat>" was a failure` / `a partial success` / `a total success` | montage result (P2) |
| G10 | `the party took the "<offer>" deal` | negotiation result (P3) |
| G11 | `5 or more heroes` (any comparison) | party size (P7) |
| G12 | `there was no fight` / `Part <N> ended without a fight` | (P7) |

### Builder
| Key | String |
|---|---|
| U1 | `leads to` |
| U2 | `only if` |
| U3 | `Paths` (tab) |
| U4 | `+ Branch` |
| U5 | `50+ paths: showing the first 50` |
| U6 | `(no fight)` / `(defeat)` after a path's last step |
| U7 | `Start at` (Test Encounter beat picker) / `Choices so far` (preset section) |

### Validator
| Key | String |
|---|---|
| V1 | `'<Beat>' goes back to '<Earlier>': a script may only go forward.` (error) |
| V2 | `Two fights on one path are not supported yet: '<A>' and '<B>'.` (error; reworded by P13) |
| V3 | `No path reaches '<Beat>'.` |
| V4 | `'<A>' and '<B>' may both be skipped: every version of this beat has an "Only if".` |
| V5 | `The path <Path> ends without a fight (a victory with no fight).` |
| V6 | `Go to: '<Name>' does not match any beat.` |
| V7 | `"<Option>" is not an option in this part.` |

Not yet signed (write and sign at implementation): the strings for the
two-script-documents warning (B19) and for the errors and warnings the
critique round added (2.7: fallthrough leak, name clash, ending after a won
fight, End mixed with Conclusion, ambiguous option, start tiles conflict,
link inside a section).

### Creator feedback
| Key | String |
|---|---|
| F1 | `Paths taken (<N> games)` |
| F2 | ending tags: `(no fight)`, `(defeat)` |

## 7. Decision ledger

| # | Date | Decision | Why |
|---|---|---|---|
| B1 | 2026-11-24 | **Grammar is Option C.** `Go to: <beat>` is the only way to route, from an option, a section exit, a result clause, a scene `if` branch, or the top of a journal. A beat can carry a "play only if" condition under its heading or, as a journal header, for every beat in that journal; a false condition skips the beat. A script with neither plays in order as today. | One routing word authors already know; quick forks need no track; long branches in their own journals explain themselves. Rejected A (a journal cannot say when it plays) and B (every fork needs a track; vote and condition drift apart). |
| B2 | 2026-11-24 | **Beat names** come from the heading (`# Montage: The Ambush`), or from the journal's name when the journal holds one beat. | Needed for `Go to` to point at a beat. |
| B3 | 2026-11-24 | The "play only if" word is not `When`. (Final word in B17.) | `When` under a beat heading already applies clauses. |
| B4 | 2026-11-24 | **Memory is Option C.** Within a part, choices and routes are remembered automatically; across parts, declared tracks only. `Track:` allowed in any script. | Near payoffs need no setup; week-later payoffs are deliberate, stable names the City already stores. Rejected A (boilerplate) and B (renames break across parts; new City data). |
| B5 | 2026-11-24 | Remembered-choice conditions read differently from `PC chose X`: the party chose; a hero / every hero / most heroes chose (tie is not "most"); the party went to. | Avoid a second meaning for "chose". |
| B6 | 2026-11-24 | Remembered choices live in `eotwscript` beside `data.story`, survive a resume, and clear when a part starts. | Resume keeps them; parts start clean. |
| B7 | 2026-11-24 | **One fight per path.** Several `# Encounter` beats allowed; each path reaches at most one, and that one is the fight. Validator error on a path reaching two. | Victory, award, `# Results` and Conclusion untouched. Several fights per part and forks into series parts are later work. |
| B8 | 2026-11-24 | An encounter beat's `When` lines may **replace** the starting area, not only add one. | Alternative fights should really be somewhere else. |
| B9 | 2026-11-24 | **Flow rules:** no loops (parser error); paths may merge; a skipped beat passes to the next written; after-fight beats route forward; `Go to: Defeat` ends as a defeat, nobody dies. | Extends David's no-loops rule; the runtime does not block loops, so the parser must. |
| B10 | 2026-11-24 | **A path may end without a fight** via `Go to: Conclusion`: a victory with no winning round. Validator warns. | The peaceful ending makes the parley worth choosing. Rejected: every path must fight. Award: Q1. |
| B11 | 2026-11-24 | **Runtime:** `data.beat` stays; new `data.path`; one "what plays next" function; "the fight reached" replaces "the first encounter beat"; per-beat state stays keyed by index. | A beat plays at most once, so index keys are safe. |
| B12 | 2026-11-24 | **Revert Turn and resume: no change.** | Choices happen outside combat turns. |
| B13 | 2026-11-24 | **Players see nothing of the branching.** | User's call: immersion. Rejected a choices recap and a "1 of 3 paths" teaser. |
| B14 | 2026-11-24 | **Builder: "leads to" lines plus a read-only Paths tab** (cap 50, icon + colour, click to open). | Whole paths without a graph. Rejected lines alone and a node graph. |
| B15 | 2026-11-24 | **Builder editing and testing:** goes-to picker, only-if field, + Branch, Test `Start at` with choices preset; validator rules. | An author must try path 3 without playing paths 1 and 2. |
| B16 | 2026-11-24 | **Creator feedback: paths taken with counts**, later phase. | Paths are the unit an author designs in. Rejected none and a per-vote breakdown. |
| B17 | 2026-11-24 | **Copy signed off** (section 6), including `Only if:` and keeping `Go to: End`. | Plain sentences; no clash with existing grammar (checked EncounterScript.lua). |
| B18 | 2026-11-24 | **Accessibility and performance** as in 2.9. | Confirmed by the user with C13. |
| B19 | 2026-11-24 | **Regressions** as in 2.10, including a new two-script-documents warning. | No capability silently lost; published modules keep playing. |
| B20 | 2026-11-24 | **Three phases:** grammar and runtime; builder; server. | The ambitious authors write text, so playtests start soonest. Rejected two phases (later first playtest, builder before the grammar is proven). |
| B21 | 2026-11-24 | **Critique corrections K1-K10 accepted** (section 8.1): host-stamped fightless ending that runs the series result; no ending `Go to` after a won fight; host-stamped fight beat read by everything that took the first encounter beat; include spans for journal headers; quoted names in conditions; no written-order assumptions; host-stamped next beat; remembered-choice wiring; combat-only uses the first fight. | The brief was wrong or silent about the code; found by the implementation review and spot-checked (no quote handling in `ParseCondition`; `DecideSeriesResult` called only from the award path). |
| B22 | 2026-11-24 | **Critique proposals P1-P13 accepted** (section 8.2): fallthrough-leak warning; montage and negotiation results as conditions and `Go to` on offers; a beat's exit `Go to` is its last line, journal and beat `Only if` both hold; unmatched names and name clashes are errors, `at "<section>"` qualifier; text path list and `Start at` in phase 1; party-size and no-fight conditions; `you chose` later; a fightless victory awards as a fought one until Q1; authoring guidance to name the choice in each branch; End-vs-Conclusion warning; a start-only clause beats island start tiles; V2 reworded. | Found by the UX and encounter-designer reviews; the fallthrough leak by both independently. |
| B23 | 2026-11-24 | **Q1 closed: a victory without a fight is a full victory** (Victories and treasure as a fought one). Whether a path ends that way is the author's choice. | User: "If an Author wants to award a victory for a fightless encounter, that is fine." |
| B24 | 2026-11-24 | **V11 covers `Go to: Defeat` only.** After a won fight, `Go to: Conclusion` is allowed: it ends the after-fight beats early without changing the result. Narrows B21/K2. | User's call during WP2. |

## 8. Critique round (2026-11-24) -- ACCEPTED in full (B21, B22)

Three independent reviews: author/player UX (Hodent), implementation against
the code, and an encounter designer writing three test encounters. Paths
below are under `EncounterOfTheWeek/`.

### 8.1 Corrections: the brief was wrong or silent about the code
These change how phase 1 is built, not what authors write.

| # | Finding | Proposed fix |
|---|---|---|
| K1 | A fightless ending has nothing to end it. The Conclusion screen waits on the combat outcome (`m_outcomeSeen`, EncounterOfTheWeek.lua:3518-3556); `DecideSeriesResult` and `# Results` run only in `HostAwardOutcome` (:6257-6273); running out of script just dismisses the stage (:6653-6665). "Results handle that" (2.4) was false. | A host-stamped script ending (`{runId, kind, fought = false}`) in eotwstate; the host runs `DecideSeriesResult` with no rounds; `UpdateEncounterConclusion` accepts the stamp (tests too); the story screen replaces the victory screen's Proceed. |
| K2 | `Go to: Defeat` / `Conclusion` after a won fight contradicts the victory already recorded (`NoteOutcome`, :3489-3507). | Validator error: no ending `Go to` in after-fight beats. |
| K3 | The battlefield is not tied to the beat reached. Ungated islands come from the first `[[encounter]]` anywhere (`FindMapEncounter`, :4398-4437); the play area is worked out at arrival (:4463-4506); `EncounterReinforcements.EncounterBeat` (EncounterReinforcements.lua:48), `StartAtCombat` (:6884), `BystanderNames` / AI behaviours (:5462, :5515) all take the first or every encounter beat. | One host-stamped `data.fightBeat` that all of these read; islands looked up only inside that beat. Replacing the start area (B8) also moves heroes into the new zone and re-shares the play area before prep. |
| K4 | A journal-level header cannot work on today's parser: included text is spliced in with no boundary (`ExpandIncludes`, EncounterScript.lua:4791-4833), so a branch journal's header lands inside the preceding section, and its `Go to` becomes that section's route. | `ExpandIncludes` returns include spans; at a span start the parser closes the open beat and reads the journal header. Warn when a link sits inside a section. |
| K5 | `ParseCondition` splits on spaces and reads and / or / not as operators, with no quotes (:4228-4267): `the party chose "Fight or flee"` mis-parses. | Read a quoted string as one token. Names match loosely (`MatchKey`: case, leading "the", trailing punctuation). |
| K6 | Written order is still assumed in places: `AfterEncounterPending` (`index < first`, :6476), `SkipToCombatTarget` (only later beats, :6843); fallthrough plus a `Go to` to an earlier-written beat can loop; an all-skipped aftermath hangs clients 30 s (:6492). | The loop check includes fallthrough; index comparisons use `data.path`; the host stamps the next beat. |
| K7 | The Draw Steel button is predicted on clients (`FightFollows`, EncounterGauntlet.lua:773; stage :7754, :7812, :8411). | Host and stage share one "next beat" function; the host stamps it when a narrative finishes. |
| K8 | Remembered choices need wiring: record at vote resolution (before `EnterSection` / `Begin` wipe it), expose in `Story()` / `IsStoryAtom`, clear in `ResetTest` (EncounterMontage.lua:8195-8228). | As stated. "every / most heroes" count the heroes who were asked. |
| K9 | Smaller: a combat-only game needs a rule for which fight; `PartTotals` differs by path so series outcome bars are not comparable across paths; `RunOnce("draw-steel-%d")` fires once per map, so `Start at` must go through `ResetTest`; publish must not block existing two-fight scripts on V2. | Combat-only: the first fight in written order. Note the outcome-bar caveat in the authoring docs. The rest as stated. |
| K10 | Q1 is wider than the brief said: any victory gives surviving heroes Victories and treasure (`OutcomesFor`, :2660), in every non-practice game, not only the scheduled week. | See P9. |

### 8.2 Design proposals (need the user's decision)

| # | Gap | Proposal | Phase |
|---|---|---|---|
| P1 | **Forgetting a `Go to` leaks into the other branch** (two reviewers): the party plays both The Parley and The Ambush, and nothing warns. | New validator warning: a path falls through into a beat that is the `Go to` target of a sibling choice. | 1 |
| P2 | **A montage's result cannot pick the next beat** ("fail and you are captured"). | Per-montage outcome, worked out when the montage ends, with a condition `"The Ambush" was a failure` / `a partial success` / `a total success`. Routes through `Only if` or a scene. | 1 |
| P3 | **A negotiation's result cannot route or be remembered.** | `Go to:` allowed on offers; condition `the party took the "Yes, but" deal`. | 1 |
| P4 | **Where a beat's exit `Go to` is written.** At the top of a journal it fires at the end (form does not follow function); journal vs beat `Only if` combination unstated. | A beat's exit `Go to:` is written as its last line (every beat kind); `Only if:` stays at the top. Journal and beat `Only if` must both hold. Drops "top of a journal" from B1's list. | 1 |
| P5 | **Renames and duplicate names.** A renamed journal or option silently breaks routes; the same option text in two sections is ambiguous; a section and a beat can share a name. | V6 (no matching beat) and V7 (no matching option) become errors; optional qualifier `the party chose "Walk away" at "The Camp"`, warning when unqualified matches several; error on a section / beat / delve name clash or a beat named End / Conclusion / Defeat. | 1 |
| P6 | **Phase 1 is hard to test without the builder.** | Move into phase 1: the validator's text path list (extend `GauntletRouteRows` to beats) and a minimal `Start at` beat with preset choices (through `ResetTest`). Update the /eotw skill's script reference with the grammar. | 1 |
| P7 | **Small missing conditions.** | `5 or more heroes` (party size, usable everywhere); `there was no fight` and `Part 1 ended without a fight`. | 1 |
| P8 | **A hero's own choice does not follow the hero** ("the hero who stole the key gets an edge later"). | `you chose "<option>"` for riders, knacks and `Allow:`. | later |
| P9 | **Award for a fightless victory until David answers Q1** (K10). | Either (a) the same as a fought victory, or (b) nothing until Q1. | 1 |
| P10 | **Choices may feel arbitrary to players** (B13 stands). | Authoring guidance only: open each branch with a line that names the choice ("Skrag lowers his axe at the white flag"). | 1 (docs) |
| P11 | **`Go to: End` vs `Conclusion`** look alike. | Validator warning when one fork mixes `End` with `Conclusion` / `Defeat`. Copy unchanged. | 1 |
| P12 | **G7 vs an island's own start tiles** both set where heroes start. | The beat's explicit G7 clause wins; validator warns when both are present. | 1 |
| P13 | **V2 reads like a bug.** | Reword: `Two fights on one path are not supported yet: '<A>' and '<B>'.` (copy change) | 1 |

## Appendix A: Evidence -- current state (audited 2026-11-23/24)

All paths under `EncounterOfTheWeek/`.

### What already branches
- **Inside a Narrative:** `Go to:` lines (`SetGoto`, EncounterScript.lua:5279)
  and `go to X` result clauses route between sections. Runtime order
  (`GauntletNext`, :3644): result clause, option route, section exit, next
  section. Loops warn in the parser (DFS, :3482-3519); the runtime does not
  block them (EncounterGauntlet.lua:596-677). Unreachable sections warn (BFS,
  :3521-3538).
- **Which fight plays -- gated islands:** several `[[encounter]]` islands under
  the encounter beat, each but the last behind a bare `When <cond>:` line
  (parser :5092-5097, :6022-6032). `Series.GatedIslandEntry`
  (EncounterOfTheWeek.lua:4335) plays the first whose story condition holds.
  Only the FIRST encounter beat's islands are read (loop breaks at :4340).
- **Beat `When <cond>: <clauses>` lines** apply once per beat
  (`whenApplied["b"..index]`, EncounterMontage.lua:443-465).
- **Text branches:** `if / elseif / else / end` in scenes and story text.

### What does not branch
- **Beat order is index+1.** `AdvanceFromStageBeat`
  (EncounterOfTheWeek.lua:6501), `FightFollows` (EncounterGauntlet.lua:773),
  `AfterEncounterBeat` (EncounterOfTheWeek.lua:6408). The beat index is
  `eotwscript.data.beat` (EncounterMontage.lua:167; Get/Set at
  EncounterOfTheWeek.lua:6380/6391).
- **One fight per part.** The aftermath stops at a second `# Encounter`
  (:6404, :7109-7129).
- **Choices are not remembered.** Vote results live in
  `data.montage.gauntlet.vote`, wiped by the next beat's `Begin`
  (EncounterMontage.lua:6956) or the next section (EncounterGauntlet.lua:598).
  `PC chose X` reads only the current turn (EncounterMontage.lua:4247). Tracks
  persist (`ChangeTrack`, :3222-3234); undeclared track clauses do nothing
  (EncounterScript.lua:6945-6954); tracks outside a series part warn (:6964).
- **Documents do not branch.** Sub-document links only inline text
  (`ExpandIncludes`, EncounterScript.lua:4791; depth 8, cycle warning).
  Header lines exist only above the first beat / under `# Part N`
  (`TakePartLines`, :4983) and under a beat heading (`TakeWhenLines`, :5068).
- **Two script candidates in a map folder:** first by name wins; the other is
  silently ignored (EncounterMontage.lua:1162-1172).

### Things keyed by beat index
`whenApplied["b"..i]`, `montageTotals["b"..i]` (EncounterMontage.lua:7327),
`RunOnce("draw-steel-"..index)`, `m_montageReported[index]`, `m.beatIndex`
(EncounterMontage.lua:6957, :7096). Safe under B9 (a beat plays at most once).

### Resume / late join / revert
- Clients read the live beat from `eotwscript`; `HostTick` re-runs `Begin`
  when `m.beatIndex` differs (EncounterMontage.lua:7096). A resume re-presents
  a half-played beat (EncounterOfTheWeek.lua:7927-7957).
- The aftermath stage lives in the map script's shared state, not eotwscript.
- `eotwscript` is not registered for checkpoint backups.

### Start zones
- A clause can ADD a start zone ("the Start2 zone becomes a starting area",
  `ParseStartZoneClause`, EncounterScript.lua:1245-1265) -> `eotwscript`
  `data.startZones` -> `EncounterZones.UnlockedStartZones`
  (EncounterZones.lua:584). Nothing replaces the default Start zone.

### Authoring surfaces and feedback
- Builder: modal at 94% x 92%, 440 px board left, editor right
  (EncounterMontageBuilder.lua:3595-3640). Script view
  (EncounterScriptBuilder.lua, `S.Outline` :476): beat cards with ^/v reorder
  and problem counts. No route UI.
- Validator prints routes as text and enumerates Narrative paths for 3/4/5
  heroes (`GauntletRouteRows`, EncounterScriptValidator.lua:773; cap 50).
- Proving Pits debrief: up/down vote and a comment for the creator
  (`danger-feedback`); read in `ShowCreatorFeedbackDialog`
  (Codex Titlescreen/EncounterOfTheWeek.lua). Proving Pits games are practice:
  no Victory, treasure or outcome (EncounterOfTheWeek.md:155).
