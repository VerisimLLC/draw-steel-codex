# Core Reference

Shared knowledge needed for ALL compendium content types: pitfalls, table names,
GoblinScript conventions, UUID maps, and import workflow.

See also: [MONSTERS.md](MONSTERS.md) for monster-specific structures.
See also: [CHARACTERS.md](CHARACTERS.md) for character options (classes, kits, ancestries, etc.).
See also: [../RULES_REFERENCE.md](../RULES_REFERENCE.md) for game rules.
See also: [../../GoblinScript_Guide.md](../../GoblinScript_Guide.md) for full GoblinScript syntax.

---

## Common Pitfalls

These errors have been discovered through testing. Read this section BEFORE creating YAML.

1. **Table names are case-sensitive.** Use the exact names from `_manifest.yaml`.
   `characterOngoingEffects` is correct; `CharacterOngoingEffects` will fail silently.

2. **`stability` is NOT a valid attribute ID.** The correct ID is `forcedmoveresistance`.
   Using `attribute: stability` on a CharacterModifier will do nothing.

3. **GoblinScript uses 1/0 not true/false for boolean values.** `activationCondition: "1"` is
   correct; `activationCondition: "true"` will error.

4. **`iconid` is REQUIRED on CharacterOngoingEffect.** If omitted or set to null, the app
   will crash when trying to display the effect. Use a default:
   `iconid: "ui-icons/skills/1.png"` (or any valid icon path).

5. **`display` table is REQUIRED on CharacterOngoingEffect.** Always include:
   ```yaml
   display:
     saturation: 1
     hueshift: 0
     bgcolor: "#ffffffff"
     brightness: 1
   ```

6. **Aura durations vs ongoing effect durations are DIFFERENT systems.**
   - Aura durations: `endnextturn`, `eoe`, `endround`, or a number (rounds).
   - Ongoing effect durations (ApplyOngoingEffectBehavior): `end_of_next_turn`, `eoe`,
     `save_ends`, `eoe_or_dying`, `endround`, `endnextround`, `until_rest`, `until_long_rest`,
     `momentary`, or a number (rounds).
   - Do NOT use `nextturn` for aura durations -- use `endnextturn`.
   - Do NOT use `end_of_next_turn` for aura durations -- that is for ongoing effects.

7. **`reasonedFilters` should be used INSTEAD OF `targetFilter`, not alongside it.**
   `targetFilter` silently removes targets, so the `reasonedFilters` explanation text would
   never be shown for those targets. Use one or the other.

8. **`ongoingEffectCustom` is an editor tracking field.** It tracks whether the ongoing effect
   was created inline in the editor. Set it to the same UUID as `ongoingEffect` if the effect
   was custom-created, or `false` if referencing a pre-existing effect.

9. **`targetType: enemies` is NOT valid.** The valid value is `targetType: target` with
   `targetAllegiance: enemy`. See the targetType table for all valid values.

10. **`operation` field EXISTS on attribute modifier.** Valid values: `add` (default), `set`,
    `max`, `min`. Use `operation: set` to set an attribute to a specific value instead of
    adding to it.

11. **GoblinScript symbol names: don't use spaces when writing formulas.** Symbol names
    are defined with spaces in the Lua code (e.g., "Movement Speed", "Condition Count"),
    but GoblinScript is forgiving about whitespace. When writing formulas, **omit spaces
    in symbol names** for accuracy: `MovementSpeed`, `ConditionCount`, `WalkingSpeed`,
    `HighestCharacteristic`. This is the safest approach. Never guess symbol names --
    always verify against `GOBLINSCRIPT-SYMBOLS.md`.

---

## ASCII-Only Rule

All Lua files and YAML content must contain only ASCII characters (bytes 0-127). Never use
em dashes, curly quotes, ellipses, or any other Unicode punctuation. Use plain ASCII
equivalents: `-` or `:` instead of em dashes, `"` instead of curly quotes, `...` instead
of ellipses.

---

## Table Names

Table names are **case-sensitive**. These are the exact names from `_manifest.yaml`:

| Table Name | __typeName | Content |
|------------|-----------|---------|
| `characterOngoingEffects` | CharacterOngoingEffect | Ongoing effects (buffs/debuffs) |
| `charConditions` | CharacterCondition | Conditions (bleeding, dazed, etc.) |
| `standardAbilities` | ActivatedAbility | Standard/shared abilities |
| `tbl_Gear` | Equipment | Equipment/items |
| `MonsterGroup` | MonsterGroup | Monster groups (for malice features) |
| `classes` | Class | Character classes |
| `subclasses` | Subclass | Subclasses |
| `kits` | Kit | Kits |
| `cultures` | Culture | Cultures |
| `feats` | CharacterFeat | Feats |
| `Skills` | Skill | Skills |
| `damageTypes` | DamageType | Damage types |
| `characterResources` | CharacterResource | Action resources |
| `complications` | CharacterComplication | Complications |
| `titles` | Title | Titles |
| `globalRuleMods` | GlobalRuleMod | Global rules |
| `customAttributes` | CustomAttribute | Custom attributes |
| `conditionRiders` | ConditionRider | Condition riders |
| `races` | Race | Ancestries/races |
| `careers` | Career | Careers |
| `languages` | Language | Languages |
| `Deities` | Deity | Deities |
| `documents` | Document | Journal documents |
| `equipmentCategories` | EquipmentCategory | Equipment categories |
| `encounters` | Encounter | Encounters |
| `backgrounds` | Background | Backgrounds |
| `minionWithCaptain` | MinionWithCaptain | Minion captain bonuses |
| `importerPowerTableEffects` | ImporterPowerTableEffect | Power table effects |
| `importerMonsterTraits` | ImporterMonsterTrait | Monster traits |

