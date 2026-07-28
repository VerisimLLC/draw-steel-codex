-- Prompt resolver harness for MCP-driven ability testing.
-- Paste into mcp__dmhub__execute_lua (NOT a codex mod file -- lives in the Lua
-- global environment). Requires the aicontrol heartbeat pin on the same token
-- (see MCP_DRIVING_NOTES.md).
--
-- What it does: installs creature._tmp_aipromptCallback, the same hook the
-- Monster AI turn loop uses, so prompt-targeted invokes (push/pull/slide
-- destinations, sub-ability prompts) resolve without UI clicks.
--   1. If the Monster AI module is loaded, its registered prompt handlers
--      (MonsterAIPrompts.lua) get first crack.
--   2. Push!/Pull!/Slide! fall back to a built-in resolver that picks the
--      FARTHEST valid straight-line destination (deterministic for tests).
--   3. Anything else is parked in PR.pending; the MCP session inspects it and
--      answers with PR.Resolve{targets = {{loc = ...}}} (or {{token = ...}}),
--      or lets it time out to the manual UI.
--
-- Usage:
--   _G.PR.Install(casterCharid)     -- after installing the aicontrol pin
--   _G.PR.pending                   -- poll from MCP: nil or prompt info table
--   _G.PR.Resolve{targets={{loc=core.Loc{x=5,y=5,floorIndex=game.currentFloorIndex}}}}
--   _G.PR.log                       -- trace of what was resolved and how

_G.PR = {
    pending = nil,
    resolution = nil,
    timeout = 60,
    log = {},
}

local function ResolveForcedMove(invokerToken, casterToken, abilityClone, symbols, options)
    local range = abilityClone:GetRange(casterToken.properties)
    local filter = abilityClone:TargetLocPassesFilterPredicate(casterToken, symbols) or function() return true end
    local loc = casterToken.loc
    for i = 1, range do loc = loc.north.west end
    local candidates = {}
    for _, dir in ipairs({"east", "south", "west", "north"}) do
        for i = 1, range * 2 do
            if filter(loc) then candidates[#candidates + 1] = loc end
            loc = loc[dir]
        end
    end
    local bestLoc, bestDist = nil, -1
    for _, c in ipairs(candidates) do
        local mi = casterToken:MarkMovementArrow(c, {straightline = true, ignorecreatures = false})
        if mi ~= nil then
            local d = mi.path.destination:DistanceInTiles(mi.path.origin)
            if d > bestDist then bestDist, bestLoc = d, c end
        end
    end
    casterToken:ClearMovementArrow()
    if bestLoc ~= nil then
        return {targets = {{loc = bestLoc}}}
    end
end

function _G.PR.Install(charid)
    local tok = dmhub.GetTokenById(charid)
    if tok == nil then print("PR: no token", charid) return end
    tok.properties._tmp_aipromptCallback = function(invokerToken, casterToken, abilityClone, symbols, options)
        local name = abilityClone.name
        -- 1) Monster AI registered handlers, when that module is loaded in this game.
        local monsterAI = rawget(_G, "MonsterAI")
        if monsterAI ~= nil then
            local handler = monsterAI.prompts[name]
                or monsterAI.prompts[string.format("%s:%s", invokerToken.properties.monster_type or "", name)]
            if handler ~= nil then
                local ok, result = pcall(handler.handler, monsterAI, invokerToken, casterToken, abilityClone, symbols, options)
                if ok and type(result) == "table" then
                    for k, v in pairs(result) do options[k] = v end
                    _G.PR.log[#_G.PR.log + 1] = "auto-resolved via Monster AI handler: " .. name
                    return "inherit"
                end
            end
        end
        -- 2) built-in forced movement resolver.
        if name == "Push!" or name == "Pull!" or name == "Slide!" then
            local ok, result = pcall(ResolveForcedMove, invokerToken, casterToken, abilityClone, symbols, options)
            if ok and type(result) == "table" then
                for k, v in pairs(result) do options[k] = v end
                _G.PR.log[#_G.PR.log + 1] = "auto-resolved forced move: " .. name
                return "inherit"
            elseif not ok then
                _G.PR.log[#_G.PR.log + 1] = "forced move resolver error: " .. tostring(result)
            end
        end
        -- 3) park for MCP inspection/resolution.
        _G.PR.pending = {
            abilityName = name,
            prompt = abilityClone:try_get("promptOverride"),
            targetType = abilityClone:try_get("targetType"),
            range = abilityClone:GetRange(casterToken.properties),
            casterid = casterToken.charid,
            casterLoc = {x = casterToken.loc.x, y = casterToken.loc.y},
            invokerid = invokerToken.charid,
        }
        _G.PR.log[#_G.PR.log + 1] = "parked prompt: " .. name
        local deadline = dmhub.Time() + _G.PR.timeout
        while _G.PR.resolution == nil and dmhub.Time() < deadline do
            coroutine.yield(0.1)
        end
        _G.PR.pending = nil
        local res = _G.PR.resolution
        _G.PR.resolution = nil
        if type(res) == "table" then
            for k, v in pairs(res) do options[k] = v end
            _G.PR.log[#_G.PR.log + 1] = "resolved via MCP: " .. name
            return "inherit"
        end
        _G.PR.log[#_G.PR.log + 1] = "timed out, falling back to manual: " .. name
        return "prompt"
    end
    print("PR installed on", charid)
end

function _G.PR.Resolve(options)
    _G.PR.resolution = options
end

print("PR harness ready")
