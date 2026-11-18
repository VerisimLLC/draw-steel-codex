--Run from the draw-steel-codex root: ../dependencies/lua/bin/lua.exe tests/hero_forced_move_prompt_test.lua
--Report SWJWEMWN: a hero's push/pull/slide on a monster was answered by the
--Monster AI, so the hero's player never chose the destination. Runs the real
--prompt-callback choice from ExecuteInvoke (AbilityInvokeAbility.lua) against
--stubs: a forced move invoked by a hero must go to the player, while a monster
--made to free strike by a hero (To the Death!, SASGFH6V) is still the AI's.

local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local path = "DMHub Game Rules/AbilityInvokeAbility.lua"
local f = assert(io.open(path, "rb"))
local s = f:read("*a"):gsub("\r\n", "\n")
f:close()

local first = "        --false unless the Monster AI controls the invoker.\n"
local last = "        print(\"AI:: PUSH:: IN INVOKE token\""
local start = assert(s:find(first, 1, true), "start marker not found")
local finish = assert(s:find(last, start, true), "end marker not found")
local chunk = "return function(invokerToken, casterToken, abilityClone, targeting)\n"
    .. s:sub(start, finish - 1)
    .. "        return aiPromptCallback\nend\n"
local choose = assert(load(chunk, "ExecuteInvoke prompt callback choice"))()

--Globals go through rawset so LuaLS does not retype the real ones.
local aiCallback = function() return "inherit" end
rawset(_G, "creature", { GetTokenAIPromptCallback = function() return false end })
rawset(_G, "MonsterAI", {
    PromptCallbackForCreature = function(token)
        if token.directorRun then return aiCallback end
        return nil
    end,
})

local hero = { charid = "hero", directorRun = false }
local monster = { charid = "skeleton", directorRun = true }

local function ability(name)
    return { name = name }
end

--The hero's forced movement: the slid monster is the caster of the prompt.
for _, name in ipairs({ "Push!", "Pull!", "Slide!" }) do
    local cb = choose(hero, monster, ability(name), "prompt")
    check(not cb, name .. " invoked by a hero on a monster must be the player's choice, not the Monster AI's")
end

--To the Death!: a hero's ability makes the monster free strike; the AI picks.
local cb = choose(hero, monster, ability("Free Strike Against Specific Target"), "prompt")
check(cb == aiCallback, "a monster's free strike forced by a hero must still be answered by the Monster AI")

--A monster's own forced movement is still the AI's.
cb = choose(monster, hero, ability("Push!"), "prompt")
check(cb == aiCallback, "a monster pushing a hero must still be answered by the Monster AI")

--A hero's own prompt with a hero caster is the player's.
cb = choose(hero, hero, ability("Slide!"), "prompt")
check(not cb, "a hero's prompt on itself must be the player's")

print(string.format("hero_forced_move_prompt: %d checks passed", checks))
