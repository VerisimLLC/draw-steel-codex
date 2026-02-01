local mod = dmhub.GetModLoading()

Persistence = RegisterGameType("Persistence")
Persistence.name = ""

--- @class ActivatedAbilityPersistenceControlBehavior:ActivatedAbilityBehavior
RegisterGameType("ActivatedAbilityPersistenceControlBehavior", "ActivatedAbilityBehavior")

--- @class ActivatedAbilityPersistenceCastBehavior:ActivatedAbilityBehavior
RegisterGameType("ActivatedAbilityPersistenceCastBehavior", "ActivatedAbilityBehavior")

RegisterGoblinScriptSymbol(creature, {
	name = "Persistent Abilities",
	type = "number",
	desc = "The number of persistent abilities that this creature has active.",
	examples = {'self.Persistent Abilities < 1'},
	calculate = function(c)
        local persistentAbilities = c:try_get("persistentAbilities", {})
        return #persistentAbilities
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

    local resultPanel = nil
    local finished = false
    local canceled = false

    local caster = casterToken:GetCreature()
    local casterClasses = caster:GetClassesAndSubClasses()
    local startOfTurnHeroicResource = 0
    for _, classInfo in pairs(casterClasses) do
        local heroicResource = classInfo.class:get_or_add("heroicResourceChecklist", {})
        for _, resourceInfo in pairs(heroicResource) do
            if string.lower(resourceInfo.name or "") == "start of turn" then
                startOfTurnHeroicResource = tonumber(resourceInfo.quantity) or 0
            end
        end
    end

    startOfTurnHeroicResource = tonumber(dmhub.EvalGoblinScript(startOfTurnHeroicResource, caster:LookupSymbol(), string.format("Calculating Start of Turn Resources")))

    local stopPresistence = {}

    local createPersistenceAbilityPanel = function(ability)
        local abilityPanel = gui.Panel{
            width = "auto",
            height = 35,
            halign = "left",
            flow = "horizontal",
            vmargin = 3,
            data = {
                ability = ability,
            },
            gui.Label{
                text = ability.abilityName,
                color = Styles.textColor,
                width = "auto",
                valign = "center",
                fontSize = 16,
            },
            gui.Button{
                classes = {'effect-button'},
                halign = "center",
                text = "Stop",
                click = function(element)
                    if stopPresistence[ability.guid] then
                        stopPresistence[ability.guid] = nil
                    else
                        stopPresistence[ability.guid] = true
                    end
                    if element:HasClass("selected") then
                        element:RemoveClass("selected")
                    else
                        element:AddClass("selected")
                    end

                    element:Get("expectedCostLabel"):FireEvent("refreshCost")
                end,
            },
        }

        return abilityPanel
    end


    local persistenceAbilities = casterToken.properties:try_get("persistentAbilities")
    local persistenceAbilityPanel = nil
    persistenceAbilityPanel = gui.Panel{
        id = "persistenceAbilityPanel",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",

        create = function(element)
            local children = {}
            for _, ability in pairs(persistenceAbilities or {}) do
                local abilityEntry = createPersistenceAbilityPanel(ability)
                children[#children+1] = abilityEntry
            end
            element.children = children
        end,
    }

    resultPanel = gui.Panel{
        classes = {"framedPanel"},
        bgimage = 'panels/square.png',
        bgcolor = Styles.backgroundColor,
        borderColor = Styles.textColor,
        borderWidth = 2,
        width = 550,
        height = 550,

        styles = {
            {
                classes = {'effect-button'},
                width = "auto",
                height = "auto",
                halign = "left",
                fontSize = 14,
                margin = 4,
                pad = 2,
            },
            {
                classes = {'effect-button' , 'selected'},
                borderColor = 'white',
				borderWidth = 2,
				bgcolor = '#882222',
            },
            {
                classes = {"persist-label"},
                color = Styles.textColor,
                valign = "top",
                width = "auto",
                fontSize = 20,
                bold = true,
            },
            {
                classes = {"persist-label",  "cannot-afford"},
                color = "red",
            },
		},

        gui.Panel{
            flow = "vertical",
            width = "90%",
            height = "90%",
            valign = "top",
            halign = "center",
            gui.Label{
                classes = {"persist-label"},
                text = ability.name or "Persistence Control",
            },

            gui.Label{
                id = "expectedCostLabel",
                classes = {"persist-label"},

                refreshCost = function(element)
                    local expectedCost = 0
                    for _, ability in pairs(persistenceAbilities or {}) do
                        if not stopPresistence[ability.guid] then
                            expectedCost = expectedCost + (ability.cost or 0)
                        end
                    end

                    element.text = string.format("Essence Gained: %d", startOfTurnHeroicResource - expectedCost)

                    if expectedCost > startOfTurnHeroicResource then
                        element:AddClass("cannot-afford")
                    else
                        element:RemoveClass("cannot-afford")
                    end
                end,

                create = function(element)
                    element:FireEvent("refreshCost")
                end,
            },

            persistenceAbilityPanel,

            gui.Button{
                halign = 'right',
                valign = 'bottom',
                text = 'Submit',
                height = 30,
                width = 160,
                click = function(element)
                    for guid, _ in pairs(stopPresistence) do
                        casterToken.properties:EndPersistentAbilityById(guid)
                    end

                    local selectedCost = 0
                    for _, ability in pairs(persistenceAbilities or {}) do
                        selectedCost = selectedCost + (ability.cost or 0)
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
            },
            gui.Button{
                halign = 'right',
                valign = 'bottom',
                text = 'Cancel',
                width = 160,
                escapeActivates = true,
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                click = function(element)
                    finished = true
                    canceled = true
                    gui.CloseModal()
                end,
            },
        },

    }

    gui.ShowModal(resultPanel)

    while not finished do
        coroutine.yield(0.1)
    end

    --Canceling stops the ability from executing
    if canceled then
        return
    end

end

function ActivatedAbilityPersistenceCastBehavior:Cast(ability, casterToken, targets, options)
    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(self.token, self.ability, self.token, 'inherit', {}, { targets = self.targets })
end