local mod = dmhub.GetModLoading()

--The Encounter of the Week authoring test, the parts a Director touches: the
--Game menu rows that start, resume and end a test, the hero picker they
--open, the title-bar item (what is being tested, and End Test) shown for
--the length of a test, and the /eotwtest chat command. The machinery (player-host mode, placing the
--heroes, the clean-up) is EncounterOfTheWeekGame's, in EncounterOfTheWeek.lua
--under "the authoring test".
--Design/plan doc: EncounterOfTheWeek/EncounterOfTheWeek.md ("The authoring test").

EncounterTest = {}

--The last party picked, so the next test opens with it already chosen.
--Machine-local: a per-author convenience, not game state.
setting{
    id = "eotw:testheroes",
    description = "Heroes last chosen for an Encounter of the Week test",
    default = "",
    storage = "preference",
}

--An Encounter of the Week party is 4-6 heroes; a test allows fewer (a quick
--check needs only one) but not more.
local MAX_TEST_HEROES = 6

local function ModeName(modeid)
    for _, m in ipairs(EncounterOfTheWeekGame.TEST_MODES) do
        if m.id == modeid then
            return m.name
        end
    end
    return tostring(modeid)
end

local function RememberedHeroes()
    local result = {}
    local text = dmhub.GetSettingValue("eotw:testheroes")
    if type(text) == "string" then
        for charid in string.gmatch(text, "[^,]+") do
            result[charid] = true
        end
    end
    return result
end

local function RememberHeroes(charids)
    dmhub.SetSettingValue("eotw:testheroes", table.concat(charids, ","))
end

--- the hero picker ---------------------------------------------------------

