# History rules review: core rules

Scope: the events the Draw Steel core rules create (Heroes book Ch. 1 The Basics, Ch. 5
general ability rules and conditions, Ch. 9 Tests, Ch. 10 Combat, Ch. 11 Negotiation,
Ch. 12 Downtime Projects, the glossary, and the general Heroic Resource pattern). Class
features and monster/Director rules are covered by the other two reviews. Written
2026-11-04 against branch `feature/hero-sheet-party-picker`.

## How to read this

- **Rule** cites `H:<line>` = `ClaudeBridge/ClaudeRefHeroes.lua`.
- **Codex today** cites code with folder shorthand: `DGR/` = `DMHub Game Rules/`,
  `DSCR/` = `Draw Steel Core Rules/`, `DSUI/` = `Draw Steel UI/`, `DSV/` = `Draw Steel V/`,
  `DT/` = `Downtime Projects/`, `data/` = `data/objectTables/`. Most rules are global rule
  mods (`data/globalrulemods/*.yaml`) or condition rows (`data/charconditions/*.yaml`)
  implemented as triggered abilities.
- **Logged today?** is the Action Log (`ChatPanel/ActionLogPanel.lua`, which shows every
  non-chat message: rolls and custom messages). Three things decide whether an automatic
  rule shows up:
  - a triggered ability posts a cast card only when `mandatory` is `false` (prompted)
    (`DGR/TriggeredAbility.lua:2644`); automatic rule triggers are silent;
  - a damage/replenish/purge/heal behavior posts its own card only when its
    `chatMessage` field is set (`Draw Steel Ability Behaviors/AbilityDamage.lua:56`,
    `DGR/AbilityReplenish.lua:718`, `DGR/AbilityPurgeEffects.lua:286`,
    `DGR/ActivatedAbility.lua:5136`);
  - per-target notes recorded on a cast card (`RecordTokenMessage`) render only as hover
    tooltips, and not at all for the caster (comment at `DGR/ActivatedAbility.lua:5138`).
- Several silent changes are still recorded somewhere, just not in the log: per-stat
  histories (`creature:GetStatHistory`, `DGR/Creature.lua:1899`; stamina, temporary
  stamina, max stamina, every resource) shown as tooltips on the sheet, the global
  resource history for Hero Tokens and Malice (`DGR/Resource.lua:40`), the negotiation's
  own story log (`DSV/NegotiationRules.lua:692`), the montage tally
  (`DocumentSystem/MontageDocument.lua:77`) and the downtime project roll list
  (`DT/DTProject.lua`). History can read these instead of starting from nothing.
- **History should show** uses the brief's row types: **Banner** (combat start/end),
  **Round heading**, **Turn heading**, **Action row**, **Nested row** (a triggered or
  automatic effect under the action that set it off), **Turn line** (compact line with
  no action: start/end of turn, saves, conditions ending; COPY T16 format),
  **What happened** sentence and **Why** line on the detail card (COPY N2/N3, R1 wording).
  Play outside combat (tests, montage, negotiation, respite) has no rounds, so it is shown
  as **Scene rows** (an action row grouped under the scene instead of a turn).
- **How often**: every combat / often / rare.

---

