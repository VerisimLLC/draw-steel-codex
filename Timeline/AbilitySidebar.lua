local mod = dmhub.GetModLoading()

local g_displayedAbility = nil

function GameHud:InitAbilityDisplayPanel(abilityDisplayPanel)
    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        interactable = false,

        showAbility = function(element, token, ability, symbols)
            g_displayedAbility = ability

            local panel

                print("ABILITY:: RENDER TRIGGER START", ability.typeName)
            if ability.typeName == "ActiveTrigger" then
                local triggerInfo = token.properties:GetTriggeredActionInfo(ability:GetText())
                print("ABILITY:: RENDER TRIGGER", ability:GetText(), json(triggerInfo))
                if triggerInfo ~= nil then
                    panel = triggerInfo:Render { width = 340 }
                    panel:SetClass("hidden", false)
                    panel:SetClass("collapsed", false)
                end
            elseif ability.typeName == "TriggeredAbilityDisplay" then
                panel = ability:Render { width = 340 }
            else

                if ability.categorization == "Trigger" then
                    local triggerInfo = token.properties:GetTriggeredActionInfo(ability.name)
                    if triggerInfo ~= nil then
                        panel = triggerInfo:Render { width = 340, token = token, ability = ability, symbols = symbols }
                    end
                end

                if panel == nil then
                    panel = CreateAbilityTooltip(ability:GetActiveVariation(token),
                        { token = token, symbols = symbols, width = 346, bgcolor = "#222222e9", })
                end
            end

            element.children = {panel}

        end,

        hideAbility = function(element)
            element.children = {}
        end,
    }

    self.abilityDisplay = resultPanel

    abilityDisplayPanel.children = {resultPanel}
end

if GameHud.instance and rawget(GameHud.instance, "abilityDisplayPanel") ~= nil then
    GameHud.instance:InitAbilityDisplayPanel(GameHud.instance.abilityDisplayPanel)
end

function CharacterPanel.EmbedDialogInAbility()
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return nil
    end

    local dialog = GameHud.CreateEmbeddedRollDialog()

    local panel = GameHud.instance.abilityDisplay
    print("HIDE:: DO EMBED")
    panel:FireEventTree("embedRollDialog", dialog)
    return dialog
end

function CharacterPanel.DisplayAbility(token, ability, symbols)
    print("ABILITY:: DISPLAY", ability)
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return false
    end

    local panel = GameHud.instance.abilityDisplay

    local embeddedRoll = panel:FindChildRecursive(function(p)
        return p:HasClass("embeddedRollDialog")
    end)
    if embeddedRoll ~= nil then
        --could not displace existing ability.
        return false
    end


    panel:FireEventTree("showAbility", token, ability, symbols)

    return true
end

function CharacterPanel.HighlightAbilitySection(options)
    if (not GameHud.instance) or (not GameHud.instance.abilityDisplay) then
        return
    end

    local panel = GameHud.instance.abilityDisplay
    panel:FireEventTree("showAbilitySection", options)
end

function CharacterPanel.HideAbility(ability)
    print("ABILITY:: HIDE", ability)
    if (not GameHud.instance) or (not rawget(GameHud.instance, "abilityDisplay")) then
        return
    end

    local panel = GameHud.instance.abilityDisplay

    local ctrl = dmhub.modKeys['ctrl'] or false
    if ctrl then
        dmhub.Coroutine(function()
            while dmhub.modKeys['ctrl'] do
                coroutine.yield(0.1)
            end
            if panel ~= nil and panel.valid and ability == g_displayedAbility then
                panel:FireEvent("hideAbility")
            end
        end)
        return true
    end

    if panel ~= nil and panel.valid and ability == g_displayedAbility then
        panel:FireEvent("hideAbility")
        return true
    end

    return false
end