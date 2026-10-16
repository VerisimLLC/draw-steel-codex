---@meta

--- @alias Vector2Arg Vector2|{x: number, y: number}
--- @alias Vector3Arg Vector3|{x: number, y: number, z: number}
--- @alias Vector4Arg Vector4|{x1: number, x2: number, y1: number, y2: number}
--- @alias ColorArg Color|string|{r: number, g: number, b: number, a: number?}|{h: number, s: number, v: number, a: number?}

--- A handle to a registered setting, returned by setting{}.
--- @class SettingRef: GameType
--- @field id string The setting id.
SettingRef = {}

--- The current value of the setting.
--- @return any
function SettingRef:Get() end

--- Sets the setting to val.
--- @param val any
function SettingRef:Set(val) end

--- setting: Register a setting.
--- @param info {id: string, description: string, help: string, storage: SettingStorage, enum: {value: any, icon: nil|string, text: nil|string, help: nil|string}[], editor: nil|"slider"|"sliderexponential"|"iconbuttons"|"iconlibrary"|"dropdown"|"check"|"color"|"text"|"input"|"buttonincrement"}
--- @return SettingRef
function setting(info) end

--- A roll definition, from DiceHarness.cs RollInfo.FromLua
--- @class RollDefinition
--- @field roll nil|string Either this should be defined, or @see categories
--- @field categories nil|table<string, {mod: nil|number, primary: nil|boolean, typedMods: table<string,integer>, attr: table<string,integer>, groups: {numDice: nil|number, numFaces: nil|number, numKeep: nil|number, subtract: nil|boolean, multiply: nil|number}[] }>
--- @field amendable nil|boolean Whether this roll is still open to being changed.
--- @field silent nil|boolean
--- @field instant nil|boolean
--- @field dmonly nil|boolean If this is only visible to the GM.
--- @field properties any Arbitrary lua object which can hold any additional roll data.
--- @field description nil|string
--- @field exploding nil|boolean
--- @field reroll nil|integer
--- @field critical nil|integer
--- @field minroll nil|integer
--- @field autofailure nil|boolean
--- @field autosuccess nil|boolean
--- @field tiers nil|integer
--- @field delay nil|boolean
--- @field begin nil|function Callback to execute when the roll begins.
--- @field complete nil|function Callback to execute when the roll ends.
--- @field tokenid nil|string
--- @field boons nil|integer
--- @field banes nil|integer
--- @field amendmentRerolls nil|boolean
RollDefinition = {}

--- The members RegisterGameType gives every game type and, through its metatable, every
--- instance of one. Each registered type should be declared `--- @class X: GameType`
--- (or `: <its base type>`, whose chain ends here).
--- @class GameType
--- @field typeName string The registered type name.
--- @field baseTypeName nil|string The registered base type name, if any.
--- @field mt table The metatable RegisterGameType sets on instances of this type.
--- @field __typeName? string The serialized type key; set on an instance to change the type it loads back as.
GameType = {}

--- Creates an instance of this type: o (or a new table) with the type's metatable set.
--- @param o? table
--- @return any
function GameType.new(o) end

--- True if key is set directly on this instance (a raw get, so class defaults do not count).
--- @param key string
--- @return boolean
function GameType:has_key(key) end

--- The value set directly on this instance for key, or defaultValue when there is none.
--- Never consults the class defaults and never raises for an unknown key.
--- @param key string
--- @param defaultValue? any
--- @return any
function GameType:try_get(key, defaultValue) end

--- Like try_get, but stores defaultValue on the instance when the key was not set.
--- @param key string
--- @param defaultValue any
--- @return any
function GameType:get_or_add(key, defaultValue) end

--- Strings this instance contributes to translation; nil when there are none.
--- @return nil|table
function GameType:TranslationStrings() end

--- True if this type is, or derives from, the named type.
--- @param typeName string
--- @return boolean
function GameType.IsDerivedFrom(typeName) end

