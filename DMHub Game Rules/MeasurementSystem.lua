local mod = dmhub.GetModLoading()

--This file implements Measurement Systems. If you want to add a new type of measurement system, or
--add some functionality to measurement systems you can do so in this file.

--- @class MeasurementSystem: GameType
--- @field new fun(o?: table): MeasurementSystem
--- @field systems table[] List of available measurement system descriptors (id, value, unitName, unitSingular, etc.).
--- @field value string Setting value id for this system (used to match dmhub.GetSettingValue("measurementsystem")).
--- @field unitName string Plural unit label (e.g. "feet", "meters").
--- @field unitSingular string Singular unit label (e.g. "foot", "meter").
--- @field text string Label shown in the setting dropdown.
--- @field abbreviation string Short unit label (e.g. "ft", "m").
--- @field tileSize number How many of this unit one tile spans.
--- @field worldUnits table[] World Map units (id, text, unitName, unitSingular) for the Map Type setting.
--- Manages conversion between native (world unit) measurements and display units.
MeasurementSystem = RegisterGameType("MeasurementSystem")

dmhub.unitsPerSquare = 5

local g_cachedSetting = nil
---@type MeasurementSystem
local g_currentSystem = nil
function MeasurementSystem.CurrentSystem()
    local setting = dmhub.GetSettingValue("measurementsystem")
    if setting ~= g_cachedSetting then
        g_cachedSetting = setting
        g_currentSystem = MeasurementSystem.systems[1]
        for _,sys in ipairs(MeasurementSystem.systems) do
            if sys.value == setting then
                g_currentSystem = sys
                break
            end
        end
    end

    return g_currentSystem
end

--the measurement system native to the game system we're playing in.
function MeasurementSystem.NativeSystem()
    return MeasurementSystem.systems[1]
end

function MeasurementSystem.ToString(num)
    if num - math.floor(num) == 0 then
        return string.format("%d", math.tointeger(num))
    else
        return string.format("%.1f", num)
    end
end

function MeasurementSystem.NativeToDisplayStringWithUnits(num, sys)
    if sys == nil then
        sys = MeasurementSystem.CurrentSystem()
    end

    local n = MeasurementSystem.NativeToDisplay(num, sys)
    local units = string.lower(cond(n == 1, sys.unitSingular, sys.unitName))
    return string.format("%s %s", MeasurementSystem.NativeToDisplayString(num, sys), units)
end

function MeasurementSystem.NativeToDisplayUnits(num, sys)
    if sys == nil then
        sys = MeasurementSystem.CurrentSystem()
    end

    local n = MeasurementSystem.NativeToDisplay(num, sys)
    local units = string.lower(cond(n == 1, sys.unitSingular, sys.unitName))
    return units
end

function MeasurementSystem.NativeToDisplayString(num, sys)
    return MeasurementSystem.ToString(MeasurementSystem.NativeToDisplay(num, sys))
end

function MeasurementSystem.NativeToDisplay(num, sys)
    local n = tonumber(num)
    if n == nil then
        return num
    end

    if sys == nil then
        sys = MeasurementSystem.CurrentSystem()
    end

    local m = n
    n = n * sys.tileSize
    n = n / dmhub.unitsPerSquare

    if n == round(n) then
        return string.format("%d", n)
    else
        return string.format("%.1f", n)
    end
end

function MeasurementSystem.DisplayToNative(num, sys)
    local n = tonumber(num)
    print("EDIT:: Display to native:", num, "/", n)
    if n == nil then
        return num
    end

    if sys == nil then
        sys = MeasurementSystem.CurrentSystem()
    end
    print("EDIT:: Display to native units per square =", dmhub.unitsPerSquare, "tileSize =", sys.tileSize, "n =", n)
    n = n * dmhub.unitsPerSquare
    n = n / sys.tileSize
    print("EDIT:: n becomes", n)
    return n
end

function MeasurementSystem.UnitName()
    local sys = MeasurementSystem.CurrentSystem()
    return sys.unitName
end

function MeasurementSystem.UnitNameSingular()
    local sys = MeasurementSystem.CurrentSystem()
    return sys.unitSingular
end

function MeasurementSystem.Abbrev()
    local sys = MeasurementSystem.CurrentSystem()
    return sys.abbreviation
end

function MeasurementSystem.FindSystemInString(str)
    str = string.lower(str)
    for _,sys in ipairs(MeasurementSystem.systems) do
        if string.find(str, string.lower(sys.unitName)) then
            return sys
        end
    end

    return nil
end

--to be used as a setting enum needs to provide bind.
MeasurementSystem.bind = false

