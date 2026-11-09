# History: build plan

Status: signed off by James, 2026-11-06. Design: BRIEF.md, REVIEW.md, COPY.md,
prototype https://claude.ai/artifact/UPWo9XvYuaDiZ388xRES35 (version 26).

## How the work runs

- **One chunk, one commit.** Each stage is still one PR, but none goes up until the build is
  finished; then they are raised together (James, 2026-11-06), so a late change to an earlier
  stage's files needs no extra PRs. Everything stays behind an off-by-default setting.
- **A tag marks where each stage ends:** `history-stage-0`, `history-stage-1` and so on. Each stage
  works on `feature/history-stage-N`, cut from the last stage's tag. Tags and branches stay local
  until the PRs go up. Merge main in at each stage end, since these files change often there.
- **History runs beside the old log until the last stage.** The old log and its messages stay
  untouched. The switch-over is one chunk.
- **History never breaks the game.** Every hook sits in hot combat code, so each is wrapped the way
  `LiveEncounter.TrackHeroStats` is: it can fail, and the cast carries on.
- **Generic hooks only.** No code for a particular ability. Content built from modifiers works
  without changes, including future content.
- **Wording comes from COPY.md.** Anything not there gets proposed first.
- **Every chunk:** smoke test in the Codex over the bridge, type check, ASCII only, new Lua files
  registered through the MCP CodeMod workflow, the UI performance rules. James clicks where nothing
  can be checked by script. `data/` YAML is only edited with the Codex closed.
- **Layering:** hooks in `DMHub Game Rules/` stay system-neutral, with Draw Steel words in the Draw
  Steel layer, so Crows keeps working. Check Crows loads after stage 0.

## Stage 0: foundations

Goal: one real action appears in a real tray, stored safely, behind the setting.
| Chunk | What | Size | Done when |
|---|---|---|---|
| 0.1 | Performance test: a probe writes 300 records, one per action, with two clients connected, and measures the cost of a write and of a load | S | We know this encounter and the last one are cheap to keep, and the hard cap is set (starting figure 300 entries) |
| 0.2 | Record store: entries keyed by id (the `BattleLog.RecordBattle` pattern); one document per map; this encounter, the last one and what lies between, under a hard cap that culls the oldest first; names and portraits snapshotted; one client writes each entry; not registered for checkpoints; the setting | M | Records survive a reload and reach a second client |
| 0.3 | F1 actions, at `ActivatedAbility:Cast` (`ActivatedAbility.lua:3133`): actor, ability, targets, castid, round, turn, map, roll facts | M | Every ability cast writes one record, prompted triggers included |
| 0.4 | The tray: table item (a rail panel since 2.1b), rail button below Chat, round and turn folds, turn numbers, target cells, starts closed; builds the newest 30-40 rows and more as you scroll up, as today's log does | L | Real rows in the tray, meeting the idle and drag budgets |

### Stage 0 notes (built 2026-11-06)

- **Entries are JSON strings, not tables** (PROBE-0.1.md), and the hard cap is 500. The tray parses
  only the rows it builds.
- **Written when the cast ends**, stamped with when it began, so a cancelled cast leaves nothing and
  one action is one write. Stage 1 should add a cast's results to its entry before that write.
- **The setting** is `historyenabled`, game-wide, with no UI: `dmhub.SetSettingValue("historyenabled",
  true)`. It has no wording yet because it never reaches a screen. Turning it on puts the rail button
  below Chat for that user (`PanelDocument.RailPlaceBelow`); 6.4 can use the same call.
- **Generic hooks added:** `ActivatedAbility.RegisterCastObserver`, `available` on a panel registration,
  `place`, `Tabletop.HasItem`, `Tabletop.CloseItem` and `Tabletop.ResizeItem` for table items, and
  `InitiativeQueue.turnNumber`, a running count, because `turn` starts again each round.
- **Measured at 485 entries:** tray open 70 ms of Lua, worst frame 150 ms; Show all 89 ms; a new row
  under 35 ms with its cast; idle open equals closed (14 ms); dragging 22 ms a frame against 25.6 ms
  for a map window. Panel count stays flat.
- **Left for later, not in stage 0's list:** the Main, Maneuver and Move markers (T8: Move is not
  recorded yet), the Draw Steel banner (T10), chips (T12), the hover titlebar's text (T2), the rail
  button's lit state while the tray is open, and text for an empty tray, which has no signed wording.
