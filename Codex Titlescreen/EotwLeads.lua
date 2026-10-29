local mod = dmhub.GetModLoading()

--Encounter of the Week Leads: rumours heard at the Blue Fish Inn that open
--new projects. Design: EncounterOfTheWeek/EncounterOfTheWeek.md, "Leads".
--
--  * Each respite at the inn earns ONE carouse. While the player has leads
--    left to learn, the inn card offers Carouse: one hero spends the evening
--    in the common room and makes a Presence test.
--  * Tier 1 or 2 learns nothing. Tier 3 learns the next lead, told in a
--    conversation with whoever knows it (the old Elementalist, for the
--    Arcane Market).
--  * A lead opens a project (EotwDowntime.PROJECTS, `lead`). The Arcane
--    Market's is Find the Arcane Market; completing it puts the market on
--    the player's town map (EotwRoster.MarketUnlocked).
--
--The City (cloudflare-game-server src/city-core.ts, "Leads") holds the
--learned leads and which respite's carouse is still open, so a carouse can
--be taken once per respite on any machine.

EotwLeads = {}

local T = UIText.T

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"

--The characteristic and skills of a carouse (a Presence test).
EotwLeads.CAROUSE_CHARACTERISTIC = "prs"
EotwLeads.CAROUSE_SKILLS = { "Brag", "Flirt", "Gamble", "Music", "Perform", "Rumors" }

--Dev (/eotwleads crit): the next carouse counts as a natural 20.
EotwLeads.forceCritical = false

