--Run from the codex root with ../dependencies/lua/bin/lua.exe tests/streamer_kit_redact_test.lua
--(any Lua 5.1-5.4 works: the module under test is pure).
--Exercises the Streamer Kit redaction gate: nothing Director-only may reach
--the viewer snapshot, and the hero fields viewers are promised come through
--exactly.
if dmhub == nil then
    dmhub = {
        GetModLoading = function() return {} end,
    }
end
dofile("EncounterOfTheWeek/StreamerKitRedact.lua")

local passed = 0
local function check(condition, message)
    if not condition then
        error("FAILED: " .. tostring(message), 2)
    end
    passed = passed + 1
end

--Every Director-only value in the fixture contains this marker, so one scan of
--the output proves none of them got through.
local SECRET = "DIRECTOR_ONLY"

--Keys that must never appear anywhere in the viewer snapshot.
local FORBIDDEN_KEYS = {
    ev = true, notes = true, directorNotes = true, malice = true, maliceCost = true,
    hidden = true, namePrivate = true, hiddenFromEnemies = true, frac = true,
    whoId = true, targetId = true, tokenIds = true,
}

--- Walk a value; call visit(path, key, value) for every key and leaf.
local function Walk(value, path, visit)
    if type(value) ~= "table" then
        visit(path, nil, value)
        return
    end
    for k, v in pairs(value) do
        local p = path .. "." .. tostring(k)
        visit(p, k, v)
        Walk(v, p, visit)
    end
end

local function AssertNoLeaks(out, label)
    Walk(out, "out", function(path, key, value)
        if key ~= nil then
            check(not FORBIDDEN_KEYS[key], label .. ": forbidden key at " .. path)
        end
        if type(value) == "string" then
            check(string.find(value, SECRET, 1, true) == nil, label .. ": Director-only text at " .. path .. " = " .. value)
        end
        check(type(value) ~= "function" and type(value) ~= "userdata", label .. ": non-data value at " .. path)
    end)
end

local function Fixture()
    return {
        seq = 812,
        updated = 1793195195000,
        mode = "combat",
        round = 3,
        malice = 7,
        victories = 2,
        encounter = {
            title = "The Goblin Ambush",
            ev = 120,
            directorNotes = SECRET .. " the chieftain flees at round 4",
            objective = { label = "Free the captives", progress = 1, goal = 3 },
        },
        turn = { kind = "monster", tokenIds = { "m-boss", "m-ambusher" } },
        heroes = {
            {
                id = "h-vex", name = "Vex Thornwood", level = 2, className = "Shadow", ancestry = "Wode Elf",
                notes = SECRET .. " player owes the Director pizza",
                stamina = { cur = 11.6, max = 24, temp = 3 },
                characteristics = { might = -1, agility = 2, reason = 1, intuition = 0, presence = 1, secretStat = SECRET },
                resource = { name = "Insight", value = 5 },
                recoveries = { cur = 4, max = 8 },
                surges = 2,
                victories = 2,
                conditions = { { id = "bleeding", name = "Bleeding" } },
                active = false,
                directorNotes = SECRET,
            },
            {
                id = "h-kal", name = "Kallis", stamina = { cur = 0, max = 30, temp = 0 }, dying = true,
                characteristics = { might = 2, agility = 1, reason = 0, intuition = 0, presence = -1 },
                resource = { name = "Ferocity", value = 1 }, recoveries = { cur = 0, max = 10 }, surges = 0,
                active = true,
            },
        },
        monsters = {
            {
                id = "m-boss", name = "Goblin Underboss", monsterType = "Goblin Underboss",
                stamina = { cur = 18, max = 40 }, ev = 12, notes = SECRET .. " has 2 extra hp", role = "Leader", organization = "Leader", level = 3,
                conditions = {
                    { id = "taunted", name = "Taunted" },
                    { id = "secretly-marked", name = SECRET .. " Marked", hiddenFromEnemies = true },
                },
                abilities = {
                    { id = "a1", name = "Spear Thrust", text = "2d10 + 2; 6 damage", used = true, maliceCost = 0, notes = SECRET },
                    { id = "a2", name = SECRET .. " Unused Trick", text = SECRET .. " big damage", used = false, maliceCost = 3 },
                },
                villainActions = {
                    { id = "va1", name = "Get Them!", text = "Each ally shifts 2.", used = true, notes = SECRET },
                    { id = "va2", name = SECRET .. " Hidden Reserves", text = SECRET .. " reinforcements arrive", used = false },
                    { id = "va3", name = SECRET .. " Last Stand", text = SECRET, used = false },
                },
            },
            {
                id = "m-ambusher", name = SECRET .. " Goblin Ambusher", monsterType = SECRET .. " Ambusher", hidden = true,
                stamina = { cur = 15, max = 15 }, ev = 4,
                abilities = { { id = "x", name = SECRET, text = SECRET, used = true } },
            },
            {
                id = "m-runner1", name = "Goblin Runner", squad = "Runners", minion = true, stamina = { cur = 4, max = 8 },
            },
            {
                id = "m-runner2", name = "Goblin Runner", squad = "Runners", minion = true, stamina = { cur = 0, max = 8 }, dead = true,
            },
            {
                id = "m-masked", name = SECRET .. " Mystery Knight", namePrivate = true, monsterType = SECRET .. " War Knight",
                squad = SECRET, stamina = { cur = 0, max = 50 },
            },
        },
        events = {
            { seq = 1, t = 100, kind = "damage", whoId = "h-vex", who = "Vex Thornwood", targetId = "m-boss", target = "Goblin Underboss", amount = 6 },
            { seq = 2, t = 101, kind = "damage", whoId = "m-ambusher", who = SECRET, targetId = "h-kal", target = "Kallis", amount = 9 },
            { seq = 3, t = 102, kind = "damage", whoId = "h-kal", targetId = "m-masked", target = SECRET .. " Mystery Knight", amount = 12, crit = true },
            { seq = 4, t = 103, kind = SECRET, whoId = "h-vex" },
        },
    }