- **Cloud file list:** History, HistoryCapture and HistoryTray are registered in Draw Steel V now,
  ahead of the code reaching main. A client without the files on disk runs the empty cloud stubs,
  so History simply isn't there for anyone on main until the PRs merge.
- **Not checked: Crows.** `Crowdex/` is not in this checkout and does not load in the test game.
  History is inert while the setting is off, but check a Crows game before merging.

## Stage 1: what happened in combat

Goal: the "did it change the table?" rule, on the glance. One family per chunk.
| Chunk | What | Hooks | Size |
|---|---|---|---|
| 1.1 | F3 damage, healing, temporary Stamina, from any source, with the number that landed; skip what changed nothing | `InflictDamageInstance` (`MCDMCreature.lua`), the heal behavior (`ActivatedAbility.lua:5094`), `GrantTemporaryStamina`, `AuraDamage` (`:7144`) | L |
| 1.2 | F2 automatic triggers, nested under their cause; add the resolving cast's id to event info | `TriggeredAbility.lua:1545`, `ActivatedAbility.lua:3986`, `DispatchEvent` | M |
| 1.3 | F4 effects and conditions starting and ending, with the cause, grouped; the Ended tag; failed saves. New "Hidden from History" checkbox (COPY H1) and the 40-marker data pass | `RemoveOngoingEffect`, `RemoveMatchingOngoingEffects`, `RemoveOngoingEffectsOnTrigger`, `PurgeCondition`, `EndTurn`, `EndRound`, the `RefreshToken` tidy-up, a turn-end check for lapsed timers, `EndPersistentAbilityById` | L |
| 1.4 | F5 winded, dying, death, confirmed minion deaths, recovering | `MCDMCreature.lua:6806-6871`, `:7069-7083`, `squadminiondeaths` (`:6109`) | S |
| 1.5 | F6 resources with a cause; Malice; the Undo button on resource lines | `ConsumeResource`, `RefreshResource`, `CharacterResource.SetMalice` | M |
| 1.6 | F7 forced movement: distance, collisions, falls, wall breaks, the saved path | `AbilityRelocateCreature`, `LuaPath:Serialize` | M |

### Stage 1 notes

- **1.1 hooks moved, for the better.** `creature.TakeDamage` and `creature.Heal` instead of the damage
  and heal behaviors: every route ends there, hand edits and falls included, and they know the number
  that landed. `SetTemporaryHitpoints` instead of `GrantTemporaryStamina`, so ongoing effects count.
- **One observer:** `GameSystem.RegisterPlayObserver` replaces the cast observer. Later families add a
  moment to it, not a new mechanism.
- **Writes batch per frame.** History.Write queues; an aura hitting eight creatures is one write.
- **Measured per hit:** 1 us with History off, 3 us inside a cast, 40 us for a line, plus the write.
- **1.2:** events carry `causecastid`, which survives the trip to another client. A trigger's entry names
  its cause and the tray nests it, so client and order don't matter, and nothing rewrites the parent.
- **Prompted triggers stay action rows** (REVIEW.md section 1). A prompted trigger does not nest yet;
  "Before the roll" and "After the roll" (T15) need roll data from stage 2.
- **1.3:** `creature:EndingEffects(cause, fn)` wraps every place something comes off a creature and
  works out what ended from what changed, so a new removal path needs one wrapper, not its own logic.
  Lapsed timers are cleared at turn end, which is how they get reported.
- **1.3 data pass, still to run, with the Codex closed:** `data/` YAML is never edited while it runs.
  From the repo root: `python docs/action-log-design/probes/mark-history-hidden.py.txt --apply` ticks
  Hidden from History on the 40 markers. Without `--apply` it only lists them. Commit it in `data/`.
- **L13 has no hook.** The Elementalist's 5 x Reason rule only shows floating text; nothing ends the
  persistence, so "Took {n} damage in one turn" cannot appear until that rule is automated.
- **1.4:** winded, dying and killed fire where the rules already decide them, in `MCDMCreature.lua`, so
  hand edits count. Minion deaths wait for the batch that confirms them, then name the squad.
- **1.5:** resources carry the number that really changed (`ReportResource`). Undo on a resource line
  goes through `History.UndoResource`, which marks the line undone and keeps it.
