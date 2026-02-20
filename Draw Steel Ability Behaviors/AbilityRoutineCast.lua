local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRoutineControlBehavior:ActivatedAbilityBehavior
RegisterGameType("ActivatedAbilityRoutineControlBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityRoutineControlBehavior.summary = "Routine Control"
ActivatedAbilityRoutineControlBehavior.triggerOnly = true

ActivatedAbility.RegisterType
{
	id = 'rouitineControl',
	text = 'Routine Control',
	createBehavior = function()
		return ActivatedAbilityRoutineControlBehavior.new{
		}
	end
}

function ActivatedAbilityRoutineControlBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	return result
end

function ActivatedAbilityRoutineControlBehavior:Cast(ability, casterToken, targets, options)

    local resultPanel = nil
    local finished = false
    local canceled = false

    local caster = casterToken.properties
    local numRoutines = caster:CalculateNamedCustomAttribute("Num Routines")

    -- Load saved routines from token properties and make a copy
    local selectedRoutines = {}
    local savedRoutines = caster.routinesSelected or {}
    for guid, timestamp in pairs(savedRoutines) do
        -- Ensure timestamp is a number for comparison
        selectedRoutines[guid] = tonumber(timestamp) or ServerTimestamp()
    end

    local createRoutineAbilityPanel = function(ability)
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
                text = ability.name,
                color = Styles.textColor,
                height = 16,
                width = "auto",
                valign = "center",
                fontSize = 16,

                hover = gui.Tooltip(ability.effect)
            },
            gui.Button{
                classes = {'effect-button'},
                halign = "center",
                text = "Select",
                click = function(element)
                    -- Toggle selection
                    if selectedRoutines[ability.guid] then
                        -- Deselect
                        selectedRoutines[ability.guid] = nil
                        element:RemoveClass("selected")
                    else
                        -- Count current selections
                        local selectedCount = 0
                        for _ in pairs(selectedRoutines) do
                            selectedCount = selectedCount + 1
                        end
                        
                        -- Only allow selection if under the limit
                        if selectedCount < numRoutines then
                            selectedRoutines[ability.guid] = ServerTimestamp()
                            element:AddClass("selected")
                        end
                    end
                end,

                create = function(element)
                    if selectedRoutines[ability.guid] then
                        element:AddClass("selected")
                    end
                end,
            },
        }

        return abilityPanel
    end


    local routineAbilities = caster:GetRoutines()
    local routineAbilityPanel = nil
    routineAbilityPanel = gui.Panel{
        id = "routineAbilityPanel",
        width = "auto",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",

        create = function(element)
            local children = {}
            for _, ability in pairs(routineAbilities or {}) do
                local abilityEntry = createRoutineAbilityPanel(ability)
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
                classes = {'effect-button' , 'selected', 'hover'},
                borderColor = 'white',
				borderWidth = 2,
				bgcolor = '#da3636',
            },
            {
                classes = {'routine-label'},
                color = Styles.textColor,
                valign = "top",
                width = "auto",
                fontSize = 20,
                bold = true,
            }
		},

        gui.Panel{
            flow = "vertical",
            width = "90%",
            height = "90%",
            valign = "top",
            halign = "center",
            gui.Label{
                classes = {"routine-label"},
                text = ability.name or "Routine Control",
            },

            routineAbilityPanel,

            gui.Button{
                halign = 'right',
                valign = 'bottom',
                text = 'Submit',
                height = 30,
                width = 160,
                click = function(element)
                    casterToken:ModifyProperties{
                        description = "Routine Selection",
                        execute = function()
                            local selected = casterToken.properties:get_or_add("routinesSelected", {})
                            -- Clear existing selections
                            for k in pairs(selected) do
                                selected[k] = nil
                            end
                            -- Set new selections
                            for guid, timestamp in pairs(selectedRoutines) do
                                selected[guid] = timestamp
                            end
                            casterToken.properties.routinesSelected = selected
                        end,
                    }

                    --instantly refresh the token.
                    game.Refresh{
                        tokens = {casterToken.charid},
                    }
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