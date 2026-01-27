local mod = dmhub.GetModLoading()

--This file implements the main roll prompt dialog that appears when you get a dice roll prompt.

local g_holdingRollOpen = false
dmhub.HoldAmendableRollOpen = function()
    return g_holdingRollOpen
end

local g_activeRoll = nil
local g_activeRollArgs = nil

setting {
    id = "privaterolls",
    description = "Default Roll Visibility",
    storage = "preference",
    default = "visible",
    editor = "dropdown",
    section = "Game",

    enum = {
        {
            value = "visible",
            text = "Visible to Everyone",
        },
        {
            value = "dm",
            text = cond(dmhub.isDM, "Visible to Director only", "Visible to you and Director"),
        }
    }
}

setting {
    id = "privaterolls:save",
    description = "Save roll visibility preferences",
    storage = "preference",
    default = true,
    editor = "check",
}

local g_rollOptionsDM = {
    {
        id = "visible",
        text = "Visible to Everyone",
    },
    {
        id = "dm",
        text = "Visible to Director only",
    },
}

local g_rollOptionsPlayer = {
    {
        id = "visible",
        text = "Visible to Everyone",
    },
    {
        id = "dm",
        text = "Visible to you and GM",
    },
}

local g_boonsBanesStyles = {
    gui.Style {
        selectors = { "label" },
        color = Styles.textColor,
        valign = "center",
        width = "20%",
        height = "100%",
        bgimage = "panels/square.png",
        fontSize = 16,
        textAlignment = "center",
        borderWidth = 1,
        borderColor = Styles.textColor,
    },
    gui.Style {
        selectors = { "label", "selected" },
        bgcolor = Styles.textColor,
        color = "black",
        bold = true,
    },
    gui.Style {
        selectors = { "label", "hover", "~selected" },
        bgcolor = Styles.textColor,
        color = "black",
        brightness = 0.9,
    },
}

local g_boonsLabels = { "Bane x 2", "Bane", "None", "Edge", "Edge x 2" }