---

## GoblinScript Boolean Values

**IMPORTANT:** GoblinScript does NOT use `true`/`false`. It uses **numeric** truth values:
- `1` = true (or any nonzero number)
- `0` = false

Use `1` for "always active" conditions, NOT `"true"`:
```yaml
activationCondition: "1"        # CORRECT: always active
activationCondition: "true"     # WRONG: GoblinScript doesn't recognize "true"
activationCondition: "0"        # Always inactive
```

Comparison operators return `1` or `0`:
```
Target.Object              # Returns 1 if object, 0 if creature
Might >= 2                 # Returns 1 if true, 0 if false
Keywords has "Elemental"   # Returns 1 if has keyword, 0 if not
```

---

## Import Workflow

Files placed in `compendium/import/` can be imported via `/import <filename>`.

**Monster files**: Detected by presence of `info:` top-level key. The file's UUID becomes the
monster's ID in the bestiary.

**Table entries**: Detected by presence of `__typeName:` top-level key. Must also include a
`_table:` metadata field specifying which table the entry belongs to:

```yaml
_table: characterOngoingEffects
__typeName: CharacterOngoingEffect
id: my-uuid-here
name: "My Effect"
...
```

**Bundle files**: For importing multiple related items (e.g., a monster + custom ongoing effects),
use the bundle format:

```yaml
_bundle:
  - _type: monster
    data:
      info: ...
      description: "My Monster"
      ...
  - _type: table
    _table: characterOngoingEffects
    data:
      __typeName: CharacterOngoingEffect
      id: ...
      ...
```

---

## UUID Reference Maps

### Action Resources

| UUID | Name | Usage |
|------|------|-------|
| `d19658a2-4d7b-4504-af9e-1a5410fb17fd` | Main Action | Per turn |
| `a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b` | Maneuver | Per turn |
| `d81ce1e9-96a3-4705-9180-1c80f72a86cf` | Free Maneuver | Unlimited |
| `b9bc06dd-80f1-4f33-bc55-25c114e3300c` | Triggered Action | Per round |
| `5e551b7d-17fb-4099-a303-bafb3c146f98` | Free Triggered Action | Unlimited |
| `67f15a17-523c-4a30-8f1a-a27e4f122605` | Villain Action | Global |
| `5bd90f9b-46be-4cf2-8ca6-a96430d62949` | Recovery | -- |
| `2d3d5511-4b80-46d1-a8c6-4705b9aa45ca` | Heroic Resource | Unbounded |
| `101bab52-7f7c-4bab-92c2-9f8e0cfb7ec8` | Malice | Global |
| `8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d` | Surges | Unbounded |
| `9f418676-96be-402b-92da-0f50294146b3` | Rampage | Unbounded |
| `2166c5fe-260e-4691-9743-06cf097a59f3` | Hero Tokens | Global |
| `093190b1-d6f8-4ad8-8a13-cfa3c4407a32` | Project Points | Unbounded |
| `5758da29-8660-47d3-805b-7c6038f476a1` | Respite Activity | During respite only |

**Respite Activity** is a special action type for abilities used during respites (downtime).
Abilities with this `actionResourceId` appear in a dedicated "Respite Activities" group in
the action bar maneuver drawer. Use this for complication/class features that say "as a
respite activity" -- do NOT use Free Maneuver for respite-only abilities.

### Conditions

| UUID | Name |
|------|------|
| `18ff50ab-053b-49d2-a456-927f8e4f9cf9` | Bleeding |
| `c27e0b16-291a-45ad-8406-973e26576a44` | Dazed |
| `1211270f-bfce-45a6-b937-d72f0e8a06a8` | Frightened |
| `70504ebe-3899-41d3-9f60-74b52ce35e39` | Grabbed |
| `da6867b1-01e3-4570-8d1b-1b94ea1ea343` | Prone |
| `2989a051-204f-442e-967d-edafc2dd5e43` | Restrained |
| `68f455f5-135f-495c-822d-40d809d2b15f` | Slowed |
| `85e26e12-e853-464d-bbbc-98ddf2c0071a` | Taunted |
| `567a3454-ead6-4416-b338-ed73d64b7805` | Weakened |
| `bfe300f4-83f9-4303-9abb-951974025e88` | Unconscious |
| `5c54050a-de9c-410f-94a7-f31b8f57daf3` | Mark |
| `c95a5d2d-6069-4434-b5d4-29796ec90f51` | On Fire |
| `13275b73-cd4e-4d33-ada3-647d7474facf` | Concealment |
| `31daf7f6-f77c-4f73-8eab-43e2d0f123c0` | Hidden |
| `98e85a3b-95a1-41d8-b176-d2d64e7d18d0` | Invisible |
| `ff146aa3-9e91-4c33-b5d2-7f4ac2dc1355` | Surprised |
| `609c216d-482d-41ea-9014-1e16a7f2f306` | Strained |
| `6f23b05d-6683-42dc-a5b6-ee23d35d3177` | Careful Observation |
| `5d091cca-ecb7-4cd0-a2b5-6081de20332a` | Judged |
| `25bb844c-23af-4acc-ab39-c4656af87f6d` | Line of Effect |
| `3210b68d-64c1-4642-a61f-71392055def6` | Relentless Nemesis |
| `a0d68486-a5ee-44e6-9c43-e89b72f14614` | Vengeance Sigil |

