--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/power_roll_display_cast_test.lua
--A power-roll modifier whose displayCondition reads cast.mode (Acolyte of Fire's
--Hurl Element bonus) must not raise a GoblinScript runtime error when the card is
--built with no cast (options.symbols nil, or no cast in it).
local function readSource(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a'):gsub('\r\n', '\n'); f:close()
    return s
end

local checks = 0
local function check(cond, msg)
    assert(cond, msg)
    checks = checks + 1
end

--The real GenerateSymbols from Creature.lua.
local creatureSource = readSource('DMHub Game Rules/Creature.lua')
local gsStart = assert(creatureSource:find('function GenerateSymbols(self, symbolTable)', 1, true))
local gsStop = assert(creatureSource:find('\nfunction creature:GetLevelInClass', gsStart, true))
assert(load(creatureSource:sub(gsStart, gsStop), 'GenerateSymbols'))()

function GoblinScriptTrue(v) return v ~= nil and v ~= false and v ~= 0 end

--Mimics the compiled GoblinScript for 'cast.mode = 4': the dot operator looks up
--'cast' and then calls the result to read 'mode'; runtime errors are caught and
--recorded as ExecuteGoblinScript does.
local runtimeErrors = {}
function ExecuteGoblinScript(formula, symbols, defaultValue, contextMessage)
    local ok, result = pcall(function()
        local cast = symbols('cast')
        local mode = tonumber(cast('mode')) or 0
        return mode == 4
    end)
    if not ok then
        runtimeErrors[#runtimeErrors+1] = tostring(result)
        return defaultValue
    end
    return result
end

local source = readSource('Draw Steel Core Rules/MCDModifyPowerRolls.lua')
local start = assert(source:find('    shouldShowInPowerRollDialog = function(self, creature, rollType, roll, options)', 1, true))
local stop = assert(source:find('    modifyPowerRoll = function(self, creature, rollType, roll, options)', start, true))
local chunk = 'local RollTypeMatches, ResolveRollCharacteristic = ...\nreturn {\n' .. source:sub(start, stop - 1) .. '}\n'
local typeInfo = assert(load(chunk, 'power modifier display'))(
    function() return true end,
    function() return nil end)

local function modifier(fields)
    local m = {
        displayCondition = '',
        try_get = function(self, k, d) if self[k] == nil then return d end return self[k] end,
        has_key = function(self, k) return self[k] ~= nil end,
        PassesFilter = function() return true end,
        HasResourcesAvailable = function() return true end,
        AppendSymbols = function(self, t) return t end,
    }
    for k, v in pairs(fields) do m[k] = v end
    return m
end

local hero = {
    LookupSymbol = function(self, t) return GenerateSymbols(nil, t) end,
}

local formula = 'cast.mode = 4'

--No options.symbols at all: the ability menu building the card.
local mod = modifier{displayCondition = formula}
local shown = typeInfo.shouldShowInPowerRollDialog(mod, hero, 'ability_power_roll', nil, {})
check(#runtimeErrors == 0, 'displayCondition reading cast.mode with no cast raised a GoblinScript error: ' .. tostring(runtimeErrors[1]))
check(shown == false, 'with no cast, cast.mode = 4 must read false')

--options.symbols present but no cast in it.
runtimeErrors = {}
shown = typeInfo.shouldShowInPowerRollDialog(mod, hero, 'ability_power_roll', nil, {symbols = {}})
check(#runtimeErrors == 0, 'displayCondition with symbols but no cast raised a GoblinScript error: ' .. tostring(runtimeErrors[1]))
check(shown == false, 'with symbols but no cast, cast.mode = 4 must read false')

--A real cast with mode 4 still passes.
local castObj = {mode = 4, lookupSymbols = {mode = function(c) return c.mode end}}
runtimeErrors = {}
shown = typeInfo.shouldShowInPowerRollDialog(mod, hero, 'ability_power_roll', nil, {symbols = {cast = castObj}})
check(#runtimeErrors == 0, 'a real cast must evaluate cleanly: ' .. tostring(runtimeErrors[1]))
check(shown == true, 'a cast in mode 4 must show the modifier')

--hintPowerRollAfter's displayAfterRoll reads the same cast symbol.
local after = modifier{activationAfterRoll = formula, displayAfterRoll = formula}
runtimeErrors = {}
local hint = typeInfo.hintPowerRollAfter(after, hero, 'ability_power_roll', {})
check(#runtimeErrors == 0, 'displayAfterRoll reading cast.mode with no cast raised a GoblinScript error: ' .. tostring(runtimeErrors[1]))
check(hint == nil, 'with no cast, displayAfterRoll cast.mode = 4 must hide the hint')

runtimeErrors = {}
hint = typeInfo.hintPowerRollAfter(after, hero, 'ability_power_roll', {symbols = {cast = castObj}})
check(#runtimeErrors == 0 and hint ~= nil and hint.result == true, 'a cast in mode 4 must activate the after-roll hint')

print('power_roll_display_cast: ' .. checks .. ' checks passed')
