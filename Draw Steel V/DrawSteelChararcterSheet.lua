local mod = dmhub.GetModLoading()

local bg_color = "#1D1D1D"
--local border_color = "#A3A3A3"
local border_color = "white"

local g_mainActionId = "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
local g_maneuverId = "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b"
local g_triggeredactionId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"
local g_abilityActionSortOrder = {
    [g_mainActionId] = -2,
    [g_maneuverId] = -1,
    [g_triggeredactionId] = 0,
}

local SwatchBlack = "#000000"
local SwatchNeutral1 = "#ffffff"
local SwatchNeutral2 = "#ffffff"
local fontScaling = 1
local g_styles = {
    {
        selectors = { "FontNumbers" },
        fontSize = 16 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Header1" },
        fontSize = 12 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Header2" },
        fontSize = 8 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        uppercase = true,
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Subheader" },
        fontSize = 6 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        uppercase = true,
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "SubheaderBold" },
        fontSize = 6 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        uppercase = true,
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Body" },
        fontSize = 8 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "BodyBold" },
        fontSize = 8 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Details" },
        fontSize = 7 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Details_Skill_Untrained" },
        fontSize = 7 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = SwatchNeutral1,
        width = "auto",
        height = 10 * fontScaling,
        valign = "top",
        lmargin = 8,
    },
    {
        selectors = { "Details_Skill_Trained" },
        fontSize = 7 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = '#8cdecf',
        width = "auto",
        height = 10 * fontScaling,
        valign = "top",
        lmargin = 8,
    },
    {
        selectors = { "DetailsBold" },
        fontSize = 7 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Annotation*" },
        fontSize = 6 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = SwatchBlack,
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "panel_bg_hero" },
        bgcolor = SwatchNeutral1
    },
    {
        selectors = { "panel_bg_monster" },
        bgcolor = "#910d0d",
        borderColor = 'red',
    },
    {
        selectors = { "panel_hero_filled" },
        bgimage = true,
        bgcolor = bg_color,
        halign = "center",
        valign = "top",
        width = 260,
        height = 50,
        borderWidth = 1,
        borderColor = border_color,
        --cornerRadius = 16,
        --beveledcorners = true,
        --bgcolor = SwatchLight,
        --bgcolor = "red",
        --bgimage = "panels/square.png",
        flow = "vertical",
        opacity = 0.9,
        --interactable = false,
    },
    {
        selectors = { "panel_hero_label" },
        fontSize = 12,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = border_color,
        height = "auto",
        valign = "top",
        halign = "center",
        width = "auto",
        bmargin = 8,

    },
}

local PopupStyles = {

    {
        valign = 'bottom',
        halign = 'center',
        width = 'auto',
        height = 'auto',
        bgcolor = 'black',
        flow = 'vertical',
        fontSize = 12,
    },
    {
        selectors = { 'popupWindow' },
        valign = 'bottom',
        halign = 'center',
        width = 300,
        height = 'auto',
        bgcolor = 'black',
        flow = 'vertical',
        borderWidth = 2,
        borderColor = 'white',
        pad = 6,
    },
    {
        selectors = { 'popupPanel' },
        flow = 'horizontal',
        width = 'auto',
        height = 'auto',
        vmargin = 4,
    },
    {
        selectors = { 'popupLabel' },
        color = 'white',
        fontSize = 16,
        width = 'auto',
        height = 'auto',
        minWidth = 220,
        valign = "center",
    },
    {
        selectors = { 'popupValue' },
        color = 'white',
        fontSize = 16,
        width = 'auto',
        height = 'auto',
        minWidth = 40,
    },

    {
        selectors = { "formPanel" },
        flow = "horizontal",
        width = '100%',
        height = 20,
    },
    {
        selectors = { 'editable' },
        color = '#aaaaff',
        priority = 2,
    },
    {
        selectors = { 'option' },
        bgcolor = 'black',
        width = '100%',
        height = 20,
    },
    {
        selectors = { 'option', 'selected' },
        bgcolor = '#880000',
    },
    {
        selectors = { 'option', 'hover' },
        bgcolor = '#880000',
    },
    {
        selectors = { 'input' },
        bold = true,
        fontFace = "inter",
        fontSize = 14,
        height = 18,
        width = 180,
    },
}




function creature:IsWinded()
    if self:CurrentHitpoints() <= (self:MaxHitpoints() / 2) then
        return true
    else
        return false
    end
end

local function GetHeroicResourceOrMaliceCost(ability, symbols)
    symbols = symbols or {}

    local token = CharacterSheet.instance.data.info.token
    local cost = ability:GetCost(token, symbols)
    if cost == nil or cost.details == nil then
        return nil
    end

    local heroicResourceEntry = nil
    for _, entry in ipairs(cost.details) do
        if entry.cost == CharacterResource.heroicResourceId or entry.cost == CharacterResource.maliceResourceId then
            heroicResourceEntry = entry
            break
        end
    end

    if heroicResourceEntry == nil then
        return nil
    end

    return heroicResourceEntry.quantity
end

local function CreateAbilityPanel()
    local resultPanel
    local m_ability = nil

    resultPanel = gui.Panel {
        classes = { "abilityHeading" },
        width = "100%",
        height = 60,
        vmargin = 0,
        linger = function(element)
            local token = CharacterSheet.instance.data.info.token
            element.tooltip = CreateAbilityTooltip(m_ability, {
                token = token,
                halign = "right",
                width = 500,
                pad = 8,
            })
        end,
        ability = function(element, ability, c)
            m_ability = ability
            element:SetClass("collapsed", false)
        end,

        rightClick = function(element)
            element.popup = gui.ContextMenu {
                entries = {

                    {
                        text = "Copy",
                        click = function()
                            element.popup = nil
                            dmhub.CopyToInternalClipboard(m_ability)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end
                    }
                },
            }
        end,

        gui.Panel {
            classes = { "abilityIconPanel" },
            ability = function(element, ability, c)
                element.bgimage = ability.iconid
                element.selfStyle = ability.display
            end,
        },

        gui.Panel {
            classes = { "abilityInfoPanel" },
            gui.Label {
                classes = { "abilityTitle" },
                text = "Ability Name",
                ability = function(element, ability, c)
                    element.text = ability.name
                end,
            },
            gui.Label {
                classes = { "abilityInfoLabel" },
                text = "Keywords",
                ability = function(element, ability, c)
                    local keywords = table.keys(ability.keywords)
                    table.sort(keywords)
                    element.text = string.join(keywords, ", ")
                end,
            },
        },

        gui.SettingsButton {
            floating = true,
            halign = "right",
            valign = "top",
            width = 16,
            height = 16,
            tmargin = 2,
            rmargin = 4,
            ability = function(element, ability, c)
                element:SetClass("hidden", not c:IsActivatedAbilityInnate(ability))
            end,
            press = function(element)
                CharacterSheet.instance:AddChild(m_ability:ShowEditActivatedAbilityDialog {
                    close = function(element)
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end,
                    delete = function(element)
                        CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(m_ability)
                    end,
                })
            end,
        },

        gui.Panel {
            classes = { "costDiamond", "collapsed" },
            floating = true,
            rotate = 135,
            gui.Panel {
                classes = { "costInnerDiamond" },
                gui.Label {
                    classes = { "abilityCostLabel" },
                    rotate = -135,


                    ability = function(element, ability, c)
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element.parent.parent:SetClass("collapsed", true)
                            return
                        end

                        element.parent.parent:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                    end,
                },
            },
        },

    }

    return resultPanel
end

local function CreateTriggeredAbilityPanel()
    local resultPanel
    local m_triggeredAbility = nil

    resultPanel = gui.Panel {
        classes = { "abilityHeading" },
        width = "100%",
        height = 60,
        vmargin = 0,
        linger = function(element)
            local token = CharacterSheet.instance.data.info.token
            element.tooltip = gui.TooltipFrame(m_triggeredAbility:Render{token = token}, {width = 500, halign = "right", valign = "center", pad = 8})
        end,
        triggeredAbility = function(element, ability, c)
            m_triggeredAbility = ability
            element:SetClass("collapsed", false)
        end,

        --[[ rightClick = function(element)
            element.popup = gui.ContextMenu {
                entries = {

                    {
                        text = "Copy",
                        click = function()
                            element.popup = nil
                            dmhub.CopyToInternalClipboard(m_triggeredAbility)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end
                    }
                },
            }
        end, ]]

        gui.Panel {
            classes = { "abilityInfoPanel" },
            gui.Label {
                classes = { "abilityTitle" },
                hmargin = 8,
                text = "Ability Name",
                triggeredAbility = function(element, ability, c)
                    element.text = ability.name
                end,
            },
            gui.Label {
                classes = { "abilityInfoLabel" },
                hmargin = 8,
                text = "Keywords",
                triggeredAbility = function(element, ability, c)
                    local keywords = table.keys(ability.keywords)
                    table.sort(keywords)
                    element.text = string.join(keywords, ", ")
                end,
            },
        },

        --[[ gui.SettingsButton {
            floating = true,
            halign = "right",
            valign = "top",
            width = 16,
            height = 16,
            tmargin = 2,
            rmargin = 4,
            ability = function(element, ability, c)
                element:SetClass("hidden", not c:IsActivatedAbilityInnate(ability))
            end,
            press = function(element)
                CharacterSheet.instance:AddChild(m_triggeredAbility:ShowEditActivatedAbilityDialog {
                    close = function(element)
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end,
                    delete = function(element)
                        CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(m_ability)
                    end,
                })
            end,
        }, ]]

        --[[ gui.Panel {
            classes = { "costDiamond", "collapsed" },
            floating = true,
            rotate = 135,
            gui.Panel {
                classes = { "costInnerDiamond" },
                gui.Label {
                    classes = { "abilityCostLabel" },
                    rotate = -135,
                    triggeredAbility = function(element, ability, c)
                        local cost = GetHeroicResourceOrMaliceCost(ability,
                            { mode = 1, charges = ability:DefaultCharges() })

                        if cost == nil then
                            element.parent.parent:SetClass("collapsed", true)
                            return
                        end

                        element.parent.parent:SetClass("collapsed", false)

                        element.text = string.format("%d", cost)
                    end,
                },
            },
        }, ]]

    }

    return resultPanel
end

