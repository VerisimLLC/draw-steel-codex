# Lizardfolk YAML implementation

Implemented 2026-09-06. Scope: YAML content only; no Lua or C# source changes.

## Rules and scope

The authoritative `monster-reference.md` Lizardfolk section takes precedence over
older text retained in `info.properties.import`. In particular, Ripper Spear keeps
12 damage on tier three. The current reference does not include the older Tail
Whip tail requirement or one-grab limit, so those restrictions were not added.
Terrorsoar is absent from the current reference; its distinct existing statistics
and damage were preserved while updating shared automation. The visible shedskin
template and hidden Deathrex variant received the relevant fixes too.

## Implemented

| Content | Changes |
|---|---|
| Ordinary Reptilian Escape | All four condition triggers consume the tail before purging/shifting. Lost Tail is indefinite, so encounter end does not regrow it. Corrected copied prompt text and made the free triggered action explicit. |
| Grunt and Shellguard | Creature-or-object targeting restored. Shellguard references the canonical next-strike bane without a mismatched editor ID. Existing captain bonuses are preserved. |
| Tonguelash | Native post-roll pull/shift choice is retained. A narrowly matched importerPowerTableEffects record invokes the existing toward-target movement constraint for the chosen shift. A final adjacency check applies grabbed from the paired tonguer. Printed tiers are unchanged. |
| Scaletooth | Razor Bite uses native bleeding potency plus a target-specific +1 modifier for its own grabbed creatures. Tail Whip uses a narrowly matched conditional-grab template, after native potency and slide resolution; removed duplicate hardcoded grab behaviors. |
| Bloodeye | Bloodshot applies actual line-of-effect caps of 4/3/2, not vision radius. Zero-aware minimum formulas preserve the tightest of these caps. Potency checks include resistance and applied potency adjustments. |
| Skyterror and Terrorsoar | Glaive Rush shifts 4 only while flying. Poison uses a condition rider attached to successfully inflicted weakened, without redundant raw-Might filters. Adjacent end-turn spread is mandatory. |
| Glider | Removed incorrect automatic ground-movement detection. Added an explicit Glider ability for Director-confirmed eligibility. The existing landing event grants flight after qualifying falls, including Terrorsoar's formerly empty branch. |
| Rex Reptilian Escape | Condition application offers the existing restricted escape prompt; successful purge consumes the tail and shifts 2. A granted manual escape ability handles arbitrary eligible effects, using a before/after effect count to avoid spending the tail when selection is cancelled. Exact timing/selection is documented as manual. |
| Ripper Spear | Grab selection is restricted to this cast's spear targets within reach; creature/object targeting and the 1-Malice cost are explicit. Removed the stale marker-based target selection. |
| Death Roll | Requires a target grabbed by this caster, purges only this caster's grab, then uses the rules-engine Slide 5 command. |
| Swat the Fly | Removed overlapping and incorrectly eligible automatic triggers. A granted manual triggered action spends the correct action and slides the selected triggering creature/object. Resolve before it leaves adjacency. |
| Trundle | Retains automated movement. Removed the misleading single unrestricted follow-up strike; actual opportunity attackers require Director adjudication. |
| Snack Attack | Each participant moves, can make a free strike, and receives the difference in cast damage before/after their own sequence. Later participants do not receive earlier participants' damage as temporary Stamina. |
| Shed Some Skin | Keeps the existing 10-Stamina template and shift. Corrected the template's stale 80-Stamina roll field. Placement, initiative linkage, and dynamically copied statistics remain partial. |
| Thresher Thrasher | Added initial movement. Adjacent start-of-turn reaction covers other creatures. Removed the inaccurate finishmove entry trigger; added a manual entry-reaction ability. Its actual free strike is restricted to the triggering/selected target. |
| Villain actions | Replaced truncated usage-limit strings with structured one-use-per-encounter resources. |
| Net Trap | Restored small-creature eligibility, removed unconditional bane, and made the entering creature perform the Agility test using their test modifiers. Director confirms enemy/awareness eligibility; existing one-use resource remains. |
| Water Pit | Keeps terrain/object creation. Removed entry-only aura rewards and the nonfunctional duplicate object rewards. Correct enter-then-exit benefits and draining are explicitly manual. |
| Flood the Shores | Removed the invalid Swim-skill modifier. The remaining effect is explicitly an unimplemented rules reminder, not an automated water buff. |

Ability/feature `implementation` values and `implementationDetails` now distinguish
supported mechanics from manual combat handling. Deathrex, both glider variants,
and faction malice are not Gold. Grunt, Shellguard, Tonguer, Scaletooth, and
Bloodeye have their identified YAML mechanics implemented; final combat acceptance
testing is still required before treating the family as certified Gold.

## Lua support needed next

