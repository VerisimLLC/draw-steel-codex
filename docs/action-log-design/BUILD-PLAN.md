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
| 0.4 | The tray: table item, rail button below Chat, round and turn folds, turn numbers, target cells, starts closed; builds the newest 30-40 rows and more as you scroll up, as today's log does | L | Real rows in the tray, meeting the idle and drag budgets |

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
- **Left for later:** effects ended by a respite (5.1), "Hidden from enemies" effects reaching players
  (2.4), the Active tag on a target's badge (3.1).

## Stage 2: the detail card

Goal: why it happened, one click from the row.
| Chunk | What | Size |
|---|---|---|
| 2.1 | Card shell, placement beside or inside the tray, the sentence builder for What happened (COPY N2, L lines) | M |
| 2.2 | The numbers: the receipt, the roll, edges and banes, one tier label | M |
| 2.3 | F10 named sources: `modifiersUsed`, kit notes (`modificationLog`), immunity and weakness, `DescribeModifications` for anything else; Why lines; typed messages; ability card on hover | L |
| 2.4 | The visibility rule: secret modifiers follow the reveal, minion Stamina and monster numbers follow Monster Info | S |

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
