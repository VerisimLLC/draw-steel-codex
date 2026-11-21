# History: handover for a new session

Written 2026-11-19. Read this first, then `BUILD-PLAN.md` (what each chunk is, and the notes
from every chunk built so far) and `COPY.md` (every signed line of wording). Machine layout
and the type-check gates are in `D:\draw-steel-codex\CLAUDE.local.md`.

## Where things stand

- **Branch:** `feature/history-stage-3` in `D:\draw-steel-codex`, 88 commits ahead of
  `origin/main` (rebased onto it 2026-11-19). **Nothing is pushed.** All PRs go up together
  at the end.
- **Done:** stages 0 to 4, and stage 5.1 except 5.1h. Today also added the Draw Steel banner,
  the teleport line, opposed power rolls, the cull guard and the card's action-bar reserve.
- **Left:** 5.1h, 5.2, 5.3, 6.1, 6.2, 6.3, 6.4, the loose ends below, then the PRs.
- **`data` shows as modified.** It is a newer checkout than main's pointer. Never commit it.
- **Stage tags** `history-stage-0` to `-2` point at pre-rebase commits. Move them before
  the PRs. The pre-rebase branch is `backup/history-stage-3-pre-rebase-1119`.
- **Engine** (`D:\dmhubclient`): the dev build comes from the local-only branch
  `dev/local-build`, which merges two PR branches, both off `upstream/master` and unpushed:
  `feat/saved-movement-path` (History's movement views) and
  `fix/opposed-roll-flat-double-edge` (double edge or bane on an opposed roll).

## How a chunk is built here

Every capture chunk has the same three parts. 5.1d (respite, commit `31f73117`) is the
shortest worked example; read its diff before writing a new one.

1. **The rules code tells play observers.** One call where the thing happens:
   `GameSystem.NotifyPlayObservers("<moment>", ...)`. Keep it generic: say what happened,
   not what History should write. Hooks in `DMHub Game Rules/` stay system-neutral.
2. **`Draw Steel V/HistoryCapture.lua` handles the moment.** Add a handler and list it in
   the `GameSystem.RegisterPlayObserver("history", {...})` table at the foot of the file.
   Start it with `if not History.Enabled() then return end`. Write a line with `WriteLine`
   (when it has a creature) or build an entry and call `History.AddCombatFacts` then
   `History.Write`.
3. **`Draw Steel V/HistoryTray.lua` words it.** A branch in `LineWords` for the new
   `family`; the small text under a line is the entry's `causetext`. Add the family and any
   new fields to the `HistoryEntry` annotations in `Draw Steel V/History.lua`.

Things that are easy to get wrong:

- **One writer per event.** Decide which client writes (the one that rolled, the host, the
  Director who clicked). Two clients writing the same event doubles it.
- **What players may read is cut in one place:** `ForPlayers` in `History.lua`, applied when
  an entry is read. Put a new visibility rule there, never in the tray. The Director check
  is `dmhub.isDM` everywhere, the Codex's standard.
- **Wording comes from COPY.md.** Anything not signed there is proposed to James first, in
  the reply, and built only after he agrees. Withdrawn lines are marked in COPY.md.
- **A line that opens a detail card** must be listed in `HasCard` (HistoryTray) and handled
  in `History.Story` and the title code in `HistoryCard.lua`.
- **Does it earn a line?** History answers "what just happened and why" during play. James
  cut the downtime roll lines because the project and the Respite already record them.
  When another surface already holds the record, write only what changes the table.

## Checking and committing

- **Syntax:** `/d/dependencies/lua/bin/luac.exe -p "<file>"`
- **Types (ceiling is zero):** from PowerShell in the repo root,
  `& D:\tools\lua-typing\check.ps1 -Files "<file>","<file>"`. To see the problems, pipe to
  `Select-Object -First 30`. A comment block placed between a function and its doc comment
  causes `undefined-doc-param`; keep doc comments directly above their function.
- **ASCII only** in Lua, comments included.
- **Edits:** several of these files are CRLF. Edit with exact-string replacement that keeps
  line endings (a small Python script using `io.open(path, newline='')` has worked all day).
- **Commit one chunk at a time:**
  `git -c core.autocrlf=false add -- <paths>`, check `git diff --cached --stat`, then
  `git commit -q -m "history: <what>" -- <paths>`. Always name the paths: the index is shared.
  The pre-commit hook re-runs the type check.

## Running it

- **Use the dev Codex**, `D:\dmhubclient\MCDMHub\Codex.exe`, test game
  `TwistedRainbowWaywornGuardian`. It reads Lua straight from `D:\draw-steel-codex`.
- **Restart, do not reload.** The bridge's reload does not reliably re-read changed files.
  Stop only the `Codex.exe` whose path is the dev one (leave any other `codex.exe`), then
  `Start-Process` it with `-WorkingDirectory "D:\dmhubclient\MCDMHub"` and
  `-ArgumentList "--gameid","TwistedRainbowWaywornGuardian"`, and poll
  `http://localhost:19876/health` until `inGame` is true and `loading` is false. About 15 s.
- **Bridge:** POST `/execute` with `{"code": "<lua>"}`; GET `/screenshot`;
  POST `/mouse?action=move|click&x=&y=&button=left` (send an empty body with `-d ""`).
  Use the bridge's virtual mouse, never the OS cursor.
- **Fed tests go on a scratch map.** Write test entries with `map = "probe-<name>"`. A fed
  entry with an `encounter` on a real map counts as an encounter and can push real rows
  out; that happened once today. Where a handler writes to `game.currentMapId` and cannot
  be redirected, feed only entries with no encounter, and tell James what you left behind.
- **Prefer the real code path over a fed notification.** Today's best checks ran the real
  function on a detached object: `creature:Rest` on a `DeepCopy` of a Hero, `DTProject:AddRoll`
  on a project attached to no sheet. Neither changed the game.
- **Do not change James's game state** without saying so first. Anything that heals, levels,
  completes a project or shows a banner to every client is his to run.
- **Engine changes:** close the dev Codex and Unity, then
  `powershell -NoProfile -ExecutionPolicy Bypass -File "D:\dmhubclient\build.ps1" windows -DevKey`
  in the background (1 to 2 minutes incremental). Success is `0` `error CS` lines and
  `[BuildScript] Windows build succeeded` in `D:\dmhubclient\build-windows.log`.

## Built today and waiting on James's testing

Say plainly in any report that these were not run for real; do not re-test them unasked.

| What | Checked how | Not yet run |
|---|---|---|
| Draw Steel banner | Tested by James | - |
| Teleport of another creature | Tested by James (Lightfall) | - |
| Opposed rolls: outcome row, dice on the card, +4 and -4 | Real Search for Hidden Creatures rows; engine arithmetic over the bridge | A failed or tied roll, a double bane, a hidden roll seen as a player |
| Respite lines (5.1d) | Tested by James | XP floor and line order need a fresh respite to see |
| Montage lines (5.1e) | Fed data | A real Encounter of the Week montage; `EncounterMontage.NoteHistory` has never executed |
| History button in Encounter of the Week | Type check only | The mode is not loaded in the test game |
| Negotiation lines (5.1f) | Fed through `NegotiationRun.Note` | A real scene; the players' wording on a second client |
| Downtime lines (5.1g) | Real `AddRoll` on a detached project | The completion line |
| Card stops above the action bar | Long Lightfall card | - |
| Cull guard (5-entry encounters) | Scratch map | - |

## Decisions James made today that are not obvious from the code

- **Movement:** a creature's own move writes nothing, teleports included. Only movement done
  to someone is recorded.
- **Dropped from scope:** Otherworldly Grace's save-ends change, Game of Chance rolls,
  character-creation rolls, the Lucky d10, delve and chest rolls, the Encounter of the Week
  negotiation and town, and downtime roll and adjustment lines.
- **After release:** the Acolyte's Patron's Gaze roll. Arcanist is not core content.
- **Performance:** three caches the review suggested were measured and not built (each
  under a millisecond). Do not add them without a measurement that says otherwise.
- **The detail card treats the action bar's strip as the foot of the screen.** Rail windows
  were left alone: users arrange those.
- **Encounter of the Week** covers its corner buttons with a full-screen stage during a
  montage or negotiation, so History cannot be opened then. Lines written there are read
  afterwards.

## Loose ends, each needing an owner

- **Empty tray text:** no signed wording. Propose it.
- **1.3 data pass:** `python docs/action-log-design/probes/mark-history-hidden.py.txt --apply`
  ticks "Hidden from History" on 40 markers. Run it with the Codex closed and commit in `data/`.
- **Crows:** `Crowdex/` is not in this checkout. Check a Crows game loads before merging.
- **6.4 checklist:** the Encounter of the Week corner strip names "Action Log"
  (`EncounterOfTheWeekHud.lua`, `CreateCornerButtonsPanel`). See the Stage 6 notes in the
  build plan.
- **Rules gaps found on the way** are in `docs/rules-deviations-check.md`, items 62 to 64.
  They are outside History.
- **Trigger names:** the Troubadour's Drama triggers are all named "Drama", so History's
  cause line cannot say which rule fired. A data rename would fix it; not decided.

## Working with James

Concise replies, no emojis. One decision at a time, with a recommendation; after proposing,
stop and wait. Report what was and was not verified, and correct an earlier claim outright
when it turns out wrong. He tests each chunk himself before moving on.
