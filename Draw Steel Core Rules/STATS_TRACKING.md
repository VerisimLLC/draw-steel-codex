# Stat tracking notes (for agents wiring up many stats)

Hand this to anyone adding per-encounter hero statistics. It is the contract for the
one function you call, plus the rules that keep stat tracking correct.

## The one call

```lua
LiveEncounter.TrackHeroStats(tokenid, statid, quantity)
```

- `tokenid` -- the token that triggered the event (a `token.charid`). See "Getting a
  tokenid" below for how to derive it from a creature.
- `statid` -- the free-form name of the stat to accumulate, e.g. `"kills"`,
  `"healingDone"`. May be a `"/"`-separated nested path, e.g.
  `"monsterDamage/" .. monsterid`, which accumulates into a sub-table the backend
  creates automatically.
- `quantity` -- how much to add. Optional, defaults to `1`. May be negative or
  fractional.

That is the whole surface. You do **not** need to find the encounter, check for
combat, validate the token, or network anything -- it does all of that.

Defined in `Draw Steel Core Rules/MCDMEncounter.lua`. It is a static function on the
`LiveEncounter` global, callable from anywhere at runtime.

## What it guarantees (so you can call it freely)

1. **It never throws.** The whole body is wrapped in `pcall`. Safe to drop into hot
   paths (damage, healing, movement, saves). A failure logs via `dmhub.Debug` and
   returns. **Do not wrap your call in your own `pcall`** -- it is redundant.

2. **It no-ops unless the stat is valid.** A stat is recorded only when ALL hold:
   - we are in active combat (initiative present and not hidden), AND
   - a `LiveEncounter` is live in that combat, AND
   - the token resolves to a hero (type `"character"`) that is participating in that
     encounter.
   Otherwise it silently does nothing. So feeding it monsters, objects, or
   out-of-combat events is fine -- they are dropped.

3. **Summons attribute to their summoner.** If the token is a summoned creature (an
   animal companion, a minion a character summoned, etc.), the stat is attributed to
   the hero at the root of the `summonerid` chain. You pass the summon's tokenid; the
   hero gets credited. A summon of a *monster* resolves to a non-hero and is dropped.

4. **It accumulates atomically on the server.** The add is routed through
   `dmhub:IncrementInitiativeData` -> `DataStore.IncrementData`, which on Durable
   Object backends is a genuinely atomic server-side increment. Concurrent writers
   (multiple players hitting things at once) cannot lose updates.

## Rules you MUST follow when adding calls

- **Call it exactly once per event, on the authoritative client.** Because the
  increment networks itself, calling it on every client that observes an event would
  multiply the count. Put your call where the event is *resolved once* -- e.g. inside
  the `ModifyProperties{execute=...}` that applies the change, or wherever the
  acting/DM client runs the rules -- not in shared refresh/redraw code that runs on
  every client.

- **Do not call `dmhub:UploadInitiativeQueue()` after it.** The resolved value rides
  back through the normal initiative-queue broadcast. `TrackHeroStats` does not mutate
  the local stats table and needs no upload.

- **Do not pre-create the stats table or sub-paths.** `LiveEncounter.Create` makes the
  empty `stats` table; nested paths are vivified by the backend on first increment.

- **Pick stable, ASCII, path-safe stat ids.** Stat ids and the segments of a nested
  path must match `^[a-zA-Z0-9_\-.:]+$` (guids and plain names are fine). Use `/` only
  as the nesting separator. Keep names consistent across call sites so they aggregate.

## Getting a tokenid

- From a **token**: use `token.charid` (this is the tokenid; `token.id` is a
  deprecated alias of the same value).
- From a **creature** (a `token.properties`, which is what most rules code holds):
  `local t = dmhub.LookupToken(creature); if t ~= nil then ... t.charid ... end`.
  `dmhub.LookupTokenId(creature)` returns the id directly. Guard for `nil` (a creature
  may have no token on the map).

## Examples

```lua
-- simple counter
LiveEncounter.TrackHeroStats(token.charid, "kills")              -- +1

-- explicit amount
LiveEncounter.TrackHeroStats(token.charid, "healingDone", 12)    -- +12

-- nested / keyed stat (backend creates the "monsterDamage" sub-table)
LiveEncounter.TrackHeroStats(token.charid, "monsterDamage/" .. monsterid, 8)

-- from a creature in rules code
local tok = dmhub.LookupToken(victimCreature)
if tok ~= nil then
    LiveEncounter.TrackHeroStats(tok.charid, "damageTaken", amount)
end
```

## Worked precedent: damageDealt / damageTaken / damagePrevention

These stats are wired in `Draw Steel Core Rules/MCDMCreature.lua` by overriding
`creature.InflictDamageInstance` (the single choke point for attack damage). It reads
the post-resistance landed amount (`result.damageDealt`). Crucially, temporary stamina
is consumed inside `TakeDamage` *after* the base call returns `damageDealt`, so the
wrapper snapshots `TemporaryHitpoints()` before and after the base call and splits the
landed damage:

- `absorbed = clamp(tempBefore - tempAfter, 0, landed)`; `staminaLoss = landed - absorbed`.
- `LiveEncounter.TrackHeroStats(victim.charid, "damageTaken", staminaLoss)` -- only the
  actual stamina loss, so temp-stamina-absorbed damage no longer inflates `damageTaken`.
