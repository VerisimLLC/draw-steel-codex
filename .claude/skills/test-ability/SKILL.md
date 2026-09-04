---
name: test-ability
description: |
  Test a Draw Steel monster ability end-to-end against its rules text by
  spawning tokens via the DMHub MCP server and observing the result. Use when
  the user types "/test-ability ...", or asks to "test ability X", "verify
  monster Y's ability", "check if ability Z works", or similar.
---

# /test-ability

Verify that a Draw Steel monster ability behaves the way its **rules text** says it should, by running real Lua inside a connected DMHub instance and reading the resulting game state. The agent driving this skill is an exhaustive, skeptical tester. It does not write fixes -- it reports findings.

## Core mission

Given a monster name and an ability name (e.g. "Goblin Assassin", "Shadow Chains"), determine whether the ability is fully and correctly automated. Every clause in the rules text is a test case. If a clause cannot be exercised automatically -- because the YAML doesn't implement it, because the engine asks the player to make a choice manually, because a side-effect doesn't fire -- that is a **failure**, not a "limitation of the medium."

**100% automation is the goal.** Never excuse an unimplemented clause with "in a VTT the GM/player would just do that." If the engine doesn't do it without manual input, say so plainly under "Automation gaps" in the report.

## Workflow

### 1. Verify the MCP connection

Call `mcp__dmhub__check_connection` first. If DMHub isn't running, stop and report that -- do not try to start it.

### 2. Gather rules text from BOTH sources

You must cross-check two independent sources:

- **`monster-reference.md`** at the project root. Use Grep to find the `## <Monster Name>` heading, then Read the surrounding section to extract the full ability block: tier bullets, **Effect:**/**Trigger:**/**N+ Malice:** lines, and any Trait that modifies the ability.
- **`compendium/bestiary/<monster-slug>.yaml`** -- find with Glob. Read the `info.properties.innateActivatedAbilities[]` entry whose `name` matches.

Compare the two. **Any divergence between rules text and YAML description is its own failure** -- record it under "Rules text divergence" in the report.

### 3. Plan test cases from the rules text

Enumerate, before running anything:

- One case per **power roll tier** (Tier 1, Tier 2, Tier 3). If the ability isn't a power roll, plan its actual resolution path.
- One case per **conditional clause** (e.g. `M<0 bleeding (save ends)` -> two cases: target with Might < 0 AND with Might >= 0).
- One case per **size-conditional damage** (e.g. "double damage vs size 1").
- One case per **effect/trigger/malice clause** (forced movement, push distance, condition application, ongoing damage, resource grant).
- One case for **adjacency / range / target count** edge if the ability text gates on it.
- One case for the **trait or villain action** if it modifies this ability.

For multi-target abilities ("Three creatures"), pack diverse stat-threshold targets into one cast and observe per-target -- this collapses N tier tests * M threshold tests into ~3 casts. Worked example: Shadow Chains (A<X restrained) tested against Mummy (A=-1), Harpy (A=0), Hobgoblin Redglare (A=2) -- 9 observations from 3 casts.

### 4. Pick targets correctly

- **Never use minions** as targets (squad/mass-damage rules distort observed damage). Filter `m.properties:try_get("minion", false)` when scanning the bestiary.
- For stat-threshold conditions (`M<0`, `A<2`, etc.), pick targets whose **published score** satisfies and doesn't satisfy. Do NOT mutate `attributes.mgt.baseValue` etc. -- the engine reads via `AttributeForPotencyResistance("mgt"|"agl"|"rea"|"inu"|"prs")`, not from baseValue, so mutation is a dead end.
- To enumerate non-minion candidates with a desired stat:
  ```lua
  for id, m in pairs(assets.monsters) do
      if not m.hidden then
          local p = m.properties
          if p and not p:try_get("minion", false) then
              local mgt = p:AttributeForPotencyResistance("mgt")  -- or agl/rea/inu/prs
              -- collect by stat value
          end
      end
  end
  ```

### 5. Execute test cases via the deterministic test-hold pattern

The harness uses two engine primitives:

