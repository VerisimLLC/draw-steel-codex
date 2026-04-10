# File Index

All Lua files loaded by `main.lua`, organized by module. This index covers every `require` statement in the project entry point.

---

## Large Modules (10+ files)

### Draw_Steel_Core_Rules_1b8f

The main game rules module for Draw Steel. Contains creature definitions, class logic, initiative, kits, monsters, and all core rule implementations.

| File | Description |
|------|-------------|
| PowerTableTriggers.lua | Power roll table trigger definitions |
| MCDMRules.lua | Top-level Draw Steel rule registration |
| DSAugmentAbilities.lua | Ability augmentation system |
| DSCareer.lua | Career type definition |
| DSCultureAspect.lua | Culture aspect components |
| DSLanguageChoice.lua | Language selection during character creation |
| DSCulture.lua | Culture type definition |
| DSModifyMounts.lua | Mount modification rules |
| DSPowerRollTables.lua | Power roll result tables |
| DSResources.lua | Draw Steel resource types (surges, hero tokens, etc.) |
| DSSkillChoice.lua | Skill selection during character creation |
| DSSuppressAbilities.lua | Ability suppression logic |
| DSTemporaryHitpoints.lua | Temporary stamina handling |
| MCDMAbilityBehavior.lua | Base ability behavior framework |
| MCDMAbilityModBehavior.lua | Ability modification behaviors |
| MCDMAbilityModifyCast.lua | Cast-time ability modifications |
| MCDMAbilityRollBehavior.lua | Roll-based ability behaviors |
| MCDMAbilitySaveBehavior.lua | Save-based ability behaviors |
| MCDMActionBar.lua | Action bar configuration |
| MCDMActivatedAbility.lua | Activated ability type definition |
| MCDMActivatedAbilityCast.lua | Activated ability casting logic |
| MCDMAttack.lua | Attack resolution system |
| MCDMCharSheet.lua | Character sheet data layer |
| MCDMCharacterBuilder.lua | Character builder logic |
| MCDMCharacterPanel.lua | Character panel UI integration |
| MCDMCharacterSheet.lua | Character sheet UI |
| MCDMCharSheetImport.lua | Character sheet import support |
| MCDMClass.lua | Class type definition |
| MCDMClassCarousel.lua | Class selection carousel |
| MCDMCommands.lua | Chat command definitions |
| MCDMCreature.lua | Core creature type for Draw Steel |
| MCDMCustomRules.lua | Custom rule overrides |
| MCDMImporterCompendium.lua | Importer compendium integration |
| MCDMInitiativeBar.lua | Initiative bar UI |
| MCDMInitiativeQueue.lua | Initiative queue logic |
| MCDMKit.lua | Kit type definition |
| MCDMKitBuilderPanel.lua | Kit builder panel UI |
| MCDMKitEditor.lua | Kit editor UI |
| MCDMLocUtils.lua | Localization utilities |
| MCDMMinion.lua | Minion creature handling |
| MCDMMonster.lua | Monster type definition |
| MCDMMonsterGroup.lua | Monster group encounters |
| MCDModifyPowerRolls.lua | Power roll modification system |
| MCDMOngoingEffects.lua | Ongoing effect management |
| MCDMPanels.lua | Rule-specific panel registrations |
| MCDMSkills.lua | Skill definitions |
| MCDMSymbols.lua | GoblinScript symbol definitions |
| MCDMUtils.lua | Shared utility functions |
| DSConditionRider.lua | Condition rider effects |
| DSRuleUtils.lua | Draw Steel rule utilities |
| DSModifyTriggerDisplay.lua | Trigger display modifications |
| DSModifyRoutine.lua | Routine modification logic |
| DSAncestryInheritance.lua | Ancestry inheritance rules |
| MCDMDeities.lua | Deity definitions |
| MCDMPrerequisite.lua | Prerequisite evaluation |
| DSComplications.lua | Complication system |
| MCDMFollowers.lua | Follower system rules |
| DSFollower.lua | Follower type definition |
| DSCharacterDescription.lua | Character description fields |
| DSModifyHRChecklist.lua | Hero resource checklist modifications |
| DSImbuement.lua | Imbuement system |
| DSAbilityImprovement.lua | Ability improvement logic |
| MCDMModifyTriggers.lua | Trigger modification system |

