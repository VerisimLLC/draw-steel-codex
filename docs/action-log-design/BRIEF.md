# Action Log redesign - design brief (DRAFT, in discovery)

Status: Phase 1 framing signed; Phase 3 decision map next. Started 2026-10-23.

## 1. Framing

- Problem: when something happens that a player or the Director did not follow, they
  cannot find out what happened quickly. The log is hidden behind a rail button, shows
  a noisy stream of bespoke cards, and buries the actual outcome (who lost how much
  Stamina, which condition landed) in hover tooltips.
- Example question it must answer in seconds: "I did 7 damage, why did the monster only
  take 5?" -> poison damage, the monster has poison immunity 2.
- Who asked: David; Ricky raised it too. The dev team rarely refers to the log.
- Not bound to today's form. Same spirit as the tabletop HUD, which reframed VTT play
  from map-first to table-first: the table holds the map and other things.
- Personas:
  - Player who missed something ("why did I lose 14 Stamina?").
  - Director settling a dispute or recovering from a mistake ("did the mark apply?").
  - Set-and-forget player who never opens it.
- Primary job: recall first. Full-session needs are served as outputs, not as the
  log's core design (see Open questions).
- Done looks like: TBD.
- Pillars (DRAFT, proposed 2026-10-23):
  1. Outcomes first, mechanics on request.
  2. Answer from where the question comes up (the creature, your hero, the round), not
     only from a panel. At a physical table nobody keeps a log: memory is spoken and
     tied to the creature and the moment.
  3. Record what happened when it happened; never re-draw history from live state.

## 2. Decision ledger

