# Draw Steel Systems Reference

Deep-dive reference for four systems discovered during Arrestor Cycle (Skip Turn) implementation.
For UI/styling patterns see [UI_BEST_PRACTICES.md](UI_BEST_PRACTICES.md).

---

## 1. Initiative Queue

### Key Files

| File | Purpose |
|------|---------|
| `DMHub Game Rules/InitiativeQueue.lua` | Core queue type and methods |
| `Draw Steel Core Rules/MCDMCreature.lua` | Turn-skip tracking, RefreshInitiativeInfo, RefreshSquadInfo |
| `Draw Steel Core Rules/MCDMInitiativeBar.lua` | NextInitiative, EndTurn suppression for skipped creatures |
| `DMHub Game Rules/AbilityInitiative.lua` | `skip_turn` mode implementation |

### dmhub.initiativeQueue Fields

| Field | Type | Description |
|-------|------|-------------|
| `guid` | string | Unique ID for this combat session -- changes each time combat starts |
| `round` | number | Current round (1-indexed) |
| `hidden` | boolean | If true, initiative is not visible to players |
| `entries` | table | Map of `initiativeid -> InitiativeQueueEntry` |

### InitiativeQueueEntry Fields

| Field | Type | Description |
|-------|------|-------------|
| `initiativeid` | string | Either `token.id` (heroes) or `"MONSTER-{type}"` (grouped monsters) |
| `initiative` | number | Initiative roll result |
| `round` | number | Round in which this entry next acts (incremented by NextTurn) |
| `turnsTaken` | number | How many times this entry has acted in total |
| `endTurnTimestamp` | number or nil | Server timestamp when this entry last ended its turn |

### Key Methods

```lua
-- GetRoundId: unique string for the current round of this combat session
-- Returns "{guid}-{round}", e.g. "abc123-2"
-- Returns nil when q.hidden == true -- always use 'or ""' as fallback
local roundId = q:GetRoundId() or ""

-- GetInitiativeId: static -- returns the initiative group ID for a token
-- Heroes: returns token.id
-- Grouped monsters: returns "MONSTER-{sanitized_type}"
local initiativeid = InitiativeQueue.GetInitiativeId(token)

-- GetFirstInitiativeEntry: returns the entry whose turn it currently is
-- Sort key: -entry.round * 1000 + initiative + dexterity * 0.01
local entry = q:GetFirstInitiativeEntry()

-- CurrentInitiativeId: convenience wrapper for GetFirstInitiativeEntry
local id = q:CurrentInitiativeId()

-- NextTurn: advance past the current entry
-- Increments entry.round; if no other entries are eligible this round, increments q.round
q:NextTurn(initiativeid)

-- SetInitiative: create or update an entry
q:SetInitiative(initiativeid, initiativeValue, dexterityValue)

-- GetTokensForInitiativeId: returns all tokens in an entry
local tokens = InitiativeQueue.GetTokensForInitiativeId(initiativeid)
```

### GetRoundId -- the Critical Pattern

`GetRoundId()` returns `string.format('%s-%d', self.guid, self.round)` -- unique per combat
session because `guid` changes every time combat starts. This is the correct way to detect
whether a skip (or any round-dependent state) was recorded in the current combat vs a previous one.

**Never use `q.round` alone** -- it resets to 1 each new combat, causing cross-combat false positives.

```lua
-- Correct: combat-session-safe round ID
self.myRoundId = q:GetRoundId() or ""

-- Wrong: plain round integer resets to 1 every combat
self.myRound = q.round
```

The `or ""` fallback is required because `GetRoundId()` returns nil when `q.hidden == true`
(initiative is hidden). On both sides of a comparison this produces `"" ~= ""` = false, which
is the correct "skip is not active" result.

**Reference pattern:** `moveDistanceRoundId` in `DMHub Game Rules/AbilityInitiative.lua` uses
the same approach to track per-round movement exhaustion across combats.

### Turn-Skip Tracking on creature

These fields are set by `MarkTurnSkipped` and read by `IsTurnSkipped`:

```lua
creature.skipTurnInitiativeId  = ""  -- initiativeid at time of skip
creature.skipTurnRoundId       = ""  -- GetRoundId() at time of skip
creature.skipTurnTurnsTaken    = 0   -- entry.turnsTaken at time of skip
```

```lua
-- Mark a creature's turn as skipped for the current round/initiative slot
function creature:MarkTurnSkipped(initiativeid)
    local q = dmhub.initiativeQueue
    self.skipTurnInitiativeId = initiativeid or ""
    self.skipTurnRoundId = q:GetRoundId() or ""
    local entry = q.entries[initiativeid]
    self.skipTurnTurnsTaken = (entry ~= nil) and (entry.turnsTaken or 0) or 0
end

-- Returns true if the creature's turn is currently skipped
-- Three-way check: roundId matches, initiativeId matches, entry hasn't advanced
function creature:IsTurnSkipped(token)
    local q = dmhub.initiativeQueue
    if q == nil then return false end
    if self:try_get("skipTurnRoundId", "") ~= (q:GetRoundId() or "") then return false end
    local myInitiativeId = InitiativeQueue.GetInitiativeId(token)
    if self:try_get("skipTurnInitiativeId", "") ~= myInitiativeId then return false end
    local entry = q.entries[myInitiativeId]
    if entry ~= nil then
        if (entry.turnsTaken or 0) > self:try_get("skipTurnTurnsTaken", 0) then
            return false  -- Entry has since taken another turn; skip has expired
        end
    end
    return true
end
```

### _tmp_initiativeStatus Values

Set by `creature:RefreshInitiativeInfo(token)` in `MCDMCreature.lua`:

| Value | Meaning |
|-------|---------|
| `"Done"` | Turn ended (or skipped) |
| `"OurTurn"` | Currently active |
| `"NonCombatant"` | Not in the initiative queue |
| `"Active"` | In queue, turn not yet taken |
| `"ActiveAndReady"` | In queue, ready action available |

`IsTurnSkipped` is checked first in `RefreshInitiativeInfo` -- a skipped creature immediately
gets `"Done"` without any further checks.

### Minion Squad Info (_tmp_minionSquad)

Set by `creature:RefreshSquadInfo(token)` in `MCDMCreature.lua`:

| Field | Type | Description |
|-------|------|-------------|
| `liveMinions` | number | Count of non-dead minions |
| `activeMinions` | number | Count of minions whose turns are NOT skipped |
| `tokens` | CharacterToken[] | All minion tokens in the squad |
| `captain` | CharacterToken or nil | The non-minion controller |
| `name` | string | Squad display name |
| `updateid` | string | Last game update ID processed |

`activeMinions` is what drives `GetNumTargets()` for minion signature abilities -- it ensures
that when a minion's turn is skipped, that minion is excluded from the squad attack target count.

### NextInitiative and EndTurn Suppression

In `MCDMInitiativeBar.lua`, `NextInitiative` iterates all tokens in the current initiative
entry before advancing the queue. Skipped creatures get their `EndTurn` call suppressed:

```lua
for _, tok in ipairs(tokens) do
    if tok.properties:IsTurnSkipped(tok) then
        -- Suppress EndTurn: save-ends conditions and end-of-turn effects do not trigger
    else
        tok.properties:EndTurn(tok)
    end
end
```

This is critical: without suppression, a skipped creature would lose save-ends conditions
and trigger end-of-turn effects even though they never acted.

---

## 2. Triggered Abilities

### Key Files

| File | Purpose |
|------|---------|
| `DMHub Game Rules/TriggeredAbility.lua` | Core TriggeredAbility type |
| `DMHub Game Rules/ActivatedAbility.lua` | Parent type; Cast, GetTargets, etc. |
| `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua` | Roll dialog integration; EmbedDialogInAbility nil guard |

### TriggeredAbility vs ActivatedAbility

`TriggeredAbility` extends `ActivatedAbility`. Key differences:

| Aspect | ActivatedAbility | TriggeredAbility |
|--------|-----------------|-----------------|
| Activation | Player clicks the ability | Fires on a game event (trigger) |
| Cost | Paid explicitly | Paid automatically on fire |
| Chat log | Yes (by default) | No (`CountsAsRegularAbilityCast` = false) |
| Activation | Manual | Automatic or prompted |

