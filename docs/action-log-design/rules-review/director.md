# History rules review: the Director's side

Audit date 2026-11-04. Scope: Malice, villain actions, minions and captains, solos,
leaders, retainers, reinforcements and objectives, dynamic terrain and hazards, auras,
monster traits that fire on their own, end of encounter. Code was read, not run; nothing
was checked in the app.

Rule references: `CRM` = `ClaudeBridge/ClaudeRefMonsters.lua` (the Monsters book as
text), `MR` = `monster-reference.md` (stat blocks; also holds the Dynamic Terrain stat
blocks from line ~23700). Code paths are repo-relative. Data counts are from
`data/monsters/*.yaml` unless stated.

Every draft line below is a proposal for sign-off (COPY.md style: past tense, result
first, names not pronouns, Hero and Stamina capitalised, conditions lower case inside
sentences). IDs from COPY.md (W*, Y*, T*, C*) are cited where an existing pattern fits.

## Five codex facts that shape most rows

1. **Automatic triggers post no cast card.** `TriggeredAbility.mandatory` defaults to
   `true` (`DMHub Game Rules/TriggeredAbility.lua:967`) and
   `TriggeredAbility:ShowChatMessageOnCast()` returns `not self.mandatory` (`:2644`).
   So a trait that "just happens" (Loyalty Collar, Infernal Ichor, Toxiferous, aura entry
   effects) never names itself in the Action Log.
2. **Flat rule-text damage posts nothing at all.** Tier/rule text such as "2 fire damage"
   goes straight to `InflictDamageInstance` with no roll dialog
   (`Draw Steel Core Rules/MCDMAbilityBehavior.lua:330-414`); only dice damage opens a roll
   ("{ability}: Roll for Damage", `Draw Steel Ability Behaviors/AbilityDamage.lua:157`).
   A mandatory trait dealing flat damage is invisible unless an immunity or weakness
   changed it (`DamageModifierChatMessage`, `MCDMCreature.lua:5793`).
3. **Malice changes are recorded, but not in the log.** Every `SetMalice` appends a note
   to a `StatHistory` in the `globalResourcesv2` document (`DMHub Game Rules/Resource.lua:40-75`),
   shown only as a hover tooltip on the Director's action-bar Malice counter
   (`DrawSteelActionBar/DrawSteelActionBar.lua:3011`) and in the Encounter Wrangler.
   Only spending through `ConsumeResources` posts a card (`MaliceSpentChatMessage`,
   `Draw Steel Core Rules/DSResources.lua:103-277`).
4. **Minion deaths are confirmed, not computed.** The squad pool owes deaths; the
   attacker's controller (a player, when a Hero dealt the damage) clicks red skulls or
   "Choose for me" (direct targets first, then nearest), and squad-death triggers wait for
   those confirmations (`Draw Steel UI/DrawSteelTokenHud.lua:25-238`,
   `Draw Steel Core Rules/MCDMCreature.lua:6020-6270`). History must record the confirmed
   deaths, not the pool arithmetic.
5. **Winded, dying and killed are events with sounds, never log entries**
   (`MCDMCreature.lua:6720-6812`). `BeginRoundChatMessage` shows only "Draw Steel!" /
   "ROUND n" (`MCDMInitiativeBar.lua:6921-6985`); `StartOfTurnChatMessage` only "Start of
   Turn".

An existing structured source History can build on: `LiveEncounter` keeps per-token,
per-round stats and writes a permanent battle record at encounter end
(`Draw Steel Core Rules/MCDMEncounter.lua:2320-2400, 2925-2960, 3504`).

## Legend

- Row types: **Action row** (an action or Malice feature someone used); **Nested** (a
  triggered effect under what set it off); **Turn line** (start/end of turn, T16);
  **Round line** (round heading T5 or a compact line at the round boundary);
  **Compact line** (anything with no action); **Why** (detail card, R1 format: bold lead,
  then one sentence); **Caption** (T14).
