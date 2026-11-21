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
| M5 | Hover, nothing new | (retired 2026-11-12, James: with nothing new the button shows only its name label) |
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
| L38 | David's preview, setting tooltip | Briefly shows actions from other turns beside the History button while History is closed. (Revised 2026-11-13: History does not minimise; only other turns show.) |

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
| X7a | Resisted, the rule text names an ongoing effect, no condition (signed 2026-11-20) | ... took 10 damage and resisted Can't Hide. |
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

## Round 11: the Why lines History can write now (signed off 2026-11-08; G1-G3 replaced by Round 17)

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
the brackets are the cue, per Round 15's hover note; the trigger's card; a monster's trigger shows its card to the Director only). This
replaces R3 (Y11: "used a triggered action" / "Trigger: ..."); whether it cost a triggered action shows
on its card. A trigger that changed the roll (an edge or bane) is 2.3c-3's, with the tier comparison,
e.g. "Conduit's Word of Guidance / It gave an edge, which moved the roll from Tier 1 to Tier 2."
| ID | Lead | Sentence |
|---|---|---|
| G7 | {Owner}'s {trigger}, with the owner's face | Triggered by this action: {what it did, in What happened's words}, e.g. Lv2 Human Null gained 1 Discipline. |
| G7a | {Owner}'s trigger, when the trigger's name is its rule text (ends in a full stop, or runs past 40 characters; James 2026-11-08) | as G7; the rule shows on the hover |
| G8 | (none) | A note typed on the action's steps or its triggers' steps, as written, in normal text; each once; skipped when it only repeats the ability's name. |

## Round 13: the tier comparisons (signed off 2026-11-08; G9-G11 replaced by Round 14)

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

## Round 14: one tier line per roll (signed off 2026-11-08)

James 2026-11-08: the Why is a sum, not an explainer line per part. One line per roll says where it
landed and what got it there, worked out for all its parts together (each part alone gave
contradicting claims). "From" is the tier the dice and characteristic gave alone. The line names the
parts on the side the tier moved, and the other side only when it changed where the roll landed. A
rule that sets the tier outright (Tier 3, Tier 1, a natural 19 or 20) is named alone. Live check 2026-11-10: a part that did nothing against the other side (an edge Twisted ignored) is not named on a side that moved the tier; what took edges or banes away leads the ", but" clause so its "it" sits next to them. A target with a
roll of its own gets its own whole line, merged with targets that read the same; one that reads like
the main roll's is left out. No line when nothing moved or held the tier, or when the recorded parts
don't come to the recorded tier. Worked out when the card opens (James 2026-11-08), so fixes reach old rows.
| ID | Where | Text |
|---|---|---|
| G12 | Why lead | Tier 3, up from Tier 2 / Tier 1, down from Tier 2 / Tier 2, not Tier 3 (something held a move) / Tier 2 (both sides would have moved it) / Tier 3 against Gwynhyvyr, up from Tier 2 (a target's own roll) |
| G12a | Why text, the parts | {names} gave an edge / a double edge / a bane / a double bane; {name} raised it a tier / lowered it a tier / made it Tier 3 / made it Tier 1 / kept it from Tier 3 / kept it off Tier 1; {name} added 2 to the roll / took 2 off the roll; a natural 19 or 20 is always Tier 3 |
| G12b | Why text, what took edges or banes away | after the edges it took were named: {name} ignored it / removed it / removed one; otherwise: {name} ignored an edge / removed a bane |
| G12c | Why text, joining | parts joined with ", and" (A, B, and C); the other side after ", but ". e.g. Prone gave an edge, but Twisted ignored it. |
| G12d | Why text, set by hand (signed off 2026-11-10) | An edge was set by hand. / Prone gave an edge, and another was set by hand. |
| Z9 | The numbers, a modifier's flat bonus (after the edge and bane lines, with Z8; a trigger's with its owner's face) | {name} .... +2 / -2. The "Bonus" line under the characteristic keeps only what no modifier accounts for. |

## Round 15: names in the Why (signed off 2026-11-10)

James 2026-11-10: a source named "Target is Restrained" read as words, not a name, in "Target is
Restrained gave an edge". Marking the name fixes it without changing the prose. Compared live: a tinted
chip (flush and padded), bold, small caps, italic, gold. Small caps chosen first; James then compared
small caps with square brackets on the busy card (2026-11-10) and chose brackets: they show where a
many-word name starts and ends, and in many games a bracketed name is one you can hover.
| ID | Where | Text |
|---|---|---|
| G13 | Why, every rule or ability name (the tier line's parts, a modifier's lead, a trigger's lead) | The name in square brackets; its owner stays outside: [Prone] gave an edge. / Dwarf Fury's [Twisted]. "Set by hand" and the plain "Trigger" lead are not names. The numbers keeps names plain. |

Hover (James 2026-11-10, chosen over an underline at rest on a busy live render): the name's mark alone
(now the brackets) is the cue that a name can be hovered; every name with something to show hovers. The underline appears
only under the name the pointer is on (the text engine draws no dotted underline). A modifier's hover
shows the text the roll dialog's own hover showed (its name and description, formulas filled in for
the roller, "Inflicted by"), recorded at the roll, each distinct text stored once per map; a
trigger's shows its card. Names recorded before this have nothing to show and don't hover. Built in 2.3d.

## Round 16: a target's line says only what differed (signed off 2026-11-10)

James 2026-11-10: on a busy card every target's line repeated the roll's parts. Only modifiers that
applied are ever named (the dialog records only the modifiers that were on, and only what each changed),
and a modifier is never named for a target it didn't apply to. The roll's line names what applied to
every target; a target gets a line only when something that applied to it alone changed its tier, and
that line names only those things. With no roll line (nothing shared moved the tier), "from" is the
dice alone. When every target's own parts moved it, the roll's line keeps a tier no target ended on:
it is what the roll did before anything about a target.
| ID | Where | Text |
|---|---|---|
| G14 | Why lead, a target's line | Tier 2 against Goblin 1, down from Tier 3 ("from" is the roll line's tier) |
| G14a | Why text, what differed | only that target's own parts: COVER gave a bane. |
| G14b | Why text, a remover of the roll line's edges or banes | Goblin 2's CAST AWAY ALL HOPE ignored the double edge. / ignored the edge / ignored one edge / removed the bane |

## Round 17: one damage line that sums it up (signed off 2026-11-10)

Replaces G1-G3 (a line per modifier, surges, immunity). Built like the tier line: what the damage came
to, "up from" what the tier dealt alone (a kit is the hero's normal damage, so it is in "from" and
never named), then the parts that changed it. Only when something besides the tier and kit changed the
damage; G6 is unchanged. The shared line names what changed the damage of every target that took some;
a target gets a line only for what applied to it alone. When targets started from different tier
damage, the shared line gives only the extra ("12 extra damage"); if the shared parts took damage
away there, there is no shared line and each target's line names everything, from its tier damage.
Targets whose lines read the same share one. Modifier names in brackets (G13); surges and immunity
plain. Each part says exactly what it changed; a modifier that adds different amounts on different
tiers is not shared. Order: modifiers, surges, weakness; what lowered it after ", but".
| ID | Where | Text |
|---|---|---|
| G15 | Why lead, the shared damage line | 19 damage, up from 15 / 6 damage, down from 8 / 8 damage (parts cancelled out) / 12 extra damage (targets on different tiers) |
| G15a | Why text, what raised it | [Empyrean Boon] added 10 holy / [Upholding High Standards] added 2 / 2 surges added 2 each (Dwarf Fury's highest characteristic, Might 2) / 1 surge added 2 (...) / fire weakness 3 added 3 |
| G15b | Why text, what lowered it, after ", but" | holy immunity 5 took 5 off / damage immunity 2 took 2 off / [Name] took 2 off |
| G15c | Why lead, a target's damage line | 15 damage to Goblin 2, down from 20 ("from" is what the shared line gave that target) |

## Round 18: what players see (signed off 2026-11-10)

The rule (REVIEW.md B5, James 2026-11-10): with Monster Info off, players see what the Action Log
shows them; with it on, also what Monster Info has revealed. Immunity and weakness always show (the
damage gives them away). A monster's ability card shows only with Monster Info on and that ability
revealed; modifier hovers on a monster's roll never reach players; monster triggers stay Director only.
Effects hidden from enemies, on a creature off the heroes' side, don't reach players.
| ID | Where | Text |
|---|---|---|
| Z10 | The numbers, a monster's power roll | Its characteristic is not named: the stat block gives a flat number, so it joins the Bonus line ("Bonus .... +2"), for everyone. |
| Z11 | The numbers, a roll hidden from players | Rolled in secret. (players: in place of the roll, with no tier lines in the Why; Director: above the numbers, after an eye) |
| Z11a | Z11's eye, Director | tooltip: Hidden from players / Visible to everyone (the Action Log's words); clicking shows the roll to players or hides it again |
| L28 | Secret modifier, Director (built here) | The name with an eye after it, tooltip: Hidden from players |
| L28a | An effect hidden from enemies, Director's History line | the line with an eye after it, tooltip: Hidden from players |

## Round 19: an effect renewed (signed off 2026-11-10)

| ID | Where | Text |
|---|---|---|
| L39 | What happened, and a lone trigger's line: an effect or condition applied by a cast while the creature still had it (the game renews it) | {Creature}'s {effect} was renewed. |

Only a cast records a renewal; one outside any cast (an aura's upkeep) stays quiet. Stacking effects use the same line for now.

## Round 20: the Sidebar Preview (signed off 2026-11-13)

| ID | Where | Text |
|---|---|---|
| L46 | Sidebar Preview, an action's header | {Actor} . {Ability} (the card title without brackets: nothing hovers) |
| L47 | Sidebar Preview, under an action with more than 2 target sentences | and {n} more |

## Round 21: play outside an action (5.1)

**Signed during the build (2026-11-14 to 2026-11-15).**
| ID | Where | Text |
|---|---|---|
| L48 | Section heading outside combat (replaces L43) | the game mode's name: Exploration / Respite |
| L49 | A Recovery spend, joined to its heal row | {Creature} regained {n} Stamina / Used a Recovery |
| L50 | Card title, a test | {Creature} · {Test name} (e.g. Gordon · Might test) |
| L51 | Card title, a Dice panel roll | {Creature} · Dice |
| L52 | A Dice panel Power Roll | L45, cause {dice} · Tier {n} |

**Respite (signed off 2026-11-15, option A: one line per Hero).**
| ID | What | Line | Cause line |
|---|---|---|---|
| L53 | The respite ends | {Hero} took a respite | only what changed: Stamina {b} to {n} · Recoveries {b} to {n} · XP {b} to {n}; joins the Respite heal row |
| L54 | Nothing to regain | {Hero} took a respite | Respite |
| L55 | Level up | {Hero} reached Level {n} | Respite |
| L56 | Effects that end when it begins | L8 / L11: {Hero} {Effect} and {effect} + Ended tag | Respite began |

No Undo on respite lines: a respite is not a turn.

**Montages (signed off 2026-11-15).** A book montage test's success depends on its difficulty, which the
journal montage does not record, and the journal montage stores no outcome: so no tags there.
| ID | What | Line | Cause line |
|---|---|---|---|
| L57 | A test in a journal montage | L44, no tag | {Characteristic} test · Tier {n} |
| L58 | The Director changes a journal counter | {Montage} successes {b} to {n} of {limit} (or failures) | Montage |
| L59 | A test in an EotW montage | {Hero} rolled {n} + Success tag (Tier 3+) / Failure tag (Tier 1) / none (Tier 2) | {Opportunity or Threat}: {Option} · Tier {n} |
| L60 | An EotW threat not vanquished | {Threat} was not vanquished | what its consequence did |
| L61 | An EotW montage ends | Montage ended | {n} successes · {n} failures · {n} threat(s) not vanquished |

**Negotiation (signed off 2026-11-15).** Players see numbers only when the Director shows them on the
stage (`live.showRaw`); otherwise interest shows as its band (Unmoved, Wary, Listening...) and patience
not at all. The legacy negotiation dialog writes nothing. Offers accepted or declined, NPC speech and
dismissed arguments write nothing.
| ID | What | Line | Cause line |
|---|---|---|---|
| L62 | It begins | Negotiation with {NPC} | Interest {n} · Patience {n} |
| L63 | An argument | {Hero} rolled {n} | Argument · Tier {n} · Interest {b} to {n} · Patience {b} to {n}; card: the argument text and the stage's cue |
| L64 | A pitfall | {Hero} hit a pitfall: {Pitfall} | Interest {b} to {n} · Patience {b} to {n} |
| L65 | Reading the NPC | {Hero} rolled {n} | Read {NPC} · Tier {n} · Learned something / Learned nothing / Learned nothing · Patience {b} to {n} |
| L66 | A trait revealed | {NPC} {Trait} revealed | Motivation / Pitfall |
| L67 | Director meter correction (Director only) | {NPC} interest {b} to {n} | Director |
| L68 | It ends | Negotiation with {NPC} ended | Final offer: {offer} / No deal |

**Downtime projects (signed off 2026-11-15).** Project rolls have no tier (edges +2/+4, no tier change).
An upcoming milestone is never shown: players see one only when it is reached, as the sheet does.
Granted downtime rolls and fishing write nothing; project event rolls use the table line.
| ID | What | Line | Cause line |
|---|---|---|---|
| L69 | A project roll | {Hero} rolled {n} | {Project} · project points {b} to {n} of {goal} |
| L70 | For another hero's project | {Hero} rolled {n} | {Owner}'s {Project} · project points {b} to {n} of {goal} |
| L71 | A breakthrough | L69 + Breakthrough tag | the second roll writes its own L69 |
| L72 | A follower's roll | {Follower} rolled {n} | {Project} · project points {b} to {n} of {goal} |
| L73 | A milestone reached | {Project} reached a milestone | The Director rolls a project event |
| L74 | Completed | {Project} completed | {Hero} · project points {n} of {goal} |
| L75 | Director adjusts points | {Project} project points {b} to {n} | Director |

**Withdrawn 2026-11-19 (James): L69-L72 and L75.** A project keeps its own rolls and adjustments, and the
Respite shows what everyone rolled, so these lines only repeated them and crowded the respite out of
History. Only what changes the table is written: L73 and L74. The hook still reports every change
(`DTProject:_notePoints`), so the lines can come back without touching the project code. L73 does not
depend on the Players Manage Downtime Projects setting: a player's project already says "Milestone
reached" whatever that setting is, and only the milestone still to come is kept from them.

**Tables and hidden rolls (signed off 2026-11-15).** Matches today's chat: a table card always shows its
row (a table's own visibility only hides rows before rolling). GM only: the engine sends the message only
to the roller and the Director, so other players get no line. Dice Tower: everyone sees the roll happen,
only the Director sees the result (the roller too sees L79). Lines follow the Director's Reveal / Hide.
| ID | What | Line | Cause line |
|---|---|---|---|
| L76 | A table roll | {Who} rolled {n} | {Table} · {result} (cut short; full in the card) |
| L77 | A project event roll | Director rolled {n} | {Project} event · {result} |
| L78 | An overridden result | L76 | {Table} · {result} · Overridden; card: the dialog's override message |
| L79 | A Dice Tower roll, non-Directors | {Who} rolled in secret | {Table} / {Characteristic} test / {Project}, no number or result |
| L80 | A hidden roll, Director | the normal line + eye | tooltip: Hidden from players (L28) |

**Macros (signed off 2026-11-15).** /awardmalice, /awardherotokens, the effect macros and /dorespite already
write their lines. Only the macro writes these; the victory screen, shops, loot, trades and the stash are
outside 5.1. Dev and debug macros write nothing.
| ID | What | Line | Cause line |
|---|---|---|---|
| L81 | /roll in chat | L45: {Who} rolled {n} | {dice}; hidden-roll rules L79/L80 apply |
| L82 | /awardvp | {Hero} gained {n} Victories | Director |
| L83 | /giveitem | {Hero} received {Item} [x{n}] | Director / {player} |
| L84 | /granttitle | {Hero} earned the title {Title} | Director / {player} |
| L85 | /awardrenown, /awardwealth | {Hero} Renown {b} to {n} / Wealth {b} to {n} | Director |

## Round 22: Director actions (5.2)

**Category 1, the Director's tools on rows (signed off 2026-11-19).** Director only; any line or action row,
nested lines included. Hide from players hides the row and everything nested under it (the Director keeps
it, with the eye-off icon, L28). Delete entry removes the row and what is nested under it at once, no
confirmation. Clear History clears this map's History for everyone, after a confirmation.
| ID | What | Wording |
|---|---|---|
| L86 | Clear History confirmation | Title: Clear History? / Body: This removes every entry on this map for everyone. It can't be undone. / Buttons: Clear History, Cancel |

**Category 2, hand edits (signed off 2026-11-19).** Stamina (damage, heal, set, temporary), conditions added or
removed, and the resources History follows (Heroic Resource, surges, Recoveries, Malice). The hand-edit controls
mark their change; the line is the usual one with who made it under it. Players see it under the usual rules.
A player's hand edit turns the Director's badge gold.
| ID | What | Line | Cause line |
|---|---|---|---|
| L87 | Any hand edit | the existing line | Director / {player} |
| L88 | Stamina set by hand | {Creature} Stamina {b} to {n} | Director / {player} |

**Category 3, reinforcements (signed off 2026-11-19).** One line per deployed wave, written by the client that
deployed it (Director button or encounter script); dismissing a wave writes nothing. Names follow the usual name
rules; if any arrival is hidden from players when it lands, the line is Director-only. It sits in the round and
turn it happened.
| ID | What | Line | Cause line |
|---|---|---|---|
| L89 | A wave deployed | {Wave name} arrived | the arrivals: {Monster} x{n} · {Monster} (a minion squad counts its members) |

**Category 4, villain actions (signed off 2026-11-19).** The action row and its card header carry a tag; no
line for the per-round budget; players see it as any action.
| ID | What | Wording |
|---|---|---|
| L90 | Tag on a villain action's row and card header | Villain Action (changed 2026-11-19, James: the slot number is dropped) |

**Category 5, overrides (signed off 2026-11-19).** Anyone driving the roll dialog may override a tier (not under
Strictly Enforce Rolls, never the Monster AI). The action row is tagged; the card shows the final tier and replaces
the tier explanation with who overrode it and what the dice gave; a test line's cause ends "Overridden". Tables
keep L78.
| ID | What | Wording |
|---|---|---|
| L91 | An overridden action row | no tag (changed 2026-11-19, James): the tier badge is drawn in the warning colour; hover: Overridden |
| L92 | The card's Why line in place of the tier explanation | {Who} overrode the result: Tier {n}. The dice gave Tier {m}. |
| L93 | A test line overridden | cause: {Test} · Tier {n} · Overridden |

**Category 6, reveals (signed off 2026-11-19).** One line when the Director reveals a spoilered modifier, written
by the Director's client. It follows the eye: while hidden again, players get no line and the Director keeps it
with the eye-off icon. Monster Info reveals write nothing.
| ID | What | Line | Cause line |
|---|---|---|---|
| L94 | A hidden modifier revealed | {Creature} {Modifier} revealed ({Modifier} revealed with no creature) | the modifier's description, in full |

## Round 23: several maps (6.1, signed off 2026-11-19)

The map switcher sits in History's title row while two or more maps you can see are in combat. It
shows the map on show, cut short when long; its menu lists those maps by name, the shown one ticked.

| ID | What | Line |
|---|---|---|
| L95 | Tooltip on the map switcher | Display history for another map |

## Round 24: empty History (signed off 2026-11-20)

| ID | What | Line |
|---|---|---|
| L96 | History on a map with nothing recorded yet | Nothing has happened on this map yet. |

## Round 25: stability and wall breaks (6.5, signed off 2026-11-20)

"Push" stands for the kind: Pull, Slide, Vertical push and Vertical pull read the same way.

| ID | What | Line | Example |
|---|---|---|---|
| L97 | Caption, stability shortened it | {Push} {moved} · Stability {s} | Push 2 · Stability 1 |
| L98 | Caption, stability stopped it | {Push} stopped · Stability {s} | Push stopped · Stability 1 |
| L99 | Card sentence, shortened | ... was pushed {moved} of {n} squares (stability {s}). | Goblin 3 was pushed 2 of 3 squares (stability 1). |
| L100 | Card sentence, stopped | ... held its ground: stability {s} stopped the push. | Goblin 3 held its ground: stability 1 stopped the push. |
| L101 | The numbers | Push {n} / Stability -{s} / Moved {moved} | Push 3 / Stability -1 / Moved 2 |
| L102 | The numbers, the attacker ignores stability | Stability ignored | |
| L103 | Caption, wall break | Broke {n} wall / Broke {n} walls | Push 3 · Broke 1 wall |
| L104 | Card sentence, wall break | ..., breaking through {n} wall(s). | Goblin 3 was pushed 3 squares, breaking through a wall. |
| L105 | Caption, blocked before it moved a square | {Push} blocked | Push blocked · Stability 2 |
| L106 | Card sentence, blocked | ... was blocked and didn't move (stability {s}). | Devil High Judge was blocked and didn't move (stability 2). |

## Round 26: triggers used inside the roll dialog (6.5b, signed off 2026-11-20)

| ID | What | Line | Example |
|---|---|---|---|
| L107 | Tag on a trigger row for a triggered action used from the roll dialog | During the roll | During the roll · Bryn · Draconian Guard › Larry -7 |

## Round 27: the rest of 6.6 (signed off 2026-11-20)

James 2026-11-20. L32 is retired: a triggered action's own card says what set it off with Y11's
words. L16 moves into the persistence line's small text. Rampage needs nothing new: it is an
ongoing effect and already gets its own lines.

| ID | What | Line | Example |
|---|---|---|---|
| L32 | (retired: Y11 instead) | | |
| Y11 | Why on a triggered action's own card | {Trigger} / Trigger: {the ability's Trigger line} | Mark: Benefit / Trigger: You or an ally uses an ability to deal rolled damage to a creature marked by you. |
| L16 | Persistence broken by damage, small text (replaces L13's) | Took {n} damage in one turn, 5 times {Characteristic} {r} | Took 12 damage in one turn, 5 times Reason 2 |
| L108 | Why, collision with an object | Hit an object / {Creature} had {n} squares of the {push} left: {n} damage, plus 2 for hitting an object. | Goblin 1 had 2 squares of the push left: 2 damage, plus 2 for hitting an object. |
| L109 | Why, collision with a creature | Hit {Other} / {Creature} had {n} squares of the {push} left, so it and {Other} each took {n} damage. | Hit Goblin 2 / Goblin 1 had 2 squares of the push left, so it and Goblin 2 each took 2 damage. |
| L110 | Strained (F5) | {Creature} is strained / {Creature} is no longer strained; small text {Resource} {n} | Lyra is strained · Clarity -2 |
| L111 | New squad captain (F5) | {Creature} is now {Squad}'s captain; small text who did it | Goblin 3 is now the Goblin Raiders' captain · Director |
| Y5c | Surges a modifier gave to keep, after the damage line (signed off 2026-11-21) | {One was / They were} gained from [{Modifier}]. | 2 surges added 2 each (...). They were gained from [I Work Better Alone]. |
| L26 | (changed 2026-11-21, James: name the creature) | {Condition} / {Creature} did not resist. / {Creature} resisted. | Weakened / Devil High Judge did not resist. |

## Round 28: the switch-over (6.4, signed off 2026-11-21)

History is the default. The old Action Log is hidden unless the setting is on.

| ID | What | Text |
|---|---|---|
| L112 | Setting name | Use Old Action Log |
| L113 | Setting tooltip | Show the old Action Log instead of History |
| L114 | History's rail button hover | History |
