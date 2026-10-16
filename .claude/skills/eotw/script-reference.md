# Encounter of the Week script reference

The script is ordinary journal markdown in the encounter map's **Map Documents**
folder. The parser is `EncounterOfTheWeek/EncounterScript.lua`;
when this file and the parser disagree, the parser wins (and fix this file).

Everything is case-insensitive unless noted. A journal soft break
(shift+enter) counts as a line break.

## Which document is the script

- Candidates: every non-hidden markdown document filed under the encounter
  map's journal folder, sorted by name.
- The first candidate that declares beats (and is not included by another
  document) is the script; a document with explicit `#` beats beats one without.
- **Sub-documents.** A line that is ONLY a link to another journal document --
  `[Name]`, `[:Name]` (embed) or `[label](document:Name)` -- is replaced by that
  document's text before parsing (nested up to 8 deep; cycles warn). A link in
  the middle of a sentence stays a link. Resolution prefers a document in the
  same map folder. Keep sub-documents directly in the Map Documents folder
  (that is what gets published). A sub-document is a "part", never a script
  of its own.
- Warnings name the document they came from (`'Mysterious Cottage' line 29: ...`).
- Rich tags (`[[scene]]`, `[[encounter]]`) stay with the document they are in.

## Top-level sections

`#` headings divide the script. Beats run in document order:

| Heading | What it is |
|---|---|
| `# Narrative` | a story beat on the stage: sections, choices, votes |
| `# Montage` | a montage of rounds: opportunities and threats, tests |
| `# Encounter` | the fight: setup instructions (traps, bystanders, an extra `Victory:`), then the `[[encounter]]` island, then any `## Reinforcements: <Name>` sections |

Not beats (can sit anywhere, including in a sub-document):

| Heading | What it is |
|---|---|
| `# Town Gate` | backstory shown in town under the encounter choice while a party forms (copied into the module record at publish) |
| `# Conclusion` | story screen after a victory, before "Return to Blackbottom" |
| `# Defeat` | story screen after a defeat |
| `# Delve: <Name>` | a delve entered from a montage option (see Delves) |

Any other `#` heading warns and is ignored. A document with no beats but an
`[[encounter]]` island plays as a plain fight.

Story sections: everything up to the next `#` heading, as paragraphs. `##`
headings and `[[tag]]` lines inside are not text, except a `[[scene]]` there
is the section's backdrop.

## Effect clauses (shared by every beat)

Any rules line -- a tier line, a `Consequence:`, a narrative option's `|` line,
a chest row -- is split into **clauses** on `. , ; ! ?`, and each clause is
matched on its own. Quantities: digits, `one`..`ten`, or `a`/`an` (= 1).
Anything unmatched is narrative text (shown, no effect). Recognized clauses
show green in the validator.

`{...}` around a clause: applied but **never shown** to players (stage, roll
dialog, log). Use it for hidden mechanics.