- **`setting "test:aiholdroll"`** (transient bool) -- when true, ability resolution pauses between the dice settling and the per-target tier read. Engine-side hook lives in `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua` immediately after the wait-for-roll-complete loop. Production play is unaffected (transient + default false).
- **`m.properties.overrideTier`** on the chat rollMessage -- read by the per-target damage code at `MCDMAbilityRollBehavior.lua:1509` and again in `CalculateMultitargetsFromRollProperties`. Setting this forces the resolved tier deterministically.

Per-test flow (run in `dmhub.Coroutine` so you can `coroutine.yield`):

```lua
-- One-time prelude (top of script):
dmhub.initiativeQueue = InitiativeQueue.Create()
dmhub.initiativeQueue.gameMode = "combat"
dmhub:UploadInitiativeQueue()
CharacterResource.SetMalice(50, "test")  -- enough for many casts

-- Per case:
local floor = game.currentFloorIndex
local function spawn(id, x, y)
    return game.SpawnTokenFromBestiaryLocally(id,
        core.Loc{x=x, y=y, floorIndex=floor}, {fitLocation=true})
end

local caster = spawn(casterBestiaryId, 0, 0)
local targets = { spawn(targetBestiaryId, 3, 0), ... }
caster:UploadToken("test")
for _, t in ipairs(targets) do t:UploadToken("test") end
game.UpdateCharacterTokens()
caster.properties._tmp_aicontrol = 1  -- bypass the roll dialog

-- Snapshot pre-state per target
local pre = {}
for i, t in ipairs(targets) do
    pre[i] = {
        hp = t.properties:CurrentHitpoints(),
        restrained = t.properties:HasNamedCondition("restrained"),
    }
end
local maliceBefore = CharacterResource.GetMalice()

-- Find the ability
local ability
for _, a in ipairs(caster.properties:GetActivatedAbilities()) do
    if a.name == ABILITY_NAME then ability = a; break end
end

-- Capture existing chat keys so the watcher only matches the new rollMessage
local seenKeys = {}
for _, m in ipairs(chat.messages) do seenKeys[m.key] = true end

-- ENGAGE THE HOLD
dmhub.SetSettingValue("test:aiholdroll", true)

-- Watcher coroutine: detect new rollMessage, set overrideTier, RELEASE the hold
dmhub.Coroutine(function()
    for i = 1, 600 do
        coroutine.yield(0.02)
        for j = #chat.messages, 1, -1 do
            local m = chat.messages[j]
            if not seenKeys[m.key] then
                local rp = m.properties
                if rp then
                    local ok, tiers = pcall(function() return rp:try_get("tiers") end)
                    -- Match a string unique to THIS ability's tier text (e.g. "restrained",
                    -- "bleeding", "weakened" -- something you know is in the tier strings)
                    if ok and tiers and tiers[1] and string.find(tiers[1], TIER_KEYWORD) then
                        rp.overrideTier = forceTier
                        m:UploadProperties(rp)
                        dmhub.SetSettingValue("test:aiholdroll", false)
                        return
                    end
                end
            end
        end
    end
    dmhub.SetSettingValue("test:aiholdroll", false)  -- failsafe
end)

-- Cast
local tlist = {}
for _, t in ipairs(targets) do tlist[#tlist+1] = {token = t} end
ability:Cast(caster, tlist, {})

-- Wait for completion -- detect via "malice paid AND a non-immune target took damage"
for w = 1, 400 do
    coroutine.yield(0.05)
    local maliceNow = CharacterResource.GetMalice()
    local probeTarget = targets[2]  -- one you know isn't immune to the damage type
    if (maliceBefore - maliceNow) >= ABILITY_COST and
       probeTarget.properties:CurrentHitpoints() < pre[2].hp then
        for _ = 1, 6 do coroutine.yield(0.05) end  -- let restrained settle
        break
    end
end

-- Observe per target
-- ... (HP delta, condition presence, location for forced movement)

-- CLEANUP -- canonical
local ids = {caster.charid}
for _, t in ipairs(targets) do ids[#ids+1] = t.charid end
game.DeleteCharacters(ids)

-- Failsafe in case the watcher never fired
dmhub.SetSettingValue("test:aiholdroll", false)
```

### 6. Cleanup is mandatory and uses `game.DeleteCharacters`

**Use `game.DeleteCharacters({charid, ...})`** -- this is the canonical removal API. Async (~1s). Fully purges tokens (gone from `allTokens`, gone from the map, `GetTokenById` returns nil). Wrap each test case in `pcall` so a runtime error still hits the cleanup path.

