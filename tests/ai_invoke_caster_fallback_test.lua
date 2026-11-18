--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_invoke_caster_fallback_test.lua
--ExecuteInvoke's Monster AI fallback for a per-target invoke, where the target
--is the caster. A hero pushing an AI-run monster still picks the squares
--(WR3ESYAG); To the Death!'s target still makes its own free strike (SASGFH6V).
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true), "start marker not found: " .. first)
    local finish = last and assert(source:find(last, start + #first, true), "end marker not found: " .. last) or #source + 1
    return source:sub(start, finish - 1)
end
--Mocks of real globals go through rawset so LuaLS does not retype them codex-wide.
local function stub(name, value) rawset(_G, name, value) end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local monsterAI = {prompts = {}}
stub("MonsterAI", monsterAI)
assert(load(section("Monster AI/MonsterAIPanel.lua",
    "function MonsterAI.PromptAnswersForCaster",
    "MonsterAIPanel = function()")))()

--The free-strike registration must carry the opt-in flag.
local promptsSource = section("Monster AI/MonsterAIPrompts.lua",
    'id = "Generic Free Strike Against Specific Target"', "handler")
check(promptsSource:find("answersForCaster = true", 1, true) ~= nil,
    "Free Strike Against Specific Target opts in to answering for its caster")
monsterAI.prompts["Free Strike Against Specific Target"] = {answersForCaster = true}
monsterAI.prompts["Push!"] = {}

--Only AI-run tokens get a callback from the fallback.
local aiCallback = function() return "ai" end
monsterAI.PromptCallbackForCreature = function(token)
    if token.aiRun then
        return aiCallback
    end
    return nil
end

--The real fallback block, run with the invoke's locals as parameters.
local fallbackBlock = section("DMHub Game Rules/AbilityInvokeAbility.lua",
    "local aiPromptCallback = creature.GetTokenAIPromptCallback(invokerToken.charid)",
    'print("AI:: PUSH:: IN INVOKE')
local chooseCallback = assert(load(
    "local invokerToken, casterToken, abilityClone, targeting = ...\n"
    .. fallbackBlock .. "\nreturn aiPromptCallback"))

stub("creature", {GetTokenAIPromptCallback = function() return false end})

local hero = {charid = "hero"}
local monster = {charid = "monster", aiRun = true}

check(chooseCallback(hero, monster, {name = "Push!"}, "prompt") == false,
    "a hero's push on an AI-run monster is left to the hero's player")
check(chooseCallback(hero, monster, {name = "Free Strike Against Specific Target"}, "prompt") == aiCallback,
    "To the Death!'s target free strike is answered by the AI")
check(chooseCallback(monster, monster, {name = "Push!"}, "prompt") == aiCallback,
    "an AI-run invoker still has its own prompts answered")
check(chooseCallback(hero, monster, {name = "Unregistered"}, "prompt") == false,
    "a prompt with no registration is left to the invoker")

print(string.format("ai_invoke_caster_fallback_test: %d checks passed", checks))
