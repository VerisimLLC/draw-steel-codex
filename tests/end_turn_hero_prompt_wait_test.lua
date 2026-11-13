--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/end_turn_hero_prompt_wait_test.lua
--The between-turn handlers that keep an ended turn current while a hero has a
--trigger prompt nobody has answered (playtest 2026-11-05 N4: an ally ended
--their turn and the Tactician's Mark: Benefit prompt died 6s later, unread).
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(last, start + #first, true))
    return source:sub(start, finish - 1)
end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

--Globals the code under test reads, set through rawset so LuaLS does not take
--these stubs for more definitions of the real globals.
local function stub(name, value) rawset(_G, name, value) end

local now = 0
local logs = {}
local heroTriggers = {}
local playerSide = true
local queue = {hidden = false, currentTurn = "hero", entries = {hero = {}}}
function queue:try_get(key) return self[key] end
function queue:IsEntryPlayer(id) return playerSide end
stub("InitiativeQueue", {GetInitiativeId = function(token) return "hero" end})

local heroProps = {}
--The name of the hero's accepted trigger still resolving (creature:TurnClaimResolving), or nil.
local claimResolving = nil
function heroProps:GetAvailableTriggers() return next(heroTriggers) ~= nil and heroTriggers or nil end
function heroProps:TurnClaimResolving() return claimResolving end
local heroToken = {valid = true, playerControlled = true, name = "Villyroth", properties = heroProps}

local function Prompt(fields)
    local t = {triggered = false, dismissed = false, abilityName = "Mark: Benefit"}
    for k,v in pairs(fields or {}) do t[k] = v end
    function t:try_get(key, default)
        local v = self[key]
        if v == nil then return default end
        return v
    end
    return t
end

stub("dmhub", {Time = function() return now end, allTokens = {heroToken}, initiativeQueue = queue})
stub("printf", function(fmt, ...) logs[#logs+1] = string.format(fmt, ...) end)
local registered = {}
stub("GameHud", {RegisterBetweenTurnHandler = function(args) registered[args.id] = args end})
stub("Tip", {notices = {}})

assert(load(section("Draw Steel Core Rules/MCDMInitiativeBar.lua",
    "--Hold the ended turn open while a hero has a trigger prompt", "local g_beginRoundStyles")))()

local first = registered["End Turn Hero Prompts"]
local second = registered["End Turn Hero Prompts After Villain Actions"]
check(first ~= nil and first.priority > 0 and first.priority < 50, "first pass runs after casts, before villain actions")
check(second ~= nil and second.priority > 50, "second pass runs after villain actions")
local notice = rawget(_G, "Tip").notices["end-turn-hero-prompt"]
check(notice ~= nil, "banner notice registered")

--Drive a wait the way RunBetweenTurnHandler does, calling setup before each resume.
local function drive(context, setup)
    local result = nil
    local co = coroutine.create(function()
        result = rawget(_G, "GameHud").WaitForHeroTriggerPrompts(context)
    end)
    local resumes = 0
    while coroutine.status(co) ~= "dead" do
        setup(resumes)
        local ok, delay = coroutine.resume(co)
        assert(ok, delay)
        resumes = resumes + 1
        if coroutine.status(co) ~= "dead" then
            now = now + (delay or 0.1)
        end
        assert(resumes < 100000, "wait never finished")
    end
    return result
end

local function Context() return {initiativeQueue = queue, endedInitiativeId = "hero"} end

--No prompts: no hold, no banner, no log.
heroTriggers = {}
logs = {}
check(drive(Context(), function() end) == "none", "nothing open passes straight through")
check(#logs == 0, "no hold logged")

--An open prompt holds until its owner answers it; the banner names it meanwhile.
local start = now
local bannerText = nil
heroTriggers = {p1 = Prompt()}
local result = drive(Context(), function()
    if now - start >= 12 then
        heroTriggers.p1.triggered = true
    elseif bannerText == nil and now > start then
        bannerText = notice.text()
    end
end)
check(result == "answered", "released once answered")
check(now - start >= 12, "turn held while the prompt was open")
check(bannerText == "Waiting for Villyroth's Mark: Benefit", "banner names the hero and prompt, got " .. tostring(bannerText))
check(notice.text() == nil, "banner gone after release")

--Prompts the turn change would not end (hostile), or that belong to a roll in
--progress, or hidden merged members, do not hold the turn.
for _,fields in ipairs{{hostile = true}, {powerRollModifier = {}}, {mergedInto = "front"}, {dismissed = true}} do
    heroTriggers = {p = Prompt(fields)}
    check(drive(Context(), function() end) == "none", "non-holding prompt passes through")
end

--Continue releases the turn, and the second pass does not hold for it again.
heroTriggers = {p1 = Prompt()}
local context = Context()
result = drive(context, function(resumes)
    if resumes == 3 then
        local _, controls = notice.text()
        assert(controls ~= nil and controls.action ~= nil, "banner offers Continue")
        controls.action.press()
    end
end)
check(result == "continued", "Continue releases the turn")
check(drive(context, function() end) == "continued", "second pass honors Continue")

--A party hero that is not playerControlled still counts through its
--players'-side initiative entry; a monster's prompt does not hold the turn.
heroToken.playerControlled = false
heroTriggers = {p1 = Prompt()}
playerSide = true
result = drive(Context(), function(resumes)
    if resumes == 2 then heroTriggers.p1.dismissed = true end
end)
check(result == "answered", "party hero on the players' side holds the turn")
playerSide = false
heroTriggers = {p1 = Prompt()}
check(drive(Context(), function() end) == "none", "monster-side prompt does not hold the turn")
heroToken.playerControlled = true

--A hero claiming the turn during the hold (Hesitation Is Weakness) ends the wait.
result = drive(Context(), function(resumes)
    if resumes == 2 then queue.currentTurn = "other" end
end)
check(result == "turn moved on", "claimed turn ends the wait")
queue.currentTurn = "hero"

--An accepted prompt whose cast is still resolving keeps the hold: its card is
--gone, but Hesitation Is Weakness has not claimed the turn yet. Passing the turn
--now crossed the two initiative writes and the Monster AI played the hero's
--stolen turn (AH6SYXTP). When the claim lands the wait reports it.
heroTriggers = {p1 = Prompt()}
bannerText = nil
result = drive(Context(), function(resumes)
    if resumes == 2 then
        heroTriggers = {}
        claimResolving = "Hesitation Is Weakness"
    elseif resumes == 6 then
        bannerText = notice.text()
    elseif resumes == 8 then
        queue.currentTurn = "other"
    end
end)
check(result == "turn moved on", "hold lasts until the claim lands, got " .. tostring(result))
check(bannerText == "Waiting for Villyroth's Hesitation Is Weakness to finish", "banner names the resolving trigger, got " .. tostring(bannerText))
queue.currentTurn = "hero"

--Accepted before the hold began (no card ever seen) still holds; a resolving
--trigger that never claims the turn releases it when it finishes.
heroTriggers = {}
claimResolving = "Mark: Benefit"
result = drive(Context(), function(resumes)
    if resumes == 4 then claimResolving = nil end
end)
check(result == "answered", "resolving trigger released without a claim, got " .. tostring(result))
claimResolving = nil
heroTriggers = {p1 = Prompt()}

--A prompt nobody answers is released at the deadline (it ages out then anyway).
start = now
result = drive(Context(), function() end)
check(result == "deadline" and now - start >= 600 and now - start < 601, "bounded by the 600s prompt age-out")

print(string.format("end_turn_hero_prompt_wait_test: %d checks passed", checks))