### Ongoing Effects (Most Common)

| UUID | Name |
|------|------|
| `08d6e8e7-5209-43e9-9eba-cd124aa81d51` | Bleeding |
| `65d906ae-c83a-4b57-adaf-17dc3793b9c5` | Dazed |
| `3cc61ad4-03d5-4db9-af58-bf59318c9d5a` | Frightened |
| `db8d0b4f-28e4-456f-bfd2-3198ae3a46eb` | Grabbed |
| `c885a4ba-bb51-4676-977d-95df9aa19d85` | Prone |
| `edf8e3e7-a511-48af-a78a-9e38fb7fe385` | Restrained |
| `12bc7f58-0ae8-4b9e-9018-74d28b083992` | Slowed |
| `b9b52786-292c-4dad-9ac0-247bbfa77662` | Weakened |
| `8e024950-034c-4f9e-b064-ca151bcbc264` | Concealment |
| `0aa81848-85f7-4c0a-915c-146de14eb8aa` | Hidden |
| `6b9ea931-b803-4811-8086-c1590a2195e5` | Invisible |
| `319e19ac-4f15-4c16-be71-96d448241c10` | Mark |
| `2677712b-9ca5-4e91-b354-293c5ab0c403` | Taunted |
| `7576a4ac-64ea-42e1-aa18-ab88b55680e4` | Surprised |
| `5ca9517b-ddbf-4f61-bd59-68e3a62708eb` | Defend |
| `27436417-0548-4658-903a-d1f7e951541d` | On Fire |
| `98bff601-1581-451e-96db-be88e063afaf` | Immobilized |
| `48cb6d1e-23c0-4165-924f-fd1337b36670` | Damage Immunity |
| `21827a29-9af8-46ac-86a0-fc74841584a8` | Edge on Next Strike |
| `529b5f9b-c443-40ae-aff3-9102eb3ac2df` | Edge on Next Strike Against |
| `44f31caa-771c-4cf2-a6bb-b3baf82b7cfb` | Edge on Strikes |
| `54455d3b-5abe-46a3-90db-20ada18c4e95` | Bane On All Power Rolls |
| `d9703a62-564a-42ee-8317-8886a473a6f8` | Bane on next attack |
| `08c87dfe-4f31-4ccb-8ba4-4d7024da9619` | Bane on next strike |
| `bbeabc9e-1ae3-400c-8dd3-ea3b1dd1b431` | Double Edge Against Winded Target |
| `a41ad86c-64ff-4421-bc55-7e5325dce78a` | Speed 0 |
| `925a4ca3-3bbd-4bed-8e05-b1f0565862a3` | Speed +5 |
| `7d43f8e4-05e9-4795-bd63-ffe5e2fd5015` | Can't Shift |
| `dd52f05d-dc37-4fb2-8c6b-2fd23daa4efe` | Can't Use Maneuvers |
| `4dadd12e-2887-430c-8f3b-40909bbfa85b` | Can't use triggered actions |
| `de2a4877-a0e6-432b-93ef-a80e018e702d` | Lose Main Action |
| `531917a1-7305-4e49-9015-9ebda58a83f2` | Ignore Difficult Terrain |
| `bf68d026-4fd0-4280-9dba-5756f2e45b51` | Rage |
| `e406004c-0e2d-483f-b64e-4e7fb772753b` | Companion Creature |

### Damage Types

| UUID | Name |
|------|------|
| `8fa72170-6b4c-43e2-b42d-1ba5cfbcb239` | Acid |
| `0b12569b-658f-43fb-9134-6cf136d04e44` | Cold |
| `71a0742f-0a08-44f1-b66a-2280faf6b7b7` | Corruption |
| `48a2c1ee-6092-4775-83c5-8dddfcfdd8e7` | Fire |
| `b3820a10-bf50-44c4-8135-2aa7eb6cfdaa` | Holy |
| `14e4938b-b811-4356-adde-994bd417f0c7` | Lightning |
| `8044ff30-3d7a-4183-9c42-9dfd4b9e98cf` | Poison |
| `bbf31b90-9729-425b-b1c8-ded83455311e` | Psychic |
| `69f209d1-4162-4515-a689-bf13f8f745af` | Sonic |
| `20942663-ff30-45c8-8fd0-67992a6638c8` | Untyped |

### Characteristics

| ID | Name |
|----|------|
| `mgt` | Might |
| `agl` | Agility |
| `rea` | Reason |
| `inu` | Intuition |
| `prs` | Presence |

### Ability GoblinScript Fields

In power roll modifier context, the `Ability` object is available with these fields:

| Field | Type | Returns |
|-------|------|---------|
| `Ability.Keywords has "X"` | Set | Check keywords (Strike, Melee, etc.) |
| `Ability.Inflicts("X")` | Function | True if inflicts named condition |
| `Ability.HasPotency` | Boolean | True if has potency checks |
| `Ability.Does Damage` | Boolean | True if deals rolled damage |
| `Ability.Has Forced Movement` | Boolean | True if includes push/pull/slide |
| `Ability.Damage Types has "X"` | Set | Damage types (fire, cold, etc.) |
| `Ability.Free Strike` | Boolean | Is a free strike |
| `Ability.Action` / `Main Action` | Boolean | Costs main action |
| `Ability.Maneuver` | Boolean | Costs maneuver |
| `Ability.Trigger` | Boolean | Is triggered ability |
| `Ability.Heroic` | Boolean | Heroic ability with resource cost |
| `Ability.Categorization` | Text | "Signature Ability", "Heroic Ability", etc. |
| `Ability.Heroic Resource Cost` | Number | Heroic resource cost (0 if none) |
| `Ability.Malice Cost` | Number | Malice cost (0 if none) |
| `Ability.Name` | Text | Ability name |
| `Ability.Range` | Number | Range in squares |
| `Ability.Allegiance` | Text | "ally", "enemy", "dead", "all" |

