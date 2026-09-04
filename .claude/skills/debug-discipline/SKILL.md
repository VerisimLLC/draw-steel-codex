---
name: debug-discipline
description: >-
  Evidence-before-edit debugging procedure for the draw-steel-codex Lua mod
  AND its C# engine repo (dmhubclient). Use this EVERY time you are diagnosing
  a malfunction -- a bug, error, crash, console error, build/compiler error,
  UI glitch, wrong value, panel not updating, audible/visual defect, or any
  "why is this happening" / "work out what's going on" / "investigate"
  request -- before proposing or making any code change. Also use it when a
  fix you just made did not work. Trigger even on casually-described symptoms
  ("the panel is blank", "it errors when I click") and even if the cause seems
  obvious. Do NOT use for pure understand/explain questions, design work,
  diff review, copy edits, or feature additions where nothing is
  malfunctioning.
---

# Debug Discipline

You are debugging a live Lua application (DMHub engine + draw-steel-codex mod).
The single most expensive failure mode here is editing code based on the first
plausible hypothesis. A plausible-but-wrong fix costs a review round, pollutes
the diff, and often masks the real bug. Evidence is cheap on this stack: the
app hot-reloads Lua and (when connected) exposes a live bridge into it. Use
that before you touch a file.

## The procedure

Work through these stages in order. Do not skip to stage 4 because the cause
"seems obvious" -- pattern-matching a symptom to a known failure is exactly how
wrong fixes happen. The symptom may have a different cause this time.

### 1. Observe the actual failure

Reproduce or directly observe the failure before reasoning about it.

- If a connected DMHub instance is available (`mcp__dmhub__check_connection`),
  reproduce there: run the triggering action, then read
  `mcp__dmhub__get_console_log` for the real error text and stack.
- If someone reported the symptom, get the exact error message or a
  screenshot-level description. "It errors" is not evidence; the line number
  in the console is.
- Note what you can NOT yet explain. Write it down in your reasoning.

### 2. Read the code that is actually executing

- Read the full function/panel involved, not just the line in the stack trace.
  Event handlers, `refreshGame`, `think`, and `monitorGame` interactions often
  mean the bug is in a different callback than the one that errored.
- Check git: `git log -p --follow -- <file>` on the suspect region. If this
  code worked recently, the diff since then is your best evidence.
- Remember `Definitions/` files are engine API stubs -- they tell you
  signatures, never behavior. Do not conclude engine behavior from a stub body.
- Engine-side Lua lives in the engine repo under `Assets\CoreAssets\Lua\*.txt`
  -- greps for `*.lua` MISS these files. If a symbol seems to not exist
  anywhere, search the `.txt` files too.

### 3. Enumerate hypotheses, then discriminate

State at least TWO distinct hypotheses for the cause -- forcing a second
hypothesis is what breaks the jump-to-conclusion reflex. For each, name the
observation that would distinguish it. Then run the CHEAPEST discriminating
test first. On this stack that is almost always live inspection, not code
reading:

- `mcp__dmhub__execute_lua` with `print()` to inspect real values: table
  contents, `token.properties` fields, `dmhub.GetTable(...)` entries, what a
  formula evaluates to. Iterate freely -- Lua errors come back to you.
- Drive real UI event paths with the `gui.GetSheetById` rig from execute_lua
  (find a panel by id, `FireEvent` on it) rather than guessing what a click
  does.
- For focus/popup/input bugs that `FireEvent` cannot reproduce, real OS clicks
  are needed (SendInput). Ask a human to click if there is no programmatic
  path -- a 10-second human click beats an hour of simulation guesswork.
- `mcp__dmhub__reload_lua` + `get_console_log` verifies whether current disk
  state even loads cleanly -- rule that out before debugging logic.

Only when one hypothesis survives the evidence do you move on.

### 4. Fix minimally, verify live

- Make the smallest change that addresses the EVIDENCED cause. Resist bundling
  cleanups into a debug fix.
- Hot-reload and re-run the exact reproduction from stage 1. "It should work
  now" is not verification; the console log after the repro is.
- If the fix does not work: STOP. Do not stack a second patch on top. Revert
  to stage 3 -- your surviving hypothesis just got falsified, which is new
  evidence.

### 5. Report before expanding scope

If you were asked to explain a problem rather than fix it, the deliverable is
the diagnosis: report the evidenced cause and the proposed fix, then confirm
before implementing. Never silently widen a debugging session into
refactoring.

## Evidence traps specific to this codebase

These commonly produce MISLEADING evidence -- check them before trusting an
observation:

- **Reading an unset global or `_tmp_` field ERRORS** (it does not return
  nil). An "attempt to index nil" may just mean uninitialized state, not a
  logic bug. Safe probes: `rawget(_G, "name")` for globals,
  `obj:try_get("_tmp_foo")` for transient fields.
- **`cond(a, b, c)` evaluates ALL THREE arguments.** An error pointing inside
  the branch you believe is "not taken" is real -- `cond` is a function, not a
  ternary, so both branches always execute.
- **Stale closures after hot reload.** Scheduled callbacks from a previous
  load keep running unless guarded by `mod.unloaded`. Weird "double" behavior
  after several reloads often disappears on app restart -- verify a bug exists
  on a FRESH load before chasing it.
- **Soft-deleted table entries.** Iterating a compendium table with `pairs`
  surfaces hidden/deleted entries; production code uses `unhidden_pairs`. If
  your probe shows an entry the UI does not, that is why.
- **"Panel did not update" is not "panel is broken".** Check whether the
  panel's `monitorGame` path actually matches the document being changed, and
  whether the data change went through `ModifyProperties`/`BeginChange` (raw
  mutations do not sync or fire refresh).

## When the cause is found

Once the cause is evidenced and the fix is specified precisely (file, anchor,
exact change), the edit itself is mechanical. Keep the fix minimal and scoped
to the evidenced cause, and re-verify live (stage 4) before considering it
done.