- **1.6:** the saved path is a plain list of {x, y, floor, altitude} from `path.steps`, because what
  `LuaPath:Serialize` returned never reached the entry. Chunk 4.1 rebuilds a route from that list.
  Collisions and wall breaks are stored for the detail card; the tray only shows distance and fall.
- **Falls land after the push.** The engine adds the landing as one last path step, so `numSteps` is one
  too many and `path.fallDistance` reads 0 afterwards. The real distance only comes with the `fall`
  event, which the engine fires when the animation ends, outside any cast. So the push leaves its row
  in `g_falling`, and the landing and the Fall Damage trigger join that row, even if it has closed.
  A fall with no push behind it stays a line, cause Fall Damage.
- **A creature landed on** joins the push's row with the caption Landed on. With no push behind the fall
  it is a line, cause Landed on by {name}. Nothing is guessed from the damage, which is called Fall
  Damage either way: the engine fires `fallenon` only on creatures in the landing square, and its symbols
  name the faller. Tested for real, pushes in both orders, falls with no push, and a second fall inside
  the push's window, which stays off the row. Not tested across clients: if a trigger runs on another
  client it finds no push there and reads as a line, which is still true.
- **Tested for real:** Brutal Slam on two clients, real heal and temporary Stamina behaviors, a Reactor
  trigger nested across clients, real end of turn, a real passing save, a real push with Growing
  Ferocity nested, a real push off a ledge in both orders (row closed before and after the landing),
  real Undo, and a Player seeing no Malice lines.
- **Tested with fed data only:** failed saves, persistence, dying lines, confirmed minion deaths.
- **Wordings:** the ones the build needed are signed off, COPY.md Round 5.
- **Left for later:** effects ended by a respite (5.1), "Hidden from enemies" effects reaching players
  (2.4), the Active tag on a target's badge (3.1). Crows is not checked: `Crowdex/` isn't in this
  checkout, so check a Crows game before merging.

## Stage 2: the detail card

Goal: why it happened, one click from the row.
| Chunk | What | Size |
|---|---|---|
| 2.1 | Card shell, placement beside or inside the tray, the sentence builder for What happened (COPY N2, L lines) | M |
| 2.2 | The numbers: the receipt, the roll, edges and banes, one tier label | M |
| 2.3 | F10 named sources: `modifiersUsed`, kit notes (`modificationLog`), immunity and weakness, `DescribeModifications` for anything else; Why lines; typed messages; ability card on hover | L |
| 2.4 | The visibility rule: secret modifiers follow the reveal, minion Stamina and monster numbers follow Monster Info | S |

### Stage 2 notes

- **2.1:** the card is a floating child of the tray's face, so it moves, scales and closes with the tray
  and no layout has to remember it. `Tabletop.ItemRect` says where the tray sits; the card picks right,
  then left, then inside the tray with Back (B7), and rechecks once a second, so dragging the tray moves
  it. It is rebuilt whenever it changes, because a scroll bar only works if it exists on its first frame.
- **Sentences:** `History.Story` turns an entry into rows, with no gui, so the hover preview (3.3) and the
  sidebar preview (3.4) can use the same words. New wordings are COPY.md Round 6.
- **Which rows open a card:** actions, and the Encounter ended line (L17). Every other line already says
  everything; L16 joins with the Why lines in 2.3.
- **W10 is not built.** "Took 6 damage from 2 minions" needs the count of minions that reached a target,
  which entries don't hold yet. Look at it with the numbers in 2.2.
- **New facts on entries:** `ability.area`, `player`, `resisted` names the condition when the rule text
  does, `endedconds`. Rows written before this have none of them, so an old row reads "Director" in its
  footer and "and Slowed ended" for a condition.
- **T13 Ally hit** was missed in stage 1; it is on the target cell now, from the same check as W11.
- **Tested for real:** the card on the right, on the left and inside the tray (a narrow table was faked),
  row swap, same row closes, close button, wheel, scroll bar drag, a row rewritten while its card is open,
  31 rows built in 19 ms. **Fed data only:** every sentence but falls, the Encounter ended card.
