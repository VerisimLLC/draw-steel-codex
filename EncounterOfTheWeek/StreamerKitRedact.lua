--Encounter of the Week Streamer Kit: the redaction gate for the viewer feed.
--
--The viewer page (and anything else downstream of the feed) treats what it
--receives as PUBLIC. The publisher runs on the elected host, which sees
--Director-level information, so redaction happens HERE, inside the Codex,
--before anything leaves the session. The page never hides anything; it only
--draws what this function let through.
--
--How it is safe: Redact builds its output from scratch and copies only the
--fields named below (an allowlist). A field added to the raw snapshot later
--is dropped until someone adds it here on purpose. Nothing is copied by
--iterating the input's keys.
--
--This module is PURE Lua: no engine globals are touched, so it runs under a
--plain interpreter (tests/streamer_kit_redact_test.lua). The in-game
--collector (StreamOverlay.lua) gathers the raw snapshot from tokens and the
--initiative queue and passes it in.
--
--Rules (Streamer Kit implementation plan, Phase 1, with the 2026-11-27
--decisions):
--  * Encounter EV and Director notes are dropped, everywhere.
--  * Malice is dropped (decided 2026-11-27, as in STREAM_OVERLAY_PLAN.md).
--  * Monster stamina becomes a band only: healthy, winded, dying or
--    defeated. No numbers and no fraction are ever published for a monster.
--  * Villain actions not yet used stay face-down: their slot number only.
--  * Monster abilities appear only once used.
--  * Hero stamina, characteristics, Heroic Resource, recoveries and surges
--    are shown exactly.
--  * Hidden creatures (hidden by the Director, the Hidden condition, an
--    unrevealed trap or object, a bystander) are dropped entirely, and so
--    are events and turn names that mention them.
--  * A private name is shown as "???".
--  * Conditions marked hiddenFromEnemies are dropped from monsters.
--
--RAW SNAPSHOT (input; built by the collector, Director-level):
--  {
--    seq, updated (ms), mode ("combat"|"exploration"|"respite"|"none"),
--    encounter = { title, ev, directorNotes,
--                  objective = { label, progress, goal, hidden } },
--    round, malice, victories,
--    turn = { kind ("hero"|"monster"|"heroes-choosing"|"monsters-choosing"),
--             tokenIds = { id, ... } },
--    heroes = { {
--      id, name, namePrivate, level, className, ancestry, notes,
--      stamina = { cur, max, temp }, dead, dying,
--      characteristics = { might, agility, reason, intuition, presence },
--      resource = { name, value }, recoveries = { cur, max }, surges,
--      victories, conditions = { { id, name } }, active,
--      portrait = { image, rect = { x1, y1, x2, y2 } }, player,
--      back = { className, subclass, ancestry, kit, winded, death,
--               recoveryValue, heroTokens, speed, disengage, stability,
--               skills = { name }, abilities = { { name, kind, cost } } } } },
--    monsters = { {
--      id, name, namePrivate, monsterType, squad, minion, hidden,
--      stamina = { cur, max }, dead, ev, notes, role, organization, level,
--      conditions = { { id, name, hiddenFromEnemies } },
--      abilities = { { id, name, text, used, maliceCost, notes } },
--      villainActions = { { id, name, text, used, notes } } } },
--    events = { { seq, t, kind, whoId, who, targetId, target, amount, crit } },
--    monsters[i].group, groupTitle: the initiative group it acts with
--      (InitiativeQueue.GetInitiativeId) and that group's title.
--    heroes[i].conditions[j].byId, monsters[i].conditions[j].byId: the
--      creature that applied it; published as conditions[j].by (its public
--      name) only when that creature is itself in the snapshot.
--    heroes[i].turnStatus, monsters[i].turnStatus: "now"|"acted"|"waiting",
--      this round's turn as the initiative bar shows it (combat only).
--    actions = nil | { { t, round, ability, villain,
--      actor = { id, name, secret, hero },
--      roll = { total, tier },
--      targets = { { id, name, secret, hero, tier, taken, healed, state,
--                    conds = { name, ... } } } } }
--      This combat's actions from History, already in the players' cut
--      (History.PlayerEntry): hidden rolls and secret conditions are out.
--    montage = nil | { title, round, rounds, phase, successes, failures,
--      unvanquished,
--      board = { { id, kind ("opportunity"|"threat"), name,
--                  state ("open"|"taken"|"vanquished"), temporary, remaining } },
--      turn = { hero, entry, option, status, tier },
--      log = { { round, hero, entry, option, tier, passed, consequence } } },
--    pastMontage = the same block for the last montage to finish (phase
--      "done", no turn), sent while no montage is running.
--    boxScore = nil | { current (round, nil once the combat is over), rounds,
--      turns = { { { actor (hero id or raw group key or foe id, nil if
--                    hidden), side = "hero"|"foe", dealt, downs, now } } },
--      heroes = { { id, cells = { { taken, healed, down, gained = { name },
--                                   ended = { name },
--                                   turns = { { i, taken, healed, down,
--                                               gained, ended } } } } } },
--      foes = { { id, group (raw group key), cells = { same, healing
--                 ignored } } } }
--      Per-round tallies and per-turn detail (StreamOverlay.lua
--      UpdateBoxScore). Published with foe rows per opaque group id and
--      damage taken only; a turn's actor only if the viewer can see it.
--  }
--  The montage block holds only what every player's screen shows: the
--  collector leaves out locked, removed and expired entries, later rounds'
--  entries, and the option a hero is still choosing.
--
--VIEWER SNAPSHOT (output): see Redact below; FORMAT_VERSION bumps on change.