**Common patterns:**
```
Ability.Keywords has "Strike"                          # Only for strikes
Ability.Inflicts("Frightened")                         # Inflicts frightened
Ability.HasPotency and Ability.Inflicts("Frightened")  # Frightened via potency (approx)
Ability.Does Damage and Ability.Keywords has "Weapon"  # Weapon damage
```

### Cast GoblinScript Fields (ActivatedAbilityCast)

**CRITICAL:** The `Cast` object is created when an ability starts casting and updated
as the cast progresses. It contains invaluable runtime information. Available in
behavior GoblinScript contexts (DrawSteelCommandBehavior rules, filterTarget, etc.).

**Target and Mode:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.TargetCount` | Number | Number of targets this ability is targeting |
| `Cast.HasPrimaryTarget` | Boolean | True if ability has at least one target |
| `Cast.PrimaryTarget` | Creature | The first/primary target |
| `Cast.HasTarget(creature)` | Function | True if creature is a target |
| `Cast.Mode` | Number | Which mode the ability was cast with |

**Damage and Healing:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.DamageDealt` | Number | Total damage dealt so far |
| `Cast.DamageRaw` | Number | Total raw damage (before resistance) |
| `Cast.DamageDealtAgainst(target)` | Function | Damage dealt to specific target |
| `Cast.Healing` | Number | Total healing done |
| `Cast.HealRoll` | Number | Healing roll result |

**Power Roll Results:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.Tier` | Number | Tier result (1, 2, or 3) |
| `Cast.TierForTarget(target)` | Function | Tier for specific target |
| `Cast.NaturalRoll` | Number | Unmodified 2d10 total |
| `Cast.HighRoll` | Number | Higher of the two d10s |
| `Cast.LowRoll` | Number | Lower of the two d10s |
| `Cast.Roll` | Number | Roll result (for Roll Behavior) |

**Forced Movement:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.ForcedMovementDistance` | Number | Total forced movement distance |
| `Cast.ForcedMovementCollision` | Boolean | Whether collision occurred |
| `Cast.ForcedMovementCreatureCount` | Number | Creatures force moved |

**Resources and Conditions:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.HeroicResourcesGained` | Number | Heroic resources gained during cast |
| `Cast.Boons` | Number | Edges applied (Draw Steel) |
| `Cast.Banes` | Number | Banes applied (Draw Steel) |
| `Cast.InflictedConditions` | Boolean | True if conditions were inflicted |
| `Cast.PurgedConditions` | Number | Conditions purged |
| `Cast.SpacesMoved` | Number | Spaces moved during cast |

**Memory (for cross-behavior data sharing):**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.Memory('name')` | Function | Retrieve stored value by name |

