# Driving DMHub via MCP to test monster abilities — field notes

Captured 2026-07-01 while testing all Goblin monsters end-to-end over the MCP bridge.
These notes supplement `SKILL.md` with what actually works, the gotchas, and a reusable
harness pattern. Read this before writing a new ability-test session.

## TL;DR — what works and what doesn't

| Ability class | Auto-resolves headlessly? | How to test |
|---|---|---|
| Plain signature strike / area / maneuver (non-minion) | **Yes** | `ability:Cast` + aicontrol pin (below). Fully reliable. |
| Ability with a `hasCustomTrigger` edge `ModifyPowerRollBehavior` (e.g. Bow's "Steady Aim", Assassin Sword Stab's edge-damage) | **No** | Dialog holds for the custom-trigger edge; it never auto-rolls/accepts. Click **Roll Dice** then **Accept Result** with `mouse_click`, or read the tier table off a screenshot. |
| Minion "per-minion" squad strike (Runner Club Charge, Sniper Bow, Spinecleaver Axe) | **No** | Squad path doesn't auto-roll. Manual **Roll Dice**, or read the action log after the fact. |
| Effects with a target-choice prompt (ally free strike, forced-move direction) | **Partial** | The prompt auto-*skips* when no valid target exists; with a valid target it may wait on "choose". |
| Villain actions, summons, triggered reactions | Untested headlessly | Need real turn context; drive via the Monster AI turn loop or manual UI. |

The single biggest reliability win is the **aicontrol heartbeat** (below). The single
biggest trap is **orphaned embedded roll dialogs** blocking the whole queue.

> **Input is virtual by default (bridge build 9+).** `mouse_click` / `mouse_drag` /
> `key_press` / `type_text` no longer move the real cursor or steal window focus --
> input is synthesized inside DMHub, so the user can keep working while a test session
> drives the app. Nothing about the calls below changes. Two things worth knowing:
> `ui_click(text="Roll Dice")` is more robust than a screenshot-derived coordinate, and
> a virtual hover only lasts while the ~15s lease is held (screenshot promptly, or
> `virtual_input("pin")` for a long unattended run -- then `virtual_input("release")`).
> Pass `transport="os"` for the old OS-level behaviour.

## The reusable harness (installed as `_G.TA`)

Install once per session (survives `reload_lua` because it lives in the Lua global env,
not a mod). Key pieces:

### Setup
```lua
dmhub.initiativeQueue = InitiativeQueue.Create()
dmhub.initiativeQueue.gameMode = "combat"
dmhub:UploadInitiativeQueue()
CharacterResource.SetMalice(50, "test")
```

### Spawn + add to initiative
```lua
local tok = game.SpawnTokenFromBestiaryLocally(bestiaryId,
    core.Loc{x=x, y=y, floorIndex=game.currentFloorIndex}, {fitLocation=true})
tok:UploadToken("test spawn")
-- after spawning all:
game.UpdateCharacterTokens()
-- add each to the queue so liveness/turn checks behave:
local iid = InitiativeQueue.GetInitiativeId(tok)
q:SetInitiative(iid, someValue, 0)
dmhub:UploadInitiativeQueue()
```