- Players see it: what a player could know at the table. "If Malice shown" = the
  Director's choice the rules allow (CRM:785-790); the codex has a per-tracker
  public/private choice (`DMHub Game Hud/TableDice.lua:560`). Hidden tokens and hidden
  zones stay Director-only until revealed.

## Table

### Malice

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Malice at start of combat (average Victories + Heroes + round 1) | CRM:772-782 | Implemented: `Draw Steel UI/DSInitiativeRoll.lua:2880`, note "Start of Combat Malice" | No (Malice history tooltip only) | Round line, Round 1 heading: "Malice +9 → 9" (T5). Why on hover: **Start of combat** / "3 for the Heroes' average Victories, 5 Heroes, Round 1." | If Malice shown | Once per encounter |
| Malice at start of each round (Heroes + round number) | CRM:773-782 | Implemented: `MCDMInitiativeQueue.lua:550-584` (`NextRound`, `CalculateMaliceGain`), note "+N malice (Round r, h heroes present)" | No; the round card shows only "ROUND n" | Round line: "Malice +7 → 12" (T5). Why: **Round 2** / "5 Heroes + Round 2." | If Malice shown | Every round |
| A dead Hero stops generating Malice | CRM:783 | Implemented: dead Heroes are not counted (`CalculateMaliceGain`) | No | Why on that round's gain: **4 Heroes** / "The Fury is dead, so 4 Heroes count: 4 + Round 3." | If Malice shown | Rare |
| Malice gained from monster traits and abilities ("the Director gains N Malice") | MR:76 (Ajax), 2344 (chorogaunt), 3485 (Aurumvas), 4156, 22436, 23048 | Rule-text pattern sets Malice with the ability name as note (`MCDMAbilityBehavior.lua:1057-1064`). Some traits not wired: Aurumvas's Absorb Soul has no modifiers (`data/monsters/aurumvas.yaml:73`) | No | Nested under its cause: "Aurumvas's Absorb Soul: Malice +1." Compact line when there is no action (Alkestis at start of turn). | If Malice shown | Some encounters; several per round when present |
| Malice spent on an ability cost or enhancement | CRM:791-794 | `ConsumeResources` wrapper measures what left the pool (`DSResources.lua:257-277`) | Yes: `MaliceSpentChatMessage` "Spent N Malice" | Chip on the action row: "3 Malice" (T12); The numbers: "Cost: 3 Malice" (C3) | Yes (posted to everyone today) | Many per encounter |
| Monster AI paying Malice directly | (codex) | `Monster AI/MonsterAIWarDogs.lua:406, 883`, `MonsterAIMinotaur.lua:355`, `MonsterAIUndead.lua:494` call `SetMalice` directly | No (bypasses the Malice card) | Same as above: record each Malice change at its source, so every spend lands on its action row | As above | When those bands run under AI |
| Malice feature used at the start of a monster's turn (band "[Creature] Malice" features) | CRM:795-800, 821-822; MR:177-186 | `MaliceAbility` (`MCDMMonsterGroup.lua:160`); 217 features in `data/objectTables/monstergroup`; full-screen banner to all (`MCDMAbilityBehavior.lua:4001-4041`). Start-of-turn timing and one-per-turn limit: not found (the Monster AI applies its own one-per-turn rule) | Yes: cast card + Malice card (banner not logged) | Action row, new action type "Malice feature", first in that monster's turn: "Angulotl Daybringer · Rainfall · 7 Malice" | Yes | Most rounds |
| Basic Malice features: Brutal Effectiveness, Malicious Strike | CRM:819-834 | MaliceAbilities applying an ongoing effect (`data/objectTables/monstergroup/monster.yaml:10-67`). "Can't be used two rounds in a row, even by different monsters" (CRM:833-834): not found outside the Monster AI | Cast + Malice card when bought; the later extra damage or potency is not explained | Action row when bought. Why on the strike it powers: **Malicious Strike** / "It dealt 4 extra damage (the Ogre's highest characteristic, Might 4)." / **Brutal Effectiveness** / "M<2 became M<3." | Yes | Most encounters |
| Malice set by hand, by a cue, or by `/awardmalice` | (codex) | `MCDMCharacterPanel.lua:3831`, `DrawSteelActionBar.lua:3009`, `EncounterWrangler.lua:1445`, cue step `MCDMInitiativeBar.lua:3548`, `Codex Macros/Macros.lua:3024-3033` | No | Compact line: "Malice set to 12 by hand (was 9)." (C5 "set by hand") | Director only | Occasional |
| Unused Malice lost at end of encounter | CRM:783-784 | `SetMalice(0, "End of Combat")`: `MCDMInitiativeBar.lua:65`, `DSVictoryScreen.lua:1879` | No | Compact line in the encounter-end block: "Malice 6 → 0: unused Malice is lost." | If Malice shown | Once per encounter |