**Potency:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.PassesPotency(target, attr, potency?)` | Function | Check potency. `potency` = "Strong"/"Average"/"Weak" or number |

**Other:**
| Field | Type | Description |
|-------|------|-------------|
| `Cast.Ability` | Ability | The ability being cast |
| `Cast.OpportunityAttacksTriggered` | Number | OAs triggered during cast |
| `Cast.CreatureListSize` | Number | Creatures in manipulated lists |

### Key Creature GoblinScript Fields

| Field | Type | Description |
|-------|------|-------------|
| `Self.ConditionCount` / `Target.ConditionCount` | Number | Count of distinct active conditions |
| `Self.Concealed` / `Target.Concealed` | Boolean | True if in concealed area |
| `Self.Winded` / `Target.Winded` | Boolean | True if winded |
| `Self.Dying` / `Target.Dying` | Boolean | True if dying |
| `Walking Speed` | Number | Walking speed in squares |
| `Movement Speed` | Number | Total movement per round (respects slowed, etc.) |
| `Flying Speed` | Number | Flying speed (0 if can't fly) |
| `Burrowing Speed` | Number | Burrowing speed (0 if can't burrow) |
| `Movement Type` | Text | Current type: "Walk", "Swim", "Fly", etc. |
| `Self.Object` / `Target.Object` | Boolean | True if object (not creature) |
| `Self.Minion` / `Target.Minion` | Boolean | True if minion |
| `Self.Keywords has "X"` | Set | Check creature keywords |
| `Self.Conditions has "X"` | Set | Check if has named condition |
| `ConditionCaster("X")` | Creature | Creature that applied condition X |
| `ConditionStacks("X")` | Number | Stack count of condition X |
| `Stacks` | Number | Stack count (in ongoing effect modifier context) |
| `Highest Characteristic` | Number | Highest of all 5 characteristics |

### Edges and Banes (Power Rolls Only)

Edges and banes modify **power rolls** (2d10 + characteristic). They do NOT apply to saves.

**Mechanical effect:**
- **Single edge** (1 edge, 0 banes): +2 to the roll total
- **Double edge** (2+ edges, 0 banes): Increases the tier result by 1
- **Single bane** (1 bane, 0 edges): -2 to the roll total
- **Double bane** (2+ banes, 0 edges): Decreases the tier result by 1
- Edges and banes **cancel each other**: 1 edge + 1 bane = net 0

**Power modifier `modtype` values:**

| modtype | Effect | Roll String |
|---------|--------|-------------|
| `edge` | +1 edge | `1 edge` |
| `double_edge` | +2 edges | `2 edge` |
| `bane` | +1 bane | `1 bane` |
| `double_bane` | +2 banes | `2 banes` |
| `edge_bane` | Convert edge to bane | `1 bane` (removes existing edge) |
| `bane_edge` | Convert bane to edge | `1 edge` (removes existing bane) |
| `bane_double_edge` | Convert bane to 2 edges | `2 edges` (removes existing bane) |
| `remove_edge` | Strip an edge | (removes edge) |
| `remove_bane` | Strip a bane | (removes bane) |
| `ignore_edges` | Remove all edges | |
| `ignore_banes` | Remove all banes | |
| `none` | No edge/bane (for damageModifier-only mods) | |

**Valid `rollType` values for power modifiers:**

| rollType | Applies to |
|----------|-----------|
| `ability_power_roll` | Standard ability power rolls |
| `test_power_roll` | Skill/attribute tests |
| `opposed_power_roll` | Opposed tests |
| `resistance_power_roll` | Resistance/defense power rolls |
| `project_roll` | Project rolls |
| `enemy_ability_power_roll` | Enemy rolls targeting this creature |
| `all` | All of the above (except enemy_ability_power_roll) |

**CRITICAL: Edges and banes are for power rolls only.** They do NOT affect condition saves
(the d10 roll to end save-ends conditions). See "Condition Saves" below for how those work.

### Condition Saves (Save Ends)

Conditions and ongoing effects with `save_ends` duration are removed by a **d10 roll** at
end of turn. This is completely separate from power rolls.

**Mechanics:**
- **Normal save**: Roll `1d10 + Save Bonus`. Success on 6+.
- **Save Bonus**: A GoblinScript symbol on the creature (e.g., from `repeatSaveModifier`
  on the ongoing effect).
- Saves are NOT power rolls -- edges and banes do NOT apply.

**The Save standard ability** (`save.yaml`, UUID `3c471682-6ffa-44bc-bdbc-1446b66bf051`)
uses `ActivatedAbilityRollBehavior` with `filterTarget` to support conditional save
modifications. For example, the Coward complication is handled by a `filterTarget` that
checks `Target.Complications has "Coward"` and rolls `2d10kl1` (2d10 keep lowest 1)
instead of the normal `1d10`.

**Dice notation for saves:**
- `1d10` -- standard save roll
- `2d10kl1` -- roll 2d10, keep lowest 1 (disadvantage)
- `2d10kh1` -- roll 2d10, keep highest 1 (advantage)

**To add complication-specific save modifications**, edit the Save standard ability in
`compendium/tables/standardabilities/save.yaml`, NOT the complication YAML. The standard
ability uses `filterTarget` with GoblinScript to detect which complications the target has
and adjust the roll formula accordingly.

**Available GoblinScript for save filterTarget:**
- `Target.Complications has "Name"` -- check if target has a named complication
- `"<<condition>>"` -- the condition being saved against (substituted at runtime)

### Power Roll Modifier Visibility and Activation

Power roll modifiers (`behavior: power`) use two independent fields to control how they
appear in the roll dialog:

| Field | Controls | Values |
|---|---|---|
| `displayCondition` | Whether the modifier **appears at all** | GoblinScript formula: truthy = show, falsy = hidden. Empty `""` = always show (default). |
| `activationCondition` | Whether the **checkbox defaults to checked** | `true` or `"1"` = pre-checked. `false` or `""` = pre-unchecked. GoblinScript formula = checked if truthy. |

The player can always manually toggle the checkbox regardless of `activationCondition`.
To completely hide a modifier when a condition isn't met, use `displayCondition`.

**Common patterns:**

```yaml
# Always visible, always active (player can uncheck)
activationCondition: "1"

# Always visible, player must opt-in (default unchecked)
activationCondition: false

# Only appears when condition met, auto-activates
displayCondition: "Magic Treasure Count >= 3"
activationCondition: "1"

# Always visible, auto-activates only when condition met
activationCondition: "Winded"

