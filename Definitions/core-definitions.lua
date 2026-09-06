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