local function CreateAbilityListPanel()
    local resultPanel

    local m_abilityPanels = {}
    local m_triggeredAbilityPanels = {}
    local m_mainActionsLabel = gui.Label {
        classes = { "submenuHeading" },
        data = { ord = g_mainActionId },
        width = "100%",
        color = "white",
        fontSize = 20,
        text = "Main Actions",
        press = function(element)
            element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
            resultPanel:FireEvent("refreshToken")
        end,
        gui.CollapseArrow {
            halign = "right",
            valign = "center",
        },
    }

    local m_maneuversLabel = gui.Label {
        classes = { "submenuHeading" },
        data = { ord = g_maneuverId },
        width = "100%",
        color = "white",
        fontSize = 20,
        text = "Maneuvers",
        press = function(element)
            element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
            resultPanel:FireEvent("refreshToken")
        end,
        gui.CollapseArrow {
            halign = "right",
            valign = "center",
        },
    }

    local m_triggersLabel = gui.Label {
        classes = { "submenuHeading" },
        data = { ord = g_triggeredactionId },
        width = "100%",
        color = "white",
        fontSize = 20,
        text = "Triggered Actions",
        press = function(element)
            element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
            resultPanel:FireEvent("refreshToken")
        end,
        gui.CollapseArrow {
            halign = "right",
            valign = "center",
        },
    }

    local m_otherActionsLabel = gui.Label {
        classes = { "submenuHeading" },
        data = { ord = "other" },
        width = "100%",
        color = "white",
        fontSize = 20,
        text = "Other Abilities",
        press = function(element)
            element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
            resultPanel:FireEvent("refreshToken")
        end,
        gui.CollapseArrow {
            halign = "right",
            valign = "center",
        },
    }

    m_mainActionsLabel:SetClassTree("collapseSet", true)
    m_maneuversLabel:SetClassTree("collapseSet", true)
    m_triggersLabel:SetClassTree("collapseSet", true)
    m_otherActionsLabel:SetClassTree("collapseSet", true)

    local GetActionId = function(ability)
        local actionid = ability:ActionResource()
        if actionid ~= g_mainActionId and actionid ~= g_maneuverId then
            actionid = "other"
        end
        return actionid
    end

    resultPanel = gui.Panel {
        m_mainActionsLabel,
        m_maneuversLabel,
        m_triggersLabel,
        m_otherActionsLabel,
        styles = {
            Styles.ActionMenu,
            {
                selectors = { "submenuHeading", "hover" },
                borderColor = "white",
            },
        },
        width = "100%-12",
        height = "auto",
        bgimage = true,
        bgcolor = "clear",
        flow = "vertical",
        halign = "left",
        valign = "top",
        lmargin = 4,
        tmargin = 2,
        refreshToken = function(element)
            local token = CharacterSheet.instance.data.info.token
            local c = token.properties
            local abilities = c:GetActivatedAbilities { characterSheet = true }
            local children = {}

            local showAbilities = {}
            if not m_mainActionsLabel:HasClass("collapseSet") then
                showAbilities[g_mainActionId] = true
            end

            if not m_maneuversLabel:HasClass("collapseSet") then
                showAbilities[g_maneuverId] = true
            end

            if not m_otherActionsLabel:HasClass("collapseSet") then
                showAbilities["other"] = true
            end

            local filteredAbilities = {}
            for _, ability in ipairs(abilities) do
                local actionResource = GetActionId(ability)
                if showAbilities[actionResource] then
                    filteredAbilities[#filteredAbilities + 1] = ability
                end
            end

            -- Collect triggered abilities separately
            local triggeredAbilities = {}
            if not m_triggersLabel:HasClass("collapseSet") then
                triggeredAbilities = c:GetTriggeredActions()
                table.sort(triggeredAbilities, function(a, b)
                    return a.name < b.name
                end)
            end

            abilities = filteredAbilities

            table.sort(abilities, function(a, b)
                local action_a = GetActionId(a)
                local action_b = GetActionId(b)
                if action_a ~= action_b then
                    return (g_abilityActionSortOrder[action_a or ""] or 0) <
                        (g_abilityActionSortOrder[action_b or ""] or 0)
                end

                return a.name < b.name
            end)

            -- Create panels for activated abilities
            while #m_abilityPanels < #abilities do
                local panel = CreateAbilityPanel()
                m_abilityPanels[#m_abilityPanels + 1] = panel
            end

            for i = 1, #abilities do
                local resource = GetActionId(abilities[i])
                m_abilityPanels[i]:FireEventTree("ability", abilities[i], c)
                m_abilityPanels[i].data.ord = resource
                children[#children + 1] = m_abilityPanels[i]
            end

            -- Create panels for triggered abilities
            while #m_triggeredAbilityPanels < #triggeredAbilities do
                local panel = CreateTriggeredAbilityPanel()
                m_triggeredAbilityPanels[#m_triggeredAbilityPanels + 1] = panel
            end

            for i = 1, #triggeredAbilities do
                m_triggeredAbilityPanels[i]:FireEventTree("triggeredAbility", triggeredAbilities[i], c)
                m_triggeredAbilityPanels[i].data.ord = g_triggeredactionId
                children[#children + 1] = m_triggeredAbilityPanels[i]
            end

            --now insert the headings at the right locations.
            local headings = { m_mainActionsLabel, m_maneuversLabel, m_triggersLabel, m_otherActionsLabel }
            local j = 1
            while #headings > 0 and j <= #children do
                for n, heading in ipairs(headings) do
                    if headings[n].data.ord == children[j].data.ord then
                        for m = n, 1, -1 do
                            table.insert(children, j, headings[m])
                            table.remove(headings, m)
                        end
                        break
                    end
                end
                j = j + 1
            end

            for _, heading in ipairs(headings) do
                children[#children + 1] = heading
            end

            for i = #abilities + 1, #m_abilityPanels do
                m_abilityPanels[i]:SetClass("collapsed", true)
                children[#children + 1] = m_abilityPanels[i]
            end

            for i = #triggeredAbilities + 1, #m_triggeredAbilityPanels do
                m_triggeredAbilityPanels[i]:SetClass("collapsed", true)
                children[#children + 1] = m_triggeredAbilityPanels[i]
            end

            element.children = children
        end,
    }

    return resultPanel
end


function CharSheet.CharacterSheetAndAvatarPanel()
    local controllerDropdown
    if dmhub.isDM then
        controllerDropdown = gui.Dropdown {
            width = 220,
            height = 26,
            vmargin = 4,
            fontSize = 15,
            halign = "center",
            refreshToken = function(element, info)
                if info.token.charid == nil then
                    element:SetClass("hidden", true)
                    return
                end

                element:SetClass("hidden", false)

                local options = {
                }

                if info.token.hasTokenOnAnyMap then
                    options[#options + 1] = {
                        id = "gm",
                        text = "Director Controlled",
                    }
                end

                local partyids = GetAllParties()
                for _, partyid in ipairs(partyids) do
                    local party = GetParty(partyid)
                    options[#options + 1] = {
                        id = partyid,
                        text = party.name
                    }
                end

                for _, userid in ipairs(dmhub.users) do
                    local sessionInfo = dmhub.GetSessionInfo(userid)
                    if not sessionInfo.dm then
                        options[#options + 1] = {
                            id = userid,
                            text = sessionInfo.displayName,
                        }
                    end
                end

                element.options = options

                local ownerId = info.token.ownerId
                if ownerId == "PARTY" then
                    element.idChosen = info.token.partyId
                elseif ownerId ~= nil and ownerId ~= "" then
                    element.idChosen = ownerId
                else
                    element.idChosen = "gm"
                end
            end,

            change = function(element)
                if element.idChosen == "gm" then
                    CharacterSheet.instance.data.info.token.ownerId = nil
                elseif GetParty(element.idChosen) ~= nil then
                    CharacterSheet.instance.data.info.token.partyId = element.idChosen
                else
                    CharacterSheet.instance.data.info.token.ownerId = element.idChosen
                end
            end,
        }
    end


    local resultPanel
    resultPanel = gui.Panel {
        id = "ds_avatarInnerPanel",
        classes = { "statsPanel" },
        vscroll = true,
        valign = "top",
        flow = "vertical",

        styles = {
        },

        gui.Panel {
            id = "ds_tokenImage",
            halign = "center",
            width = 256,
            height = 256,
            tmargin = 88,

            gui.CreateTokenImage(nil, {
                width = "100%",
                height = "100%",

                refreshAppearance = function(element, info)
                    element:FireEventTree("token", info.token)
                end,

            }),

            gui.Panel {
                id = "ds_avatarOverlay",
                width = "100%",
                height = "100%",
                bgimage = "panels/square.png",
                bgcolor = "black",

                click = function(element)
                    CharacterSheet.instance:FireEvent("toggleAppearance")
                end,

                styles = {
                    {
                        selectors = { "#ds_avatarOverlay" },
                        opacity = 0,
                    },
                    {
                        selectors = { "#ds_avatarOverlay", "hover" },
                        opacity = 0.8,
                        transitionTime = 0.2,
                    },
                    {
                        selectors = { "parent:press" },
                        brightness = 0.7,
                        transitionTime = 0.2,
                    },
                },

                gui.Label {
                    width = "100%",
                    height = "20%",
                    halign = "center",
                    valign = "center",
                    bgimage = "panels/square.png",
                    bgcolor = "black",
                    text = "Customize Appearance",
                    color = "white",
                    textAlignment = "center",
                    fontSize = 14,
                    interactable = false,

                    styles = {
                        {
                            opacity = 0,
                        },
                        {
                            selectors = { "parent:hover" },
                            opacity = 1,
                            transitionTime = 0.2,
                        },
                        {
                            selectors = { "parent:press" },
                            brightness = 0.7,
                            transitionTime = 0.2,
                        },
                    },

                },
            },
        },



        gui.Panel {

            bgimage = true,
            bgcolor = "clear",
            width = 256,
            height = "auto",
            flow = "vertical",
            halign = "center",
            valign = "top",
            tmargin = 15,

            --name of character
            gui.Label {

                text = "Name",
                color = border_color,
                fontSize = 20,
                textAlignment = "center",
                characterLimit = 30,

                bgimage = true,
                bgcolor = bg_color,
                borderWidth = 2,
                borderColor = border_color,

                width = "100%",
                height = 50,
                halign = "center",

                editable = true,


                refreshToken = function(element, info)
                    element.text = info.token.name
                end,

                change = function(element)
                    local token = CharacterSheet.instance.data.info.token

                    token.name = element.text
                    token:UploadAppearance()
                end,

                gui.Panel {

                    classes = { "privacyIcon" },
                    swallowPress = true,

                    refreshToken = function(element, info)
                        element:SetClass("inactive", not info.token.namePrivate)
                    end,

                    press = function(element)
                        local token = CharacterSheet.instance.data.info.token

                        token.namePrivate = not token.namePrivate

                        token:UploadAppearance()

                        CharacterSheet.instance:FireEvent('refreshAll')
                    end

                },

            },

            --name label
            gui.Label {

                text = "Name",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",


            },

            --ancestry of character
            gui.Label {

                text = "Ancestry",
                color = border_color,
                fontSize = 20,
                textAlignment = "center",

                bgimage = true,
                bgcolor = bg_color,
                borderWidth = 2,
                borderColor = border_color,

                width = "100%",
                height = 50,
                halign = "center",
                valign = "top",
                tmargin = 10,
                characterLimit = 32,
                change = function(element)
                    local token = CharacterSheet.instance.data.info.token
                    token.properties.monster_type = element.text
                    CharacterSheet.instance:FireEvent('refreshAll')
                end,

                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        element.text = info.token.properties:try_get("monster_type", "")
                        if info.token.properties:IsMonster() and element.text == "" then
                            element.text = "(No monster type)"
                            element:SetClass("invalid", true)
                        else
                            element:SetClass("invalid", false)
                        end
                        --element.text = info.token.properties:RaceOrMonsterType()
                        --element.text = creature.GetTokenDescription(element)
                        element.editable = true
                    else
                        element.text = info.token.properties:RaceOrMonsterType()
                        element.editable = false
                    end
                end


            },

            --ancestry label
            gui.Label {

                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        element.text = "Monster"
                    else
                        element.text = "Ancestry"
                    end
                end,
                text = "Ancestry",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",


            },

            --class of character
            gui.Label {

                text = "Class",
                color = border_color,
                fontSize = 20,
                minFontSize = 12,
                textAlignment = "center",

                bgimage = true,
                bgcolor = bg_color,
                borderWidth = 2,
                borderColor = border_color,

                hpad = 8,
                width = "100%",
                height = 50,
                halign = "center",
                valign = "top",
                tmargin = 10,
                --[[
                gui.Dropdown {
                    halign = "center",
                    valign = "bottom",
                    data = { dirty = true },
                    options = {},
                    sort = true,
                    hasSearch = true,
                    monitorAssets = { "ObjectTables" },
                    refreshAssets = function(element)
                        element.data.dirty = true
                    end,
                    refreshToken = function(element, info)
                        if info.token.properties:IsMonster() then
                            if element.data.dirty then
                                local options = {}
                                options[#options + 1] = {
                                    id = "none",
                                    text = "None",
                                }
                                local t = dmhub.GetTable(MonsterGroup.tableName)
                                for k, v in unhidden_pairs(t) do
                                    options[#options + 1] = { text = v.name, id = k }
                                end
                                element.options = options
                                element.data.dirty = false
                            end
                            element.idChosen = info.token.properties:try_get("groupid", "none")
                            element:SetClass("hidden", false)
                        else
                            element:SetClass("hidden", true)
                        end
                    end,

                    change = function(element)
                        local token = CharacterSheet.instance.data.info.token
                        if element.idChosen == "none" then
                            token.properties.groupid = nil
                        else
                            token.properties.groupid = element.idChosen
                        end
                        CharacterSheet.instance:FireEvent('refreshAll')
                    end,
                },
                --]]

                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        local bandid = info.token.properties:try_get("groupid", "none")
                        local t = dmhub.GetTable(MonsterGroup.tableName)
                        local band = t[bandid]
                        local s = ""
                        if band == nil then
                            s = "-"
                        else
                            s = band.name
                            local keywords = {}
                            for keyword, _ in pairs(info.token.properties.keywords or {}) do
                                if keyword ~= band.name then
                                    keywords[#keywords + 1] = keyword
                                end
                            end

                            table.sort(keywords)
                            for _, keyword in ipairs(keywords) do
                                s = s .. "," .. keyword
                            end
                        end

                        element.text = s
                        return
                    end


                    local classesTable = dmhub.GetTable('classes')

                    local classes = info.token.properties:get_or_add("classes", {})
                    for i, entry in ipairs(classes) do
                        local classInfo = classesTable[entry.classid]
                        if classInfo ~= nil then
                            element.text = classInfo.name
                            return
                        end
                    end

                    element.text = "-"
                end,

                gui.SettingsButton {
                    floating = true,
                    halign = "right",
                    valign = "top",
                    margin = 2,
                    width = 16,
                    height = 16,
                    refreshToken = function(element, info)
                        element:SetClass("collapsed", not info.token.properties:IsMonster())
                    end,
                    press = function(element)
                        if element.popup ~= nil then
                            element.popup = nil
                        else
                            local token = CharacterSheet.instance.data.info.token

                            local monsterKeywords = {}

                            local monsterOptions = {}
                            monsterOptions[#monsterOptions + 1] = { id = "none", text = "None" }

                            local t = dmhub.GetTable(MonsterGroup.tableName)
                            for k, v in unhidden_pairs(t) do
                                monsterOptions[#monsterOptions + 1] = { text = v.name, id = k }
                                monsterKeywords[#monsterKeywords + 1] = { id = v.name, text = v.name }
                            end

                            --make sure we also include any keywords the monster has in already.
                            for keyword, _ in pairs(token.properties.keywords or {}) do
                                local alreadyExists = false
                                for _, entry in ipairs(monsterKeywords) do
                                    if entry.id == keyword then
                                        alreadyExists = true
                                        break
                                    end
                                end

                                if not alreadyExists then
                                    monsterKeywords[#monsterKeywords + 1] = { id = keyword, text = keyword }
                                end
                            end

                            table.sort(monsterKeywords, function(a, b) return a.text < b.text end)

                            local resultPanel
                            resultPanel = gui.TooltipFrame(
                                gui.Panel {
                                    width = 340,
                                    height = "auto",
                                    styles = {
                                        Styles.Default,
                                        PopupStyles,
                                        CharSheet.GetCharacterSheetStyles(),
                                    },

                                    destroy = function(element)
                                        --if the monster has a band, make sure it has the keyword too.
                                        local token = CharacterSheet.instance.data.info.token
                                        local band = t[token.properties:try_get("groupid", "none")]
                                        if band ~= nil then
                                            token.properties.keywords = token.properties.keywords or {}
                                            token.properties.keywords[band.name] = true
                                        end

                                        CharacterSheet.instance:FireEvent('refreshAll')
                                    end,

                                    children = {

                                        gui.Panel {
                                            flow = "horizontal",
                                            width = "auto",
                                            height = "auto",
                                            gui.Label {
                                                width = 120,
                                                fontSize = 18,
                                                bold = true,
                                                height = 24,
                                                text = "Band:",
                                            },
                                            gui.Dropdown {
                                                sort = true,
                                                hasSearch = true,
                                                options = monsterOptions,
                                                idChosen = token.properties:try_get("groupid", "none"),
                                                change = function(element)
                                                    local token = CharacterSheet.instance.data.info.token
                                                    if element.idChosen == nil then
                                                        token.properties.groupid = nil
                                                    else
                                                        token.properties.groupid = element.idChosen
                                                    end
                                                end,
                                            },
                                        },

                                        gui.Divider {
                                            width = "80%",
                                            height = 1,
                                            vmargin = 4,
                                        },

                                        gui.Panel {
                                            flow = "horizontal",
                                            width = "auto",
                                            height = "auto",
                                            gui.Label {
                                                width = 120,
                                                fontSize = 18,
                                                bold = true,
                                                height = 24,
                                                text = "Keywords:",
                                            },

                                            gui.SetEditor {
                                                value = rawget(token.properties, "keywords") or {},
                                                addItemText = "Add Keyword...",
                                                options = monsterKeywords,
                                                change = function(element, value)
                                                    local token = CharacterSheet.instance.data.info.token
                                                    token.properties.keywords = value
                                                end,
                                            }
                                        },
                                    }
                                },

                                {
                                    halign = "right",
                                    valign = "center",
                                    interactable = true,
                                }
                            )

                            element.popup = resultPanel
                        end
                    end,
                },
            },

            --class label
            gui.Label {
                text = "Class",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",

                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        element.text = "Type"
                    else
                        element.text = "Class"
                    end
                end,
            },

            --subclass of character
            gui.Label {

                classes = { "monstercollapse", "followercollapse" },
                text = "Subclass",
                color = border_color,
                fontSize = 20,
                textAlignment = "center",

                bgimage = true,
                bgcolor = bg_color,
                borderWidth = 2,
                borderColor = border_color,

                width = "100%",
                height = 50,
                halign = "center",
                valign = "top",
                tmargin = 10,

                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        return
                    end

                    local classesTable = dmhub.GetTable('classes')

                    local classes = info.token.properties:GetSubclasses()
                    for i, entry in ipairs(classes) do
                        element.text = entry.name
                        return
                    end

                    element.text = "-"
                end

            },

            --subclass label
            gui.Label {
                classes = { "monstercollapse", "followercollapse" },

                text = "Subclass",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",
            },

            --monster organization.
            gui.Dropdown {
                classes = { "monsteronly" },
                options = {
                    { id = "minion",  text = "Minion" },
                    { id = "horde",   text = "Horde" },
                    { id = "platoon", text = "Platoon" },
                    { id = "elite",   text = "Elite" },
                    { id = "leader",  text = "Leader" },
                    { id = "solo",    text = "Solo" },
                },
                refreshToken = function(element, info)
                    local c = info.token.properties
                    if not c:IsMonster() then
                        return
                    end

                    if c.minion then
                        element.idChosen = "minion"
                        return
                    end

                    element.idChosen = c:Organization() or "none"
                end,
                change = function(element)
                    local c = CharacterSheet.instance.data.info.token.properties

                    if c.minion and element.idChosen ~= "minion" then
                        c.minionSquad = nil
                    end
                    c.minion = (element.idChosen == "minion")

                    local org = c:Organization()
                    if org ~= nil then
                        c.role = string.upper_first(element.idChosen) .. string.sub(c.role, #org + 1)
                    else
                        c.role = string.upper_first(element.idChosen)
                    end
                    CharacterSheet.instance:FireEvent('refreshAll')
                end,
            },

            gui.Label {
                classes = { "monsteronly" },
                text = "Organization",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",
            },


            --Followers only
            gui.Dropdown {
                classes = { "followeronly" },
                options = {
                    { id = "artisan", text = "Artisan"},
                    { id = "retainer", text = "Retainer"},
                    { id = "sage", text = "Sage"},
                },
                refreshToken = function(element, info)
                    local c = info.token.properties

                    if not c:IsFollower() then
                        return
                    end

                    if c:try_get("followerType") == nil then
                        c.followerType = "artisan"
                    end
                    element.idChosen = c.followerType
                end,
                change = function(element)
                    local c = CharacterSheet.instance.data.info.token.properties

                    c.followerType = element.idChosen
                    c.retainer = (element.idChosen == "retainer")

                    CharacterSheet.instance:FireEvent('refreshAll')
                end,
            },

            gui.Label {
                classes = { "followeronly" },
                text = "Follower Type",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",
            },

            --monster role.
            gui.Dropdown {
                classes = { "monsterorfolloweronly" },
                options = {
                    { id = "ambusher",   text = "Ambusher" },
                    { id = "artillery",  text = "Artillery" },
                    { id = "brute",      text = "Brute" },
                    { id = "controller", text = "Controller" },
                    { id = "defender",   text = "Defender" },
                    { id = "harrier",    text = "Harrier" },
                    { id = "hexer",      text = "Hexer" },
                    { id = "mount",      text = "Mount" },
                    { id = "skirmisher", text = "Skirmisher" },
                    { id = "support",    text = "Support" },
                },
                refreshToken = function(element, info)
                    if not info.token.properties:IsMonster() then
                        return
                    end

                    local c = info.token.properties
                    local org = c:Organization()
                    if org == "solo" or org == "leader" then
                        element:SetClass("collapsed", true)
                        return
                    end

                    element:SetClass("collapsed", false)

                    element.idChosen = c:Role() or "none"
                end,
                change = function(element)
                    local c = CharacterSheet.instance.data.info.token.properties

                    local org = c:Organization() or "platoon"

                    c.role = string.upper_first(org) .. " " .. string.upper_first(element.idChosen)
                    CharacterSheet.instance:FireEvent('refreshAll')
                end,
            },

            gui.Label {
                classes = { "monsterorfolloweronly" },
                text = "Role",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",
                refreshToken = function(element, info)
                    if not info.token.properties:IsMonster() then
                        return
                    end
                    local c = info.token.properties
                    local org = c:Organization()
                    if org == "solo" or org == "leader" then
                        element:SetClass("collapsed", true)
                        return
                    end

                    element:SetClass("collapsed", false)
                end,
            },

            controllerDropdown,

            --Controlled by
            gui.Label {

                text = "Controlled by",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",


            },

            -- Titles
            gui.Multiselect {
                options = Title.GetDropdownList(),
                addItemText = "Grant title...",
                refreshToken = function(element, info)
                    element:SetClass("collapsed", info.token.properties:IsMonster())
                    local v = info.token.properties:GetTitles()
                    element.value = info.token.properties:GetTitles()
                    -- element:FireEvent("refreshSet")
                end,
                change = function(element, value)
                    local token = CharacterSheet.instance.data.info.token
                    local creature = token.properties
                    creature:SetTitles(value)
                end,
            },
            gui.Label {

                text = "Titles",
                color = border_color,
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",

                refreshToken = function(element, info)
                    element:SetClass("collapsed", info.token.properties:IsMonster())
                end,
            },
        },


        --[[gui.Panel {
            classes = { "panel_hero_filled" },
            --id = "characterAncestryPanel",
            CharSheet.CharacterNameLabel(),
        },
        gui.Label {
            classes = { "panel_hero_label" },
            text = "Name",
        },
        ----------------------------------------
        -- Ancestry Box
        ----------------------------------------
        gui.Panel {

            bgimage = true,
            bgcolor = bg_color,
            borderWidth = 2,
            borderColor = border_color,
            beveledcorners = true,
            refreshToken = function(element, info)
                if info.token.properties:IsMonster() then
                    element:SetClass("panel_bg_hero", false)
                    element:SetClass("panel_bg_monster", true)
                else
                    element:SetClass("panel_bg_monster", false)
                    element:SetClass("panel_bg_hero", true)
                end
            end,
            classes = { "panel_hero_filled" },
            interactable = false,

            gui.Label {

                color = border_color,
                width = 260,
                height = 50,
                textAlignment = "center",
                fontSize = 25,

                halign = "center",
                valign = "center",
                refreshAppearance = function(element, info)
                    element:SetClass("collapsed", info.token.properties == nil)
                end,
                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        element.text = info.token.properties:try_get("monster_type", "")
                        if info.token.properties:IsMonster() and element.text == "" then
                            element.text = "(No monster type)"
                            element:SetClass("invalid", true)
                        else
                            element:SetClass("invalid", false)
                        end
                        --element.text = info.token.properties:RaceOrMonsterType()
                        --element.text = creature.GetTokenDescription(element)
                    else
                        element.text = info.token.properties:RaceOrMonsterType()
                    end
                end
            },
        },
        gui.Label {
            classes = { "panel_hero_label" },
            text = "Ancestry",
            refreshToken = function(element, info)
                if info.token.properties:IsMonster() then
                    element.text = "Monster Entry"
                else
                    element.text = "Ancestry"
                end
            end
        },

        -- CLASS
        gui.Panel {
            classes = { "panel_hero_filled" },
            gui.Panel {
                id = "characterLevelsPanel",
                classes = {},

                refreshAppearance = function(element, info)
                    element:SetClass("collapsed",
                        info.token.properties == nil or info.token.properties.typeName ~= "character")
                end,

                refreshCharacterInfo = function(element, character)
                    local currentPanels = element.children


                    local classesTable = dmhub.GetTable('classes')
                    local children = {}

                    local classes = character:get_or_add("classes", {})
                    for i, entry in ipairs(classes) do
                        local classInfo = classesTable[entry.classid]
                        if classInfo ~= nil then
                            local label = currentPanels[i] or gui.Label {
                                color = border_color,
                                width = 260,
                                height = "100%",
                                textAlignment = "center",
                                fontSize = 25,

                                halign = "center",
                                valign = "center",
                            }

                            label.text = string.format("%s %d", classInfo.name, entry.level)

                            children[#children + 1] = label
                        elseif info.token.properties:IsMonster() then
                            local label = currentPanels[i] or gui.Label {
                                classes = { "statsLabel", "classLevelLabel", "heading" },
                            }

                            label.text = info.token.properties.role

                            children[#children + 1] = label
                        end
                    end

                    element.children = children
                end
            },
        },
        gui.Label {
            classes = { "panel_hero_label" },
            text = "Class",
            refreshToken = function(element, info)
                if info.token.properties:IsMonster() then
                    element.text = "Monster Role"
                else
                    element.text = "Class"
                end
            end
        },

        -- SUBCLASS
        gui.Panel {
            classes = { "panel_hero_filled" },
            gui.Panel {
                id = "characterLevelsPanel",

                --This function is called by the character sheet system when the displayed token is updated. Here we just hide the
                --panel if a monster is being shown. But we can probably get rid of this for the Codex?
                refreshAppearance = function(element, info)
                    element:SetClass("collapsed",
                        info.token.properties == nil or info.token.properties.typeName ~= "character")
                end,

                --this function is called by the character sheet system whenever there is a CHARACTER ("hero") in the character sheet. It's not called if displaying a monster.
                --For the Codex, character sheets are probably ONLY for characters, so we don't even have to worry about monsters being shown?
                refreshCharacterInfo = function(element, character)
                    --this is the panels the class has with whatever it was showing previously. It's good for performance to
                    --reuse panels rather than destroy them so we are effectively building a new list of child panels here but
                    --reusing what we can.
                    local currentChildren = element.children

                    local children = {}

                    local subclasses = character:GetSubclasses()
                    for i, subclass in ipairs(subclasses) do
                        local label = currentChildren[i] or gui.Label {
                            classes = { "statsLabel", "classLevelLabel" },
                        }
                        label.text = subclass.name
                        children[#children + 1] = label
                    end

                    --make sure any added child panels get added back in.
                    if #children ~= #currentChildren then
                        element.children = children
                    end
                end,
            },
        },
        gui.Label {
            classes = { "panel_hero_label" },
            text = "Subclass",
        },

        gui.Label {
            classes = { "link", "statsLabel" },
            fontSize = 11,
            halign = "center",
            valign = "top",
            text = "Source",
            refreshAppearance = function(element, info)
                element:SetClass("collapsed",
                    info.token.properties == nil or info.token.properties:try_get("source") == nil)
                if element:HasClass("collapsed") == false then
                    element.text = dmhub.DescribeDocument(info.token.properties.source)
                end
            end,
            click = function(element)
                local info = CharacterSheet.instance.data.info
                dmhub.OpenDocument(info.token.properties.source)
            end,
        },]]



    }
    return resultPanel
end

local EditResistanceEntry = function(creature, resistanceEntry, params)
    if resistanceEntry:try_get("dr") == nil or resistanceEntry:try_get("apply") ~= "Damage Reduction" then
        return nil
    end

    local damageTypeOptions = {}

    damageTypeOptions[#damageTypeOptions + 1] = {
        id = "all",
        text = "all",
    }

    local damageTable = dmhub.GetTable(DamageType.tableName) or {}
    for k, v in unhidden_pairs(damageTable) do
        local name = string.lower(v.name)
        damageTypeOptions[#damageTypeOptions + 1] = {
            id = name,
            text = name,
        }
    end

    local resultPanel
    local args = {
        style = {
            flow = 'horizontal',
            width = "auto",
            height = "auto",
            hmargin = 0,
            vmargin = 2,
            valign = 'top',
        },

        data = {
            entry = resistanceEntry,
        },

        children = {
            gui.Dropdown({
                options = {
                    {
                        id = "immunity",
                        text = "Immunity",
                    },
                    {
                        id = "vulnerability",
                        text = "Weakness",
                    },
                },
                idChosen = cond(resistanceEntry.dr >= 0, "immunity", "vulnerability"),
                events = {
                    change = function(element)
                        resistanceEntry.dr = math.abs(resistanceEntry.dr) *
                        cond(element.optionChosen == "immunity", 1, -1)
                        resultPanel:FireEvent("change")
                        element.parent:FireEventTree("refresh")
                    end,

                    refresh = function(element)
                        element.idChosen = cond(resistanceEntry.dr >= 0, "immunity", "vulnerability")
                    end,
                },
                style = {
                    halign = 'left',
                    valign = 'center',
                    height = 24,
                    width = 100,
                },
            }),

            gui.Input {
                editable = true,
                characterLimit = 3,
                change = function(element)
                    local isvulnerability = resistanceEntry.dr < 0
                    local n = tonumber(element.text)
                    if n == nil then
                        element.text = string.format("%d", math.abs(resistanceEntry.dr))
                        return
                    end
                    if n ~= nil and n < 0 then
                        isvulnerability = not isvulnerability
                    end

                    resistanceEntry.dr = math.abs(round(n)) * cond(isvulnerability, -1, 1)
                    resultPanel:FireEventTree("refresh")

                    CharacterSheet.instance:FireEvent('refreshAll')
                end,
                create = function(element)
                    element:FireEvent("refresh")
                end,
                refresh = function(element)
                    local dr = math.abs(resistanceEntry:try_get("dr", 0))
                    element.text = tostring(dr)
                end,
                halign = 'left',
                valign = 'center',
                fontSize = 14,
                height = 24,
                width = 20,
            },

            gui.Label({
                text = "to",
                style = {
                    halign = 'left',
                    valign = 'center',
                    width = 'auto',
                    height = 'auto',
                    hmargin = 6,
                },
            }),

            gui.Dropdown({
                options = damageTypeOptions,
                optionChosen = resistanceEntry.damageType,
                halign = 'left',
                valign = 'center',
                height = 24,
                width = 120,

                events = {
                    change = function(element)
                        resistanceEntry.damageType = element.optionChosen
                        resultPanel:FireEvent("change")
                    end,
                },
            }),

            gui.Label({
                text = " damage",
                style = {
                    halign = 'left',
                    valign = 'center',
                    width = 'auto',
                    height = 'auto',
                },
            }),

            gui.DeleteItemButton {
                width = 16,
                height = 16,

                click = function(element)
                    creature:DeleteResistance(resistanceEntry)
                    resultPanel:FireEvent("change")
                end,
            },
        },
    }

    for k, p in pairs(params) do
        args[k] = p
    end

    resultPanel = gui.Panel(args)
    return resultPanel
end

function CharSheet.DSEditImmunitiesPopup(element, info)
    local creature = info.token.properties
    local parentElement = element

    local children = {}

    children[#children + 1] = gui.Label {
        halign = "center",
        fontSize = 24,
        text = "Immunities & Weaknesses",
        width = "auto",
        height = "auto",
    }

    for i, resistance in ipairs(creature:GetResistances()) do
        children[#children + 1] = EditResistanceEntry(creature, resistance, {
            change = function(element)
                CharacterSheet.instance:FireEvent('refreshAll')
                CharSheet.DSEditImmunitiesPopup(parentElement, info)
            end,
        })
    end

    children[#children + 1] =
        gui.PrettyButton {
            text = 'Add Entry',
            width = 200,
            halign = 'center',
            valign = 'bottom',
            fontSize = 20,
            margin = 2,
            height = 50,
            pad = 4,
            hpad = 4,
            events = {
                click = function(element)
                    local resistances = creature:GetResistances()

                    resistances[#resistances + 1] = ResistanceEntry.new {
                        apply = 'Damage Reduction',
                        damageType = 'untyped',
                        dr = 1,
                    }

                    creature:SetResistances(resistances)

                    CharacterSheet.instance:FireEvent('refreshAll')
                    CharSheet.DSEditImmunitiesPopup(parentElement, info)
                end,
            },
        }

    --[[
	children[#children+1] = gui.Panel{
		bgimage = "panels/square.png",
		bgcolor = "white",
		height = 1,
		width = 100,
		vmargin = 20,
		halign = "center",
	}

	children[#children+1] = gui.Label{
		halign = "center",
		fontSize = 24,
		text = "Innate Condition Immunities",
		width = "auto",
		height = "auto",
	}


	local immunityPanels = {}
	local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)

	for k,v in pairs(creature:try_get("innateConditionImmunities", {})) do
		local condid = k
		local cond = conditionsTable[k]
		if cond ~= nil then
			immunityPanels[#immunityPanels+1] = gui.Label{
				text = cond.name,
				fontSize = 20,
				width = 240,

				gui.DeleteItemButton{
					width = 16,
					height = 16,
					halign = "right",
					valign = "center",
					click = function(element)
						creature:try_get("innateConditionImmunities", {})[k] = nil
						CharacterSheet.instance:FireEvent('refreshAll')
						CharSheet.DSEditImmunitiesPopup(parentElement, info)
					end,
				}
			}

		end
	end

	table.sort(immunityPanels, function(a,b) return a.text < b.text end)
	for _,p in ipairs(immunityPanels) do
		children[#children+1] = p
	end

	children[#children+1] = gui.Dropdown{
		create = function(element)
			local options = {}

			local immunities = creature:try_get("innateConditionImmunities", {})

			for j,cond in pairs(conditionsTable) do
				if cond:try_get("hidden", false) == false and cond.immunityPossible and (not immunities[j]) then
					options[#options+1] = {
						id = j,
						text = cond.name,
					}
				end
			end

			table.sort(options, function(a,b) return a.text < b.text end)
			table.insert(options, 1, {
				id = "none",
				text = "Add Immunity...",
			})

			element.options = options
			element.idChosen = "none"
		end,

		change = function(element)
			if element.idChosen == "none" then
				return
			end

			local immunities = creature:get_or_add("innateConditionImmunities", {})
			immunities[element.idChosen] = true
			CharacterSheet.instance:FireEvent('refreshAll')
			CharSheet.DSEditImmunitiesPopup(parentElement, info)
		end,
	}
]]

    element.popupPositioning = "panel"

    element.popup = gui.TooltipFrame(
        gui.Panel {
            width = "auto",
            height = "auto",
            styles = {
                Styles.Default,
                PopupStyles,
            },

            children = children,
        },

        {
            halign = "right",
            interactable = true,
        }
    )
end

local function DSCharSheet()
    --find id for recovery from resourcestable
    local recoveryid = "5bd90f9b-46be-4cf2-8ca6-a96430d62949"

    local DSCharSheetPanel = gui.Panel {

        styles = {
            g_styles,
            {
                selectors = {"~monster", "~follower", "monsterorfolloweronly" },
                collapsed = 1,
            },
            {
                selectors = { "~monster", "monsteronly" },
                collapsed = 1,
            },
            {
                selectors = { "monster", "monstercollapse" },
                collapsed = 1,
            },
            {
                selectors = { "~follower", "followeronly" },
                collapsed = 1,
            },
            {
                selectors = { "follower", "followercollapse" },
                collapsed = 1,
            },
        },

        bgimage = true,
        bgcolor = "clear",
        width = "100%",
        height = "100%",

        flow = "horizontal",

        refreshToken = function(element, info)
            if info.token.properties:IsFollower() then
                element:SetClassTree("follower", true)
                element:SetClassTree("monster", false)
            elseif info.token.properties:IsMonster() then
                element:SetClassTree("monster", true)
                element:SetClassTree("follower", false)
            else
                element:SetClassTree("follower", false)
                element:SetClassTree("monster", false)
            end
        end,


        --kingpanel 1
        gui.Panel {

            width = "20%",
            height = "100%",

            CharSheet.CharacterSheetAndAvatarPanel(),
        },

        --kingpanel 2
        gui.Panel {

            bgimage = true,
            bgcolor = "clear",
            width = "40%",
            height = "100%",

            flow = "vertical",

            --skillpoints
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = "24%",

                --frame
                gui.Panel {

                    bgimage = true,
                    bgcolor = bg_color,
                    width = "100%",
                    height = "80%",

                    border = 2,
                    borderColor = border_color,
                    beveledcorners = true,
                    cornerRadius = 15,

                    halign = "center",
                    valign = "center",

                    flow = "vertical",

                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "100%",
                        height = "52%",

                        flow = "horizontal",
                        tmargin = 7,
                        bmargin = 7,

                        create = function(element)
                            local children = {}

                            for _, attrid in ipairs(creature.attributeIds) do
                                local info = creature.attributesInfo[attrid]
                                local panel = gui.Panel {

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "15%",
                                    height = "100%",
                                    halign = "center",

                                    press = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        if token.properties:IsMonster() then
                                            --monsters just directly edit the label.
                                            return
                                        end
                                        local baseValue = token.properties:GetBaseAttribute(attrid).baseValue
                                        local modifiers = token.properties:DescribeModifications(attrid, baseValue)

                                        print("POPUP::", attrid, info.description)

                                        gui.PopupOverrideAttribute {
                                            parentElement = element,
                                            token = token,
                                            attributeName = info.description,
                                            baseValue = baseValue,
                                            modifications = modifiers,
                                            characterSheet = true,
                                        }
                                    end,

                                    gui.Label {

                                        text = info.description,
                                        uppercase = true,
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Panel {

                                        width = 70,
                                        height = 70,
                                        bgimage = true,
                                        color = "clear",
                                        border = 3,
                                        borderColor = border_color,
                                        halign = "center",
                                        valign = "bottom",

                                        gui.Label {

                                            characterLimit = 2,
                                            text = "+0",
                                            textAlignment = "center",
                                            color = border_color,
                                            fontSize = 30,
                                            width = "100%",
                                            height = "auto",
                                            halign = "center",
                                            valign = "center",
                                            change = function(element)
                                                local token = CharacterSheet.instance.data.info.token
                                                local t = element.text
                                                if t:sub(1, 1) == "+" then
                                                    t = t:sub(2)
                                                end

                                                local v = tonumber(t)
                                                if v ~= nil then
                                                    token.properties.attributes[attrid] = CharacterAttribute.new {
                                                        id = attrid,
                                                        baseValue = round(v),
                                                    }
                                                end

                                                CharacterSheet.instance:FireEvent('refreshAll')
                                            end,

                                            refreshToken = function(element, info)
                                                element.editable = info.token.properties:IsMonster()

                                                if info.token.properties:GetAttribute(attrid):Modifier() > -1 then
                                                    element.text = "+" ..
                                                        tostring(info.token.properties:GetAttribute(attrid):Modifier())
                                                else
                                                    element.text = tostring(info.token.properties:GetAttribute(attrid)
                                                    :Modifier())
                                                end
                                            end,
                                        },
                                    },
                                }

                                children[#children + 1] = panel
                            end

                            element.children = children
                        end,
                    },

                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "100%",
                        height = "40%",

                        flow = "horizontal",
                        tmargin = 7,

                        gui.Panel {

                            width = "15%",
                            height = 70,
                            bgimage = true,
                            bgcolor = "clear",
                            halign = "center",

                            gui.Panel {

                                width = "100%",
                                height = 40,

                                bgimage = true,
                                bgcolor = "clear",
                                border = 2,
                                borderColor = border_color,
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    local size = token.properties:GetBaseCreatureSizeNumber()
                                    local modifications = token.properties:DescribeModifications("creatureSize", size)
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Size",
                                        baseValue = size,
                                        modifications = modifications,
                                        characterSheet = true,
                                        namingTable = creature.sizes,
                                    }
                                    CharacterSheet.instance:FireEvent('refreshAll')
                                end,

                                gui.Label {

                                    text = "4",
                                    fontSize = 20,
                                    color = border_color,
                                    height = "auto",
                                    width = "auto",

                                    halign = "center",
                                    valign = "center",

                                    refreshToken = function(element, info)
                                        element.text = info.token.properties:try_get("_tmp_creaturesize") or info.token.creatureSize
                                    end,
                                },

                            },

                            gui.Label {

                                text = "Size",
                                fontSize = 20,
                                color = border_color,
                                height = "auto",
                                width = "auto",

                                halign = "center",
                                valign = "bottom",

                            },


                        },



                        gui.Panel {

                            width = "15%",
                            height = 70,
                            bgimage = true,
                            bgcolor = "clear",
                            halign = "center",

                            gui.Panel {

                                width = "100%",
                                height = 40,

                                bgimage = true,
                                bgcolor = "clear",
                                border = 2,
                                borderColor = border_color,
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    if token.properties:IsMonster() then
                                        return
                                    end
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Speed",
                                        baseValue = token.properties:GetBaseSpeed(),
                                        modifications = token.properties:DescribeSpeedModifications(),
                                        characterSheet = true,
                                    }
                                end,

                                gui.Label {
                                    text = "4",
                                    fontSize = 20,
                                    color = border_color,
                                    height = "auto",
                                    width = "auto",

                                    halign = "center",
                                    valign = "center",
                                    characterLimit = 2,

                                    change = function(element)
                                        local n = tonumber(element.text)
                                        if n ~= nil then
                                            n = math.max(0, round(n))
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            creature.walkingSpeed = n
                                        end

                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,

                                    refreshToken = function(element, info)
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        element.editable = creature:IsMonster()
                                        element.text = creature:CurrentMovementSpeed()
                                    end,
                                },

                                gui.Label {
                                    halign = "right",
                                    valign = "center",
                                    width = 44,
                                    height = "auto",
                                    rmargin = 2,
                                    fontSize = 11,
                                    textAlignment = "left",
                                    refreshToken = function(element, info)
                                        local text = ""
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        for _, info in ipairs(creature.movementTypeInfo) do
                                            if info.id ~= "walk" then
                                                local canuse = creature:GetSpeed(info.id) >= creature:WalkingSpeed()
                                                if canuse then
                                                    if text ~= "" then
                                                        text = text .. "\n"
                                                    end
                                                    text = text .. info.name
                                                end
                                            end
                                        end
                                        element.text = text
                                    end,
                                },
                            },

                            gui.Label {

                                text = "Speed",
                                fontSize = 20,
                                color = border_color,
                                height = "auto",
                                width = "auto",

                                halign = "center",
                                valign = "bottom",





                            },


                        },

                        gui.Panel {

                            width = "15%",
                            height = 70,
                            bgimage = true,
                            bgcolor = "clear",
                            halign = "center",

                            gui.Panel {

                                width = "100%",
                                height = 40,

                                bgimage = true,
                                bgcolor = "clear",
                                border = 2,
                                borderColor = border_color,
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Disengage Speed",
                                        characterSheet = true,
                                    }
                                end,

                                gui.Label {

                                    text = "4",
                                    fontSize = 20,
                                    color = border_color,
                                    height = "auto",
                                    width = "auto",

                                    halign = "center",
                                    valign = "center",

                                    refreshToken = function(element, info)
                                        local customAttr = CustomAttribute.attributeInfoByLookupSymbol["disengagespeed"]
                                        if customAttr ~= nil then
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local result = creature:GetCustomAttribute(customAttr)
                                            element.text = tostring(result)
                                        else
                                            element.text = ""
                                        end
                                    end,


                                },



                            },

                            gui.Label {

                                text = "Disengage",
                                fontSize = 20,
                                color = border_color,
                                height = "auto",
                                width = "auto",

                                halign = "center",
                                valign = "bottom",

                            },


                        },

                        gui.Panel {

                            width = "15%",
                            height = 70,
                            bgimage = true,
                            bgcolor = "clear",
                            halign = "center",

                            gui.Panel {

                                width = "100%",
                                height = 40,

                                bgimage = true,
                                bgcolor = "clear",
                                border = 2,
                                borderColor = border_color,
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    if token.properties:IsMonster() then
                                        return
                                    end
                                    local baseStability = token.properties:BaseForcedMoveResistance()
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Stability",
                                        baseValue = baseStability,
                                        modifications = token.properties:DescribeModifications("forcedmoveresistance", baseStability),
                                        characterSheet = true,
                                    }
                                end,

                                gui.Label {

                                    text = "4",
                                    fontSize = 20,
                                    color = border_color,
                                    height = "auto",
                                    width = "auto",
                                    minWidth = 80,
                                    textAlignment = "center",

                                    halign = "center",
                                    valign = "center",
                                    characterLimit = 2,

                                    change = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        local n = tonumber(element.text)
                                        if n ~= nil then
                                            n = math.max(0, round(n))

                                            token.properties.stability = n
                                        end
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,

                                    refreshToken = function(element, info)
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        element.editable = creature:IsMonster()
                                        element.text = creature:Stability()
                                    end,


                                },
                            },

                            gui.Label {

                                text = "Stability",
                                fontSize = 20,
                                color = border_color,
                                height = "auto",
                                width = "auto",

                                halign = "center",
                                valign = "bottom",


                            },


                        },

                    },

                },
            },

            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = "80%",

                flow = "horizontal",

                gui.Panel {

                    bgimage = true,
                    bgcolor = "clear",
                    width = "50%",
                    height = "100%",

                    flow = "vertical",

                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "100%",
                        height = "12%",

                        gui.Panel {

                            bgimage = true,
                            bgcolor = bg_color,
                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 15,
                            width = "100%",
                            height = "100%",

                            flow = "vertical",

                            gui.Label {

                                text = "Potencies",
                                color = border_color,
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",

                            },

                            gui.Divider {

                                width = "80%",
                            },

                            gui.Label {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "auto",
                                height = "auto",
                                flow = "horizontal",
                                halign = "center",

                                bmargin = 15,


                                gui.Panel {

                                    bgimage = true,
                                    bgcolor = "clear",
                                    border = 2,
                                    borderColor = border_color,
                                    beveledcorners = true,
                                    cornerRadius = 15,
                                    width = "25%",
                                    height = "50%",
                                    halign = "center",
                                    valign = "center",
                                    rmargin = 10,

                                    gui.Label {

                                        text = "Strong",
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Label {

                                        text = "1",
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "bottom",

                                        refreshToken = function(element, info)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local strong = creature:CalcuatePotencyValue("Strong")
                                            element.text = strong
                                        end

                                    },



                                },

                                gui.Panel {

                                    bgimage = true,
                                    bgcolor = "clear",
                                    border = 2,
                                    borderColor = border_color,
                                    beveledcorners = true,
                                    cornerRadius = 15,
                                    width = "25%",
                                    height = "50%",
                                    halign = "center",
                                    valign = "center",

                                    gui.Label {

                                        text = "Average",
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Label {

                                        text = "2",
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "bottom",

                                        refreshToken = function(element, info)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local average = creature:CalcuatePotencyValue("Average")
                                            element.text = average
                                        end

                                    },



                                },

                                gui.Panel {

                                    bgimage = true,
                                    bgcolor = "clear",
                                    border = 2,
                                    borderColor = border_color,
                                    beveledcorners = true,
                                    cornerRadius = 15,
                                    width = "25%",
                                    height = "50%",
                                    halign = "center",
                                    valign = "center",
                                    lmargin = 10,

                                    gui.Label {

                                        text = "Weak",
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Label {

                                        text = "2",
                                        color = border_color,
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "bottom",

                                        refreshToken = function(element, info)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local weak = creature:CalcuatePotencyValue("Weak")
                                            element.text = weak
                                        end

                                    },



                                },

                            },

                        },

                    },

                    --immunities king panel
                    gui.Panel {

                        width = "100%",
                        height = "11%",
                        bgimage = true,
                        bgcolor = "clear",
                        vmargin = 18,


                        gui.Panel {

                            width = "100%",
                            height = "100%",
                            bgimage = true,
                            bgcolor = bg_color,
                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 15,

                            valign = "center",
                            flow = "vertical",

                            gui.Label {

                                text = "Immunities & Weaknesses",
                                color = border_color,
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                tmargin = 5,
                            },

                            gui.SettingsButton {
                                floating = true,
                                halign = "right",
                                valign = "top",
                                hmargin = 18,
                                vmargin = 8,
                                width = 16,
                                height = 16,
                                press = function(element)
                                    if element.popup ~= nil then
                                        element.popup = nil
                                    else
                                        CharSheet.DSEditImmunitiesPopup(element, CharacterSheet.instance.data.info)
                                    end
                                end,
                            },


                            gui.Divider {

                                width = "80%",
                            },


                            --immunities list.
                            gui.Label {
                                bgimage = true,
                                bgcolor = "clear",
                                width = "95%",
                                height = "100%-54",
                                halign = "center",
                                valign = "top",
                                tmargin = 5,
                                fontSize = 16,
                                bold = false,

                                flow = "vertical",

                                refreshToken = function(element, info)
                                    local resistances = info.token.properties:ResistanceEntries()
                                    print("RESISTANCES::", json(resistances))
                                    local immunities = {}
                                    local weaknesses = {}
                                    for _, entry in ipairs(resistances) do
                                        local damageType = entry.entry.damageType
                                        local dr = entry.entry.dr or 0
                                        if dr > 0 then
                                            immunities[damageType] = math.max(immunities[damageType] or 0, dr)
                                        elseif dr < 0 then
                                            weaknesses[damageType] = math.max(weaknesses[damageType] or 0, -dr)
                                        end
                                    end

                                    local immunitiesList = {}
                                    local weaknessesList = {}

                                    for key, value in pairs(immunities) do
                                        immunitiesList[#immunitiesList + 1] = string.format("%s %d", key, value)
                                    end

                                    for key, value in pairs(weaknesses) do
                                        weaknessesList[#weaknessesList + 1] = string.format("%s %d", key, value)
                                    end

                                    table.sort(immunitiesList)
                                    table.sort(weaknessesList)

                                    local immunitiesText = "-"
                                    if #immunitiesList > 0 then
                                        immunitiesText = table.concat(immunitiesList, ", ")
                                    end

                                    local weaknessesText = "-"
                                    if #weaknessesList > 0 then
                                        weaknessesText = table.concat(weaknessesList, ", ")
                                    end

                                    element.text = string.format("<b>Immunities:</b> %s\n<b>Weaknesses:</b> %s",
                                        immunitiesText, weaknessesText)
                                    print("RESISTANCES:: TEXt =", element.text)
                                end,
                            },
                        },
                    },

                    --skills king panel
                    gui.Panel {

                        width = "100%",
                        height = "23%",
                        bgimage = true,
                        bgcolor = "clear",
                        bmargin = 18,
                        valign = "top",

                        gui.Panel {

                            width = "100%",
                            height = "100%",
                            bgimage = true,
                            bgcolor = bg_color,
                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 15,

                            valign = "center",
                            flow = "vertical",

                            gui.Label {

                                text = "Skills",
                                color = border_color,
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                tmargin = 5,
                            },

                            gui.SettingsButton {
                                floating = true,
                                halign = "right",
                                valign = "top",
                                hmargin = 18,
                                vmargin = 8,
                                width = 16,
                                height = 16,
                                press = function(element)
                                    local options = {
                                        callbacks = {
                                            confirm = function(newSkills)
                                                local token = CharacterSheet.instance.data.info.token
                                                CharacterSkillDialog.saveFeatures(token, newSkills.features)
                                                CharacterSkillDialog.saveLevelChoices(token, newSkills.levelChoices)
                                                CharacterSheet.instance:FireEventTree("refresh")
                                                CharacterSheet.instance:FireEvent("refreshAll")
                                            end,
                                        }
                                    }
                                    CharacterSheet.instance:AddChild(CharacterSkillDialog.CreateAsChild(options))
                                end,
                            },

                            gui.Divider {

                                width = "80%",
                            },


                            --skills list
                            gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "95%",
                                height = "100%-54",
                                halign = "center",
                                valign = "top",
                                tmargin = 5,

                                flow = "vertical",

                                vscroll = true,


                                refreshToken = function(element, info)
                                    if element.data.init == true then
                                        return
                                    end
                                    element.data.init = true

                                    local token = info.token

                                    local children = {}

                                    for _, cat in ipairs(Skill.categories) do
                                        local panel = gui.Label {
                                            width = "100%",
                                            height = "auto",
                                            textAlignment = "left",
                                            fontSize = 16,
                                            valign = "top",
                                            bold = false,

                                            refreshToken = function(element, info)
                                                local creature = info.token.properties
                                                local proficiencyList = nil
                                                for i, skill in ipairs(Skill.SkillsInfo) do
                                                    if skill.category == cat.id and creature:ProficientInSkill(skill) then
                                                        if proficiencyList == nil then
                                                            proficiencyList = skill.name
                                                        else
                                                            proficiencyList = proficiencyList .. ", " .. skill.name
                                                        end
                                                    end
                                                end

                                                if proficiencyList == nil then
                                                    element:SetClass("collapsed", true)
                                                else
                                                    element:SetClass("collapsed", false)
                                                    element.text = string.format("<b>%s:</b> %s", cat.text,
                                                        proficiencyList)
                                                end
                                            end
                                        }

                                        children[#children + 1] = panel
                                    end

                                    element.children = children
                                end,
                            },
                        },
                    },

                    CharSheet.LanguagesPanel(),
                    CharSheet.KitPanel(),




                },

                gui.Panel {
                    width = "50%-18",
                    height = "100%-50",
                    halign = "right",
                    bgimage = true,
                    bgcolor = "clear",
                    borderWidth = 2,
                    borderColor = "white",
                    valign = "top",
                    flow = "vertical",

                    gui.Panel {
                        vscroll = true,
                        width = "100%-5",
                        height = "100%-95",
                        halign = "left",
                        valign = "top",
                        CreateAbilityListPanel(),
                    },

                    gui.Button {
                        width = "100%-27",
                        height = 35,
                        halign = "center",
                        valign = "bottom",
                        bmargin = 7,
                        text = "Create Ability",
                        press = function(element)
                            local newAbility = ActivatedAbility.Create {
                                name = "New Ability",
                            }

                            CharacterSheet.instance:AddChild(newAbility:ShowEditActivatedAbilityDialog {
                                add = function(element)
                                    CharacterSheet.instance.data.info.token.properties:AddInnateActivatedAbility(
                                        newAbility)
                                    CharacterSheet.instance:FireEvent("refreshAll")
                                end,
                                cancel = function(element)
                                end,
                            })
                        end,
                    },

                    gui.Button {
                        width = "100%-27",
                        height = 35,
                        halign = "center",
                        valign = "bottom",
                        tmargin = 0,
                        bmargin = 10,
                        text = "Paste Ability",
                        press = function(element)
                            local clipboardItem = DeepCopy(dmhub.GetInternalClipboard())

                            CharacterSheet.instance.data.info.token.properties:AddInnateActivatedAbility(
                                clipboardItem)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,

                        refreshToken = function(element, info)
                            local clipboardItem = dmhub.GetInternalClipboard()

                            if clipboardItem == nil or clipboardItem.typeName ~= "ActivatedAbility" then
                                element:SetClass("hidden", true)
                            else
                                element:SetClass("hidden", false)
                                element.text = "Paste " .. "<b>" .. clipboardItem.name .. "</b>"
                            end
                        end
                    }
                },

            },



        },

        --kingpanel 3
        gui.Panel {

            bgimage = true,
            bgcolor = "clear",
            width = "40%",
            height = "100%",

            flow = "vertical",


            --victory+ kingpanel
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = "24%",


                --frame
                gui.Panel {

                    bgimage = true,
                    bgcolor = bg_color,
                    width = "95%",
                    height = "80%",

                    border = 2,
                    borderColor = border_color,
                    beveledcorners = true,
                    cornerRadius = 15,

                    halign = "center",
                    valign = "center",

                    flow = "vertical",

                    --Queen panel for Victories and lvl
                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "100%",
                        height = "50%",

                        flow = "horizontal",

                        --monster stats such as EV showing in place of Victories.
                        gui.Panel {
                            bgimage = true,
                            bgcolor = "clear",
                            width = "80%",
                            height = "100%",
                            flow = "horizontal",
                            refreshToken = function(element, info)
                                element:SetClass("collapsed", not info.token.properties:IsMonster())
                            end,

                            --minion-only "with captain" panel
                            gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "30%",
                                height = "100%",
                                halign = "right",

                                flow = "vertical",

                                refreshToken = function(element, info)
                                    element:SetClass("collapsed", not info.token.properties.minion)
                                end,

                                gui.Label {

                                    text = "WITH CAPTAIN",
                                    color = "white",
                                    fontSize = 16,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "35%",

                                    valign = "top",
                                    halign = "center",
                                    textAlignment = "center",

                                    tmargin = 8,
                                    lmargin = 10,


                                },

                                gui.Label {

                                    text = "4",
                                    color = "white",
                                    fontSize = 18,
                                    characterLimit = 32,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "35%",

                                    valign = "top",
                                    halign = "center",
                                    textAlignment = "center",

                                    tmargin = 4,
                                    lmargin = 10,

                                    editable = true,

                                    refreshToken = function(element, info)
                                        if (not info.token.properties:IsMonster()) or (not info.token.properties.minion) then
                                            return
                                        end

                                        local text = trim(info.token.properties.withCaptain or "")
                                        if text == "" then
                                            text = "-"
                                        end
                                        element.text = text
                                    end,

                                    change = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        token.properties.withCaptain = element.text
                                        CharacterSheet.instance:FireEvent('refreshAll')
                                    end,
                                },
                            },


                            --monster-only free strike panel
                            gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "15%",
                                height = "100%",
                                halign = "right",

                                flow = "vertical",

                                gui.Label {

                                    text = "FREE STRIKE",
                                    color = "white",
                                    fontSize = 16,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "35%",

                                    valign = "top",
                                    halign = "center",
                                    textAlignment = "center",

                                    tmargin = 8,
                                    lmargin = 10,


                                },

                                gui.Label {

                                    text = "4",
                                    color = "white",
                                    fontSize = 26,
                                    characterLimit = 3,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "35%",

                                    valign = "top",
                                    halign = "center",
                                    textAlignment = "center",

                                    tmargin = 4,
                                    lmargin = 10,

                                    editable = true,

                                    refreshToken = function(element, info)
                                        if not info.token.properties:IsMonster() then
                                            return
                                        end

                                        local attack = info.token.properties:OpportunityAttack()
                                        element.text = string.format("%d", round(attack))
                                    end,

                                    change = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        local newValue = round(tonumber(element.text) or
                                        token.properties:OpportunityAttack())
                                        element.text = string.format("%d", newValue)
                                        token.properties.opportunityAttack = newValue
                                    end,
                                },
                            },

                            --monster-only ev panel
                            gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "15%",
                                height = "100%",
                                halign = "right",

                                flow = "vertical",

                                gui.Label {

                                    text = "EV",
                                    color = "white",
                                    fontSize = 20,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "35%",

                                    valign = "top",
                                    halign = "center",
                                    textAlignment = "center",

                                    tmargin = 8,
                                    lmargin = 10,


                                },

                                gui.Label {

                                    text = "4",
                                    color = "white",
                                    fontSize = 26,
                                    characterLimit = 3,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "35%",

                                    valign = "top",
                                    halign = "center",
                                    textAlignment = "center",

                                    tmargin = 4,
                                    lmargin = 10,

                                    editable = true,

                                    refreshToken = function(element, info)
                                        if not info.token.properties:IsMonster() then
                                            return
                                        end

                                        local ev = info.token.properties.ev
                                        element.text = string.format("%d", round(ev))
                                    end,

                                    change = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        local newValue = round(tonumber(element.text) or token.properties.ev)
                                        element.text = string.format("%d", newValue)
                                        token.properties.ev = newValue
                                    end,
                                },
                            },

                        },

                        --Victories
                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            width = "80%",
                            height = "100%",

                            flow = "vertical",

                            refreshToken = function(element, info)
                                element:SetClass("collapsed", info.token.properties:IsMonster())
                            end,

                            --Victories label
                            gui.Label {

                                text = "VICTORIES:",
                                color = "white",
                                fontSize = 20,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "100%",
                                height = "35%",

                                tmargin = 8,
                                lmargin = 20,
                            },

                            --Victories bar
                            gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "100%",
                                height = "65%",



                                gui.Panel {

                                    styles = {
                                        {
                                            selectors = { "notch", "left" },
                                            beveledcorners = true,
                                            cornerRadius = { x1 = 8, y1 = 0, x2 = 0, y2 = 8 },
                                        },
                                        {
                                            selectors = { "notch", "right" },
                                            beveledcorners = true,
                                            cornerRadius = { x1 = 0, y1 = 8, x2 = 8, y2 = 0 },
                                        },
                                        {
                                            selectors = { "notch" },
                                            width = string.format("%f%%", 100 / 15),
                                            height = "100%",
                                            borderColor = border_color,
                                            border = 2,
                                            bgcolor = "black",
                                        },
                                        {
                                            selectors = { "notch", "filled" },
                                            bgcolor = "#aaaaff",
                                        },
                                        {
                                            selectors = { "notch", "hover" },
                                            bgcolor = "#aaaaaa",
                                        },
                                        {
                                            selectors = { "notch", "hover", "filled" },
                                            bgcolor = "#ffaaff",
                                        },
                                    },

                                    refreshToken = function(element, info)
                                        if element.data.init == nil then
                                            element.data.init = true
                                            element:FireEvent("build")
                                        end
                                        local victories = info.token.properties:GetVictories()
                                        if victories ~= element.data.victories then
                                            local children = element.data.children
                                            element.data.victories = victories
                                            for i = 1, #children do
                                                children[i]:SetClass("filled", i <= victories)
                                            end
                                        end
                                    end,

                                    build = function(element)
                                        local children = {}
                                        for i = 1, 15 do
                                            local index = i
                                            children[#children + 1] = gui.Panel {
                                                classes = { "notch", cond(i == 1, "left"), cond(i == 15, "right") },
                                                bgimage = true,
                                                press = function()
                                                    local token = CharacterSheet.instance.data.info.token
                                                    local newValue = index
                                                    if token.properties:GetVictories() >= index then
                                                        newValue = index - 1
                                                    end
                                                    token:ModifyProperties {
                                                        description = "Set Victories",
                                                        execute = function()
                                                            token.properties:SetVictories(newValue)
                                                        end,
                                                    }
                                                    CharacterSheet.instance:FireEvent('refreshAll')
                                                end,
                                            }
                                        end
                                        element.children = children
                                        element.data.children = children
                                    end,

                                    flow = "horizontal",

                                    width = 530,
                                    height = "65%",

                                    halign = "left",

                                    lmargin = 20,

                                    beveledcorners = true,
                                    cornerRadius = 8,


                                },


                            },

                        },

                        --double divider
                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            width = "4%",
                            height = "100%",

                            flow = "horizontal",


                            gui.Panel {

                                bgimage = true,
                                bgcolor = border_color,
                                width = "6%",
                                height = "80%",
                                halign = "left",
                                valign = "center",
                                rmargin = 8,


                            },

                            gui.Panel {

                                bgimage = true,
                                bgcolor = border_color,
                                width = "6%",
                                height = "80%",
                                valign = "center",





                            },

                        },

                        --level panel
                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            width = "15%",
                            height = "100%",

                            flow = "vertical",

                            gui.Label {

                                text = "LEVEL",
                                color = "white",
                                fontSize = 20,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "100%",
                                height = "35%",

                                valign = "top",
                                halign = "center",
                                textAlignment = "center",

                                tmargin = 8,
                                lmargin = 10,


                            },

                            gui.Label {

                                text = "4",
                                color = "white",
                                fontSize = 26,
                                characterLimit = 2,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "100%",
                                height = "35%",

                                valign = "top",
                                halign = "center",
                                textAlignment = "center",


                                tmargin = 4,
                                lmargin = 10,

                                refreshToken = function(element, info)
                                    local level = info.token.properties:CharacterLevel()
                                    if level == 0 then
                                        element.text = "-"
                                    else
                                        element.text = string.format("%d", level)
                                    end

                                    element.editable = info.token.properties:IsMonster()
                                end,

                                change = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    local n = math.max(0,
                                        round(tonumber(element.text) or token.properties:CharacterLevel()))
                                    token.properties.cr = n
                                    CharacterSheet.instance:FireEvent("refreshAll")
                                end,
                            },
                        },
                    },

                    --big divider
                    gui.Panel {

                        bgimage = true,
                        bgcolor = border_color,
                        width = "95%",
                        height = 2,
                        halign = "center",
                        valign = "center",
                        bmargin = 10,


                    },

                    --Queen panel for weatlh, renown and XP
                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "100%",
                        height = "50%",

                        flow = "horizontal",

                        gui.Panel {

                            bgimage = true,
                            bgcolor = bg_color,
                            width = "30%",
                            height = "80%",

                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 12,

                            halign = "center",

                            flow = "vertical",

                            gui.Label {

                                text = "WEALTH",

                                fontSize = 18,
                                color = "white",

                                tmargin = 6,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                textAlignment = "center",

                            },

                            gui.Label {

                                text = "4",

                                fontSize = 22,
                                color = "white",

                                tmargin = 8,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "90%",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                textAlignment = "center",
                                characterLimit = 4,

                                refreshToken = function(element, info)
                                    local wealth = info.token.properties:CalculateNamedCustomAttribute("Wealth")

                                    element.text = wealth
                                end,

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Wealth",
                                        characterSheet = true,
                                    }
                                end,

                            },



                        },

                        gui.Panel {

                            bgimage = true,
                            bgcolor = bg_color,
                            width = "30%",
                            height = "80%",

                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 12,

                            halign = "center",

                            flow = "vertical",

                            gui.Label {

                                text = "RENOWN",

                                fontSize = 18,
                                color = "white",

                                tmargin = 6,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                textAlignment = "center",

                            },

                            gui.Label {

                                text = "4",

                                fontSize = 22,
                                color = "white",

                                tmargin = 8,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "90%",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                textAlignment = "center",
                                characterLimit = 4,

                                refreshToken = function(element, info)
                                    local renown = info.token.properties:CalculateNamedCustomAttribute("Renown")

                                    element.text = renown
                                end,

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Renown",
                                        characterSheet = true,
                                    }
                                end,
                            },



                        },

                        gui.Panel {

                            bgimage = true,
                            bgcolor = bg_color,
                            width = "30%",
                            height = "80%",

                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 12,

                            halign = "center",

                            flow = "vertical",

                            gui.Label {

                                text = "XP",

                                fontSize = 18,
                                color = "white",

                                tmargin = 6,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                textAlignment = "center",

                                --epic if level 10 or more otherwise xp
                                refreshToken = function(element, info)
                                    local level = info.token.properties:CharacterLevel()
                                    if level >= 10 then
                                        element.text = "EPIC"
                                    else
                                        element.text = "XP"
                                    end
                                end,

                            },

                            gui.Label {

                                text = "4",

                                fontSize = 22,
                                color = "white",

                                tmargin = 8,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "90%",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                textAlignment = "center",
                                characterLimit = 4,

                                editable = true,

                                change = function(element)
                                    local info = CharacterSheet.instance.data.info
                                    local newXP = tonumber(element.text)

                                    if newXP == nil then
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    else
                                        info.token.properties.xp = math.max(0, round(newXP))
                                    end
                                end,

                                refreshToken = function(element, info)
                                    local xp = info.token.properties:try_get("xp", 0)

                                    element.text = xp
                                end,



                            },



                        },


                    },



                },




            },

            --stamine + resources
            gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                width = "100%",
                height = "20%",

                --frame
                gui.Panel {

                    bgimage = true,
                    bgcolor = bg_color,
                    width = "95%",
                    height = "80%",

                    border = 2,
                    borderColor = border_color,
                    beveledcorners = true,
                    cornerRadius = 15,

                    halign = "center",
                    valign = "top",

                    flow = "horizontal",

                    --stamina queenpanel
                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "35%",
                        height = "100%",

                        gui.Label {

                            text = "STAMINA",
                            color = "white",
                            fontSize = 20,

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",

                            halign = "center",
                            valign = "top",

                            tmargin = 10,


                        },

                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            border = 2,
                            borderColor = border_color,
                            beveledcorners = true,
                            cornerRadius = 10,

                            width = 220,
                            height = 70,
                            halign = "horizontal",
                            valign = "top",

                            lmargin = 20,
                            tmargin = 50,

                            flow = "horizontal",

                            gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "60%",
                                height = "100%",
                                lmargin = 15,

                                gui.Label {

                                    text = "TEMP:",
                                    fontSize = 15,
                                    color = border_color,
                                    halign = "right",
                                    valign = "top",
                                    textAlignment = "top",
                                    lmargin = 40,
                                    tmargin = 4,


                                },

                                --temp stamina
                                gui.Panel {

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "50%",
                                    height = "70%",
                                    halign = "right",
                                    valign = "bottom",

                                    flow = "horizontal",


                                    gui.Label {

                                        text = "+",
                                        fontSize = 30,
                                        color = "blue",
                                        halign = "left",
                                        width = "auto",
                                        height = "auto",
                                        lmargin = 10,

                                        refreshToken = function(element, info)
                                            local creature = info.token.properties

                                            if creature:TemporaryHitpointsStr() == "--" then
                                                element:SetClass("hidden", true)
                                            else
                                                element:SetClass("hidden", false)
                                            end
                                        end



                                    },

                                    gui.Label {

                                        text = "30",
                                        fontSize = 30,
                                        color = "blue",
                                        halign = "left",
                                        width = 37,
                                        characterLimit = 3,
                                        minFontSize = 8,
                                        height = "auto",
                                        editable = true,

                                        refreshToken = function(element, info)
                                            local creature = info.token.properties
                                            element.text = creature:TemporaryHitpointsStr()
                                        end,

                                        change = function(element)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            creature:SetTemporaryHitpoints(element.text)
                                            element.data.previous_value = nil
                                            CharacterSheet.instance:FireEvent('refreshAll')
                                        end,



                                    },


                                },


                            },

                            gui.Panel {

                                bgimage = true,
                                bgcolor = border_color,
                                width = 2,
                                height = "80%",
                                valign = "center",
                            },

                            gui.Label {

                                text = "Healthy",
                                fontSize = 13,
                                color = border_color,
                                halign = "center",
                                valign = "center",
                                lmargin = 6,
                                width = "auto",
                                height = "auto",


                                refreshToken = function(element, info)
                                    local creature = info.token.properties

                                    if creature:IsDead() then
                                        element.text = "DEAD"
                                    elseif creature:CurrentHitpoints() <= 0 then
                                        element.text = "DYING"
                                    elseif creature:IsWinded() then
                                        element.text = "WINDED"
                                    else
                                        element.text = "HEALTHY"
                                    end
                                end


                            },

                        },


                        gui.Panel {

                            bgimage = mod.images.shield2,
                            bgcolor = border_color,


                            width = 120,
                            height = 120,
                            halign = "horizontal",
                            valign = "center",

                            lmargin = 0,

                            gui.Panel {
                                id = "staminaContainer",
                                flow = "vertical",
                                halign = "center",
                                valign = "center",
                                width = "100%",
                                height = "auto",
                                gui.Label {

                                    text = "",
                                    color = "white",
                                    fontSize = 28,


                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "auto",

                                    valign = "center",
                                    halign = "center",

                                    textAlignment = "center",

                                    editable = true,
                                    characterLimit = 4,

                                    refreshToken = function(element, info)
                                        local hp = info.token.properties:CurrentHitpoints()
                                        element.text = string.format("%d", hp)
                                    end,

                                    change = function(element)
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        creature:SetCurrentHitpoints(element.text)
                                        element.data.previous_value = nil --don't flash green/red on an edit.
                                        CharacterSheet.instance:FireEvent('refreshAll')
                                    end,

                                },

                                gui.Label {

                                    text = "/4",
                                    color = "white",
                                    fontSize = 19,
                                    tmargin = -8,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "auto",
                                    height = "auto",
                                    minWidth = 70,

                                    valign = "center",
                                    halign = "center",

                                    textAlignment = "center",
                                    characterLimit = 4,

                                    change = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        local t = element.text
                                        if t:sub(1, 1) == "/" then
                                            t = t:sub(2)
                                        end

                                        local n = tonumber(t)
                                        if n ~= nil then
                                            n = round(n)
                                            token.properties.max_hitpoints = n
                                        end

                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,

                                    refreshToken = function(element, info)
                                        --monsters can direct edit stamina.
                                        element.editable = info.token.properties:IsMonster()

                                        local maxhp = info.token.properties:MaxHitpoints()
                                        element.text = string.format("/%d", math.tointeger(maxhp))
                                    end,

                                    press = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        if token.properties:IsMonster() then
                                            return
                                        end
                                        local baseValue = token.properties:BaseHitpoints()
                                        gui.PopupOverrideAttribute {
                                            parentElement = element,
                                            token = token,
                                            attributeName = "Stamina",
                                            characterSheet = true,
                                            baseValue = baseValue,
                                            modifications = token.properties:DescribeModifications("hitpoints", baseValue),
                                        }
                                    end,

                                },
                            },
                        }
                    },

                    --divider 1
                    gui.Panel {

                        bgimage = true,
                        bgcolor = border_color,
                        width = 2,
                        height = "85%",

                        valign = "center",

                    },

                    gui.Panel {



                        bgimage = true,
                        bgcolor = "clear",
                        width = "21%",
                        height = "100%",


                        gui.Label {

                            text = "RECOVERIES",
                            color = "white",
                            fontSize = 20,

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",

                            halign = "center",
                            valign = "top",

                            tmargin = 10,
                        },

                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            border = 3,
                            borderColor = border_color,

                            width = 80,
                            height = 80,
                            halign = "center",
                            valign = "center",

                            cornerRadius = 40,

                        },

                        gui.Panel {
                            width = "100%",
                            height = 40,
                            y = 8,
                            halign = "center",
                            valign = "center",
                            flow = "vertical",
                            gui.Label {

                                text = "4",
                                color = "white",
                                fontSize = 28,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "30%",
                                height = "50%",
                                characterLimit = 3,
                                editable = true,

                                valign = "center",
                                halign = "center",

                                textAlignment = "center",

                                refreshToken = function(element, info)
                                    local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
                                    local recoveryInfo = resourcesTable[recoveryid]
                                    local quantity = max(0,
                                        (info.token.properties:GetResources()[recoveryid] or 0) -
                                        (info.token.properties:GetResourceUsage(recoveryid, recoveryInfo.usageLimit) or 0))
                                    element.text = string.format("%d", quantity)
                                end,
                                change = function(element)
                                    local resourcesTable = dmhub.GetTable(CharacterResource.tableName)
                                    local recoveryInfo = resourcesTable[recoveryid]
                                    local n = round(tonumber(element.text))
                                    if n ~= nil then
                                        local token = CharacterSheet.instance.data.info.token
                                        local current = token.properties:GetResources()[recoveryid] or 0

                                        n = math.min(math.max(0, n), current)

                                        local used = token.properties:GetResourceUsage(recoveryid,
                                            recoveryInfo.usageLimit) or 0
                                        local desiredTotal = n + used
                                        local diff = desiredTotal - current
                                        if diff > 0 then
                                            token.properties:RefreshResource(recoveryid, recoveryInfo.usageLimit, diff)
                                        else
                                            token.properties:ConsumeResource(recoveryid, recoveryInfo.usageLimit, -diff)
                                        end
                                    end

                                    CharacterSheet.instance:FireEvent("refreshAll")
                                end,
                            },

                            gui.Label {

                                text = "4",
                                color = "white",
                                fontSize = 14,

                                bgimage = true,
                                bgcolor = "clear",
                                width = "auto",
                                height = "50%",
                                bgimage = true,
                                bgcolor = "clear",

                                valign = "center",
                                halign = "center",

                                textAlignment = "center",

                                refreshToken = function(element, info)
                                    local quantity = info.token.properties:GetResources()[recoveryid] or 0
                                    element.text = string.format("/%d", quantity)
                                end,
                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Recoveries",
                                        baseValue = "hide",
                                        modifications = token.properties:DescribeResourceModifications(CharacterResource.recoveryResourceId),
                                        characterSheet = true,
                                    }
                                end,
                            },
                        },

                        gui.Panel {
                            flow = "vertical",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            valign = "bottom",
                            bmargin = 10,
                            bgimage = true,
                            bgcolor = "clear",

                            press = function(element)
                                local token = CharacterSheet.instance.data.info.token
                                gui.PopupOverrideAttribute {
                                    parentElement = element,
                                    token = token,
                                    attributeName = "Recovery Value",
                                    characterSheet = true,
                                    baseValue = math.floor(token.properties:MaxHitpoints() / 3),
                                    modifications = token.properties:DescribeModifications("recoveryvalue", math.floor(token.properties:MaxHitpoints() / 3)),
                                }
                            end,

                            gui.Label {
                                textAlignment = "center",
                                fontSize = 14,
                                bold = true,
                                refreshToken = function(element, info)
                                    element.text = string.format("+%d", info.token.properties:RecoveryAmount())
                                end,
                                text = "+14",
                                width = "auto",
                                height = "auto",
                                valign = "bottom",
                                halign = "center",
                                vmargin = -2,
                            },

                            gui.Label {
                                textAlignment = "center",
                                fontSize = 14,
                                bold = true,
                                text = "Recovery Value",
                                width = "auto",
                                height = "auto",
                                valign = "bottom",
                                halign = "center",
                                vmargin = -2,
                            },
                        },
                    },

                    --divider 2
                    gui.Panel {

                        bgimage = true,
                        bgcolor = border_color,
                        width = 2,
                        height = "85%",

                        valign = "center",

                    },

                    gui.Panel {



                        bgimage = true,
                        bgcolor = "clear",
                        width = "21%",
                        height = "100%",

                        refreshToken = function(element, info)
                            local creature = info.token.properties
                            if creature:IsFollower() then
                                element:SetClass("collapsed", true)
                            else
                                element:SetClass("collapsed", false)
                            end
                        end,

                        gui.Label {

                            text = "HEROIC",
                            color = "white",
                            fontSize = 20,
                            uppercase = true,

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",
                            halign = "center",
                            valign = "top",

                            tmargin = 10,

                            refreshToken = function(element, info)
                                local creature = info.token.properties
                                element.text = string.format("%s", creature:GetHeroicResourceName())
                            end,

                        },

                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            border = 3,
                            borderColor = border_color,

                            width = 80,
                            height = 80,
                            halign = "center",
                            valign = "center",

                            beveledcorners = true,
                            cornerRadius = 20,

                        },

                        gui.Label {

                            text = "4",
                            color = "white",
                            fontSize = 28,

                            characterLimit = 3,
                            editable = true,

                            bgimage = true,
                            bgcolor = "clear",
                            width = "100%",
                            height = "35%",

                            valign = "center",
                            halign = "center",

                            textAlignment = "center",
                            numeric = true,

                            refreshToken = function(element, info)
                                local creature = info.token.properties
                                local resources = creature:GetHeroicOrMaliceResources()
                                element.text = tostring(resources)
                            end,

                            change = function(element)
                                local n = tonumber(element.text)
                                if n ~= nil then
                                    local creature = CharacterSheet.instance.data.info.token.properties
                                    local diff = n - creature:GetHeroicOrMaliceResources()
                                    if diff > 0 then
                                        creature:RefreshResource(CharacterResource.heroicResourceId, "unbounded", diff)
                                    else
                                        creature:ConsumeResource(CharacterResource.heroicResourceId, "unbounded", -diff)
                                    end
                                end

                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        },

                    },

                    --divider 3
                    gui.Panel {

                        bgimage = true,
                        bgcolor = border_color,
                        width = 2,
                        height = "85%",

                        valign = "center",

                    },

                    --surges
                    gui.Panel {

                        bgimage = true,
                        bgcolor = "clear",
                        width = "21%",
                        height = "100%",

                        gui.Label {

                            text = "SURGES",
                            color = "white",
                            fontSize = 20,

                            bgimage = true,
                            bgcolor = "clear",
                            width = "auto",
                            height = "auto",

                            halign = "center",
                            valign = "top",

                            tmargin = 10,
                        },

                        gui.Panel {

                            bgimage = true,
                            bgcolor = "clear",
                            border = 3,
                            borderColor = border_color,

                            width = 80,
                            height = 80,
                            halign = "center",
                            valign = "center",

                        },

                        gui.Label {

                            text = "4",
                            color = "white",
                            fontSize = 28,
                            characterLimit = 3,
                            editable = true,
                            numeric = true,

                            bgimage = true,
                            bgcolor = "clear",
                            width = "100%",
                            height = "35%",

                            valign = "center",
                            halign = "center",

                            textAlignment = "center",

                            refreshToken = function(element, info)
                                local creature = info.token.properties
                                local resources = creature:GetAvailableSurges()
                                element.text = tostring(resources)
                            end,

                            change = function(element)
                                local n = tonumber(element.text)
                                if n ~= nil then
                                    n = math.max(0, n)
                                    local creature = CharacterSheet.instance.data.info.token.properties
                                    local diff = n - creature:GetAvailableSurges()
                                    if diff > 0 then
                                        creature:RefreshResource(CharacterResource.surgeResourceId, "unbounded", diff)
                                    else
                                        creature:ConsumeResource(CharacterResource.surgeResourceId, "unbounded", -diff)
                                    end
                                end

                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        },

                    },

                },


            },

            CharSheet.FeaturesAndNotesPanel(),
        }

    }


    return DSCharSheetPanel