## 1. Starting combat, rounds and turns

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Turn order decided: d10, 6 or higher lets the players choose | H:24939-24945 | Automated. Threshold from "Initiative Threshold" of non-surprised heroes, `DSUI/DSInitiativeRoll.lua:74`; card sent `:2856` | Yes: RollInitiativeChatMessage ("Heroes win turn order!") | Banner (T10): "Draw Steel! · Heroes go first (rolled 7)". Why when the threshold is not 6: "Initiative Threshold 5: Shadow's [feature] lets the heroes win on a 5 or more." | every combat |
| Creatures surprised at the start (no triggered actions, edge against them) until the end of round 1 | H:24926-24938, H:998-1000 | Director marks them in the setup dialog (`DSUI/DSInitiativeRoll.lua:1528`, Surprised with EoE duration); purged at the start of round 2 (`data/charconditions/surprised.yaml`, trigger beginround, `Combat Round > 1`). "If one side is all surprised, the other acts first" not verified | No. Initiative card does not mention surprise; the purge is silent | Banner sub-line: "Goblin Warrior 1 and Goblin Warrior 2 are surprised until the end of round 1." Turn line in round 2: "Surprised ended · Start of round 2". Why on rolls: "Surprised: an edge on the roll against Goblin Warrior 1." | rare |
| A new round begins | H:25012-25016 | `DSCR/MCDMInitiativeBar.lua:7030` (NewRound) | Yes: BeginRoundChatMessage ("ROUND 2") | Round heading (T5) | every combat |
| Effects that last "until the end of the round" expire | (effect wording) | `DGR/Creature.lua:11230` (EndRound) removes them silently | No | Turn line at the round's end: "[Effect] ended · End of round 2" | often |
| A creature's turn starts | H:25017-25026 | `DSCR/MCDMInitiativeQueue.lua:773` (BeginTurnForEntry) | Yes: StartOfTurnChatMessage, text "Start of Turn" only | Turn heading (T7); everything below nests under it | every combat |
| Start-of-turn effects: auras and areas that hurt a creature starting its turn there; effects lasting "until the start of your next turn" end (Defend, Aid Attack) | H:25568-25571, H:25690-25693 | Automated in `DGR/Creature.lua:10830-10920` (prestartturn trigger, aura expiry, `movedamageStartTurn`). Aura damage goes through `DSCR/MCDMCreature.lua:7144` (AuraDamage) with no card | No (damage only in the stamina history; expiries silent) | Turn lines: "Took 3 fire damage · Start of turn: [Wall of Fire]"; "Defend ended · Start of turn" | every combat |
| Heroic Resource gained at the start of each turn (2, or 1d3, by class) | H:7852-7853 (same pattern in every class) | Automated per class: beginturn Replenish trigger, e.g. `data/classes/censor.yaml:5669-5699`; obeys the "Automated Heroic Resource Gains" setting | Yes: ResourceChatMessage, reason "Start of Turn" | Turn line (T16): "Wrath +2 · Start of turn" / "Ferocity +2 · Start of turn (1d3)" | every combat |
| The other side has finished, so the rest of a side act one after another | H:24960-24967 | Director picks turns on the initiative bar; nothing to enforce | Start of turn only | Why on the turn heading when it surprises: "All the Heroes have acted, so the remaining enemies take their turns in a row." | often |
| A creature's turn ends | H:25017 | `DGR/Creature.lua:11183` (EndTurn: endturn event, effect expiry); `data/globalrulemods/end-turn-save.yaml` | No | Turn lines grouped at the end of the turn (rows below) | every combat |
| EoT effects end at the end of the affected creature's turn | H:7555-7559, H:659-660 | Automated: "End Turn Effects" purges EoT conditions without a roll (`DSCR/MCDMAbilitySaveBehavior.lua:740`); EoT ongoing effects drop in EndTurn | No | Turn line (T16): "Slowed ended · End of turn" | every combat |
| Saving throw at the end of the turn (d10, 6 or higher ends the effect) | H:7560-7568, H:937-942 | Automated prompt: "End Turn Saving Throws" (`end-turn-save.yaml`), roll dialog `DSCR/MCDMAbilitySaveBehavior.lua:567`, threshold from "Save Ends" | Partly: the d10 roll card "Saving Throw vs Weakened". Whether it ended is not stated | Turn line (T16): "Saved against Weakened · End of turn: rolled 7 (6 or more ends it)" / "Weakened continues · End of turn: rolled 3 (6 or more ends it)" | every combat |
| Hero Token spent to succeed on a failed saving throw | H:1418-1419 | Automated button "Succeed Instead" (`DSCR/DSResources.lua:492`); token history note "Succeeded on a saving throw" | Roll card only; the spend is in the hidden Hero Token history | Turn line: "Saved against Bleeding · End of turn: rolled 3, a Hero Token made it a success". Why: "Spent a Hero Token: a failed saving throw becomes a success." | often |

