# Monster AI

This module provides an automated combat AI for monsters in DMHub. When active, it takes turns for all non-player creatures in the initiative queue -- moving tokens, selecting abilities, choosing targets, and advancing initiative automatically.

## File Overview

| File | Purpose |
|---|---|
| `MonsterAI.lua` | Core AI engine: turn loop, pathfinding, target selection, ability execution, scoring framework |
| `MonsterAIMonsters.lua` | Registered **moves** -- one per monster ability or combo. This is where specific monster AI behaviors live |
| `MonsterAIPrompts.lua` | Registered **prompts** -- handlers for abilities that require a secondary choice (shift destination, push/pull direction, invoked sub-ability targets) |
| `MonsterAITactics.lua` | Registered **tactics** -- passive scoring modifiers that bias target/position selection (flanking, aid attack, high ground) |
| `MonsterAIPanel.lua` | DM-only dockable panel UI: start/stop AI, view analysis of available moves per monster type, enable/disable individual moves |

## Load Order

In `main.lua` (prefix `Monster_AI_d7b4`):
```
MonsterAI.lua        -- must be first (defines the MonsterAI game type)
MonsterAIPanel.lua
MonsterAIMonsters.lua
MonsterAIPrompts.lua
MonsterAITactics.lua
```

## Architecture

### The Turn Loop

1. `MonsterAIPanel.lua` runs a coroutine (`MonsterAIThread`) that polls the initiative queue.
2. When it is a non-player turn, it creates a `MonsterAI` instance and calls `PlayTurnCoroutine(initiativeid)`.
3. For each token in that initiative entry:
   - Minions: find their Signature Ability and execute it as a coordinated squad strike (`ExecuteSquadStrike`).
   - Non-minions: iterate up to 6 times calling `FindAndExecuteMove()`, which scores every registered move and executes the best one. The loop breaks when no move scores above 0.
4. After all tokens act, initiative advances automatically.

### Three Registration Systems

The AI's behavior is defined by three registries on the `MonsterAI` singleton:

#### 1. Moves (`MonsterAI:RegisterMove{}`)

A **move** is a scoreable, executable action the AI can take on its turn. Each move:
- Has an `id` (unique string), `description`, and `category` ("Main Actions", "Basic Strikes", "Maneuvers")
- Lists `abilities` -- an array of ability name strings that must all exist on the token and be affordable
- Optionally lists `monsters` -- an array of `monster_type` strings. If present, the move only applies to those monsters. If omitted, the move is **generic** (applies to all monsters)
- Has a `score(self, ai, token, ability1, ability2, ...)` function that returns `{score = N, loc = destLoc, ...}` or `nil`
- Has an `execute(self, ai, token, scoringInfo, ability1, ability2, ...)` function that performs the move

#### 2. Prompts (`MonsterAI:RegisterPrompt{}`)

A **prompt** handles abilities that require a secondary targeting choice during resolution (e.g., a Shift destination after a hit, or a Push/Pull direction). Registered with:
- `prompts` -- array of ability name strings this handler responds to. Can be plain names (`"Shift"`) or monster-qualified (`"Decrepit Skeleton:Invoked Ability"`)
- `handler(ai, invokerToken, casterToken, abilityClone, symbols, options)` -- returns a table with `targets` array, or `nil` to fall through to manual prompting

#### 3. Tactics (`MonsterAI:RegisterTactic{}`)

A **tactic** is a passive scoring modifier that adjusts the edge count when evaluating strike targets. Tactics don't execute anything -- they bias which target/position the AI prefers.
- `id`, `description`
- `score(self, token, tokenLoc, enemy, ability)` -- returns a number (typically 0 or 1) added to the target's edge score, or `nil`

### Scoring Model

The AI's decision-making is score-based:

1. **Move scoring**: Each move's `score()` is called. The move with the highest `score` value wins. Generic moves like free strikes use low scores (0.2) so monster-specific moves are preferred.
2. **Target scoring within a move**: `FindBestMoveToUseStrike` iterates every reachable tile, evaluates valid targets from that position, and picks the tile that maximizes `numTargets + edges*0.1 - movementCost*0.001`.
3. **Edge adjustments**: For each potential target at each position, active tactics add/subtract from the edge score. Line of sight obstruction subtracts 1 edge. Being a ranged attacker adjacent to enemies subtracts 1 edge.

### Key Helper Methods