- **2.1b, a rail panel (James, 2026-11-07):** History registers as a dockable panel with content, so the
  rail opens it as a window like Chat: frame, transparency, pin, pop out, Font Size zoom. Two generic
  registration fields in `PresentPanel`: `defaultWidth` (the rows are laid out for 410, plus the 8 px
  resize strip) and `dragInPlace` (rail windows are dragged without it, which restyles the whole window
  every frame: History's drag went from 64 ms a frame to 15; Chat's is 18). Only History sets them; giving
  every rail window `dragInPlace` is a separate change. The table item and the `Tabletop.lua` additions
  from 0.4 and 2.1 are gone. The card is placed from the window's position; popped out, it opens inside.
  The roll card that folds into History later (S5) aims at this window.
- **2.1c, rows (James, 2026-11-07):** a hairline above every action, folded turn and turn group (@border at
  31%, the prototype's 5% white); the seam under a round heading and in the card at 75% (12%). Trigger rows
  are one line: the result after a caret is never cut, the "{Owner} · {trigger}" part shortens with an
  ellipsis and shows whole on hover. Widths are estimated per character, generously, because the engine
  can't measure text before layout. Tested on the seven-trigger Brutal Slam turn.
- **2.1d, the card (James, 2026-11-07):** the rail windows' frame (gradient, rounded, blurred backdrop,
  shadow); no white edge on the card or the selected row, which is marked by @bgRaised instead (a
  see-through fill shows the table behind the window under Transparent UI). A tail, a square turned 45
  degrees behind the card, points at the row. The card lines up with its row from the panels'
  distancesToScreenEdge, slides to stay on screen, follows the list as it scrolls, and holds at the list's
  edge with no tail when the row scrolls out of sight. Over the list (popped out, or no room) it is solid
  and has no tail.
- **Performance after the feedback rounds (James: feels fine, 2026-11-07):** on a freshly started
  Codex, idle runs at the frame cap with History open or closed; a card opens in 23-26 ms; dragging
  runs at 14 ms a frame; wheel scrolling at 14 ms. Two one-frame hitches stay: opening History from
  the rail (~95 ms) and Show all (120-140 ms for ~33 rows, 29 ms of it Lua). Spreading Show all over
  frames is 6.2's. Measure on a fresh start: after a day of reloads and pop outs the Codex itself
  slowed to ~4 frames a second, which made Show all look like a 2.7 s stall.
- **2.2, the numbers:** the prototype's receipt under What happened: Power roll (the two dice, the
  characteristic, a flat Bonus, edges and banes with their counts and the C4 note, Total with its tier),
  then a sum per target (its own roll if it had one, Tier lines by damage type, immunity or weakness,
  Taken / Taken, each / Regained), then Triggered and Cost. Wordings are COPY.md Round 7 (Z1-Z7).
  New facts: `roll.natural`, `roll.characteristic`, `roll.bonus`, and a target's own `roll` (edges,
  banes, total), which the roll behaviour now keeps on the cast as `targetRolls` beside `tokenToTier`.
  Rows written before 2.2 show only the total, the tier and the targets' sums.
- **Left for 2.3:** surges and kit bonuses are inside the Tier line's number until 2.3 splits them out
  with the named sources. Immunity is one line per target even when two hits each met it.
- **Tested:** a real Brutal Slam (5 + 5, Might 2, an edge from Prone, 14, Tier 2, 8 taken) and a fed
  entry with three edges and a bane, a flat bonus, a target cancelled out on its own roll, typed damage
  with immunity, a weakness, two goblins grouped, healing, a damaging trigger and a Malice cost.
- **2.3 in four commits:** 2.3a edge and bane sources, 2.3b surges and kit bonuses, 2.3c Why lines and
  typed messages, 2.3d the ability card on hover.
- **2.3a, edge and bane sources:** under each edge or bane line, one line per thing that added to it
  (COPY.md Round 8): its arrows, a trigger owner's face, its name as the roll dialog's badge showed it;
  edges first, Set by hand last on each side, then the C4 note. The roll dialog measures each enabled
  modifier's edges and banes as CalculateRollText applies it (so the sources add up to the counts) and
  keeps the list on each target row as `edgeSources`; the power roll copies it onto the cast as
  `targetSources`; capture keeps it on the roll (from a target with no roll of its own) and on a
  target's own roll. Spoilered names stay redacted for players, as in the dialog.
- **Limits of 2.3a:** two targets with the same counts from different sources show the first one's under
  Power roll. (Removers were not listed either; 2.3a2 adds them.)