# Forced (hidden checkbox, always applies, player cannot toggle)
force: true
```

**When to use which:**

- **Hide** (`displayCondition` with formula): When you are **confident** the modifier is
  irrelevant to the situation (e.g., "3+ magic items" when the character has 1).
- **Show unchecked** (`activationCondition: false`): When the modifier costs resources,
  when the player might want it off, when a Director/table ruling could change whether
  it applies, or when you don't have enough information to confidently say it should
  be used. This preserves player agency.
- **Show checked** (`activationCondition: "1"` or formula): When the modifier should
  almost always apply and the player would rarely want to turn it off.

**Key distinction:** `activationCondition: false` means "show but default unchecked" --
it does NOT hide the modifier. Use `displayCondition` with a falsy formula to hide it.
Hiding removes player agency; showing-unchecked preserves it for edge cases.

### Keywords

**Ability keywords** (string keys, not UUIDs):

Animal, Area, Strike, Focus, Kit, Magic, Melee, Psionic, Weapon, Ranged, Telepathy, Air,
Earth, Fire, Green, Rot, Void, Water, Routine, Performance, Beastheart, Companion, Charge,
Telekinesis, Chronopathy, Potion

**Item keywords**:

Potion, Neck, Light Armor, Medium Armor, Heavy Armor, Oil, Scroll, Arms, Hands, Head, Feet,
Waist, Shield, Implement, Wand, Whip, Light Weapon, Medium Weapon, Heavy Weapon, Polearm,
Net, Bow, Ring

**Creature keywords** (string keys):

Abyssal, Accursed, Animal, Beast, Construct, Dragon, Elemental, Fey, Giant, Horror, Humanoid,
Infernal, Ooze, Plant, Soulless, Swarm, Undead

**GoblinScript keyword checks:**

| Context | Syntax | Example |
|---------|--------|---------|
| Self keywords | `Keywords has "Name"` | `Keywords has "Elemental"` |
| Target keywords | `Target.Keywords has "Name"` | `Target.Keywords has "Undead"` |
| Ability keywords | `Ability.Keywords has "Name"` | `Ability.Keywords has "Strike"` |
| Used ability keywords | `UsedAbility.Keywords has "Name"` | `UsedAbility.Keywords has "Melee"` |

Keywords are **case-insensitive** in GoblinScript. Use in `targetFilter`, `activationCondition`,
`creatureFilter`, `conditionFormula`, and anywhere GoblinScript is evaluated.

### Custom Attributes

Custom attributes are boolean/numeric flags on creatures, set via `behavior: attribute`
modifiers using the attribute's UUID. They control mechanics like terrain interaction,
forced movement, grab rules, and more. Access in GoblinScript by lowercase name (no spaces).

**Pattern to set a custom attribute:**
```yaml
- __typeName: CharacterModifier
  behavior: attribute
  attribute: "<custom-attribute-uuid>"  # UUID from table below
  value: 1                              # 1 = enabled for boolean flags
```

#### Movement

| UUID | GoblinScript Symbol | Effect |
|------|-------------------|--------|
| `b6c7c0b4-4584-4889-a2de-1f62aa9df2ce` | `ignoredifficultterrain` | Ignore difficult terrain |
| `6a081cac-d26a-4e1e-a26b-2ace8c92fb58` | `canshiftindifficultterrain` | Can shift in difficult terrain |
| `112b8524-f15d-4d3b-84d7-a8aaa5997bb8` | `freelymovethroughenemies` | Move through enemy spaces freely |
| `8e55aa4a-aae4-4df7-85b7-07ce1b93a6c9` | `canmovethroughwalls` | Incorporeal movement |
| `fb37652f-d640-4a53-9392-0930dcb30eab` | `hover` | Hover (don't fall when prone/speed 0) |
| `42d3d3ec-da00-4338-a97a-fa5ea9d62472` | `shiftdisabled` | Can't shift |
| `333fca17-b1be-4725-9e39-94618bd297fa` | `disengagespeed` | Disengage shift distance (base: 1) |
| `9ee45115-de41-4698-952f-ae7eb42ad17f` | `numberofmovementactions` | Move actions per turn (base: 1) |
| `9e41a093-bf02-4b65-aa0d-42ed091d7927` | `speedwhileslowed` | Speed when slowed (base: 2) |
| `6707d8ac-4323-47bc-9593-e36fd1ac146e` | `chargingspeed` | Speed during charge (base: walking speed) |
| `11650b6f-ee8f-4ab1-9a44-b56a3d43119a` | `jumpdistance` | Jump distance (base: max(1, max(Might, Agility))) |

#### Combat

| UUID | GoblinScript Symbol | Effect |
|------|-------------------|--------|
| `d721a407-25c6-4519-92e1-ac0e8ed68e8c` | `cannotmakeopportunityattacks` | Can't make opportunity attacks |
| `e2773895-411c-404e-a7f4-1aa50cd87710` | `immunityfromopportunityattack` | Immune to opportunity attacks |
| `e8a97ea6-d2e2-4d59-a1d3-11124a104147` | `untargetable` | Can't be targeted |
| `16228928-9f29-4510-a703-65344f2356ef` | `ignoreconcealment` | Ignore concealment |
| `33b6a265-6b89-4def-b86d-507d86061fe8` | `ignorecover` | Ignore cover |
| `f383ffc8-817d-4965-ae92-2e839f27e063` | `criticalthreshold` | Nat roll for crit (base: 19) |
| `90d8d88a-97ae-41a5-925f-e8e474f13c48` | `bonusrange` | Bonus to ability range |
| `0c15efd6-bf73-47bb-aa60-7da385613f9a` | `freestrikebonus` | Bonus to free strike damage |
| `db9d189c-9cfb-438e-b5db-1505f4d3d41e` | `grantflankingtoallies` | Grant flanking to allies |
| `17802d38-f848-47d8-af1c-fcfde60e16bb` | `countasallytoenemiesforflanking` | Count as ally to enemies for flanking |

#### Grab and Forced Movement

| UUID | GoblinScript Symbol | Effect |
|------|-------------------|--------|
| `7a91dad1-97f4-4411-b326-425d58bb2bb2` | `maximumgrabbedcreatures` | Max grabs (base: 1) |
| `5b818edb-5b86-4765-834e-5657a969f3ad` | `grabrange` | Grab distance (base: 1) |
| `8d5825a9-586c-4a6f-b62c-40e65c829cd4` | `sizewhengrabbing` | Effective size for grab (base: Size) |
| `3da3f2c5-4937-4781-998c-b2cfabd11919` | `fullspeedgrabbing` | Full speed while grabbing |
| `82abd296-d79f-4d33-b1e6-47a28f30e161` | `cannotbeforcemoved` | Can't be force moved |
| `ce01b08c-82b7-4fa5-8fc5-8e110cf019d7` | `ignorestability` | Ignore target stability |
| `ba15f0e1-b50c-4324-af08-ce8f2b8f2cf0` | `forcedmovementincrease` | Bonus to all forced movement |
| `ec9c5327-a83e-44ca-a00c-fdb345fecb5d` | `pushbonus` | Bonus to push distance |
| `85836d50-319f-4d25-97c4-3d883a741f43` | `pullbonus` | Bonus to pull distance |
| `84454469-e727-4dfe-8d76-c806f976171b` | `slidebonus` | Bonus to slide distance |
| `151ac2f1-5bd3-4070-8b16-e14896d6933b` | `fallreduction` | Fall height reduction (base: max(0, Agility)) |
| `f97461b9-3424-4479-8c46-e48c835c5d68` | `nodamagefromforcedmovement` | No collision damage from forced movement |

#### Wealth and Renown

Wealth and Renown are custom attributes in the Advancement category. They appear on the
character sheet (Draw Steel V) and can be modified by the player via the UI or by modifiers
in complications, titles, etc. They are **not** resources (like Heroic Resource) -- they use
`behavior: attribute`, not `behavior: resource`.

| UUID | GoblinScript Symbol | Base | Effect |
|------|-------------------|------|--------|
| `036da4db-4406-4038-ae7d-cf0b37890f5f` | `wealth` | 1 | Character's Wealth score |
| `d97c2794-cb70-420f-b078-e260b43e154b` | `renown` | 0 | Character's Renown score |

**Modification pattern:**
```yaml
# +1 Renown (e.g., Outlaw, Disgraced)
- __typeName: CharacterModifier
  behavior: attribute
  attribute: d97c2794-cb70-420f-b078-e260b43e154b
  value: 1