### TriggeredAbility-Specific Fields

| Field | Type | Description |
|-------|------|-------------|
| `trigger` | string | Event ID (e.g. `"losehitpoints"`, `"attack"`, `"beginturn"`) |
| `triggerFilter` | string or nil | GoblinScript condition; must be truthy for trigger to fire |
| `mandatory` | boolean or string | `true` = auto-fire; `false` = prompt player; string = setting key |
| `despawnBehavior` | string | `"remove"` or `"corpse"` -- how to handle despawned targets |
| `characterConditionRequired` | string | Condition the subject must have |

### Execution Path

```
TriggeredAbility:Trigger()
  -> Evaluate triggerFilter (GoblinScript)
  -> Resolve target list (self, attacker, target, subject, aura, etc.)
  -> IsMandatory()?
       true  -> TriggerCo() wraps Cast() directly
       false -> DispatchAvailableTrigger() -> shows prompt UI
                -> On player activation: executeTrigger() -> TriggerCo() -> Cast()
                -> Prompt expires after 5 seconds or on turn change
```

`CountsAsRegularAbilityCast()` returns `false` for triggered abilities -- they bypass the
normal action economy chat logging.

### Roll Dialog Nil Guard (EmbedDialogInAbility)

When a power roll fires from a triggered ability, the character sidebar panel may not be
open. `CharacterPanel.EmbedDialogInAbility()` returns `nil` in that case.

**Pattern:** only overwrite `dialog` when the embedded dialog is non-nil. The fallback
`GameHud.instance.rollDialog` (the shared global roll dialog) is used otherwise.

```lua
-- In MCDMAbilityRollBehavior.lua, before ShowDialog:
local embeddedDialog = CharacterPanel.EmbedDialogInAbility()
if embeddedDialog ~= nil then
    dialog = embeddedDialog
    -- Give a few cycles for the embedded panel to initialise before ShowDialog
    for i=1,4 do
        coroutine.yield(0.01)
    end
end

-- 'dialog' is now either the embedded sidebar panel or GameHud.instance.rollDialog
dialog.data.ShowDialog{ ... }
```

**Do not** unconditionally write `dialog = CharacterPanel.EmbedDialogInAbility()` -- this
overwrites the valid fallback with nil and causes a nil-access crash on `dialog.data`.

---

## 3. Action Bar and Minion Squad Targeting

### Key Files

| File | Purpose |
|------|---------|
| `Draw Steel UI/DrawSteelActionBar.lua` | Action bar, target selection, targetPairs |
| `Draw Steel Core Rules/MCDMActivatedAbility.lua` | GetSquadTargetPermutations, GetNumTargets, PrepareTargets |

### GetSquadTargetPermutations

Recursively computes valid minion-to-target assignments for a squad signature ability:

```lua
GetSquadTargetPermutations(
    squad,                      -- CharacterToken[] -- squad members
    squadTargetsPerToken,       -- table[] -- per-minion reachable location sets
    targets,                    -- {token: CharacterToken}[] -- enemies to assign
    targetLocsOccupying,        -- table[] -- location sets per target
    output,                     -- CharacterToken[][] -- accumulates valid permutations
    outputTargetingCombinations,-- {a,b}[][] -- parallel array of ray pairs (optional)
    currentCombinationInternal  -- {a: Token, b: Token}[] -- recursion accumulator
)
```

Each entry in `outputTargetingCombinations` is an array of `{a: CharacterToken, b: CharacterToken}`
pairs, where `a` = the minion token and `b` = the target token. **These are token objects, not IDs.**

### targetPairs in the Action Bar

`DrawSteelActionBar` converts token-object pairs to ID pairs and stores them in GoblinScript symbols:

```lua
-- DrawSteelActionBar.lua (around line 4575)
local targetPairs = {}
for i, ray in ipairs(rays) do
    targetPairs[#targetPairs + 1] = { a = ray.a.id, b = ray.b.id }
end
g_currentSymbols.targetPairs = targetPairs
```

