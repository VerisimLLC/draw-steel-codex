local mod = dmhub.GetModLoading()

--Encounter of the Week: the Temple of Saint Llewellyn, once the town has restored it (the
--community project Restore the Temple, EotwDowntime.lua). Two lists:
--
--  * Your Fallen: this account's fallen heroes and how each can come back.
--    The owner begins a Rite of Return here (it needs a free roster slot);
--    undying heroes (Hakaan, Revenant, Vampire) awaken at the Graveyard
--    instead, and a doomed Hakaan is beyond return.
--  * Rites Under Way: every rite in town. Any player's living hero may spend a
--    Downtime Activity on one (2d10 + Presence or Reason, +2 if trained in
--    Religion). At the goal the hero rises; if the owner's roster is full the
--    rite waits, and the owner presses Rise once a slot is free.
--
--The City (cloudflare-game-server src/city-core.ts, "Rites of Return") keeps
--the rites and checks every rule; this file only shows them. A rite's goal is
--30 x the fallen hero's level, doubled for each earlier rite. Words live in
--EotwTextTemple.lua. Design: TEMPLE_BRIEF.md.

EotwTemple = {}

local T = UIText.T

local TEXT = "#efe4cc"
local DIM = "#c9bfa9"
local GOLD = "#d9b56a"
local RED = "#ff8888"

--How many rites show before "Show all".
local RITES_SHOWN = 5
--An average Downtime roll (2d10 + 2 or so), for "about N rolls".
local AVERAGE_ROLL = 13
--The characteristics a rite is worked with, and the skill that adds +2.
local RITE_CHARACTERISTICS = { "prs", "rea" }
local RITE_SKILL = "Religion"

local function Request(action, args, onDone, onFail)
    local conn = EotwRoster.Connection()
    if conn == nil or not conn.connected then
        onFail(T("temple.error.not_connected"))
        return
    end
    conn:Request{
        action = action,
        args = args,
        success = function(result)
            if mod.unloaded then
                return
            end
            onDone(result or {})
        end,
        error = function(message)
            if mod.unloaded then
                return
            end
            printf("EotW temple: %s failed: %s", action, tostring(message))
            onFail(tostring(message))
        end,
    }
end

local function Label(text, fontSize, color, extra)
    local args = {
        text = text,
        fontSize = fontSize or 16,
        color = color or TEXT,
        width = "100%",
        height = "auto",
        textWrap = true,
    }
    for key, value in pairs(extra or {}) do
        args[key] = value
    end
    return gui.Label(args)
end

local function Heading(text)
    return Label(text, 22, GOLD, { bold = true, tmargin = 14, bmargin = 6 })
end

--A portrait from a hero summary (an image id), or a plain silhouette.
local function Portrait(portrait, width, height)
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
    }
end

--"Goal 300 (level 5, about 11 rolls)", plus a line when an earlier rite doubled it.
local function GoalText(goal, level, priorRites)
    local rolls = math.max(1, math.ceil((tonumber(goal) or 0) / AVERAGE_ROLL))
    local text = T("temple.goal", { goal = tostring(goal), level = tostring(level or 1), rolls = tostring(rolls) })
    if (tonumber(priorRites) or 0) > 0 then
        text = text .. "\n" .. T("temple.goal_doubled", { count = tostring(priorRites) })
    end
    return text
end

--The best of Presence and Reason for this hero, and Religion if trained.
local function RiteRollFor(tok)
    local best, bestValue = RITE_CHARACTERISTICS[1], nil
    for _, attrid in ipairs(RITE_CHARACTERISTICS) do
        local value = 0
        pcall(function() value = tok.properties:GetAttribute(attrid):Modifier() end)
        if bestValue == nil or value > bestValue then
            best, bestValue = attrid, value
        end
    end
    local skill = ""
    pcall(function()
        for _, info in ipairs(Skill.SkillsInfo) do
            if info.name == RITE_SKILL and tok.properties:ProficientInSkill(info) then
                skill = RITE_SKILL
            end
        end
    end)
    return best, skill
