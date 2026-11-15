# Puzzle Types: Authoring Reference

A puzzle type is one Lua file that calls `PuzzleType.Register{...}`. The framework does
everything around it: shared state and sync, late joiners, the Solved / Failed banner,
the chat line, timers, Director Reset / Solve / Bypass, hints, roles, per-player assists,
and showing the puzzle in a journal page (`[[puzzle:Name]]`), behind a Puzzle Lock on a
map object, on the table, the icon rail or in chat -- one puzzle in any number of these
places (see "Where a puzzle lives"). Your file only says what the puzzle looks like and how a move changes it.

Worked example: `DocumentSystem/PuzzleTerminal.lua` (a password terminal with a code
sheet only one role can read). Others: `RichSliderPuzzle.lua` (click-only grid),
`RichTornPuzzle.lua` (drag plus click-to-place, holds), `PuzzleCombination.lua` (custom
setup controls, keyboard play, a once-per-hero test through the host request queue, kept
data) and `PuzzleWardedSeal.lua` (the fullest example: a host that deals players different
parts, a generated puzzle from an engine-free module, an in-window chat, its own `HostTick`
with presence and timer control). The framework itself is
`DocumentSystem/PuzzleFramework.lua` (model) and `RichPuzzle.lua` (frame and window).

## The smallest useful type

```lua
local mod = dmhub.GetModLoading()

PuzzleType.Register{
    id = "lever3",
    name = "Three levers",
    fields = {
        { id = "answer", type = "text", label = "Answer (e.g. 101)", default = "101" },
    },
    NewState = function(config, ctx)
        return { levers = "000" }          -- a string, not a list (see State rules)
    end,
    IsSolved = function(state, config)
        return state.levers == config.answer
    end,
    Render = function(ctx)
        local buttons = {}
        for i = 1, 3 do
            buttons[i] = gui.Button{
                classes = {"sizeM"},
                text = "Lever " .. i,
                click = function(element)
                    ctx:Change(function(state)
                        local c = state.levers:sub(i, i) == "1" and "0" or "1"
                        state.levers = state.levers:sub(1, i - 1) .. c .. state.levers:sub(i + 1)
                    end, "Pull lever")
                end,
                refreshPuzzle = function(element, newCtx)
                    ctx = newCtx
                    element.text = string.format("Lever %d: %s", i,
                        newCtx.state.levers:sub(i, i) == "1" and "down" or "up")
                end,
            }
        end
        return gui.Panel{ flow = "horizontal", width = "auto", height = "auto", children = buttons }
    end,
}
```

New files only load once registered in their CodeMod (see the codex `CLAUDE.md`).

## `PuzzleType.Register` fields

| Field | Required | What it is |
|---|---|---|
| `id`, `name` | yes | Stable id (stored in every puzzle) and the name in the type picker. |
| `fields` | no | Director setup fields, drawn by the framework (below). |
| `NewState(config, ctx)` | yes | A fresh board. Use `ctx.random` for anything random. |
| `IsSolved(state, config)` | yes | Pure check, run after every move and again by the host before anything opens. |
| `Render(ctx)` | yes | Build the panel ONCE. It is refreshed by the `refreshPuzzle(element, ctx)` event, fired down the whole tree -- **every half second while a timer runs**, not only on change (see State rules). |
| `IsFailed(state, config, now)` | no | True when the puzzle is lost (a bomb went off). Timers are separate (below). |
| `SolvedState(config)` | no | A finished board, so the Director's Solve shows it. Without it, Solve bypasses. |
| `Hint(state, config)` | no | Text the Director can reveal with "Show hint". |
| `Status(state, config)` | no | One line under the puzzle ("Moves: 4"); nil for none. |
| `ConfigKey(config)` | no | A string; when it changes (e.g. grid size), saved boards are discarded and a new one is made. |
| `roles` | no | `{ {id, name}, ... }` the Director can hand to players; read `ctx.role`. |
| `assists` | no | `{ {id, label}, ... }` per-player toggles drawn under the puzzle; read `ctx:Assist(id)`. |
| `CreateEditor(id, config, setConfig)` | no | The annotations-strip tile, when an image picker is not enough. |
| `HandleRequest(id, state, req, userid, after)` | no | The host applies players' requests (see Requests below). |
| `HostTick(id)` | no | Runs about once a second on the host for each puzzle of the type; a type with one applies its own requests with `Puzzle.ProcessRequests`. |
| `noTimeLimit` | no | The framework's time limit is not offered. |

