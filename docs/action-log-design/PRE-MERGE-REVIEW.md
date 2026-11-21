# History: pre-merge code review (2026-11-21)

Branch `feature/history-stage-3` against base 61b9c62e, plus a trial merge with origin/main
(db3426cf, 109 commits ahead; merges with no textual conflicts, tree 23ac45bd). Code reading
only, nothing run live. "Checked" = re-read in the code by the lead session after the
reviewer reported it; the rest are reviewer findings with the confidence they gave.

## Status (2026-11-21, uncommitted, type check clean, not yet run live)

Fixed in the working copy: 1, 2, 3, 7-11 except 7 (see below), 12, 14 (fade only), 15, 16,
17 (RollUtils.NotifyTested and RollOnTableProperties.NotifyRolled are now failure-safe),
18, 19 (xpcall + traceback), 20, 21, 22, 23, 27, 28; minor: hover dwell, squad order,
"1 surge", UndoResource not undoable, open card closes when its row goes, legacy
"deprecated" effect ids, EncounterMontage doc comment. Also: the two HISTORYDIAG prints
removed; 23's fix may be the Battle Grace missing-surge cause (it read target row 1).
Mechanism notes:
- 1 + 12: `PanelDocument.OnRailLayoutApplied` hook, run at the end of DocumentSystem's
  EnterGame coroutine (after the first-entry View and the update check) and after every
  `ViewsApplyLayout`. HistoryTray's own EnterGame handler is gone.
- 2: History.lua `Flush` holds a batch for a document that reads `isnew` until EnterGame
  has fired (or the module loaded in a game); drops everything when not `dmhub.inGame`.
- 13: `standsInFor` on a DockablePanel registration; History and the Action Log name each
  other, so a dock saved with one shows the other.
- 6: table rolls and saves now carry `rollInfo`/`details` in their notify payloads;
  History records `RollUtils.RollPrivacy`.

No change needed: 24 (initiative is per map, and Revert Turn is clicked from the current
map's bar, so the current map is the combat's); 11's opposed total (the card and tray only
print totals when OpposedTotalsShown says so); EotW corner (rails rebuild on the setting
change, which re-asks the custom interface for its corner); 26 left as is (it prunes inert
expired instances; moving it to rules code changes nothing a player sees).