| Method | What it does |
|---|---|
| `ai:FindBestMoveToUseStrike(token, ability, scorefn?)` | Finds the best reachable tile to use a strike ability from. Returns `loc, score` |
| `ai:FindBestMoveToUseBurst(token, ability, scorefn?)` | Same but for burst/area abilities (targetType "all") |
| `ai:FindValidTargetsOfStrike(token, ability, loc, range?)` | Returns sorted array of `{token, loc, charge, edges}` for valid targets from a position |
| `ai:ExecuteAbility(casterToken, ability, targets?, options?)` | Moves, displays line-of-sight rays, invokes the ability, waits for resolution |
| `ai:Speech(token, text, options?)` | Makes a token say something (text can be a string or array for random selection) |
| `ai:FindReachableConcealment()` | Finds the nearest reachable concealed tile |
| `ai:FindClosestEnemy()` | Returns the nearest enemy token |
| `ai:DistanceFromNearestEnemy(token)` | Returns distance to the closest enemy |
| `ai:SetTargetsForExpectedPrompt(options)` | Pre-sets targets for the next prompt callback (used for complex combos) |
| `MonsterAI.Sleep(seconds)` | Coroutine yield for pacing/animation |

### Standard Score/Execute Generators

Two helpers reduce boilerplate for simple strike-based moves:

```lua
-- Returns a score function that uses FindBestMoveToUseStrike
GenerateStandardStrikeScoreFunction(score)

-- Returns an execute function that moves then uses the strike
GenerateStandardStrikeExecuteFunction()
```

## How to Add AI for a New Monster

### Step 1: Identify the Monster's Abilities

Open the monster's YAML file in `compendium/bestiary/`. The key field is `monster_type` (e.g., `"Goblin Warrior"`) -- this is what you match against in the `monsters` array. Look at `innateActivatedAbilities` for the ability names, keywords, ranges, and targeting.

### Step 2: Register Moves in `MonsterAIMonsters.lua`

For each ability or combo the monster should use, add a `MonsterAI:RegisterMove{}` call. Example for a simple strike:

```lua
MonsterAI:RegisterMove{
    id = "Razor Claws",           -- unique ID, typically matches ability name
    category = "Main Actions",     -- or "Maneuvers", "Basic Strikes"
    monsters = {"Ghoul"},          -- monster_type strings from the YAML
    abilities = {"Razor Claws"},   -- ability name(s) that must be present and affordable
    description = "Ghoul's preferred melee attack.",
    score = GenerateStandardStrikeScoreFunction(1),
    execute = GenerateStandardStrikeExecuteFunction(),
}
```

### Step 3: Choose a Score Value

Score values determine priority. Guidelines:
- **0.2** -- Generic fallback (free strikes). Monster-specific moves should always score higher
- **0.5 - 0.8** -- Situational moves (hide, maneuvers with conditions)
- **1.0** -- Standard signature ability
- **1.5 - 2.5** -- Powerful or malice-costing abilities that should be preferred when available
- Return `nil` from `score()` if the move can't be used (no targets in range, conditions not met)

### Step 4: Write the Score Function

The score function evaluates whether the move is viable and how good it is. Common patterns:

**Simple strike** -- use the standard generator:
```lua
score = GenerateStandardStrikeScoreFunction(1),
```

**Strike with custom target preference** -- provide a scoring function:
```lua
score = function(self, ai, token, ability)
    local loc, score = ai:FindBestMoveToUseStrike(token, ability, function(targetToken, edges)
        -- prefer low-stamina targets
        return 1 + (1 - targetToken.properties:CurrentHitpoints() / targetToken.properties.max_hitpoints)
    end)
    if loc ~= nil then
        return {score = score, loc = loc}
    end
end,
```

**Burst/area ability** -- use `FindBestMoveToUseBurst`:
```lua
score = function(self, ai, token, ability)
    local loc, score = ai:FindBestMoveToUseBurst(token, ability, function(targetToken)
        if targetToken:IsFriend(token) then return -1 end  -- avoid allies
        return 1
    end)
    if loc ~= nil and score >= 2 then  -- only use if hitting 2+ enemies
        return {score = score * 0.5, loc = loc}
    end
end,
```

**Conditional availability** -- return `nil` when conditions aren't met:
```lua
score = function(self, ai, token, ability)
    if token.properties:HasNamedCondition("Hidden") then
        return nil  -- don't use this if already hidden
    end
    -- ...
end,
```

### Step 5: Write the Execute Function

The execute function performs the move. Standard pattern:

```lua
execute = function(self, ai, token, scoringInfo, ability)
    -- 1. Move to the chosen position
    local path = token:Move(scoringInfo.loc, {maxCost = 10000, ignoreFalling = false})
    ai.Sleep(0.5)

    -- 2. Optional: say something for flavor
    ai:Speech(token, {"Attack!", "Take this!"})
    ai.Sleep(0.5)

    -- 3. Find targets and execute the ability
    local targets = ai:FindValidTargetsOfStrike(token, ability, scoringInfo.loc)
    ai:ExecuteAbility(token, ability, targets)
end,
```

For burst abilities, omit the targets parameter:
```lua
ai:ExecuteAbility(token, ability)  -- auto-targets all in range
```

### Step 6: Handle Prompts (If Needed)

If the monster's ability triggers a secondary prompt (e.g., forced movement direction, a sub-ability invocation), add a prompt handler in `MonsterAIPrompts.lua`:

```lua
MonsterAI:RegisterPrompt{
    prompts = {"Monster Name:Ability Name"},  -- or just "Ability Name" if generic
    handler = function(ai, invokerToken, casterToken, abilityClone, symbols, options)
        -- Calculate best target/location for the prompt
        -- Return {targets = {{token = someToken}}} or {targets = {{loc = someLoc}}}
        -- Return nil to fall back to manual prompting
    end,
}
```

### Step 7: Register Tactics (If Needed)

If the monster benefits from a positioning tactic not already registered, add it in `MonsterAITactics.lua`:

```lua
MonsterAI:RegisterTactic{
    id = "My Tactic",
    description = "Description of what the tactic does.",
    score = function(self, token, tokenLoc, enemy, ability)
        -- Return a number (typically 1) to add an edge for this target
        -- Return nil or 0 for no bonus
    end,
}
```

Note: tactics apply to ALL monsters unless filtered with a `monsters` array.

### Multi-Ability Combos

For monsters that should combo abilities (e.g., Leap then Razor Claws), list multiple abilities:

```lua
MonsterAI:RegisterMove{
    id = "Leap and Claw",
    monsters = {"Ghoul"},
    abilities = {"Leap", "Razor Claws"},  -- both must be present and affordable
    score = function(self, ai, token, leapAbility, razorClawsAbility)
        -- score function receives abilities in order
    end,
    execute = function(self, ai, token, scoringInfo, leapAbility, razorClawsAbility)
        -- execute both in sequence
        ai:ExecuteAbility(token, leapAbility, leapTargets)
        ai.Sleep(0.5)
        ai:ExecuteAbility(token, razorClawsAbility, clawTargets)
    end,
}
```

Use `ai:SetTargetsForExpectedPrompt{}` if the first ability triggers a prompt that should be auto-resolved for the combo.

## Existing Monster AIs

Currently implemented in `MonsterAIMonsters.lua`:

| Monster Type | Moves |
|---|---|
| *(Generic - all monsters)* | Charge and Free Strike, Ranged Free Strike, Knockback, Grab, Aid Attack |
| Goblin Warrior | Spear Charge, Bury the Point |
| Goblin Assassin / Goblin Pirate Assassin | Sword Stab, Shadow Chains, Hide in Concealment |
| Bugbear Channeler | Shadow Drag, Twist Shape, Blistering Element |
| Ryll | Two Shot |
| Ghoul | Razor Claws, Leap and Claw |
| Zombie | Clobber and Clutch, Zombie Dust |
| Skeleton | Bone Shards, Bone Spur |

## Tips

- The `monster_type` field in the YAML must match the `monsters` array exactly (it is case-sensitive).
- Generic moves (no `monsters` array) are available to all monsters as fallbacks. Keep their scores low.
- `ai.Sleep()` calls add pacing between actions so the DM can follow what is happening. Use 0.3-1.0 seconds between steps.
- `ai:Speech()` accepts a string or an array of strings (picks one at random). Good for flavor.
- The AI iterates up to 6 action cycles per token, so a monster can use a maneuver + a main action + more if it has the resources.
- Abilities must be affordable (`ability:CanAfford(token)`) or the move is skipped. The framework checks this automatically before calling `score()`.
- The scoring info table returned from `score()` is passed directly to `execute()` as `scoringInfo`. You can store arbitrary data in it (e.g., a pre-computed target list).
- Minions are handled automatically via `ExecuteSquadStrike` -- you generally don't need to register moves for them.
- The DM can enable/disable individual moves per monster type via the Monster AI panel.