--- Makes reads and writes of field a on this type's instances go to field b.
--- @param a string
--- @param b string
function GameType.AddAlias(a, b) end

--- Engine globals set outside the stub generator's view: by core Lua TextAssets
--- (commands.txt, game-hud-menu.txt, input.txt, settings.txt, ...) or by C#
--- (LuaNative.SetGlobal, LuaNative.cs DoString), which the generator does not learn
--- names from. Declared here so a stub regen keeps them.

--- One entry of Commands._macros: the help and completion info for a slash command.
--- @class CommandMacroInfo
--- @field doc? string Full usage text.
--- @field summary? string One-line summary shown by the chat input.
--- @field completions? fun(args: string[], argIndex: integer): table Argument suggestions for the chat input.
--- @field commandInfo? table How the no-code command builder surfaces this command.

--- Slash commands and command-line actions: `/name args` calls Commands.name(args), with
--- the text after the name as args (CommandController.ExecuteCommand). commands.txt fills
--- it with the engine's commands and game-hud-menu.txt adds the menu-command registry
--- below; the codex adds entries (`Commands.foo = function(str)`) and, in DMHub
--- Utils/Utils.lua, the macro registry: `_macros` below and the RegisterMacro /
--- GetMacroInfo / GetAllMacros / GetCurrentArg / RegisterBuiltinDoc functions, whose
--- declarations LuaLS picks up from the codex.
--- @class CommandsTable
--- @field _macros table<string, CommandMacroInfo> Help and completions by command name. Created by the codex's DMHub Utils/Utils.lua.
--- @field [string] fun(str?: string): any A command; str is the text after the command name.
Commands = {}

--- Registers a menu command (name, icon, menu, group, command or execute, setting,
--- folder, dmonly, devonly, ...), from game-hud-menu.txt. Ignored when dmonly or devonly
--- rules it out for this user.
--- @param args table
function Commands.Register(args) end

--- The launchable-panel menu item whose name is str, or nil.
--- @param str string
--- @return table|nil
function Commands.GetCommandInfo(str) end

--- Every registered menu command, keyed by identifier.
--- @return table<string, table>
function Commands.GetRegisteredCommands() end

--- Appends the registered menu commands' menu items to result, filed into subfolders by
--- folder when subfolders is given.
--- @param result table[]
--- @param subfolders? table
--- @param includeFiltered? boolean
function Commands.AccumulateMenuItems(result, subfolders, includeFiltered) end

--- The Dice Studio API. Set by ScriptEngine.cs only for admin accounts (and in the editor);
--- nil for everyone else, so code outside the admin-only Dice Studio must check it.
--- @type DiceStudioLua
dicestudio = nil

--- The live game HUD: the object the codex's CreateGameHud returns, installed by
--- SheetHud.cs. nil until a game's HUD has been created (not set at the title screen).
--- @type GameHud
gamehud = nil

--- Escape-key priorities, lowest to highest, from input.txt. Each value is the priority's
--- rank; pass it as a panel's `escapePriority`.
--- @class EscapePriorityTable
--- @field DMHUB_MOCKUP_DEV integer
--- @field EXIT_DM_MODE integer
--- @field DMHUB_EXIT_TITLESCREEN integer
--- @field DMHUB_EXIT_TOOL_DIALOG integer
--- @field DMHUB_OBJECT_ESCAPE integer
--- @field DMHUB_TOKEN_ESCAPE integer
--- @field DMHUB_TOKEN integer
--- @field CANCEL_TOKEN_MENU integer
--- @field CANCEL_ACTION_BAR integer
--- @field EXIT_CHARACTER_SHEET integer
--- @field DMHUB_CANCEL_TOOL integer
--- @field DMHUB_CONTEXT_MENU integer
--- @field EXIT_INVENTORY_DIALOG integer
--- @field EXIT_DIALOG integer
--- @field EXIT_ROLL_DIALOG integer
--- @field EXIT_MODAL_DIALOG integer
--- @field DMHUB_POPUP integer
--- @field DMHUB_DROPDOWN integer

