# Healing stats for the encounter stat system

Status: **investigation complete, no code written.** This document is now the findings,
not a briefing. Written 2026-07-30 after the battle-log / `encounter_complete` work
(see `LIVE_ENCOUNTER.md`, "The battle log + `encounter_complete`"), investigated the
same day.

Everything below was traced through the codebase and re-measured against the last 8
days of live telemetry (2026-07-21 .. 2026-07-28). Where something is a guess it says
so. Section 2 corrects claims made in the first draft of this document.

---

## 1. The ask

`LiveEncounter` tracks 20+ per-hero combat stats (`STATS_TRACKING.md`). **Healing is
not one of them.** Work out whether it should be, and if so, what exactly gets
counted and where it hooks.

`STATS_TRACKING.md` uses `healingDone` in an illustrative example
(`LiveEncounter.TrackHeroStats(token.charid, "healingDone", 12)`). That is **example
prose only** -- no such stat is recorded anywhere. Fixing that misleading example is
a reasonable side-effect of this work.

## 2. The finding that reframes everything

**Draw Steel healing is a permission system, not a transfer system.** Almost no
ability moves Stamina from a healer to a target; it grants the target the right to
spend one of *their own* Recoveries. So the stat the game actually wants is
"**Recoveries granted to allies**", and direct healing is the rare special case.

**Today nothing can attribute a granted Recovery to the hero who granted it.** The
grant and the healing are two separate ability casts, on two different creatures,
usually resolving on two different machines, and the only thing that crosses between
them is a two-field payload that does not name the granter.

### The grant chain, verified end to end

| # | Hop | Where | Who is the caster |
|---|---|---|---|
| 1 | Granter's ability runs an `ActivatedAbilityInvokeAbilityBehavior` pointing at a standard ability (`Ally May Spend Recovery`, `Self Or Ally May Spend Recovery`, `Multiple Allies May Spend Recovery`, ...) | `DMHub Game Rules/AbilityInvokeAbility.lua:466` | granter |
| 2 | That standard ability is cast **as the recipient** (`invokerToken = target.token`), with `abilityClone.invoker` set to the granter | `AbilityInvokeAbility.lua:466-467`, `:521` | recipient (granter still recoverable via `ability.invoker`) |
| 3 | Its only behavior is `ActivatedAbilityCustomTriggerBehavior`, which dispatches `custom` with `{triggername = "Spend Recovery", triggervalue = <max recoveries>}` | `DMHub Game Rules/AbilityCustomTrigger.lua:140-157` | recipient -- **granter identity is dropped here** |
| 4 | The event is serialized (tokens -> `"charid:"`) and queued on the recipient's `triggeredEvents`, then drained on the recipient's controlling client | `DMHub Game Rules/Creature.lua:9561-9615`, `:4800-4834` | -- |
| 5 | The recipient's **global rule-mod** `TriggeredAbility` named "Spend Recovery" fires: `Replenish{mode=expend, resource=Recovery, quantity=mode}` then `Heal{roll="Recovery Value * Mode"}` | `data/objectTables/globalrulemods/triggers.yaml:11-59` (and `:60-110` for the `Prompt Recovery` variant) | recipient |
| 6 | `ActivatedAbilityHealBehavior:Cast` emits `healing_done` with `casterToken == target.token` | `DMHub Game Rules/ActivatedAbility.lua:3973`, `:4042-4078` | recipient |

Two trigger names exist and both land on hop 5:

- `"Spend Recovery"` (`may-spend-recovery.yaml`, id `f57cb6f7-...`) -- `mandatory = prompt_remote`,
  so it auto-spends when the recipient has no active controller and prompts the
  controlling player otherwise (`TriggeredAbility.lua:62-73`).
- `"Prompt Recovery"` (`prompt-spend-recovery.yaml`, id `3b05eb22-...`) -- `mandatory = false`,
  always prompts.

Usage is wide: 38 data files reference `May Spend Recovery` (51 references), plus 6
for `Ally May Spend Recovery`, 4 for `Prompt Spend Recovery`, and 8 more across the
other wrappers. This is the dominant healing mechanism in the game.

### Corrections to the first draft of this document

