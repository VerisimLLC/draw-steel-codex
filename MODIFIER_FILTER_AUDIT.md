# Modifier "Only if" (filterCondition) audit

Read-only audit of which `CharacterModifier` types honour `filterCondition`. No Lua was
changed. Line numbers are as of this audit; "Creature.lua" means `DMHub Game Rules/Creature.lua`
and "CharacterModifier.lua" means `DMHub Game Rules/CharacterModifier.lua` unless a path is given.

## How "Only if" works, in plain words

Every modifier on a creature (from class features, kits, items, conditions, ongoing effects,
templates, global rules, summoner/mount/captain hand-offs) is gathered into one list by
`creature:CalculateActiveModifiers` (Creature.lua:6571; `character:CalculateActiveModifiers` in
Character.lua:811 for heroes). Near the end, `creature:FilterModifiers` (Creature.lua:6593-6623)
evaluates each modifier's "Only if" formula with `CharacterModifier:PassesFilter`
(CharacterModifier.lua:4305) and drops the ones that are false. The result is what
`creature:GetActiveModifiers()` returns, cached per game update. So any modifier type whose
effect is computed by walking `GetActiveModifiers()` (or `GetActiveModifiersExcludingAuras`,
which is built by the same function and is also filtered) honours "Only if" for free, and the
condition is re-checked every game update. Aura modifiers are checked separately when they are
added (Creature.lua:6458). Three types set `filterRequiresRoll = true`, which makes `PassesFilter`
always say yes (CharacterModifier.lua:4311) so they can test the formula themselves later, with
roll or caster symbols. A type does **not** honour "Only if" when its effect is read some other
way: straight from `feature.modifiers` at build time, from a value saved onto the character when
a choice was made, or in a loop that runs before `FilterModifiers`.

While the filter is being evaluated, `GetActiveModifiers()` on the same creature returns the
half-built list with every conditional modifier removed (the recursion guard,
Creature.lua:6361-6363 plus the in-place removal at 6597-6605). So an "Only if" that reads a
stat changed by another conditional modifier (or by itself) sees the value **without** those
modifiers. It does not loop; it just ignores them.

## Per-type table

Verdicts: **Honoured**, **Partly**, **Not honoured**, **Unsafe** (works, but a conditional is
a trap or makes no sense), **Needs in-app test**.