| Date | Decision | Rationale |
|---|---|---|
| 2026-10-23 | Primary job = recall of recent play; detail one click away | The log is opened after the fact, when someone is confused |
| 2026-10-23 | Free to reimagine the form; no obligation to keep the panel | Same reframing licence as the tabletop HUD |
| 2026-10-23 | Personas: missed-something player, dispute-settling Director, set-and-forget player | Agreed by James |
| 2026-10-23 | PROVISIONAL: one entry = one action (option B), grouped by round and turn; mechanics one click away | Answers "what landed on whom" directly; exploring in detail, may be discarded if it does not meet the needs |
| 2026-10-23 | Encounter recap is already served by the victory screen (titles for heroes and monsters by contribution) | James; no new recap output needed for that "why" |
| 2026-10-23 | B3 (pictures first, older play folds up) is the strongest content model so far; not yet THE approach | James: "miles ahead" of today, but the surface (rail panel vs tabletop) was never explored |
| 2026-10-23 | Surface reopened: explore tabletop options before locking the panel | James; the mockups had assumed a rail panel |
| 2026-10-23 | Glance layer = P1, a History tray as a table item (being mocked) | One home whatever the map window does; no new map chrome; fits "users arrange their UI" |
| 2026-10-23 | Symbols follow the roll dialog: edges and banes use its chevron (`drawsteel/Icons_Nav_CollapseArrow.png`, up for edge, two stacked for double), surges its lightning bolt (`game-icons/surge.png`) | James: one symbol per concept across the roll and its record |
| 2026-10-24 | Ricky's feedback verdicts agreed (Appendix M), with forced movement shown as the targeting cross-section on hover | James |
| 2026-10-24 | Glance budget: the glance line shows only what changed the outcome or spent something; the how lives in the detail | Keeps the line readable as more cases fold in |
| 2026-10-26 | Continue from the latest P1 prototype; the gap is presentation and missing functions, not the concept | James, after the reframing interview showed nothing better |
| 2026-10-26 | Rejected: the roll card as the history entry | The timeline roll card itself does not show everything that shaped the roll (e.g. 3 edges and 1 bane netting to a double edge) |
| 2026-10-26 | Rejected as a default: 'since your last turn' catch-up | Assumes how players use it; serves one or two player types; detail-minded players want a specific thing |
| 2026-10-26 | Detail opens as a card beside the tray (one at a time; the row stays highlighted), not inline; it reads what happened, then why (each change to the result as a contrast), then the numbers as a receipt | James, after the three inline layouts all read as confusing: no container, five nesting levels, arithmetic first |
| 2026-10-26 | Search filters the tray in place: an always-visible field, suggestions that become chips (creatures, abilities, conditions, outcome words), chips and words all match, an Active tag on what is still on; History on a token or hero card opens the tray with that creature's chip (replacing the creature popover) | James, approving Appendix U |
| 2026-10-26 | Minimised History is the standard window button with one badge: a grey count of unseen turns (your own turns excluded), gold when an unseen entry touched a creature you control; hover previews "Since you last looked"; opening clears it and lands on "New since you looked". The Director gets the grey count, gold only for players' hand edits | James, approving Appendix V (two levels) |
| 2026-10-27 | David saw a demo of the prototype (tray, detail card, search, minimised block) and thinks it is great | James; David asked for the redesign |
| 2026-10-27 | Players can open History on any token they can see; monster numbers in the detail follow Monster Info knowledge (Stamina tier, characteristics and immunities only once revealed) | James, Appendix W 1 |
| 2026-10-27 | Wording signed off and applied (COPY.md): the name is History; Why lines lead with the cause in Draw Steel's words, then what it did ("instead of", not "X, not Y"); surges are gained and spent; triggers quote the ability's Trigger line; the edge note follows the rules' wording | James, two rounds |
| 2026-11-04 | No encounter-wide turn numbers: a turn is named by its round and creature ("Round 2, the Fury's turn"); folded groups read "5 earlier turns" | James, Appendix W 3; applied to the prototype |
| 2026-11-04 | Reversed the same day: turn numbers stay (a small number on folded turns, "Turn 13" in headings, "Turns 5-9" groups, "Round 2, turn 13" in the card) | James |
| 2026-11-05 | What earns a place: did it change the table? Glance = Stamina, conditions/effects starting or ending, being moved or falling, resources, winded/dying/death/minion deaths. Card only = what explains a number (edges, banes, kit bonuses, potency, immunity amounts, surge split). Left out = what changed nothing (moving on your own turn, a trigger that did nothing, an empty start of turn) | James, REVIEW.md "Step 1" |
| 2026-11-05 | Marker effects stay out of History through a new checkbox on ongoing effects ("Hidden" can't be used: it also removes the Tac panel chip, the Director's manual remove). Label waits on the name. The name (N1, History) is reopened | James, REVIEW.md gap 1 |
| 2026-11-05 | The name stays History, after a for and against (clashes noted: the Director's "Turn History" rewind dialog, the History lore skill) | James |
| 2026-11-05 | Gap 1 closed: History records results where they happen (damage, healing, temporary Stamina, conditions, resources), names the cause, skips what changed nothing; markers get "Hidden from History" | James, REVIEW.md gap 1 |
| 2026-11-05 | Gap 2: the broad fix for effects ending (hooks at removal, end of turn, end of round, sustain tidy-up, lapsed timers) plus a persistence piece for its cause and for walls and areas | James, REVIEW.md gap 2 |
| 2026-11-05 | Gaps 3-5 closed: winded/dying/death as signed-off captions (minions once confirmed, recovery shown); Malice keeps today's split (players see spends, Director sees all; sharing stays the public table tracker); passive numbers named generically through `DescribeModifications`, no per-ability code | James, REVIEW.md gaps 3-5 |
| 2026-11-05 | All eight fixes adopted one at a time (B1-B8), with James's additions: the map arrow's engine change is built here as an engine PR, and a faded ghost (`CreateGhost`) marks the start square; "Active" always shows; S5 becomes "Nothing matches "{search}"." | James, REVIEW.md section 2 |
| 2026-11-06 | After reviewing the build: target cells use the tray's width (face, number and name, captions below); the side-view button sits on the movement line with a real Phosphor icon; David's brief "what happened" beside a closed History is built, with a setting | James, REVIEW.md "James's review of the build" |
| 2026-11-06 | Every changed number reads "{before} to {now}" (no arrow in the fonts; carets tried and dropped); an Ended tag partners Active; a roll the table watched gets a line even if it changed nothing, so failed saves show | James, COPY.md Round 4 |
| 2026-11-06 | Rail and defaults: History gets its own rail button below Chat (the Chat group keeps Chat and Safety); starts closed for everyone, Director included, one click away; two settings stay (History notifications, History Sidebar Preview); the rail button keeps the badge when the tray is off the table | James, REVIEW.md decision 2 |
| 2026-11-06 | Several maps: one History showing one map's fight, the one last clicked (not while reading); a switcher only while more than one map is in combat; badge and preview cover every map you can see; search covers the shown map and its previous encounter | James, REVIEW.md decision 3 |
| 2026-11-06 | Revert keeps rows, faded with a Reverted tag, out of the totals, with a Turn reverted line; History's document is not registered for checkpoints. Undo stays on resource lines. Director keeps Hide/Reveal, Delete entry and Clear History on right-click | James, REVIEW.md decision 4 |
| 2026-11-06 | Out of combat: compact lines in time order under an Out of combat heading between encounters. Keeps this encounter, the previous one and what lies between, across sessions (engine check: document limits). Hovering the ability name in the card header shows the ability card | James, REVIEW.md decision 5 |
| 2026-11-06 | Typed messages: never on the glance; in the card's Why, as written, unless the message is only the ability's name (generic rule, no per-ability code) | James, REVIEW.md decision 5 |
| 2026-11-06 | First-build scope: all ten families (F1-F10) before release, because History replaces the log and nothing may be lost. Built in stages, combat first, then out of combat and Director actions; History runs beside the old log, off by default, until the last stage; the old log goes in the same step that turns History on for everyone | James, REVIEW.md decision 1 |
| 2026-11-06 | Build plan signed off (BUILD-PLAN.md, 27 chunks). Retention gets a hard cap, performance first: try this encounter and the last, cull the oldest, build the newest 30-40 rows and more on scroll, as today's log does. Engine PR agreed in principle | James |
| 2026-11-07 | History is a rail panel window like Chat, not a table item: the rail windows' frame and transparency, pin and pop out. Its height is the user's; Show all only unfolds every turn. Popped out, the card opens inside the window | James, after the 2.1 feedback |

## 3. Open questions

- Which full-session "whys" are worth an output (encounter recap, session summary to a
  journal, catch-up since your last turn)? Candidate list in Appendix C.

## Appendix A - Current-state audit (code, 2026-10-23)

### Surface
- `ChatPanel/ActionLogPanel.lua`: `DockablePanel.Register{name = "Action Log"}`, a rail
  panel. Unread badge with a count of entries from other users since the panel was last
  on screen (`actionlog:lastviewed` per-game preference).
- Chrome per entry: `CreateActionLogCard` - 40px token portrait, name, 6px colour bar
  (player colour, or hard-coded `#AA0000` for monsters), indented 20px when "out of
  turn".
- Lazy history: builds the newest 12 entries, loads 12 more on scroll to top.
- DM-only: right-click Delete Message / Clear Chat / Hide from players; per-roll
  visibility eye.
- No search, no filter, no grouping beyond cast-adoption (below).

### Data model
- The log is a filtered view of the chat store: every message that is not plain chat,
  data, object or a custom message on the "chat" channel.
- Engine cap: `ChatPanel.cs:2193` keeps only the newest **128 messages, shared with
  chat**. One ability cast writes several messages (cast + roll + modifiers, heals,
  resources, notes), so a busy combat holds a few rounds at most. Full-session search
  is impossible on this store.
- Entries store ids, not snapshots: names, portraits and the out-of-turn indent are
  read from LIVE state at render time. A deleted token makes its entries render as 0x0
  (they vanish); a renamed token renames history; "out of turn" is computed against the
  current initiative, not the one at the time.

### What feeds it
Roll messages (every dice roll: power rolls, tests, damage, initiative, Dice panel,
macros, roll-on-table, downtime, montage). A power roll whose `castid` matches a cast
card is nested under it. The power-roll card is also a LIVE interaction surface: amend
edge/bane after the roll, tier rows highlight, amendable rows.

17 custom card types:

| Type | File | Shows |
|---|---|---|
| CastActivatedAbilityChatMessage | DMHub Game Rules/ActivatedAbility.lua:2886 | ability name, type, "Executing...", 28px target portraits; per-target outcomes only in hover |
| ActivatedAbilityDamageChatMessage | Draw Steel Ability Behaviors/AbilityDamage.lua:454 | "N type damage" - only when the content author typed a chatMessage; also squad overflow damage (MCDMCreature.lua:6224) |
| DamageModifierChatMessage | Draw Steel Core Rules/MCDMCreature.lua:5308 | immunity/weakness changed a hit: shield chip, +/-N, source |
| HealChatMessage | DMHub Game Rules/AbilityReplenish.lua:147 | "Regained N Stamina" |
| ResourceChatMessage | Draw Steel V/ResourceChat.lua | resource gain/consume, reason, Undo button |
| MaliceSpentChatMessage | Draw Steel Core Rules/DSResources.lua:112 | Malice diamond, ability, hover = ability card |
| ActionLogNoteChatMessage | DMHub Game Rules/AbilityReplenish.lua:203 | title + detail for a bonus already folded into a roll |
| ActivatedAbilityTemporaryStaminaChatMessage | Draw Steel Core Rules/DSTemporaryHitpoints.lua:20 | temp Stamina granted |
| ActivatedAbilityPurgeEffectsChatMessage | DMHub Game Rules/AbilityPurgeEffects.lua:24 | effects removed |
| ActivatedAbilitySaveEndsToEotChatMessage | Draw Steel Core Rules/MCDMAbilitySaveBehavior.lua:834 | save-ends converted to EoT |
| TeleportChatMessage | Draw Steel Ability Behaviors/AbilityTeleportToLineEnd.lua:9 | teleport |
| StartOfTurnChatMessage | Draw Steel Core Rules/MCDMInitiativeBar.lua:6785 | "Start of Turn" card for every turn |
| BeginRoundChatMessage | Draw Steel Core Rules/MCDMInitiativeBar.lua:6715 | "Draw Steel!" / "ROUND N" banner |
| RollInitiativeChatMessage | Draw Steel UI/DSInitiativeRoll.lua:1173 | initiative roll |
| PatronsGazeChatMessage | Draw Steel Acolyte/Acolyte.lua:509 | Acolyte risk roll (suppresses the standard roll card) |
| SpoilerRevealChatMessage | Timeline/EmbeddedRollDialog.lua:568 | Director revealed a hidden modifier |
| AudioLogChatMessage | DMHub Core Panels/Audio.lua:1014 | "Now playing" / sound effects |

Per-target outcomes recorded only in the cast card's portrait hover
(`ActivatedAbility.RecordTokenMessage`, ~25 call sites): damage dealt, tier achieved,
conditions applied/removed, potency resisted or not, Stamina regained, grabbed, surges
lost, temp Stamina, carrier effects.

Not found in the sweep (no log entry): forced movement (push/pull/slide), conditions
applied or removed outside a cast, manual Stamina edits, winded/dying/death, end of
turn, end of combat, Victories, respites.

### Overlap with newer surfaces
- `Timeline/AbilitySidebar.lua` + `EmbeddedRollDialog.lua`: the live ability card and
  roll dialog, with a read-only copy other players see. The log's "watch it happen" job
  is now largely done there.

### Dormant: the Battle Log document
- `Draw Steel Core Rules/MCDMEncounter.lua:2661-2825`: when an encounter ends, the
  Director's client appends a permanent record to the `dsBattleLog` shared document
  (max 200 battles): what was fought, outcome, duration, per-hero headline numbers
  (damage, taken, prevented, kills, downed). Its own comment calls it "the reviewable
  campaign history". Nothing outside the file reads it: no UI shows it.
- The outcome screen (`Draw Steel UI/DSVictoryScreen.lua`) already turns per-hero stats
  into awarded roles at the end of combat.

### Style debt
Hard-coded colours (`#111111`, `#AA0000`, `white`, `#1194FF`, `#DE1E47`), a bespoke
layout per card type, 40px dice faces and 28pt totals beside 11px subtext; not on the
STYLE_GUIDE row grammar.

## Appendix B - A real log, read cold (James's screenshot, 2026-10-23)

About nine entries fill a tall panel. Problems, in order of cost to the reader:

1. Subject and object are ambiguous. "Orc Conduit / Roll Resistance vs Might / 10
   damage; slowed (EoT)": did the Orc deal it or take it? Targets are tiny portraits on
   some cards and absent on others.
2. The result line is the ability's tier text, not what happened. "5 damage" with three
   targets: to whom, and how much landed after immunity? Whether "slowed" applied
   (potency) is not shown.
3. The biggest things on screen are the least useful: dice faces and a 28pt total. The
   outcome sits in small text below.
4. Contradictions: a Free Strike marked "Aborted" still shows a roll and "6 damage";
   Free Strike labelled "Main Action".
5. Duplication: "Reactor 1 / 2 fire damage / 2 fire damage" (author text plus the
   automatic line).
6. One action spreads across several cards ("Power Roll Test" card, then a separate
   "Power Roll Test: Power Roll" card).
7. The colour bar is red on every entry, so it carries no information. Director-only
   eye icons sit in every roll.
8. No round or turn structure is visible in a scroll of this length.

## Appendix C - Why would anyone want a full-session log? (reasoned guesses)

| Why | Better served by |
|---|---|
| Writing session notes or a recap | A generated session summary written to a journal document |
| "Who carried the fight" / bragging rights | An encounter recap (the Battle Log record and outcome-screen stats already exist) |
| Catching up after being away from the table or joining late | "Since your last turn" catch-up, scoped to your hero |
| Disputes about something two rounds ago | Recall of the current encounter, searchable by creature |
| Resource bookkeeping ("how many Recoveries did I spend?") | The hero sheet's state, not a log |
| Bug reports and support | Developer logging; out of scope for the player-facing design |

## Appendix D - Precedent scan (web, 2026-10-23)

Items marked [unverified] rest on search snippets only.

- Pathfinder Kingmaker / Wrath (Owlcat): one line per action; hover lists every bonus
  and penalty with its source; Combat / Dialogue / Events tabs; enemy stats gated by
  knowledge ("?19-34"). Closest precedent for the "why". https://www.gamebanshee.com/kd8qf
- Baldur's Gate 3: players treat the combat log's math as the source of truth when
  tooltips were wrong (2024). https://mein-mmo.de/baldurs-gate-3-luegt-seit-monaten-tooltips-falsch/
- Solasta: a tooltip saying why a roll had advantage was "one of the most requested"
  features; without it players could not adapt their next turn. https://www.gamebanshee.com/3df88
- Hearthstone history bar: icons for the last ~7-10 plays, blue border yours, red
  theirs, hover for detail. Cautionary case: an entry showed cast-time damage (20), not
  what landed (30). https://hearthstone.wiki.gg/wiki/History
- Into the Breach: prevents the question by telegraphing outcomes in advance.
- Foundry core: no search; GM export to .txt. Modules fill the gap: Chat Trimmer
  (combat rounds summarised, originals one click away, full-text search), Damage Log
  (HP changes with undo; non-owners see less; no "why"), Dice Chronicle (end-of-session
  stats and awards), and **Draw Steel: Battle Log** - a direct competitor that groups
  the chat by battle phase. https://foundryvtt.com/packages/draw-steel-battle-log
- Roll20: chat persists across sessions; the Chat Archive has no search since 2019.
  Users: players Ctrl+F the logs "to locate details in the story".
  https://app.roll20.net/forum/permalink/7658843/
- D&D Beyond Game Log: campaign-wide, cannot be cleared; complaints from 2021 to 2026.
- Owlbear Rodeo: deliberately minimal ("Recent Rolls").

Why people want long history (evidence): finding story details later (Roll20), writing
recaps (bloggers scan the roll log for rolls that changed what characters knew, chose,
lost or risked), stats and awards (Foundry modules). Recap tools for absent players work
from voice transcripts, not the VTT log. Weak or no evidence for streaming or AFK
catch-up.

Gaps nobody fills (opportunity):
1. Dealt vs taken, with the reason ("7 dealt, 5 taken: poison immunity 2").
2. Sessions as a unit (split, clear, recap by session).
3. Built-in search and filter.
4. Per-creature history ("what happened to this goblin").
5. Hidden information: what detail each viewer may see.
6. Glanceable and deep together.
7. Log to recap material.

## Appendix E - Option B explored (2026-10-23, provisional)

Mockup: https://claude.ai/artifact/UpyCsCKpcPuCcsdcrpgzXN (two panels: James's screenshot
re-expressed as B, interactive; and the awkward cases). All copy in it is placeholder.

