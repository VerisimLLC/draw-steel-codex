# LiveEncounter — design notes

Context notes for working on the DMHub / Draw Steel Codex `LiveEncounter` system. This
describes how a "live encounter" is modeled, created, stored, networked, and surfaced
in the UI. Hand this to a fresh session before touching encounter / initiative code.

## TL;DR

- `Encounter` is the **authored** definition of an encounter (which monsters/groups,
  how it scales with hero count, optional reinforcement waves). It is content stored
  in the `encounters` data table and embedded in journals via the `RichEncounter`
  rich tag.
- `LiveEncounter` is the **runtime state** of an encounter that is currently being
  played. It derives from `Encounter` and is literally a deep copy of an authored
  `Encounter`, re-typed as a `LiveEncounter`.
- An initiative queue holds exactly one live encounter in its `liveEncounter`
  field. Combats started "Custom" (no authored encounter) get a **basic empty
  `LiveEncounter`** (`LiveEncounter.CreateEmpty()`), not `false` — every new
  queue is created carrying one. Only queues persisted before this convention
  can still hold `false`/`nil`, which is why readers stay defensive.

Both types are defined in **`Draw Steel Core Rules/MCDMEncounter.lua`**.

## Type relationship

```lua
LiveEncounter = RegisterGameType("LiveEncounter", "Encounter")
LiveEncounter.tableName = "liveencounters"
```

Because it derives from `Encounter`, a `LiveEncounter` **inherits all of Encounter's
fields and methods** and should be treated as an `Encounter` with extensions:

- Fields: `name`, `monsters`, `groups`, `waves`, `saveAppearances`, ...
- Methods: `CountEDS`, `Describe`, `CloneForNumberOfHeroes`, `AddMonster`, `AddGroup`,
  `MainMonster`, `AdjustedMonsterQuantity`, `AddWave`, `WaveRoundText`, ...

> Important: a `LiveEncounter` **is** the encounter data. There is **no nested
> `.encounter` field**. Access `liveEncounter.name` / `.groups` / `.monsters` directly
> and call the inherited methods (`liveEncounter:Describe()`, etc.). (An earlier draft
> wrapped the encounter in a `.encounter` field; that design was replaced.)

## Construction — the deep-copy + re-type idiom

```lua
function LiveEncounter.Create(encounter)
    local result = DeepCopy(encounter)
    result.typeName = "LiveEncounter"
    result.tableName = LiveEncounter.tableName
    setmetatable(result, LiveEncounter.mt)
    return result
end
```

This mirrors the established re-type idiom in the codebase
(`DMHub Game Rules/TriggeredAbility.lua` → `TriggeredAbility:GenerateManualVersion`,
which does `clone.typeName = ...` + `setmetatable(clone, ActivatedAbility.mt)`).

Why each line matters:

- `DeepCopy(encounter)` — copies all the encounter's data. `DeepCopy`
  (`DMHub Utils/Utils.lua`) **preserves the source metatable**, so the copy comes out
  as an `Encounter`. It also preserves `_tmp_` keys by reference and skips them when
  copying. The deep copy decouples live state from the authored definition — mutating
  the `LiveEncounter` never touches the saved `Encounter`.
- `result.typeName = "LiveEncounter"` — game-type instances carry a **raw** `typeName`
  field that the serializer reads. Without overwriting it, the copy would still
  serialize/deserialize as an `Encounter`. This is the line that actually makes it a
  different type on the wire.
- `result.tableName = LiveEncounter.tableName` — so the instance reports the
  `liveencounters` table name rather than `encounters`. (Largely cosmetic here —
  live encounters are not stored in a data table — but keeps the type honest.)
- `setmetatable(result, LiveEncounter.mt)` — switches method/field resolution to the
  `LiveEncounter` type (which chains to `Encounter`), so inherited and live-only
  methods resolve correctly. `<Type>.mt` is the metatable created by
  `RegisterGameType`.

### Display name

```lua
function LiveEncounter:GetName()
    return self:try_get("name")
end
```

Just the (copied) encounter name. `try_get` returns `nil` if name was never set, so
callers should treat `nil` as "unnamed".