### Villain actions

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Villain action used (one per round, each once per encounter, at the end of another creature's turn) | CRM:576-601; MR:118-140 | `VillainActionState` (`DSResources.lua:288-351`), consumed when the cast completes (`DMHub Game Rules/ActivatedAbility.lua:4000-4022`); initiative-bar strip flashes only between turns when the budget is unspent (`MCDMInitiativeBar.lua:3110-3131`); banner (`:2761-2790`). Data: 70/69/70 VA 1/2/3. Monster AI uses VA 1-3 in rounds 1-3. Timing is guided, not enforced | Yes: ordinary cast card (banner not logged; nothing says "Villain Action") | Action row placed between the two turns, new action type "Villain Action 1/2/3" (T11 needs it): "Ajax · Phoenix Wing King · Villain Action 1". Turn heading stays with the turn it followed. | Yes | At most 1 per round, solo and leader encounters |
| Director overrides: Use anyway, Mark as Used, Reset this Villain Action | CRM:580-584 | `MCDMInitiativeBar.lua:2925-2970` (undoable doc writes) | No | Compact line: "Villain Action 2 marked used by hand." / "Villain Action 2 reset." | Director only | Rare |

### Minions and captains

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Squad acts as one on one initiative | CRM:848-852, 929-943 | Squads share an initiative id; one start-of-turn for all members (`MCDMInitiativeQueue.lua:768-790`) | Start of Turn card names the squad's tokens | Turn heading: "Goblin Warriors · Turn 6 · Enemy turn · 4 minions" (T7) | Yes | Every minion encounter |
| Damage reduces the shared Stamina pool; minions can't be winded, healed or gain temporary Stamina | CRM:853-864 | Pool kept in `_tmp_minionSquad` (`MCDMCreature.lua:1272-1443, 5400-5450`) | Partly: the attack's roll card only; the pool change is shown nowhere | What happened (W9): "Goblin Warriors took 5 damage: 1 of 4 minions killed." | Yes (the rules say share minion rules with players, CRM:844-847) | Every hit on minions |
| One minion dies per minion-Stamina of pool damage; the creature who dealt it picks which | CRM:865-876 | Not automatic: red skulls; the attacker's controller confirms or uses "Choose for me" (`DrawSteelTokenHud.lua:25-53, 172-238`). Deaths and `creaturedeath`/`kill` triggers fire on confirmation | No | Same W9 sentence, written when deaths are confirmed; captions "1 of 4 killed" / "Squad destroyed" (T14). Why (Y13): **Minions** / "Each minion in this squad has 5 Stamina, so 5 damage killed one." | Yes | Every minion encounter |
| Overflow: single-target damage worth two or more minions kills the nearest ones too | CRM:889-903 | Skulls offered on non-targets once damage overflows (`DrawSteelTokenHud.lua:106-109`); "Choose for me" takes the nearest | No | W9 plus Why: **Minions** / "12 damage is two minions' Stamina, so the nearest one died too." | Yes | Often |
| Area damage can kill only minions in the area | CRM:904-913 | Not verified: no area-only check found in the skull rules | No | Why: **Area ability** / "Only minions in the area can die: 3 were caught, so the squad lost 15 Stamina instead of 18." | Yes | Often |
| Minion immunity or weakness applied once to the squad | CRM:914-920 | Not found as a squad rule; immunity/weakness card posts per damage instance | Partly (per instance) | Why, once on the squad row: **Fire immunity 2** / "Applied once to the whole squad, as the last step." | Yes | Occasional |
| Squad signature action: one roll; a second or third minion on the same target adds its free strike value | CRM:944-960 | Implemented: squad target locks and gang-up (`MCDMActivatedAbility.lua:4210-4380`) | Yes (cast + roll); the gang-up extra is not explained | Action row "Goblin Warriors · Spear Charge"; W10 "Dwarf Fury took 6 damage from 2 minions."; Why: **2 minions** / "The second minion added its free strike, 2." The numbers (C4): "One roll for the whole squad." | Yes | Every minion turn |
| Squad critical hit: every participating minion may take another main action | CRM:961-963 | Implemented (`MCDMActivatedAbility.lua:4082`, `MCDMAbilityRollBehavior.lua:2358`) | Roll card shows the critical only | Chip "Critical"; nested line: "Critical hit: each minion that attacked can take another main action." | Yes | Rare |
| Minion maneuvers together; a minion who takes its own maneuver drops out of the squad's action | CRM:983-992 | "Maneuver or Action" rule and per-minion tracking (`MCDMCreature.lua:1236-1270`) | Cast cards | Action rows under the squad's turn; caption on the minion that dropped out: "Acted alone" | Yes | Occasional |
| Free strikes together: summed as one strike | CRM:993-998 | Not found | Each free strike separately | One nested row: "3 Goblin Warriors made free strikes: the Fury took 6 damage." | Yes | Occasional |
| Squad traits on minion deaths; deaths gated by traits; pool regrowth | MR:17448 (limbjumble); `data/monsters/troll-whelp.yaml` | `squadminiondeaths` trigger dispatched once per confirmed batch (`MCDMCreature.lua:6100-6112`); "Gated Minion Deaths" attribute (`MCDMCreature.lua:2800-2810`) | No (mandatory) | Nested under the kill: "The Troll Whelps' Group Appetite: ..." (content-driven); regrowth as a turn line: "Limbjumbles · Start of turn: the squad's Stamina was restored." | Yes | Rare |
| Captain attached to a squad | CRM:1033-1045 | Manual "Make Captain" (`MCDMCharacterPanel.lua:9076`, `MCDMMinion.lua:991`) | No | Compact line: "The Goblin Monarch is now the Goblin Warriors' captain." | Yes | Once per squad |
| With Captain benefit | CRM:1046-1050; MR:205 | Applied while the captain lives (`MCDMMinion.lua:2187-2217`, `MCDMCreature.lua:1433, 1998`); 115 With Captain entries in MR | No (passive) | Why: **With Captain** / "The Clawfish gain an edge on strikes while the Angulotl Daybringer is their captain." | Yes | Every squad strike with a captain |
| Captain lost; a new ally may become captain at the start of the next round | CRM:1051-1054 | Benefit stops when the captain dies; captain status is cleared only when the squad is wiped (`MCDMCreature.lua:1205-1232`); automatic re-captaining not found | No | Compact line: "The Goblin Warriors lost their captain." / Round line: "The Goblin Underboss is now the Goblin Warriors' captain." | Yes | Rare |

### Solos, leaders, retainers, summons

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Solo turns: two turns a round, not consecutive (Ajax three) | CRM:1644-1645; MR:25, 868 | `extraturns` attribute → `turnsPerRound` (`MCDMInitiativeQueue.lua:405-435`); boss-turn pips (`MCDMInitiativeBar.lua:7066-7090`). "Can't take turns consecutively": not found | Start of Turn card each turn; nothing says which turn | Turn heading: "Arixx · Turn 4 · Enemy turn · second turn this round" | Yes | Every round of a solo fight |
| End Effect: at the end of its turn, take N unreducible damage to end one save-ends effect | CRM:572-575, 1646-1649; MR:868 (and 22 leaders/solos with the trait) | Endturn trigger, prompted (`mandatory: false`), purge with `damageToSelf` (`data/monsters/arixx.yaml`, End Effect); AI decides via the shared End Effect handler | Partly: an "End Effect" cast card; which effect ended and the damage taken are not shown (a purge chat message is set in 7 of ~57 monster files) | Turn line (T16): "Arixx took 5 damage to end dazed · End of turn". Why: **End Effect** / "This damage can't be reduced." | Yes | Most solo and leader turns while affected |
| Solo Action (5 Malice: an extra main action, even while dazed) | CRM:1649-1651 | Malice ability ("Solo Action" in arixx.yaml) | Yes (cast + Malice card) | Action row, type "Malice feature": "Arixx · Solo Action · 5 Malice" ; nested: "Arixx took an extra main action." | Yes | Occasional |
| Leader and support buffs to allies (passive or start-of-turn) | CRM:656-662, 1600-1611; MR:1529 | Passive modifiers silent; granted actions are casts | Cast cards for granted actions only | Why lines naming the leader; nested rows for granted actions: "The Goblin Monarch's What Are You Waiting For? let 3 goblins shift and strike." | Yes | Leader encounters |
| Leader or solo triggered action | MR:110-116 (Ajax) | Director prompt (non-mandatory) or AI handler | Yes (cast card) | Nested (R3 Y11): **Ajax used a triggered action** / "Trigger: A creature within 10 squares regains Stamina." | Yes | Often |
| Retainer acts as part of its mentor's turn | CRM:35303-35306 | Grouped in initiative with the mentor (`MCDMCreature.lua:982-990`) | Cast cards credited to the retainer | Rows nested under the mentor's turn: "Fury · Turn 3 · Hero turn · with Human Warrior" | Yes | Every turn of a Hero with a retainer |
| Retainer shares the mentor's surges; spends at the mentor's highest characteristic | CRM:35316-35320 | Implemented (`MCDMCreature.lua:391-432`) | Not explained | Why (Y5 variant): **Spent 1 surge** / "From the Fury's surges: 3 extra damage (the Fury's Might 3)." | Yes | Occasional |
| Retainer dying and death (negative half Stamina); retainers can't use Malice | CRM:35313-35315 | Implemented (`MCDMCreature.lua:2748-2790, 3471-3476`) | No | Captions "Dying" / "Killed" (T14) | Yes | Rare |
| Summoned creatures arrive and act right after the summoner; one summon per summoner turn | CRM:723-727 | Summon behavior; summons removed at end of combat (`MCDMInitiativeBar.lua:67-68`). Once-per-turn limit: not verified | Cast card of the summoning ability only | Nested: "2 rotting zombies appeared next to the Fury." | Yes | Often |
| Heal via damage counts one instance only | CRM:728-733 | Not found | No | Why: **Heals via damage** / "Regained 8 Stamina: one target's damage, not the total." | Yes | Occasional |

### Reinforcements, objectives and the end of the encounter

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Reinforcements arrive (Director's choice; objective formulas such as "EV within 5 of those lost", "at the end of each round") | CRM:2105-2110, 2174-2182, 2484-2489, 1748-1754 | Encounter waves: the Director deploys from the initiative-bar strip once the arrival round is reached (`MCDMInitiativeBar.lua:3229-3236`, `MCDMEncounter.lua:4176-4187, 4381-4530`); scripts can deploy (`MCDMEncounter.lua:6265`). Objective formulas not automated | No | Round line: "Reinforcements arrived: 4 Goblin Warriors and a Goblin Underboss." | Yes once the tokens are visible | Some encounters, up to every round |
| Encounter cue fired (scripted beat: banner, group test, Malice) | (codex) | `MCDMInitiativeBar.lua:3380-3560` | No (banner only) | Compact line: "Cue: The bridge collapses." | Director only (players see its effects) | Scripted encounters |
| Objective met: victory, defeat or failure condition | CRM:1683-1720, 1840-1870 | `LiveEncounter:CheckVictory` (`MCDMEncounter.lua:4815-4885`): all defeated, non-minions defeated, leader defeated, outnumbered, half defeated, solo exhausted, destroy the thing; scripts can replace it. Durations and failure counts only via scripts | No (victory screen) | Compact line closing the encounter: "Victory: the Goblin Monarch was defeated. Each Hero earned 1 Victory." | Yes | Once per encounter |
| Enemies flee or surrender; Heroes flee; dramatic finish or event ending | CRM:1857-1870, 2499-2503 | End Combat prompt (victory screen, no victory, cancel) (`MCDMInitiativeBar.lua:108`) | No | Compact line: "Combat ended with no Victory awarded." | Yes | Once |
| Director changes a monster's Stamina; optional Last-Stand Stamina | CRM:2478-2483, 2508-2514 | Manual Stamina edits possible; Last-Stand Stamina: not found | No | Compact line: "The Ogre Goon's Stamina was set to 1 by hand." (C5) | Director only; players see the result through Monster Info | Occasional |
| End-of-encounter cleanup: Malice to 0, summons removed, map-anchored auras removed, `endcombat` triggers, "until the end of the encounter" effects end, battle record written | CRM:783-784 | `PerformEndCombat` (`MCDMInitiativeBar.lua:28-80`); `LiveEncounter.CompleteEncounter` (`MCDMEncounter.lua:3504`) | No | Compact block: "Encounter ended · Round 5 · Victory", then "Malice 6 → 0", "Summoned creatures left the battle." | Yes (Malice part if shown) | Once |

### Dynamic terrain and hazards

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Terrain object activates when a creature enters it or interacts (traps, pressure plates) | CRM:33693-33708; MR:23735 | ~23 targetable objects in `data/objects` (Brambles, Bramble Barricade, Snare Trap, Net Trap, Iron Jaws, Pillar, Field Ballista, Blade Wall, Fire DTO); `pressureplate` triggers; hidden-trap banner (`Targetable Objects/TargetableObject.lua:42-84`). Not found in data: Angry Beehive, Holy Idol, Tree of Might, Hypercube, Iron Dragon, Boiling Oil, Spike Trap | Banner for hidden traps only; dice damage shows a roll card | Nested under the move that set it off: "The Fury stepped on the Snare Trap and is restrained (save ends)." | Yes (a hidden trap once sprung) | Hazard encounters |
| Environmental hazard zones: entry or start-of-turn effect, or a power roll (lava, quicksand, toxic plants, flammable oil) | CRM:33784 onward | Environmental Keyword zones (`Draw Steel Core Rules/EnvironmentalKeyword.lua`; 17 keywords in `data/objectTables/environmentalkeywords` incl. lava, quicksand, toxic-plants, flammable-oil, burning-oil). Flat entry effect is mandatory; the power roll is a prompt | Power roll card only; a flat entry effect posts nothing | Nested under the move: "The Fury entered lava and took 5 fire damage." Turn line: "Lava · Start of turn: the Fury took 5 fire damage." | Yes (hidden zones: once revealed) | Hazard encounters |
| Terrain changes on its own between turns (fire spreads into oil, magma flow, bee swarm grows) | MR:23735, 23874; keyword `spreadsInto` | `EnvironmentalKeyword.SpreadZonesAtEndOfRound` (`EnvironmentalKeyword.lua:3395`) and object-keyword transform (`:3629`); magma flow and beehive not found | No | Round line at the round's end: "The burning oil spread to 2 more squares." | Yes if the zone is visible | Rare |
| Object destroyed (pillar topples, wall square broken) | CRM:33668-33672 (Stamina per object or square) | `TargetableObject.TakeDamage` fires `objectdestroyed` before removal (`TargetableObject.lua:128-168`) | Only if the destroy trigger is prompted (cast card) | Nested: "The Pillar was destroyed and toppled: the Fury took 6 damage." | Yes | Occasional |
| Siege engine or object operated by an adjacent creature (Field Ballista) | CRM:34721 onward | Operate mode, object as caster (see `DrawSteelActionBar/CLAUDE.md`, Operating objects) | Yes (cast card, object as caster) | Action row credited to the operator: "Fury used the Field Ballista: Release Bolt." | Yes | Rare |
| Start-of-round object effects (Holy Idol's d6, Tree of Might, Hypercube teleports, ram resets) | MR:24456, 24499, 24515, 24891 | `beginround` dispatched to objects (`MCDMInitiativeBar.lua:7044`, `DSInitiativeRoll.lua:2865`); these objects not found in data | No | Round line: "Tree of Might: each enemy with Might below 0 took 10 corruption damage." | Yes | Rare |
| Hidden objects found by search; deactivate tests | CRM:33682-33692, 33713-33721 | Hidden objects are `objectInvisibleToPlayers`; Deactivate via granted or map-feature abilities (`EnvironmentalKeyword.lua:3830-3845`); search reveal not verified | Cast/roll cards only | Action row (Search or Deactivate test) with nested "found the Snare Trap" / "the Snare Trap is deactivated" | Yes once found | Rare |

### Auras

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| Creature enters an aura or area, the first time in a round, or starts its turn there | MR:910, 947, 4533, 5840, 8064 | Aura triggers (`DMHub Game Rules/Aura.lua:36-61`): onenter, onfirstenterround, targetstartturnaura, casterstartturnaura, casterendturnaura; power roll = prompt + roll card; flat entry effect = mandatory | Roll card if rolled; otherwise nothing | Nested under the move: "The Fury entered the Fossil Cryptic's debris and took 3 damage." Turn line at start of turn. | Yes | Often where present |
| Passive aura modifiers (halved healing, banes on ranged) | MR:4533, 8064 | Modifiers | No | Why: **Withering aura** / "The Fury regained 4 Stamina instead of 8." | Yes | Often where present |
| Aura or area ends (end of round, caster gone, end of encounter) | (codex) | `Aura.CheckObjectAuraExpirationEndOfRound`, `Aura.RemoveOrphanedTurnScopedAuras` (`MCDMInitiativeBar.lua:7044-7050`); `RemoveExpiredMapAnchoredAurasAtEndOfCombat` (`:70`) | No | Compact line: "The storm of skulls ended." | Yes | Occasional |

### Monster traits that fire on their own (patterns)

Trigger ids used in `data/monsters` (top): losehitpoints 102, endturn 94, creaturedeath 79,
onenter 73, beginturn 70, zerohitpoints 59, inflictcondition 49, rollinitiative 41,
takedamage 36, dealdamage 30, movethrough 19, beginround 15, endcombat 6, dying 6,
winded 2, squadminiondeaths 1, endround 0 (1 in all data).

| Event or pattern | Rule (file:line) | Codex today | Logged today? | History should show (row type + draft line) | Players see it? | How often |
|---|---|---|---|---|---|---|
| On death: explode or splash (Loyalty Collar, Infernal Ichor, knight's bone barrier) | MR:10559, 19266, 20754 | `zerohitpoints` / `creaturedeath` triggers, mostly mandatory (e.g. `data/monsters/war-dog-aerocite.yaml:78-117`) | Partly: dice damage leaves a "Loyalty Collar: Roll for Damage" card; flat damage (Infernal Ichor 2 fire) nothing | Nested under the killing blow (W13): "The War Dog Commando's Loyalty Collar then hit the Fury for 3 damage." | Yes | Very often (war dogs, hobgoblins) |
| Cheat death: first time at 0 Stamina, stays at 1 or 10 and falls prone (Arise, Endless Knight) | MR:17929, 18159 | `zerohitpoints` trigger, Gold | No | Nested: "The Skeleton was reduced to 0 Stamina but has 1 Stamina and is prone." Why: **Arise** / "The first time it drops to 0 from damage that isn't fire or holy, it stays at 1 Stamina." | Yes | Often (undead) |
| Last act before dying: a free strike (Relentless, Bloodfire Burn) | MR:14143, 14288 | Prompted trigger (Relentless, Silver) | Cast card if used | Nested: "The Orc Bloodrunner made a free strike before dying." (Y11 for the Why) | Yes | Often (orcs) |
| An ally drops nearby: move, free strike, or Malice (Death Frenzy, Death Circle, Absorb Soul) | MR:3485, 9104, 9283 | Prompted `zerohitpoints` triggers; Absorb Soul not wired | Cast card if used | Nested under the kill: "The Gnoll Abyssal Summoner's Death Frenzy: moved 5 and made a free strike." | Yes (Malice part if shown) | Often (gnolls) |
| While winded: edges, immunity (Lethe, Defiant Anger, More... More...) | MR:2079, 3520, 13721 | Modifiers; becoming winded fires `winded` and a sound only (`MCDMCreature.lua:6809`) | No | Caption "Winded"; W4 "... and is now winded."; Why: **Lethe** / "The Bendrak is winded, so the strike gained an edge." | Yes | Very often (demons) |
| Triggered by becoming winded (first time) | MR:18665 | `winded` trigger (2 uses) | As its prompt or mandatory status | Nested under the hit that winded it | Yes | Rare |
| Start of the monster's turn: damage nearby, free strikes on shared spaces, Malice, allies end conditions | MR:224, 618, 1529, 2840, 23048 | `beginturn` triggers (70), mostly mandatory | Start of Turn card only; dice damage shows a roll | Turn line: "Clawfish · Start of turn: 2 lightning damage to the wet Fury." | Yes | Every round where present |
| End of the monster's turn: hide attempt, residue, End Effect | MR:412, 7466 | `endturn` triggers (94) | Cast card if prompted | Turn line: "Shadow Elf Scout · End of turn: hid." | Yes (that it hid) | Every round where present |
| Start of turn: a save-ends effect becomes end of turn (Otherworldly Grace) | MR:6191 | Not verified | No | Turn line: "Dawn Mage · Start of turn: dazed now ends at the end of this turn." | Yes | Often (high elves) |
| First time each round or turn: moving through deals damage; first fire damage boosts speed | MR:9473, 10829, 18014 | `movethrough` triggers (19), usage limits | No (mandatory) | Nested under the move: "The Specter moved through the Fury: 2 corruption damage." | Yes | Often |
| Start of each round: choose a stance, restrain someone, regain immunity | MR:145, 4868, 19585, 23534 | `beginround` triggers (15; Ajax's Tactical Stance prompted) | Cast card if prompted | Round line: "Ajax chose the Vanguard stance." | Yes | Every round (solo) |
| End of each round: burning objects, detonators, dust tests | MR:3785, 8029, 21138 | `endround` trigger exists but is used once in all data; "a burning object takes 1d6 fire damage at the end of each round": not found | No | Round line at the round's end: "The barrel took 4 fire damage from burning." | Yes | Occasional |
| Retaliation when attacked, grabbed or struck in melee (Toxiferous, Searing Skin) | MR:260, 8229 | `attacked` / `inflictcondition` triggers, mandatory, flat damage | No | Nested under the strike (W13): "The Angulotl Cleaver's Toxiferous then hit the Fury for 1 poison damage." | Yes | Often |
| Start of the encounter: choose a rival, set a field | MR:15315, 16868 | `rollinitiative` triggers (41) | No | Compact line under the Draw Steel! banner: "The Rival Conduit chose the Censor as its rival." | Yes | Once per encounter |
| End of the encounter traits | (data) | `endcombat` triggers (6) | No | Compact line in the end block | Yes | Rare |

## Gaps in rules automation found along the way (not History work, but History will show the result)

Not found: Malicious Strike's "not two rounds in a row" outside the Monster AI; Malice
features limited to the start of a turn and once per turn; "I Am the Captain Now";
solo "can't take turns consecutively"; minion "free strike together"; heal-via-damage
single instance; Last-Stand Stamina; burning objects at the end of each round; Aurumvas's
Absorb Soul; most book dynamic terrain objects. Not verified: area-only minion deaths,
once-per-squad immunity, Otherworldly Grace, search revealing hidden objects.