- `LiveEncounter.TrackHeroStats(grantor, "damagePrevention", absorbed)` -- credited to
  whoever granted the temp stamina (`creature.temporary_hitpoints_source`, captured
  *before* the base call because it is cleared when the pool empties mid-call), not to
  the protected creature. So a hero shielding a non-hero ally still gets the credit.
- `LiveEncounter.TrackHeroStats(attacker.charid, "damageDealt", landed)` (attacker from
  `symbols.attacker`, nil for environmental/aura damage) -- the full landed amount; the
  attacker still dealt it even if temp stamina soaked it.

The grantor is recorded when temp stamina is applied: `GrantTemporaryStamina` and the
ongoing-effect grant in `creature:ApplyOngoingEffect` pass `options.source` to
`SetTemporaryHitpoints`, whose DS override stores it as `temporary_hitpoints_source` and
clears it when the pool hits zero. The `RemoveTemporaryHitpoints` round-trip that absorbs
damage passes no source, so it survives until depletion. A creature has at most one
temp-stamina source at a time.

It all runs once on the resolving client, inside the damaging `ModifyProperties` execute,
alongside the existing `cast:CountDamage` -- a good template for "hook the one place the
event is finalized, use the real applied amount, call once."

## Worked precedent: kills / minionKills

Also in `creature.TakeDamage` (`Draw Steel Core Rules/MCDMCreature.lua`). Two paths,
because minions are modeled as a shared squad stamina pool rather than individual
stamina:

- **Regular monsters** -- counted at the death transition (`(not isDeadAtStart) and
  self:IsDead()`), in the same block that fires `attacker:TriggerEvent("kill")`. We
  add `LiveEncounter.TrackHeroStats(killerToken.charid, "kills")`, guarded to non-hero
  victims (a dying hero is not a kill).
- **Minions** -- the minion branch returns before that death code, so it counts kills
  itself. Minion stamina is a squad pool (`MaxHitpoints = liveMinions * health_single`),
  so a single hit can empty several `health_single` bands. We capture
  `CurrentHitpoints()` before the hit and compute
  `ceil(hpBefore/health_single) - ceil((hpBefore-amount)/health_single)` as the number
  killed, crediting the attacker that many `minionKills`. Because the count comes from
  the pool delta, the "Strikes with Multiple Targets" clamp (redundant calls land with
  `amount == 0`) and area hits (one band per call, summed) both come out right, and
  overkill past the last minion is bounded so it never over-counts.

## Worked precedent: tierRolls (power-roll tier tally)

`ActivatedAbilityPowerRollBehavior:Cast` (`Draw Steel Core Rules/MCDMAbilityRollBehavior.lua`)
records which tier each power roll landed on. The `Cast` coroutine runs once on the
authoritative casting client; right after the roll resolves (and the cancel check
passes) it computes the effective tier (`rollProperties:try_get("overrideTier") or
DiceResultToTier(m_result)` -- the same value the per-target loop applies) and calls:

```lua
LiveEncounter.TrackHeroStats(casterToken.charid, string.format("tierRolls/tier%d", rolledTier))
```

So a tier-2 result for a hero increments `stats[heroid].tierRolls.tier2`. The call is
placed before the per-target loop so it fires exactly once per roll regardless of how
many targets the ability hits. Non-hero casters (monsters) are dropped by
`TrackHeroStats` itself.

## Worked precedent: spacesMoved

`creature:Moved` (the DS wrapper in `Draw Steel Core Rules/MCDMCreature.lua`) is the
engine's per-move callback -- DMHub calls it once on the moving client whenever the
token finishes a move, and it does its own `ModifyProperties` upload, so it is the
authoritative single-fire point. After the base call it adds `path.numSteps` (tiles
traversed) to `spacesMoved`, gated to:

- `self:IsOurTurn()` -- the same gate the base `Moved` uses for movement-cost
  accounting, so it counts exactly the movement the engine attributes to your turn
  (normal movement and shifting), and naturally drops forced movement that happens on
  someone else's turn.
- `not path.forced` and `path.movementType ~= "teleport"` -- exclude pushes/pulls/slides
  and teleports, which are not the hero choosing to walk spaces.

`TrackHeroStats` self-guards to heroes in the live encounter, so non-hero movers are
dropped (a summon attributes to its summoner).

## Authoring hook: the "Track Stat" ability behavior

For stats that should be author-driven rather than code-driven, the `track_stat`
ability behavior (`Draw Steel Ability Behaviors/AbilityTrackStat.lua`) exposes a
free-form stat name + a GoblinScript quantity + a standard "Apply To" selector, and
calls `TrackHeroStats` for each applied creature. Prefer adding a behavior to an
ability over hard-coding a call when a content author should control it.

## Reading stats back

- `liveEncounter:GetStats()` -> `{ [tokenid] = { statid = total, ... }, ... }`
- `liveEncounter:GetStatsForToken(tokenid)` -> one hero's `{ statid = total }`

Both are read-only views; only ever mutate through `TrackHeroStats`.

## Build caveat (temporary)

The underlying engine binding `dmhub:IncrementInitiativeData` requires a C# build. Until
that build ships, `TrackHeroStats` calls safely no-op (the missing-method error is
caught by its `pcall` and logged via `dmhub.Debug`). After the build + relaunch, the
increments network for real. Writing the call sites now is safe regardless.
