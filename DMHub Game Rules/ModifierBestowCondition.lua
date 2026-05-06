local mod = dmhub.GetModLoading()


CharacterModifier.RegisterType('bestowcondition', "Bestow Condition")

CharacterModifier.TypeInfo.bestowcondition = {

	init = function(modifier)
		modifier.conditionid = 'none'
    end,

    bestowConditions = function(modifier, creature, conditionsRecorded, conditionExplanations)
        if modifier.conditionid ~= 'none' then
            if creature ~= nil then
                local immunities = creature:GetConditionImmunities()
                if not immunities[modifier.conditionid] then
                     conditionsRecorded[modifier.conditionid] = (tonumber(conditionsRecorded[modifier.conditionid] or 0) or 1) + 1
                     if conditionExplanations and modifier:try_get("explanation", "") ~= "" then
                        conditionExplanations[modifier.conditionid] = modifier.explanation
                     end
                end
            end
        end
    end,

    createEditor = function(modifier, element)
        local Refresh

        local firstRefresh = true

        Refresh = function()
            if firstRefresh then
                firstRefresh = false
            else
                element:FireEvent("refreshModifier")
            end

            local children = {}
			children[#children+1] = modifier:FilterConditionEditor()

            local options = {
                {
                    id = "none",
                    text = "(None)",
                }
            }

            local conditionsTable = dmhub.GetTable(CharacterCondition.tableName)
            for key,conditionInfo in pairs(conditionsTable or {}) do
                if conditionInfo:try_get("hidden", false) == false then
                    options[#options+1] = {
                        id = key,
                        text = conditionInfo.name,
                    }
                end
            end

            children[#children+1] = gui.Panel{
                classes = {'formPanel'},
                children = {
                    gui.Label{
                        text = 'Bestow:',
                        classes = {'formLabel'},
                    },
                    gui.Dropdown{
                        styles = ThemeEngine.GetStyles(),
                        selfStyle = {
                            height = 30,
                            width = 260,
                            fontSize = 16,
                        },
                        options = options,
                        sort = true,

                        idChosen = modifier.conditionid,

                        events = {
                            change = function(element)
                                modifier.conditionid = element.idChosen
                                Refresh()
                            end,
                        },
                    },
                }
            }

            children[#children+1] = gui.Panel{
                classes = {"formPanel"},
                gui.Label{
                    text = "Explanation:",
                    classes = {"formLabel"},
                },
                gui.Input{
                    height = "auto",
                    maxHeight = 80,
                    minHeight = 20,
                    width = 400,
                    fontSize = 16,
                    textAlignment = "topleft",
                    multiline = true,
                    text = modifier:try_get("explanation", ""),
                    events = {
                        change = function(element)
                            modifier.explanation = element.text
                            Refresh()
                        end,
                    },

                }
            }

            element.children = children
        end

        Refresh()
    end,
}