--The leads, in the order a carouse learns them (the City's CITY_LEADS).
EotwLeads.ORDER = { "arcane-market" }

--Each lead: what it is called, the project it opens, and the conversation
--that tells it. conversation(heroName) returns { {who = "npc"|"hero", text}, ... }.
EotwLeads.LEADS = {
    ["arcane-market"] = {
        id = "arcane-market",
        title = T("leads.arcane_market.title"),
        project = "find-arcane-market",
        npc = {
            name = T("leads.arcane_market.npc_name"),
            title = T("leads.arcane_market.npc_title"),
            --the bestiary's Rival Elementalist art.
            portrait = "3492c3c2-871e-44c5-abc1-1cde5a7fb097",
        },
        conversation = function(heroName)
            return {
                { who = "npc", text = T("leads.arcane_market.line1_npc") },
                { who = "hero", text = T("leads.arcane_market.line2_hero") },
                { who = "npc", text = T("leads.arcane_market.line3_npc") },
                { who = "hero", text = T("leads.arcane_market.line4_hero") },
                { who = "npc", text = T("leads.arcane_market.line5_npc") },
                { who = "npc", text = T("leads.arcane_market.line6_npc", { hero = heroName }) },
                { who = "hero", text = T("leads.arcane_market.line7_hero") },
            }
        end,
    },
}

local function Bump()
    EotwDowntime.revision = EotwDowntime.revision + 1
end

--The leads this player has not learned yet, in order.
function EotwLeads.LeadsLeft()
    local known = EotwRoster.LearnedLeads()
    local result = {}
    for _, id in ipairs(EotwLeads.ORDER) do
        if not known[id] then
            result[#result+1] = id
        end
    end
    return result
end

--Can the player carouse now? (A respite's carouse is open and a lead is
--left to learn; the City decides, see EotwRoster.CarouseRespite.)
function EotwLeads.CanCarouse()
    return EotwRoster.CarouseRespite() ~= nil and #EotwLeads.LeadsLeft() > 0
end

--- recording a carouse ----------------------------------------------------------

--A carouse whose dice have landed but the City has not yet recorded:
--{ [userid] = { respiteid, heroid, natural, total } }.
setting{
    id = "eotw:pendingCarouse",
    default = "",
    storage = "preference",
}

--Send a rolled carouse to the City. The pending entry stays until the City
--answers, so the dice result is never lost or re-rolled. onDone(ok, resultOrMessage).
local function SendCarouse(entry, onDone)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        onDone(false, T("leads.carouse.offline"))
        return
    end
    conn:Request{
        action = "carouse",
        args = entry,
        success = function(result)
            EotwDowntime.UI.SaveMine("eotw:pendingCarouse", nil)
            local tier = nil
            pcall(function() tier = EotwDowntime.TestTier(entry.natural, entry.total) end)
            local leads = 0
            for _, _ in pairs(result.leads or {}) do
                leads = leads + 1
            end
            EotwAnalytics.Track("eotw_carouse", {
                heroid = entry.heroid,
                natural = entry.natural,
                total = entry.total,
                tier = tier,
                leads = leads,
            })
            EotwRoster.SetListedLeads(result.leads, result.carouse)
            --the lead's project can be started now: list it.
            EotwDowntime.RefreshProjects()
            Bump()
            onDone(true, result)
        end,
        error = function(message)
            --refused (no carouse open, the hero is away...): it will never
            --be taken, so let it go and re-read what the City says.
            EotwDowntime.UI.SaveMine("eotw:pendingCarouse", nil)
            EotwRoster.Refresh()
            Bump()
            onDone(false, message)
        end,
    }
end

--Record a carouse left over from a dropped connection. Called when the town
--connects (EotwDowntime.ResumePending).
function EotwLeads.ResumePending()
    local _, entry = EotwDowntime.UI.LoadMine("eotw:pendingCarouse")
    if type(entry) == "table" and type(entry.respiteid) == "string" and type(entry.natural) == "number" then
        SendCarouse(entry, function(ok, result)
            if ok then
                printf("EotW town: recorded a carouse left over from last time (tier %s)", tostring(result.tier))
            end
        end)
    end
end

--The carouse roll's bonus and a description of it.
local function CarouseBonus(tok, skill)
    local attrid = EotwLeads.CAROUSE_CHARACTERISTIC
    local value = EotwDowntime.UI.CharacteristicValue(tok, attrid)
    local info = creature.attributesInfo[attrid]
    local parts = { "2d10", string.format("%+d %s", value, info ~= nil and info.description or attrid) }
    local bonus = value
    if skill ~= nil and skill ~= "" then
        bonus = bonus + 2
        parts[#parts+1] = string.format("+2 %s", skill)
    end
    return bonus, table.concat(parts, " ")
end

--The carouse skills this hero is trained in.
local function CarouseSkills(tok)
    return EotwDowntime.UI.TrainedSkills(tok, { skills = EotwLeads.CAROUSE_SKILLS })
end

--The heroes who could carouse now: at home and loaded, in roster order.
local function Carousers()
    local result = {}
    local away = EotwRoster.AwayHeroes()
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local tok = dmhub.GetCharacterById(hero.heroid)
        if tok ~= nil and away[hero.heroid] == nil then
            result[#result+1] = { hero = hero, tok = tok }
        end
    end
    return result
end

--- the conversation ----------------------------------------------------------------

--The speakers' figures, the montage stage's sizes (as the inn's reveal).
local FIGURE_WIDTH = 230
local FIGURE_HEIGHT = 300
local FIGURE_FADE = 0.15
--Characters a second as a line types out.
local TYPE_CPS = 45

--A speaker's figure over the dialog box: an image id (the NPC) or a hero's
--off-token portrait, cropped to the figure's shape with a soft foot.
local function Figure(image, tok, side)
    return gui.Panel{
        classes = { "leadFigure" },
        width = FIGURE_WIDTH,
        height = FIGURE_HEIGHT,
        hmargin = 40,
        halign = side,
        valign = "bottom",
        bgimage = "panels/square.png",
        bgcolor = "#00000000",
        --set on the panel itself: edgeFade from a class rule is not applied.
        edgeFade = FIGURE_FADE,
        interactable = false,
        create = function(element)
            local portrait = image
            if tok ~= nil then
                pcall(function() portrait = tok.offTokenPortrait end)
            end
            if portrait == nil or portrait == "" then
                return
            end
            element.bgimage = portrait
            element.selfStyle.bgcolor = "white"
            if tok ~= nil then
                local rect = nil
                pcall(function() rect = tok:GetPortraitRectForAspect(FIGURE_WIDTH / FIGURE_HEIGHT * (1 - FIGURE_FADE), portrait) end)
                if rect ~= nil then
                    local y1 = math.max(FIGURE_FADE, rect.y1 + (rect.y2 - rect.y1) * FIGURE_FADE)
                    rect = { x1 = rect.x1, y1 = y1, x2 = rect.x2, y2 = rect.y2 }
                end
                element.selfStyle.imageRect = rect
            end
        end,
    }
end

--Play a lead's conversation between its NPC and the hero who heard it, in
--a dialog box like the montage's. A click finishes the line being typed,
--then moves on; Escape skips to the end. onDone() when it is over.
function EotwLeads.ShowConversation(host, leadid, heroid, onDone)
    local lead = EotwLeads.LEADS[leadid]
    local tok = dmhub.GetCharacterById(heroid)
    if lead == nil then
        if onDone ~= nil then
            onDone()
        end
        return
    end
    local heroName = (tok ~= nil and tok.name) or T("leads.hero_fallback")
    local lines = lead.conversation(heroName)
    local index = 1
    local typed = 0
    local lineStart = dmhub.Time()
    local closing = false

    local npcFigure = Figure(lead.npc.portrait, nil, "left")
    local heroFigure = Figure(nil, tok, "right")
    local speakerLabel = gui.Label{ classes = { "leadSpeaker" }, text = "", interactable = false }
    local textLabel = gui.Label{ classes = { "leadText" }, text = "", interactable = false }
    local prompt = gui.Panel{
        classes = { "leadPrompt", "collapsed" },
        floating = true,
        width = 18,
        height = 18,
        halign = "right",
        valign = "bottom",
        bgimage = "phosphor/caret-down-fill.png",
        interactable = false,
        thinkTime = 0.6,
        think = function(element)
            element:SetClass("dimmed", not element:HasClass("dimmed"))
        end,
    }

    --show whose line it is: their name, their figure lit, the other dimmed.
    local function ShowSpeaker()
        local line = lines[index]
        local npcSpeaks = line.who == "npc"
        speakerLabel.text = cond(npcSpeaks, T("leads.conversation.npc_speaker", { name = lead.npc.name, title = lead.npc.title }), heroName)
        npcFigure:SetClass("listening", not npcSpeaks)
        heroFigure:SetClass("listening", npcSpeaks)
        textLabel.text = ""
        typed = 0
        lineStart = dmhub.Time()
        prompt:SetClass("collapsed", true)
    end

    local overlay
    local stage

    local function Close()
        if closing then
            return
        end
        closing = true
        stage:SetClassTree("leadOff", true)
        dmhub.Schedule(0.4, function()
            if overlay ~= nil and overlay.valid then
                overlay:DestroySelf()
            end
            if not mod.unloaded and onDone ~= nil then
                onDone()
            end
        end)
    end

    local function Advance()
        if closing then
            return
        end
        local line = lines[index]
        if typed < #line.text then
            --finish the line first.
            typed = #line.text
            textLabel.text = line.text
            prompt:SetClass("collapsed", false)
            return
        end
        audio.FireSoundEvent("Mouse.Click")
        if index >= #lines then
            Close()
            return
        end
        index = index + 1
        ShowSpeaker()
    end

    stage = gui.Panel{
        classes = { "leadStage" },
        floating = true,
        width = 1100,
        height = "auto",
        halign = "center",
        valign = "bottom",
        bmargin = 30,
        flow = "vertical",
        interactable = false,
        gui.Panel{
            width = "100%",
            height = FIGURE_HEIGHT,
            flow = "none",
            interactable = false,
            npcFigure,
            heroFigure,
        },
        gui.Panel{
            classes = { "leadBox" },
            width = "100%",
            height = 160,
            bgimage = "panels/square.png",
            pad = 18,
            borderBox = true,
            flow = "vertical",
            interactable = false,
            speakerLabel,
            textLabel,
            prompt,
        },
    }

    overlay = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        --dims the inn behind, and catches every click.
        bgimage = "panels/square.png",
        bgcolor = "#000000a0",
        styles = {
            {
                selectors = { "leadOff" },
                opacity = 0,
                transitionTime = 0.35,
            },
            {
                selectors = { "leadStage", "leadOff" },
                y = 30,
                transitionTime = 0.35,
                easing = "easeOutCubic",
            },
            {
                selectors = { "leadFigure", "listening" },
                brightness = 0.45,
                transitionTime = 0.25,
            },
            --the montage stage's dialog box, opaque (as the inn's reveal).
            {
                selectors = { "leadBox" },
                bgcolor = "#06080cff",
                border = 2,
                borderColor = "#ffffff60",
                cornerRadius = 8,
            },
            {
                selectors = { "leadSpeaker" },
                fontSize = 16,
                bold = true,
                color = "#ffd66b",
                width = "100%",
                height = "auto",
                textAlignment = "left",
                bmargin = 4,
            },
            {
                selectors = { "leadText" },
                fontSize = 19,
                color = "#ffffff",
                width = "100%",
                height = "auto",
                textAlignment = "left",
            },
            {
                selectors = { "leadPrompt" },
                bgcolor = "#ffd66b",
            },
            {
                selectors = { "leadPrompt", "dimmed" },
                opacity = 0.25,
            },
        },
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            Close()
        end,
        press = function(element)
            Advance()
        end,
        thinkTime = 0.02,
        think = function(element)
            if closing then
                return
            end
            local line = lines[index]
            if typed < #line.text then
                typed = math.min(#line.text, math.floor((dmhub.Time() - lineStart) * TYPE_CPS))
                textLabel.text = string.sub(line.text, 1, typed)
                if typed >= #line.text then
                    prompt:SetClass("collapsed", false)
                end
            end
        end,
        stage,
    }

    host:AddChild(overlay)
    ShowSpeaker()
    --born faded and low, then rises in.
    stage:SetClassTreeImmediate("leadOff", true)
    dmhub.Schedule(0.03, function()
        if not mod.unloaded and stage ~= nil and stage.valid then
            stage:SetClassTree("leadOff", false)
        end
    end)
end

--After a lead's conversation: offer to start the project it opens, once
--the City has listed it (it may take a moment after the carouse).
local function OfferLeadProject(host, leadid, tries)
    local lead = EotwLeads.LEADS[leadid]
    if lead == nil or mod.unloaded or host == nil or not host.valid then
        return
    end
    if EotwDowntime.GetProject(lead.project) == nil then
        if (tries or 0) < 10 then
            EotwDowntime.RefreshProjects()
            dmhub.Schedule(0.5, function()
                OfferLeadProject(host, leadid, (tries or 0) + 1)
            end)
        end
        return
    end
    if EotwDowntime.CanStart(lead.project) then
        EotwDowntime.ShowStartProjectDialog(host, lead.project)
    end
end

--- the carouse dialog ----------------------------------------------------------------

--What each tier of a carouse means, shown in the tier table.
local CAROUSE_TIERS = {
    T("leads.carouse.tier1"),
    T("leads.carouse.tier2"),
    T("leads.carouse.tier3"),
}

--The Draw Steel tier glyphs (DrawSteelGlyphs font): 11 or lower, 12-16, 17+.
local TIER_GLYPHS = { "!", "@", "#" }

--A power roll's tier table, the look of the game's roll dialog: one row per
--tier with its glyph; the tier the dice show is filled gold while they
--tumble, and flashes when the roll lands. Returns the panel and a controller:
--  ctl.WatchDice(rolls, bonus)  follow these tumbling dice (rollInfo.rolls)
--  ctl.Finish(tier)             light the final tier and flash it
--  ctl.Clear()                  no tier lit
local function TierTable(texts)
    local s = { dice = nil, faces = {}, bonus = 0 }
    local rows = {}
    local ctl = {}

    local function Highlight(tier, finish)
        for i, row in ipairs(rows) do
            if row.valid then
                row:SetClassTree("highlight", i == tier)
                if finish and i == tier then
                    row:PulseClass("flash")
                end
            end
        end
    end

    for i, text in ipairs(texts) do
        rows[i] = gui.Panel{
            classes = { "eotwTierRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = "panels/square.png",
            vpad = 4,
            hpad = 12,
            borderBox = true,
            tmargin = 2,
            gui.Label{
                classes = { "eotwTierGlyph" },
                fontFace = "DrawSteelGlyphs",
                text = TIER_GLYPHS[i] or tostring(i),
                fontSize = 34,
                width = 56,
                height = 24,
                valign = "center",
                textAlignment = "left",
            },
            gui.Label{
                classes = { "eotwTierText" },
                text = text,
                fontSize = 16,
                width = "100%-60",
                height = "auto",
                valign = "center",
            },
        }
    end

    local tbl = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 10,
        styles = {
            { selectors = { "eotwTierRow" }, bgcolor = "#1d1913", cornerRadius = 4 },
            { selectors = { "eotwTierRow", "highlight" }, bgcolor = GOLD },
            { selectors = { "eotwTierRow", "flash" }, brightness = 3, transitionTime = 1 },
            { selectors = { "eotwTierGlyph" }, color = TEXT },
            { selectors = { "eotwTierText" }, color = TEXT },
            --full black on the gold, as the game's roll dialog.
            { selectors = { "eotwTierGlyph", "highlight" }, color = "#000000" },
            { selectors = { "eotwTierText", "highlight" }, color = "#000000" },
        },
        --each die reports the face it shows as it tumbles (chat.DiceEvents).
        diceface = function(element, diceguid, num, timeRemaining)
            if s.dice == nil then
                return
            end
            s.faces[diceguid] = num
            local natural = 0
            for _, roll in ipairs(s.dice) do
                local face = s.faces[roll.guid]
                if face == nil then
                    return
                end
                natural = natural + face
            end
            Highlight(EotwDowntime.TestTier(natural, natural + s.bonus), false)
        end,
        children = rows,
    }

    function ctl.WatchDice(rolls, bonus)
        s.dice = {}
        s.faces = {}
        s.bonus = bonus or 0
        for _, roll in ipairs(rolls or {}) do
            if not roll.dropped then
                s.dice[#s.dice+1] = roll
                pcall(function() chat.DiceEvents(roll.guid):Listen(tbl) end)
            end
        end
    end
    function ctl.Finish(tier)
        s.dice = nil
        Highlight(tier, true)
    end
    function ctl.Clear()
        s.dice = nil
        Highlight(nil, false)
    end
    return tbl, ctl
end

--Carouse: pick a hero, then click or throw the dice for their Presence test.
--Tier 3 learns a lead, told in its conversation; then the project it opens
--is offered.
function EotwLeads.ShowCarouseDialog(host)
    local state = {
        heroid = nil,
        skill = nil,
        --"choose" -> "rolling" -> "done"
        phase = "choose",
        natural = 0,
        total = 0,
        tier = 0,
        leadid = nil,
        message = "",
    }
    local respiteid = EotwRoster.CarouseRespite()

    local dlg = nil
    local body = nil
    local resultBody = nil
    local hintLabel = nil
    local finishRow = nil
    local cage = nil
    local armedSignature = nil

    --built once, between the choices and the result, so the highlight
    --survives the re-renders while the dice tumble.
    local tierTable, tierCtl = TierTable(CAROUSE_TIERS)

    local function SelectHero(c)
        if c == nil then
            state.heroid = nil
            return
        end
        state.heroid = c.hero.heroid
        state.skill = CarouseSkills(c.tok)[1]
    end

    --the default carouser: the best bonus.
    local function ChooseDefault()
        local best, bestBonus = nil, nil
        for _, c in ipairs(Carousers()) do
            local bonus = CarouseBonus(c.tok, CarouseSkills(c.tok)[1])
            if bestBonus == nil or bonus > bestBonus then
                best, bestBonus = c, bonus
            end
        end
        return best
    end

    local function Disarm()
        armedSignature = nil
        if cage ~= nil and cage.valid then
            pcall(function() cage:CancelDicePreviewRoll() end)
        end
    end

    local function CloseDialog()
        if state.phase == "rolling" then
            return
        end
        Disarm()
        if dlg ~= nil and dlg.valid then
            dlg:DestroySelf()
        end
    end

    local Render

    local function ArmDice(signature)
        Disarm()
        local tok = state.heroid ~= nil and dmhub.GetCharacterById(state.heroid) or nil
        if cage == nil or not cage.valid or tok == nil or respiteid == nil then
            return
        end
        armedSignature = signature
        local bonus = CarouseBonus(tok, state.skill)
        local heroid = state.heroid
        dmhub.Roll{
            roll = string.format("2d10%+d", bonus),
            description = T("leads.carouse.roll_name"),
            preview = true,
            previewPanel = cage,
            cancel = function()
                if mod.unloaded then
                    return
                end
                armedSignature = nil
                tierCtl.Clear()
                Render()
            end,
            begin = function(rollInfo)
                if mod.unloaded then
                    return
                end
                armedSignature = nil
                state.phase = "rolling"
                state.message = ""
                --the tier table follows the dice as they tumble.
                tierCtl.WatchDice(rollInfo.rolls, bonus)
                Render()
            end,
            complete = function(rollInfo)
                if mod.unloaded then
                    return
                end
                local natural = math.floor(tonumber(rollInfo.naturalRoll) or 0)
                local total = math.floor(tonumber(rollInfo.total) or 0)
                --dev: /eotwleads crit makes this a natural 20.
                if EotwLeads.forceCritical then
                    EotwLeads.forceCritical = false
                    printf("EotW town (dev): this carouse counts as a natural 20 (the dice said %d)", natural)
                    natural = 20
                    total = 20 + bonus
                end
                local entry = { respiteid = respiteid, heroid = heroid, natural = natural, total = total }
                --kept until the City has it: a crash now must not buy a re-roll.
                EotwDowntime.UI.SaveMine("eotw:pendingCarouse", entry)
                state.natural = natural
                state.total = total
                state.tier = EotwDowntime.TestTier(natural, total)
                tierCtl.Finish(state.tier)
                Render()
                SendCarouse(entry, function(ok, result)
                    if mod.unloaded then
                        return
                    end
                    state.phase = "done"
                    if not ok then
                        state.message = tostring(result)
                        state.tier = 0
                        tierCtl.Clear()
                    else
                        state.tier = tonumber(result.tier) or state.tier
                        state.leadid = result.leadid
                        if state.leadid ~= nil then
                            local lead = EotwLeads.LEADS[state.leadid]
                            EotwDowntime.UI.ShowBanner(host, T("leads.carouse.new_lead_banner"), lead ~= nil and lead.title or "", "Notify.BigBanner_Pos")
                        end
                    end
                    Render()
                end)
            end,
        }
    end

    Render = function()
        if body == nil or not body.valid then
            return
        end
        local carousers = Carousers()
        local chosen = nil
        for _, c in ipairs(carousers) do
            if c.hero.heroid == state.heroid then
                chosen = c
            end
        end
        if chosen == nil and state.phase == "choose" then
            SelectHero(ChooseDefault())
            for _, c in ipairs(carousers) do
                if c.hero.heroid == state.heroid then
                    chosen = c
                end
            end
        end
        local name = chosen ~= nil and tostring(chosen.tok.name or T("leads.carouse.your_hero")) or T("leads.carouse.your_hero")

        local children = {}
        children[#children+1] = gui.Label{
            text = T("leads.carouse.who_heading"),
            fontSize = 15,
            color = DIM,
            width = "100%",
            height = "auto",
            tmargin = 14,
            bmargin = 4,
        }
        local chips = {}
        for _, c in ipairs(carousers) do
            local selected = state.heroid == c.hero.heroid
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
                press = function()
                    if state.phase ~= "choose" then
                        return
                    end
                    audio.FireSoundEvent("Mouse.Click")
                    SelectHero(c)
                    Render()
                end,
                EotwDowntime.UI.Portrait(c.tok, 24, 32),
                gui.Label{
                    text = T("leads.carouse.hero_choice", { hero = tostring(c.tok.name or T("leads.hero_fallback")), bonus = string.format("%+d", EotwDowntime.UI.CharacteristicValue(c.tok, EotwLeads.CAROUSE_CHARACTERISTIC)) }),
                    fontSize = 16,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    hmargin = 6,
                    interactable = false,
                },
            }
        end
        if #chips == 0 then
            chips[1] = gui.Label{
                text = T("leads.carouse.nobody_home"),
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
            local trained = CarouseSkills(chosen.tok)
            local skillOptions = { { id = "", text = T("leads.carouse.no_skill") } }
            for _, skillName in ipairs(trained) do
                skillOptions[#skillOptions+1] = { id = skillName, text = T("leads.carouse.skill_choice", { skill = skillName }) }
            end
            children[#children+1] = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                tmargin = 12,
                gui.Label{
                    text = T("leads.carouse.skill_heading"),
                    fontSize = 15,
                    color = DIM,
                    width = 100,
                    height = "auto",
                    valign = "center",
                },
                gui.Dropdown{
                    width = 240,
                    height = 34,
                    fontSize = 16,
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
                    text = table.concat(EotwLeads.CAROUSE_SKILLS, ", "),
                    fontSize = 13,
                    italics = true,
                    color = DIM,
                    width = 300,
                    height = "auto",
                    valign = "center",
                    lmargin = 10,
                },
            }
            local _, formula = CarouseBonus(chosen.tok, state.skill)
            children[#children+1] = gui.Label{
                text = formula,
                fontSize = 17,
                color = TEXT,
                width = "100%",
                height = "auto",
                tmargin = 12,
            }
        end

        --the result.
        local resultText, resultDetail = "", ""
        if state.phase == "rolling" and state.total > 0 then
            resultText = tostring(state.total)
            resultDetail = T("leads.carouse.result_natural", { natural = state.natural })
        elseif state.phase == "done" and state.tier > 0 then
            resultText = T("leads.carouse.result_tier", { tier = state.tier })
            if state.leadid ~= nil then
                local lead = EotwLeads.LEADS[state.leadid]
                resultDetail = T("leads.carouse.result_lead", { total = state.total, natural = state.natural, hero = name, lead = lead ~= nil and lead.title or state.leadid })
            elseif state.tier == 3 then
                resultDetail = T("leads.carouse.result_tier3_nothing_left", { total = state.total, natural = state.natural })
            elseif state.tier == 2 then
                resultDetail = T("leads.carouse.result_tier2", { total = state.total, natural = state.natural, hero = name })
            else
                resultDetail = T("leads.carouse.result_tier1", { total = state.total, natural = state.natural, hero = name })
            end
        end
        body.children = children

        --under the tier table: the result and any error.
        children = {}
        children[#children+1] = gui.Panel{
            width = "100%",
            height = 100,
            flow = "vertical",
            tmargin = 8,
            gui.Label{
                text = resultText,
                fontSize = 40,
                bold = true,
                color = cond(state.leadid ~= nil, AMBER, GOLD),
                width = "auto",
                height = "auto",
                halign = "center",
            },
            gui.Label{
                text = resultDetail,
                fontSize = 16,
                color = DIM,
                width = "90%",
                height = "auto",
                halign = "center",
                textAlignment = "center",
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
        if resultBody ~= nil and resultBody.valid then
            resultBody.children = children
        end

        --the bottom: the dice while choosing; afterwards Listen (a lead) or Close.
        local canRoll = state.phase == "choose" and chosen ~= nil and respiteid ~= nil
        local hint = ""
        if state.phase == "choose" then
            if respiteid == nil then
                hint = T("leads.carouse.hint_no_respite")
            elseif chosen == nil then
                hint = T("leads.carouse.nobody_home")
            else
                hint = T("leads.carouse.hint_roll")
            end
        end
        if hintLabel ~= nil and hintLabel.valid then
            hintLabel.text = hint
        end
        if finishRow ~= nil and finishRow.valid then
            finishRow:SetClass("collapsed", state.phase ~= "done")
            local listen = finishRow:Get("eotwLeadListen")
            if listen ~= nil then
                listen:SetClass("collapsed", state.leadid == nil)
            end
        end
        if cage ~= nil and cage.valid then
            cage:SetClass("hidden", state.phase == "done")
        end
        if canRoll then
            local signature = tostring(state.heroid) .. "|" .. tostring(state.skill)
            if signature ~= armedSignature then
                ArmDice(signature)
            end
        elseif armedSignature ~= nil and state.phase == "choose" then
            Disarm()
        end
    end

    dlg = gui.Panel{
        floating = true,
        width = 860,
        height = 700,
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
            CloseDialog()
        end,
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev and state.phase == "choose" then
                element.data.seen = rev
                Render()
            end
        end,
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
                    bgimage = "phosphor/beer-stein-fill.png",
                    bgcolor = GOLD,
                },
                gui.Label{
                    text = T("leads.carouse.title"),
                    fontSize = 28,
                    bold = true,
                    color = TEXT,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
            },
            gui.Label{
                text = T("leads.carouse.intro"),
                fontSize = 16,
                italics = true,
                color = DIM,
                width = "100%",
                height = "auto",
                bmargin = 4,
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    body = element
                end,
            },
            tierTable,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",
                create = function(element)
                    resultBody = element
                end,
            },
        },
        gui.Panel{
            floating = true,
            halign = "center",
            valign = "bottom",
            width = "100%",
            height = "auto",
            flow = "vertical",
            gui.Label{
                text = "",
                fontSize = 16,
                italics = true,
                color = AMBER,
                width = "100%",
                height = 40,
                textAlignment = "center",
                create = function(element)
                    hintLabel = element
                end,
            },
            --the dice, resting until clicked or thrown (as the project roll dialog).
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
                    pcall(function() element.dicePreviewScreenBounds = true end)
                    Render()
                end,
                destroy = function(element)
                    ---@cast element DicePreview
                    pcall(function() element:CancelDicePreviewRoll() end)
                    element:SetAsDicePreviewPanel(false)
                end,
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
            --once the dice have spoken: Listen (a lead was learned) and Close.
            gui.Panel{
                classes = { "collapsed" },
                floating = true,
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                valign = "bottom",
                bmargin = 34,
                create = function(element)
                    finishRow = element
                    Render()
                end,
                gui.Button{
                    id = "eotwLeadListen",
                    classes = { "collapsed" },
                    text = T("leads.carouse.listen_button"),
                    fontSize = 24,
                    width = 260,
                    height = 54,
                    hmargin = 8,
                    click = function()
                        local leadid = state.leadid
                        local heroid = state.heroid
                        CloseDialog()
                        if leadid ~= nil and heroid ~= nil then
                            EotwLeads.ShowConversation(host, leadid, heroid, function()
                                OfferLeadProject(host, leadid, 0)
                            end)
                        end
                    end,
                },
                gui.Button{
                    text = T("leads.carouse.close_button"),
                    fontSize = 24,
                    width = 200,
                    height = 54,
                    hmargin = 8,
                    click = function()
                        CloseDialog()
                    end,
                },
            },
        },
        --close: an X in the top-right corner (not while the dice are in the air).
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
            linger = gui.Tooltip(T("leads.carouse.close_tooltip")),
            press = function()
                audio.FireSoundEvent("UI.WindowClose")
                CloseDialog()
            end,
        },
    }
    host:AddChild(dlg)
end

--- the inn card's section --------------------------------------------------------

--The panel the inn mounts dialogs on, for the dev `talk` command.
---@type Panel|nil
local m_innHost = nil

--The inn card's leads section, under Take a Respite: Carouse while a
--respite's carouse is open, and Start Project for each lead learned whose
--project is not yet under way or done. Empty (no height) otherwise.
function EotwLeads.InnLeadsPanel(host)
    m_innHost = host
    local function Row(icon, text, buttonText, tooltip, onClick)
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            tmargin = 8,
            pad = 8,
            borderBox = true,
            bgimage = "panels/square.png",
            bgcolor = "#1d1913",
            borderWidth = 1,
            borderColor = "#d9b56a55",
            cornerRadius = 6,
            gui.Panel{
                width = 22,
                height = 22,
                valign = "center",
                rmargin = 8,
                bgimage = icon,
                bgcolor = AMBER,
            },
            gui.Label{
                text = text,
                fontSize = 15,
                color = TEXT,
                width = "100%-270",
                height = "auto",
                valign = "center",
            },
            gui.Button{
                text = buttonText,
                fontSize = 17,
                width = 220,
                height = 38,
                halign = "right",
                valign = "center",
                linger = gui.Tooltip(tooltip),
                click = function()
                    audio.FireSoundEvent("Mouse.Click")
                    onClick()
                end,
            },
        }
    end

    local function Rebuild(element)
        local children = {}
        if EotwLeads.CanCarouse() then
            children[#children+1] = Row("phosphor/beer-stein-fill.png",
                T("leads.inn.carouse_row"),
                T("leads.inn.carouse_button"), T("leads.inn.carouse_tooltip"),
                function()
                    EotwLeads.ShowCarouseDialog(host)
                end)
        end
        local known = EotwRoster.LearnedLeads()
        for _, leadid in ipairs(EotwLeads.ORDER) do
            local lead = EotwLeads.LEADS[leadid]
            if known[leadid] and lead ~= nil and EotwDowntime.CanStart(lead.project) then
                local project = EotwDowntime.PROJECTS[lead.project]
                children[#children+1] = Row(project ~= nil and project.icon or "phosphor/hammer-fill.png",
                    T("leads.inn.project_row", { lead = lead.title, npc = lead.npc.name }),
                    T("leads.inn.project_button"), T("leads.inn.project_tooltip", { project = project ~= nil and project.title or T("leads.inn.project_fallback") }),
                    function()
                        EotwDowntime.ShowStartProjectDialog(host, lead.project)
                    end)
            end
        end
        element.children = children
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            local rev = EotwDowntime.revision + EotwRoster.revision * 100000
            if element.data.seen ~= rev then
                element.data.seen = rev
                Rebuild(element)
            end
        end,
        create = function(element)
            Rebuild(element)
        end,
    }
end

--- dev commands -----------------------------------------------------------------

local DEV_USAGE = [[Usage: /eotwleads <command> (open the town first)
  crit       the next carouse counts as a natural 20 (learns a lead)
  reset      forget your leads and carouses; the latest respite's carouse opens again (city admins)
  talk       replay the Arcane Market conversation (needs a hero at home)
  state      print the leads learned, the open carouse and the market
To restart the hunt: /eotwleads reset, then /eotwdowntime resetproject find-arcane-market.]]

pcall(function()
    Commands.RegisterMacro{
        name = "eotwleads",
        summary = "dev: carousing and leads at the Blue Fish Inn",
        doc = DEV_USAGE,
        command = function(str)
            if not (dmhub.GetSettingValue("dev") or dmhub.isAdminAccount) then
                print("EotW town: /eotwleads is a developer command")
                return
            end
            local verb = string.lower(string.match(str or "", "^%s*(%S+)") or "")
            if verb == "crit" then
                EotwLeads.forceCritical = not EotwLeads.forceCritical
                printf("EotW town (dev): next carouse is %s", cond(EotwLeads.forceCritical, "a natural 20", "rolled normally"))
            elseif verb == "reset" then
                local conn = EotwRoster.Connection()
                if conn == nil or not conn.connected then
                    print("EotW town (dev): open the town first (no city connection)")
                    return
                end
                conn:Request{
                    action = "dev-reset-leads",
                    args = {},
                    success = function(result)
                        EotwRoster.SetListedLeads(result.leads, result.carouse)
                        EotwRoster.Refresh()
                        printf("EotW town (dev): leads forgotten (%s rows); open carouse: %s", tostring(result.deleted), tostring(result.carouse))
                    end,
                    error = function(message)
                        printf("EotW town (dev): reset refused: %s", tostring(message))
                    end,
                }
            elseif verb == "talk" then
                local heroes = Carousers()
                local host = m_innHost
                if host == nil or not host.valid then
                    print("EotW town (dev): open the Blue Fish Inn first")
                    return
                end
                if #heroes == 0 then
                    print("EotW town (dev): no hero at home to listen")
                    return
                end
                EotwLeads.ShowConversation(host, "arcane-market", heroes[1].hero.heroid, nil)
            elseif verb == "state" then
                local known = {}
                for id, _ in pairs(EotwRoster.LearnedLeads()) do
                    known[#known+1] = id
                end
                printf("EotW town (dev): leads learned: %s; open carouse: %s; can carouse: %s; market found: %s",
                    cond(#known > 0, table.concat(known, ", "), "none"), tostring(EotwRoster.CarouseRespite()),
                    tostring(EotwLeads.CanCarouse()), tostring(EotwRoster.MarketUnlocked()))
            else
                print(DEV_USAGE)
            end
        end,
    }
end)