### DMHub_Core_Panels_65a9

Core UI panels for the DMHub application. Contains map tools, chat, audio, and all major editor panels.

| File | Description |
|------|-------------|
| GoblinScriptDebugger.lua | GoblinScript debugging tool |
| Chat.lua | Chat panel |
| Floors.lua | Floor/level management |
| Terrain.lua | Terrain painting tools |
| CharacterPanel.lua | Character panel sidebar |
| Tilesheet.lua | Tilesheet management |
| Brush.lua | Map brush tools |
| Objects.lua | Object placement panel |
| ObjectPropertiesDialog.lua | Object property editor dialog |
| CreateEffectDialog.lua | Visual effect creation dialog |
| Weather.lua | Weather effects panel |
| Audio.lua | Audio playback panel |
| MapSettings.lua | Map configuration settings |
| ModShare.lua | Module sharing panel |
| TimeOfDay.lua | Time of day controls |
| OnlineUsers.lua | Connected users panel |
| DebugLog.lua | Debug log viewer |
| Commands.lua | Command registration |
| ObjectImport.lua | Object import dialog |
| DicePanel.lua | Dice rolling panel |
| Devtools.lua | Developer tools |
| AudioImport.lua | Audio file import |
| MapImport.lua | Map import dialog |
| StatusPanel.lua | Status display panel |
| VisionPerspective.lua | Vision/perspective controls |
| ClipboardPanel.lua | Clipboard management |
| Layers.lua | Map layer management |
| GameControls.lua | Game session controls |
| Tutorial.lua | Tutorial system |
| InteractiveObject.lua | Interactive object setup |
| MapsPanel.lua | Map browser panel |
| CreateMapDialog.lua | New map creation dialog |
| DrawingPanel.lua | Freehand drawing tools |
| AIImporter.lua | AI-assisted content import |
| GoblinScriptEditor.lua | GoblinScript formula editor |
| Theme.lua | UI theme configuration |
| GoblinScriptDocs.lua | GoblinScript documentation viewer |
| InfoDocument.lua | Info document display |
| InfoBubble.lua | Hover info bubble |
| AIPanel.lua | AI assistant panel |
| AICore.lua | AI integration core |
| APIDocumentation.lua | API documentation viewer |
| Journal.lua | Journal/notes panel |
| JournalPDFViewer.lua | PDF viewer for journal entries |
| BackupsPanel.lua | Backup management panel |
| ElevationPanel.lua | Elevation editing panel |
| Questboard.lua | Quest tracking board |

### DMHub_Game_Rules_fc51

The generic game rules engine. Contains base types for creatures, classes, spells, equipment, and all system-agnostic rule primitives.