### Anatomy of an entry
- Head: actor portrait, actor, ability, action type, expand caret.
- One line per target: portrait, name, condition chips (struck through when resisted),
  a reduction marker when immunity/weakness changed the number, net Stamina change.
- Cost line when something was spent (Malice, Heroic Resource).
- Triggered actions nest under the action they interrupted.
- One click opens the detail: rolls with dice, every edge/bane and its cause, the
  printed tier text, per-target math ("7 damage - 2 (damage immunity 2) = 5 taken;
  Stamina 30 -> 25"), potency checks, movement, who rolled and when.
- Grouped under Round and Turn headings.

### The awkward cases and how B handles them (recommendations)
| Case | Handling |
|---|---|
| Triggered action mid-action | Nested under the interrupted action, tagged Triggered |
| Effects with no actor (Bleeding, aura damage, save ends) | Compact effect row under the turn it happened in |
| Resource ticks (start-of-turn Heroic Resource, Malice gain) | Compact row under the turn; Malice on the round heading |
| Director's manual edits (Stamina, conditions) | Compact "Director changed X" row. Not logged today |
| Forced movement, winded, dying, killed, minions killed | Chips on the target line. Not logged today |
| Minion squad | One entry for the squad |
| Hidden creature name | "Unknown creature", as today |
| Director-hidden roll | Shown only on the Director's view, marked hidden |
| Cancelled action with no effect | One muted line |
| Tests, free dice rolls, out-of-combat play | Same row grammar, outside any round |
| Sound log (signed HoH feature, per-player opt-in) | Kept as a muted compact row for those who opted in |

### Tested against the needs
| Need | B alone |
|---|---|
| "I did 7, why did it take 5?" | Yes: reduction marker at a glance, math one click away |
| "Did the condition apply?" (Director dispute) | Yes: chips, resisted ones struck through, potency in the detail |
| "What did the monsters do while I was away?" | Yes: round/turn headings plus one line per action |
| "Why did I lose 14 Stamina?" | Partly: needs a per-creature lens (search/filter category) |
| Set-and-forget player | No: needs outcomes surfaced outside the log (surface category) |

### Where B strains
1. An entry is complete only when the action resolves: it needs an in-progress state.
2. Nesting a trigger needs a link from the triggered cast to the one it interrupted
   (engine check; the roll dialog's trigger phase is the likely place).
3. Revert Turn: entries after the checkpoint must be struck or removed.
4. It needs a structured record per action, written when the action resolves.

### Engine reality for B
- The spine exists: `CastActivatedAbilityChatMessage` already carries castid, caster,
  targets, status, and per-target outcomes via `RecordTokenMessage` (~25 call sites),
  but as display strings. B makes them structured and snapshots names and portraits.
- `DamageModifierChatMessage` is sent from `InflictDamageInstance`, which already
  receives `symbols.cast`, so the reduction can attach to its action.
- Roll messages are separate chat messages and get pruned at 128; the detail layer must
  snapshot roll results into the action record rather than point at them.
- B writes roughly one record per action where today writes three to five messages, so
  the same cap holds more history (a data-model decision later).

### James's reaction to the text version (2026-10-23)
"Easier to read, but I still see a wall of text and bounce off it." Diagnosis:
- Reading is serial; a glance needs things the eye picks up without reading (faces,
  big numbers, icons, position). Every row was sentences at near-equal weight.
- Names repeated three times per action (turn heading, actor, targets).
- Every action from every round at the same level of detail.
- Partly the mock: initials instead of token art, no condition icons.

Two picture-first variants added to the canvas:
- B2 "pictures first": the turn heading names the actor once; each action is its
  ability name plus target portraits carrying the Stamina change, a condition badge
  (slashed when resisted) and a shield badge when immunity changed the number. Text
  lives only in the one-click detail.
- B3 "older play folds up": as B2, but the further back, the coarser. Earlier turns
  fold to one line (actor, then who they hurt and by how much); earlier rounds fold to
  one line (who lost how much). A "New since you looked" divider marks where to start.

## Appendix F - Surface options: rail panel vs tabletop (2026-10-23)

### What the tabletop offers (verified)
- The table is personal: maps live in windows on it; each user arranges their own
  table; the Director shares items with a share button (`DMHub Game Hud/Tabletop.lua`,
  `dmhubclient/TABLETOP_MAP_WINDOWS.md`).
- **Combat is per map**: round, initiative and combat banner belong to the map's
  window, and several windows can each be in combat. A banner missed because no
  window showed the map plays when the map is next shown. Today's log is global, so two
  fights on two maps interleave in it.
- Modules can put their own items on the table: `Tabletop.itemKinds[kind]` (available,
  exists, name, size, face), moved, resized and removed like NPC cards, saved per user.
  First user: the Audio soundboard pad.
- Rail entries for other modules: `RailEntryTypes` in DocumentSystem.lua.
- NPC/creature cards (built from the EotW hero card) and token HUDs exist.
- Table dice are deliberately unlogged "fidget rolls": a precedent for leaving things
  out of the record.
- The Director's Screen: a private band for the Director's own items.

### Options
| | Where it lives | Reaches the set-and-forget player | Fights on two maps | Respects "users arrange their UI" | Main risk | Build |
|---|---|---|---|---|---|---|
| S1 Rail window | A window opened from the rail (today's surface, B3 content) | No | Needs a map filter | Fully | Still hidden; only opened when confused | Low |
| S2 Table item | An object you lay on the table (a battle record), per user; the Director can share it | Only if placed | Needs a map filter | Fully | It is S1 with different chrome; new users never place it | Low-medium (itemKinds exists) |
| S3 On the map window | A history strip on each map window, like the initiative bar: last few actions as portraits and numbers; click opens B3 | Yes: it is where they already look | Scoped per map by nature | Partly: it adds to the window's chrome (must fold away) | Takes map space; tight in small windows | Medium |
| S4 On the creature | Token hover and creature/hero cards show what happened to that creature, with causes | Yes, for their own hero | Per creature | Fully | Answers creature questions only; hover needs a non-hover path | Medium |
| S5 Pushed moments | Each resolved action leaves a short card on the table that settles into a history pile or strip | Yes | Per map if it settles on the window | No: it takes attention | Noise mid-turn; overlaps the ability sidebar | High |

### Recommendation (pending James)
Layered, with no single "log" surface:
- S3 is the glance: a per-map history strip on the map window, collapsible, whose
  latest turn reads like B3.
- S4 answers "what happened to me / to it" on the creature itself.
- B3's full view opens from either, in a window the user places (rail or table:
  S1 and S2 are the same view in two containers).
- S5 only as a transition: the ability sidebar's live card shrinking into the strip
  when the action resolves, which teaches where history lives.

## Appendix G - Playable tabletop mock of the layered approach (2026-10-23)

Canvas board "Layered approach on the tabletop (playable)" (the canvas now opens on it):
https://claude.ai/artifact/UpyCsCKpcPuCcsdcrpgzXN

Real material from the running Codex (bridge, read-only; the bridge session was told
before and after): the Inn of Beginnings map window with its tokens (screenshot), the
app title bar and action bar, the rail buttons, token art and condition icons copied
from the image cache with `assets:ResizeCachedImage`, and the marble surface texture
from the engine repo (`Assets/Resources/Tabletop/TabletopMarble.jpg`). Numbers and
copy are mock.

What it shows:
- S3 strip hanging from the map window's title bar (where Round 2 lives). Newest on the
  right, pinned next to Full log; older turns shrink, Round 1 is one chip; the oldest
  slide off the left edge. History in the title bar folds it away. Click an entry for
  the B3 detail (rolls, tier, immunity math).
- S4: click any token for what happened to it this encounter, with causes. The player's
  hero card ("Your turn") lists what happened since their last turn (-14 Stamina).
- Full view: Full log on the strip, or the rail's Action Log button, opens B3 as a
  window on the table.
- S5 transition (Play): the ability card slides in, dice roll, Tier 2 lights, -5 with
  a shield and "8 - 3 immunity, pushed 2" rises over Reactor 1, then the card shrinks
  into the strip's newest slot and the strip makes room for it.

Open questions the mock raises:
- The strip covers the top of the map: acceptable, or should it sit outside the window
  frame (below the title bar, on the table)?
- Does the token-click history clash with the existing token click (select) and the
  token HUD? A hover card plus a click path may be needed.
- Where does the hero card live for a player who already has the hero sheet open?

## Appendix H - James's play-test of the mock, and the code behind it (2026-10-23)

### Feedback
1. The top of the map window is the initiative ribbon: the strip cannot hang there.
   Outside the map might work, but a maximized map has no "outside".
2. Hero cards are small (132 wide) and are getting a flip-to-back: no stacking
   information on the face; at most a hover button that opens the log.
3. Hovering a token shows the character panel; clicking gives the radial menu.
   A "history" slot in the radial for your own hero is plausible; what a player sees
   for a monster is an open point.
4. The S5 fold (ability card into the history) is liked, with performance concerns.

### What the code says
- Map HUD: the initiative bar, and the Director's villain-action, reinforcements,
  cues, encounter-actions and boss bands, move into the live window's overlay at the
  top (`Tabletop.lua` `PlaceMapHuds`, `ScaleMapHuds`: full width 1180, shrinks in
  narrower windows). Maximized, the window's titlebar rows move into a strip hung from
  the app title bar and the map HUD starts below it.
- Maximized maps sit at the bottom of the stack; journals, panel windows, NPC cards and
  other table items float over them. The Director's Screen is hidden while a map is
  maximized.
- Table items from modules (`Tabletop.itemKinds`): moved, scaled and removed like NPC
  cards, saved per user with the layout, keyed by a string. First user: the Audio pad.
- Action bar: bottom centre of the screen, not the map; its drawers already show the
  last-used ability's icon; the trigger reaction panel is bottom centre too.
- Hero card (`Codex Titlescreen/EotwHeroCard.lua`): 132 x ~200. Card back
  (`HeroCardBack.lua`, Lisa, prototype on main): a 26 px hover-only flip chip at top
  centre (`CreateFlipButton`), back pages turned by footer arrows.
- Radial menu (`DMHub Token UI/TokenUI.lua:2633-2860`): on a token you control,
  Character Sheet, Inventory and Emotes, plus the slots below. **On a token you do not
  control there is a radial too**, with one or two slots: Monster Info (when the
  `monsterinfo` setting is on) or View Portrait, and Rename (when players may rename
  monsters). Free angles remain.
- Ghost animation precedent (`Tabletop.lua:2374` `AnimateGhost`): minimizing flies one
  image panel (think every 0.01 s, about 0.26 s) and destroys it; the real window
  collapses at once. No live panel tree is animated.
- Turn Rewind (`MCDMInitiativeBar.lua:411-1440`, prototype, on by default): while you
  play your turn it keeps checkpoints before and after each ability and move, with a
  plain-text list of what happened between them (Turn History dialog, `/rewind`). Local
  to the acting client and that turn only. Opportunity: "rewind to before this" from
  your own entries.
- Hero sheet performance rules (build plan, round 3): no per-frame work while idle,
  push not rebuild, frost on one surface only. The log should meet the same bar.

## Appendix I - Revised layered design after the play-test (proposal, 2026-10-23)

### Where the glance layer lives (open: James to pick)
| | P1 History tray (table item) | P2 Under the map window | P3 On the initiative ribbon |
|---|---|---|---|
| What | A compact B3 strip as a table item (`Tabletop.itemKinds`), showing the live map's combat | Hangs from the window's bottom edge, outside the frame | Each creature's ribbon entry gets an outcome badge; hover or click shows its turn |
| Maximized map | Floats over it, like cards and journals do | No outside: needs a second home (screen bottom-left) | Comes along: the ribbon moves with the map HUD |
| Covers the ribbon or map | Only where the user puts it | No | Adds to the ribbon's crowding |
| Users arrange their UI | Yes: move, scale, put away; default spot in the built-in Views | Fixed to the window | Fixed |
| Out of combat (tests, rolls) | Yes | Yes | No ribbon out of combat |
| Build | Low to medium (item kinds exist) | Medium, two homes | Medium; touches a busy file |

Recommendation: P1. One home whatever the window does, no new map chrome, and it
follows the rail philosophy. P3's idea (history keyed to turn order) is worth keeping
as the tray's own grouping, which already runs by turn.

### Per creature
- Radial: a History slot on any token you can see. Your own hero: yes. A monster: open
  question; recommendation: the events players already saw (no hidden numbers), with
  Stamina only as Monster Knowledge allows.
- Table cards: a hover chip beside the flip chip, opening the same creature history.
  Nothing added to the card's face.
- Both open one creature-history popover; "See all" opens the full log filtered to that
  creature.

### The S5 fold, built cheaply
As the Tabletop's minimize does: the ability sidebar closes as it does today, and a
single small ghost (the tray entry's look: two faces and a number, 3-4 panels) flies to
the tray slot in about 0.3 s, then the real entry is appended (never a rebuild). No fold
when the tray is not on screen; reduce-motion turns it off. Budget: under 0.5 ms CPU a
frame during the fold, nothing while idle.

## Appendix J - P1 mock (2026-10-23)

Canvas board "P1: History tray on the table (playable)"; the canvas opens on it. The
earlier strip board is kept, marked superseded.
- History tray: a table item at the left of the table (hover titlebar with close,
  corner grips), B3 inside: Round 1 folded, earlier turns folded to one line, the latest
  turn open with picture rows; click any turn or action for its detail. "Full log" grows
  the same item to full height with every turn open. The rail's chat-bubble button puts
  the tray on or off the table.
- Radial: click any token. The History slot (gold, top) sits beside the real slots:
  Character Sheet, Inventory, Emotes, View Portrait on your own hero; Monster Info on a
  monster; View Portrait on another hero. It opens the creature's history; "Show only
  them in History" filters the tray to that creature.
- Hero cards (132 x 192): a History chip (gold, top left) shows on hover beside the flip
  chip; nothing added to the face.
- S5 fold: Play runs Dwarf Fury's Brutal Slam; the ability card closes as today and a
  small stand-in (two faces and -5) flies into the tray's newest slot, then the entry
  appears and the previous turn folds. No fold when the tray is off the table, filtered or
  grown to the full log.
- Monster history shows Healthy / Winded rather than numbers, to illustrate the Monster
  Knowledge rule (open question).

## Appendix K - Every case in the P1 tray (2026-10-23)

Canvas board "P1 tray: every case, Director or player view" (the canvas opens on it):
four trays side by side. Switch Director / Player in the board's Tweaks (viewer).

### Row grammar it settles (proposal)
- Action row, glance: ability name, then chips for what shaped the roll, then the
  targets (face, net number, condition badge, one or two captions).
  - Chips: Edge / Double edge (green, up triangles), Bane / Double bane (red, down
    triangles), Cancel out (muted), surges (gold, with what they bought), Heroic
    Resource cost (blue diamond), Malice (red diamond), Critical (gold fill), and
    neutral chips for Rerolled, Changed after the roll, +N from an ally.
  - Captions under a face: Push N / Teleported N / Collision, Immunity -N, Fire
    weakness +N, N soaked by temp, Resisted, Winded (amber), Dying (red), Killed and
    N of M killed (red fill), Spent a Recovery, Ended X.
  - Numbers: damage red, healing green, temporary Stamina blue.
- Action row, detail: Power roll (dice + characteristic + edges), the edge/bane line
  naming each source and the tier change, the printed tier text (italic), surges and
  what they bought, per-target math, cost, movement, who rolled and when.
- Compact rows for everything without an action: resource ticks (with the hero's
  face), start/end-of-turn effects, saving throws (end of turn), auras, Director hand
  edits, hidden rolls (hatched, Director only), dice, tables, class roll cards, sound.
- Banners: Draw Steel! with initiative, Combat ended with a link to the victory screen.
- Undo and revert: the undone row or the reverted turn stays, struck through, under a
  "Director reverted..." row.
- Out of combat: tests, montage and negotiation rows end in a result chip instead of
  target faces.

### Player view differences
Hidden rolls disappear; a hidden monster shows as "Unknown creature" with a dark face;
monster Stamina numbers become Winded / Killed; Malice totals are kept (players already
see what Malice bought).

### Rules checked (ClaudeRefHeroes.lua and draw-steel-rules memory)
Edges +2, double edge or bane = one tier, edge and bane cancel; natural 19-20 = Tier 3
and a critical (another main action) on a main action; surges: up to 3 for extra damage
equal to the highest characteristic each, or 2 for +1 potency on one target; cover =
bane, high ground and flanking = edge; prone = edge for melee against it; Weakened =
bane on power rolls; Bleeding = 1d6 + level on a main action; saving throws at end of
turn, d10, 6+.

### Not yet shown
Several creatures' triggered actions on one roll (a stack), a roll with several
damage types, an ability that hits allies and enemies alike, and a long minion
squad fight.

## Appendix L - Shareable P1 prototype (2026-10-23)

Standalone link for reviewers: https://claude.ai/artifact/UPWo9XvYuaDiZ388xRES35 (private
until James shares it). The design canvas (UpyCsCKpcPuCcsdcrpgzXN) opens on its P1 board
again, so the link already sent still shows P1.

A two-round encounter on the Inn of Beginnings, from James's view (Dwarf Fury), with a
"View as" control for the Director. The tray folds Round 1 and earlier Round 2 turns;
everything unfolds, and every action opens its detail. It folds in the catalogue cases
plus the four that were missing:
1. A trigger stack on one roll: numbered rows under the action, in resolution order,
   tagged Before the roll / After the roll / Free (Zakaarior's bane, the Censor's 3 holy,
   the Null's Discipline +1).
2. Several damage types in one hit: the caption reads "6 fire, 4 cold" and "Fire
   immunity -3"; the detail does the math per type.
3. An ability that hits allies and enemies: foes first, then an amber "Ally hit" group,
   plus a "Hit an ally" chip.
4. A minion squad across turns: one face for the squad, "2 of 4 killed", then "Squad
   destroyed".
Also: edge, double edge, bane, surges for damage and for potency, Malice costs, an ally
bonus, conditions applied and resisted, winded, a hidden roll (Director view only), and
monster Stamina as Healthy/Winded for players.
The demo's roll card carries the roll dialog's edge/bane bar (BANE BANE X EDGE EDGE with
chevrons) and surge bolts, lighting the double edge, the tier jump and two spent surges
before the card closes and the stand-in flies into the tray.

## Appendix M - Ricky's feedback, triaged (agreed by James 2026-10-24, with the change below)

Ricky (dev, has thought about the log for a while) reviewed the P1 prototype. A data
point, not a direction. He liked the roll moving into the log and the fold-and-drill.

### Proposed rule: the glance budget
The glance line shows only what changed the outcome or spent something: who, the
ability, the tier, edges and banes, surges, costs, a critical, the net number per
target, conditions (applied, resisted, immune), a state change (winded, dying,
killed) and movement distance. Everything that explains how (sources, flat
modifiers, per-target edge lists, paths, rolls) lives in the detail. Exceptions
earn a place on the glance line only when they differ between targets.

### Verdicts
| # | Ricky's point | Verdict | Where |
|---|---|---|---|
| 1 | Show why surges came (banked vs granted by e.g. Trained Assassin) | Include | Detail: each surge's source, and "lost if unused" (the roll dialog already knows this, EmbeddedRollDialog.lua:3747) |
| 2 | Show roll modifiers (e.g. +1 rolled damage on Fire abilities) | Include | Detail only: already inside the number; a chip each would crowd the line |
| 3 | Different tiers per target (edges/banes per target; minion squads) | Include | Glance: per-target tier only when targets differ; detail lists each target's edges and banes (per-target boons exist, EmbeddedRollDialog.lua:1668) |
| 4 | Tier at a glance | Include | One tier badge per action (the roll card's <=11 / 12-16 / 17+ badge); per-target badges only when they differ |
| 5 | Minion squads attacking | Include | Caption "2 minions" on each target when they differ; detail per minion |
| 6 | Forced movement shown as a path, falls | Include, on hover | Caption "Push 3, fell 10"; hovering it (or clicking, for a non-hover path) shows the side-on movement cross-section the targeting tooltip already draws (`MovementCrossSection.cs`, `dmhub.SetMovementCrossSection`, `MOVEMENT_CROSS_SECTION_REFERENCE.md`), with its red collision and fall badges. James 2026-10-24. Needs the path stored at the time and a way to rebuild it for the renderer (engine check) |
| 7 | Turn numbers ("look at turn 15") | Include | A small number on each turn heading; round headings stay |
| 8 | Turn auto-populates Main / Maneuver / Move slots, colour coded, collapse after 30 s | Partial | Three small action pips on the current turn's heading only, filled as used. No empty placeholder rows. Turns fold when the next turn starts, not on a timer (a timer moves rows under the reader). Colour only alongside text |
| 9 | Saving throws and condition ends, with the cause (save, end of turn, Healing Grace) | Include | A row each; the creature's history shows applied and ended. Not recorded today |
| 10 | Target deaths | Include | Already: Killed caption; a row when death comes outside an action (Bleeding) |
| 11 | Trigger consistency (Tactician's mark +4 damage, Talent's Feedback Loop source) | Include, as a rule | Every triggered or free effect sits under the action that set it off and names it. Engine work: link a triggered cast to its cause |
| 12 | Condition immunity when a condition is inflicted | Include | Struck condition badge with an "Immune" caption, the same grammar as resisted |
| 13 | Always open vs open when needed (Matt, Ricky: always; Lisa: hide by default, players found the old one confusing) | Both, via defaults | The tray is a table item; the built-in Views decide the default. Proposal: on for the Director, one click for players. Defaults category |

New persona: the always-on follower (Matt, Ricky): keeps it open and glances at it
between turns. The tray's fold-by-age already serves them.

Kept out on purpose: flat modifiers on the glance line, empty placeholder rows, timers,
paths shown by default, per-target edge lists on the glance line.

## Appendix N - Prototype round 2: Ricky's points folded in (2026-10-24)

Same link (https://claude.ai/artifact/UPWo9XvYuaDiZ388xRES35), now 13 turns over two rounds.
- Turn numbers on every turn (folded and open); round headings stay.
- Fold by age, one level more: the compact tray shows Round 1 as one line, Round 2's
  turns 5-9 as one "Turns 5-9" line, then turns 10-12 one line each, then the current
  turn open. Full log opens everything.
- Current turn heading carries Main / Maneuver / Move markers (Move used; Main fills when
  Play resolves the Brutal Slam).
- Tier badge on every action line (the roll card's <=11 / 12-16 / 17+); per-target tier
  badges only where targets differ (turn 6: Orc and Null Tier 2, the Fury Tier 1 because
  of cover).
- Minion squad attacking: "2 minions" / "1 minion" under each target (turn 2).
- Surge sources in the detail (turn 10: 1 banked, 1 from Trained Assassin, lost if
  unused); roll bonus in the detail (turn 11: +1 rolled damage on Fire abilities).
- Saves and condition ends: the Null's end-of-turn save (turn 7), Slowed ending at end of
  turn (turn 9), Grabbed ended by Healing Grace (turn 9) and by the grabber being pushed
  away (turn 12).
- Trigger causes: the Tactician's Mark +4 nested under the Shadow's strike that set it
  off (turn 10); death shown as Killed.
- Condition immunity: Frightened struck through with "Immune: frightened" (turn 12).
- Forced movement: "Push 3 · fell 4" (turn 12) shows the side-on cross-section on hover
  (click pins it), modelled on the targeting tooltip: ground silhouette on the tile grid,
  pusher and mover, blue push arrow, red fall arrow, landing ghost with a red -6 fall
  badge.

## Appendix O - Play runs two turns and a round change (2026-10-24)

Play on the prototype now runs about 16 seconds:
1. Turn 13, Dwarf Fury: Brutal Slam (double edge, two surges) as before; the card closes
   and its stand-in folds into the tray; Main fills on the turn heading.
2. Turn 14, Reactor 1 (enemy): the turn heading appears and turn 13 folds to one line;
   the read-only roll card a player sees while the Director rolls; the Troubadour's
   trigger arrives before the roll (blue ring on the Troubadour, a "Triggered" strip on
   the card, BANE lights); 13 - 2 = 11, Tier 1; -4 fire rises over the Fury and the
   Elementalist; the Fury's hero card flashes red (the EotW card's hurt wash) and drops
   to 9 / 33; the stand-in folds the attack, with the trigger nested, into the tray.
3. Round 3: Round 2 folds to one line, the Round 3 heading shows the Malice gain, and the
   Troubadour's turn opens with Drama +2.
The "Turns a-b" group grows as turns pass (5-9, then 5-10): fold by age, live.

## Appendix P - "Not there yet" (James, 2026-10-25)

After the longer Play: better than today, but hard to parse what was going on, and
"something about the design doesn't sit right". James's read: we may be tied to what an
action log is in the current system and in other games, without having settled what it
means for the Codex and Draw Steel. Re-opening the framing through an interview
(candidate reframes in the session, not yet in the brief).

### Interview, round 1 (James, 2026-10-25)
- Real questions at the table: "What just happened? Where did that damage come from? Why
  am I slowed?" Worst with collision and forced-movement damage, triggers and auras. The
  answer is in today's log, but clicking in to get it is part of the problem. People open
  the log or ask the Director.
- The longer Play was hard to parse: matching tray entries to tokens, a lot happening at
  once, and telling prototype pieces from today's interface.
- Ideal in one sentence: "The Codex is great, it's clear what's happening and if I ever
  miss anything, the action log catches me up in no time, I can even get a blow by blow if
  I need it."
- Reframes: A partly (the answer at the thing that changed, but order of events still
  matters); some B (the enemy turn); C on theme for cinematic moments; D cool but too
  slow; E solved elsewhere.
- The cross-section on hover was not discoverable.

### Code check
When damage lands, the token floats only the number (`DMHub Token UI/TokenUI.lua:2150`,
red `floatlabel`), though the damage entry already carries its type (including `collide`
and `fall`) and the attacker id (used for the hit sound).

### Emerging hypothesis (to test with James)
Three layers, of which we have only designed the third:
1. In the moment: the effect names its cause where it lands ("-2 collision", "-3 aura",
   "Slowed: Power Roll Test"). Prevents most questions; the data already exists.
2. Catch-up: the tray answers "what happened since I last looked", in order, folded,
   with cinematic moments marked.
3. Blow by blow: the detail one click away.
Tying them together: hovering an entry lights its tokens on the map (and the reverse).
Draw Steel angle: much of what hits you is indirect (forced movement, collisions, falls,
triggers, auras, ongoing effects), often on someone else's turn; making the indirect
visible is the Codex's job here. Anything with more to show (the cross-section) needs a
visible cue, not hover on text.

### Interview, round 2 (James, 2026-10-25)
- The three-layer reading is not the whole answer: "something else is still nagging".
- Causes on the map: clutter is a real concern; a turn can have a lot of damage flying
  around. Sound effects per damage type already help. A reason might help, but carefully.
- When people need catching up: when they weren't paying attention, not at a game phase:
  someone came into the room, they were reading something else, they went to the toilet.
- Cinematic moments: tokens already show visual effects; marking them in the history is an
  event row, and the map shows it. The list so far covers the moments James can think of.

### Interview, round 3 (James, 2026-10-25)
- "Welcome back" card: asked how we would know the user wasn't there.
- "Told, not decoded": interesting; math-focused groups may find it harder to parse,
  but with the blow-by-blow behind it, it could work.
- "One place" (live card and history as one strip): no. The Codex works hard to keep the
  play space clear: only what players and Directors put there, plus what is needed when it
  is needed (the roll dialog appears only as needed).
- "Your story first": no. A tactical game about synergising with teammates.

### Finding: the Codex already remembers state on the things themselves
- `StatHistory` (`DMHub Game Rules/Creature.lua:22-120`): each creature keeps its last 8
  changes to Stamina, temporary Stamina, max Stamina, Heroic Resource, surges and other
  resources: the note (cause), resulting value, who, when, disposition, attacker. Synced
  with the creature.
- Shown on hover: the character panel's Stamina bar shows the Stamina history tooltip
  (`MCDMCharacterPanel.lua:5313`, `gui.StatsHistoryTooltip`); table trackers (Malice, hero
  medallions, counters) show their change history in a tooltip (`TableDice.lua:2617-2660`).
- Ongoing effects record who applied them (`casterInfo.tokenid`, `OngoingEffect.lua:384`).
- Absence: the engine tracks app focus (`Application.isFocused`, InputController's
  background throttle; frame-time windows count `focusedSeconds`) but exposes no plain Lua
  field for focus or input idle time. Small engine addition. It cannot tell "looking at the
  screen but talking"; the new-since-you-looked marker and an on-demand button cover that.

### Candidate reframe (to test)
Not a log, but memory on the things: every piece of state on the table (Stamina,
conditions, resources, Malice, trackers) remembers its own recent story and shows it when
you look at it. The History tray is those memories woven into time order, for catching up
and the blow by blow. Builds on systems that exist instead of a separate log store.

### Interview, round 4 (James, 2026-10-26)
- The conversation drifted away from the prototype; the latest prototype is the much
  better direction, though still visually confusing.
- The real questions: on a table people control, how do they know there is something
  in the history, and how do they bring it up fast? Idea: the minimized block (as other
  tabletop HUD pieces) gets a small notification.
- Keep: the timeline power roll folding into the history (a great indicator); search.
- "Why am I slowed?": people hover the condition on their token (it shows who applied it
  and with what), or open the log. Few know the Stamina history hover exists, and it only
  answers about your own creature; only the Director sees everything. Splitting history
  across many places segments it.
- Idle detection is unreliable (reading a phone at the desk). "Since your last turn" is
  more promising.
- Replay and rewind: interesting, but performance worries on older laptops (Transparent UI
  off, lowered settings); nobody should be locked out.
- Wants the missing piece that ties it together into an "oh, I understand" moment.

## Appendix Q - What players actually report (in-app feedback, 2026-10-26)

Searched 2,085 feedback tickets (titles and triage areas; full text for the 12 most
relevant), read-only via the bug-fix scripts.
1. The log is the source of truth, so it must show what landed.
   - FRAKESH6: "action log shows the wrong damage when orc conduit uses their trigger to
     give double edge" (rolled 7, the trigger made it 12, the log showed 7 and 9 damage).
   - XP78F954: "I didn't get a second main action after my crit despite the log saying I
     would."
   - D2HJ593U: the dice showed 1, the log showed 2. J6JDYWGT: a double bane still logged
     Tier 3.
   - XJNFC7VA: a player reports a bug citing "you can see the roll in the action log":
     players use it as evidence.
2. Getting to it in the rail era.
   - 7M3H2C59: "I can't pull up my Action Log." Pop-out bugs: 4FJ5VYME, K6H9J536,
     ZDNC938Z, Y4AGUAW5.
   - AM79CDYV: "Action Log and Chat windows always have a red dot on them." A notice that
     is always on means nothing.
3. Completeness and teammates' results.
   - P94P9TDZ: "Missing 2 players rolls in the action log." JVDB4DH4: "My action log is
     not updating." 985MMSPH: "Can't see other players result on Presence Test."
4. "Why" questions beyond damage.
   - M4QPGE2V: "Why did I get my Maneuver back?" XJNFC7VA: Drama gained on a roll that was
     not a natural 19. 47Y6C8ET: "I don't really know what happened when I used Dramatic
     Reversal."
5. Noise: MYEJSNWK: "Provide a way to clear the action log. There is a bunch of junk in
   there from my players experimenting."
6. Hidden information: 48NDEWA9: the Draw Steel banner listed monsters still hidden.
No GitHub issues in VerisimLLC mention the action log.

### Interview, round 5 (James, 2026-10-26)
- Not the roll card: the timeline roll card is not in its final form, and it does not show
  everything that influenced a roll. Edges and banes cap at a double and cancel each
  other: 3 edges and 1 bane show only as a double edge, and the player never learns there
  were 3 edges. People go to the action log for that; the history detail must show it.
- The prototype's expanded detail is not as readable or quick to parse as it should be;
  possibly just prototype finish, but it needs work.
- "Since your last turn": torn. It assumes how a player will use it. Player types (Robin
  D. Laws' archetypes: tactician, storyteller, casual and the rest) all play Draw Steel in
  the Codex; a round-up serves one or two of them. If we cannot tell what a player cares
  about and serve the wrong thing, they dig anyway and it is no better than today.
- Conclusion: the latest prototype was closer; it may need better presentation and more
  functionality rather than a new concept.
- Search terms people would use: creature names, ability names, conditions ("slowed" shows
  why you are slowed). Not "turn 15".
- Turn numbers: James is not sold (order of turns rarely matters to him), but he is one
  player type; open.

### Persona lens update
Design for Robin D. Laws' player types rather than a single "player": Power Gamer,
Butt-Kicker, Tactician, Specialist, Method Actor, Storyteller, Casual Gamer. Each pulls a
different layer: glance (Casual, Butt-Kicker), the roll's full arithmetic (Power Gamer,
Tactician), search (Specialist, Tactician), cinematic moments (Storyteller, Butt-Kicker).
Principle: let each pull what they want fast, rather than guessing and pushing a summary.

## Appendix R - What players say in public (web research, 2026-10-26)

Sources: r/drawsteel (all Codex posts Jan-Oct 2026 via the Arctic Shift archive, comments
on ~25 threads), ~39 Steam reviews and Steam discussions, EN World. Quotes paraphrased
except one; links in the session report. Some Steam reviewers and Reddit posters are
testers or team-adjacent.

Themes (independent sources):
- Can't tell what the automation did or why: ~10. zupancia (23 Oct, regrets choosing the
  Codex over Foundry): "Every session we have problems figuring out what the automations
  have done and why." Also: is that right or a bug; a Null "pinballing" around the map
  leaves a new Director asking what happened; stability and conditions applied without
  explanation.
- The log is too thin for the why: ~5 plus the team's own acknowledgement. Triggers fired
  without anyone knowing which event they answered; a Recovery spent from a prompt nobody
  could trace (HornScrub, 1 Sep). "See why a roll hit tier 3 and what made up the final
  damage" (ThrowbackPie, 9 Jan). Codex team (10 Jan): plans for a more complete log with
  references on everything.
- Collapsing into one damage total felt less impactful than seeing the forced-movement-
  into-a-wall maths (johnleeuk21, 9 Jan): clarity and drama.
- Trigger prompts fleeting or hard to source: ~6. Whose step is next in multi-actor
  resolution (Dramatic Reversal): ~3.
- Requests: inventory changes in the log ("bookkeeping game changer").
- Praise: conditions clear on tokens, initiative greys out who acted, minion grouping,
  allies' trigger prompts help table talk, rewind, less bookkeeping: ~12.
- Not found: complaints about Malice or the Director's turn; YouTube and other socials had
  nothing indexed.

Read: the strongest public pain is the why, especially for triggers and composite
damage. It touches retention (a group considering moving to Foundry).

## Appendix S - Readable detail: proposal (2026-10-26, awaiting James)

Board "Expanded detail: three layouts" on the prototype link (image:
`detail-options.png`). One roll opened three ways: Dwarf Fury's Brutal Slam, three edges
(flanking with Zakaarior, target prone, high ground) and one bane (Reactor 1's trigger
when targeted) netting to one edge: 7 + 2 + 2 = 11, Tier 1; then two surges and damage
immunity 2: 7 taken.

Rules note: three edges and one bane net to a single edge, not a double edge (edges count
up to two; one bane cancels one). The code agrees
(`MCDMAbilityRollBehavior.lua:80`, `GetRollModFromEdgesAndBanes`). That is the case the
detail must explain: the player saw three reasons for an edge and got Tier 1.

Options:
- A. Receipt (recommended): two sums (power roll, then each target's damage) in the order
  they happened, one fact per line, every number in one right-hand column, each edge and
  bane named under the line it changed, with who or what granted it (face or icon).
  Familiar maths for Power Gamers and Tacticians; the right column scans in a second.
  Taller than today's grid.
- B. Sum line: each sum on one line of chips; sources wait behind a hover. Shortest, but
  it repeats the roll card's problem (the net hides the sources until you dig) and hover
  is weak on touch and for people who do not know to try it.
- C. Pictures: the roll dialog's edge/bane bar, a tier track showing how close the roll
  came, the damage as a bar. Most visual; most to build; grows tall with several targets.

Rules for any layout (the finish James asked for):
- The detail uses the tray's full width, not the indent under the turn face.
- Body text 14-15px; one fact per line; numbers in tabular figures in one column.
- Order of resolution: roll, edges and banes, tier, then per target, then cost and who.
- A trigger sits at the point in the chain where it fired and says what set it off
  ("when targeted", "after the roll"), answering "which event did it respond to".
- When a cancelled or capped source changed the tier, one muted line says what it would
  have been ("Without the bane: double edge, Tier 2"). Only then.
- Same symbols as the roll dialog: chevrons for edges and banes, the surge bolt.

Engine check: a stored roll keeps only the net counts (`boons`, `banes`, and per-target
offsets in `multitargets`; `CalculateMultitargetsFromRollProperties` caps each at two).
The roll dialog knows each named source at roll time (`m_activeModifiers`, snapshotted
per target as `modifiersUsed`, `EmbeddedRollDialog.lua:5642`), and edges added with the
dialog's own +/- buttons have no source. Showing sources means writing a small list
(source name, edge or bane, from whom, before or after the roll) into the roll when it is
accepted, plus a "set by hand" entry for the buttons.

### In play (2026-10-26)
James asked to see the three layouts in play. The prototype link now has a "Detail
layout" switch (A receipt / B sum line / C pictures) in its controls, applying to every
action's detail in the tray, plus "Open the Brutal Slam" after Play.
- Play: the Fury's roll card starts on a double edge (three edges); Reactor 1's trigger
  fires when targeted (blue ring, "Triggered" strip) and the bar drops to one edge; 4 + 3 +
  2 + 2 = 11, Tier 1; two surges; 7 taken after damage immunity 2.
- Every action's detail is now structured data (roll, edge/bane sources, per-target sums,
  triggers, costs) read by all three layouts, so the comparison holds across the tray:
  per-target cover bane (turn 6), two damage types with a bonus and fire immunity
  (turn 11), surge sources and a triggered Mark (turn 10), a bane that cost a tier
  (turn 14), healing (turn 9), a fall (turn 12).
- Scenario changes for consistency: Reactor 1 has damage immunity 2 (so turn 7 deals 4)
  and was knocked prone in turn 7 (the prone edge's source); turn 11's two-type hit moved
  to Test Monster Z 1 (fire immunity 3).

### James's play of the three layouts (2026-10-26)
- The layering confuses: the action row is indented, but its detail folds out unindented
  (my full-width rule), so it is hard to tell whether there is more to expand, or where one
  row's detail ends and the next row begins.
- All three layouts were hard to parse; it was hard to understand what had happened.
Read: two problems. Structure: the detail has no container of its own, and the tray now
has five nested levels (round, turn, action, detail, target) in 410px, with one signifier
(a caret) doing two jobs. Content: every layout opens on arithmetic, not on what happened
and why; the reader has to work the story out of the sums.
Proposal (awaiting James): a detail card beside the tray instead of folding inline; the
card opens on what happened, then why (each thing that changed the result, phrased as a
contrast: "Tier 1, not Tier 2: ..."), then the numbers as a receipt.

### Built: the detail card (2026-10-26)
Same prototype link. Clicking an action row (chevron on the right) opens its card beside
the tray; the tray keeps its shape and the row stays highlighted. Carets on the left only
fold. The card: header (actor, ability, action type, round and turn, close), What
happened (one sentence per creature, with face and number), Why (each change to the
result as a contrast; "a straight roll" when nothing changed it; the fall line shows the
side view on hover), The numbers (the receipt), who rolled and when. The A/B/C switch and
layouts B and C are gone; the static comparison board stays on the canvas as a record.
All 14 actions have What happened and Why copy, placeholder until signed off.
Known gap: "Open the Brutal Slam" opens the card but does not scroll the tray to its row.

## Appendix T - What it takes to build (feasibility, 2026-10-26)

James: the History tray with the detail card is the direction; with search, and the
token and hero-card history showing the same detail, it solves the problem. Question: how
much works with today's code, and what has to change.

### Works today (UI work only, the data already exists)
- The tray as a table item and a rail toggle: `Tabletop.itemKinds` (the Audio pad is the
  precedent).
- History from a token: the radial menu exists on tokens you control and on tokens you do
  not (`DMHub Token UI/TokenUI.lua:2633-2860`, free angles left).
- History from a hero card: hover chips, as the flip chip does (`Codex Titlescreen/EotwHeroCard.lua`).
- The roll card folding into the tray: one-image ghost, as `AnimateGhost` does (`Tabletop.lua:2374`).
- Round and turn grouping: the round is readable when an event happens
  (`dmhub.initiativeQueue.round`); turn starts are already logged.
- Roll facts: dice, total, net edges and banes, tier, per-target edge/bane offsets are on
  the roll (`boons`, `banes`, `multitargets`); a power roll links to its cast by `castid`.
- Immunity and weakness: the damage code already works out the amount, rating, damage type,
  source name, attacker and ability (`InflictDamageInstance`, `MCDMCreature.lua:5590-5660`),
  and how much temporary Stamina soaked.
- Search, filters and the player view: client-side over the records; hidden rolls are
  flagged, hidden tokens and monster Stamina are known.

### Codex changes (known in the moment, not kept today)
1. One history record per action. Today the per-target results are display strings
   (`RecordTokenMessage`, 29 call sites, e.g. "9 untyped damage", "Tier 3 (...)") inside
   the cast card, and names and portraits are read live (renames and deletions rewrite
   history). Start the record in `ActivatedAbility:Cast` (`ActivatedAbility.lua:3133`, the
   one funnel every ability goes through, with castid, caster and targets) and fill it as the
   cast resolves: per target, the damage steps (tier damage, surges, bonuses, immunity or
   weakness, temp Stamina, final), conditions (applied, resisted with potency, immune),
   movement, state changes. Snapshot names and portraits. The largest piece.
2. Edge and bane sources: the roll dialog knows each named source (`m_activeModifiers`,
   `modifiersUsed` per target, `EmbeddedRollDialog.lua:5642`); save the list on the record
   when the roll is accepted, plus "set by hand" for the dialog's +/- buttons.
3. Damage bonuses and surge sources: from the same modifiers (e.g. "+1 rolled damage on
   Fire abilities"); banked surges vs a feature's surges lost if unused (the dialog already
   knows this, Appendix M).
4. Trigger causes. Ability-use triggers already receive the cast that set them off
   (`symbols.cast`, `TriggeredAbility.lua:1545`); reactions to attacked, damaged, collide
   and similar events get the attacker but no cast id (e.g. the "attacked" event,
   `ActivatedAbility.lua:3986`). Add the resolving cast's id to event info and stamp each
   triggered cast with its event, triggering creature and cast, so it nests under its cause.
   Triggers that add an edge or bane already appear as named roll modifiers.
5. Conditions ending, with the cause: not logged today. `creature:RemoveOngoingEffect` is
   central (`Creature.lua:7687`); callers pass why (end of turn, save, an ability, the
   grabber moved away).
6. Forced movement, collisions and falls: not logged today. Record distance, collisions,
   fall and collision damage, and the path (`LuaPath:Serialize()`).
7. Winded, dying and death, and the Director's manual Stamina edits: not logged today
   (Stamina history keeps the last 8 per creature, too short to rebuild from).
8. The card's words: a sentence builder that turns a record into "What happened" lines and
   "Why" contrasts (one template per outcome type). All wording needs James's sign-off.
9. Storage: the chat store keeps only the newest 128 messages, shared with chat
   (`ChatPanel.cs:2193`), so a history long enough to search cannot live there. Put records
   in a shared document per encounter (the dormant `dsBattleLog` document is the
   precedent), keep the current and previous encounters, and decide what Revert Turn does:
   register the document for checkpoints (entries roll back with the board) or mark
   entries reverted (the struck-through rows the catalogue shows).

### Engine checks and small engine work
- Document limits: confirm a per-encounter document of a few hundred records, written on
  every action, is within size and write-rate limits.
- Cross-section from history: `dmhub.SetMovementCrossSection` takes a live token and a
  path, and draws today's terrain from the token's current position. Needs a way to build a
  `LuaPath` from saved data (it has `Deserialize`, but Lua has no way to make an empty one)
  and a start-position argument.
- Optional: the attack cross-section (`dmhub.SetAttackCrossSection`) could show why cover
  gave a bane, but it reads current positions; history would need stored positions.

### Still to design
Search (where the box lives, what it matches, how results show), the minimized tray's
notification, whether players can open a monster's history, the record's wording, turn
numbers.

## Appendix U - Search: proposal (2026-10-26, awaiting James)

Needs it serves: "why am I slowed? just type slowed"; creature names, ability names,
conditions (round 5); the creature filter from the radial and hero card is the same job.
Lesson from the Stamina history hover: few people find what is hidden, so search is not.

1. Where: a search field always visible in the tray header, beside Full log. Not behind an
   icon.
2. What it matches, live as you type: creature names (who acted, who was hit, who
   triggered), ability names, conditions (applied, resisted, immune, ended), damage types,
   and outcome words (killed, winded, dying, pushed, fell, collision, triggered, surge,
   Malice, critical). Not dice or turn numbers.
3. Suggestions while typing, grouped (Creatures, Abilities, Conditions, Other) with faces
   and icons. Picking one makes a chip; chips combine ("Dwarf Fury" + "Slowed" = when the
   Fury was slowed). The radial's and hero card's History open the tray with that
   creature's chip, so there is one filter, not two. Free text still matches anything.
4. Results (the fork): filter in place, recommended. The tray shows only matching
   actions, still under their round and turn headings, unfolded, with the match
   highlighted and a count; clicking one opens the detail card as now, the matching line
   marked. Alternative: a flat list of result sentences replacing the tray, each jumping to
   its place.
5. Active now: a match whose effect is still on (Slowed until end of turn) gets an
   "Active" tag, so "slowed" answers why you are slowed today, not only that you were.
6. Scope: what the tray holds (this encounter and the previous one); results from the
   previous encounter group under its own heading.
7. Player view: search never reveals what the player cannot see (hidden creatures stay
   "Unknown creature" and do not match by name; hidden rolls do not match).
Wording below for sign-off (placeholder until then).

### Built: search (2026-10-26)
Same prototype link. A search field under the tray header ("Search creatures, abilities,
conditions"). Typing filters live and shows suggestions grouped as Creatures, Abilities,
Conditions and Other, ranked by names that start with what was typed, each with its match
count; Enter or a click makes a chip, Backspace on an empty field removes the last one.
Results filter the tray in place under their rounds and turns, unfolded, with a count;
matching names, abilities and condition badges are marked; conditions still on carry
"Active"; the detail card marks the matching lines. With a creature chip, a condition chip
means that creature got (or gave) it, so "Dwarf Fury" + "Slowed" finds only the Reactor
Pulse. History on a token's radial or a hero card opens the tray with that creature's chip
(the creature popover is gone). Scenario change so "why am I slowed?" has an answer:
Reactor Pulse now slows (save ends) on R<1; the Fury is slowed (Active), the Elementalist
resists. The previous-encounter scope is not shown: the mock has one encounter.
James, after playing it: "yep i like it" (2026-10-26).

## Appendix V - The minimised tray and its notification: proposal (2026-10-26, awaiting James)

Code today: windows minimise into a 40 px button floating on the table or docked on the
icon rail (`Tabletop.lua` 2329-2740; other files' windows use `Tabletop.MinimizeExternal`,
the PDF viewer is the precedent). The button already takes a badge (`buttonOps.badge`
{icon, color} with `badgeShown`; a map window shows a red sword while in combat) and a
hover preview (`buttonOps.hover`). Table items do not minimise. The current log's rail
marker counts every message from anyone else since the panel was last on screen
(`ActionLogPanel.lua:43`), so in combat it is always on (ticket AM79CDYV).

Proposal:
- The block: History minimises like any window, into the standard 40 px button (floating
  or docked on the rail), with the History icon. Click opens the tray at "New since you
  looked".
- Two levels of signal, so the strong one keeps its meaning:
  - Quiet: a small grey count of turns you have not seen (out of combat: entries). A turn
    with six entries counts once.
  - Strong: gold, when something happened to a creature you control that you did not do
    yourself: damage or healing, a condition put on or ended, forced movement, a fall or
    collision, a triggered reaction that hit it, winded or dying, the Director changing its
    Stamina or resources by hand.
  - Both clear when you open the tray; nothing fades on a timer.
- Hover: a preview card in the style of the map windows' hover, "Since you last looked":
  up to three "What happened" lines, your creatures first, then "and N more turns", then
  "Click to open".
- The Director: the quiet count only, plus gold when a player changed something by hand
  (Stamina, conditions, resources, an undo). Monsters are all theirs, so "your creatures"
  would always be gold.
- A setting to turn notifications off.
Not proposed: toasts or pop-ups near the map (the table stays clear), a dot for every
message (today's always-on dot).
Code: the badge needs a count (an addition to `buttonOps.badge`); the rail's new-content
marker already takes a count (`DockablePanel` `newContentCount`).

### Built: the minimised tray (2026-10-26)
Same prototype link. Hover the tray: its titlebar has a minimise dash; the tray becomes the
40 px History block on the table. Minimising remembers what was on show. Play: the Fury's
own turn adds nothing; the Reactor's Pulse hitting the Fury turns the badge gold "1"; the
Troubadour's turn makes it "2". Hovering the block shows "Since you last looked" with the
Fury's line first (gold edge), then the others, "and N more turns" when there are more,
"Click to open". Opening (the block, or the rail button) clears it, unfolds the new turns,
folds the earlier turns of that round into one line, and puts "New since you looked"
before the first new turn. View as Director: grey count only (the scenario has no player
hand edits). New wording: "Nothing new since you last looked." (for sign-off).

## Appendix W - Closing the open decisions (2026-10-27)

### 1. Can players open a monster's history? (decided: yes, 2026-10-27)
Recommendation: yes, on every token the player can see, in the same radial slot as on
their own. It filters entries the tray already shows players, so it reveals nothing new.
Numbers about a monster in the detail card follow Monster Info's knowledge
(`Draw Steel Core Rules/MonsterKnowledge.lua`: per monster type, Stamina tier 0-3,
characteristics, immunities, abilities; learned in play or revealed by the Director):
Stamina at the tier players know (Healthy / Winded until exact), a characteristic or
immunity value only once revealed; otherwise the line keeps its contrast without the
number ("Reactor 1 could not resist" for "Reactor 1's Agility 1 could not resist").
Innate immunities that change damage are already revealed automatically when they do.
Alternatives: only creatures you control (monsters through search), or only while the
Director's Monster Info setting is on.

### 2. Wording (decided 2026-10-27)
Signed off in two rounds; see COPY.md. Applied to the prototype.

### 3. Turn numbers (decided 2026-11-04: kept, after briefly dropping them)
Today in the prototype: a small number on each folded turn, "Turn 13" in each turn heading,
"Turns 5-9" on the folded group, "Round 2, turn 13" in the detail card. Ricky asked for them
("look at turn 15"); James is not sold; search does not use them.
Recommendation: drop the encounter-wide turn number and name a turn by its round and
creature, which is how Draw Steel and the table talk ("Round 2, the Fury's turn").
Folded group: "5 earlier turns" (faces as now). Turn heading: "Dwarf Fury · Hero turn".
Card: "Main action · Round 2". A solo creature's two turns: "first turn" / "second turn".
Alternative: keep the numbers small and secondary, as now.

## Appendix X - Design review before the build (2026-11-04, in progress)

### Coverage audit: what today's Action Log does that History does not yet say
Rule: coverage means nothing is lost; where today's way is weak, recommend the better one.
Covered: the unread marker (the block's badge), round and turn starts, initiative, casts and
per-target results, immunity and weakness, healing, temporary Stamina, conditions removed,
teleports, Malice spent, bonuses folded into a roll, hidden rolls (Director only), pop-out
problems (History is a table window). Amending edges, banes or the tier after a roll: today
only while that roll is still the active roll (`MCDMAbilityRollBehavior.lua:3327`), the same
control as the roll dialog's, so History loses nothing.
Gaps:
- G1 Director tools on entries. Today, right-click: Delete Message, Clear Chat, Hide from
  players / Reveal to players (`ActionLogPanel.lua:885-910`), plus a visibility eye per roll.
  Players asked for a way to clear experiment junk (ticket MYEJSNWK). History has none.
- G2 Undo on resource changes (the Resource card's Undo button, `Draw Steel V/ResourceChat.lua`).
- G3 The ability itself: today hovering a Malice spend shows the ability card. History names
  abilities but never shows what they do.
- G4 Rolls outside an action: Dice panel, macros, roll on a table, tests, montages,
  negotiation, downtime, initiative, class roll cards (Acolyte), the Director revealing a
  hidden modifier, and "Now playing" audio. Appendix K says compact rows for most; the
  prototype shows none, and out-of-combat grouping (no rounds or turns) is undecided.
- G5 Retention outside combat: History keeps this encounter and the previous one; what
  happens between encounters, and next session, is undecided (today: the newest 128
  messages, across sessions).
- G6 Content authors' own lines: a damage behavior's authored chat message
  (`AbilityDamage.lua:454`) has no place in the detail card yet.

### David's feedback after the demo (via James, 2026-11-04)
- D1 Chat and History on separate rail buttons by default. Today both built-in Views
  (Director, Player) group Chat, Action Log and Safety into one rail group
  (`DocumentSystem.lua:26972`, `27031`). Change: History gets its own slot; the Chat group
  keeps Chat and Safety.
- D2 A brief preview when something lands while History is closed or minimised; none when
  it is open; a setting to turn it off. Precedent in the app: the chat speech bubble
  (`DocumentSystem.lua:16400`): when chat is not on screen, a new message shows in a bubble
  beside its rail button, lingers 5 s past the last message, up to 4 rows, placed to avoid
  open windows, click opens chat. History would reuse it beside its button or block, with
  the "What happened" line.
- D3 Hovering a forced movement also draws the movement arrow on the map where it
  happened. `CharacterToken:MarkMovementArrow(targetLoc, options)` draws from the token's
  current spot (`Definitions/CharacterToken.lua:465`); history needs it from a saved start.
  Same engine ask as the cross-section from a saved path: one request covers both.

### Independent design review (fresh-eyes reviewer, 2026-11-04; code references checked)
1. Glance numbers are not what landed: a face shows the strike's -13 while the card says 17
   taken (the Mark's 4 sits on a trigger row); folds add up targets only and net damage
   against healing (Zakaarior -1 = 9 taken, 8 healed); "7 fire" is dealt, the story says
   4 taken. Fix: faces show the total taken including nested triggers; folds show damage and
   healing apart; captions use taken numbers.
2. Several creatures in one turn lose their actor: an initiative entry can hold several
   tokens (`MCDMInitiativeBar.lua:38`, a Director's group turn), and action rows carry no
   actor face. Fix: an actor face on any row whose actor is not the turn's only creature;
   decide where actions with no cause sit (a free strike from an enemy moving away).
3. Several maps each in their own combat: one tray per map, or one that follows the focused
   map? Which fight the badge counts and search covers.
4. Notifications only when minimised: "x" (off the table) silences everything; an open tray
   never gets the "New since you last looked" marker; defaults (M #13) never reached the
   ledger. Fix: decide defaults; the rail button keeps the badge when the tray is off; mark
   new rows on an open tray too.
5. Rows move under the reader: turns fold as the next starts; a card whose row folds stays
   open with nothing highlighted. Fix: no auto-fold while the pointer is on the tray or a
   card is open; never fold the selected turn; hold scroll and show "N new below".
6. Hover-only and colour-only signals: the hero-card chip (James's constraint, kept), the
   side view on hovered text ("Hover here for the side view"), creature names only in
   tooltips, duplicate portraits for numbered monsters, resisted shown only as a greyed
   icon, friend/foe by ring colour, gold vs grey badge by colour. Fix: an icon button for the
   side view, a "Resisted" caption, numbered duplicate faces, a shape or face on the gold
   badge.
7. Monster Knowledge contradicts itself: minion Stamina appears in Y13 and the receipt; a
   monster's own receipt shows its characteristic, which players already see on the live
   read-only card; spoiler modifiers (`EmbeddedRollDialog.lua:425`) would be named as
   sources. Fix: one rule, the receipt shows what players saw live; spoilers stay redacted.
8. Revert, undo and Turn Rewind: Appendix T considered registering the History document
   for checkpoints, which would erase history (pillar 3, dispute persona); Monster
   Knowledge itself rolls back with checkpoints (`MonsterKnowledge.lua:59`). Fix: do not
   register; append revert markers; count a revert once.
9. Scale: ten targets wrap the strip and put ten sentences in the card; folds show 5 faces
   with no "+N"; Show all or a creature chip unfolds a long fight at once (vscroll ~3 ms a
   panel). Fix: "+N", grouped identical outcomes ("Goblins 1-4 each took 6"), lazy build.
10. Wording between surfaces: "<=11" badge vs "Tier 1"; S5 says "this encounter" though
    search covers the previous one too; turn numbers kept but search ignores "turn 15";
    "Active" in the tray only while searching but always in the card.
11. Font Size and narrow windows: tray plus card need ~800 px; glance text at 9.5-10 px is
    ~8 px at 80%. Fix: open the card on the side with room, or inside the tray when narrow;
    a minimum glance text size.
Questions it raised: one History per map or one following the focused map; the tray or
block on by default for players; Revert Turn erases or strikes through; what replaces round
and turn out of combat; History from a token adds to or replaces the search; a monster's
receipt follows knowledge or the live card; is gold harm only, or any change.