local mod = dmhub.GetModLoading()

StreamerKitRedact = {}

StreamerKitRedact.FORMAT_VERSION = 1

--Monster stamina bands. A monster is "winded" at half its Stamina or less,
--as in the rules; "dying" covers a monster at 0 or below that is not yet
--defeated (a solo with a "when reduced to 0" trait, a minion waiting on its
--squad); "defeated" when it is dead.
StreamerKitRedact.MONSTER_STATES = { "healthy", "winded", "dying", "defeated" }

local MAX_HEROES = 8
local MAX_MONSTERS = 60
local MAX_ABILITIES = 30
local MAX_CONDITIONS = 16
local MAX_EVENTS = 20
local MAX_STRING = 600

local HERO_STATES = { ok = true, winded = true, dying = true, dead = true }
local MODES = { combat = true, exploration = true, respite = true, montage = true, none = true }
local MAX_BOARD = 40
local MAX_MONTAGE_LOG = 12
local ENTRY_KINDS = { opportunity = true, threat = true }
local MAX_ACTIONS = 12
local MAX_TARGETS = 10
--the back of a hero's card (what any player sees turning it over).
local MAX_BACK_SKILLS = 40
local MAX_BACK_ABILITIES = 30
local BACK_ABILITY_KINDS = { signature = true, heroic = true, main = true, maneuver = true, triggered = true, other = true }
local MAX_SHORT = 60
local TARGET_STATES = { winded = true, dying = true, killed = true }
local ENTRY_STATES = { open = true, taken = true, vanquished = true }
local MONTAGE_PHASES = { rounds = true, consequences = true, done = true }
local TURN_STATUSES = {
    scene = true, choosing = true, rolling = true, perk = true, pardon = true,
    dice = true, chest = true, chestlanded = true, delvechoice = true,
}
local TURN_KINDS = { hero = true, monster = true, ["heroes-choosing"] = true, ["monsters-choosing"] = true }
--the kinds StreamOverlay.lua emits, plus ones planned for the ticker.
local EVENT_KINDS = {
    damage = true, heal = true, winded = true, dying = true, dead = true,
    defeated = true, recovery = true, ability = true, villainaction = true,
    ["combat-start"] = true, ["combat-end"] = true, victory = true, defeat = true,
}
local SIDES = { hero = true, monster = true }
local OUTCOMES = { victory = true, defeat = true }
local CHARACTERISTICS = { "might", "agility", "reason", "intuition", "presence" }

--- A whole number, or nil when the value is not a number.
--- @param n any
--- @return nil|integer
local function Whole(n)
    n = tonumber(n)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
        return nil
    end
    return math.floor(n + 0.5)
end

--- A short plain string, or nil.
--- @param s any
--- @return nil|string
local function Str(s)
    if type(s) ~= "string" or s == "" then
        return nil
    end
    if #s > MAX_STRING then
        s = string.sub(s, 1, MAX_STRING)
    end
    return s
end

--- A portrait image id the viewer server may fetch: a bare content id
--- (base64 md5, served from the legacy image bucket) or a URL-form id on the
--- Codex image host. Anything else -- an asset id, a local path, another
--- host -- is dropped, so the server is never pointed somewhere else.
--- @param s any
--- @return nil|string
function StreamerKitRedact.PortraitImage(s)
    if type(s) ~= "string" or #s < 16 or #s > 120 then
        return nil
    end
    if string.match(s, "^[%w%+/=]+$") ~= nil and #s <= 64 then
        return s
    end
    local key = string.match(s, "^https://codexback%.com/([%w_%-~]+)$")
    if key ~= nil and #key >= 16 then
        return s
    end
    return nil