## Where it lives: the initiative queue

`InitiativeQueue` (defined in `Draw Steel Core Rules/MCDMInitiativeQueue.lua`) has:

```lua
InitiativeQueue.liveEncounter = false   -- type default, for deserializing old queues
```

`InitiativeQueue.Create()` sets the field to `LiveEncounter.CreateEmpty()` on
every new queue, so at runtime the field is a `LiveEncounter` object for any
queue created since that convention landed (including Custom combats and
non-combat game-mode queues like respite/downtime, where the empty encounter is
inert: no objective, no boss bar, no reinforcements). The `false` type default
only matters for old persisted queues. Initiative queues are stored **per map** in the game document
(`gameDetails.initiativeQueues[mapid]`) and networked to all clients, so the
`liveEncounter` (and its full copied encounter data) rides along with the queue.

Access from Lua via `dmhub.initiativeQueue` (the queue for the current map; `nil` when
there is no initiative). Read defensively:

```lua
local liveEncounter = dmhub.initiativeQueue and dmhub.initiativeQueue:try_get("liveEncounter")
if type(liveEncounter) == "table" then
    -- it's a LiveEncounter
end
```

Use `try_get` + a `type(...) == "table"` check rather than truthiness, because the
field can be `false`, `nil` (older queues that predate the field), or a table.

## How it gets set: "Draw Steel!" flow

All in `Draw Steel UI/DSInitiativeRoll.lua`:

1. `ShowCombatSetupDialog(selectedTokens)` builds the combat setup dialog. At the top
   it shows an **encounter dropdown** populated by `Encounter.GetEncountersOnCurrentMap()`
   (see below). The first option is `Custom` (default); the rest are the encounters
   found on the map. The dropdown option ids are `custom` and `encounter-<N>`, where
   `<N>` indexes into the dialog-local `m_encountersOnMap` list. The current choice is
   tracked in the dialog-local `m_selectedEncounterId`.
2. On **Draw Steel!** press, the chosen encounter is resolved and stashed in a
   module-local carrier `g_selectedEncounterOpenInitiative` (nil for Custom) — this
   mirrors the existing `g_selectedTokensOpenInitiative` pattern, because the queue is
   actually created later, in a different function.
3. The Draw Steel banner coroutine (controller/DM only) creates the queue:
   ```lua
   info.initiativeQueue = InitiativeQueue.Create()  -- carries an empty LiveEncounter already
   ...
   if g_selectedEncounterOpenInitiative ~= nil then
       info.initiativeQueue.liveEncounter = LiveEncounter.Create(g_selectedEncounterOpenInitiative)
   else
       --Custom combat: build a basic live encounter and seed onsetMonsterCount
       --from the actual non-minion monster tokens entering combat (the empty
       --encounter has no authored monsters, and without a nonzero onset count
       --CheckVictory short-circuits: "no monsters -> nothing to win").
       local live = LiveEncounter.Create(Encounter.new())
       live.onsetMonsterCount = <count of non-minion monsters entering combat>
       info.initiativeQueue.liveEncounter = live
   end
   info.initiativeQueue.liveEncounter:RecordOnsetHeroes(g_playerTokensOpenInitiative)
   g_selectedEncounterOpenInitiative = nil
   Commands.rollinitiative()
   ```
   `Commands.rollinitiative()` ends in `info.UploadInitiative()`, so setting
   `liveEncounter` **before** that call is what gets it uploaded/networked.

## How encounters on the map are discovered

`Encounter.GetEncountersOnCurrentMap()` (in `MCDMEncounter.lua`) returns a list of the
encounters authored into the journals available on the current map. It searches two
sources, deduplicated by document id:

1. **Info bubbles on the current map** (searched first, so they win the
   default-encounter inference in the combat setup dialog):

```
dmhub.infoBubbles            -- info bubbles on the CURRENT map (engine-provided)
  -> bubble.document          -- an InfoDocument
  -> :GetMarkdownDocument()   -- the referenced journal markdown document
  -> :GetReferencedAnnotations()  -- annotations actually present in the text
  -> filter typeName == "RichEncounter"
  -> annotation.encounter     -- the authored Encounter
```