# -5 Wealth (e.g., Indebted)
- __typeName: CharacterModifier
  behavior: attribute
  attribute: 036da4db-4406-4038-ae7d-cf0b37890f5f
  value: -6    # base is 1, so -6 gives net -5

# +3 Stamina bonus (e.g., Infernal Contract Bad choice)
# value can be an integer or a GoblinScript expression like "Level - 1"
```

**Conditional modification** -- use `filterCondition` (GoblinScript expression):
```yaml
# Renown cap: -1 Renown only when Renown > 0 (Betrothed drawback)
- __typeName: CharacterModifier
  behavior: attribute
  attribute: d97c2794-cb70-420f-b078-e260b43e154b
  value: -1
  filterCondition: "Renown > 0"
```

**Feature choice between Renown/Wealth/Stamina** -- see `infernal-contract-but-like-bad.yaml`
for a working example of `CharacterFeatureChoice` with three options, each modifying a
different attribute.

**UI integration:** The character sheet reads these via
`token.properties:CalculateNamedCustomAttribute("Wealth")`. Clicking the value in the UI
opens `gui.PopupOverrideAttribute` which clones standard feature templates from
`importerStandardFeatures` (`renown-modification.yaml`, `wealth-modification.yaml`).

**Macros:** `/awardrenown` and `/awardwealth` chat commands also use these standard feature
templates to grant Renown/Wealth to characters.

#### Status and Resources

| UUID | GoblinScript Symbol | Effect |
|------|-------------------|--------|
| `96b930c8-846a-4221-991a-5ded3c9e9b39` | `cannotregainstamina` | Can't regain stamina |
| `e3a362d8-7a61-4aee-89fe-e1ba927a9184` | `immunetonondamageeffects` | Immune to non-damage effects |
| `7565750e-2376-4809-abc2-47eed82153d1` | `cannotberemoved` | Can't be removed from map |
| `3d9a620e-06ab-4dc0-94dc-7af862d7bd63` | `ignorefireimmunity` | Attacks ignore fire immunity |

#### Potency Resistance

| UUID | GoblinScript Symbol | Effect |
|------|-------------------|--------|
| `39e08262-baa3-4947-98cd-fb8045ff991e` | `mightpotencyresistance` | Might potency resistance (base: Might) |
| `f09c8c3c-a863-456f-868f-1bbbace18380` | `agilitypotencyresistance` | Agility potency resistance (base: Agility) |
| `23e48f75-9484-47a6-a068-fbdb31a2e77c` | `reasonpotencyresistance` | Reason potency resistance (base: Reason) |
| `1422a518-b444-4ac5-b200-2f0b33aca87b` | `intuitionpotencyresistance` | Intuition potency resistance (base: Intuition) |
| `e4c0b067-bfc8-4a41-8b6d-4f167da13591` | `presencepotencyresistance` | Presence potency resistance (base: Presence) |

### Standard Abilities (for ActivatedAbilityInvokeAbilityBehavior)

Standard abilities are reusable abilities invoked via `standardAbility` UUID in
`ActivatedAbilityInvokeAbilityBehavior`. Parameters are passed via `standardAbilityParams`
and interpolated using `<<paramName>>` syntax.

**Usage pattern:**
```yaml
- __typeName: ActivatedAbilityInvokeAbilityBehavior
  standardAbility: "14c386b6-693c-4abf-aebe-3b5f5a017886"  # Shift
  standardAbilityParams:
    distance: "3"