- **Found in 2.3a:** pressing the dialog's Roll Dice by its text over the bridge hits the side tab's
  label, not the button; click it with the virtual mouse. 2.2's `targetRolls` path is live (it sits in
  the same per-target block, which a real cast reaches).
- **For 2.3c (James, 2026-11-08):** the card should say which trigger caused a nested gain (Y15). A
  resource line keeps only the trigger's name (`causetext`, e.g. "Discipline"); capture must also keep
  the trigger's own text, which lives on the TriggeredAbility's `description` (the Null's reads "You
  gain 1 discipline the first time in a round that an enemy uses Malice.").
- **2.3a2, removed edges and banes (James, 2026-11-08; COPY.md Round 9):** the roll dialog also records
  what each modifier takes away (`removedEdges`, `removedBanes`, `ignore` for the Ignore modtypes, which
  run last with `lateness = 100`). A target's own remover carries the target as its owner. The card
  lists a remover last under its line, dimmed, as "Ignored by" or "Removed by"; a side that lost every
  edge or bane keeps its line ("Edge, ignored", value 0). Tested with a real Brutal Slam while the
  Dwarf Fury was Twisted (Prone's edge, Ignored by Twisted, Tier 2) and a fed entry with a target's
  remover, a partial removal and an ignored bane on a target's own roll.
- **2.3a2 feedback (James, 2026-11-08):** a side that lost every edge or bane is crossed out, not
  relabelled: its line (label and value, the value muted) and each source under it carry a strikethrough,
  and the reason sits once, after the line, in the aside style ("~~Edge~~ Ignored by Twisted"; James
  chose the top line only, since Ignore applies to the whole side). Only a partial removal
  keeps the remover's own line, since nobody knows which edge it took. The old dimmed remover line read
  brighter than the sources; reasons now use `@fgMuted`. The card's styles live on the tray, so a style
  change needs the History window closed and reopened after a reload.
- **Found in 2.3a2:** `MCDMCreature.lua` wraps `creature.ApplyOngoingEffect` with no reload guard, so
  every hot reload of that file stacks another wrapper and one effect writes one History line per
  reload. Dev-only (a fresh start has one wrapper); restart before judging effect lines.
- **2.3b, the Tier line split (COPY.md Round 10):** each damaged target's sum lists the tier's own damage,
  then the kit (K1), the roll dialog's damage modifiers (K2, named as their badges, a trigger's owner
  with a face), then surges (C3s behind the surge bolt), then immunity and Taken. Each part comes off
  the line of the type it added to; if the parts don't fit the lines (a negative remainder, or a type
  with no line) the line stays whole. Sources: the kit from the ability's `modificationLog` note (the
  kit's type is the tier's first damage, as MCDMKit matches it); modifiers measured around each
  `ModifyRollProperties` in CalculateRollText with `RollPropertiesPowerTable.DamageByType`, kept per
  target as `damageSources` and on the cast as `targetDamageSources`; surges as `targetSurges` (count,
  the highest characteristic, the type a surge modifier names). Entries written before keep one line.
