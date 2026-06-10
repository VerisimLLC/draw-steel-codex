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
- `LiveEncounter.TrackHeroStats(attacker.charid, "damageDealt", counted)` and
  `LiveEncounter.TrackHeroStats(attacker.charid, "overkill", overkill)` (attacker from
  `symbols.attacker`, nil for environmental/aura damage). The landed amount is split:
  `counted` is the damage that mattered -- temp stamina absorbed plus the stamina the
  victim's pool actually lost, with the pool loss capped at what brings the victim
  exactly to its kill threshold -- and `overkill` is the rest. The kill threshold
  is `creature:KillThresholdStamina()` (defined beside the IsDead/IsDying overrides in
  `MCDMCreature.lua`, which compare against it): characters and retainers die at
  `-BloodiedThreshold()`, everything else (including minion squad pools) at 0. Pool
  loss is measured from the actual before/after `CurrentHitpoints()` delta, so the
  minion-squad clamps inside `TakeDamage` (area damage capped at one minion's max
  stamina, "Strikes with Multiple Targets" ignoring redundant instances) are respected
  without re-deriving them: a non-area strike CAN drain the whole squad pool and is
  counted until the pool hits 0, with the excess recorded as overkill. The attacker is
  still credited for temp-stamina-soaked damage (it consumed a real resource); only
  past-death damage is overkill. `damageTaken` (above) intentionally still records the
  full stamina loss including past-death damage -- it is a victim-side stat and the
  overkill split is attacker-side.

Two turn-relative stats ride the same attacker block, both using the overkill-excluded
`counted` amount:

- `allyDamageDealt` -- when the attacker's damage lands while it is a DIFFERENT
  friendly creature's turn, the hero whose turn it is gets the credit (the ally's
  triggered free strikes, opportunity damage, etc. that their turn enabled). The turn
  owner is resolved via `dmhub.initiativeQueue:CurrentInitiativeId()` ->
  `dmhub.GetTokenById`, which works because hero initiative ids ARE tokenids;
  squad/grouping ids (`MONSTER-...`) fail the lookup, which correctly skips monster
  turns (and grouped-hero initiatives, where the owner would be ambiguous). The
  attacker's `summonerid` chain is walked to its root first, so a hero's own summon
  attacking on their turn counts as their own damage, not ally damage. The friendship
  gate is `turnToken:IsFriend(attackerToken)`, so enemy damage during a hero's turn
  records nothing.
- `enemyTurnDamage` -- when the attacker's damage lands while an ENEMY of the attacker
  is taking their turn (triggered abilities, free strikes, opportunity damage on the
  monster's turn), the attacker gets the credit (a summon attributes to its hero via
  TrackHeroStats as usual). This only needs to classify which SIDE owns the turn, so
  when the current initiativeid is not a tokenid (monster type groups, minion squads)
  it falls back to scanning `dmhub.allTokens` for any token whose
  `InitiativeQueue.GetInitiativeId` matches -- any member of the squad/group works for
  a friend-or-foe check. A monster attacking during a hero's turn passes the same gate
  but is dropped by TrackHeroStats's hero guard.

Damage immunity also feeds `damagePrevention`, credited to the **victim** (it is their
own immunity). The base `InflictDamageInstance` applies immunity/DR before returning
`damageDealt`, and the wrapper still holds the raw pre-immunity `amount` argument, so
`immunityPrevented = floor(amount) - landed`, clamped at zero (vulnerability and
amplification increase damage and must not record negative prevention). This is tracked
even when `landed == 0` -- full immunity is the maximal prevention case. It stacks
cleanly with the temp-stamina split above: immunity prevention is measured against the
pre-immunity amount, temp-stamina prevention against the post-immunity landed amount, so
nothing is double-counted.