Setup field `type`s: `text`, `multiline`, `number` (`min`, `max`), `toggle`, `choice`
(`options = { {id, text}, ... }`), `image`, and `custom`: `Control = function(config,
setConfig) return panel end` draws its own control (the combination lock's per-dial code
picker and named image list). Optional `visible = function(config)` hides a field until it
applies. After any field changes, the setup fires `setupChanged` down every field row, so a
custom control that depends on other fields rebuilds on that event (a `think` inside the
setup popup does not tick). Every puzzle also gets a "Time limit" field from the framework.

## The context (`ctx`)

| | |
|---|---|
| `ctx.state`, `ctx.config` | The board and the Director's setup. Copies: change the board only through `ctx:Change`. |
| `ctx:Change(fn, description)` | `fn(state, config)` edits a copy; return `false` to cancel. Saved, synced, checked for solve/fail. |
| `ctx.readonly` | True when solved, failed, the journal page is in edit mode, or `ctx.away`. Ignore input then. |
| `ctx.away` | A player opened a lock's puzzle away from the lock (a page, the table, chat). The frame already makes your panel take no clicks; dim or explain if you like. |
| `ctx.solved`, `ctx.failed`, `ctx.status` | Outcome. The framework draws the banner; you only adjust your own look if you want. |
| `ctx.now` | `dmhub.serverTime`: within about half a second on every client. |
| `ctx.random(k)` | Seeded integer in 1..k: the same on every client for the same board. |
| `ctx.role`, `ctx:Assist(id)` | This player's role id (or nil) and assist toggles. |
| `ctx.isDirector`, `ctx.userid`, `ctx.userName` | Who is looking. |
| `ctx:Hold(key)` / `ctx:Release(key)` / `ctx:HeldBy(key)` | One player at a time on a piece. `HeldBy` names another player holding it; holds expire after 20 s. |
| `ctx:Pick(key)` / `ctx:Picked()` / `ctx:Unpick()` | Click-to-place: pick a piece up (holding it), then act on the next click. |

## State rules (these bite)

- **Never store a Lua list.** Lists are uploaded whole, so two players' moves to one list
  overwrite each other. Use keyed tables (`tiles["r3c4"]`) or strings (`"8,7,1,6"`).
  A running log is one string you append to, as the terminal does.
- **State must be plain data**: strings, numbers, booleans, keyed tables.
- **Redraw from `ctx`, never from local variables**, so Reset, Revert Turn and other
  players' moves all show. Local state is fine for things only this client sees (what is
  being dragged).
- **Don't rebuild on every `refreshPuzzle`.** While a timer runs (or holds are live) the
  frame fires it every half second with nothing changed. A panel that rebuilds its children
  each time closes any open dropdown and loses half-typed input. Update text in place, or
  compare a signature of what you draw (`json(ctx.state)` plus anything else you show) and
  rebuild only when it differs, as the Warded seal does.
- **Never write config from `Render`**; config is the Director's.
- Text entry: Enter fires `submit` on a single-line `gui.Input` (not `confirm`). Give it a
  button too, as the terminal does.

## Kept data: what survives a Reset