- **Tested in 2.3b:** a real Brutal Slam with 2 surges at Tier 3 (20; Tier 3 11, Panther kit +4, Spent 2
  surges (Might 2 each) +4, Taken 19) and a fed entry with the Mark and its owner's face, typed fire
  parts with fire immunity, one surge, and parts that don't fit. Not tried live: a real damage modifier
  (none on the Fury's Brutal Slam), so the dialog's measurement has only run with nothing to record.
- **Found in 2.3b:** resource lines stack the same way after reloads (one surge gain or spend wrote
  eight lines). Surges spent on accepting the roll also write their own "spent 2 surges" line beside
  the action, which the receipt now repeats; worth folding into the action as a cost later.
- **2.3c split (James, 2026-11-08):** 2.3c-1 the Why lines from what entries already record; 2.3c-2
  triggers (Y11, Y15: capture the trigger's own text) and typed messages; 2.3c-3 the tier comparisons
  (Y1, Y2). Later, outside 2.3: falls (Y7), potency (Y8, Y9), Y5b, minions (Y13, after 2.4), L32,
  L33, L16.
- **2.3c-1, the Why section (COPY.md Round 11, G1-G6):** `History.Why(entry)` builds the rows with no
  gui (area ability that hit an ally, damage modifiers, surges, immunity or weakness, condition
  immunity), one line per distinct fact, naming every target that shares it; G6 only when the roll and
  damage are exactly the tier's (a kit doesn't count as a change). Rendered between What happened and
  The numbers as in the prototype: bold lead, sentence, a rule down the left. An action whose only
  change is an edge or bane has no Why section until 2.3c-3. Tested on the real entries (the surge
  Brutal Slam gets G2, Slide One Target G6) and fed entries for every line.
- **2.3c-2, triggers and typed messages (COPY.md Round 12, G7-G8; James 2026-11-08):** the Why says a
  trigger fired and what it changed ("{Owner}'s {trigger} / Triggered by this action: ...", in What
  happened's words); its rules sit behind a hover on its name in 2.3d (a monster's: Director only),
  so no trigger text is captured. Resource lines an automatic trigger writes now keep `trigger` and
  `triggerby`. Typed messages: one-line `typedmessage` play-observer hooks where a step posts its
  author's chatMessage (damage, conferred conditions, healing, purge, temporary Stamina, resource
  reasons); capture keeps them on the running cast's row (`messages`), skipping the ability's own
  name and repeats. Triggers that change the roll move to 2.3c-3 with the tier comparison.