| File | Description |
|------|-------------|
| DamageFlags.lua | Damage flag definitions |
| BasicRules.lua | Core rule primitives |
| CustomFields.lua | Custom field system |
| Skills.lua | Skill type definitions |
| ProficiencyLevel.lua | Proficiency level system |
| MeasurementSystem.lua | Unit measurement configuration |
| RollableTables.lua | Rollable random table system |
| Variant.lua | Rule variant support |
| Anim.lua | Animation definitions |
| DamageTypes.lua | Damage type registry |
| Projectile.lua | Projectile effect system |
| Language.lua | Language type definitions |
| Party.lua | Party management |
| Currency.lua | Currency system |
| Condition.lua | Condition type definitions |
| Feat.lua | Feat type definition |
| Prerequisite.lua | Prerequisite evaluation system |
| CharacterFeature.lua | Character feature framework |
| FeaturePrefab.lua | Feature prefab templates |
| InitiativeQueue.lua | Base initiative queue |
| CharacterType.lua | Character type system |
| GlobalRuleMod.lua | Global rule modification system |
| Background.lua | Background type definition |
| Aura.lua | Aura effect system |
| AttackTriggeredAbility.lua | Attack-triggered ability system |
| ActivatedAbilityCast.lua | Activated ability casting framework |
| ActivatedAbility.lua | Activated ability base type |
| AbilityTransform.lua | Ability transformation behavior |
| AbilitySummon.lua | Summoning ability behavior |
| Loot.lua | Loot generation system |
| Equipment.lua | Equipment type definition |
| CreatureFilter.lua | Creature filtering/search |
| EquipmentCategory.lua | Equipment category definitions |
| Creature.lua | Core creature type definition |
| RuleUtils.lua | Rule utility functions |
| Character.lua | Player character type |
| Monster.lua | Monster type definition |
| Spells.lua | Spell type definitions |
| SpellcastingFeature.lua | Spellcasting feature system |
| Attack.lua | Attack type definition |
| Concentration.lua | Concentration tracking |
| OngoingEffect.lua | Ongoing effect type |
| Resource.lua | Resource type definitions |
| CharacterModifier.lua | Character modifier framework |
| ModifierD20Rolls.lua | D20 roll modifiers |
| ModifierDamageRolls.lua | Damage roll modifiers |
| ModifierProficiency.lua | Proficiency modifiers |
| ModifierModifyAbilities.lua | Ability modification modifiers |
| Class.lua | Class type definition |
| Race.lua | Race/Ancestry type definition |
| Light.lua | Light source system |
| Vision.lua | Vision type definitions |
| CustomAttribute.lua | Custom attribute system |
| ModifierGrantSpells.lua | Spell-granting modifiers |
| ModifierSpellcasting.lua | Spellcasting modifiers |
| ModifierDamageAfterSave.lua | Post-save damage modifiers |
| ModifierGrantSpellList.lua | Spell list granting modifiers |
| BaseAttributes.lua | Base attribute definitions |
| AbilityRemoveCreature.lua | Creature removal ability behavior |
| AbilityRelocateCreature.lua | Creature relocation ability behavior |
| AbilityPurgeEffects.lua | Effect purge ability behavior |
| AbilityDropItems.lua | Item drop ability behavior |
| ProficiencyLevels.lua | Proficiency level configuration |
| GoblinScriptDocs.lua | GoblinScript documentation entries |
| AbilitySavingThrow.lua | Saving throw ability behavior |
| TriggeredAbility.lua | Triggered ability type |
| AttributeGenerator.lua | Attribute generation system |
| BackgroundCharacteristic.lua | Background characteristic tables |
| AbilityReplenish.lua | Resource replenish ability behavior |
| WeaponProperty.lua | Weapon property definitions |
| AbilityCreateItem.lua | Item creation ability behavior |
| GameSystem.lua | Game system registration framework |
| dnd5e.lua | D&D 5e game system adapter |
| FeaturePrefabInstance.lua | Feature prefab instance handling |
| ModifierAltSpells.lua | Alternative spell modifiers |
| ModifierGrantFeat.lua | Feat-granting modifiers |
| AbilitySkillCheck.lua | Skill check ability behavior |
| AbilityFizzle.lua | Ability fizzle behavior |
| AbilityResetRollStatus.lua | Roll status reset behavior |
| AbilityRoll.lua | Generic roll ability behavior |
| AbilityInvokeAbility.lua | Ability invocation behavior |
| AbilityFloatText.lua | Floating text ability behavior |
| AbilityTableRoll.lua | Table roll ability behavior |
| ModifierBestowCondition.lua | Condition-bestowing modifiers |
| ModifierConditionSourceBestow.lua | Condition source bestowing |
| ActivatedAbilityReaction.lua | Reaction ability handling |
| CharacterPanelGameRules.lua | Character panel game rule hooks |
| ModifierCreatureType.lua | Creature type modifiers |
| AbilityCreatureSet.lua | Creature set ability behavior |
| AbilityLimit.lua | Ability usage limit behavior |
| AbilityMovementType.lua | Movement type ability behavior |
| AbilityInitiative.lua | Initiative ability behavior |
| AbilityConditionSource.lua | Condition source ability behavior |
| AbilityCustomTrigger.lua | Custom trigger ability behavior |
| AbilityScript.lua | Script execution ability behavior |
| AbilityApplyRiders.lua | Rider effect application behavior |
| AbilityDelay.lua | Delay ability behavior |
| AbilityOrderTargets.lua | Target ordering ability behavior |
| ModifierMovementText.lua | Movement text modifiers |
| Path.lua | Path/subclass definitions |
| QuestboardQuests.lua | Quest definitions for the questboard |
| Titles.lua | Title definitions |

