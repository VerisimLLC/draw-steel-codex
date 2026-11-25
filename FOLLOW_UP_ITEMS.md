# Follow-up items (outside the block editors)

These came up while designing the block editors. They are engine and rules fixes, not editor
work, so they are parked here and **not** being done now. Each links to where it was found.

## "Only if" (filterCondition) gaps
From [`MODIFIER_FILTER_AUDIT.md`](MODIFIER_FILTER_AUDIT.md). Until each is fixed, the block editor
does not offer "Only if" around that type (`supportsFilter = false`).

| # | Item | Where | Smallest fix |
|---|---|---|---|
| F1 | **Transform** ignores a false "Only if" when adding the beast's modifiers and when blocking equipment: both run before the modifier list is filtered. | `DMHub Game Rules/Creature.lua`, `FillTemporalActiveModifiers` (the `AddModifiers` and `PreventsEquipment` loops) | Check `PassesFilter` at the top of `CharacterModifier:AddModifiers` and `:PreventsEquipment`; pass the modifier's entry from the caller; clear `_tmp_attr` after the loops. A worked version was committed as `fe0c61b` and reverted (type check clean, not tested in the app). |
| F2 | **Captain and rider** modifiers don't re-check their own condition the way companion modifiers do. | `modcaptain`, `modrider` (see the audit) | Re-check `PassesFilter`, as `DSBeastheartModifyCompanion.lua:58` does. |
| F3 | **D20 rolls**: the automatic roll path never checks "Only if" (only the roll dialog does). | `DMHub Game Rules/ModifierD20Rolls.lua` (`hintD20Roll`, ~272-277) | Check the filter in `hintD20Roll`. |
| F4 | **Condition-rule modifiers** (e.g. Unbalanced) are added after filtering, so their own "Only if" is never checked. | `DMHub Game Rules/Creature.lua`, `CalculateConditionModifiers` (~6628-6641) | Filter them before adding. |
| F5 | **Dormant bug**: `FillModifiersFromModifiers` appends the whole table instead of each modifier. No type uses the hook today. | `DMHub Game Rules/Creature.lua` ~6559-6561 | Append each entry. |
| F6 | **Needs an in-app test**: `alternateappearance`, `movementrestriction`, `suspended`. | See the audit | Test, then allow "Only if" if it holds. |

## Roll tooltip
| # | Item | Where | Note |
|---|---|---|---|
| F7 | The roll-option tooltip's automatic line lists only the edge/bane/tier change and extra damage; potency, surges and added text appear only if the modifier's Description says so. | `Draw Steel Core Rules/MCDModifyPowerRolls.lua` ~982-1046 (`renderOnRoll`) | Either list them automatically, or have the block editor write each block's sentence into the modifier's Description (framework D3). |
| F8 | "Change a tier's text" block (sets "Add to Table", `addText`) and an "Arm effect" block. | Planned under Q3 in `BLOCK_EDITOR_FRAMEWORK.md` | Editor work, but deferred until the core editors are built. |
