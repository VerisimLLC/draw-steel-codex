local mod = dmhub.GetModLoading()

--This file implements Measurement Systems. If you want to add a new type of measurement system, or
--add some functionality to measurement systems you can do so in this file.

--- @class MeasurementSystem: GameType
--- @field systems table[] List of available measurement system descriptors (id, value, unitName, unitSingular, etc.).
--- @field value string Setting value id for this system (used to match dmhub.GetSettingValue("measurementsystem")).
--- @field unitName string Plural unit label (e.g. "feet", "meters").
--- @field unitSingular string Singular unit label (e.g. "foot", "meter").
--- Manages conversion between native (world unit) measurements and display units.
MeasurementSystem = RegisterGameType("MeasurementSystem")

dmhub.unitsPerSquare = 5

local g_cachedSetting = nil
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

dmhub.DistanceDisplayFunction = function(num)
    local sys = MeasurementSystem.CurrentSystem()
    local n = tonumber(num)
    if sys == nil or n == nil then
        return num
    end

    n = MeasurementSystem.NativeToDisplay(n, sys)
    return string.format("%s %s", n, sys.unitName)
end