Damage halved by `(half)` power-roll modifiers also feeds `damagePrevention`, tracked in
`ExecuteDamage` (`Draw Steel Core Rules/MCDMAbilityBehavior.lua`), which is where the
`(half)` markers in the tier text are parsed and applied (flooring once per marker). The
prevented amount is `damageBeforeHalving - damage`, snapshotted after the characteristic
bonus is added and before the half loop, and recorded inside the same
`ModifyProperties` execute as `cast:CountDamage`. It is credited to the **target**: by
execute time the tier text carries only the bare `(half)` marker, so whoever applied the
halving (the target's own trait/trigger vs a protector ally) is not recoverable -- the
target is the best available attribution. Upgrading this to true provenance would mean
recording the halver's tokenid alongside the marker when `modifyRollProperties`
(`MCDModifyPowerRolls.lua`) appends it, and threading it through the cast like
`SetPotencyApplied`. Halving stacks cleanly with the layers above: it is
applied before `InflictDamageInstance`, so immunity prevention measures against the
post-half amount, and `damageTaken + all prevention` still sums to the raw damage.
`(no damage)` tier markers skip damage entirely and are intentionally NOT counted yet.

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

So a tier-2 result for a hero increments `stats[heroid].tierRolls.tier2` (within the
current round bucket). The call is placed before the per-target loop so it fires
exactly once per roll regardless of how many targets the ability hits. Non-hero
casters (monsters) are dropped by `TrackHeroStats` itself.

The same block also records `edges` and `banes` -- the number of edges/banes applied
to the completed roll, read from `m_result.boons`/`m_result.banes` (the engine's
boon/bane naming for Draw Steel's edges/banes, captured from the roll dialog's
`completeRoll`). They share the tier gate, so the denominators line up: every roll
counted in `tierRolls` contributes its edges/banes, and nothing else does.

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

## Worked precedent: forcedMovementDealt / forcedMovementTaken

Every forced-movement flow (the tier-text push/pull/slide rule commands, the raw
`ActivatedAbilityForcedMovementBehavior`, and direct/remote invokes of the standard
"Forced Movement: X" abilities) funnels into a `relocate_creature` cast of an ability
clone whose `range` has already been adjusted for stability, Big Versus Little, Forced
Movement Increase, and caster forced-movement bonuses, and whose `forcedMovement` field
carries the movement type. The wrapper around
`ActivatedAbilityRelocateCreatureBehavior.Cast` at the bottom of
`Draw Steel Core Rules/MCDMAbilityBehavior.lua` hooks that single funnel point, gated to
`forcedMovement ~= nil` and effective movementType `"move"` (teleports and jumps are not
forced movement).

The recorded distance is the clone's range in squares -- the post-adjustment
*entitlement*, not the actual path length. A push 5 that hits a wall after 2 squares
counts as 5 (matching the rules' notion of how far you got to force-move them), and the
actual-distance shortfall is deliberately ignored. Two stats:

- `forcedMovementTaken` -- credited to the moved creature (the clone's caster).
- `forcedMovementDealt` -- credited to the pusher (the clone's `invoker` field, falling
  back to `options.symbols.invoker`), and only when the moved creature is an enemy of
  the pusher (`pusherToken:IsFriend(...)` false) -- sliding allies into position does
  not count as moving your enemies.

The Cast runs once, on the client that resolves the forced-movement prompt, so the
increment is single-fire. A "Too Much Stability" outcome never reaches the relocate cast
(range 0 fails out earlier), so it records no distance -- instead it records
`standsFirm` (+1 per attempt), credited to the would-be-moved hero, at the two places
that produce that outcome: the tier-command rule in
`Draw Steel Core Rules/MCDMAbilityBehavior.lua` (`range <= 0` with `stability > 0`,
right before `ShowFailSpeech("Too Much Stability")`) and
`ActivatedAbilityForcedMovementBehavior:Cast` in `DMHub Game Rules/ActivatedAbility.lua`
(same condition, before its Too Much Stability invoke). The remote-invoke flow fails
out at the first site before anything is sent, so there is no double-count. The
"Cannot Be Force Moved" / immunity / grabbed outcomes are intentionally NOT counted --
standing firm is specifically stability zeroing out the distance.

## Worked precedent: heroicResourcesGained / heroicResourcesSpent

`creature.ConsumeResource`, `creature.RefreshResource`, and
`creature.AddUnboundedResource` (all in `DMHub Game Rules/Resource.lua`) are the three
engine entry points that change the heroic resource pool. All three are wrapped in
`Draw Steel Core Rules/MCDMCreature.lua`; each wrapper snapshots
`GetResources()[CharacterResource.heroicResourceId]` before the base call and records
the actual delta after: positive -> `heroicResourcesGained`, negative ->
`heroicResourcesSpent`. Measuring the real delta (instead of trusting the requested
quantity) makes clamping (gains capped at the resource max, spends capped at what is
available), no-op calls, and the combat-id rollover all correct for free --
`GetResources` ignores stale unbounded entries from a previous combat, so the first
gain of a new combat measures from 0 rather than from the leftover value.

The wrappers only track when the key is the heroic resource id AND the creature is a
`character`. The character gate matters: heroic resource sharing (a companion spending
from its summoner hero's pool) redirects the base call to the hero, which re-enters
the wrappers as the hero -- tracking the companion's outer call too would double
count. Malice (the monster analogue) never matches the heroic resource id, and
TrackHeroStats self-guards to heroes in the live encounter as usual.

## Worked precedent: conditionsInflicted / conditionsReceived

The DS override of `creature:InflictCondition` (`Draw Steel Core Rules/MCDMCreature.lua`)
is the single choke point for condition application, so the tracking lives inside its
non-purge branch, next to the `inflictcondition` event dispatch. Both stats use nested
paths keyed by lowercased condition name, so they aggregate per condition:
`conditionsInflicted/frightened`, `conditionsReceived/prone`, etc.

- Only the official conditions count, via the `g_officialStatConditions` set above the
  function: bleeding, dazed, frightened, grabbed, prone, restrained, slowed, taunted,
  weakened. Surprised and homebrew/internal conditions are deliberately excluded.
- Only genuinely NEW applications count. `wasActive` is captured from
  `inflictedConditions[conditionid]` before the entry is created, so refreshing an
  already-active condition (new caster, new duration) records nothing, as do purges.
  Immunity returns out of the function before the tracking is reached.
- `conditionsReceived/<name>` -- credited to the victim.
- `conditionsInflicted/<name>` -- credited to `args.casterInfo.tokenid` (absent for
  environmental/self-applied sources), skipped when the inflicter IS the victim
  (e.g. voluntarily dropping prone records only conditionsReceived).
- TrackHeroStats self-guards as usual: a monster frightening a hero records only the
  hero's conditionsReceived; a hero frightening a monster records only the hero's
  conditionsInflicted.

## Authoring hook: the "Track Stat" ability behavior

For stats that should be author-driven rather than code-driven, the `track_stat`
ability behavior (`Draw Steel Ability Behaviors/AbilityTrackStat.lua`) exposes a
free-form stat name + a GoblinScript quantity + a standard "Apply To" selector, and
calls `TrackHeroStats` for each applied creature. Prefer adding a behavior to an
ability over hard-coding a call when a content author should control it.

Stats recorded this way by shipped content (do NOT add code-side tracking for these):

- `criticals` -- critical hits, recorded by the Critical Hit global rule content's
  behaviors. Consumed by the victory screen's hero roles (Deadeye, Hat Trick).

## Storage layout: per-round buckets

Stats are stored per round, transparently to callers: `IncrementStat` reads
`dmhub.initiativeQueue.round` and writes to
`liveEncounter/stats/<tokenid>/round<N>/<statid>`. Call sites do NOT change -- the same
`TrackHeroStats(tokenid, statid, quantity)` call lands in whatever round is current.
The round key is the string `"round<N>"` (not a bare number) so no serialization layer
mistakes the sub-table for an array. Whole-combat totals are produced by summing the
round buckets on read.

## Reading stats back

- `liveEncounter:GetStats()` -> raw `{ [tokenid] = { round1 = { statid = total, ... }, ... }, ... }`
- `liveEncounter:GetStatsForToken(tokenid)` -> one hero's whole-combat `{ statid = total }`,
  summed across rounds (nested sub-tables like `conditionsInflicted` deep-merge). This
  is a freshly-built table, safe to keep.
- `liveEncounter:GetStatsForTokenByRound(tokenid)` -> one hero's raw `{ round1 = {...}, ... }`
- `liveEncounter:GetStatsForTokenInRound(tokenid, round)` -> one hero's `{ statid = total }`
  for a single numeric round

Except for `GetStatsForToken`, these are read-only views; only ever mutate through
`TrackHeroStats`.

## Build caveat (temporary)

The underlying engine binding `dmhub:IncrementInitiativeData` requires a C# build. Until
that build ships, `TrackHeroStats` calls safely no-op (the missing-method error is
caught by its `pcall` and logged via `dmhub.Debug`). After the build + relaunch, the
increments network for real. Writing the call sites now is safe regardless.
