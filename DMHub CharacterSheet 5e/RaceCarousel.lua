local mod = dmhub.GetModLoading()

function CharSheet.RaceChoicePanel(options)
    local resultPanel

    local leftPanel
    local rightPanel

    local racesTable = dmhub.GetTable(Race.tableName)

    local racePanels = {}

    local carousel

    local GetTargetIndex = function()
        local result = 1 - round(carousel.targetPosition)
        if result < 1 then
            result = 1
        end

        if result > #racePanels then
            result = #racePanels
        end
        return result
    end

    local SetTargetIndex = function(index)
        carousel.targetPosition = -(index - 1)
    end

    local GetCurrentIndex = function()
        local index1 = clamp(1 - math.floor(carousel.currentPosition), 1, #racePanels)
        local index2 = clamp(1 - math.ceil(carousel.currentPosition), 1, #racePanels)

        if index1 == index2 then
            return {
                primary = index1,
                secondary = index2,
                ratio = 0,
            }
        end

        local deadzone = 0.2
        local ratio = carousel.currentPosition - math.floor(carousel.currentPosition)
        if ratio < deadzone then
            ratio = 0
        elseif ratio > (1 - deadzone) then
            ratio = 1
        else
            ratio = (ratio - deadzone) / (1 - deadzone * 2)
        end

        if ratio > 0.5 then
            ratio = 1 - ratio
            return {
                primary = index2,
                secondary = index1,
                ratio = ratio,
            }
        else
            return {
                primary = index1,
                secondary = index2,
                ratio = ratio,
            }
        end
    end

    for k, race in pairs(racesTable) do
        if race:try_get("hidden", false) == false then
            local portraitPanel = gui.Panel {
                classes = { "racePortrait" },
                bgimage = race.portraitid,

                imageLoaded = function(element)
                    if element.bgimageWidth * 1.5 < element.bgimageHeight then
                        element.selfStyle.imageRect = {
                            x1 = 0,
                            x2 = 1,
                            y1 = 0,
                            y2 = (element.bgimageWidth / element.bgimageHeight) * 1.5,
                        }
                    else
                        element.selfStyle.imageRect = {
                            x1 = 0,
                            x2 = (element.bgimageHeight / element.bgimageWidth) / 1.5,
                            y1 = 0,
                            y2 = 1,
                        }
                    end
                end,


            }
            local portraitContainer = gui.Panel {
                classes = { "racePortraitContainer" },
                portraitPanel,
            }
            local shadow = gui.Panel {
                classes = { "racePortraitShadow" },
                interactable = false,
            }
            racePanels[#racePanels + 1] = gui.Panel {
                data = {
                    index = 0,
                    race = race,
                    last_carousel = nil,
                },
                flow = "none",
                carousel = function(element, f)
                    if f == element.data.last_carousel then
                        return
                    end

                    element.data.last_carousel = f

                    local x = math.abs(f)
                    element.selfStyle.scale = 1 / (x * 0.3 + 1)
                    element.selfStyle.y = x * 30

                    local opacity = clamp(2.5 - x, 0, 1)

                    shadow.selfStyle.opacity = opacity
                    portraitContainer.selfStyle.opacity = opacity
                    portraitPanel.selfStyle.opacity = opacity
                end,
                click = function(element)
                    SetTargetIndex(element.data.index)
                    resultPanel:FireEventTree("targetIndexChanged")
                end,
                classes = { "racePanel" },
                shadow,
                portraitContainer,
            }
        end
    end

    table.sort(racePanels, function(a, b) return a.data.race.name < b.data.race.name end)
    for i, panel in ipairs(racePanels) do
        panel.data.index = i
    end

    carousel = gui.Carousel {
        data = {
            last_pos = nil,
        },
        horizontalCurve = 0.2,
        verticalCurve = 0.1,
        maximumVelocity = 2,

        halign = "center",
        valign = "top",

        itemSpacing = 220,
        vmargin = 32,
        width = 800,
        height = 600,

        children = racePanels,



        refreshBuilder = function(element)
            local creature = CharacterSheet.instance.data.info.token.properties
            if creature:try_get("raceid") ~= nil then
                element.draggable = false
                for i, panel in ipairs(racePanels) do
                    if panel.data.race.id == creature.raceid then
                        element.currentPosition = -(i - 1)
                        element.targetPosition = -(i - 1)
                        panel:SetClass("hidden", false)
                    else
                        panel:SetClass("hidden", true)
                    end
                end
            else
                for i, panel in ipairs(racePanels) do
                    panel:SetClass("hidden", false)
                end
                element.draggable = true
            end
        end,

        create = function(element)
            element.targetPosition = 0
            element:FireEvent("refreshBuilder")
        end,

        move = function(element)
            if element.currentPosition ~= element.data.last_pos then
                element.data.last_pos = element.currentPosition
                resultPanel:FireEventTree("refreshCarousel")
            end
        end,

        drag = function(element)
            element.targetPosition = round(element.currentPosition)
            resultPanel:FireEventTree("targetIndexChanged")
        end,

        styles = {
            {
                selectors = { "racePanel" },
                width = 400,
                height = "150% width",
                halign = "center",
                valign = "center",
            },
            {
                selectors = { "racePortraitContainer" },
                width = "100%",
                height = "100%",
                bgcolor = "black",
                borderColor = Styles.textColor,
                borderWidth = 2,
                bgimage = "panels/square.png",
            },
            {
                selectors = { "racePortraitContainer", "parent:hover", "~hasrace" },
                brightness = 1.5,
            },
            {
                selectors = { "racePortrait" },
                width = "100%-4",
                height = "100%-4",
                halign = "center",
                valign = "center",
                bgcolor = "white",
            },
            {
                selectors = { "racePortraitShadow" },
                bgimage = "panels/square.png",
                bgcolor = "#00000099",
                width = "100%+64",
                height = "100%+64",
                halign = "center",
                valign = "center",
                cornerRadius = 8,
                borderColor = "#00000099",
                borderWidth = 32,
                borderFade = true,
            }
        }
    }

    local selectionPanel = gui.Panel {
        width = 280,
        height = 40,
        halign = "center",
        valign = "top",
        flow = "horizontal",

        styles = {
            {
                selectors = { "paging-arrow", "hasrace" },
                collapsed = 1,
            }
        },

        gui.PagingArrow {
            facing = -1,
            press = function(element)
                if GetTargetIndex() > 1 then
                    SetTargetIndex(GetTargetIndex() - 1)
                end
                resultPanel:FireEventTree("targetIndexChanged")
            end,

            targetIndexChanged = function(element)
                element:SetClass("hidden", GetTargetIndex() <= 1)
            end,
        },

        gui.Label {
            text = "Elf",
            halign = "center",
            valign = "center",
            fontSize = 32,
            minFontSize = 10,
            bold = false,
            width = "80%",
            height = "100%",
            textAlignment = "center",

            refreshCarousel = function(element)
                local child = element.children[1]

                local info = GetCurrentIndex()

                element.text = racePanels[info.primary].data.race.name
                element.selfStyle.opacity = 1 - info.ratio

                child.text = racePanels[info.secondary].data.race.name
                child.selfStyle.opacity = info.ratio
            end,

            gui.Label {
                fontSize = 32,
                minFontSize = 10,
                bold = false,
                width = "100%",
                height = "100%",
                textAlignment = "center",
            },
        },

        gui.PagingArrow {
            facing = 1,
            press = function(element)
                if GetTargetIndex() < #racePanels then
                    SetTargetIndex(GetTargetIndex() + 1)
                end
                resultPanel:FireEventTree("targetIndexChanged")
            end,
            targetIndexChanged = function(element)
                element:SetClass("hidden", GetTargetIndex() >= #racePanels)
            end,
        },
    }

    local m_selectedSubrace = nil

    local m_subraceCurrentRace = nil
    local subracePanels = {}
    local subraceListPanel = nil
    subraceListPanel = gui.Panel {
        classes = { "subraceList" },
        width = 600,
        height = "100% available",
        vmargin = 16,
        hpad = 8,
        vpad = 4,
        flow = "vertical",
        vscroll = true,

        styles = {
            {
                selectors = { "subraceList", "hasrace" },
                collapsed = 1,
            },
            {
                selectors = { "subraceItem" },
                flow = "horizontal",
                height = 96,
                width = 500,
                vmargin = 4,
                halign = "left",
                bgimage = "panels/square.png",
                bgcolor = "clear",
            },
            {
                selectors = { "subraceItem", "hover" },
                bgcolor = "#ffffff22"
            },
            {
                selectors = { "subraceItem", "selected" },
                bgcolor = "#ffffff22"
            },
        },

        refreshCarousel = function(element)
            local info = GetCurrentIndex()

            --we don't cross-fade, just fade-in.
            local ratio = 1 - info.ratio * 2

            local race = racePanels[info.primary].data.race

            if race == m_subraceCurrentRace then
                return
            end

            m_subraceCurrentRace = race

            local subracesTable = dmhub.GetTable('subraces') or {}

            local subraces = {}

            for raceid, raceInfo in pairs(subracesTable) do
                if raceInfo:try_get("hidden", false) == false and raceInfo:try_get("parentRace", "none") == race.id then
                    subraces[#subraces + 1] = raceInfo
                end
            end

            for i, subrace in ipairs(subraces) do
                subracePanels[i] = subracePanels[i] or gui.Panel {
                    classes = { "subraceItem" },

                    data = {
                        subrace = nil,
                    },
                    subrace = function(element, subrace)
                        element.data.subrace = subrace
                    end,

                    press = function(element)
                        m_selectedSubrace = element.data.subrace.id
                        m_subraceCurrentRace = nil --force refresh
                        resultPanel:FireEventTree("refreshCarousel")
                    end,

                    gui.Panel {
                        borderColor = Styles.textColor,
                        borderWidth = 2,
                        bgcolor = "black",
                        bgimage = "panels/square.png",
                        width = 64,
                        height = 96,
                        halign = "left",

                        gui.Panel {
                            width = "100%-4",
                            height = "100%-4",
                            bgcolor = "white",
                            halign = "center",
                            valign = "center",

                            subrace = function(element, subrace)
                                local portraitid = subrace.portraitid
                                if portraitid == "" then
                                    local racesTable = dmhub.GetTable("races")
                                    local race = racesTable[subrace.parentRace]
                                    portraitid = race.portraitid
                                end

                                if portraitid == "" then
                                    element:SetClass("hidden", true)
                                else
                                    element:SetClass("hidden", false)
                                    element.bgimage = portraitid
                                end
                            end,

                            imageLoaded = function(element)
                                --if element.bgimageWidth > element.bgimageHeight then
                                --    element.selfStyle.imageRect = {
                                --        x1 = 0,
                                --        x2 = 1,
                                --        y1 = 0,
                                --        y2 = element.bgimageWidth/element.bgimageHeight,
                                --    }
                                --else
                                --    element.selfStyle.imageRect = {
                                --        x1 = 0,
                                --        x2 = element.bgimageHeight/element.bgimageWidth,
                                --        y1 = 0,
                                --        y2 = 1,
                                --    }
                                --end
                            end,

                        }
                    },

                    gui.Label {
                        width = 360,
                        height = 64,
                        hmargin = 32,
                        textAlignment = "left",
                        fontSize = 32,
                        minFontSize = 12,

                        subrace = function(element, subrace)
                            element.text = subrace.name
                        end,
                    },
                }

                subracePanels[i]:FireEventTree("subrace", subrace)
            end

            for i, panel in ipairs(subracePanels) do
                panel:SetClass("collapsed", i > #subraces)
            end

            if #subraces > 0 then
                local nselected = 1
                for i = 1, #subraces do
                    if subraces[i].id == m_selectedSubrace then
                        nselected = i
                        break
                    end
                end

                m_selectedSubrace = subraces[nselected].id

                for i = 1, #subracePanels do
                    subracePanels[i]:SetClass("selected", nselected == i)
                end
            end

            element.children = subracePanels
        end,
    }

    local displayedIndex = nil
    local displayedSubrace = nil

    local GetSelectedRace = function()
        local creature = CharacterSheet.instance.data.info.token.properties
        if creature:has_key("raceid") then
            return creature:Race()
        end

        if racePanels == nil or displayedIndex == nil or racePanels[displayedIndex] == nil then
            return nil
        end

        local race = racePanels[displayedIndex].data.race
        return race
    end

    local GetSelectedSubrace = function()
        local creature = CharacterSheet.instance.data.info.token.properties
        if creature:has_key("raceid") then
            return creature:Subrace()
        end

        local race = GetSelectedRace()
        local subrace = nil
        if m_selectedSubrace ~= nil then
            local subracesTable = dmhub.GetTable('subraces') or {}
            local foundSubrace = subracesTable[m_selectedSubrace]
            if foundSubrace ~= nil and foundSubrace:try_get("parentRace") == race.id then
                subrace = foundSubrace
            end
        end

        return subrace
    end



    local descriptionContainer = gui.Panel {
        halign = "center",
        valign = "top",
        borderWidth = 2,
        borderColor = Styles.textColor,
        vmargin = 24,
        width = "100%",
        height = "100% available",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        flow = "vertical",


        refreshCarousel = function(element)
            local child = element.children[1]

            local info = GetCurrentIndex()

            --we don't cross-fade, just fade-in.
            local ratio = 1 - info.ratio * 2

            if displayedIndex == info.primary and displayedSubrace == m_selectedSubrace then
                element:FireEventTree("fade", ratio)
                return
            end

            displayedIndex = info.primary
            displayedSubrace = m_selectedSubrace

            local race = GetSelectedRace()
            local subrace = GetSelectedSubrace()
            if subrace == nil then
                subrace = race
            end

            element:FireEventTree("refreshDescription", race, subrace)
            element:FireEventTree("fade", ratio)
        end,

        gui.Panel {
            vscroll = true,
            height = "100%",
            width = "100%",

            styles = {
                {
                    selectors = { "separator" },
                    bgimage = "panels/square.png",
                    bgcolor = Styles.textColor,
                    height = 2,
                    width = "100%",
                    halign = "center",
                    valign = "top",
                    vmargin = 8,
                },
                {
                    selectors = { "padding" },
                    width = 2,
                    height = 20,
                },
                {
                    selectors = { "sectionTitle" },
                    fontSize = 22,
                    height = 30,
                    bold = false,
                },
                {
                    selectors = { "featureDescription" },
                    width = "100%",
                    height = "auto",
                },
                {
                    selectors = { "collapsibleHeading" },
                    width = "100%",
                    height = 30,
                    bgimage = "panels/square.png",
                    bgcolor = "#ffffff00",
                },
                {
                    selectors = { "collapsibleHeading", "hover" },
                    bgcolor = "#ffffff11",
                },
            },

            gui.Panel {
                width = "95%",
                height = "auto",
                halign = "center",
                flow = "vertical",
                vmargin = 32,

                gui.Label {
                    bold = false,
                    fontSize = 32,
                    valign = "top",
                    halign = "left",
                    height = 36,
                    width = "100%",
                    textAlignment = "left",

                    refreshDescription = function(element, race, subrace)
                        element.text = subrace.name
                    end,

                    fade = function(element, ratio)
                        element.selfStyle.opacity = ratio
                    end,

                    gui.Button {

                        text = string.format("Change %s", GameSystem.RaceName),
                        halign = "right",
                        valign = "top",
                        fontSize = 14,

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            element:SetClass("collapsed", creature:try_get("raceid") == nil)
                        end,

                        click = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            creature.raceid = nil
                            creature.subraceid = nil

                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,
                    }
                },

                gui.Panel {
                    classes = { "separator" },
                },

                gui.Panel {
                    classes = { "padding" },
                },

                gui.Panel {
                    classes = { "collapsibleHeading" },
                    create = function(element)
                        element:FireEvent("click")
                    end,
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("raceOverview"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label {
                        classes = { "sectionTitle" },
                        text = tr("Overview"),
                        refreshDescription = function(element, race, subrace)
                            if race == subrace then
                                element.text = tr("Overview")
                            else
                                element.text = string.format("%s Overview", race.name)
                            end
                        end,
                    },
                    gui.CollapseArrow {
                        halign = "right",
                        valign = "center",
                    },
                },

                gui.Panel {
                    classes = { "separator" },
                },

                gui.Label {
                    id = "raceOverview",
                    classes = { "featureDescription" },
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    refreshDescription = function(element, race, subrace)
                        element.text = race.details
                    end,

                    fade = function(element, ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel {
                    classes = { "padding" },
                },

                gui.Panel {
                    refreshDescription = function(element, race, subrace)
                        element:SetClass("collapsed", race == subrace or subrace.details == "")
                    end,
                    vmargin = 0,
                    hmargin = 0,
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    gui.Panel {
                        classes = { "collapsibleHeading" },
                        click = function(element)
                            element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                            element:Get("subraceOverview"):SetClass("collapsed", element:HasClass("collapseSet"))
                        end,
                        gui.Label {
                            classes = { "sectionTitle" },
                            text = tr("Overview"),
                            refreshDescription = function(element, race, subrace)
                                element.text = subrace.name
                            end,
                        },
                        gui.CollapseArrow {
                            halign = "right",
                            valign = "center",
                        },
                    },

                    gui.Panel {
                        classes = { "separator" },
                    },



                    gui.Label {
                        id = "subraceOverview",
                        classes = { "featureDescription" },
                        width = "100%",
                        wrap = true,
                        height = "auto",
                        refreshDescription = function(element, race, subrace)
                            if race ~= subrace then
                                element.text = subrace.details
                            end
                        end,

                        fade = function(element, ratio)
                            element.selfStyle.opacity = ratio
                        end,
                    },


                    gui.Panel {
                        classes = { "padding" },
                    },
                },


                gui.Panel {
                    classes = { "collapsibleHeading" },
                    create = function(element)
                        element:FireEvent("click")
                    end,
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("raceLore"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label {
                        classes = { "sectionTitle" },
                        text = tr("Lore"),
                        refreshDescription = function(element, race, subrace)
                            if race == subrace then
                                element.text = tr("Lore")
                            else
                                element.text = string.format("Lore")
                            end
                        end,
                    },
                    gui.CollapseArrow {
                        halign = "right",
                        valign = "center",
                    },
                },

                gui.Panel {
                    classes = { "separator" },
                },

                gui.Label {
                    id = "raceLore",
                    classes = { "featureDescription" },
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    refreshDescription = function(element, race, subrace)
                        element.text = race.lore
                    end,

                    fade = function(element, ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel {
                    classes = { "padding" },
                },

                gui.Panel {
                    classes = { "collapsibleHeading" },
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("traits"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label {
                        classes = { "sectionTitle" },
                        text = tr("Traits"),
                    },
                    gui.CollapseArrow {
                        halign = "right",
                        valign = "center",
                    },
                },

                gui.Panel {
                    classes = { "separator" },
                },


                gui.Panel {
                    id = "traits",
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    --race
                    CharSheet.FeatureDetailsPanel {
                        alert = function(element)
                            resultPanel:FireEvent("alert")
                        end,
                    },

                    --subrace
                    CharSheet.FeatureDetailsPanel {
                        alert = function(element)
                            resultPanel:FireEvent("alert")
                        end,
                    },

                    data = {
                        featurePanels = {},
                        featureDetailsPanels = nil,
                    },

                    refreshBuilder = function(element)
                        local race = GetSelectedRace()
                        if race == nil then
                            return
                        end

                        local subrace = GetSelectedSubrace()
                        element:FireEvent("refreshDescription", race, subrace or race, true)
                    end,
                    refreshDescription = function(element, race, subrace, nofire)
                        if element.data.featureDetailsPanels == nil then
                            element.data.featureDetailsPanels = element.children
                        end

                        local detailsPanels = element.data.featureDetailsPanels

                        local textItems = {
                            string.format(tr("<b>Size.</b>  Your people are size %s creatures."), race.size),
                            string.format(tr("<b>Height.</b>  Your people are %s tall."), race.height),
                            string.format(tr("<b>Weight.</b>  Your people weigh %s pounds."), race.weight),
                            string.format(tr("<b>Life Expectancy.</b>  Your people live %s years."), race.lifeSpan),
                            string.format(tr("<b>Speed.</b>  Your base walking speed is %s"),
                                MeasurementSystem.NativeToDisplayStringWithUnits(race.moveSpeeds.walk)),
                        }

                        if race:IsInherited() then
                            local creature = CharacterSheet.instance.data.info.token.properties
                            if creature ~= nil then
                                local inheritedRace = creature:InheritedAncestry()
                                if inheritedRace ~= nil then
                                    textItems[1] = string.format(
                                        tr(
                                        "<b>Size.</b>  You are a size %s creature, just as you were in your former life."),
                                        inheritedRace.size)
                                else
                                    textItems[1] = string.format(tr(
                                        "<b>Size.</b>  You have the same size as you did in your former life"))
                                end
                            end
                        end

                        if not element:HasClass("hasrace") then
                            for i, p in ipairs(detailsPanels) do
                                p.data.hide = true
                            end

                            local featureDetails = {}
                            race:FillFeatureDetails(nil, {}, featureDetails)

                            if subrace ~= race then
                                subrace:FillFeatureDetails(nil, {}, featureDetails)
                            end


                            for _, f in ipairs(featureDetails) do
                                local text = f.feature:GetSummaryText()
                                if text ~= nil then
                                    textItems[#textItems + 1] = text
                                end
                            end
                        else
                            detailsPanels[1].data.hide = false
                            detailsPanels[2].data.hide = (subrace == race)

                            detailsPanels[1].data.criteria = { race = race }
                            detailsPanels[2].data.criteria = { race = subrace }
                        end


                        local featurePanels = element.data.featurePanels

                        for i, text in ipairs(textItems) do
                            featurePanels[i] = featurePanels[i] or gui.Label {
                                classes = { "featureDescription" },
                            }

                            featurePanels[i].text = text
                        end

                        for i, p in ipairs(featurePanels) do
                            p:SetClass("collapsed", i > #textItems)
                        end



                        local children = {}
                        for i, p in ipairs(featurePanels) do
                            children[#children + 1] = p
                        end

                        for i, p in ipairs(detailsPanels) do
                            children[#children + 1] = p
                        end

                        element.children = children

                        if not nofire then
                            for i, p in ipairs(detailsPanels) do
                                p:FireEventTree("refreshBuilder")
                            end
                        end
                    end,
                },
            },
        },
    }

    leftPanel = gui.Panel {
        id = "leftPanel",
        width = "40%",
        height = "100%",
        halign = "center",
        flow = "vertical",

        gui.Panel {
            id = "carouselContainer",
            flow = "vertical",
            width = "100%",
            height = "auto",
            carousel,
            selectionPanel,

            styles = {
                {
                    selectors = { "#carouselContainer", "hasrace" },
                    y = 132,
                    scale = 1.4,
                    transitionTime = 0.4,
                }
            },
        },
        subraceListPanel,
    }


    rightPanel = gui.Panel {
        width = "40%",
        height = "100%",
        halign = "center",
        flow = "vertical",

        descriptionContainer,

        gui.Button {
            text = "Select",
            halign = "center",
            fontSize = 26,
            bold = true,
            vmargin = 24,
            width = 196,
            height = 64,

            refreshBuilder = function(element)
                local creature = CharacterSheet.instance.data.info.token.properties
                element:SetClass("collapsed", creature:try_get("raceid") ~= nil)
            end,

            click = function(element)
                local creature = CharacterSheet.instance.data.info.token.properties

                local race = GetSelectedRace()
                local subrace = GetSelectedSubrace()

                creature.raceid = race.id
                if subrace ~= nil then
                    creature.subraceid = subrace.id
                else
                    creature.subraceid = nil
                end

                CharacterSheet.instance:FireEvent("refreshAll")
                CharacterSheet.instance:FireEventTree("refreshBuilder")
            end,
        },
    }

    local args = {
        width = "100%",
        height = "100%",
        flow = "horizontal",
        halign = "center",
        valign = "center",

        refreshBuilder = function(element)
            local creature = CharacterSheet.instance.data.info.token.properties
            local hasRace = creature:has_key("raceid")
            element:SetClassTree("hasrace", hasRace)
            if not hasRace then
                resultPanel:FireEvent("alert")
            end
        end,

        leftPanel,
        rightPanel,
    }

    for k, v in pairs(options) do
        args[k] = v
    end

    resultPanel = gui.Panel(args)

    resultPanel:FireEventTree("targetIndexChanged")

    return resultPanel
end