end

local out = StreamerKitRedact.Redact(Fixture())

--Nothing Director-only reaches the viewer snapshot.
AssertNoLeaks(out, "full fixture")
check(out.malice == nil, "malice is dropped")
check(out.encounter.ev == nil and out.encounter.directorNotes == nil, "encounter EV and notes are dropped")
check(out.v == StreamerKitRedact.FORMAT_VERSION, "format version stamped")

--Encounter card fields.
check(out.encounter.title == "The Goblin Ambush", "title kept")
check(out.round == 3 and out.victories == 2 and out.mode == "combat", "round, victories, mode kept")
check(out.encounter.objective.label == "Free the captives" and out.encounter.objective.progress == 1 and out.encounter.objective.goal == 3, "objective kept")

--Heroes are exact.
local vex, kal = out.heroes[1], out.heroes[2]
check(#out.heroes == 2, "both heroes")
check(vex.name == "Vex Thornwood" and vex.initials == "VT", "hero name and initials")
check(vex.stamina.cur == 12 and vex.stamina.max == 24 and vex.stamina.temp == 3, "hero stamina exact (rounded to whole)")
check(vex.state == "winded", "hero at or under half is winded")
check(vex.characteristics.might == -1 and vex.characteristics.agility == 2 and vex.characteristics.reason == 1
    and vex.characteristics.intuition == 0 and vex.characteristics.presence == 1, "characteristics exact")
check(vex.characteristics.secretStat == nil, "only the five characteristics are copied")
check(vex.resource.name == "Insight" and vex.resource.value == 5, "heroic resource exact")
check(vex.recoveries.cur == 4 and vex.recoveries.max == 8, "recoveries exact")
check(vex.surges == 2 and vex.victories == 2, "surges and victories exact")
check(vex.conditions[1].id == "bleeding", "hero conditions kept")
check(vex.notes == nil and vex.directorNotes == nil, "hero notes dropped")
check(kal.state == "dying" and kal.active == true, "a hero at 0 is dying; active turn kept")

--Foes: bands only, hidden ones gone.
check(out.foes.total == 4, "hidden monster not counted")
check(out.foes.standing == 3, "the dead runner is not standing")
local byId = {}
for _, foe in ipairs(out.foes.list) do
    byId[foe.id] = foe
    check(foe.stamina == nil and foe.cur == nil and foe.max == nil, "no monster stamina numbers for " .. tostring(foe.id))
end
check(byId["m-ambusher"] == nil, "hidden monster dropped entirely")
local boss = byId["m-boss"]
check(boss.state == "winded", "boss at 18/40 is winded")
check(#boss.abilities == 1 and boss.abilities[1].name == "Spear Thrust", "only used abilities shown")
check(#boss.villainActions == 3, "every villain action slot shown")
check(boss.villainActions[1].used and boss.villainActions[1].name == "Get Them!", "used villain action face-up")
check(not boss.villainActions[2].used and boss.villainActions[2].name == nil and boss.villainActions[2].text == nil
    and boss.villainActions[2].slot == 2, "unused villain action face-down")
check(#boss.conditions == 1 and boss.conditions[1].id == "taunted", "hiddenFromEnemies condition dropped")
check(boss.role == nil and boss.organization == nil and boss.level == nil, "monster stat-block metadata not copied")
check(byId["m-runner1"].state == "winded" and byId["m-runner1"].squad == "Runners" and byId["m-runner1"].minion, "minion banded with squad")
check(byId["m-runner2"].state == "defeated", "dead monster defeated")
local masked = byId["m-masked"]
check(masked.name == "???" and masked.squad == nil and masked.monsterType == nil, "private name masked, type and squad withheld")
check(masked.state == "dying", "a monster at 0 not yet dead is dying")

--Turn: names only of visible creatures.
check(out.turn.kind == "monster" and out.turn.name == "Goblin Underboss", "turn names only the visible monster")

--Events: hidden actors dropped, names from the snapshot, unknown kinds dropped.
check(#out.events == 2, "event by a hidden monster and unknown kind dropped")
check(out.events[1].who == "Vex Thornwood" and out.events[1].target == "Goblin Underboss" and out.events[1].amount == 6, "event names from the snapshot")
check(out.events[2].target == "???" and out.events[2].crit == true, "event target masked by private name")

--Monster bands.
check(StreamerKitRedact.MonsterBand({ cur = 21, max = 40 }, false) == "healthy", "above half is healthy")
check(StreamerKitRedact.MonsterBand({ cur = 20, max = 40 }, false) == "winded", "exactly half is winded")
check(StreamerKitRedact.MonsterBand({ cur = 1, max = 40 }, false) == "winded", "1 stamina is winded")
check(StreamerKitRedact.MonsterBand({ cur = 0, max = 40 }, false) == "dying", "0 not dead is dying")
check(StreamerKitRedact.MonsterBand({ cur = 30, max = 40 }, true) == "defeated", "dead is defeated whatever the stamina")
check(StreamerKitRedact.MonsterBand(nil, false) == "healthy", "unknown stamina reads healthy, not a guess")

--Garbage in: no crash, nothing leaks.
;(function()
    local empty = StreamerKitRedact.Redact(nil)
    check(type(empty.heroes) == "table" and #empty.heroes == 0 and empty.foes.total == 0, "nil raw gives an empty snapshot")
    check(empty.mode == "none", "unknown mode falls back to none")

    local odd = StreamerKitRedact.Redact({
        mode = SECRET,
        heroes = { "not a table", { id = "h1", name = "A", stamina = { cur = "lots", max = 0 / 0 } } },
        monsters = { { id = "m1", name = "Goblin", stamina = { cur = math.huge, max = 10 } }, 42 },
        turn = { kind = SECRET },
        events = { "x", { kind = "damage", whoId = "m1", amount = "big" } },
        encounter = { title = 99, objective = { label = SECRET, hidden = true } },
    })
    AssertNoLeaks(odd, "odd input")
    check(#odd.heroes == 1 and odd.heroes[1].stamina.cur == 0, "non-numeric stamina becomes 0")
    check(odd.turn == nil, "unknown turn kind dropped")
    check(odd.encounter.objective == nil, "hidden objective dropped")
    check(odd.encounter.title == nil, "non-string title dropped")
    check(#odd.events == 1 and odd.events[1].amount == nil and odd.events[1].who == "Goblin", "non-numeric amount dropped")
end)()

--A field added to the raw snapshot later is dropped until allowlisted.
;(function()
    local raw = Fixture()
    raw.secretPlan = SECRET
    raw.heroes[1].futureField = SECRET
    raw.monsters[1].futureField = SECRET
    raw.monsters[1].abilities[1].futureField = SECRET
    raw.events[1].futureField = SECRET
    AssertNoLeaks(StreamerKitRedact.Redact(raw), "new raw fields")
end)()

--The kinds and sides StreamOverlay.lua emits come through; other sides do not.
;(function()
    local raw = Fixture()
    raw.events = {
        { seq = 1, kind = "combat-start" },
        { seq = 2, kind = "damage", whoId = "h-vex", whoSide = "hero", targetId = "m-boss", targetSide = "monster", amount = 3 },
        { seq = 3, kind = "heal", targetId = "h-kal", targetSide = SECRET, amount = 5 },
        { seq = 4, kind = "combat-end" },
    }
    local result = StreamerKitRedact.Redact(raw)
    AssertNoLeaks(result, "overlay events")
    check(#result.events == 4, "overlay event kinds accepted")
    check(result.events[1].kind == "combat-start" and result.events[4].kind == "combat-end", "combat start and end kept")
    check(result.events[2].whoSide == "hero" and result.events[2].targetSide == "monster", "sides kept")
    check(result.events[3].targetSide == nil and result.events[3].target == "Kallis", "unknown side dropped")
end)()

--Caps keep the document small.
;(function()
    local raw = { events = {}, monsters = {} }
    for i = 1, 100 do
        raw.events[i] = { seq = i, kind = "heal" }
    end
    for i = 1, 200 do
        raw.monsters[i] = { id = "m" .. i, name = "Rat", stamina = { cur = 1, max = 1 } }
    end
    local capped = StreamerKitRedact.Redact(raw)
    check(#capped.events == 20 and capped.events[20].seq == 100 and capped.events[1].seq == 81, "keeps the newest 20 events")
    check(#capped.foes.list == 60, "monster list capped")
end)()

--Redact does not modify its input.
;(function()
    local raw = Fixture()
    StreamerKitRedact.Redact(raw)
    check(raw.malice == 7 and raw.monsters[2].hidden == true and raw.encounter.ev == 120, "input left untouched")
end)()

--Viewer link helpers: the code format must match the game server's
--(cloudflare-game-server/src/viewer-core.ts CODE_ALPHABET / CODE_LENGTH).
;(function()
    check(StreamerKitRedact.CODE_ALPHABET == "ABCDEFGHJKMNPQRSTUVWXYZ23456789", "alphabet matches the server")
    check(#StreamerKitRedact.CODE_ALPHABET == 31 and StreamerKitRedact.CODE_LENGTH == 6, "31 characters, 6 long")
    local guid = "3f2a9c1e-7b44-4d0e-9a51-c0ffee123456"
    local code = StreamerKitRedact.ViewerCodeFromHex(guid)
    check(code ~= nil and #code == 6, "a GUID makes a six-character code")
    check(StreamerKitRedact.IsViewerCode(code), "the code is well formed")
    check(StreamerKitRedact.ViewerCodeFromHex(guid) == code, "the same hex makes the same code")
    check(StreamerKitRedact.ViewerCodeFromHex("3f2a9c1e7b44") == nil, "too few hex digits gives nil")
    check(StreamerKitRedact.ViewerCodeFromHex(nil) == nil, "nil gives nil")
    --chunk 0x0000 -> "A", 0x001e (30) -> "9", 0x001f (31) wraps to "A".
    check(StreamerKitRedact.ViewerCodeFromHex("0000001e001f0001000200030000") == "A9ABCD", "each 16-bit chunk maps mod 31")
    local seen = {}
    for i = 1, 200 do
        local hex = string.format("%08x%08x%08x", i * 2654435761 % 4294967296, i * 40503 % 4294967296, i * 7919)
        local c = StreamerKitRedact.ViewerCodeFromHex(hex) or ""
        check(StreamerKitRedact.IsViewerCode(c), "generated code is valid: " .. c)
        for j = 1, #c do
            local ch = string.sub(c, j, j)
            check(ch ~= "I" and ch ~= "L" and ch ~= "O" and ch ~= "0" and ch ~= "1", "no look-alike characters")
        end
        seen[c] = true
    end
    check(StreamerKitRedact.IsViewerCode("KX7P2Q"), "a valid code")
    check(not StreamerKitRedact.IsViewerCode("kx7p2q"), "lower case is not a stored code")
    check(not StreamerKitRedact.IsViewerCode("KX7P2O"), "O is not in the alphabet")
    check(not StreamerKitRedact.IsViewerCode("KX7P2"), "too short")
    check(not StreamerKitRedact.IsViewerCode(nil), "nil is not a code")

    check(StreamerKitRedact.ClampDelay("30") == 30, "typed seconds")
    check(StreamerKitRedact.ClampDelay(12.9) == 12, "whole seconds")
    check(StreamerKitRedact.ClampDelay(-4) == 0, "never negative")
    check(StreamerKitRedact.ClampDelay(5000) == 900, "capped at 15 minutes")
    check(StreamerKitRedact.ClampDelay("soon") == 0, "unreadable is 0")
    check(StreamerKitRedact.ClampDelay(0 / 0) == 0, "NaN is 0")
end)()

--the outcome, for the recap card: only the known words pass.
;(function()
    local raw = Fixture()
    check(StreamerKitRedact.Redact(raw).outcome == nil, "no outcome while the fight goes on")
    raw.outcome = "victory"
    check(StreamerKitRedact.Redact(raw).outcome == "victory", "victory passes")
    raw.outcome = "defeat"
    check(StreamerKitRedact.Redact(raw).outcome == "defeat", "defeat passes")
    raw.outcome = "the cellar door is the real exit"
    check(StreamerKitRedact.Redact(raw).outcome == nil, "any other text is dropped")
    raw.outcome = { malice = 7 }
    local out = StreamerKitRedact.Redact(raw)
    check(out.outcome == nil, "a table is dropped")
    AssertNoLeaks(out, "outcome")
end)()

--the montage: its block passes only in montage mode, and only known fields.
;(function()
    local raw = Fixture()
    raw.mode = "montage"
    raw.montage = {
        title = "Through the Reedmarsh",
        round = 2, rounds = 3, phase = "rounds",
        successes = 3, failures = 1, unvanquished = 0,
        secretEntries = { SECRET },
        board = {
            { id = "o1", kind = "opportunity", name = "Bribe the Ferryman", state = "taken", notes = SECRET },
            { id = "t1", kind = "threat", name = "Leeches", state = "open", remaining = 2, temporary = true,
              consequence = { text = SECRET } },
            { id = "x", kind = "secret", name = SECRET },
            { id = "y", kind = "threat", name = "" },
            { id = "z", kind = "opportunity", name = "Odd state", state = SECRET },
        },
        turn = { hero = "Ilsa Varn", entry = "Leeches", option = "Burn them off", status = "rolling", tier = 9,
                 options = { SECRET } },
        log = {},
    }
    for i = 1, 20 do
        raw.montage.log[i] = { round = 1, hero = "Sev", entry = "Entry " .. i, option = "Climb", tier = 2, applied = { SECRET } }
    end
    raw.montage.log[21] = { round = 2, entry = "Leeches", consequence = true, effects = SECRET }

    local out = StreamerKitRedact.Redact(raw)
    check(out.mode == "montage", "montage mode passes")
    local m = out.montage
    check(m ~= nil and m.title == "Through the Reedmarsh", "montage title")
    check(m.round == 2 and m.rounds == 3 and m.phase == "rounds", "round, rounds and phase")
    check(m.successes == 3 and m.failures == 1 and m.unvanquished == 0, "totals")
    check(#m.board == 3, "board keeps known kinds with names: " .. #m.board)
    check(m.board[1].state == "taken" and m.board[2].remaining == 2 and m.board[2].temporary == true, "entry state, remaining, temporary")
    check(m.board[1].remaining == nil, "an opportunity has no remaining count")
    check(m.board[3].state == "open", "an unknown state reads open")
    check(m.turn.option == "Burn them off" and m.turn.tier == nil, "the chosen option passes; an impossible tier does not")
    check(#m.log == 12, "only the last 12 log lines: " .. #m.log)
    check(m.log[12].consequence == true and m.log[12].entry == "Leeches", "the newest line is last")
    AssertNoLeaks(out, "montage")

    raw.montage.turn.status = "choosing"
    check(StreamerKitRedact.Redact(raw).montage.turn.option == nil, "no option while the hero is still choosing")
    raw.montage.turn.status = "peeking"
    check(StreamerKitRedact.Redact(raw).montage.turn == nil, "an unknown turn status drops the turn")

    raw.mode = "combat"
    check(StreamerKitRedact.Redact(raw).montage == nil, "no montage block outside montage mode")
    raw.mode = "montage"
    raw.montage = SECRET
    out = StreamerKitRedact.Redact(raw)
    check(out.montage == nil, "a non-table montage is dropped")
    AssertNoLeaks(out, "montage garbage")

    --a finished montage rides along, folded up, once the montage is over.
    raw.mode = "combat"
    raw.montage = nil
    raw.pastMontage = {
        title = "Through the Reedmarsh", round = 3, rounds = 3, phase = "rounds",
        successes = 5, failures = 2, unvanquished = 1,
        board = { { id = "o1", kind = "opportunity", name = "Bribe the Ferryman", state = "taken", notes = SECRET } },
        turn = { hero = "Ilsa Varn", entry = SECRET, option = SECRET, status = "rolling" },
        log = { { round = 3, hero = "Sev", entry = "Leeches", option = "Climb", tier = 3, applied = { SECRET } } },
        secret = SECRET,
    }
    out = StreamerKitRedact.Redact(raw)
    local past = out.pastMontage
    check(past ~= nil and past.title == "Through the Reedmarsh" and past.phase == "done", "the finished montage passes, as done")
    check(past.successes == 5 and past.failures == 2 and #past.board == 1 and #past.log == 1, "its totals, board and log")
    check(past.turn == nil, "no turn on a finished montage")
    AssertNoLeaks(out, "past montage")
    raw.mode = "montage"
    raw.montage = { title = "Next", round = 1, rounds = 2, phase = "rounds", board = {}, log = {} }
    check(StreamerKitRedact.Redact(raw).pastMontage == nil, "not while a montage is running")
    raw.mode = "none"
    raw.pastMontage = SECRET
    check(StreamerKitRedact.Redact(raw).pastMontage == nil, "a non-table past montage is dropped")
end)()

--initiative groups: opaque ids in order, titles kept unless a member's name is private.
;(function()
    local raw = Fixture()
    local byId = {}
    for _, m in ipairs(raw.monsters) do byId[m.id] = m end
    byId["m-boss"].group = "boss-guid"; byId["m-boss"].groupTitle = "The Underboss and Friends"
    byId["m-ambusher"].group = "boss-guid"; byId["m-ambusher"].groupTitle = SECRET
    byId["m-runner1"].group = "MONSTER-Runners"; byId["m-runner1"].groupTitle = "Runners"
    byId["m-runner2"].group = "MONSTER-Runners"; byId["m-runner2"].groupTitle = "Runners"
    byId["m-masked"].group = "masked-guid"; byId["m-masked"].groupTitle = SECRET .. " Knight's Retinue"
    local out = StreamerKitRedact.Redact(raw)
    local foes = {}
    for _, f in ipairs(out.foes.list) do foes[f.id] = f end
    check(foes["m-boss"].group == "g1" and foes["m-boss"].groupTitle == "The Underboss and Friends", "first group, its title")
    check(foes["m-runner1"].group == "g2" and foes["m-runner2"].group == "g2", "a squad shares one group")
    check(foes["m-runner1"].groupTitle == "Runners", "the squad's title")
    check(foes["m-masked"].group == "g3" and foes["m-masked"].groupTitle == "???", "a private member hides the title")
    check(foes["m-ambusher"] == nil, "a hidden member stays out")
    AssertNoLeaks(out, "groups")
    for _, f in ipairs(out.foes.list) do
        check(f._groupKey == nil, "no internal key left on " .. tostring(f.id))
        check(f.group == nil or string.match(f.group, "^g%d+$") ~= nil, "group ids are opaque")
    end
end)()

--actions from History: who used what, on whom, what happened; hidden creatures out.
;(function()
    local raw = Fixture()
    raw.actions = {
        { t = 1000, round = 1, ability = "Judgment", actor = { id = "h-vex", name = "Vex Thornwood", hero = true },
          roll = { total = 17, tier = 3, sources = { SECRET } },
          targets = {
            { id = "m-boss", name = "Goblin Underboss", tier = 3, taken = 9, state = "winded", conds = { "Taunted" }, parts = { SECRET } },
            { id = "m-ambusher", name = SECRET, tier = 2, taken = 5 },
            { id = "m-masked", name = SECRET .. " Mystery Knight", secret = true, tier = 1, taken = 2, state = "exploded" },
          } },
        { t = 2000, round = 1, ability = SECRET .. " Ambush", actor = { id = "m-ambusher", name = SECRET },
          targets = { { id = "h-kal", name = "Kallis", hero = true, taken = 7 } } },
        { t = 3000, round = 2, ability = "Get Them!", villain = true, actor = { id = "m-unknown", name = SECRET, secret = true },
          roll = { total = 9, tier = 7 }, targets = {} },
        { t = 4000, ability = "" },
    }
    local out = StreamerKitRedact.Redact(raw)
    check(type(out.actions) == "table" and #out.actions == 2, "two actions survive: " .. tostring(out.actions and #out.actions))
    local a = out.actions[1]
    check(a.ability == "Judgment" and a.actor.name == "Vex Thornwood" and a.actor.side == "hero", "actor and ability")
    check(a.roll.total == 17 and a.roll.tier == 3 and a.roll.sources == nil, "roll total and tier only")
    check(#a.targets == 2, "the hidden target is dropped")
    check(a.targets[1].name == "Goblin Underboss" and a.targets[1].taken == 9 and a.targets[1].state == "winded", "target result")
    check(a.targets[1].conds[1] == "Taunted", "conditions it started")
    check(a.targets[2].name == "???" and a.targets[2].state == nil, "a secret name reads ???; an unknown state is dropped")
    local v = out.actions[2]
    check(v.villain == true and v.actor.name == "???" and v.roll.tier == nil, "villain action, secret actor, impossible tier dropped")
    AssertNoLeaks(out, "actions")

    raw.actions = SECRET
    check(StreamerKitRedact.Redact(raw).actions == nil, "non-table actions are dropped")
    raw.actions = nil
    check(StreamerKitRedact.Redact(raw).actions == nil, "no History, no actions")
end)()

-- Hero card art: only a stored image id of the two known forms, with its crop.
;(function()
    local P = StreamerKitRedact.PortraitImage
    check(P("eQGTS9rnrtJ_wOjVvwdjbw") == nil, "an R2 key without its host is not a bare md5 (has _)")
    check(P("q83vEjRWeJASNFZ4kBI0Vg==") == "q83vEjRWeJASNFZ4kBI0Vg==", "a bare base64 md5")
    check(P("https://codexback.com/eQGTS9rnrtJ_wOjVvwdjbw") ~= nil, "a URL-form id on the Codex host")
    check(P("https://evil.example.com/eQGTS9rnrtJ_wOjVvwdjbw") == nil, "another host")
    check(P("https://codexback.com/a/../../x") == nil, "a path with segments")
    check(P("http://codexback.com/eQGTS9rnrtJ_wOjVvwdjbw") == nil, "plain http")
    check(P("0f8c3b9e-1d2a-4c5b-9e7f-112233445566") == nil, "an asset id (GUID)")
    check(P("C:/Users/someone/portrait.png") == nil, "a local path")
    check(P(42) == nil and P(nil) == nil and P("short") == nil, "non-strings and short strings")

    local raw = Fixture()
    raw.heroes[1].portrait = { image = "q83vEjRWeJASNFZ4kBI0Vg==", rect = { x1 = -0.5, y1 = 0.1, x2 = 0.9, y2 = 7 }, extra = SECRET }
    raw.heroes[1].player = "Sam"
    if raw.heroes[2] ~= nil then
        raw.heroes[2].portrait = { image = "https://elsewhere.example/" .. SECRET }
    end
    local out = StreamerKitRedact.Redact(raw)
    local p = out.heroes[1].portrait
    check(p ~= nil and p.image == "q83vEjRWeJASNFZ4kBI0Vg==", "the portrait id is kept")
    check(p ~= nil and p.rect.x1 == 0 and p.rect.y1 == 0.1 and p.rect.x2 == 0.9 and p.rect.y2 == 1, "the crop is clamped to the image")
    check(p ~= nil and p.extra == nil, "nothing else rides along")
    check(out.heroes[1].player == "Sam", "the player name")
    if out.heroes[2] ~= nil then
        check(out.heroes[2].portrait == nil, "a portrait on another host is dropped")
    end
    raw.heroes[1].portrait = { image = "q83vEjRWeJASNFZ4kBI0Vg==", rect = { x1 = 0.8, y1 = 0, x2 = 0.2, y2 = 1 } }
    local r = StreamerKitRedact.Redact(raw).heroes[1].portrait.rect
    check(r.x1 == 0 and r.x2 == 1, "an inside-out crop falls back to the whole image")
    AssertNoLeaks(out, "portraits")
end)()

;(function()
    -- the back of a hero's card: known fields only, lists capped.
    local raw = Fixture()
    local skills, abilities = {}, {}
    for i = 1, 50 do skills[i] = "Skill " .. i end
    for i = 1, 40 do abilities[i] = { name = "Ability " .. i, kind = "heroic", cost = i, text = SECRET } end
    abilities[1] = { name = "Judgment", kind = SECRET, cost = 3 }
    abilities[2] = { name = "", kind = "main" }
    raw.heroes[1].back = {
        className = "Censor", subclass = "Paragon", ancestry = "Human", kit = string.rep("K", 200),
        winded = 16.4, death = -16, recoveryValue = 11, heroTokens = 2,
        speed = 5, disengage = 1, stability = 2,
        skills = skills, abilities = abilities,
        notes = SECRET, gear = { SECRET }, complication = SECRET, downtime = SECRET,
    }
    local out = StreamerKitRedact.Redact(raw)
    local b = out.heroes[1].back
    check(b ~= nil and b.subclass == "Paragon", "subclass")
    check(b.winded == 16 and b.death == -16 and b.recoveryValue == 11 and b.heroTokens == 2, "thresholds and counts")
    check(b.speed == 5 and b.disengage == 1 and b.stability == 2, "movement")
    check(#b.kit == 60, "a long name is cut short")
    check(#b.skills == 40, "skills capped: " .. #b.skills)
    check(#b.abilities == 29, "abilities capped, the unnamed one dropped: " .. #b.abilities)
    check(b.abilities[1].name == "Judgment" and b.abilities[1].kind == "other", "an unknown kind reads other")
    check(b.abilities[2].cost == 3 and b.abilities[2].text == nil, "cost kept, text dropped")
    check(b.notes == nil and b.gear == nil and b.complication == nil and b.downtime == nil, "nothing else rides along")
    AssertNoLeaks(out, "hero back")
    raw.heroes[1].back = SECRET
    check(StreamerKitRedact.Redact(raw).heroes[1].back == nil, "a non-table back is dropped")
end)()

;(function()
    -- each combatant's turn this round: three known values, nothing else.
    local raw = Fixture()
    raw.heroes[1].turnStatus = "now"
    raw.heroes[2].turnStatus = "acted"
    raw.monsters[1].turnStatus = "waiting"
    raw.monsters[2].turnStatus = SECRET
    local out = StreamerKitRedact.Redact(raw)
    check(out.heroes[1].turnStatus == "now" and out.heroes[2].turnStatus == "acted", "hero turn status")
    local byId = {}
    for _, foe in ipairs(out.foes.list) do byId[foe.id] = foe end
    local m1 = byId[raw.monsters[1].id]
    check(m1 == nil or m1.turnStatus == "waiting", "foe turn status")
    for _, foe in ipairs(out.foes.list) do
        check(foe.turnStatus == nil or foe.turnStatus == "now" or foe.turnStatus == "acted" or foe.turnStatus == "waiting", "only known turn values")
    end
    AssertNoLeaks(out, "turn status")
end)()

;(function()
    -- who applied a condition: named only when that creature is in the snapshot.
    local raw = Fixture()
    local heroId = raw.heroes[1].id
    raw.monsters[1].conditions = {
        { id = "judged", name = "Judged", byId = heroId },
        { id = "slowed", name = "Slowed", byId = "nobody-we-show" },
        { id = "dazed", name = "Dazed" },
    }
    local hiddenId = nil
    for _, m in ipairs(raw.monsters) do if m.hidden then hiddenId = m.id end end
    raw.heroes[2].conditions = { { id = "frightened", name = "Frightened", byId = hiddenId or "hidden-x" } }
    local out = StreamerKitRedact.Redact(raw)
    local foe = nil
    for _, f in ipairs(out.foes.list) do if f.id == raw.monsters[1].id then foe = f end end
    check(foe ~= nil, "the fixture's first monster is shown")
    local by = {}
    for _, c in ipairs(foe.conditions) do by[c.id] = c.by or false; check(c._byId == nil and c.byId == nil, "no raw source id leaves") end
    check(by.judged == out.heroes[1].name, "a visible hero is named: " .. tostring(by.judged))
    check(by.slowed == false, "a source not in the snapshot is left off")
    check(by.dazed == false, "no source, no name")
    check(out.heroes[2].conditions[1].by == nil, "a hidden creature is never named")
    AssertNoLeaks(out, "condition sources")
end)()

print(string.format("streamer_kit_redact_test: %d checks passed", passed))