| Type id | Display name | Verdict | Evidence (file:line) | Recommendation |
|---|---|---|---|---|
| `abilitycustomisation` | Ability Customisation | Not applicable | Never authored: injected per creature by `RegisterFeatureCalculation` (Draw Steel Core Rules/MCDModifyPowerRolls.lua:3683-3703); it has no editor. Applied through the filtered list (MCDMCreature.lua:3805-3812). | Don't allow Only if (system-generated, no UI). |
| `abilityimprovement` | Ability Improvement | Honoured | Read from caster's active list, DrawSteelActionBar/DrawSteelActionBar.lua:5121-5123. | Allow Only if. |
| `activated` | Activated Ability | Honoured | `fillActivatedAbilities` called over the active list: Creature.lua:4204/4240, Draw Steel Core Rules/MCDMCreature.lua:3668-3672. Sheets/builder list the ability from `feature.modifiers` regardless (Draw Steel V/DrawSteelChararcterSheet.lua:7930, Draw Steel V/HeroSheetFeatures.lua:211, Draw Steel Character Builder/FeatureCache.lua:1115) - display only. | Allow Only if. |
| `altspells` | Custom Spellcasting (5e) | Honoured | Creature.lua:4041-4045 (active list). | Allow Only if (5e only). |
| `alternateappearance` | Alternate Appearance | Needs in-app test | The list of looks is honoured (Draw Steel Modifiers/ModifierAlternateAppearance.lua:66-77), and its editor already shows the Only if field (:14). But choosing a look stores it on the token engine-side (`token:OverrideAlternateAppearance`, DMHub CharacterSheet Base/HeroSheetAppearance.lua:327). Whether the engine drops that look when the modifier goes inactive is not visible in Lua. | Test in app: apply a look, make the filter false, see if the token reverts. Allow only if it reverts. |
| `armorclasscalculation` | Armor Class Calculation (5e) | Honoured | Checks the filter itself (CharacterModifier.lua:1846-1847) and is read from the active list (Creature.lua:14268-14270, 14343-14345). | Allow Only if (5e only). |
| `attackattribute` | Attack Attribute (5e) | Honoured | Creature.lua:1639-1641. | Allow Only if (5e only). |
| `attribute` | Modify Attribute | Honoured | `CalculateAttribute` walks the active list (Creature.lua:7140-7147, 7198-7203). Builder display reads `feature.modifiers` (Draw Steel V/HeroBuildPools.lua:1419, FeatureCache.lua:2070) - display only. Caveat: a filter that reads an attribute sees it without any conditional modifiers (see intro). | Allow Only if. |
| `aura` | Aura | Honoured | `FillAuras` over `GetActiveModifiersExcludingAuras` (Creature.lua:14105-14109), which is filtered (Creature.lua:6399). | Allow Only if. |
| `bestowcondition` | Bestow Condition | Honoured | Explicit `PassesFilter` before bestowing: Creature.lua:7015-7020, 6471 (auras), Draw Steel Core Rules/MCDMCreature.lua:4512, 4561. Caveat: the 7015 check runs mid-build (comment at 7016), so the formula only sees modifiers gathered so far. | Allow Only if. |
| `castingorigin` | Casting Origin | Honoured (different meaning) | `filterRequiresRoll` (Draw Steel Modifiers/ModifierCastingOrigin.lua:6). The field is reused as "who may cast through me": evaluated against the caster, and **blank means nobody** (:250-256, used at :291-294). Its own editor edits it (:41-46). | Don't allow generic Only if: AND-ing a test into it changes its meaning (blank -> "anyone who passes"). |
| `companion` | Beastheart Companion | Honoured (with caution) | `GetCompanionType` walks the active list (Draw Steel Beastheart/DSModifierCompanion.lua:51-62); editor shows Only if (:13). It is normally emitted by the companion choice (Draw Steel Beastheart/DSCompanionChoice.lua:177). A filter using `HasCompanion` / `CompanionType` reads this same modifier (Draw Steel Beastheart/DSCompanion.lua:523-555). | Don't allow in the block editor (choice-generated; self-referencing symbols). |
| `conditionimmunity` | Condition Immunity | Honoured | Active list (Creature.lua:14177-14179, MCDMCreature.lua:4131-4132) and a second explicit check that treats an erroring formula as "no immunity" (CharacterModifier.lua:4346-4352). | Allow Only if. |
| `conditionsourcebestow` | Reciprocal Condition | Honoured | Read from the condition target's active list (Creature.lua:6983-6986). The filter is evaluated on the target (bearer), not the caster. | Allow Only if (say in the UI that "you" is the bearer). |
| `creaturetype` | Modify Creature Type | Honoured | Creature.lua:427-430, Character.lua:1067-1070. | Allow Only if. |
| `d20` | Modify D20 Rolls (5e) | Partly | `filterRequiresRoll` (DMHub Game Rules/ModifierD20Rolls.lua:164). The dialog path checks it (`canModifyD20Roll`, :272-277, via Creature.lua:7442). The automatic path does not: `ApplyModifiersToD20Roll` (Creature.lua:7452-7457) -> `ModifyD20RollDefaultBehavior` (CharacterModifier.lua:3594-3604) only consults `hintD20Roll` (ModifierD20Rolls.lua:198), which never reads `filterCondition`. | Add support: in `hintD20Roll`, return nil when `DoesD20ModifierPassFilter` fails (same call as :275). 5e only. |
| `damage` | Modify Damage (5e) | Honoured | `filterRequiresRoll` (DMHub Game Rules/ModifierDamageRolls.lua:30); `hintDamageRoll` evaluates it with attack/target symbols and returns nil on false (:123-127); callers drop nil hints (Creature.lua:7309-7311). | Allow Only if (5e only; formula sees roll symbols). |
| `expandsingletarget` | Expand Single Target | Honoured | Draw Steel Core Rules/MCDMActivatedAbility.lua:4977-4979. | Allow Only if. |
| `filter` | Filter | Honoured | Draw Steel Modifiers/ModifierFilter.lua:104-107. (Its own `filter` field is a separate target test.) | Allow Only if. |
| `forcedmovement` | Forced Movement | Honoured | Draw Steel Modifiers/ModifierForcedMovement.lua:126-130. | Allow Only if. |
| `grantSpellList` | Grant Spell List (5e) | Honoured | Creature.lua:3950-3957. | Allow Only if (5e only). |
| `grantSpells` | Grant Spells (5e) | Honoured | Creature.lua:3950-3957. | Allow Only if (5e only). |
| `grantkeyword` | Grant Keyword | Honoured (with caution) | `monster:Keywords()` walks the active list (Draw Steel Core Rules/MCDMMonster.lua:27-37). A filter using `Keywords` reads this same list mid-build. | Allow Only if; warn against testing Keywords in it. |
| `granttreasure` | Grant Treasure | Partly / one-time grant | Claim is built from `feature.modifiers`, not the active list: builder FeatureCache.lua:310-315, sheets Draw Steel V/HeroSheetFeatures.lua:1794, Draw Steel V/DrawSteelChararcterSheet.lua:8413-8415. Only the Manifest lookup is filtered (Draw Steel Modifiers/ModifierGrantTreasure.lua:741-749). A claimed item stays forever. | Don't allow Only if (one-time grant). |
| `growingresources` | Growing Resources Table | Honoured | Draw Steel Modifiers/ModifierGrowingResources.lua:154-160. | Allow Only if. |
| `icon` | Status Icon | Honoured | Creature.lua:1290, 1436-1437. | Allow Only if. |
| `ignoredifficultterrain` | Ignore Difficult Terrain | Honoured | DMHub Game Rules/ModifierMovementText.lua:658-686; used by `IgnoreDifficultTerrain` (MCDMCreature.lua:7523-7524) and by the engine per area. | Allow Only if. |
| `invisibility` | Invisibility | Honoured / Unsafe with "Concealed" | `onTokenRefresh` over the active list (Creature.lua:6073-6080). It stamps `_tmp_concealedInvisibleUpdate` (Draw Steel Modifiers/ModifierInvisibility.lua:15-19), which the next build counts as concealed (Creature.lua:6396). An Only if that tests `Concealed` would keep itself on. | Allow Only if; warn against `Concealed` in it. |
| `journalexplanation` | Journal Explanation | Honoured | Draw Steel Modifiers/ModifierJournalExplanation.lua:146-148. | Allow Only if. |
| `kitaccess` | Access to new types of kits | Partly | Whether kit features are added at all is decided by scanning raw `feature.modifiers` (Draw Steel Core Rules/MCDMCustomRules.lua:124-140). `KitTypesAllowed` / `CanHaveKits` are filtered (Draw Steel Core Rules/MCDMKit.lua:1108-1118). | Don't allow Only if (build-time access; a conditional kit makes no sense). |
| `light` | Light Source | Partly | The light list is filtered (Draw Steel Modifiers/ModifierLight.lua:73-80), but the chosen light is saved to `equipment.mainhand1` (Creature.lua:4426-4430; DMHub CharacterSheet Base/CharacterSheetAppearance.lua:3155) and stays when the filter goes false. | Don't allow Only if (it unlocks a choice). |
| `loyaltycollar` | Loyalty Collar | Honoured | Draw Steel Modifiers/ModifierLoyaltyCollar.lua:102-108. | Allow Only if. |
| `modcaptain` | Modify Squad Captain | Honoured (small gap) | Minion's active list feeds the captain (Draw Steel Core Rules/MCDMMonster.lua:1314-1316); editor shows Only if (Draw Steel Modifiers/ModifierCaptain.lua:25). Unlike `modcompanion`, `FillSquadCaptainModifiers` (:41-46) does not re-check the filter, so if the minion's list is read mid-build (recursion guard) a false filter can leak. | Allow Only if; add the one-line re-check (see infrastructure). |
| `modcompanion` | Modify Companion | Honoured | Re-checks its own filter (Draw Steel Beastheart/DSBeastheartModifyCompanion.lua:58); called over the active list (Draw Steel Beastheart/DSCompanion.lua:891-892). | Allow Only if. |
| `modifyability` | Modify Abilities | Honoured | Creature.lua:11545-11556, 4314-4316; MCDMCreature.lua:3805-3812; AbilityInvokeAbility.lua:1398-1400; PowerTableTriggers.lua:150-155. | Allow Only if. |
| `modifydamageaftersave` | Damage Multiplier After Save | Honoured | Draw Steel Ability Behaviors/AbilityDamage.lua:308-310. | Allow Only if. |
| `modifyresourcechecklist` | Modify Resource Checklist | Honoured | Draw Steel Core Rules/MCDMClass.lua:65-66. | Allow Only if. |
| `modifytrigger` | Modify Trigger | Honoured | Checks itself on every path: Draw Steel Core Rules/MCDMModifyTriggers.lua:918, 1262, 1398. | Allow Only if. |
| `modrider` | Modify Mount Riders | Honoured (small gap) | Mount's active list feeds the rider (Creature.lua:6843-6846); editor shows Only if (Draw Steel Core Rules/DSModifyMounts.lua:25). Same missing re-check as `modcaptain` (DSModifyMounts.lua:41-46). | Allow Only if; add the re-check. |
| `modsummoner` | Modify Summoner | Honoured | Re-checks its own filter in both directions (DSBeastheartModifyCompanion.lua:160, 184). | Allow Only if. |
| `monstermodes` | Monster Modes | Unsafe | Honoured (MCDMCreature.lua:9152-9154), but the type's own comment says not to filter it on Monster Mode, since the mode picker must exist in every mode (MCDMCreature.lua:9241-9243). It is a declaration with no effect of its own. | Don't allow Only if. |
| `movementcarrier` | Movement Carrier | Honoured | Only read from ongoing effects, and checks the filter itself (Draw Steel Modifiers/ModifierMovementCarrier.lua:183-189). | Allow Only if. |
| `movementrestriction` | Movement Restriction | Honoured / Needs in-app test | Built from the active list (MCDMCreature.lua:8836-8856) but cached in `_tmp_movementRestrictionCalculation` until `creature:Invalidate` (MCDMCreature.lua:168, 8876-8883). A filter that depends on other tokens may go stale. | Allow Only if; test that the restriction lifts when the filter turns false. |
| `movementtext` | Reminder Text | Honoured | DMHub Game Rules/ModifierMovementText.lua:487-489; Draw Steel UI/DSHud.lua:386-388. | Allow Only if. |
| `multiattack` | Multiple Attacks | Not applicable | No hooks beyond an editor (CharacterModifier.lua:2431-2443) and nothing reads it. | Don't allow (type has no effect). |
| `power` | Modify Power Rolls | Honoured | Active list (MCDMCreature.lua:5271-5300) plus its own re-check (MCDModifyPowerRolls.lua:820, 857); embedded-in-ability modifiers checked separately (MCDMAbilityRollBehavior.lua:1507-1510, MCDMActivatedAbility.lua:1962-1964); free strikes (MCDMAbilityBehavior.lua:2301). The filter is evaluated with caster symbols only, no Target. | Allow Only if. |
| `powertableadditional` | Power Roll Trigger Addition | Honoured | Draw Steel Modifiers/ModifierRollAdditional.lua:109-112. | Allow Only if. |
| `powertabletrigger` | Power Roll Trigger | Honoured | Every token's active list: MCDMAbilityRollBehavior.lua:1905-1909, 4083-4086; DrawSteelActionBar.lua:12946-12948; Draw Steel UI/DSActionBar.lua:1693. | Allow Only if. |
| `proficiency` | Grant Skill or Language | Honoured (builder caveat) | Skills: Character.lua:440-447; languages: Creature.lua:1456-1459; builder tallies from the active list (Draw Steel Character Builder/HeroSkillsLanguages.lua:516-518). A "fixed grants" summary reads raw `feature.modifiers` (Draw Steel V/HeroBuildPools.lua:3646-3650) - display only. If the condition is false while building, the builder will not count the grant and may offer it again. | Allow Only if, with care. |
| `resistance` | Damage Immunity | Honoured | Creature.lua:3715-3717; token hover lists only filtered ones (Draw Steel UI/DrawSteelTokenHud.lua:397-399). | Allow Only if. |
| `resource` | Grant Resource | Honoured | Creature.lua:7557-7561, 7236-7240. Builder/sheet only read it to display or edit custom values (FeatureCache.lua:2091, Draw Steel V/HeroSheetWrite.lua:499). | Allow Only if. |
| `rollsattacking` | Rolls Attacking Us (5e) | Honoured | Creature.lua:7413-7415, 7333-7335. | Allow Only if (5e only). |
| `routine` | Routine | Honoured | `GetRoutines` (Draw Steel Core Rules/DSModifyRoutine.lua:297-304). Note: the "routine blocks later modifiers until selected" rule (DMHub Game Rules/CharacterFeature.lua:114-117) ignores the filter, so a selected-but-filtered routine still unblocks its siblings. | Allow Only if. |
| `spell` | Innate Spellcasting (5e) | Honoured | Creature.lua:4204/4240. | Allow Only if (5e only). |
| `spellcasting` | Spellcasting (5e) | Honoured | Creature.lua:3950-3953; multiclass count also filtered (DMHub Game Rules/ModifierSpellcasting.lua:52-58). | Allow Only if (5e only). |
| `suppressabilities` | Suppress Abilities | Honoured | `modifyAbility` over the active list (same callers as `modifyability`). | Allow Only if. |
| `suspended` | Suspended In Air | Honoured / Needs in-app test | Set from the active list each refresh (Creature.lua:6012 clears, 6073-6080 sets via Draw Steel Modifiers/ModifierSuspended.lua:10-12). Nothing in Lua reads `_tmp_suspended`; the consumer is presumably the engine. | Allow Only if; confirm in app the creature lands when the filter turns false. |
| `tokenvisual` | Token Visual Effect | Honoured | Draw Steel Modifiers/ModifierTokenVisual.lua:93-104 (polled by the driver, :170). | Allow Only if. |
| `transform` | Transformation | Partly | Most hooks use the active list, but two loops run inside `FillTemporalActiveModifiers` **before** filtering: `addModifiers` (Creature.lua:6917-6927, injects the beast's modifiers) and `preventsEquipment` (Creature.lua:6929-6934, skips all equipment). Also `originalSize` is recorded from raw ongoing-effect modifiers (Creature.lua:8556-8562). | Add support: guard those two loops with `mod.mod:PassesFilter(self, mod)`. Until then, don't allow. |
| `trigger` | Triggered Ability | Honoured | Creature.lua:11573-11577, 11717-11730, 12300-12317; MCDMCreature.lua:7544-7547. Editors / Monster AI reports read raw `feature.modifiers` (Draw Steel Ability Editor/NewTriggeredAbilityEditor.lua:2979-2990, Monster AI/MonsterAISupport.lua:243) on purpose, display only. | Allow Only if. |
| `triggerdisplay` | Triggered Ability Display | Honoured | `GetTriggeredActions` (Draw Steel Core Rules/DSModifyTriggerDisplay.lua:662-669). Sheets list it from `feature.modifiers` (display only). | Allow Only if. |

61 registered types. `none` (CharacterModifier.lua:435) and `kitmodifyability`
(Draw Steel Core Rules/MCDMKit.lua:785) have TypeInfo but are never registered, so they are
not authorable and are left out.

Tally: 50 Honoured (some with a caveat), 5 Partly (`d20`, `transform`, `kitaccess`,
`granttreasure`, `light`), 3 Needs in-app test (`alternateappearance`, `movementrestriction`,
`suspended`), 1 Unsafe (`monstermodes`), 2 not applicable (`multiattack`,
`abilitycustomisation`), plus the honoured-but-caution cases noted in the table
(`castingorigin`, `companion`, `invisibility`, `grantkeyword`, `proficiency`).

## Infrastructure changes to add support where it is missing (smallest first)

1. **`transform`**: in `creature:FillTemporalActiveModifiers`, add `and mod.mod:PassesFilter(self, mod)`
   to the `AddModifiers` loop (Creature.lua:6918-6920) and the `PreventsEquipment` loop
   (Creature.lua:6930-6931). Two lines.
2. **`modcaptain` / `modrider`**: add `if not self:PassesFilter(creature, context) then return end`
   to `CharacterModifier:FillSquadCaptainModifiers` (Draw Steel Modifiers/ModifierCaptain.lua:41)
   and `CharacterModifier:FillRiderModifiers` (Draw Steel Core Rules/DSModifyMounts.lua:41),
   copying `FillCompanionModifiers` (DSBeastheartModifyCompanion.lua:58). Guards against the
   pre-filter list handed out by the recursion guard.
3. **`d20`**: in `hintD20Roll` (DMHub Game Rules/ModifierD20Rolls.lua:198), return nil when
   `DoesD20ModifierPassFilter(self, self.filterCondition, creature, rollType, options)` is false.
   This fixes the auto-apply path (`ApplyModifiersToD20Roll`). 5e only, so low priority.
4. **Condition-rule modifiers skip the filter for every type.** `creature:CalculateConditionModifiers`
   (Creature.lua:6628-6641) appends the modifiers of rule-driven conditions **after**
   `FilterModifiers` has run (Creature.lua:6584-6587). In Draw Steel the one rule adds
   "Unbalanced" when Stamina is at or below zero (Draw Steel Core Rules/MCDMRules.lua:1324-1331),
   so an Only if on any modifier inside that condition is ignored. Fix: check
   `mod:PassesFilter(self)` before appending, or append before filtering.
5. **Latent bug, not used today:** `creature:FillModifiersFromModifiers` (Creature.lua:6553-6562)
   appends the whole `result` table instead of each `mod`. No type defines `fillModifiers`, so it
   is dormant, but anyone adding that hook will get broken entries.
6. **Display readers of raw `feature.modifiers`** (builder/sheet ability lists, HeroBuildPools
   fixed grants, Monster AI reports, listed in the table) always show conditional grants. Fine
   for "what this feature gives"; change only if a design wants "currently active" there.
7. **Persisted choices** (`light`, `granttreasure`, `alternateappearance`) would need the stored
   choice re-validated against the filtered list on every read. Not small; better to not offer
   Only if on these.
8. **`kitaccess`**: would need `MCDMCustomRules.lua:124-140` to evaluate filters on features
   that are still being collected (no creature context yet). Not worth it.

## Which block-editor types should declare `supportsFilter = true` now

Per BLOCK_EDITOR_CODING_PLAN.md section 4.7, Logic AND-s its test into each child's
`filterCondition`. Declare `supportsFilter = true` for:

`abilityimprovement`, `activated`, `attribute`, `aura`, `bestowcondition`, `conditionimmunity`,
`conditionsourcebestow`, `creaturetype`, `expandsingletarget`, `filter`, `forcedmovement`,
`grantkeyword`, `growingresources`, `icon`, `ignoredifficultterrain`, `invisibility`,
`journalexplanation`, `loyaltycollar`, `modcaptain`, `modcompanion`, `modifyability`,
`modifydamageaftersave`, `modifyresourcechecklist`, `modifytrigger`, `modrider`, `modsummoner`,
`movementcarrier`, `movementtext`, `power`, `powertableadditional`, `powertabletrigger`,
`proficiency`, `resistance`, `resource`, `routine`, `suppressabilities`, `tokenvisual`,
`trigger`, `triggerdisplay`.

If the block editor ever exposes the 5e types, these are also safe: `altspells`,
`armorclasscalculation`, `attackattribute`, `damage`, `grantSpellList`, `grantSpells`,
`rollsattacking`, `spell`, `spellcasting`.

Declare **true after a fix**: `transform` (item 1), `d20` (item 3). These fixes are parked as follow-ups in [`FOLLOW_UP_ITEMS.md`](FOLLOW_UP_ITEMS.md).
Declare **true after an in-app test passes**: `alternateappearance`, `movementrestriction`,
`suspended`.

Keep **false**: `castingorigin` (the field has its own meaning; blank means "no one"),
`companion` (choice-generated, self-referencing symbols), `granttreasure`, `kitaccess`, `light`
(one-time grants or unlocked choices), `monstermodes` (declaration; must exist in every mode),
`multiattack` (no effect), `abilitycustomisation` (system-generated).

Gotchas to put in the Logic wrapper's help text:
- The test is about the modifier's **bearer**, even for hand-offs (`modcaptain` on the minion,
  `modrider` on the mount, `conditionsourcebestow` on the condition's target).
- `power` evaluates it with no Target; `damage`/`d20` evaluate it at roll time.
- A test that reads a stat changed by another conditional modifier sees the stat without it.
- Don't test `Concealed` on Invisibility or `Keywords` on Grant Keyword.