| Write | Effect |
|---|---|
| `you gain 2 Healing Potions` / `each party member gains 1 Healing Potion` | item(s) to the acting hero / every hero. Name = a gear item, trailing `s` tolerated |
| `you lose 5 stamina` / `each party member loses 3 stamina` | damage |
| `you heal 5 stamina` (`regain`, `recover`) / `each party member heals ...` | healing |
| `you gain 5 temporary stamina` / `each party member gains ...` | temporary Stamina (the higher of old and new) |
| `you gain 2 surges` / `[at the start of the next combat] each party member gains 1 surge` | surges, banked and paid when combat starts |
| `your recovery value is increased by 2` / `+2 recovery value` / `each party member's recovery value is increased by 2` | Recovery Value boon until the next respite |
| `you lose a recovery` / `each party member loses two recoveries` | recoveries lost (no Stamina back) |
| `+1 hero token` / `you gain 2 hero tokens` / `the party gains 1 hero token` | party Hero Token pool |
| `+2 intelligence` / `the party gains 1 intelligence` | Intelligence pool (needs `Unlock: Intelligence` somewhere; warns otherwise) |
| `+2 malice` / `gain 2 malice` | Director's Malice pool (carries into combat) |
| `a Wode Hag joins you` / `Wolf joins you` | allied monster (bestiary name), on a free Start tile, controlled by the acting player, fights on the heroes' side |
| `the threat is vanquished` / `you vanquish the threat` | resolves the threat (no consequence) |
| `you begin the encounter surprised` / `you are surprised` | monsters go first; Surprised on every hero (sticky) |
| `you surprise the enemy` / `the enemies are surprised` | heroes go first; monsters Surprised at combat start |
| `you win initiative` / `you lose initiative` | forced initiative, no die |
| `you cannot be surprised` / `the party is immune to surprise` | Surprised withheld from heroes (and lifted); a later surprise still loses initiative |
| `the encounter begins with a fair roll` / `you roll for initiative normally` / `you are no longer surprised` | cancels what went AGAINST the party (their Surprised, a lose/surprised outcome); keeps anything in their favour |
| `you know the stamina of goblins` / `the party learns the stamina of every undead` | exact Stamina shown for monsters with that stat-block keyword |
| `reveal traps` / `reveal the trap zones during the next combat` / `traps are revealed` | that zone type becomes visible to players at the encounter beat |
| `unlock Interrogate the Goblin` / `you unlock ...` | a `(Locked)` entry joins the board |
| `you gain an edge on Climb the Cliff` / `the party has a double bane on Sneak Past` | standing edge/bane on that `###` option's test for whoever takes it |
| `roll twice on Tinkerer's Wares` / `roll on Herb Pouch` / `you roll 3 times on X` | rolls the entry's own dice table (see "Dice tables in an entry") that many times on the host and applies each row landed on |
| `your rolled damage is increased by 1` / `+1 to rolled damage` / `each party member's rolled damage is increased by 1` | +N to the damage of every damaging power roll, until the next respite |
| `your maximum Stamina is reduced by 5` / `you lose 5 maximum stamina` / `each party member's maximum stamina is reduced by 5` | Stamina maximum curse, until the next respite |
| `you lose a consumable` / `each party member loses a consumable` | one random consumable item leaves the inventory; a hero carrying none silently loses 1 Recovery instead |
| `the Start2 zone becomes a starting area` / `you may also start in the Start2 zone` | that zone type joins the Start zone for pre-combat confinement (heroes may stand there before the fight; it is revealed at the encounter beat) |
| `reveal the Treasure Chest object` / `the Treasure Chest object is revealed` | a map object the author left INACTIVE (Object Properties -> deactivate) is switched on at the encounter beat. The word "object" is required |
| `you fail ...`, `you succeed ...`, `nothing happens` | narrative only (recognized, no effect) |

Initiative: the last initiative outcome wins, but surprise overrides it -- a
surprised party always loses the initiative, a surprised enemy always hands it
to the heroes.