### Draw_Steel_Character_Builder_45c3

The Draw Steel character builder wizard. Handles step-by-step character creation with ancestry, culture, career, class, and kit selection.

| File | Description |
|------|-------------|
| CharacterAttributeChoice.lua | Attribute selection step |
| CharComplicationChoice.lua | Complication selection step |
| CharacterCultureChoice.lua | Culture selection step |
| CharacterIncidentChoice.lua | Inciting incident selection step |
| CharacterKitChoice.lua | Kit selection step |
| CharacterTitleChoice.lua | Title selection step |
| State.lua | Builder state machine |
| CharacterBuilder.lua | Main builder orchestration |
| FeatureCache.lua | Feature caching for builder |
| SelectionStatus.lua | Selection validation status |
| DescriptionStatus.lua | Description completion status |
| Styles.lua | Builder UI styles |
| CharacterPanel.lua | Builder character panel |
| FeatureSelector.lua | Feature selection widget |
| AncestryDetail.lua | Ancestry detail view |
| CultureDetail.lua | Culture detail view |
| CareerDetail.lua | Career detail view |
| ClassDetail.lua | Class detail view |
| DescriptionDetail.lua | Description detail view |
| ComplicationDetail.lua | Complication detail view |
| KitDetail.lua | Kit detail view |
| TitleDetail.lua | Title detail view |
| Selectors.lua | Shared selector components |
| MainPanel.lua | Builder main panel layout |

### Downtime_Projects_c618

Downtime project system for between-adventure activities. Covers project creation, rolling, sharing, and the Director management panel.

| File | Description |
|------|-------------|
| DTConstant.lua | Downtime constants (single) |
| DTConstants.lua | Downtime constants collection |
| DTHelpers.lua | Shared helper functions |
| DTFollowers.lua | Follower integration for projects |
| DTSettings.lua | Downtime settings |
| DTProgressItem.lua | Progress item tracking |
| DTRoll.lua | Downtime roll handling |
| DTAdjustment.lua | Roll adjustment system |
| DTProject.lua | Project type definition |
| DTInfo.lua | Project info display |
| DTShares.lua | Project sharing system |
| DTBusinessRules.lua | Business rule validation |
| DTUIComponents.lua | Shared UI components |
| DTSelectItemDialog.lua | Item selection dialog |
| DTConfirmationDialog.lua | Confirmation dialog |
| DTAdjustmentDialog.lua | Roll adjustment dialog |
| DTShareDialog.lua | Project sharing dialog |
| DTRoller.lua | Dice roller for projects |
| DTProjectRollDialog.lua | Project roll dialog |
| DTProjectEditor.lua | Project editor panel |
| DTCharSheetTab.lua | Character sheet downtime tab |
| DTGrantRollsDialog.lua | Grant rolls dialog |
| DTDirectorPanel.lua | Director management panel |
| Main.lua | Module entry point |

### DocumentSystem_3045

Rich document system for in-game journals, handouts, and embedded interactive widgets.

