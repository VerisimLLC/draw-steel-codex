--- @alias integer number

--- @alias Vector2Arg Vector2|{x: number, y: number}
--- @alias Vector3Arg Vector3|{x: number, y: number, z: number}
--- @alias Vector4Arg Vector4|{x1: number, x2: number, y1: number, y2: number}

--- @class SettingRef
SettingRef = {}

--- SettingRef:Get
--- @return any
function SettingRef:Get()
	return nil
end

--- SettingRef:Set
--- @param val any
function SettingRef:Set(val)
end

--- setting: Register a setting.
--- @param info {id: string, description: string, help: string, storage: SettingStorage, enum: {value: any, icon: nil|string, text: nil|string, help: nil|string}[], editor: nil|"slider"|"iconbuttons"|"iconlibrary"|"dropdown"|"check"|"color"}
function setting(info)
	--dummy code
end

--- A roll definition, from DiceHarness.cs RollInfo.FromLua
--- @class RollDefinition
--- @field roll nil|string Either this should be defined, or @see categories
--- @field categories nil|table<string, {mod: nil|number, primary: nil|boolean, typedMods: table<string,int>, attr: table<string,int>, groups: {numDice: nil|number, numFaces: nil|number, numKeep: nil|number, subtract: nil|boolean, multiply: nil|number, }[] }>
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