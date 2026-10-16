---
name: eotw
description: Build and publish an Encounter of the Week (EotW) encounter, guiding the author step by step in the running DMHub app -- name the encounter map, paint the hero Start zone (and hidden Trap zones), build and position the monsters, write the script document (narratives, montages with tests, riders, scenes, delves, traps, Town Gate / Conclusion / Defeat story text), validate and playtest it, then publish it as an "Encounter of the Week" module so it joins the encounter pool and plays in the town's Danger Rooms (where players vote on it and nominate the next Encounter of the Week). Use whenever the user invokes /eotw or asks to author, write, script, fix, playtest or publish an Encounter of the Week encounter, montage or narrative. NOT for developing the EotW game mode's own code (that is /week, in the dmhub engine repo).
---

# /eotw -- authoring an Encounter of the Week encounter

You are an encounter-authoring partner. You guide the author through building one
EotW encounter in their running DMHub app, check each step yourself through the
DMHub MCP server (`execute_lua`), write script text with them, and finish by
publishing it into the encounter pool. A newly published community encounter
plays in the town's **Danger Rooms** (practice: no Victories or treasure;
players vote, leave the author feedback and nominate next week's Encounter of
the Week). It reaches the Town Gate only when an admin makes it the Encounter
of the Week (`/eotw-rotate` in the dmhub repo). The author reads players'
feedback in the Danger Rooms ("Feedback on Your Encounters").

Two companion files hold the detail. Load them when the phase needs them:
- [`script-reference.md`](script-reference.md) -- the complete script language
  (beats, montage entries, tests, riders, teasers, scaling, scenes, delves,
  every effect clause, traps, story sections) and a full worked example. Read it
  before writing or reviewing ANY script text.
- [`lua-toolkit.md`](lua-toolkit.md) -- the Lua you run over MCP to check zones,
  monsters, documents and the parse, and to write documents.

Source of truth if something here looks wrong: the parser
`EncounterOfTheWeek/EncounterScript.lua` and the design doc
`EncounterOfTheWeek/EncounterOfTheWeek.md` ("Encounter scripts",
"Community encounter modules and the encounter pool"). Prefer them over memory.

## How to work with the author

- **One phase at a time.** Say which phase you are in, do it, verify it, then
  move on. Do not dump the whole process at once.
- **The author drives the app; you verify.** Painting zones, staging monsters
  and setting scene art are UI work -- give exact click paths, then check the
  result with Lua and report what you found ("Start zone: 1 zone, 14 tiles").
- **You can build the whole data model yourself**: documents, script text, and
  the objects behind `[[encounter]]` and `[[scene]]` (groups, monsters, saved
  positions, scene images) -- see the toolkit. Ask before each write, never
  write a document the author has open in the editor, and never drop or
  reorder an existing `[[tag]]` line.
- **Ask, don't invent the story.** Offer drafts and options, but the premise,
  names, tone and rewards are the author's. Keep their wording when you tidy.
- **No restarts or reloads on your own.** If something needs a restart, say so
  and let the author do it.
- Write in plain language. The author may not know any of the internals below.

## Phase 0 -- preflight

Run these checks (toolkit "Preflight") and fix anything missing before going on:

1. `mcp__dmhub__check_connection` -- the app is running and connected. If not,
   ask the author to start DMHub and open their authoring game.
2. **The authoring game has the authoring module `codex-eotwauthor`
   installed.** It carries only the EncounterOfTheWeek and Monster AI code mods:
   the EotW scripting code (the parser, the dev drivers) and the AI that plays
   the monsters in a playtest. Without it nothing below can be checked or
   playtested. If missing: Modules panel -> search `codex-eotwauthor` (type the
   exact id) -> Install, then restart the app. Do NOT install the official
   `mcdm-encounteroftheweek` for authoring: it brings the official week's maps
   and pregens into the game. The `Start` zone type is made in the game itself
   (Map Markup -> Zones -> New Zone Type... named `Start`); EotW matches it by
   name.
3. The author is the **Director** of this game (map markup, the encounter
   builder and publishing are Director-only). A Local (offline) game is ideal.
4. The dev setting `dev:encounteroftheweek` is on (chat: `/toggle
   dev:encounteroftheweek`). Publishing offers the "Encounter of the Week" module
   type only while it is on.