| File | Description |
|------|-------------|
| DocumentSystem.lua | Core document framework |
| MarkdownDocument.lua | Markdown document renderer |
| MontageDocument.lua | Montage document type |
| RichImage.lua | Embedded image widget |
| Bar.lua | Progress bar widget |
| LinkResolution.lua | Internal link resolution |
| RichEncounter.lua | Embedded encounter widget |
| RichSetting.lua | Embedded setting widget |
| RichParty.lua | Embedded party widget |
| RichCounter.lua | Counter widget |
| RichCheckbox.lua | Checkbox widget |
| RichAudio.lua | Audio player widget |
| RichMacro.lua | Macro execution widget |
| MarkdownLabel.lua | Markdown label component |
| MarkdownDocCreate.lua | Document creation dialog |
| DocumentNewUser.lua | New user onboarding document |
| RichTimer.lua | Timer widget |
| RichScene.lua | Scene transition widget |
| RichFollower.lua | Follower display widget |
| RichDice.lua | Dice roller widget |
| RichFishing.lua | Fishing mini-game widget |
| MarkdownDisplay.lua | Markdown display component |
| TextStorage.lua | Text storage backend |
| RichDrawsteel.lua | Draw Steel-specific widgets |
| RichReminder.lua | Reminder widget |

### Draw_Steel_Ability_Behaviors_aef5

Ability behavior implementations for Draw Steel. Each file defines a specific behavior that can be attached to activated abilities.

| File | Description |
|------|-------------|
| AbilityChangeElevation.lua | Change elevation behavior |
| AbilityChangeTerrain.lua | Terrain modification behavior |
| AbilityTemporaryEffects.lua | Temporary effect application |
| AbilityFall.lua | Falling behavior |
| AbilityDestroyCreature.lua | Creature destruction behavior |
| AbilityRecoverSelection.lua | Recovery selection behavior |
| AbilityDisguise.lua | Disguise behavior |
| AbilityDamage.lua | Damage dealing behavior |
| AbilityRaiseCorpse.lua | Corpse raising behavior |
| AbilityForcedMovementLoc.lua | Location-based forced movement |
| AbilityRecastAbility.lua | Ability recast behavior |
| AbilityMemory.lua | Memory storage behavior |
| AbilityPayCost.lua | Cost payment behavior |
| AbilityOpposedPowerRoll.lua | Opposed power roll behavior |
| AbilityRevertLocation.lua | Location revert behavior |
| AbilityPersistentCast.lua | Persistent cast behavior |
| AbilityCharacterSpeech.lua | Character speech behavior |
| AbilityMacro.lua | Macro execution behavior |
| AbilityRoutineCast.lua | Routine cast behavior |
| AbilityStealAbility.lua | Ability theft behavior |
| AbilityCreateObject.lua | Object creation behavior |
| AbilityTargetLocs.lua | Target location selection |
| AbilityAddNewTargets.lua | Additional target selection |

### DMHub_Game_Hud_efeb

Game HUD module. Contains the action bar, initiative bar, roll dialogs, interactive objects, and all in-game overlay UI.

| File | Description |
|------|-------------|
| GameHud.lua | Main game HUD framework |
| ActionBar.lua | Player action bar |
| InitiativeBar.lua | Initiative tracker bar |
| DockablePanel.lua | HUD dockable panel system |
| DeathScreen.lua | Death/dying screen overlay |
| NetworkStatus.lua | Network connection status |
| RequireDCDialog.lua | DC requirement dialog |
| Journal.lua | In-game journal access |
| ModalDialog.lua | Modal dialog framework |
| RulerTool.lua | Distance ruler tool |
| RollDialog.lua | Dice roll dialog |
| RestDialog.lua | Rest/recovery dialog |
| Interactive.lua | Interactive element handling |
| InteractiveSign.lua | Interactive sign objects |
| Importer.lua | HUD import integration |
| Keybinds.lua | Keyboard binding configuration |
| ObjectKeyFrame.lua | Object keyframe animation |
| ObjectEventHandler.lua | Object event handling |
| RollOnTableDialog.lua | Roll-on-table dialog |
| FullscreenDisplay.lua | Fullscreen image/text display |
| Macros.lua | Macro system integration |
| GameHudMenu.lua | Game HUD context menu |