end

--This account's heroes who can work on a rite now: living, in town, with a
--Downtime Activity to spend. { { id, text } } for a dropdown.
local function HelperOptions()
    local away = EotwRoster.AwayHeroes()
    local options = {}
    for _, hero in ipairs(EotwRoster.GetHeroes() or {}) do
        local downtime = EotwRoster.GetDowntime(hero.heroid)
        if downtime > 0 and away[hero.heroid] == nil and dmhub.GetCharacterById(hero.heroid) ~= nil then
            local name = type(hero.summary) == "table" and hero.summary.name or hero.heroid
            options[#options+1] = { id = hero.heroid, text = T("temple.helper_option", { name = tostring(name), downtime = tostring(downtime) }) }
        end
    end
    return options
end

---The Temple of Saint Llewellyn's panel, for its location scene.
---@param host Panel the town screen (dice and banners mount on it)
---@return Panel
function EotwTemple.Panel(host)
    --nil while loading; the City's list-rites answer after.
    local board = nil
    local errorText = nil
    local showAll = false
    --a roll is in flight: every roll button waits.
    local rolling = false
    --the hero chosen to help, per rite (owner|heroid -> helper heroid).
    local helperChoice = {}
    --the /city/projectsRev this board last read; a newer one re-reads it.
    local seenRev = nil
    local generation = 0
    local listPanel = nil
    local Rebuild

    local function Load()
        generation = generation + 1
        local asked = generation
        Request("list-rites", {}, function(result)
            if asked ~= generation then
                return
            end
            board = result
            errorText = nil
            Rebuild()
        end, function(message)
            errorText = message
            Rebuild()
        end)
    end

    local function Fail(message)
        errorText = message
        Rebuild()
    end

    local function BeginRite(heroid)
        Request("start-rite", { heroid = heroid }, function()
            audio.FireSoundEvent("Mouse.Click")
            Load()
        end, Fail)
    end

    local function Rise(heroid)
        Request("rise-hero", { heroid = heroid }, function()
            EotwRoster.Refresh()
            Load()
        end, Fail)
    end

    --breakthroughOf: a natural 19+ earns the same hero a free roll on the rite,
    --made at once.
    local function RollOnRite(rite, helperid, breakthroughOf)
        local tok = dmhub.GetCharacterById(helperid)
        if tok == nil or rolling then
            return
        end
        rolling = true
        local attrid, skill = RiteRollFor(tok)
        EotwDowntime.Roll{
            heroid = helperid,
            characteristic = attrid,
            skill = skill,
            breakthroughOf = breakthroughOf,
            rite = { owner = rite.owner, heroid = rite.heroid, title = T("temple.rite_title", { name = tostring(rite.name) }) },
            done = function(ok, result)
                rolling = false
                if not ok then
                    Fail(tostring(result))
                    return
                end
                if type(result) == "table" and result.risen == true then
                    EotwDowntime.ShowBanner(host, T("temple.banner.risen_title", { name = tostring(rite.name) }), T("temple.banner.risen_subtitle"))
                elseif type(result) == "table" and result.completed == true then
                    EotwDowntime.ShowBanner(host, T("temple.banner.complete_title", { name = tostring(rite.name) }), T("temple.banner.complete_subtitle"))
                elseif type(result) == "table" and result.breakthrough == true and type(result.rollid) == "string" then
                    EotwDowntime.ShowBanner(host, T("downtime.roll.breakthrough_banner"), T("temple.banner.breakthrough_subtitle"))
                    dmhub.Schedule(1.5, function()
                        if not mod.unloaded then
                            RollOnRite(rite, helperid, result.rollid)
                        end
                    end)
                end
                EotwRoster.Refresh()
                Load()
            end,
        }
    end

    --One of this account's fallen heroes, and how they can come back.
    local function FallenRow(entry)
        local summary = type(entry.summary) == "table" and entry.summary or {}
        local name = tostring(summary.name or T("temple.hero_fallback"))
        local status
        local action = nil
        local free = (tonumber(board.living) or 0) < (tonumber(board.slots) or EotwRoster.BASE_SLOTS)
        if entry.grave == "waiting" then
            status = T("temple.fallen.awaken_waiting", { clock = os.date("%I:%M %p", math.floor((tonumber(entry.readyAt) or 0) / 1000)) })
        elseif entry.grave == "ready" then
            status = T("temple.fallen.awaken_ready")
        elseif entry.grave == "beyond" then
            status = T("temple.fallen.beyond")
        elseif entry.riteActive then
            status = T("temple.fallen.rite_under_way")
        else
            local goalText = GoalText(entry.riteGoal, summary.level, entry.priorRites)
            if entry.grave == "fire" then
                goalText = T("temple.fallen.fire") .. "\n" .. goalText
            end
            if free then
                status = goalText
                action = gui.Button{
                    text = T("temple.fallen.begin_button"),
                    fontSize = 16,
                    width = 200,
                    height = 40,
                    halign = "right",
                    valign = "center",
                    data = { armed = false },
                    --two clicks: the first says what it commits to.
                    click = function(element)
                        if not element.data.armed then
                            element.data.armed = true
                            element.text = T("temple.fallen.begin_confirm")
                            element:ScheduleEvent("disarm", 4)
                            return
                        end
                        element.data.armed = false
                        BeginRite(entry.heroid)
                    end,
                    disarm = function(element)
                        element.data.armed = false
                        element.text = T("temple.fallen.begin_button")
                    end,
                }
            else
                status = goalText .. "\n" .. T("temple.fallen.no_slot")
            end
        end
        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "#2a2418cc",
            cornerRadius = 8,
            pad = 8,
            borderBox = true,
            vmargin = 3,
            Portrait(summary.portrait, 54, 72),
            gui.Panel{
                width = cond(action ~= nil, "100%-280", "100%-70"),
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 12,
                Label(name, 20, TEXT, { bold = true }),
                Label(EotwRoster.FormatDetails(summary.level, summary.ancestry, summary.className), 14, DIM),
                Label(status, 14, TEXT, { italics = true }),
            },
            action,
        }
    end

    --One rite under way: whose, how far, who helped, and a roll for one of
    --this account's heroes.
    local function RiteRow(rite)
        local mine = rite.owner == dmhub.loginUserid
        local name = tostring(rite.name or T("temple.hero_fallback"))
        local points = tonumber(rite.points) or 0
        local goal = math.max(1, tonumber(rite.goal) or 1)
        local percent = math.floor(points * 100 / goal)
        local helpers = {}
        for _, c in ipairs(rite.contributors or {}) do
            local who = tostring(c.heroName or "?")
            if type(c.playerName) == "string" and c.playerName ~= "" then
                who = T("temple.rite.contributor", { hero = who, player = c.playerName })
            end
            helpers[#helpers+1] = who
        end
        local lines = {
            T("temple.rite.progress", { points = tostring(points), goal = tostring(goal), percent = tostring(percent) }),
        }
        if #helpers > 0 then
            lines[#lines+1] = T("temple.rite.helpers", { names = table.concat(helpers, ", ") })
        end

        local controls
        if rite.waiting then
            if mine then
                controls = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    Label(T("temple.rite.waiting_mine"), 14, GOLD),
                    gui.Button{
                        text = T("temple.rite.rise_button"),
                        fontSize = 16,
                        width = 160,
                        height = 36,
                        click = function()
                            Rise(rite.heroid)
                        end,
                    },
                }
            else
                controls = Label(T("temple.rite.waiting_other"), 14, DIM)
            end
        else
            local options = HelperOptions()
            local key = rite.owner .. "|" .. rite.heroid
            if #options == 0 then
                controls = Label(T("temple.rite.no_helpers"), 14, DIM)
            else
                local chosen = helperChoice[key]
                local valid = false
                for _, option in ipairs(options) do
                    if option.id == chosen then
                        valid = true
                    end
                end
                if not valid then
                    chosen = options[1].id
                    helperChoice[key] = chosen
                end
                controls = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "horizontal",
                    tmargin = 4,
                    gui.Dropdown{
                        width = 300,
                        height = 34,
                        fontSize = 15,
                        styles = ThemeEngine.GetStyles(),
                        options = options,
                        idChosen = chosen,
                        change = function(element)
                            ---@cast element Dropdown
                            helperChoice[key] = element.idChosen
                        end,
                    },
                    gui.Button{
                        text = T("temple.rite.roll_button"),
                        fontSize = 16,
                        width = 200,
                        height = 34,
                        lmargin = 8,
                        click = function()
                            RollOnRite(rite, helperChoice[key])
                        end,
                    },
                }
            end
        end

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = cond(mine, "#2a2418cc", "#ffffff0a"),
            cornerRadius = 8,
            pad = 8,
            borderBox = true,
            vmargin = 3,
            Portrait(rite.portrait, 54, 72),
            gui.Panel{
                width = "100%-70",
                height = "auto",
                flow = "vertical",
                valign = "center",
                lmargin = 12,
                Label(cond(mine, T("temple.rite.name_yours", { name = name }), T("temple.rite.name_of", { name = name })), 20, TEXT, { bold = true }),
                Label(EotwRoster.FormatDetails(rite.level, rite.ancestry, rite.className), 14, DIM),
                Label(table.concat(lines, "\n"), 14, TEXT),
                controls,
            },
        }
    end

    Rebuild = function()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local rows = {}
        if errorText ~= nil then
            rows[#rows+1] = Label(errorText, 15, RED)
        end
        if board == nil then
            rows[#rows+1] = Label(T("temple.loading"), 16, DIM, { halign = "center" })
            listPanel.children = rows
            return
        end

        rows[#rows+1] = Heading(T("temple.fallen.heading"))
        if #(board.fallen or {}) == 0 then
            rows[#rows+1] = Label(T("temple.fallen.empty"), 15, DIM)
        end
        for _, entry in ipairs(board.fallen or {}) do
            rows[#rows+1] = FallenRow(entry)
        end

        rows[#rows+1] = Heading(T("temple.rites.heading"))
        local rites = board.rites or {}
        if #rites == 0 then
            rows[#rows+1] = Label(T("temple.rites.empty"), 15, DIM)
        end
        for i, rite in ipairs(rites) do
            if i > RITES_SHOWN and not showAll then
                rows[#rows+1] = gui.Button{
                    text = T("temple.rites.show_all", { count = tostring(#rites) }),
                    fontSize = 16,
                    width = 220,
                    height = 36,
                    halign = "center",
                    click = function()
                        showAll = true
                        Rebuild()
                    end,
                }
                break
            end
            rows[#rows+1] = RiteRow(rite)
        end
        listPanel.children = rows
    end

    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        create = function(element)
            Load()
        end,
        --re-read the board when any rite in town moves.
        thinkTime = 0.5,
        think = function(element)
            local conn = EotwRoster.Connection()
            if conn == nil or not conn.connected then
                return
            end
            local rev = conn:GetPath("/city/projectsRev")
            if seenRev == nil then
                seenRev = rev
                return
            end
            if rev ~= seenRev then
                seenRev = rev
                Load()
            end
        end,
        Label(T("temple.intro"), 20, TEXT, { italics = true, bmargin = 8 }),
        Label(T("temple.how"), 15, DIM, { bmargin = 4 }),
        gui.Panel{
            width = "100%",
            height = "auto",
            maxHeight = 620,
            flow = "vertical",
            vscroll = true,
            create = function(element)
                listPanel = element
                Rebuild()
            end,
        },
    }
end
