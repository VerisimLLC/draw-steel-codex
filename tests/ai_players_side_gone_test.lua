--Run from the codex root: ../dependencies/lua/bin/lua.exe tests/ai_players_side_gone_test.lua
--MonsterAI.PlayersSideGone: the Monster AI holds monster turns once no hero is
--left in the fight (2026-11-13 playtest N7: after an EotW defeat the AI
--replayed one monster turn over a thousand times). A queue with no players'
--entries (monster versus monster) never counts as the players being gone.
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

local tokensByEntry = {}
stub("GameHud", {
    instance = {initiativeInterface = {}},
    GetTokensForInitiativeId = function(_, _, initiativeid) return tokensByEntry[initiativeid] or {} end,
})
local monsterAI = {}
function monsterAI.TokenIsLiveCombatant(tok) return tok.alive end
stub("MonsterAI", monsterAI)
assert(load(section("Monster AI/MonsterAIPanel.lua",
    "function MonsterAI.PlayersSideGone",
    "--Runs as a DockablePanel background process")))()

local function MakeQueue(players)
    local q = {entries = {}}
    for id, isPlayer in pairs(players) do
        q.entries[id] = {}
        q.entries[id].player = isPlayer
    end
    function q:IsEntryPlayer(id) return self.entries[id].player end
    return q
end

local queue = MakeQueue{heroes = true, demons = false}
tokensByEntry.heroes = {{alive = true}, {alive = false}}
tokensByEntry.demons = {{alive = true}}
check(monsterAI.PlayersSideGone(queue) == false, "one live hero keeps the fight going")

tokensByEntry.heroes = {{alive = false}, {alive = false}}
check(monsterAI.PlayersSideGone(queue) == true, "all heroes dead: players gone")

tokensByEntry.heroes = {}
check(monsterAI.PlayersSideGone(queue) == true, "heroes off the map: players gone")

--Several hero entries: any live one counts.
queue = MakeQueue{h1 = true, h2 = true, demons = false}
tokensByEntry.h1 = {}
tokensByEntry.h2 = {{alive = true}}
check(monsterAI.PlayersSideGone(queue) == false, "a live hero in another entry counts")

--Monster versus monster style: no players' entries at all.
queue = MakeQueue{red = false, blue = false}
tokensByEntry.red = {{alive = true}}
tokensByEntry.blue = {}
check(monsterAI.PlayersSideGone(queue) == false, "no players' entries never counts as gone")

print(string.format("ai_players_side_gone_test: %d checks passed", checks))
