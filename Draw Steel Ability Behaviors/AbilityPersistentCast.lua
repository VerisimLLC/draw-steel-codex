local mod = dmhub.GetModLoading()

Persistence = RegisterGameType("Persistence")
Persistence.name = ""

--- @class ActivatedAbilityPersistenceControlBehavior:ActivatedAbilityBehavior
RegisterGameType("ActivatedAbilityPersistenceControlBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityPersistenceCastBehavior:ActivatedAbilityBehavior
RegisterGameType("ActivatedAbilityPersistenceCastBehavior", "ActivatedAbilityBehavior")

RegisterGoblinScriptSymbol(creature, {
	name = "Number of Persistent Abilities",
	type = "number",
	desc = "The number of persistent abilities that this creature has active.",
	examples = {'self.Number of Persistent Abilities < 1'},
	calculate = function(c)
        local persistentAbilities = c:try_get("persistentAbilities", {})
        return #persistentAbilities
	end,
})

RegisterGoblinScriptSymbol(creature, {
	name = "Persistent Abilities",
	type = "set",
	desc = "Persistent abilities that this creature currently has active.",
	examples = {'self.Persistent Abilities has "Behold the Mystery"'},
	calculate = function(c)
        local persistentAbilities = c:try_get("persistentAbilities", {})

        local results = {}
        for _, ability in pairs(persistentAbilities) do
            results[#results+1] = ability.abilityName
        end

        return StringSet.new {
            strings = results,
        }
	end,
})

ActivatedAbilityPersistenceControlBehavior.summary = "Persistence Control"
ActivatedAbilityPersistenceControlBehavior.triggerOnly = true
ActivatedAbilityPersistenceControlBehavior.mono = false

ActivatedAbility.RegisterType
{
	id = 'persistenceControl',
	text = 'Persistence Control',
	createBehavior = function()
		return ActivatedAbilityPersistenceControlBehavior.new{
		}
	end
}

function ActivatedAbilityPersistenceControlBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	return result
end

function ActivatedAbilityPersistenceControlBehavior:Cast(ability, casterToken, targets, options)

    local finished = false
    local canceled = false

    local caster = casterToken:GetCreature()
    local casterClasses = caster:GetClassesAndSubClasses()
    local startOfTurnHeroicResource = 0
    for _, classInfo in pairs(casterClasses) do
        local heroicResource = classInfo.class:get_or_add("heroicResourceChecklist", {})
        for _, resourceInfo in pairs(heroicResource) do
            if string.lower(resourceInfo.name or "") == "start of turn" then
                startOfTurnHeroicResource = resourceInfo.quantity or 0
            end
        end
    end

    startOfTurnHeroicResource = tonumber(dmhub.EvalGoblinScript(startOfTurnHeroicResource, caster:LookupSymbol(), string.format("Calculating Start of Turn Resources")))

    local persistenceAbilities = casterToken.properties:try_get("persistentAbilities") or {}

    -- Track which abilities are selected to KEEP (start with all selected).
    local keepAbilities = {}
    for _, ab in pairs(persistenceAbilities) do
        keepAbilities[ab.guid] = true
    end

    -- Reference to the cost label so chips can trigger a refresh.
    local costLabelElement = nil

    local function refreshCostLabel()
        if costLabelElement == nil then
            return
        end
        local expectedCost = 0
        for _, ab in pairs(persistenceAbilities) do
            if keepAbilities[ab.guid] then
                expectedCost = expectedCost + (ab.cost or 0)
            end
        end

        costLabelElement.text = string.format("Essence Gained: %d", startOfTurnHeroicResource - expectedCost)

        if expectedCost > startOfTurnHeroicResource then
            costLabelElement:SetClass("persist-cannot-afford", true)
        else
            costLabelElement:SetClass("persist-cannot-afford", false)
        end
    end

    -- Build chip panels for each persistent ability.
    local chipPanels = {}
    for _, persistAbility in pairs(persistenceAbilities) do
        local capturedAbility = persistAbility

        chipPanels[#chipPanels+1] = gui.Panel{
            classes = {"persist-chip"},
            flow = "horizontal",

            press = function(element)
                if keepAbilities[capturedAbility.guid] then
                    keepAbilities[capturedAbility.guid] = nil
                    element:SetClass("persist-chip-selected", false)
                else
                    keepAbilities[capturedAbility.guid] = true
                    element:SetClass("persist-chip-selected", true)
                end
                refreshCostLabel()
            end,

            create = function(element)
                if keepAbilities[capturedAbility.guid] then
                    element:SetClass("persist-chip-selected", true)
                end
            end,

            hover = function(element)
                local abilities = casterToken.properties:GetActivatedAbilities{excludeGlobal = true}
                for _, ab in ipairs(abilities) do
                    if ab.name == capturedAbility.abilityName then
                        element.tooltip = CreateAbilityTooltip(ab, {
                            token = casterToken,
                            halign = "right",
                            width = 500,
                        })
                        break
                    end
                end
            end,

            gui.Label{
                classes = {"persist-chip-label"},
                text = capturedAbility.abilityName,
            },
        }
    end

    -- Assemble main content.
    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"persist-title"},
        text = ability.name or "Persistence Control",
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"persist-instruction"},
        text = "Select abilities to end.",
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"persist-cost-label"},

        create = function(element)
            costLabelElement = element
            refreshCostLabel()
        end,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"persist-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"persist-chips-wrap"},
        children = chipPanels,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"persist-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"persist-button-row"},
        gui.Panel{
            classes = {"persist-submit"},
            press = function(element)
                -- End any persistent abilities that were NOT selected to keep.
                for _, ab in pairs(persistenceAbilities) do
                    if not keepAbilities[ab.guid] then
                        casterToken.properties:EndPersistentAbilityById(ab.guid)
                    end
                end

                -- Calculate essence from kept abilities.
                local selectedCost = 0
                for _, ab in pairs(persistenceAbilities) do
                    if keepAbilities[ab.guid] then
                        selectedCost = selectedCost + (ab.cost or 0)
                    end
                end
                local earnedEssence = startOfTurnHeroicResource - selectedCost

                local ongoingEffectsTable = dmhub.GetTable("characterOngoingEffects") or {}
                for id, effect in pairs(ongoingEffectsTable) do
                    if string.lower(effect.name) == "essence at start" then
                        casterToken:ModifyProperties{
                            description = "Set Start of Turn Essence",
                            execute = function()
                                casterToken.properties:ApplyOngoingEffect(id, nil, casterToken, {stacks = earnedEssence + 1})
                            end,
                        }
                        break
                    end
                end

                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"persist-button-label"},
                text = "Submit",
            },
        },
        gui.Panel{
            classes = {"persist-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"persist-button-label"},
                text = "Cancel",
            },
        },
    }

    local resultPanel = gui.Panel{
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#040807",
        border = 1,
        borderColor = "#5C3D10",
        cornerRadius = 6,
        width = 480,
        height = "auto",
        pad = 12,

        styles = {
            {
                selectors = {"label", "persist-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "persist-instruction"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#C49A5A",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "persist-cost-label"},
                fontFace = "Berling",
                fontSize = 14,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
                bold = true,
            },
            {
                selectors = {"label", "persist-cost-label", "persist-cannot-afford"},
                color = "#D53031",
            },
            {
                selectors = {"panel", "persist-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "persist-chips-wrap"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                bmargin = 2,
            },
            {
                selectors = {"panel", "persist-chip"},
                height = "auto",
                minHeight = 22,
                width = "auto",
                halign = "left",
                valign = "top",
                hpad = 8,
                vpad = 4,
                margin = 3,
                flow = "horizontal",
                bgimage = "panels/square.png",
                border = 1,
                borderColor = "#5C6860",
                bgcolor = "clear",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "persist-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "persist-chip", "persist-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"label", "persist-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "persist-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "persist-submit"},
                width = 130,
                height = 30,
                halign = "right",
                rmargin = 8,
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#966D4B",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "persist-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "persist-cancel"},
                width = 130,
                height = 30,
                halign = "right",
                bgimage = "panels/square.png",
                bgcolor = "#040807",
                border = 1,
                borderColor = "#5C6860",
                cornerRadius = 4,
            },
            {
                selectors = {"panel", "persist-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "persist-button-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
            },
        },

        children = mainChildren,
    }

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    if canceled then
        return
    end

end

function ActivatedAbilityPersistenceCastBehavior:Cast(ability, casterToken, targets, options)
    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(self.token, self.ability, self.token, 'inherit', {}, { targets = self.targets })
end