end


function CharSheet.NotesInnerPanel()
    local GetNotes = function(creature)
        if creature:has_key("notes") then
            return creature.notes
        end

        if creature:IsMonster() then
            return {
                {
                    title = "Monster Notes",
                    text = "",
                }
            }
        else
            return {
                {
                    title = "Backstory",
                    text = "",
                }
            }
        end
    end

    local EnsureNotes = function(creature)
        if not creature:has_key("notes") then
            creature.notes = GetNotes(creature)
        end
        return creature.notes
    end

    local CreateNotesSection = function(i, params)
        local resultPanel

        local args = {
            width = "95%",
            height = "auto",
            flow = "vertical",
            halign = "center",

            gui.Panel {
                flow = "horizontal",
                width = "100%",
                height = "auto",
                vmargin = 4,
                gui.Input {
                    fontSize = 14,
                    multiline = false,
                    width = "60%",
                    height = 22,
                    blockChangesWhenEditing = true,
                    placeholderText = "Enter section title...",
                    refreshToken = function(element, info)
                        local notes = GetNotes(info.token.properties)
                        if i <= #notes then
                            element.text = notes[i].title
                        end
                    end,

                    editlag = 1,
                    edit = function(element)
                        element:FireEvent("change")
                    end,
                    change = function(element)
                        local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
                        if i <= #notes and notes[i].title ~= element.text then
                            notes[i].title = element.text
                            CharacterSheet.instance.data.info.token.properties.notesRevision = dmhub.GenerateGuid()
                        end
                    end,
                },
                gui.DeleteItemButton {
                    width = 24,
                    height = 24,
                    halign = "right",
                    click = function(element)
                        resultPanel:FireEvent("delete")
                    end,
                },
            },

            gui.Input {
                width = "98%",
                valign = "top",
                vmargin = 4,
                halign = "center",
                height = "auto",
                multiline = true,
                minHeight = 100,
                textAlignment = "topleft",
                fontSize = 14,
                blockChangesWhenEditing = true,

                placeholderText = "Enter notes...",

                refreshToken = function(element, info)
                    local notes = GetNotes(info.token.properties)
                    if i <= #notes then
                        element.text = notes[i].text
                    end
                end,

                --note when this is edited and make sure that when the sheet is closed we sync
                --any changes to the cloud.
                data = {
                    edits = false
                },

                edit = function(element)
                    element.data.edits = true
                end,

                restoreOriginalTextOnEscape = false,

                closeCharacterSheet = function(element)
                    if element.data.edits then
                        element:FireEvent("change")
                    end
                end,

                change = function(element)
                    element.data.edits = false
                    local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
                    if i <= #notes and notes[i].text ~= element.text then
                        notes[i].text = element.text
                        CharacterSheet.instance.data.info.token.properties.notesRevision = dmhub.GenerateGuid()
                    end
                end,
            },

        }

        for k, p in pairs(params) do
            args[k] = p
        end

        resultPanel = gui.Panel(args)
        return resultPanel
    end

    local addNotesButton = gui.AddButton {
        hmargin = 15,
        halign = "right",
        linger = function(element)
            gui.Tooltip("Add a new section")(element)
        end,
        click = function(element)
            local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
            notes[#notes + 1] = {
                title = "",
                text = "",
            }
            CharacterSheet.instance:FireEvent("refreshAll")
        end,
    }

    local sectionPanels = {}

    return gui.Panel {
        width = "100%",
        height = "100%",
        valign = "center",
        vscroll = true,

        gui.Panel {
            width = "97%",
            hmargin = 4,
            halign = "left",
            height = "auto",

            flow = "vertical",

            addNotesButton,

            refreshToken = function(element, info)
                local notes = GetNotes(info.token.properties)
                local children = {}
                local newSectionPanels = {}

                for i, note in ipairs(notes) do
                    local child = sectionPanels[i] or CreateNotesSection(i, {
                        delete = function(element)
                            local notes = EnsureNotes(CharacterSheet.instance.data.info.token.properties)
                            if i <= #notes then
                                table.remove(notes, i)
                                CharacterSheet.instance:FireEvent("refreshAll")
                            end
                        end,
                    })

                    newSectionPanels[i] = child
                    children[#children + 1] = child
                end

                sectionPanels = newSectionPanels

                children[#children + 1] = addNotesButton

                element.children = children
            end,
        }
    }
end

local function CharacterSheetEditLanguagesPopup(element)
    local resultPanel

    local token = CharacterSheet.instance.data.info.token
    local creature = token.properties
    local parentElement = element

    local languagesTable = dmhub.GetTable(Language.tableName)

    local children = {}

    children[#children + 1] = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "vertical",

        create = function(element)
            element:FireEvent("refreshPanel")
        end,

        refreshPanel = function(element)
            local children = {}

            for k, v in pairs(creature:try_get("innateLanguages", {})) do
                local langid = k
                local lang = languagesTable[k]
                if lang ~= nil then
                    children[#children + 1] = gui.Label {
                        width = "80%",
                        height = 20,
                        flow = "horizontal",
                        text = lang.name,
                        fontSize = 16,
                        textAlignment = "left",
                        halign = "center",

                        gui.DeleteItemButton {
                            width = 16,
                            height = 16,
                            halign = "right",
                            valign = "center",
                            click = function(element)
                                creature.innateLanguages[langid] = nil
                                resultPanel:FireEventTree("refreshPanel")
                                CharacterSheet.instance:FireEvent('refreshAll')
                            end,
                        },
                    }
                end
            end

            table.sort(children, function(a, b) return a.text < b.text end)

            element.children = children
        end,
    }

    children[#children + 1] = gui.Dropdown {
        vmargin = 8,
        hasSearch = true,
        create = function(element)
            element:FireEvent("refreshPanel")
        end,

        refreshPanel = function(element)
            local innateLanguages = creature:try_get("innateLanguages", {})
            local options = {}
            for k, v in unhidden_pairs(languagesTable) do
                if innateLanguages[k] == nil then
                    options[#options + 1] = {
                        id = k,
                        text = string.format("%s (%s)", v.name, v.speakers),
                    }
                end
            end

            table.sort(options, function(a, b) return a.text < b.text end)
            table.insert(options, 1, {
                id = "none",
                text = "Add Language...",
            })

            if creature:try_get("customInnateLanguage") == nil then
                options[#options + 1] = {
                    id = "custom",
                    text = "Custom Language...",
                }
            end

            element.options = options

            element.idChosen = "none"
        end,

        change = function(element)
            if element.idChosen ~= "none" then
                if element.idChosen == "custom" then
                    creature.customInnateLanguage = ""
                else
                    creature:get_or_add("innateLanguages", {})[element.idChosen] = true
                end
                resultPanel:FireEventTree("refreshPanel")
                CharacterSheet.instance:FireEvent('refreshAll')
            end
        end,
    }


    element.popupPositioning = "panel"

    resultPanel = gui.TooltipFrame(
        gui.Panel {
            width = 340,
            height = "auto",
            styles = {
                Styles.Default,
                PopupStyles,
                CharSheet.GetCharacterSheetStyles(),
            },

            children = children,
        },

        {
            halign = "right",
            valign = "center",
            interactable = true,
        }
    )

    parentElement.popup = resultPanel
end


function CharSheet.LanguagesPanel()
    local resultPanel
    resultPanel = gui.Panel {
        width = "100%",
        height = "13%",
        bmargin = 16,

        gui.Panel {

            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = bg_color,
            border = 2,
            borderColor = border_color,
            beveledcorners = true,
            cornerRadius = 15,

            valign = "center",
            flow = "vertical",

            gui.SettingsButton {
                floating = true,
                halign = "right",
                valign = "top",
                hmargin = 18,
                vmargin = 8,
                width = 16,
                height = 16,
                press = function(element)
                    if element.popup ~= nil then
                        element.popup = nil
                    else
                        CharacterSheetEditLanguagesPopup(resultPanel)
                    end
                end,
            },

            gui.Label {

                text = "Languages",
                color = border_color,
                fontSize = 20,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "top",
                tmargin = 5,
            },


            gui.Divider {
                width = "80%",
            },

            gui.Label {
                width = "90%",
                height = 60,
                halign = "center",
                textAlignment = "topleft",
                text = "Languages",
                fontSize = 16,
                minFontSize = 7,
                textOverflow = "ellipsis",
                refreshToken = function(element, info)
                    local creature = info.token.properties

                    local languages = {}
                    local languagesTable = dmhub.GetTable("languages") or {}
                    for langid, _ in pairs(creature:LanguagesKnown()) do
                        local lang = languagesTable[langid]
                        if lang ~= nil then
                            local text = lang.name
                            if trim(lang.speakers) ~= "" then
                                text = text .. " (" .. lang.speakers .. ")"
                            end

                            languages[#languages + 1] = text
                        end
                    end

                    table.sort(languages)
                    element.text = table.concat(languages, ", ")
                end,
            },
        },

    }

    return resultPanel
end

function CharSheet.KitPanel()
    local resultPanel
    resultPanel = gui.Panel {
        refreshToken = function(element, info)
            local c = info.token.properties
            if not c:CanHaveKits() then
                element:SetClass("collapsed", true)
                return
            end

            local kit = c:Kit()
            if kit == nil then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)
            element:FireEventTree("refreshKit", info, kit)
        end,

        width = "100%",
        height = "27%",
        bgimage = true,
        bgcolor = "clear",

        styles = {
            {
                selectors = { "valueLabel" },
                bold = true,
                fontSize = 18,
                hpad = 6,
                textWrap = false,
                minFontSize = 12,
                color = "white",
                textAlignment = "center",
                bgimage = "panels/square.png",
                bgcolor = "clear",
                beveledcorners = true,
                borderColor = border_color,
                border = 1,
                cornerRadius = 4,
                width = "100%",
                height = 24,
                valign = "center",
            },
            {
                selectors = { "labelName" },
                fontSize = 14,
                halign = "center",
                textAlignment = "center",
                width = "100%",
                height = 16,
                bold = false,
                textWrap = false,
            },
            {
                selectors = { "valuePanel" },
                flow = "vertical",
                height = "auto",
                halign = "center",
            }
        },

        gui.Panel {

            width = "100%",
            height = "98%",
            bgimage = true,
            bgcolor = bg_color,
            border = 2,
            borderColor = border_color,
            beveledcorners = true,
            cornerRadius = 15,

            flow = "vertical",


            gui.Panel {

                width = "100%",
                height = 110,

                flow = "vertical",

                gui.Label {

                    text = "Kit",
                    color = border_color,
                    fontSize = 20,
                    halign = "center",
                    valign = "top",
                    height = "auto",
                    width = "auto",

                },

                gui.Divider {

                    width = "80%",
                },

                gui.Panel {

                    width = "70%",
                    height = 40,
                    bgimage = true,
                    bgcolor = "clear",
                    border = 1,
                    borderColor = border_color,
                    beveledcorners = true,
                    cornerRadius = 10,
                    halign = "center",

                    tmargin = 5,

                    gui.Label {

                        text = "Name",
                        width = "auto",
                        height = "auto",
                        color = border_color,
                        fontSize = 15,
                        halign = "center",

                        refreshKit = function(element, info, kit)
                            element.text = kit.name
                        end,

                    },


                },

                gui.Label {

                    text = "Name",
                    width = "auto",
                    height = "auto",
                    color = border_color,
                    fontSize = 15,
                    halign = "center",
                    valign = "top",

                },



            },

            gui.Panel {

                width = "100%",
                height = "auto",

                flow = "horizontal",

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 160,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            local weapons = kit.weapons
                            local weaponItems = {}
                            for w, _ in pairs(weapons) do
                                weaponItems[#weaponItems + 1] = w
                            end
                            table.sort(weaponItems)

                            if #weaponItems == 0 then
                                element.text = "None"
                                return
                            end
                            element.text = table.concat(weaponItems, ",")
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Weapon",
                    }
                },

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 60,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = string.format("+%d", kit.speed)
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Speed",
                    }
                },

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 60,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = kit:FormatDamageBonus("melee") or "-"
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Melee",
                    }
                },

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 60,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = kit:FormatDamageBonus("ranged") or "-"
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Ranged",
                    }
                },

            },

            gui.Panel {

                tmargin = 4,
                width = "100%",
                height = "auto",

                flow = "horizontal",

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 160,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = kit.armor
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Armor",
                    }
                },

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 60,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = string.format("+%d", kit.disengage)
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Disengage",
                    }
                },

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 60,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = string.format("+%d", kit.stability)
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Stability",
                    }
                },

                gui.Panel {
                    classes = { "valuePanel" },
                    width = 60,
                    gui.Label {
                        classes = { "valueLabel" },
                        refreshKit = function(element, info, kit)
                            element.text = string.format("+%d", kit.health)
                        end,
                    },
                    gui.Label {
                        classes = { "labelName" },
                        text = "Stamina",
                    }
                },

            },


        },






    }

    return resultPanel