| Feature | Needed capability and approach | Unlocks | Effort / confidence | Likely files and risks |
|---|---|---|---|---|
| Effect application identity | Event exposing the newly applied effect instance, duration, and caster; purge that specific instance rather than asking the Director. | Rex Escape, three Deathrex records | MEDIUM / 8 | `DMHub Game Rules/Creature.lua`, `TriggeredAbility.lua`, `AbilityPurgeEffects.lua`. Must cover ordinary conditions and non-condition effects without duplicate offers. |
| Exact adjacency transitions | Arrival/departure events independent of opportunity-attack eligibility, with shifts, traversed squares, and targetable objects covered. | Swat and Thresher | MEDIUM / 7 | Movement dispatch in `Creature.lua`, trigger definitions in `MCDMRules.lua`; object events may need engine support. `finishmove` and aura onenter are insufficient substitutes. |
| Actual opportunity attackers | Cast-scoped list of distinct creatures that actually made opportunity attacks during a movement, rather than counting offered opportunities. | Trundle | MEDIUM / 7 | `Creature.lua`, `ActivatedAbilityCast.lua`, opportunity-attack resolution. Handle declined prompts, cancellation, and multiplayer sequencing. |
| Grounded displacement and falling | Ground-only displacement information and an event at the qualifying point during a fall. | Skyterror and Terrorsoar Glider | MEDIUM / 7 | `Creature.lua` path context and falling pipeline; possibly LuaPath bridge fields. Current fall trigger runs on landing. |
| Duplicate overrides | Copy current deathrex characteristics, set 10 maximum/current Stamina, omit villain actions, enforce original-square placement and shared initiative. | Shed Some Skin | MEDIUM / 8 | `AbilitySummon.lua`. Existing duplicate support helps, but a fixed template cannot follow modified originals. |
| Source-linked traps | Retain creator/allegiance, distinguish restraint from each trap, and expose adjacent rescue interactions with rescuer eligibility and maneuver cost. | Net Trap | MEDIUM / 7 | Object pressure-plate bridge, triggered ability and interaction code. Awareness is Director knowledge and needs an explicit choice rather than an invented numeric condition. |
| Linked water lifecycle | Per-pit same-turn entry/exit tracking, open/drained state, eligible drain tests with fall/prone outcomes, and map flood expiry based on open pits. | Water Pit and Flood the Shores | HIGH / 6 | Object/zone lifecycle and encounter events. A simple exit trigger wrongly rewards creatures who started inside. Deleting a decorative object does not drain terrain. |
| Submersion and swimming speed | Physical submerged detection plus a modifier scoped to swimming speed. | Flood the Shores | MEDIUM / 6 | Movement and terrain APIs. `InWater` currently means selected swim movement, and `swim` grants a movement capability rather than modifying its speed. |

No fake enemy check based on Lizardfolk keywords, pre-roll Tonguelash mode choice,
automatic flood buff based only on selected swim movement, or entry-only Water Pit
reward was introduced as a substitute for these missing capabilities.

## Verification

- All 21 affected YAML files pass `validate_yaml.py --base-dir . <files>`.
- Read-only runtime fixtures exercise all four new importer pattern cases (three
  Tonguelash shifts and Tail Whip's conditional grab).
- Read-only runtime fixtures exercise all six LoE cap combinations: 4, 3, 2,
  4+2, 2+4, and 4+3+2; results are the tightest nonzero cap.
- Read-only runtime fixtures verify Snack Attack's damage-difference calculation
  and Rex Escape's no-change/success gates. A formula precedence issue found by
  this check was fixed with explicit parentheses.
- Runtime fixtures use detached objects and explicit YAML-derived pattern data;
  they do not mutate live tokens or upload/replace compendium tables. The connected
  runtime still exposed the old cached table entries during the check, so these
  tests do not claim that the edited files were already reloaded there.
- Existing unrelated worktree changes were preserved. No build, Lua deployment,
  import, or cloud upload was performed.

## Combat acceptance tests still needed

1. Each escape condition: decline/accept, second escape prohibited, tail persists
   across encounter end; manual regrowth permits escape again. Rex cancellation
   must not spend the tail, and a non-condition EoT effect must be selectable.
2. A squad of two tonguers attacks different targets and chooses different OR
   branches. Confirm directed shifts, paired distances, and ownership of each grab.
3. Razor Bite against its own grab versus another creature's grab; Tail Whip at
   both potency boundaries and both sides of reach after movement.
4. Bloodshot at every tier, with potency resistance and an existing tighter cap.
5. Poison immunity/resistance, spread to an adjacent turn-ending creature, correct
   expiry, and removal of the source weakened condition/rider.
6. Snack Attack with multiple allies, zero damage, immunity, skipped strikes,
   different owners, and cancellation. Verify one move/strike sequence per target.
7. Death Roll source-specific release, Swat action cost, Thresher correct target,
   and villain-action one-use limits.
8. Net Trap uses the entering creature's Agility/test modifiers, with conditional
   awareness bane and no second resolution after the one-use resource is spent.

These interactive checks were not executed against a live encounter.