### DMHub_Core_UI_752e

Core UI framework. Contains the base panel system, dropdown menus, scrollable containers, and shared UI utilities.

| File | Description |
|------|-------------|
| DefaultStyles.lua | Default UI style definitions |
| Dropdown.lua | Dropdown menu component |
| Gui.lua | Core GUI framework |
| Hud.lua | Base HUD system |
| GuiUtils.lua | GUI utility functions |
| MarkdownLabel.lua | Markdown-enabled label |
| SetEditor.lua | Set/collection editor widget |
| SettingsGui.lua | Settings panel GUI |
| Utils.lua | UI utility functions |
| ParticleValue.lua | Particle value display |
| Scrollable.lua | Scrollable container |
| EnumeratedSliderControl.lua | Enumerated slider widget |
| DockablePanel.lua | Dockable panel framework |
| Multiselect.lua | Multi-select widget |
| UISettings.lua | UI settings management |
| IconEditor.lua | Icon editor widget |
| ProgressDice.lua | Progress dice display |
| EnhIconButton.lua | Enhanced icon button |
| CharacterSelect.lua | Character selection widget |
| ActionButton.lua | Action button component |
| DialogResize.lua | Dialog resize handling |

### Draw_Steel_UI_bd58

Draw Steel-specific UI components. Contains the token HUD, action bar, character builder panels, and Draw Steel dialog windows.

| File | Description |
|------|-------------|
| Main.lua | Module entry point |
| DrawSteelTokenHud.lua | Draw Steel token HUD overlay |
| DSActionBar.lua | Draw Steel action bar |
| DSCareerBuilder.lua | Career builder panel |
| DSClassEditor.lua | Class editor panel |
| DSCultureBuilder.lua | Culture builder panel |
| DSHud.lua | Draw Steel HUD integration |
| DSInitiativeRoll.lua | Initiative roll dialog |
| DSInventoryCompendium.lua | Inventory compendium panel |
| DSInventoryEditor.lua | Inventory editor panel |
| DSKeywordPicker.lua | Keyword picker widget |
| DSMaliceCompendium.lua | Malice abilities compendium |
| DSRequestRollsDialog.lua | Request rolls dialog |
| DSRollDialog.lua | Draw Steel roll dialog |
| DSTriggerBar.lua | Trigger bar UI |
| DSDeitiesCompendium.lua | Deities compendium panel |
| PopupOverrideAttribute.lua | Attribute override popup |

### DMHub_Compendium_c080

Compendium system for browsing and editing game content. Contains editors for classes, backgrounds, items, abilities, and the compendium browser.

| File | Description |
|------|-------------|
| GlobalRuleModEditor.lua | Global rule mod editor |
| ClassEditor.lua | Class editor |
| BackgroundEditor.lua | Background editor |
| RaceEditor.lua | Race/Ancestry editor |
| Compendium.lua | Compendium browser panel |
| ManageCompendium.lua | Compendium management panel |
| ItemEditor.lua | Item editor |
| ActivatedAbilityEditor.lua | Activated ability editor |
| TriggeredAbilityEditor.lua | Triggered ability editor |
| OngoingEffectEditor.lua | Ongoing effect editor |
| CodeMod.lua | Code modification system |
| Translation.lua | Translation/localization support |
| ItemCompendium.lua | Item compendium panel |
| GameSystemCompendium.lua | Game system compendium |
| AICompendium.lua | AI-assisted compendium features |

### Draw_Steel_V_567e

Draw Steel version-specific features. Contains the encounter panel, negotiation system, downtime, fishing, and the heroes panel.