2. **Game-wide journal documents**: every markdown document in the journal table
   (`dmhub.GetTable(CustomDocument.tableName)`, via `unhidden_pairs`) whose folder
   chain roots at an accessible root (`CustomDocument.GetAccessibleRoots()` +
   `IsDocInAccessibleRoot`) — for the Director that is Shared Documents, Private
   Documents, Templates, and the current map's folder. Documents filed under
   *other* maps' folders are excluded. These documents are harvested with the same
   `GetReferencedAnnotations` pipeline, sorted by document name for a stable
   dropdown order.

Each returned entry is `{ name, encounter, richEncounter, bubbleid, docid }`, where
`bubbleid` is nil for encounters found in game-wide journal documents.

Key subtlety: it uses `MarkdownDocument:GetReferencedAnnotations()` (in
`DocumentSystem/MarkdownDocument.lua`), **not** the raw `document.annotations` table.
A document's `annotations` table can contain stale/orphaned entries (e.g. an
`encounter-1` left behind after a duplicate tag was deleted, or an empty `encounter:`
tag) that no longer appear in the rendered journal. `GetReferencedAnnotations`
tokenizes the content with the engine's `BreakdownRichTags` and resolves tags to
annotation keys with the same `-N` de-duplication the renderer uses, so only
annotations actually referenced by the text are returned. Iterating the raw table
instead reintroduces phantom "Encounter" entries.

## How it surfaces in the UI

The initiative bar round label (`Draw Steel Core Rules/MCDMInitiativeBar.lua`, the
`refresh` on the round `gui.Label`, ~line 2095) prefixes the encounter name when a
live encounter is present:

```lua
local roundText = string.format('Round %d', info.initiativeQueue.round)
local liveEncounter = info.initiativeQueue:try_get("liveEncounter")
if type(liveEncounter) == "table" then
    local name = liveEncounter:GetName()
    if name ~= nil and name ~= "" then
        roundText = string.format('%s - %s', name, roundText)
    end
end
element.text = roundText
```

So it reads e.g. `Goblin Guards - Round 1` when an encounter was chosen, or plain
`Round 1` for Custom / no live encounter.

## Per-hero statistics (`stats` + `IncrementStat`)

A live encounter accumulates **per-hero statistics** for the duration of the fight.
`LiveEncounter.Create` initializes an empty `stats` table; it rides inside the live
encounter (and therefore inside the networked initiative queue) like every other live
field. The shape is:

```
stats = {
  ["<heroTokenid>"] = {
    kills = 3,             -- regular monsters this hero killed
    minionKills = 7,       -- individual minions this hero killed (see below)
    damageDealt = 40,      -- post-resistance damage this hero dealt
    damageTaken = 18,      -- actual stamina lost (temp-stamina-absorbed excluded)
    damagePrevention = 12, -- damage this hero's granted temp stamina absorbed (see below)
    spacesMoved = 23,      -- tiles voluntarily moved in combat (move/shift; see below)
    monsterDamage = { ["<monsterid>"] = 8, ... },
    tierRolls = { tier1 = 2, tier2 = 5, tier3 = 1 },  -- power-roll tier tally
    ...
  },
  ...
}
```

`damageTaken` and `damagePrevention` are split in `creature.InflictDamageInstance`
(`Draw Steel Core Rules/MCDMCreature.lua`). Temporary stamina is consumed inside
`TakeDamage` *after* the base call computes `damageDealt`, so the wrapper snapshots
`TemporaryHitpoints()` before/after and divides the landed damage: the part the temp
stamina absorbed is `damagePrevention` and the rest is `damageTaken` (so temp-absorbed
damage no longer inflates `damageTaken`). `damagePrevention` is credited to **whoever
granted** the temp stamina, not the creature that was protected -- so a hero who shields
a non-hero ally still gets the credit. The grantor is recorded as
`creature.temporary_hitpoints_source` when temp stamina is granted (the
`grant_temporary_stamina` behavior and ongoing-effect grants pass `options.source` to
`SetTemporaryHitpoints`); a creature has at most one temp-stamina source at a time, and
it is cleared when the pool is depleted.

