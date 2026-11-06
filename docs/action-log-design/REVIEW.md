# History: design review before the build (2026-11-04)

Inputs: an independent fresh-eyes review of the design and prototype; a coverage audit of
today's Action Log; David's feedback after the demo; a rules review in four parts
(`rules-review/core.md`, `classes-1.md`, `classes-2.md`, `director.md`, about 700 events).
Details and code references: BRIEF.md Appendix X and the four rules files.

## Step by step (from 2026-11-05)

James asked to take this in small steps. Step 1 decided the rule below; step 2 sorts each
gap by it and says whether the fix is code, data or both; then the fixes and decisions.

**Step 1, decided 2026-11-05: what earns a place.** Did it change the table?
- Glance: Stamina up or down; a condition or effect starting or ending; moved by someone
  else, or falling; resources (Heroic Resource, surges, Malice, Hero Tokens, Recoveries);
  winded, dying, death, minions dying.
- Card only: what explains a number (edges and banes, kit bonuses, potency, immunity
  amounts, which surge went where).
- Left out: what changed nothing (walking on your own turn, a trigger that did nothing, a
  start of turn where nothing happened).
- Exception (James, 2026-11-06): a roll the table watched gets a line even if it changed
  nothing, so a failed save shows, at the end of that turn, with Active on it.

**Step 2: the gaps, one at a time.** Gaps 1 and 2 below turned out to share one cause, so
there are five: (1) results with no card or authored message; (2) effects ending;
(3) winded, dying, death, minion deaths; (4) Malice; (5) passive modifiers unnamed.

Gap 1, checked in data 2026-11-05. Prompted triggers (the player is asked, e.g. Wellspring
of Grace through the shared "Spend Recovery" prompt) already post a card; what they lose is
the cause. Truly automatic ones (no question asked) show nothing without a typed message:
Righteous Phalanx (15 damage on entering, `classes/conduit.yaml:12006`), Edict of
Unyielding Resolve (10 temporary Stamina each turn, `characterongoingeffects/
edict-of-unyielding-resolve.yaml:52`), start-of-turn area damage (`MCDMCreature.lua:7144`).
History replaces the Action Log, so today's cards and typed messages have nowhere else to
show; History writes its own lines.

Marker effects (proposed 2026-11-05, James's idea): ongoing effects already carry the
editor's "Hidden" checkbox (`statusEffect = false`, `DMHub Compendium/OngoingEffectEditor.lua:182`;
83 effects, Righteous Phalanx Target among them), which every token and sheet display
honours (`DMHub Token UI/TokenUI.lua:337`). History leaves Hidden effects out. "Hidden from
enemies" (26) follows the token rule. "Hidden on token" (98) is mixed: markers (Moved This
Turn, Blitz Tracking, Chain Reaction Target) and real effects (Vanish, Levitate, Rivalry),
so History shows them and the pure markers get "Hidden" ticked in data.
Withdrawn the same day: "Hidden" also takes an effect off the Tac panel's chips, the only
place a Director removes it by hand (James). The markers need their own History signal;
the list is in `marker-effects.md`.
Decided 2026-11-05 (James): a new checkbox on ongoing effects, ticked on markers, keeps them
out of History and changes nothing else. Its label waits on the feature's name, which James
reopened the same day.

**Gap 1 closed 2026-11-05 (James).** Code: History records damage, healing, temporary
Stamina, conditions and resources where they happen, names the cause, and skips changes that
changed nothing (temporary Stamina keeps the greater amount, `DSTemporaryHitpoints.lua:6`).
Lingering area damage goes through one function (`creature:AuraDamage`,
`MCDMCreature.lua:7144`), so one fix covers Wall of Fire, monster auras and zones. Data: tick
"Hidden from History" (COPY.md H1) on the markers in `marker-effects.md` once James has
checked the list. Prompted triggers already post a card; they gain their cause.

**Gap 2, where effects end (checked 2026-11-05).** A handful of places, not one per ability:
removal (`creature:RemoveOngoingEffect`/`BySeq`, `RemoveMatchingOngoingEffects`,
`RemoveOngoingEffectsOnTrigger`, `PurgeCondition`: saves, abilities that end a condition,
dying, end of encounter, by hand); end of turn and end of round (`creature:EndTurn`,
`creature:EndRound`, `DMHub Game Rules/Creature.lua:11183`, `:11230`); a sustain formula
failing (`creature:RefreshToken` tidy-up, `:6134`); timers and concentration that lapse
quietly (`CharacterOngoingEffectInstance:Expired`, `OngoingEffect.lua:531`, filtered out
with no removal; History checks them at each turn end). Persistence adds its own piece
(`creature:EndPersistentAbilityById`, `MCDMCreature.lua:7512`) for the cause and for walls
and areas, which are not effects on a creature.
**Gap 2 closed 2026-11-05 (James):** the broad fix plus the persistence piece; effects that
end together are grouped (one line per turn end; one closing entry for the encounter, listing
what ended by creature). Wording in the later sign-off round.

