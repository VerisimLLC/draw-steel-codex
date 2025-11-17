local mod = dmhub.GetModLoading()

local g_numHeroesSetting = setting{
    id = "numheroes",
    description = "Number of Heroes",
    help = "This setting will guide balance of encounters you create.",
    section = "game",
    editor = "dropdown",
    default = 4,
    enum = {
        {
            value = 3,
            text = "Three or Less Heroes",
        },
        {
            value = 4,
            text = "Four Heroes",
        },
        {
            value = 5,
            text = "Five Heroes",
        },
        {
            value = 6,
            text = "Six or More Heroes",
        },
    }
}

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


local CreateEncounterPanel


DockablePanel.Register {
    name = "Encounter creator",
    icon = "icons/standard/Icon_App_EncounterCreator.png",
    minHeight = 200,
    vscroll = true,
    content = function()
        return CreateEncounterPanel()
    end,
}


Encounter = RegisterGameType('Encounter')

Encounter.name = 'New Encounter'

Encounter.tableName = 'encounters'

Encounter.monsters = {}

Encounter.groups = {}

EncounterFolder = RegisterGameType('EncounterFolder')

EncounterFolder.tableName = 'encounterfolders'

EncounterFolder.name = 'New Encounter Folder'




function Encounter.MainMonster(encounter)
    local mainmonster = nil
    for i, group in ipairs(encounter.groups) do
        for monsterid, value in pairs(group.monsters) do
            local monster = assets.monsters[monsterid]
            if mainmonster == nil or monster.properties.ev > mainmonster.properties.ev then
                mainmonster = monster
            end
        end
    end

    return mainmonster
end

function Encounter.CloneForNumberOfHeroes(self, numHeroes)
    numHeroes = numHeroes or g_numHeroesSetting:Get()
    local encounter = DeepCopy(self)
    for i=#encounter.groups,1,-1 do
        if encounter.groups[i].minHeroes ~= nil and encounter.groups[i].minHeroes > numHeroes then
            table.remove(encounter.groups, i)
        end
    end

    return encounter
end

function Encounter.AddMonster(self, monsterid)
    self.monsters = DeepCopy(self.monsters)
    self.monsters[monsterid] = (self.monsters[monsterid] or 0) + 1
end