| File | Description |
|------|-------------|
| ResourceChat.lua | Resource tracking in chat |
| EncounterPanel.lua | Encounter management panel |
| HeroesPanel.lua | Heroes overview panel |
| CollapsedDiceRollPanel.lua | Collapsed dice roll display |
| Negotiation.lua | Negotiation UI |
| NegotiationRules.lua | Negotiation rule system |
| DowntimeProject.lua | Downtime project integration |
| FishingPanel.lua | Fishing mini-game panel |
| SkillsDialog.lua | Skills dialog |
| DrawSteelChararcterSheet.lua | Draw Steel character sheet |
| Questboard.lua | Quest board panel |
| FollowersTab.lua | Followers tab |
| Chessboard.lua | Chessboard mini-game |

### Development_Utilities_aa55

Development and debugging tools for module authors.

| File | Description |
|------|-------------|
| GoblinScriptDebugger.lua | GoblinScript expression debugger |
| TriggerDebugger.lua | Trigger/event debugger |
| Macros.lua | Development macro tools |
| CharacterInspector.lua | Character data inspector |
| Example.lua | Example code templates |
| RegexMatcher.lua | Regex testing tool |
| DevTools.lua | General developer tools |
| AudioDev.lua | Audio development tools |
| FontMap.lua | Font/glyph map viewer |
| ControlZoo.lua | UI control showcase |
| RandomTestPanel.lua | Random test generation panel |
| Blur.lua | Blur effect testing |
| AbilityDebugBehavior.lua | Ability debug behavior |

---

## Smaller Modules

| Module | Files | Purpose |
|--------|-------|---------|
| DMHub_Titlescreen_6089 | 6 | Title screen, styles, and settings |
| DMHub_Utils_5b73 | 8 | Core utilities, GoblinScript, coroutines, markdown |
| Codex_Quotes_2aae | 2 | Quote registry and display |
| Draw_Steel_Importers_3466 | 3 | Monster and rules importers |
| Draw_Steel_Audio_06c8 | 2 | Audio surface types and audio main |
| Codex_Macros_ac16 | 2 | Macro system and timer macros |
| DMHub_CharacterSheet_Base_b03e | 5 | Base character sheet framework |
| Great_Library_Macros_a4ba | 1 | Great Library macro collection |
| Monster_AI_d7b4 | 5 | Monster AI behavior, tactics, and prompts |
| DelianTomb_046b | 1 | Delian Tomb starter adventure |
| Potency_Adjustment_Mod_b741 | 1 | Potency adjustment system |
| Chat_Enhancements_6e49 | 3 | Chat enhancements (in-character, whisper) |
| Image_Zoo_8f12 | 1 | Image browser/zoo |
| Codex_Titlescreen_1eb4 | 2 | Codex-specific title screen and title bar |
| DMHub_CharacterSheet_5e_b1b6 | 9 | D&D 5e character sheet (deprecated) |
| DMHub_Import_Framework_6cc3 | 5 | Import framework (Beyond, 5eTools) |
| Draw_Steel_Modifiers_d18e | 9 | Draw Steel modifier types |
| DrawSteelActionBar_5d75 | 2 | Draw Steel action bar and trigger panel |
| ChatPanel_cb3b | 3 | Chat panel and action log |
| Targetable_Objects_34c9 | 1 | Targetable object system |
| Draw_Steel_Beastheart_b691 | 2 | Beastheart companion system |
| Draw_Steel_Inventory_8a0f | 1 | Draw Steel inventory system |
| LanguageRelations_0df1 | 1 | Language relation system |
| Draw_Steel_UX_Update_cec0 | 5 | UX update (dice panel, builder, VFX) |
| THC_Forge_Steel_Character_Importer_15c0 | 6 | Forge Steel character importer |
| Timeline_e083 | 3 | Timeline panel and ability sidebar |
| Draw_Steel_Character_Build_38e3 | 1 | Ancestry inheritance for character build |
| Draw_Steel_8a33 | 1 | Draw Steel module entry point |
| DMHub_Token_UI_203c | 4 | Token UI, effects, emotes, and config |
