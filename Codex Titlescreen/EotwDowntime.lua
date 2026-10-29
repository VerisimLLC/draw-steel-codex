local mod = dmhub.GetModLoading()

--Encounter of the Week Downtime: what heroes do in Blackbottom between
--encounters. Design: EncounterOfTheWeek/EncounterOfTheWeek.md, "Downtime".
--
--  * Heroes come home from the Town Gate with their wounds (lost Stamina,
--    spent Recoveries; see EotwRoster.SetWounds).
--  * At the Blue Fish Inn a player takes a Respite: every hero at home rests,
--    turning Victories into XP and into Downtime Activities (one each), and
--    regaining all Stamina and Recoveries. A hero who does not want to rest
--    can Catch Their Breath instead: spend a Recovery to regain Stamina.
--  * Downtime Activities are spent on Projects. A project roll is 2d10 + a
--    characteristic (+2 for a listed skill) with no tiers: the total is the
--    Project Points it adds. A natural 19 or 20 is a breakthrough: one more
--    roll, free. Expand the Guild (60 points, +30 each time, five times)
--    opens a hero slot.
--
--The City (cloudflare-game-server src/city-core.ts) holds each hero's
--Downtime count and every project's progress, so spending a Downtime
--Activity and adding its points is one atomic step there. The hero's own
--record (XP, Victories, Stamina) changes here and is pushed like any edit.

EotwDowntime = {}

local T = UIText.T
local TP = UIText.Plural

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"

--A natural roll of at least this is a breakthrough (Draw Steel: 19-20).
EotwDowntime.BREAKTHROUGH_NATURAL = 19

--Bumped whenever a project or a respite changes; UIs poll it.
EotwDowntime.revision = 0

--Dev (/eotwdowntime breakthrough): the next project roll counts as a natural 20.
EotwDowntime.forceBreakthrough = false

local function Bump()
    EotwDowntime.revision = EotwDowntime.revision + 1
end

--- projects ---------------------------------------------------------------

--What the town shows of each project the City knows (CITY_PROJECTS in
--city-core.ts holds the goals and what a completion does).
EotwDowntime.PROJECTS = {
    ["expand-guild"] = {
        id = "expand-guild",
        scope = "player",
        title = T("downtime.projects.expand_guild.title"),
        icon = "phosphor/shield-star-fill.png",
        location = "guild",
        characteristics = { "rea", "prs" },
        skills = { "Brag", "Empathize", "Flirt", "Lead", "Perform", "Persuade" },
        --what completing it gives, shown under its cost.
        benefit = T("downtime.projects.expand_guild.benefit"),
        --the line under the title, from the project's state (list-projects).
        blurb = function(state)
            if state ~= nil and state.maxed then
                return T("downtime.projects.expand_guild.blurb_maxed")
            end
            return T("downtime.projects.expand_guild.blurb")
        end,
    },
    --Opened by a lead heard while carousing at the Blue Fish Inn (EotwLeads);
    --completing it puts the Arcane Market on this player's town map.
    ["find-arcane-market"] = {
        id = "find-arcane-market",
        scope = "player",
        title = T("downtime.projects.find_arcane_market.title"),
        icon = "phosphor/storefront-fill.png",
        location = "inn",
        lead = "arcane-market",
        characteristics = { "inu", "prs" },
        skills = { "Alchemy", "Magic", "Read Person" },
        benefit = T("downtime.projects.find_arcane_market.benefit"),
        --the banner when it completes.
        completeBanner = { text = T("downtime.projects.find_arcane_market.complete_banner"), subtitle = T("downtime.projects.find_arcane_market.complete_subtitle") },
        blurb = function(state)
            if state ~= nil and state.maxed then
                return T("downtime.projects.find_arcane_market.blurb_maxed")
            end
            return T("downtime.projects.find_arcane_market.blurb")
        end,
        --What the hero says after a roll (EotwDowntime.PickRollLine): by how far
        --along the project now is (early under a third, late from two thirds)
        --and the roll's tier as a mood (3 hopeful, 2 neutral, 1 fed up), plus
        --the completing roll's lines. Several per pool: the jukebox avoids
        --repeating a recent line.
        rollLines = {
            early = {
                hopeful = {
                    T("downtime.lines.arcane_market.early_hopeful_1"),
                    T("downtime.lines.arcane_market.early_hopeful_2"),
                    T("downtime.lines.arcane_market.early_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.arcane_market.early_neutral_1"),
                    T("downtime.lines.arcane_market.early_neutral_2"),
                    T("downtime.lines.arcane_market.early_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.arcane_market.early_frustrated_1"),
                    T("downtime.lines.arcane_market.early_frustrated_2"),
                    T("downtime.lines.arcane_market.early_frustrated_3"),
                },
            },
            mid = {
                hopeful = {
                    T("downtime.lines.arcane_market.mid_hopeful_1"),
                    T("downtime.lines.arcane_market.mid_hopeful_2"),
                    T("downtime.lines.arcane_market.mid_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.arcane_market.mid_neutral_1"),
                    T("downtime.lines.arcane_market.mid_neutral_2"),
                    T("downtime.lines.arcane_market.mid_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.arcane_market.mid_frustrated_1"),
                    T("downtime.lines.arcane_market.mid_frustrated_2"),
                    T("downtime.lines.arcane_market.mid_frustrated_3"),
                },
            },
            late = {
                hopeful = {
                    T("downtime.lines.arcane_market.late_hopeful_1"),
                    T("downtime.lines.arcane_market.late_hopeful_2"),
                    T("downtime.lines.arcane_market.late_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.arcane_market.late_neutral_1"),
                    T("downtime.lines.arcane_market.late_neutral_2"),
                    T("downtime.lines.arcane_market.late_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.arcane_market.late_frustrated_1"),
                    T("downtime.lines.arcane_market.late_frustrated_2"),
                    T("downtime.lines.arcane_market.late_frustrated_3"),
                },
            },
            done = {
                T("downtime.lines.arcane_market.done_1"),
                T("downtime.lines.arcane_market.done_2"),
                T("downtime.lines.arcane_market.done_3"),
            },
        },
    },
    --A COMMUNITY project: every hero in town adds to one total (1000 points,
    --in city-core.ts). Under way from the start; worked on at the
    --Construction, which becomes the Hall of Heroes when it completes.
    ["build-hall-of-heroes"] = {
        id = "build-hall-of-heroes",
        scope = "community",
        title = T("downtime.projects.build_hall.title"),
        icon = "phosphor/hammer-fill.png",
        location = "hall",
        locationName = T("downtime.projects.build_hall.place"),
        characteristics = { "mgt", "rea" },
        skills = { "Architecture", "Blacksmithing", "Carpentry", "Mechanics" },
        benefit = T("downtime.projects.build_hall.benefit"),
        completeBanner = { text = T("downtime.projects.build_hall.complete_banner"), subtitle = T("downtime.projects.build_hall.complete_subtitle") },
        blurb = function(state)
            if state ~= nil and state.maxed then
                return T("downtime.projects.build_hall.blurb_maxed")
            end
            return T("downtime.projects.build_hall.blurb")
        end,
        rollLines = {
            early = {
                hopeful = {
                    T("downtime.lines.hall.early_hopeful_1"),
                    T("downtime.lines.hall.early_hopeful_2"),
                    T("downtime.lines.hall.early_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.hall.early_neutral_1"),
                    T("downtime.lines.hall.early_neutral_2"),
                    T("downtime.lines.hall.early_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.hall.early_frustrated_1"),
                    T("downtime.lines.hall.early_frustrated_2"),
                    T("downtime.lines.hall.early_frustrated_3"),
                },
            },
            mid = {
                hopeful = {
                    T("downtime.lines.hall.mid_hopeful_1"),
                    T("downtime.lines.hall.mid_hopeful_2"),
                    T("downtime.lines.hall.mid_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.hall.mid_neutral_1"),
                    T("downtime.lines.hall.mid_neutral_2"),
                    T("downtime.lines.hall.mid_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.hall.mid_frustrated_1"),
                    T("downtime.lines.hall.mid_frustrated_2"),
                    T("downtime.lines.hall.mid_frustrated_3"),
                },
            },
            late = {
                hopeful = {
                    T("downtime.lines.hall.late_hopeful_1"),
                    T("downtime.lines.hall.late_hopeful_2"),
                    T("downtime.lines.hall.late_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.hall.late_neutral_1"),
                    T("downtime.lines.hall.late_neutral_2"),
                    T("downtime.lines.hall.late_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.hall.late_frustrated_1"),
                    T("downtime.lines.hall.late_frustrated_2"),
                    T("downtime.lines.hall.late_frustrated_3"),
                },
            },
            done = {
                T("downtime.lines.hall.done_1"),
                T("downtime.lines.hall.done_2"),
                T("downtime.lines.hall.done_3"),
            },
        },
    },
    --The second COMMUNITY project, built at its own site (4000 points, in
    --city-core.ts); completing it opens the Town Hall's votes and petitions.
    ["build-town-hall"] = {
        id = "build-town-hall",
        scope = "community",
        title = T("downtime.projects.build_town_hall.title"),
        icon = "phosphor/hammer-fill.png",
        location = "townhall",
        locationName = T("downtime.projects.build_town_hall.place"),
        characteristics = { "mgt", "rea", "prs" },
        skills = { "Architecture", "Lead", "Persuade", "Society" },
        benefit = T("downtime.projects.build_town_hall.benefit"),
        completeBanner = { text = T("downtime.projects.build_town_hall.complete_banner"), subtitle = T("downtime.projects.build_town_hall.complete_subtitle") },
        blurb = function(state)
            if state ~= nil and state.maxed then
                return T("downtime.projects.build_town_hall.blurb_maxed")
            end
            return T("downtime.projects.build_town_hall.blurb")
        end,
        rollLines = {
            early = {
                hopeful = {
                    T("downtime.lines.town_hall.early_hopeful_1"),
                    T("downtime.lines.town_hall.early_hopeful_2"),
                    T("downtime.lines.town_hall.early_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.town_hall.early_neutral_1"),
                    T("downtime.lines.town_hall.early_neutral_2"),
                    T("downtime.lines.town_hall.early_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.town_hall.early_frustrated_1"),
                    T("downtime.lines.town_hall.early_frustrated_2"),
                    T("downtime.lines.town_hall.early_frustrated_3"),
                },
            },
            mid = {
                hopeful = {
                    T("downtime.lines.town_hall.mid_hopeful_1"),
                    T("downtime.lines.town_hall.mid_hopeful_2"),
                    T("downtime.lines.town_hall.mid_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.town_hall.mid_neutral_1"),
                    T("downtime.lines.town_hall.mid_neutral_2"),
                    T("downtime.lines.town_hall.mid_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.town_hall.mid_frustrated_1"),
                    T("downtime.lines.town_hall.mid_frustrated_2"),
                    T("downtime.lines.town_hall.mid_frustrated_3"),
                },
            },
            late = {
                hopeful = {
                    T("downtime.lines.town_hall.late_hopeful_1"),
                    T("downtime.lines.town_hall.late_hopeful_2"),
                    T("downtime.lines.town_hall.late_hopeful_3"),
                },
                neutral = {
                    T("downtime.lines.town_hall.late_neutral_1"),
                    T("downtime.lines.town_hall.late_neutral_2"),
                    T("downtime.lines.town_hall.late_neutral_3"),
                },
                frustrated = {
                    T("downtime.lines.town_hall.late_frustrated_1"),
                    T("downtime.lines.town_hall.late_frustrated_2"),
                    T("downtime.lines.town_hall.late_frustrated_3"),
                },
            },
            done = {
                T("downtime.lines.town_hall.done_1"),
                T("downtime.lines.town_hall.done_2"),
                T("downtime.lines.town_hall.done_3"),
            },
        },
    },
}

--A Draw Steel test's tier from a 2d10 roll: 11 or less, 12-16, 17+, and a
--natural 19-20 is always tier 3. Project rolls have no tiers; a project's
--rollLines use this to pick what the hero says.
function EotwDowntime.TestTier(natural, total)
    if natural >= EotwDowntime.BREAKTHROUGH_NATURAL or total >= 17 then
        return 3
    end
    return cond(total >= 12, 2, 1)
end

--projectid -> the project's state as the City last reported it:
--{projectid, completions, maxCompletions, points, goal, maxed, recent, open}.
local m_projects = {}
--scope -> a list request is in flight.
local m_listing = {}

--A project's last known state, or nil before the first list.
function EotwDowntime.GetProject(projectid)
    return m_projects[projectid]
end

--Ask the City for this account's projects and the town's community ones,
--and cache them.
function EotwDowntime.RefreshProjects()
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        return
    end
    for _, scope in ipairs({ "player", "community" }) do
        if not m_listing[scope] then
            m_listing[scope] = true
            conn:Request{
                action = "list-projects",
                args = { scope = scope },
                success = function(result)
                    m_listing[scope] = false
                    for _, project in ipairs(result.projects or {}) do
                        m_projects[project.projectid] = project
                    end
                    Bump()
                end,
                error = function(message)
                    m_listing[scope] = false
                    printf("EotW town: could not list %s projects: %s", scope, tostring(message))
                end,
            }
        end
    end
end