Timing words on the boons and curses ("this encounter", "for the rest of the
encounter", "until the next respite") are flavour. Write "of every Dwarf", not
"of dwarves", for a stamina reveal: the keyword is singularised by dropping a
trailing "s", so "dwarves" would become "dwarve".

Prose names (items, monsters) are looked up when the effect applies. Anything
that is not in the core data must ship in the module (tick it when publishing),
or it silently grants nothing for players.

## Montage beats

```
# Montage

[[scene]]

Intro prose: shown in the header for the whole montage (about 7 lines max).

## Round 1
4 Players: -2 Opportunity, -1 Threat
5 Players: -1 Opportunity

## Opportunity: Mysterious Cottage

A cottage sits off the path, smoke curling from its chimney.

---

PC approaches the cottage door.
Witch (Wode Hag) enters
Witch: (in Hyrallic) Who comes knocking?
Witch is alert

### Negotiate with her for aid

PC: Good morrow! We seek help.

|Negotiation Test: Presence (Empathize, Persuade, Lie)
|You fail. The witch is unimpressed.
|You gain one Healing Potion
|Each party member gains one Healing Potion
|Edge: You speak Hyrallic

if tier1 then
    Witch: Begone!
else
    Witch: Take these, and go.
end

### Search the garden

|Search Test: Intuition (Search, Alertness)
|You lose 3 stamina; nettles
|a small find => You gain 1 Healing Potion
|a great find => You gain 1 Healing Potion. +1 hero token

## Threat: Goblin Scouts (Temporary)

Two goblins shadow the party. They will raise the alarm.

### Ambush them

|Ambush Test: Agility (Sneak, Hide)
|They escape and warn the camp. You begin the encounter surprised
|The threat is vanquished
|The threat is vanquished. You surprise the enemy

Consequence: You begin the encounter surprised

## Round 2
...
```

**Rounds.** `## Round N` opens a round. No round heading = one round. Entries
**persist into later rounds** until taken or vanquished (except `(Temporary)`).
Each hero acts once per round: they approach one entry. When everyone has acted
(or nothing is left) the round ends. After the last round, every unvanquished
threat delivers its consequence.

**Entries.** `## Opportunity: <Name>` or `## Threat: <Name>`, with optional tags
in parentheses after the name, in any combination, e.g. `(Locked, Temporary)`:
- `(Required)` -- never removed by party-size scaling.
- `(Locked)` -- hidden until a clause `unlock <Name>` lands; then appears at
  once if its round has come, else when it does. Never scaled away. A locked
  threat that never unlocks has no consequence.
- `(Temporary)` -- gone at the end of the round it appeared in (for a locked
  entry, the round it unlocked). An unvanquished temporary threat pays its
  consequence at that round's end.

Entry body:
- Paragraphs = the card's description.
- `Options:` paragraph = the approach text.
- `Consequence: <clauses>` (threats) = applied at the end if never vanquished.
  A threat without one warns.

**Options and tests.** `### <Option name>` under an entry is a choice. Its test
is a journal power-roll block:

```
|<Test name>: <Characteristic> (<Skill>, <Skill>)
|<tier 1 text: 11 or lower>
|<tier 2 text: 12-16>
|<tier 3 text: 17+>
|<optional 4th line: critical, a natural 19-20>
|<optional rider lines>
```

- Every line starts with `|`. The header needs a space after the colon.
- Exactly one roll per option, and **it must sit under a `###` heading** or it
  is dropped.
- Characteristic: Might, Agility, Reason, Intuition, Presence (a name anywhere
  in the attr text -- a `|Name: X` line naming none is a rule, not a roll).
  The roll is 2d10 + the characteristic; a hero trained in a listed skill adds
  +2 (Skilled).
- **Skill names must match the game's skill list exactly** (e.g. `Track`, not
  "Tracking"; `Handle Animals`). Check with the toolkit.
- **An option with no roll** -- `|` clause lines and no `|Name: Characteristic`
  header -- is taken without a test: its clauses apply at once. Lines above
  its rules are its own scene; lines below are its outcome scene.
- Tier text is clauses (see the table). Make every tier say something.
- **Every test has a critical** (natural 19 or 20). Leave the 4th line out
  and it is built for you: tier 3's full text plus "The party gains an
  additional hero token." Write a 4th line only when a critical should give
  something different. Players never see the critical tier (stage, roll
  dialog, outcome icons) until one is rolled; then the stage reveals it.

**Teasers.** `|<teaser> => <full text>` on a tier line: players see the teaser
until that tier lands; tiers never reached keep their teaser. Only the full
text is parsed for effects.

**Dice tables in an entry.** A table written anywhere in a montage entry (or
delve obstacle) is that entry's own, rolled by a `roll on <name>` clause in
any of its tiers or rows:

```
|Tinkerer's Wares: 1d6
|1-2: You gain 1 Healing Potion
|3: You gain 1 Black Ash Dart
|6: You gain 2 Healing Potions
```

The roll happens on the host; the party sees "Tinkerer's Wares: rolled 4"
then what the row gave. A table header straight after a roll block ends the
roll block (a blank line between them is still tidier). A `roll on` that
names no table of its entry warns.

**Knacks: riders, secret options, knack versions.** Reward what makes each hero
different. The full vocabulary, the perks the montage plays by their real
rules, and the authoring STANDARD are in `EncounterOfTheWeek/KNACKS_REFERENCE.md`
-- read it before writing a montage. In short:

- **Riders** (lines after the tiers, or under an option with no roll):
  `|<Effect>: <requirement>`. Effects: `Edge`, `Double Edge`, `Bane`,
  `Double Bane`, and `Allow` (aliases `Secret`, `Only`, `Requires`).
  `|Edge (Round 1): ...` counts only in round 1.
- **`Allow` makes the option SECRET**: a hero who does not meet it never sees
  it (nor does anyone watching that hero). It is not shown locked.
- **`#### If <requirement>`** under an option is a KNACK VERSION of it for a
  hero who meets the requirement: `|` clauses with no roll (the knack makes the
  problem moot) or its own `|Name: Characteristic` roll (a better table).
  First knack met wins. Also `#### Instead, if ...:` / `#### Knack: ...`.
