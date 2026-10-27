local mod = dmhub.GetModLoading()

--Encounter of the Week analytics. Two jobs:
--
--1. TAGGING. The engine stamps `eotw = true|false` onto EVERY analytics event
--   (engine and Lua alike; AnalyticsManager.StampContext). In an EotW game it
--   knows on its own (the account's EotW slot game); in the town -- which is
--   the titlescreen, where no game is loaded -- this file tells it through
--   analytics.SetContext. Inside a game it also adds eotwWhere / eotwBoard /
--   eotwEncounter, so any table (use_ability, turn_end, encounter_complete...)
--   can be sliced by board and encounter without a join.
--
--2. THE EOTW EVENTS, all named eotw_*. Every one carries the run fields
--   (runid = the game id, encounter, board, week, part, practice) when it
--   happens in a game. One RUN is one player's time in one EotW game:
--   eotw_run_start (or eotw_run_resume on a later sitting), eotw_phase as it
--   moves between story / montage / combat / ..., and exactly one
--   eotw_run_end with outcome victory / defeat / abandoned. A run that never
--   ended cleanly (quit, crash, never came back) is closed as abandoned with
--   how = "quit" the next time this machine opens the town, from the record
--   kept in the eotw:analyticsRun preference.
--
--Lives in Codex Titlescreen (the core codex) because the town runs at the
--titlescreen, where the separate EncounterOfTheWeek mod is not loaded.
--Respects the telemetry_enabled opt-out like every other track() helper.

EotwAnalytics = {}

--Machine-local record of each user's open run, so a run that ends with the
--app (quit, crash) can still be closed. JSON: { [userid] = run }.
setting{
    id = "eotw:analyticsRun",
    default = "",
    storage = "preference",
}

local function TelemetryOn()
    return dmhub.GetSettingValue("telemetry_enabled") ~= false
end

--One player's run in one EotW game; also the shape kept in eotw:analyticsRun.
---@class EotwAnalyticsRun
---@field runid string|nil the game id
---@field encounter string|nil
---@field board string|nil "gate" | "pits"
---@field week number|nil
---@field part number|nil
---@field practice boolean|nil
---@field host boolean|nil
---@field phase string|nil
---@field minutes number|nil
---@field sittings number|nil
---@field ended boolean|nil

--The run this client is in right now (set by BeginRun, ended by EndRun).
--Its fields ride every eotw_* event sent from inside the game.
---@type EotwAnalyticsRun|nil
local m_run = nil

--m_run, for code already behind an InRun() check.
---@return EotwAnalyticsRun
local function OpenRun()
    return m_run --[[@as EotwAnalyticsRun]]
end

--The phase the run is in, and when it began (dmhub.Time, this sitting).
local m_phase = nil
local m_phaseAt = nil

local function ReadRuns()
    local text = dmhub.GetSettingValue("eotw:analyticsRun")
    if type(text) ~= "string" or text == "" then
        return {}
    end
    --FromJson answers {success, result}, not the decoded value.
    local parsed = dmhub.FromJson(text)
    if type(parsed) ~= "table" or not parsed.success or type(parsed.result) ~= "table" then
        return {}
    end
    return parsed.result
end

local function WriteRun(run)
    local all = ReadRuns()
    all[dmhub.loginUserid] = run
    dmhub.SetSettingValue("eotw:analyticsRun", dmhub.ToJson(all))
end

local function RunFields(fields, run)
    if run == nil then
        return
    end
    fields.runid = run.runid
    fields.encounter = run.encounter
    fields.board = run.board
    fields.week = run.week
    fields.part = run.part
    fields.practice = run.practice
end

--Send one eotw_* event. fields is consumed. The run fields are added when a
--run is open; an explicit `run` (a record being closed from the town) wins.
---@param eventType string
---@param fields table
---@param run? table
function EotwAnalytics.Track(eventType, fields, run)
    if not TelemetryOn() then
        return
    end
    pcall(function()
        RunFields(fields, run or m_run)
        fields.type = eventType
        fields.userid = dmhub.userid
        fields.gameid = dmhub.gameid
        fields.version = dmhub.version
        analytics.Event(fields)
    end)
end

--Is `runid` a run of the game `gameid` (the game itself, or a later part
--played on in it)?
local function RunOfGame(runid, gameid)
    return type(runid) == "string" and (runid == gameid or string.sub(runid, 1, #gameid + 5) == gameid .. "-part")
end

--- the town ----------------------------------------------------------------

local m_townOpenAt = nil

--Close a run left open by a game that ended with the app: on town open, any
--record for this user whose game is not the one they can still resume is an
--abandoned run. resumableGameid is the account's EotW slot game (the resume
--row); a record for it stays open, since the player may yet go back.
---@param resumableGameid? string
---@param how? string what ended it; "quit" (left and never came back) by default
function EotwAnalytics.ReconcileRuns(resumableGameid, how)
    local run = ReadRuns()[dmhub.loginUserid]
    if type(run) ~= "table" or run.runid == nil then
        return
    end
    if resumableGameid ~= nil and RunOfGame(run.runid, resumableGameid) then
        return
    end
    EotwAnalytics.Track("eotw_run_end", {
        outcome = "abandoned",
        how = how or "quit",
        lastPhase = run.phase,
        minutes = run.minutes,
        host = run.host,
        sittings = run.sittings,
    }, run)
    WriteRun(nil)
end

--Does this player have a run open in `gameid` (they played it before and
--did not finish)? The town asks as it enters a game: a resume, not a start.
---@param gameid string
---@return boolean
function EotwAnalytics.HasOpenRun(gameid)
    local run = ReadRuns()[dmhub.loginUserid]
    return type(run) == "table" and RunOfGame(run.runid, gameid)
end

--The town gave up `gameid` (the resume row's Abandon, or a new party
--replacing the old game): close this player's run in it, if one is open.
---@param gameid string
---@param how string
function EotwAnalytics.CloseRun(gameid, how)
    local run = ReadRuns()[dmhub.loginUserid]
    if type(run) == "table" and RunOfGame(run.runid, gameid) then
        EotwAnalytics.ReconcileRuns(nil, how)
    end
end

--The town (the EotW screen at the titlescreen) opened or closed. Tags every
--event sent meanwhile as EotW, and measures the visit.
function EotwAnalytics.TownOpened()
    if m_townOpenAt ~= nil then
        return
    end
    analytics.SetContext("eotw", true, "titlescreen")
    analytics.SetContext("eotwWhere", "town", "titlescreen")
    m_townOpenAt = dmhub.Time()
    EotwAnalytics.Track("eotw_town_open", {})
end

---@param reason? string what closed it: "enter_game", "back", ...
function EotwAnalytics.TownClosed(reason)
    analytics.SetContext("eotw", nil)
    analytics.SetContext("eotwWhere", nil)
    if m_townOpenAt == nil then
        return
    end
    local seconds = math.floor(dmhub.Time() - m_townOpenAt)
    m_townOpenAt = nil
    EotwAnalytics.Track("eotw_town_close", { seconds = seconds, reason = reason })
end

function EotwAnalytics.IsTownOpen()
    return m_townOpenAt ~= nil
end

--- the run (game side) -----------------------------------------------------

--The run's id: the game's id, or "<gameid>-part<n>" once a series party has
--gone straight on to its next part in the same game (EncounterOfTheWeek.lua
--Series.StartNextPart), so each part played is its own run.
local m_runIdOverride = nil

---@param runid string
function EotwAnalytics.SetRunId(runid)
    m_runIdOverride = { gameid = dmhub.gameid, runid = runid }
end

local function CurrentRunId()
    if m_runIdOverride ~= nil and m_runIdOverride.gameid == dmhub.gameid then
        return m_runIdOverride.runid
    end
    return dmhub.gameid
end

--Open this client's run in the current EotW game. info: encounter (key),
--board ("gate"|"pits"), week, part, practice, host (bool), plus anything to
--report on eotw_run_start (party size, this player's heroes...). A second
--sitting in the same game reports eotw_run_resume instead. Safe to call more
--than once per sitting: only the first does anything.
---@param info table
function EotwAnalytics.BeginRun(info)
    local runid = CurrentRunId()
    if m_run ~= nil and m_run.runid == runid then
        return
    end

    local runs = ReadRuns()
    local prior = runs[dmhub.loginUserid]
    local resume = type(prior) == "table" and prior.runid == runid

    --a run in another game was never closed: it is over now.
    if type(prior) == "table" and prior.runid ~= nil and not resume then
        EotwAnalytics.Track("eotw_run_end", {
            outcome = "abandoned",
            how = "quit",
            lastPhase = prior.phase,
            minutes = prior.minutes,
            host = prior.host,
            sittings = prior.sittings,
        }, prior)
    end

    ---@type EotwAnalyticsRun
    local run = {
        runid = runid,
        encounter = info.encounter,
        board = info.board,
        week = info.week,
        part = info.part,
        practice = info.practice,
        host = info.host,
        phase = resume and prior.phase or nil,
        minutes = resume and prior.minutes or 0,
        sittings = (resume and tonumber(prior.sittings) or 0) + 1,
    }
    m_run = run
    WriteRun(run)

    analytics.SetContext("eotwWhere", "game", "game")
    analytics.SetContext("eotwBoard", info.board, "game")
    analytics.SetContext("eotwEncounter", info.encounter, "game")

    local fields = {}
    for k, v in pairs(info.report or {}) do
        fields[k] = v
    end
    fields.host = info.host
    fields.sittings = run.sittings
    if resume then
        fields.lastPhase = prior.phase
        EotwAnalytics.Track("eotw_run_resume", fields)
    else
        EotwAnalytics.Track("eotw_run_start", fields)
    end
end

function EotwAnalytics.InRun()
    return m_run ~= nil and m_run.runid == CurrentRunId() and not m_run.ended
end

--Keep the run record's minutes current, so a run closed from the town after
--a quit still says how long it lasted. Called from the game's play clock.
---@param seconds number this machine's play time in this game, all sittings
function EotwAnalytics.UpdateMinutes(seconds)
    if not EotwAnalytics.InRun() then
        return
    end
    local run = OpenRun()
    local minutes = math.floor((seconds or 0) / 60)
    if minutes ~= run.minutes then
        run.minutes = minutes
        WriteRun(run)
    end
end

--The run is now in `phase` ("gathering", "montage", "combat", ...): kept in
--the run record so eotw_run_end (and a run closed from the town after a
--quit) can say where the player was. Sends nothing -- the game's host
--reports the party's phase changes as eotw_phase. A repeat is ignored.
---@param phase string
function EotwAnalytics.NotePhase(phase)
    if not EotwAnalytics.InRun() or phase == m_phase then
        return
    end
    m_phase = phase
    m_phaseAt = dmhub.Time()
    local run = OpenRun()
    run.phase = phase
    WriteRun(run)
end

function EotwAnalytics.CurrentPhase()
    return m_phase
end

--Close this client's run. outcome: "victory" | "defeat" | "abandoned".
--how says what ended it ("conclusion", "abandon_button", "party_left"...).
--Only the first call per run does anything.
---@param outcome string
---@param how string
---@param fields? table extra fields
---@param seconds? number this machine's play time in this game, all sittings
function EotwAnalytics.EndRun(outcome, how, fields, seconds)
    if not EotwAnalytics.InRun() then
        return
    end
    local run = OpenRun()
    local report = {}
    for k, v in pairs(fields or {}) do
        report[k] = v
    end
    report.outcome = outcome
    report.how = how
    report.lastPhase = m_phase or run.phase
    if m_phaseAt ~= nil then
        report.lastPhaseSeconds = math.floor(dmhub.Time() - m_phaseAt)
    end
    report.host = run.host
    report.sittings = run.sittings
    if seconds ~= nil then
        report.minutes = math.floor(seconds / 60)
        report.seconds = math.floor(seconds)
    else
        report.minutes = run.minutes
    end
    EotwAnalytics.Track("eotw_run_end", report)
    WriteRun(nil)
    --keep m_run so the rest of this sitting's events still carry the run
    --fields; `ended` stops a second EndRun, NotePhase and a restart.
    run.ended = true
end