`g_currentSymbols.targetPairs` is then available to GoblinScript formulas and ability effect code
as `symbols.targetPairs`.

### GetNumTargets Override

For minion signature abilities, `GetNumTargets` returns `activeMinions` (not `liveMinions`):

```lua
-- MCDMActivatedAbility.lua
function ActivatedAbility:GetNumTargets(casterToken, symbols)
    local result = g_numTargetsFunction(self, casterToken, symbols)

    if casterToken ~= nil and casterToken.properties.minion
       and self.categorization == "Signature Ability"
       and result == 1
       and casterToken.properties:has_key("_tmp_minionSquad") then
        return casterToken.properties._tmp_minionSquad.activeMinions
            or casterToken.properties._tmp_minionSquad.liveMinions
    end

    return result
end
```

`activeMinions` excludes minions whose turns are skipped (see `RefreshSquadInfo` in Section 1).

### PrepareTargets -- Consolidating Multi-Minion Hits

When multiple minions target the same enemy, `PrepareTargets` collapses them into one entry
with an `addedStacks` count:

```lua
-- MCDMActivatedAbility.lua
function ActivatedAbility:PrepareTargets(casterToken, symbols, targets)
    if casterToken.properties.minion and self.categorization == "Signature Ability" then
        local result = {}
        for _, target in ipairs(targets) do
            local found = false
            for _, existing in ipairs(result) do
                if target.token ~= nil and existing.token ~= nil
                    and target.token.id == existing.token.id then
                    existing.addedStacks = (existing.addedStacks or 0) + 1
                    found = true
                    break
                end
            end
            if not found then
                result[#result + 1] = target
            end
        end
        return result
    end
    return targets
end
```

Effect code then loops `addedStacks` times to apply damage/effects per attacker.

### Minion Squad Attack -- End-to-End Flow

```
1. DrawSteelActionBar.CalculateSpellTargeting
      Detects: caster is a minion with squad signature ability
      Calls GetTargetingRays() -> GetSquadTargetPermutations()
      Returns {a: Token, b: Token}[] ray pairs

2. Action bar stores targetPairs
      targetPairs[i] = { a = ray.a.id, b = ray.b.id }
      g_currentSymbols.targetPairs = targetPairs

3. Player confirms targets -> ActivatedAbility:Cast()
      GetNumTargets() -> activeMinions count
      PrepareTargets() -> consolidate multi-minion hits with addedStacks
      GetTargetingRays() -> visual targeting rays drawn on map

4. Effect resolution (MCDMAbilityRollBehavior / ability behavior code)
      symbols.targetPairs -> which minion hit which target
      target.addedStacks -> apply effects N+1 times if multiple minions hit same enemy
```

### Known Bug: Extra Attackers Modifier (Escalated)

In `MCDMAbilityRollBehavior.lua` around line 912, `numAttackers` is computed by comparing
`pair.b` (from `targetPairs`, which stores `ray.b.id`) against `target.token.charid`.
If `token.id != token.charid` (which may be the case for some token types), this comparison
always fails and `numAttackers` stays 0, preventing the Extra Attackers modifier from appearing.

This bug is escalated to the senior developer for investigation.

---

## 4. Roll Dialog (DSRollDialog / EmbeddedRollDialog)

### Key Files

| File | Purpose |
|------|---------|
| `Draw Steel UI/DSRollDialog.lua` | Main power roll dialog, ShowDialog entry point |
| `Timeline/EmbeddedRollDialog.lua` | Embedded roll dialog, GetEnabledModifiers, prepare handlers |
| `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua` | ShowDialog call site, modifier assembly |

### ShowDialog Entry Point