- **Requirements** are INTENT, joined by `or`: `you can teleport` (a speed OR
  an ability such as Black Ash Teleport), `you can speak with animals`,
  `you can use telepathy`, `you can go unnoticed`, `you can make light`,
  `you are immune to fire`, `you have fire weakness`, `you have the Lucky Dog
  perk`, `you were a Farmer`, `you were raised in the Wilderness`, `you worship
  Grole the One-Handed`, `you serve the Life domain`, `your kit is Mountain`,
  `you carry a Healing Potion`, `you are small`, `your Wealth is 2 or higher`,
  `your Renown is 2 or higher`, `you speak Zaliac`, `you are a Dwarf`,
  `you are skilled in Track`. Never name a pregen.
- The validator's **Knack coverage** section checks the standard: every test
  has a knack, opportunities have secret options, each pregen meets 3+.

**Companions and assists** need no authoring. When a hero approaches an
entry, other heroes may go along (once a round each). Their knack versions,
secret options and languages count for the turn; edge and bane riders read
only the hero making the test, so if a companion's language should help,
write it as a knack version or a secret option, not as `Edge: you speak X`.
Before a test is rolled, each companion may assist with a listed skill
nobody has used (never the hero's last), adding an edge or bane. So list two
or more skills on a test if you want it assistable.

**Party-size scaling.** Lines directly under `## Round N`:
`<range> Players: -<n> Opportunity, -<n> Threat`, where range is `4`, `4-5`
or `5+` (`Heroes` works too). Every line covering the party size applies,
cumulatively, removing entries at random **from those this round
introduces** (never `(Required)` or `(Locked)` ones). Removal is silent.
Parties are 4-6 heroes: author each round for 6 and trim for 4 and 5.

**Scenes.** A `---` line in an entry (above its first option) ends the card text
and starts a scripted scene; each non-blank line after it is one step:
- `PC` = the approaching hero.
- `Name (Monster) enters` / `appears` / `arrives`; `Name exits` / `leaves` /
  `departs`. The monster (a bestiary name) gives the portrait; a bare `Name`
  must itself be a monster name.
- `Name: text` = speech (PC, or a character who enters in this entry).
  `Name: (in Hyrallic) text` is garbled for anyone whose hero does not speak it.
- Emotes: `Witch is alert` / `alarmed` / `scared`, or `Goblin (scared): text`.
- Narration: any other line.
- Branches: `if <cond> then` ... `elseif <cond> then` ... `else` ... `end`.
  Conditions: `PC speaks X`, `PC is X` (class/ancestry, or `PC is small` /
  `PC is immune to fire`), `PC has X` (anything by name: skill, perk, ability,
  item...), `PC is skilled in X`, `PC can X` (any capability: `PC can fly`),
  `PC was a X` (career), `PC carries X`, `PC worships X`, `PC chose <option>`,
  `tier1`/`tier2`/`tier3`, `crit`, combined with `not`, `and`, `or` and
  parentheses.
- Under an option: lines above its roll are the pre-roll scene, lines below
  are the outcome scene. **Effects apply after the outcome scene is read.**
- Entries without a scene get an automatic intro.

**Scene art.** `[[scene]]` under `# Montage` (or `[[scene:name]]`) sets the stage
backdrop; its image lives on the tag's `RichScene` object (see the toolkit, "Rich tags").
A `[[scene:name]]` directly under a `## Round N` heading (above its entries) is
that round's backdrop from then on: a day scene for round 1, a night scene for
round 2. A scene image may be a video (.webm/.mp4 uploaded as the scene's
image): the stage loops it, muted.

## Delves

A montage option whose body has the line `Delve: <Name>` (and no roll) sends the
hero into `# Delve: <Name>`, anywhere in the script (usually a sub-document):

```
# Delve: Forbidden Tomb

Chest: every 1-2 obstacles

## Obstacle: Collapsing Stair
The steps crumble underfoot.
### Leap across
|Leap Test: Agility (Jump)
|You lose 4 stamina
|You lose 2 stamina
|You clear it

## Obstacle: ...

## Chest
PC pries open a dusty chest.
|Treasure: 1d6
|1-2: You gain 1 Healing Potion
|3-5: You gain 2 Healing Potions
|6: +1 hero token

## Continue
PC peers deeper into the dark.

## Leave
PC turns back toward the light.

## Forced Out
Exhausted, PC staggers out.
```

The whole delve is that hero's one turn; their companions go in with them
(each may assist one obstacle test in the whole delve). They meet random
obstacles (shaped exactly like opportunities); a chest comes due every 1-2
obstacles (dice table rows are clauses; unfound rows read `???`). Then "Press
deeper (lose 1 Recovery)" or "Turn back" (`## Leave` or `## Turn Back`); at 0
Recoveries they are forced out. Deeper is not harder, just more chests.

**In-order delve (a story chain).** For a quest that runs step by step from
one starting point (a rescue: find the trail, descend the gully, climb into the
sinkhole), add the line `Order: in sequence` under the `# Delve:` heading:

```
# Delve: The Lost Boy

Order: in sequence

## Obstacle: Where Did He Go?
...
## Obstacle: Down the Gully
...
## Obstacle: The Sinkhole Cave
...  (the reward goes in this last step's tiers, e.g. +3 hero tokens)

## Continue
PC: He's still out there.

## Turn Back
PC: I can't go any further tonight.

## End
The mother weeps and laughs and hugs everyone.
```

- Obstacles come in the order written, never at random.
- After every step but the last, the `## Continue` scene plays and the hero
  chooses "Press on" (free) or "Turn back".
- `## Chest` is optional (no warning without one).
- Finishing the last step plays `## End` (also `## Finish`) and ends the turn,
  even if that step left the hero on 0 Recoveries.
- A hero on 0 Recoveries before a later step is still forced out.
- Use this instead of a chain of `(Locked)` entries unlocked one by one, which
  spends a different hero's turn on each step.

## Narrative beats

```
# Narrative

[[scene]]

Intro prose for the beat.

## The Crossroads

The road forks beneath a lightning-split oak.

Choose together: which way do you go?

### Take the high road

The ridge path is longer but safer.

|+1 hero token

### Take the low road

## The Shrine

Choose individually:

### Offer a coin

|You gain 1 Healing Potion

### Walk on

## Ambush!

Arrows hiss from the trees. Draw steel!
```

- `## <Section>` sections play in order; a section's own `[[scene:x]]` overrides
  the backdrop while it is up.
- Mode marker paragraph: words like "together", "agree", "as a group" -> one
  vote per **player**; "individually", "each hero", "separately" -> one choice
  per **hero**. Default is together (warns if a section has 2+ options and no
  marker).
- `### Option`: prose is its description; `|` lines are rules text (clauses).
  **No power rolls in narratives.**
- A section with no options gets a Proceed button.
- Together: rules text is aimed at the whole party; a split vote is settled by
  a random voter (with a dramatic flash). Individually: each option applies once
  for the group that took it.
- `Unlock: Intelligence` (a paragraph in a narrative beat or section) turns on
  the Intelligence pool and the Tactical Preparation screen for the rest of the
  game; earn it with `+N intelligence` clauses. With it on, the party starts
  with no enemy Stamina display and can buy it, surprise and trap knowledge
  with Intelligence before the fight.

## The encounter beat

```
# Encounter

Trap: Place 4 Snare Trap objects in Trap zones and delete the other Trap zones.

[[encounter]]
```

- **Setup instructions**, one per line: `<Label>: Place <n> <Object> objects in
  [the] <Zone> zones [and delete the other <Zone> zones]`. The host pools every
  tile of that zone type on the map, picks `n` at random, places the object
  asset (matched by its display name) there, and with the delete clause trims
  the zones to the picked tiles. Missing object or zone: logged and skipped.
  Other prose in the beat is notes.
- Trap zones should be hidden from players; `reveal traps` (or Tactical
  Preparation) reveals them.
- **Bystanders**: `Hostages: Civilian tokens stay out of initiative.` (also
  `... take no turns`, `Civilian 1 and Civilian 2 are bystanders`). Tokens
  already on the map whose name is the given name, starts with "<name> ", or
  whose bestiary type is that name, never join initiative: they take no turns,
  the Monster AI never targets them, and they do not count as monsters to
  defeat. Pair it with an Encounter Script on the `[[encounter]]` (e.g. a
  hostage rescue) for what happens to them.
- **Arranging the heroes**: when the heroes win the initiative (the die, or
  `you win initiative` / `you surprise the enemy`), the fight pauses after the
  Draw Steel banner so players can move their heroes anywhere in the start
  zone (plus zones a `... becomes a starting area` clause unlocked) and press
  Ready (2 minutes at most). A party that loses initiative, or is surprised,
  goes straight in. Nothing to write in the script.
- **Encounter Scripts** on the `[[encounter]]` (the encounter builder's
  Scripts section, or `EncounterScriptInstance` in Lua) run on the EotW host
  and may replace the victory condition and add a defeat condition.
- The **first** `[[encounter]]` island is the start-of-combat fight; its monsters
  spawn behind the stage at their saved positions, scaled to the party size,
  then the stage dissolves and Draw Steel begins.
- **Extra victory**: `Victory: The heroes also win once every Dwarf on the map
  is defeated.` (also `every enemy on the map ...`, `no dwarves are left on the
  map`, `defeat all the monsters on the map`). Victory comes when the
  encounter's own condition is met (an Encounter Script's, or every monster
  defeated) OR when no enemy of that kind is left standing on the map. A
  keyword (`Dwarf`) matches a monster keyword or a word of its bestiary type;
  `enemy`/`monster`/`foe` means every enemy. Bystanders and allies never count,
  and reinforcements still to come do not either: clear the map and the fight
  is won before the next wave arrives.
