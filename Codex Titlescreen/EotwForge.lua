local mod = dmhub.GetModLoading()

--The built Great Forge in the Encounter of the Week town: a crafting
--workshop. Before a player may use it, Giddlebrick Thundlestrom of the
--Tinkerer's Guild has to be talked round:
--  * the first visit plays a conversation (EotwLeads.PlayConversation) whose
--    opening depends on the account's standing -- "defender" (won the
--    Forge's siege), "builder" (100+ Project Points into building it) or
--    "stranger" -- and ends with the hero's choice: push for a station (the
--    negotiation) or leave;
--  * the negotiation is Lisa's EotW negotiation, played here by
--    NegotiationScene / NegotiationSceneStage (Draw Steel V), from the script
--    in EotwTextForgeNegotiation.lua;
--  * the City (city-core.ts "The Great Forge workshop") keeps the result:
--    interest 4 opens the Forge, 5 also puts 100 points into the account's
--    first treasure, anything lower locks the Forge to this player for a
--    while (3: 1 hour, 2: 4 hours, 0-1: 24 hours), shown on the town map as a
--    clock and countdown. A visit after the lock goes straight to the talk.
--Once in, each hero crafts one treasure at a time: Gold echelon 1 treasures
--with a project goal, rolled with Downtime Activities on the hero's
--"forge-craft" project, collected into their pack when done.
--Design: EncounterOfTheWeek.md, "The Great Forge workshop".

EotwForge = rawget(_G, "EotwForge") or {}

local T = UIText.T

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"
local GREEN = "#9fd38a"

--Bumped whenever the Forge's status changes; UIs poll it.
EotwForge.revision = 0

--forgeView as the City last sent it, for which account, and when (dmhub.Time).
local m_status = nil
local m_statusUser = nil
local m_fetchedAt = -1000
local m_fetching = false
--when the lock ends, on dmhub.Time()'s clock (the City sends the time left).
local m_lockEnds = nil
--how long a fetched status is trusted before the map asks again.
local STATUS_SECONDS = 60

--the last town panel the Forge was shown in (for /eotwforge talk).
local m_host = nil

local function Bump()
    EotwForge.revision = EotwForge.revision + 1
end

local function SetStatus(status)
    if type(status) ~= "table" then
        return
    end
    m_status = status
    m_statusUser = dmhub.loginUserid
    m_fetchedAt = dmhub.Time()
    local remaining = (tonumber(status.remainingMs) or 0) / 1000
    m_lockEnds = cond(remaining > 0, dmhub.Time() + remaining, nil)
    Bump()
end

--The account's Forge as last fetched (nil before the first answer):
--{built, standing, access, bonus, lastInterest, tries, remainingMs, crafts}.
function EotwForge.Status()
    if m_statusUser ~= dmhub.loginUserid then
        return nil
    end
    return m_status
end