**Gap 3, winded, dying, death, minion deaths (checked 2026-11-05).** Detected in two places,
taking damage (`MCDMCreature.lua:6806-6871`) and Stamina set directly, e.g. a hand edit
(`:7069-7083`); each fires an event and a sound, never a log entry. Confirmed minion deaths
fire once per batch (`squadminiondeaths`, `:6109`). Proposal: captions on the row that caused
it (T14, signed off), a line when nothing did, recovery shown too, minions only once confirmed.
**Gap 3 closed 2026-11-05 (James), as proposed.** Code only.

**Gap 4, Malice (checked 2026-11-05).** Correction to section 1: spending Malice on an
ability already posts a card everyone sees (`MaliceSpentChatMessage`, `DSResources.lua:272`).
Every other change goes only to the Director's counter tooltip. All changes pass through
`CharacterResource.SetMalice` (`DSResources.lua:79`) with a reason already attached (start of
combat, each round's gain, traits, "Manually set", end of combat), so the fix is one hook.
Open: the rules leave it to the Director whether players see Malice (CRM:785-790).
Who sees what today (from code, 2026-11-05): gains are Director-only (the action-bar counter's
tooltip, the Encounter Wrangler). Players see every spend card, and a Malice tracker the
Director places on the table as public (`DMHub Game Hud/TableDice.lua:2316`), whose hover
shows the same history with reasons (`:2641`). So the codex's "Director's choice" is that
tracker; the earlier "on by default" proposal was withdrawn. Revised proposal: keep today's
split in History (players see spends, the Director sees every change); sharing stays the
public tracker's job.
**Gap 4 closed 2026-11-05 (James), with the revised proposal.** Code only (one hook in
`SetMalice`); no new setting.

**Gap 5, passive numbers (checked 2026-11-05).** Card only by the rule (they explain a
number). Most names already exist in three places: roll modifiers kept by the roller
(`rollProperties.modifiersUsed`, `DSRollDialog.lua:3963`), kit bonuses written onto the
ability ("Includes +2 damage from {kit} kit", `MCDMKit.lua:475`), immunity and weakness in
the damage code. Left over: changes made outside a roll, e.g. healing halved through the
"Stamina Regain Halved" attribute (`ActivatedAbility.lua:5089`), where the code knows the
change but not which effect caused it. Possible data side: a bonus written straight into a
formula instead of a named modifier shows as an unexplained total.
Generic answer (James asked for no per-ability code, 2026-11-05): `creature:DescribeModifications`
(`DMHub Game Rules/Creature.lua:7147`) and `DescribeModificationsToNamedCustomAttribute`
(`MCDMCreature.lua:222`) already list every modifier that changed an attribute, with the
value before and after; the Hero sheet's stat sources use them (`EotwHeroSheetData.lua:424-477`).
So each place a number lands (the gap 1 hooks) asks those for the attributes it read. Any
ability, item or DLC built from modifiers is named with no new code; only content that
bypasses modifiers (a script editing numbers, a bonus typed into a formula) cannot be.
**Gap 5 closed 2026-11-05 (James), with the generic approach.** Step 2 is done: all five
gaps closed. Still open from it: James checks `marker-effects.md`; the new line wording
(trigger results, temporary Stamina, effects ending and grouped endings, recovering from
winded or dying) goes in one sign-off round. Next: the fixes in section 2, one at a time,
then the decisions in section 3 (decision 1 is mostly settled by the gaps; its open part is
whether F8 and F9 join the first build).

## 1. The big finding: History has to record at the source, not from chat

Most of what players can't explain never reaches today's log, for a handful of reasons:
- Automatic triggers post no ability card (`TriggeredAbility:ShowChatMessageOnCast`
  returns `not mandatory`, `TriggeredAbility.lua:2644`; mandatory is the default). Their
  per-target results are written onto that card, so with no card they are dropped
  (`ActivatedAbility.lua:3174`). Their damage still shows when the author filled in the
  damage behavior's chat message (`AbilityDamage.lua:56`), and immunity/weakness always
  posts its own line. (Correction 2026-11-05: an earlier wording said they post nothing.)
- Chat and the log are split by a filter: everything that is not plain chat goes to the
  Action Log (`ChatPanel/ActionLogPanel.lua:31`), so nothing log-worthy is stuck in chat.
- Damage, healing, temporary Stamina and resource lines appear only when the content author
  typed a chat message on that behavior. Flat rule-text damage ("2 fire damage") posts
  nothing. So coverage depends on authoring, ability by ability.
- Nothing records an effect ending: end of turn, saves, dying, end of combat, a sustain
  condition lost, persistence broken (the Elementalist's 5 x Reason rule only shows floating
  text, `elementalist.yaml:4869`).
- Winded, dying, death and minion deaths are events with sounds, never entries. Minion deaths
  are chosen by whoever hit the squad, so History must record the confirmed deaths.
- Malice changes are recorded only in a hover tooltip on the Director's counter.
- Passive numbers (kit bonuses, captain, auras, the Mark) fold into rolls unnamed.

**Proposal R: record at the source.** History does not read chat. Each family of event is
written where the game already handles it, so every ability and trait is covered without
per-ability authoring, and the old chat cards can stay as they are.
| Family | Recorded at | Shows as |
|---|---|---|
| F1 Actions, prompted triggers | `ActivatedAbility:Cast` | action row |
| F2 Automatic triggers (traits, auras, class features) | the triggered cast, mandatory too | nested under its cause, else a line naming the feature |
| F3 Damage, healing, temporary Stamina from any source (auras, terrain, start/end of turn, falls, collisions, hand edits) | the damage, heal and temporary Stamina code | numbers on the action, or a line with its source |
| F4 Effects and conditions starting and ending, with why | inflict / remove condition and ongoing effect, persistence end, end of combat, dying | condition badges, "Ended" lines |
| F5 Thresholds: winded, dying, death, confirmed minion deaths, strained, rampage, captain changes | the existing creature events | captions and lines |
| F6 Resources with a structured cause: Heroic Resource, surges, Malice, Hero Tokens, Recoveries, Victories, losses at end of combat | the resource code (it already keeps a stat history) | lines, chips |
| F7 Movement: push, pull, slide, stability, teleport, falls, collisions, wall breaks, with the path | `AbilityRelocateCreature` | captions, side view, map arrow |
| F8 Rolls and play without an action: tests, montages, negotiation, respite, downtime, Dice panel, tables | the roll and those panels | compact rows |
| F9 Director actions: reinforcements, villain actions, overrides, hand edits, reveals | the Director's tools | lines (players see what was visible) |
| F10 Named modifiers for Why lines | roll dialog `modifiersUsed`, the damage code | Why lines |
Recommendation: F1-F7 and F10 in the first build (every combat); F8 and F9 next.

## 2. Fixes (taken one at a time from 2026-11-05)

Adopted: B1, B2, B3 with "{n} new below" counting rows (2026-11-05).
B4 part 1 adopted 2026-11-05: side-view icon button on the movement caption; hovering it
draws the movement arrow on the map. The engine change (draw an arrow and the side view from
a saved start or path) is built here and proposed as an engine PR (James). James added: a
faded ghost of the creature at its start square. The engine already has it,
`CharacterToken:CreateGhost(loc)` (`Definitions/CharacterToken.lua:497`, used by the Monster
AI's plan preview), so no engine change for that; a creature whose token is gone (a dead
minion) gets no ghost.
B4 part 2 adopted 2026-11-05: "Resisted" caption (T14), numbered faces on shared portraits,
the gold badge becomes a diamond (the quiet count stays a circle).
B5 adopted 2026-11-05: players see what they could see live. Spoiler modifiers follow the
existing reveal (`PowerRollSpoilers`, `Timeline/EmbeddedRollDialog.lua:437`); minion Stamina
and a monster's own numbers follow Monster Info unless the live roll showed them. Y13 without
the number goes to the wording round.
B6 adopted 2026-11-05: "+N" when faces don't fit, identical results grouped (pattern to the
wording round), details built when opened.
B7 adopted 2026-11-05: the card opens on the side with room, else inside the tray with a way
back (label to the wording round); glance text at least 11 px at 100% Font Size.
B8, "Active" decided 2026-11-05: always shown, in tray and card, as a small tag on the
condition badge only.
B8 adopted in full 2026-11-05: "Tier 1" everywhere ("<=11" under it on the roll card only),
search finds "turn 15", S5 now reads: Nothing matches "{search}". All eight fixes adopted.
Wording still to propose (one round): trigger and temporary Stamina lines, effects ending
and grouped endings, recovering from winded or dying, Y13 without minion Stamina, grouped
identical results, the in-tray card's way back.

