local mod = dmhub.GetModLoading()

local g_mainActionId = "d19658a2-4d7b-4504-af9e-1a5410fb17fd"
local g_maneuverId = "a513b9a6-f311-4b0f-88b8-4e9c7bf92d0b"
local g_triggeredactionId = "b9bc06dd-80f1-4f33-bc55-25c114e3300c"
local g_villainActionId = "villain-action"
local g_abilityActionSortOrder = {
    [g_mainActionId] = -2,
    [g_maneuverId] = -1,
    [g_triggeredactionId] = 0,
    [g_villainActionId] = 1,
}

--Transient highlight for a capability revealed from search (Phase B). The
--reveal flashes the accent on instantly, HOLDS it, then fades out over
--SEARCH_REVEAL_FADE (the rule's transitionTime, eased) with a dark gap before
--the next flash - a gentle "here I am" rather than an aggressive strobe. The
--rule is merged into the action-list and Features panel style cascades so it
--resolves on either surface.
local SEARCH_REVEAL_FADE = 0.8
local SEARCH_REVEAL_RULE = {
    selectors = { "searchReveal" },
    bgcolor = "@accent",
    transitionTime = SEARCH_REVEAL_FADE,
    easing = "easeInOutSine",
}

--Scroll an arbitrary descendant into (vertically centered) view within its
--nearest vscroll ancestor. There is no engine ScrollIntoView and no
--child-offset API, so the offset is summed from the rendered heights of
--preceding siblings up the chain to the scroll panel (the normalized-position
--math mirrors JournalPDFViewer). Returns false until layout has rendered
--(heights still 0), so the caller can retry; true once it has positioned (or
--when everything fits and no scroll is needed). Every engine read is
--pcall-guarded - panel reads ERROR rather than return nil.
local function ScrollCapabilityIntoView(target)
    if target == nil or not target.valid then
        return false
    end

    local scrollPanel = target.parent
    while scrollPanel ~= nil do
        local isScroll = false
        pcall(function() isScroll = scrollPanel.vscroll == true end)
        if isScroll then
            break
        end
        scrollPanel = scrollPanel.parent
    end
    if scrollPanel == nil then
        return false
    end

    local windowH = 0
    local targetH = 0
    pcall(function() windowH = scrollPanel.renderedHeight or 0 end)
    pcall(function() targetH = target.renderedHeight or 0 end)
    if windowH <= 0 or targetH <= 0 then
        return false
    end

    local contentH = 0
    pcall(function()
        for _, c in ipairs(scrollPanel.children) do
            contentH = contentH + (c.renderedHeight or 0)
        end
    end)
    local range = contentH - windowH
    if range <= 0 then
        --Everything fits; the target is already visible.
        return true
    end

    local offset = 0
    local node = target
    while node ~= nil and node ~= scrollPanel do
        local parent = node.parent
        if parent == nil then
            return false
        end
        pcall(function()
            for _, s in ipairs(parent.children) do
                if s == node then
                    break
                end
                offset = offset + (s.renderedHeight or 0)
            end
        end)
        node = parent
    end

    local desiredTop = offset - (windowH - targetH) * 0.5
    if desiredTop < 0 then
        desiredTop = 0
    elseif desiredTop > range then
        desiredTop = range
    end
    --vscrollPosition: 1 = top, 0 = bottom.
    scrollPanel.vscrollPosition = 1 - desiredTop / range
    return true
end

--Each pulse: fade the accent IN over SEARCH_REVEAL_FADE, HOLD at full for
--SEARCH_REVEAL_HOLD, fade OUT over SEARCH_REVEAL_FADE (symmetric), then a slight
--SEARCH_REVEAL_GAP pause before the next fade-in - a gentle "here I am" breathe.
--Plain SetClass(true)/(false) animate both directions over the rule's
--transitionTime. A finite scheduled chain (no persistent think).
local SEARCH_REVEAL_PULSES = 3
local SEARCH_REVEAL_HOLD = 0.3
local SEARCH_REVEAL_GAP = 0.1
local function PulseRevealRepeated(target)
    local remaining = SEARCH_REVEAL_PULSES
    local function cycle()
        if mod.unloaded or target == nil or not target.valid then
            return
        end
        target:SetClass("searchReveal", true)
        --Hold begins once the fade-in has completed.
        dmhub.Schedule(SEARCH_REVEAL_FADE + SEARCH_REVEAL_HOLD, function()
            if mod.unloaded or target == nil or not target.valid then
                return
            end
            target:SetClass("searchReveal", false)
            remaining = remaining - 1
            if remaining > 0 then
                dmhub.Schedule(SEARCH_REVEAL_FADE + SEARCH_REVEAL_GAP, cycle)
            end
        end)
    end
    cycle()
end

--Phase B for a revealed capability: locate the matched row (findTarget runs
--each retry because the row may still be building / unrendered), scroll it
--into view, then pulse the highlight. Retries briefly while the freshly
--expanded section lays out (heights start at 0); gives up quietly.
local function ScheduleRevealAndPulse(findTarget)
    local attempts = 0
    local function attempt()
        if mod.unloaded then
            return
        end
        local target = findTarget()
        if target ~= nil and target.valid and ScrollCapabilityIntoView(target) then
            PulseRevealRepeated(target)
            return
        end
        attempts = attempts + 1
        if attempts < 12 then
            dmhub.Schedule(0.05, attempt)
        end
    end
    attempt()
end

local fontScaling = 1
local g_styles = {
    {
        selectors = { "FontNumbers" },
        fontSize = 16 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Header1" },
        fontSize = 12 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Header2" },
        fontSize = 8 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        uppercase = true,
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Subheader" },
        fontSize = 6 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        uppercase = true,
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "SubheaderBold" },
        fontSize = 6 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        uppercase = true,
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Body" },
        fontSize = 8 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "BodyBold" },
        fontSize = 8 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Details" },
        fontSize = 7 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Details_Skill_Untrained" },
        fontSize = 7 * fontScaling,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = "@fgStrong",
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
        color = "#8cdecf",  -- bespoke trained-skill mint; no clean token analog
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
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "Annotation*" },
        fontSize = 6 * fontScaling,
        fontFace = "Berling",
        fontWeight = "SemiBold",
        color = "@fgInverse",
        width = "auto",
        height = "auto",
    },
    {
        selectors = { "panel_bg_hero" },
        bgcolor = "@bgInverse"
    },
    {
        selectors = { "panel_bg_monster" },
        bgcolor = "@danger",
        borderColor = "@danger",
    },
    {
        selectors = { "panel_hero_filled" },
        bgimage = true,
        bgcolor = "@bg",
        halign = "center",
        valign = "top",
        width = 260,
        height = 50,
        borderColor = "@border",
        flow = "vertical",
        opacity = 0.9,
    },
    {
        selectors = { "panel_hero_label" },
        fontSize = 12,
        fontFace = "Berling",
        fontWeight = "Regular",
        color = "@fgStrong",
        height = "auto",
        valign = "top",
        halign = "center",
        width = "auto",
        bmargin = 8,

    },
    -- Solid panel-as-divider line (fakes a border via a thin filled panel).
    -- Apply to panels with width/height sized as a thin bar; bgcolor follows
    -- the active scheme's border token so the visual stays consistent with
    -- real {bordered} frames elsewhere on the sheet.
    {
        selectors = { "cs-divider-line" },
        bgcolor = "@border",
    },
    -- Privacy (eye) icon on the name field.  Tints with the scheme's strong
    -- foreground so the icon stays legible across schemes.  PNG is a white
    -- silhouette with alpha; bgcolor acts as a tint multiplier.
    {
        selectors = { "privacyIcon" },
        halign = "right",
        valign = "center",
        x = 16,
        width = 16,
        height = 16,
        bgimage = "ui-icons/eye-closed.png",
        bgcolor = "@fgStrong",
    },
    {
        selectors = { "privacyIcon", "hover" },
        brightness = 1.5,
    },
    {
        selectors = { "privacyIcon", "inactive" },
        bgimage = "ui-icons/eye.png",
    },
}

