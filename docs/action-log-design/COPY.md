# History: wording for sign-off

**Status 2026-10-27:** all signed off, including Round 2 (James: "Yes, those work"). Applied to
the prototype the same day. Signed off as listed: N1 (History), N2, T, C (except C4), S, M, E.

Every user-facing string in the prototype, grouped by surface. Reply with the IDs you want
changed; anything not called out is signed off. Ability and trigger names in [brackets] are
content, not wording. Rules applied: Hero and Stamina capitalised; condition names
capitalised as names ("Slowed ended"), lower case inside sentences ("is slowed"); no
pronouns for creatures (names instead).

## Three calls first

**N1. The feature's name.** Recommended: **History**. It is the word on the radial slot,
the hero card chip and the tray, and it says what it holds without "log" (a text dump, the
thing being replaced). Alternatives: keep "Action Log" (familiar to today's users);
"Combat History" (wrong outside combat: tests, montages, negotiation). If History: the old
name appears once in the rail tooltip for a release, "History (was Action Log)".

**N2. "What happened" sentences.** One sentence per creature, past tense, the result first:
| ID | Pattern | Example |
|---|---|---|
| W1 | {Creature} took {N} damage. | Monster Test 1 took 11 damage. |
| W2 | {Creature} took {N} {type} damage. | Dwarf Fury took 4 fire damage. |
| W3 | ... damage: {split}. | Test Monster Z 1 took 8 damage: 4 fire and 4 cold. |
| W4 | ..., was pushed {N} square(s) and is now winded. | Reactor 1 took 7 damage, was pushed 1 square and is now winded. |
| W5 | ... and is {condition} ({duration}). | ... and is slowed (save ends). / ... slowed until the end of its turn. |
| W6 | ... and resisted being {condition}. | Polder Elementalist took 4 fire damage and resisted being slowed. |
| W7 | ... It was not {condition}. (immune) | It was not frightened. |
| W8 | {Creature} took {N} damage and was killed. | Monster Test 1 took 17 damage and was killed. |
| W9 | {Squad} took {N} damage: {k} of {m} minions killed. / ... the squad is destroyed. | Goblin Warriors took 5 damage: 1 of 4 minions killed. |
| W10 | {Creature} took {N} damage from {k} minion(s). | Dwarf Fury took 6 damage from 2 minions. |
| W11 | {Creature}, an ally, was caught in the burst and took {N} damage. | |
| W12 | {Creature} regained {N} Stamina [and is no longer {condition}]. | Zakaarior regained 8 Stamina and is no longer grabbed. |
| W13 | {Owner}'s {trigger} then hit {Creature} for {N} {type} damage. | Reactor 1's [Reactor trigger] then hit the Wode Elf Troubadour for 2 fire damage. |
| W14 | {Creature} gained {N} {resource}. | Human Null gained 1 Discipline. |
| W15 | ... pushed {N} squares off {place}, it fell {N} squares. | Test Monster Z 1 took 14 damage: pushed 3 squares off the gallery, it fell 4 squares. |

**N3. "Why" lines.** A short contrast, then one plain sentence: **{lead}** / {reason}.
Only what moved the result away from the plain roll.
| ID | Lead | Reason (example) |
|---|---|---|
| Y1 | Tier 1, not Tier 2 | Reactor 1's trigger added a bane when it was targeted, cancelling one of three edges. |
| Y2 | {Name}: Tier 1, not Tier 2 | The Fury had cover, a bane against that target only: 13 - 2 = 11. |
| Y3 | 7, not 9 | Reactor 1 has damage immunity 2. |
| Y4 | 4 fire, not 7 | Test Monster Z 1 has fire immunity 3. The 7 includes +1 from [Elementalist feature] on Fire abilities. |
| Y5 | +4 from surges | Two surges from the bank. / One from the bank, one from Trained Assassin (lost if not used on this strike). |
| Y6 | +4 from the Mark | High Elf Tactician's Mark triggered when the strike hit. |
| Y7 | 14, not 8 | The fall added 6. Hover here for the side view. |
| Y8 | Prone | Two surges raised the potency from A<1 to A<2, so Reactor 1 could not resist. (Agility 1 shown only once Monster Info reveals it) |
| Y9 | Fury slowed / Elementalist not slowed | R<1: the Fury's Reason 0 could not resist. / R<1: the Elementalist's Reason 2 resisted. |
| Y10 | Not frightened | Test Monster Z 1 is immune to frightened. |
| Y11 | Triggered | Reactor 1's trigger answered the strike on its ally ([trigger condition]). |
| Y12 | Hit an ally | The burst catches every creature in the area, allies included. |
| Y13 | 1 minion, not more | Each minion in this squad has 5 Stamina, so 5 damage kills one. |
| Y14 | Grabbed ended | Healing Grace ends one condition. |
| Y15 | Discipline +1 | The Null gains Discipline when an enemy spends Malice. |
| Y16 | (nothing moved it) | Nothing changed the result: a straight roll. |

## Everything else (sign off as a block)

### Tray
| ID | Where | Text | Note |
|---|---|---|---|
| T1 | Title | History | |
| T2 | Titlebar on hover | History · {map name} | |
| T3 | Tooltips | Minimise / Take the tray off the table | |
| T4 | Expand button | Show all / Show less | change: was "Full log" / "Smaller" |
| T5 | Round heading | Round {n} · right, Director only: Malice {before} to {now} | changed 2026-11-06: no arrow in the Codex fonts; players see no Malice here (gap 4) |
| T6 | Folded turns | Turns {a}–{b} | turn numbers kept (2026-11-04) |
| T7 | Turn heading | {Creature} · Turn {n} · Hero turn / Enemy turn / Enemy turn · {n} minions | turn numbers kept (2026-11-04) |
| T8 | Turn markers | Main / Maneuver / Move | |
| T9 | Marker | New since you last looked | change: was "New since you looked", now matches M1 |
| T10 | Banner | Draw Steel! · Heroes go first (rolled {n}) | Enemies go first when they win |
| T11 | Action type | Main action / Maneuver / Free strike / Triggered action | |
| T12 | Chips | Edge / Double edge / Bane / Double bane / Cancelled out / {n} surges / {n} surges: potency +1 / {n} Malice / {n} {Heroic Resource} / Critical / Hit an ally | |
| T13 | Ally group | Ally hit | |
| T14 | Captions | Push {n} / Push {n} · fell {n} / Winded / Dying / Killed / {k} of {m} killed / Squad destroyed / {n} minions / Cover: bane / {n} fire, {n} cold / Fire immunity -{n} / Fire weakness +{n} / {n} soaked by temporary Stamina / Resisted / Immune to frightened / {Condition} + Ended tag | changed 2026-11-06: was "Grabbed ended"; change: "Immune: frightened" -> "Immune to frightened", "Ended Grabbed" -> "Grabbed ended" |
| T15 | Trigger rows | Before the roll / After the roll / Triggered / Free · {Owner} · {trigger} › {result} | One line (James, 2026-11-07): the result goes after a caret (a portrait and amount, "Clarity +1", "Prone"); a long name shortens with "…" and shows whole on hover |
| T16 | Turn lines | {Resource} +{n} · Start of turn ({die}) / saved against {Condition} · End of turn: rolled {n} ({target} or more ends it) / {Condition} + Ended tag · End of turn / ... · {cause} | see Round 4 |
| T17 | Hidden roll (Director only) | Director rolled {dice} · Hidden from players | |
| T18 | Player view | Unknown creature | hidden monsters |
| T19 | Row tooltip | Open the detail | |

### Detail card
| ID | Where | Text |
|---|---|---|
| C1 | Header | {Creature} · {Ability} / {Action type} · Round {n}, turn {n} |
| C2 | Sections | What happened / Why / The numbers |
| C3 | Numbers | Power roll / Dice / {Characteristic} / Edge ({n} edges, {n} bane) / Total / Tier {n} / Their roll / Taken / Regained / Triggered / Cost: {n} Malice |
| C4 | Numbers notes | Three edges count as two; the bane cancels one. / Without the bane: double edge, Tier 2. / One roll for the whole squad. |
| C5 | Sources | Flanking, with {Creature} / {Creature} is prone (melee) / High ground / Cover / {Owner}'s {trigger} when targeted / set by hand |
| C6 | Footer | Rolled by {player} · {time} / Director · {time} |
| C7 | Close | Close the detail (tooltip) |

### Search
| ID | Where | Text |
|---|---|---|
| S1 | Placeholder | Search creatures, abilities, conditions |
| S2 | Suggestion groups | Creatures / Abilities / Conditions / Other |
| S3 | Other words | Killed / Winded / Triggered / Surges / Malice / Pushed / Fell / Immunity / Resisted / Critical |
| S4 | Count | {n} matches / 1 match |
| S5 | No results | Nothing matches "{search}". (changed 2026-11-05, fix B8: search also covers the previous encounter) |
| S6 | Tag | Active / Ended (Ended added 2026-11-06, grey, the partner of Active) |
| S7 | Tooltips | Clear the search / Remove {chip} |

### Minimised History
| ID | Where | Text |
|---|---|---|
| M1 | Hover header | Since you last looked |
| M2 | Hover lines | the "What happened" sentences (N2) |
| M3 | Hover overflow | and {n} more turns / and 1 more turn |
| M4 | Hover footer | Click to open |
| M5 | Hover, nothing new | Nothing new since you last looked. |
| M6 | Screen reader | History, {n} new turns |
| M7 | Setting | History notifications: On / Off |

### Ways in
| ID | Where | Text |
|---|---|---|
| E1 | Radial slot (any token) | History |
| E2 | Hero card chip tooltip | History |
| E3 | Rail button | History (was Action Log) for one release, then History |

## Round 2: James's four changes (signed off 2026-10-27)

Draw Steel's own wording (Heroes book): you **gain** and **spend** surges; each surge spent
deals **extra damage equal to your highest characteristic score**; two or more edges make
a **double edge**; "a double edge and just one bane, the roll is made with one edge,
regardless of how many individual edges contribute"; a creature **uses a triggered
action**, and every triggered ability has its own **Trigger:** line.

**R1. Why lines: the cause first, then what it did (replaces "X, not Y").** The lead names
the rule or source in Draw Steel's words; the sentence says what changed, with "instead
of" where a number moved.
| ID | Lead | Sentence |
|---|---|---|
| Y1 | Bane from Reactor 1's [Reactor trigger] | It cancelled one of three edges, so the roll stayed at Tier 1 instead of Tier 2. |
| Y2 | Cover | A bane on the roll against the Fury only: 13 - 2 = 11, Tier 1 instead of Tier 2. |
| Y3 | Damage immunity 2 | Reactor 1 took 7 damage instead of 9. |
| Y4 | Fire immunity 3 | Test Monster Z 1 took 4 fire damage instead of 7. The 7 includes +1 from [Elementalist feature] on Fire abilities. |
| Y5 | Spent 2 surges | Each dealt 2 extra damage (the Fury's highest characteristic, Might 2). |
| Y5b | Spent 2 surges | Each dealt 2 extra damage (Agility 2). One was gained from Trained Assassin and could only be spent on this strike. |
| Y6 | Marked by the High Elf Tactician | The strike dealt 4 extra damage. |
| Y7 | Fell 4 squares | The fall dealt 6 damage, for 14 instead of 8. Hover here for the side view. |
| Y8 | Potency raised with 2 surges | A<1 became A<2, so Reactor 1 could not resist being knocked prone. |
| Y9 | Reason 0 / Reason 2 | R<1: the Fury could not resist being slowed. / R<1: the Elementalist resisted. |
| Y10 | Immune to frightened | Test Monster Z 1 cannot be frightened. |
| Y12 | Area ability | The burst hits every creature in the area, allies included. |
| Y13 | Minions | Each minion in this squad has 5 Stamina, so 5 damage killed one. |
| Y14 | Healing Grace | It ends one condition: grabbed. |
| Y15 | Discipline | The Null gains 1 Discipline when an enemy spends Malice. |
| Y16 | (nothing changed it) | Nothing changed the roll or the damage. |

Alternative: no lead, one full sentence each ("Reactor 1's damage immunity 2 reduced the
damage from 9 to 7."). Easier to read once, slower to scan, and the bold lead is also what
search marks.

**R2. Surges without "the bank".**
| ID | Where | Text |
|---|---|---|
| Y5 | Why | as R1 above |
| C3s | The numbers | Spent 2 surges (Might 2 each) .......... +4 |
| T12s | Chip | 2 surges (unchanged) |

**R3. Triggered actions in Draw Steel's words (replaces Y11).** The lead says who used which
triggered action; the sentence quotes that ability's own Trigger line, which answers
"what set it off" in the rules' words.
| ID | Lead | Sentence |
|---|---|---|
| Y11 | Reactor 1 used a triggered action | Trigger: {the ability's Trigger text}, e.g. "An ally within 2 squares is targeted by a strike." |
| Y11f | Human Null used a free triggered action | Trigger: {text} |

**R4. The edge rule note (C4).**
| ID | Where | Text |
|---|---|---|
| C4 | Under the edge and bane sources | A maximum of two edges count (a double edge); with one bane, the roll is made with one edge. |
| C4b | Two or more banes | A maximum of two banes count (a double bane); with one edge, the roll is made with one bane. |
| C4c | Edges and banes cancel | Edges and banes cancel out: the roll is made without either. |

## Round 3: wording signed off 2026-11-05

**H1. The ongoing effect editor's new checkbox.** Sits with "Hidden on token" and "Hidden
from enemies"; marks pure markers so History leaves them out (REVIEW.md gap 1).
| ID | Where | Text |
|---|---|---|
| H1 | Checkbox label | Hidden from History |
| H1t | Its tooltip | If this is checked, History won't show this effect starting or ending. Use it for markers that only track rules. It still appears in menus, so it can be removed by hand. |

**H2. New rows while scrolled up (fix B3).**
| ID | Where | Text |
|---|---|---|
| H2 | Marker at the bottom of an open tray scrolled away from the newest rows; counts new rows; click jumps down | {n} new below (e.g. "3 new below") |

## Round 4: new lines (2026-11-06)

**Changed numbers (signed off).** The Codex's label fonts have no arrow, and carets read like a sum
when tried in the prototype ("Malice 6 up 5" looked like 11). Every changed number uses one pattern
with no glyph and no colour: {before} to {now}.
| ID | Where | Shows |
|---|---|---|
| L0 | Any changed number | temporary Stamina 3 to 10 / Malice 4 to 9 / Stamina 22 to 13 |

**Group 1: results with no action behind them (signed off).** The creature in bold, the cause on
the small line under it, as T16.
| ID | What | Line | Cause line |
|---|---|---|---|
| L1 | Damage | {Creature} took {n} [{type}] damage | {cause} |
| L2 | Damage at the start of a turn | {Creature} took {n} [{type}] damage | Start of turn: {cause} |
| L3 | Healing | {Creature} regained {n} Stamina | {cause} |
| L4 | Temporary Stamina | {Creature} temporary Stamina {before} to {now} | {cause} |
| L5 | A condition | {Creature} is {condition} ({duration}) | {cause} |
| L6 | A resource | {Creature} gained {n} {resource} | {cause} |

**Group 2: effects ending (signed off).** The name and the status are kept apart by an Ended tag, the
partner of Active.
| ID | What | Line | Cause line |
|---|---|---|---|
| L7 | One effect | {Creature} {Effect} + Ended tag | End of turn |
| L8 | Several together | {Creature} {Effect} and {effect} + Ended tag | End of turn |
| L9 | A save | {Creature} saved against {Condition} | End of turn: rolled {n} ({target} or more ends it) |
| L10 | A failed save | {Creature} failed a save against {Condition} + Active tag | End of turn: rolled {n} ({target} or more ends it) |
| L11 | Something else ended it | {Creature} {Effect} + Ended tag | {what ended it} |
| L12 | Ended by dying | {Creature} {Effect} + Ended tag | {Creature} is dying |
| L13 | Persistence broken | {Creature} stopped maintaining {ability} | Took {n} damage in one turn |
| L14 | Persistence by choice | same | Chose to stop |
| L15 | Persistence, targets gone | same | All its targets are dead |
| L16 | Persistence Why (card) | Persistent Magic | {n} damage in one turn is 5 times Reason {r}. |
| L17 | End of the encounter | Encounter ended | Round {n}; the card lists what ended, by creature |

**Group 3: winded, dying, death and Malice (signed off).** When an action caused these they stay as
the T14 captions; these are for when one didn't. Recovering uses the rules' words, not the Ended tag,
because "Dying Ended" could read as the creature died.
| ID | What | Line or caption | Cause line |
|---|---|---|---|
| L18 | Recovering, on a heal | caption: No longer winded / No longer dying | |
| L19 | Winded, no action | {Creature} is winded | {cause} |
| L20 | Dying, no action | {Creature} is dying | {cause} |
| L21 | Killed, no action | {Creature} was killed | {cause} |
| L22 | Minions, no action | {Squad} {k} of {m} minions killed | {cause} |
| L23 | Malice from a trait (Director only) | {Creature} Malice {before} to {now} | {trait} |
| L24 | Malice set by hand (Director only) | Director Malice {before} to {now} | Set by hand |

**Group 4: what players see, and grouped results (signed off).**
| ID | What | Wording |
|---|---|---|
| L25 | Y13 when players don't know minion Stamina | Minions / {n} damage was enough to kill one minion. |
| L26 | Resisting, monster's number unknown to players | Knocked prone: it did not resist |
| L27 | Secret modifier, players | Edge from [blacked-out bar] |
| L28 | Secret modifier, Director | Edge from {name}, eye icon, tooltip: Hidden from players |
| L29 | Identical results, different names | {A}, {B} and {C} each took {n} damage. |
| L30 | Identical results, numbered creatures | {Creatures} {a}-{b} each took {n} damage. |
| L31 | Grouped total in the numbers | Taken, each |
| L32 | Prompted trigger's cause (Why) | {Trigger} / It let {Creature} {what it let them do}. |
| L33 | Free strike's cause (Why) | Moved away without shifting / {Creature} moved away from {Creature}, who made a free strike against it. |

**Group 5: small labels (signed off, so the wording round is complete).**
| ID | What | Wording |
|---|---|---|
| L34 | Way back when the card opens inside the tray | < Back (single guillemet, in the fonts) |
| L35 | Side-view button tooltip | Side view |
| L36 | Side-view button, screen readers | Side view and path on the map |
| L37 | David's preview, setting name | History Sidebar Preview: On / Off |
| L38 | David's preview, setting tooltip | Briefly shows each action beside the History button while History is closed or minimised. |

**Decision 4 wording (signed off 2026-11-06).**
| ID | What | Wording |
|---|---|---|
| L39 | Tag on a reverted row | Reverted |
| L40 | Line at the moment of the revert | Turn reverted / By the Director or By {player} |
| L41 | Director's right-click in History | Hide from players / Reveal to players / Delete entry / Clear History |
| L42 | Resource line button | Undo |

**Decision 5 wording (signed off 2026-11-06).**
| ID | What | Line | Cause line |
|---|---|---|---|
| L43 | Heading between encounters | Out of combat | |
| L44 | A test | {Creature} rolled {n} | {Characteristic} test · Tier {n} |
| L45 | A Dice panel roll | {Creature} rolled {n} | {dice} |

## Round 5: wordings the stage 1 build needed (signed off 2026-11-06)

| ID | What | Draft |
|---|---|---|
| D1 | Duration on a condition badge or line | (EoT) / (EoE) / (save ends) |
| D2 | Cause line when something lapses as the round ends | End of round |
| D3 | An effect that isn't a condition, no action | {Creature} {Effect} ({duration}) |
| D4 | A save rolled outside the end of a turn | Rolled {n} ({target} or more ends it) |
| D5 | A resource spent, no action | {Creature} spent {n} {resource} |
| D6 | Hero Tokens, shared by the party | {Resource} {before} to {now} |
| D7 | Forced movement under a target | Push {n} / Pull {n} / Slide {n} / Vertical push {n} / Vertical pull {n} |
| D8 | With a fall, or only a fall | Push {n} · fell {m} / Fell {m} |
| D9 | Forced movement, no action | {Creature} was pushed {n} squares, it fell {m} squares |
| D10 | A creature landed on, on the push's row (signed off 2026-11-07) | Landed on |
| D11 | Cause when a creature landed on it, no push (signed off 2026-11-07) | Landed on by {Creature} |

## Round 6: wordings the detail card needs (signed off 2026-11-07)

N2 covers most sentences. These are the cases it doesn't cover, as built in chunk 2.1.
| ID | What | Draft |
|---|---|---|
| X1 | An effect that isn't a condition | {Creature} took 3 damage and gained {Effect} until the end of its turn. |
| X2 | An effect ended (a condition keeps W12) | ... and {Effect} ended. / {Creature}'s {Effect} ended. |
| X3 | A creature landed on | ... took 10 damage and was landed on. |
| X4 | Temporary Stamina took some of it | ... took 7 damage, 3 of it to temporary Stamina. |
| X5 | Temporary Stamina grew | {Creature}'s temporary Stamina went from 3 to 10. / ... and temporary Stamina went from 3 to 10. |
| X6 | A fall with no push | ... took 6 damage and fell 4 squares. |
| X7 | Resisted, the rule text names no condition | ... took 4 damage and resisted. |
| X8 | Damage partly typed | ... took 10 damage: 6 fire and 4 untyped. |
| X9 | W11 for any area, not only a burst | {Creature}, an ally, was caught in the area and took {N} damage. |
| X10 | A trigger that did more than damage (W13 covers damage) | {Owner}'s {trigger}: {sentence} |
| X11 | An action that changed nothing | {Creature} used {Ability}. |
| X12 | C6 with no roll behind it | {player} · {time} |
| X13 | L30, no plural | Goblin 1-4 each took 6 damage. |

Two N2 changes the data forces:
- W15 loses "off {place}": nothing records the ledge's name, so it reads "pushed 3 squares, it fell 4 squares."
- EoE stays out of sentences: the Codex also stores "no timer" as EoE, so a fall's Prone would read
  "until the end of the encounter" when it ends on standing up. The tray keeps its (EoE) (D1).

## Round 7: wordings the numbers need (signed off 2026-11-07)

The receipt (chunk 2.2) uses C3, C3s, C4/C4b/C4c and T12 as signed. These are the cases they don't cover.
| ID | Where | Text |
|---|---|---|
| Z1 | A target's own edges or banes | {Edge / Double edge / Bane / Double bane} for this target |
| Z2 | A damage line | Tier 2 / Tier 2: fire (two types give two lines) |
| Z3 | The value beside a double edge or double bane | +1 tier / -1 tier |
| Z4 | Total for grouped targets (as in X13) | Taken, each |
| Z5 | Immunity or weakness | Damage immunity 2 / Fire immunity 3 (the Why leads) / Fire weakness 3 |
| Z6 | A flat roll bonus with no name behind it | Bonus |
| Z7 | A Heroic Resource cost | Cost: {n} {Heroic Resource}, e.g. Cost: 3 Ferocity (C3's pattern) |

## Round 8: the edge and bane sources (signed off 2026-11-08)

C5 as signed needs facts the Codex doesn't record (who you flank with, whether a strike was melee). The
receipt names each source as the roll dialog's badge did when the roll was made, so History repeats what
the player saw. This replaces C5.
| ID | Source | Text |
|---|---|---|
| C5 | A modifier | its badge name: Flanking / High Ground / Cover / Prone / Target is {name} |
| C5t | Another creature's trigger | {Owner}'s {trigger}, e.g. Reactor 1's Test 5 |
| C5h | The dialog's edge and bane buttons | Set by hand |

## Round 9: removed edges and banes (signed off 2026-11-08)

Ignore Edges, Ignore Banes, Remove Edge, Remove Bane and the removing half of Edge becomes Bane are listed
too, so the card explains an edge that was there but did not count. When a side loses every edge or bane,
its line and each source under it are crossed out, with the reason once, after the line, in the muted aside style
(James, 2026-11-08: "real visual feedback on it being ignored"). When it loses only some, nobody knows
which, so the remover gets its own muted line last, with no arrows.
| ID | Where | Text |
|---|---|---|
| C5i | The line when every edge or bane was taken away | ~~Edge~~ Ignored by {name}, its value (+2, +1 tier, -2, -1 tier) crossed out and muted; each source under it crossed out with no reason (~~Prone~~), since the reason is the whole line's; on a target's own roll, ~~Edge for this target~~ |
| C5r | The reason, or the remover's own line when only some were removed | Ignored by {name} (Ignore) / Removed by {name} (Remove one); several join: Ignored by X, removed by Y |
| C5o | A remover that belongs to the target | {Target}'s {name}, e.g. Ignored by Ajax's Steadfast; the target's face shows only on a remover's own line, not in an inline reason |

## Round 10: the Tier line split (signed off 2026-11-08)

A target's sum lists what made its damage, in the order it applied: the tier's own damage (characteristic
included), the kit, the roll dialog's damage modifiers, then surges, then immunity or weakness and Taken.
Each addition comes off the damage type it was added to. Entries written before this keep one Tier line.
| ID | Where | Text |
|---|---|---|
| K1 | A kit's damage bonus | {Kit} kit, e.g. Panther kit .......... +2 (one line per kit) |
| K2 | A damage modifier from the roll dialog | its badge name, as C5 / C5t: Mark, {Owner}'s {trigger} with the owner's face .......... +4 |
| C3s | Surges spent on damage | the surge bolt, Spent 2 surges, then (Might 2 each) muted .......... +4; a tie for highest names the first in sheet order |

## Round 11: the Why lines History can write now (signed off 2026-11-08)

General forms of R1's examples, for 2.3c-1. Each line is a bold lead with one sentence under it and a
thin rule on its left, between What happened and The numbers. A line that applies to several targets
is written once, naming them as What happened does (L29, L30). Order: area, modifiers, surges, immunity,
condition immunity. Y14 is not built (What happened already says the condition ended); Y2 moves to
2.3c-3 with Y1; Y4's second sentence is dropped (The numbers lists the parts just below).
| ID | Lead | Sentence |
|---|---|---|
| G1 | Damage immunity 2 / Fire immunity 3 / Fire weakness 3 (Z5) | {Target} took {landed} {type} damage instead of {before}. |
| G2 | Spent 2 surges / Spent 1 surge | Each dealt 2 extra damage (Dwarf Fury's highest characteristic, Might 2). One surge: It dealt ...; typed: extra fire damage; several targets: ... damage to {Target} (...). |
| G3 | the modifier's badge name (Mark; High Elf Tactician's Mark with the owner's face) | It dealt 4 extra damage. Lowered: It took 2 off the damage. Several targets: ... to {Target}. |
| G4 | Area ability (only when an ally was hit) | It hits every creature in the area, allies included. |
| G5 | Immune to {condition} | {Target} cannot be {condition}. Prone reads knocked prone. |
| G6 | (none, muted italics) | Nothing changed the roll or the damage. Only when the action rolled or dealt damage and had no edges, banes, extra damage or immunity (a kit is the hero's normal damage). |

## Round 12: triggers and typed messages in Why (signed off 2026-11-08)

The Why says that a trigger fired and what it changed; its rules sit behind a hover on its name (2.3d:
a dotted underline, the trigger's card; a monster's trigger shows its card to the Director only). This
replaces R3 (Y11: "used a triggered action" / "Trigger: ..."); whether it cost a triggered action shows
on its card. A trigger that changed the roll (an edge or bane) is 2.3c-3's, with the tier comparison,
e.g. "Conduit's Word of Guidance / It gave an edge, which moved the roll from Tier 1 to Tier 2."
| ID | Lead | Sentence |
|---|---|---|
| G7 | {Owner}'s {trigger}, with the owner's face | Triggered by this action: {what it did, in What happened's words}, e.g. Lv2 Human Null gained 1 Discipline. |
| G7a | {Owner}'s trigger, when the trigger's name is its rule text (ends in a full stop, or runs past 40 characters; James 2026-11-08) | as G7; the rule shows on the hover |
| G8 | (none) | A note typed on the action's steps or its triggers' steps, as written, in normal text; each once; skipped when it only repeats the ability's name. |

## Round 13: the tier comparisons (signed off 2026-11-08)

History recomputes the tier with a side of the roll taken away, by the roll's own rules
(RollUtils.DiceResultToTier), and says what each side did. One Why line per side: edges, banes, what
ignored or removed them, and each tier modifier; roll lines come first in the Why. Leads name the
sources as The numbers does (C5, C5t, C5h), joined with "and". Replaces Y1's and Y2's wordings. A
roll whose recomputed tier doesn't match the recorded one (a row from before this) gets no tier lines.
| ID | Where | Text |
|---|---|---|
| G9 | Why, edges or banes that changed the tier | It gave an edge (a double edge / a bane / a double bane), which moved the roll from Tier 1 to Tier 2. Several sources: They gave ... |
| G9s | Why, edges or banes that didn't | It gave an edge; the roll stayed at Tier 2. |
| G9r | Why, what ignored or removed them | It ignored an edge (a double edge), ... / It removed an edge, ... with G9's or G9s's ending |
| G9t | Why, a target's own edges or banes (target-only sources) | It gave a bane against Reactor 1, which moved that roll from Tier 2 to Tier 1. / ...; that roll stayed at Tier 2. |
| G10 | Why, tier modifiers | Tier Up: It raised the roll a tier, from Tier 1 to Tier 2. Tier Down: It lowered the roll a tier, from Tier 3 to Tier 2. Tier 3: It made the roll Tier 3 instead of Tier 1. Tier 1: It made the roll Tier 1 instead of Tier 2. Not Tier 3: It kept the roll from Tier 3: Tier 2 instead. Not Tier 1: It lifted the roll off Tier 1: Tier 2 instead. Unchanged: ...; the roll stayed at Tier 3. |
| G11 | Why, a natural 19 or 20 that changed the tier | Natural 19 / A natural 19 or 20 is always Tier 3, so the roll is Tier 3 instead of Tier 2. |
| Z8 | The numbers, a tier modifier (after the edge and bane lines; a trigger's with its owner's face) | {name} .... Tier 3 / Tier 1 / +1 tier / -1 tier / not Tier 3 / not Tier 1 |
