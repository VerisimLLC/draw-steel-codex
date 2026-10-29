# Type checking the codex

The codex is plain Lua 5.4, checked before it runs by
[lua-language-server](https://github.com/LuaLS/lua-language-server) (LuaLS) reading
[LuaCATS](https://luals.github.io/wiki/annotations/) annotations: `---@param`,
`---@return`, `---@class`, `---@field`, `---@type`, `---@cast`. The engine never sees
them; they are comments. `Definitions/` holds the stubs that describe the engine's Lua API
(`dmhub`, `gui`, `game`, ...), and `.luarc.json` holds the checker's settings, which your
editor, the command line and CI all share.

## The rule: zero problems

**Every file checks clean, and a change must keep it that way.** Since 2026-10-14 the
whole codex reports zero problems, and CI checks every push to `main` and every pull
request (`.github/workflows/lua-typecheck.yml`). There is no allowance per file: one new
problem fails the check.

When the checker reports something, fix it. Most findings are real -- a nil that can
arrive, a misspelt field, a missing `local`, a wrong argument -- and checking clean is
what lets everyone trust the next red mark. Only where a line is right and cannot be
expressed to the checker, suppress **that one line** and say why:

```lua
--D&D 5e reach in feet: Distance counts a diagonal as 7 under 5e's 5 units per square.
---@diagnostic disable-next-line: deprecated
if attackerToken:DistanceInFeet(defenderToken) > self.meleeRange then
```

Never suppress a whole file (`---@diagnostic disable` without `-next-line`), and never
change `.luarc.json` to make a finding go away.

## Seeing problems

**In your editor.** Install the [Lua extension](https://marketplace.visualstudio.com/items?itemName=sumneko.lua)
for VS Code (or any editor that runs LuaLS) and open the codex folder itself, so it picks
up `.luarc.json`. Problems show as you type and in the Problems panel. Check the
extension's LuaLS version matches `LUALS_VERSION` in the workflow; a different version can
report different problems.

**From the command line**, any OS, with a [LuaLS release](https://github.com/LuaLS/lua-language-server/releases)
(the one CI uses is named in the workflow), run from the codex folder:

```bash
lua-language-server --check . --configpath .luarc.json --checklevel=Warning --num_threads=4
```

It exits 1 and lists every problem when there is any. `--num_threads` is how many worker
processes share the work; each holds the whole codex in memory (1.7-2.5 GB), so use fewer
on a smaller machine. A full run takes about four minutes on four workers.

**DMHub developers** with the parent repository also have `tools/lua-typing/check.ps1`
(`-Changed` for just your edited files in under a minute), a git hook that runs it on
commit, and the full reference, `LUA_TYPING_REFERENCE.md`.

## Writing code that checks clean

The patterns behind most findings, and their fixes:

- **Declare game types.** `X = RegisterGameType("X")` with a `--- @class X: GameType`
  line above it (or `: ParentType`), and a `--- @field` line for each field instances
  carry. A field nothing declares is reported wherever it is read.
- **Type parameters** of anything other code calls: `--- @param token CharacterToken`.
  An untyped parameter is checked as whatever LuaLS guesses from its uses, and that guess
  can change from run to run -- see "A problem that comes and goes" below.
- **Type locals assigned later.** `local panel = nil` assigned further down and read in a
  closure reads as `nil` everywhere. Put `---@type Panel` on the line above (or `Panel?`
  if it really can be read while nil).
- **Narrow event handlers.** Standard handlers (`click`, `change`, `think`, ...) on
  `gui.Label`, `gui.Input`, `gui.Dropdown` and friends get the right widget type
  automatically. In custom events, say what the element is: `---@cast element Dropdown`
  as the first line of the body.
- **Type what you keep in `panel.data`** with a small `---@class` and a typed local; a
  plain table's fields are never checked.
- **Handle nil where it can really arrive.** If a getter can return nil, guard the read.
  If it cannot here and the checker cannot see why, `---@cast x -nil` with a comment
  naming the reason.
- **Write the return list without brackets:** `fun(): boolean?, table?`.
  `fun(): (nil|boolean), (nil|table)` parses as ONE return value.

## Globals

Assigning a global whose name starts with a lower-case letter is reported
(`lowercase-global`): it is nearly always a missing `local`, and a leaked global is
shared by every caller -- one panel's variable silently becomes another's. Add the
`local`. Globals that really are shared across files are listed in `diagnostics.globals`
in `.luarc.json`; add to that list only for one of those, never to silence a leak. Names
starting `g_` are exempt, by convention for deliberate module-level state.

## A problem that comes and goes

LuaLS infers the type of untyped code from how it is used, and which use it looks at first
can vary -- between runs, between machines, between numbers of workers. A finding that
appears on one run and not the next is that: an untyped symbol. Annotate it, and the
finding either goes for good or turns into a real one you can fix.

## Running it in CI

`.github/workflows/lua-typecheck.yml` runs on every push to `main` and every pull request
that touches a `.lua` file, `.luarc.json` or the workflow, and can be started by hand
from the Actions tab. It downloads the pinned LuaLS release (checked against its
SHA-256), runs the check above with `LUALS_WORKERS` workers, and
`.github/scripts/luals_report.py` turns the result into annotations on the pull request's
changed lines and a table in the run summary. The job fails on any problem, and also when
a worker produced no result (LuaLS would otherwise merge what it has and read as clean).

Sizing, measured 2026-10-14 with Linux LuaLS 3.19.2 on a clean export of the codex, pinned
to 4 cores (a public repository's `ubuntu-latest` runner has 4 vCPUs and 16 GB):

| Workers | Wall time | Peak memory, all workers |
|---|---|---|
| 1 | 650 s | 5.5 GB |
| 2 | 355 s | 4.9 GB |
| 4 | 226 s | 6.8 GB |

The workflow uses 4. Those cores were a desktop i9's, so expect a runner to take longer --
plausibly 5-8 minutes; the job's 30-minute timeout leaves room. Pushing to `main` directly
is not blocked by CI (it reports after the fact); a pull request shows the result before
merge.

## Also

- Annotations are comments, so the **ASCII-only** rule applies to them too (no em dashes
  or curly quotes; see `CLAUDE.md`).
- A pull request that adds a file adds it under the same rule: zero problems.