- **"Spend Recovery (2,116 events) = Self-heal, spending your own Recovery" is wrong.**
  That ability name is the *global trigger from hop 5*, which only ever fires from a
  grant. It is the "a grant was taken" counter. It mixes self-grants (Fury's
  "Spend 1 Ferocity: you can spend a Recovery") with ally-grants, and cannot tell
  them apart, because `source` is the spender in both cases. Re-measured:
  **2,118 events / 25,225 Stamina**, of which **2,077 have `source == target`** --
  by construction, not by coincidence.
- **"Arise (431 events) = Ally revive" is wrong.** `Arise` is undead **monster**
  self-healing: Skeleton 157, Ghoul 144, Soulwight 76, Armored Soulwight 53, Undead
  Servitor 1. Not hero healing at all.
- **The self-vs-ally split cannot be derived from `healing_done` today.** Only
  **566 of 5,458** records (10%) have `source ~= target`, and they are essentially
  all direct-heal abilities: My Life For Yours 347, Invoked Ability 61, Stolen
  Vitality 40, Regain Stamina 36, Restrained By Rafflos 20, Ally Recovery 20.
- **The manual portrait/diamond spend is invisible to `healing_done` but visible in
  `recovery_spend`:** 2,796 records in the same 8 days (1,867 `rest`, 929 `combat`),
  capped at 20/day/install. It calls `creature:Heal` directly rather than going
  through the heal behavior. So total Recovery spending is far larger than what
  `healing_done` sees, and the two tables do not overlap.

Net 8-day picture of `healing_done` by ability (5,458 records, ability -> events /
Stamina): Spend Recovery 2,118 / 25,225; Catch Breath 1,377 / 15,289; My Life For
Yours 672 / 9,153; Arise 431 / 3,568; Invoked Ability 185 / 1,855; Healing Potion
156 / 1,813; Endless Knight 129 / 1,816.

## 3. Every path that changes Stamina upward, and what it can tell us

| Path | Where | Recovery spent? | Granter known? |
|---|---|---|---|
| Granted Recovery (hop 5 above) | `globalrulemods/triggers.yaml` | yes, recipient's | **NO** (this is the whole problem) |
| Catch Breath maneuver | `globalrulemods/catch-breath.yaml` -- `Replenish{expend}` + `Heal{Recovery Value}`, both `applyto: caster` | yes, own | n/a (self) |
| Portrait diamond / TacPanel Recoveries box | `MCDMCharacterPanel.lua:3236-3292`, `:9146-9196` -- `Heal()` + `ConsumeResource()` directly | yes, own | n/a (self) |
| Hero-token substitute (2 hero tokens instead of a Recovery) | same two sites | **no** | n/a (self) |
| Shared/bonded Recoveries (Sacred Bond, Beastheart bond) | `Resource.lua:653-684`, menu at `MCDMCharacterPanel.lua:3106-3160` | yes, **someone else's** | yes -- the pool owner is explicit |
| Censor "My Life For Yours" | `data/objectTables/classes/censor.yaml:150-158` -- `Heal{Caster.Recovery Value}` + `Replenish{expend, applyto: caster}` | yes, **granter's own** | **yes** -- `casterToken` is the Censor, target is the ally |
| `Ally Heals Recovery Value` standard ability | `standardabilities/ally-heals-recovery-value.yaml` | yes, caster's | yes |
| Conduit "Healing Grace" | `Draw Steel Ability Behaviors/AbilityRecoverSelection.lua:594-635` | yes, recipient's | **NO -- and destroyed early, see the bug in section 4** |
| Direct-heal abilities (Healing Potion, Endless Knight, monster self-heals) | `ActivatedAbility.lua:3973` | no | yes (`casterToken`) |
| `ActivatedAbilitySetStaminaBehavior` / `creature.SetStaminaDirect` | `ActivatedAbility.lua:4093`, `MCDMCreature.lua:5625` | no | yes, but bypasses `Heal` entirely |
| Respite / rest / manual sheet edit | `Creature.lua:10080`, `RestDialog.lua:461`, `DSCharacterSheet.lua:2218` | varies | out of combat -- `TrackHeroStats` drops it anyway |
| Temporary Stamina grant | `DSTemporaryHitpoints.lua:5` -- already takes a `granterTokenId` | no | **yes, already** |
| Minions | `MCDMCreature.lua:5597-5600` -- `Heal` short-circuits to `SetCurrentHitpoints` on the squad pool | no | -- |

`creature.Heal` (`MCDMCreature.lua:5578`) is the single funnel for all of it, and its
signature is `(self, amount, note)`: **recipient only, no healer parameter.** `note`
is localised display prose (`"<casterName>'s <abilityName>"`) built for the stat
history tooltip -- do not parse it. So a hook in `Heal` can only ever produce a
`healingReceived` stat.