function GameHud.CreateRollDialog(self)
    --the creature doing the roll
    local creature = nil

    --creature targeted by the roll.
    local targetCreature = nil


    --- @type nil|({token: CharacterToken, boons: number, banes: number, text: string, modifiers: CharacterModifier[], triggers: list}[])
    local m_multitargets = nil
    local m_CalculateMultiTargets = nil

    local GetCurrentMultiTarget = function()
        if m_multitargets == nil or targetCreature == nil then
            return nil
        end

        for i, target in ipairs(m_multitargets) do
            if target.token.properties == targetCreature then
                return i
            end
        end

        return nil
    end

    local m_symbols = nil

    --any ongoing roll as a result of this dialog.
    local m_rollInfo = nil

    local rollType = ''
    local rollSubtype = ''
    local rollProperties = nil

    local resultPanel
    local CalculateRollText

    local rollAllPrompts = nil
    local rollActive = nil
    local beginRoll = nil
    local completeRoll = nil
    local cancelRoll = nil

    local m_shown = 0
    local m_richStatus = nil

    local OnShow = function(richStatus)
        print("Dice:: ROLL")
        audio.FireSoundEvent("Notify.Diceroll")

        chat.events:Push()
        chat.events:Listen(resultPanel)
        if m_richStatus ~= nil then
            dmhub.PopUserRichStatus(m_richStatus)
            m_richStatus = nil
        end

        m_richStatus = dmhub.PushUserRichStatus(richStatus)

        m_shown = m_shown + 1
    end

    local OnHide = function()
        m_rollInfo = nil
        if m_richStatus ~= nil then
            dmhub.PopUserRichStatus(m_richStatus)
            m_richStatus = nil
        end

        if m_shown > 0 then
            chat.events:Pop()
            m_shown = m_shown - 1
        end
    end

    local RelinquishPanel = function()
        --relinquish the coroutine owning this panel.
        resultPanel:FireEventTree("closedialog")
        m_rollInfo = nil
        resultPanel.data.coroutineOwner = nil
        g_holdingRollOpen = false
    end


    local styles = {
        Styles.Panel,
        {
            selectors = { 'framedPanel' },
            width = 940,
            height = 700,
            halign = "center",
            valign = "bottom",
            bgcolor = 'white',
        },
        {
            selectors = { "framedPanel", "minimized" },
            width = 300,
            height = 100,
            halign = "center",
            valign = "bottom",
            transitionTime = 0.2,
        },
        {
            selectors = { 'main-panel' },
            width = '100%-32',
            height = '100%-32',
            flow = 'vertical',
            halign = 'center',
            valign = 'center',
        },
        {
            selectors = { 'main-panel', 'minimized' },
            transitionTime = 0.2,
            width = '100%-8',
            height = '100%-8',
        },
        {
            selectors = { 'buttonPanel' },
            width = '100%',
            height = 60,
            flow = 'horizontal',
            valign = 'bottom',
        },
        {
            selectors = { 'title' },
            width = 'auto',
            height = 'auto',
            color = 'white',
            halign = 'center',
            valign = 'top',
            fontSize = 28,
        },
        {
            selectors = { 'explanation' },
            width = 'auto',
            height = 'auto',
            color = 'white',
            halign = 'center',
            valign = 'top',
            fontSize = 20,
        },
        {
            selectors = { 'roll-input' },
            width = '90%',
            halign = 'center',
            priority = 20,
            fontSize = 22,
            height = 34,
            valign = 'center',
        },
        {
            selectors = { 'checkbox' },
            height = 24,
            width = 'auto',
        },
        {
            selectors = { 'checkbox-label' },
            fontSize = 18,
        },
        {
            selectors = { 'modifiers-panel' },
            flow = 'vertical',
            height = 'auto',
            width = 'auto',
        },

        Styles.AdvantageBar,

        {
            selectors = { "reduceWhenMinimized", "minimized" },
            uiscale = 0.4,
            transitionTime = 0.2,
        },

        {
            selectors = { "hideWhenMinimized", "minimized" },
            uiscale = 0,
            transitionTime = 0.2,
        },

        {
            selectors = { "collapsedWhenRolling", "rolling" },
            collapsed = 1,
        },
        {
            selectors = { "collapsedWhenRolling", "finishedRolling" },
            collapsed = 1,
        },

        {
            selectors = { "hiddenWhenRolling", "rolling" },
            hidden = 1,
        },
        {
            selectors = { "hiddenWhenRolling", "finishedRolling" },
            hidden = 1,
        },

        {
            selectors = { "shownWhenFinished", "~finishedRolling" },
            collapsed = 1,
        },
        {
            selectors = { "shownWhenRollingOrFinished", "~finishedRolling", "~rolling" },
            collapsed = 1,
        },

        {
            selectors = { "icon" },
            bgcolor = "white",
            height = 48,
            width = 48,
        },

        {
            selectors = { "icon", "override" },
            bgcolor = "#ffff88",
            transitionTime = 0.2,
            brightness = 2,
        },
        {
            selectors = { "icon", "override", "inactive" },
            bgcolor = "#888844",
            transitionTime = 0.2,
        },
        {
            selectors = { "icon", "hover" },
            brightness = 3.0,
            transitionTime = 0.2,
        },
        {
            selectors = {"ai"},
            --hidden = 1,
            y = -10000,
            priority = 1000,
        },
    }

    local title = gui.Label {
        id = "rollDialogTitle",
        classes = { 'title', 'reduceWhenMinimized' },
        color = Styles.textColor,
    }

    local explanation = gui.Label {
        classes = { 'explanation', 'reduceWhenMinimized' },
    }

    local ShowTargetHints

    local rollInput = gui.Input{
        classes = { 'roll-input', 'hideWhenMinimized' },
        selectAllOnFocus = true,
        events = {
            edit = function(element)
                if element:HasClass("rolling") or element:HasClass("finishedRolling") then
                    return
                end
                element:SetClass("manualEdit", true)
                chat.PreviewChat(string.format('/roll %s', element.text))
                ShowTargetHints(element.text)
            end,
            change = function(element)
                if element:HasClass("rolling") or element:HasClass("finishedRolling") then
                    return
                end
                chat.PreviewChat(string.format('/roll %s', element.text))
            end,
        },
    }


    local autoRollCheck = gui.Check {
        text = "Auto-roll",
        value = false,
        valign = "bottom",
    }
    local autoHideCheck = gui.Check {
        text = "Auto-hide",
        value = false,
        valign = "bottom",
    }
    local autoQuickCheck = gui.Check {
        text = "Auto-quick",
        value = false,
        valign = "bottom",
    }

    local rollAllPromptsCheck = gui.Check {
        text = "Roll all prompts",
        value = true,
        valign = "bottom",
    }

    local autoRollId = nil

    local autoRollPanel = gui.Panel {
        valign = "bottom",
        width = "80%",
        height = "auto",
        flow = "vertical",
        autoHideCheck,
        autoQuickCheck,
        autoRollCheck,
    }

    local prerollCheck = gui.Check {
        text = "Pre-roll dice",
        classes = { "hiddenWhenRolling", "hideWhenMinimized" },
        value = dmhub.GetSettingValue("preroll"),
        valign = "bottom",
        vmargin = 6,
        change = function(element)
            dmhub.SetSettingValue("preroll", element.value)
            CalculateRollText()
        end,
        textCalculated = function(element)
            element:SetClass("collapsed", (not dmhub.isDM))
        end,
    }

    local updateRollVisibility
    local hideRollDropdown = gui.Dropdown {
        classes = { "hiddenWhenRolling", "hideWhenMinimized" },
        width = 300,
        height = 32,
        valign = "center",
        fontSize = 18,
        idChosen = dmhub.GetSettingValue("privaterolls"),
        options = cond(dmhub.isDM, g_rollOptionsDM, g_rollOptionsPlayer),
        valign = "bottom",
        prepare = function(element)
            element.idChosen = dmhub.GetSettingValue("privaterolls")
        end,

        change = function(element)
            updateRollVisibility:FireEvent("prepare")
        end,
    }

    updateRollVisibility = gui.Check {
        classes = { "hiddenWhenRolling", "hideWhenMinimized" },
        text = "Use roll visibility setting for all rolls",
        valign = "bottom",
        value = dmhub.GetSettingValue("privaterolls:save"),
        prepare = function(element)
            updateRollVisibility:SetClass("hidden", hideRollDropdown.idChosen == dmhub.GetSettingValue("privaterolls"))
        end,
    }

    local m_options

    --a selectors which allows alternate roll options to be selected, e.g. choosing between an Athletics and Acrobatics check.
    local alternateRollsBar


    --targets we record damage or other things about.
    local targetHints = nil

    ShowTargetHints = function(rollText)
        for i, hint in ipairs(targetHints or {}) do
            local str = rollText

            if hint.half then
                str = str .. " HALF"
            end

            creature.UploadExpectedCreatureDamage(hint.charid, resultPanel.data.rollid, str)
        end
    end

    local RemoveTargetHints = function()
        for _, hint in ipairs(targetHints or {}) do
            creature.UploadExpectedCreatureDamage(hint.charid, resultPanel.data.rollid, nil)
        end
    end

    local rollDisabledLabel
    local rollDiceButton
    local cancelButton
    local proceedAfterRollButton
    local rollAgainButton

    local modifierChecks = {}
    local modifierDropdowns = {}

    local m_boons = 0

    local boonBar
    local surgesBar

    local m_activeModifiers = {}

    local m_customContainer
    local m_tableContainer


    local GetEnabledModifiers = function()
        local enabledModifiers = {}
        for i, mod in ipairs(m_options.modifiers or {}) do
            if mod.modifier then
                local ischecked = false
                local force = mod.modifier:try_get("force", false)
                if mod.override ~= nil then
                    ischecked = mod.override
                elseif force then
                    ischecked = true
                elseif mod.hint ~= nil then
                    ischecked = mod.hint.result
                end

                if ischecked and (not mod.failsRequirement) then
                    enabledModifiers[#enabledModifiers + 1] = mod
                end
            end
        end

        table.sort(enabledModifiers, function(a, b)
            return a.modifier:ApplyToRollLateness(a) < b.modifier:ApplyToRollLateness(b)
        end)

        return enabledModifiers
    end


    --this is the current 'base roll' that is being calculated based on.
    local baseRoll = '1d6'
    CalculateRollText = function(calculationOptions)
        m_activeModifiers = {}

        local rollDisallowed = nil

        local roll = baseRoll

        local enabledModifiers = GetEnabledModifiers()

        if GameSystem.UseBoons then
            roll = GameSystem.ApplyBoons(roll, m_boons)
        end

        if creature then
            local syms = {
                target = GenerateSymbols(targetCreature)
            }

            if m_symbols ~= nil then
                for k, v in pairs(m_symbols) do
                    syms[k] = v
                end
            end
            roll = dmhub.NormalizeRoll(roll, creature:LookupSymbol(syms), "Calculate roll")
        end

        local afterCritMods = {}

        if creature then
            for i, mod in ipairs(enabledModifiers) do
                --call this generic function which might be modified by mods.
                roll = mod.modifier:ApplyToRoll(mod.context, creature, targetCreature, rollType, roll)

                if rollType == 'damage' then
                    if mod.modFromTarget then
                        roll = mod.modifier:ModifyDamageAgainstUs(mod.context, targetCreature, creature, roll)
                    elseif mod.modifier:CriticalHitsOnly() then
                        afterCritMods[#afterCritMods + 1] = mod
                    else
                        roll = mod.modifier:ModifyDamageRoll(mod, creature, targetCreature, roll)
                    end
                end

                m_activeModifiers[#m_activeModifiers + 1] = mod.modifier
            end

            for i, dropdown in ipairs(modifierDropdowns) do
                for j, option in ipairs(dropdown.data.mod.modifierOptions) do
                    if option.id == dropdown.idChosen and option.mod ~= nil then
                        if rollType == 'damage' then
                            roll = option.mod:ModifyDamageRoll(option, creature, targetCreature, roll)
                        end

                        m_activeModifiers[#m_activeModifiers + 1] = option.mod

                        if option.disableRoll then
                            rollDisallowed = option.disableRoll
                        end
                    end
                end
            end
        end

        if rollDisallowed ~= nil then
            rollDisabledLabel:SetClass("collapsed-anim", false)
            rollDisabledLabel.text = rollDisallowed
        else
            rollDisabledLabel:SetClass("collapsed-anim", true)
        end

        rollDiceButton:SetClass("hidden", rollDisallowed ~= nil)

        local rollInfo = dmhub.ParseRoll(roll, creature)

        local newText = dmhub.RollToString(rollInfo)

        if #afterCritMods > 0 then
            for i, mod in ipairs(afterCritMods) do
                newText = mod.modifier:ModifyDamageRoll(mod, creature, targetCreature, newText)
            end

            rollInfo = dmhub.ParseRoll(newText, creature)
            newText = dmhub.RollToString(rollInfo)
        end

        if dmhub.isDM and dmhub.GetSettingValue("preroll") then
            local cats = dmhub.RollInstantCategorized(newText)
            newText = ""
            for k, n in pairs(cats) do
                newText = string.format("%s%s%s [%s]", newText, cond(newText == "", "", " "), n, k)
            end

            newText = dmhub.RollToString(dmhub.ParseRoll(newText, creature))
        end

        if GameSystem.CombineNegativesForRolls then
            newText = dmhub.NormalizeRoll(newText, nil, nil, { "NormalizeNegatives" })
        end

        if newText ~= rollInput.text then
            rollInput.text = newText
        else
            rollInput:FireEvent('change')
        end

        if rollProperties ~= nil then
            -- Check for roll requirements and update modifiers that fail
            resultPanel:FireEventTree("prepareBeforeRollProperties", rollInfo, enabledModifiers, rollProperties)
            resultPanel:FireEventTree('prepare', m_options)

            enabledModifiers = GetEnabledModifiers()

            rollProperties:ResetMods()

            for i, mod in ipairs(enabledModifiers) do
                mod.modifier:ModifyRollProperties(mod.context, creature, rollProperties, targetCreature)
            end
        end

        ShowTargetHints(newText)

        calculationOptions = calculationOptions or {}
        calculationOptions.rollInfo = dmhub.ParseRoll(newText, creature)
        resultPanel:FireEventTree("textCalculated", calculationOptions)


        if rollProperties ~= nil then
            if not m_customContainer:HasClass("collapsed") then
                m_customContainer:FireEventTree("refreshMods")
            end

            if not m_tableContainer:HasClass("collapsed") then
                m_tableContainer:FireEventTree("refreshMods")
            end
        end

        return roll
    end

    local DuplicateTriggerToMultiTargets

    local RecalculateMultiTargets

    local rerollFudgedButton = gui.HudIconButton {
        icon = "panels/hud/clockwise-rotation.png",
        halign = "right",
        valign = "center",
        width = 32,
        height = 32,
        press = function(element)
            CalculateRollText()
        end,
        textCalculated = function(element)
            element:SetClass("hidden", (not dmhub.isDM) or (not dmhub.GetSettingValue("preroll")))
        end,
    }

    local rollInputContainer = gui.Panel {
        width = "auto",
        flow = "horizontal",
        width = '80%',
        halign = 'center',
        height = 34,
        valign = 'center',
        rollInput,
        rerollFudgedButton,
    }

    local CreateTriggerPanel = function(info)
        local m_info = info
        local token = dmhub.GetTokenById(info.charid)
        local triggerPanel
        local tokenPanel = gui.CreateTokenImage(token, {
            width = 48,
            height = 48,
            halign = "center",
            valign = "top",
        })

        local label = gui.Label {
            fontSize = 14,
            bold = true,
            width = "auto",
            height = "auto",
            halign = "center",
        }

        local augmentationOptions = {}
        for i = 1, 3 do
            local index = i
            augmentationOptions[#augmentationOptions + 1] = gui.Label {
                width = 60,
                height = 16,
                fontSize = 12,
                minFontSize = 6,
                bgimage = true,
                swallowPress = true,
                press = function(element)
                    if element:FindParentWithClass("selftrigger") then
                        --it's our creature so can click directly.
                        m_info.triggered = true
                        m_info.augmentations = m_info.augmentations or {}
                        m_info.augmentations[index] = not m_info.augmentations[index]
                        DuplicateTriggerToMultiTargets(m_info)
                        RecalculateMultiTargets()
                    end
                end,
                rightClick = function(element)
                    if m_info.modifier.powerRollModifier:try_get("changeTarget") then
                        return
                    end
                    local tok = dmhub.GetTokenById(info.charid)
                    if tok == nil or not tok.canControl then
                        return
                    end
                    element.popup = gui.ContextMenu {
                        entries = {
                            {
                                text = cond(m_info.augmentations ~= nil and m_info.augmentations[index], "Deactivate", "Activate"),
                                click = function()
                                    element.popup = nil
                                    m_info.triggered = true
                                    m_info.augmentations = m_info.augmentations or {}
                                    m_info.augmentations[index] = not m_info.augmentations[index]
                                    DuplicateTriggerToMultiTargets(m_info)
                                    RecalculateMultiTargets()
                                end,
                            }
                        }
                    }
                end,

                hover = function(element)
                    local tok = dmhub.GetTokenById(m_info.charid)
                    if tok == nil then
                        return
                    end

                    local additionalModifiers = tok.properties:GetAdditionalCostModifiersForPowerTableTrigger(m_info
                    .modifier)
                    local modifier = additionalModifiers[index]
                    if modifier == nil then
                        return
                    end

                    local rules = StringInterpolateGoblinScript(modifier:try_get("rulesText", ""), tok.properties)
                    if rules ~= "" then
                        gui.Tooltip(rules)(element)
                    end
                end,
            }
        end

        local augmentationsPanel = gui.Panel {
            width = "auto",
            height = "auto",
            halign = "center",
            children = augmentationOptions,
            styles = {
                {
                    selectors = { "label" },
                    bgcolor = Styles.backgroundColor,
                    color = Styles.textColor,
                    borderWidth = 2,
                    borderColor = Styles.textColor,
                    textAlignment = "center",
                },
                {
                    selectors = { "label", "hover" },
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor,
                    borderWidth = 2,
                    borderColor = Styles.textColor,
                },
                {
                    selectors = { "label", "selected" },
                    bgcolor = Styles.textColor,
                    color = Styles.backgroundColor,
                    borderWidth = 2,
                    borderColor = Styles.textColor,
                },
            },
        }

        triggerPanel = gui.Panel {
            classes = { "hideWhenMinimized", "triggerPanel", cond(dmhub.LookupTokenId(creature) == info.charid, "selftrigger", "othertrigger") },
            width = 160,
            height = 90,
            bgimage = true,
            flow = "vertical",

            hover = function(element)
                local tok = dmhub.GetTokenById(m_info.charid)
                if tok ~= nil then
                    local rules = StringInterpolateGoblinScript(m_info.modifier:try_get("rules", ""), tok.properties)
                    if rules ~= "" then
                        gui.Tooltip(rules)(element)
                    end
                end
            end,
            refreshTriggerInfo = function(element, info)
                m_info = info

                element:SetClass("afterroll", info.modifier:try_get("forceReroll", false))

                local tok = dmhub.GetTokenById(info.charid)
                if tok ~= nil then
                    tokenPanel:FireEventTree("token", tok)

                    local augmentations = info.augmentations or {}
                    local additionalModifiers = tok.properties:GetAdditionalCostModifiersForPowerTableTrigger(info
                    .modifier)
                    for i = 1, #augmentationOptions do
                        local panel = augmentationOptions[i]
                        local modifier = additionalModifiers[i]
                        panel:SetClass("collapsed", modifier == nil)
                        if modifier ~= nil then
                            local costType = modifier:try_get("resourceCostType")
                            local amount = ExecuteGoblinScript(modifier:try_get("resourceCostAmount", 1),
                                creature:LookupSymbol {}, 0)
                            local available = tok.properties:GetHeroicOrMaliceResources()
                            if costType ~= "cost" or amount > available then
                                panel:SetClass("collapsed", true)
                            else
                                panel.text = string.format("%d %s", amount, tok.properties:GetHeroicResourceName())
                                panel:SetClass("selected", augmentations[i])
                            end
                        end
                    end
                end

                element.selfStyle.halign = cond(info.hostile, "right", "left")

                element:SetClass("triggered", info.triggered)

                label.text = info.modifier.name
            end,
            --- @param element Panel
            ping = function(element, count)
                if count > 1 then
                    element:SetClass("ping", true)
                    element:SetClass("pong", not element:HasClass("pong"))

                    element:ScheduleEvent("ping", 0.25, count - 1)
                else
                    element:SetClass("ping", false)
                    element:SetClass("pong", false)
                end
            end,
            press = function(element)
                if m_info.modifier:try_get("forceReroll") and (not g_holdingRollOpen) then
                    return
                end
                if m_info.notakeback then
                    --this is a once-only trigger
                    return
                end
                if element:HasClass("selftrigger") then
                    --it's this creature's trigger so it can click directly.
                    m_info.triggered = not m_info.triggered
                    m_info.augmentations = {}
                    DuplicateTriggerToMultiTargets(m_info)
                    RecalculateMultiTargets()
                else
                    local text = "Pinging trigger controller."
                    local token = info.charid and dmhub.GetTokenById(info.charid)
                    if token and token.valid then
                        local player = token.playerNameOrNil
                        if player ~= nil then
                            text = string.format("Pinging %s to ask them to use the trigger.", player)
                        end
                    end

                    if dmhub.isDM then
                        text = text .. "\nRight-click to activate the trigger directly."
                    end

                    gui.Tooltip(text)(element)

                    m_info.ping = dmhub.GenerateGuid()
                    resultPanel:FireEventTree("dispatchTriggerUpdates")
                    element:FireEvent("ping", 12)
                end
            end,
            rightClick = function(element)
                if m_info.notakeback then
                    --this is a once-only trigger
                    return
                end

                if m_info.modifier:try_get("forceReroll") and (not element:HasClass("finishedRolling")) then
                    return
                end

                if m_info.modifier.powerRollModifier:try_get("changeTarget") then
                    return
                end

                local tok = dmhub.GetTokenById(info.charid)
                if tok == nil or not tok.canControl then
                    return
                end
                element.popup = gui.ContextMenu {
                    entries = {
                        {
                            text = cond(m_info.triggered, "Deactivate", "Activate"),
                            click = function()
                                element.popup = nil
                                m_info.triggered = not m_info.triggered
                                m_info.augmentations = {}
                                DuplicateTriggerToMultiTargets(m_info)
                                RecalculateMultiTargets()
                            end,
                        }
                    }
                }
            end,
            tokenPanel,
            label,
            augmentationsPanel,
        }

        return triggerPanel
    end

    local m_openedTriggers = nil

    local triggersContainer = gui.Panel {
        width = "100%",
        height = "auto",
        maxHeight = 96,
        wrap = true,
        flow = "horizontal",
        vscroll = true,

        styles = {
            {
                selectors = { "label" },
                color = Styles.textColor,
            },
            {
                selectors = { "label", "parent:triggered" },
                color = Styles.backgroundColor,
            },
            {
                selectors = { "triggerPanel" },
                bgcolor = "#00000000",
            },
            {
                selectors = { "triggerPanel", "selftrigger" },
                border = 1,
                borderColor = "grey",
            },
            {
                selectors = { "triggerPanel", "selftrigger", "~triggered", "hover", "rolling" },
                bgcolor = Styles.textColor,
                brightness = 0.7,
            },
            {
                selectors = { "triggerPanel", "selftrigger", "~triggered", "hover", "~afterroll" },
                bgcolor = Styles.textColor,
                brightness = 0.7,
            },
            {
                selectors = { "triggerPanel", "triggered" },
                bgcolor = Styles.textColor,
            },
            {
                selectors = { "triggerPanel", "hover" },
                border = 1,
                borderColor = "white",
            },
            {
                selectors = { "triggerPanel", "ping" },
                border = 2,
                borderColor = "#ff00ff",
            },
            {
                selectors = { "triggerPanel", "ping", "pong" },
                borderColor = "#ff88ff",
            },

        },

        prepare = function(element, options)
            element:SetClass("collapsed", true)
        end,
        recalculatedMultiTargets = function(element, multitargets)
            if multitargets == nil then
                element:SetClass("collapsed", true)
                return
            end

            local maintarget = multitargets[GetCurrentMultiTarget()]
            if maintarget == nil or #maintarget.triggers == 0 then
                element:SetClass("collapsed", false)
                return
            end

            element:SetClass("collapsed", false)
            local children = element.children
            for i, trigger in ipairs(maintarget.triggers) do
                local panel = children[i] or CreateTriggerPanel(trigger)
                panel:FireEvent("refreshTriggerInfo", trigger)
                children[i] = panel
            end

            for i = 1, #children do
                children[i]:SetClass("collapsed", i > #maintarget.triggers)
                children[i]:FireEvent("cleartrigger")
            end

            element.children = children
        end,

        monitorGameEvent = "charactersUpdated",

        thinkTime = 0.5,
        think = function(element)
            if (not element:HasClass("rolling") and (not element:HasClass("finishedRolling"))) then
                element:FireEvent("cleartriggers")
                return
            end

            if m_multitargets == nil or creature == nil then
                element:FireEvent("cleartriggers")
                return
            end

            local casterToken = dmhub.LookupToken(creature)
            if casterToken == nil then
                element:FireEvent("cleartriggers")
                return
            end

            for targetIndex, target in ipairs(m_multitargets) do
                for triggerIndex, trigger in ipairs(target.triggers) do
                    local targetAll = (trigger.modifier:try_get("multitarget", "one") == "all")
                    if m_openedTriggers == nil then
                        m_openedTriggers = {}
                    end

                    local key = trigger.modifier.guid
                    if not targetAll then
                        key = key .. target.token.charid
                    end

                    if m_openedTriggers[key] == nil then
                        local triggerIndexes = {}
                        triggerIndexes[#triggerIndexes + 1] = {
                            targetIndex = targetIndex,
                            triggerIndex = triggerIndex
                        }
                        local targets
                        if targetAll then
                            targets = { casterToken.charid }
                        else
                            targets = { target.token.charid }
                        end

                        local triggered = trigger.triggered
                        if triggered then
                            local augmentations = trigger.augmentations
                            if augmentations ~= nil then
                                for k, val in pairs(augmentations) do
                                    if val and type(k) == "number" then
                                        triggered = k
                                    end
                                end
                            end
                        end

                        local activeTrigger = ActiveTrigger.new {
                            id = dmhub.GenerateGuid(),
                            targets = targets,
                            triggered = triggered,
                            dismissed = trigger.dismissed,
                            powerRollModifier = trigger.modifier,
                            casterid = dmhub.LookupTokenId(creature),
                            originalAbilityRange = trigger.originalAbilityRange,
                            free = trigger.modifier:try_get("type") == "free",
                        }

                        if trigger.modifier.powerRollModifier:try_get("resourceCostType") == "cost" then
                            activeTrigger.heroicResourceCost = tonumber(trigger.modifier.powerRollModifier:try_get("resourceCostAmount", 1))
                        end

                        activeTrigger._tmp_tokenid = trigger.charid
                        activeTrigger._tmp_refreshTime = 0
                        activeTrigger._tmp_triggerIndexes = triggerIndexes
                        trigger.forceupdate = false

                        m_openedTriggers[key] = activeTrigger
                    elseif trigger.forceupdate then
                        trigger.forceupdate = false

                        local activeTrigger = m_openedTriggers[key]
                        activeTrigger.triggered = trigger.triggered
                        activeTrigger.dismissed = trigger.dismissed
                        trigger._tmp_refreshTime = 0
                    end
                end
            end

            if m_openedTriggers ~= nil then
                element.monitorGame = "/characters"

                for key, activeTrigger in pairs(m_openedTriggers) do
                    if activeTrigger._tmp_refreshTime == 0 or dmhub.Time() > activeTrigger._tmp_refreshTime + 20 then
                        activeTrigger._tmp_refreshTime = dmhub.Time()
                        local token = dmhub.GetTokenById(activeTrigger._tmp_tokenid)
                        if token ~= nil then
                            token:ModifyProperties {
                                description = "Set Trigger",
                                execute = function()
                                    token.properties:DispatchAvailableTrigger(activeTrigger)
                                end,
                            }
                        end
                    end
                end
            end
        end,

        --used to see if we've changed the trigger status of any triggers. If we have
        --then dispatch the updates.
        dispatchTriggerUpdates = function(element)
            if m_openedTriggers == nil or m_multitargets == nil then
                return
            end

            local haveUpdates = false

            for key, activeTrigger in pairs(m_openedTriggers) do
                for _, indexes in ipairs(activeTrigger._tmp_triggerIndexes) do
                    local target = m_multitargets[indexes.targetIndex]
                    if target ~= nil then
                        local triggerInfo = target.triggers[indexes.triggerIndex]
                        if triggerInfo ~= nil then
                            local triggered = triggerInfo.triggered
                            if triggered then
                                local augmentations = triggerInfo.augmentations
                                if augmentations ~= nil then
                                    for k, val in pairs(augmentations) do
                                        if val and type(k) == "number" then
                                            triggered = k
                                        end
                                    end
                                end
                            end

                            local ping = triggerInfo.ping or false

                            if triggered ~= activeTrigger.triggered or ping ~= activeTrigger.ping then
                                if triggered and activeTrigger.powerRollModifier and activeTrigger.powerRollModifier:try_get("forceReroll") then
                                    --this is a once-only trigger
                                    activeTrigger.dismissed = true
                                end

                                activeTrigger.triggered = triggered
                                activeTrigger.ping = ping
                                activeTrigger._tmp_refreshTime = 0 --this will force it to re-send.
                                haveUpdates = true
                            end
                        end
                    end
                end
            end

            if haveUpdates then
                element:FireEvent("think")
            end
        end,

        charactersUpdated = function(element)
            if m_openedTriggers == nil then
                return
            end

            local needUpdate = false

            for key, trigger in pairs(m_openedTriggers) do
                local token = dmhub.GetTokenById(trigger._tmp_tokenid)
                if token ~= nil then
                    local tokenTriggers = token.properties:GetAvailableTriggers() or {}
                    local tokenTrigger = tokenTriggers[trigger.id]
                    if tokenTrigger ~= nil and tokenTrigger.triggered ~= trigger.triggered then
                        trigger.triggered = tokenTrigger.triggered
                        trigger.retargetid = tokenTrigger.retargetid
                        trigger.dismissed = tokenTrigger.dismissed
                        needUpdate = true

                        --update any triggers to match.
                        if m_multitargets ~= nil then
                            for _, indexes in ipairs(trigger._tmp_triggerIndexes) do
                                local target = m_multitargets[indexes.targetIndex]
                                if target ~= nil then
                                    local triggerInfo = target.triggers[indexes.triggerIndex]
                                    if triggerInfo ~= nil then
                                        triggerInfo.augmentations = {}
                                        triggerInfo.triggered = cond(trigger.triggered, true, false)
                                        triggerInfo.retargetid = trigger.retargetid

                                        if type(trigger.triggered) == "number" then
                                            triggerInfo.augmentations[trigger.triggered] = true
                                        end

                                        DuplicateTriggerToMultiTargets(triggerInfo)
                                    end
                                end
                            end
                        end
                    end
                end
            end

            if needUpdate then
                RecalculateMultiTargets()
            end
        end,

        destroy = function(element)
            element:FireEvent("closedialog")
        end,

        closedialog = function(element)
            element:FireEvent("cleartriggers")
        end,

        --- @param element Panel
        cleartriggers = function(element)
            element.monitorGame = nil
            if m_openedTriggers == nil then
                return
            end

            local triggersByToken = {}
            for key, trigger in pairs(m_openedTriggers) do
                local triggerList = triggersByToken[trigger._tmp_tokenid] or {}
                triggersByToken[trigger._tmp_tokenid] = triggerList
                triggerList[#triggerList + 1] = trigger
            end

            m_openedTriggers = nil

            for tokenid, triggerList in pairs(triggersByToken) do
                local token = dmhub.GetTokenById(tokenid)
                if token ~= nil and token.valid then
                    token:ModifyProperties {
                        description = "Clear Triggers",
                        undoable = false,
                        execute = function()
                            for _, trigger in ipairs(triggerList) do
                                token.properties:ClearAvailableTrigger(trigger)
                            end
                        end,
                    }
                end
            end
        end,
    }

    local tableStyles = {
        Styles.Table,
        gui.Style {
            selectors = { "label" },
            pad = 6,
            fontSize = 20,
            width = "auto",
            height = "auto",
            color = Styles.textColor,
            valign = "center",
        },
        gui.Style {
            selectors = { "row" },
            width = "auto",
            height = "auto",
            bgimage = "panels/square.png",
            borderColor = Styles.textColor,
            borderWidth = 1,
        },
        gui.Style {
            selectors = { "row", "oddRow" },
            bgcolor = "#222222ff",
        },
        gui.Style {
            selectors = { "row", "evenRow" },
            bgcolor = "#444444ff",
        },
    }

    m_customContainer = gui.Panel {
        classes = { "hideWhenMinimized" },
        width = "94%",
        height = "auto",
        halign = "center",
        valign = "bottom",
        flow = "vertical",
        styles = tableStyles,
    }

    m_tableContainer = gui.Table {
        width = "60%",
        height = "auto",
        halign = "center",
        valign = "bottom",
        flow = "vertical",
        styles = tableStyles,
    }


    local m_lastCalculationOptions = nil

    local multitokenContainer = gui.Panel {
        styles = {
            {
                selectors = { "tokenContainer" },
                bgimage = "panels/square.png",
                bgcolor = "#00000000",
            },
            {
                selectors = { "tokenContainer", "selected" },
                bgimage = "panels/square.png",
                bgcolor = "#ffffff18",
            },
            {
                selectors = { "tokenContainer", "hover" },
                bgimage = "panels/square.png",
                bgcolor = "#ffffff22",
            },
            {
                selectors = { "icon" },
                bgimage = "game-icons/surge.png",
                width = 16,
                height = 16,
                bgcolor = "#ffffff66",
            },
            {
                selectors = { "icon", "activated" },
                bgcolor = "white",
            },
        },
        width = "auto",
        height = "auto",
        maxWidth = 400,
        halign = "center",
        valign = "top",
        flow = "horizontal",
        wrap = true,
        prepare = function(element, options)
            if m_multitargets == nil or #m_multitargets <= 1 then
                element:SetClass("collapsed", true)
                return
            end

            element:SetClass("collapsed", false)

            local children = {}

            for i, target in ipairs(m_multitargets) do
                local nameLabel = gui.Label {
                    fontSize = 12,
                    minFontSize = 8,
                    bold = true,
                    color = Styles.textColor,
                    width = "95%",
                    height = "auto",
                    maxHeight = 30,
                    halign = "center",
                    textOverflow = "truncate",
                    text = target.token.name,
                    textAlignment = "center",
                }
                local boonLabel = gui.Label {
                    fontSize = 10,
                    color = cond(target.text == nil, Styles.textColor, "#9999ffff"),
                    width = "95%",
                    height = "auto",
                    halign = "center",
                    valign = "top",
                    textAlignment = "center",
                    characterLimit = 28,

                    hover = function(element)
                        if target.text ~= nil then
                            gui.Tooltip(target.text)(element)
                        end
                    end,

                    recalculatedMultiTargets = function(element, multitargets)
                        if multitargets == nil then
                            return
                        end

                        local maintarget = multitargets[GetCurrentMultiTarget()]
                        local multitarget = multitargets[i]

                        if maintarget == nil or multitarget == nil then
                            return
                        end


                        if maintarget == multitarget then
                            element.text = ""
                            return
                        end

                        local maintargetModifiers = {}
                        local multitargetModifiers = {}

                        for _, mod in ipairs(maintarget.modifiers) do
                            if mod.modifier ~= nil then
                                local ischecked = false
                                local force = mod.modifier:try_get("force", false)
                                if mod.override ~= nil then
                                    ischecked = mod.override
                                elseif force then
                                    ischecked = true
                                elseif mod.hint ~= nil then
                                    ischecked = mod.hint.result
                                end

                                if ischecked then
                                    maintargetModifiers[mod.modifier.name] = true
                                end
                            end
                        end

                        for _, mod in ipairs(multitarget.modifiers) do
                            if mod.modifier ~= nil then
                                local ischecked = false
                                local force = mod.modifier:try_get("force", false)
                                if mod.override ~= nil then
                                    ischecked = mod.override
                                elseif force then
                                    ischecked = true
                                elseif mod.hint ~= nil then
                                    ischecked = mod.hint.result
                                end

                                if ischecked then
                                    multitargetModifiers[mod.modifier.name] = true
                                end
                            end
                        end

                        local text = ""

                        for k, _ in pairs(maintargetModifiers) do
                            if multitargetModifiers[k] == nil then
                                text = text .. " <s><color=#BBBBBB>" .. k .. "</color></s>"
                            end
                        end

                        for k, _ in pairs(multitargetModifiers) do
                            if maintargetModifiers[k] == nil then
                                text = text .. " <b>" .. k .. "</b>"
                            end
                        end

                        element.text = text
                    end,
                }

                local surges = {}
                for surgeNum = 3, 1, -1 do
                    surges[#surges + 1] = gui.Panel {
                        classes = { "icon", "hideWhenMinimized" },
                        textCalculated = function(element, calculationOptions)
                            if m_multitargets == nil or m_multitargets[i] == nil then
                                return
                            end
                            element:SetClass("activated", (m_multitargets[i].surges or 0) >= surgeNum)

                            local surgesAvailable = creature:GetAvailableSurges()
                            for i = 1, #m_multitargets do
                                surgesAvailable = surgesAvailable - (m_multitargets[i].surges or 0)
                            end

                            if rollProperties ~= nil then
                                surgesAvailable = surgesAvailable + rollProperties:try_get("surges", 0)
                            end

                            element:SetClass("hidden", (surgeNum - (m_multitargets[i].surges or 0)) > surgesAvailable)
                        end,
                        press = function(element)
                            if m_multitargets[i].surges == surgeNum then
                                m_multitargets[i].surges = surgeNum - 1
                            else
                                m_multitargets[i].surges = surgeNum
                            end
                            RecalculateMultiTargets()
                        end,
                    }
                end

                local tokenPanel = gui.Panel {
                    classes = { "tokenContainer", "hideWhenMinimized", cond(targetCreature == target.token.properties, "selected") },
                    width = 80,
                    height = 80,
                    flow = "vertical",
                    halign = "center",

                    press = function(element)
                        for i, child in ipairs(element.parent.children) do
                            child:SetClass("selected", child == element)
                        end
                        targetCreature = target.token.properties
                        m_options.targetCreature = targetCreature
                        m_options.modifiers = m_multitargets[i].modifiers

                        local calculationOptions = m_lastCalculationOptions or {}
                        calculationOptions.surges = target.surges or 0

                        resultPanel:FireEventTree('prepare', m_options)
                        CalculateRollText(calculationOptions)

                        RecalculateMultiTargets()
                    end,

                    gui.Panel {
                        flow = "horizontal",
                        width = "100%",
                        height = 48,
                        gui.CreateTokenImage(target.token, {
                            halign = "center",
                            valign = "top",
                            width = 48,
                            height = 48,
                            bgcolor = "white",
                        }),

                        gui.Panel {

                            floating = true,
                            halign = "right",
                            flow = "vertical",
                            height = "100%",
                            width = 16,
                            children = surges,
                        }
                    },

                    nameLabel,
                    boonLabel,
                }

                children[#children + 1] = tokenPanel
            end

            element.children = children
        end,
    }

    alternateRollsBar = gui.Panel {
        classes = { "hideWhenMinimized", "advantage-bar" },
        prepare = function(element, options)
            if options.alternateOptions == nil or #options.alternateOptions <= 1 then
                element:SetClass("collapsed-anim", true)
                return
            end

            local chooseAlternate = options.chooseAlternate
            local children = {}
            for optionIndex, alternate in ipairs(options.alternateOptions) do
                children[#children + 1] = gui.Label {
                    bgimage = 'panels/square.png',
                    classes = { 'advantage-element', cond(options.alternateChosen == optionIndex, "selected") },
                    text = alternate.text,
                    press = function(element)
                        chooseAlternate(optionIndex)
                    end,
                }
            end

            element.children = children
            element:SetClass("collapsed-anim", false)
        end,
    }

    if GameSystem.UseBoons then
        local boonsBanesLabels = {}

        local m_currentBoons = 0

        for i, text in ipairs(g_boonsLabels) do
            boonsBanesLabels[#boonsBanesLabels + 1] = gui.Label {
                text = text,
                press = function(element)
                    local delta = (i - 3) - m_currentBoons
                    m_boons = m_boons + delta
                    if GetCurrentMultiTarget() ~= nil then
                        local index = GetCurrentMultiTarget()
                        m_multitargets[index].boonsOverride = (m_multitargets[index].boonsOverride or 0) + delta
                    end
                    CalculateRollText()
                    RecalculateMultiTargets()
                end,
                textCalculated = function(element, calculationOptions)
                    local rollInfo = (calculationOptions or {}).rollInfo or {}
                    local boons = rollInfo.boons or 0
                    local banes = rollInfo.banes or 0
                    if boons > 0 and banes > 0 then
                        if boons > banes then
                            m_currentBoons = 1
                        elseif boons < banes then
                            m_currentBoons = -1
                        else
                            m_currentBoons = 0
                        end
                    else
                        m_currentBoons = boons - banes
                    end
                    element:SetClass("selected", m_currentBoons == i - 3)
                end,
            }
        end

        boonBar = gui.Panel {
            styles = g_boonsBanesStyles,
            classes = { "hideWhenMinimized", "boonbanePanel" },
            halign = "center",
            width = "60%",
            height = 22,
            flow = "horizontal",

            prepare = function(element, options)
                element:SetClass("collapsed", not GameSystem.AllowBoonsForRoll(options))
                m_boons = 0

                if GetCurrentMultiTarget() ~= nil then
                    local index = GetCurrentMultiTarget()
                    m_boons = (m_multitargets[index].boonsOverride or 0)
                end
            end,

            children = boonsBanesLabels,
        }

        boonBar:AddChild(gui.Panel {
            classes = { "icon" },
            bgimage = "panels/hud/anticlockwise-rotation.png",
            floating = true,
            halign = "right",
            x = 20,
            width = 16,
            height = 16,
            textCalculated = function(element, calculationOptions)
                element:SetClass("hidden", m_boons == 0)
            end,
            press = function(element)
                m_boons = 0
                CalculateRollText()
            end,
        })
    end


    local CreateSurgeIcon = function(index)
        return gui.Panel {
            classes = { "icon", "surges" },
            textCalculated = function(element, calculationOptions)
                local surgesAvailable = 0
                if creature ~= nil then
                    surgesAvailable = creature:GetAvailableSurges()
                    print("SURGES:: BASE =", surgesAvailable)
                end

                if rollProperties ~= nil then
                    surgesAvailable = surgesAvailable + rollProperties:try_get("surges", 0)
                end

                if m_multitargets ~= nil and #m_multitargets > 1 then
                    local mainTarget = GetCurrentMultiTarget()
                    for i = 1, #m_multitargets do
                        if i ~= mainTarget and m_multitargets[i].surges ~= nil then
                            surgesAvailable = surgesAvailable - m_multitargets[i].surges
                        end
                    end
                end

                print("SURGES:: HAVE SURGES", surgesAvailable)

                m_lastCalculationOptions = calculationOptions
                calculationOptions = calculationOptions or {}
                element:SetClass("collapsed",
                    rollProperties == nil or rollProperties.typeName ~= "RollPropertiesPowerTable" or creature == nil or
                    surgesAvailable < index)
                if rollProperties ~= nil and (not element:HasClass("collapsed")) then
                    element:SetClass("override", calculationOptions.surges ~= nil)
                    element:SetClass("inactive",
                        (calculationOptions.surges or rollProperties:try_get("surges", 0)) < index)
                    if (not element:HasClass("inactive")) then
                        local mods = GetEnabledModifiers()
                        local newSurgeDamage
                        for _, mod in ipairs(mods) do
                            if mod.modifier ~= nil and mod.modifier:try_get("rollRequirement") == "surges" and mod.modifier:try_get("surgeDamageType") ~= "untyped" then
                                newSurgeDamage = mod.modifier.surgeDamageType
                            end
                        end
                        if newSurgeDamage ~= nil then
                            rollProperties:ModifyDamageWithType(creature:HighestCharacteristic(), newSurgeDamage)
                        else
                            rollProperties:ModifyDamage(creature:HighestCharacteristic())
                        end
                    end
                end
            end,

            press = function(element)
                local surgesOverride = index
                if not element:HasClass("inactive") then
                    surgesOverride = surgesOverride - 1
                end

                if surgesOverride > 3 then
                    surgesOverride = 3
                end

                local options = m_lastCalculationOptions or {}
                options.surges = surgesOverride

                if m_multitargets ~= nil and GetCurrentMultiTarget() <= #m_multitargets then
                    m_multitargets[GetCurrentMultiTarget()].surges = surgesOverride
                end

                --CalculateRollText(options)
                RecalculateMultiTargets()
                -- Re-check requirements with the updated surge count
                if rollProperties ~= nil then
                    local rollInfo = dmhub.ParseRoll(rollInput.text, creature)
                    resultPanel:FireEventTree("prepareBeforeRollProperties", rollInfo, GetEnabledModifiers(), rollProperties)
                    resultPanel:FireEventTree('prepare', m_options)
                end
                CalculateRollText(options)
            end,
        }
    end

    surgesBar = gui.Panel {
        classes = { "hideWhenMinimized" },
        styles = {
            {
                flow = "horizontal",
            },

            {
                selectors = { "surges" },
                bgimage = "game-icons/surge.png",
            },
            {
                selectors = { "inactive" },
                bgcolor = "#aaaaaa",
                transitionTime = 0.2,
            },

        },
        width = 400,
        height = "auto",
        halign = "center",

        prepare = function(element, options)
            element:SetClass("collapsed", not string.find(options.type or "", "ability_power_roll"))
        end,

        gui.Panel {
            halign = "center",
            valign = "center",
            width = "auto",
            height = "auto",
            bgcolor = "black",
            bgimage = true,
            borderColor = "white",
            borderWidth = 1,
            hpad = 8,
            vpad = 4,
            tmargin = 8,
            textCalculated = function(element, calculationOptions)
                local surgesAvailable = 0
                if creature ~= nil then
                    surgesAvailable = creature:GetAvailableSurges()
                    print("SURGES:: BASE =", surgesAvailable)
                end

                if rollProperties ~= nil then
                    surgesAvailable = surgesAvailable + rollProperties:try_get("surges", 0)
                end

                if m_multitargets ~= nil and #m_multitargets > 1 then
                    local mainTarget = GetCurrentMultiTarget()
                    for i = 1, #m_multitargets do
                        if i ~= mainTarget and m_multitargets[i].surges ~= nil then
                            surgesAvailable = surgesAvailable - m_multitargets[i].surges
                        end
                    end
                end
                element:SetClass("hidden", surgesAvailable <= 0)
            end,

            gui.Label{
                bold = true,
                valign = "center",
                color = "white",
                text = "Surges:",
                width = "auto",
                height = "auto",
                fontSize = 24,
            },
            CreateSurgeIcon(1),
            CreateSurgeIcon(2),
            CreateSurgeIcon(3),
            CreateSurgeIcon(4),
            CreateSurgeIcon(5),
            CreateSurgeIcon(6),
            CreateSurgeIcon(7),
            CreateSurgeIcon(8),
            CreateSurgeIcon(9),
            CreateSurgeIcon(10),
            CreateSurgeIcon(11),
            CreateSurgeIcon(12),

            --a button to reset surge overrides. Only visible if we have overrides.
            gui.Panel {
                classes = { "icon" },
                bgimage = "panels/hud/anticlockwise-rotation.png",
                floating = true,
                halign = "right",
                x = 2,
                width = 16,
                height = 16,
                textCalculated = function(element, calculationOptions)
                    element:SetClass("hidden", calculationOptions == nil)
                end,
                press = function(element)
                    if m_multitargets ~= nil and GetCurrentMultiTarget() <= #m_multitargets then
                        m_multitargets[GetCurrentMultiTarget()].surges = 0
                    end

                    CalculateRollText()
                end,
            },
        },
    }

    local modifiersPanel = gui.Panel {
        classes = { "hideWhenMinimized", "modifiers-panel" },
        width = 0, --take up no space so the multi-target panel can be centered.
        events = {

            -- Here we get a pass at deciding any modifications to which modifiers are available
            -- that will modify rollProperties (e.g. damage) after edges and banes have been calculated.
            --- @param element Panel
            --- @param rollInfo ChatMessageDiceRollInfoLua
            prepareBeforeRollProperties = function(element, rollInfo, enabledModifiers, rollProperties)
                for modifierIndex, mod in ipairs(m_options.modifiers or {}) do
                    if mod.modifier ~= nil and mod.modifier:try_get("rollRequirement", "none") ~= "none" then
                        local passes = mod.modifier:CheckRollRequirement(rollInfo, enabledModifiers, rollProperties)

                        mod.failsRequirement = not passes

                        -- Uncheck abilities that fail requirements without triggering change events
                        if not passes and mod.override then
                            mod.override = false
                        end
                    else
                        -- Clear failsRequirement for modifiers without requirements
                        mod.failsRequirement = nil
                    end
                end
            end,

            prepare = function(element, options)
                modifierChecks = {}
                modifierDropdowns = {}
                if creature == nil or options.modifiers == nil then
                    element.children = {}
                    element:SetClass('collapsed-anim', true)
                    return
                end

                element:SetClass('collapsed-anim', false)

                local addedCritical = false

                local children = {}

                for modifierIndex, mod in ipairs(options.modifiers) do
                    if mod.modifier then
                        -- Skip modifiers that fail requirements
                        if mod.failsRequirement then
                            goto continue
                        end
                        
                        mod.context = mod.context or {}
                        local ischecked = false
                        local force = mod.modifier:try_get("force", false)
                        if mod.override ~= nil then
                            ischecked = mod.override
                        elseif force then
                            ischecked = true
                        elseif mod.hint ~= nil then
                            ischecked = mod.hint.result
                        end

                        local check --gui.Check that will come out of this.

                        local tooltip = mod.modifier:GetSummaryText()
                        if creature ~= nil then
                            tooltip = StringInterpolateGoblinScript(tooltip, creature)
                        end
                        for i, justification in ipairs(mod.hint.justification) do
                            tooltip = string.format("%s\n<color=%s>%s", tooltip, cond(ischecked, '#aaffaa', '#ffaaaa'),
                                justification)
                        end

                        local text = mod.modifier.name
                        if mod.modFromTarget then
                            text = string.format("Target is %s", text)
                        end

                        local triggeredModifier = mod.modifier:try_get("_tmp_trigger")

                        if triggeredModifier then
                            local token = dmhub.GetTokenById(mod.modifier._tmp_triggerCharid)
                            if token ~= nil then
                                text = string.format("%s (%s)", text, token.name)
                            end
                        else
                            --resource usage gets an availability description.
                            local availability = mod.modifier:DescribeResourceAvailability(creature,
                                mod.context.charges or 1, options.expectedCostOfCurrentCast)
                            if availability then
                                text = string.format("%s (%s)", text, availability)
                            end
                        end

                        local classes = nil

                        if force then
                            classes = { "collapsed-anim" }
                        end

                        check = gui.Check {
                            classes = classes,
                            text = text,
                            value = ischecked,
                            data = {
                                mod = mod,
                                modifierIndex = modifierIndex,
                            },
                            events = {
                                change = function(element)
                                    mod.override = element.value

                                    resultPanel:FireEventTree('prepare', m_options)
                                    CalculateRollText()
                                    RecalculateMultiTargets()
                                end,
                                linger = gui.Tooltip {
                                    text = tooltip,
                                    maxWidth = 600,
                                },
                            },
                        }

                        children[#children + 1] = check
                        modifierChecks[#modifierChecks + 1] = check

                        if mod.modifier:try_get("resourceCostType", "none") == "multicost" and ischecked then
                            mod.context.charges = mod.context.charges or 1
                            local panel = gui.Panel {
                                flow = "horizontal",
                                width = 160,
                                height = 18,
                                gui.Label {
                                    text = "Charges:",
                                    fontSize = 16,
                                    width = 70,
                                    height = "auto",
                                    valign = "center",
                                },
                                gui.Input {
                                    text = mod.context.charges,
                                    characterLimit = 2,
                                    width = 24,
                                    height = 14,
                                    fontSize = 14,
                                    selectAllOnFocus = true,
                                    change = function(element)
                                        local num = tonumber(element.text)
                                        if num == nil then
                                            element.text = mod.context.charges
                                            return
                                        end

                                        mod.context.charges = num

                                        resultPanel:FireEventTree('prepare', m_options)
                                        CalculateRollText()
                                        RecalculateMultiTargets()
                                    end,
                                }
                            }

                            children[#children + 1] = panel
                        end
                    elseif mod.check then
                        --this is a checkbox that is passed in that we will pass the results of straight out.

                        local check = gui.Check {
                            text = mod.text,
                            value = mod.value,
                            data = {
                                mod = mod,
                            },
                            events = {
                                change = function(element)
                                    element.data.mod.change(element.value)
                                end,
                                linger = function(element)
                                    if mod.tooltip ~= nil then
                                        gui.Tooltip {
                                            text = element.data.mod.tooltip,
                                            maxWidth = 600,
                                        } (element)
                                    end
                                end,
                            },
                        }

                        children[#children + 1] = check
                    elseif mod.modifierOptions then
                        local dropdown = gui.Dropdown {
                            width = 300,
                            height = 26,
                            valign = "center",
                            fontSize = 18,
                            idChosen = mod.hint.result,
                            options = mod.modifierOptions,
                            data = {
                                mod = mod,
                            },
                            change = function(element)
                                CalculateRollText()
                            end,
                        }

                        local panel = gui.Panel {
                            flow = "horizontal",
                            height = 36,
                            width = "80%",
                            gui.Label {
                                text = mod.text .. ":",
                                classes = "explanation",
                                halign = "left",
                                valign = "center",
                                width = 120,
                            },
                            linger = gui.Tooltip {
                                text = mod.tooltip,
                                maxWidth = 600,
                            },
                            dropdown,
                        }

                        modifierDropdowns[#modifierDropdowns + 1] = dropdown
                        children[#children + 1] = panel
                    end
                    
                    ::continue::
                end

                element.children = children
            end,
        },
    }

    local CancelRollDialog = function()
        RemoveTargetHints()
        if cancelRoll ~= nil then
            if not rollAllPromptsCheck:HasClass("collapsed-anim") and rollAllPromptsCheck.value and rollAllPrompts ~= nil then
                rollAllPrompts()
            end
            cancelRoll()
        end
        resultPanel:SetClass('hidden', true)
        chat.PreviewChat('')
        OnHide()
        RelinquishPanel()
    end

    rollAgainButton = gui.PrettyButton {
        text = "Re-roll",
        classes = { "shownWhenRollingOrFinished", "button" },
        width = 160,
        height = 50,
        styles = {
            {
                priority = 20,
                halign = "left",
            },
            {
                priority = 20,
                selectors = { "minimized" },
                halign = "center",
            },
        },

        press = function(element)
            print("REROLL:: DOING REROLL...", g_activeRoll)
            if g_activeRoll == nil then
                return
            end

            local guid = dmhub.GenerateGuid()

            g_activeRoll = g_activeRoll:Amend {
                guid = guid,
                roll = g_activeRollArgs.roll,
                amendmentRerolls = true,
                description = g_activeRollArgs.description .. " -- Re-rolled!",
                amendable = g_activeRollArgs.amendable,
                tokenid = g_activeRollArgs.tokenid,
                silent = g_activeRollArgs.rollIsSilent,
                instant = g_activeRollArgs.instant,
                creature = g_activeRollArgs.creature,
                properties = g_activeRollArgs.properties,
                begin = function(rollInfo)
                    m_rollInfo = rollInfo
                    resultPanel:FireEventTree("beginRoll", rollInfo, guid)
                end,
            }
        end,
    }

    proceedAfterRollButton = gui.PrettyButton {
        text = "Accept Result",
        classes = { "shownWhenRollingOrFinished", "button" },
        width = 200,
        height = 50,

        events = {},

    }

    rollDiceButton = gui.PrettyButton {
        text = 'Roll Dice',
        classes = { "collapsedWhenRolling", "button" },
        width = 200,
        height = 50,
        events = {
            press = function(element)
                resultPanel:FireEvent('submit')
            end,
            enter = function(element)
                print("RollDialog:: ENTER")
                element:FireEvent("press")
            end,
        }
    }

    cancelButton = gui.PrettyButton {
        text = 'Cancel',
        classes = { "collapsedWhenRolling", "button" },
        escapeActivates = true,
        escapePriority = EscapePriority.EXIT_ROLL_DIALOG,
        width = 200,
        height = 50,
        events = {
            press = function(element)
                CancelRollDialog()
            end,
        }
    }

    rollDisabledLabel = gui.Label {
        classes = { 'explanation', "collapsed-anim" },
        color = "#ffaaaaff",
        valign = "bottom",
    }

    local buttonPanel = gui.Panel {
        styles = {
            {
                selectors = { "button" },
                halign = "right",
                valign = "center",
            },
            {
                selectors = { "button", "minimized" },
                halign = "center",
                transitionTime = 0.2,
                uiscale = 0.4,
            },
        },
        classes = { 'buttonPanel' },
        floating = true,
        valign = "bottom",
        children = {
            rollAgainButton,
            rollDiceButton,
            cancelButton,
            proceedAfterRollButton,
        },
    }

    local mainPanel = gui.Panel {
        classes = { 'main-panel' },
        children = {
            title,
            gui.Divider { classes = { "hideWhenMinimized" }, width = "50%" },
            explanation,
            alternateRollsBar,
            gui.Panel {
                width = "100%",
                height = "auto",
                flow = "horizontal",
                modifiersPanel,

                gui.Panel {
                    width = 430,
                    height = 100,
                    vscroll = true,
                    halign = "center",
                    valign = "bottom",
                    vmargin = 12,

                    multitokenContainer,
                }
            },
            boonBar,
            surgesBar,
            m_tableContainer,
            m_customContainer,
            rollInputContainer,
            triggersContainer,
            autoRollPanel,
            prerollCheck,
            hideRollDropdown,
            updateRollVisibility,
            rollAllPromptsCheck,
            rollDisabledLabel,
            buttonPanel,
        }
    }

    DuplicateTriggerToMultiTargets = function(triggerInfo)
        if m_multitargets == nil or triggerInfo.modifier:try_get("multitarget", "one") ~= "all" then
            return
        end

        triggerInfo.duplicated = true

        for i, target in ipairs(m_multitargets) do
            for j, trigger in ipairs(target.triggers) do
                if trigger ~= triggerInfo and trigger.modifier.guid == triggerInfo.modifier.guid and trigger.charid == triggerInfo.charid then
                    target.triggers[j] = DeepCopy(triggerInfo)
                end
            end
        end


        resultPanel:FireEventTree("dispatchTriggerUpdates")
    end

    RecalculateMultiTargets = function()
        if m_multitargets == nil or rollProperties == nil then
            return
        end

        rollInput:SetClass("manualEdit", false)

        if m_CalculateMultiTargets ~= nil then
            m_multitargets = m_CalculateMultiTargets()
        end

        local index = nil
        for i, target in ipairs(m_multitargets) do
            if target.token.properties == targetCreature then
                index = i
                break
            end
        end

        if index == nil then
            return
        end

        local needReroll = false


        for i = 1, #m_multitargets do
            index = index + 1
            if index > #m_multitargets then
                index = 1
            end

            targetCreature = m_multitargets[index].token.properties
            m_options.targetCreature = targetCreature
            m_options.modifiers = table.shallow_copy(m_multitargets[index].modifiers)

            local triggers = m_multitargets[index].triggers or {}

            for j, trigger in ipairs(triggers) do
                if trigger.triggered then
                    local powerRollModifier = trigger.modifier.powerRollModifier

                    local triggerer = dmhub.GetTokenById(trigger.charid)

                    local additionalModifiers = (triggerer and triggerer.valid and triggerer.properties:GetAdditionalCostModifiersForPowerTableTrigger(trigger.modifier)) or
                    {}

                    local augmentations = trigger.augmentations or {}
                    for j = #additionalModifiers, 1, -1 do
                        if augmentations[j] then
                            local additionalModifier = DeepCopy(additionalModifiers[j])
                            additionalModifier.baseModifier = powerRollModifier
                            powerRollModifier = additionalModifier
                            break
                        end
                    end

                    if trigger.modifier:try_get("forceReroll") and (not trigger.forcedReroll) then
                        trigger.forcedReroll = true
                        trigger.notakeback = true
                        trigger.forceupdate = true
                        trigger.dismissed = true
                        needReroll = true
                    end

                    --mark this modifier as coming from a trigger.
                    powerRollModifier._tmp_trigger = true
                    powerRollModifier._tmp_triggerCharid = trigger.charid

                    trigger.triggerInfo = {
                        hint = { result = true, justification = {} },
                        context = { mod = powerRollModifier },
                        modifier = powerRollModifier,
                    }
                    m_options.modifiers[#m_options.modifiers + 1] = trigger.triggerInfo
                end
            end

            resultPanel:FireEventTree('prepare', m_options)
            local roll = CalculateRollText {
                surges = m_multitargets[index].surges or 0,
            }

            local rollInfo = dmhub.ParseRoll(roll, m_multitargets[index].token.properties)

            m_multitargets[index].modifiersUsed = DeepCopy(m_activeModifiers)
            m_multitargets[index].rollProperties = DeepCopy(rollProperties)
            m_multitargets[index].rollProperties.multitargets = nil
            m_multitargets[index].boons = (rollInfo.boons or 0)
            m_multitargets[index].banes = (rollInfo.banes or 0)
        end

        --make sure the rollProperties have the correct multitargets.
        rollProperties.multitargets = {}
        for _, target in ipairs(m_multitargets) do
            local t = DeepCopy(target)
            t.tokenid = target.token.charid
            t.token = nil
            rollProperties.multitargets[#rollProperties.multitargets + 1] = t
        end

        --the 'index' refers to the 'main'/selected target which everything else is normalized against.
        --a multitarget's "boons" is relative to the boons for the roll.
        local normalizedBoons = m_multitargets[index].boons
        local normalizedBanes = m_multitargets[index].banes
        if m_rollInfo ~= nil then
            --if the roll has already started then the roll defines the normalized boons.
            normalizedBoons = (m_rollInfo.boons or 0)
            normalizedBanes = (m_rollInfo.banes or 0)
        end
        for i = 1, #m_multitargets do
            m_multitargets[i].boons = m_multitargets[i].boons - normalizedBoons
            m_multitargets[i].banes = m_multitargets[i].banes - normalizedBanes
            rollProperties.multitargets[i].boons = m_multitargets[i].boons
            rollProperties.multitargets[i].banes = m_multitargets[i].banes
        end

        resultPanel:FireEventTree("recalculatedMultiTargets", m_multitargets, rollProperties)

        if needReroll then
            rollAgainButton:FireEvent("press")
            return true
        end
    end

    local delayRoll = 0
    local rollIsSilent = false

    local showDialogDuringRoll = false

    resultPanel = gui.Panel {
        classes = { 'hidden' },
        width = 940,
        height = 700,
        halign = "center",
        valign = "center",

        styles = styles,

        gui.Panel {
            classes = { "framedPanel" },
            cornerRadius = 0,
            opacity = 0.95,
            blurBackground = true,
            gui.Panel {
                halign = "right",
                valign = "top",
                width = "auto",
                height = "auto",
                flow = "horizontal",
                gui.Panel {
                    styles = {
                        {
                            selectors = { "hover" },
                            brightness = 1.4,
                        },
                    },
                    width = 24,
                    height = 24,
                    bgimage = true,
                    bgcolor = "black",
                    valign = "center",
                    borderWidth = 2,
                    borderColor = Styles.textColor,
                    press = function(element)
                        resultPanel:SetClassTree("minimized", not resultPanel:HasClass("minimized"))
                    end,
                },
                gui.CloseButton {
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_ROLL_DIALOG,
                    press = function(element)
                        cancelButton:FireEventTree("press")
                    end,
                },
            },
            mainPanel,
        },

        data = {

            rollid = nil,

            coroutineOwner = nil,

            ShowDialog = function(options)
                if not resultPanel.valid then
                    return
                end

                print("RollDialog:: SHOW", options)

                --if we are using an ability and we have cast info and it is the creature
                --taking this roll then record any resources they've committed to using.
                if options.creature ~= nil then
                    local castInfo = ActivatedAbility.CurrentCastInfo()
                    if castInfo ~= nil and dmhub.LookupTokenId(options.creature) == castInfo.casterToken.charid then
                        options.expectedCostOfCurrentCast = options.expectedCostOfCurrentCast or
                        ActivatedAbility.ExpectedResourceConsumptionFromCurrentCast()
                    end
                end

                if coroutine.GetCurrentId() ~= nil then
                    if resultPanel.data.coroutineOwner == nil then
                        resultPanel.data.coroutineOwner = coroutine.GetCurrentId()
                    else
                        while resultPanel.valid and resultPanel.data.coroutineOwner ~= coroutine.GetCurrentId() and coroutine.IsCoroutineWithIdStillRunning(resultPanel.data.coroutineOwner) do
                            coroutine.yield(0.01)
                        end

                        if resultPanel.valid then
                            resultPanel.data.coroutineOwner = coroutine.GetCurrentId()
                        end
                    end
                end

                if options.delay ~= nil then
                    local a, b = coroutine.running()

                    if dmhub.inCoroutine then
                        local t = dmhub.Time()
                        while dmhub.Time() < t + delay do
                            coroutine.yield(0.02)
                        end
                    else
                        local delay = options.delay

                        local optionsCopy = {}
                        for k, v in pairs(options) do
                            optionsCopy[k] = v
                        end

                        optionsCopy.rollid = dmhub.GenerateGuid()
                        optionsCopy.delay = nil

                        dmhub.Schedule(delay, function()
                            if resultPanel.valid then
                                resultPanel.data.ShowDialog(optionsCopy)
                            end
                        end)


                        return optionsCopy.rollid
                    end
                end

                print("RollDialog:: inCoroutine", dmhub.inCoroutine)
                if dmhub.inCoroutine then
                    while not resultPanel:HasClass("hidden") do
                        coroutine.yield(0.02)

                        if resultPanel == nil or (not resultPanel.valid) then
                            return
                        end
                    end
                elseif not resultPanel:HasClass("hidden") then
                    local rollid = dmhub.GenerateGuid()
                    --not in a coroutine so just reschedule this.
                    dmhub.Schedule(1.0, function()
                        if resultPanel.valid then
                            local optionsCopy = {}
                            for k, v in pairs(options) do
                                optionsCopy[k] = v
                            end

                            optionsCopy.rollid = rollid

                            resultPanel.data.ShowDialog(optionsCopy)
                        end
                    end)

                    return rollid
                end

                m_rollInfo = nil

                print("RollDialog:: deterministic =", dmhub.IsRollDeterministic(options.roll), "from", options.roll)
                if options.skipDeterministic and dmhub.IsRollDeterministic(options.roll) then
                    --this is a quick, happy path that we try to take if the roll is deterministic and we don't need to show the dialog.
                    --This is used to avoid the significant performance cost of creating the UI elements.
                    print("RollDialog:: RESOLVING DETERMINISTIC...")

                    local activeModifiers = false
                    for _, mod in ipairs(options.modifiers or {}) do
                        if mod.modifier then
                            local ischecked = false
                            local force = mod.modifier:try_get("force", false)
                            if force then
                                ischecked = true
                            elseif mod.hint ~= nil then
                                ischecked = mod.hint.result
                            end

                            if ischecked then
                                activeModifiers = true
                                break
                            end
                        end
                    end

                    if not activeModifiers then
                        local guid = dmhub.GenerateGuid()

                        local tokenid = nil
                        if options.creature ~= nil then
                            tokenid = dmhub.LookupTokenId(creature)
                        end

                        --insert the castid into this roll so that we know
                        --which cast this roll is associated with.
                        if m_symbols ~= nil and options.rollProperties then
                            options.rollProperties.castid = m_symbols.castid
                        end

                        --we take care not to call something that could yield in the complete() function.
                        --Instead call it after.
                        local rollInfo = nil
                        dmhub.Roll {
                            guid = guid,
                            description = options.description,
                            tokenid = tokenid,
                            silent = true,
                            instant = true,
                            roll = options.roll,
                            creature = options.creature,
                            properties = options.rollProperties,
                            complete = function(rollInfoArg)
                                rollInfo = rollInfoArg
                            end
                        }

                        RelinquishPanel()

                        print("INVOKE:: DETERMINISTIC ROLL COMPLETE", rollInfo)
                        if rollInfo ~= nil and options.completeRoll ~= nil then
                            print("INVOKE:: CALLING COMPLETE ROLL")
                            options.completeRoll(rollInfo)
                        end

                        return guid
                    end
                end

                if options.tableRef ~= nil then
                    --delegate table rolls to the specialized dialog for them.
                    print("RollDialog:: Delegating to RollOnTableDialog for", options.tableRef)
                    return resultPanel.data.rollOnTableDialog.data.ShowDialog(options)
                end

                showDialogDuringRoll = options.showDialogDuringRoll

                --ensure these buttons are shown when showing the dialog.
                resultPanel:SetClassTree("rolling", false)
                resultPanel:SetClassTree("finishedRolling", false)

                if options.PopulateTable ~= nil then
                    m_tableContainer:SetClass("collapsed", false)
                    options.PopulateTable(m_tableContainer)
                else
                    m_tableContainer:SetClass("collapsed", true)
                end

                if options.PopulateCustom ~= nil then
                    m_customContainer:SetClass("collapsed", false)
                    options.PopulateCustom(m_customContainer, options.creature, options)
                else
                    m_customContainer:SetClass("collapsed", true)
                end

                rollDiceButton.hasFocus = true

                m_symbols = options.symbols

                resultPanel.data.rollid = options.rollid or dmhub.GenerateGuid()
                rollIsSilent = false
                delayRoll = 0

                local richStatus = "Rolling dice"
                if options.type == "ability_power_roll" then
                    if options.ability ~= nil then
                        richStatus = string.format("Rolling power for %s", options.ability.name)
                    else
                        richStatus = "Rolling power"
                    end
                elseif options.title then
                    richStatus = string.format("Rolling %s", options.title)
                end

                if resultPanel:HasClass('hidden') then
                    resultPanel:SetClass('hidden', false)
                    OnShow(richStatus)
                end

                if not options.nofadein then
                    resultPanel:PulseClass("fadein")
                end

                m_options = options

                targetHints = options.targetHints

                rollType = options.type
                rollSubtype = options.subtype
                rollProperties = options.rollProperties

                creature = options.creature
                targetCreature = options.targetCreature
                m_multitargets = options.multitargets
                m_CalculateMultiTargets = options.CalculateMultiTargets

                title.text = options.title or 'Roll Dice'
                explanation.text = options.explanation or ''

                rollInput:SetClass("manualEdit", false)

                rollAllPrompts = options.rollAllPrompts
                rollActive = options.rollActive
                beginRoll = options.beginRoll
                completeRoll = options.completeRoll
                cancelRoll = options.cancelRoll

                resultPanel:FireEventTree('prepare', options)

                baseRoll = options.roll
                CalculateRollText()

                RecalculateMultiTargets()

                resultPanel:SetClass("ai", (creature ~= nil and creature._tmp_aicontrol > 0) or false)

                if options.numPrompts ~= nil and options.numPrompts > 1 then
                    rollAllPromptsCheck.value = true
                    rollAllPromptsCheck.data.SetText(string.format("Roll all %d prompts", options.numPrompts))
                    rollAllPromptsCheck:SetClass("collapsed-anim", false)
                else
                    rollAllPromptsCheck.value = false
                    rollAllPromptsCheck:SetClass("collapsed-anim", true)
                end

                if options.skipDeterministic and dmhub.IsRollDeterministic(rollInput.text) and dmhub.IsRollDeterministic(options.roll) then
                    rollIsSilent = true
                    if options.delayInstant ~= nil then
                        delayRoll = options.delayInstant
                    end
                    rollDiceButton:FireEventTree("press")
                elseif options.autoroll == true or dmhub.GetSettingValue("autorollall") or (options.creature ~= nil and options.creature._tmp_aicontrol > 0) then
                    if options.delayInstant ~= nil then
                        delayRoll = options.delayInstant or 0
                    else
                        delayRoll = 0
                    end

                    --TODO: Work out why this small delay seems necessary. The dice rolls are really funky/physics is weird if we don't have it.
                    dmhub.Schedule(0.1, function()
                        rollDiceButton:FireEventTree("press")
                    end)
                elseif options.autoroll == "cancel" then
                    cancelButton:FireEventTree("press")
                elseif options.autoroll ~= nil then
                    local autoroll = dmhub.GetSettingValue(string.format("%s:autoroll", options.autoroll.id))
                    local hideFromPlayers = dmhub.GetSettingValue(string.format("%s:hideFromPlayers", options.autoroll
                    .id))
                    local quickRoll = dmhub.GetSettingValue(string.format("%s:quickRoll", options.autoroll.id))

                    autoRollPanel:SetClass("collapsed-anim", false)
                    autoRollCheck.value = autoroll or false
                    autoRollCheck.data.SetText(string.format("Auto-roll %s in future", options.autoroll.text))
                    autoHideCheck.data.SetText(string.format("Hide %s from players", options.autoroll.text))
                    autoQuickCheck.data.SetText(string.format("Skip rolling animation for %s", options.autoroll.text))
                    autoRollId = options.autoroll.id

                    autoHideCheck.value = hideFromPlayers or false
                    autoQuickCheck.value = quickRoll or false


                    if autoroll then
                        rollDiceButton:FireEventTree("press")
                    end
                else
                    autoRollPanel:SetClass("collapsed-anim", true)
                    autoRollId = nil
                end

                return resultPanel.data.rollid
            end,

            IsShown = function()
                return not resultPanel:HasClass('hidden')
            end,

            Cancel = function()
                CancelRollDialog()
            end,
        },

        events = {
            submit = function(element)
                if not rollInput:HasClass("manualEdit") then
                    RecalculateMultiTargets()
                end

                RemoveTargetHints()

                local showingDialog = showDialogDuringRoll

                local completeFunction

                if showingDialog then
                    resultPanel:SetClassTree("rolling", true)
                    resultPanel:SetClassTree("finishedRolling", false)
                    g_holdingRollOpen = true


                    proceedAfterRollButton.events.press = function()
                        resultPanel:SetClass('hidden', true)
                        RelinquishPanel()
                        showingDialog = false
                    end

                    print("AI:: Dialog SETTING UP EVENT", creature ~= nil and creature._tmp_aicontrol or 0)
                    if creature ~= nil and creature._tmp_aicontrol > 0 then
                        local TryToProceed
                        local m_timerState = nil


                        TryToProceed = function()
                            --print("AI:: Dialog TRY TO PROCEED", resultPanel.valid and showingDialog)
                            if resultPanel.valid and showingDialog then
                                local tokens = dmhub.allTokens
                                local haveTriggers = false

                                local q = dmhub.initiativeQueue
                                if q ~= nil then
                                    for _,tok in ipairs(tokens) do
                                        local initiativeid = InitiativeQueue.GetInitiativeId(tok)
                                        if q:IsEntryPlayer(initiativeid) or tok.playerControlled then
                                            local triggers = tok.properties:GetAvailableTriggers(true)
                                            for _,trigger in pairs(triggers or {}) do
                                                if trigger.powerRollModifier then
                                                    haveTriggers = true
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end

                                --check to make sure we don't need to reroll.
                                if not haveTriggers then
                                    triggersContainer:FireEvent("charactersUpdated")
                                    CalculateRollText()
                                    local rerolling = RecalculateMultiTargets()
                                    if rerolling then
                                        --we need to reroll.
                                        dmhub.Schedule(3.0, function()
                                            TryToProceed()
                                        end)
                                        return
                                    end
                                end

                                --print("AI:: Dialog haveTriggers =", haveTriggers, m_timerState)

                                if haveTriggers and (m_timerState == nil or (dmhub.Time() < m_timerState.expire) or m_timerState.paused) then
                                    local t = dmhub.Time()
                                    if m_timerState == nil then
                                        --print("AI:: Dialog SET TIMER STATE")
                                        m_timerState = {
                                            start = t,
                                            current = t,
                                            expire = t + 5,
                                            text = "Triggers available. Click to pause.",
                                            callback = function()
                                                if m_timerState ~= nil then
                                                    if m_timerState.paused then
                                                        UpdateTriggerReactionPanel(nil)
                                                        if proceedAfterRollButton.valid then
                                                            proceedAfterRollButton:FireEventTree("press")
                                                        end
                                                        return
                                                    else
                                                        m_timerState.text = "Triggers available. Click to dismiss."
                                                        m_timerState.paused = true
                                                        UpdateTriggerReactionPanel(m_timerState)
                                                    end
                                                end
                                            end,
                                        }
                                    end

                                    m_timerState.current = t
                                    UpdateTriggerReactionPanel(m_timerState)
                                    dmhub.Schedule(0.2, function()
                                        TryToProceed()
                                    end)
                                else
                                    UpdateTriggerReactionPanel(nil)
                                    proceedAfterRollButton:FireEventTree("press")
                                end
                            end
                        end
                        --AI controlled creature, we auto-press the proceed button after a short delay.
                        dmhub.Schedule(3.0, function()
                            TryToProceed()
                        end)
                    end
                else
                    resultPanel:SetClass('hidden', true)
                    RelinquishPanel()
                end

                OnHide()

                local dmonly = false
                local instant = false

                if autoRollId ~= nil then
                    dmonly = autoHideCheck.value
                    instant = autoQuickCheck.value

                    dmhub.SetSettingValue(string.format("%s:autoroll", autoRollId), autoRollCheck.value)
                    dmhub.SetSettingValue(string.format("%s:hideFromPlayers", autoRollId), autoHideCheck.value)
                    dmhub.SetSettingValue(string.format("%s:quickRoll", autoRollId), autoQuickCheck.value)
                end

                if hideRollDropdown.idChosen == "dm" then
                    dmonly = true
                end

                if hideRollDropdown.idChosen ~= dmhub.GetSettingValue("privaterolls") and updateRollVisibility.value then
                    --update the setting for private rolls from now on.
                    dmhub.SetSettingValue("privaterolls", hideRollDropdown.idChosen)
                end

                dmhub.SetSettingValue("privaterolls:save", updateRollVisibility.value)

                if rollAllPrompts ~= nil and rollAllPromptsCheck.value then
                    rollAllPrompts()
                end

                --we must save off anything from the surrounding scope since this dialog might be reused after this.
                local activeRollFn = rollActive
                local beginRollFn = beginRoll
                local completeRollFn = completeRoll
                local creatureUsed = creature
                local modifiersUsed = DeepCopy(m_activeModifiers)
                local multitargetsUsed = m_multitargets

                local tokenid = nil

                if creature ~= nil then
                    tokenid = dmhub.LookupTokenId(creature)
                end

                rollProperties = rollProperties or RollProperties.new {}

                completeFunction = function(rollInfo)
                    local resourceConsumed = false

                    local surgesUsed = 0

                    local surgesNote = nil

                    local triggerCostsPaid = {}

                    local modifiersAccountedFor = {}

                    if multitargetsUsed ~= nil then
                        for i, target in ipairs(multitargetsUsed) do
                            for j, trigger in ipairs(target.triggers or {}) do
                                if trigger.triggered and trigger.modifier.powerRollModifier:try_get("changeTarget") and type(trigger.retargetid) == "string" and m_symbols ~= nil and m_symbols.cast ~= nil then
                                    m_symbols.cast:RecordRetarget { casterid = trigger.charid, tokenid = target.token.charid, retargetid = trigger.retargetid, retargetType = trigger.modifier.powerRollModifier:try_get("changeTargetEffect", "all") }
                                end
                            end

                            local thisTargetSurgesUsed = 0
                            local thisTargetSurgesGained = 0
                            local thisTargetNonWastedSurgesGained = 0

                            if target.rollProperties ~= nil then
                                thisTargetSurgesGained = target.rollProperties:try_get("surges", 0)
                                thisTargetNonWastedSurgesGained = target.rollProperties:try_get("nonwastedSurges", 0)
                            end

                            if target.surges ~= nil and target.surges > 0 then
                                thisTargetSurgesUsed = target.surges
                            end


                            thisTargetSurgesUsed = thisTargetSurgesUsed - thisTargetSurgesGained
                            if thisTargetSurgesUsed < -thisTargetNonWastedSurgesGained then
                                thisTargetSurgesUsed = -thisTargetNonWastedSurgesGained
                            end

                            surgesUsed = surgesUsed + thisTargetSurgesUsed
                            if thisTargetSurgesUsed > 0 then
                                if surgesNote == nil then
                                    surgesNote = string.format("Used %d %s attacking %s", thisTargetSurgesUsed,
                                        cond(thisTargetSurgesUsed > 1, "surges", "surge"), target.token.name)
                                else
                                    surgesNote = string.format("%s, %d %s attacking %s", surgesNote, thisTargetSurgesUsed,
                                        cond(thisTargetSurgesUsed > 1, "surges", "surge"), target.token.name)
                                end
                            elseif thisTargetSurgesUsed < 0 then
                                if surgesNote == nil then
                                    surgesNote = string.format("Gained %d %s attacking %s", -thisTargetSurgesUsed,
                                        cond(-thisTargetSurgesUsed > 1, "surges", "surge"), target.token.name)
                                else
                                    surgesNote = string.format("%s, gained %d %s attacking %s", surgesNote,
                                        -thisTargetSurgesUsed, cond(-thisTargetSurgesUsed > 1, "surges", "surge"),
                                        target.token.name)
                                end
                            end

                            for i, modifier in ipairs(target.modifiersUsed or {}) do
                                local c = creatureUsed

                                --see if this modifier is associated with a trigger, in which case it's that creature that consumes resources.
                                for _, trigger in ipairs(target.triggers or {}) do
                                    local token = dmhub.GetTokenById(trigger.charid)
                                    if token ~= nil and token.valid and trigger.triggered and trigger.modifier.powerRollModifier.guid == modifier.guid then
                                        c = token.properties
                                        if trigger.duplicated and triggerCostsPaid[trigger.modifier.guid] then
                                            --this is a duplicate trigget already accounted for.
                                            c = nil
                                        end
                                        break
                                    end

                                    if token ~= nil and token.valid and trigger.triggered then
                                        local additionalModifiers = token.properties
                                        :GetAdditionalCostModifiersForPowerTableTrigger(trigger.modifier)
                                        for _, additionalModifier in ipairs(additionalModifiers) do
                                            if additionalModifier.guid == modifier.guid then
                                                local token = dmhub.GetTokenById(trigger.charid)
                                                if token ~= nil then
                                                    c = token.properties
                                                    if trigger.duplicated and triggerCostsPaid[trigger.modifier.guid] then
                                                        --this is a duplicate trigget already accounted for.
                                                        c = nil
                                                    end
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end

                                --if the modifier is coded to have a specific caster responsible for it.
                                if modifier:try_get("casterCharid") ~= nil then
                                    if modifiersAccountedFor[modifier.guid] then
                                        --this is a duplicate modifier already accounted for.
                                        c = nil
                                    else
                                        local token = dmhub.GetTokenById(modifier.casterCharid)
                                        if token ~= nil then
                                            c = token.properties
                                        end
                                        modifiersAccountedFor[modifier.guid] = true
                                    end
                                end

                                if c ~= nil then
                                    local tokenUsed = dmhub.LookupToken(c)
                                    if tokenUsed ~= nil then
                                        local rollSymbols
                                        if rollProperties ~= nil then
                                            rollSymbols = rollProperties:GetSymbols(m_rollInfo, target.token.properties)
                                        end
                                        modifier:InstallSymbolsFromContext {
                                            triggerer = c:LookupSymbol {},
                                            abilitytarget = target.token.properties:LookupSymbol {},
                                            abilitycaster = creatureUsed:LookupSymbol {},
                                            tier = rollSymbols,
                                        }
                                        tokenUsed:ModifyProperties {
                                            description = "Consume resources",
                                            undoable = false,
                                            execute = function()
                                                --this also triggers the modifier's custom trigger
                                                local consume = modifier:ConsumeResource(c)
                                                resourceConsumed = consume or resourceConsumed
                                            end,
                                        }
                                    end
                                end
                            end

                            for _, trigger in ipairs(target.triggers or {}) do
                                if trigger.triggered and ((not trigger.duplicated) or (not triggerCostsPaid[trigger.modifier.guid])) then
                                    --TriggerPayCost uploads the properties.
                                    trigger.modifier:TriggerPayCost(trigger)
                                    triggerCostsPaid[trigger.modifier.guid] = true
                                end
                            end
                        end
                    else
                        for i, modifier in ipairs(modifiersUsed) do
                            local tokenUsed = dmhub.LookupToken(creatureUsed)
                            if tokenUsed ~= nil then
                                tokenUsed:ModifyProperties {
                                    description = "Consume resources",
                                    undoable = false,
                                    execute = function()
                                        local consume = modifier:ConsumeResource(creatureUsed)
                                        resourceConsumed = consume or resourceConsumed
                                    end,
                                }
                            end
                        end
                    end

                    if surgesUsed ~= 0 then
                        resourceConsumed = true
                        local tokenUsed = dmhub.LookupToken(creatureUsed)
                        if tokenUsed ~= nil then
                            tokenUsed:ModifyProperties {
                                description = "Consume surges",
                                undoable = false,
                                execute = function()
                                    creatureUsed:ConsumeSurges(surgesUsed, surgesNote)
                                end,
                            }
                        end
                    end

                    local ongoingEffects = {}
                    for i, modifier in ipairs(modifiersUsed) do
                        local newOngoingEffects = modifier:ApplyOngoingEffectsToSelfOnRoll(creature)
                        if newOngoingEffects ~= nil then
                            for j, c in ipairs(newOngoingEffects) do
                                ongoingEffects[#ongoingEffects + 1] = c
                            end
                        end
                    end

                    if resourceConsumed or #ongoingEffects > 0 then
                        local creatureToken = dmhub.LookupToken(creatureUsed)
                        if creatureToken ~= nil then
                            for i, cond in ipairs(ongoingEffects) do
                                creatureUsed:ApplyOngoingEffect(cond.ongoingEffect, cond.duration, nil, {
                                    untilEndOfTurn = cond.durationUntilEndOfTurn,
                                })
                            end
                            creatureToken:Upload('Used resource')
                        end
                    end

                    if completeRollFn ~= nil then
                        completeRollFn(rollInfo)
                    end
                end

                --insert the castid into this roll so that we know
                --which cast this roll is associated with.
                if m_symbols ~= nil and m_options.rollProperties then
                    m_options.rollProperties.castid = m_symbols.castid
                end

                print("ROLL:: SET CASTID", m_symbols ~= nil, m_symbols and m_symbols.castid)

                local activeRoll
                local rollArgs = {
                    guid = resultPanel.data.rollid,
                    description = m_options.description,
                    amendable = m_options.amendable,
                    tokenid = tokenid,
                    silent = rollIsSilent,
                    delay = delayRoll,
                    dmonly = dmonly,
                    instant = instant,
                    roll = rollInput.text,
                    creature = creature,
                    properties = rollProperties,
                    begin = function(rollInfo)
                        print("ROLL:: BEGIN", rollInfo, rollIsSilent, instant)
                        m_rollInfo = rollInfo
                        if beginRollFn ~= nil then
                            beginRollFn(rollInfo)
                        end

                        resultPanel:FireEventTree("beginRoll", rollInfo, resultPanel.data.rollid)
                    end,
                    complete = function(rollInfo)
                        print("ROLL:: COMPLETE")
                        m_rollInfo = rollInfo

                            print("AI:: Dialog IS COMPLETE, SHOWING DIALOG:", showingDialog)
                        if showingDialog then
                            resultPanel:SetClassTree("rolling", false)
                            resultPanel:SetClassTree("finishedRolling", true)

                            proceedAfterRollButton.events.press = function()
                                print("AI:: Dialog PRESSED PROCEED AFTER ROLL")
                                resultPanel:SetClass('hidden', true)
                                RelinquishPanel()

                                completeFunction(rollInfo)
                            end

                            print("AI:: Dialog ROLL COMPLETE...")
                            if creature ~= nil and creature._tmp_aicontrol > 0 then
                            print("AI:: Dialog ROLL PRESS PROCEED...")
                                proceedAfterRollButton:FireEvent("press")
                            end

                            return
                        end

                        completeFunction(rollInfo)


                        if g_activeRoll == activeRoll then
                            g_activeRoll = nil
                print("ROLL:: ACTIVE ROLL CANCEL")
                        end
                    end
                }

                g_activeRollArgs = rollArgs

                -- Hook for external mods to intercept rolls
                local hookResult = nil
                if RollDialog_BeforeRoll then
                    hookResult = RollDialog_BeforeRoll({
                        rollArgs = rollArgs,
                        roll = rollArgs.roll,
                        description = rollArgs.description,
                        creature = rollArgs.creature,
                        tokenid = rollArgs.tokenid,
                        properties = rollArgs.properties,
                        dmonly = rollArgs.dmonly,
                        instant = rollArgs.instant,
                        silent = rollArgs.silent,
                        delay = rollArgs.delay,
                        guid = rollArgs.guid,
                        modifiers = modifiersUsed,
                        multitargets = multitargetsUsed,
                        boons = m_boons,
                    })
                end

                if hookResult == "intercept" then
                    return
                end                

                activeRoll = dmhub.Roll(rollArgs)
                print("ROLL:: ACTIVE ROLL FROM", rollArgs, "HAVE", activeRoll)

                g_activeRoll = activeRoll

                if activeRollFn ~= nil then
                    activeRollFn(activeRoll)
                end

                chat.PreviewChat('')
            end,
        },
    }

    return resultPanel
end