end

--- A crop fraction, clamped to the image.
--- @param n any
--- @param default number
--- @return number
local function Fraction(n, default)
    n = tonumber(n)
    if n == nil or n ~= n then
        return default
    end
    n = math.max(0, math.min(1, n))
    return math.floor(n * 10000 + 0.5) / 10000
end

--- @param portrait any
--- @return nil|{image: string, rect: {x1: number, y1: number, x2: number, y2: number}}
local function Portrait(portrait)
    if type(portrait) ~= "table" then
        return nil
    end
    local image = StreamerKitRedact.PortraitImage(portrait.image)
    if image == nil then
        return nil
    end
    local r = type(portrait.rect) == "table" and portrait.rect or {}
    local rect = { x1 = Fraction(r.x1, 0), y1 = Fraction(r.y1, 0), x2 = Fraction(r.x2, 1), y2 = Fraction(r.y2, 1) }
    if rect.x2 <= rect.x1 or rect.y2 <= rect.y1 then
        rect = { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }
    end
    return { image = image, rect = rect }
end

--- An array part only, capped: ignores map keys a caller may have mixed in.
--- @param list any
--- @param max integer
--- @return table
local function List(list, max)
    local result = {}
    if type(list) ~= "table" then
        return result
    end
    for i = 1, math.min(#list, max) do
        result[#result + 1] = list[i]
    end
    return result
end

--- A short label (a name, a size), or nil.
--- @param s any
--- @return nil|string
local function Short(s)
    s = Str(s)
    if s ~= nil and #s > MAX_SHORT then
        s = string.sub(s, 1, MAX_SHORT)
    end
    return s
end

--- The back of a hero's card: known fields only, lists capped. Never notes,
--- gear, complications or anything else the raw table may carry.
--- @param back any
--- @return nil|table
local function HeroBack(back)
    if type(back) ~= "table" then
        return nil
    end
    local out = {
        subclass = Short(back.subclass),
        kit = Short(back.kit),
        winded = Whole(back.winded),
        death = Whole(back.death),
        recoveryValue = Whole(back.recoveryValue),
        heroTokens = Whole(back.heroTokens),
        speed = Whole(back.speed),
        disengage = Whole(back.disengage),
        stability = Whole(back.stability),
        skills = {},
        abilities = {},
    }
    for _, skill in ipairs(List(back.skills, MAX_BACK_SKILLS)) do
        local name = Short(skill)
        if name ~= nil then
            out.skills[#out.skills + 1] = name
        end
    end
    for _, a in ipairs(List(back.abilities, MAX_BACK_ABILITIES)) do
        if type(a) == "table" and Short(a.name) ~= nil then
            local cost = Whole(a.cost)
            out.abilities[#out.abilities + 1] = {
                name = Short(a.name),
                kind = BACK_ABILITY_KINDS[a.kind] and a.kind or "other",
                cost = (cost ~= nil and cost > 0 and cost <= 99) and cost or nil,
            }
        end
    end
    return out
end

--- A creature named in an action, or nil when viewers may not learn of it.
--- @param c any
--- @param hiddenIds table
--- @param visibleNames table
--- @return nil|table
local function ActionCreature(c, hiddenIds, visibleNames)
    if type(c) ~= "table" then
        return nil
    end
    if c.id ~= nil and hiddenIds[c.id] then
        return nil
    end
    local name = (c.id ~= nil and visibleNames[c.id]) or nil
    if name == nil then
        name = (c.secret == true) and "???" or (Str(c.name) or "???")
    end
    return { name = name, side = (c.hero == true) and "hero" or "monster" }
end

--- This combat's actions (see RAW SNAPSHOT), newest last, capped.
--- @param raw any
--- @param hiddenIds table
--- @param visibleNames table
--- @return nil|table
local function RedactActions(raw, hiddenIds, visibleNames)
    if type(raw) ~= "table" then
        return nil
    end
    local out = {}
    for i = math.max(1, #raw - MAX_ACTIONS + 1), #raw do
        local a = raw[i]
        if type(a) == "table" and Str(a.ability) ~= nil
            and not (type(a.actor) == "table" and a.actor.id ~= nil and hiddenIds[a.actor.id]) then
            local action = {
                t = Whole(a.t),
                round = Whole(a.round),
                ability = Str(a.ability),
                villain = a.villain == true or nil,
                actor = ActionCreature(a.actor, hiddenIds, visibleNames),
                targets = {},
            }
            if type(a.roll) == "table" then
                local tier = Whole(a.roll.tier)
                action.roll = {
                    total = Whole(a.roll.total),
                    tier = (tier ~= nil and tier >= 1 and tier <= 3) and tier or nil,
                }
            end
            for _, t in ipairs(List(a.targets, MAX_TARGETS)) do
                local target = ActionCreature(t, hiddenIds, visibleNames)
                if target ~= nil then
                    local tier = Whole(t.tier)
                    target.tier = (tier ~= nil and tier >= 1 and tier <= 3) and tier or nil
                    target.taken = Whole(t.taken)
                    target.healed = Whole(t.healed)
                    target.state = TARGET_STATES[t.state] and t.state or nil
                    target.conds = {}
                    for _, c in ipairs(List(t.conds, MAX_CONDITIONS)) do
                        if Str(c) ~= nil then
                            target.conds[#target.conds + 1] = Str(c)
                        end
                    end
                    action.targets[#action.targets + 1] = target
                end
            end
            out[#out + 1] = action
        end
    end
    return out
end

--- The montage block (see RAW SNAPSHOT). Nil unless it is a table.
--- @param raw any
--- @return nil|table
local function RedactMontage(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local out = {
        title = Str(raw.title),
        round = Whole(raw.round),
        rounds = Whole(raw.rounds),
        phase = MONTAGE_PHASES[raw.phase] and raw.phase or "rounds",
        successes = Whole(raw.successes) or 0,
        failures = Whole(raw.failures) or 0,
        unvanquished = Whole(raw.unvanquished) or 0,
        board = {},
        log = {},
    }
    for _, entry in ipairs(List(raw.board, MAX_BOARD)) do
        if type(entry) == "table" and ENTRY_KINDS[entry.kind] and Str(entry.name) ~= nil then
            out.board[#out.board + 1] = {
                id = Str(entry.id),
                kind = entry.kind,
                name = Str(entry.name),
                state = ENTRY_STATES[entry.state] and entry.state or "open",
                temporary = entry.temporary == true or nil,
                remaining = entry.kind == "threat" and Whole(entry.remaining) or nil,
            }
        end
    end
    local turn = raw.turn
    if type(turn) == "table" and TURN_STATUSES[turn.status] then
        local tier = Whole(turn.tier)
        out.turn = {
            hero = Str(turn.hero),
            entry = Str(turn.entry),
            --the choice only once it is made.
            option = (turn.status ~= "choosing" and turn.status ~= "scene") and Str(turn.option) or nil,
            status = turn.status,
            tier = (tier ~= nil and tier >= 1 and tier <= 4) and tier or nil,
        }
    end
    local log = type(raw.log) == "table" and raw.log or {}
    for i = math.max(1, #log - MAX_MONTAGE_LOG + 1), #log do
        local e = log[i]
        if type(e) == "table" then
            local tier = Whole(e.tier)
            out.log[#out.log + 1] = {
                round = Whole(e.round),
                hero = Str(e.hero),
                entry = Str(e.entry),
                option = Str(e.option),
                tier = (tier ~= nil and tier >= 1 and tier <= 4) and tier or nil,
                passed = e.passed == true or nil,
                consequence = e.consequence == true or nil,
            }
        end
    end
    return out
end

local function Initials(name)
    local words = {}
    for word in string.gmatch(name, "%w+") do
        words[#words + 1] = word
    end
    if #words >= 2 then
        return string.upper(string.sub(words[1], 1, 1) .. string.sub(words[2], 1, 1))
    end
    if #words == 1 then
        return string.upper(string.sub(words[1], 1, 2))
    end
    return "?"
end

--- The name viewers see.
local function PublicName(entry)
    if entry.namePrivate then
        return "???"
    end
    return Str(entry.name) or "???"
end

--- Conditions as { {id, name} }, sorted, without the ones enemies may not see
--- when dropSecret is set.
local function Conditions(list, dropSecret)
    local result = {}
    local seen = {}
    for _, c in ipairs(List(list, MAX_CONDITIONS * 2)) do
        if type(c) == "table" and not (dropSecret and c.hiddenFromEnemies) then
            local id = Str(c.id)
            if id ~= nil and not seen[id] and #result < MAX_CONDITIONS then
                seen[id] = true
                --byId rides along until Redact can name it (ResolveSources).
                result[#result + 1] = { id = id, name = Str(c.name) or id, _byId = Str(c.byId) }
            end
        end
    end
    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

--- @return string "ok"|"winded"|"dying"|"dead"
local function HeroState(hero, cur, max)
    if hero.dead then
        return "dead"
    end
    if hero.dying or (cur ~= nil and cur <= 0) then
        return "dying"
    end
    if cur ~= nil and max ~= nil and max > 0 and cur <= max / 2 then
        return "winded"
    end
    return "ok"
end

--- The band for a monster's stamina. Exposed for the tests and the collector.
--- @param stamina nil|{cur: number, max: number}
--- @param dead boolean
--- @return string "healthy"|"winded"|"dying"|"defeated"
function StreamerKitRedact.MonsterBand(stamina, dead)
    if dead then
        return "defeated"
    end
    local cur, max = nil, nil
    if type(stamina) == "table" then
        cur, max = tonumber(stamina.cur), tonumber(stamina.max)
    end
    if cur == nil or max == nil or max <= 0 then
        return "healthy"
    end
    if cur <= 0 then
        return "dying"
    end
    if cur <= max / 2 then
        return "winded"
    end
    return "healthy"
end

--a combatant's turn this round, as the initiative bar shows it.
local TURN_STATUSES = { now = true, acted = true, waiting = true }

--- @param s any
--- @return nil|string
local function TurnStatus(s)
    if type(s) == "string" and TURN_STATUSES[s] then
        return s
    end
    return nil
end

local function RedactHero(hero)
    local name = PublicName(hero)
    local stamina = type(hero.stamina) == "table" and hero.stamina or {}
    local cur, max = Whole(stamina.cur), Whole(stamina.max)
    local out = {
        id = Str(hero.id),
        name = name,
        initials = Initials(name),
        stamina = { cur = cur or 0, max = max or 0, temp = Whole(stamina.temp) or 0 },
        state = HeroState(hero, cur, max),
        conditions = Conditions(hero.conditions, false),
        active = hero.active == true,
        turnStatus = TurnStatus(hero.turnStatus),
        victories = Whole(hero.victories),
        surges = Whole(hero.surges),
        level = Whole(hero.level),
        className = Str(hero.className),
        ancestry = Str(hero.ancestry),
        portrait = Portrait(hero.portrait),
        back = HeroBack(hero.back),
        player = Str(hero.player),
    }
    if type(hero.characteristics) == "table" then
        out.characteristics = {}
        for _, key in ipairs(CHARACTERISTICS) do
            out.characteristics[key] = Whole(hero.characteristics[key])
        end
    end
    if type(hero.resource) == "table" then
        out.resource = { name = Str(hero.resource.name), value = Whole(hero.resource.value) }
    end
    if type(hero.recoveries) == "table" then
        out.recoveries = { cur = Whole(hero.recoveries.cur), max = Whole(hero.recoveries.max) }
    end
    return out
end

local function RedactMonster(monster)
    local out = {
        id = Str(monster.id),
        name = PublicName(monster),
        minion = monster.minion == true,
        state = StreamerKitRedact.MonsterBand(monster.stamina, monster.dead == true),
        conditions = Conditions(monster.conditions, true),
        turnStatus = TurnStatus(monster.turnStatus),
        abilities = {},
        villainActions = {},
    }
    if not monster.namePrivate then
        out.squad = Str(monster.squad)
        out.monsterType = Str(monster.monsterType)
    end
    for _, ability in ipairs(List(monster.abilities, MAX_ABILITIES)) do
        if type(ability) == "table" and ability.used == true then
            out.abilities[#out.abilities + 1] = { name = Str(ability.name) or "???", text = Str(ability.text) }
        end
    end
    for i, action in ipairs(List(monster.villainActions, MAX_ABILITIES)) do
        if type(action) == "table" then
            if action.used == true then
                out.villainActions[#out.villainActions + 1] = { slot = i, used = true, name = Str(action.name) or "???", text = Str(action.text) }
            else
                out.villainActions[#out.villainActions + 1] = { slot = i, used = false }
            end
        end
    end
    return out
end

local MAX_BOX_ROUNDS = 30
local MAX_BOX_TAGS = 8
local MAX_BOX_TURNS = 20

--- Condition names for a box score cell: short strings, capped.
local function BoxTags(list)
    local result = {}
    for _, name in ipairs(List(list, MAX_BOX_TAGS)) do
        local s = Short(name)
        if s ~= nil then
            result[#result + 1] = s
        end
    end
    return result
end

--- The box score block. Heroes keep taken and healed per round; foes keep
--- damage taken only (it is in the combat log already), per initiative
--- group, never stamina. A row is kept only for a hero in the snapshot, a
--- group the snapshot shows, or a foe the snapshot shows.
--- @param box any
--- @param heroIds table<string, boolean>
--- @param groupIds table<string, string> raw group key -> opaque id
--- @param foeIds table<string, boolean> visible foes
--- @return nil|table
local function RedactBoxScore(box, heroIds, groupIds, foeIds)
    if type(box) ~= "table" then
        return nil
    end
    local rounds = math.max(0, math.min(Whole(box.rounds) or 0, MAX_BOX_ROUNDS))
    local current = Whole(box.current)
    if current ~= nil and (current < 1 or current > rounds) then
        current = nil
    end
    local out = { rounds = rounds, current = current, turns = {}, heroes = {}, foes = {} }

    --each round's turns: the actor only as a hero in the snapshot, a shown
    --group's opaque id or a visible foe; anyone else acts unnamed.
    local rawTurns = type(box.turns) == "table" and box.turns or {}
    local turnCounts = {}
    for r = 1, rounds do
        local list = {}
        for _, turn in ipairs(List(rawTurns[r], MAX_BOX_TURNS)) do
            if type(turn) == "table" then
                local entry = {
                    dealt = math.max(0, Whole(turn.dealt) or 0),
                    downs = math.max(0, Whole(turn.downs) or 0),
                    now = turn.now == true and r == current or nil,
                }
                local a = turn.actor
                if type(a) == "string" then
                    if turn.side == "hero" and heroIds[a] then
                        entry.hero = a
                    elseif turn.side == "foe" and groupIds[a] ~= nil then
                        entry.group = groupIds[a]
                    elseif turn.side == "foe" and foeIds[a] then
                        entry.foe = a
                    end
                end
                list[#list + 1] = entry
            end
        end
        out.turns[r] = list
        turnCounts[r] = #list
    end

    local function Cell(c, withHealing)
        local cell = {
            taken = math.max(0, Whole(c.taken) or 0),
            down = math.max(0, Whole(c.down) or 0),
            gained = BoxTags(c.gained),
            ended = BoxTags(c.ended),
        }
        if withHealing then
            cell.healed = math.max(0, Whole(c.healed) or 0)
        end
        return cell
    end
    local function Cells(cells, withHealing)
        local result = {}
        cells = type(cells) == "table" and cells or {}
        for r = 1, rounds do
            local c = type(cells[r]) == "table" and cells[r] or {}
            local cell = Cell(c, withHealing)
            cell.turns = {}
            for _, tc in ipairs(List(c.turns, MAX_BOX_TURNS)) do
                local i = type(tc) == "table" and Whole(tc.i) or nil
                if i ~= nil and i >= 1 and i <= turnCounts[r] then
                    local t = Cell(tc, withHealing)
                    t.i = i
                    cell.turns[#cell.turns + 1] = t
                end
            end
            result[r] = cell
        end
        return result
    end
    for _, row in ipairs(List(box.heroes, MAX_HEROES * 2)) do
        if type(row) == "table" and type(row.id) == "string" and heroIds[row.id] and #out.heroes < MAX_HEROES then
            out.heroes[#out.heroes + 1] = { id = row.id, cells = Cells(row.cells, true) }
        end
    end
    local seenGroups = {}
    for _, row in ipairs(List(box.foes, MAX_MONSTERS * 2)) do
        if type(row) == "table" and #out.foes < MAX_MONSTERS then
            if type(row.group) == "string" then
                local gid = groupIds[row.group]
                if gid ~= nil and not seenGroups[gid] then
                    seenGroups[gid] = true
                    out.foes[#out.foes + 1] = { group = gid, cells = Cells(row.cells, false) }
                end
            elseif type(row.id) == "string" and foeIds[row.id] then
                out.foes[#out.foes + 1] = { id = row.id, cells = Cells(row.cells, false) }
            end
        end
    end
    return out
end

--- Redact a raw (Director-level) snapshot into the viewer snapshot.
--- @param raw nil|table anything that is not a table redacts to an empty snapshot
--- @return table
function StreamerKitRedact.Redact(raw)
    if type(raw) ~= "table" then
        raw = {}
    end

    --every monster id viewers must not learn about, so events and turn names
    --can be checked against it.
    local hiddenIds = {}
    local visibleNames = {}
    local monsters = {}
    local standing, total = 0, 0
    for _, monster in ipairs(List(raw.monsters, MAX_MONSTERS * 4)) do
        if type(monster) == "table" then
            if monster.hidden then
                if monster.id ~= nil then
                    hiddenIds[monster.id] = true
                end
            elseif #monsters < MAX_MONSTERS then
                local entry = RedactMonster(monster)
                monsters[#monsters + 1] = entry
                total = total + 1
                if entry.state ~= "defeated" then
                    standing = standing + 1
                end
                if monster.id ~= nil then
                    visibleNames[monster.id] = entry.squad or entry.monsterType or entry.name
                end
            end
        end
    end

    --initiative groups: an opaque id per group, in order of first appearance
    --(the raw id can carry a squad name), and the group's title unless a
    --member's name is private.
    local groupIds, groupCount, groupPrivate = {}, 0, {}
    local visibleIndex = 0
    for _, monster in ipairs(List(raw.monsters, MAX_MONSTERS * 4)) do
        if type(monster) == "table" and not monster.hidden and visibleIndex < MAX_MONSTERS then
            visibleIndex = visibleIndex + 1
            local key = monster.group
            if type(key) == "string" and key ~= "" then
                if groupIds[key] == nil then
                    groupCount = groupCount + 1
                    groupIds[key] = "g" .. groupCount
                end
                if monster.namePrivate then
                    groupPrivate[key] = true
                end
                local entry = monsters[visibleIndex]
                entry.group = groupIds[key]
                entry.groupTitle = Str(monster.groupTitle)
                entry._groupKey = key
            end
        end
    end
    for _, entry in ipairs(monsters) do
        if entry._groupKey ~= nil then
            if groupPrivate[entry._groupKey] then
                entry.groupTitle = "???"
            end
            entry._groupKey = nil
        end
    end

    local heroes = {}
    for _, hero in ipairs(List(raw.heroes, MAX_HEROES)) do
        if type(hero) == "table" then
            local entry = RedactHero(hero)
            heroes[#heroes + 1] = entry
            if hero.id ~= nil then
                visibleNames[hero.id] = entry.name
            end
        end
    end

    --who applied each condition: named only when it is a creature this
    --snapshot already shows (as the combat log names actors); unknown,
    --hidden or off-feed sources leave the condition unattributed.
    local function ResolveSources(list)
        for _, c in ipairs(list or {}) do
            local id = c._byId
            c._byId = nil
            if id ~= nil and not hiddenIds[id] and visibleNames[id] ~= nil and visibleNames[id] ~= "???" then
                c.by = visibleNames[id]
            end
        end
    end
    for _, entry in ipairs(heroes) do
        ResolveSources(entry.conditions)
    end
    for _, entry in ipairs(monsters) do
        ResolveSources(entry.conditions)
    end

    local out = {
        v = StreamerKitRedact.FORMAT_VERSION,
        seq = Whole(raw.seq) or 0,
        updated = Whole(raw.updated) or 0,
        mode = MODES[raw.mode] and raw.mode or "none",
        round = Whole(raw.round),
        victories = Whole(raw.victories),
        outcome = OUTCOMES[raw.outcome] and raw.outcome or nil,
        heroes = heroes,
        foes = { standing = standing, total = total, list = monsters },
        events = {},
    }
    out.actions = RedactActions(raw.actions, hiddenIds, visibleNames)

    local heroIds, foeIds = {}, {}
    for _, entry in ipairs(heroes) do
        if entry.id ~= nil then
            heroIds[entry.id] = true
        end
    end
    for _, entry in ipairs(monsters) do
        if entry.id ~= nil and not hiddenIds[entry.id] then
            foeIds[entry.id] = true
        end
    end
    out.boxScore = RedactBoxScore(raw.boxScore, heroIds, groupIds, foeIds)
    if out.mode == "montage" then
        out.montage = RedactMontage(raw.montage)
    else
        --the last montage to finish, folded up on the page: no turn in flight.
        out.pastMontage = RedactMontage(raw.pastMontage)
        if out.pastMontage ~= nil then
            out.pastMontage.phase = "done"
            out.pastMontage.turn = nil
        end
    end

    local encounter = type(raw.encounter) == "table" and raw.encounter or {}
    out.encounter = { title = Str(encounter.title) }
    local objective = encounter.objective
    if type(objective) == "table" and not objective.hidden then
        out.encounter.objective = {
            label = Str(objective.label),
            progress = Whole(objective.progress),
            goal = Whole(objective.goal),
        }
    end

    if type(raw.turn) == "table" and TURN_KINDS[raw.turn.kind] then
        local turn = { kind = raw.turn.kind }
        local names, seen = {}, {}
        for _, id in ipairs(List(raw.turn.tokenIds, MAX_MONSTERS)) do
            local name = visibleNames[id]
            if name ~= nil and not hiddenIds[id] and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
        table.sort(names)
        if #names > 0 then
            turn.name = table.concat(names, ", ")
        end
        out.turn = turn
    end

    --names in events come only from this snapshot's own visible entries, never
    --from the raw event, so a hidden or private name cannot ride along.
    local events = type(raw.events) == "table" and raw.events or {}
    for i = math.max(1, #events - MAX_EVENTS * 4 + 1), #events do
        local e = events[i]
        if type(e) == "table" and EVENT_KINDS[e.kind]
            and not (e.whoId ~= nil and hiddenIds[e.whoId])
            and not (e.targetId ~= nil and hiddenIds[e.targetId]) then
            out.events[#out.events + 1] = {
                seq = Whole(e.seq),
                t = Whole(e.t),
                kind = e.kind,
                who = (e.whoId ~= nil and visibleNames[e.whoId]) or nil,
                whoSide = SIDES[e.whoSide] and e.whoSide or nil,
                target = (e.targetId ~= nil and visibleNames[e.targetId]) or nil,
                targetSide = SIDES[e.targetSide] and e.targetSide or nil,
                amount = Whole(e.amount),
                crit = e.crit == true or nil,
            }
        end
    end
    --keep the newest MAX_EVENTS.
    while #out.events > MAX_EVENTS do
        table.remove(out.events, 1)
    end

    return out
end

-- ---------------------------------------------------------------------------
-- Viewer link helpers (pure; shared with the game server's rules in
-- cloudflare-game-server/src/viewer-core.ts, which must agree)
-- ---------------------------------------------------------------------------

--Viewer codes: six characters, upper-case letters and digits without the
--look-alikes (I, L, O, 0, 1), so a streamer can read one out on stream.
StreamerKitRedact.CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
StreamerKitRedact.CODE_LENGTH = 6
--Twitch's own delay setting tops out at 15 minutes.
StreamerKitRedact.MAX_DELAY_SECONDS = 900

--- A viewer code from random hex digits (a GUID; dashes and other characters
--- are skipped). Each character takes 16 bits, so the bias of the modulo is
--- negligible. Nil if there are too few hex digits.
--- @param hex nil|string
--- @return nil|string
function StreamerKitRedact.ViewerCodeFromHex(hex)
    if type(hex) ~= "string" then
        return nil
    end
    local digits = string.gsub(string.lower(hex), "[^0-9a-f]", "")
    local alphabet = StreamerKitRedact.CODE_ALPHABET
    local code = {}
    for i = 1, StreamerKitRedact.CODE_LENGTH do
        local chunk = string.sub(digits, (i - 1) * 4 + 1, i * 4)
        if #chunk < 4 then
            return nil
        end
        local n = tonumber(chunk, 16) % #alphabet
        code[i] = string.sub(alphabet, n + 1, n + 1)
    end
    return table.concat(code)
end

--- Is this a well-formed viewer code (already upper-case)?
--- @param code any
--- @return boolean
function StreamerKitRedact.IsViewerCode(code)
    if type(code) ~= "string" or #code ~= StreamerKitRedact.CODE_LENGTH then
        return false
    end
    for i = 1, #code do
        if string.find(StreamerKitRedact.CODE_ALPHABET, string.sub(code, i, i), 1, true) == nil then
            return false
        end
    end
    return true
end

--- A stream delay as typed by the streamer: whole seconds, 0..MAX_DELAY_SECONDS.
--- Anything unreadable is 0.
--- @param value any
--- @return integer
function StreamerKitRedact.ClampDelay(value)
    local n = tonumber(value)
    if n == nil or n ~= n then
        return 0
    end
    n = math.floor(n)
    if n < 0 then
        return 0
    end
    if n > StreamerKitRedact.MAX_DELAY_SECONDS then
        return StreamerKitRedact.MAX_DELAY_SECONDS
    end
    return n
end