`creature.ConsumeResource` (`Resource.lua:616`) is the equivalent single funnel for
Recovery *spending*, and it already has a DS wrapper precedent for exactly this shape
of tracking (`MCDMCreature.lua:4889-4957`, the heroic-resource delta wrappers).

## 4. The one enabling change: name the granter in the trigger payload

Add a third field to the `custom` dispatch at `AbilityCustomTrigger.lua:147`:

```lua
local granter = self.invoker or casterToken.properties   -- read via ability:try_get("invoker")
target.token.properties:DispatchEvent("custom", {
    triggername = self.triggerName,
    triggervalue = value,
    triggersource = granter,
})
```

Why this works and costs nothing:

- `abilityClone.invoker` is already set to the granter by both invoke routes -- the
  local one (`AbilityInvokeAbility.lua:521`, whose `invokerToken` argument is the
  outer cast's caster) and the `runOnController` one (`AbilityInvocation` carries
  `invokerid`, resolved at `:1089` and passed through at `:1204`).
- The payload **survives the network hop for free**: `DispatchEvent` serializes
  creature-properties tables to `"charid:<id>"` (`Creature.lua:9561-9595`) and
  `RefreshToken` deserializes them back to live properties on the controlling client
  (`Creature.lua:4806-4818`). Pass `casterToken.properties` (a table), not the token
  userdata, so the local and remote paths yield the same type.
- Registering it as a `"Trigger Source"` symbol of type `creature` on the custom
  trigger (`TriggeredAbility.lua:637-652`) makes it usable from GoblinScript too, so
  content authors get provenance as a side benefit.
- Once it is in the payload it lands in the recipient's trigger cast symbols the same
  way `Trigger Name` / `Trigger Value` already do, so `options.symbols.triggersource`
  is readable from **both** behaviors of hop 5 -- the Replenish and the Heal.

**A transient (`_tmp_`) provenance stamp will NOT work.** `DispatchEvent` routes
through the networked `triggeredEvents` queue whenever the creature has an
`activeControllerId` -- even when that controller is this same client
(`Creature.lua:9555` vs `:9597`) -- so the spend can resolve on a machine that never
saw the grant. This rules out the `temporary_hitpoints_source` pattern that
`damagePrevention` uses.

### Bug found while tracing

`AbilityRecoverSelection.lua:602` passes the **recipient** as the invoke source:

```lua
ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(token, maySpendRecovery, token, "self", options.symbols, options)
```

so `abilityClone.invoker` becomes the recipient and the granter is destroyed one hop
*earlier* than everywhere else. This is the Conduit's **Healing Grace** -- the
flagship ally-healing ability of the flagship healer class. It should almost
certainly be `ExecuteInvoke(casterToken, maySpendRecovery, token, ...)`. Check
nothing downstream relies on `invoker == recipient` there before changing it (range
inheritance and `symbols.invoker` are the two consumers to check).

## 5. Recommended stat set

Split by attribution quality, cheapest first.

**Tier 0 -- zero Lua, data only.** Add a `track_stat` behavior
(`Draw Steel Ability Behaviors/AbilityTrackStat.lua`) with `Apply To = caster` to the
granter-side standard abilities (`ally-may-spend-recovery.yaml`,
`self-or-ally-may-spend-recovery.yaml`, `multiple-allies-may-spend-recovery.yaml`,
`ally-or-self-may-spend-recovery.yaml`). Gives `recoveriesOffered` on the granter
immediately. Counts **offers, not takes** -- a declined prompt still counts, and the
`numrecoveries` allowance is not what gets spent. Useful as a sanity denominator, not
as the headline number.

**Tier 1 -- one wrapper, no protocol change.**

- `recoveriesSpent` -- wrap `creature.ConsumeResource` for
  `CharacterResource.recoveryResourceId` in `MCDMCreature.lua`, measuring the real
  before/after delta of `RecoveriesAvailableToSpend()` exactly as the heroic-resource
  wrappers do (`MCDMCreature.lua:4929-4937`). Catches every path in the section 3
  table that says "yes". Strictly better than the derived
  `math.max(0, onsetRecoveries - currentRecoveries)` currently computed in
  `BuildBattleRecord` (`MCDMEncounter.lua:1825-1826`), which cannot be
  round-bucketed and silently absorbs any mid-combat Recovery refresh.