--Ask the City for the account's Forge. onDone(ok, statusOrMessage).
function EotwForge.Fetch(onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false, T("great_forge.workshop.offline"))
        end
        return
    end
    m_fetching = true
    conn:Request{
        action = "forge-status",
        args = {},
        success = function(result)
            m_fetching = false
            SetStatus(result)
            EotwForge.ResumePending()
            if onDone ~= nil then
                onDone(true, result)
            end
        end,
        error = function(message)
            m_fetching = false
            m_fetchedAt = dmhub.Time()
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--When the Forge's lock on this player ends (dmhub.Time()), or nil if it is
--not locked. The town map's node reads this every half second, which also
--keeps the status fresh while the Forge is built.
function EotwForge.LockedUntil()
    if not EotwRoster.GreatForgeBuilt() then
        return nil
    end
    local stale = m_statusUser ~= dmhub.loginUserid or dmhub.Time() - m_fetchedAt > STATUS_SECONDS
    if stale and not m_fetching then
        EotwForge.Fetch(nil)
    end
    if m_statusUser ~= dmhub.loginUserid or m_lockEnds == nil or m_lockEnds <= dmhub.Time() then
        return nil
    end
    return m_lockEnds
end

--"1:23:45" (or "4:05" under an hour) for a number of seconds.
function EotwForge.FormatTime(seconds)
    local left = math.max(0, math.ceil(seconds))
    local hours = math.floor(left / 3600)
    local minutes = math.floor((left % 3600) / 60)
    if hours == 0 then
        return string.format("%d:%02d", minutes, left % 60)
    end
    return string.format("%d:%02d:%02d", hours, minutes, left % 60)
end

--- reporting the talk ---------------------------------------------------------------

--A finished talk the City has not acknowledged: { negotiationid, interest }.
--Kept on this machine per account until it is, so a crash cannot drop it.
setting{
    id = "eotw:pendingForgeTalk",
    default = "",
    storage = "preference",
}

local function SendTalk(talk, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        if onDone ~= nil then
            onDone(false, T("great_forge.workshop.offline"))
        end
        return
    end
    conn:Request{
        action = "forge-negotiated",
        args = { negotiationid = talk.negotiationid, interest = talk.interest },
        success = function(result)
            EotwDowntime.UI.SaveMine("eotw:pendingForgeTalk", nil)
            SetStatus(result.forge)
            if onDone ~= nil then
                onDone(true, result.forge)
            end
        end,
        error = function(message)
            --refused (locked, not built): it will never be taken.
            EotwDowntime.UI.SaveMine("eotw:pendingForgeTalk", nil)
            if onDone ~= nil then
                onDone(false, message)
            end
        end,
    }
end

--Send a talk left over from last time, if any. Called after each status fetch.
function EotwForge.ResumePending()
    local _, talk = EotwDowntime.UI.LoadMine("eotw:pendingForgeTalk")
    if type(talk) == "table" and type(talk.negotiationid) == "string" and type(talk.interest) == "number" then
        SendTalk(talk, function(ok)
            if ok then
                printf("EotW town: recorded a Great Forge talk left over from last time (interest %d)", talk.interest)
            end
        end)
    end
end

--- the negotiation ----------------------------------------------------------------

local m_beat = nil
local m_beatText = nil

--Giddlebrick's negotiation, parsed from its script (re-parsed if the script
--text changed, e.g. a writer's edit reloaded).
function EotwForge.Beat()
    local text = T("forge.negotiation.script")
    if m_beat == nil or text ~= m_beatText then
        local beat, warnings = NegotiationScene.Parse(text)
        m_beat = beat
        m_beatText = text
        for _, warning in ipairs(warnings) do
            printf("EotW town: Great Forge negotiation script: %s", warning)
        end
    end
    return m_beat
end

--The starting attitude by standing (David 2026-11-15).
local ATTITUDE_BY_STANDING = { defender = "open", builder = "neutral", stranger = "suspicious" }

--The heroes at home who can speak, as the negotiation wants them.
local function Speakers()
    local result = {}
    for _, entry in ipairs(EotwLeads.HeroesAtHome()) do
        result[#result+1] = { charid = entry.hero.heroid, name = entry.tok.name or "", ownerId = dmhub.loginUserid }
    end
    return result
end

--A town test: 2d10 + the hero's best characteristic the argument names, +2
--when they are trained in one of its skills. Real 3D dice.
local function ShowRoll(args)
    local tok = dmhub.GetCharacterById(args.heroid)
    if tok == nil then
        args.send("rollCancelled", { rollSeq = args.rollSeq })
        return
    end
    local characteristics, skills = NegotiationScene.ParseTest(args.attr)
    local best, bestValue = nil, nil
    for attrid, _ in pairs(characteristics) do
        local value = EotwDowntime.UI.CharacteristicValue(tok, attrid)
        if bestValue == nil or value > bestValue then
            best, bestValue = attrid, value
        end
    end
    local bonus = bestValue or 0
    local names = {}
    for _, skill in ipairs(skills) do
        names[#names+1] = skill.name
    end
    local trained = #names > 0 and EotwDowntime.UI.TrainedSkills(tok, { skills = names }) or {}
    if #trained > 0 then
        bonus = bonus + 2
    end
    --knack edges and banes: one net edge is +2, a net double edge is one
    --tier better (and the reverse for banes), as the book's rule.
    local verdict = args.verdict or {}
    local net = math.max(-2, math.min(2, (verdict.boons or 0) - (verdict.banes or 0)))
    if net == 1 then
        bonus = bonus + 2
    elseif net == -1 then
        bonus = bonus - 2
    end
    dmhub.Roll{
        roll = string.format("2d10%+d", bonus),
        description = T("negscene.roll.description", { hero = args.heroName or tok.name or "", name = args.name or "" }),
        complete = function(rollInfo)
            if mod.unloaded or not args.stillWanted() then
                return
            end
            local natural = math.floor(tonumber(rollInfo.naturalRoll) or 0)
            local total = math.floor(tonumber(rollInfo.total) or 0)
            local tier = NegotiationScene.TierFor(natural, total)
            if net == 2 then
                tier = math.min(3, tier + 1)
            elseif net == -2 then
                tier = math.max(1, tier - 1)
            end
            args.send("rolled", {
                rollSeq = args.rollSeq,
                tier = tier,
                total = total,
                natural = natural,
            })
        end,
    }
end

--Play the negotiation over the town. onDone(forge) once it is over and the
--City has the result (forge = the new status, or nil if nothing was sent or
--the City refused it).
---@param host Panel
---@param opts {backdrop: string|nil}|nil
---@param onDone fun(forge: table|nil)
function EotwForge.ShowNegotiation(host, opts, onDone)
    opts = opts or {}
    local beat = EotwForge.Beat()
    local status = EotwForge.Status()
    if beat == nil or status == nil or #Speakers() == 0 then
        onDone(nil)
        return
    end
    local negotiationid = dmhub.GenerateGuid()
    --what the City answered, once the talk is over: false while waiting.
    local reported = nil
    local overlay = nil
    --each hero's knack facts, read once per talk (the stage asks per card).
    local factsByHero = {}

    local session = NegotiationScene.LocalSession{
        Beat = function()
            return beat
        end,
        Heroes = Speakers,
        ShowRoll = ShowRoll,
        --knack arguments ("|Allow:") and edges, by the same rules as a montage.
        Verdict = function(charid, argument)
            local facts = factsByHero[charid]
            if facts == nil then
                local tok = dmhub.GetCharacterById(charid)
                if tok == nil or tok.properties == nil then
                    facts = TestRiders.CompleteFacts({})
                else
                    facts = TestRiders.CreatureFacts(tok.properties)
                end
                factsByHero[charid] = facts
            end
            return TestRiders.Evaluate(argument.riders, facts)
        end,
        Track = function(event, fields)
            fields.standing = status.standing
            EotwAnalytics.Track("eotw_forge_" .. event, fields)
        end,
        --how it ended decides the Forge: leaving before anyone spoke changes
        --nothing; otherwise the interest reached is reported.
        Finish = function(m, outcome, offer, b)
            if outcome == "left" and #(m.log or {}) == 0 then
                reported = { sent = false }
                return {}
            end
            local talk = { negotiationid = negotiationid, interest = m.interest }
            EotwDowntime.UI.SaveMine("eotw:pendingForgeTalk", talk)
            reported = { sent = true, done = false }
            SendTalk(talk, function(ok, result)
                reported.done = true
                reported.forge = cond(ok, result, nil)
                if not ok then
                    printf("EotW town: the City refused the Great Forge talk: %s", tostring(result))
                end
            end)
            return {}
        end,
    }
    session:Begin{ attitude = ATTITUDE_BY_STANDING[status.standing] or "suspicious", finalOptions = { "deal" } }

    local function Close()
        if overlay ~= nil and overlay.valid then
            overlay:DestroySelf()
        end
        --wait (briefly) for the City's answer.
        local tries = 0
        local function Wait()
            if mod.unloaded then
                return
            end
            if reported == nil or not reported.sent then
                onDone(nil)
            elseif reported.done or tries >= 20 then
                onDone(reported.forge)
            else
                tries = tries + 1
                dmhub.Schedule(0.5, Wait)
            end
        end
        Wait()
    end

    local npc = EotwLeads.GIDDLEBRICK.npc
    overlay = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        bgimage = cond(opts.backdrop ~= nil, opts.backdrop, "panels/square.png"),
        bgcolor = cond(opts.backdrop ~= nil, "#555555ff", "#000000ee"),
        children = {
            gui.Panel{
                width = "100%",
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = "#000000b0",
                interactable = false,
            },
            gui.Panel{
                floating = true,
                width = "100%",
                height = "100%",
                vpad = 20,
                borderBox = true,
                NegotiationSceneStage.Create{
                    session = session,
                    selfHosted = true,
                    leave = true,
                    canAct = function(charid)
                        return true
                    end,
                    figure = function()
                        return EotwLeads.Figure(npc.portrait, nil, "center", npc.video, npc.videoAspect)
                    end,
                    createHeroCard = function(entry, cardOpts)
                        cardOpts.showStats = false
                        --every hero here is the player's own: no "The party" line.
                        cardOpts.subtitle = function()
                            return ""
                        end
                        return EotwHeroCard.CreateHeroCard(entry, cardOpts)
                    end,
                    styles = EotwHeroCard.rules,
                    onDone = function(result)
                        Close()
                    end,
                },
            },
        },
    }
    host:AddChild(overlay)
end

--- the first visit's conversation --------------------------------------------------

--Giddlebrick's opening for this standing, ending with the hero's choice:
--"push" (to the negotiation) or "leave".
local function Opening(standing)
    local key = cond(standing == "defender" or standing == "builder", standing, "stranger")
    local function L(name)
        return T("forge.talk." .. key .. "." .. name)
    end
    return {
        npc = EotwLeads.GIDDLEBRICK.npc,
        conversation = function(heroName, tok)
            return {
                { who = "npc", text = L("line1_npc") },
                { who = "hero", text = L("line2_hero") },
                { who = "npc", text = L("line3_npc") },
                { who = "choice", options = {
                    { text = L("push_hero"), result = "push" },
                    { text = L("leave_hero"), result = "leave", lines = {
                        { who = "npc", text = L("leave_npc") },
                    } },
                } },
            }
        end,
    }
end

--Opening the built Forge: what Giddlebrick does about this player.
--  access              nothing: the workshop is open;
--  locked              close the location again (the map shows the clock);
--  never pushed yet    the conversation, then the negotiation if they push;
--  pushed before       straight to the negotiation.
--close() closes the location (a Leave, or a talk that locked the Forge).
---@param host Panel|nil
---@param opts {backdrop: string|nil}|nil
---@param close fun()
function EotwForge.OnOpen(host, opts, close)
    if host == nil then
        return
    end
    m_host = host
    EotwForge.Fetch(function(ok, status)
        if mod.unloaded or not ok or type(status) ~= "table" or not status.built then
            return
        end
        if status.access then
            return
        end
        if (tonumber(status.remainingMs) or 0) > 0 then
            close()
            return
        end
        EotwForge.Approach(host, opts, close)
    end)
end

--Go to Giddlebrick (from OnOpen, or the workshop's Talk button): the
--conversation the first time, else straight to the negotiation.
function EotwForge.Approach(host, opts, close)
    local status = EotwForge.Status()
    if host == nil or not host.valid or status == nil or status.access then
        return
    end
    local heroes = EotwLeads.HeroesAtHome()
    if #heroes == 0 then
        return
    end

    local function AfterTalk(forge)
        if mod.unloaded then
            return
        end
        if forge == nil then
            return
        end
        if forge.access then
            EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.access_banner"),
                cond(forge.bonus, T("great_forge.workshop.access_bonus_subtitle"), T("great_forge.workshop.access_subtitle")))
        else
            EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.refused_banner"),
                T("great_forge.workshop.refused_subtitle", { time = EotwForge.FormatTime((tonumber(forge.remainingMs) or 0) / 1000) }))
            close()
        end
    end

    if (tonumber(status.tries) or 0) > 0 then
        EotwForge.ShowNegotiation(host, opts, AfterTalk)
        return
    end
    local pick = heroes[math.random(#heroes)]
    EotwAnalytics.Track("eotw_forge_intro", { heroid = pick.hero.heroid, standing = status.standing })
    EotwLeads.PlayConversation(host, Opening(status.standing), pick.hero.heroid, function(result)
        if mod.unloaded then
            return
        end
        if result == "push" then
            EotwForge.ShowNegotiation(host, opts, AfterTalk)
        else
            close()
        end
    end)
end

--- the treasures ------------------------------------------------------------------

--A treasure's project goal: the number its "Project Goal" text starts with.
---@param item equipment
---@return integer|nil
local function ProjectGoal(item)
    local text = item:try_get("projectGoal", "")
    local n = type(text) == "string" and tonumber(string.match(text, "^%s*(%d+)")) or nil
    if n == nil or n < 1 then
        return nil
    end
    return math.floor(n)
end

--What the Forge can craft (David 2026-11-15: Gold echelon 1 treasures for
--now, prerequisites ignored; imbuements left out): { {itemid, item, goal}, ... } by name.
function EotwForge.Treasures()
    local result = {}
    local gear = dmhub.GetTable("tbl_Gear") or {}
    for itemid, item in unhidden_pairs(gear) do
        local goal = ProjectGoal(item)
        --an imbuement (imbueTargetType) improves another treasure: it is
        --not an item a hero can be handed, so it is not offered.
        if goal ~= nil
            and item:try_get("imbueTargetType") == nil
            and item:try_get("hiddenFromPlayers", false) ~= true
            and (tonumber(item:try_get("echelon", 1)) or 1) == 1
            and (tonumber(item:try_get("implementation", 1)) or 1) >= gui.ImplementationStatus.Gold then
            result[#result+1] = { itemid = itemid, item = item, goal = goal }
        end
    end
    table.sort(result, function(a, b)
        return tostring(a.item.name) < tostring(b.item.name)
    end)
    return result
end

--The codex's own item card as a tooltip, or just the name.
local function ItemTooltip(element, item, name)
    local tooltipFn = rawget(_G, "CreateItemTooltip")
    if item ~= nil and tooltipFn ~= nil then
        local ok = pcall(function()
            element.tooltip = tooltipFn(item, { valign = "center", width = 360 }, nil)
        end)
        if ok then
            return
        end
    end
    gui.Tooltip(name)(element)
end

local function ItemIcon(item, size)
    local icon = item ~= nil and item:try_get("iconid", "") or ""
    return gui.Panel{
        interactable = false,
        width = size,
        height = size,
        valign = "center",
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        borderWidth = 1,
        borderColor = GOLD,
        cornerRadius = 4,
        gui.Panel{
            interactable = false,
            width = "84%",
            height = "84%",
            halign = "center",
            valign = "center",
            bgimage = cond(icon ~= "", icon, "phosphor/sword-fill.png"),
            bgcolor = "white",
        },
    }
end

--The characteristic a hero rolls on a treasure: its best of the ones the
--treasure lists (any of the five when it lists none).
local function CraftCharacteristic(tok, item)
    local allowed = item ~= nil and item:try_get("projectRollCharacteristic") or nil
    local best, bestValue = nil, nil
    for attrid, _ in pairs(creature.attributesInfo or {}) do
        if type(allowed) ~= "table" or next(allowed) == nil or allowed[attrid] then
            local value = EotwDowntime.UI.CharacteristicValue(tok, attrid)
            if bestValue == nil or value > bestValue then
                best, bestValue = attrid, value
            end
        end
    end
    return best, bestValue or 0
end

--- the treasure picker --------------------------------------------------------------

--Choose what a hero crafts: every treasure on offer, with a search box and
--the item's card on hover. onStart(itemid, item, goal) when one is picked.
function EotwForge.ShowPicker(host, heroid, onStart)
    if host == nil or not host.valid then
        return
    end
    local tok = dmhub.GetCharacterById(heroid)
    local heroName = (tok ~= nil and tok.name) or T("great_forge.workshop.your_hero")
    local treasures = EotwForge.Treasures()
    local state = { filter = "", selected = nil }
    local dlg = nil
    local grid = nil
    local startButton = nil
    local Render

    local function Close()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end

    local function Card(entry)
        local item = entry.item
        local name = tostring(item.name)
        local selected = state.selected ~= nil and state.selected.itemid == entry.itemid
        return gui.Panel{
            classes = { "forgeTreasure", cond(selected, "selected", nil) },
            width = 196,
            height = 74,
            hmargin = 4,
            vmargin = 4,
            flow = "horizontal",
            hpad = 8,
            borderBox = true,
            bgimage = "panels/square.png",
            linger = function(element)
                ItemTooltip(element, item, name)
            end,
            press = function(element)
                audio.FireSoundEvent("Mouse.Click")
                state.selected = entry
                Render()
            end,
            ItemIcon(item, 44),
            gui.Panel{
                interactable = false,
                width = "100%-54",
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 8,
                gui.Label{
                    interactable = false,
                    text = name,
                    fontSize = 15,
                    bold = true,
                    color = TEXT,
                    width = "100%",
                    height = "auto",
                    textWrap = true,
                },
                gui.Label{
                    interactable = false,
                    text = T("great_forge.workshop.goal", { goal = entry.goal }),
                    fontSize = 13,
                    color = DIM,
                    width = "100%",
                    height = "auto",
                },
            },
        }
    end

    Render = function()
        if grid == nil or not grid.valid then
            return
        end
        local filter = string.lower(state.filter or "")
        local cards = {}
        for _, entry in ipairs(treasures) do
            if filter == "" or string.find(string.lower(tostring(entry.item.name)), filter, 1, true) ~= nil then
                cards[#cards+1] = Card(entry)
            end
        end
        if #cards == 0 then
            cards[1] = gui.Label{ text = T("great_forge.workshop.picker_none"), fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        end
        grid.children = cards
        if startButton ~= nil and startButton.valid then
            local entry = state.selected
            startButton:SetClass("collapsed", entry == nil)
            if entry ~= nil then
                startButton.text = T("great_forge.workshop.start_button", { item = tostring(entry.item.name) })
            end
        end
    end

    dlg = gui.Panel{
        floating = true,
        width = 900,
        height = 820,
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
        styles = {
            Styles.Default,
            { selectors = { "forgeTreasure" }, bgcolor = "#1d1913", cornerRadius = 6, borderWidth = 1, borderColor = "#3a3125" },
            { selectors = { "forgeTreasure", "hover" }, borderColor = GOLD, brightness = 1.15 },
            { selectors = { "forgeTreasure", "selected" }, borderColor = AMBER, borderWidth = 2, bgcolor = "#2a2216" },
        },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Close()
        end,
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            gui.Panel{
                width = 30,
                height = 30,
                valign = "center",
                rmargin = 10,
                bgimage = "phosphor/flame-fill.png",
                bgcolor = GOLD,
            },
            gui.Label{
                text = T("great_forge.workshop.picker_title", { hero = heroName }),
                fontSize = 28,
                bold = true,
                color = TEXT,
                width = "100%-80",
                height = "auto",
                valign = "center",
            },
            gui.Panel{
                width = 22,
                height = 22,
                halign = "right",
                valign = "top",
                bgimage = "phosphor/x-bold.png",
                bgcolor = DIM,
                linger = gui.Tooltip(T("great_forge.workshop.close_tooltip")),
                press = function()
                    audio.FireSoundEvent("UI.WindowClose")
                    Close()
                end,
            },
        },
        gui.Label{
            text = T("great_forge.workshop.picker_intro"),
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            vmargin = 6,
        },
        gui.Input{
            width = 320,
            height = 32,
            fontSize = 16,
            halign = "left",
            bmargin = 8,
            placeholderText = T("great_forge.workshop.search"),
            editlag = 0.2,
            edit = function(element)
                state.filter = element.text
                Render()
            end,
        },
        gui.Panel{
            width = "100%",
            height = "100%-200",
            flow = "horizontal",
            wrap = true,
            vscroll = true,
            valign = "top",
            create = function(element)
                grid = element
                Render()
            end,
        },
        gui.Button{
            classes = { "collapsed" },
            halign = "center",
            valign = "bottom",
            tmargin = 10,
            text = "",
            fontSize = 20,
            width = 420,
            height = 46,
            create = function(element)
                startButton = element
                Render()
            end,
            click = function()
                local entry = state.selected
                if entry == nil then
                    return
                end
                audio.FireSoundEvent("Mouse.Click")
                Close()
                onStart(entry.itemid, entry.item, entry.goal)
            end,
        },
    }
    host:AddChild(dlg)
end

--- crafting -------------------------------------------------------------------------

local function Request(action, args, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        onDone(false, T("great_forge.workshop.offline"))
        return
    end
    conn:Request{
        action = action,
        args = args,
        success = function(result)
            onDone(true, result)
        end,
        error = function(message)
            onDone(false, message)
        end,
    }
end

--Start a hero on a treasure.
function EotwForge.StartCraft(heroid, itemid, item, goal, onDone)
    Request("forge-start-craft", { heroid = heroid, itemid = itemid, itemName = tostring(item.name), goal = goal }, function(ok, result)
        if ok then
            SetStatus(result.forge)
            EotwAnalytics.Track("eotw_forge_start", { heroid = heroid, itemid = itemid, item = tostring(item.name), goal = goal })
        end
        onDone(ok, result)
    end)
end

--One roll on a hero's treasure: a Downtime Activity, or a breakthrough's
--free follow-up (breakthroughOf = its rollid). Kept until the City has it,
--as every project roll is (EotwDowntime.ResumePending sends it on).
function EotwForge.Roll(heroid, breakthroughOf, onDone)
    local tok = dmhub.GetCharacterById(heroid)
    local craft = EotwForge.Craft(heroid)
    if tok == nil or craft == nil then
        onDone(false, T("great_forge.workshop.not_ready"))
        return
    end
    local item = (dmhub.GetTable("tbl_Gear") or {})[craft.itemid]
    local attrid, bonus = CraftCharacteristic(tok, item)
    local roll = {
        rollid = dmhub.GenerateGuid(),
        projectid = "forge-craft",
        heroid = heroid,
        characteristic = attrid or "",
        skill = "",
        breakthroughOf = breakthroughOf,
    }
    dmhub.Roll{
        roll = string.format("2d10%+d", bonus),
        description = T("great_forge.workshop.roll_description", { hero = tok.name or "", item = craft.itemName or "" }),
        complete = function(rollInfo)
            if mod.unloaded then
                return
            end
            roll.natural = math.floor(tonumber(rollInfo.naturalRoll) or 0)
            roll.total = math.floor(tonumber(rollInfo.total) or 0)
            EotwDowntime.UI.SaveMine("eotw:pendingProjectRoll", roll)
            Request("project-roll", roll, function(ok, result)
                EotwDowntime.UI.SaveMine("eotw:pendingProjectRoll", nil)
                if ok then
                    EotwRoster.SetListedDowntime(heroid, result.downtime)
                    EotwAnalytics.Track("eotw_forge_roll", { heroid = heroid, itemid = craft.itemid, natural = roll.natural,
                        total = roll.total, completed = result.completed, breakthrough = result.breakthrough })
                end
                EotwForge.Fetch(function()
                    onDone(ok, result)
                end)
            end)
        end,
    }
end

--Collect a finished treasure: the City hands it over once, then it goes in
--the hero's pack and the hero is saved.
function EotwForge.Collect(heroid, onDone)
    local tok = dmhub.GetCharacterById(heroid)
    if tok == nil then
        onDone(false, T("great_forge.workshop.not_ready"))
        return
    end
    Request("forge-claim", { heroid = heroid }, function(ok, result)
        if not ok then
            onDone(false, result)
            return
        end
        if result.already or type(result.itemid) ~= "string" then
            EotwForge.Fetch(function()
                onDone(true, result)
            end)
            return
        end
        tok:ModifyProperties{
            description = "Collected a treasure from the Great Forge",
            undoable = false,
            execute = function()
                tok.properties:GiveItem(result.itemid, 1)
            end,
        }
        EotwAnalytics.Track("eotw_forge_collect", { heroid = heroid, itemid = result.itemid, item = result.itemName })
        --let the property write land before the export, as EotwMarket does.
        dmhub.Schedule(0.3, function()
            if mod.unloaded then
                return
            end
            EotwRoster.PushHero(heroid, function(pushed, message)
                EotwForge.Fetch(function()
                    onDone(true, result)
                end)
            end)
        end)
    end)
end

--A hero's craft as last fetched, or nil.
function EotwForge.Craft(heroid)
    local status = EotwForge.Status()
    for _, craft in ipairs((status ~= nil and status.crafts) or {}) do
        if craft.heroid == heroid and not craft.delivered then
            return craft
        end
    end
    return nil
end

--- the workshop panel ---------------------------------------------------------------

local function Portrait(tok)
    return EotwDowntime.UI.Portrait(tok, 44, 58)
end

local function Bar(points, goal)
    local fraction = goal > 0 and math.min(1, points / goal) or 0
    return gui.Panel{
        interactable = false,
        width = "100%",
        height = 18,
        tmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = "#0b0907",
        cornerRadius = 4,
        borderWidth = 1,
        borderColor = "#3a3125",
        gui.Panel{
            interactable = false,
            floating = true,
            halign = "left",
            width = string.format("%.1f%%", fraction * 100),
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = GOLD,
            cornerRadius = 4,
        },
        gui.Label{
            interactable = false,
            floating = true,
            text = T("great_forge.workshop.progress", { points = points, goal = goal }),
            fontSize = 13,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "center",
        },
    }
end

--One hero's row: who, what they are crafting and how far along, and the
--button for what they can do next.
local function HeroRow(host, hero, busy, setBusy)
    local tok = dmhub.GetCharacterById(hero.heroid)
    local name = (tok ~= nil and tok.name) or (hero.summary or {}).name or T("great_forge.workshop.your_hero")
    local away = EotwRoster.AwayHeroes()[hero.heroid] ~= nil
    local craft = EotwForge.Craft(hero.heroid)
    local downtime = EotwRoster.GetDowntime(hero.heroid) or 0
    local gear = dmhub.GetTable("tbl_Gear") or {}
    local item = craft ~= nil and gear[craft.itemid] or nil

    local status
    local buttonText = nil
    local blocked = nil
    local action = nil
    if tok == nil then
        status = T("great_forge.workshop.loading_hero")
    elseif away then
        status = T("great_forge.workshop.away")
        blocked = status
    end
    if craft == nil then
        status = status or T("great_forge.workshop.idle")
        buttonText = T("great_forge.workshop.choose_button")
        action = function()
            EotwForge.ShowPicker(host, hero.heroid, function(itemid, picked, goal)
                setBusy(true)
                EotwForge.StartCraft(hero.heroid, itemid, picked, goal, function(ok, result)
                    setBusy(false)
                    if not ok then
                        EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.error_banner"), tostring(result))
                    elseif type(result.craft) == "table" and result.craft.completed then
                        EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.done_banner", { item = tostring(picked.name) }),
                            T("great_forge.workshop.done_bonus_subtitle", { hero = name }))
                    end
                end)
            end)
        end
    elseif craft.completed then
        status = T("great_forge.workshop.finished", { item = craft.itemName })
        buttonText = T("great_forge.workshop.collect_button")
        action = function()
            setBusy(true)
            EotwForge.Collect(hero.heroid, function(ok, result)
                setBusy(false)
                if ok then
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.collected_banner", { item = craft.itemName }),
                        T("great_forge.workshop.collected_subtitle", { hero = name }))
                else
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.error_banner"), tostring(result))
                end
            end)
        end
    else
        status = status or T("great_forge.workshop.crafting", { item = craft.itemName })
        local free = (craft.open or {})[1]
        buttonText = cond(free ~= nil, T("great_forge.workshop.free_roll_button"), T("great_forge.workshop.work_button"))
        if free == nil and downtime < 1 then
            blocked = blocked or T("great_forge.workshop.no_downtime")
        end
        action = function()
            setBusy(true)
            EotwForge.Roll(hero.heroid, free ~= nil and free.rollid or nil, function(ok, result)
                setBusy(false)
                if not ok then
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.error_banner"), tostring(result))
                elseif result.completed then
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.done_banner", { item = craft.itemName }),
                        T("great_forge.workshop.done_subtitle", { hero = name }))
                elseif result.breakthrough then
                    EotwDowntime.UI.ShowBanner(host, T("great_forge.workshop.breakthrough_banner"),
                        T("great_forge.workshop.breakthrough_subtitle", { hero = name }))
                end
            end)
        end
    end
    if busy then
        blocked = blocked or T("great_forge.workshop.busy")
    end

    local details = {
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
        gui.Label{
            text = status,
            fontSize = 13,
            color = cond(craft ~= nil, AMBER, DIM),
            width = "100%",
            height = "auto",
        },
    }
    if craft ~= nil then
        details[#details+1] = Bar(tonumber(craft.points) or 0, tonumber(craft.goal) or 0)
    end

    local itemBox = nil
    if craft ~= nil then
        itemBox = gui.Panel{
            width = 50,
            height = 50,
            valign = "center",
            lmargin = 8,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            linger = function(element)
                ItemTooltip(element, item, craft.itemName or "")
            end,
            ItemIcon(item, 50),
        }
    end

    return gui.Panel{
        width = "100%",
        height = 84,
        flow = "horizontal",
        vmargin = 2,
        hpad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#1d1913",
        cornerRadius = 6,
        opacity = cond(away, 0.5, 1),
        children = {
            Portrait(tok),
            itemBox or gui.Panel{ width = 0, height = 0 },
            gui.Panel{
                width = "100%-260",
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 10,
                children = details,
            },
            gui.Button{
                text = buttonText or "",
                fontSize = 15,
                width = 130,
                height = 34,
                halign = "right",
                valign = "center",
                opacity = cond(blocked == nil and action ~= nil, 1, 0.4),
                linger = function(element)
                    if blocked ~= nil then
                        gui.Tooltip(blocked)(element)
                    end
                end,
                click = function()
                    if blocked ~= nil or action == nil then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    action()
                end,
            },
        },
    }
end

--The built Forge's card: Giddlebrick's answer so far, then each hero's
--treasure. host mounts dialogs; opts.backdrop is the negotiation's
--backdrop; close() closes the location.
---@param host Panel|nil
---@param opts {backdrop: string|nil}|nil
---@param close fun()
---@return Panel
function EotwForge.Panel(host, opts, close)
    local body = nil
    local busy = false
    local Rebuild

    local function SetBusy(value)
        busy = value
        Rebuild()
    end

    local function Note(text)
        return gui.Label{ text = text, fontSize = 16, italics = true, color = DIM, width = "100%", height = "auto", halign = "center", textAlignment = "center", vmargin = 20 }
    end

    Rebuild = function()
        if body == nil or not body.valid then
            return
        end
        local status = EotwForge.Status()
        local rows = {}
        if status == nil then
            rows[1] = Note(T("great_forge.workshop.loading"))
        elseif not status.access then
            local remaining = (tonumber(status.remainingMs) or 0) / 1000
            local lockEnds = EotwForge.LockedUntil()
            if lockEnds ~= nil then
                rows[1] = Note(T("great_forge.workshop.locked", { time = EotwForge.FormatTime(lockEnds - dmhub.Time()) }))
            elseif #EotwLeads.HeroesAtHome() == 0 then
                rows[1] = Note(T("great_forge.workshop.no_heroes_home"))
            else
                rows[1] = Note(T("great_forge.workshop.no_access"))
                rows[2] = gui.Button{
                    text = T("great_forge.workshop.talk_button"),
                    fontSize = 18,
                    width = 260,
                    height = 44,
                    halign = "center",
                    click = function()
                        audio.FireSoundEvent("Mouse.Click")
                        EotwForge.Approach(host, opts, close)
                    end,
                }
            end
            if remaining > 0 and lockEnds == nil then
                EotwForge.Fetch(nil)
            end
        else
            if status.bonus then
                rows[#rows+1] = gui.Label{ text = T("great_forge.workshop.bonus"), fontSize = 15, bold = true, color = GREEN, width = "100%", height = "auto", bmargin = 6 }
            end
            for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
                rows[#rows+1] = HeroRow(host, hero, busy, SetBusy)
            end
            if EotwRoster.GetHeroes() == nil then
                rows[#rows+1] = Note(T("great_forge.workshop.loading"))
            elseif #rows == 0 then
                rows[1] = Note(T("great_forge.workshop.no_heroes"))
            end
        end
        body.children = rows
    end

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        data = { seen = -1, lockShown = nil },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwForge.revision + EotwRoster.revision * 100000
            --a lock's text counts down too.
            local lockEnds = EotwForge.Status() ~= nil and EotwForge.LockedUntil() or nil
            local lockShown = lockEnds ~= nil and math.ceil(lockEnds - dmhub.Time()) or nil
            if element.data.seen ~= rev or element.data.lockShown ~= lockShown then
                element.data.seen = rev
                element.data.lockShown = lockShown
                Rebuild()
            end
        end,
        gui.Label{
            text = T("great_forge.workshop.title"),
            fontSize = 26,
            bold = true,
            color = TEXT,
            width = "auto",
            height = "auto",
        },
        gui.Label{
            text = T("great_forge.workshop.intro"),
            fontSize = 15,
            italics = true,
            color = DIM,
            width = "100%",
            height = "auto",
            vmargin = 8,
        },
        gui.Panel{
            width = "100%",
            height = "100%-120",
            flow = "vertical",
            vscroll = true,
            rpad = 12,
            borderBox = true,
            create = function(element)
                body = element
                Rebuild()
            end,
        },
    }
end

--- dev commands -------------------------------------------------------------------

local DEV_USAGE = [[Usage: /eotwforge <command> (open the town first)
  state      print your standing, access, lock and crafts at the Great Forge
  reset      forget your Forge standing and crafts (city admins)
  talk       play the negotiation now (needs a hero at home; reports its result)
  parse      parse the negotiation script and print its warnings]]

pcall(function()
    Commands.RegisterMacro{
        name = "eotwforge",
        summary = "dev: the built Great Forge (Giddlebrick, crafting)",
        doc = DEV_USAGE,
        command = function(str)
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then
                print("EotW town: /eotwforge is a developer command")
                return
            end
            local verb = string.lower(string.match(str or "", "^%s*(%S+)") or "")
            if verb == "state" then
                EotwForge.Fetch(function(ok, s)
                    if not ok then
                        printf("EotW town (dev): forge-status failed: %s", tostring(s))
                        return
                    end
                    printf("EotW town (dev): built %s, standing %s, access %s, bonus %s, last interest %s, tries %s, locked for %ds",
                        tostring(s.built), tostring(s.standing), tostring(s.access), tostring(s.bonus), tostring(s.lastInterest),
                        tostring(s.tries), math.floor((tonumber(s.remainingMs) or 0) / 1000))
                    for _, craft in ipairs(s.crafts or {}) do
                        printf("  %s: %s %s/%s%s%s", tostring(craft.heroid), tostring(craft.itemName), tostring(craft.points),
                            tostring(craft.goal), cond(craft.completed, " done", ""), cond(craft.delivered, " collected", ""))
                    end
                end)
            elseif verb == "reset" then
                Request("dev-reset-forge", {}, function(ok, result)
                    if ok then
                        SetStatus(result.forge)
                        printf("EotW town (dev): Great Forge forgotten (%s rows)", tostring(result.deleted))
                    else
                        printf("EotW town (dev): reset refused: %s", tostring(result))
                    end
                end)
            elseif verb == "talk" then
                local host = m_host
                if host == nil or not host.valid then
                    print("EotW town (dev): open the built Great Forge once first")
                    return
                end
                EotwForge.Fetch(function(ok)
                    if ok then
                        EotwForge.ShowNegotiation(host, nil, function(forge)
                            printf("EotW town (dev): talk over; access %s", tostring(forge ~= nil and forge.access))
                        end)
                    end
                end)
            elseif verb == "parse" then
                m_beat = nil
                local beat = EotwForge.Beat()
                if beat ~= nil then
                    printf("EotW town (dev): %s: %d traits, %d arguments, %d offers", beat.name, #beat.traits, #beat.arguments, #beat.offers)
                end
            else
                print(DEV_USAGE)
            end
        end,
    }
end)