--Open the picker for a test of this mode ("start", "montage" or "combat").
--The mode can still be changed in the dialog.
function EncounterTest.ShowDialog(modeid)
    local ok, reason = EncounterOfTheWeekGame.CanStartTest(modeid)
    if not ok then
        printf("EotW test: %s", tostring(reason))
        return
    end

    local gamehud = GameHud.instance
    --false (not nil) until the hud is built.
    if not gamehud then
        return
    end

    local candidates = EncounterOfTheWeekGame.TestCandidates()
    local remembered = RememberedHeroes()
    local chosen = {}
    local count = 0
    for _, c in ipairs(candidates) do
        if remembered[c.charid] and count < MAX_TEST_HEROES then
            chosen[c.charid] = true
            count = count + 1
        end
    end

    local chosenMode = modeid
    local statusLabel
    local startButton

    local function ChosenList()
        local list = {}
        for _, c in ipairs(candidates) do
            if chosen[c.charid] then
                list[#list + 1] = c.charid
            end
        end
        return list
    end

    local function Refresh()
        if statusLabel == nil or startButton == nil then
            return
        end
        local n = #ChosenList()
        local text
        if n == 0 then
            text = "Choose the heroes to play the encounter with."
        elseif n > MAX_TEST_HEROES then
            text = string.format("%d heroes chosen: a party is at most %d.", n, MAX_TEST_HEROES)
        elseif n < 4 then
            text = string.format("%d %s chosen. A real party is 4-6; the monsters scale for at least 3.", n, cond(n == 1, "hero", "heroes"))
        else
            text = string.format("%d heroes chosen.", n)
        end
        statusLabel.text = text
        startButton:SetClass("disabled", n == 0 or n > MAX_TEST_HEROES)
    end

    local rows = {}
    if #candidates == 0 then
        rows[1] = gui.Label{
            classes = { "sizeS", "fgMuted" },
            width = "100%",
            height = "auto",
            textWrap = true,
            vmargin = 12,
            text = "This game has no heroes off this map to test with. Install a module with pregens (or make some heroes) and keep them off the encounter map.",
        }
    end
    local lastGroup = nil
    for _, c in ipairs(candidates) do
        local candidate = c
        if candidate.pregen ~= lastGroup then
            lastGroup = candidate.pregen
            rows[#rows + 1] = gui.Label{
                classes = { "sizeXs", "fgMuted", "bold" },
                width = "100%",
                height = "auto",
                tmargin = cond(#rows == 0, 0, 10),
                bmargin = 2,
                uppercase = true,
                text = cond(candidate.pregen, "Pregens", "Other heroes in this game"),
            }
        end
        rows[#rows + 1] = gui.Panel{
            width = "100%",
            height = 44,
            flow = "horizontal",
            vmargin = 2,
            gui.CreateTokenImage(candidate.token, {
                width = 40,
                height = 40,
                valign = "center",
                rmargin = 8,
            }),
            gui.Check{
                classes = { "sizeS" },
                width = "100%-60",
                height = 26,
                valign = "center",
                text = candidate.name,
                value = chosen[candidate.charid] == true,
                change = function(element)
                    chosen[candidate.charid] = element.value == true or nil
                    Refresh()
                end,
            },
        }
    end

    local heroesOnMap = EncounterOfTheWeekGame.HeroesOnMap()
    local modeOptions = {}
    for _, m in ipairs(EncounterOfTheWeekGame.TEST_MODES) do
        if EncounterOfTheWeekGame.CanStartTest(m.id) then
            modeOptions[#modeOptions + 1] = { id = m.id, text = m.name }
        end
    end

    statusLabel = gui.Label{
        classes = { "sizeS" },
        width = "100%",
        height = "auto",
        tmargin = 10,
        textWrap = true,
        text = "",
    }

    startButton = gui.Button{
        classes = { "sizeL", "selected" },
        width = "100%",
        halign = "center",
        tmargin = 12,
        text = "START TEST",
        click = function(element)
            if element:HasClass("disabled") then
                return
            end
            local list = ChosenList()
            RememberHeroes(list)
            gamehud:CloseModal()
            local started, why = EncounterOfTheWeekGame.StartTest{ mode = chosenMode, heroes = list }
            if not started then
                printf("EotW test: %s", tostring(why))
            end
        end,
    }

    local dialog = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "none",
        bgimage = "panels/square.png",
        bgcolor = "#000000c0",
        styles = ThemeEngine.GetStyles(),

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            gamehud:CloseModal()
        end,

        gui.Panel{
            classes = { "framedPanel" },
            width = 560,
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "vertical",
            pad = 20,
            borderBox = true,

            gui.Label{
                classes = { "sizeXl", "bold" },
                width = "100%",
                height = "auto",
                text = "Test Encounter",
            },
            gui.Label{
                classes = { "sizeS", "fgMuted" },
                width = "100%",
                height = "auto",
                tmargin = 2,
                text = tostring(game.currentMap ~= nil and game.currentMap.description or ""),
            },
            gui.Label{
                classes = { "sizeS" },
                width = "100%",
                height = "auto",
                tmargin = 10,
                textWrap = true,
                text = "Play this map's encounter the way its players will: you become a player for the test, with copies of the heroes you choose placed in the Start zone. END TEST (in the title bar) puts the map back and returns you to the Director.",
            },
            gui.Panel{
                width = "100%",
                height = 30,
                flow = "horizontal",
                tmargin = 12,
                gui.Label{
                    classes = { "sizeS", "bold" },
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    rmargin = 8,
                    text = "Start at",
                },
                gui.Dropdown{
                    classes = { "sizeS" },
                    width = 200,
                    height = 26,
                    valign = "center",
                    options = modeOptions,
                    idChosen = chosenMode,
                    change = function(element)
                        ---@cast element Dropdown
                        chosenMode = element.idChosen --[[@as string]]
                    end,
                },
            },
            gui.Label{
                classes = { "sizeS", "bold" },
                width = "100%",
                height = "auto",
                tmargin = 12,
                bmargin = 4,
                text = "Heroes",
            },
            gui.Panel{
                width = "100%",
                height = "auto",
                maxHeight = 360,
                vscroll = true,
                flow = "vertical",
                children = rows,
            },
            gui.Label{
                classes = { "sizeXs", "fgMuted", cond(#heroesOnMap == 0, "collapsed", nil) },
                width = "100%",
                height = "auto",
                tmargin = 8,
                textWrap = true,
                text = "Already on this map, so also in the test: " .. table.concat(heroesOnMap, ", ") .. ".",
            },
            statusLabel,
            startButton,
            gui.Button{
                classes = { "sizeS" },
                width = "100%",
                height = 30,
                halign = "center",
                tmargin = 6,
                text = "CANCEL",
                click = function(element)
                    gamehud:CloseModal()
                end,
            },
        },
    }

    Refresh()
    gamehud:ShowModal(dialog)
end

--- the title-bar item ------------------------------------------------------
--What is being tested and the way out, as an item in the title bar's
--status area (the EotW interface's titlebarPanels hook, so it is there
--exactly while the tester sees the EotW interface and never covers the
--initiative bar or the stage). After an app restart mid-test this client is
--a Director again with no EotW interface; the Game menu's Resume / End rows
--cover that.

local function TestOwnedHere()
    local test = EncounterOfTheWeekGame.GetTest()
    if test == nil or test.by ~= dmhub.loginUserid then
        return nil
    end
    return test
end

--The title-bar item: "Encounter Test: Combat" and END TEST.
function EncounterTest.CreateTitlebarItem()
    local titleLabel = gui.Label{
        classes = { "sizeXs", "bold" },
        width = "auto",
        height = "auto",
        valign = "center",
        rmargin = 10,
        uppercase = true,
        text = "Encounter Test",
    }
    local endButton = gui.Button{
        classes = { "sizeXs", "selected" },
        width = 90,
        height = 22,
        valign = "center",
        text = "END TEST",
        click = function(element)
            element.text = "ENDING..."
            element:SetClass("disabled", true)
            EncounterOfTheWeekGame.EndTest()
        end,
    }

    local function Refresh()
        local test = TestOwnedHere()
        if test == nil then
            return
        end
        local text = string.format("Encounter Test: %s", ModeName(test.mode))
        if test.phase == "ending" then
            text = text .. " (ending...)"
        end
        titleLabel.text = text
        endButton:SetClass("collapsed", test.phase ~= "running")
    end

    return gui.Panel{
        styles = ThemeEngine.GetStyles(),
        width = "auto",
        height = "100%",
        flow = "horizontal",
        lmargin = 12,
        rmargin = 12,
        thinkTime = 0.5,
        create = function(element)
            Refresh()
        end,
        think = function(element)
            Refresh()
        end,
        titleLabel,
        endButton,
    }
end

--- the Game menu -----------------------------------------------------------
--One row per test mode for the Director while the current map's script has
--that beat and nothing is running, and End Encounter Test while the local
--user's test is on. Not dmonly: that is decided once, when this file loads,
--and a test reloads it as a player.

for _, m in ipairs(EncounterOfTheWeekGame.TEST_MODES) do
    local modeid = m.id
    Commands.Register{
        name = "Test Encounter: " .. m.name,
        identifier = "eotwtest-" .. modeid,
        icon = "panels/initiative/initiative-icon.png",
        menu = "game",
        group = "eotwtest",
        execute = function()
            EncounterTest.ShowDialog(modeid)
        end,
        filtered = function()
            local ok = false
            pcall(function() ok = EncounterOfTheWeekGame.CanStartTest(modeid) end)
            return not ok
        end,
    }
end

Commands.Register{
    name = "Resume Encounter Test",
    identifier = "eotwtest-resume",
    icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    group = "eotwtest",
    execute = function()
        EncounterOfTheWeekGame.ResumeTest()
    end,
    filtered = function()
        local test = TestOwnedHere()
        return test == nil or test.phase ~= "running" or dmhub.playerHostMode == true
    end,
}

Commands.Register{
    name = "End Encounter Test",
    identifier = "eotwtest-end",
    icon = "panels/initiative/initiative-icon.png",
    menu = "game",
    group = "eotwtest",
    execute = function()
        EncounterOfTheWeekGame.EndTest()
    end,
    filtered = function()
        return TestOwnedHere() == nil
    end,
}

--"/eotwtest start|montage|combat|end|state": the same from chat (and MCP).
pcall(function()
    Commands.RegisterMacro{
        name = "eotwtest",
        summary = "play-test this map's Encounter of the Week encounter as a player",
        doc = "Usage: /eotwtest start | montage | combat | end | state\nstart, montage and combat open the hero picker for a test from the first beat, the montage, or the encounter; end ends the running test and returns you to the Director; state prints the test record.",
        command = function(str)
            local arg = string.lower(string.gsub(str or "", "^%s*(.-)%s*$", "%1"))
            if arg == "start" or arg == "montage" or arg == "combat" then
                EncounterTest.ShowDialog(arg)
            elseif arg == "end" then
                EncounterOfTheWeekGame.EndTest()
            else
                print(json(EncounterOfTheWeekGame.GetTest() or {}))
                print(string.format("playerHostMode = %s, playerHostModeForced = %s", tostring(dmhub.playerHostMode), tostring(dmhub.playerHostModeForced)))
            end
        end,
    }
end)