**Built into the prototype 2026-11-05** (artifact UPWo9XvYuaDiZ388xRES35, version 19; source in
the session scratchpad `actionlog-proto/project/Main.dc.html`; checks `check3-6.js` pass, and
each fix was looked at in the browser). Scenario additions so every fix shows: Zakaarior's free
strike inside Test Monster Z 1's turn (B2); the Power Roll Test also hits the Tactician, Censor
and Shadow for 10 each (B6 "+3" and grouping); a secret "Ambusher" edge on round 1's axe (B5);
a "Window: wide/narrow" demo button (B7). Draft lines in the prototype, for the wording round:
"5 damage was enough to kill one minion."; "Knocked prone: it did not resist"; "{names} each
took {n} damage."; "Taken, each"; "Back"; the button's tooltip "Side view"; the free strike's
"Free strike" and "Moved away without shifting" Why line. Not shown in the prototype: damage and
healing apart in a fold (Zakaarior sits behind "+N"; checked in code), the card opening on the
other side, lazy building.

**James's review of the build, 2026-11-06 (prototype version 21).**
- Target cells: face on the left, number and full name beside it, captions on the line below.
  One target takes the full width; two to four sit in two columns; past four, three cells and
  "+N" with the rest named beside it. "Ally hit" became a caption on the cell (T13). Rows are
  about half their old height. The tier pill sits on the caption line so names aren't cut.
