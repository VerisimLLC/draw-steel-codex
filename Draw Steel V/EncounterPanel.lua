local mod = dmhub.GetModLoading()

--To go from a monsterid to an actual monster:
-- local monster = assets.monsters[monsterid]

--sample encounter
--encounter = {
--    groups = {
--        {
--            monsters = {
--
--                ["8e2c0f64-0b98-45a2-a7ea-6ff1eae6a5c4"] = 4,
--                ["2f4d8b2e-5f3e-4c60-a4c1-1e37f4ed37b6"] = 1,
--            },
--        },
--        {
--            minHeroes = 3,
--            monsters = {
--                ["b7122d63-1ac3-4c4d-b7d5-82c5f1ea93d3"] = 1,
--            }
--        }
--    }
--}
--

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateEncounterPanel

DockablePanel.Register {
    name = "Encounter creator",
    icon = "icons/standard/Icon_App_EncounterCreator.png",
    minHeight = 200,
    vscroll = true,
    content = function()
        track("panel_open", {
            panel = "Encounter creator",
            dailyLimit = 30,
        })
        return CreateEncounterPanel()
    end,
}

--Encounter is defined in Draw Steel Core Rules/MCDMEncounter.lua (data + rules).
--We re-fetch the registered type here so the UI methods below can attach to it.
Encounter = RegisterGameType('Encounter')

EncounterFolder = RegisterGameType('EncounterFolder')

EncounterFolder.tableName = 'encounterfolders'

EncounterFolder.name = 'New Encounter Folder'

--Encounter data/rules methods (MainMonster, AdjustedMonsterQuantity,
--CloneForNumberOfHeroes, AddMonster, AddGroup, CountEDS, Describe) live in
--Draw Steel Core Rules/MCDMEncounter.lua. The encounter-creator UI methods
--(Encounter.Editor / Encounter.CreateEditorDialog) remain below.

local function createSmallMonsterDisplay(monsterid, quantity)
    local monster = assets.monsters[monsterid]

    --example of one monster: image + name + quantity BACK
    return gui.Panel {

        width = "100%",
        height = 41,
        halign = "left",
        bmargin = 3,

        flow = "horizontal",

        gui.Panel {

            classes = { "image", "bordered" },
            bgimage = monster.appearance.portraitId,
            width = 35,
            height = 35,
            halign = "left",
            tmargin = 3,
            lmargin = 3,

        },

        gui.Label {

            text = string.format("%s", monster.name),
            fontSize = 13,
            width = "auto",
            height = "100%",
            lmargin = 5,
        },

        gui.Label {

            text = string.format("%d", quantity),
            fontSize = 13,
            width = "auto",
            height = "100%",
            halign = "right",
        },

    }
end

