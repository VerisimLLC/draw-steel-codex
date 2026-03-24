# Module Map

The codebase contains **42 modules** with **517 files** loaded via `main.lua`. Each module is a directory following the naming convention `ModuleName_XXXX` (where `XXXX` is a hex module ID).

## Engine API

| Module | Files | Purpose |
|--------|-------|---------|
| `Definitions/` | 209 | LuaLS type stubs for the DMHub engine API. Documents globals like `dmhub`, `gui`, `game`, `creature`. Not loaded at runtime — used only for editor tooling. |

## Foundation (Generic Game Framework)

| Module | Files | Purpose | Key Files |
|--------|-------|---------|-----------|
| `DMHub_Game_Rules_fc51` | 104 | Base game rules: creatures, characters, abilities, conditions, equipment, classes, modifiers | `Creature.lua`, `Character.lua`, `ActivatedAbility.lua`, `Condition.lua`, `BasicRules.lua`, `GameSystem.lua` |
| `DMHub_Core_UI_752e` | 21 | Core UI framework: panel wrappers, controls, layout | `Gui.lua`, `Hud.lua`, `DockablePanel.lua`, `Scrollable.lua`, `Dropdown.lua` |
| `DMHub_Utils_5b73` | 8 | Shared utilities: helpers, formula engine, coroutines | `Utils.lua`, `GoblinScript.lua`, `CoroutineUtils.lua`, `MarkdownRenderUtils.lua` |
| `DMHub_CharacterSheet_Base_b03e` | 5 | Base character sheet framework | |
| `DMHub_Import_Framework_6cc3` | 5 | Import framework for loading external data | |
| `DMHub_Token_UI_203c` | 4 | Token UI rendering and interaction | |

## Domain (Draw Steel System)

| Module | Files | Purpose | Key Files |
|--------|-------|---------|-----------|
| `Draw_Steel_Core_Rules_1b8f` | 65 | Draw Steel game system: overrides base rules, adds DS-specific mechanics | `MCDMRules.lua`, `MCDMCreature.lua`, `MCDMCharacter.lua`, `MCDMMonster.lua`, `MCDMActivatedAbility.lua` |
| `Downtime_Projects_c618` | 27 | Downtime project system: project rolling, business mechanics, shared state | |
| `Draw_Steel_Ability_Behaviors_aef5` | 23 | Individual ability behavior implementations | `AbilityDamage.lua`, `AbilityForcedMovementLoc.lua`, `AbilityTemporaryEffects.lua`, `AbilityMacro.lua` |
| `Draw_Steel_Modifiers_d18e` | 10 | Modifier implementations | `ModifierCaptain.lua`, `ModifierForcedMovement.lua`, `ModifierInvisibility.lua` |
| `Draw_Steel_8a33` | 1 | Draw Steel base/glue module | |
| `Draw_Steel_Beastheart_b691` | 2 | Beastheart companion system | |
| `Monster_AI_d7b4` | 5 | Monster AI behavior system | |
| `Potency_Adjustment_Mod_b741` | 1 | Potency adjustment mechanics | |

## UI & Panels

| Module | Files | Purpose | Key Files |
|--------|-------|---------|-----------|
| `DMHub_Core_Panels_65a9` | 49 | Application panels: chat, character, map tools, compendium, audio, dev tools | `Chat.lua`, `CharacterPanel.lua`, `Compendium.lua`, `Devtools.lua` |
| `DocumentSystem_3045` | 25 | Rich document/journal system with embedded content | `MarkdownDocument.lua`, `MarkdownDisplay.lua`, `RichImage.lua`, `RichEncounter.lua` |
| `Draw_Steel_Character_Builder_45c3` | 24 | Character creation wizard UI and state machine | `CharacterBuilder.lua`, `AncestryDetail.lua`, `ClassDetail.lua`, `FeatureSelector.lua` |
| `DMHub_Game_Hud_efeb` | 22 | Game HUD: action bar, initiative, roll dialogs, rest, macros | |
| `Draw_Steel_UI_bd58` | 17 | DS-specific UI: action bar, character sheet, class editors | `DSActionBar.lua`, `DSCharacterSheet.lua`, `DSRollDialog.lua` |
| `DMHub_Compendium_c080` | 16 | Compendium browser and editors for all game content | |
| `Draw_Steel_V_567e` | 13 | Newer DS features: encounter, heroes, negotiation, downtime, fishing, chessboard | |
| `DMHub_CharacterSheet_5e_b1b6` | 10 | 5e-style character sheet (legacy/alternate) | |
| `DrawSteelActionBar_5d75` | 2 | Draw Steel action bar additions | |

## Development & Utilities

| Module | Files | Purpose |
|--------|-------|---------|
| `Development_Utilities_aa55` | 13 | Debug tools: GoblinScript debugger, trigger debugger, character inspector, control zoo |
| `Draw_Steel_UX_Update_cec0` | 5 | UX improvements and polish |
| `Timeline_e083` | 3 | Timeline/history system |
| `Chat_Enhancements_6e49` | 3 | Chat enhancements |
| `ChatPanel_cb3b` | 3 | Chat panel extensions |

## Importers & Content

| Module | Files | Purpose |
|--------|-------|---------|
| `DMHub_Titlescreen_6089` | 6 | Title screen, settings, display styles |
| `Draw_Steel_Importers_3466` | 4 | Draw Steel data importers |
| `THC_Forge_Steel_Character_Importer_15c0` | 6 | THC Forge Steel character importer |
| `Draw_Steel_Audio_06c8` | 2 | Audio system for Draw Steel |
| `Draw_Steel_Inventory_8a0f` | 1 | Inventory system |
| `Codex_Macros_ac16` | 2 | Codex macro system |
| `Codex_Quotes_2aae` | 2 | Codex quotes registry and display |
| `Codex_Titlescreen_1eb4` | 2 | Codex title screen customization |
| `Image_Zoo_8f12` | 1 | Image asset management |
| `Great_Library_Macros_a4ba` | 1 | Great Library macro definitions |
| `LanguageRelations_0df1` | 1 | Language relation data |
| `Targetable_Objects_34c9` | 1 | Targetable object system |
| `DelianTomb_046b` | 1 | Delian Tomb adventure content |
| `Draw_Steel_Character_Build_38e3` | 1 | Character build utilities |