MeasurementSystem.systems = {
	MeasurementSystem.new{
        value = "Feet",
        text = "Feet",
		unitName = "Feet",
        unitSingular = "Foot",
        abbreviation = "ft",
        tileSize = 5,
	},
	MeasurementSystem.new{
        value = "Meters",
        text = "Meters",
		unitName = "Meters",
        unitSingular = "Meter",
        abbreviation = "m",
        tileSize = 1.5,
	},
	MeasurementSystem.new{
        value = "Tiles",
        text = "Tiles",
		unitName = "Tiles",
        unitSingular = "Tile",
        abbreviation = "",
        tileSize = 1,
	},
}

setting{
    id = "measurementsystem",
    description = "Measurement Units",
    section = "General",
    storage = "preference",
    editor = "dropdown",
    default = "Feet",
    enum = MeasurementSystem.systems,
}

--Map type and world-map scale. A Battlemap is tactical: one tile is a few feet
--and distances follow the Measurement Units preference. A World Map is a
--region or world: one tile (usually a hex) is a stretch of land, measured in
--miles, kilometers, leagues or a unit the Director names. Edited in Map
--Settings > Map Type; the measuring tool reports distances in these units.
setting{
    id = "map:maptype",
    description = "Map Type",
    storage = "map",
    default = "battlemap",
}

setting{
    id = "map:worldunit",
    description = "World Map Unit",
    storage = "map",
    default = "miles",
}

--the unit's name when map:worldunit is "custom" (e.g. "days").
setting{
    id = "map:worldunitname",
    description = "World Map Custom Unit",
    storage = "map",
    default = "",
}

setting{
    id = "map:worldtilesize",
    description = "World Map Tile Size",
    storage = "map",
    default = 6,
}

--The scale a map gets when it is first made a World Map. The Director can
--replace it with any map's scale ("Use as default" in Map Settings).
setting{
    id = "worldmap:defaultunit",
    description = "Default World Map Unit",
    storage = "game",
    default = "miles",
}

setting{
    id = "worldmap:defaultunitname",
    description = "Default World Map Custom Unit",
    storage = "game",
    default = "",
}

setting{
    id = "worldmap:defaulttilesize",
    description = "Default World Map Tile Size",
    storage = "game",
    default = 6,
}

MeasurementSystem.worldUnits = {
    { id = "miles", text = "Miles", unitName = "miles", unitSingular = "mile" },
    { id = "kilometers", text = "Kilometers", unitName = "kilometers", unitSingular = "kilometer" },
    { id = "leagues", text = "Leagues", unitName = "leagues", unitSingular = "league" },
    { id = "custom", text = "Custom", unitName = "units", unitSingular = "unit" },
}

--true if the current map's grid is hexes rather than squares.
function MeasurementSystem.IsHexMap()
    local tiletype = dmhub.GetSettingValue("maplayout:tiletype")
    if tiletype == "flattop" or tiletype == "pointtop" then
        return true
    end
    if tiletype == "custom" then
        local stagger = dmhub.GetSettingValue("maplayout:stagger")
        return stagger == "vertical" or stagger == "horizontal"
    end
    return false
end

--Plural and singular names for a world unit id; customName is used for "custom".
function MeasurementSystem.WorldUnitNames(unitid, customName)
    if unitid == "custom" then
        local name = string.match(customName or "", "^%s*(.-)%s*$")
        if name ~= "" then
            return name, name
        end
    end
    for _,unit in ipairs(MeasurementSystem.worldUnits) do
        if unit.id == unitid then
            return unit.unitName, unit.unitSingular
        end
    end
    return "miles", "mile"
end

--The current map's scale if it is a World Map, else nil:
--{amount = units per tile, unitName = plural, unitSingular = singular}.
function MeasurementSystem.WorldMapScale()
    if dmhub.GetSettingValue("map:maptype") ~= "world" then
        return nil
    end
    local amount = tonumber(dmhub.GetSettingValue("map:worldtilesize")) or 6
    local plural, singular = MeasurementSystem.WorldUnitNames(dmhub.GetSettingValue("map:worldunit"), dmhub.GetSettingValue("map:worldunitname"))
    return { amount = amount, unitName = plural, unitSingular = singular }
end

--A distance of `tiles` tiles on a world map, e.g. "18 miles".
function MeasurementSystem.WorldDistanceString(tiles, scale)
    local d = round(tiles * scale.amount * 10) / 10
    return string.format("%s %s", MeasurementSystem.ToString(d), cond(d == 1, scale.unitSingular, scale.unitName))
end

dmhub.DistanceDisplayFunction = function(num)
    local sys = MeasurementSystem.CurrentSystem()
    local n = tonumber(num)
    if sys == nil or n == nil then
        return tostring(num)
    end

    local world = MeasurementSystem.WorldMapScale()
    if world ~= nil then
        return MeasurementSystem.WorldDistanceString(n / dmhub.unitsPerSquare, world)
    end

    local display = MeasurementSystem.NativeToDisplay(n, sys)
    local unitName = sys.unitName
    if sys.value == "Tiles" and MeasurementSystem.IsHexMap() then
        unitName = "Hexes"
    end
    return string.format("%s %s", display, unitName)
end