## 2. Ending combat

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| The Director ends combat (victory screen, no victory, or defeat) | H:26036-26056 | `DSCR/MCDMInitiativeBar.lua:108` (PromptEndCombat), `:28` (PerformEndCombat); `DSUI/DSVictoryScreen.lua` | No (a defeat posts plain chat text, `MCDMInitiativeBar.lua:4359`) | Banner: "Combat ended · Victory" / "Combat ended · Defeat" | every combat |
| Victories awarded for the combat | H:1521-1525, H:26037 | `DSUI/DSVictoryScreen.lua:1918` (AwardVictories), shown on the victory screen | No | Banner line: "Each Hero gained 1 Victory." Per hero in the detail: "Dwarf Fury: Victories 2 -> 3." | every combat |
| Remaining Heroic Resource lost at the end of the encounter | H:7858 (each class) | `DSCR/MCDMCreature.lua:8184` ("Reset Heroic Resource") | No | Turn line under the end banner: "Wrath 4 lost · End of combat" | every combat |
| Remaining surges lost | H:7496-7497 | Surges resource is `clearOutsideOfCombat` (`data/characterresources/surges.yaml`) | No | "2 surges lost · End of combat" | every combat |
| Temporary Stamina disappears | H:25985-25986, H:1019-1021 | `DSCR/MCDMCreature.lua:8167` | No | "5 temporary Stamina lost · End of combat" | often |
| Effects and conditions end (hero's choice); persistent abilities end | H:7544-7554, H:26038-26040, H:937-939 | `DSCR/MCDMCreature.lua:8124-8137` ends persistent abilities and removes EoE conditions/effects. **Save-ends conditions and effects are not cleared** (only `duration == "eoe"`); not found anywhere else | No | "Weakened ended · End of combat" (one line per creature, folded) | every combat |

## 3. Heroic Resources, surges and Victories (general rules)

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Heroic Resource equal to Victories at the start of combat | H:7850-7852 (each class) | rollinitiative Replenish per class, e.g. `data/classes/censor.yaml:5840-5868` | Yes: ResourceChatMessage, reason "Draw Steel" | Turn line under the banner: "Wrath +3 · Draw Steel!". Why: "Victories 3: a Hero starts combat with Heroic Resource equal to their Victories." | every combat |
| Heroic Resource not spent when the target resists a potency-only effect | H:7437-7451 (also Malice) | Not found | n/a | Why: "Overwatch cost no focus: Reactor 1's Reason 2 resisted R<1." | rare |
| Heroic abilities outside combat cost nothing, once until a Victory or Respite | H:7861-7869 (each class) | Not found | n/a | Action row note: "Used outside combat: no wrath spent. Usable again after the next Victory or Respite." | rare |
| Surges gained | H:7477-7482 | Resource "surges"; gains come from features and Hero Tokens | Only when the granting behavior has a chatMessage; the Hero Token route is not logged | Nested row: "Dwarf Fury gained 2 surges." | every combat |
| Surges spent for extra damage (up to 3, highest characteristic each) | H:7486-7489 | Roll dialog (`DSCR/MCDMAbilityRollBehavior.lua:52`, "ability_surges") | On the roll card | Chip (T12) "2 surges"; Why (Y5): "Spent 2 surges: each dealt 2 extra damage (Might 2)." | every combat |
| 2 surges spent to raise a potency by 1 for one target | H:7491-7495 | `data/globalrulemods/surges.yaml` | On the roll card | Why (Y8): "Potency raised with 2 surges: A<1 became A<2, so Reactor 1 could not resist being knocked prone." | often |

## 4. Power rolls

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Edges and banes net out (double edge/bane shifts the tier; double edge plus one bane = one edge) | H:1300-1338 | Roll dialog; the log card shows counts, net modifier and double edge/bane icons (`ChatPanel/ActionLogPanel.lua:341-510`). Sources are not named | Counts only | Why (Y1/Y2), one per source: "Bane from cover: a bane on the roll against the Fury only: 13 - 2 = 11, Tier 1 instead of Tier 2." | every combat |
| Bonuses and penalties, e.g. a skill (+2) | H:1361-1372, H:23957-23964 | `data/globalrulemods/tests.yaml:10` (Skilled) | Net modifier on the roll card | Why: "Climb skill: +2." | often |
| Natural 19 or 20 always Tier 3; on a main action it is a critical hit and grants another main action | H:1284-1292, H:7453-7465 | `data/globalrulemods/critical-hit.yaml:24-69` (extra main action, banner, float text) | Yes: ResourceChatMessage "Critical Hit!" plus the dramatic banner | Chip "Critical"; Nested row: "Dwarf Fury gained an extra main action (critical hit)." | rare |
| Roll downgraded to a lower tier, or the tier set by hand | H:1271-1279 | Click a tier row: `DSCR/MCDMAbilityRollBehavior.lua:995` sets overrideTier and "X overrode the result" | Stored on the roll | Why: "Chose Tier 2 instead of Tier 3." / source "set by hand" (C5) | rare |
| Automatic tier outcome; different automatic outcomes cancel | H:1373-1384 | Not found as a general rule | n/a | Why: "Automatic Tier 3 from [effect]; the roll still checks for a critical hit." | rare |
| One roll, different tiers per target (edges/banes against some targets) | H:7466-7476 | Per-target edges/banes on the roll (`multitargets`); the log card's total follows the first target only (`ActionLogPanel.lua:345`) | Partly | Per-target Why (Y2 "Cover: ... against the Fury only") and a tier per target in the detail | often |
| Potency: the effect lands only if the target's characteristic is lower | H:7340-7428 | `DSCR/MCDMAbilityBehavior.lua:2031/2038` record "Resisted potency" / "Did not resist potency" | On the cast card as a hover tooltip only | What happened (W5/W6): "... and is slowed (save ends)" / "... and resisted being slowed." Why (Y9): "R<1: the Elementalist's Reason 2 resisted." | every combat |

## 5. Hero Tokens

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Session starts with Hero Tokens equal to the number of Heroes; unused ones vanish at the end | H:1400-1402, H:1426-1428 | Director's refresh button (`DSCR/MCDMCharacterPanel.lua:3322`), note "Session Reset" in the token history | No | Scene row: "Hero Tokens set to 4 (session start, 4 Heroes)." | often |
| Hero Token earned (heroic act, test reward) | H:1403-1410, H:23789-23791 | Manual edit (token history "Set manually") | No | Scene/Turn line: "The party gained 1 Hero Token (Director)." | often |
| Hero Token spent for 2 surges | H:1415-1416 | `DSCR/DSResources.lua:572` (spend menu: "Gained 2 surges"); one benefit per turn enforced when strict | No (token history only) | Nested row: "Dwarf Fury spent a Hero Token and gained 2 surges." | often |
| Hero Token spent to reroll a test (must use the new roll) | H:1421, H:23594-23595 | `DSCR/DSResources.lua:450` (Re-roll rule), history "Re-rolled a test" | Reroll shows on the roll card; spend not logged | Why: "Spent a Hero Token to reroll: 9 became 14." | rare |
| 2 Hero Tokens spent to regain Stamina equal to the recovery value (on your turn, or when taking damage, before the damage) | H:1423-1425 | Spend menu heals directly (`DSCR/DSResources.lua:572`, Heal "Hero Tokens"); separately a prompt when a Hero would die (`data/globalrulemods/heroic-resources.yaml:51`, "Recovery on Death") | Menu route: no. Death prompt: yes (cast + "Hero Tokens Spent on Recovery") | Nested row: "Dwarf Fury spent 2 Hero Tokens and regained 12 Stamina before taking the damage." | rare |

## 6. Damage and Stamina

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Damage from an ability | H:25869-25873 | `Draw Steel Ability Behaviors/AbilityDamage.lua` | On the roll card; a separate damage card only when the behavior has a chatMessage | What happened (W1/W2/W3) | every combat |
| Damage immunity / weakness (highest one only; weakness before immunity) | H:25885-25916, H:591-603 | `DSCR/MCDMCreature.lua:5793` | Yes: DamageModifierChatMessage | Why (Y3/Y4): "Damage immunity 2: Reactor 1 took 7 damage instead of 9." | often |
| Temporary Stamina absorbs damage first | H:25973-25977 | `DSCR/MCDMCreature.lua:5806-5813` (absorbed amount computed for stats) | No | What happened: "Human Null took 9 damage: 5 soaked by temporary Stamina." (T14) | often |
| Temporary Stamina granted (the larger amount is kept, not added) | H:25978-25984 | `DSCR/DSTemporaryHitpoints.lua:5` keeps the larger pool; the card (`:201`) reports the granted amount even when nothing changed | Yes, but can mislead | "Human Null gained 5 temporary Stamina." Why when ignored: "Kept 10 temporary Stamina: a new grant only replaces a smaller one." | often |
| Damage with no ability: auras, damaging terrain, areas entered (forced movement counts) | H:25347-25351, H:25380-25383, H:25502-25506 | Automated via aura entry and `DSCR/MCDMCreature.lua:7144` (AuraDamage) | No (stamina history only) | Nested under the move or Turn line: "Reactor 1 took 3 fire damage from [Wall of Fire] (pushed into it)." | often |
| Stamina set by hand | (n/a) | `DGR/Creature.lua:2017` writes the stamina history | No | Turn line: "Stamina set by hand: 23 -> 15 (Director)." | often |
| Stamina maximum reduced | H:25857-25858 | `max_stamina` stat history (`DGR/Creature.lua:1976`) | No | "Dwarf Fury's Stamina maximum is now 30." | rare |
| Winded (Stamina at or below half maximum) | H:25922-25927, H:1075-1076 | `DSCR/MCDMCreature.lua:6810` (event + sound) | No | What happened (W4): "... and is now winded." | every combat |
| Hero dying (0 or lower): bleeding that can't be removed, no Catch Breath | H:25928-25934, H:646-650 | `data/globalrulemods/dying.yaml` (bestows Bleeding, suppresses Catch Breath); `DSCR/MCDMCreature.lua:6806` | No | "Dwarf Fury took 9 damage and is dying." Why: "Dying: bleeding until no longer dying, and can't Catch Breath." | rare |
| Hero dies at the negative of their winded value | H:25935-25938 | `DSCR/MCDMCreature.lua:2758` (kill threshold), creaturedeath `:6946` | No | What happened (W8): "Dwarf Fury took 6 damage and died." | rare |
| Director-controlled creature dies at 0 Stamina | H:25939-25941, H:973-976 | `data/globalrulemods/monster-death.yaml` | No | W8: "Monster Test 1 took 17 damage and was killed." | every combat |
| Knocked unconscious instead of killed; damage while unconscious kills; waking after an hour (Hero spends a Recovery) | H:25950-25966 | Not found (Unconscious condition exists, `data/charconditions/unconscious.yaml`) | No | "Bandit 2 took 8 damage and was knocked unconscious." | rare |
| Object damaged or destroyed | H:25987-26005 | objectdestroyed event (`DGR/TriggeredAbility.lua:320`) | No | "The wooden door took 3 damage and was destroyed." | rare |
| Underwater: fire immunity 5, lightning weakness 5, bane without swim | H:26006-26009 | `data/globalrulemods/underwater.yaml` | Immunity card / bane count only | Why: "Underwater: fire immunity 5." | rare |
| Suffocating: 1d6 damage at the end of each round after Might rounds | H:26010-26017 | Not found | No | Turn line: "Took 4 damage · End of round: out of breath" | rare |
| Bleeding: lose 1d6 + level after a main action, triggered action, or Might/Agility roll | H:7623-7632, H:500-502 | `data/charconditions/bleeding.yaml` (finishability trigger, prompted, 1d6+Level, can't be reduced) | Yes: "Bleeding" cast card + roll | Nested under the action: "then lost 5 Stamina to bleeding." Why: "Bleeding: 1d6 + level after a main action; it can't be prevented." | often |

## 7. Recoveries and healing

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Catch Breath: spend a Recovery, regain recovery value | H:25572-25578, H:1574-1581 | `data/globalrulemods/catch-breath.yaml` (blocked while dying) | Yes: cast + "Recovery Spent" resource card | Action row (W12): "Dwarf Fury spent a Recovery and regained 12 Stamina." | every combat |
| Heal main action: target spends a Recovery or makes a saving throw | H:25706-25711 | `data/globalrulemods/actions.yaml:154` | Yes (cast) | Action row: "Human Conduit used Heal: Dwarf Fury spent a Recovery and regained 12 Stamina." | often |
| Recovery spent through another creature's ability | H:25865-25868 | `data/globalrulemods/triggers.yaml:20` ("Spend Recovery" plumbing) | Heal card when the behavior has a chatMessage | Nested row under the ability | every combat |
| Director-controlled creature given a Recovery regains a third of its maximum | H:25942-25949 | `DSCR/MCDMCreature.lua:3131` | Via the ability | Why: "Director-controlled creatures have no Recoveries: regains one-third of its Stamina maximum." | rare |

## 8. Conditions and effects (general)

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Condition imposed by an ability | H:7618-7696 | `DSCR/MCDMCreature.lua:4458` (InflictCondition) | Inside the cast/roll card | What happened (W5): "... and is grabbed." | every combat |
| Condition imposed or removed outside a cast (by hand, by a trigger with no chatMessage) | (baseline) | Same | No | Turn line: "Prone · set by hand (Director)" / "Prone ended · removed by hand" | often |
| Condition blocked by immunity | (traits) | Speech bubble or float text only (`DSCR/MCDMCreature.lua:4461`) | No | W7 "It was not frightened." Why (Y10) "Immune to frightened." | rare |
| Same condition doesn't stack; frightened or taunted from a new source replaces the old | H:7534-7543, H:7642-7644, H:7692-7694 | One entry per condition; a new caster overwrites (`DSCR/MCDMCreature.lua:4458` onwards) | No | Why: "Frightened of Reactor 1 replaced frightened of Goblin Assassin 2." | rare |
| Effects of the same ability don't stack (most impactful applies) | H:7523-7533 | Not verified | n/a | Why: "Null Field from two Nulls counts once." | rare |
| Frightened / taunted end when the source dies (codex behavior; not in the Heroes condition text) | (codex) | `data/charconditions/frightened.yaml:81-100`, `taunted.yaml:51-70` | Yes: purge cards "Source of fear died" / "Taunter died" | Turn line: "Taunted ended · Goblin Warrior 1 died" | rare |
| A creature ends an effect it imposed (free maneuver) | H:7572-7574 | `data/globalrulemods/triggers.yaml:148` ("End Effect") | Yes (cast) | Action row | rare |
| Dazed: one thing per turn, no triggered actions; triggered action already used this round | H:7633-7636, H:25036-25054 | Dazed modifiers (`data/charconditions/dazed-14fe1a12.yaml`); triggered-action gate `DGR/Creature.lua:7679` | No (the trigger is simply not offered) | Why on a missing reaction: "Dazed: can't use triggered actions." / "Already used a triggered action this round." | often |

## 9. Automatic condition endings and side effects

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Grab ends when either creature is force moved out of adjacency | H:7659-7662 | `data/charconditions/grabbed.yaml:294-354` | Yes: purge card "Force moved away from grab" | Nested under the forced movement: "... was pushed 2 squares and is no longer grabbed." | often |
| Grab ends when the grabbed creature teleports | H:7659-7660, H:25313-25314 | `grabbed.yaml:90` | No | Nested: "... teleported and is no longer grabbed." | rare |
| Restrained ends on teleport; a teleported prone creature may stand | H:7685, H:25307-25314 | `restrained.yaml:108`, `prone.yaml:106` | No | Nested: "... and is no longer restrained." | rare |
| Escape Grab: Tier 2 lets the grabber make a free strike first | H:25580-25596 | `grabbed.yaml:129` | Yes (cast, roll, invoked strike) | Action row with Nested row: "Goblin Warrior 1 made a free strike before letting go: Dwarf Fury took 4 damage." | often |
| Grab: Tier 2 lets the target make a free strike first | H:25597-25614 | `data/globalrulemods/grab.yaml` | Yes | Nested row as above | often |
| Hidden: an edge on ability rolls; hidden ends once an ability or strike resolves | H:24408-24427 | `data/charconditions/hidden.yaml:28-101`, `data/globalrulemods/hiding.yaml` | No (only the Hide cast) | Nested: "... and is no longer hidden." Why: "Hidden: an edge on this roll." | often |
| Search for Hidden Creatures (opposed test) reveals creatures | H:24428-24447 | `data/globalrulemods/maneuvers.yaml:199`; reveal outcome not verified | Cast + rolls | Action row: "Human Tactician searched: Goblin Sniper is no longer hidden." | rare |
| Knocked prone while flying or climbing: falls | H:7673-7674, H:25272-25276 | `data/globalrulemods/falling.yaml:177-215` ("Fall when Prone") | "Falling Damage" card only | Nested (W15): "... knocked prone and fell 4 squares, taking 8 damage." | rare |
| Flying creature with speed reduced to 0 falls | H:25275-25276, H:683-687 | Not found (only prone triggers a fall) | n/a | Same as above | rare |

## 10. Movement and forced movement

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Push, pull or slide | H:25361-25383 | `DGR/AbilityRelocateCreature.lua:600-830`; distance in `DGR/ActivatedAbility.lua:6262-6340` | No | What happened (W4): "... was pushed 2 squares ..." (with the cross-section on hover, Appendix M) | every combat |
| Stability reduces forced movement (or stops it) | H:25494-25501 | `DGR/ActivatedAbility.lua:6274-6322`: shown only in the move prompt; full negation fires "Too Much Stability", a Hidden ability that only speaks (`data/standardabilities/too-much-stability.yaml`) | No | Why: "Stability 1: pushed 2 squares instead of 3." / "Stood firm: stability 2 stopped a push 2." | every combat |
| Big Versus Little: +1 square when larger with a melee weapon ability | H:25416-25420 | `DGR/ActivatedAbility.lua:6262-6272` (prompt only) | No | Why: "Big Versus Little: pushed 3 squares instead of 2." | often |
| Slammed into a creature: both take 1 per square remaining | H:25421-25434 | `data/globalrulemods/collision.yaml` via the collide event (`AbilityRelocateCreature.lua:830-1000`) | Yes: bare "Collision" damage cards | Nested: "Reactor 1 was pushed into Goblin Warrior 2: both took 2 damage." | often |
| Slammed into an object: 2 + 1 per square remaining | H:25461-25465 | `collision.yaml` (+2 WithObject) | Yes: "Collision" card | Why: "Hit a wall with 2 squares left: 2 + 2 = 4 damage." | often |
| Hurled through an object (glass/wood/stone/metal): object breaks, creature takes 3/5/8/11 | H:25470-25488 | Breakable walls break (engine; `wallbreak` event, `AbilityRelocateCreature.lua:756-764`) but nothing deals the damage; comment at `:669`: "a clean smash-through deals no collision damage" | No | "Reactor 1 was pushed through a wooden wall and took 5 damage." | rare |
| Force moved downward into an object: falling damage as if Agility 0 | H:25466-25469 | Not found | n/a | Why: "Forced down 3 squares: falling damage with Agility 0." | rare |
| Vertical forced movement / pushed off a ledge: falls after the movement | H:25402-25415, H:25489-25493 | Fall after movement (TryFall) | "Falling Damage" card | W15: "... pushed 3 squares off the gallery, it fell 4 squares." | rare |
| Falling: 2 per square (max 50), Agility reduces the height, water reduces it by 4, lands prone | H:25319-25328, H:674-677 | `data/globalrulemods/falling.yaml:24-59` | Yes: "Falling Damage" card, no height or reduction | Why (Y7): "Fell 4 squares: the fall dealt 6 damage (Agility 1 took off 1 square)." | rare |
| Falling onto a creature: it takes the same damage; knocked prone if the faller's size is greater than its Might | H:25333-25338 | `falling.yaml:68-175` | Yes: "Fallen On Top Of" card | Nested row under the fall | rare |
| Falling far (100 squares a round) | H:25339-25342 | Not found | n/a | Turn line | rare |
| Burrowing creature force moved horizontally: 1 damage per square instead | H:25202-25207 | Not found | n/a | Why | rare |
| Opportunity attack (adjacent enemy moves away without shifting; not with a bane) | H:25732-25739, H:846-848 | `data/globalrulemods/opportunity-attack.yaml:24-85` (prompted); bane check `DGR/Creature.lua:7661` | Yes when taken (cast); a suppressed one is silent | Nested under the move: "Goblin Warrior 1 made an opportunity attack: Dwarf Fury took 4 damage." Why when none: "No opportunity attack: the Goblin has a bane against the Fury." | every combat |
| Teleport | H:25282-25318 | Relocate behavior; TeleportChatMessage only for one ability (`Draw Steel Ability Behaviors/AbilityTeleportToLineEnd.lua:148`) | Only the cast | Nested: "... teleported 5 squares." | often |
| Jump beyond the baseline (Might/Agility test) | H:25249-25265 | `data/globalrulemods/move-actions.yaml:72`, rolled jump `AbilityRelocateCreature.lua:222` | Roll | Action row | rare |
| Climbing a creature; knocked off (falls, prone) | H:25227-25248 | `data/globalrulemods/climbing-other-creatures.yaml`, `data/standardabilities/fall-off-creature.yaml` | Cast + roll | Nested row | rare |
| Mounted combat: rider force moved is knocked off; mount dies, both fall prone | H:26022-26035 | Not found | n/a | Nested row | rare |
| Squeezed into a creature's space: bane on rolls | H:25105-25109 | Not found | n/a | Why | rare |
| A death trigger resolves after the forced movement from the same hit | H:25507-25511 | Not verified | n/a | Ordering only: nest the death after the move | rare |

## 11. Situational edges and banes (Why lines)

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Flanking: edge on melee strikes | H:25786-25795 | `data/globalrulemods/flanking.yaml` | Count only | Why: "Flanking with Human Null: an edge." (C5) | every combat |
| Cover: bane on damage-dealing abilities | H:25796-25800 | `data/globalrulemods/cover.yaml` | Count only | Why (Y2) | every combat |
| Concealment / invisible: bane on strikes | H:25801-25813 | `data/globalrulemods/concealment.yaml` | Count only | Why: "Concealment (fog): a bane." | rare |
| High ground: edge | H:25352-25360 | `data/globalrulemods/high-ground.yaml` | Count only | Why: "High ground: an edge." | often |
| Prone target (melee edge), prone striker (bane), restrained, grabbed, weakened, frightened, taunted | H:7623-7696 | Condition modifiers (`data/charconditions/*.yaml`) | Count only | Why: "Reactor 1 is prone (melee): an edge." (C5) | every combat |
| Aid Attack: the next ally roll against that enemy gains an edge (used up) | H:25568-25571 | `data/globalrulemods/maneuvers.yaml:16` (ongoing effect) | Cast only; use and expiry silent | Why: "Aid Attack from Human Null: an edge." Turn line: "Aid Attack used" | often |
| Defend: double bane on rolls against you until your next turn; no benefit while taunting | H:25690-25696 | `data/globalrulemods/actions.yaml:98`; the taunting exception not verified | Cast only | Why: "Defend: a double bane on rolls against the Tactician." | often |

## 12. Tests

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Test made: difficulty and outcome (success, consequence, reward, failure) | H:23494-23505, H:23596-23791 | `DMHub Game Hud/RequireDCDialog.lua`, `DSUI/DSRequestRollsDialog.lua` | Roll card; the outcome words are in the dialog | Action/Scene row: "Dwarf Fury made a medium Might test (Climb): 14, success with a consequence." | often |
| Natural 19 or 20 on a test: success with a reward at any difficulty | H:23649-23654 | Tier text (`DocumentSystem/HeroicTestDocument.lua:31`) | Roll | Why: "Natural 19: success with a reward." | rare |
| Consequence by default: the Director gains 2 Malice at the start of the next combat | H:23701-23703, H:23734-23736 | Not found (manual) | No | Scene row: "Consequence: the Director gains 2 Malice at the start of the next combat." Later, on the round heading, Why: "Malice +2 from Dwarf Fury's Climb test." | often |
| Reward by default: the party earns a Hero Token | H:23789-23791 | Not found (manual) | No | "Reward: the party gained 1 Hero Token." | often |
| Director trades a failure for success with a consequence (or the reverse) | H:23716-23722, H:23737-23743 | Not found | No | Why: "Took success with a consequence instead of failure: lost 1d6 Stamina." | rare |
| Assist a test (Tier 1 bane, Tier 2 edge, Tier 3 double edge) | H:24365-24386 | Not found as a mechanic | No | Nested under the test: "Human Null assisted (Flirt): an edge on the test." | rare |
| Opposed power roll (higher total wins; tie changes nothing; double edge = +4) | H:23887-23911 | `DSUI/DSRequestRollsDialog.lua:290` (opposed_power_roll) | Rolls | Scene row: "Opposed test: Shadow 15, Guard 12. The Shadow sneaks by." | rare |
| Reactive and secret tests (Director rolls for the Heroes) | H:23912-23946 | Director roll requests; hidden rolls | Roll (hidden) | T17 "Director rolled 2d10 · Hidden from players" | rare |
| Group test: half or more succeed; collective reward or consequence (bane on next roll, 2 Malice per Hero) | H:24475-24516 | Launcher only: encounter cue step `DSCR/MCDMEncounter.lua:334`, `DSCR/MCDMInitiativeBar.lua:3446`; the outcome rule is not found | Rolls only | Scene row: "Group test (Agility, medium): 3 of 4 succeeded, so the group succeeded." | rare |

## 13. Montage tests

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Montage test begins (difficulty, success and failure limits) | H:24521-24576, H:24707-24739 | `DocumentSystem/MontageDocument.lua:77-110` (LiveMontage); EotW `EncounterOfTheWeek/EncounterMontage.lua` | No | Scene heading: "Montage test: Cross the Infinite Desert (hard: 6 successes, 2 failures)." | rare |
| Each test, assist or ability adds a success or failure | H:24577-24628, H:24689-24696 | Director's +/- buttons (`MontageDocument.lua:988`) | Rolls only; the tally is not | Scene row: "Dwarf Fury: success (3 of 6)." | rare |
| Montage round ends; the test stops after 2 rounds | H:24697-24706 | Not verified | No | Turn line: "Montage round 1 ended: 3 successes, 1 failure." | rare |
| Outcome: total success, partial success, total failure; Victories | H:24633-24658, H:24740-24752 | Outcomes with Victories fields (`MontageDocument.lua:224`, `:629-681`); award not verified | No | Banner: "Montage test: total success. Each Hero gained 2 Victories." | rare |
| The same skill can't be used twice | H:24601-24608 | Not found | n/a | Why when refused | rare |

## 14. Negotiation

The negotiation already keeps a structured story log (`LiveNegotiation.history`, entries
`{who, text, cue, tone}`, `DSV/NegotiationRules.lua:692`, written by `NegotiationRun.Log`
`:1411`) and saves run records to its journal document. None of it reaches the Action Log.

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Negotiation opens; interest and patience from the NPC's attitude | H:26712-26764, H:26294-26312 | `DSV/NegotiationRules.lua:491` (attitudes), begin logged `:1468` | Own log only | Scene heading: "Negotiation with Zola Honeycut: interest 2, patience 4 (neutral)." | rare |
| Shared language raises patience by 1 or 2 | H:26313-26319 | Not found | n/a | Why: "Patience +1: Korvo speaks Zola's language." | rare |
| Test to uncover a motivation or pitfall (Tier 1 costs 1 patience) | H:26776-26797 | Logged in its own log (`NegotiationRules.lua:2779-2784`) | Own log only | Scene row: "Val read Zola and learned a pitfall: revelry." | rare |
| Argument: appeal to a motivation, no motivation, pitfall, repeated, caught in a lie, natural 19-20 | H:26839-26898 | `DSV/NegotiationRules.lua:571-630` (Resolve) | Own log only | Scene row: "Jorn appealed to greed: interest 2 -> 3, patience 3 -> 2." Why: "Greed is a motivation: medium test, Tier 2." / "Pitfall (higher authority): interest and patience each fell by 1." | rare |
| Renown: famous or infamous Hero gains an edge on some arguments | H:26899-26960 | Not found | n/a | Why: "Famous to Zola (Renown 3, Impression 3): an edge." | rare |
| NPC's offer by interest; negotiation ends (interest 5 or patience 0 final offer, interest 0 no deal, walk away) | H:26961-27045 | `NegotiationRules.lua:638` (Terminal), offers and accept map | Own log only | Banner: "Negotiation ended: Zola's final offer accepted (interest 4)." | rare |
| Stop combat to start a negotiation (hard Presence test as a maneuver) | H:26705-26711 | Not found | n/a | Action row | rare |

## 15. Respite, Experience and downtime projects

| Event | Rule | Codex today | Logged today? | History should show | How often |
|---|---|---|---|---|---|
| Respite finished: all Stamina and Recoveries regained | H:1584-1596, H:914-917 | `DGR/Creature.lua:13537` (Rest "long"), called from `Draw Steel Respite/RSPSession.lua:689` | No (stamina history note "Respite") | Scene row: "Respite finished: Dwarf Fury regained 18 Stamina and all Recoveries." | often |
| Victories convert to Experience, then reset to 0 | H:1533-1535, H:1547-1552 | `DGR/Creature.lua:13543-13567` | No | "Dwarf Fury's 3 Victories became 3 XP (now 19 XP)." | often |
| Level gained when XP reaches the threshold | H:2362-2371, H:2403 | `DGR/Creature.lua:13553-13566` (16 XP per level setting) | No | Banner: "Dwarf Fury reached level 2." | rare |
| Respite interrupted: no benefits | H:1597-1601 | Not found (the Director just doesn't finish it) | n/a | Scene row: "Respite interrupted: no Stamina or Recoveries regained." | rare |
| Project roll as a respite activity: total becomes project points (minimum 1) | H:27325-27336, H:882-885 | `DT/DTProjectRollDialog.lua:50` (roll request), points kept in the project's roll list | Roll only | Scene row: "Polder Elementalist's project roll: 14 points toward Imbue Armor (120 of 150)." | often |
| Breakthrough on a natural 19 or 20: another project roll | H:27330-27332, H:505-507 | `DT/DTConstants.lua:17`, `DT/DTProject.lua:287` | No | Why: "Natural 19: breakthrough, another roll." | rare |
| Project event (milestone) | H:27392-27460 | `DT/DTProjectRollDialog.lua:346` ("Resolve Downtime Project Milestone") | Roll only | Scene row with the event text | rare |
| Language of the project source: bane or double bane | H:27350-27357 | `data/globalrulemods/tests.yaml:28-47` | Count only | Why: "Source in a related language: a bane." | rare |
| Project completed | H:27333-27335 | `DT/DTProject.lua:576` (grants the item) | No | Scene row: "Imbue Armor completed: Dwarf Fury gained [item]." | rare |
| Victory for a noncombat challenge (trap, negotiation, montage, puzzle) | H:1526-1532 | Manual edit on the sheet (`DSCR/MCDMCharacterPanel.lua:3708`, `DSV/HeroSheetCard.lua:2280`) | No | Scene row: "Each Hero gained 1 Victory (negotiation with Zola)." | often |

---

## Count

130 events across 15 topics (counted from the tables above):

- 23 have no implementation found in the codex (20 not found, 3 not verified).
- 46 are automated, or done by hand in the app, but leave no Action Log entry. Some of
  these are kept in a stat history, the Hero Token history or the negotiation's own log.
- 34 have a log entry for the event itself. Several are bare, for example "Collision 2"
  with no push, or a temporary Stamina card that can be wrong.
- 27 leave only a partial trace: a roll with no outcome, an edge/bane count, a tooltip,
  or a card for a different part of the event.

## Gaps that matter most

1. **Forced movement and what it caused.** Push/pull/slide has no record, and the parts
   that change it (stability, Big Versus Little, a full negation) live only in the move
   prompt or a speech bubble. Collision and fall damage appear as bare cards with no link
   to the push. Every combat.
2. **Winded, dying, death and kills.** Nothing is logged, and dying silently adds
   bleeding that will hurt the Hero on every main action. Every combat.
3. **End of turn.** EoT effects end silently; a saving throw shows only its d10, not what
   it ended. Every combat.
4. **Damage with no ability.** Aura, damaging terrain and start-of-turn damage reach
   only the stamina history; hand edits to Stamina are invisible. Often.
5. **Conditions ending on their own.** A grab ended by a teleport, hidden ended by
   attacking, surprise ending in round 2, condition immunity (speech bubble only): no
   record. Often.
6. **End-of-combat cleanup.** Heroic Resource reset, surges and temporary Stamina lost,
   EoE effects ended, Victories awarded: all silent. Every combat.
7. **Hero Token spends.** The surge and Stamina spends sit only in the hidden token
   history; a token-saved saving throw looks like a failed roll. Often.
8. **Test consequences and rewards.** The default "+2 Malice next combat" and "Hero
   Token" outcomes aren't automated or recorded, so the Malice at the next combat has no
   visible cause. Often outside combat.

## Surprises

- **Hurled through a wall deals no damage.** Breakable walls break, but nothing deals the
  rules' 3/5/8/11 damage (`AbilityRelocateCreature.lua:669`).
- **Save-ends effects outlive combat.** `creature:EndCombat` clears only EoE durations,
  but the rules say save ends lasts until a save or the end of combat (H:937-939).
- **The temporary Stamina card can be wrong.** It reports the granted amount even when
  the creature keeps a larger existing pool.
- **Potency results are already recorded per target**, but only as cast-card tooltips.
- **A flying creature reduced to speed 0** (grabbed, restrained) does not fall; only
  prone triggers a fall.
- **Some rule-driven records already exist outside the log.** These are the stat
  histories, the Hero Token and Malice history, the negotiation's toned story log, the
  montage tally and the project roll list. History can read them instead of rebuilding.
- **Frightened and taunted end when their source dies.** This is a codex behaviour, and
  it is logged; the Heroes condition text I read does not include it.
- **The Elementalist example** (class review's scope): H:11159-11160. The rule reads
  "If you take damage equal to or greater than 5 times your Reason score in one turn, you
  stop maintaining any persistent abilities."