Waiting on a decision (copy or design): 4 (how a note reads in History; whether a note-only
trigger gets a row), 5 (hidden creatures), 7 (monster Stamina for players), 14 rest (audio
captions with no Chat rail button), 25 (Turn Rewind needs a checkpoint sequence, not time).
After the merge with main (the code is main's): Iron Grip `logActorCondition`, Immune to
Forced Movement (needs wording), `NoteStability` before the immunity check, nested-invoke
kit bonus. Not done (unmeasured perf): History.Keys caching, searchResults walk,
MergeStyles per linger, GetConditionImmunities; g_links growth (small).

Later the same day (all signed by James): 7 and Malice (players see Malice lines only in
Encounter of the Week; monster Stamina numbers follow the Stamina bar's rule) in 297c59da;
5 (unseen creatures) and the no-map Table record in 4404c634; 4 (notes), 14 (caption toast)
and 25 (Turn Rewind by rewind point) in c6c68704; origin/main merged in b37e87e8; the
post-merge items (immunity line and order, Iron Grip, nested kit bonus) in 85dcc34b.
Live checks over the bridge, 2026-11-21 (merged branch): all passed. Enemy Stamina line
(written with its key, hidden from players until Monster Info reveals it); Iron Grip escape
(row credits the Null, 4 damage, rider note in the Why); Faster than the Eye on two targets,
one Prone (Prone target's own roll 19 with one edge from Prone, the other 17); Get In Get
Out's nested strike (Tier line "Cloak and Dagger +1"); audio caption bubble, still up with
Chat in front; dock UI (caption toast; a docked Action Log restored as History); a new game's
first entry (built-in Director View, History on the rail). Whole-codex type check: 0.
Not covered: the promptWhenResolving target-order path itself; surges spent per target.
Found: Get In Get Out writes two rows (the outer ability, aimed at the Shadow and changing
nothing, and the strike), since the nested strike has its own card.

## 1. Fix before merge

1. **New users never get their built-in View.** Checked. `HistoryTray.lua:6333` runs
   `PlaceRailButton()` synchronously on EnterGame; `RailPlaceBelow("history", "chat")`
   writes `iconraillayout`. DocumentSystem's EnterGame coroutine (`DocumentSystem.lua:27224`)
   waits for the documents layer + 5 frames, then finds `iconraillayout` non-empty, so
   `nothingOfTheirs` is false and `ViewsSwitchTo("builtin:player"/"builtin:director")`
   never runs. Every first entry to a game (layout is per-game). Crows same via the
   Action Log. Also: a pristine v6 user's rail no longer matches the stamp, so they get the
   "updated / Keep mine" prompt instead of a silent update. Fix: skip when the layout is
   empty (v7/v8 already place History), or run after the View auto-apply.
2. **A History write before the document has synced can wipe that map's History.** Checked.
   `History.lua:303` `WriteEntries` has no `doc.isnew` / loading gate; on an empty snapshot
   it seeds tables and `CompleteChange` PUTs over the cloud doc (the playlist wipe
   mechanism). Any capture while a client is still loading or rejoining. Fix: requeue
   while `doc.isnew` or the game is loading.
3. **Undo on a reverted resource line applies twice.** Checked. `HistoryTray.lua:2489`
   ignores `entry.reverted`. Revert Turn restores the Recovery, then Undo on the faded line
   takes the heal off and refunds the Recovery again. Same for Turn Rewind. Fix:
   `and entry.reverted == nil`.
4. **main's new Action Log Note behavior (f2a2b312) shows nowhere by default.** Checked the
   path. `ActionLogNoteChatMessage.Post` (`AbilityReplenish.lua:213`) is a plain
   `chat.SendCustom`, which only the old Action Log renders, and it has no play-observer
   notify. A trigger whose only effect is the note writes no History row
   (`ChangedTheTable`, `HistoryCapture.lua:412`, ignores messages). The older `Post`
   callers (`AbilityDamage.lua:482` bonus note, `MCDMCreature.lua:7558` heal bonus) have
   the same gap. No data uses `log_note` yet; Condemned (Gerold) is the intended user.

## 2. Privacy: players see Director-only information

5. **Hidden / invisible creatures are named to players.** `History.Creature`
   (`HistoryCapture.lua:88`) records only `namePrivate`; ForPlayers (`History.lua:449`) has
   no `invisibleToPlayers` / `IsHidden()` cut (only reinforcements check it, Capture:2240).
6. **GM-only and Dice Tower table rolls and saves show to players.** `OnTableRolled`
   (Capture:2142) and `OnSaved` (Capture:2025) never record `RollUtils.RollPrivacy`.
7. **Monster Stamina numbers.** Checked. `staminaset` (Capture:2200) and
   `temporarystamina` (Capture:1206) store exact values; the tray prints
   "X Stamina 40 to 25" (`HistoryTray.lua:2217`) with no Monster Knowledge gate.
8. **Malice lines in the rail badge and hover card.** Checked. `Unseen()`
   (`HistoryTray.lua:5944`) runs every line through LineWords with no malice filter (the
   list and bubble both filter it). Players also get phantom unseen turns from
   ownerless Malice lines; the Director gets `quiet` Malice lines.
9. **Monster trigger cards through the ability title.** Checked. `AbilityCard` falls back
   to `TriggerCard` (`HistoryCard.lua:737`); the header (`:897`) gates only on
   `PlayersMaySeeAbility`, which is revealed on any use. Breaks COPY Round 18.
10. **Side view of a token the player can't see.** Checked. `RowMovers`
    (`HistoryCard.lua:1032`) tests `token.valid`, not `canSee`; the ghost shows its live
    appearance and path.
11. Smaller: a hidden roll's total survives in `who.opposed` (`History.lua:526`); surge
    origin hovers (`part.freefrom[i].hover`, `gainedfrom`) aren't cleared by
    `WithoutHovers` (`History.lua:535`, card `:2843`). Malice filtering lives in the tray,
    not ForPlayers, so any new reader leaks it.

## 3. Old Action Log, Crows and dock-mode regressions

12. **Applying a built-in View drops the Action Log** for old-log and Crows users:
    `ViewsApplyLayout` (`DocumentSystem.lua:27934`) stores v7/v8 as-is (no "action log"),
    and `PlaceRailButton` runs only on EnterGame / the setting change. Crows on a pristine
    v6 view loses it for the session after the silent update.
13. **Dock mode loses a docked Action Log with nothing in its place.**
    `PanelPermittedForUser` now checks `available` (`DockablePanel.lua:2259`); History is
    never added to a dock. Medium confidence (depends on rail-off users).
14. **Audio captions.** They moved from chat to the Chat rail bubble: they fade within
    about 1.3 s when Chat is in front (the bubble think at `DocumentSystem.lua:17386`
    ignores `evenInFront`), and show nothing in dock mode, with Chat grouped/overflowed,
    or on the old log (`Audio.lua:1238-1363`). The 10 s freshness check compares two
    clients' server time (skews).
15. **The sidebar preview keeps running for old-log users.** Checked. `BubbleTick`
    (`HistoryTray.lua:6233`) gates only on `History.Enabled()`; it sorts keys for every
    map every 0.5 s and builds bubble panels that `ShowRailBubble` then drops unattached.
    Fix: bail on `History.UsingOldLog()`.
16. History radial item (`TokenUI.lua:2818`) and card chip (`HeroCardBack.lua:1559`) show
    for old-log users and do nothing; gate on `UsingOldLog()`. The EotW HUD
    (`EncounterOfTheWeekHud.lua:1220`) reads `UsingOldLog()` once at build.

## 4. Robustness: a History error can stall play

17. **Tests can hang.** Checked. `RollCustomPowerTableTest`'s `completeRoll`
    (`MCDMCreature.lua:5517`) calls `NotifyTested` before the pcall'd `onComplete`; the
    notify's own work (`RollUtils.NotifyTested`) is outside the observer pcall. A raise
    there leaves a montage or puzzle test waiting with its card hidden. Same order in
    `ShowCharacteristicRollDialog` (`:5632`, drops "rollpower" triggers) and
    `DSRequestRollsDialog.lua:1104` (the Director's request waits forever). Fix: pcall or
    move after.
18. **A nil map drops the whole frame's batch.** Checked. `Flush` (`History.lua:355`)
    indexes `byMap[entry.map]` outside the pcall after clearing `g_waiting`. Possible for
    off-map heroes (respites through `GetCharacterById`).
19. `HandEdit`, `ForCast`, `EndingEffects` (`Creature.lua:80`, `:98`, `:9105`) pcall and
    re-raise with `error(err, 0)`: every `RemoveOngoingEffect`, purge, end-of-turn removal
    and TacPanel hand edit now loses its stack trace in bug reports. Use
    `xpcall(fn, debug.traceback)`.
20. Roll details (`AddRoll`, `AddDamageParts`, `AddRollTriggers`, `EdgeSources`,
    Capture:792-833) run before `History.Write`; one error silently loses the row. The
    up-front spend's 0.5 s Schedule (Capture:1450) doesn't check `token.valid`.

## 5. Wrong or stale display

21. **Merged "ended" lines never show Reverted** (`HistoryTray.lua:3668`): the sig omits
    `reverted`; the rebuild also drops `hidden`/`secret` (HiddenEye missing) and appends
    to the shared `sources` table, widening the Director's Delete/Hide.
22. **Action row sig ignores nested-entry rewrites** (`HistoryTray.lua:3685`): Hide/Reveal
    on a nested trigger or roll doesn't rebuild the row or open card; the menu keeps
    offering "Hide from players"; a revealed secret opposed roll stays "rolled in
    secret". Fix: `tostring(kid)` in the sig.
23. **Per-target roll data by loop index** (`MCDMAbilityRollBehavior.lua:2415-2460`): with
    `promptWhenResolving`, every target reads `multitargets[1]`'s edges, banes, sources
    and surges. The in-play surge count has had the same bug since before the branch.
    main's b64b3c71 narrows it to forced-movement tiers. Match by `tokenid`.
24. Lines filed under `game.currentMapId` (Malice with no caster Capture:1541, Hero
    Tokens 1568, downtime 1613, negotiation 1662, montage 1722, `OnTurnReverted` 2320):
    a Director looking at another map files them there, and Revert Turn marks nothing on
    the combat map.
25. Turn Rewind still matches by time (`History.lua:754`, `:775`), the skew Revert Turn
    already fixed.
26. `OnTurnEnded` (Capture:2365) runs `ModifyProperties` on every token with lapsed
    effects from inside History, on whichever client clicked End Turn, once per token in
    a group turn: game state that only changes when History is on.
27. Card scroll `maxHeight = args.maxHeight - 62` (`HistoryCard.lua:3675`) assumes a
    one-line header; a wrapped title runs the bottom past the frame.
28. The fold-animation copy (`HistoryTray.lua:5574`) isn't
    `MakeNonInteractiveRecursive`: a map click in its 0.9 s flight can land on the copy.

## 6. Minor

- "Potency raised with %d surges" reads "1 surges" (`HistoryCard.lua:3286`); wording
  needs James's sign-off.
- Squad-death rows in hash order (`HistoryCard.lua:569`); two hover dwell timers can open
  a hover twice (`:806`).
- Iron Grip's escape damage ignores main's `logActorCondition` (`AbilityDamage.lua:58`);
  Immune to Forced Movement leaves no trace, and at `AbilityInvokeAbility.lua:1502`
  `NoteStability` runs before the immunity check; nested-invoke strikes (3d0dce40) may
  drop the kit bonus part from the Tier line.
- `UndoResource`'s ModifyProperties is undoable (Ctrl+Z restores, line still says Undone).
- Perf: `History.Keys` re-sorted per map on every BubbleTick and Unseen; `searchResults`
  tree walk per refresh; `MergeStyles(Styles())` per linger and keystroke;
  `GetConditionImmunities` extra walk per InflictCondition.
- Small leaks: `g_links`/`g_linkIds`, `g_parsed`, `g_closing`/`g_falling`/`g_provoking`;
  `History.Clear` leaves `data.counts`.
- Open card left showing a deleted or filtered-out entry (`HistoryTray.lua:4752`).
- Old saved effect instances share id "deprecated" (`Creature.lua:9078`).
- `NoteHistory` sits under `TotalsFromLog`'s doc comment (`EncounterMontage.lua:338`).

## Housekeeping before the PRs

- Two uncommitted `HISTORYDIAG` prints (MCDMAbilityRollBehavior.lua, EmbeddedRollDialog.lua).
- `Definitions/dmhub.lua` stubs (`CreatePath`, `MarkMovementArrow` path) were hand-copied
  from engine `feat/saved-movement-path` (af03f472): land with that engine PR. HistoryCard
  pcalls the call.
- Whole-codex type check on the merged tree not run.
- Rules fix 4d265199 (ResetMods clears `nonwastedSurges`) reviewed correct; name it in the
  PR as a gameplay fix (strike-only surges can no longer be banked).

## Checked and clean

Syntax (`luac -p`) and ASCII on all 59 changed files and the 24 merged shared files.
Observers are pcall'd and re-register on reload without doubling; every handler is gated
on `History.Enabled()` (Crows writes nothing); one writer per event; all `CompleteChange`
calls are `undoable = false` and the document isn't checkpoint-registered; entries are
compact JSON with a 500 cap and culling; wrappers keep return values and argument order;
no nested ModifyProperties; no `game.Refresh`; no per-frame work beyond gated thinks;
vscroll set at creation; Schedules guarded; `cond()` and forward declarations safe; old
saved entries read safely in the card and tray; `historyenabled` referenced nowhere on main.