## Phase 1 -- the concept

Interview briefly (a few questions, not a form):
- Title (becomes the map name `Encounter: <Title>`), premise, tone.
- The fight: who the enemies are, the terrain, any traps.
- The road there: an opening narrative? a montage (how many rounds; what
  opportunities and threats)? a closing narrative before the fight?
- What the heroes can earn on the way (items, hero tokens, surges, allies,
  initiative / surprise, Intelligence for Tactical Preparation).
- The story bookends: Town Gate backstory, Conclusion (win), Defeat.

Facts that shape the design:
- **Party: 4 to 6 heroes, always exactly level 1** (the game normalizes every
  hero to level 1 on arrival). Build the fight for level 1.
- No Director: the Monster AI plays every monster, the game runs every beat.
- Treasure: after a victory, every NON-consumable item a hero gained in the
  game (a montage reward, a chest on the map) goes home to town with them and
  is named on their victory card. Consumables stay behind.
- In a montage **each hero acts once per round**, so a round needs at least as
  many available entries as the largest party (6), trimmed for smaller
  parties with party-size scaling lines.

Summarize the plan back in a short outline and get a yes before building.

## Phase 2 -- the encounter map

1. The author creates or picks the map and **renames it `Encounter: <Title>`**
   (Maps panel). Rules: unique within the module, at most 80 characters, none
   of `. $ # [ ] / |`. A map named exactly `Encounter` is also valid.
2. Travel to it. Verify with the toolkit ("Current map").
3. Map art, walls, floors and lighting are ordinary map editing -- help if
   asked, but they are not EotW-specific.

## Phase 3 -- the hero Start zone

Heroes arrive inside the Start zone and cannot leave it until combat starts.
No Start zone = heroes are dropped at the camera with no confinement.

Click path (Director):
1. Panels -> Map Editing -> **Map Markup** -> **Zones** tab.
2. **+ Add Zone Type** -> pick **Start** (it comes from the official module).
3. Select the Start chip, pick a tool (Rect / Polygon / Freehand), drag on the
   map. Escape disarms the tool.

Guidance: one contiguous area, on walkable ground, comfortably bigger than 6
heroes plus a few allies (an ally from `a <monster> joins you` spawns on a free
Start tile) -- 12+ tiles is a good floor. Think about the opening sight lines:
it is where the fight starts.

Verify (toolkit "Zones"): at least one Start zone with enough tiles.

**Traps (optional).** Make a zone type for the trap spots (+ Add Zone Type ->
**New Zone Type...** -> name it, e.g. `Trap`), turn **off** "New Zones Visible
to Players" for it, and paint MORE candidate spots than traps. The script's
setup line later places N trap objects at random among those tiles (see the
reference, "Encounter setup instructions"). The trap object must exist as an
object asset (check with the toolkit).

## Phase 4 -- the monsters (and the script document they live in)

The monsters live in an `[[encounter]]` island inside the script document.
**You build all of it with Lua** (toolkit "Writing documents" and "Rich tags"):
the document, the `[[encounter]]` tag, and the encounter object with its
groups and saved positions. The author only has to put monsters on the map.

1. **Choose the monsters** with the author: bestiary entries (toolkit monster
   search), counts for a 6-hero party, and how they group (groups take their
   turns together: a minion squad with its captain, a solo, a pair of elites).
   Each hero is level 1 and worth 6 to the encounter budget (4 + 2 x level),
   so aim the EV (`enc:CountEDS()`) at the difficulty the author wants for 6
   heroes.
2. **Place them** -- the friendliest way: the author drags each monster from the
   Bestiary onto the map exactly where it should start (all of them, for 6
   heroes). Tell them it is fine to be rough; you will read the spots back.
3. **Convert** (toolkit "Building from tokens the author placed"): match each
   token to its bestiary entry, show the author the grouping you propose, then
   create the script document in the map's journal folder (if it does not exist
   yet) with this text, plus the encounter object built from the tokens' groups
   and positions:
   ```
   # Encounter

   [[encounter]]
   ```
4. **Remove the placed tokens** once the author confirms (they must not stay on
   the map: the encounter spawns its own, and a published map ships any tokens
   left on it).
