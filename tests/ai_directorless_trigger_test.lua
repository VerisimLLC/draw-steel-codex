--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_directorless_trigger_test.lua
--MonsterAI.DismissUnhandledDirectorlessTrigger: with nobody in the Director's
--chair, an optional trigger the AI has no handler for is dismissed, not left
--on the host (N5: the Iron Orb's Abyssal Aura).
local function section(path, first, last)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    local start = assert(source:find(first, 1, true))
    local finish = last and assert(source:find(last, start + #first, true)) or #source + 1
    return source:sub(start, finish - 1)
end
--Mocks of real globals go through rawset so LuaLS does not retype them codex-wide.
local function stub(name, value) rawset(_G, name, value) end
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end

local dm = {directorlessPlay = true}
stub("dmhub", dm)
local monsterAI = {}
stub("MonsterAI", monsterAI)
assert(load(section("Monster AI/MonsterAIPanel.lua",
    "function MonsterAI.DismissUnhandledDirectorlessTrigger",
    "GameHud.RegisterBetweenTurnHandler{")))()

local function MakeTrigger(id)
    return {
        id = id,
        abilityName = "Abyssal Aura",
        triggered = false,
        dismissed = false,
        GetText = function() return "Abyssal Aura" end,
    }
end

local dispatched = {}
local props = {availableTriggers = {}}
function props:GetAvailableTriggers() return self.availableTriggers end
function props:DispatchAvailableTrigger(t) dispatched[#dispatched+1] = t.id end
local token = {charid = "orb", properties = props}
function token:ModifyProperties(args) args.execute() end

local logged = {}
local handlers = {}
local ai = {}
function ai:FindTriggerHandler(_, trigger) return handlers[trigger.id] end
function ai:SetLogContext() end
function ai:LogDecision(event, fields) logged[#logged+1] = {event = event, fields = fields} end

local dismiss = monsterAI.DismissUnhandledDirectorlessTrigger

--No handler, no Director: dismissed, dispatched, logged.
local t1 = MakeTrigger("t1")
props.availableTriggers.t1 = t1
check(dismiss(ai, token, t1) == true, "unhandled trigger is dismissed")
check(t1.dismissed == true, "live trigger marked dismissed")
check(dispatched[1] == "t1", "dismissal is dispatched")
check(logged[1].event == "TRIGGER SKIPPED", "dismissal is logged")

--A registered handler (even one that deferred) keeps its say.
local t2 = MakeTrigger("t2")
props.availableTriggers.t2 = t2
handlers.t2 = {id = "Some Handler"}
check(dismiss(ai, token, t2) == false, "handled trigger is left alone")
check(t2.dismissed == false, "handled trigger not dismissed")

--Already answered: nothing to do.
local t3 = MakeTrigger("t3")
t3.triggered = true
props.availableTriggers.t3 = t3
check(dismiss(ai, token, t3) == false, "answered trigger is left alone")

--With a Director at the table the trigger still goes to them.
dm.directorlessPlay = false
local t4 = MakeTrigger("t4")
props.availableTriggers.t4 = t4
check(dismiss(ai, token, t4) == false, "Director game leaves the trigger")
check(t4.dismissed == false, "Director game trigger not dismissed")
check(#dispatched == 1 and #logged == 1, "only the first case wrote anything")

print(string.format("ai_directorless_trigger_test: %d checks passed", checks))