- `recoveriesGivenToAllies` -- in the recovery-sharing branch at
  `Resource.lua:661-680`, credit the **pool owner** whose Recovery a bonded ally
  spent. Small, fully attributable, and genuinely a support contribution.
- `healingDone` / `healingReceived` / `overheal` -- at
  `ActivatedAbility.lua:4042-4078`, beside the existing `track("healing_done", ...)`.
  Everything needed is already in scope: `healAmount` post-"Stamina Regain Halved",
  `damageBefore`, and the already-computed `overheal`. Follow the
  `damageDealt`/`overkill` precedent: credit `healAmount - overheal` as the counted
  amount. Runs once per target inside `completeRoll` on the resolving client.
  Skip `healingDone` when caster == target. **This is correct for direct heals and
  for the Censor pattern, and still credits the recipient for granted Recoveries
  until Tier 2 lands.**
- `tempStaminaGranted` -- `DSTemporaryHitpoints.lua:5` already receives
  `granterTokenId`. Arguably a fairer basis for **The Shield** than the current
  consumption-side `damagePrevention`, which only credits temp Stamina that actually
  got hit.

**Tier 2 -- the real number, needs section 4.**

- `recoveriesGranted` -- credited to `options.symbols.triggersource` at the
  Replenish-expend of a Recovery inside the recipient's trigger cast. This is the
  stat the ask is actually about: "how many Recoveries did you let your allies
  spend", counting only Recoveries actually **taken**.
- `healingDone` upgrade -- in `HealBehavior:Cast`, prefer
  `options.symbols.triggersource` over `casterToken` as the healer. One expression
  change, and it makes granted-Recovery healing attribute to the granter without
  touching any of the 38 data files that grant Recoveries.
- `selfHealing` -- the residual: caster == target and no `triggersource`. Keeps
  Catch Breath and the diamond out of the ally-healing numbers instead of swamping
  them (Catch Breath alone is 1,377 events / 15,289 Stamina in 8 days).

**Victory screen.** Once `recoveriesGranted` exists, a "Medic" / "Field Surgeon" role
ranking it is straightforward. Rank on `recoveriesGranted` (count), not on healed
Stamina -- Stamina amounts scale with the *recipient's* Recovery value, so ranking
Stamina rewards healing the highest-level ally rather than healing the most. Read
`project_victory_screen_role_semantics` and the header comment in
`DSVictoryScreen.lua` first: the role list is winner-only with a fatigue bias, and
`The Shield` (`DSVictoryScreen.lua:317-329`) is the model to copy for `minValue`
shape. Suggested `minValue` 2.

**Battle log.** Add `recoveriesGranted` to both the stored `heroes` entry and the
`analytics.heroStats` entry in `BuildBattleRecord`. Zero-valued stats are already
omitted (`BattleNonZero`), so it costs bytes only on heroes who actually healed --
worth it. Keep `recoveriesStart`/`recoveriesEnd` as they are; they answer a different
question (how depleted is the party).

## 6. Traps

1. **Do not rank granted Stamina.** See the Medic note above. Count grants.
2. **`healing_done`'s `source` is the spender, not the granter** -- any historical
   analysis of who healed is measuring the wrong thing. Do not backfill conclusions
   from it.
3. **`quantity = mode` on the global trigger**, so a hero offered 3 Recoveries who
   takes 1 spends exactly 1. The `triggervalue` allowance is an upper bound, never a
   count.
4. **The hero-token substitute heals without spending a Recovery**, so
   `recoveriesSpent` and `healingReceived` legitimately disagree there.
5. **Monster-side is automatic.** `TrackHeroStats` feeds `monsterStats` for non-hero
   actors with no call-site change, so undead self-healing (Skeleton/Ghoul `Arise`,
   3,568 Stamina in 8 days) starts being recorded the moment any of these hooks land.
   That is a legitimately interesting battle-log fact -- confirm it is wanted.
6. **Summons/retainers attribute to their owner automatically** (`STATS_TRACKING.md`
   guarantee 3). Desirable here: a Beastheart companion spending the beastheart's
   Recovery should credit the beastheart.
7. **`ActivatedAbilitySetStaminaBehavior` and `SetStaminaDirect` bypass `Heal`
   entirely.** Rare; audit what content uses them before deciding to ignore them.