end

function CharSheet.CreateNotesPanel()
    return gui.Panel {
        width = "100%-4",
        height = "100%",
        halign = "center",

        CharSheet.NotesInnerPanel(),
    }
end

function CharSheet.InnerFeaturesPanel()
    return gui.Panel {
        width = "100%",
        height = "100%",
        valign = "center",
        vscroll = true,
        gui.Panel {
            classes = { "featuresPanel" },
            flow = "vertical",
            width = "97%",
            hmargin = 4,
            halign = "left",
            height = "auto",

            CharSheet.CharacterFeaturesPanel(),


            --list of additional/custom features.
            gui.Panel {
                height = "auto",
                halign = "center",
                width = "100%-16",

                data = {
                    properties = nil,
                },

                refreshToken = function(element, info)
                    if info.token.properties ~= element.data.properties then
                        element.children = { CharacterFeature.ListEditor(info.token.properties, 'characterFeatures',
                            { dialog = CharacterSheet.instance, notify = CharacterSheet.instance }) }
                        element.data.properties = info.token.properties
                    end
                end,
            },

            --creature templates.
            gui.Panel {
                height = "auto",
                halign = "center",
                width = "100%-16",
                flow = "vertical",

                gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    data = {
                        children = {},
                    },
                    refreshToken = function(element, info)
                        local templates = info.token.properties:try_get("creatureTemplates")
                        if templates == nil or #templates <= #element.data.children then
                            return
                        end


                        while #templates > #element.data.children do
                            local label = gui.Label {
                                classes = { "statsLabel" },
                                width = "80%",
                                height = "auto",
                            }
                            local n = #element.data.children + 1
                            element.data.children[n] = gui.Panel {
                                width = "100%",
                                height = "auto",
                                flow = "horizontal",
                                refreshToken = function(element, info)
                                    local templates = info.token.properties:try_get("creatureTemplates")
                                    if templates == nil or #templates < n then
                                        element:SetClass("collapsed", true)
                                        return
                                    end

                                    local templatesTable = dmhub.GetTable("creatureTemplates")
                                    local templateInfo = templatesTable[templates[n]]
                                    if templateInfo == nil then
                                        element:SetClass("collapsed", true)
                                        return
                                    end

                                    element:SetClass("collapsed", false)
                                    if templateInfo.description ~= '' then
                                        label.text = string.format("%s--%s", templateInfo.name, templateInfo.description)
                                    else
                                        label.text = templateInfo.name
                                    end
                                end,

                                label,
                                gui.DeleteItemButton {
                                    width = 24,
                                    height = 24,
                                    halign = "right",
                                    click = function(element)
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        creature:RemoveTemplate(n)
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,
                                },
                            }
                        end

                        element.children = element.data.children
                    end,
                },

                gui.Dropdown {
                    monitorAssets = true,
                    width = 200,
                    height = 30,
                    vmargin = 4,
                    idChosen = "none",

                    create = function(element)
                        element:FireEvent("refreshAssets")
                    end,

                    refreshAssets = function(element)
                        local choices = {
                            {
                                id = "none",
                                text = "Add Creature Template...",
                            },
                        }

                        local templateTable = dmhub.GetTable("creatureTemplates") or {}
                        for k, entry in pairs(templateTable) do
                            if not entry:try_get("hidden", false) then
                                choices[#choices + 1] = {
                                    id = k,
                                    text = entry.name,
                                }
                            end
                        end

                        element.options = choices
                    end,

                    change = function(element)
                        local creature = CharacterSheet.instance.data.info.token.properties
                        if element.idChosen ~= "none" then
                            creature:AddTemplate(element.idChosen)
                        end
                        element.idChosen = "none"
                        CharacterSheet.instance:FireEvent('refreshAll')
                    end,

                },
            },


            --feats.
            gui.Panel {
                height = "auto",
                halign = "center",
                width = "100%-16",
                flow = "vertical",

                refreshToken = function(element, info)
                    if info.token.properties:IsMonster() then
                        element:SetClass("collapsed", true)
                        return
                    end

                    element:SetClass("collapsed", false)
                end,

                gui.Panel {
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    data = {
                        children = {},
                    },
                    refreshToken = function(element, info)
                        local feats = info.token.properties:try_get("creatureFeats")
                        if feats == nil or #feats <= #element.data.children then
                            return
                        end


                        while #feats > #element.data.children do
                            local label = gui.Label {
                                classes = { "statsLabel" },
                                width = "80%",
                                height = "auto",
                            }
                            local n = #element.data.children + 1
                            element.data.children[n] = gui.Panel {
                                width = "100%",
                                height = "auto",
                                flow = "horizontal",
                                refreshToken = function(element, info)
                                    local feats = info.token.properties:try_get("creatureFeats")
                                    if feats == nil or #feats < n then
                                        element:SetClass("collapsed", true)
                                        return
                                    end

                                    local featsTable = dmhub.GetTable(CharacterFeat.tableName)
                                    local featInfo = featsTable[feats[n]]
                                    if featInfo == nil then
                                        element:SetClass("collapsed", true)
                                        return
                                    end

                                    element:SetClass("collapsed", false)
                                    if featInfo.description ~= '' then
                                        label.text = string.format("%s", featInfo.name)
                                    else
                                        label.text = featInfo.name
                                    end
                                end,

                                label,
                                gui.DeleteItemButton {
                                    width = 24,
                                    height = 24,
                                    halign = "right",
                                    click = function(element)
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        creature:RemoveFeat(n)
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,
                                },
                            }
                        end

                        element.children = element.data.children
                    end,
                },

            },


        }
    }