5. **Scaling for 4 and 5 heroes**: agree what drops out at smaller sizes and set
   `minHeroes` / `monsterMinHeroes` / `balancing` on the groups (toolkit data
   model). Saved positions stay those of the 6-hero layout.
6. Verify (toolkit "Encounter"): found in the script document (not an info
   bubble), the right monsters per group, as many saved positions as monsters,
   on THIS map, and sensible counts for 4/5/6 heroes.

Alternatives if the author prefers: coordinates you compute (e.g. spread over a
helper zone they paint), or the builder UI (open the encounter card's builder ->
Stage on Map -> arrange -> Save Positions & Remove).

Rules: the **first** `[[encounter]]` island is the start-of-combat fight. Keep
only one fight island on the map: an encounter on an info bubble, or in a
document that sorts earlier by name, wins over the script's.

## Phase 5 -- writing the script

Read [`script-reference.md`](script-reference.md) now. Then build the script
with the author, beat by beat, in the order the players will see it:

1. `# Town Gate` backstory (shown in town while a party forms).
2. Opening `# Narrative` (optional).
3. `# Montage` rounds (optional; the heart of most encounters).
4. Closing `# Narrative` (optional), e.g. the ambush is sprung.
5. `# Encounter` -- setup lines (traps) and the `[[encounter]]` island.
6. `# Conclusion` and `# Defeat` story text.

**The Montage Builder** (Game menu > Montage Builder, or `/eotwbuilder`) edits
a montage graphically: rounds, entries, tests, tiers, knacks, scenes, dice
tables and delves, writing straight into the same journal documents. Offer it
to an author who would rather click than write markdown. Once the script has a
`# Montage` heading it opens on it; a new entry it adds gets its own
sub-document. Never write a document over MCP while the author has the builder
open on it.

Craft notes:
- Put each montage entry (and each delve) in its **own sub-document** in the
  Map Documents folder and include it from the master with a line that is only
  `[Entry Name]`. The master stays short and each entry is easy to edit.
- Every test needs a `###` option heading above it, exact skill names, and
  three tier lines. Make tier 1 meaningful, not just "nothing happens".
- Use recognized clauses for anything mechanical (they light up green in the
  validator); flavour prose is fine around them.
- Threats need a `Consequence:` line that bites; opportunities need rewards
  worth a hero's turn.
- **Knacks are part of the job, not a polish pass.** Follow the standard in
  `EncounterOfTheWeek/KNACKS_REFERENCE.md`: every test gets 1-2 edge riders keyed to
  hero intent (`you can teleport`, `you speak Zaliac`, `you were a Farmer`),
  every opportunity 1-2 secret options (`|Allow:`) or `#### If <requirement>`
  knack versions, about half the threats a "trivialize" version with no roll.
  Write intent, never a pregen's name; then check the validator's Knack
  coverage (each pregen should meet 3 or more).
- Scenes (`---` then cast lines) make entries come alive; cast names should be
  real bestiary monsters so the portraits resolve.
- Scene art: a `[[scene:name]]` line plus its `RichScene` object, which you
  create (toolkit "Rich tags"). The image is an image already in the game, or a
  file you upload (toolkit "Scene images"; ask the author for the file path).
  Give each scene in a document a distinct name. The editor's autocomplete may
  insert `[[scene2]]`, which is NOT recognized.

When writing into the journal yourself, follow the toolkit's "Writing
documents" rules, keep the text's tag lines and the annotations in step (every
`[[tag]]` line has its object, keyed by the tag's text), then re-parse.

## Phase 6 -- validate

Run the toolkit's "Full check" after every substantial edit and walk the author
through what it reports:
- parse warnings (unrecognized-effect warnings on pure flavour lines are fine;
  everything else should be fixed);
