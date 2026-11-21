---
name: typecheck
description: Check the codex Lua for LuaLS type problems and fix them, so CI's Lua type check (zero problems) passes. Runs the codex's own tools/typing scripts, so it works with only the draw-steel-codex repository. Use when someone says "/typecheck", "check my types", "fix the type errors", "the Lua type check failed", "CI typecheck is red", "clean up typing", or before opening a pull request with Lua changes. By default checks the .lua files changed in git; also takes file paths, "staged", or "all".
---

# Type check and clean up

The codex rule is **zero LuaLS problems** in every file; CI fails a push or pull request on
any. [`TYPING.md`](../../../TYPING.md) is the standard -- read it before fixing anything
beyond the obvious. This skill gets someone from "red" to "clean" without them needing to
know LuaLS.

Work from the codex root (the folder holding `.luarc.json`). Python 3 is required.

## Arguments

- none: the `.lua` files changed in git (modified + untracked). The usual case.
- one or more paths: just those files.
- `staged`: what the next commit holds (`--staged`).
- `all`: the whole codex, exactly as CI checks it (`--all`; a few minutes and ~2 GB of RAM
  per worker, 4 workers by default -- pass `--threads 2` on a small machine).

## Steps

1. **Bring the generated annotations up to date.** Both are quick, idempotent, and only
   edit what is missing:

   ```bash
   python tools/typing/annotate_gametypes.py
   python tools/typing/gen_table_overloads.py
   ```

   The first gives every `X = RegisterGameType(...)` its `--- @class X: Parent` and
   `--- @field new fun(o?: table): X` lines. The second types `dmhub.GetTable` /
   `GetTableCached` rows for every `X.tableName = "..."`. If either touched a file the
   user did not change, say which and why (someone else's new type had not been run
   through it); do not revert it.

2. **Run the checker:**

   ```bash
   python tools/typing/check.py [files... | --staged | --all]
   ```

   Exit 0 = clean; exit 1 = problems, printed as `path:line:col: code: message`; exit 2 =
   the check could not run. If it says lua-language-server was not found, stop and tell
   the user to install the VS Code "Lua" extension (sumneko.lua) or a LuaLS release
   (version: `LUALS_VERSION` in `.github/workflows/lua-typecheck.yml`), or pass
   `--server <path>`. Do not download it yourself.

3. **Fix each problem at its cause.** Read the code around it first. The usual ones:

   | Code | Usual cause | Fix |
   |---|---|---|
   | `lowercase-global` | missing `local` | add `local`; only a genuinely shared global goes in `diagnostics.globals` in `.luarc.json` |
   | `undefined-field` / `inject-field` | a field no `@class` declares | add `--- @field name type` to the class; for `panel.data`, a small `---@class` and a typed local |
   | `need-check-nil` | a value that can be nil | guard it; if it truly cannot be nil here, `---@cast x -nil` with a comment saying why |
   | `param-type-mismatch` / `assign-type-mismatch` | wrong or unnarrowed type | fix the value, type the parameter, or `---@cast` in an event handler |
   | `undefined-global` | typo, or a global from a file not loaded first | fix the name; check the defining file exists |
   | a finding that comes and goes between runs | untyped symbol | annotate it (`---@param`, `---@type`) |

   Prefer annotations and real fixes over suppression. Change behaviour only to fix a real
   bug the checker found (a nil that can arrive, a misspelt field), and say so in your
   report. **Never** add a file-wide `---@diagnostic disable`, and never edit `.luarc.json`
   to make a finding go away. Where a line is right and cannot be expressed to the checker,
   suppress that one line with a reason:

   ```lua
   --<why this is correct>
   ---@diagnostic disable-next-line: <code>
   ```

   Keep every file ASCII-only, comments and annotations included.

4. **Re-run step 2 on the same files until it reports zero.** Also `luac -p` any file you
   edited if `../dependencies/lua/bin/luac.exe` exists.

5. **Before a pull request, offer an `all` run** if the change renamed or retyped anything
   other files use (a class, a field, a function signature, a `tableName`): the
   changed-files check cannot see a file you did not touch breaking. CI runs it anyway.

## Report

End with: the files checked and the final result; each fix in one line (file:line, what
and why), with real bugs found called out separately; every suppression with its reason;
any file the generators touched; and anything left unresolved, with what was tried.
