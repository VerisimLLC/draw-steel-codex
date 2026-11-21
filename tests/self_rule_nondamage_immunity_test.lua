--Run from the draw-steel-codex root with ../dependencies/lua/bin/lua.exe tests/self_rule_nondamage_immunity_test.lua
--"Immune to Non Damage Effects" (Elixir of Saint Elspeth, Cast Away All Hope,
--Juked, ...) protects a creature from OTHER creatures' non-damage effects. It
--must not cancel the creature's own self-targeted rules, e.g. a Conduit's
--Pray result "Gain 5 Piety; choose and use a domain effect" (issue GH566M36).
local path = 'Draw Steel Core Rules/MCDMAbilityBehavior.lua'
local f = assert(io.open(path, 'rb'))
local source = f:read('*a'):gsub('\r\n', '\n'); f:close()

local start = assert(source:find('\nfunction ActivatedAbilityDrawSteelCommandBehavior:ExecuteCommandInternal(', 1, true), 'ExecuteCommandInternal not found')
local stop = assert(source:find('\nend\n', start, true), 'end of ExecuteCommandInternal not found')
local body = source:sub(start + 1, stop + 4)

--Engine stubs: only what ExecuteCommandInternal touches on these paths.
regex = {
    MatchGroups = function(str, pattern)
        if pattern == 'TEST_NONDAMAGE' and str:find('^gain ') then return {all = str} end
        if pattern == 'TEST_DAMAGE' and str:find('^%d+ damage') then return {all = str} end
        return nil
    end,
    ReplaceAll = function(str, pattern, repl) return str end,
}
dmhub = {GetTable = function() return {} end}
unhidden_pairs = pairs
ActivatedAbilityDrawSteelCommandBehavior = {
    ResolveOrGroups = function(rule) return rule end,
    NormalizeRuleTextForCreature = function(_, rule) return rule end,
}

local executed = {}
local patterns = {
    {pattern = 'TEST_NONDAMAGE', isdamage = false, execute = function() executed[#executed+1] = 'nondamage' end},
    {pattern = 'TEST_DAMAGE', isdamage = true, execute = function() executed[#executed+1] = 'damage' end},
}
local chunk = 'local g_rulePatterns = ...\n' .. body
assert(load(chunk, 'ExecuteCommandInternal'))(patterns)
local Behavior = ActivatedAbilityDrawSteelCommandBehavior

local function Token(charid, immune)
    return {
        charid = charid,
        valid = true,
        properties = {
            CalculateNamedCustomAttribute = function(_, name)
                if name == 'Immune to Non Damage Effects' and immune then return 1 end
                return 0
            end,
        },
    }
end

local function Options(redirect, retargets)
    local cast = {
        RedirectDamageTarget = function() return redirect end,
        try_get = function(_, k, d) if k == 'retargets' and retargets ~= nil then return retargets end return d end,
    }
    return {symbols = {cast = cast}}
end

local checks = 0
local function Run(caster, target, options, rule)
    executed = {}
    Behavior:ExecuteCommandInternal({name = 'Test'}, caster, target, options, rule)
    return table.concat(executed, ',')
end
local function Check(cond, msg)
    assert(cond, msg)
    checks = checks + 1
end

local conduit = Token('conduit', true)

--Own rule on itself: the immunity must not apply.
Check(Run(conduit, conduit, Options(), 'Gain 5 Piety') == 'nondamage',
    'a creature immune to non-damage effects must still run its own self-targeted non-damage rule (Pray: Gain 5 Piety)')
--Same creature through a different token object.
Check(Run(Token('conduit', false), conduit, Options(), 'Gain 5 Piety') == 'nondamage',
    'self-targeted rule must run when the caster token is a different object for the same creature')

--Another creature's rule: still blocked, damage still lands.
local enemy = Token('enemy', false)
Check(Run(enemy, conduit, Options(), 'Gain 5 Piety') == '',
    "another creature's non-damage effect must still be ignored by an immune target")
Check(Run(enemy, conduit, Options(), '5 damage') == 'damage',
    "another creature's damage must still apply to an immune target")
Check(Run(enemy, Token('plain', false), Options(), 'Gain 5 Piety') == 'nondamage',
    'a target without the immunity takes non-damage effects')

--Redirect / retarget immunity paths are unchanged, even on a self-cast.
Check(Run(conduit, conduit, Options(Token('other', false)), 'Gain 5 Piety') == '',
    'a damage-only redirect must still block non-damage effects')
Check(Run(conduit, conduit, Options(nil, {{retargetType = 'none', retargetid = 'conduit'}}), 'Gain 5 Piety') == '',
    'a damage-only retarget entry must still block non-damage effects')

print('self_rule_nondamage_immunity: ' .. checks .. ' checks passed')