`Puzzle.ReadKept(id)` returns a copy of the puzzle's kept table; `Puzzle.ChangeKept(id, fn,
description)` edits it in place (`fn(kept)`, keyed tables only). Reset leaves it; setting
the puzzle up again (`Puzzle.Create`, e.g. a type change) clears it. Use it for once-only
records -- who has rolled a test, what it revealed -- so a Reset is not a free retry. The
lock's Force it record (`kept.bypass`) and the combination lock's `kept.listen` /
`kept.marks` live here.

## Requests: players ask, the host decides

For anything the table must not be able to do twice (a once-per-hero test, a bet), the
player files a request and the host applies it:

- `Puzzle.Request(id, { kind = "...", ... })` -- queued per player in the board, numbered,
  applied once and in order.
- `HandleRequest(id, state, req, userid, after)` on your type -- edit `state` (the board
  copy) for the board; push functions into `after` for writes to other documents (chat,
  kept data, status), which run once the board is saved. Return `false` to wait (that
  player's later requests wait behind it).
- Do the once-only check **in `after`**, against `Puzzle.ReadKept`: two requests arriving in
  the same tick both see the saved kept data, but each `after` runs after the previous one
  has written.
- `Puzzle.RegisterRequestHandler(kind, fn)` -- a shared handler for every type (the lock's
  `bypass`), tried before the type's own.

## Heroes and tests

- `Puzzle.MyHero()` -- the player's selected token, else their primary character.
- `Puzzle.HeroById(tokenid)`.
- `Puzzle.RollTest(tok, attrid, skill, name, tiers, stillWanted, onDone, onCancel, bane)` --
  the montage's skill-aware test (Skilled chip, features), private to the roller; `skill`
  may be `""` or two skills ("Read Person, Gamble": the Skilled chip lights for either).
  `onDone(tier, natural)`; `onCancel` when the player closes the roll. `bane`, optional, is a
  reason string: the roll gets a bane that names it ("Bane: Vell has clammed up").
- `Puzzle.TestOutcome(tier, natural, difficulty)` -- Draw Steel's test difficulty rows:
  `"success"`, `"consequence"`, `"failure"`, `"failconsequence"`, plus `reward`.

## Keyboard

Panel `keybinds` do **not** override game keys: in the main window they fire alongside the
game command on the same key (an arrow would turn your dial and move a token) and in every
panel holding the key. To own keys, do what the PDF viewer does: bind them in a command
context (`dmhub.SetCommandBinding(key, "mycmd", "mycontext")` once), push the context while
your panel has the GUI focus (`gui.ChildHasFocus(panel)`; push straight away when you call
`gui.SetFocus`, not only from a `think`), pop it when focus leaves or the panel is
destroyed, and receive the keys as events via `commands = { "mycmd", ... }`. See
`PuzzleCombination.lua` (`combolock`).

Three traps, found on the Warded seal (`wardseal`):

- **One Enter press fires both the `return` and `enter` bindings.** If Enter opens a
  confirm, the second binding answers it at once; ignore a repeat within a few tenths of a
  second.
- **Escape belongs to the window**: binding it in your context does not stop it closing the
  puzzle window. Use another key for "no".
- **A text box inside the panel** (a chat input) also counts for `gui.ChildHasFocus`, so
  typing would trigger your keys. Push the context only when `gui.GetFocus() == panel`, and
  set the focus to the panel itself when the player clicks your board.

## Solving, failing, timers

- Board puzzles: `IsSolved` reads the board, and the host re-checks it, so a client
  claiming a solve its board does not show is rejected.
- Action puzzles (a password): write a flag (`state.unlocked = true`) and have `IsSolved`
  read it. **The host cannot verify a flag**, so a player running Lua could forge one.
- **Answers are readable.** Everything in config and state is on every client. A
  determined player can read the password. Accepted for table play; do not use puzzles to
  protect real secrets.
- Timers: the Director sets a time limit and presses Start timer; the host fails the
  puzzle when it runs out. The game setting "Puzzle timers" (normal / double / off) scales
  every limit. Use `IsFailed` only for losses your board decides (a wrong wire cut).
- A type can drive the timer itself from the host: `Puzzle.StartTimer(id)` (the seal's
  Begin, so a table with no Director still gets one), `Puzzle.PauseTimer` / `ResumeTimer` /
  `ExtendTimer(id, seconds)`, `Puzzle.TimeLeft(id)` (nil when none) and
  `Puzzle.TimerPaused(id)`. Pause is one flag, not a count: if several things can pause it
  (two players rolling at once), keep who is pausing in your state, pause when the first
  starts, resume only when the last ends, and never resume a pause you did not make (the
  seal's `RollPause`). Call these from `after`, not inside the board edit.

## Split parts: one puzzle, different views

The framework's `roles` are handed out by the Director in config. A table with no Director,
or one where the parts must follow who turns up, needs the host to deal instead. The Warded
seal's pattern (`PuzzleWardedSeal.lua`):

- **A gathering, then Begin.** The board starts at `phase = "gathering"`; anyone can press
  Begin, which is a request, and the host deals in `HandleRequest`. Parts live in **state**
  (`state.parts = { hands = userid, solo = bool, readers = { [userid] = "m1,L2" } }`), not
  in `config.roles`: players never write config, and a Reset must re-deal.
- **Who is there:** `Puzzle.PresentUsers(id)` (fresh heartbeats). Leave Directors out of the
  deal (`dmhub.GetSessionInfo(userid).dm`); a player host is a player and is dealt in.
- **What the player would rather have:** an `"account"` setting follows the player but other
  players cannot read it, so each window writes it into the gathering state
  (`state.prefs[userid]`) and the host honours it where it can. A Director's pin goes in
  config and wins.
- **One function says who sees what**, `RoleOf(state, userid, isDirector)`, and the panel
  draws from it alone: hands, solo (one player sees everything), reader with page keys,
  Director (sees all) or watching.
- **Coming and going in `HostTick`:** mark the hands away after a few seconds without a
  heartbeat, hand over to a present reader after a minute, let a returning player read
  again, and give any page nobody holds to the reader with the fewest. Log each change in
  words.
- **Changing parts:** swap / pass / take are offers in state, answered by the other player;
  once anything has been done to the board they also need the referee (the Director, or the
  player host at a table without one: `IsDMOrPlayerHost()`).
- **Hidden is not secret.** Every client has the whole state, ward and pages included; the
  split is a table agreement, as with any puzzle answer.

## Generated puzzles: keep the generator engine-free

The seal's ward and codex pages come from `PuzzleWardGen.lua`, which touches no engine API:
it takes a seeded `random(k)` (`Puzzle.SeededRandom`) and returns plain tables. That lets
`tests/puzzle_ward_gen_test.lua` run thousands of seeds through the bundled `lua.exe`
(from the codex root: `../dmhubclient/dependencies/lua/bin/lua.exe
tests/puzzle_ward_gen_test.lua [seeds]`), checking that every ward has exactly one answer,
that the rule which decides is spread across lines, that the page text reads back to the
rule it came from, and that the Ask questions exist for every page. The host generates once
at Begin and writes the result into state, so every client draws the same thing without
re-running it. Do the same for any type whose content is generated: the module owns
`Generate`, `Solve` and the player-facing text, and the type file only deals and draws.

## Shared rune art

`DocumentSystem/PuzzleRunes.lua` holds the ten named runes (Flame, Eye, Key, Moon, Sun,
Skull, Star, Sword, Crown, Hourglass) used by the combination lock and the seal, the
colour-blind-safe thread colours (Okabe-Ito: Crimson, Amber, Gold, Jade, Azure, Rose) with
their patterns (solid, dashed, dotted), and `PuzzleRunes.ThreadPanel(colour, pattern,
width, thickness)`. Always show a rune's or thread's name as text beside it. New rune art
dropped into the same slots upgrades every puzzle that uses them.

## Games of chance

`GameOfChance.Register{...}` (`GameOfChance.lua`) makes a game of chance a puzzle type:
winning the required rounds solves it, losing the allowed rounds fails it or offers another
game, and stakes (gold, 1 Wealth, a Recovery) are paid once per game by the host and given
back by Reset -- every game's payment, kept through Play again. Two flows:

- **Bet** (the default; the shell game): the host deals a round everyone watches in sync,
  players point and test, one places the bet, the host judges it. A game supplies
  `DealRound`, `Duration`, `Options`, `Judge`, `Board` and its test.
- **Turns** (`flow = "turns"`, `GameOfChanceTurns.lua`; Liar's dice in `LiarsDice.lua`): a
  round is a challenge made of turns -- players' moves as requests, NPC turns run by the
  host. A game supplies `presets`, `presetOptions`, `startLabel(g)`, `NewGame`,
  `CanStart`, `Start`, `Move` (any phase but "over"; it gets the phase), `HostStep` (gets
  the pace), `Status`, `Board` (receives the `chanceTurns` event), and optionally `EndNow`.
  It reports `{log, chat, round = "win"|"lose", final, bettor}` events; the layer counts
  rounds, pays stakes and ends the game. The game's public data lives in `state.g`.

**Host-held secrets.** Everything in a puzzle's state is on every client. When reading it
would win the game (the gamblers' hidden dice), keep it on the host only:
`GameOfChanceTurns.ReadSecret(id)` / `WriteSecret(id, t)` store it in a `PerGamePreference`
setting -- the host's own local file, kept through a Lua reload or restart on that machine.
Put a salted hash of each secret in state (`LiarsDiceBidder.Commit(salt, text)`, 64-bit
FNV-1a) and publish the salt at the reveal so the table can check it; the salt is what stops
anyone guessing a small secret from its hash. A new host has no secret: the game must cope
(Liar's dice shakes the challenge again). At a table with no Director the host is a player,
who could look. The preference file is per machine, not per account (`{persistentDataPath}
/settings/<gameid>.<id>.txt`), so two windows on one computer share it: a second test window
can read the host's secret. Check the hiding with two computers, not two windows.

**Pacing.** Each window reports how its player watches (slowly = 2, "don't watch" = 0) and
the host times NPC turns to the slowest player present. Report from what the window last
*sent*, never by comparing with saved state inside the redraw: the request's own write
redraws before the host has applied it, and that loop overflows the stack.

**Rolls that hold the table.** A test roll opens a dialog that takes time. Send a
"rolling" request when it opens and when it closes (or the result arrives); while any are
open the host holds the moves that would make the result stale, and drops a forgotten one
after a minute. Never pause on a single flag: several players can roll at once.

## Map locks and effects

A Puzzle Lock (Interactable component -> Puzzle Lock on any map object) shows your type
with no extra work. A library object can preset the type: `puzzletype = "combination"` on
the `PuzzleLockInteractive` makes each placed copy start as that puzzle the first time the
Director uses it (the Combination lock object in the Puzzles folder; the Puzzle switch
leaves it empty and asks). What solving or failing does is chosen by the Director in the lock's
setup. To add your own effect (an alarm, lights, guards), register it:

```lua
PuzzleEffect.Register{
    id = "alarm",
    name = "Sound the alarm",
    Apply = function(effect) chat.Send("An alarm blares!") end,  -- runs on the host; must be safe to run twice
    Undo = function(effect) end,                                  -- optional, for the Director's Reset
}
```

## Where a puzzle lives (placement)

One puzzle can live in several places at once, and they all show the same board. The
Director puts it there from the Puzzles panel: drag a row, or use its Place menu (also on
right-click). Code: `PuzzlePlace.lua` (building blocks), `PuzzlePlaceMap.lua` (the map),
`PuzzleShare.lua` (table, rail, chat, and the row's drag to every surface).

| Place | How it gets there | Home kind |
|---|---|---|
| A map object | Dropped on it, Place on map + click, or Lock the selected object: a Puzzle Lock component is added (or an existing one repointed) | `lock` |
| Empty floor | Dropped there: a Puzzle switch (or Combination lock) object is placed | `lock` |
| Near a door | Dropped by a drawn door or a door object: a lock object with "Unlock this door" already set | `lock` |
| A journal page | Dropped on the page: a `[[puzzle:...]]` tag whose `puzzleid` names this puzzle | `journal` |
| The table | Dropped on the bare table, or Put on your table: a table item (share it from its title bar) | `table` |
| The icon rail | Dropped on a rail, or Add to your rail: a button | `rail` |
| Chat | Dropped on chat, or Post in chat: a link anyone can click | (not a home) |

**Homes.** `Puzzle.Homes(id)` returns home key -> `{kind, floorid, objid, docid, tag, placed}`
from the index document. `placed` records what placing added (`"component"`, `"object"`), so
`PuzzlePlace.RemoveHome` takes exactly that away; a lock the Director built by hand keeps its
component with an empty puzzle id. Deleting tag text or a component sends no event, so the
panel checks every home each time it builds (`PuzzlePlace.HomeLive`) and shows gone ones
with Clear. Old single-home index entries (`kind`/`floorid`/`objid`/`docid` on the entry) are
read as one home and moved into `homes` on their next write.

**Journal tags.** A tag's puzzle is `Puzzle.JournalId(tag, prefix)`: its `puzzleid` field when
set, else the page's own id (`Puzzle.OwnJournalId`: page + tag name). The lock setup and the
tag's cog offer "Use an existing puzzle" (`Puzzle.SetupPanel`'s `pick`); a lock that moves
to another puzzle takes its targets and range with it (`PuzzlePlace.MoveLock`).

**Table, rail and chat are the journal's own.** A puzzle is a stand-in journal entry
`"puzzle:<id>"`: `CustomDocument.JournalEntryProviders.puzzle` returns a plain table marked
`virtual` (description, `kindName` "Puzzle: Solved", `icon`, `open()`, `DisplayPanel` for the
hover preview), and `FindJournalEntry`, `JournalEntryKindName/Icon` and `OpenContent` honour
it. So `Tabletop.OpenDocItem("puzzle:<id>")`, the rail's `"journal:puzzle:<id>"` key and
`ChatItemLinks.DocItem("puzzle:<id>")` need no puzzle code of their own. Another module can
add its own prefix the same way. (`CustomDocument` is a GameType: reading an unset field on
it raises, so use `rawget`.)

**Solve at the lock.** `Puzzle.SolveOnlyAtLock(id)` is true when the puzzle has locks and the
lock setup's "Can be solved from anywhere" (`config.solveAnywhere`) is off. A window opened
at the lock passes `atLock = true` to `Puzzle.OpenWindow` / `Puzzle.CreatePanel`; anywhere
else a player gets the board built non-interactive, `ctx.away`, and "Solve this at the ...".
The Director is never away.

**Puzzle-wide actions.** `Puzzle.ConfirmWide(id, title, lines, confirmText, fn, opts)` asks
before Reset (always), Solve, Bypass and a type change when the puzzle lives in more than
one place, naming the places, who is in it (`Puzzle.UserNameWhere`) and the lock effects
(`Puzzle.LockEffectLines`). Use it for any new action that changes every place at once.

**Presence says where.** `Puzzle.MarkPresent(id, present, where)`: "at the Chest" (lock),
"on Handout 3" (page frames), "from chat" (`ChatItemLinks.openingFromChat` is true while a
chat link opens). Directors never trigger a Join notice and are left out of players'
presence lines.

**Map placement gotchas.**
- `obj:AddComponent` returns a component with no properties: find the new key in
  `obj.components`, then `properties:Construct("PuzzleLock")`.
- The hit test is each object's `area` padded half a tile, smallest wins; boxes under a
  tenth of a tile (glow and scratch effects) count only with the point inside.
- `obj:Destroy()` takes several seconds to show.
- `GameHud:ModalDialog` closes the top modal after a button's click returns, so a confirm
  opened from another confirm's button would close at once: schedule it (0.05 s).
- Place on map catches the click on a see-through layer in `GameHud.instance.bannerLayer`;
  in the tabletop view only clicks inside the live map window count
  (`Tabletop.MapWindowRect`).

## Accessibility checklist

The framework gives every type a Bypass, a Draw Steel "Force it" test on locks (once per
hero, kept through Reset, result in chat), a text banner and chat line, confirm-on-Reset and
adjustable timers. Your type must still:

- [ ] offer a path with no drag (clicks or typing); `ctx:Pick` makes it easy;
- [ ] never rely on hover alone, colour alone, or sound alone;
- [ ] keep text readable at its real size (14 px or more), and offer a "Larger text"
      assist if the look is small;
- [ ] say in words what changed after a move (a status line, a log line).

## Testing

- `[[puzzle:Name]]` on a scratch journal page is the fastest loop; edit, reload (F4).
  A page made from Lua also needs the tag's annotation, which the editor adds when you
  type the tag: `annotations = { ["puzzle:Name"] = tag }` with
  `tag = RichPuzzle.Create(); tag.identifier = "Name"`. Without it the tag draws nothing.
- The Director's Panels -> Puzzles -> New puzzle makes a puzzle with no page or lock; its
  Place menu puts it anywhere without dragging (`PuzzlePlace.PlaceAt`, `PutOnTable`,
  `AddToRail`, `PostInChat` from Lua). Remove test homes with `PuzzlePlace.RemoveEverywhere`
  and the puzzle with `PuzzlePlace.Forget`, by id.
- A page drop is easiest to test by dragging onto an open page (`doc:ShowDocument()`); the
  drop goes through the page's `itemLinkDrop`, not through puzzle code.
- A second window as a player: `dmhub.DuplicateWindowInNewProcess{asplayer = true}`.
  A window started before a new file was registered does not load it; restart it.
- The Director's Panels -> Puzzles list shows every puzzle, its state and who is at it.
- To see another part's view from one window, write it into state by hand
  (`Puzzle.Change(id, function(st) st.parts = {...} end, "test")`); the duplicate window
  always logs in as the same secondary account, so it cannot show a deal between two
  different players.
- `Puzzle.SetAssist(id, assistid, on)` from Lua works but does not tick the assist's
  checkbox; click the checkbox when you want to see both agree.
- A turns game's party-side tests from one window: set `state.g.seats.s1.user` to a stand-in
  so your window counts as the party, send the requests, set it back. A throwaway turns game
  can be registered at runtime from Lua to test the layer; never ship one.
- A second window that you drive over HTTP needs its own MCP port:
  `dmhub.DuplicateWindowInNewProcess{asplayer = true, args = "--mcp-port 19878"}`.
- `wrap = true` on a horizontal panel does not grow its height: a second line overlaps what
  follows. Lay buttons out in explicit lines instead.