```

#### Movement

| UUID | Name | Params | Description |
|------|------|--------|-------------|
| `14c386b6-693c-4abf-aebe-3b5f5a017886` | **Shift** | `distance`, `targetfilter` | Shift X squares (most used: 57 refs) |
| `de95d093-f3d4-4d74-99fe-ab49aae8b167` | **Move Speed** | -- | Move up to walking speed |
| `1de07d8e-11c3-4621-9055-bb8e26c9a40f` | **Teleport** | `range` | Teleport to empty space |
| `4a993863-896f-47d0-8449-74c1fe2279b0` | **Move** | `distance` | Generic move |
| `8010820f-6bf3-422f-985b-2af02f620113` | **Jump** | `distance` | Jump X squares |
| `090c096b-0841-45db-bb48-175f51a3bf75` | **Ally Shift** | `range`, `distance`, `count` | Ally targets shift |
| `6a8164e8-0492-47f2-8237-101af54e05c1` | **Use a Move Action** | -- | Full move action |

#### Forced Movement

| UUID | Name | Params | Description |
|------|------|--------|-------------|
| `8acf7d21-2e06-4439-bff0-bfaf72c24514` | **Push** | `range` | Push in straight line |
| `3ecc4aca-2df1-42d0-b535-8a943fa5f0e9` | **Pull** | `range` | Pull in straight line |
| `21f855e5-cef6-46a9-96aa-976d1ac35a6c` | **Slide** | `range` | Slide any direction |
| `6c340696-278d-45ed-9ff0-2f317313b8af` | **Vertical Push** | `range` | Vertical push |
| `82863cf6-ec8f-4035-952b-60c319a12b75` | **Vertical Slide** | `range` | Vertical slide |
| `8a44cac4-f869-4d8d-8139-06c2d2926f0d` | **Vertical Pull** | `range` | Vertical pull |

#### Free Strikes and Attacks

| UUID | Name | Params | Description |
|------|------|--------|-------------|
| `f4a4f737-cc4d-4bc1-8aa8-a4ee344e2d42` | **Make Free Strike** | -- | Target makes their free strike |
| `6ff06550-b5f4-4259-8146-57f377d16dd9` | **Free Strike** | -- | Caster makes their free strike |
| `0a68f64c-67f7-4279-9741-38aedaab7029` | **Melee Free Strike** | -- | Caster melee free strike |
| `0ca5fc04-6068-4f47-b5c6-936d3a595f24` | **Ranged Free Strike** | -- | Caster ranged free strike |
| `491c36e6-a36b-47be-9134-788b071fa7ca` | **Melee Free Strike vs Target** | `targetid` | Target makes melee FS vs specific target |
| `952ff59e-8467-4141-aae6-d9ce35094c25` | **Free Strike vs Target** | `targetid` | Free strike vs specific target |
| `6b1d83d3-6e25-472e-a6a6-421be6a6db5c` | **Free Strike With Edge** | `edges` | Free strike with edge bonus |
| `7b19698f-5fe2-4eea-9ef8-7621a7974073` | **Signature Ability** | -- | Target uses signature ability |
| `64d1be94-fd92-4d0b-92f4-a6d638089f1a` | **Signature Strike** | -- | Target uses signature strike |

#### Composites (Move + Attack)

| UUID | Name | Description |
|------|------|-------------|
| `dfb59889-b651-40a6-80be-56d38bd34198` | **Move Speed + Melee Free Strike** | Move then melee free strike |
| `1c423f02-73e6-4c44-8341-17d854f15fc5` | **Move Speed + Free Strike** | Move then any free strike |
| `362a8107-45f8-4698-92fd-194a55ae8d72` | **Move Speed OR Free Strike** | Choice: move or free strike |

#### Healing and Recovery

| UUID | Name | Params | Description |
|------|------|--------|-------------|
| `f57cb6f7-13b9-4ebb-8e88-88ead0a9c203` | **May Spend Recovery** | `numrecoveries` | Target spends recovery |
| `a478d5f1-fed3-4772-9930-c3e82dc23f12` | **Ally May Spend Recovery** | `numrecoveries`, `range` | Ally spends recovery |
| `60b012ab-dde8-4246-afc2-5a9b32e660ef` | **Grant Temp Stamina** | -- | Grant temp stamina |

#### Condition / Effect Management

| UUID | Name | Description |
|------|------|-------------|
| `3c471682-6ffa-44bc-bdbc-1446b66bf051` | **Save** | Make a saving throw |
| `0b1cc306-e0b8-4898-836a-c84b0ee7df47` | **Purge Save Ends Effect** | Remove own save-ends effect |
| `62d8c42b-c4af-4941-aa73-658bdbe80c9d` | **Remove Condition** | Remove a condition |

#### Stealth

| UUID | Name | Description |
|------|------|-------------|
| `9683c15c-de03-4129-869c-d4054928cf97` | **Hide if in Cover/Concealment** | Attempt to hide |
| `003a1b5e-0b14-4c99-b948-0f0fc715bbf2` | **Caster May Hide** | Caster hides |
| `bd9f9431-2ee2-41c1-81cb-c08570144cb9` | **Shift and Hide** | Shift then hide |

#### Common Parameters

| Param | Typical Values | Used In |
|-------|---------------|---------|
| `distance` | `"3"`, `"5"`, `"movement speed"` | Shift, Move, Jump |
| `range` | `"5"`, `"10"`, `"20"` | Teleport, Push/Pull/Slide, Ally abilities |
| `targetid` | `"<<Cast.Primary Target.id>>"` | Free strikes vs specific targets |
| `numrecoveries` | `"1"` | Recovery spending abilities |
| `edges` | `"1"`, `"2"` | Free Strike With Edge |

### Monster Groups

Monster groups are stored in the `MonsterGroup` table. The `monsterGroupId` field on a
monster references its group UUID. Groups control malice features and group-wide bonuses.
Look up existing groups by browsing the MonsterGroup table in the compendium editor.