--- @type EscapePriorityTable
EscapePriority = nil

--- Panels launchable from the HUD menu and by name, from game-hud-menu.txt.
--- @class LaunchablePanelRegistry
LaunchablePanel = {}

--- Registers a launchable panel. args is the registration table (name, icon, content,
--- folder, dmonly, devonly, ...); a panel with an identical name replaces the old one.
--- @param args table
function LaunchablePanel.Register(args) end

--- The open panel with this name, launching it first if it is not open.
--- @param name string
--- @return Panel|nil
function LaunchablePanel.GetOrLaunchPanel(name) end

--- Creates, parents and focuses the panel for registration entry p.
--- @param p table
--- @param args? table
--- @return Panel
function LaunchablePanel.LaunchPanel(p, args) end

--- Launches the panel whose name matches str (case-insensitive), including filtered ones.
--- @param str string
--- @param args? table
--- @return boolean launched
function LaunchablePanel.LaunchPanelByName(str, args) end

--- Appends this registry's menu items to result.
--- @param result table[]
--- @param subfolders table
--- @param includeFiltered? boolean
function LaunchablePanel.AccumulateMenuItems(result, subfolders, includeFiltered) end

--- Every launchable panel's menu item, sorted by group, ordering and text.
--- @param includeFiltered? boolean
--- @return table[]
function LaunchablePanel.GetMenuItems(includeFiltered) end

--- Engine additions to the coroutine library: GetCurrentId and IsCoroutineWithIdStillRunning
--- from lua-coroutine.txt, atexit from LuaNative.cs. They concern the coroutines the engine
--- itself runs (dmhub.Coroutine and friends), not ones made with coroutine.create.

--- The id of the engine coroutine currently running, or nil outside one.
--- @return nil|integer
function coroutine.GetCurrentId() end

--- True while the engine coroutine with this id has not finished.
--- @param id nil|integer
--- @return boolean
function coroutine.IsCoroutineWithIdStillRunning(id) end

--- Queues fn to run when the current engine coroutine finishes. Does nothing outside one,
--- or when fn is nil.
--- @param fn nil|function
function coroutine.atexit(fn) end

--- Every engine coroutine still running (dmhub.Coroutine and friends), in start order.
--- Created by LuaNative.cs and replaced wholesale when coroutines are reset, so read the
--- global each time rather than keeping the table.
--- @type {coroutine: thread, id: integer, hostElevation: nil|integer}[]
builtin_coroutines = {}

--- The developer game recorder. Set by ScriptEngine.OnLogin only for admin accounts (and
--- in the editor), like dicestudio; nil for everyone else.
--- @type GameRecorderLua
recorder = nil

--- A registered setting: the table passed to setting{} (settings.txt), after setting{} adds
--- ord and enumKeys. Registrations may carry further keys of their own.
--- @class SettingInfo
--- @field id string
--- @field description? string
--- @field help? string
--- @field storage? SettingStorage
--- @field default any
--- @field editor? string
--- @field section? string
--- @field enum? {value: any, icon: nil|string, text: nil|string, help: nil|string}[]
--- @field enumKeys? table<any, integer> Set by setting{} when enum is: each enum value's index in enum.
--- @field ord integer Registration order, set by setting{}.
--- @field format? string
--- @field min? number
--- @field max? number
--- @field resetCount? integer
--- @field [string] any

--- Every registered setting by id, from settings.txt.
--- @type table<string, SettingInfo>
Settings = {}

--- Every registered setting in registration order, from settings.txt. A re-registered id
--- keeps its place.
--- @type SettingInfo[]
SettingsOrdered = {}

--- The setting's current value as display text: the matching enum entry's text for an
--- enum setting, otherwise tostring of the value. From settings.txt.
--- @param var SettingInfo
--- @return string
function GetSettingPrettyValue(var) end