local function createGroupPanel(encounter)
    local groupkingpanel
    groupkingpanel = gui.Panel {

        styles = ThemeEngine.MergeStyles({

            {
                selectors = { "addButton" },
                hidden = 1,
            },

            {
                selectors = { "addButton", "parent:hover", "~full" },
                hidden = 0,
            },

        }),

        classes = { "bg" },
        width = "96%",
        height = "auto",
        valign = "top",
        flow = "vertical",

        maxHeight = 300,
        vscroll = true,

        update = function(element)
            local panels = {}

            for i, group in ipairs(encounter.groups) do
                --Once the encounter has waves, offer a dropdown to choose which wave
                --this group arrives with. Defaults to "Start of Encounter".
                local waveDropdown
                if #encounter.waves > 0 then
                    local waveOptions = { { id = "start", text = "Start of Encounter" } }
                    for _, wave in ipairs(encounter.waves) do
                        waveOptions[#waveOptions + 1] = { id = wave.id, text = wave.name }
                    end

                    --if the group references a wave that has since been deleted, fall
                    --back to the start of the encounter.
                    local chosen = group.wave or "start"
                    local found = false
                    for _, opt in ipairs(waveOptions) do
                        if opt.id == chosen then
                            found = true
                            break
                        end
                    end
                    if not found then
                        chosen = "start"
                        group.wave = nil
                    end

                    waveDropdown = gui.Dropdown {
                        classes = { "form" },
                        floating = true,
                        halign = "right",
                        valign = "top",
                        hmargin = 50,
                        vmargin = 4,
                        width = 180,
                        height = 18,
                        fontSize = 11,
                        options = waveOptions,
                        idChosen = chosen,
                        change = function(element)
                            if element.idChosen == "start" then
                                group.wave = nil
                            else
                                group.wave = element.idChosen
                            end
                        end,
                    }
                end

                panels[#panels + 1] = gui.Panel {

                    classes = { "bordered", "bg" },
                    width = "85%",
                    height = "65",
                    valign = "top",
                    tmargin = 5,
                    flow = "horizontal",

                    rightClick = function(self)
                        self.popup = gui.ContextMenu {
                            entries = {

                                {
                                    text = "Duplicate",
                                    click = function()
                                        encounter.groups[#encounter.groups + 1] = DeepCopy(group)
                                        element:FireEventTree("update")
                                    end
                                }
                            },
                        }
                    end,

                    gui.Panel {

                        classes = { "bordered" },
                        width = 50,
                        height = 65,
                        halign = "left",

                        gui.Label {

                            classes = { "fgStrong", "number" },
                            text = #panels + 1,
                            fontSize = 14,
                        },

                    },

                    gui.Panel {

                        flow = "vertical",
                        width = "100%-60",
                        height = "auto",

                        --in the create we loop over allthe monsters in thebackend and create a
                        --panel for each monster

                        classes = { "grouppanel" },

                        create = function(element)
                            local panels = {}

                            for monsterid, quantity in pairs(group.monsters) do
                                local monster = assets.monsters[monsterid]

                                local squadSizeLabel
                                if monster ~= nil and monster.properties.minion then
                                    squadSizeLabel = gui.Label{
                                        text = string.format(" (Squads of %d)", group.squadSize or 4),
                                        classes = {"link"},
                                        fontSize = 12,
                                        valign = "center",
                                        create = function (element)
                                            element:FireEvent("refresh", quantity)
                                        end,
                                        press = function(element)
                                            group.squadSize = (group.squadSize or 4) + 4
                                            if group.squadSize > element.data.quantity then
                                                group.squadSize = 4
                                            end

                                            element:FireEvent("refresh", element.data.quantity)
                                        end,
                                        refresh = function(element, newQuantity)
                                            --'refresh' is also a global tree-wide broadcast fired with no args
                                            --(GameHud.Refresh -> sheet:FireEventTree('refresh')); fall back to the
                                            --last known quantity so a stray broadcast doesn't compare nil < 8.
                                            newQuantity = newQuantity or element.data.quantity
                                            if newQuantity == nil then
                                                return
                                            end
                                            element.data.quantity = newQuantity
                                            if newQuantity < 8 then
                                                element:SetClass("hidden", true)
                                                return
                                            else
                                                element:SetClass("hidden", false)
                                            end

                                            element.text = string.format(" (Squads of %d)", group.squadSize or 4)
                                        end,
                                    }
                                end


                                panels[#panels + 1] = gui.Panel {

                                    flow = "horizontal",
                                    width = "auto",
                                    height = "auto",
                                    halign = "left",

                                    gui.Label {

                                        classes = { "fgStrong" },
                                        width = "auto",
                                        height = "auto",
                                        fontSize = 16,
                                        text = string.format("%d", quantity),
                                        rmargin = 3,
                                        editable = true,
                                        characterLimit = 2,

                                        change = function(self)
                                            if tonumber(self.text) == 0 then
                                                group.monsters[monsterid] = nil
                                                self:FindParentWithClass("grouppanel"):FireEvent("create")

                                                return
                                            end

                                            if tonumber(self.text) ~= nil then
                                                group.monsters[monsterid] = tonumber(self.text)
                                            else
                                                group.monsters[monsterid] = 1
                                            end

                                            self.text = group.monsters[monsterid]

                                            if squadSizeLabel ~= nil then
                                                squadSizeLabel:FireEvent("refresh", group.monsters[monsterid])
                                            end
                                        end

                                    },
                                    gui.Label {

                                        classes = { "fg" },
                                        width = "auto",
                                        height = "auto",
                                        fontSize = 16,
                                        text = string.format("X %s", creature.GetTokenDescription(monster)),
                                    },

                                    squadSizeLabel,
                                }
                            end

                            element.children = panels

                            if #panels >= 4 then
                                element.parent:SetClassTree("full", true)
                            else
                                element.parent:SetClassTree("full", false)
                            end
                        end

                    },

                    gui.Button {

                        classes = { "addButton", "sizeXs" },
                        halign = "center",
                        valign = "center",
                        floating = true,

                        click = function(element)
                            local monsterinfo = dmhub.GetSelectedMonster()

                            if monsterinfo == nil then
                                element:FireEvent("showmenu")
                                return
                            end

                            if monsterinfo ~= nil then
                                group.monsters[monsterinfo.monsterid] = (group.monsters[monsterinfo.monsterid] or 0) +
                                    monsterinfo.quantity
                            end

                            element.parent:FireEventTree("create")
                        end,

                        showmenu = function(element)
                            local monsterpanels = {}

                            for monsterid, monster in pairs(assets.monsters) do
                                --print("VENLA: ", monster, monster.name, monster.description)
                                if not monster.hidden then
                                    local name = creature.GetTokenDescription(monster)

                                    monsterpanels[#monsterpanels + 1] = gui.Label {

                                        classes = { "sizeXs", "bg" },
                                        text = name,
                                        width = "100%",
                                        valign = "top",

                                        search = function(element, searchtext)
                                            if string.find(string.lower(element.text), searchtext) then
                                                element:SetClass("collapsed", false)
                                            else
                                                element:SetClass("collapsed", true)
                                            end
                                        end,

                                        click = function(label)
                                            local monster = assets.monsters[monsterid]

                                            if monster.properties.minion then
                                                group.monsters[monsterid] = (group.monsters[monsterid] or 0) + 4
                                            else
                                                group.monsters[monsterid] = (group.monsters[monsterid] or 0) + 1
                                            end

                                            element.parent:FireEventTree("create")

                                            element.popup = nil
                                        end,

                                    }
                                end
                            end

                            table.sort(monsterpanels, function(a, b)
                                return a.text < b.text
                            end)

                            local monsterlist = gui.Panel {
                                width = 300,
                                height = 400,
                                flow = "vertical",
                                vscroll = true,
                                children = monsterpanels,
                            }

                            element.popupsInheritStyles = true
                            element.popup = gui.Panel {
                                classes = { "bordered", "bg" },
                                width = "auto",
                                height = "auto",
                                valign = "center",
                                halign = "left",
                                x = -600,
                                flow = "vertical",

                                gui.SearchInput {
                                    classes = {"bordered"},
                                    fontSize = 11,
                                    height = 20,
                                    width = 280,
                                    placeholderText = "Search...",
                                    hasFocus = true,

                                    edit = function(element)
                                        element.parent:FireEventTree("search", string.lower(element.text))
                                    end,

                                    confirm = function(element)
                                        local query = element.text
                                        if query ~= "" then
                                            local resultCount = 0
                                            for _, child in ipairs(monsterlist.children) do
                                                if not child:HasClass("collapsed") then
                                                    resultCount = resultCount + 1
                                                end
                                            end
                                            track("search_query", {
                                                query = query,
                                                resultCount = resultCount,
                                                context = "encounter",
                                                dailyLimit = 20,
                                            })
                                        end
                                    end,

                                },

                                monsterlist,
                            }
                        end,

                        rightClick = function(element)
                            local monsterinfo = dmhub.GetSelectedMonster()

                            if monsterinfo == nil then
                                return
                            end

                            if group.monsters[monsterinfo.monsterid] ~= nil and group.monsters[monsterinfo.monsterid] > 0 then
                                group.monsters[monsterinfo.monsterid] = (group.monsters[monsterinfo.monsterid] or 0) - 1
                            end

                            if group.monsters[monsterinfo.monsterid] == 0 then
                                group.monsters[monsterinfo.monsterid] = nil
                            end

                            element.parent:FireEventTree("create")
                        end

                    },

                    gui.Button {
                        classes = { "deleteButton", "sizeXs" },
                        x = 18,

                        floating = true,
                        halign = "right",
                        valign = "top",
                        press = function(element)
                            table.remove(encounter.groups, i)
                            groupkingpanel:FireEvent("update")
                        end,
                    },

                    gui.Label {
                        classes = { "link" },
                        floating = true,
                        fontSize = 12,
                        halign = "right",
                        valign = "bottom",
                        hmargin = 8,
                        vmargin = 4,
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        text = "Balancing",
                        press = function(element)
                            local balancing = group.balancing or {}
                            for _, i in ipairs({ 3, 4, 5, 6, 7 }) do
                                balancing[i] = balancing[i] or {}
                                balancing[i].monsters = balancing[i].monsters or {}
                            end

                            local balancingBaseline = DeepCopy(balancing)
                            local children = {}

                            for _, i in ipairs({ 3, 4, 5, 6, 7 }) do
                                local heroCount = i
                                local info = balancing[heroCount]

                                local rightChildren = {
                                    gui.Panel {
                                        halign = "right",
                                        flow = "horizontal",
                                        width = "auto",
                                        height = "auto",
                                        vmargin = 4,
                                        gui.Label {
                                            fontSize = 12,
                                            text = "Stamina:",
                                            width = "auto",
                                            height = "auto",
                                            hmargin = 4,
                                        },
                                        gui.Input {
                                            classes = { "form" },
                                            fontSize = 12,
                                            width = 50,
                                            height = 12,
                                            hmargin = 4,
                                            text = info.stamina or "",
                                            characterLimit = 4,
                                            change = function(element)
                                                local val = tonumber(element.text)
                                                if val ~= nil then
                                                    balancing[heroCount].stamina = val
                                                else
                                                    balancing[heroCount].stamina = nil
                                                end

                                                element.text = balancing[heroCount].stamina or ""
                                            end,
                                        }
                                    },

                                    gui.Check {
                                        classes = { "form" },
                                        text = "Disable Solo Action",
                                        height = 14,
                                        minWidth = 100,
                                        value = balancing[heroCount].disableSolo or false,
                                        halign = "right",
                                        fontSize = 10,
                                        change = function(element)
                                            balancing[heroCount].disableSolo = element.value
                                        end,
                                    },
                                }

                                --per-monster-type count adjustments for this number of heroes.
                                for monsterid, baseQuantity in pairs(group.monsters) do
                                    local monster = assets.monsters[monsterid]
                                    local monsterName = (monster ~= nil and creature.GetTokenDescription(monster)) or "Unknown"
                                    local quantity = baseQuantity

                                    local valueLabel
                                    valueLabel = gui.Label {
                                        fontSize = 11,
                                        width = "auto",
                                        height = "auto",
                                        valign = "center",
                                        hmargin = 3,
                                        text = string.format("%+d %s", balancing[heroCount].monsters[monsterid] or 0, monsterName),
                                    }

                                    local function adjust(delta)
                                        local cur = (balancing[heroCount].monsters[monsterid] or 0) + delta
                                        --never let the adjusted count drop below zero monsters.
                                        if quantity + cur < 0 then
                                            cur = -quantity
                                        end
                                        if cur == 0 then
                                            balancing[heroCount].monsters[monsterid] = nil
                                        else
                                            balancing[heroCount].monsters[monsterid] = cur
                                        end
                                        valueLabel.text = string.format("%+d %s", cur, monsterName)
                                    end

                                    rightChildren[#rightChildren + 1] = gui.Panel {
                                        halign = "right",
                                        flow = "horizontal",
                                        width = "auto",
                                        height = "auto",
                                        vmargin = 1,

                                        valueLabel,

                                        gui.Label {
                                            classes = { "link" },
                                            fontSize = 14,
                                            text = "[-]",
                                            width = "auto",
                                            height = "auto",
                                            valign = "center",
                                            hmargin = 2,
                                            press = function()
                                                adjust(-1)
                                            end,
                                        },

                                        gui.Label {
                                            classes = { "link" },
                                            fontSize = 14,
                                            text = "[+]",
                                            width = "auto",
                                            height = "auto",
                                            valign = "center",
                                            hmargin = 2,
                                            press = function()
                                                adjust(1)
                                            end,
                                        },
                                    }
                                end

                                children[#children + 1] = gui.Panel {
                                    flow = "horizontal",
                                    width = "100%",
                                    height = "auto",
                                    gui.Label {
                                        width = 80,
                                        height = "auto",
                                        fontSize = 12,
                                        valign = "center",
                                        text = string.format("%d Heroes", heroCount),
                                    },

                                    gui.Panel {
                                        width = 250,
                                        flow = "vertical",
                                        height = "auto",
                                        children = rightChildren,
                                    },
                                }
                            end

                            local panel = gui.Panel {
                                -- styles = ThemeEngine.GetStyles(),
                                classes = { "dialog" },
                                width = 350,
                                height = "auto",
                                flow = "vertical",
                                hpad = 6,
                                vpad = 6,
                                children = children,
                                destroy = function(element)
                                    if not dmhub.DeepEqual(balancingBaseline, balancing) then
                                        group.balancing = balancing
                                    end
                                end,
                            }

                            element.popupsInheritStyles = true
                            element.popup = panel
                        end,
                    },

                    waveDropdown,

                    gui.Panel {
                        floating = true,
                        halign = "right",
                        valign = "top",
                        hmargin = 8,
                        vmargin = 4,
                        flow = "horizontal",
                        width = 34,
                        height = 16,
                        press = function(element)
                            local entries = {}
                            for _, i in ipairs({ 0, 3, 4, 5, 6, 7 }) do
                                entries[#entries + 1] = {
                                    text = cond(i == 0, "Always", string.format("%d+ Heroes", i)),
                                    selected = (group.minHeroes or 0) == i,
                                    click = function()
                                        group.minHeroes = cond(i == 0, nil, i)
                                        element.parent:FireEventTree("create")
                                        element.popup = nil
                                    end,
                                }
                            end

                            element.popup = gui.ContextMenu {
                                entries = entries,
                            }
                        end,
                        gui.Label {
                            width = 18,
                            height = 16,
                            fontSize = 12,
                            text = (group.minHeroes and string.format("%d+", group.minHeroes)) or "all",
                            create = function(element)
                                element.text = (group.minHeroes and string.format("%d+", group.minHeroes)) or "all"
                            end,
                        },
                        gui.Panel {
                            classes = { "image" },
                            bgimage = "icons/icon_app/icon_app_18.png",
                            width = 16,
                            height = 16,
                        },
                    },
                }
            end

            element.children = panels
        end

    }

    return groupkingpanel
end

local function createMonsterDisplayPanel(monsterid, quantity)
    local monster = assets.monsters[monsterid]

    local evtotal = monster.properties:EV() * quantity

    if monster.properties.minion then
        evtotal = round(evtotal / 4)
    end

    return gui.Panel {

        classes = { "bordered", "bg" },
        width = "90%",
        height = 110,
        halign = "center",
        flow = "horizontal",
        pad = 1,
        bmargin = 8,

        --monster image panel
        gui.Panel {

            classes = { "image" },
            width = "35%",
            height = "100%",
            bgimage = monster.appearance.portraitId,
            halign = "left",

        },

        --king panel for name and info
        gui.Panel {

            width = "65%",
            height = "100%",
            flow = "vertical",

            gui.Label {

                classes = { "fgStrong" },
                text = string.format("%s", monster.name),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                classes = { "fg" },
                text = string.format("Level %d", monster.properties:Level()),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                classes = { "fg" },
                text = string.format("%d", quantity),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                classes = { "fg" },
                text = string.format("%s", monster.properties.role),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                classes = { "fg" },
                text = string.format("EV: %d  Total: %d", monster.properties:EV(), evtotal),
                halign = "center",
                fontSize = 16,

            },

        },

    }
end

--Builds the "Waves" management interface for the encounter editor. By default an
--encounter has no additional waves; the user adds them with the "Add Wave" button.
--Each wave is listed with an editable name and a dropdown choosing which round it
--arrives on (rounds 2-6, or "Every round"). onWavesChanged is called whenever the
--set of waves changes (add/remove/rename) so the per-group wave dropdowns can
--refresh their options.
local function createWavePanel(encounter, onWavesChanged)
    local wavesListPanel
    local resultPanel

    wavesListPanel = gui.Panel {
        width = "90%",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",

        update = function(element)
            local rows = {}

            for i, wave in ipairs(encounter.waves) do
                rows[#rows + 1] = gui.Panel {
                    classes = { "bordered", "bg" },
                    width = "100%",
                    height = 32,
                    halign = "center",
                    valign = "top",
                    tmargin = 4,
                    flow = "horizontal",

                    gui.Label {
                        classes = { "fgStrong", "number" },
                        width = 22,
                        height = "100%",
                        fontSize = 13,
                        valign = "center",
                        halign = "left",
                        lmargin = 4,
                        textAlignment = "center",
                        text = string.format("%d", i),
                    },

                    gui.Input {
                        classes = { "form" },
                        width = "44%",
                        height = 20,
                        valign = "center",
                        halign = "left",
                        lmargin = 4,
                        fontSize = 12,
                        text = wave.name,
                        characterLimit = 24,
                        change = function(element)
                            local newname = element.text
                            if newname == "" then
                                newname = "Reinforcements"
                            end
                            wave.name = newname
                            element.text = newname
                            onWavesChanged()
                        end,
                    },

                    gui.Dropdown {
                        classes = { "form" },
                        width = 110,
                        height = 20,
                        valign = "center",
                        halign = "right",
                        rmargin = 28,
                        fontSize = 12,
                        options = {
                            { id = "2", text = "Round 2" },
                            { id = "3", text = "Round 3" },
                            { id = "4", text = "Round 4" },
                            { id = "5", text = "Round 5" },
                            { id = "6", text = "Round 6" },
                            { id = "every", text = "Every round" },
                        },
                        idChosen = tostring(wave.round),
                        change = function(element)
                            if element.idChosen == "every" then
                                wave.round = "every"
                            else
                                wave.round = tonumber(element.idChosen)
                            end
                        end,
                    },

                    gui.Button {
                        classes = { "deleteButton", "sizeXs" },
                        floating = true,
                        halign = "right",
                        valign = "center",
                        rmargin = 4,
                        press = function(element)
                            table.remove(encounter.waves, i)
                            wavesListPanel:FireEvent("update")
                            onWavesChanged()
                        end,
                    },
                }
            end

            element.children = rows
        end,
    }

    resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",

        wavesListPanel,

        gui.Panel {
            width = "90%",
            height = 40,
            halign = "center",
            valign = "top",
            tmargin = 5,

            gui.Button {
                classes = { "sizeS" },
                width = 140,
                halign = "center",
                valign = "center",
                text = "Add Wave",
                press = function(element)
                    encounter:AddWave()
                    wavesListPanel:FireEvent("update")
                    onWavesChanged()
                end,
            },
        },
    }

    resultPanel:FireEventTree("update")

    return resultPanel
end

function Encounter.Editor(self, options)
    local resultPanel

    local groupPanel = createGroupPanel(self)

    local appearancesCheck

    if options.journal then
        appearancesCheck = gui.Check {
            classes = { "form" },
            text = "Save monster appearances",
            value = self.saveAppearances,
            change = function(element)
                self.saveAppearances = element.value
            end,
        }
    end

    resultPanel = gui.Panel {

        width = "100%-16",
        height = "100%-16",
        flow = "vertical",
        hpad = 8,
        vpad = 8,

        gui.Label {

            classes = { "fgStrong" },
            text = self.name,
            fontSize = 16,
            bold = true,
            halign = "center",
            minWidth = 160,
            textAlignment = "center",
            height = 20,
            valign = "top",
            tmargin = 5,
            bmargin = 6,

            characterLimit = 20,
            editable = true,
            change = function(label)
                self.name = label.text
            end,

        },

        gui.Panel {

            classes = { "bordered", "bg" },
            width = "90%",
            height = 30,
            halign = "center",
            valign = "top",
            tmargin = 5,
            gui.Label {

                text = string.format("EV total: %d", self:CountEDS()),
                fontSize = 14,
                halign = "left",
                lmargin = 6,

                thinkTime = 0.2,

                think = function(label)
                    label.text = string.format("EV total: %d", self:CountEDS())
                end
            },
        },

        gui.Label {
            classes = { "fgStrong" },
            text = "Groups:",
            fontSize = 16,
            bold = true,
            halign = "center",
            valign = "top",
            tmargin = 4,
        },

        groupPanel,

        gui.Panel {

            classes = { "bordered", "bg" },
            width = "90%",
            height = "50",
            valign = "top",
            tmargin = 5,

            gui.Button {

                classes = { "addButton", "sizeXs" },
                halign = "center",
                valign = "center",

                click = function(element)
                    local grouppanels = {}

                    self:AddGroup()

                    groupPanel:FireEvent("update")
                end

            },

        },

        gui.Label {
            classes = { "fgStrong" },
            text = "Waves:",
            fontSize = 16,
            bold = true,
            halign = "center",
            valign = "top",
            tmargin = 8,
        },

        createWavePanel(self, function()
            --refresh the group panels so their per-group wave dropdowns pick up the
            --new/removed/renamed waves.
            groupPanel:FireEvent("update")
        end),

        gui.Label {
            classes = { "fgStrong" },
            text = "Victory Conditions:",
            fontSize = 16,
            bold = true,
            halign = "center",
            valign = "top",
            tmargin = 8,
        },

        --Both the victory-condition dropdown and (when "Destroy the Thing!" is chosen) the
        --object-keyword selector live in this single bordered panel.
        gui.Panel {
            classes = { "bordered", "bg" },
            width = "90%",
            height = "auto",
            halign = "center",
            valign = "top",
            tmargin = 5,
            vpad = 8,
            borderBox = true,
            flow = "vertical",

            gui.Dropdown {
                classes = { "form" },
                width = "94%",
                height = 24,
                halign = "center",
                valign = "center",
                fontSize = 12,
                options = Encounter.GetVictoryConditions(),
                idChosen = self:try_get("victoryCondition", "all_defeated"),
                change = function(element)
                    self.victoryCondition = element.idChosen
                    resultPanel:FireEventTree("refreshDestroy")
                end,
            },

            --Shown only when the "Destroy the Thing!" victory condition is selected. Lets the
            --DM pick which Targetable object keyword identifies the "thing" to destroy, or
            --explains how to add one if the map has no Targetable objects with keywords.
            gui.Panel {
                width = "94%",
                height = "auto",
                halign = "center",
                valign = "top",
                flow = "vertical",

                create = function(element)
                    element:FireEvent("refreshDestroy")
                end,

                refreshDestroy = function(element)
                    local isDestroy = self:try_get("victoryCondition", "all_defeated") == "destroy_thing"
                    element:SetClass("collapsed", not isDestroy)
                    if not isDestroy then
                        element.children = {}
                        return
                    end

                    local keywords = Encounter.GetTargetableObjectKeywords()

                    if #keywords == 0 then
                        element.children = {
                            gui.Label {
                                classes = { "fgStrong" },
                                width = "100%",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                tmargin = 8,
                                fontSize = 12,
                                textWrap = true,
                                text = "To select a thing to destroy add an object to the map with the Targetable property and a keyword",
                            },
                        }
                        return
                    end

                    local options = {}
                    for _, keyword in ipairs(keywords) do
                        options[#options + 1] = { id = keyword, text = keyword }
                    end

                    local chosen = self:try_get("victoryDestroyKeyword")
                    if chosen == nil or not table.contains(keywords, chosen) then
                        chosen = keywords[1]
                        self.victoryDestroyKeyword = chosen
                    end

                    element.children = {
                        gui.Dropdown {
                            classes = { "form" },
                            width = "100%",
                            height = 24,
                            halign = "center",
                            valign = "center",
                            tmargin = 8,
                            fontSize = 12,
                            options = options,
                            idChosen = chosen,
                            change = function(dropdown)
                                self.victoryDestroyKeyword = dropdown.idChosen
                            end,
                        },
                    }
                end,
            },
        },

        --Number of Victories each hero earns for winning this encounter.
        gui.Panel {
            width = "90%",
            height = 30,
            halign = "center",
            valign = "top",
            tmargin = 5,
            flow = "horizontal",

            gui.Label {
                classes = { "fgStrong" },
                text = "Victories:",
                fontSize = 14,
                halign = "left",
                valign = "center",
                width = "auto",
                height = "auto",
            },

            gui.Input {
                classes = { "form" },
                width = 60,
                height = 24,
                halign = "left",
                valign = "center",
                hmargin = 8,
                fontSize = 12,
                numeric = true,
                characterLimit = 3,
                text = tostring(self:try_get("victories", 1)),
                change = function(element)
                    --validate as a non-negative integer; revert to the stored value on
                    --bad input.
                    local n = tonumber(element.text)
                    if n == nil then
                        element.text = tostring(self:try_get("victories", 1))
                        return
                    end
                    n = math.floor(n)
                    if n < 0 then n = 0 end
                    self.victories = n
                    element.text = tostring(n)
                end,
            },
        },

        gui.Panel {

            width = "100%",
            height = "auto",
            flow = "vertical",

            create = function(panel)
                panel:FireEvent("displayMonsters")
            end,

            displayMonsters = function(panel)
                local children = {}

                for monsterid, quantity in pairs(self.monsters) do
                    children[#children + 1] = createMonsterDisplayPanel(monsterid, quantity)
                end

                panel.children = children
            end

        },

        --[[gui.Panel {

            classes = {

                'monster-drag-target',

            },

            width = "90%",
            height = 110,
            border = 1,
            borderColor = Styles.textColor,
            halign = 'center',
            tmargin = 12,
            bgimage = true,
            bgcolor = "black",

            monsterDraggedOnto = function()
                print("venla got the event")
            end,

            press = function()
                local monsterinfo = dmhub.GetSelectedMonster()

                if monsterinfo == nil then
                    return
                end

                self:AddMonster(monsterinfo.monsterid)

                resultPanel:FireEventTree("displayMonsters")
            end,



            thinkTime = 0.1,
            think = function(element)
                local imageAspect = element.bgsprite.dimensions.y / element.bgsprite.dimensions.x

                local w = element.renderedWidth
                local h = element.renderedHeight
                local panelAspect = h / w

                local height = panelAspect / imageAspect

                element.selfStyle.imageRect = {
                    x1 = 0,
                    x2 = 1,
                    y1 = 0.5 - height / 2,
                    y2 = 0.5 + height / 2,
                }
            end,



            gui.Button {
                classes = {"addButton"},
            

                halign = "center",
                valign = "center",

                click = function(element)
                    local monsterpanels = {}

                    for monsterid, monster in pairs(assets.monsters) do
                        print("VENLA: ", monster, monster.name, monster.description)
                        local name = creature.GetTokenDescription(monster)

                        monsterpanels[#monsterpanels + 1] = gui.Label {

                            text = name,
                            fontSize = 11,
                            bgimage = true,
                            width = "100%",
                            height = 20,

                            search = function(element, searchtext)
                                if string.find(string.lower(element.text), searchtext) then
                                    element:SetClass("collapsed", false)
                                else
                                    element:SetClass("collapsed", true)
                                end
                            end,

                            click = function(label)
                                self:AddMonster(monsterid)

                                element.popup = nil

                                resultPanel:FireEventTree("displayMonsters")
                            end


                        }
                    end

                    table.sort(monsterpanels, function(a, b)
                        return a.text < b.text
                    end)


                    local monsterlist = gui.Panel {

                        bgimage = true,
                        bgcolor = "black",
                        width = 300,
                        height = 400,
                        flow = "vertical",
                        maxHeight = 400,
                        vscroll = true,

                        children = monsterpanels,

                        styles = {

                            {
                                classes = { "label" },
                                bgcolor = "black",
                                color = Styles.textColor,
                            },

                            {
                                classes = { "label", "hover" },
                                bgcolor = Styles.textColor,
                                color = "black",
                            }

                        },

                    }

                    element.popup = gui.Panel {

                        styles = Styles.Default,
                        width = "auto",
                        height = "auto",
                        flow = "vertical",

                        gui.Input {

                            fontSize = 11,
                            height = 20,
                            width = 280,
                            placeholderText = "Search...",
                            hasFocus = true,

                            edit = function(element)
                                element.parent:FireEventTree("search", string.lower(element.text))
                            end,

                            confirm = function(element)
                                local query = element.text
                                if query ~= "" then
                                    local resultCount = 0
                                    for _, child in ipairs(monsterlist.children) do
                                        if not child:HasClass("collapsed") then
                                            resultCount = resultCount + 1
                                        end
                                    end
                                    track("search_query", {
                                        query = query,
                                        resultCount = resultCount,
                                        context = "encounter_add_monster",
                                        dailyLimit = 20,
                                    })
                                end
                            end,

                        },

                        monsterlist,
                    }
                end,


            },

            gui.Label {

                text = "Drag a monster here from Bestiary",
                fontSize = 14,
                valign = "bottom",
                halign = "center",
                bmargin = 10,

                thinkTime = 0.2,
                think = function(element)
                    local monsterinfo = dmhub.GetSelectedMonster()

                    if monsterinfo == nil then
                        element.text = "Select a monster in the Bestiary to add"
                        element.parent.bgimage = true
                        element.parent.selfStyle.bgcolor = "black"
                    else
                        local monster = assets.monsters[monsterinfo.monsterid]
                        element.text = string.format("<b>%s</b> is selected. Click to add", monster.name)
                        local monsterimage = monster.appearance.portraitId
                        if monsterimage ~= nil then
                            element.parent.bgimage = monsterimage
                            element.parent.selfStyle.bgcolor = "#ffffff11"
                        else
                            element.parent.bgimage = true
                            element.parent.selfStyle.bgcolor = "black"
                        end
                    end
                end
            }




        },]]

        appearancesCheck,

        gui.Button {

            classes = { "sizeM" },
            text = options.mode or "Save",
            halign = "center",
            valign = "bottom",

            press = function(button)
                if options.save then
                    options.save()
                else
                    analytics.Event {
                        type = "create_encounter",
                        encounter = self.name,
                        eds = self:CountEDS(),
                    }

                    dmhub.SetAndUploadTableItem("encounters", self)
                end

                button:FindParentWithClass("editorPanel"):DestroySelf()
            end,

        },
    }

    resultPanel:FireEventTree("update")
    return resultPanel
end

function Encounter.CreateEditorDialog(encounter, options)
    local editorPanel

    editorPanel = gui.Panel {

        classes = { "editorPanel" },
        styles = ThemeEngine.GetStyles(),

        halign = "center",
        valign = "center",
        width = 800,
        height = 800,

        gui.Panel {

            classes = { "dialog" },

            halign = "center",
            width = "100%",
            height = "100%",

            encounter.Editor(encounter, options),

            gui.Button {
                classes = { "closeButton" },
                halign = "right",
                valign = "top",
                press = function()
                    editorPanel:DestroySelf()
                end,
            },

        }

    }

    ThemeEngine.OnThemeChanged(mod, function()
        if editorPanel ~= nil and editorPanel.valid then
            editorPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    GameHud.instance.documentsPanel:AddChild(editorPanel)
end

CreateEncounterPanel = function()
    --- @type Panel

    local inspectorPanel

    inspectorPanel = gui.Panel {
        id = "inspector-panel",
        styles = ThemeEngine.GetStyles(),
        hpad = 6,
        width = "100%",
        height = "auto",
        flow = "vertical",
        monitorAssets = true,
        bgimage = true,
        bgcolor = "clear",

        xrightClick = function(panel)
            panel.popup = gui.ContextMenu {
                entries = {

                    {
                        text = "Add folder",
                        click = function()
                            panel.popup = nil
                            local newfolder = EncounterFolder.new {}
                            dmhub.SetAndUploadTableItem(EncounterFolder.tableName, newfolder)
                        end
                    }
                },
            }
        end,

        events = {
            create = function(panel)
                panel:FireEvent("update")
            end,

            refreshAssets = function(panel)
                panel:FireEvent("update")
            end,

            update = function(panel)
                local children = {}

                local encounters = dmhub.GetTable('encounters')
                local encounterfolders = dmhub.GetTable('encounterfolders')

                local index = 1

                for key, encounterfolder in unhidden_pairs(encounterfolders) do
                    local folder = gui.TreeNode {

                        text = encounterfolder.name,
                        width = "100%",
                        editable = true,
                        dragTarget = true,

                        change = function(self, newname)
                            encounterfolder.name = newname
                            dmhub.SetAndUploadTableItem(encounterfolder.tableName, encounterfolder)
                        end,

                        contentPanel = gui.Panel {

                            classes = { "bg" },
                            height = 100,
                            width = 100,
                        }

                    }

                    children[index] = folder
                    index = index + 1
                end

                for key, encounter in unhidden_pairs(encounters) do
                    local monstertable = encounter.monsters

                    --choose boss monster to be 'head' of the encounter

                    local highestev = 0
                    local headmonster = nil

                    for key, quantity in pairs(monstertable) do
                        local currentmonster = assets.monsters[key]

                        --print("venla", key, "current monster = ", currentmonster)

                        if headmonster == nil then
                            headmonster = currentmonster
                        end

                        if currentmonster.properties:EV() > highestev then
                            highestev = currentmonster.properties:EV()
                            headmonster = currentmonster
                        end

                        --print("venla", currentmonster.properties)
                    end

                    local headmonsteravatar = true

                    if headmonster ~= nil then
                        headmonsteravatar = headmonster.appearance.portraitId
                    end

                    --boss/headmonster code over

                    children[index] = gui.Panel {

                        classes = { "featureCard" },
                        width = "90%",
                        height = 110,
                        halign = "left",
                        flow = "vertical",
                        pad = 1,
                        vmargin = 8,
                        draggable = true,

                        canDragOnto = function(self, target)
                            return target ~= nil and target:HasClass("folder")
                        end,

                        drag = function(self, target)
                            print("venla: dragged to a panel")
                        end,

                        data = {
                            encounter = encounter,
                        },

                        click = function(self)
                            gui.SetFocus(self)
                            for _, sibling in ipairs(self.parent.children) do
                                sibling:SetClass("selected", false)
                            end
                            self:SetClass("selected", true)
                        end,

                        --king panel for name and difficulty
                        gui.Panel {

                            classes = { "featureCardHeader", "expanded" },
                            width = "100%",
                            height = "23%",
                            flow = "horizontal",

                            gui.Label {

                                text = string.format("%s", encounter.name),
                                halign = "left",
                                valign = "center",
                                height = "auto",
                                width = "auto",
                                fontSize = 16,
                                lmargin = 12,

                            },

                            gui.Label {

                                text = string.format("EV: %d", encounter:CountEDS()),
                                halign = "right",
                                valign = "center",
                                height = "auto",
                                width = "auto",
                                fontSize = 16,
                                rmargin = 12,

                                thinkTime = 0.2,

                                think = function(label)
                                    label.text = string.format("EV: %d", encounter:CountEDS())
                                end

                            },
                        },

                        gui.Panel {

                            classes = { "featureCardBody" },
                            width = "100%",
                            height = "85%",
                            flow = "horizontal",

                            --monster image panel
                            gui.Panel {

                                classes = { "image" },
                                width = "35%",
                                height = "91%",
                                bgimage = headmonsteravatar,
                                halign = "left",

                                thinkTime = 0.2,

                                think = function(panel)
                                    local mainmonster = Encounter.MainMonster(encounter)
                                    if mainmonster ~= nil then
                                        panel.bgimage = mainmonster.appearance:GetPortraitId()
                                    end
                                end

                            },

                            --king panel for monster list
                            gui.Panel {

                                vscroll = true,
                                height = "auto",
                                maxHeight = 80,
                                width = "65%",
                                gui.Label {

                                    width = "100%",
                                    height = "100%",
                                    flow = "vertical",

                                    lmargin = 5,
                                    fontSize = 16,
                                    textAlignment = "TopLeft",
                                    text = Encounter.Describe(encounter),

                                    --[[local monstertable = encounter.monsters

                                    back
                                    createSmallMonsterDisplay(),

                                    create = function(panel)
                                        panel:FireEvent("displayMonsters")
                                    end,

                                    displayMonsters = function(panel)
                                        local children = {}

                                        for monsterid, quantity in pairs(monstertable) do
                                            children[#children + 1] = createSmallMonsterDisplay(monsterid, quantity)
                                        end

                                        panel.children = children
                                    end]]

                                },

                            },

                        },

                        gui.Button {
                            classes = { "deleteButton", "sizeXs" },
                            x = 18,

                            floating = true,
                            halign = "right",
                            valign = "top",
                            press = function(element)
                                encounter.hidden = true
                                dmhub.SetAndUploadTableItem("encounters", encounter)
                                inspectorPanel:FireEvent("update")
                            end,
                        },

                        gui.Button {
                            classes = { "settingsButton", "sizeXs" },
                            x = 18,
                            y = 20,
                            floating = true,
                            halign = "right",
                            valign = "top",

                            swallowPress = true,
                            press = function(element)
                                local encounterCopy = DeepCopy(encounter)
                                encounterCopy:CreateEditorDialog { mode = "Save" }
                            end,
                        },

                    }

                    index = index + 1
                end

                panel.children = children
            end,
        }
    }

    local addEncounterButton = gui.Button {

        classes = { "addButton", "sizeXs" },
        halign = "center",

        click = function(element)
            local dock = element:FindParentWithClass("dockablePanel")
            assert(dock ~= nil)

            dock.popupPositioning = "panel"

            local newEncounter = Encounter.new()

            local editorPanel

            editorPanel = gui.Panel {

                classes = { "editorPanel" },
                styles = ThemeEngine.GetStyles(),

                halign = "center",
                valign = "center",
                width = 400,
                height = 500,

                gui.Panel {

                    classes = { "dialog" },

                    halign = "center",
                    width = 360,
                    height = 500,

                    newEncounter.Editor(newEncounter, { mode = "Create" }),

                    gui.Button {
                        classes = { "closeButton" },
                        halign = "right",
                        valign = "top",
                        press = function()
                            editorPanel:DestroySelf()
                        end,
                    },

                }

            }

            ThemeEngine.OnThemeChanged(mod, function()
                if editorPanel ~= nil and editorPanel.valid then
                    editorPanel.styles = ThemeEngine.GetStyles()
                end
            end)

            GameHud.instance.documentsPanel:AddChild(editorPanel)
        end

    }

    local resultPanel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",
        inspectorPanel,
        addEncounterButton,

    }

    ThemeEngine.OnThemeChanged(mod, function()
        if inspectorPanel ~= nil and inspectorPanel.valid then
            inspectorPanel.styles = ThemeEngine.GetStyles()
        end
    end)

    return resultPanel
end

dmhub.GetSelectedEncounter = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.encounter) then
        return nil
    end

    local encounter = gui.GetFocus().data.encounter
    return encounter:CloneForNumberOfHeroes()
end

-- Global-search provider: encounters ("In this game"). DM-only content. The
-- Encounter creator selects encounters internally with no per-encounter
-- deep-link, so activation opens the panel (coarse open; exact-select is a
-- later refinement).
Search.RegisterProvider{
    id = "encounters",
    bucket = "ingame",
    typeLabel = "Encounter",
    enumerate = function(needle)
        if not dmhub.isDM then
            return {}
        end
        local results = {}
        local t = dmhub.GetTable("encounters") or {}
        for k,v in unhidden_pairs(t) do
            local name = (type(v) == "table" and rawget(v, "name")) or nil
            if type(name) == "string" and Search.MatchesText(name, needle) then
                results[#results+1] = {
                    name = name,
                    score = Search.Score(name, needle),
                    actionLabel = "Open in Encounter Builder",
                    activate = function()
                        DockablePanel.LaunchPanelByName("Encounter creator", "show")
                    end,
                }
            end
        end
        return results
    end,
}