- **Reinforcements**: a `## Reinforcements: <Name>` section, written AFTER the
  opening `[[encounter]]` and after every setup line (everything below it
  belongs to it until the next `##` or `#`):

  ```
  ## Reinforcements: The Golden Hand

  Arrive: every round from round 2
  Enter: the Reinforcements zone
  Shout: Don't let them get away!
  Shout: After them, lads!

  [[encounter]]

  [[encounter]]
  ```

  - `Arrive:` when they come, at the START of the round (they act that round):
    `round 3`, `rounds 2 and 4`, `rounds 2-4`, `every round`, `every round
    from round 2`, `every other round starting round 3`, `every 2 rounds from
    round 2 until round 6`.
  - `Enter:` the zone type they appear in (paint it in Map Markup -> Zones, keep
    it hidden from players). They fill its free tiles in random order; extras
    spill onto free neighbours. With no `Enter:` they use their island's saved
    positions.
  - `Shout:` lines (any number): one arriving creature (a captain or other
    non-minion first) says one of them at random, as a speech bubble.
  - The section's `[[encounter]]` islands are the groups that arrive. Several
    islands take turns, one per arrival (gunners, then trappers, then gunners
    ...). Build each in the encounter builder: party-size scaling (`Appears:`
    gates and per-size balancing) works exactly as for the opening fight.
  - Several sections may run side by side (a recurring squad plus a boss on
    round 4). A section with no `Arrive:` or no island warns and never comes.
  - `/eotwreinforce` lists what the script will send and what has arrived;
    `/eotwreinforce arrive 1` brings section 1's next group in now.