8. Follow the `STATS_TRACKING.md` contract: call once per event on the authoritative
   client, do not wrap in your own `pcall`, do not call
   `dmhub:UploadInitiativeQueue()` after, stat ids match `^[a-zA-Z0-9_\-.:]+$`.

## 7. How to verify

- **Syntax, without disturbing the running app:** `mcp__dmhub__execute_lua` with
  `load(dmhub.ReadTextFile("C:\\dev\\dmhub\\draw-steel-codex\\<Module>\\<File>.lua"))`.
- **Live, without a real combat:** the stat readers can be temporarily monkey-patched
  and restored in a single `execute_lua` call -- that is how `BuildBattleRecord` was
  exercised. Restore in the same script.
- **For real:** start a combat with a Conduit (Healing Grace) or a Censor (My Life
  For Yours), heal an ally and yourself, and check `live:GetStatsForToken(charid)`
  mid-fight. Exercise the cross-machine case deliberately -- grant a Recovery to a
  hero controlled by a *different* player -- because that is the path the
  `triggersource` plumbing exists for. `/roles` prints role eligibility; the Stats
  Debugger (Development Tools) shows full per-hero totals.
- Do **not** auto-reload Lua -- David triggers reloads.

## 8. Files

| File | What is in it |
|---|---|
| `Draw Steel Core Rules/STATS_TRACKING.md` | The `TrackHeroStats` contract + every worked precedent. **Read first.** |
| `Draw Steel Core Rules/LIVE_ENCOUNTER.md` | Stats storage, the battle log, `encounter_complete`. |
| `DMHub Game Rules/AbilityCustomTrigger.lua` | Hop 3 -- the dispatch that must carry `triggersource`. |
| `DMHub Game Rules/AbilityInvokeAbility.lua` | Hops 1-2 -- where `abilityClone.invoker` is set (`:340`, `:521`, `:1204`). |
| `DMHub Game Rules/TriggeredAbility.lua` | `custom` trigger symbol registration (`:637`); `IsMandatory` / `prompt_remote` (`:62`). |
| `DMHub Game Rules/Creature.lua` | `DispatchEvent` + payload serialization (`:9506`), the controller-side drain (`:4800`). |
| `DMHub Game Rules/ActivatedAbility.lua` | `ActivatedAbilityHealBehavior:Cast` (`:3973`) -- the heal hook and the existing `healing_done` emit. |
| `DMHub Game Rules/AbilityReplenish.lua` | `ActivatedAbilityReplenishBehavior:Cast` (`:145`) -- the expend that spends the Recovery (`:587`). |
| `DMHub Game Rules/Resource.lua` | `creature.ConsumeResource` (`:616`) and Recovery sharing (`:653-684`). |
| `Draw Steel Core Rules/MCDMCreature.lua` | `creature.Heal` (`:5578`), `RecoveriesAvailableToSpend` (`:1505`), the heroic-resource wrapper precedent (`:4889-4957`). |
| `Draw Steel Core Rules/MCDMEncounter.lua` | `TrackHeroStats`, `BuildBattleRecord` (`:1660`), `GetHeroRecoveries` (`:1009`), `BattleLog`. |
| `Draw Steel Core Rules/MCDMCharacterPanel.lua` | The two manual spend sites (`:3236`, `:9146`) and the shared-Recovery menu (`:3106`). |
| `Draw Steel Ability Behaviors/AbilityRecoverSelection.lua` | Conduit Healing Grace, and the invoker bug at `:602`. |
| `Draw Steel Ability Behaviors/AbilityTrackStat.lua` | The `track_stat` authoring hook (Tier 0). |
| `Draw Steel Core Rules/DSTemporaryHitpoints.lua` | `GrantTemporaryStamina` (`:5`) -- already has the granter. |
| `Draw Steel UI/DSVictoryScreen.lua` | `ComputeHeroRolesInternal` -- where a Medic role would go; `The Shield` at `:317`. |
| `data/objectTables/globalrulemods/triggers.yaml` | The two global Spend Recovery triggered abilities (hop 5). |
| `data/objectTables/globalrulemods/catch-breath.yaml` | The Catch Breath maneuver. |
| `data/objectTables/standardabilities/*spend-recovery*.yaml` | The six grant wrappers. |

Analytics for cross-checking: the `codex-analytics` skill, tables `healing_done`,
`recovery_spend`, `use_ability` (`totalHealing`), cache at
`D:\dev\dmhub-admin\mcdm-cache\`.