function Encounter.AddGroup(self)
    self.groups = DeepCopy(self.groups)
    self.groups[#self.groups + 1] = { monsters = {} }
end

function Encounter.CountEDS(self)
    local EDSTotal = 0

    for i, group in ipairs(self.groups) do
        for monsterid, quantity in pairs(group.monsters) do
            local monster = assets.monsters[monsterid]

            if monster.properties.minion then
                EDSTotal = EDSTotal + round((assets.monsters[monsterid].properties.ev * quantity) / 4)
            else
                EDSTotal = EDSTotal + (assets.monsters[monsterid].properties.ev * quantity)
            end
        end
    end

    return EDSTotal
end

function Encounter.Describe(self)
    local monstersingroups = {}

    for i, group in ipairs(self.groups) do
        for monsterid, quantity in pairs(group.monsters) do
            monstersingroups[monsterid] = (monstersingroups[monsterid] or 0) + quantity
        end
    end

    local resultString = ""

    for monsterid, quantity in pairs(monstersingroups) do
        local monster = assets.monsters[monsterid]
        resultString = resultString .. string.format("%d X %s \n", quantity, creature.GetTokenDescription(monster))
    end

    return resultString
end

local function createSmallMonsterDisplay(monsterid, quantity)
    local monster = assets.monsters[monsterid]

    --example of one monster: image + name + quantity BACK
    return gui.Panel {

        bgimage = true,
        bgcolor = "red",
        width = "100%",
        height = 41,
        halign = "left",
        bmargin = 3,

        flow = "horizontal",

        gui.Panel {

            bgimage = monster.appearance.portraitId,
            bgcolor = "white",
            width = 35,
            height = 35,
            halign = "left",
            tmargin = 3,
            lmargin = 3,
            border = 1,
            borderColor = Styles.textColor,

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

        styles = {

            {
                classes = { "addButton" },
                hidden = 1,
            },

            {
                classes = { "addButton", "parent:hover", "~full" },
                hidden = 0,
            },

        },

        width = "90%",
        height = "auto",
        bgimage = true,
        bgcolor = "black",
        valign = "top",
        flow = "vertical",

        maxHeight = 300,
        vscroll = true,


        update = function(element)
            local panels = {}

            for i, group in ipairs(encounter.groups) do
                panels[#panels + 1] = gui.Panel {

                    width = "90%",
                    height = "65",
                    border = 1,
                    borderColor = "white",
                    bgimage = true,
                    bgcolor = "black",
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

                        width = 50,
                        height = 65,
                        borderColor = "white",
                        border = 1,
                        bgimage = true,
                        halign = "left",

                        gui.Label {

                            text = #panels + 1,
                            fontSize = 14,
                            color = "white",
                        }

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

                                panels[#panels + 1] = gui.Panel {

                                    flow = "horizontal",
                                    width = "auto",
                                    height = "auto",
                                    halign = "left",

                                    gui.Label {

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
                                        end


                                    },
                                    gui.Label {

                                        width = "auto",
                                        height = "auto",
                                        fontSize = 16,
                                        text = string.format("X %s", creature.GetTokenDescription(monster)),


                                    },





                                }
                            end

                            element.children = panels

                            if #panels >= 2 then
                                element.parent:SetClassTree("full", true)
                            else
                                element.parent:SetClassTree("full", false)
                            end
                        end

                    },

                    gui.AddButton {

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
                                            local monster = assets.monsters[monsterid]

                                            if monster.properties.minion then
                                                group.monsters[monsterid] = (group.monsters[monsterid] or 0) + 4
                                            else
                                                group.monsters[monsterid] = (group.monsters[monsterid] or 0) + 1
                                            end

                                            element.parent:FireEventTree("create")

                                            element.popup = nil
                                        end


                                    }
                                end
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
                                    end


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



                    gui.DeleteItemButton {
                        width = 16,
                        height = 16,
                        x = 18,

                        floating = true,
                        halign = "right",
                        press = function(element)
                            table.remove(encounter.groups, i)
                            groupkingpanel:FireEvent("update")
                        end,
                    },

                    gui.Label{
                        classes = {"link"},
                        floating = true,
                        fontSize = 12,
                        halign = "right",
                        valign = "bottom",
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        text = "Balancing",
                        press = function(element)
                            local balancing = group.balancing or {}
                            for _,i in ipairs({3,4,5,6,7}) do
                                balancing[i] = balancing[i] or {}
                            end

                            local balancingBaseline = dmhub.DeepCopy(balancing)
                            local children = {}

                            for _,i in ipairs({3,4,5,6,7}) do
                                local info = balancing[i]
                                children[#children+1] = gui.Panel{
                                    flow = "horizontal",
                                    width = "100%",
                                    height = "auto",
                                    gui.Label{
                                        width = 80,
                                        height = "auto",
                                        fontSize = 12,
                                        valign = "center",
                                        text = string.format("%d Heroes", i),
                                    },

                                    gui.Panel{
                                        width = 180,
                                        flow = "vertical",
                                        height = "auto",
                                        gui.Panel{
                                            halign = "right",
                                            flow = "horizontal",
                                            width = "auto",
                                            height = "auto",
                                            vmargin = 4,
                                            gui.Label{
                                                fontSize = 12,
                                                text = "Stamina:",
                                                width = "auto",
                                                height = "auto",
                                                hmargin = 4,
                                            },
                                            gui.Input{
                                                fontSize = 12,
                                                width = 50,
                                                height = 12,
                                                hmargin = 4,
                                                text = info.stamina or "",
                                                characterLimit = 4,
                                                change = function(element)
                                                    local val = tonumber(element.text)
                                                    if val ~= nil then
                                                        balancing[i].stamina = val
                                                    else
                                                        balancing[i].stamina = nil
                                                    end

                                                    element.text = balancing[i].stamina or ""
                                                end,
                                            }
                                        },

                                        gui.Check{
                                            text = "Disable Solo Action",
                                            height = 14,
                                            minWidth = 100,
                                            value = balancing[i].disableSolo or false,
                                            halign = "right",
                                            fontSize = 10,
                                            change = function(element)
                                                balancing[i].disableSolo = element.value
                                            end,
                                        },
                                    },
                                }
                            end

                            local panel = gui.Panel{
                                styles = {
                                    Styles.Default,
                                    Styles.Panel,
                                },
                                classes = {"framedPanel"},
                                width = 260,
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

                            element.popup = panel
                        end,
                    },

                    gui.Panel{
                        floating = true,
                        halign = "right",
                        valign = "top",
                        flow = "horizontal",
                        width = 34,
                        height = 16,
                        press = function(element)
                            local entries = {}
                            for _,i in ipairs({0,3,4,5,6,7}) do
                                entries[#entries+1] = {
                                    text = cond(i == 0, "Always", string.format("%d+ Heroes", i)),
                                    selected = (group.minHeroes or 0) == i,
                                    click = function()
                                        group.minHeroes = cond(i == 0, nil, i)
                                        element.parent:FireEventTree("create")
                                        element.popup = nil
                                    end,
                                }
                            end

                            element.popup = gui.ContextMenu{
                                entries = entries,
                            }
                        end,
                        gui.Label{
                            width = 18,
                            height = 16,
                            fontSize = 12,
                            text = (group.minHeroes and string.format("%d+", group.minHeroes)) or "all",
                            create = function(element)
                                element.text = (group.minHeroes and string.format("%d+", group.minHeroes)) or "all"
                            end,
                        },
                        gui.Panel{
                            bgimage = "icons/icon_app/icon_app_18.png",
                            bgcolor = "white",
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

    local evtotal = monster.properties.ev * quantity

    if monster.properties.minion then
        evtotal = round(evtotal / 4)
    end

    return gui.Panel {

        width = "90%",
        height = 110,
        bgimage = true,
        bgcolor = "black",
        border = 1,
        borderColor = Styles.textColor,
        halign = "center",
        flow = 'horizontal',
        pad = 1,
        bmargin = 8,

        --monster image panel
        gui.Panel {

            width = "35%",
            height = "100%",
            bgimage = monster.appearance.portraitId,
            bgcolor = "white",
            halign = "left",
            border = { 0, 0, 1, 0 },
            borderColor = Styles.textColor,


        },

        --king panel for name and info
        gui.Panel {

            width = "65%",
            height = "100%",
            bgimage = true,
            bgcolor = "black",
            flow = 'vertical',


            gui.Label {

                text = string.format("%s", monster.name),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                text = string.format("Level %d", monster.properties:Level()),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                text = string.format("%d", quantity),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                text = string.format("%s", monster.properties.role),
                halign = "center",
                fontSize = 16,

            },

            gui.Label {

                text = string.format("EV: %d  Total: %d", monster.properties.ev, evtotal),
                halign = "center",
                fontSize = 16,

            },

        },

    }
end



function Encounter.Editor(self, options)
    local resultPanel

    local groupPanel = createGroupPanel(self)

    resultPanel = gui.Panel {

        bgimage = true,
        width = '100%',
        height = '100%',
        flow = 'vertical',

        styles = {

            {
                classes = { 'label' },
                width = "auto",
                height = "auto",
            }

        },

        gui.Label {

            text = self.name,
            fontSize = 16,
            bold = true,
            halign = "center",
            minWidth = 160,
            textAlignment = "center",
            height = 20,
            valign = "top",
            tmargin = 5,


            characterLimit = 20,
            editable = true,
            change = function(label)
                self.name = label.text
            end,

        },

        gui.Divider {

            valign = "top",
        },

        gui.Panel {

            width = "90%",
            height = 30,
            border = 1,
            borderColor = Styles.textColor,
            halign = 'center',
            valign = "top",
            bgimage = true,
            bgcolor = "black",
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

            --[[gui.Label {
                text = string.format("Trivial"),
                fontSize = 14,
                color = "blue",
                halign = "right",
                rmargin = 6,
            }]]

        },

        gui.Label {

            text = 'Groups:',
            fontSize = 16,
            bold = true,
            halign = "center",
            valign = "top",
            tmargin = 4,


        },

        groupPanel,

        gui.Panel {

            width = "90%",
            height = "50",
            border = 1,
            borderColor = "white",
            bgimage = true,
            bgcolor = "black",
            valign = "top",
            tmargin = 5,

            gui.AddButton {

                halign = "center",
                valign = "center",

                click = function(element)
                    local grouppanels = {}

                    self:AddGroup()

                    groupPanel:FireEvent("update")
                end

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



            gui.AddButton {

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
                            end


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

        gui.Button {

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

                    dmhub.SetAndUploadTableItem('encounters', self)
                end

                button:FindParentWithClass('editorPanel'):DestroySelf()
            end

        }
    }


    resultPanel:FireEventTree("update")
    return resultPanel
end

function Encounter.CreateEditorDialog(encounter, options)

    local editorPanel

    editorPanel = gui.Panel {

        classes = { 'editorPanel' },

        halign = 'center',
        valign = 'center',
        width = 400,
        height = 500,


        gui.Panel {

            styles = {
                Styles.Default,
                Styles.Panel,
            },


            classes = { "framedPanel" },


            halign = 'center',
            --bgimage = true,
            width = 360,
            height = 500,
            --bgcolor = "white",

            encounter.Editor(encounter, options),

            gui.CloseButton {

                halign = "right",
                valign = "top",
                press = function()
                    editorPanel:DestroySelf()
                end
            }

        }



    }



    GameHud.instance.documentsPanel:AddChild(editorPanel)
end

CreateEncounterPanel = function()
    --- @type Panel

    local inspectorPanel

    inspectorPanel = gui.Panel {
        id = 'inspector-panel',
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

                            height = 100,
                            width = 100,
                            bgcolor = "red",
                            bgimage = true,
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

                        if currentmonster.properties.ev > highestev then
                            highestev = currentmonster.properties.ev
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

                        width = "90%",
                        height = 110,
                        bgimage = true,
                        bgcolor = "black",
                        halign = "center",
                        flow = 'vertical',
                        pad = 1,
                        bmargin = 8,
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
                        end,

                        classes = { "encounterpanel" },

                        styles = {

                            {
                                border = 1,
                                borderColor = Styles.textColor,
                                classes = { "encounterpanel" },

                            },

                            {
                                border = 3,
                                borderColor = "white",
                                brightness = 1.4,
                                classes = { "encounterpanel", "focus" },

                            },


                        },

                        --king panel for name and difficulty
                        gui.Panel {

                            width = "100%",
                            height = "23%",
                            flow = 'horizontal',
                            bgimage = true,
                            bgcolor = "clear",
                            --DAVID: (bug to fix) making the border partial ex: {0, 0, 1, 0} doesn't works
                            border = 1,
                            borderColor = Styles.textColor,


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

                            width = "100%",
                            height = "85%",
                            flow = "horizontal",

                            --monster image panel
                            gui.Panel {

                                width = "35%",
                                height = "91%",
                                bgimage = headmonsteravatar,
                                bgcolor = "white",
                                halign = "left",
                                border = { 0, 0, 1, 0 },
                                borderColor = Styles.textColor,

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




                        gui.DeleteItemButton {
                            width = 16,
                            height = 16,
                            x = 18,

                            floating = true,
                            halign = "right",
                            press = function(element)
                                encounter.hidden = true
                                dmhub.SetAndUploadTableItem('encounters', encounter)
                                inspectorPanel:FireEvent("update")
                            end,
                        },

                        gui.SettingsButton {
                            width = 16,
                            height = 16,
                            x = 18,
                            y = 20,
                            floating = true,
                            halign = "right",

                            swallowPress = true,
                            press = function(element)
                                local encounterCopy = DeepCopy(encounter)
                                encounterCopy:CreateEditorDialog{mode = "Save"}
                            end,
                        }

                    }

                    index = index + 1
                end

                panel.children = children
            end,
        }
    }

    local addEncounterButton = gui.AddButton {

        halign = 'center',

        click = function(element)
            local dock = element:FindParentWithClass("dockablePanel")
            assert(dock ~= nil)

            dock.popupPositioning = "panel"

            local newEncounter = Encounter.new()

            local editorPanel

            editorPanel = gui.Panel {

                classes = { 'editorPanel' },

                halign = 'center',
                valign = 'center',
                width = 400,
                height = 500,


                gui.Panel {

                    styles = {
                        Styles.Default,
                        Styles.Panel,
                    },


                    classes = { "framedPanel" },


                    halign = 'center',
                    --bgimage = true,
                    width = 360,
                    height = 500,
                    --bgcolor = "white",

                    newEncounter.Editor(newEncounter, { mode = "Create" }),

                    gui.CloseButton {

                        halign = "right",
                        valign = "top",
                        press = function()
                            editorPanel:DestroySelf()
                        end
                    }

                }



            }



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

    return resultPanel
end

dmhub.GetSelectedEncounter = function()
    if gui.GetFocus() == nil or (not gui.GetFocus().data.encounter) then
        return nil
    end

    local encounter = gui.GetFocus().data.encounter
    return encounter:CloneForNumberOfHeroes()
end
