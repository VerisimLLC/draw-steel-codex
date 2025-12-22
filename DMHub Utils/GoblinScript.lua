local mod = dmhub.GetModLoading()

local g_useCompiled = false

local g_compiledGoblinScript
g_compiledGoblinScript = setting{
    id = "compiledgoblinscript",
    name = "Compiled Goblin Script",
    default = true,
    description = "Use compiled Goblin Script evaluation where possible. Improves performance.",
    onchange = function()
        g_useCompiled = g_compiledGoblinScript:Get()
        print("GoblinScript: use compiled =", g_useCompiled)
    end,
}

g_useCompiled = g_compiledGoblinScript:Get()

local g_compiled = {}
local g_errors = {}

Commands.flushcompiledgoblinscript = function()
    g_compiled = {}
    g_errors = {}
    print("GoblinScript: Flushed compiled formula cache")
end

local g_debugEntries = {}
local g_debugScheduled = false
local g_debugPanel = nil

function RegisterGoblinScriptDebugPanel(panel)
    g_debugPanel = panel
end

local function LogDebugEntry(entry)
    if not g_debugPanel.valid then
        g_debugPanel = nil
    else
        g_debugEntries[#g_debugEntries+1] = entry
        if g_debugScheduled == false then
            g_debugScheduled = true
            dmhub.Schedule(0.1, function()
                g_debugScheduled = false
                if g_debugPanel ~= nil and g_debugPanel.valid then
                    g_debugPanel:FireEvent("debugEntries", g_debugEntries)
                end
                g_debugEntries = {}
            end)
        end
    end
end

local g_profileGoblinScript = dmhub.ProfileMarker("ExecuteGoblinScript")

local g_profileInstruments = {}

function ExecuteGoblinScript(formula, symbols, defaultValue, contextMessage)
    if formula == "" or formula == nil then
        return defaultValue
    end

    local t = type(formula)
    if t == "number" then
        return formula
    end
--[[
    local profile = g_profileInstruments[formula]
    if profile == nil then
        profile = dmhub.ProfileMarker("GoblinScript:" .. formula)
        g_profileInstruments[formula] = profile
    end

    local _ = profile.Begin
    ]]

    if (not g_useCompiled) or t ~= "string" then
        local result = dmhub.EvalGoblinScriptDeterministic(formula, symbols, defaultValue, contextMessage)
        --print("GoblinScript:: EVAL", formula, "DETERMINISTIC ->", result)
        --local _ = profile.End
        return result
    end

    local fn = g_compiled[formula]

    if fn == nil then
        local out = {}
        fn = dmhub.CompileGoblinScriptDeterministic(formula, out)
        print("GoblinScript:: Compiled formula", formula, "becomes", out)
        if out.error then
            print("GoblinScript: Error in formula", formula, "error:", out.error)
        end

        if fn == nil then
            fn = false
        end

        g_compiled[formula] = fn
    end

    if fn == false then
        --print("GoblinScript:: EVAL", formula, "COULD NOT COMPILE ->", result)
        --local _ = profile.End
        return defaultValue
    else
        if type(symbols) == "table" then
            symbols = GenerateSymbols(symbols)
        end

        local ok, result = pcall(fn,symbols)
        local error
        if not ok then
            error = result
            result = defaultValue
            if g_errors[formula] == nil then
                print("GoblinScript: Runtime error in formula", formula, "error:", result)
                g_errors[formula] = true
            end
        elseif result == nil then
            result = defaultValue
        end

        --print("GoblinScript:: EVAL", formula, "CALCULATED ->", result, "ok", ok)
        if result == true then
            result = 1
        elseif result == false then
            result = 0
        end


        if g_debugPanel ~= nil then
            LogDebugEntry{
                input = formula,
                deterministic = true,
                result = result,
                error = error,
                reason = contextMessage,
                lookupFunction = symbols,
                lookups = {},
            }
        end


        --local _ = profile.End
        return result
    end
end

BuiltinGoblinScriptFunctions = {
    min = math.min,
    max = math.max,
    floor = math.floor,
    ceiling = math.ceil,
    friends = function(a, b)
        local toka = dmhub.LookupToken(a)
        local tokb = dmhub.LookupToken(b)
        if toka == nil or tokb == nil then
            return false
        end

        return toka:IsFriend(tokb)
    end,

    lineofsight = function(a, b)
        local toka = dmhub.LookupToken(a)
        local tokb = dmhub.LookupToken(b)
        if toka == nil or tokb == nil then
            return 1
        end
        local coverInfo = dmhub.GetCoverInfo(toka, tokb)
        if coverInfo == nil then
            return 1
        end

        return 1 - coverInfo.coverModifier
    end,

    substring = function(haystack, needle)
        return string.find(haystack, needle) ~= nil
    end,
}

GoblinScriptTestObject = RegisterGameType("GoblinScriptTestObject")
GoblinScriptTestObject.lookupSymbols = {
    self = function(c)
        return c
    end,

    symbols = function(c)
        return GenerateSymbols(c)
    end,

    level = function(c)
        return 1
    end,

    stamina = function(c)
        return 10
    end,

    maximumstamina = function(c)
        return 30
    end,

    monstertype = function(c)
        return "Goblin"
    end,

    conditions = function(c)
        return StringSet.new{
            strings = {"Poisoned", "Weakened"},
        }
    end,
}

local testInstance = GoblinScriptTestObject.new()

local function UnitTestGoblinScript(formula, expectedValue, out)
    local symbols = GenerateSymbols(testInstance)
    local fn = dmhub.CompileGoblinScriptDeterministic(formula, out)
    if out.error then
        print("GoblinScript Unit Test: FAILED to compile formula", formula, "error:", out.error)
        return false
    end

    local ok,result = pcall(fn,symbols)
    if not ok then
        print("GoblinScript Unit Test: RUNTIME ERROR in formula", formula, "error:", result)
        return false
    end

    if result == true then
        result = 1
    elseif result == false then
        result = 0
    end

    if result ~= expectedValue then
        print("GoblinScript Unit Test: FAILED formula", formula, "expected", expectedValue, "got", result)
        return false
    end

    return true
end

Commands.goblinscriptunittest = function(str)
    local tests = {
        {"18 + (Level - 1)*6", 18 + (1 - 1)*6},
        {"min(10, 20)", 10},
        {"max(10, 20)", 20},
        {"floor(3.7)", 3},
        {"ceiling(3.2)", 4},
        {"self.stamina + 5", 15},
        {"self.monstertype = \"Goblin\"", 1},
        {"self.monstertype ~= \"Goblin\"", 0},
        {"self.conditions has \"Poisoned\"", 1},
        {"self.conditions has \"Burning\"", 0},
        {"5 when stamina > 5", 5},
        {"5 when stamina < 5", 0},
        {"2 + 5 when stamina > 5 and level = 1 else 12", 7},
        {"2 + 5 when stamina < 5 and level = 1 else 12", 14},
        {"max(stamina, 118, 4, 170, 24)", 170},
        {"stamina or level or 4", 10},
        {"stamina or level or 18", 18},
        {"stamina + x where x = 7", 17},
        {"Stamina <= Maximum Stamina/2", 1},
        {"Stamina <= Maximum Stamina/4", 0},
        {"symbols = self", 1},
        {"symbols = symbols", 1},
        {"symbols != self", 0},
        {"symbols != symbols", 0},
    }

    local allPassed = true
    for i, test in ipairs(tests) do
        local formula = test[1]
        local expectedValue = test[2]
        local out = {}
        local passed = UnitTestGoblinScript(formula, expectedValue, out)
        if not passed then
            print("GoblinScript Unit Test: Lua code for failed", formula, ":\n", out.lua)
            allPassed = false
        end
    end

    if allPassed then
        print("GoblinScript Unit Test: ALL TESTS PASSED")
    else
        print("GoblinScript Unit Test: SOME TESTS FAILED")
    end

end