--- The engine's Theme game type (RegisterGameType in lua-core.txt). The codex adds the
--- theme editor functions to it (DMHub Core Panels/Theme.lua).
--- @class Theme: GameType
--- @field new fun(o?: table): Theme
Theme = {}

--- The title screen game type, registered by titlescreen.txt; the engine and the codex add
--- its screens as methods.
--- @class Titlescreen: GameType
--- @field new fun(o?: table): Titlescreen
--- @field dialog SheetContainer The title screen's container, which LuaTitlescreen.cs passes to CreateTitlescreen.
Titlescreen = {}

--- A shuffle bag of the integers 1..n, from jukebox.txt: Next draws them in random order
--- and refills the bag once every one has been drawn.
--- @class Jukebox: GameType
--- @field new fun(o?: table): Jukebox
--- @field deck integer[] Integers still to be drawn.
--- @field discard integer[] Integers already drawn.
Jukebox = {}

--- A new bag of the integers 1..elements.
--- @param elements? integer Defaults to 1.
--- @return Jukebox
function Jukebox.Create(elements) end

--- Moves every drawn integer back into the bag, in random order.
function Jukebox:Shuffle() end

--- Resizes the bag to the integers 1..n.
--- @param n integer
function Jukebox:CheckSize(n) end

--- Draws the next integer, refilling the bag first if it is empty.
--- @return integer
function Jukebox:Next() end

--- One animated item-icon effect, from item-effects.txt.
--- @class ItemEffectInfo
--- @field text string Display name.
--- @field video string The effect video, used as the icon overlay's bgimage.
--- @field opacity number
--- @field mask boolean Mask the video to the item icon's shape.