- **Tested in 2.3c-2:** the real Convocation of Chaos card (Lv2 Human Null's Discipline); a real Brutal
  Slam with notes sent from inside the cast (the ability's own name skipped, a repeat kept once); fed
  entries for every line. The hooks in DMHub Game Rules (heal, purge, replenish) were not reloaded
  live; they load on the next restart.
- **Found in 2.3c-2:** the Wode Elf Troubadour's drama trigger is named with its whole rule ("Whenever a
  creature rolls a natural 2 ..."), so its lead read as a sentence. James chose G7a: a name ending in
  a full stop or past 40 characters leads as "{Owner}'s trigger"; the rule shows on the hover.
- **2.3c-3, the tier comparisons (COPY.md Round 13, G9-G11, Z8):** the roll dialog also records each
  modifier's tier effect (Tier Up/Down `tiers`, `autosuccess`, `autofailure`, `nottierthree`,
  `nottierone`, measured from ParseRoll like the edges; James: they are power roll modifiers, so
  History can name them). The Why recomputes the tier with one side taken away, through
  `RollUtils.DiceResultToTier` itself: the edges, the banes, what ignored or removed them, each tier
  modifier, and the natural 19-20 rule; a target's own roll covers only its target-only sources. Roll
  lines come first. A roll whose recomputed tier doesn't match the recorded one (rows from before 2.3a)
  gets none. The numbers lists each tier modifier after the edges and banes (Z8).
- **Tested in 2.3c-3:** real entries (Prone moved a Brutal Slam from Tier 2 to Tier 3; Twisted's ignored
  edge; Word of Guidance on Bluster's targets); fed cases for a cancelled double edge with Tier Up, a
  natural 19 under a double bane, automatic Tier 3, a target's Cover and Not Tier 3, and an
  unexplained tier (no lines). Not tried live: a real tier modifier in the roll dialog.
- **Limit of 2.3c-3:** each side is recomputed alone, so two sources that only change the tier together
  (a bane and a Not Tier 3 on the same target) each read "stayed at". Several targets that got the
  same target-only source get one line each. (Both limits gone in 2.3c-4.)
- **2.3c-4, one tier line per roll (COPY.md Round 14, G12-G12d, Z9):** James found the per-part lines
  confusing: each claimed its own tier change. The Why is a sum: one line per roll ("Tier 3, up from
  Tier 2" / "Prone gave an edge."), worked out for all parts together in `TierStory`. Parts are grouped
  (all edge givers, all bane givers, what removed each, each tier modifier, each flat bonus, a natural
  19-20); the line names the side the tier moved, and adds ", but ..." only when the other side
  changed where it landed. A rule that sets the tier outright is named alone. A target's own roll gets
  a whole line of its own, merged across targets, dropped when it reads like the main roll's. The roll
  dialog now also records each modifier's flat change to the roll (`bonus`, the sum of ParseRoll's
  category mods); The numbers shows it after the edges (Z9) and the "Bonus" line keeps the rest.
  Worked out when the card opens, not stored at the roll (James): same facts and same rule either way,
  rows stay small, and fixes reach old rows.
- **Tested in 2.3c-4:** 23 offline cases through the real `TierStory` code with
  `RollUtils.DiceResultToTier` copied in (every row of the signed-off table, set by hand, a remover of
  an edge no part gave, both sides cancelling, Not Tier 1, three parts, the guard).
  Live 2026-11-10 after the rebase: the real Prone Slam reads "Tier 3, up from Tier 2 / Prone gave
  an edge."; the Twisted and 16 + Might Slams get no line. A fed card (Rune +2 with Prone ignored by
  Twisted, two targets held by their own bane) showed the line naming the ignored edge, and the
  "but" clause putting the bane before "Twisted ignored it"; fixed (a part is named only when it did
  something against the other side; removers lead the "but" clause). The numbers shows "Rune of
  Striking +2" after the edges and Bonus +1 for the rest. Not tried live: a real flat bonus in the
  roll dialog (no modifier on the map adds one); its ParseRoll measure was checked on the bridge.

## Stage 3: getting to it

| Chunk | What | Size |
|---|---|---|
| 3.1 | Search: field, suggestions, chips, filter in place, Active tag, "turn 15" | M |
| 3.2 | History from a token's radial and a hero card's chip | S |
| 3.3 | Minimised block, badges on block and rail, hover preview, History notifications, new-rows markers, nothing moves under the reader | M |
| 3.4 | History Sidebar Preview and its setting, reusing the chat speech bubble's placement (`DocumentSystem.lua:16400`) | S |

## Stage 4: movement views

| Chunk | What | Size |
|---|---|---|
| 4.1 | Engine PR: draw the movement arrow and the side view from a saved start and path (`MarkMovementArrow`, `SetMovementCrossSection`, a way to build a `LuaPath` in Lua) | M |
| 4.2 | Side-view button on movement captions, arrow, `CreateGhost` at the start square | S |

## Stage 5: everything else the old log shows

| Chunk | What | Size |
|---|---|---|
| 5.1 | F8 play without an action: tests, Dice panel, tables, macros, montages, negotiation, respite, downtime; the Out of combat section | L |
| 5.2 | F9 Director actions: reinforcements, villain actions, overrides, hand edits, reveals; right-click Hide/Reveal, Delete entry, Clear History | M |
| 5.3 | Revert Turn and Turn Rewind: Reverted rows, the Turn reverted line, out of the totals | M |

## Stage 6: finish and switch over

| Chunk | What | Size |
|---|---|---|
| 6.1 | Several maps: follows the map last clicked, the switcher, badge and preview across maps | M |
| 6.2 | Scale: "+N", grouped results, details built when opened; a long-fight test at the hard cap | M |
| 6.3 | Font Size and narrow windows (the responsive-panel checks); full performance pass | S |
| 6.4 | Switch-over: History on for everyone; old log off the rail; the built-in Views give History its own button; stored rail layouts repaired (`g_railRenamedPanels`); tooltip "History (was Action Log)"; old messages keep posting, because other code reads them | M |

## Risks

- **Performance of two encounters (0.1).** Today's log keeps about 140 messages and that has drawn
  one complaint, so there's no value in a really long history. If two encounters cost too much,
  the hard cap wins and the older encounter shortens. That's why it goes first.
- **Who writes.** Two clients recording the same event would double it. Each hook needs one clear
  writer; lapsed timers are the likeliest trouble because no single client owns them.
- **Cost on hot paths.** Damage runs often, so `DescribeModifications` only runs when a number
  actually changed. Measure in 1.1.
- **Trigger causes (1.2).** Nesting relies on passing the cast through events. Some events may not
  have one, and those fall back to a line in the turn.
- **Old log readers (6.4).** Roll dialogs, respite, Encounter of the Week and others use chat
  messages, so 6.4 removes the panel, not the messages.

## Answered by James (2026-11-06)

1. Today's log keeps about 140 messages, culling the oldest, builds the last 30-40 and more as you
   scroll up, and has drawn one complaint. Try this encounter and the last, as long as performance
   holds; a really long history has no value.
2. The engine PR for the arrow and side view from a saved start is already agreed in principle.

## Not in this plan

The rules deviations in `docs/rules-deviations-check.md`. Separate work.