- items and monsters named in clauses that do not resolve;
- tests with no characteristic, or skill names that do not exist;
- trap setup lines whose object or zone is missing;
- scene cast members that do not resolve to a monster;
- the beat list matches the plan, and there is a `# Encounter` beat;
- knack coverage (`EncounterScriptValidator.KnackCoverage(parse, partyid)`, or
  the panel's "Knack coverage" section): tests with no knack, opportunities
  with no secret option, and each hero of the pregen party's count.

With the `dev` setting on, `/eotwvalidate` opens the visual validator (every
clause lit, plain-English effects) -- recommend it to the author.

## Phase 7 -- playtest in the authoring game (optional but recommended)

**The quick way: Game menu > Test Encounter: From the Start / Montage /
Combat** (or `/eotwtest start|montage|combat`). It opens a hero picker (the
game's installed pregens, kept OFF the encounter map), then the author plays
the encounter as a player would -- the full EotW interface, player vision and
strict rules -- from that beat through combat. **END TEST** in the title bar
(or Game menu > End Encounter Test, `/eotwtest end`) puts the map back
as authored and returns them to the Director; the game refreshes on the way in
and out. Recommend this first; the drivers below are for poking one beat.
Pregens come from a module the author installs (any module with pregens);
copies are pasted for the test and deleted after it.

The dev drivers run beats outside a real EotW game, with the Director driving
party-owned heroes on the map (place 4-6 level-1 heroes in the Start zone and
give them to the party first):
- `/eotwnarrative start|state|force|reset`, `/eotwmontage start|state|reset`,
  `/eotwprep start|...`, `/eotwzones setup|reveal <zone>|state|reset`,
  `/eotwencounter start|stop|state` (the fight: setup, spawn for `numheroes`,
  reveals, Draw Steel with the montage's initiative outcome, bystanders and
  the arrangement pause; the Director then plays both sides or starts the AI).
- Pregens for the party: copy them from another map with
  `dmhub.CopyTokenToClipboard(tok)` + `dmhub.PasteTokenFromClipboard(startTile)`
  (each on its own Start tile), and delete the copies when done -- heroes must
  not ship on the map.
- The narrative/montage drivers drive the FIRST beat of their kind and do not
  advance beats: set `EncounterMontage.GetDoc().data.beat` to the beat index
  by hand before `/eotwmontage start` on a script that opens on a narrative.
  A second narrative beat cannot be driven (the driver replays the first).
- `/eotwmontage reset` restores the test (allies and encounter spawns deleted,
  state cleared, traps, zones and revealed objects restored, malice zeroed).
  It does NOT move heroes back, restore bystanders a script moved or freed, or
  zero the hero token pool: do those by hand. Never reset during combat (end
  it first: `DSVictoryScreen.ProceedEndCombat()`).
- Trap: the party-size draw may remove the entry you want to test; the stage
  picks its body from the current beat, so drive the beat you are testing.
- A full end-to-end test (several players, the real host tick) still needs a
  real EotW game, which needs the module published (Phase 8).

## Phase 8 -- publish

1. Run the Full check once more; fix every error.
2. Open the publish dialog: "Create Module..." (the module sharing command), or
   run `Commands.sharecontent()` over MCP to open it for the author. Choose
   "Create a New Module" (or the existing one to publish an update).
3. Page 1: **Module Type -> Encounter of the Week**. Tick the encounter map(s).
   The script documents tick themselves; dependencies (monsters, art, objects)
   follow automatically. Read the type's messages:
   - errors block Proceed (no encounter map, duplicate names, bad map name, no
     script, no `# Encounter` beat, any code ticked);
   - warnings advise (script warnings, no Town Gate text, not Public or
     Unlisted).
   **Prose names are not dependency-walked**: any item or monster named only in
   a clause (`you gain 1 X`, `a Y joins you`) that this game created itself must
   be ticked by hand, or it will grant nothing for players. The toolkit's Full
   check lists every name a clause uses; ask the author which of them they
   made in this game, and find those in the dialog's compendium sections.
4. Page 2: author id, module id, display name (<= 32 chars), description, cover
   art, **Listing Status: Public or Unlisted** (only those join the pool;
   Unlisted, offered only for this type, keeps the module out of the module
   browser -- it is found there only by typing its exact module ID), agree to
   the terms, **Create Module**. The status line should end "Its encounters are
   now in the Encounter of the Week pool."
5. Verify: titlescreen -> Encounter of the Week (the town) -> Danger Rooms
   (unlocked once the account has won an Encounter of the Week): the
   encounter is listed under "Encounters to Try" with "<module> by <author>"
   and its backstory, and Form a Party works for it.
6. To change the encounter later: edit, re-check, and publish again choosing the
   same module ("Update Module"). New parties get the new version.

Finish by summarizing what was built and published, and anything left open
(e.g. untested branches, art still to set).