end

function CharSheet.CreateFeaturesPanel()
    return gui.Panel {
        width = "100%",
        height = "100%",
        CharSheet.InnerFeaturesPanel(),
    }
end

function CharSheet.FeaturesAndNotesPanel()
    local notesPanel = CharSheet.CreateNotesPanel()
    local featuresPanel = CharSheet.CreateFeaturesPanel()
    local followersPanel = CharSheet.CreateFollowersPanel()
    local contentPanels = { notesPanel, featuresPanel, followersPanel }
    for i = 1, #contentPanels do
        contentPanels[i]:SetClass("collapsed", i ~= 1)
    end

    local CreateTab = function(text, index)
        return gui.Label {
            classes = { "tab", cond(index == 1, "selected") },
            bgimage = true,
            text = text,
            press = function(element)
                for i, panel in ipairs(element.parent.children) do
                    panel:SetClass("selected", i == index)
                end
                for i, panel in ipairs(contentPanels) do
                    panel:SetClass("collapsed", i ~= index)
                end
            end,

            refreshToken = function(element, info)
                local creature = CharacterSheet.instance.data.info.token.properties
                if text ~= "Followers" then
                    return
                end
                if creature:IsHero() then
                    element:SetClass("collapsed", false)
                else
                    element:SetClass("collapsed", true)
                    -- If followers tab was selected but creature is not a hero, switch to Notes tab
                    if element.parent.children[3]:HasClass("selected") then
                        -- Switch to Notes tab (index 1)
                        for i, tabPanel in ipairs(element.parent.children) do
                            tabPanel:SetClass("selected", i == 1)
                        end
                        for i, panel in ipairs(contentPanels) do
                            panel:SetClass("collapsed", i ~= 1)
                        end
                    end
                end
            end,
        }
    end

    local resultPanel
    resultPanel = gui.Panel {
        width = "100%-40",
        height = "55.3%",
        bgimage = true,
        bgcolor = bg_color,
        valign = "top",
        halign = "center",
        borderColor = border_color,
        borderWidth = 2,
        flow = "vertical",

        styles = {
            Styles.Tabs,

        },

        --tab panel.
        gui.Panel {
            flow = "horizontal",
            valign = "top",
            width = "100%",
            height = "auto",
            bgimage = true,
            bgcolor = "clear",
            borderColor = "#aaaaaa",
            borderWidth = 1,
            CreateTab("Notes", 1),
            CreateTab("Features", 2),
            CreateTab("Followers", 3),
        },
        gui.Panel {
            width = "100%",
            height = "100%-50",
            children = contentPanels,
        },
    }

    return resultPanel
end

CharSheet.RegisterTab {
    id = "CharacterSheet",
    text = "Character",
    panel = DSCharSheet,

}

CharSheet.defaultSheet = "CharacterSheet"

dmhub.RefreshCharacterSheet()