**Do NOT use:**
- `game.UnsummonTokens({...})` -- silently no-ops on `SpawnTokenFromBestiaryLocally` tokens. After many runs the board ends up covered in orphans.
- `tok.despawned = true` -- only hides visually; leaves stale entries that accumulate across runs.

If you spawn tokens and a test crashes before cleanup, run a final emergency-cleanup pass at the end of the report:

```lua
local testNames = { ["<MonsterA>"]=true, ["<MonsterB>"]=true, ... }
local ids = {}
for _, t in ipairs(dmhub.allTokens) do
    local mt = t.properties and t.properties:try_get("monster_type", "")
    if testNames[mt] then ids[#ids+1] = t.charid end
end
if #ids > 0 then game.DeleteCharacters(ids) end
```

Note: `tok.name` is `nil` on locally-spawned tokens; filter on `monster_type` instead.

### 7. MCP-execution gotchas

- `mcp__dmhub__execute_lua` runs the script in a **fresh non-coroutine environment**. `coroutine.yield(...)` errors at top level. Wrap your test body in `dmhub.Coroutine(function() ... end)` and stash results in a global like `_G._TA_LOG`. Poll from a follow-up MCP call (use `rawget(_G, "_TA_LOG")` because strict mode errors on uninitialized globals).
- State (combat, malice) can reset between MCP calls. Re-init both at the top of any script that needs them.
- `chat.messages` is a bounded buffer; index positions shift but `m.key` is stable. Dedupe new messages by tracking keys, not indices.

### 8. Report (verbose inline)

Final message MUST contain these sections, in this order:

1. **Subject** -- `<Monster> -- <Ability>` and where its rules text was sourced.
2. **Rules text** -- quote the actual clauses from monster-reference.md.
3. **Rules text divergence** -- monster-reference vs YAML, line-by-line. "(none)" if clean.
4. **Test plan** -- numbered list of cases, with the clause each case targets.
5. **Per-test results** -- for each case:
   - Setup: species, sizes, attributes, position
   - Expected: what the rules text says should happen
   - Observed: what `print()` returned (damage, conds, movement, override-on-msg)
   - Verdict: PASS / FAIL / AUTOMATION GAP, with one-sentence justification
6. **Automation gaps** -- bullet list of clauses the engine did not resolve without manual input.
7. **Summary** -- `passes / fails / automation_gaps / total`, one-sentence overall verdict.

## Invariants

- **No code edits.** You diagnose, you do not fix. If you spot the YAML bug while testing, mention it under the relevant case but do not modify the file.
- **No skipped clauses.** Every clause in the rules text gets a case.
- **No assumed PASS.** A case is PASS only if the observed state matches the expected state for the *specific* clause being tested. "Some damage happened" is not a pass for "5 damage; M<0 bleeding (save ends)".
- **Be skeptical of zero-damage results.** If `damage == 0` and the rules say damage should occur, investigate. Could be legit (target has Damage Reduction for that type -- check `compendium/bestiary/<target>.yaml` for `resistances:`), or could be that the ability ran a different code path (missed cast, target untargetable, etc.). Use `mcp__dmhub__get_console_log level="error"`.
- **ASCII only** in any Lua you author -- the DMHub Lua runtime requires it.

## Inspection helpers

- `targetTok.properties:CurrentHitpoints()` -- stamina remaining
- `targetTok.properties:HasNamedCondition("bleeding"|"restrained"|...)` -- case-insensitive condition check
- `targetTok.properties:ActiveOngoingEffects(false)` -- list of ongoing effect instances
- `targetTok.loc.x`, `targetTok.loc.y` -- position (for forced movement)
- `CharacterResource.GetMalice()` / `CharacterResource.SetMalice(N, label)`
- `mcp__dmhub__get_console_log` with `level="error"` -- catch coroutine errors

## When NOT to use this skill

- The user wants to test a **player character** ability -- this skill is monster-focused. Heroes have a different invocation path; offer to extend the skill if asked.
- The user wants to **fix** an ability rather than test it. Run a test first to confirm the bug, then switch to a fix workflow once the failure is characterised.
- DMHub isn't running. Detect via `mcp__dmhub__check_connection` and stop with a clear message.