--The ids of the characteristics a project allows, with display names, in
--the game system's own order: { {id, name}, ... }.
local function ProjectCharacteristics(project)
    local result = {}
    for _, attrid in ipairs(project.characteristics) do
        local info = creature.attributesInfo[attrid]
        result[#result+1] = { id = attrid, name = info ~= nil and info.description or attrid }
    end
    return result
end

--The hero's modifier for a characteristic (0 if it cannot be read).
local function CharacteristicValue(tok, attrid)
    local value = 0
    pcall(function() value = tok.properties:GetAttribute(attrid):Modifier() end)
    return value
end

--The project's listed skills this hero is trained in, by name.
local function TrainedProjectSkills(tok, project)
    local trained = {}
    pcall(function()
        for _, skill in ipairs(Skill.SkillsInfo) do
            for _, name in ipairs(project.skills) do
                if skill.name == name and tok.properties:ProficientInSkill(skill) then
                    trained[#trained+1] = name
                end
            end
        end
    end)
    return trained
end

--- what heroes say about a project roll ---------------------------------------

--The lines each project said last, newest last: projectid -> { text, ... }.
--Kept for the session (lines heard in a row are what get tiresome).
local m_recentLines = {}
local RECENT_LINES_KEPT = 12

--The jukebox: the line a hero says after a roll on this project, or nil if
--the project has no rollLines. tier (1-3) sets the mood, progress (0-1)
--how far along it is. A line said recently is never picked while its pool
--has another; when every line of the pool was said recently, the one said
--longest ago plays.
function EotwDowntime.PickRollLine(projectid, tier, progress, completed)
    local project = EotwDowntime.PROJECTS[projectid]
    local lines = project ~= nil and project.rollLines or nil
    if lines == nil then
        return nil
    end
    local pool
    if completed then
        pool = lines.done
    else
        local band = lines.early
        if progress >= 0.67 then
            band = lines.late
        elseif progress >= 0.34 then
            band = lines.mid
        end
        local mood = "neutral"
        if tier >= 3 then
            mood = "hopeful"
        elseif tier <= 1 then
            mood = "frustrated"
        end
        pool = band[mood]
    end
    if pool == nil or #pool == 0 then
        return nil
    end

    local recent = m_recentLines[projectid] or {}
    --when each line was last said (higher is more recent); 0 = not lately.
    local lastSaid = {}
    for i, text in ipairs(recent) do
        lastSaid[text] = i
    end
    local fresh = {}
    for _, text in ipairs(pool) do
        if lastSaid[text] == nil then
            fresh[#fresh+1] = text
        end
    end
    local choice
    if #fresh > 0 then
        choice = fresh[math.random(#fresh)]
    else
        choice = pool[1]
        for _, text in ipairs(pool) do
            if lastSaid[text] < lastSaid[choice] then
                choice = text
            end
        end
    end

    --remember it, once, as the newest.
    local kept = {}
    for _, text in ipairs(recent) do
        if text ~= choice then
            kept[#kept+1] = text
        end
    end
    kept[#kept+1] = choice
    while #kept > RECENT_LINES_KEPT do
        table.remove(kept, 1)
    end
    m_recentLines[projectid] = kept
    return choice
end

--- respite and catching breath ----------------------------------------------

--A respite in progress, kept until every hero is pushed and the City has
--credited the Downtime, so a crash or a dropped connection resumes it:
--{ [userid] = { respiteid, grants = {heroid = amount}, pushed = {heroid = true}, stage } }.
setting{
    id = "eotw:pendingRespite",
    default = "",
    storage = "preference",
}

--A project roll whose dice have landed but the City has not yet recorded:
--{ [userid] = { rollid, projectid, heroid, natural, total, characteristic, skill, breakthroughOf } }.
setting{
    id = "eotw:pendingProjectRoll",
    default = "",
    storage = "preference",
}

local function LoadMine(settingid)
    local all = {}
    local text = dmhub.GetSettingValue(settingid)
    if type(text) == "string" and text ~= "" then
        --FromJson answers {success, result}, not the decoded value.
        local parsed = dmhub.FromJson(text)
        if type(parsed) == "table" and parsed.success and type(parsed.result) == "table" then
            all = parsed.result
        end
    end
    return all, all[dmhub.loginUserid]
end

local function SaveMine(settingid, value)
    local all = LoadMine(settingid)
    all[dmhub.loginUserid] = value
    dmhub.SetSettingValue(settingid, dmhub.ToJson(all))
end

--A hero's Victories (0 if unreadable).
local function Victories(tok)
    local v = 0
    pcall(function() v = tok.properties:GetVictories() or 0 end)
    return math.max(0, math.floor(v))
end

--Stamina and Recoveries for display: cur, max, recoveries left, recovery max.
local function Vitals(tok)
    local cur, max, left, rmax = 0, 0, 0, 0
    pcall(function()
        local props = tok.properties
        cur = props:CurrentHitpoints()
        max = props:MaxHitpoints()
        local id = CharacterResource.recoveryResourceId
        rmax = props:GetResources()[id] or 0
        left = math.max(0, rmax - (props:GetResourceUsage(id, "long") or 0))
    end)
    return cur, max, left, rmax
end

--Every living roster hero with what a respite would do for them:
--{ {hero, tok, away, victories, canRest, wounded, reason}, ... } in roster
--order. wounded: has lost Stamina or spent Recoveries (a respite needs one).
function EotwDowntime.RestCandidates()
    local result = {}
    local away = EotwRoster.AwayHeroes()
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local tok = dmhub.GetCharacterById(hero.heroid)
        local entry = { hero = hero, tok = tok, away = away[hero.heroid], victories = 0, canRest = false, wounded = false }
        if entry.away ~= nil then
            entry.reason = T("inn.row.away", { party = entry.away })
        elseif tok == nil or not EotwRoster.IsInStep(hero.heroid) then
            entry.reason = T("inn.row.loading")
        else
            entry.victories = Victories(tok)
            entry.canRest = true
            local cur, max, left, rmax = Vitals(tok)
            entry.wounded = cur < max or left < rmax
        end
        result[#result+1] = entry
    end
    return result
end

local m_respiteBusy = false

--Why a respite cannot be taken when every hero at home is unhurt.
EotwDowntime.NO_WOUNDS_MESSAGE = T("inn.footer.no_wounds")

--Is a respite being written right now?
function EotwDowntime.RespiteBusy()
    return m_respiteBusy
end

--Secret Twin's drawback: after each respite roll a d10, and on a 1 or 2 the
--hero's past catches up. EotW plays it out: the hero is marked with
--ASSASSIN_FIELD, and the next montage they play gets an assassin threat
--(EncounterMontage). No roll while an assassin is still on their trail.
local SECRET_TWIN_ID = "d8af2c17-c677-44bb-b237-d695fcff49c1"
EotwDowntime.ASSASSIN_FIELD = "eotwAssassinPending"

--Heroes whose past caught up in the respite being taken, waiting for their
--banner (ShowPastCatchesUp): { heroid, ... }.
local m_pastCatchesUp = {}

--Roll Secret Twin's d10 for a hero who is resting. Runs inside RestHero's
--ModifyProperties.
local function RollSecretTwin(tok)
    local props = tok.properties
    if not props:try_get("complications", {})[SECRET_TWIN_ID] or props:try_get(EotwDowntime.ASSASSIN_FIELD, false) then
        return
    end
    local roll = math.random(1, 10)
    printf("EotW town: %s rolls %d for Secret Twin", tostring(tok.name), roll)
    if roll <= 2 then
        props[EotwDowntime.ASSASSIN_FIELD] = true
        m_pastCatchesUp[#m_pastCatchesUp+1] = tok.charid
    end
end

--Rest one hero's working copy for this respite, unless it already has.
local function RestHero(tok, respiteid, victories)
    local done = false
    pcall(function()
        local stamps = rawget(tok.properties, "eotwRespites")
        done = type(stamps) == "table" and stamps[respiteid] ~= nil
    end)
    if done then
        return
    end
    tok:ModifyProperties{
        description = "Respite at the Blue Fish Inn",
        undoable = false,
        execute = function()
            local props = tok.properties
            --heals, turns Victories into XP and refreshes Recoveries.
            props:Rest("long")
            RollSecretTwin(tok)
            local stamps = {}
            local old = rawget(props, "eotwRespites")
            if type(old) == "table" then
                for k, v in pairs(old) do
                    stamps[k] = v
                end
            end
            stamps[respiteid] = victories
            props.eotwRespites = stamps
        end,
    }
end

--Drop one hero from a pending respite (they fell or were dismissed since it
--began) and save it. Returns true if the hero was in it.
local function DropRespiteHero(pending, heroid)
    if pending.grants == nil or pending.grants[heroid] == nil then
        return false
    end
    pending.grants[heroid] = nil
    pending.pushed[heroid] = nil
    SaveMine("eotw:pendingRespite", pending)
    printf("EotW town: hero %s is no longer on the roster; left out of the respite", tostring(heroid))
    return true
end

--Carry a pending respite forward: rest and push each hero not yet pushed,
--then credit the Downtime with the City. Safe to call again at any stage.
local function ContinueRespite(onDone)
    local _, pending = LoadMine("eotw:pendingRespite")
    if type(pending) ~= "table" or type(pending.respiteid) ~= "string" then
        m_respiteBusy = false
        if onDone ~= nil then
            onDone(true)
        end
        return
    end
    m_respiteBusy = true
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        m_respiteBusy = false
        if onDone ~= nil then
            onDone(false, T("inn.respite.not_connected"))
        end
        return
    end
    pending.pushed = pending.pushed or {}

    --a hero who fell or was dismissed since the respite began has nothing to
    --rest or credit, pushed or not; the City refuses the whole Downtime grant
    --while one is in it (F32BZRF2). The roster lists living heroes only, but
    --until it has been listed FindHero misses everyone, so wait for it.
    if EotwRoster.GetHeroes() ~= nil then
        for heroid, _ in pairs(pending.grants or {}) do
            if EotwRoster.FindHero(heroid) == nil then
                DropRespiteHero(pending, heroid)
            end
        end
    end

    --first every hero's record, one push at a time.
    for heroid, amount in pairs(pending.grants or {}) do
        if not pending.pushed[heroid] then
            --not in step also covers a roster not listed yet.
            if not EotwRoster.IsInStep(heroid) then
                --an import is in flight; try again shortly.
                dmhub.Schedule(1, function()
                    if not mod.unloaded then
                        ContinueRespite(onDone)
                    end
                end)
                return
            else
                local tok = dmhub.GetCharacterById(heroid)
                RestHero(tok, pending.respiteid, amount)
                --let the property write land before the export, as JoinRoster does.
                dmhub.Schedule(0.3, function()
                    if mod.unloaded then
                        return
                    end
                    EotwRoster.PushHero(heroid, function(ok, message)
                        if not ok then
                            --a stale copy reloads from the city; the next
                            --pass rests it again (it carries no stamp).
                            m_respiteBusy = false
                            if onDone ~= nil then
                                onDone(false, message)
                            end
                            return
                        end
                        pending.pushed[heroid] = true
                        SaveMine("eotw:pendingRespite", pending)
                        ContinueRespite(onDone)
                    end)
                end)
                return
            end
        end
    end

    --then the Downtime, credited once per hero for this respite.
    local grants = {}
    for heroid, amount in pairs(pending.grants or {}) do
        grants[#grants+1] = { heroid = heroid, amount = amount }
    end
    if #grants == 0 then
        SaveMine("eotw:pendingRespite", nil)
        m_respiteBusy = false
        Bump()
        if onDone ~= nil then
            onDone(true)
        end
        return
    end
    conn:Request{
        action = "grant-downtime",
        --respite: this is a real respite, which earns one carouse at the inn.
        args = { grantid = pending.respiteid, grants = grants, respite = true },
        success = function(result)
            SaveMine("eotw:pendingRespite", nil)
            m_respiteBusy = false
            local heroCount = 0
            for _, _ in pairs(result.downtime or {}) do
                heroCount = heroCount + 1
            end
            EotwAnalytics.Track("eotw_downtime", { activity = "respite", heroes = heroCount })
            for heroid, downtime in pairs(result.downtime or {}) do
                EotwRoster.SetListedDowntime(heroid, downtime)
            end
            EotwRoster.SetListedLeads(nil, result.carouse)
            --the respite closed every series part the account had open.
            EotwRoster.SetOpenParts(result.openParts)
            Bump()
            EotwRoster.Refresh()
            if onDone ~= nil then
                onDone(true, nil, result.closedParts)
            end
        end,
        error = function(message)
            m_respiteBusy = false
            printf("EotW town: the Downtime from the respite was not credited yet: %s", tostring(message))
            --a hero our roster still thought was alive: leave them out and
            --send the rest. Each retry removes a hero, so this cannot loop.
            local text = tostring(message)
            local gone = text:match("^hero ([%w_%-]+) has fallen") or text:match("^hero ([%w_%-]+) does not exist")
            if gone ~= nil and not mod.unloaded and DropRespiteHero(pending, gone) then
                ContinueRespite(onDone)
                return
            end
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Take a respite: every hero at home (not away in a party) rests at once.
--onDone(ok, message, closedParts) when it has all reached the City;
--closedParts lists the series parts it closed ({board, encounter}).
function EotwDowntime.TakeRespite(onDone)
    if m_respiteBusy then
        return
    end
    local _, pending = LoadMine("eotw:pendingRespite")
    if type(pending) == "table" then
        --finish the one already under way first.
        ContinueRespite(onDone)
        return
    end
    local grants = {}
    local count = 0
    local wounded = 0
    for _, entry in ipairs(EotwDowntime.RestCandidates()) do
        if entry.canRest then
            grants[entry.hero.heroid] = entry.victories
            count = count + 1
            if entry.wounded then
                wounded = wounded + 1
            end
        end
    end
    if count == 0 then
        if onDone ~= nil then
            onDone(false, T("inn.respite.nobody_home"))
        end
        return
    end
    --a respite is for healing: with nobody hurt there is nothing to rest
    --from (and each respite earns a carouse, so it must not be repeatable).
    if wounded == 0 then
        if onDone ~= nil then
            onDone(false, EotwDowntime.NO_WOUNDS_MESSAGE)
        end
        return
    end
    SaveMine("eotw:pendingRespite", {
        respiteid = dmhub.GenerateGuid(),
        grants = grants,
        pushed = {},
        stage = "new",
    })
    ContinueRespite(onDone)
end

--Can this hero catch their breath? Returns nil if so, else why not.
function EotwDowntime.CatchBreathBlocked(heroid)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil or not EotwRoster.IsInStep(heroid) then
        return T("inn.catch_breath.loading")
    end
    if EotwRoster.AwayHeroes()[heroid] ~= nil then
        return T("inn.catch_breath.away")
    end
    local cur, max, left = Vitals(tok)
    if cur >= max then
        return T("inn.catch_breath.full_stamina")
    end
    if left <= 0 then
        return T("inn.catch_breath.no_recoveries")
    end
    return nil
end

--Catch Your Breath in town: spend one Recovery to regain Stamina equal to
--the hero's recovery value, without resting (Victories stay unspent).
function EotwDowntime.CatchBreath(heroid, onDone)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil or EotwDowntime.CatchBreathBlocked(heroid) ~= nil then
        return
    end
    tok:ModifyProperties{
        description = "Catch Your Breath",
        undoable = false,
        execute = function()
            local props = tok.properties
            props:Heal(props:RecoveryAmount(), "Use Recovery")
            props:ConsumeResource(CharacterResource.recoveryResourceId, "long", 1, "Caught their breath at the inn")
        end,
    }
    Bump()
    EotwAnalytics.Track("eotw_downtime", { activity = "catch_breath", heroid = heroid })
    dmhub.Schedule(0.3, function()
        if mod.unloaded then
            return
        end
        EotwRoster.PushHero(heroid, function(ok, message)
            Bump()
            if onDone ~= nil then
                onDone(ok, message)
            end
        end)
    end)
end

--- project rolls ----------------------------------------------------------

--Send a rolled project roll to the City. The pending entry stays until the
--City answers, so a dropped connection sends it again later (the City
--ignores a rollid it has already recorded). onDone(ok, resultOrMessage).
local function SendProjectRoll(roll, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false, T("downtime.roll.offline"))
        end
        return
    end
    conn:Request{
        action = "project-roll",
        args = {
            rollid = roll.rollid,
            projectid = roll.projectid,
            heroid = roll.heroid,
            natural = roll.natural,
            total = roll.total,
            characteristic = roll.characteristic,
            skill = roll.skill,
            breakthroughOf = roll.breakthroughOf,
        },
        success = function(result)
            SaveMine("eotw:pendingProjectRoll", nil)
            if type(result.project) == "table" then
                m_projects[result.project.projectid] = result.project
            end
            local tier = nil
            pcall(function() tier = EotwDowntime.TestTier(roll.natural, roll.total) end)
            local project = type(result.project) == "table" and result.project or {}
            EotwAnalytics.Track("eotw_project_roll", {
                projectid = roll.projectid,
                heroid = roll.heroid,
                natural = roll.natural,
                total = roll.total,
                tier = tier,
                characteristic = roll.characteristic,
                skill = roll.skill,
                breakthrough = roll.breakthroughOf ~= nil,
                progress = project.progress,
                completed = project.completed,
            })
            EotwRoster.SetListedDowntime(roll.heroid, result.downtime)
            EotwRoster.SetListedSlots(result.slots)
            Bump()
            if onDone ~= nil then
                onDone(true, result)
            end
        end,
        error = function(message)
            --the City refused it (no Downtime left, the project is done...):
            --it will never take this roll, so let it go.
            SaveMine("eotw:pendingProjectRoll", nil)
            Bump()
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Record a project roll left over from a dropped connection. Called when the
--town connects.
function EotwDowntime.ResumePending()
    local _, roll = LoadMine("eotw:pendingProjectRoll")
    if type(roll) == "table" and type(roll.rollid) == "string" and type(roll.natural) == "number" then
        SendProjectRoll(roll, function(ok, result)
            if ok then
                printf("EotW town: recorded a project roll left over from last time (+%s)", tostring(roll.total))
            end
        end)
    end
    local _, respite = LoadMine("eotw:pendingRespite")
    if type(respite) == "table" then
        ContinueRespite(nil)
    end
    --a carouse whose dice landed but the City never heard about.
    EotwLeads.ResumePending()
end

--The roll formula's bonus and a description of it, for a hero working on a
--project with a characteristic and (optionally) one of its skills.
function EotwDowntime.RollBonus(tok, attrid, skill)
    local value = CharacteristicValue(tok, attrid)
    local info = creature.attributesInfo[attrid]
    local parts = { "2d10", string.format("%+d %s", value, info ~= nil and info.description or attrid) }
    local bonus = value
    if skill ~= nil and skill ~= "" then
        bonus = bonus + 2
        parts[#parts+1] = string.format("+2 %s", skill)
    end
    return bonus, table.concat(parts, " ")
end

--Roll for a project and record it. args = {projectid, heroid, characteristic,
--skill, breakthroughOf?, begin = function(rollInfo, bonus) (the dice are
--thrown), rolled = function(natural, total), done = function(ok,
--resultOrMessage), previewPanel?, cancel?}. With previewPanel (a
--gui.DicePreview cage) the dice are only ARMED: they rest in the cage until
--the player clicks or throws them, and cancel() fires if a throw is too
--weak to roll. The dice are real 3D dice (dmhub.Roll works at the
--titlescreen); the City spends the Downtime only when it records the roll.
function EotwDowntime.Roll(args)
    local project = EotwDowntime.PROJECTS[args.projectid]
    local tok = dmhub.GetCharacterById(args.heroid)
    if project == nil or tok == nil then
        args.done(false, T("downtime.roll.not_ready"))
        return
    end
    local bonus = EotwDowntime.RollBonus(tok, args.characteristic, args.skill)
    local roll = {
        rollid = dmhub.GenerateGuid(),
        projectid = args.projectid,
        heroid = args.heroid,
        characteristic = args.characteristic,
        skill = args.skill or "",
        breakthroughOf = args.breakthroughOf,
    }
    local title = cond(args.breakthroughOf ~= nil, T("downtime.roll.dice_breakthrough", { project = project.title }), T("downtime.roll.dice_project", { project = project.title }))
    dmhub.Roll{
        roll = string.format("2d10%+d", bonus),
        description = title,
        preview = args.previewPanel ~= nil,
        previewPanel = args.previewPanel,
        cancel = function()
            if not mod.unloaded and args.cancel ~= nil then
                args.cancel()
            end
        end,
        --the dice are thrown: rollInfo.rolls carries each die's guid, whose
        --chat.DiceEvents report the face it shows as it tumbles.
        begin = function(rollInfo)
            if not mod.unloaded and args.begin ~= nil then
                args.begin(rollInfo, bonus)
            end
        end,
        complete = function(rollInfo)
            if mod.unloaded then
                return
            end
            roll.natural = math.floor(tonumber(rollInfo.naturalRoll) or 0)
            roll.total = math.floor(tonumber(rollInfo.total) or 0)
            --dev: /eotwdowntime breakthrough makes this roll a natural 20.
            if EotwDowntime.forceBreakthrough then
                EotwDowntime.forceBreakthrough = false
                roll.natural = 20
                roll.total = 20 + bonus
                printf("EotW town (dev): this project roll counts as a natural 20 (the dice said %d)", math.floor(tonumber(rollInfo.naturalRoll) or 0))
            end
            --kept until the City has it: a crash now must not lose the roll.
            SaveMine("eotw:pendingProjectRoll", roll)
            if args.rolled ~= nil then
                args.rolled(roll.natural, roll.total)
            end
            SendProjectRoll(roll, args.done)
        end,
    }
end

--The open breakthrough (free follow-up roll) a hero has on a project, or nil.
function EotwDowntime.OpenBreakthrough(projectid, heroid)
    local state = m_projects[projectid]
    for _, r in ipairs(state ~= nil and state.open or {}) do
        if r.heroid == heroid then
            return r
        end
    end
    return nil
end

--- shared UI bits -----------------------------------------------------------

--A dramatic banner for the town: the game's own swords-and-band banner
--(DramaticBanner), mounted once on the town screen, since the titlescreen
--has no game HUD to carry it. sound is an optional sound event (the
--banner's default is the Draw Steel sting). Returns false if it could not
--be shown.
local m_bannerPanel = nil
---@param tokenid nil|string the token whose portrait the banner shows
---@param bannerType nil|string an id from DramaticBanner.types ("heroic" when nil)
local function ShowBanner(host, text, subtitle, sound, tokenid, bannerType)
    local ok = pcall(function()
        if m_bannerPanel == nil or not m_bannerPanel.valid then
            m_bannerPanel = gui.Panel{
                floating = true,
                width = "100%",
                height = "100%",
                interactable = false,
                DramaticBanner.Create(),
            }
            host:AddChild(m_bannerPanel)
        else
            --on top of whatever opened since.
            m_bannerPanel:SetAsLastSibling()
        end
        DramaticBanner.Show{ text = text, subtitle = subtitle, sound = sound, tokenid = tokenid, bannerType = bannerType }
    end)
    return ok
end

--After a respite: a malice banner, one after another, for each Secret Twin
--hero whose d10 came up 1 or 2 (RollSecretTwin).
local function ShowPastCatchesUp(host)
    local list = m_pastCatchesUp
    m_pastCatchesUp = {}
    for i, heroid in ipairs(list) do
        dmhub.Schedule((i - 1) * 4.5, function()
            if mod.unloaded or not host.valid then
                return
            end
            ShowBanner(host, T("inn.secret_twin.banner_title"), T("inn.secret_twin.banner_subtitle"), nil, heroid, "malice")
        end)
    end
end

--How long a gain takes to ease into place on a project bar, in seconds.
local BAR_ANIMATION_SECONDS = 0.9

--A project's progress bar: a gold fill for the points so far and an amber
--"ghost" segment past it previewing a roll's points while its dice tumble.
--Returns the bar panel and a controller:
--  ctl.Set(points, goal)        show this at once (stops any animation)
--  ctl.Update(points, goal)     ease up to a higher value of the same goal,
--                               else Set
--  ctl.Preview(points)          the ghost: this many points past the fill
--                               (nil hides it)
--  ctl.WatchDice(rolls, bonus)  preview the running total of these tumbling
--                               dice (rollInfo.rolls) plus bonus
--  ctl.StopDice()               stop watching the dice
--  ctl.AnimateTo(points, onDone) ease the fill (and its count) up to points
--  ctl.Busy()                   is an animation running?
local function ProgressBar(height)
    local fill = gui.Panel{
        floating = true,
        halign = "left",
        width = "0%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = GOLD,
        cornerRadius = 4,
        interactable = false,
    }
    --the preview of a roll's points: a layer BEHIND the fill reaching to
    --fill + preview, so the part past the fill shows, and the fill eats into
    --it as the gain animates in. Width 0 while there is no preview.
    local ghost = gui.Panel{
        floating = true,
        halign = "left",
        width = "0%",
        height = "100%",
        bgimage = "panels/square.png",
        bgcolor = "#ffd38a",
        opacity = 0.55,
        cornerRadius = 4,
        interactable = false,
    }
    local label = gui.Label{
        text = "",
        fontSize = 15,
        bold = true,
        color = TEXT,
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        floating = true,
        textWrap = false,
        interactable = false,
    }

    --shown = the points the fill shows now (fractional while animating);
    --preview = the ghost's points; anim = {from, to, start, onDone}.
    local s = { shown = 0, goal = 0, preview = nil, anim = nil, dice = nil, faces = {}, bonus = 0, pulse = 0 }

    local function Paint()
        local goal = s.goal
        local shown = math.min(s.shown, goal)
        local fraction = 0
        if goal > 0 then
            fraction = math.max(0, math.min(1, shown / goal))
        end
        fill.selfStyle.width = string.format("%.2f%%", fraction * 100)
        --the ghost reaches from the bar's start to where the preview would
        --land; the fill drawn over it hides all but the gain.
        local ghostTo = 0
        if s.preview ~= nil and goal > 0 then
            local previewTo = (s.anim ~= nil and s.anim.from or s.shown) + s.preview
            ghostTo = math.max(0, math.min(1, previewTo / goal))
        end
        ghost.selfStyle.width = string.format("%.2f%%", ghostTo * 100)
        local count = math.floor(shown + 0.5)
        if s.preview ~= nil and s.anim == nil then
            --bold, in the label's own color: amber text vanished over the gold.
            label.text = string.format("%d <b>+ %d</b> / %d", count, math.max(0, s.preview), goal)
        else
            label.text = string.format("%d / %d", count, goal)
        end
        --dark text once the gold reaches the middle, where the label sits.
        label.selfStyle.color = cond(fraction > 0.5, "#1b140c", TEXT)
    end

    local bar
    bar = gui.Panel{
        width = "100%",
        height = height,
        bgimage = "panels/square.png",
        bgcolor = "#2c261c",
        cornerRadius = 4,
        borderWidth = 1,
        borderColor = "#5a4b33",
        flow = "none",
        styles = {
            --a brief glow as a gain lands.
            { selectors = { "eotwBarFlash" }, brightness = 1, transitionTime = 0.4 },
            { selectors = { "eotwBarFlash", "flash" }, brightness = 1.8, transitionTime = 0.08 },
        },
        classes = { "eotwBarFlash" },
        thinkTime = 0.03,
        think = function(element)
            local now = dmhub.Time()
            if s.anim ~= nil then
                local t = math.min(1, (now - s.anim.start) / BAR_ANIMATION_SECONDS)
                --ease out: quick at first, settling into place.
                local eased = 1 - (1 - t) ^ 3
                s.shown = s.anim.from + (s.anim.to - s.anim.from) * eased
                if t >= 1 then
                    local onDone = s.anim.onDone
                    s.shown = s.anim.to
                    s.anim = nil
                    s.preview = nil
                    element:PulseClass("flash")
                    Paint()
                    if onDone ~= nil then
                        onDone()
                    end
                    return
                end
                Paint()
            elseif s.preview ~= nil then
                --the ghost breathes while the dice decide.
                s.pulse = s.pulse + 0.15
                ghost.selfStyle.opacity = 0.45 + 0.25 * math.sin(s.pulse)
            end
        end,
        --fired by chat.DiceEvents for each die as it tumbles: num is the face
        --it shows now. Once every die has shown a face, preview their sum.
        diceface = function(element, diceguid, num, timeRemaining)
            if s.dice == nil then
                return
            end
            s.faces[diceguid] = num
            local total = s.bonus
            for _, roll in ipairs(s.dice) do
                local face = s.faces[roll.guid]
                if face == nil then
                    return
                end
                total = total + face
            end
            s.preview = math.max(0, total)
            Paint()
        end,
        --behind to front: the preview, the fill, the count.
        ghost,
        fill,
        label,
    }

    local ctl = {}
    function ctl.Set(points, goal)
        s.anim = nil
        s.shown = points or 0
        s.goal = goal or 0
        Paint()
    end
    function ctl.Busy()
        return s.anim ~= nil
    end
    function ctl.Update(points, goal)
        if s.anim ~= nil then
            return
        end
        if goal == s.goal and points > s.shown then
            ctl.AnimateTo(points)
        elseif points ~= s.shown or goal ~= s.goal then
            ctl.Set(points, goal)
        end
    end
    function ctl.Preview(points)
        s.preview = points
        ghost.selfStyle.opacity = 0.55
        Paint()
    end
    function ctl.StopDice()
        if s.dice ~= nil and bar.valid then
            for _, roll in ipairs(s.dice) do
                pcall(function() chat.DiceEvents(roll.guid):Unlisten(bar) end)
            end
        end
        s.dice = nil
    end
    function ctl.WatchDice(rolls, bonus)
        ctl.StopDice()
        s.dice = {}
        s.faces = {}
        s.bonus = bonus or 0
        for _, roll in ipairs(rolls or {}) do
            if not roll.dropped then
                s.dice[#s.dice+1] = roll
                pcall(function() chat.DiceEvents(roll.guid):Listen(bar) end)
            end
        end
    end
    function ctl.AnimateTo(points, onDone)
        s.anim = { from = s.shown, to = points, start = dmhub.Time(), onDone = onDone }
    end
    return bar, ctl
end

--A two-click button: the first click asks, the second within 4s confirms.
local function ConfirmButton(text, confirmText, width, onConfirm)
    local confirming = false
    return gui.Button{
        text = text,
        fontSize = 20,
        width = width,
        height = 46,
        resetConfirm = function(element)
            confirming = false
            element.text = text
        end,
        click = function(element)
            if not confirming then
                confirming = true
                element.text = confirmText
                element:ScheduleEvent("resetConfirm", 4)
                return
            end
            confirming = false
            element.text = text
            onConfirm(element)
        end,
    }
end

local function Portrait(tok, width, height)
    local portrait = nil
    if tok ~= nil then
        pcall(function() portrait = tok.offTokenPortrait end)
    end
    if type(portrait) ~= "string" or portrait == "" then
        return gui.Panel{
            interactable = false,
            width = width,
            height = height,
            valign = "center",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff10",
            cornerRadius = 6,
            gui.Panel{
                interactable = false,
                width = "60%",
                height = "100% width",
                halign = "center",
                valign = "center",
                bgimage = "phosphor/user-fill.png",
                bgcolor = "#ffffff2a",
            },
        }
    end
    local rect = nil
    pcall(function() rect = tok:GetPortraitRectForAspect(width / height, portrait) end)
    return gui.Panel{
        interactable = false,
        width = width,
        height = height,
        valign = "center",
        bgimage = portrait,
        bgcolor = "white",
        cornerRadius = 6,
        borderWidth = 1,
        borderColor = "#8c7a55",
        imageRect = rect,
    }
end

--A small amber hammer chip with a count, for Downtime Activities.
local function HammerChip(count)
    return gui.Panel{
        width = "auto",
        height = 22,
        flow = "horizontal",
        hpad = 6,
        borderBox = true,
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#3a2a10",
        cornerRadius = 6,
        borderWidth = 1,
        borderColor = "#e0a43a",
        interactable = false,
        gui.Panel{
            width = 14,
            height = 14,
            valign = "center",
            bgimage = "phosphor/hammer-fill.png",
            bgcolor = AMBER,
            interactable = false,
        },
        gui.Label{
            text = tostring(count),
            fontSize = 14,
            bold = true,
            color = AMBER,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 4,
            interactable = false,
        },
    }
end

--- the project roll dialog ----------------------------------------------------

--A choice among options (the roll dialog's characteristic): dark when idle,
--warmer on hover, gold-framed when chosen. The text never changes color.
local TOGGLE_STYLES = {
    { selectors = { "eotwToggle" }, bgcolor = "#1d1913", borderWidth = 1, borderColor = "#5a4b33" },
    { selectors = { "eotwToggle", "hover" }, bgcolor = "#2c2318", borderColor = "#8c7a55" },
    { selectors = { "eotwToggle", "selected" }, bgcolor = "#3a2e1a", borderWidth = 2, borderColor = GOLD },
    { selectors = { "eotwToggle", "selected", "hover" }, bgcolor = "#463720", borderWidth = 2, borderColor = GOLD },
}

--The heroes who could work on a project now: at home and loaded, in roster
--order. Each entry: {hero, tok, downtime, breakthrough (an open free roll)}.
local function ProjectWorkers(projectid)
    local result = {}
    local away = EotwRoster.AwayHeroes()
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local tok = dmhub.GetCharacterById(hero.heroid)
        if tok ~= nil and away[hero.heroid] == nil then
            result[#result+1] = {
                hero = hero,
                tok = tok,
                downtime = EotwRoster.GetDowntime(hero.heroid),
                breakthrough = EotwDowntime.OpenBreakthrough(projectid, hero.heroid),
            }
        end
    end
    return result
end

--The best characteristic for this hero on this project.
local function BestCharacteristic(tok, project)
    local best, bestValue = project.characteristics[1], nil
    for _, attrid in ipairs(project.characteristics) do
        local v = CharacteristicValue(tok, attrid)
        if bestValue == nil or v > bestValue then
            best, bestValue = attrid, v
        end
    end
    return best
end

--The project roll dialog: pick who works on it, with which characteristic
--and skill, then roll. Stays open so several Downtime Activities can be
--spent in a row; a breakthrough offers its free roll here.
function EotwDowntime.ShowRollDialog(host, projectid)
    local project = EotwDowntime.PROJECTS[projectid]
    if project == nil then
        return
    end

    --what the dialog has chosen, and where the last roll stands.
    local state = {
        heroid = nil,
        characteristic = nil,
        skill = nil,
        rolling = false,
        resultText = "",
        resultDetail = "",
        --this dialog's roll completed the project.
        completed = false,
        breakthrough = false,
        message = "",
        --what the hero said about the last roll (PickRollLine), or nil:
        --{heroid, text}.
        line = nil,
        --the last roll's dice and total.
        natural = 0,
        total = 0,
    }

    local dlg = nil
    local body = nil
    local hintLabel = nil
    local finishButton = nil

    --the project's line and bar sit above the re-rendered body, so a gain
    --animating on the bar is never rebuilt mid-way.
    local blurbLabel = gui.Label{
        text = "",
        fontSize = 16,
        italics = true,
        color = DIM,
        width = "100%",
        height = "auto",
        bmargin = 8,
    }
    local bar, barCtl = ProgressBar(26)
    do
        local st = EotwDowntime.GetProject(projectid)
        barCtl.Set(st ~= nil and tonumber(st.points) or 0, st ~= nil and tonumber(st.goal) or 0)
    end

    --pick a default hero: one owed a free breakthrough roll, else the one
    --with the most Downtime.
    local function ChooseDefaultHero()
        local workers = ProjectWorkers(projectid)
        local best = nil
        for _, w in ipairs(workers) do
            if w.breakthrough ~= nil then
                return w
            end
            if best == nil or w.downtime > best.downtime then
                best = w
            end
        end
        return best
    end

    local function SelectHero(w)
        if w == nil then
            state.heroid = nil
            return
        end
        state.heroid = w.hero.heroid
        state.characteristic = BestCharacteristic(w.tok, project)
        local trained = TrainedProjectSkills(w.tok, project)
        state.skill = trained[1]
    end

    local Render

    --The dice rest in a cage at the bottom of the dialog, armed with the
    --current choices; clicking or throwing them makes the roll. armedSignature
    --is what they are armed with (nil = not armed): a change of hero,
    --characteristic, skill or free roll re-arms them.
    local cage = nil
    local armedSignature = nil

    local function Disarm()
        armedSignature = nil
        if cage ~= nil and cage.valid then
            pcall(function() cage:CancelDicePreviewRoll() end)
        end
    end

    local function ArmDice(signature)
        Disarm()
        if cage == nil or not cage.valid or state.heroid == nil then
            return
        end
        armedSignature = signature
        local breakthrough = EotwDowntime.OpenBreakthrough(projectid, state.heroid)
        local before = EotwDowntime.GetProject(projectid)
        local goalBefore = before ~= nil and tonumber(before.goal) or 0
        EotwDowntime.Roll{
            previewPanel = cage,
            projectid = projectid,
            heroid = state.heroid,
            characteristic = state.characteristic,
            skill = state.skill,
            breakthroughOf = breakthrough ~= nil and breakthrough.rollid or nil,
            --the player threw the dice: the roll is under way, and the bar
            --previews what they show as they tumble.
            begin = function(rollInfo, bonus)
                armedSignature = nil
                state.rolling = true
                state.message = ""
                state.resultText = "..."
                state.resultDetail = T("downtime.roll.dice_rolling")
                state.breakthrough = false
                state.line = nil
                if bar.valid then
                    barCtl.WatchDice(rollInfo.rolls, bonus)
                end
                Render()
            end,
            --a throw too weak to roll: the dice go back to rest, armed again.
            cancel = function()
                armedSignature = nil
                Render()
            end,
            rolled = function(natural, total)
                state.natural = natural
                state.total = total
                state.resultText = string.format("+%d", math.max(0, total))
                state.resultDetail = T("downtime.roll.result_natural", { natural = natural })
                state.breakthrough = natural >= EotwDowntime.BREAKTHROUGH_NATURAL
                if bar.valid then
                    barCtl.StopDice()
                    barCtl.Preview(math.max(0, total))
                end
                Render()
            end,
            done = function(ok, result)
                if mod.unloaded then
                    return
                end
                if not ok then
                    state.rolling = false
                    state.message = tostring(result)
                    if bar.valid then
                        barCtl.StopDice()
                        barCtl.Preview(nil)
                    end
                    Render()
                    return
                end
                local tok = dmhub.GetCharacterById(state.heroid)
                local name = tok ~= nil and tok.name or T("downtime.roll.your_hero")
                local p = result.project or {}

                --the banners wait for the gain to settle on the bar.
                local function Announce()
                    if mod.unloaded then
                        return
                    end
                    if result.breakthrough then
                        local subtitle = T("downtime.roll.breakthrough_subtitle", { hero = name, project = project.title })
                        if result.refunded then
                            subtitle = T("downtime.roll.breakthrough_refunded_subtitle", { hero = name, project = project.title })
                        end
                        ShowBanner(host, T("downtime.roll.breakthrough_banner"), subtitle)
                    end
                    if result.completed then
                        local text = T("downtime.roll.complete_banner", { project = project.title })
                        local subtitle = T("downtime.roll.complete_subtitle")
                        if projectid == "expand-guild" then
                            text = T("downtime.roll.guild_banner")
                            subtitle = T("downtime.roll.guild_subtitle", { slots = string.format("%d", EotwRoster.Slots()) })
                        elseif project.completeBanner ~= nil then
                            text = project.completeBanner.text
                            subtitle = project.completeBanner.subtitle
                        end
                        --after the breakthrough banner, if both.
                        dmhub.Schedule(cond(result.breakthrough, 4.5, 0), function()
                            if not mod.unloaded then
                                ShowBanner(host, text, subtitle)
                            end
                        end)
                    end
                end

                if result.completed then
                    state.resultDetail = cond(p.maxed, T("downtime.roll.result_finished", { natural = state.natural }), T("downtime.roll.result_complete", { natural = state.natural }))
                    if result.refunded then
                        --the City gave the breakthrough's extra roll back.
                        state.resultDetail = cond(p.maxed, T("downtime.roll.result_finished_refunded", { natural = state.natural, hero = name }), T("downtime.roll.result_complete_refunded", { natural = state.natural, hero = name }))
                    end
                else
                    state.resultDetail = T("downtime.roll.result_hero", { natural = state.natural, hero = tostring(name) })
                end

                --the hero's word on how it went: by the roll's tier and how
                --close the project now is.
                local goal = tonumber(p.goal) or 0
                local progress = 1
                if not result.completed and goal > 0 then
                    progress = (tonumber(p.points) or 0) / goal
                end
                local tier = EotwDowntime.TestTier(state.natural or 0, state.total or 0)
                local text = EotwDowntime.PickRollLine(projectid, tier, progress, result.completed == true)
                if text ~= nil then
                    state.line = { heroid = state.heroid, text = text }
                end

                if not bar.valid then
                    state.rolling = false
                    Announce()
                    return
                end
                if result.completed then
                    --fill to the end and stay full: the project is done (it
                    --has ended; a next expansion has to be started anew).
                    state.completed = true
                    barCtl.AnimateTo(goalBefore, function()
                        Announce()
                        state.rolling = false
                        Render()
                    end)
                else
                    barCtl.AnimateTo(tonumber(p.points) or 0, function()
                        state.rolling = false
                        Announce()
                        Render()
                    end)
                end
                Render()
            end,
        }
    end

    Render = function()
        if body == nil or not body.valid then
            return
        end
        local projectState = EotwDowntime.GetProject(projectid)
        local workers = ProjectWorkers(projectid)
        local chosen = nil
        for _, w in ipairs(workers) do
            if w.hero.heroid == state.heroid then
                chosen = w
            end
        end
        if chosen == nil and not state.rolling then
            SelectHero(ChooseDefaultHero())
            for _, w in ipairs(workers) do
                if w.hero.heroid == state.heroid then
                    chosen = w
                end
            end
        end

        local children = {}

        blurbLabel.text = project.blurb(projectState)
        --a finished project's bar stays full; only one under way follows the City.
        if projectState ~= nil and projectState.active == true and not state.rolling and not barCtl.Busy() then
            barCtl.Update(tonumber(projectState.points) or 0, tonumber(projectState.goal) or 0)
        end

        --who works on it.
        children[#children+1] = gui.Label{
            text = T("downtime.roll.who_heading"),
            fontSize = 15,
            color = DIM,
            width = "100%",
            height = "auto",
            tmargin = 14,
            bmargin = 4,
        }
        local chips = {}
        for _, w in ipairs(workers) do
            local selected = state.heroid == w.hero.heroid
            local usable = w.downtime > 0 or w.breakthrough ~= nil
            chips[#chips+1] = gui.Panel{
                width = "auto",
                height = 40,
                flow = "horizontal",
                hpad = 8,
                borderBox = true,
                hmargin = 3,
                vmargin = 3,
                bgimage = "panels/square.png",
                bgcolor = cond(selected, "#3a2e1a", "#1d1913"),
                borderWidth = cond(selected, 2, 1),
                borderColor = cond(selected, GOLD, "#5a4b33"),
                cornerRadius = 6,
                opacity = cond(usable, 1, 0.5),
                press = function()
                    if state.rolling then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    SelectHero(w)
                    state.message = ""
                    Render()
                end,
                linger = function(element)
                    if w.breakthrough ~= nil then
                        gui.Tooltip(T("downtime.roll.free_roll_tooltip"))(element)
                    elseif not usable then
                        gui.Tooltip(T("downtime.roll.no_downtime_tooltip"))(element)
                    end
                end,
                Portrait(w.tok, 24, 32),
                gui.Label{
                    text = w.tok.name or T("downtime.roll.hero_fallback"),
                    fontSize = 16,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    hmargin = 6,
                    interactable = false,
                },
                HammerChip(w.downtime),
                gui.Label{
                    classes = { cond(w.breakthrough ~= nil, "visible", "collapsed") },
                    text = T("downtime.roll.free_roll_tag"),
                    fontSize = 13,
                    italics = true,
                    color = AMBER,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 6,
                    interactable = false,
                },
            }
        end
        if #chips == 0 then
            chips[1] = gui.Label{
                text = T("downtime.roll.nobody_home"),
                fontSize = 16,
                italics = true,
                color = DIM,
                width = "auto",
                height = "auto",
            }
        end
        children[#children+1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            wrap = true,
            children = chips,
        }

        if chosen ~= nil then
            --the characteristic.
            local options = {}
            for _, c in ipairs(ProjectCharacteristics(project)) do
                local selected = state.characteristic == c.id
                --a toggle with its own look (a stock button's hover turns
                --the text black, unreadable on the selected dark fill).
                local classes = { "eotwToggle" }
                if selected then
                    classes[#classes+1] = "selected"
                end
                options[#options+1] = gui.Panel{
                    classes = classes,
                    styles = TOGGLE_STYLES,
                    width = 170,
                    height = 36,
                    hmargin = 4,
                    bgimage = "panels/square.png",
                    cornerRadius = 6,
                    press = function()
                        if state.rolling then
                            return
                        end
                        audio.FireSoundEvent("Mouse.Click")
                        state.characteristic = c.id
                        Render()
                    end,
                    gui.Label{
                        text = string.format("%s %+d", c.name, CharacteristicValue(chosen.tok, c.id)),
                        fontSize = 16,
                        color = TEXT,
                        width = "auto",
                        height = "auto",
                        halign = "center",
                        valign = "center",
                        interactable = false,
                    },
                }
            end
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 12,
                gui.Label{
                    text = T("downtime.roll.characteristic_heading"),
                    fontSize = 15,
                    color = DIM,
                    width = 140,
                    height = "auto",
                    valign = "center",
                },
                gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    children = options,
                },
            }

            --the skill.
            local trained = TrainedProjectSkills(chosen.tok, project)
            local skillOptions = { { id = "", text = T("downtime.roll.no_skill") } }
            for _, name in ipairs(trained) do
                skillOptions[#skillOptions+1] = { id = name, text = T("downtime.roll.skill_choice", { skill = name }) }
            end
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 8,
                gui.Label{
                    text = T("downtime.roll.skill_heading"),
                    fontSize = 15,
                    color = DIM,
                    width = 140,
                    height = "auto",
                    valign = "center",
                },
                gui.Dropdown{
                    width = 240,
                    height = 34,
                    fontSize = 16,
                    --the open list needs the themed sheet; the titlescreen's
                    --legacy styles leave it as bare labels.
                    styles = ThemeEngine.GetStyles(),
                    options = skillOptions,
                    idChosen = state.skill or "",
                    change = function(element)
                        ---@cast element Dropdown
                        local id = element.idChosen
                        state.skill = cond(id ~= nil and id ~= "", id, nil)
                        Render()
                    end,
                },
                gui.Label{
                    text = cond(#trained == 0, T("downtime.roll.skills_none_trained", { skills = table.concat(project.skills, ", ") }), table.concat(project.skills, ", ")),
                    fontSize = 13,
                    italics = true,
                    color = DIM,
                    width = 320,
                    height = "auto",
                    valign = "center",
                    lmargin = 10,
                },
            }

            local _, formula = EotwDowntime.RollBonus(chosen.tok, state.characteristic, state.skill)
            children[#children+1] = gui.Label{
                text = formula,
                fontSize = 18,
                color = TEXT,
                width = "100%",
                height = "auto",
                tmargin = 12,
            }
        end

        --the result of the last roll.
        children[#children+1] = gui.Panel{
            width = "100%",
            height = 96,
            flow = "vertical",
            tmargin = 10,
            gui.Label{
                classes = { cond(state.breakthrough, "visible", "collapsed") },
                text = T("downtime.roll.breakthrough_label"),
                fontFace = "display",
                fontSize = 30,
                color = AMBER,
                width = "auto",
                height = "auto",
                halign = "center",
            },
            gui.Label{
                text = state.resultText,
                fontSize = 40,
                bold = true,
                color = GOLD,
                width = "auto",
                height = "auto",
                halign = "center",
            },
            gui.Label{
                text = state.resultDetail,
                fontSize = 15,
                color = DIM,
                width = "auto",
                height = "auto",
                halign = "center",
            },
        }

        --what the hero made of it (projects with rollLines).
        local lineTok = state.line ~= nil and dmhub.GetCharacterById(state.line.heroid) or nil
        children[#children+1] = gui.Panel{
            classes = { cond(state.line ~= nil and not state.rolling, "visible", "collapsed") },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 6,
            bgimage = "panels/square.png",
            bgcolor = "#1d1913",
            cornerRadius = 6,
            pad = 8,
            borderBox = true,
            Portrait(lineTok, 36, 48),
            gui.Label{
                text = state.line ~= nil and T("downtime.roll.hero_line", { hero = tostring(lineTok ~= nil and lineTok.name or T("downtime.roll.your_hero")), line = state.line.text }) or "",
                fontSize = 17,
                italics = true,
                color = TEXT,
                width = "100%-60",
                height = "auto",
                valign = "center",
                lmargin = 10,
            },
        }

        children[#children+1] = gui.Label{
            text = state.message,
            fontSize = 15,
            color = RED,
            width = "100%",
            height = 22,
            textAlignment = "center",
        }

        body.children = children

        --the dice: armed with the current choices when a roll is possible.
        local free = chosen ~= nil and chosen.breakthrough ~= nil
        local projectActive = projectState ~= nil and projectState.active == true
        local canRoll = chosen ~= nil and (free or chosen.downtime > 0) and projectActive
        local chosenName = T("downtime.roll.hint_your_hero")
        local freeRollid = ""
        if chosen ~= nil then
            chosenName = tostring(chosen.tok.name or chosenName)
            if chosen.breakthrough ~= nil then
                freeRollid = tostring(chosen.breakthrough.rollid)
            end
        end
        --finished: the project is done, or no hero at home has a roll left
        --(no Downtime, no free breakthrough). Then the dice give way to a big
        --Close; otherwise the X in the corner is the way out.
        local anyCanWork = false
        for _, w in ipairs(workers) do
            if w.downtime > 0 or w.breakthrough ~= nil then
                anyCanWork = true
            end
        end
        local finished = not state.rolling and (state.completed or not projectActive or not anyCanWork)
        if finishButton ~= nil and finishButton.valid then
            finishButton:SetClass("collapsed", not finished)
        end

        local hint = ""
        if state.rolling then
            hint = ""
        elseif canRoll and free then
            hint = T("downtime.roll.hint_free", { hero = chosenName })
        elseif canRoll then
            hint = T("downtime.roll.hint_roll")
        elseif state.completed then
            hint = T("downtime.roll.hint_complete", { benefit = tostring(project.benefit or T("downtime.roll.hint_done")) })
        elseif not projectActive then
            hint = T("downtime.roll.hint_not_under_way")
        elseif chosen == nil then
            hint = T("downtime.roll.hint_nobody_home")
        elseif not anyCanWork then
            hint = T("downtime.roll.hint_no_downtime_left")
        else
            hint = T("downtime.roll.hint_hero_no_downtime")
        end
        if hintLabel ~= nil and hintLabel.valid then
            hintLabel.text = hint
        end
        if not state.rolling then
            if canRoll then
                local signature = table.concat({
                    tostring(state.heroid), tostring(state.characteristic), tostring(state.skill),
                    freeRollid,
                }, "|")
                if signature ~= armedSignature then
                    ArmDice(signature)
                end
            elseif armedSignature ~= nil then
                Disarm()
            end
        end
    end

    --A fixed size, so nothing jumps as the rows change during a roll: the
    --header, bar and choices hang from the top, the hint and the dice sit
    --on the bottom, and the space between absorbs the changes. (A fixed
    --height with flow "vertical" would spread the rows out instead.)
    dlg = gui.Panel{
        floating = true,
        width = 860,
        height = 820,
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "none",
        pad = 24,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            if not state.rolling then
                barCtl.StopDice()
                Disarm()
                element:DestroySelf()
            end
        end,
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev and not state.rolling then
                element.data.seen = rev
                Render()
            end
        end,
        --the top: title, the project's line and bar, then the choices.
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "top",
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                bmargin = 6,
                gui.Panel{
                    width = 30,
                    height = 30,
                    valign = "center",
                    rmargin = 10,
                    bgimage = "phosphor/hammer-fill.png",
                    bgcolor = GOLD,
                },
                gui.Label{
                    text = T("downtime.roll.title", { project = project.title }),
                    fontSize = 28,
                    bold = true,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            },
            blurbLabel,
            bar,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    body = element
                end,
            },
        },

        --the bottom: how to roll (or why not) over the dice.
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "100%",
            height = "auto",
            flow = "vertical",

            --a fixed height: the line empties while the dice roll.
            gui.Label{
                text = "",
                fontSize = 16,
                italics = true,
                color = AMBER,
                width = "100%",
                height = 46,
                textAlignment = "center",
                create = function(element)
                    hintLabel = element
                end,
            },

            --The dice, resting until clicked or thrown -- the same kind of dice
            --cage the game's roll dialog has (a gui.DicePreview armed by
            --dmhub.Roll{preview = true, previewPanel = cage}). Built once: a
            --rebuild would drop the armed roll.
            gui.DicePreview{
                width = "70%",
                height = 120,
                halign = "center",
                bgimage = true,
                bgcolor = "white",
                styles = { gui.Style{ opacity = 0 } },
                draggable = true,
                dragMove = false,
                create = function(element)
                    ---@cast element DicePreview
                    cage = element
                    element:SetAsDicePreviewPanel(true)
                    --thrown dice roll out across the whole screen, not just the cage.
                    pcall(function() element.dicePreviewScreenBounds = true end)
                    --the body is in place by now: render, which arms the dice.
                    Render()
                end,
                destroy = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:CancelDicePreviewRoll() end)
                    element:SetAsDicePreviewPanel(false)
                end,
                --input goes through the cage's own methods, so only THIS
                --dialog's dice react.
                hover = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewMouseEnter() end)
                end,
                dehover = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewMouseLeave() end)
                end,
                click = function(element)
                    ---@cast element DicePreview
                    if armedSignature ~= nil then
                        pcall(function() element:DicePreviewClick() end)
                    end
                end,
                dragging = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewDragThink() end)
                end,
                drag = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:DicePreviewDragEnd() end)
                end,
            },

            --where the dice were, once there is nothing left to roll: a big
            --Close (see `finished` in Render). Floats over the empty cage.
            gui.Button{
                classes = { "collapsed" },
                floating = true,
                halign = "center",
                valign = "bottom",
                bmargin = 34,
                text = T("downtime.roll.close_button"),
                fontSize = 24,
                width = 260,
                height = 54,
                create = function(element)
                    finishButton = element
                    --built after the dice cage's first render: show it now if
                    --the dialog opened with nothing left to roll.
                    Render()
                end,
                click = function()
                    if state.rolling then
                        return
                    end
                    if dlg ~= nil and dlg.valid then
                        barCtl.StopDice()
                        Disarm()
                        dlg:DestroySelf()
                    end
                end,
            },
        },

        --close: an X in the top-right corner (not while dice are in the air).
        gui.Panel{
            floating = true,
            halign = "right",
            valign = "top",
            x = 10,
            y = -10,
            width = 22,
            height = 22,
            bgimage = "phosphor/x-bold.png",
            styles = {
                { selectors = { "eotwDialogClose" }, bgcolor = DIM },
                { selectors = { "eotwDialogClose", "hover" }, bgcolor = "#ffffff", scale = 1.15 },
            },
            classes = { "eotwDialogClose" },
            linger = gui.Tooltip(T("downtime.roll.close_tooltip")),
            press = function()
                if state.rolling then
                    return
                end
                audio.FireSoundEvent("UI.WindowClose")
                if dlg ~= nil and dlg.valid then
                    barCtl.StopDice()
                    Disarm()
                    dlg:DestroySelf()
                end
            end,
        },
    }
    host:AddChild(dlg)
end

--- projects under way (the Hero's Guild) -------------------------------------------

--Is this project under way (started and not yet completed)?
function EotwDowntime.IsActive(projectid)
    local state = m_projects[projectid]
    return state ~= nil and state.active == true
end

--Could this project be started now? Not while it is under way or finished,
--nor before the City has listed it.
function EotwDowntime.CanStart(projectid)
    local state = m_projects[projectid]
    return state ~= nil and state.active ~= true and state.maxed ~= true
end

--Should the Guild offer to start this project? Whenever it is listed and
--not under way -- even when it can never complete again, so the screen
--does not give away how many times it can be done (the dialog then says
--the guild cannot grow).
function EotwDowntime.CanOffer(projectid)
    local state = m_projects[projectid]
    return state ~= nil and state.active ~= true
end

--Start a project, so heroes can spend Downtime on it. onDone(ok, message).
function EotwDowntime.StartProject(projectid, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false, T("downtime.start.not_connected"))
        end
        return
    end
    conn:Request{
        action = "start-project",
        args = { projectid = projectid },
        success = function(result)
            EotwAnalytics.Track("eotw_project_start", { projectid = projectid })
            if type(result.project) == "table" then
                m_projects[result.project.projectid] = result.project
            end
            Bump()
            if onDone ~= nil then
                onDone(true)
            end
        end,
        error = function(message)
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Ask whether to start a project: what it does, what it costs, how it is
--worked on. Start sends start-project.
function EotwDowntime.ShowStartProjectDialog(host, projectid)
    local project = EotwDowntime.PROJECTS[projectid]
    local state = m_projects[projectid]
    if project == nil then
        return
    end
    local goal = state ~= nil and tonumber(state.goal) or 0
    --a project that can never complete again: the dialog says so instead
    --of offering to start it (the Guild still offers it; see CanOffer).
    local maxed = state ~= nil and state.maxed == true
    local statusLabel = gui.Label{
        text = "",
        fontSize = 15,
        color = RED,
        width = "100%",
        height = 22,
        textAlignment = "center",
    }
    local dlg
    dlg = gui.Panel{
        floating = true,
        width = 720,
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        pad = 28,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            gui.Panel{
                width = 30,
                height = 30,
                valign = "center",
                rmargin = 10,
                bgimage = project.icon,
                bgcolor = GOLD,
            },
            gui.Label{
                text = T("downtime.start.title", { project = project.title }),
                fontSize = 28,
                bold = true,
                color = TEXT,
                width = "auto",
                height = "auto",
                valign = "center",
            },
        },
        gui.Label{
            text = project.blurb(state),
            fontSize = 18,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 10,
        },
        gui.Label{
            text = cond(maxed, T("downtime.start.maxed"), T("downtime.start.goal", { goal = string.format("%d", goal) })),
            fontSize = 20,
            color = TEXT,
            width = "100%",
            height = "auto",
            textAlignment = "center",
            tmargin = 6,
        },
        gui.Label{
            classes = { cond(maxed, "collapsed", "eotwBenefit") },
            text = project.benefit,
            fontSize = 22,
            bold = true,
            color = GOLD,
            width = "100%",
            height = "auto",
            textAlignment = "center",
            vmargin = 6,
        },
        statusLabel,
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            tmargin = 8,
            gui.Button{
                classes = { cond(maxed, "collapsed", "eotwStart") },
                text = T("downtime.start.start_button"),
                fontSize = 20,
                width = 220,
                height = 46,
                hmargin = 6,
                click = function()
                    audio.FireSoundEvent("Mouse.Click")
                    EotwDowntime.StartProject(projectid, function(ok, message)
                        if mod.unloaded then
                            return
                        end
                        if not ok then
                            if statusLabel.valid then
                                statusLabel.text = tostring(message)
                            end
                            return
                        end
                        if dlg ~= nil and dlg.valid then
                            dlg:DestroySelf()
                        end
                    end)
                end,
            },
            gui.Button{
                text = T("downtime.start.not_now_button"),
                fontSize = 20,
                width = 180,
                height = 46,
                hmargin = 6,
                click = function()
                    dlg:DestroySelf()
                end,
            },
        },
    }
    host:AddChild(dlg)
end

--A project's card: its progress, what it takes, the latest rolls, and the
--way in to the roll dialog. host is the panel to mount the roll dialog on
--(the town screen).
function EotwDowntime.ProjectCard(host, projectid)
    local project = EotwDowntime.PROJECTS[projectid]
    local bar, barCtl = ProgressBar(22)

    local titleLabel = gui.Label{
        text = project.title,
        fontSize = 22,
        bold = true,
        color = TEXT,
        width = "auto",
        height = "auto",
        valign = "center",
    }
    local stepLabel = gui.Label{
        text = "",
        fontSize = 15,
        color = DIM,
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 10,
    }
    local blurbLabel = gui.Label{
        text = "",
        fontSize = 15,
        italics = true,
        color = DIM,
        width = "100%",
        height = "auto",
        vmargin = 4,
    }
    local characteristicNames = {}
    for _, c in ipairs(ProjectCharacteristics(project)) do
        characteristicNames[#characteristicNames+1] = c.name
    end
    local needsLabel = gui.Label{
        text = T("downtime.card.needs", { characteristics = table.concat(characteristicNames, T("downtime.card.characteristic_separator")), skills = table.concat(project.skills, ", ") }),
        fontSize = 14,
        color = DIM,
        width = "100%",
        height = "auto",
        tmargin = 6,
    }
    local recentLabel = gui.Label{
        text = "",
        fontSize = 14,
        color = DIM,
        width = "100%",
        height = "auto",
        tmargin = 4,
    }
    local workButton = gui.Button{
        text = T("downtime.card.work_button"),
        fontSize = 18,
        width = 250,
        height = 40,
        halign = "right",
        linger = function(element)
            if element.data.reason ~= nil then
                gui.Tooltip(element.data.reason)(element)
            end
        end,
        data = { reason = nil },
        click = function(element)
            if element.data.reason ~= nil then
                return
            end
            EotwDowntime.ShowRollDialog(host, projectid)
        end,
    }

    local function Refresh()
        local state = EotwDowntime.GetProject(projectid)
        blurbLabel.text = project.blurb(state)
        --no "expansion N of M": how many there can be is not shown.
        stepLabel.text = ""
        if state ~= nil then
            --a gain eases into place; anything else shows at once.
            barCtl.Update(tonumber(state.points) or 0, tonumber(state.goal) or 0)
        end

        local parts = {}
        for i, r in ipairs(state ~= nil and state.recent or {}) do
            if i > 4 then
                break
            end
            local heroName = tostring(r.heroName or T("downtime.card.hero_fallback"))
            local total = string.format("%d", tonumber(r.total) or 0)
            local text = T("downtime.card.recent_roll", { hero = heroName, total = total })
            if r.breakthrough then
                local word = string.format("<color=%s>%s</color>", AMBER, T("downtime.card.breakthrough_word"))
                text = T("downtime.card.recent_roll_breakthrough", { hero = heroName, total = total, breakthrough = word })
            end
            parts[#parts+1] = text
        end
        recentLabel.text = cond(#parts > 0, T("downtime.card.latest", { rolls = table.concat(parts, "  -  ") }), T("downtime.card.no_rolls"))

        --who can work on it now.
        local anyDowntime, anyBreakthrough = false, false
        for _, w in ipairs(ProjectWorkers(projectid)) do
            if w.downtime > 0 then
                anyDowntime = true
            end
            if w.breakthrough ~= nil then
                anyBreakthrough = true
            end
        end
        local reason = nil
        if state == nil or state.active ~= true then
            reason = T("downtime.card.not_under_way")
        elseif not anyDowntime and not anyBreakthrough then
            reason = T("downtime.card.no_downtime")
        end
        workButton.data.reason = reason
        workButton.selfStyle.opacity = cond(reason == nil, 1, 0.45)
        workButton.text = cond(anyBreakthrough, T("downtime.card.breakthrough_button"), T("downtime.card.work_button"))
    end

    EotwDowntime.RefreshProjects()

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        bgimage = "panels/square.png",
        --translucent like the scene's own card: the art reads through.
        bgcolor = "#0e0b08dc",
        borderWidth = 1,
        borderColor = "#d9b56a77",
        cornerRadius = 10,
        pad = 16,
        borderBox = true,
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev then
                element.data.seen = rev
                Refresh()
            end
        end,
        create = function(element)
            Refresh()
        end,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = 22,
                height = 22,
                valign = "center",
                rmargin = 8,
                bgimage = project.icon,
                bgcolor = GOLD,
            },
            titleLabel,
            stepLabel,
            gui.Label{
                text = T("downtime.card.under_way"),
                fontSize = 13,
                italics = true,
                color = GOLD,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
            },
        },
        blurbLabel,
        bar,
        needsLabel,
        recentLabel,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 6,
            workButton,
        },
    }
end

--The project card for the free space on a location's scene: shown only
--while the project is under way. width in the scene's units.
function EotwDowntime.ProjectSidePanel(host, projectid, width)
    local panel
    panel = gui.Panel{
        classes = { "collapsed" },
        width = width,
        height = "auto",
        flow = "vertical",
        data = { seen = -1 },
        --a collapsed panel stops thinking, so the watcher is a sibling
        --below that stays alive.
        EotwDowntime.ProjectCard(host, projectid),
    }
    local watcher = gui.Panel{
        width = 1,
        height = 1,
        interactable = false,
        data = { seen = -1 },
        thinkTime = 0.25,
        think = function(element)
            local rev = EotwDowntime.revision
            if element.data.seen ~= rev and panel.valid then
                element.data.seen = rev
                panel:SetClass("collapsed", not EotwDowntime.IsActive(projectid))
            end
        end,
    }
    EotwDowntime.RefreshProjects()
    return gui.Panel{
        width = "auto",
        height = "auto",
        flow = "vertical",
        children = { panel, watcher },
    }
end

--- Tribute to the Builders ------------------------------------------------------

--Text shown as typed: rich-text tags in a player's name are not applied.
local function PlainName(text)
    return "<noparse>" .. string.gsub(tostring(text or ""), "</?[nN][oO][pP][aA][rR][sS][eE]>", "") .. "</noparse>"
end

--A builder's name, or the stand-in for rolls made before names were kept.
local function BuilderName(name)
    if type(name) ~= "string" or name == "" then
        return T("tribute.unknown_player")
    end
    return PlainName(name)
end

local function BuilderHeroName(name)
    if type(name) ~= "string" or name == "" then
        return T("tribute.unknown_hero")
    end
    return PlainName(name)
end

--The cornerstone or capstone: who placed it, with which hero, and when.
local function StoneBox(heading, subtitle, stone)
    return gui.Panel{
        width = "48%",
        height = "auto",
        flow = "vertical",
        halign = "center",
        hmargin = 6,
        bgimage = "panels/square.png",
        bgcolor = "#d9b56a1c",
        borderWidth = 1,
        borderColor = "#d9b56a66",
        cornerRadius = 8,
        pad = 12,
        borderBox = true,
        gui.Label{ text = heading, fontSize = 20, bold = true, color = GOLD, width = "100%", height = "auto", textAlignment = "center" },
        gui.Label{ text = subtitle, fontSize = 14, italics = true, color = DIM, width = "100%", height = "auto", textAlignment = "center" },
        gui.Label{ text = BuilderName(stone.name), fontSize = 22, bold = true, color = TEXT, width = "100%", height = "auto", textAlignment = "center", tmargin = 6 },
        gui.Label{
            text = T("tribute.stone_detail", { hero = BuilderHeroName(stone.heroName), when = DescribeServerTimestamp(stone.at) }),
            fontSize = 14,
            color = DIM,
            width = "100%",
            height = "auto",
            textAlignment = "center",
        },
    }
end

--One ranked builder: place, name and points; hovering lists their heroes.
local function BuilderRow(rank, builder)
    local lines = { T("tribute.heroes_heading") }
    for _, hero in ipairs(builder.heroes or {}) do
        lines[#lines+1] = TP("tribute.hero_line", tonumber(hero.points) or 0, { hero = BuilderHeroName(hero.name) })
    end
    local mine = builder.userid == dmhub.loginUserid
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = cond(mine, "#2a2418cc", "#ffffff0a"),
        styles = {
            { selectors = {"hover"}, bgcolor = cond(mine, "#3a3220dd", "#ffffff18") },
        },
        cornerRadius = 6,
        hpad = 10,
        vpad = 6,
        borderBox = true,
        vmargin = 2,
        hover = gui.Tooltip(table.concat(lines, "\n")),
        gui.Label{ text = string.format("#%d", rank), fontSize = 17, bold = true, color = cond(rank <= 3, GOLD, DIM), width = 54, height = "auto", valign = "center" },
        gui.Label{ text = BuilderName(builder.name), fontSize = 17, bold = mine, color = TEXT, width = "100%-190", height = "auto", valign = "center" },
        gui.Label{ text = TP("tribute.points", tonumber(builder.points) or 0), fontSize = 16, color = TEXT, width = 130, height = "auto", valign = "center", textAlignment = "right" },
    }
end

--The Tribute to the Builders for a project: its cornerstone (the first
--roll), its capstone once complete (the roll that finished it), and every
--builder ranked by Project Points. Read from the City's
--list-project-builders. host mounts the dialog.
function EotwDowntime.ShowTribute(host, projectid)
    local project = EotwDowntime.PROJECTS[projectid]
    local body = nil
    local dlg
    local function Show(children)
        if body ~= nil and body.valid then
            body.children = children
        end
    end
    dlg = gui.Panel{
        floating = true,
        width = 760,
        height = "auto",
        halign = "center",
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#14110dff",
        borderWidth = 2,
        borderColor = "#8c7a55",
        cornerRadius = 10,
        flow = "vertical",
        pad = 24,
        borderBox = true,
        styles = { Styles.Default },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:DestroySelf()
        end,
        gui.Label{ text = T("tribute.title"), fontSize = 30, bold = true, color = TEXT, width = "100%", height = "auto", textAlignment = "center" },
        gui.Label{ text = project ~= nil and project.title or "", fontSize = 18, italics = true, color = DIM, width = "100%", height = "auto", textAlignment = "center", bmargin = 10 },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            create = function(element)
                body = element
                Show{ gui.Label{ text = T("tribute.loading"), fontSize = 18, color = DIM, width = "100%", height = "auto", textAlignment = "center", vmargin = 20 } }
            end,
        },
        gui.Button{
            text = T("tribute.close_button"),
            fontSize = 18,
            width = 180,
            height = 40,
            halign = "center",
            tmargin = 12,
            click = function()
                dlg:DestroySelf()
            end,
        },
    }
    host:AddChild(dlg)

    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        Show{ gui.Label{ text = T("tribute.error"), fontSize = 18, color = RED, width = "100%", height = "auto", textAlignment = "center", vmargin = 20 } }
        return
    end
    conn:Request{
        action = "list-project-builders",
        args = { projectid = projectid },
        success = function(result)
            if mod.unloaded or dlg == nil or not dlg.valid then
                return
            end
            local builders = result.builders or {}
            if #builders == 0 then
                Show{ gui.Label{ text = T("tribute.empty"), fontSize = 18, color = DIM, width = "100%", height = "auto", textAlignment = "center", vmargin = 20 } }
                return
            end
            ---@type Panel[]
            local stones = {}
            if type(result.cornerstone) == "table" then
                stones[#stones+1] = StoneBox(T("tribute.cornerstone"), T("tribute.cornerstone_subtitle"), result.cornerstone)
            end
            if type(result.capstone) == "table" then
                stones[#stones+1] = StoneBox(T("tribute.capstone"), T("tribute.capstone_subtitle"), result.capstone)
            end
            ---@type Panel[]
            local rows = {}
            for i, builder in ipairs(builders) do
                rows[#rows+1] = BuilderRow(i, builder)
            end
            local more = (tonumber(result.builderCount) or #builders) - #builders
            if more > 0 then
                rows[#rows+1] = gui.Label{ text = TP("tribute.more_builders", more), fontSize = 15, italics = true, color = DIM, width = "100%", height = "auto", textAlignment = "center", vmargin = 4 }
            end
            Show{
                gui.Panel{ width = "100%", height = "auto", flow = "horizontal", halign = "center", children = stones },
                gui.Label{
                    text = T("tribute.summary", { builders = TP("tribute.builder_count", tonumber(result.builderCount) or #builders), points = TP("tribute.points", tonumber(result.totalPoints) or 0) }),
                    fontSize = 16,
                    color = TEXT,
                    width = "100%",
                    height = "auto",
                    textAlignment = "center",
                    vmargin = 10,
                },
                gui.Label{ text = T("tribute.ranked_heading"), fontSize = 18, bold = true, color = GOLD, width = "100%", height = "auto", bmargin = 4 },
                gui.Panel{
                    width = "100%",
                    height = "auto",
                    maxHeight = 420,
                    flow = "vertical",
                    vscroll = true,
                    rpad = 10,
                    borderBox = true,
                    children = rows,
                },
            }
        end,
        error = function(message)
            printf("EotW town: could not list the builders of %s: %s", projectid, tostring(message))
            if not mod.unloaded then
                Show{ gui.Label{ text = T("tribute.error"), fontSize = 18, color = RED, width = "100%", height = "auto", textAlignment = "center", vmargin = 20 } }
            end
        end,
    }
end

--The small "Tribute to the Builders" button under a community project, and
--on the building it became.
function EotwDowntime.TributeButton(host, projectid)
    return gui.Button{
        text = T("tribute.button"),
        fontSize = 12,
        width = 160,
        height = 22,
        halign = "right",
        tmargin = 8,
        click = function()
            audio.FireSoundEvent("Mouse.Click")
            EotwDowntime.ShowTribute(host, projectid)
        end,
    }
end

--- the Construction (the Hall of Heroes being built) --------------------------

--The Construction scene's card: what is being built, and the town's shared
--project (Build the Hall of Heroes) with its progress, the latest builders
--and the way in to the roll dialog. host mounts the roll dialog.
function EotwDowntime.ConstructionPanel(host)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            text = T("downtime.construction.intro"),
            fontSize = 20,
            italics = true,
            color = TEXT,
            width = "100%",
            height = "auto",
            bmargin = 12,
        },
        gui.Label{
            text = T("downtime.construction.community"),
            fontSize = 15,
            color = DIM,
            width = "100%",
            height = "auto",
            bmargin = 16,
        },
        EotwDowntime.ProjectCard(host, "build-hall-of-heroes"),
        EotwDowntime.TributeButton(host, "build-hall-of-heroes"),
    }
end

--The Town Hall's building site: the same, for the town's shared project
--Build the Town Hall.
function EotwDowntime.TownHallConstructionPanel(host)
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Label{
            text = T("downtime.town_hall_site.intro"),
            fontSize = 20,
            italics = true,
            color = TEXT,
            width = "100%",
            height = "auto",
            bmargin = 12,
        },
        gui.Label{
            text = T("downtime.town_hall_site.community"),
            fontSize = 15,
            color = DIM,
            width = "100%",
            height = "auto",
            bmargin = 16,
        },
        EotwDowntime.ProjectCard(host, "build-town-hall"),
        EotwDowntime.TributeButton(host, "build-town-hall"),
    }
end

--- the Blue Fish Inn ----------------------------------------------------------

--One hero's row at the inn: portrait, name, Stamina and Recoveries, what a
--respite would give them, and Catch Your Breath.
local function InnRow(entry, onChanged)
    local hero = entry.hero
    local tok = entry.tok
    local summary = hero.summary or {}
    local name = (tok ~= nil and tok.name) or summary.name or T("inn.row.hero_fallback")

    local vitals = "-"
    local barFraction = 0
    local dying = false
    if tok ~= nil then
        local cur, max, left, rmax = Vitals(tok)
        vitals = T("inn.row.vitals", { stamina = string.format("%d", cur), stamina_max = string.format("%d", max), recoveries = string.format("%d", left), recoveries_max = string.format("%d", rmax) })
        if max > 0 then
            barFraction = math.max(0, math.min(1, cur / max))
        end
        dying = EotwRoster.TokenIsDying(tok)
    end

    local gains
    if not entry.canRest then
        gains = gui.Label{
            text = entry.reason or "",
            fontSize = 14,
            italics = true,
            color = DIM,
            width = 150,
            height = "auto",
            valign = "center",
            textAlignment = "right",
        }
    else
        gains = gui.Panel{
            width = 150,
            height = "auto",
            flow = "vertical",
            valign = "center",
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                gui.Panel{
                    width = 16,
                    height = 16,
                    valign = "center",
                    bgimage = "phosphor/trophy-fill.png",
                    bgcolor = GOLD,
                },
                gui.Label{
                    text = string.format("%d", entry.victories),
                    fontSize = 16,
                    bold = true,
                    color = GOLD,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 4,
                },
            },
            gui.Label{
                text = cond(entry.victories > 0,
                    T("inn.row.gains", { xp = string.format("%d", entry.victories), downtime = string.format("%d", entry.victories) }),
                    T("inn.row.full_rest")),
                fontSize = 13,
                color = cond(entry.victories > 0, AMBER, DIM),
                width = "auto",
                height = "auto",
                halign = "right",
            },
        }
    end

    local breathReason = EotwDowntime.CatchBreathBlocked(hero.heroid)
    local breathButton = gui.Button{
        text = T("inn.catch_breath.button"),
        fontSize = 14,
        width = 120,
        height = 30,
        valign = "center",
        lmargin = 10,
        opacity = cond(breathReason == nil, 1, 0.4),
        linger = function(element)
            if breathReason ~= nil then
                gui.Tooltip(breathReason)(element)
            elseif tok ~= nil then
                local amount = 0
                pcall(function() amount = tok.properties:RecoveryAmount() end)
                gui.Tooltip(T("inn.catch_breath.tooltip", { amount = string.format("%d", amount) }))(element)
            end
        end,
        click = function()
            if breathReason ~= nil then
                return
            end
            audio.FireSoundEvent("Mouse.Click")
            EotwDowntime.CatchBreath(hero.heroid, onChanged)
            onChanged()
        end,
    }

    return gui.Panel{
        width = "100%",
        height = 68,
        flow = "horizontal",
        vmargin = 2,
        hpad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        cornerRadius = 6,
        opacity = cond(entry.away ~= nil, 0.5, 1),
        Portrait(tok, 42, 56),
        gui.Panel{
            width = "100%-370",
            height = "auto",
            flow = "vertical",
            valign = "center",
            lmargin = 10,
            gui.Label{
                text = name,
                fontSize = 18,
                bold = true,
                color = TEXT,
                width = "100%",
                height = "auto",
                textWrap = false,
                minFontSize = 12,
            },
            gui.Panel{
                width = "100%",
                height = 6,
                vmargin = 3,
                bgimage = "panels/square.png",
                bgcolor = "#2c261c",
                cornerRadius = 3,
                flow = "none",
                gui.Panel{
                    width = string.format("%.1f%%", barFraction * 100),
                    height = "100%",
                    halign = "left",
                    bgimage = "panels/square.png",
                    bgcolor = cond(barFraction >= 1, "#5f9a4a", "#c0563a"),
                    cornerRadius = 3,
                },
            },
            gui.Label{
                text = cond(dying, T("inn.row.vitals_dying", { dying = string.format("<color=#ff8f7a>%s</color>", T("inn.row.dying")), vitals = vitals }), vitals),
                fontSize = 13,
                color = DIM,
                width = "100%",
                height = "auto",
            },
        },
        gains,
        breathButton,
    }
end

--The Blue Fish Inn's card: every hero with their wounds, Take a Respite for
--all of them, Catch Your Breath for one, and where to spend Downtime after.
--host mounts dialogs; openLocation(id) goes to another town location.
function EotwDowntime.InnPanel(host, openLocation)
    local listPanel = nil
    local footerLabel = nil
    local statusLabel = nil
    local afterPanel = nil
    local respiteButton = nil
    --a series' next part that a respite would close (warning), and the
    --ones the last respite here did close (note).
    local seriesWarning = nil
    local seriesNote = nil

    local Rebuild
    Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local candidates = EotwDowntime.RestCandidates()
        local rows = {}
        local resting, victories, wounded = 0, 0, 0
        for _, entry in ipairs(candidates) do
            rows[#rows+1] = InnRow(entry, Rebuild)
            if entry.canRest then
                resting = resting + 1
                victories = victories + entry.victories
                if entry.wounded then
                    wounded = wounded + 1
                end
            end
        end
        if EotwRoster.GetHeroes() == nil then
            rows[1] = gui.Label{ text = T("inn.list.loading"), fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        elseif #rows == 0 then
            rows[1] = gui.Label{ text = T("inn.list.no_heroes"), fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        end
        listPanel.children = rows

        if footerLabel ~= nil and footerLabel.valid then
            if resting == 0 then
                footerLabel.text = T("inn.footer.nobody_home")
            elseif wounded == 0 then
                footerLabel.text = EotwDowntime.NO_WOUNDS_MESSAGE
            else
                if victories > 0 then
                    footerLabel.text = TP("inn.footer.rest_downtime", resting, { downtime = TP("inn.footer.downtime_activities", victories) })
                else
                    footerLabel.text = TP("inn.footer.rest", resting)
                end
            end
        end
        if seriesWarning ~= nil and seriesWarning.valid then
            local lines = {}
            if resting > 0 and wounded > 0 then
                for _, held in ipairs(EncounterOfTheWeek.PartsHeldOpen()) do
                    lines[#lines+1] = T("inn.series.warning", held)
                end
            end
            seriesWarning.text = table.concat(lines, "\n")
            seriesWarning:SetClass("collapsed", #lines == 0)
        end
        if respiteButton ~= nil and respiteButton.valid then
            --on the button itself: opacity is not inherited from this wrapper.
            local opacity = cond(resting > 0 and wounded > 0 and not EotwDowntime.RespiteBusy(), 1, 0.45)
            for _, child in ipairs(respiteButton.children) do
                child.selfStyle.opacity = opacity
            end
        end

        --where to spend Downtime: shown once any hero at home has some.
        if afterPanel ~= nil and afterPanel.valid then
            local total = 0
            for _, entry in ipairs(candidates) do
                if entry.away == nil then
                    total = total + EotwRoster.GetDowntime(entry.hero.heroid)
                end
            end
            local children = {}
            if total > 0 then
                children[#children+1] = gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    valign = "center",
                    HammerChip(total),
                    gui.Label{
                        text = TP("inn.after.downtime", total),
                        fontSize = 15,
                        color = TEXT,
                        width = "auto",
                        height = "auto",
                        valign = "center",
                        lmargin = 8,
                    },
                }
                local anyActive = false
                for id, project in pairs(EotwDowntime.PROJECTS) do
                    local state = EotwDowntime.GetProject(id)
                    if state ~= nil and state.active == true then
                        anyActive = true
                        children[#children+1] = gui.Button{
                            text = string.format("%s (%d/%d)", project.title, tonumber(state.points) or 0, tonumber(state.goal) or 0),
                            fontSize = 15,
                            width = 300,
                            height = 34,
                            tmargin = 6,
                            linger = gui.Tooltip(cond(project.location == "inn", T("inn.after.project_here_tooltip"), T("inn.after.project_elsewhere_tooltip", { place = project.locationName or T("inn.after.guild_place") }))),
                            click = function()
                                if project.location == "inn" then
                                    EotwDowntime.ShowRollDialog(host, id)
                                else
                                    openLocation(project.location)
                                end
                            end,
                        }
                    end
                end
                if not anyActive then
                    --no project under way: point the way to where one starts.
                    children[#children+1] = gui.Button{
                        text = T("inn.after.guild_button"),
                        fontSize = 15,
                        width = 300,
                        height = 34,
                        tmargin = 6,
                        linger = gui.Tooltip(T("inn.after.guild_tooltip")),
                        click = function()
                            openLocation("guild")
                        end,
                    }
                end
            end
            afterPanel.children = children
            afterPanel:SetClass("collapsed", #children == 0)
        end
    end

    EotwDowntime.RefreshProjects()

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev then
                element.data.seen = rev
                Rebuild()
            end
        end,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Label{
                text = T("inn.respite.heading"),
                fontSize = 26,
                bold = true,
                color = TEXT,
                width = "auto",
                height = "auto",
                valign = "center",
            },
            gui.Label{
                text = T("inn.respite.duration"),
                fontSize = 16,
                italics = true,
                color = DIM,
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
            },
        },
        gui.Label{
            text = T("inn.respite.intro"),
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            vmargin = 8,
        },
        gui.Panel{
            width = "100%",
            height = "100%-390",
            flow = "vertical",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            create = function(element)
                listPanel = element
                Rebuild()
            end,
        },
        gui.Label{
            text = "",
            fontSize = 15,
            color = TEXT,
            width = "100%",
            height = "auto",
            tmargin = 10,
            create = function(element)
                footerLabel = element
            end,
        },
        gui.Label{
            classes = { "collapsed" },
            text = "",
            fontSize = 15,
            color = AMBER,
            width = "100%",
            height = "auto",
            tmargin = 6,
            create = function(element)
                seriesWarning = element
            end,
        },
        gui.Label{
            text = "",
            fontSize = 15,
            color = RED,
            width = "100%",
            height = 22,
            create = function(element)
                statusLabel = element
            end,
        },
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "right",
                create = function(element)
                    respiteButton = element
                end,
                ConfirmButton(T("inn.respite.button"), T("inn.respite.button_confirm"), 360, function()
                    if EotwDowntime.RespiteBusy() then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    if statusLabel ~= nil and statusLabel.valid then
                        statusLabel.text = ""
                    end
                    EotwDowntime.TakeRespite(function(ok, message, closedParts)
                        if mod.unloaded then
                            return
                        end
                        if not ok and statusLabel ~= nil and statusLabel.valid then
                            statusLabel.text = tostring(message)
                        end
                        if ok then
                            ShowPastCatchesUp(host)
                            if seriesNote ~= nil and seriesNote.valid then
                                local lines = {}
                                for _, held in ipairs(EncounterOfTheWeek.PartsHeldOpen(closedParts or {})) do
                                    lines[#lines+1] = T("inn.series.closed", held)
                                end
                                seriesNote.text = table.concat(lines, "\n")
                                seriesNote:SetClass("collapsed", #lines == 0)
                            end
                        end
                        Rebuild()
                    end)
                    Rebuild()
                end),
            },
        },
        gui.Label{
            classes = { "collapsed" },
            text = "",
            fontSize = 15,
            italics = true,
            color = AMBER,
            width = "100%",
            height = "auto",
            tmargin = 8,
            create = function(element)
                seriesNote = element
            end,
        },
        --after a respite: carouse in the common room for leads, and start
        --the projects those leads open (EotwLeads.lua).
        EotwLeads.InnLeadsPanel(host),
        gui.Panel{
            classes = { "collapsed" },
            width = "100%",
            height = "auto",
            flow = "vertical",
            tmargin = 12,
            create = function(element)
                afterPanel = element
            end,
        },
    }
end

--Pieces of this file's UI that EotwLeads.lua reuses.
EotwDowntime.UI = {
    Portrait = Portrait,
    ShowBanner = ShowBanner,
    ConfirmButton = ConfirmButton,
    CharacteristicValue = CharacteristicValue,
    TrainedSkills = TrainedProjectSkills,
    LoadMine = LoadMine,
    SaveMine = SaveMine,
    TOGGLE_STYLES = TOGGLE_STYLES,
}

--- dev commands ---------------------------------------------------------------

--The roster heroes a dev command names: those whose name starts with
--`name` (case-insensitive), or every hero at home when name is empty.
local function DevHeroes(name)
    local result = {}
    local away = EotwRoster.AwayHeroes()
    name = string.lower(name or "")
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local tok = dmhub.GetCharacterById(hero.heroid)
        local heroName = (tok ~= nil and tok.name) or (hero.summary or {}).name or ""
        if name == "" then
            if away[hero.heroid] == nil then
                result[#result+1] = hero
            end
        elseif string.sub(string.lower(heroName), 1, #name) == name then
            result[#result+1] = hero
        end
    end
    return result
end

local function DevHeroName(hero)
    local tok = dmhub.GetCharacterById(hero.heroid)
    return (tok ~= nil and tok.name) or (hero.summary or {}).name or hero.heroid
end

--Change a roster hero's working copy and push it (dev commands only).
local function DevModifyHero(hero, description, execute)
    local tok = dmhub.GetCharacterById(hero.heroid)
    if tok == nil or not EotwRoster.IsInStep(hero.heroid) then
        printf("EotW town (dev): %s is not loaded yet; try again in a moment", DevHeroName(hero))
        return
    end
    tok:ModifyProperties{
        description = description,
        undoable = false,
        execute = function()
            execute(tok.properties)
        end,
    }
    dmhub.Schedule(0.3, function()
        if not mod.unloaded then
            EotwRoster.PushHero(hero.heroid)
        end
    end)
end

local DEV_USAGE = [[Usage: /eotwdowntime <command> (open the town first)
  grant <n> [hero]      give n Downtime Activities (project rolls) to the hero, or to every hero at home
  victories <n> [hero]  give n Victories, to try a respite
  wound <n> [hero]      take n Stamina and spend one Recovery, to try Catch Breath
  tire <n> [hero]       spend n Recoveries (no Stamina lost), so a respite is allowed
  breakthrough          the next project roll counts as a natural 20
  resetproject [id]     forget a project's progress, rolls and completions (city admins);
                        id defaults to expand-guild (also: find-arcane-market)
  state                 print each hero's Downtime, the roster slots and the projects
[hero] matches the start of a hero's name, case-insensitive.]]

pcall(function()
    Commands.RegisterMacro{
        name = "eotwdowntime",
        summary = "dev: grant Downtime, Victories or wounds to town heroes",
        doc = DEV_USAGE,
        command = function(str)
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then
                print("EotW town: /eotwdowntime is a developer command")
                return
            end
            local arg = string.gsub(str or "", "^%s*(.-)%s*$", "%1")
            local verb, rest = string.match(arg, "^(%S+)%s*(.*)$")
            verb = string.lower(verb or "")
            local amount, name = string.match(rest or "", "^(%-?%d+)%s*(.*)$")
            local n = math.floor(tonumber(amount) or 0)

            if verb == "breakthrough" then
                EotwDowntime.forceBreakthrough = not EotwDowntime.forceBreakthrough
                printf("EotW town (dev): next project roll is %s", cond(EotwDowntime.forceBreakthrough, "a natural 20", "rolled normally"))
                return
            end

            if verb == "resetproject" then
                local conn = EotwRoster.Connection()
                if conn == nil or not conn.connected then
                    print("EotW town (dev): open the town first (no city connection)")
                    return
                end
                --the project id is optional: Expand the Guild by default.
                local projectid = string.match(rest or "", "^(%S+)") or "expand-guild"
                if EotwDowntime.PROJECTS[projectid] == nil then
                    printf("EotW town (dev): no project '%s'", projectid)
                    return
                end
                conn:Request{
                    action = "dev-reset-project",
                    args = { projectid = projectid },
                    success = function(result)
                        if type(result.project) == "table" then
                            m_projects[result.project.projectid] = result.project
                        end
                        EotwRoster.SetListedSlots(result.slots)
                        Bump()
                        EotwRoster.Refresh()
                        printf("EotW town (dev): %s reset (not started); %s slots", projectid, tostring(result.slots))
                    end,
                    error = function(message)
                        printf("EotW town (dev): reset refused: %s", tostring(message))
                    end,
                }
                return
            end

            if verb == "state" then
                printf("EotW town (dev): %d of %d slots used", EotwRoster.LivingCount(), EotwRoster.Slots())
                for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
                    local tok = dmhub.GetCharacterById(hero.heroid)
                    local victories, xp = 0, 0
                    if tok ~= nil then
                        pcall(function()
                            victories = tok.properties:GetVictories()
                            xp = tok.properties:try_get("xp", 0)
                        end)
                    end
                    local cur, max, left, rmax = 0, 0, 0, 0
                    if tok ~= nil then
                        cur, max, left, rmax = Vitals(tok)
                    end
                    printf("  %s: Downtime %d, Victories %d, XP %d, Stamina %d/%d, Recoveries %d/%d%s",
                        DevHeroName(hero), EotwRoster.GetDowntime(hero.heroid), victories, xp, cur, max, left, rmax,
                        cond(EotwRoster.IsDying(hero.heroid), " (dying)", ""))
                end
                for id, _ in pairs(EotwDowntime.PROJECTS) do
                    local s = EotwDowntime.GetProject(id)
                    if s == nil then
                        printf("  project %s: not listed yet", id)
                    else
                        printf("  project %s: %d/%d, %d completed, %d open breakthrough(s)", id,
                            tonumber(s.points) or 0, tonumber(s.goal) or 0, tonumber(s.completions) or 0, #(s.open or {}))
                    end
                end
                EotwDowntime.RefreshProjects()
                return
            end

            if (verb ~= "grant" and verb ~= "victories" and verb ~= "wound" and verb ~= "tire") or amount == nil then
                print(DEV_USAGE)
                return
            end
            local heroes = DevHeroes(name)
            if #heroes == 0 then
                printf("EotW town (dev): no hero matches '%s' (is the town open?)", tostring(name))
                return
            end

            if verb == "grant" then
                local conn = EotwRoster.Connection()
                if conn == nil or not conn.connected then
                    print("EotW town (dev): open the town first (no city connection)")
                    return
                end
                local grants = {}
                for _, hero in ipairs(heroes) do
                    grants[#grants+1] = { heroid = hero.heroid, amount = n }
                end
                conn:Request{
                    action = "grant-downtime",
                    args = { grantid = "dev-" .. dmhub.GenerateGuid(), grants = grants },
                    success = function(result)
                        for heroid, downtime in pairs(result.downtime or {}) do
                            EotwRoster.SetListedDowntime(heroid, downtime)
                            local hero = EotwRoster.FindHero(heroid)
                            printf("EotW town (dev): %s now has %s Downtime", hero ~= nil and DevHeroName(hero) or heroid, tostring(downtime))
                        end
                        Bump()
                    end,
                    error = function(message)
                        printf("EotW town (dev): grant refused: %s", tostring(message))
                    end,
                }
            elseif verb == "victories" then
                for _, hero in ipairs(heroes) do
                    DevModifyHero(hero, "Dev: Victories", function(props)
                        props:SetVictories(math.max(0, props:GetVictories() + n))
                    end)
                    printf("EotW town (dev): %s gains %d Victories", DevHeroName(hero), n)
                end
            elseif verb == "wound" then
                for _, hero in ipairs(heroes) do
                    DevModifyHero(hero, "Dev: wounds", function(props)
                        props.damage_taken = math.max(0, (props.damage_taken or 0) + n)
                        props:ConsumeResource(CharacterResource.recoveryResourceId, "long", 1, "Dev: wounded")
                    end)
                    printf("EotW town (dev): %s takes %d damage and spends a Recovery", DevHeroName(hero), n)
                end
            elseif verb == "tire" then
                for _, hero in ipairs(heroes) do
                    DevModifyHero(hero, "Dev: spend Recoveries", function(props)
                        props:ConsumeResource(CharacterResource.recoveryResourceId, "long", n, "Dev: tired")
                    end)
                    printf("EotW town (dev): %s spends %d Recoveries", DevHeroName(hero), n)
                end
            end
        end,
    }
end)