### Deterministic tier — two mechanisms, prefer forcedroll
- **`options.symbols.forcedroll = N`** on `ability:Cast(caster, targets, options)`.
  The roll behavior does `regex.ReplaceAll(roll, "\\d+d\\d+", tostring(N))`, so the roll
  becomes deterministic. Pick N so `N + rollBonus` lands in the tier band you want and is
  **< 19** (>=19 can crit-promote on 4-tier tables). Helper:
  `tier1 -> 2`, `tier2 -> 14 - bonus`, `tier3 -> 18 - bonus` (bonus = the ability's +stat).
- **`setting "test:aiholdroll"` + `rollProperties.overrideTier`** (the SKILL.md path): pause
  after roll-complete via a chat-watcher, set `overrideTier`, release. Works but is more
  moving parts than forcedroll. Only needed when you can't influence the roll string.

### aicontrol heartbeat — REQUIRED for auto-resolution
`creature._tmp_aicontrol > 0` is what makes the roll dialog auto-roll and auto-accept
(see `Draw Steel UI/DSRollDialog.lua:2749` autoroll, `:2824` amendable auto-proceed).
**Setting it once does not stick** — a property `Invalidate()` during the cast resets it to
its type default (0). Pin it with a background coroutine:
```lua
dmhub.Coroutine(function()
    while pinning do
        for _, cid in ipairs(pinTokens) do
            local t = dmhub.GetTokenById(cid)
            if t and t.valid then t.properties._tmp_aicontrol = 5 end
        end
        coroutine.yield(0.1)
    end
end)
```
Register every spawned caster's charid in `pinTokens`. With this, plain strikes AND
amendable-but-non-custom-trigger rolls (e.g. Eye of Surlach) auto-Accept.

### Observation
Snapshot pre/post per target: `properties:CurrentHitpoints()`, condition names via
`ActiveOngoingEffects(false)` + `inflictedConditions`, and `loc.x/loc.y` for forced
movement. The **chat rollMessage** (`m.properties.tiers`, `.multitargets`, `.overrideTier`)
is the authoritative record and the **left-hand Action Log** shows the resolved outcome
text ("4 damage; push 3") even when your snapshot missed it.

### Cleanup — mandatory, and dismiss dialogs FIRST
```lua
TA.DismissEmbedded()          -- cancel gamehud.rollDialog AND the embedded sidebar dialog
game.DeleteCharacters(charids) -- canonical purge; async ~1s
dmhub.SetSettingValue("test:aiholdroll", false)
dmhub.SetSettingValue("autorollall", false)
```
`game.UnsummonTokens` silently no-ops on locally-spawned tokens — always use
`game.DeleteCharacters`. `tok.name` is nil on local spawns; filter orphans by
`monster_type`.

## Gotchas learned the hard way

1. **Orphaned embedded roll dialogs block everything.** When a cast is abandoned (times
   out, crashes, or you delete its token mid-roll), the ability-sidebar's *embedded* roll
   dialog stays `IsShown()` and the next cast's `ExecuteInvoke` wait-loop
   (`AbilityInvokeAbility.lua:460`) blocks forever behind it. `gamehud.rollDialog.data.Cancel()`
   does NOT clear it (that's the standalone dialog, not the embedded one). Use:
   ```lua
   local d = CharacterPanel.FindEmbeddedRollDialog(); if d and d.data and d.data.Cancel then d.data.Cancel() end
   CharacterPanel.HideAbility(nil); CharacterPanel.UnlockDisplayAbility()
   ```
   Call this before every cast and in cleanup.

2. **Never delete a target mid-cast.** `CalculateMultitargetsFromRollProperties`
   (`MCDMAbilityRollBehavior.lua:280`) resolves `dmhub.GetCharacterById(tokenid)`; a deleted
   token yields a nil `.token`. Two call sites dereferenced `.token` without a guard and
   crashed the whole cast (0 damage). Fixed defensively this session (see below), but the
   harness rule stands: let a cast fully finish before cleanup.

3. **Wrapping `ability:Cast` in a child `dmhub.Coroutine` regressed everything to 0 damage.**
   Cast on the runner coroutine directly. Don't nest.

4. **`_tmp_aicontrol` resets to 0 during the cast** (see heartbeat above). A one-shot
   assignment is not enough.

5. **Deterministic silent path vs amendable path.** `forcedroll` makes simple abilities take
   the `skipDeterministic` silent fast-path (no dialog at all) — that's why plain strikes
   "just worked". Abilities with a custom-trigger edge modifier force the amendable dialog
   regardless and don't silent-resolve.

6. **`GameHud.instance` is transiently `false` right after `reload_lua`** while the HUD
   re-inits. Wait ~3s after a reload before casting, or you'll hit the fallback path.

7. **`reload_lua` DOES apply on-disk `.lua` edits.** `lua_status` lists only mods changed
   *since the last reload*; your just-reloaded mods correctly drop off the list.

8. **Zombies (Zombie monster) have corruption/damage reduction** — a "tier 2 = 4" corruption
   ability landed 3 on a Zombie. Pick clean-resistance targets (Worg) unless testing DR, and
   check `compendium/bestiary/<target>.yaml` `resistances:` when a number is off by 1.

## Bugs found & fixed this session (surfaced by MCP testing)

- `MCDMCreature.lua` ~5211: a stray `print("Info::", json(info))` on **every** damage event
  spammed "Could not serialize user data value: LuaCharacterToken" errors. Removed.
- `MCDMAbilityRollBehavior.lua` 378 & 1619: `.token.charid` on a multitarget entry with a
  nil token crashed the cast. Added nil guards (matches the existing `targetToken ~= nil`
  guard pattern). This is a real player-facing risk when a target is removed mid-cast.
- `AbilitySidebar.lua` 1608: `dialog = GameHud.instance.rollDialog` fallback dereferenced the
  `GameHud.instance = false` default. Guarded with `elseif GameHud.instance then` + a
  `gamehud.rollDialog` fallback so headless/off-turn casts don't crash the roll.

## Additional notes (2026-07-01, Beastheart level-2 testing)

- **`ability:Cast` targets must be `{token = tok}` wrappers**, not raw tokens.
  Passing raw tokens crashes in `AbilityDamage.lua:118` (`attempt to index a nil
  value (field 'token')`) after the roll resolves. Correct call:
  `ability:Cast(casterToken, {{token = targetToken}}, {symbols = {}})`.
- **Forced-movement destination prompts (push/pull/slide) auto-resolve via
  `_tmp_aipromptCallback`** -- the same hook the Monster AI turn loop installs
  (`MonsterAI.lua:118-153`, handlers in `MonsterAIPrompts.lua`). The invoke gate is
  `AbilityInvokeAbility.lua` ExecuteInvoke: when `_tmp_aicontrol > 0` AND
  `_tmp_aipromptCallback` is set, prompt-targeted invokes call the callback instead
  of showing UI. Callback contract: receives
  `(invokerToken, casterToken, abilityClone, symbols, options)`; to resolve, merge
  `{targets = {{loc = someLoc}}}` (or `{{token = someToken}}`) into `options` and
  return `"inherit"`; return `"prompt"` to fall back to the manual picker.
  `invokerToken` = the aicontrolled ability caster; `casterToken` = the creature
  being moved (ring/candidate origin).
  - Install the callback on the CASTER alongside the aicontrol pin. See the
    "PR harness" pattern below; the Monster AI module is often NOT loaded in a
    game, so don't depend on `MonsterAI.prompts` (probe with
    `rawget(_G, "MonsterAI")`).
  - Engine support added 2026-07-01: ExecuteInvoke now direct-casts when the
    callback resolved targeting (`aiResolvedTargeting`) instead of routing
    through the action bar (which dropped loc targets at the `beginCasting`
    TODO and stalled waiting for clicks). Also: `beginCasting` now transfers
    packaged loc targets into `m_positionTargetsChosen`, and the action bar's
    `invokeAbility` handler honors `instantCast` by setting `castImmediately`.
  - Reusable harness: **`prompt_resolver.lua` in this skill directory.** Paste
    its contents into `execute_lua` once per session (after the aicontrol pin),
    then `_G.PR.Install(casterCharid)`. Auto-resolves Push!/Pull!/Slide! to the
    farthest valid straight-line square; delegates to `MonsterAI.prompts`
    handlers when that module is loaded; parks anything else in `PR.pending`
    for the MCP session to inspect and answer with
    `PR.Resolve{targets={{loc=...}}}` (60s timeout -> manual UI fallback).
    Re-run `PR.Install` after a `reload_lua`.
  - Verified end-to-end: This One's Yours (push 3, stability 1) resolved
    headlessly -- target moved 2 squares and took 2 damage, no mouse input.
- **Activating a triggered ability headlessly:** when a trigger fires, an entry
  appears in `token.properties:GetAvailableTriggers()` (and the trigger panel UI).
  To activate from MCP, set `triggered = true` on the entry inside
  `ModifyProperties` -- the sustain coroutine in `TriggeredAbility.lua` picks it
  up and runs the cast (set it to a mode NUMBER for a non-default mode; true =
  mode 1). To dismiss, set `dismissed = true`. Watch for expiry: triggers age
  out ~6s after the owner's turn-refresh id changes.
  ```lua
  local trg = bh.properties:GetAvailableTriggers() or {}
  for guid,v in pairs(trg) do
      bh:ModifyProperties{ description = "Activate trigger", undoable = false,
          execute = function() bh.properties:GetAvailableTriggers()[guid].triggered = true end }
  end
  ```
- **`finishmove` triggers with `Path` symbols** (Catcher / This One's Yours
  pattern) verified working headlessly end-to-end: enemy push past the owner ->
  trigger appears (notification sound + availableTriggers) -> activation runs
  RevertLoc + redirect push + per-square damage, with the push auto-resolved by
  the prompt resolver.
- **Clicking map squares headlessly (fallback when a UI truly needs a click):**
  center the camera with `dmhub.FocusToken(charid)`, then map world coords to
  pixels via `dmhub.cameraBounds`:
  `px = (wx - b.x1)/(b.x2 - b.x1) * 1920; py = 1080 - (wy - b.y1)/(b.y2 - b.y1) * 1080`
  (square (x,y) center = world (x+0.5, y+0.5)). Verified accurate.
- **`usageLimitOptions` charges are not consumed by a direct headless `ability:Cast`** --
  payment goes through the action bar's cost-proposal flow. Verify limits in real UI.
- **Beastheart companion testing:** `CallCompanion` in `DSBeastheart.lua` is file-local.
  To spawn a companion headlessly, replicate it: `GetCompanionType()` ->
  `game.SpawnTokenFromBestiaryLocally` -> set `summonerid`, `companionBestiaryId`,
  `initiativeGrouping`, `partyid` -> `UploadToken` -> set `properties.companionid`
  on the beastheart inside `ModifyProperties`.

## Suggested future MCP-bridge / harness improvements

- A Lua helper `MonsterAI` one-shot that sets up a proper turn context (aicontrol +
  prompt callbacks) so minion squad strikes and prompt-effects auto-resolve — the current
  `MonsterAI:ExecuteAbility` still routes through the sidebar and hit the same gates.
- An engine hook to force a roll dialog to auto-roll+accept regardless of caster identity
  (a superset of `autorollall` that also covers the amendable proceed and minion path).
- An MCP tool to dismiss any open roll dialog / ability sidebar (so a stuck test doesn't
  require a screenshot + mouse click to recover).