local PopupStyles = {

    {
        valign = 'bottom',
        halign = 'center',
        width = 'auto',
        height = 'auto',
        bgcolor = "@bg",
        flow = 'vertical',
        fontSize = 12,
    },
    {
        selectors = { 'popupWindow' },
        valign = 'bottom',
        halign = 'center',
        width = 300,
        height = 'auto',
        bgcolor = "@bg",
        flow = 'vertical',
        borderColor = "@border",
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
        color = "@fgStrong",
        fontSize = 16,
        width = 'auto',
        height = 'auto',
        minWidth = 220,
        valign = "center",
    },
    {
        selectors = { 'popupValue' },
        color = "@fgStrong",
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
        color = "@accent",
        priority = 2,
    },
    {
        selectors = { 'option' },
        bgcolor = "@bg",
        width = '100%',
        height = 20,
    },
    {
        selectors = { 'option', 'selected' },
        bgcolor = "@danger",
    },
    {
        selectors = { 'option', 'hover' },
        bgcolor = "@danger",
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
            --Stamped so the search reveal (Phase B) can locate this panel by
            --the matched ability name.
            element.data.capabilityName = ability.name
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
            gradientMapping = true,
            ability = function(element, ability, c)
                element.bgimage = ability:GetIcon()
                element.selfStyle = ability:GetIconDisplay()
                element.selfStyle.gradient = ability:GetIconGradient()
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
                    local keywords = {}
                    for k,_ in pairs(ability.keywords) do
                        keywords[#keywords+1] = ActivatedAbility.CanonicalKeyword(k)
                    end
                    table.sort(keywords)
                    element.text = string.join(keywords, ", ")
                end,
            },
        },

        -- Button group: customise (always visible) + settings (innate only).
        gui.Panel{
            floating = true,
            halign   = "right",
            valign   = "top",
            flow     = "horizontal",
            width    = "auto",
            height   = "auto",
            tmargin  = 2,
            rmargin  = 4,

            gui.Button{
                classes = {"customiseAbilityButton"},
                tooltip = "Customize this ability",
                press   = function(element)
                    if m_ability == nil then return end
                    local tok = CharacterSheet.instance.data.info.token
                    if tok == nil or not tok.valid then return end
                    CharacterSheet.instance:AddChild(
                        m_ability:ShowCustomisationDialog(tok, CharacterSheet.instance)
                    )
                end,
            },

            gui.Button{
                classes = {"settingsButton"},
                lmargin  = 8,
                ability = function(element, ability, c)
                    element:SetClass("hidden", not c:IsActivatedAbilityInnate(ability))
                end,
                press   = function(element)
                    --this gets the actual underlying ability.
                    local ability = CharacterSheet.instance.data.info.token.properties:IsActivatedAbilityInnate(m_ability)
                    if not ability then return end
                    CharacterSheet.instance:AddChild(ability:ShowEditActivatedAbilityDialog{
                        close = function(element)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                        delete = function(element)
                            CharacterSheet.instance.data.info.token.properties:RemoveInnateActivatedAbility(ability)
                        end,
                    })
                end,
            },
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
            --Stamped so the search reveal (Phase B) can locate this panel by
            --the matched ability name.
            element.data.capabilityName = ability.name
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
                    local keywords = {}
                    for k,_ in pairs(ability.keywords) do
                        keywords[#keywords+1] = ActivatedAbility.CanonicalKeyword(k)
                    end
                    table.sort(keywords)
                    element.text = string.join(keywords, ", ")
                end,
            },
        },

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

    local m_villainActionsLabel = gui.Label {
        classes = { "submenuHeading" },
        data = { ord = g_villainActionId },
        width = "100%",
        text = "Villain Actions",
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
    m_villainActionsLabel:SetClassTree("collapseSet", true)

    local function IsVillainAction(ability)
        local v = ability:try_get("villainAction")
        return v ~= nil and v ~= "none"
    end

    local GetActionId = function(ability)
        if IsVillainAction(ability) then
            return g_villainActionId
        end
        local actionid = ability:ActionResource()
        if actionid ~= g_mainActionId and actionid ~= g_maneuverId then
            actionid = "other"
        end
        return actionid
    end

    local function buildActionMenuStyles()
        return ThemeEngine.MergeTokens{
            Styles.ActionMenu,

            { selectors = {"submenuHeading"},
              bgcolor = "@bgAlt", borderColor = "@border",
              color = "@fgStrong", fontSize = 16 },
            { selectors = {"submenuHeading", "hover"},
              bgcolor = "@bg", borderColor = "@fgStrong" },

            { selectors = {"abilityHeading"},
              bgcolor = "@bg", borderColor = "@border" },
            { selectors = {"abilityHeading", "hover"},
              bgcolor = "@bgAlt", borderColor = "@accent" },

            { selectors = {"abilityTitle"},     color = "@fgStrong" },
            { selectors = {"abilityInfoLabel"}, color = "@fgMuted" },

            SEARCH_REVEAL_RULE,
        }
    end

    resultPanel = gui.Panel {
        m_mainActionsLabel,
        m_maneuversLabel,
        m_triggersLabel,
        m_otherActionsLabel,
        m_villainActionsLabel,
        styles = buildActionMenuStyles(),
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
            local abilities = c:GetActivatedAbilities {} -- characterSheet = true }
            local children = {}

            local hasVillainActions = false
            for _, ability in ipairs(abilities) do
                if IsVillainAction(ability) then
                    hasVillainActions = true
                    break
                end
            end
            m_villainActionsLabel:SetClass("collapsed", not hasVillainActions)

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

            if hasVillainActions and not m_villainActionsLabel:HasClass("collapseSet") then
                showAbilities[g_villainActionId] = true
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

                if action_a == g_villainActionId then
                    -- Villain Action 1 < Villain Action 2 < Villain Action 3 by string compare
                    return a:try_get("villainAction", "") < b:try_get("villainAction", "")
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
            local headings = { m_mainActionsLabel, m_maneuversLabel, m_triggersLabel, m_otherActionsLabel, m_villainActionsLabel }
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

        --Deep-link hook: the bestiary monster-ability search result fires
        --"revealCapability" after opening the sheet, to expand the action
        --section holding the matched ability so it is visible without
        --hunting. Traits render on the Features tab (handled there), so a
        --"Trait" capability is ignored here; a no-op if the ability is not
        --found. Note a name can be BOTH an ability and a trait (e.g.
        --"Abyssal Protectors") - the categorization decides which surface
        --reveals it.
        revealCapability = function(element, capName, categorization)
            if type(capName) ~= "string" or capName == "" or categorization == "Trait" then
                return
            end
            local token = CharacterSheet.instance.data.info.token
            if token == nil then
                return
            end
            local c = token.properties
            local header = nil

            --Triggered abilities live in their own section, separate from
            --the activated-ability list.
            pcall(function()
                for _, a in ipairs(c:GetTriggeredActions()) do
                    if a.name == capName then
                        header = m_triggersLabel
                        return
                    end
                end
            end)

            if header == nil then
                pcall(function()
                    for _, a in ipairs(c:GetActivatedAbilities {}) do
                        if a.name == capName then
                            local ord = GetActionId(a)
                            if ord == g_villainActionId then
                                header = m_villainActionsLabel
                            elseif ord == g_mainActionId then
                                header = m_mainActionsLabel
                            elseif ord == g_maneuverId then
                                header = m_maneuversLabel
                            else
                                header = m_otherActionsLabel
                            end
                            return
                        end
                    end
                end)
            end

            if header ~= nil then
                header:SetClassTree("collapseSet", false)
                element:FireEvent("refreshToken")

                --Phase B: scroll the now-rendered ability panel into view and
                --pulse it. The panels stamp data.capabilityName; the matching
                --one is non-collapsed (pooled-out panels keep a stale name).
                local listPanel = element
                ScheduleRevealAndPulse(function()
                    local result = nil
                    local function walk(p, depth)
                        if p == nil or depth > 8 or result ~= nil then
                            return
                        end
                        local cn = nil
                        pcall(function() cn = p.data and p.data.capabilityName or nil end)
                        if cn == capName and not p:HasClass("collapsed") then
                            result = p
                            return
                        end
                        local ok, ch = pcall(function() return p.children end)
                        if ok and type(ch) == "table" then
                            for _, c in ipairs(ch) do
                                walk(c, depth + 1)
                            end
                        end
                    end
                    walk(listPanel, 0)
                    return result
                end)
            end
        end,
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = buildActionMenuStyles()
        end
    end)

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
                fontSize = 20,
                textAlignment = "center",
                characterLimit = 30,

                bgimage = true,
                classes = {"bordered"},

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
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",


            },

            --ancestry of character
            gui.Label {

                text = "Ancestry",
                fontSize = 20,
                textAlignment = "center",

                bgimage = true,
                classes = {"bordered"},

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
                    if info.token.properties:IsMonster() or info.token.properties:IsCompanion() then
                        element.text = info.token.properties:try_get("monster_type", "")
                        if element.text == "" then
                            element.text = "(No monster type)"
                            element:SetClass("invalid", true)
                        else
                            element:SetClass("invalid", false)
                        end
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
                    if info.token.properties:IsCompanion() then
                        element.text = "Companion Type"
                    elseif info.token.properties:IsMonster() then
                        element.text = "Monster"
                    else
                        element.text = "Ancestry"
                    end
                end,
                text = "Ancestry",
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",


            },

            --class of character
            gui.Label {

                text = "Class",
                fontSize = 20,
                minFontSize = 12,
                textAlignment = "center",

                bgimage = true,
                classes = {"bordered"},

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

                gui.Button {
                    classes = {"settingsButton"},
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
                                    monsterKeywords[#monsterKeywords + 1] = { id = keyword, text = ActivatedAbility.CanonicalKeyword(keyword) }
                                end
                            end

                            table.sort(monsterKeywords, function(a, b) return a.text < b.text end)

                            local resultPanel
                            resultPanel = gui.TooltipFrame(
                                gui.Panel {
                                    width = 500,
                                    height = "auto",
                                    flow = "vertical",
                                    pad = 8,
                                    borderBox = true,

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
                                                        local group = MonsterGroup.Get(token.properties.groupid)
                                                        if group ~= nil then
                                                            token.properties.monster_category = group.name
                                                        end
                                                    end
                                                end,
                                            },
                                        },

                                        gui.MCDMDivider {
                                            width = "80%",
                                            height = 1,
                                            vmargin = 8,
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

                                            gui.Multiselect {
                                                value = rawget(token.properties, "keywords") or {},
                                                width = "80%",
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

                            element.popupsInheritStyles = true
                            element.popup = resultPanel
                        end
                    end,
                },
            },

            --class label
            gui.Label {
                text = "Class",
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

                classes = { "bordered", "monstercollapse", "followercollapse" },
                text = "Subclass",
                fontSize = 20,
                textAlignment = "center",

                bgimage = true,

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
                fontSize = 12,
                textAlignment = "center",

                width = "100%",
                height = "auto",
                halign = "center",


            },

            --Monsters can be treated as objects
            gui.Dropdown {
                classes = { "monsterorfolloweronly" },
                options = {
                    { id = "creature", text = "Creature" },
                    { id = "object",   text = "Object" },
                },
                refreshToken = function(element, info)
                    local c = info.token.properties
                    element.idChosen = cond(c:try_get("treatAsObject", false), "object", "creature")
                end,
                change = function(element)
                    local c = CharacterSheet.instance.data.info.token.properties
                    c.treatAsObject = (element.idChosen == "object")
                    CharacterSheet.instance:FireEvent('refreshAll')
                end,
            },

            gui.Label {
                classes = { "monsterorfolloweronly" },
                text = "Treat as",
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

            classes = {"bordered"},
            bgimage = true,
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
                    height = 30,
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
                textAlignment = "center",
                numeric = true,
                height = 24,
                width = 34,
                lmargin = 4,
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
                hasSearch = true,
                sort = true,
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

            gui.Button {
                classes = {"deleteButton"},
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
        classes = {"sizeXl", "bold"},
        halign = "center",
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
        gui.Button {
            classes = {"sizeM"},
            text = 'Add Entry',
            halign = 'center',
            valign = 'bottom',
            vmargin = 4,
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

    element.popupPositioning = "panel"

    element.popup = gui.Panel {
        classes = {"framedPanel"},
        halign = "right",
        interactable = true,
        flow = "vertical",
        hpad = 24,
        vpad = 14,
        width = "auto",
        height = "auto",
        styles = ThemeEngine.MergeStyles{
            PopupStyles,
        },
        children = children,
    }
end

--==============================================================
-- Monster level scaling: the "Adjust Level" dialog (chunk 4).
--
-- Opens from the LEVEL indicator in the monster stat-block header. It previews
-- the full consequence of moving to a target level -- a Now / After compare
-- table with signed deltas, an echelon callout (only when crossing 3/4, 6/7,
-- 9/10) and a scaling-down note -- before committing via
-- monster:SetLevelAdjustment. All math + the generated feature live in
-- MCDMMonster.lua (MCDMMonsterScaling + monster:Set/Clear/HasLevelAdjustment);
-- this is presentation only.
--
-- Per-creature stats (EV / Stamina / Free strike) read the creature's actual
-- current value and show After = Now + (current -> target) delta, exactly what
-- Apply produces. Reference stats (Damage, Highest characteristic, Potency) are
-- shown from the MCDM table / formula at the current vs target level (there is
-- no single per-creature damage number, and characteristic / potency are
-- echelon-derived).
--==============================================================

local function ScalingSignedString(n)
    if n > 0 then
        return string.format("+%d", n)
    end
    return string.format("%d", n)
end

local function ShowAdjustLevelDialog(token)
    if token == nil or token.properties == nil then
        return
    end
    local props = token.properties
    if not props:IsMonster() then
        return
    end

    local org, role = props:ScalingOrgRole()
    local isLeaderSolo = (org == "leader" or org == "solo")
    local dtype = MCDMMonsterScaling.DamageType(org, role)

    -- Strikes add the highest characteristic on top of the table damage and so
    -- scale differently from non-strike power rolls (table delta + characteristic
    -- delta vs table delta alone). Only surface a Strike damage row when this
    -- monster actually has a strike ability, so monsters without one get no dead row.
    local hasStrike = false
    for _, a in ipairs(props:GetActivatedAbilities {}) do
        if a:HasKeyword("Strike") then
            hasStrike = true
            break
        end
    end

    local minLevel = MCDMMonsterScaling.minLevel
    local maxLevel = MCDMMonsterScaling.maxLevel
    local baseLevel = props:GetScalingBaseLevel()
    local currentLevel = round(tonumber(props:CharacterLevel()) or baseLevel)
    currentLevel = math.max(minLevel, math.min(maxLevel, currentLevel))

    -- The creature's actual current per-creature stats (these already include
    -- any adjustment in effect now).
    local nowEV = round(tonumber(props:EV()) or 0)
    local nowStamina = round(tonumber(props:MaxHitpoints()) or 0)
    local nowFreeStrike = round(tonumber(props:OpportunityAttack()) or 0)

    -- Minion squads. A level adjustment normally hits only this token, but a
    -- minion is one of a squad of identical minions, so scaling one leaves the
    -- rest behind. When this minion belongs to a squad we offer to scale every
    -- member together (default on). Squad membership = same MinionSquad name and
    -- monster type; recomputed fresh at Apply time so deaths mid-dialog can't
    -- leave a stale target list.
    local function CollectSquadMembers()
        local squadName = nil
        pcall(function() squadName = props:MinionSquad() end)
        if not props:try_get("minion", false) or squadName == nil then
            return { token }
        end
        local mtype = props:try_get("monster_type", nil)
        local members = {}
        for _, t in ipairs(dmhub.GetTokens() or {}) do
            local tp = t.properties
            local match = false
            pcall(function()
                match = tp ~= nil and tp:try_get("minion", false) == true
                    and tp:MinionSquad() == squadName
                    and (mtype == nil or tp:try_get("monster_type", nil) == mtype)
            end)
            if match then
                members[#members + 1] = t
            end
        end
        if #members == 0 then
            return { token }
        end
        return members
    end

    local squadSize = #CollectSquadMembers()
    local isSquadMinion = squadSize > 1
    -- Default on: the common case is scaling the whole squad together.
    local applyToSquad = isSquadMinion

    -- Mutable selection; starts at the current level (no change).
    local targetLevel = currentLevel

    -- Forward-declared so the helpers / event handlers below can reach them.
    local dialog
    local previewPanel
    local valueLabel
    local slider
    local echelonBanner
    local noteLabel
    local footerLabel
    local squadCheck

    local function signum(n)
        if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end
    end

    -- Adjustment-column text: the signed delta, or blank when unchanged.
    local function adjStr(n)
        if n == 0 then return "" end
        return ScalingSignedString(n)
    end

    -- One Now / After / Adjustment compare row. The Adjustment column is tinted
    -- success (increase) or danger (decrease); dir is its sign. Unchanged
    -- echelon rows (dim=true) are quieted so the rows that move stay salient.
    local function CompareRow(idx, labelText, nowText, afterText, adjText, dir, dim)
        local changed = dir ~= 0
        local quiet = dim and not changed
        local adjClass = { "tableLabel", "bold" }
        if dir > 0 then
            adjClass = { "tableLabel", "bold", "adjustInc" }
        elseif dir < 0 then
            adjClass = { "tableLabel", "bold", "adjustDec" }
        end
        return gui.Panel{
            classes = { "row", cond(idx % 2 == 0, "evenRow", "oddRow") },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            borderBox = true,
            hpad = 10,
            vpad = 5,
            opacity = cond(quiet, 0.5, 1.0),

            gui.Label{ classes = { "tableLabel" }, text = labelText, width = "36%", height = "auto", halign = "left", textWrap = true },
            gui.Label{ classes = { "tableLabel" }, text = nowText, width = "17%", height = "auto", textAlignment = "center" },
            gui.Label{ classes = { "tableLabel" }, text = afterText, width = "17%", height = "auto", textAlignment = "center" },
            gui.Label{ classes = adjClass, text = adjText, width = "30%", height = "auto", textAlignment = "center" },
        }
    end

    local function BuildPreviewRows()
        local deltas = MCDMMonsterScaling.ComputeDeltas(org, role, currentLevel, targetLevel) or {}
        local rows = {}

        rows[#rows+1] = gui.Panel{
            classes = { "row", "headerRow" },
            width = "100%",
            height = "auto",
            flow = "horizontal",
            borderBox = true,
            hpad = 10,
            vpad = 8,
            gui.Label{ classes = { "tableLabel", "bold" }, text = "", width = "36%", height = "auto" },
            gui.Label{ classes = { "tableLabel", "bold" }, text = "Now", width = "17%", height = "auto", textAlignment = "center" },
            gui.Label{ classes = { "tableLabel", "bold" }, text = "After", width = "17%", height = "auto", textAlignment = "center" },
            gui.Label{ classes = { "tableLabel", "bold" }, text = "Adjustment", width = "30%", height = "auto", textAlignment = "center" },
        }

        -- Separator under the header so it reads distinctly from the data rows.
        rows[#rows+1] = gui.Panel{ classes = { "adjustDivider" }, width = "100%", height = 1, bmargin = 2 }

        local idx = 0
        local function add(labelText, nowText, afterText, adjText, dir, dim)
            idx = idx + 1
            rows[#rows+1] = CompareRow(idx, labelText, nowText, afterText, adjText, dir, dim)
        end

        -- Encounter value (per-creature)
        add("Encounter value",
            string.format("%d", nowEV),
            string.format("%d", nowEV + (deltas.ev or 0)),
            adjStr(deltas.ev or 0), signum(deltas.ev or 0), false)

        -- Stamina (per-creature)
        add("Stamina",
            string.format("%d", nowStamina),
            string.format("%d", nowStamina + (deltas.stamina or 0)),
            adjStr(deltas.stamina or 0), signum(deltas.stamina or 0), false)

        -- Damage T1/T2/T3 (reference: MCDM table for this org/role)
        local rowCur = MCDMMonsterScaling.RowFor(org, currentLevel)
        local rowTgt = MCDMMonsterScaling.RowFor(org, targetLevel)
        local dmgNow = rowCur and rowCur[dtype]
        local dmgTgt = rowTgt and rowTgt[dtype]
        if dmgNow ~= nil and dmgTgt ~= nil then
            local d1, d2, d3 = deltas.t1 or 0, deltas.t2 or 0, deltas.t3 or 0
            local changed = d1 ~= 0 or d2 ~= 0 or d3 ~= 0
            local dStr = ""
            if changed then
                dStr = string.format("%s / %s / %s",
                    ScalingSignedString(d1), ScalingSignedString(d2), ScalingSignedString(d3))
            end
            add("Damage (T1 / T2 / T3)",
                string.format("%d / %d / %d", dmgNow[1], dmgNow[2], dmgNow[3]),
                string.format("%d / %d / %d", dmgTgt[1], dmgTgt[2], dmgTgt[3]),
                dStr, cond(changed, signum(targetLevel - currentLevel), 0), false)

            -- Strike damage = table damage + highest characteristic, which scales
            -- by the table delta plus the characteristic delta (so it moves more
            -- than the row above when an echelon boundary is crossed). Only shown
            -- when the monster has a strike ability.
            if hasStrike then
                local sCharNow = MCDMMonsterScaling.HighestCharacteristic(currentLevel, isLeaderSolo)
                local sCharTgt = MCDMMonsterScaling.HighestCharacteristic(targetLevel, isLeaderSolo)
                local s1 = (dmgTgt[1] + sCharTgt) - (dmgNow[1] + sCharNow)
                local s2 = (dmgTgt[2] + sCharTgt) - (dmgNow[2] + sCharNow)
                local s3 = (dmgTgt[3] + sCharTgt) - (dmgNow[3] + sCharNow)
                local sChanged = s1 ~= 0 or s2 ~= 0 or s3 ~= 0
                local sStr = ""
                if sChanged then
                    sStr = string.format("%s / %s / %s",
                        ScalingSignedString(s1), ScalingSignedString(s2), ScalingSignedString(s3))
                end
                add("Strike damage (T1 / T2 / T3)",
                    string.format("%d / %d / %d", dmgNow[1] + sCharNow, dmgNow[2] + sCharNow, dmgNow[3] + sCharNow),
                    string.format("%d / %d / %d", dmgTgt[1] + sCharTgt, dmgTgt[2] + sCharTgt, dmgTgt[3] + sCharTgt),
                    sStr, cond(sChanged, signum(targetLevel - currentLevel), 0), false)
            end
        end

        -- Free strike (per-creature; T1 table delta, no characteristic)
        add("Free strike",
            string.format("%d", nowFreeStrike),
            string.format("%d", nowFreeStrike + (deltas.freeStrike or 0)),
            adjStr(deltas.freeStrike or 0), signum(deltas.freeStrike or 0), false)

        -- Highest characteristic (reference formula; echelon row)
        local charNow = MCDMMonsterScaling.HighestCharacteristic(currentLevel, isLeaderSolo)
        local charTgt = MCDMMonsterScaling.HighestCharacteristic(targetLevel, isLeaderSolo)
        add("Highest characteristic",
            ScalingSignedString(charNow),
            ScalingSignedString(charTgt),
            adjStr(charTgt - charNow), signum(charTgt - charNow), true)

        -- Potency weak/avg/strong (reference formula; echelon row)
        local function potTriple(level)
            local s = MCDMMonsterScaling.PotencyStrong(level, isLeaderSolo)
            return math.max(0, s - 2), math.max(0, s - 1), s
        end
        local wNow, aNow, sNow = potTriple(currentLevel)
        local wTgt, aTgt, sTgt = potTriple(targetLevel)
        add("Potency (weak / avg / strong)",
            string.format("%d / %d / %d", wNow, aNow, sNow),
            string.format("%d / %d / %d", wTgt, aTgt, sTgt),
            adjStr(sTgt - sNow), signum(sTgt - sNow), true)

        return rows
    end

    local function Refresh()
        if valueLabel ~= nil and valueLabel.valid then
            valueLabel.text = string.format("%d", targetLevel)
        end
        if slider ~= nil and slider.valid then
            -- setValueNoEvent repositions the thumb (fires updateValue) without
            -- firing 'change'. SetValue(v, false) would skip updateValue too, so
            -- the thumb would not follow the stepper arrows.
            slider.data.setValueNoEvent(targetLevel)
        end
        if previewPanel ~= nil and previewPanel.valid then
            previewPanel.children = BuildPreviewRows()
        end

        local curEch = MCDMMonsterScaling.Echelon(currentLevel)
        local tgtEch = MCDMMonsterScaling.Echelon(targetLevel)
        local crossing = (tgtEch ~= curEch)
        if echelonBanner ~= nil and echelonBanner.valid then
            -- Report the ACTUAL characteristic and potency deltas, not the echelon
            -- difference: they diverge at the echelon-4 leader/solo boundary, where
            -- the characteristic is capped at +5 while potency reaches 6, so
            -- crossing 9<->10 moves potency but leaves the characteristic unchanged.
            local charD = MCDMMonsterScaling.HighestCharacteristic(targetLevel, isLeaderSolo)
                        - MCDMMonsterScaling.HighestCharacteristic(currentLevel, isLeaderSolo)
            local potD = MCDMMonsterScaling.PotencyStrong(targetLevel, isLeaderSolo)
                       - MCDMMonsterScaling.PotencyStrong(currentLevel, isLeaderSolo)
            local moved = (charD ~= 0 or potD ~= 0)
            echelonBanner:SetClass("collapsed", not (crossing and moved))
            if crossing and moved then
                local function phrase(noun, delta)
                    return string.format("%s %s by %d", noun,
                        cond(delta > 0, "increases", "decreases"), math.abs(delta))
                end
                local body
                if charD == potD then
                    body = string.format("Potency and highest characteristic %s by %d",
                        cond(potD > 0, "increase", "decrease"), math.abs(potD))
                elseif charD == 0 then
                    body = phrase("Potency", potD) .. "; highest characteristic is unchanged"
                elseif potD == 0 then
                    body = phrase("Highest characteristic", charD) .. "; potency is unchanged"
                else
                    body = phrase("Potency", potD) .. " and " .. string.lower(phrase("Highest characteristic", charD))
                end
                echelonBanner.text = string.format("Echelon %d. %s.", tgtEch, body)
            end
        end

        if noteLabel ~= nil and noteLabel.valid then
            noteLabel:SetClass("collapsed", not (targetLevel < baseLevel))
        end

        if footerLabel ~= nil and footerLabel.valid then
            if targetLevel == baseLevel then
                footerLabel.text = "At the base level. No adjustment is applied."
            else
                footerLabel.text = "Click Reset to restore the creature to its original level."
            end
        end
    end

    local function SetTarget(n)
        n = math.max(minLevel, math.min(maxLevel, round(tonumber(n) or targetLevel)))
        if n == targetLevel then
            return
        end
        targetLevel = n
        Refresh()
    end

    valueLabel = gui.Label{
        classes = { "number", "sizeL", "bold" },
        text = string.format("%d", currentLevel),
        width = 56,
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
    }

    slider = gui.Slider{
        width = "80%",
        height = 24,
        halign = "center",
        vmargin = 4,
        minValue = minLevel,
        maxValue = maxLevel,
        value = currentLevel,
        round = true,
        change = function(element)
            SetTarget(element:GetValue())
        end,
    }

    previewPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        tmargin = 12,
    }

    echelonBanner = gui.Label{
        classes = { "sizeXs", "bold", "collapsed" },
        width = "100%",
        height = "auto",
        halign = "left",
        textAlignment = "left",
        textWrap = true,
        tmargin = 12,
    }

    noteLabel = gui.Label{
        classes = { "sizeXs", "collapsed" },
        text = "Some monsters have been hand-tuned and scaling values are approximate for these creatures.",
        width = "100%",
        height = "auto",
        halign = "left",
        textAlignment = "left",
        textWrap = true,
        tmargin = 8,
    }

    footerLabel = gui.Label{
        classes = { "sizeXs" },
        width = "100%",
        height = "auto",
        halign = "left",
        textAlignment = "left",
        textWrap = true,
        tmargin = 12,
    }

    -- Squad scope toggle (minions only). Collapsed for non-squad creatures.
    squadCheck = gui.Check{
        text = string.format("Apply to all %d minions in this squad", squadSize),
        value = applyToSquad,
        halign = "left",
        tmargin = 12,
        change = function(element)
            applyToSquad = element.value
        end,
    }
    squadCheck:SetClass("collapsed", not isSquadMinion)

    dialog = gui.Panel{
        classes = { "dialog" },
        -- Custom rules: tint the Adjustment column (the base tableLabel rule sets
        -- @fg, which otherwise wins over a plain success/danger class), and a
        -- clean 1px themed divider (a bordered box left end-cap artifacts).
        styles = ThemeEngine.MergeStyles{
            { selectors = { "tableLabel", "adjustInc" }, color = "@success", priority = 100 },
            { selectors = { "tableLabel", "adjustDec" }, color = "@danger", priority = 100 },
            { selectors = { "adjustDivider" }, bgimage = true, bgcolor = "@border" },
        },
        width = 660,
        height = "auto",
        minHeight = 440,
        flow = "vertical",
        borderBox = true,
        pad = 20,

        gui.Label{
            classes = { "modalTitle" },
            text = "Adjust Level",
            width = "100%",
            height = "auto",
            tmargin = 4,
        },

        gui.Button{
            classes = { "closeButton" },
            halign = "right",
            valign = "top",
            floating = true,
            margin = 8,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                gui.CloseModal()
            end,
        },

        -- Subtitle: "<b>Name</b> - Role", centered. (Base Level lives on the
        -- stepper row, right-aligned to the slider's edge.)
        gui.Label{
            classes = { "sizeS" },
            text = string.format("<b>%s</b> - %s", token.name or "Monster", props:try_get("role", "")),
            width = "92%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            textWrap = true,
            tmargin = 4,
        },

        -- Stepper (minus / value / plus) centered, with Base Level right-aligned
        -- to the slider's right edge. The wrapper matches the slider's 80% width
        -- so "right" lands on the scale's edge.
        gui.Panel{
            width = "80%",
            height = "auto",
            halign = "center",
            valign = "center",
            flow = "none",
            vmargin = 8,

            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                valign = "center",

                gui.Button{
                    classes = { "pagingArrow" },
                    valign = "center",
                    click = function(element)
                        SetTarget(targetLevel - 1)
                    end,
                },
                valueLabel,
                gui.Button{
                    classes = { "pagingArrow", "right" },
                    valign = "center",
                    click = function(element)
                        SetTarget(targetLevel + 1)
                    end,
                },
            },

            gui.Label{
                classes = { "sizeS" },
                text = string.format("<b>Base Level:</b> %d", baseLevel),
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
            },
        },

        slider,
        previewPanel,
        echelonBanner,
        noteLabel,
        squadCheck,
        footerLabel,

        -- Cancel / Reset / Apply
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            valign = "bottom",
            tmargin = 16,

            gui.Button{
                text = "Cancel",
                width = 120,
                height = 40,
                hmargin = 6,
                click = function(element)
                    gui.CloseModal()
                end,
            },
            gui.Button{
                text = "Reset",
                width = 120,
                height = 40,
                hmargin = 6,
                click = function(element)
                    -- Reset returns the selection to the creature's original
                    -- (base) level; Apply then commits the restoration.
                    targetLevel = baseLevel
                    Refresh()
                end,
            },
            gui.Button{
                text = "Apply",
                width = 120,
                height = 40,
                hmargin = 6,
                click = function(element)
                    -- Recompute the squad fresh so a death mid-dialog can't
                    -- target a stale member; fall back to this token alone.
                    local targets = { token }
                    if isSquadMinion and applyToSquad then
                        targets = CollectSquadMembers()
                    end
                    for _, tok in ipairs(targets) do
                        tok:ModifyProperties{
                            description = "Adjust monster level",
                            combine = true,
                            execute = function()
                                tok.properties:SetLevelAdjustment(targetLevel)
                            end,
                        }
                    end
                    if CharacterSheet.instance ~= nil then
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end
                    gui.CloseModal()
                end,
            },
        },
    }

    Refresh()
    gui.ShowModal(dialog)
end

-- Villain-action slot vocabulary. The picker is launched for one slot at a time
-- and only offers candidates authored for that same slot (slot-locked).
local g_villainSlotMeta = {
    ["Villain Action 1"] = { label = "Opener",        roman = "I" },
    ["Villain Action 2"] = { label = "Crowd Control",  roman = "II" },
    ["Villain Action 3"] = { label = "Showstopper",    roman = "III" },
}

-- Maps an implementation-status value (gui.ImplementationStatus) to the status
-- modifier class for the canonical colored dot (DefaultStyles spellImplementationIcon).
local g_implDotClass = {
    [0] = "wontimplement",
    [1] = "unimplemented",
    [2] = "bronze",
    [3] = "silver",
    [4] = "gold",
}

-- Browse every villain action across the bestiary in a given slot, preview the
-- real ability card, and duplicate one onto this creature. CHUNK 2 (modal core):
-- slot-locked alphabetical list + real CreateAbilityTooltip preview + "Add to
-- this creature" (deep-copy with a fresh guid, categorization + slot preset).
-- Search, the implementation-status cross-check filter, status dots, and "Create
-- New Villain Action" arrive in the next pass. Reuses the cached bestiary
-- ability index (GetBestiaryVillainActions / GetBestiaryAbilityObject) so it
-- shares the bestiary's single GoblinScript scan rather than re-scanning.
local function ShowVillainActionPicker(token, slot)
    if token == nil or token.properties == nil then
        return
    end
    if not token.properties:IsMonster() then
        return
    end

    local meta = g_villainSlotMeta[slot] or { label = "Villain Action", roman = "" }

    -- Forward-declared so the list / preview / add handlers can reach them.
    local dialog
    local listPanel
    local previewPanel
    local verdictLabel
    local addButton
    local selectedEntry = nil

    -- Filter state. allEntries is the slot's full candidate set (stored once the
    -- bestiary index is ready); the visible list is derived from it by the search
    -- needle and the cross-check toggle.
    local allEntries = {}
    local searchNeedle = ""
    -- "Exclude Narrative and Unimplemented" cross-checks the status field (which
    -- the importer over-marks) against the structural signal: keep only entries
    -- that are Bronze+ AND carry real behaviors. Default off -- inform, do not
    -- enforce; the director opts in.
    local excludeUnimplemented = false

    -- The status field is unreliable on its own (the importer over-marks Silver),
    -- so the verdict cross-checks it against whether the ability carries real
    -- behaviors: "<Status> - mechanics verified" when it auto-resolves, or
    -- "<Status> - no mechanics (text only)" when it is director-adjudicated.
    local function UpdateVerdict()
        if verdictLabel == nil or not verdictLabel.valid then
            return
        end
        if selectedEntry == nil then
            verdictLabel:SetClass("collapsed", true)
            return
        end
        local status = selectedEntry.implementation or 1
        local statusName = gui.ImplementationStatusValues[status] or "Unknown"
        local verdict = cond(selectedEntry.hasBehaviors,
            "mechanics verified", "no mechanics (text only)")
        verdictLabel.text = string.format("%s - %s", statusName, verdict)
        verdictLabel.classes = { "sizeXs", "bold", "implStatus" .. tostring(status) }
        verdictLabel:SetClass("collapsed", false)
    end

    local function RefreshPreview()
        UpdateVerdict()
        if previewPanel == nil or not previewPanel.valid then
            return
        end
        local children
        if selectedEntry == nil then
            children = {
                gui.Label{
                    classes = { "sizeS" },
                    text = "Select a villain action to preview it.",
                    width = "100%", height = "auto",
                    halign = "center", valign = "center",
                    textAlignment = "center", textWrap = true,
                },
            }
        else
            -- The real ability card (1:1 with how it renders in play), not a
            -- re-render. Fetched on demand for the one selected ability.
            local obj = GetBestiaryAbilityObject(selectedEntry.monsterId, selectedEntry.name)
            local card = nil
            if obj ~= nil then
                card = CreateAbilityTooltip(obj, { token = token, width = 380, pad = 8 })
            end
            if card ~= nil then
                children = { card }
            else
                children = {
                    gui.Label{
                        classes = { "sizeS" },
                        text = "This ability could not be loaded for preview.",
                        width = "100%", height = "auto",
                        halign = "center", valign = "center",
                        textAlignment = "center", textWrap = true,
                    },
                }
            end
        end
        previewPanel.children = children
    end

    local function BuildRows(entries)
        table.sort(entries, function(a, b)
            if a.name ~= b.name then
                return a.name < b.name
            end
            return (a.monsterName or "") < (b.monsterName or "")
        end)
        local rows = {}
        for i, entry in ipairs(entries) do
            local capturedEntry = entry
            local subText = entry.monsterName or ""
            if entry.level ~= nil then
                subText = string.format("%s - Level %d", subText, entry.level)
            end
            local status = entry.implementation or 1
            local dotClass = g_implDotClass[status] or "unimplemented"
            local row
            row = gui.Panel{
                classes = { "row", cond(i % 2 == 0, "evenRow", "oddRow"), "hoverable" },
                width = "100%",
                height = "auto",
                flow = "horizontal",
                borderBox = true,
                hpad = 10,
                vpad = 6,
                press = function(element)
                    selectedEntry = capturedEntry
                    if listPanel ~= nil and listPanel.valid then
                        for _, child in ipairs(listPanel.children) do
                            child:SetClass("selected", child == element)
                        end
                    end
                    if addButton ~= nil and addButton.valid then
                        addButton.interactable = true
                    end
                    RefreshPreview()
                end,
                -- Per-row implementation-status dot (the canonical colored dot
                -- used on compendium entries; scheme-consistent implStatus tokens).
                gui.Panel{
                    classes = { "spellImplementationIcon", dotClass },
                    halign = "left",
                    valign = "center",
                },
                gui.Panel{
                    width = "100%-24", height = "auto", flow = "vertical",
                    halign = "left", valign = "center",
                    gui.Label{
                        classes = { "tableLabel", "bold" },
                        text = capturedEntry.name,
                        width = "100%", height = "auto",
                        halign = "left", textWrap = true,
                    },
                    gui.Label{
                        classes = { "sizeXs" },
                        text = subText,
                        width = "100%", height = "auto",
                        halign = "left", textWrap = true,
                    },
                },
            }
            rows[#rows + 1] = row
        end
        if #rows == 0 then
            local emptyText = cond(#allEntries == 0,
                "No villain actions found for this slot.",
                "No villain actions match your search and filter.")
            rows = {
                gui.Label{
                    classes = { "sizeS" },
                    text = emptyText,
                    width = "100%", height = "auto",
                    halign = "center", textAlignment = "center", textWrap = true,
                },
            }
        end
        return rows
    end

    -- Derive the visible list from allEntries by the search needle (matched over a
    -- combined name + monster + level haystack, reusing Search.MatchesText) and
    -- the cross-check toggle. Then rebuild the rows.
    local function ApplyFilter()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local filtered = {}
        for _, e in ipairs(allEntries) do
            local keep = true
            if excludeUnimplemented then
                local status = e.implementation or 1
                keep = (status >= gui.ImplementationStatus.Bronze) and (e.hasBehaviors == true)
            end
            if keep and searchNeedle ~= "" then
                local hay = string.format("%s %s level %s",
                    e.name or "", e.monsterName or "", tostring(e.level or ""))
                keep = Search.MatchesText(hay, searchNeedle)
            end
            if keep then
                filtered[#filtered + 1] = e
            end
        end
        listPanel.children = BuildRows(filtered)
    end

    -- The bestiary index builds lazily in a coroutine. If it is not ready yet,
    -- show a loading line and re-poll until it is.
    local function Populate()
        if listPanel == nil or not listPanel.valid then
            return
        end
        local entries, ready = GetBestiaryVillainActions(slot)
        if not ready then
            listPanel.children = {
                gui.Label{
                    classes = { "sizeS" },
                    text = "Loading bestiary...",
                    width = "100%", height = "auto",
                    halign = "center", textAlignment = "center",
                },
            }
            dmhub.Schedule(0.3, function()
                if mod.unloaded then
                    return
                end
                Populate()
            end)
            return
        end
        allEntries = entries
        ApplyFilter()
    end

    listPanel = gui.Panel{
        vscroll = true,
        width = "100%",
        -- Fills the left pane below the search input and the filter checkbox.
        height = "100%-72",
        flow = "vertical",
    }

    previewPanel = gui.Panel{
        vscroll = true,
        width = "100%",
        height = "100%-28",
        flow = "vertical",
        halign = "center",
    }

    -- Cross-check verdict, shown under the preview card.
    verdictLabel = gui.Label{
        classes = { "sizeXs", "bold", "collapsed" },
        width = "100%", height = "auto",
        halign = "left", valign = "bottom",
        textAlignment = "left", textWrap = true,
        tmargin = 6,
    }

    -- Smart search: ability name, monster name, or level (reuses the global
    -- search matcher). Results stay grouped alphabetically.
    local searchInput = gui.SearchInput{
        width = "100%",
        height = 26,
        fontSize = 14,
        halign = "left",
        placeholderText = "Search villain actions, monsters, levels...",
        editlag = 0.25,
        edit = function(element)
            searchNeedle = Search.Normalize(element.text) or ""
            ApplyFilter()
        end,
    }

    -- The cross-check filter. gui.Check has intrinsic sizing -- never width 100%.
    local excludeCheck = gui.Check{
        text = "Exclude Narrative and Unimplemented",
        value = excludeUnimplemented,
        halign = "left",
        vmargin = 6,
        change = function(element)
            excludeUnimplemented = element.value
            ApplyFilter()
        end,
    }

    addButton = gui.Button{
        text = "Add to this creature",
        width = 200,
        height = 40,
        hmargin = 6,
        interactable = false,
        click = function(element)
            if selectedEntry == nil then
                return
            end
            local source = GetBestiaryAbilityObject(selectedEntry.monsterId, selectedEntry.name)
            if source == nil then
                return
            end
            -- Duplicate the source onto this creature (the source is untouched).
            -- Fresh guid so it is a distinct ability; force the categorization and
            -- the launched slot so it lands in the right group even if the source
            -- was authored for a different slot. This modal lives outside the sheet
            -- panel tree, so the mutation is wrapped in ModifyProperties (mirroring
            -- the Adjust Level Apply) rather than relying on the sheet's own upload.
            local copy = DeepCopy(source)
            copy.guid = dmhub.GenerateGuid()
            copy.categorization = "Villain Action"
            copy.villainAction = slot
            token:ModifyProperties{
                description = "Add villain action",
                execute = function()
                    token.properties:AddInnateActivatedAbility(copy)
                end,
            }
            if CharacterSheet.instance ~= nil then
                CharacterSheet.instance:FireEvent("refreshAll")
            end
            gui.CloseModal()
        end,
    }

    dialog = gui.Panel{
        classes = { "dialog" },
        styles = ThemeEngine.GetStyles(),
        width = 820,
        height = 600,
        flow = "vertical",
        borderBox = true,
        pad = 20,

        gui.Label{
            classes = { "modalTitle" },
            text = "Add Villain Action",
            width = "100%", height = "auto",
            tmargin = 4,
        },

        gui.Button{
            classes = { "closeButton" },
            halign = "right",
            valign = "top",
            floating = true,
            margin = 8,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function(element)
                gui.CloseModal()
            end,
        },

        -- Context line: "Opener - Villain Action I - <creature>".
        gui.Label{
            classes = { "sizeS" },
            text = string.format("<b>%s</b> - Villain Action %s - %s",
                meta.label, meta.roman, token.name or "Monster"),
            width = "100%", height = "auto",
            halign = "left", textAlignment = "left", textWrap = true,
            tmargin = 4, bmargin = 10,
        },

        -- Two-pane body. Left: search + cross-check filter + slot-locked list.
        -- Right: the real ability-card preview + the cross-check verdict.
        gui.Panel{
            width = "100%",
            height = "100%-150",
            flow = "horizontal",

            gui.Panel{
                width = "44%", height = "100%", flow = "vertical",
                searchInput,
                excludeCheck,
                listPanel,
            },
            gui.Panel{ width = "2%", height = "100%" },
            gui.Panel{
                width = "54%", height = "100%", flow = "vertical",
                previewPanel,
                verdictLabel,
            },
        },

        -- Cancel / Create New Villain Action / Add to this creature.
        gui.Panel{
            width = "100%", height = "auto", flow = "horizontal",
            halign = "center", valign = "bottom", tmargin = 16,

            gui.Button{
                text = "Cancel",
                width = 120, height = 40, hmargin = 6,
                click = function(element)
                    gui.CloseModal()
                end,
            },
            -- Build a fresh villain action from scratch in the ability editor,
            -- preset to this slot. Mirrors the sheet's Create Ability path.
            gui.Button{
                text = "Create New Villain Action",
                width = 220, height = 40, hmargin = 6,
                click = function(element)
                    gui.CloseModal()
                    if CharacterSheet.instance == nil then
                        return
                    end
                    local newAbility = ActivatedAbility.Create {
                        name = "New Villain Action",
                        categorization = "Villain Action",
                        villainAction = slot,
                    }
                    CharacterSheet.instance:AddChild(newAbility:ShowEditActivatedAbilityDialog {
                        add = function(el)
                            CharacterSheet.instance.data.info.token.properties:AddInnateActivatedAbility(newAbility)
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                        cancel = function(el)
                        end,
                    })
                end,
            },
            addButton,
        },
    }

    Populate()
    RefreshPreview()
    gui.ShowModal(dialog)
end

local function DSCharSheet()
    --find id for recovery from resourcestable
    local recoveryid = "5bd90f9b-46be-4cf2-8ca6-a96430d62949"

    -- Factored so the OnThemeChanged subscription can re-resolve with the
    -- same composition the panel was built from.
    local function buildSheetStyles()
        return ThemeEngine.MergeStyles{
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
        }
    end

    local DSCharSheetPanel = gui.Panel {
        classes = {"surfaceRadial"},

        styles = buildSheetStyles(),

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

                    classes = {"bordered"},
                    bgimage = true,
                    width = "100%",
                    height = "80%",

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
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Panel {

                                        classes = {"bordered"},
                                        width = 70,
                                        height = 70,
                                        bgimage = true,
                                        color = "clear",
                                        border = 3,
                                        halign = "center",
                                        valign = "bottom",

                                        gui.Label {

                                            characterLimit = 2,
                                            text = "+0",
                                            textAlignment = "center",
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

                                classes = {"bordered"},
                                bgimage = true,
                                bgcolor = "clear",
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    if token.properties:IsMonster() then
                                        gui.PopupMonsterSize {
                                            parentElement = element,
                                            token = token,
                                            characterSheet = true,
                                        }
                                    else
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
                                    end
                                    CharacterSheet.instance:FireEvent('refreshAll')
                                end,

                                gui.Label {

                                    text = "4",
                                    fontSize = 20,
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

                            press = function(element)
                                local token = CharacterSheet.instance.data.info.token
                                gui.PopupMovementSpeed {
                                    parentElement = element,
                                    token = token,
                                    characterSheet = true,
                                }
                            end,

                            gui.Panel {

                                width = "100%",
                                height = 40,

                                classes = {"bordered"},
                                bgimage = true,
                                bgcolor = "clear",
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                gui.Label {
                                    text = "4",
                                    fontSize = 20,
                                    height = "auto",
                                    width = "auto",

                                    halign = "center",
                                    valign = "center",
                                    characterLimit = 2,

                                    refreshToken = function(element, info)
                                        local creature = CharacterSheet.instance.data.info.token.properties
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

                                classes = {"bordered"},
                                bgimage = true,
                                bgcolor = "clear",
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

                                classes = {"bordered"},
                                bgimage = true,
                                bgcolor = "clear",
                                beveledcorners = true,
                                cornerRadius = 10,

                                halign = "center",

                                press = function(element)
                                    local token = CharacterSheet.instance.data.info.token
                                    local baseValueEdit
                                    if token.properties:IsMonster() then
                                        baseValueEdit = function(n)
                                            n = math.max(0, round(n))
                                            token.properties.stability = n
                                            CharacterSheet.instance:FireEventTree("refresh")
                                            CharacterSheet.instance:FireEvent("refreshAll")

                                            return string.format("%d", token.properties.stability)
                                        end
                                    end

                                    local baseStability = token.properties:BaseForcedMoveResistance()
                                    gui.PopupOverrideAttribute {
                                        parentElement = element,
                                        token = token,
                                        attributeName = "Stability",
                                        modifications = token.properties:DescribeModifications("forcedmoveresistance", baseStability),
                                        characterSheet = true,
                                        baseValue = baseStability,
                                        baseValueEdit = baseValueEdit,
                                    }
                                end,

                                gui.Label {

                                    text = "4",
                                    fontSize = 20,
                                    height = "auto",
                                    width = "auto",
                                    minWidth = 80,
                                    textAlignment = "center",

                                    halign = "center",
                                    valign = "center",
                                    characterLimit = 2,

                                    refreshToken = function(element, info)
                                        local creature = CharacterSheet.instance.data.info.token.properties
                                        element.text = creature:Stability()
                                    end,


                                },
                            },

                            gui.Label {

                                text = "Stability",
                                fontSize = 20,
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

                            classes = {"bordered"},
                            bgimage = true,
                            beveledcorners = true,
                            cornerRadius = 15,
                            width = "100%",
                            height = "100%",

                            flow = "vertical",

                            gui.Label {

                                text = "Potencies",
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "center",

                            },

                            gui.MCDMDivider { width = "80%", },

                            gui.Label {

                                bgimage = true,
                                bgcolor = "clear",
                                width = "auto",
                                height = "auto",
                                flow = "horizontal",
                                halign = "center",

                                bmargin = 15,


                                gui.Panel {

                                    classes = {"bordered"},
                                    bgimage = true,
                                    bgcolor = "clear",
                                    beveledcorners = true,
                                    cornerRadius = 15,
                                    width = "25%",
                                    height = "50%",
                                    halign = "center",
                                    valign = "center",
                                    rmargin = 10,

                                    gui.Label {

                                        text = "Strong",
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Label {

                                        text = "1",
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "bottom",

                                        refreshToken = function(element, info)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local strong = creature:CalculatePotencyValue("Strong")
                                            element.text = string.format("%d", strong)
                                        end

                                    },



                                },

                                gui.Panel {

                                    classes = {"bordered"},
                                    bgimage = true,
                                    bgcolor = "clear",
                                    beveledcorners = true,
                                    cornerRadius = 15,
                                    width = "25%",
                                    height = "50%",
                                    halign = "center",
                                    valign = "center",

                                    gui.Label {

                                        text = "Average",
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Label {

                                        text = "2",
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "bottom",

                                        refreshToken = function(element, info)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local average = creature:CalculatePotencyValue("Average")
                                            element.text = string.format("%d", average)
                                        end

                                    },



                                },

                                gui.Panel {

                                    classes = {"bordered"},
                                    bgimage = true,
                                    bgcolor = "clear",
                                    beveledcorners = true,
                                    cornerRadius = 15,
                                    width = "25%",
                                    height = "50%",
                                    halign = "center",
                                    valign = "center",
                                    lmargin = 10,

                                    gui.Label {

                                        text = "Weak",
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "top",

                                    },

                                    gui.Label {

                                        text = "2",
                                        fontSize = 20,
                                        width = "auto",
                                        height = "auto",
                                        halign = "center",
                                        valign = "bottom",

                                        refreshToken = function(element, info)
                                            local creature = CharacterSheet.instance.data.info.token.properties
                                            local weak = creature:CalculatePotencyValue("Weak")
                                            element.text = string.format("%d", weak)
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

                            classes = {"bordered"},
                            width = "100%",
                            height = "100%",
                            bgimage = true,
                            beveledcorners = true,
                            cornerRadius = 15,

                            valign = "center",
                            flow = "vertical",

                            gui.Label {

                                text = "Immunities & Weaknesses",
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                tmargin = 5,
                            },

                            gui.Button {
                                classes = {"settingsButton"},
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


                            gui.MCDMDivider { width = "80%", },


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

                            classes = {"bordered"},
                            width = "100%",
                            height = "100%",
                            bgimage = true,
                            beveledcorners = true,
                            cornerRadius = 15,

                            valign = "center",
                            flow = "vertical",

                            gui.Label {

                                text = "Skills",
                                fontSize = 20,
                                width = "auto",
                                height = "auto",
                                halign = "center",
                                valign = "top",
                                tmargin = 5,
                            },

                            gui.Button {
                                classes = {"settingsButton"},
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

                            gui.MCDMDivider { width = "80%", },


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
                    classes = {"bordered"},
                    width = "50%-18",
                    height = "100%-50",
                    halign = "right",
                    bgimage = true,
                    bgcolor = "clear",
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

                    classes = {"bordered"},
                    bgimage = true,
                    width = "95%",
                    height = "80%",

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
                                local props = info.token.properties
                                element:SetClass("collapsed", not (props:IsMonster() or props:IsCompanion()))
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
                                        local props = info.token.properties
                                        if not (props:IsMonster() or props:IsCompanion()) then
                                            return
                                        end

                                        element.editable = not props:IsCompanion()

                                        local attack = props:OpportunityAttack()
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
                                        local props = info.token.properties
                                        if not (props:IsMonster() or props:IsCompanion()) then
                                            return
                                        end

                                        local ev = props:EV()
                                        element.text = string.format("%d", round(ev))
                                    end,

                                    change = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        local newValue = round(tonumber(element.text) or token.properties:BaseEV())
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
                                local props = info.token.properties
                                element:SetClass("collapsed", props:IsMonster() or props:IsCompanion())
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

                                    styles = ThemeEngine.MergeTokens{
                                        {
                                            selectors = { "notch" },
                                            width = string.format("%f%%", 100 / 15),
                                            height = "100%",
                                            borderColor = "@border",
                                            bgcolor = "@bg",
                                            cornerRadius = 0,
                                            priority = 5,
                                        },
                                        {
                                            selectors = { "notch", "left" },
                                            beveledcorners = true,
                                            cornerRadius = { x1 = 8, y1 = 0, x2 = 0, y2 = 8 },
                                            priority = 10,
                                        },
                                        {
                                            selectors = { "notch", "right" },
                                            beveledcorners = true,
                                            cornerRadius = { x1 = 0, y1 = 8, x2 = 8, y2 = 0 },
                                            priority = 10,
                                        },
                                        {
                                            selectors = { "notch", "filled" },
                                            bgcolor = "@accent",
                                            priority = 10,
                                        },
                                        {
                                            selectors = { "notch", "hover" },
                                            bgcolor = "@fgMuted",
                                            priority = 10,
                                        },
                                        {
                                            selectors = { "notch", "hover", "filled" },
                                            bgcolor = "@accentHover",
                                            priority = 10,
                                        },
                                    },

                                    create = function(element)
                                        local function rebuild()
                                            return ThemeEngine.MergeTokens{
                                                { selectors = {"notch"}, width = string.format("%f%%", 100 / 15), height = "100%",
                                                  borderColor = "@border", bgcolor = "@bg", cornerRadius = 0, priority = 5 },
                                                { selectors = {"notch", "left"}, beveledcorners = true,
                                                  cornerRadius = { x1 = 8, y1 = 0, x2 = 0, y2 = 8 }, priority = 10 },
                                                { selectors = {"notch", "right"}, beveledcorners = true,
                                                  cornerRadius = { x1 = 0, y1 = 8, x2 = 8, y2 = 0 }, priority = 10 },
                                                { selectors = {"notch", "filled"}, bgcolor = "@accent", priority = 10 },
                                                { selectors = {"notch", "hover"}, bgcolor = "@fgMuted", priority = 10 },
                                                { selectors = {"notch", "hover", "filled"}, bgcolor = "@accentHover", priority = 10 },
                                            }
                                        end
                                        ThemeEngine.OnThemeChanged(mod, function()
                                            if element ~= nil and element.valid then
                                                element.styles = rebuild()
                                            end
                                        end)
                                    end,

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
                                                classes = { "notch", "bordered", cond(i == 1, "left"), cond(i == 15, "right") },
                                                -- cornerRadius = cond(i == 1, nil, cond(i == 15, nil, 0)),
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

                                classes = {"cs-divider-line"},
                                bgimage = true,
                                width = "6%",
                                height = "80%",
                                halign = "left",
                                valign = "center",
                                rmargin = 8,


                            },

                            gui.Panel {

                                classes = {"cs-divider-line"},
                                bgimage = true,
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

                            --Level number with the Adjust Level affordance to its
                            --left (monster level scaling): a small up/down-arrow
                            --icon button that opens the Adjust Level dialog.
                            --Monsters only.
                            gui.Panel {
                                bgimage = true,
                                bgcolor = "clear",
                                width = "100%",
                                height = "35%",
                                -- flow "none" so the arrow overlays to the right
                                -- without displacing the centered level number.
                                -- The number is declared FIRST and the arrow LAST
                                -- so the arrow renders on top and stays clickable
                                -- (later siblings win pointer events).
                                flow = "none",
                                valign = "center",
                                tmargin = 4,

                                gui.Label {

                                    text = "4",
                                    fontSize = 26,
                                    -- 3 chars so a scaled level fits the appended
                                    -- asterisk (e.g. "11*").
                                    characterLimit = 3,

                                    bgimage = true,
                                    bgcolor = "clear",
                                    width = "100%",
                                    height = "100%",

                                    halign = "center",
                                    valign = "center",
                                    textAlignment = "center",

                                    -- Level-scaling signpost. While a Level
                                    -- Adjustment is in effect the number is
                                    -- tinted success (scaled up) or danger
                                    -- (scaled down) and carries a trailing
                                    -- asterisk, so the adjusted state reads
                                    -- without relying on color alone.
                                    classes = { "levelValue" },
                                    styles = ThemeEngine.MergeTokens{
                                        { selectors = { "levelValue" }, color = "white" },
                                        { selectors = { "levelValue", "scaledUp" }, color = "@success", priority = 100 },
                                        { selectors = { "levelValue", "scaledDown" }, color = "@danger", priority = 100 },
                                    },

                                    refreshToken = function(element, info)
                                        local c = info.token.properties
                                        local level = round(tonumber(c:CharacterLevel()) or 0)
                                        local adjusted = c:IsMonster() and c:HasLevelAdjustment()

                                        if level == 0 then
                                            element.text = "-"
                                        elseif adjusted then
                                            element.text = string.format("%d*", level)
                                        else
                                            element.text = string.format("%d", level)
                                        end

                                        local up, down = false, false
                                        if adjusted then
                                            local base = c:GetScalingBaseLevel()
                                            up = level > base
                                            down = level < base
                                        end
                                        element:SetClass("scaledUp", up)
                                        element:SetClass("scaledDown", down)

                                        -- While adjusted the number is a
                                        -- read-only signpost that opens the
                                        -- modal on click; direct level edits go
                                        -- through the Adjust Level dialog so the
                                        -- stored deltas stay consistent.
                                        element.editable = c:IsMonster() and not adjusted
                                    end,

                                    -- Dynamic hover, shown only while adjusted:
                                    -- names the base level and the revert path.
                                    hover = function(element)
                                        local sheet = CharacterSheet.instance
                                        if sheet == nil then
                                            return
                                        end
                                        local token = sheet.data.info.token
                                        if token == nil or token.properties == nil then
                                            return
                                        end
                                        local c = token.properties
                                        if not (c:IsMonster() and c:HasLevelAdjustment()) then
                                            return
                                        end
                                        gui.Tooltip(string.format(
                                            "Adjusted from Level %d. Click to review.",
                                            c:GetScalingBaseLevel()))(element)
                                    end,

                                    -- When adjusted the number is non-editable,
                                    -- so a click opens the Adjust Level dialog
                                    -- ("Click to review"). When not adjusted the
                                    -- label handles its own click for inline
                                    -- editing and this is a no-op.
                                    click = function(element)
                                        local sheet = CharacterSheet.instance
                                        if sheet == nil then
                                            return
                                        end
                                        local token = sheet.data.info.token
                                        if token == nil or token.properties == nil then
                                            return
                                        end
                                        if token.properties:IsMonster() and token.properties:HasLevelAdjustment() then
                                            ShowAdjustLevelDialog(token)
                                        end
                                    end,

                                    change = function(element)
                                        -- Guard against firing during teardown / when the value
                                        -- did not actually change: a spurious refreshAll mid-destroy
                                        -- recomputes stats while the modifier pipeline is half torn
                                        -- down (e.g. Stability transiently nil).
                                        if CharacterSheet.instance == nil then
                                            return
                                        end
                                        local token = CharacterSheet.instance.data.info.token
                                        if token == nil or token.properties == nil then
                                            return
                                        end
                                        local n = math.max(0,
                                            round(tonumber(element.text) or token.properties:CharacterLevel()))
                                        if n == round(tonumber(token.properties.cr) or 0) then
                                            return
                                        end
                                        token.properties.cr = n
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,
                                },

                                gui.Panel {
                                    classes = { "bordered", "hoverable" },
                                    bgimage = "panels/square.png",
                                    bgcolor = "clear",
                                    width = 24,
                                    height = 26,
                                    halign = "right",
                                    valign = "center",
                                    rmargin = 8,
                                    flow = "vertical",

                                    hover = gui.Tooltip("Adjust Level"),

                                    refreshToken = function(element, info)
                                        element:SetClass("collapsed", not info.token.properties:IsMonster())
                                    end,

                                    click = function(element)
                                        ShowAdjustLevelDialog(CharacterSheet.instance.data.info.token)
                                    end,

                                    gui.Panel {
                                        width = 13,
                                        height = "50%",
                                        halign = "center",
                                        valign = "top",
                                        bgimage = "icons/icon_arrow/icon_arrow_29.png",
                                        bgcolor = "white",
                                    },
                                    gui.Panel {
                                        width = 13,
                                        height = "50%",
                                        halign = "center",
                                        valign = "bottom",
                                        bgimage = "icons/icon_arrow/icon_arrow_30.png",
                                        bgcolor = "white",
                                    },
                                },
                            },
                        },
                    },

                    --big divider
                    gui.Panel {

                        classes = {"cs-divider-line"},
                        bgimage = true,
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

                            classes = {"bordered"},
                            bgimage = true,
                            width = "30%",
                            height = "80%",

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

                            classes = {"bordered"},
                            bgimage = true,
                            width = "30%",
                            height = "80%",

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

                            classes = {"bordered"},
                            bgimage = true,
                            width = "30%",
                            height = "80%",

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

                    classes = {"bordered"},
                    bgimage = true,
                    width = "95%",
                    height = "80%",

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

                            classes = {"bordered"},
                            bgimage = true,
                            bgcolor = "clear",
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

                                classes = {"cs-divider-line"},
                                bgimage = true,
                                width = 2,
                                height = "80%",
                                valign = "center",
                            },

                            gui.Label {

                                text = "Healthy",
                                fontSize = 13,
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

                            classes = {"cs-divider-line"},
                            bgimage = mod.images.shield2,

                            width = 120,
                            height = 120,
                            halign = "horizontal",
                            valign = "center",

                            lmargin = -2,

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
                                        element.editable = info.token.properties:IsMonster() or info.token.properties:IsCompanion()

                                        local maxhp = info.token.properties:MaxHitpoints()
                                        element.text = string.format("/%d", math.tointeger(maxhp))
                                    end,

                                    press = function(element)
                                        local token = CharacterSheet.instance.data.info.token
                                        if token.properties:IsMonster() or token.properties:IsCompanion() then
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

                        classes = {"cs-divider-line"},
                        bgimage = true,
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

                            classes = {"bordered"},
                            bgimage = true,
                            bgcolor = "clear",
                            border = 3,

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

                        classes = {"cs-divider-line"},
                        bgimage = true,
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

                            classes = {"bordered"},
                            bgimage = true,
                            bgcolor = "clear",
                            border = 3,

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

                        classes = {"cs-divider-line"},
                        bgimage = true,
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

                            classes = {"bordered"},
                            bgimage = true,
                            bgcolor = "clear",
                            border = 3,

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

    ThemeEngine.OnThemeChanged(mod, function()
        if DSCharSheetPanel ~= nil and DSCharSheetPanel.valid then
            DSCharSheetPanel.styles = buildSheetStyles()
        end
    end)

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
                gui.Button {
                    classes = {"deleteButton"},
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
                characterLimit = 10000,
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

    local addNotesButton = gui.Button {
        classes = {"addButton"},
        hmargin = 15,
        height = 24,
        width = 24,
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
                        classes = {"sizeM"},
                        width = "80%",
                        height = 20,
                        flow = "horizontal",
                        text = lang.name,
                        textAlignment = "left",
                        halign = "center",

                        gui.Button {
                            classes = {"deleteButton"},
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
        height = 30,
        width = "auto",
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

    resultPanel = gui.Panel {
        classes = {"framedPanel"},
        halign = "right",
        valign = "center",
        interactable = true,
        flow = "vertical",
        hpad = 24,
        vpad = 14,
        width = 340,
        height = "auto",
        styles = ThemeEngine.GetStyles(),
        children = children,
    }

    parentElement.popup = resultPanel
end


function CharSheet.LanguagesPanel()
    local resultPanel
    resultPanel = gui.Panel {
        width = "100%",
        height = "13%",
        bmargin = 16,

        gui.Panel {

            classes = {"bordered"},
            width = "100%",
            height = "100%",
            bgimage = true,
            beveledcorners = true,
            cornerRadius = 15,

            valign = "center",
            flow = "vertical",

            gui.Button {
                classes = {"settingsButton"},
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
                fontSize = 20,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "top",
                tmargin = 5,
            },


            gui.MCDMDivider { width = "80%",},

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

        styles = ThemeEngine.MergeTokens{
            {
                selectors = { "valueLabel" },
                bold = true,
                fontSize = 18,
                hpad = 6,
                textWrap = false,
                minFontSize = 12,
                color = "@fgStrong",
                textAlignment = "center",
                bgimage = "panels/square.png",
                bgcolor = "clear",
                beveledcorners = true,
                borderColor = "@border",
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

            classes = {"bordered"},
            width = "100%",
            height = "98%",
            bgimage = true,
            beveledcorners = true,
            cornerRadius = 15,

            flow = "vertical",


            gui.Panel {

                width = "100%",
                height = 110,

                flow = "vertical",

                gui.Label {

                    text = "Kit",
                    fontSize = 20,
                    halign = "center",
                    valign = "top",
                    height = "auto",
                    width = "auto",

                },

                gui.MCDMDivider { width = "80%", },

                gui.Panel {

                    classes = {"bordered"},
                    width = "70%",
                    height = 40,
                    bgimage = true,
                    bgcolor = "clear",
                    border = 1,
                    beveledcorners = true,
                    cornerRadius = 10,
                    halign = "center",

                    tmargin = 5,

                    gui.Label {

                        text = "Name",
                        width = "auto",
                        height = "auto",
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
                            print("KIT::", json(kit))
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

--[[
    Redesigned Features tab content (search redesign ch5).

    Replaces the flat GetClassFeaturesAndChoicesWithDetails list with a
    grouped, filterable index built on FeatureCategoriser (FeatureCache.lua):
    groups = categoriser buckets (the Class group sub-grouped by level), a
    filter box narrowing rows via the shared Search matcher, unspent-choice
    badges on groups and rows, inline choice dropdowns preserved, and
    ability-granting features revealing the standard ability card on demand
    ("View ability" toggle).

    The global-search features-on-creatures provider lands here: it fires
    "filterFeatures" with the matched feature's name after selecting the tab,
    so the panel arrives pre-filtered to the feature that was clicked.

    Build discipline:
    - Group bodies are built ONLY while expanded (panels under a vscroll
      container are expensive even when collapsed), and rebuilt fresh on
      every change (reattaching previously-built panels orphans them).
    - Expansion and filter state live in locals here so they survive the
      fresh rebuilds triggered by refreshToken / choice changes.
    - The direct characterFeatures list (sheet-added custom features) shows
      under a "Custom Features" group, ALWAYS LAST in the group order; each
      row's expansion carries its Edit/Copy/Delete buttons (managed where
      the user sees them). The gear (settings) menu next to the filter box
      only ADDS things: Add Custom Feature, Paste Feature, creature
      templates. The old bottom strip is hidden for characters (it stays
      inline for monsters and other creature kinds; its delete-only feats
      list was a 5e holdover and is not carried over).
    - The categoriser (FeatureCache.lua) enforces single-home display:
      completed structural slots (subclass/deity/domain) are dropped from
      the index (their outcomes are ordinary rows); made feature choices
      that grant a skill/language re-home to that bucket; and a made
      choice's chosen option features fold INTO the slot entry (entry
      .chosen) instead of appearing as duplicate rows - the slot row's
      expansion renders the chosen feature's description and ability card.
]]

--Group header copy. Buckets without an entry fall back to the categoriser's
--display name.
local FEATURE_GROUP_LABELS = {
    perk = "Perks",
    title = "Titles",
    complication = "Complications",
    skill = "Skills",
    language = "Languages",
    custom = "Custom Features",
    treasure = "Treasures",
    condition = "Conditions",
    effect = "Ongoing Effects",
}

--Buckets whose header appends the origin name(s): "Ancestry - Human",
--"Career - Agent", "Class - Censor - Paragon" (class + subclass, in
--first-seen pipeline order).
local FEATURE_GROUP_ORIGIN_PREFIX = {
    class = true,
    ancestry = true,
    career = true,
    kit = true,
}

--"Level 5, upgraded at levels 7, 9" (capitalised per James's copy review).
local function FeatureLevelString(levels)
    if levels == nil or levels[1] == nil then
        return ""
    end
    local s = string.format("Level %d", math.max(1, levels[1]))
    if #levels > 1 then
        s = string.format("%s, upgraded at level%s %d", s, cond(#levels > 2, "s", ""), levels[2])
        for i = 3, #levels do
            s = string.format("%s, %d", s, levels[i])
        end
    end
    return s
end

--Expando arrow with the expanded state baked in at construction: rows and
--groups rebuild fresh on every change, and calling SetClass("expanded")
--after creation replays the 0.2s rotate transition on every already-open
--arrow. GOTCHA: the classes key must be OMITTED entirely when collapsed -
--gui.CombineFields REPLACES (not merges) the constructor's default
--{"triangle","expandoArrow"} classes when handed an empty list, leaving an
--unstyled full-size triangle.
local function FeatureExpandoArrow(expanded, options)
    if expanded then
        options.classes = {"expanded"}
    end
    return gui.ExpandoArrow(options)
end

--Abilities granted by an index entry: the feature's own modifiers plus the
--modifiers of any chosen option features (a made ability picker carries the
--ability on its chosen feature, folded into the slot entry by the
--categoriser). Detection is the builder's pattern: behavior
--activated/triggerdisplay/routine carries the ability.
local function FeatureGrantedAbilities(entry)
    local abilities = {}
    local function gather(feature)
        pcall(function()
            for _,modifier in ipairs(feature:try_get("modifiers", {})) do
                local behavior = modifier.behavior
                if behavior == "activated" or behavior == "triggerdisplay" or behavior == "routine" then
                    local ability = rawget(modifier, cond(behavior == "activated", "activatedAbility", "ability"))
                    if ability ~= nil then
                        abilities[#abilities+1] = ability
                    end
                end
            end
        end)
    end
    gather(entry.feature)
    for _,chosenFeature in ipairs(entry.chosen or {}) do
        gather(chosenFeature)
    end
    return abilities
end

--How many of a choice slot's selections are still unmade. For point-buy
--slots (costsPoints) NumChoices is the POINTS BUDGET, not a pick count -
--two picks costing 3 points complete a 3-point slot - so completeness is
--judged by points spent. Either way, a slot the engine can offer no further
--option for (Choices() returns nil) counts as complete: no dropdown would
--show, so badging it would be a dead end.
local function FeatureUnspentChoices(feature, creature)
    local unspent = 0
    pcall(function()
        local num = feature:NumChoices(creature)
        if num == nil or num <= 0 then
            return
        end
        local made = creature:GetLevelChoices()[feature.guid] or {}
        if feature:try_get("costsPoints") then
            local options = feature:GetOptions(creature:GetLevelChoices()) or {}
            local spent = 0
            for _,choiceid in ipairs(made) do
                for _,opt in ipairs(options) do
                    if opt.guid == choiceid then
                        spent = spent + (rawget(opt, "pointsCost") or 1)
                        break
                    end
                end
            end
            unspent = math.max(0, num - spent)
        else
            unspent = math.max(0, num - #made)
        end
        if unspent > 0 then
            local nextOptions = feature:Choices(#made + 1, made, creature)
            if nextOptions == nil or #nextOptions == 0 then
                unspent = 0
            end
        end
    end)
    return unspent
end

--Best-effort description for any index entry. Each probe is pcall-isolated:
--reading a method that does not exist on a game type ERRORS rather than
--returning nil, so one probe must not kill the next (gear items have no
--GetDescription but do carry a description field).
local function FeatureEntryDescription(entry)
    local desc = nil
    pcall(function()
        desc = entry.feature:GetDescription()
    end)
    if desc == nil or desc == "" then
        pcall(function()
            desc = entry.feature:try_get("description")
        end)
    end
    if desc == "" then
        desc = nil
    end
    return desc
end

--Display names of the options a fully-made choice slot resolved to, so the
--row can read "Forgettable Face" rather than "Agent Perk".
local function FeatureChosenTexts(feature, creature)
    local texts = {}
    pcall(function()
        local num = feature:NumChoices(creature)
        if num == nil or num <= 0 then
            return
        end
        local made = creature:GetLevelChoices()[feature.guid] or {}
        for i = 1, num do
            local chosenId = made[i]
            if chosenId ~= nil then
                for _,opt in ipairs(feature:Choices(i, made, creature) or {}) do
                    if opt.id == chosenId then
                        texts[#texts+1] = opt.text
                    end
                end
            end
        end
    end)
    return texts
end

local function FeaturesIndexPanel()
    local resultPanel

    --State preserved across fresh rebuilds.
    local m_filter = ""
    local m_expandedGroups = {}
    local m_expandedLevels = {}
    local m_expandedRows = {}
    local m_info = nil

    local m_countLabel
    local m_filterInput
    local m_headerPanel
    local m_groupsContainer
    local Rebuild

    local styles = ThemeEngine.MergeTokens{
        {
            selectors = {"featureGroupHeader"},
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = {"featureGroupHeader", "hover"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"featureIndexRow"},
            bgimage = true,
            bgcolor = "clear",
        },
        {
            selectors = {"featureIndexRow", "hover"},
            bgcolor = "@bgAlt",
        },
        {
            selectors = {"featureChoiceBadge"},
            bgimage = true,
            bgcolor = "@accent",
            color = "@fgInverse",
            cornerRadius = 8,
        },
        {
            selectors = {"featureMutedText"},
            color = "@fgMuted",
        },
        {
            selectors = {"featureViewAbility"},
            color = "@accent",
        },
        {
            selectors = {"featureViewAbility", "hover"},
            color = "@accentHover",
        },
        {
            selectors = {"featureClearFilter"},
            bgcolor = "@fgMuted",
        },
    }

    local function entrySearchText(entry)
        if entry._searchText == nil then
            local parts = {entry.name or "", FeatureEntryDescription(entry) or ""}
            --Chosen option features are folded into the slot entry, so the
            --filter must reach their names and descriptions too.
            for _,chosenFeature in ipairs(entry.chosen or {}) do
                pcall(function()
                    parts[#parts+1] = chosenFeature.name or ""
                    parts[#parts+1] = chosenFeature:GetDescription() or ""
                end)
            end
            entry._searchText = table.concat(parts, " ")
        end
        return entry._searchText
    end

    --Build a feature row's body: description, inline choice dropdowns, and
    --the View-ability toggle. Called lazily on first expand.
    local function BuildRowBody(body, entry, creature)
        body.data.built = true
        local children = {}

        --A made choice slot's expansion shows the CHOSEN feature's content
        --(the categoriser suppresses the chosen option's separate row);
        --entries without chosen options show their own description.
        local descs = {}
        for _,chosenFeature in ipairs(entry.chosen or {}) do
            pcall(function()
                local d = chosenFeature:GetDescription()
                if d ~= nil and d ~= "" then
                    descs[#descs+1] = d
                end
            end)
        end
        if #descs == 0 then
            local desc = FeatureEntryDescription(entry)
            if desc ~= nil then
                descs[#descs+1] = desc
            end
        end
        for _,desc in ipairs(descs) do
            children[#children+1] = gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 12,
                textWrap = true,
                text = desc,
            }
        end

        --Custom features are managed where the user sees them: the row
        --carries Edit / Copy / Delete (the gear menu only ADDS things).
        if entry.bucket == "custom" then
            children[#children+1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "left",
                vmargin = 2,
                gui.Button{
                    classes = {"sizeS"},
                    text = "Edit",
                    click = function(element)
                        local editor = entry.feature:PopupEditor()
                        editor.data.notifyElement = resultPanel
                        CharacterSheet.instance:AddChild(editor)
                    end,
                },
                gui.Button{
                    classes = {"sizeS"},
                    text = "Copy",
                    hmargin = 6,
                    click = function(element)
                        dmhub.CopyToInternalClipboard(entry.feature)
                        gui.Tooltip("Copied to clipboard!")(element)
                    end,
                },
                gui.Button{
                    classes = {"sizeS"},
                    text = "Delete",
                    click = function(element)
                        local c = CharacterSheet.instance.data.info.token.properties
                        local items = c:try_get("characterFeatures", {})
                        for i,f in ipairs(items) do
                            if f == entry.feature or (entry.guid ~= nil and f.guid == entry.guid) then
                                table.remove(items, i)
                                break
                            end
                        end
                        c.characterFeatures = items
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end,
                },
            }
        end

        if entry.kind == "build" then
            local feature = entry.feature
            local numChoices = 0
            pcall(function()
                numChoices = feature:NumChoices(creature) or 0
            end)
            for i = 1, numChoices do
                local options = nil
                local idChosen = "none"
                pcall(function()
                    local made = creature:GetLevelChoices()[feature.guid] or {}
                    options = feature:Choices(i, made, creature)
                    idChosen = made[i] or "none"
                end)
                if options ~= nil and #options > 0 then
                    local choiceIndex = i
                    children[#children+1] = gui.Dropdown{
                        height = 26,
                        width = 240,
                        halign = "left",
                        vmargin = 2,
                        textDefault = "Choose...",
                        sort = true,
                        options = options,
                        idChosen = idChosen,
                        change = function(element)
                            local c = CharacterSheet.instance.data.info.token.properties
                            local choice = element.idChosen
                            if choice == "none" then
                                choice = nil
                            end
                            local levelChoices = c:GetLevelChoices()
                            if levelChoices[feature.guid] == nil then
                                levelChoices[feature.guid] = {}
                            end
                            levelChoices[feature.guid][choiceIndex] = choice
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                    }
                end
            end

            local abilities = FeatureGrantedAbilities(entry)
            if #abilities > 0 then
                local cardContainer = gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    classes = {"collapsed"},
                    data = {},
                }
                children[#children+1] = gui.Label{
                    classes = {"featureViewAbility"},
                    width = "auto",
                    height = "auto",
                    fontSize = 12,
                    vmargin = 2,
                    bgimage = true,
                    bgcolor = "clear",
                    text = "View ability",
                    press = function(element)
                        local showing = cardContainer:HasClass("collapsed")
                        if showing and not cardContainer.data.built then
                            cardContainer.data.built = true
                            local cards = {}
                            for _,ability in ipairs(abilities) do
                                local ok, card = pcall(function()
                                    return ability:Render({
                                        width = "96%",
                                        halign = "left",
                                        bgimage = true,
                                    }, {})
                                end)
                                if ok and card ~= nil then
                                    cards[#cards+1] = card
                                end
                            end
                            cardContainer.children = cards
                        end
                        cardContainer:SetClass("collapsed", not showing)
                        element.text = cond(showing, "Hide ability", "View ability")
                    end,
                }
                children[#children+1] = cardContainer
            end
        end

        body.children = children
    end

    local function BuildRow(entry, creature)
        local rowKey = tostring(entry.guid or entry.name or "?")

        --A non-build row with no description has nothing to expand into;
        --build-pipeline rows may still carry dropdowns or an ability card,
        --and custom rows always carry their Edit/Copy/Delete buttons.
        local expandable = entry.kind == "build" or entry.bucket == "custom"
            or FeatureEntryDescription(entry) ~= nil
        local expanded = expandable and m_expandedRows[rowKey] == true

        local titleText = entry.name or "Feature"
        local subParts = {}
        if entry.kind == "build" and (entry._unspent or 0) == 0 then
            local texts = FeatureChosenTexts(entry.feature, creature)
            if #texts > 0 then
                titleText = table.concat(texts, ", ")
                subParts[#subParts+1] = entry.name
            end
        end
        local levelStr = FeatureLevelString(entry.levels)
        if levelStr ~= "" then
            subParts[#subParts+1] = levelStr
        end

        local tri = nil
        if expandable then
            tri = FeatureExpandoArrow(expanded, {
                valign = "center",
            })
        end

        local body = gui.Panel{
            width = "100%-16",
            halign = "left",
            hmargin = 16,
            height = "auto",
            flow = "vertical",
            classes = {cond(expanded, "expanded", "collapsed")},
            data = {
                built = false,
            },
        }
        if expanded then
            BuildRowBody(body, entry, creature)
        end

        local titleChildren = {
            gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 13,
                bold = true,
                text = titleText,
            },
        }
        if #subParts > 0 then
            titleChildren[#titleChildren+1] = gui.Label{
                classes = {"featureMutedText"},
                width = "100%",
                height = "auto",
                fontSize = 11,
                italics = true,
                text = table.concat(subParts, " - "),
            }
        end

        local headerChildren = {
            gui.Panel{
                width = "100%-80",
                height = "auto",
                flow = "vertical",
                halign = "left",
                children = titleChildren,
            },
        }
        --Right-side controls live in one right-aligned cluster so the expand
        --arrow keeps a fixed position on every row; the "Choose" pill sits to
        --its left rather than pushing the arrow inward.
        local rightChildren = {}
        if (entry._unspent or 0) > 0 then
            rightChildren[#rightChildren+1] = gui.Label{
                classes = {"featureChoiceBadge"},
                width = "auto",
                height = "auto",
                fontSize = 11,
                hpad = 6,
                vpad = 1,
                borderBox = true,
                valign = "center",
                hmargin = 4,
                text = "Choose",
            }
        end
        if tri ~= nil then
            rightChildren[#rightChildren+1] = tri
        end
        if #rightChildren > 0 then
            headerChildren[#headerChildren+1] = gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = rightChildren,
            }
        end

        local header = gui.Panel{
            classes = {"featureIndexRow"},
            width = "100%",
            height = "auto",
            flow = "horizontal",
            press = cond(expandable, function(element)
                local nowExpanded = not tri:HasClass("expanded")
                tri:SetClass("expanded", nowExpanded)
                body:SetClass("collapsed", not nowExpanded)
                if nowExpanded then
                    m_expandedRows[rowKey] = true
                    if not body.data.built then
                        BuildRowBody(body, entry, creature)
                    end
                else
                    m_expandedRows[rowKey] = nil
                end
            end),
            children = headerChildren,
        }

        return gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vmargin = 1,
            header,
            body,
        }
    end

    --Build one bucket group. Returns the group panel (nil when filtering and
    --nothing matches) and the matched-entry count.
    local function BuildGroup(bucketId, bucket, entries, creature)
        local matched = {}
        for _,e in ipairs(entries) do
            if m_filter == "" or Search.MatchesText(entrySearchText(e), m_filter) then
                matched[#matched+1] = e
            end
        end
        if m_filter ~= "" and #matched == 0 then
            return nil, 0
        end

        --Filtering forces matching groups open so the hits are visible.
        local expanded = (m_filter ~= "") or (m_expandedGroups[bucketId] == true)

        local label = FEATURE_GROUP_LABELS[bucketId] or bucket.name
        if FEATURE_GROUP_ORIGIN_PREFIX[bucketId] then
            --Distinct origin names in first-seen order: "Ancestry - Human",
            --"Class - Censor - Paragon" (class then subclass).
            local names = {}
            local seen = {}
            for _,e in ipairs(entries) do
                local n = e.originName
                if n ~= nil and not seen[n] then
                    seen[n] = true
                    names[#names+1] = n
                end
            end
            if #names > 0 then
                label = string.format("%s - %s", bucket.name, table.concat(names, " - "))
            end
        end

        local unspentTotal = 0
        for _,e in ipairs(matched) do
            unspentTotal = unspentTotal + (e._unspent or 0)
        end

        --Expansion is a LAZY IN-PLACE toggle, not a Rebuild: rebuilding the
        --whole tab on every arrow press costs ~100ms of synchronous Lua
        --(BuildIndex + per-entry choice checks + all panels). Bodies build
        --their rows on first expand and then just toggle the collapsed
        --class; full rebuilds happen only for data/filter changes.
        local function BuildGroupBodyChildren()
            local bodyChildren = {}
            if bucketId == "class" then
                --Sub-group the class bucket by level, preserving pipeline
                --order within each level. Each level is its own lazy
                --collapsible sub-group; expansion state survives rebuilds
                --via m_expandedLevels, and filtering forces levels open.
                local byLevel = {}
                local levelsSeen = {}
                for _,e in ipairs(matched) do
                    local lvl = e.level or 0
                    if byLevel[lvl] == nil then
                        byLevel[lvl] = {}
                        levelsSeen[#levelsSeen+1] = lvl
                    end
                    local t = byLevel[lvl]
                    t[#t+1] = e
                end
                table.sort(levelsSeen)
                for _,lvl in ipairs(levelsSeen) do
                    local levelEntries = byLevel[lvl]
                    local levelExpanded = (m_filter ~= "") or (m_expandedLevels[lvl] == true)

                    local levelUnspent = 0
                    for _,e in ipairs(levelEntries) do
                        levelUnspent = levelUnspent + (e._unspent or 0)
                    end

                    local levelTri = FeatureExpandoArrow(levelExpanded, {
                        valign = "center",
                    })

                    local levelHeaderChildren = {
                        levelTri,
                        gui.Label{
                            classes = {"featureMutedText"},
                            width = "auto",
                            height = "auto",
                            fontSize = 11,
                            valign = "center",
                            text = string.format("%s (%d)", cond(lvl > 0, string.format("Level %d", lvl), "Other"), #levelEntries),
                        },
                    }
                    if levelUnspent > 0 then
                        levelHeaderChildren[#levelHeaderChildren+1] = gui.Label{
                            classes = {"featureChoiceBadge"},
                            width = "auto",
                            height = "auto",
                            fontSize = 11,
                            hpad = 6,
                            vpad = 1,
                            borderBox = true,
                            halign = "right",
                            valign = "center",
                            text = string.format("%d to choose", levelUnspent),
                        }
                    end

                    local levelRows
                    local function BuildLevelRows()
                        levelRows.data.built = true
                        local rowChildren = {}
                        for _,e in ipairs(levelEntries) do
                            rowChildren[#rowChildren+1] = BuildRow(e, creature)
                        end
                        levelRows.children = rowChildren
                    end
                    levelRows = gui.Panel{
                        width = "100%-12",
                        halign = "right",
                        height = "auto",
                        flow = "vertical",
                        classes = {cond(not levelExpanded, "collapsed")},
                        data = { built = false },
                    }
                    if levelExpanded then
                        BuildLevelRows()
                    end

                    bodyChildren[#bodyChildren+1] = gui.Panel{
                        classes = {"featureGroupHeader"},
                        width = "100%",
                        height = "auto",
                        flow = "horizontal",
                        vmargin = 1,
                        press = function(element)
                            if m_filter ~= "" then
                                return
                            end
                            local nowExpanded = not (m_expandedLevels[lvl] == true)
                            if nowExpanded then
                                m_expandedLevels[lvl] = true
                            else
                                m_expandedLevels[lvl] = nil
                            end
                            levelTri:SetClass("expanded", nowExpanded)
                            levelRows:SetClass("collapsed", not nowExpanded)
                            if nowExpanded and not levelRows.data.built then
                                BuildLevelRows()
                            end
                        end,
                        children = levelHeaderChildren,
                    }
                    bodyChildren[#bodyChildren+1] = levelRows
                end
            else
                for _,e in ipairs(matched) do
                    bodyChildren[#bodyChildren+1] = BuildRow(e, creature)
                end
            end
            return bodyChildren
        end

        local bodyPanel
        bodyPanel = gui.Panel{
            width = "100%-12",
            halign = "right",
            height = "auto",
            flow = "vertical",
            classes = {cond(not expanded, "collapsed")},
            data = { built = false },
        }
        local function EnsureBodyBuilt()
            if bodyPanel.data.built then
                return
            end
            bodyPanel.data.built = true
            bodyPanel.children = BuildGroupBodyChildren()
        end
        if expanded then
            EnsureBodyBuilt()
        end

        local tri = FeatureExpandoArrow(expanded, {
            valign = "center",
        })

        local headerChildren = {
            tri,
            gui.Label{
                width = "auto",
                height = "auto",
                fontSize = 13,
                bold = true,
                text = label,
            },
            gui.Label{
                classes = {"featureMutedText"},
                width = "auto",
                height = "auto",
                fontSize = 11,
                hmargin = 6,
                valign = "center",
                text = cond(m_filter ~= "", string.format("%d of %d", #matched, #entries), string.format("%d", #entries)),
            },
        }
        if unspentTotal > 0 then
            headerChildren[#headerChildren+1] = gui.Label{
                classes = {"featureChoiceBadge"},
                width = "auto",
                height = "auto",
                fontSize = 11,
                hpad = 6,
                vpad = 1,
                borderBox = true,
                halign = "right",
                valign = "center",
                text = string.format("%d to choose", unspentTotal),
            }
        end

        local groupPanel = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            vmargin = 2,

            gui.Panel{
                classes = {"featureGroupHeader"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                press = function(element)
                    if m_filter ~= "" then
                        return
                    end
                    local nowExpanded = not (m_expandedGroups[bucketId] == true)
                    if nowExpanded then
                        m_expandedGroups[bucketId] = true
                    else
                        m_expandedGroups[bucketId] = nil
                    end
                    tri:SetClass("expanded", nowExpanded)
                    bodyPanel:SetClass("collapsed", not nowExpanded)
                    if nowExpanded then
                        EnsureBodyBuilt()
                    end
                end,
                children = headerChildren,
            },

            bodyPanel,
        }

        return groupPanel, #matched
    end

    Rebuild = function()
        if m_info == nil or not resultPanel.valid then
            return
        end
        local creature = m_info.token.properties
        if creature == nil or creature.typeName ~= "character" then
            resultPanel:SetClass("collapsed", true)
            m_headerPanel:SetClass("collapsed", true)
            m_groupsContainer.children = {}
            return
        end
        resultPanel:SetClass("collapsed", false)
        m_headerPanel:SetClass("collapsed", false)

        local index = FeatureCategoriser.BuildIndex(creature)

        local groupsChildren = {}
        local total = 0
        local matchedTotal = 0
        for _,bucketId in ipairs(index.order) do
            local group = index.groups[bucketId]
            local entries = {}
            for _,e in ipairs(group.items) do
                e._unspent = cond(e.kind == "build", FeatureUnspentChoices(e.feature, creature), 0)
                entries[#entries+1] = e
            end
            if #entries > 0 then
                total = total + #entries
                local groupPanel, matchedCount = BuildGroup(bucketId, group.bucket, entries, creature)
                matchedTotal = matchedTotal + matchedCount
                if groupPanel ~= nil then
                    groupsChildren[#groupsChildren+1] = groupPanel
                end
            end
        end
        m_groupsContainer.children = groupsChildren

        if m_filter == "" then
            m_countLabel.text = string.format("%d features", total)
        elseif matchedTotal == 0 then
            m_countLabel.text = string.format("No matches in %d features", total)
        else
            m_countLabel.text = string.format("Showing %d of %d features", matchedTotal, total)
        end
    end

    m_countLabel = gui.Label{
        classes = {"featureMutedText"},
        width = "auto",
        height = "auto",
        fontSize = 12,
        halign = "left",
        valign = "center",
        text = "",
    }

    local clearButton
    m_filterInput = gui.SearchInput{
        width = 200,
        height = 20,
        fontSize = 14,
        halign = "right",
        valign = "center",
        placeholderText = "Filter features...",
        editlag = 0.25,
        edit = function(element)
            m_filter = Search.Normalize(element.text)
            clearButton:SetClass("collapsed", element.text == nil or element.text == "")
            Rebuild()
        end,
    }
    clearButton = gui.Panel{
        floating = true,
        classes = {"featureClearFilter", "collapsed"},
        bgimage = "ui-icons/close.png",
        width = 14,
        height = 14,
        halign = "right",
        valign = "center",
        x = -4,
        press = function()
            m_filterInput.text = ""
            m_filterInput:FireEvent("edit")
        end,
    }
    m_filterInput:AddChild(clearButton)

    --Settings (gear) menu: the sheet's standard section-cog pattern
    --(settingsButton class + element.popup, same as the Immunities /
    --Skills / Languages cogs - native click-out dismissal, framedPanel +
    --PopupStyles theming). The menu only ADDS things: custom features are
    --edited on their rows in the Custom Features group. Template changes
    --rebuild the popup in place (the Immunities popup's idiom).
    local m_gearButton
    local ShowManageMenu

    ShowManageMenu = function(element)
        if m_info == nil then return end

        local children = {}

        children[#children+1] = gui.Label{
            classes = {"sizeXl", "bold"},
            halign = "center",
            text = "Manage Features",
            width = "auto",
            height = "auto",
        }

        children[#children+1] = gui.Button{
            classes = {"sizeM"},
            text = "Add Custom Feature",
            width = 220,
            halign = "center",
            vmargin = 4,
            click = function()
                local c = CharacterSheet.instance.data.info.token.properties
                local items = c:try_get("characterFeatures", {})
                local feature = CharacterFeature.Create{}
                items[#items+1] = feature
                c.characterFeatures = items
                element.popup = nil
                CharacterSheet.instance:FireEvent("refreshAll")
                local editor = feature:PopupEditor()
                editor.data.notifyElement = resultPanel
                CharacterSheet.instance:AddChild(editor)
            end,
        }

        local clipboardItem = dmhub.GetInternalClipboard()
        if clipboardItem ~= nil and (clipboardItem.typeName == "CharacterFeature" or clipboardItem.typeName == "ActivatedAbility") then
            children[#children+1] = gui.Button{
                classes = {"sizeM"},
                text = "Paste Feature",
                width = 220,
                halign = "center",
                vmargin = 4,
                click = function()
                    local c = CharacterSheet.instance.data.info.token.properties
                    local item = dmhub.GetInternalClipboard()
                    local feature = nil
                    if item ~= nil and item.typeName == "CharacterFeature" then
                        feature = DeepCopy(item)
                        DeepReplaceGuids(feature)
                    elseif item ~= nil and item.typeName == "ActivatedAbility" then
                        local ability = DeepCopy(item)
                        DeepReplaceGuids(ability)
                        local modifier = CharacterModifier.new{
                            guid = dmhub.GenerateGuid(),
                            name = ability.name,
                            description = "",
                            behavior = "activated",
                            activatedAbility = ability,
                        }
                        feature = CharacterFeature.Create{
                            name = ability.name,
                            modifiers = { modifier },
                        }
                    end
                    if feature ~= nil then
                        local items = c:try_get("characterFeatures", {})
                        items[#items+1] = feature
                        c.characterFeatures = items
                    end
                    element.popup = nil
                    CharacterSheet.instance:FireEvent("refreshAll")
                end,
            }
        end

        --width "auto" popup: every child must be fixed/auto width (a "100%"
        --child makes the auto-sized popup blow out to the screen bounds).
        children[#children+1] = gui.Label{
            width = "auto",
            height = "auto",
            halign = "center",
            fontSize = 14,
            bold = true,
            vmargin = 4,
            text = "Creature Templates",
        }

        local creature = m_info.token.properties
        local templates = nil
        pcall(function() templates = creature:try_get("creatureTemplates") end)
        local templatesTable = dmhub.GetTable("creatureTemplates") or {}
        for i,tid in ipairs(templates or {}) do
            local templateInfo = templatesTable[tid]
            if templateInfo ~= nil then
                local n = i
                children[#children+1] = gui.Panel{
                    width = 320,
                    height = "auto",
                    flow = "horizontal",
                    --statsLabel is a sheet-local class; the popup island only
                    --carries the theme cascade, so style the label inline.
                    gui.Label{
                        width = "80%",
                        height = "auto",
                        fontSize = 14,
                        text = templateInfo.name,
                    },
                    gui.Button{
                        classes = {"deleteButton"},
                        width = 24,
                        height = 24,
                        halign = "right",
                        click = function()
                            local c = CharacterSheet.instance.data.info.token.properties
                            c:RemoveTemplate(n)
                            CharacterSheet.instance:FireEvent("refreshAll")
                            ShowManageMenu(element)
                        end,
                    },
                }
            end
        end

        children[#children+1] = gui.Dropdown{
            width = 220,
            height = 28,
            halign = "center",
            vmargin = 4,
            idChosen = "none",
            create = function(dropdown)
                local choices = {
                    { id = "none", text = "Add Creature Template..." },
                }
                local templateTable = dmhub.GetTable("creatureTemplates") or {}
                for k,entry in pairs(templateTable) do
                    if not entry:try_get("hidden", false) then
                        choices[#choices+1] = { id = k, text = entry.name }
                    end
                end
                dropdown.options = choices
            end,
            change = function(dropdown)
                local c = CharacterSheet.instance.data.info.token.properties
                if dropdown.idChosen ~= "none" then
                    c:AddTemplate(dropdown.idChosen)
                end
                dropdown.idChosen = "none"
                CharacterSheet.instance:FireEvent("refreshAll")
                ShowManageMenu(element)
            end,
        }

        element.popupPositioning = "panel"
        element.popup = gui.Panel{
            classes = {"framedPanel"},
            halign = "right",
            interactable = true,
            flow = "vertical",
            hpad = 24,
            vpad = 14,
            width = "auto",
            height = "auto",
            --Popups are styling islands: the theme cascade must be supplied
            --explicitly or the Dropdown's internals lose their layout rules.
            --PopupStyles is deliberately NOT included: its selectorless
            --catch-all rule (flow vertical + valign bottom on EVERY panel)
            --wrecks the Dropdown control, stacking its triangle below the
            --label and outside the frame.
            styles = ThemeEngine.GetStyles(),
            children = children,
        }
    end

    m_gearButton = gui.Button{
        classes = {"settingsButton"},
        width = 16,
        height = 16,
        halign = "right",
        valign = "center",
        hmargin = 6,
        linger = function(element)
            gui.Tooltip("Manage Features and Templates")(element)
        end,
        press = function(element)
            if element.popup ~= nil then
                element.popup = nil
            else
                ShowManageMenu(element)
            end
        end,
    }

    m_groupsContainer = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = styles,

        refreshToken = function(element, info)
            local changedToken = false
            pcall(function()
                changedToken = m_info ~= nil and m_info.token.properties ~= info.token.properties
            end)
            if changedToken then
                m_gearButton.popup = nil
            end
            m_info = info
            Rebuild()
        end,

        --Custom-feature PopupEditors notify here on change (the
        --notifyElement contract): refresh the sheet so the index rebuilds.
        refreshModifier = function(element)
            CharacterSheet.instance:FireEvent("refreshAll")
        end,

        --Deep-link hook: the global-search features-on-creatures provider
        --fires this (with the matched feature's name) after landing the
        --sheet on the Features tab.
        filterFeatures = function(element, needle)
            if type(needle) ~= "string" then
                needle = ""
            end
            m_filterInput.text = needle
            m_filterInput:FireEvent("edit")
        end,

        m_groupsContainer,
    }

    --The filter/count/settings row is returned SEPARATELY so the tab can
    --pin it above the scroll area (it must survive scrolling).
    m_headerPanel = gui.Panel{
        width = "100%",
        height = 26,
        flow = "horizontal",
        styles = styles,
        m_countLabel,
        m_filterInput,
        m_gearButton,
    }

    return { header = m_headerPanel, body = resultPanel }
end

function CharSheet.InnerFeaturesPanel()
    local index = FeaturesIndexPanel()
    return gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",

        --Carries the search-reveal pulse rule so a monster trait row (in the
        --legacy ListEditor below) can be highlighted when revealed from search.
        styles = ThemeEngine.MergeTokens{ SEARCH_REVEAL_RULE },

        --Filter/count/settings row, pinned ABOVE the scroll area so it
        --survives scrolling. tmargin keeps the input clear of the tab
        --strip's border above.
        gui.Panel {
            width = "97%",
            hmargin = 4,
            tmargin = 6,
            halign = "left",
            height = "auto",
            index.header,
        },

        gui.Panel {
        width = "100%",
        height = "100%-36",
        valign = "top",
        vscroll = true,
        gui.Panel {
            classes = { "featuresPanel" },
            flow = "vertical",
            width = "97%",
            hmargin = 4,
            halign = "left",
            height = "auto",

            index.body,


            --Legacy bottom strip: custom-feature ListEditor + creature
            --templates + feats list. For characters this strip is folded
            --into the Features tab's gear (settings) menu; it stays inline
            --for monsters and other creature kinds.
            gui.Panel {
            width = "100%",
            height = "auto",
            flow = "vertical",
            refreshToken = function(element, info)
                element:SetClass("collapsed", info.token.properties.typeName == "character")
            end,

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
                                gui.Button {
                                    classes = {"deleteButton"},
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
                                gui.Button {
                                    classes = {"deleteButton"},
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

            },


        },
        },
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
            text = text,
            press = function(element)
                for i, panel in ipairs(element.parent.children) do
                    panel:SetClass("selected", i == index)
                end
                for i, panel in ipairs(contentPanels) do
                    panel:SetClass("collapsed", i ~= index)
                end
            end,

            --Deep-link hook: lets external code (global search's
            --features-on-creatures results) land the sheet on a named tab via
            --CharacterSheet.instance:FireEventTree("selectSheetTab", "Features").
            selectSheetTab = function(element, tabText)
                if tabText == text then
                    element:FireEvent("press")
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

    --Held so the revealCapability hook can select the Features tab the same
    --way pressing it does.
    local m_featuresTab = CreateTab("Features", 2)

    local resultPanel
    resultPanel = gui.Panel {
        classes = {"bordered"},
        width = "100%-40",
        height = "55.3%",
        bgimage = true,
        valign = "top",
        halign = "center",
        flow = "vertical",

        --Deep-link hook: a bestiary trait search result fires
        --"revealCapability" after opening the monster sheet. A monster's
        --traits render on the Features sub-tab (a flat list), so selecting
        --that tab is the Phase A reveal. Abilities (non-"Trait") are handled
        --by the action list and ignored here.
        revealCapability = function(element, capName, categorization)
            if categorization ~= "Trait" then
                return
            end
            m_featuresTab:FireEvent("press")
            if type(capName) ~= "string" or capName == "" then
                return
            end

            --Phase B: scroll the matched trait row into view and pulse it. A
            --trait renders as one markdown label whose visible text begins
            --with the trait name ("<b>End Effect.</b> ..."), so match on the
            --stripped prefix. Best-effort: a no-op if not located.
            local featuresContent = contentPanels[2]
            ScheduleRevealAndPulse(function()
                local result = nil
                local function walk(p, depth)
                    if p == nil or depth > 30 or result ~= nil then
                        return
                    end
                    local t = nil
                    pcall(function() t = p.text end)
                    if type(t) == "string" and t ~= "" then
                        local plain = (t:gsub("<.->", ""))
                        if string.sub(plain, 1, #capName) == capName then
                            result = p
                            return
                        end
                    end
                    local ok, ch = pcall(function() return p.children end)
                    if ok and type(ch) == "table" then
                        for _, c in ipairs(ch) do
                            walk(c, depth + 1)
                        end
                    end
                end
                walk(featuresContent, 0)
                return result
            end)
        end,

        --tab panel.
        gui.Panel {
            classes = {"tabBar"},
            valign = "top",
            width = "100%",
            CreateTab("Notes", 1),
            m_featuresTab,
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