--- The item-icon effects by id (an item's iconEffect), from item-effects.txt.
--- @type table<string, ItemEffectInfo>
ItemEffects = {}

--- The artist editor, from artists.txt.
--- @class ArtistEditor
Artist = {}

--- A form panel that edits an artist; fire its `artist` event with the artist to edit.
--- @return Panel
function Artist.CreateEditorPanel() end

--- The subscription management screen, from subs-screen.txt.
--- @param arguments {dialog: Panel} The dialog it is shown in; sizes it.
--- @return Panel
function CreateSubscriptionScreen(arguments) end

--- The terms of use shown on the title screen, as markdown; set by the patch-notes
--- TextAssets.
--- @type string
termsAndOngoingEffectsText = ""

--- BEGIN generated by tools/lua-typing/gen_table_overloads.py -- do not edit by hand
--- Typed overloads for the data-table getters: each registered game type that declares
--- `X.tableName = "name"` makes GetTable("name") return its rows as X. Merged by LuaLS
--- with the declarations in dmhub.lua; names no type declares keep the plain signature.
---@overload fun(tableName: "abilityTemplates"): table<string, AbilityTemplate>
---@overload fun(tableName: "attributeGenerator"): table<string, AttributeGenerator>
---@overload fun(tableName: "audioPlaylists"): table<string, AudioPlaylist>
---@overload fun(tableName: "audioVariantPools"): table<string, VariantPool>
---@overload fun(tableName: "backgrounds"|"careers"): table<string, Background>
---@overload fun(tableName: "campaignNotes"): table<string, CampaignNote>
---@overload fun(tableName: "characterOngoingEffects"): table<string, CharacterOngoingEffect>
---@overload fun(tableName: "characterResources"): table<string, CharacterResource>
---@overload fun(tableName: "characterTypes"): table<string, CharacterType>
---@overload fun(tableName: "charConditions"): table<string, CharacterCondition>
---@overload fun(tableName: "classes"): table<string, Class>
---@overload fun(tableName: "compendiumPermissions"): table<string, CompendiumPermission>
---@overload fun(tableName: "complications"): table<string, CharacterComplication>
---@overload fun(tableName: "cultureAspects"): table<string, CultureAspect>
---@overload fun(tableName: "cultures"): table<string, Culture>
---@overload fun(tableName: "currency"): table<string, Currency>
---@overload fun(tableName: "customAttributes"): table<string, CustomAttribute>
---@overload fun(tableName: "customfields"): table<string, CustomFieldCollection>
---@overload fun(tableName: "damageFlags"): table<string, DamageFlag>
---@overload fun(tableName: "damageTypes"): table<string, DamageType>
---@overload fun(tableName: "Deities"): table<string, Deity>
---@overload fun(tableName: "DeityDomains"): table<string, DeityDomain>
---@overload fun(tableName: "documentClasses"): table<string, DocumentClass>
---@overload fun(tableName: "documents"): table<string, CustomDocument>
---@overload fun(tableName: "downtimeActivities"): table<string, DowntimeActivity>
---@overload fun(tableName: "encounterfolders"): table<string, EncounterFolder>
---@overload fun(tableName: "encounterRuleSets"): table<string, EncounterRuleSet>
---@overload fun(tableName: "encounters"): table<string, Encounter>
---@overload fun(tableName: "encounterScripts"): table<string, EncounterScript>
---@overload fun(tableName: "environmentalKeywords"): table<string, EnvironmentalKeyword>
---@overload fun(tableName: "equipmentCategories"): table<string, EquipmentCategory>
---@overload fun(tableName: "feats"): table<string, CharacterFeat>
---@overload fun(tableName: "featurePrefabs"): table<string, CharacterFeaturePrefabs>
---@overload fun(tableName: "FishSpecies"): table<string, FishSpecies>
---@overload fun(tableName: "footprintStyles"): table<string, FootprintStyle>
---@overload fun(tableName: "glossaryTerms"): table<string, GlossaryTerm>
---@overload fun(tableName: "journalStyles"): table<string, JournalStylesheet>
---@overload fun(tableName: "kits"): table<string, Kit>
---@overload fun(tableName: "languageRelations"): table<string, LanguageRelation>
---@overload fun(tableName: "languages"): table<string, Language>
---@overload fun(tableName: "liveencounters"): table<string, LiveEncounter>
---@overload fun(tableName: "mapScripts"): table<string, MapScript>
---@overload fun(tableName: "MonsterGroup"): table<string, MonsterGroup>
---@overload fun(tableName: "negotiators"): table<string, Negotiator>
---@overload fun(tableName: "parties"): table<string, Party>
---@overload fun(tableName: "pdfReferences"): table<string, PDFFragment>
---@overload fun(tableName: "powerRolls"): table<string, PowerRollTableGroup>
---@overload fun(tableName: "proficiencyLevel"): table<string, ProficiencyLevel>
---@overload fun(tableName: "races"): table<string, Race>
---@overload fun(tableName: "Skills"): table<string, Skill>
---@overload fun(tableName: "SpellLists"): table<string, SpellList>
---@overload fun(tableName: "Spells"): table<string, Spell>
---@overload fun(tableName: "tbl_Gear"): table<string, equipment>
---@overload fun(tableName: "titles"): table<string, Title>
---@overload fun(tableName: "VisionType"): table<string, VisionType>
---@overload fun(tableName: "weaponProperties"): table<string, WeaponProperty>
---@param tableName string
---@return table<string, table>
function dmhub.GetTable(tableName) end

--- Typed overloads for the data-table getters: each registered game type that declares
--- `X.tableName = "name"` makes GetTable("name") return its rows as X. Merged by LuaLS
--- with the declarations in dmhub.lua; names no type declares keep the plain signature.
---@overload fun(tableName: "abilityTemplates"): table<string, AbilityTemplate>
---@overload fun(tableName: "attributeGenerator"): table<string, AttributeGenerator>
---@overload fun(tableName: "audioPlaylists"): table<string, AudioPlaylist>
---@overload fun(tableName: "audioVariantPools"): table<string, VariantPool>
---@overload fun(tableName: "backgrounds"|"careers"): table<string, Background>
---@overload fun(tableName: "campaignNotes"): table<string, CampaignNote>
---@overload fun(tableName: "characterOngoingEffects"): table<string, CharacterOngoingEffect>
---@overload fun(tableName: "characterResources"): table<string, CharacterResource>
---@overload fun(tableName: "characterTypes"): table<string, CharacterType>
---@overload fun(tableName: "charConditions"): table<string, CharacterCondition>
---@overload fun(tableName: "classes"): table<string, Class>
---@overload fun(tableName: "compendiumPermissions"): table<string, CompendiumPermission>
---@overload fun(tableName: "complications"): table<string, CharacterComplication>
---@overload fun(tableName: "cultureAspects"): table<string, CultureAspect>
---@overload fun(tableName: "cultures"): table<string, Culture>
---@overload fun(tableName: "currency"): table<string, Currency>
---@overload fun(tableName: "customAttributes"): table<string, CustomAttribute>
---@overload fun(tableName: "customfields"): table<string, CustomFieldCollection>
---@overload fun(tableName: "damageFlags"): table<string, DamageFlag>
---@overload fun(tableName: "damageTypes"): table<string, DamageType>
---@overload fun(tableName: "Deities"): table<string, Deity>
---@overload fun(tableName: "DeityDomains"): table<string, DeityDomain>
---@overload fun(tableName: "documentClasses"): table<string, DocumentClass>
---@overload fun(tableName: "documents"): table<string, CustomDocument>
---@overload fun(tableName: "downtimeActivities"): table<string, DowntimeActivity>
---@overload fun(tableName: "encounterfolders"): table<string, EncounterFolder>
---@overload fun(tableName: "encounterRuleSets"): table<string, EncounterRuleSet>
---@overload fun(tableName: "encounters"): table<string, Encounter>
---@overload fun(tableName: "encounterScripts"): table<string, EncounterScript>
---@overload fun(tableName: "environmentalKeywords"): table<string, EnvironmentalKeyword>
---@overload fun(tableName: "equipmentCategories"): table<string, EquipmentCategory>
---@overload fun(tableName: "feats"): table<string, CharacterFeat>
---@overload fun(tableName: "featurePrefabs"): table<string, CharacterFeaturePrefabs>
---@overload fun(tableName: "FishSpecies"): table<string, FishSpecies>
---@overload fun(tableName: "footprintStyles"): table<string, FootprintStyle>
---@overload fun(tableName: "glossaryTerms"): table<string, GlossaryTerm>
---@overload fun(tableName: "journalStyles"): table<string, JournalStylesheet>
---@overload fun(tableName: "kits"): table<string, Kit>
---@overload fun(tableName: "languageRelations"): table<string, LanguageRelation>
---@overload fun(tableName: "languages"): table<string, Language>
---@overload fun(tableName: "liveencounters"): table<string, LiveEncounter>
---@overload fun(tableName: "mapScripts"): table<string, MapScript>
---@overload fun(tableName: "MonsterGroup"): table<string, MonsterGroup>
---@overload fun(tableName: "negotiators"): table<string, Negotiator>
---@overload fun(tableName: "parties"): table<string, Party>
---@overload fun(tableName: "pdfReferences"): table<string, PDFFragment>
---@overload fun(tableName: "powerRolls"): table<string, PowerRollTableGroup>
---@overload fun(tableName: "proficiencyLevel"): table<string, ProficiencyLevel>
---@overload fun(tableName: "races"): table<string, Race>
---@overload fun(tableName: "Skills"): table<string, Skill>
---@overload fun(tableName: "SpellLists"): table<string, SpellList>
---@overload fun(tableName: "Spells"): table<string, Spell>
---@overload fun(tableName: "tbl_Gear"): table<string, equipment>
---@overload fun(tableName: "titles"): table<string, Title>
---@overload fun(tableName: "VisionType"): table<string, VisionType>
---@overload fun(tableName: "weaponProperties"): table<string, WeaponProperty>
---@param tableName string
---@return table<string, table>
function dmhub.GetTableVisible(tableName) end
--- END generated by tools/lua-typing/gen_table_overloads.py
