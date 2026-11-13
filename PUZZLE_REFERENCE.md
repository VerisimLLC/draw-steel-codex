# Puzzle Types: Authoring Reference

A puzzle type is one Lua file that calls `PuzzleType.Register{...}`. The framework does
everything around it: shared state and sync, late joiners, the Solved / Failed banner,
the chat line, timers, Director Reset / Solve / Bypass, hints, roles, per-player assists,
and showing the puzzle in a journal page (`[[puzzle:Name]]`) or behind a Puzzle Lock on a
map object. Your file only says what the puzzle looks like and how a move changes it.

Worked example: `DocumentSystem/PuzzleTerminal.lua` (a password terminal with a code
sheet only one role can read). Others: `RichSliderPuzzle.lua` (click-only grid) and
`RichTornPuzzle.lua` (drag plus click-to-place, holds). The framework itself is
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
| `Render(ctx)` | yes | Build the panel ONCE. It is refreshed by the `refreshPuzzle(element, ctx)` event, fired down the whole tree. |
| `IsFailed(state, config, now)` | no | True when the puzzle is lost (a bomb went off). Timers are separate (below). |
| `SolvedState(config)` | no | A finished board, so the Director's Solve shows it. Without it, Solve bypasses. |
| `Hint(state, config)` | no | Text the Director can reveal with "Show hint". |
| `Status(state, config)` | no | One line under the puzzle ("Moves: 4"); nil for none. |
| `ConfigKey(config)` | no | A string; when it changes (e.g. grid size), saved boards are discarded and a new one is made. |
| `roles` | no | `{ {id, name}, ... }` the Director can hand to players; read `ctx.role`. |
| `assists` | no | `{ {id, label}, ... }` per-player toggles drawn under the puzzle; read `ctx:Assist(id)`. |
| `CreateEditor(id, config, setConfig)` | no | The annotations-strip tile, when an image picker is not enough. |

Setup field `type`s: `text`, `multiline`, `number` (`min`, `max`), `toggle`, `choice`
(`options = { {id, text}, ... }`), `image`. Optional `visible = function(config)` hides a
field until it applies. Every puzzle also gets a "Time limit" field from the framework.

## The context (`ctx`)

| | |
|---|---|
| `ctx.state`, `ctx.config` | The board and the Director's setup. Copies: change the board only through `ctx:Change`. |
| `ctx:Change(fn, description)` | `fn(state, config)` edits a copy; return `false` to cancel. Saved, synced, checked for solve/fail. |
| `ctx.readonly` | True when solved, failed, or the journal page is in edit mode. Ignore input then. |
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
- **Never write config from `Render`**; config is the Director's.
- Text entry: Enter fires `submit` on a single-line `gui.Input` (not `confirm`). Give it a
  button too, as the terminal does.

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

## Map locks and effects

A Puzzle Lock (Interactable component -> Puzzle Lock on any map object) shows your type
with no extra work. What solving or failing does is chosen by the Director in the lock's
setup. To add your own effect (an alarm, lights, guards), register it:

```lua
PuzzleEffect.Register{
    id = "alarm",
    name = "Sound the alarm",
    Apply = function(effect) chat.Send("An alarm blares!") end,  -- runs on the host; must be safe to run twice
    Undo = function(effect) end,                                  -- optional, for the Director's Reset
}
```

## Accessibility checklist

The framework gives every type a Bypass, a Draw Steel bypass test on locks, a text
banner and chat line, confirm-on-Reset and adjustable timers. Your type must still:

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
- The Director's Panels -> Puzzles -> New puzzle makes a puzzle with no page or lock.
- A second window as a player: `dmhub.DuplicateWindowInNewProcess{asplayer = true}`.
  A window started before a new file was registered does not load it; restart it.
- The Director's Panels -> Puzzles list shows every puzzle, its state and who is at it.
