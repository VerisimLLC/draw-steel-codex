local mod = dmhub.GetModLoading()

--Encounter of the Week: the Training Grounds, where heroes Level up. The town
--builds them together (Build the Training Grounds, EotwDowntime.lua); once
--built, a respite only banks XP (EotwDowntime.RespiteBanksXp) and a hero with
--enough XP comes here to take the Level. Design:
--EncounterOfTheWeek/EncounterOfTheWeek.md, "The Training Grounds".
--
--The Level up itself is EotwRoster.LevelUpHero (one Level per press, saved to
--the City, the Builder opened on its Level up page); this file is the card
--that lists the player's heroes and offers it. All text is in
--EotwTextTrainingGrounds.lua.

EotwTrainingGrounds = {}

local T = UIText.T
local TP = UIText.Plural

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local AMBER = "#ffd38a"
local RED = "#ff8888"
local GREEN = "#7fbf5f"

--Text an OPTIONAL entry may leave empty: nil when it is.
local function Optional(text)
    if text == nil or text == "" then
        return nil
    end
    return text
end

--One of these lines at random, skipping empty ones; nil when all are empty.
local function PickVariant(lines)
    local options = {}
    for _, text in ipairs(lines) do
        if Optional(text) ~= nil then
            options[#options+1] = text
        end
    end
    if #options == 0 then
        return nil
    end
    return options[math.random(#options)]
end

--Is this machine connected to the town?
local function Connected()
    local conn = EotwRoster.Connection()
    return conn ~= nil and conn.connected
end

--How many more Levels the hero's XP would pay for after the next one,
--capped by the top Level.
local function ExtraLevels(state)
    local per = math.max(1, state.xpPerLevel)
    local levels = math.floor(state.xpIntoLevel / per) - 1
    local room = (GameSystem.numLevels or 10) - state.level - 1
    return math.max(0, math.min(levels, room))
end

--The hero's XP bar: a gold fill of xpIntoLevel / xpPerLevel, green when full.
local function XpBar(state)
    local fraction = 0
    if state.xpPerLevel > 0 then
        fraction = math.max(0, math.min(1, state.xpIntoLevel / state.xpPerLevel))
    end
    if state.reason == "maxlevel" then
        fraction = 1
    end
    return gui.Panel{
        width = "100%",
        height = 10,
        vmargin = 4,
        bgimage = "panels/square.png",
        bgcolor = "#2c261c",
        cornerRadius = 4,
        flow = "none",
        interactable = false,
        gui.Panel{
            width = string.format("%.1f%%", fraction * 100),
            height = "100%",
            halign = "left",
            bgimage = "panels/square.png",
            bgcolor = cond(fraction >= 1, GREEN, GOLD),
            cornerRadius = 4,
            interactable = false,
        },
    }
end

--One hero's row: portrait, name and Level, the XP bar and what it means, and
--on the right Level Up, Finish Your Level, or why neither.
--  levelUp(hero, state)  run when its button is pressed
local function HeroRow(hero, levelUp)
    local tok = dmhub.GetCharacterById(hero.heroid)
    local summary = hero.summary or {}
    local name = (tok ~= nil and tok.name) or summary.name or ""
    local state = EotwRoster.LevelUpState(hero.heroid)
    local nextLevel = state.level + 1

    --the line under the bar.
    local xpLine
    if state.reason == "maxlevel" then
        xpLine = T("traininggrounds.reason.maxlevel")
    elseif state.ready then
        xpLine = T("traininggrounds.row.ready", { level = string.format("%d", nextLevel) })
        local extra = ExtraLevels(state)
        if extra > 0 then
            xpLine = xpLine .. "  " .. TP("traininggrounds.row.more_levels", extra)
        end
    else
        xpLine = T("traininggrounds.row.xp", {
            xp = string.format("%d", math.max(0, state.xpIntoLevel)),
            per = string.format("%d", state.xpPerLevel),
            level = string.format("%d", nextLevel),
        })
    end

    --Victories a respite has yet to turn into XP.
    local bankedLine = nil
    if tok ~= nil and state.reason ~= "maxlevel" then
        local victories = 0
        pcall(function() victories = tok.properties:GetVictories() or 0 end)
        if victories > 0 then
            bankedLine = Optional(TP("traininggrounds.reason.banked", victories))
        end
    end

    --the right side: a button, or the reason there is none.
    local right
    local finishing = (not state.ready) and state.choicesLeft > 0 and state.reason ~= "away" and state.reason ~= "notloaded" and state.reason ~= "notonroster"
    if (state.ready or finishing) and Connected() then
        local tooltip
        if state.ready then
            tooltip = T("traininggrounds.level_up_tooltip", { hero = name, level = string.format("%d", nextLevel) })
        else
            tooltip = T("traininggrounds.finish_tooltip", { hero = name })
        end
        right = gui.Button{
            classes = { cond(state.ready, "eotwLevelUp", "eotwFinishLevel") },
            text = cond(state.ready, T("traininggrounds.level_up_button"), T("traininggrounds.finish_button")),
            fontSize = 17,
            width = 200,
            height = 40,
            valign = "center",
            linger = gui.Tooltip(tooltip),
            click = function()
                audio.FireSoundEvent("Mouse.Click")
                levelUp(hero, state)
            end,
        }
    else
        local reasonText = ""
        if state.reason == "xp" then
            reasonText = T("traininggrounds.reason.xp", {
                need = string.format("%d", math.max(0, state.xpPerLevel - state.xpIntoLevel)),
                level = string.format("%d", nextLevel),
            })
        elseif state.reason == "away" then
            reasonText = T("traininggrounds.reason.away")
        elseif state.reason == "notloaded" or state.reason == "notonroster" then
            reasonText = T("traininggrounds.reason.notloaded")
        elseif not Connected() then
            reasonText = T("traininggrounds.error.not_connected")
        end
        right = gui.Label{
            text = reasonText,
            fontSize = 14,
            italics = true,
            color = DIM,
            width = 200,
            height = "auto",
            valign = "center",
            textAlignment = "right",
        }
    end

    local level = state.level
    local levelText = ""
    if level > 0 then
        levelText = T("eotw.hero.level", { level = string.format("%d", level) })
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        minHeight = 76,
        flow = "horizontal",
        vmargin = 3,
        hpad = 10,
        vpad = 8,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = cond(state.ready, "#262013", "#1d1913"),
        borderWidth = cond(state.ready, 1, 0),
        borderColor = GOLD,
        cornerRadius = 6,
        opacity = cond(state.reason == "away", 0.55, 1),
        EotwDowntime.UI.Portrait(tok, 45, 60),
        gui.Panel{
            width = "100%-275",
            height = "auto",
            flow = "vertical",
            valign = "center",
            lmargin = 12,
            rmargin = 8,
            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                gui.Label{
                    text = name,
                    fontSize = 19,
                    bold = true,
                    color = TEXT,
                    width = "auto",
                    maxWidth = 360,
                    height = "auto",
                    textWrap = false,
                    minFontSize = 12,
                    valign = "center",
                },
                gui.Label{
                    text = levelText,
                    fontSize = 15,
                    color = GOLD,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 10,
                },
            },
            XpBar(state),
            gui.Label{
                text = xpLine,
                fontSize = 14,
                color = cond(state.ready, AMBER, DIM),
                width = "100%",
                height = "auto",
            },
            gui.Label{
                classes = { cond(bankedLine == nil, "collapsed", "eotwBanked") },
                text = bankedLine or "",
                fontSize = 13,
                italics = true,
                color = DIM,
                width = "100%",
                height = "auto",
            },
        },
        right,
    }
end

--The Training Grounds' card: the player's heroes, each with their XP toward
--the next Level and a Level Up button when they have enough. host is the
--panel the Builder mounts on (the town screen).
function EotwTrainingGrounds.Panel(host)
    local listPanel = nil
    local statusLabel = nil
    --a Level up is open in the Builder: the rows wait for it to close.
    local busy = false

    local Rebuild

    local function SetStatus(text, color)
        if statusLabel ~= nil and statusLabel.valid then
            statusLabel.text = text or ""
            statusLabel.selfStyle.color = color or TEXT
        end
    end

    local function LevelUp(hero, state)
        if busy then
            return
        end
        if not Connected() then
            SetStatus(T("traininggrounds.error.not_connected"), RED)
            return
        end
        local tok = dmhub.GetCharacterById(hero.heroid)
        local name = tok ~= nil and tok.name or ""
        local newLevel = cond(state.ready, state.level + 1, state.level)
        SetStatus("")
        busy = true
        local ok = EotwRoster.LevelUpHero{
            heroid = hero.heroid,
            host = EncounterOfTheWeek.TownScreen() or host,
            onDone = function(finished)
                busy = false
                if mod.unloaded then
                    return
                end
                EotwAnalytics.Track("eotw_training_grounds_level", { heroid = hero.heroid, level = newLevel, finished = finished })
                if finished then
                    local banner = T("traininggrounds.done.finished", { hero = name, level = string.format("%d", newLevel) })
                    SetStatus(banner, AMBER)
                    EotwDowntime.UI.ShowBanner(host, banner, PickVariant({ T("traininggrounds.cheer_1"), T("traininggrounds.cheer_2"), T("traininggrounds.cheer_3") }) or "")
                else
                    SetStatus(T("traininggrounds.done.unfinished", { hero = name }), DIM)
                end
                Rebuild()
            end,
        }
        if not ok then
            busy = false
            SetStatus(T("traininggrounds.error.could_not_open"), RED)
            Rebuild()
        end
    end

    Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local heroes = EotwRoster.GetHeroes()
        local rows = {}
        if heroes == nil then
            rows[1] = gui.Label{ text = T("traininggrounds.reason.notloaded"), fontSize = 16, italics = true, color = DIM, width = "auto", height = "auto", halign = "center", vmargin = 20 }
        else
            for _, hero in ipairs(heroes) do
                rows[#rows+1] = HeroRow(hero, LevelUp)
            end
            if #rows == 0 then
                rows[1] = gui.Label{ text = T("traininggrounds.empty"), fontSize = 16, italics = true, color = DIM, width = "100%", height = "auto", textAlignment = "center", vmargin = 20 }
            end
        end
        listPanel.children = rows
    end

    local greeting = PickVariant({ T("traininggrounds.greeting_1"), T("traininggrounds.greeting_2"), T("traininggrounds.greeting_3") })

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        data = { seen = -1 },
        thinkTime = 0.5,
        think = function(element)
            if busy then
                return
            end
            local rev = EotwRoster.revision + EotwDowntime.revision * 100000
            if element.data.seen ~= rev then
                element.data.seen = rev
                Rebuild()
            end
        end,
        gui.Label{
            text = T("traininggrounds.intro"),
            fontSize = 20,
            italics = true,
            color = TEXT,
            width = "100%",
            height = "auto",
            bmargin = 8,
        },
        gui.Label{
            classes = { cond(greeting == nil, "collapsed", "eotwGreeting") },
            text = greeting or "",
            fontSize = 16,
            italics = true,
            color = GOLD,
            width = "100%",
            height = "auto",
            bmargin = 8,
        },
        gui.Label{
            text = T("traininggrounds.explainer"),
            fontSize = 15,
            color = DIM,
            width = "100%",
            height = "auto",
            bmargin = 14,
        },
        gui.Label{
            text = string.upper(T("traininggrounds.heroes_heading")),
            fontSize = 15,
            bold = true,
            color = GOLD,
            width = "100%",
            height = "auto",
            bmargin = 6,
        },
        gui.Panel{
            width = "100%",
            height = "100%-300",
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
            fontSize = 16,
            color = TEXT,
            width = "100%",
            height = "auto",
            minHeight = 24,
            tmargin = 10,
            create = function(element)
                statusLabel = element
            end,
        },
    }
end