```lua
local rollKey = dialog.data.ShowDialog{
    -- Identity
    type        = "ability_power_roll",   -- roll type ID
    description = ability.name .. ": Power Roll",
    title       = ability.name,

    -- Roll formula
    roll        = roll,                   -- string, e.g. "2d10+5"

    -- Context
    creature        = caster,
    targetCreature  = primaryTarget,
    symbols         = options.symbols,    -- GoblinScript symbol table
    ability         = ability,

    -- Targets and modifiers
    modifiers         = modifiersApplied, -- see Modifier Structure below
    multitargets      = multitargets,     -- array of target data tables
    CalculateMultiTargets = fn,           -- function() -> updated multitargets array

    -- Roll properties (power table tiers and damage)
    rollProperties  = rollProperties,     -- RollPropertiesPowerTable

    -- Behaviour flags
    showDialogDuringRoll = true,  -- keep dialog open after dice resolve
    amendable            = true,  -- allow re-rolling (requires showDialogDuringRoll)
    autoroll             = false, -- skip dialog; string = setting key controlling this

    -- Result panels
    PopulateCustom = fn,   -- populate custom result area
    PopulateTable  = fn,   -- populate power table display

    -- Callbacks
    rollActive   = function(activeRoll) ... end,  -- receive roll object
    beginRoll    = function(rollInfo) ... end,    -- fires when roll starts
    completeRoll = function(rollInfo) ... end,    -- fires when roll accepted
    cancelRoll   = function() ... end,            -- fires if user cancels
}
```

**Field name gotcha:** The dynamic target-recalculation function must be passed as
`CalculateMultiTargets` (capital C, capital M, capital T). DSRollDialog reads
`options.CalculateMultiTargets` exactly. Do not use `RecalculateMultitargets` or any
other capitalisation variant.

### Modifier Structure

Each entry in the `modifiers` array:

```lua
{
    modifier        = CharacterModifier,  -- the modifier object
    hint            = { result = true },  -- initial enabled state (from hint system)
    override        = true or false or nil, -- explicit user toggle (nil = use hint/force)
    context         = {},                 -- arbitrary data for modifier functions
    failsRequirement = nil or true,       -- set by prepareBeforeRollProperties
    text            = "Edge",             -- checkbox label
    tooltip         = "Adds an edge...",  -- hover tooltip
    modifierOptions = nil or array,       -- if set, renders a dropdown instead of checkbox
    modFromTarget   = nil or true,        -- modifier applies to target, not caster
}
```

### GetEnabledModifiers -- Precedence Rules

Returns sorted array of currently-checked modifiers (excludes `failsRequirement` entries):

| Priority | Condition | Result |
|----------|-----------|--------|
| 1 (highest) | `mod.override ~= nil` | Use `mod.override` (user toggle wins) |
| 2 | `mod.modifier.force == true` | Enabled; cannot be unchecked |
| 3 (lowest) | otherwise | Use `mod.hint.result` |

Force-flagged modifiers are rendered as locked checkboxes in the UI.

### prepare and prepareBeforeRollProperties

`prepare` fires when `ShowDialog` is called and again when result panels are shown.
Use it to rebuild `element.children` based on current options:

```lua
gui.Panel{
    prepare = function(element, options)
        if options.modifiers == nil then
            element.children = {}
            return
        end
        local children = {}
        for _, mod in ipairs(options.modifiers) do
            if not mod.failsRequirement then
                children[#children+1] = BuildModifierRow(mod)
            end
        end
        element.children = children
    end,
}
```

`prepareBeforeRollProperties` fires just before the dice roll, after the roll formula is
finalised. Use it to disable modifiers whose `rollRequirement` is not met by the current roll:

```lua
-- Example: disable a modifier if no boons are present in the roll
prepareBeforeRollProperties = function(element, rollInfo, enabledModifiers, rollProperties)
    for _, mod in ipairs(m_options.modifiers or {}) do
        if mod.modifier:try_get("rollRequirement", "none") ~= "none" then
            local passes = mod.modifier:CheckRollRequirement(rollInfo, enabledModifiers, rollProperties)
            mod.failsRequirement = not passes
            if not passes then mod.override = false end
        end
    end
end
```

### Roll Event Sequence

```
ShowDialog called
  -> prepare fires on all child panels
  -> User adjusts modifiers / boons / banes
  -> CalculateRollText() called each change
  -> User clicks Roll
  -> prepareBeforeRollProperties fires
  -> Dice resolve
  -> prepare fires on result panels
  -> completeRoll callback fires when user accepts result
```
