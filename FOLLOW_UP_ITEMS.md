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
| F3 | **D20 rolls**: the automatic roll path never checks "Only if" (only the roll dialog does). | `DMHub Game Rules/ModifierD20Rolls.lua` (`hintD20Roll`, ~198; ~272-277 is the dialog path, which does check) | Check the filter in `hintD20Roll`. |
| F4 | **Condition-rule modifiers** (e.g. Unbalanced) are added after filtering, so their own "Only if" is never checked. | `DMHub Game Rules/Creature.lua`, `CalculateConditionModifiers` (~6850) | Filter them before adding. |
| F5 | **Dormant bug**: `FillModifiersFromModifiers` appends the whole table instead of each modifier. No type uses the hook today. | `DMHub Game Rules/Creature.lua` ~6782-6784 | Append each entry. |
| F6 | **Needs an in-app test**: `alternateappearance`, `movementrestriction`, `suspended`. | See the audit | Test, then allow "Only if" if it holds. |

## Roll tooltip
| # | Item | Where | Note |
|---|---|---|---|
| F7 | The roll-option tooltip's automatic line lists only the edge/bane/tier change and extra damage; potency, surges and added text appear only if the modifier's Description says so. | `Draw Steel Core Rules/MCDModifyPowerRolls.lua` ~982-1046 (`renderOnRoll`) | Either list them automatically, or have the block editor write each block's sentence into the modifier's Description (framework D3). |
| F8 | "Change a tier's text" block (sets "Add to Table", `addText`) and an "Arm effect" block. | Planned under Q3 in `BLOCK_EDITOR_FRAMEWORK.md` | Editor work, but deferred until the core editors are built. |

## Core content data problems (found by opening every class, 2026-11-25)
Content fixes, not editor work. Details in
[`ui-mockup/class-builder-data/TEXT_ONLY_FEATURES_AUDIT.md`](ui-mockup/class-builder-data/TEXT_ONLY_FEATURES_AUDIT.md).

| # | Item |
|---|---|
| F9 | **Berserker:** the 8-Ferocity push-surge trigger reads `"2 When Level >= 4 else 1"` and never checks for 8 Ferocity, so from 4th level it gives 2 surges at 4 Ferocity. The Reaver's reads `"... and Heroic Resources This Turn >= 8"`. |
| F10 | **Talent:** the checklist has a 10th-level start-of-turn row (1d3 + 2) that the Clarity trigger's table lacks. **Beastheart:** the reverse (the trigger has a 10th-level row the checklist lacks). |
| F11 | **Null:** the 12-Discipline row of Discipline Mastery is display text only; nothing applies it. |
| F12 | **Elementalist:** the 7th-level mantles for Fire, Green and Void lack `suppressOthers` (Earth has it), so a hero may see two; Green's mantle is named "Burning Ground" (copied from Fire). |
| F13 | **Fury:** a 10th-level skill choice has no name; the Berserker's Growing Ferocity holds a record named "Vuken Growing Ferocity". **Conduit:** "Burgeoning Saint" holds a power modifier that changes nothing. |

## Engine events the editors need
| # | Item | Where | Note |
|---|---|---|---|
| F14 | **Partly done (2026-11-25, commit `ff10c001`):** spending surges now fires the Use Resource trigger (`useresource`, Resource "surges", Quantity = how many). The class builder's "spends surges" gain saves as that trigger with `Resource = "Surges"` joined to its test. **Still missing:** what the surges bought, and spending surges on potency. The Magewright (third party) gains Wonder when "you or an ally spends 3 or more surges on a single ability to increase the damage" or "2 surges ... to increase the potency"; the event can't tell the two apart, and the roll dialog only spends surges on damage ("Surges only buy extra damage", `Timeline/EmbeddedRollDialog.lua`). | `Draw Steel Core Rules/MCDMCreature.lua` (`ConsumeSurges`), `Timeline/EmbeddedRollDialog.lua`, `Draw Steel UI/DSRollDialog.lua` | Pass a Purpose ("damage" / "potency") with the event and add spending surges on potency to the roll dialog. Until then a Magewright line can only test the count (`Quantity >= 3`). |
| F15 | **Surges leave through `ConsumeResource` too, with different rules.** Losing surges to an enemy effect (`MCDMAbilityBehavior.lua:1619`) or typing a lower number on the Draw Steel V sheet (`DrawSteelChararcterSheet.lua:7081`) fires `useresource "surges"` as if spent; a retainer's spend through `ConsumeResource` fires on the mentor, not the retainer (`Resource.lua:876-889`); and a roll option that costs surges spends them in a separate `ConsumeSurges` call (`CharacterModifier.lua:3724-3732`), so one roll can raise two events and "Quantity >= 3" can miss. Found by the 2026-11-25 review. | `DMHub Game Rules/Resource.lua` ~1012-1017, `Draw Steel Core Rules/MCDMCreature.lua` (`ConsumeSurges`) | Send surge spends in `ConsumeResource` through the same rule as `ConsumeSurges` (no event for losses or hand edits; fire on the spender), and spend a roll's surges in one call. |

## "Only if" gaps found by the 2026-11-25 review
| # | Item | Where | Note |
|---|---|---|---|
| F16 | **Kit access ignores "Only if"**: the game decides kit access by scanning the feature's modifiers directly, so a false condition still grants the kit. The audit also rates `granttreasure` and `light` "partly" and `monstermodes` and `invisibility` "unsafe" without listing them here. | `Draw Steel Core Rules/MCDMCustomRules.lua:126-133`; MODIFIER_FILTER_AUDIT.md | Until fixed, the editor must not offer "Only if" around these (the prototype offers it everywhere today; see BLOCK_EDITOR_REVIEW.md). |

## Core content that could be automated (found 2026-11-25, recorded 2026-11-26)
Content work, not editor work. The class builder shows each finding on the feature's card
(`ui-mockup/class-builder/text-audit.js`, generated from `ui-mockup/class-builder-data/TEXT_ONLY_FEATURES_AUDIT.md`).

| # | Item |
|---|---|
| F17 | **14 text-only features could be built with existing blocks:** Censor Templar (10th), Conduit Avatar (10th), Stormwight Stormborn and Blessing of Fortunate Weather (5th), Null Discipline Mastery Improvement and Manifold Resonance (10th), Cryokinetic Synaptic Triage (8th), Metakinetic Inertial Dampener (8th), Summoner Minion Chain (4th), Circle of Storms Heart of Nature (Encounter 3), Tactician Warmaster (10th), Insurgent Covert Operations (Encounter 1), Troubadour Dramaturgy and Greatest of All Time (10th). The audit says how for each. |
| F18 | **7 need a block the editor doesn't have yet** (editor backlog, after the core editors): Beastheart Everyone's Best Friend and the montage-aware effects; Oracle Prophecy; Green Chimeric Manifestation (merging two forms); Null Enhanced Null Field; Summoner Minions / Essence Outside of Combat; Duelist Masterwork. Also `modifytrigger` (7 records), which still opens as an advanced block. |