`kills` and `minionKills` are recorded in `creature.TakeDamage`
(`Draw Steel Core Rules/MCDMCreature.lua`), which runs once on the resolving client.
A **regular monster** death is counted at the existing death-transition (where the
attacker's `"kill"` trigger fires) as `+1` `kills`, guarded to non-hero victims.
**Minions** share a squad stamina pool and return from `TakeDamage` before that path,
so they are counted separately: each hit tallies how many single-minion stamina bands
it emptied (`hpBefore -> hpBefore - amount`) and credits the attacker that many
`minionKills`. This is what makes "multiple minions killed by one blow" count
correctly, and overkill past the last minion does not over-count.

`spacesMoved` accumulates the tiles a hero moves under their own power during combat.
It is recorded in the DS `creature:Moved` wrapper (`Draw Steel Core Rules/MCDMCreature.lua`)
by adding `path.numSteps` each move, gated to the mover's own turn (`IsOurTurn()`, the
same gate the base uses for movement-cost accounting). Forced movement (pushes/pulls/
slides) and teleports are excluded -- only normal movement and shifting count.

The `tierRolls` sub-table tallies how many power rolls this hero resolved to each
tier (`tier1`/`tier2`/`tier3`). It is recorded once per resolved power roll in
`ActivatedAbilityPowerRollBehavior:Cast` (`Draw Steel Core Rules/MCDMAbilityRollBehavior.lua`),
using the same effective tier the cast applies (a manual amend / test `overrideTier`
wins over the natural dice tier). Resistance rolls (`CastResistance`) are a separate
path and are not counted.

Each hero gets a sub-table keyed by their tokenid (`token.charid`). Stat ids may be
plain (`"kills"`) or a `/`-separated path (`"monsterDamage/<monsterid>"`); a path
implies an intermediate sub-table that the **backend creates automatically**.

### Recording a stat — `LiveEncounter.TrackHeroStats(tokenid, statid, quantity)` (preferred)

This is the **safe, static entry point** for combat/damage code. It finds the current
live encounter for you, validates everything, and never throws:

```lua
LiveEncounter.TrackHeroStats(token.charid, "kills")                        -- +1
LiveEncounter.TrackHeroStats(token.charid, "monsterDamage/"..monsterid, 8) -- +8
```

It does nothing (cleanly) unless **both**: (1) the token resolves to a hero (a summon
is followed up to its summoner), and (2) we are in combat with a `LiveEncounter` in
which that hero is participating. It is wrapped in `pcall`, so it is safe to call
unconditionally from hot paths — callers do not need to find the encounter, check for
combat, or guard the token type. Prefer this over the instance method below; reach for
the instance method only when you already hold the `LiveEncounter` for another reason.

### Writing a stat — `LiveEncounter:IncrementStat(tokenid, statid, quantity)`

```lua
encounter:IncrementStat(token.charid, "kills")                        -- +1
encounter:IncrementStat(token.charid, "monsterDamage/"..monsterid, 8) -- +8
```

`quantity` defaults to 1. The increment is **routed through the server's atomic
increment** (`dmhub:IncrementInitiativeData`, a thin wrapper over
`DataStore.IncrementData` that targets `initiativeQueues/<currentMapId>/liveEncounter/...`).
On Durable Object backends this is genuinely atomic, so concurrent writers (multiple
players recording damage at once) can't lose updates; on Firebase it downgrades to a
read-modify-write. The resolved value rides back through the normal initiative-queue
broadcast — `IncrementStat` does **not** mutate the local `stats` table or call
`UploadInitiativeQueue` itself, so do not wrap it in an upload.

### Attribution rules (`LiveEncounter:ResolveStatHero`)

A stat is only recorded for a **valid hero (type `"character"`) in the current combat**;
every other token is silently ignored. The resolution, in `ResolveStatHero(tokenid)`:

1. **Summon attribution.** Summoned creatures (animal companions, minions a character
   summoned, etc.) attribute their stats to the hero that summoned them. The resolver
   walks `token.summonerid` (the summoner's tokenid) up to the root of the summon chain
   (cycle-guarded, capped at 16 hops).
2. The root must be a hero (`token.properties:IsHero()`).
3. The root must be an active combatant — it must appear in `GetBattleHeroTokens()`
   (the deduped hero tokens in the live initiative queue). Membership confirms both
   "is a hero" and "is in this encounter".

If any check fails, `IncrementStat` returns without writing. The stat is keyed by the
**resolved hero's** tokenid, not the token originally passed — so a companion's damage
lands under its summoner.

### Reading stats

- `LiveEncounter:GetStats()` — the whole `{ tokenid -> {statid -> total} }` table
  (empty table if none yet).
- `LiveEncounter:GetStatsForToken(tokenid)` — one hero's `{statid -> total}` map.

Both are read-only views; mutate only through `IncrementStat`.

### Cross-component wiring

| Layer | File | What |
|---|---|---|
| Engine (C#) | `Assets/Scripts/LuaInterface.cs` | `dmhub:IncrementInitiativeData(path, amount)` — builds the absolute `/GameDetails/<gameid>/initiativeQueues/<currentMapId>/<path>` and calls `DataStore.IncrementData`. |
| Stub | `draw-steel-codex/Definitions/dmhub.lua` | LuaLS signature for `IncrementInitiativeData`. |
| Rules (Lua) | `Draw Steel Core Rules/MCDMEncounter.lua` | `stats` init in `Create`; `TrackHeroStats` (static, safe), `IncrementStat`, `ResolveStatHero`, `GetStats`, `GetStatsForToken`. |

## Gotchas & conventions

- **No `.encounter` sub-field.** Treat a `LiveEncounter` as an `Encounter`.
- **Serialization hinges on raw `typeName`.** If you write new code that clones/retypes
  encounters, set the raw `typeName` field (not just the metatable), or it will
  round-trip as the wrong type.
- **Read `liveEncounter` defensively** (`try_get` + `type == "table"`): every
  new queue carries a `LiveEncounter`, but queues persisted before that
  convention can still hold `false` or `nil`.
- **Inherited `waves`.** `Encounter` now supports reinforcement `waves`
  (`Encounter.AddWave` / `WaveRoundText`, and `Describe` annotates wave monsters).
  `LiveEncounter` inherits all of this for free — useful when live combat needs to know
  which groups arrive on later rounds.
- **Live wave deployment.** `LiveEncounter` adds runtime wave state on top of the
  inherited `waves`:
  - `deployedWaves` — a set `{ [waveid] = true }` of waves already deployed or
    dismissed. Empty by default; copy-on-write via `MarkWaveDeployed` so the shared
    type default is never mutated. **This is what governs whether a wave's deploy
    button still shows.**
  - `IsWaveDeployed(waveid)` / `MarkWaveDeployed(waveid)` — query / set the deployed
    flag. After `MarkWaveDeployed`, network the change (the live encounter rides inside
    the queue, so `info.UploadInitiative()` / `dmhub:UploadInitiativeQueue()`).
  - `WaveHasMonsters(waveid)` — true if any group assigned to the wave has monsters.
  - `GetAvailableWaves(currentRound)` — waves not yet deployed, holding monsters, and
    whose arrival round is reached (numeric round arrives at `currentRound >= round`;
    `"every"` is available on any round).
  - `DeployWave(waveid, initiativeQueue)` — spawns every group assigned to the wave
    (prefers authored `group.spawnlocs`, else a grid around `dmhub.cameraPosition`),
    registers each spawned group with the queue via `SetInitiative(groupid, 0, 0)`,
    and marks the wave deployed. Returns the number of tokens spawned. Mirrors the
    per-group spawn logic in `RichEncounter.spawn` (which itself skips wave groups so
    reinforcements are *not* placed up front).
  - **Position round-trip via token tags.** `DeployWave` tags every spawned
    reinforcement token with three persistent creature properties:
    `encounterWaveId` (the wave guid), `encounterGroupIndex` (stable: the live
    encounter is a plain deep copy of the authored encounter, so group order matches),
    and `encounterSpawnSlot` (the flat spawn-order slot). `RichEncounter`'s "Save and
    Remove" (`despawn`) then **scans `dmhub.allTokens`** for tokens tagged with one of
    this encounter's wave ids and banks each one's current `token.loc` into the
    **authored** encounter's matching wave `group.spawnlocs[slot]` (then deletes them).
    Scanning the map -- rather than reading the live encounter -- means the save works
    whether or not combat is still active and regardless of which live encounter is
    current (an earlier live-encounter-keyed approach silently saved nothing when
    combat had ended or a different combat was live). The full round trip: deploy (grid
    fallback the first time) -> DM repositions -> Save and Remove banks positions into
    the authored encounter -> next combat's fresh live encounter deep-copies them ->
    `DeployWave` reads `group.spawnlocs[slot]` and spawns there.

  The DM-facing UI is the **Reinforcements strip** in
  `Draw Steel Core Rules/MCDMInitiativeBar.lua` (mounted just below the villain action
  strip): a deploy button per available wave, styled with the same `vaDrawer` chrome.
  Click deploys; right-click → Dismiss marks the wave deployed without spawning.
- **Custom buttons (script-driven).** `LiveEncounter` can also carry
  `customButtons` — action buttons that are *not* authored into the encounter but
  added/removed at runtime by code (map-object scripts, macros). Surfaced by the
  **Encounter Actions strip** in `MCDMInitiativeBar.lua` (DM-only, below the cues
  strip, same `vaDrawer` chrome). A button is a flat table of scalars:
  `{ id, name, summary, tooltip, command, sticky }`. `command` is a chat-style
  command line without the leading slash (e.g. `"gnollarmy summon"`), executed via
  `dmhub.Execute` on the Director's client when clicked. By default a button is
  one-shot: the strip removes it (and uploads the queue) *before* executing, so a
  slow interactive command can't be double-fired; `sticky = true` keeps it until
  code removes it. Right-click → Dismiss removes without executing.
  - Instance API (mutations don't upload; network afterwards):
    `GetCustomButtons()`, `GetCustomButton(id)`, `SetCustomButton(button)`
    (upsert by id, copy-on-write, returns true if changed),
    `RemoveCustomButton(id)`.
  - Static safe helpers (find the current queue's live encounter, mutate, and
    upload via `dmhub:UploadInitiativeQueue()`; no-ops cleanly when combat is
    inactive or the queue predates the always-present live encounter):
    `LiveEncounter.EnsureCustomButton(button)`,
    `LiveEncounter.DismissCustomButton(id)`. Both are pcall-wrapped and return
    true on change. Call on the Director's client only.
  - Custom combats carry an empty `LiveEncounter` (see above), so buttons work
    there too. Only queues persisted before the always-present convention can
    lack one; scripts that must support those should offer a slash-command
    fallback.
- **Lua-only changes** reload at runtime; no C# rebuild needed. Files are ASCII-only;
  forward-declare self-referencing locals (see `draw-steel-codex/CLAUDE.md`).

## Key files

| File | Role |
|---|---|
| `Draw Steel Core Rules/MCDMEncounter.lua` | `Encounter` + `LiveEncounter` types, `LiveEncounter.Create`, `Encounter.GetEncountersOnCurrentMap` |
| `Draw Steel Core Rules/MCDMInitiativeQueue.lua` | `InitiativeQueue` type; `liveEncounter` field default |
| `Draw Steel UI/DSInitiativeRoll.lua` | Combat setup dialog, encounter dropdown, queue creation that sets `liveEncounter` |
| `Draw Steel Core Rules/MCDMInitiativeBar.lua` | Round label that shows `"<Encounter> - Round N"` |
| `DocumentSystem/MarkdownDocument.lua` | `GetReferencedAnnotations` (content-referenced annotation resolution) |
| `DocumentSystem/RichEncounter.lua` | `RichEncounter` rich tag that wraps an `Encounter` in a journal |
| `Draw Steel V/EncounterPanel.lua` | Encounter-creator UI (`Encounter.Editor` / `CreateEditorDialog`) |