- Side-view button: sits on the movement caption's line. Icon is the real Phosphor glyph
  `phosphor/arrow-elbow-right-down-bold.png` (the full ~9k set is in
  `StreamingAssets/phosphor-icons.zip`, any name works; `assets.GetPhosphorIcons` searches it).
- David's preview (D2), which had been parked in decision 2: when an action finishes and History
  is closed or minimised, a "what happened" card shows beside the rail button or block for about
  five seconds (longer with the pointer on it); never over an open tray; clicking opens History
  on that action; gives way to the hover preview. The prototype's "Beside History" button stands
  in for the setting. Setting wording goes to the wording round. D1 (own rail slot) stays in
  decision 2.

**Font check for wording (2026-11-06, read from the TextMeshPro assets).** Berling is a static
atlas. Not available: the arrow U+2192 and less-or-equal U+2264 (no label font's table has them;
Berlingske Regular's fallback Newzald-Medium is dynamic and its source has them, but Bold has no
fallbacks, so it can't be relied on). DrawSteelGlyphs has no arrow (it has the tier glyphs).
Labels have no inline images, so a Phosphor arrow can't sit inside a sentence. Available: middle
dot, en dash, times, single guillemet, curly quotes. Minus U+2212 is Regular-only through a
fallback, so bold numbers in the Codex use a plain "-". Lua source stays ASCII, so these go in as
byte escapes. This hits T5 ("Malice +{n} → {n}") and the card's "Stamina a → b" notes.

**Wording group 1 signed off 2026-11-06 (COPY.md Round 4), with the caret rule:** a lone number
shows the new value, the Builder's caret (`HeroSheetCard.Mark`) and the size of the change; inside
a sentence, "to". The players' round heading drops Malice, matching gap 4. Prototype version 22,
with two sample lines: Reactor 1's Wall of Fire damage (turn 14) and the Troubadour's temporary
Stamina (turn 15).

**Reversed the same day after James tried it (prototype version 23):** carets are out; they read
like a sum and red clashed with the Builder. Every changed number now reads "{before} to {now}".
Wording group 2 signed off with an Ended tag and the failed save line (COPY.md Round 4). The axe in
turn 8 now slows Zakaarior (save ends) so his failed save shows in turn 12.

**Wording round complete 2026-11-06:** groups 1-5 signed off (COPY.md Round 4, L0-L38); no drafts left
in the prototype. Still open: James checks `marker-effects.md`; decisions 1 (F8 and F9 scope), 2
(defaults, rail, whether the preview and notifications stay two settings), 3 (several maps), 4
(revert, undo, Director tools), 5 (out of combat, retention); then the build plan.

**Decision 2 closed 2026-11-06 (James):** own rail button below Chat; starts closed for everyone
(he declined "on for the Director"); two settings stay; the rail button keeps the badge when the
tray is off the table.
**Decision 3 closed 2026-11-06 (James):** one History, following the map last clicked unless the
pointer is on the tray or a card is open; a switcher only while two maps are in combat; badge and
preview cover every map you can see; search covers the shown map and its previous encounter.
**Decision 4 closed 2026-11-06 (James):** reverted rows stay, faded, tagged Reverted, out of the
totals, with a Turn reverted line; History's document stays out of checkpoint backups. Undo stays
on resource lines. Director tools stay on right-click (COPY.md L39-L42).
**Decision 5, three of four closed 2026-11-06 (James):** Out of combat heading with compact lines;
retention as above, across sessions, subject to the engine's document limits; ability card on hover
in the card header (COPY.md L43-L45). Typed messages talked through: 759 fields in the data, 530
different messages, 210 identical to the ability name, but others carry real explanation ("Gained 2
surges (target killed, winded, or bleeding)"), so "ignore them" would lose information.
**Decision 5 closed 2026-11-06 (James):** typed messages never reach the glance; in the card's Why
they show as written unless they only repeat the ability's name.
**Decision 1 closed 2026-11-06 (James):** all ten families before release (this replaces the "F1-F7 and
F10 first" recommendation in section 1). Stages: combat first, then out of combat and Director
actions. History runs beside the old log, off by default, until the last stage, then the old log
goes in the same step that turns History on for everyone. **All review decisions are closed.**
The prototype caught up with decisions 2-5 on 2026-11-06 (version 26; every item looked at in the
browser): starts closed; Chat and History on separate rail buttons, History with Phosphor's
`clock-counter-clockwise-bold`; rail badge; History notifications control; map switcher with a sample
"Old Mill" fight; Reverted rows with a Turn reverted line; Out of combat; ability card on hovering the
detail card's title; a typed message sample in turn 5's Why. Not in the prototype: Undo on resource
lines, the Director's right-click menu, History following the last-clicked map. Next: the build plan. Prototype changes are batched until the fixes are through.

- B1 Numbers on the glance are what landed: a face shows the total taken including nested
  triggers; folds show damage and healing separately; captions use taken numbers.
- B2 An actor face on a row whose actor isn't the turn's only creature (a Director's group
  turn); an action with no cause sits as a line in the turn it happened in.
- B3 Nothing moves under the reader: no folding while the pointer is on the tray or a card
  is open; the selected turn never folds; when scrolled up, hold position and show
  "{n} new below".
- B4 Signals that are not hover-only or colour-only: the side view gets an icon button on
  the movement caption (drop "Hover here for the side view"); hovering it also draws the
  movement arrow on the map (David); a "Resisted" caption; duplicate portraits numbered; the
  gold badge carries a shape, not colour alone. (The hero card's hover chip stays: James's
  constraint.)
- B5 One visibility rule: the record shows players what they saw live; spoiler modifiers
  stay redacted until revealed; anything not shown live (a monster's characteristic in a
  Why line, minion Stamina) follows Monster Info.
- B6 Scale: a "+N" face when a strip or fold is full; identical outcomes grouped ("Goblins
  1-4 each took 6"); results built lazily.
- B7 Font Size and narrow windows: the card opens on the side with room, or inside the tray
  when there is none; glance text never smaller than 11 px at 100%.
- B8 Wording: one tier label everywhere ("Tier 1", the badge showing "<=11" under it only
  on the roll card); "Nothing in this encounter matches" becomes "Nothing matches"; search
  accepts "turn 15"; "Active" shows the same way in tray and card.
New wording in this block for sign-off: "{n} new below", "Nothing matches "{search}"."

## 3. Decisions, one per round

1. What History records (Proposal R above), and the first-build scope.
2. Defaults, the rail and notifications: History on its own rail slot, not in the Chat
   group (David); what is on by default for players and the Director; the brief preview
   beside the button or block when History is closed, reusing the chat speech bubble, with a
   setting (David); the badge when the tray is off the table; the new-rows marker on an open
   tray.
3. Several maps, each in its own combat: one History per map, or one that follows the
   focused map.
4. Revert Turn, undo and the Director's tools: strike-through or erase on revert; Delete,
   Hide from players, Clear; Undo on resource lines.
5. Out of combat and keeping history: how play without rounds groups; how long History keeps
   things between encounters and sessions; the ability card on hover; content authors' own
   lines.

## 4. Possible rules bugs found along the way (not History work)

The rules agents noted implementation differences from the rules. None are verified;
each needs checking against the book before anyone changes code. Lists: core.md
"Surprises", classes-1.md "Rules deviations noticed", classes-2.md "Surprises and data
issues", director.md "Gaps in rules automation". Examples: no damage for being thrown
cleanly through a wall; save-ends effects continuing after combat; Prophecy marked Gold with
no modifiers; Quick and Brutal granting a maneuver where the rule grants a main and a move
action; Materialize using a flat 2 instead of Reason; features not implemented (Warmaster,
Masterwork, Templar, Oracular Visions and others).