## Full worked example (master + one sub-document)

Master document `Encounter` (in Map Documents of map `Encounter: The Drowned Bell`):

```
# Town Gate

Fishermen speak of a bell tolling beneath the flooded chapel at Brackwater.
Those who went to look have not come back.

# Narrative

[[scene]]

## The Causeway

The old causeway is half under water. Choose together: how do you cross?

### Wade straight across

|Each party member loses 2 stamina

### Wait for low tide

|You lose initiative

# Montage

[[scene:marsh]]

The chapel looms ahead. You have time to prepare -- but not much.

## Round 1
4 Players: -2 Opportunity
5 Players: -1 Opportunity

[Reed Cutter's Hut]
[Sunken Shrine]
[Heron Watch]
[Drowned Graves]
[Bog Lights]
[Smugglers' Cache]
[The Tolling]

## Round 2

[Flooded Nave]
[Bell Ringers]

# Encounter

[[encounter]]

# Conclusion

The bell falls silent. Brackwater sleeps soundly for the first time in a month.

# Defeat

The tolling goes on, and now it calls your names.
```

Sub-document `The Tolling` (same folder):

```
## Threat: The Tolling (Required)

Each toll of the bell draws something closer from the deep.

### Muffle the bell

|Muffle Test: Might (Lift, Climb)
|The bell rings louder. You lose 3 stamina
|The threat is vanquished
|The threat is vanquished. {+1 hero token}
|Allow: you are skilled in Climb or Lift

Consequence: You begin the encounter surprised
```
