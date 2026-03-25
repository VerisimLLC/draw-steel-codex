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

    local finished = false
    local canceled = false

    local caster = casterToken.properties
    local numRoutines = caster:CalculateNamedCustomAttribute("Num Routines")

    -- Load saved routines from token properties and make a copy.
    -- Each entry maps guid -> timestamp (for eviction ordering).
    local selectedRoutines = {}
    local savedRoutines = caster:try_get("routinesSelected", {})
    for guid, timestamp in pairs(savedRoutines) do
        selectedRoutines[guid] = tonumber(timestamp) or ServerTimestamp()
    end

    -- Track chip elements by guid so we can update classes on eviction.
    local chipElements = {}

    -- Helper: find the oldest selected routine guid.
    local function findOldestSelected()
        local oldestGuid = nil
        local oldestTime = nil
        for guid, ts in pairs(selectedRoutines) do
            if oldestTime == nil or ts < oldestTime then
                oldestTime = ts
                oldestGuid = guid
            end
        end
        return oldestGuid
    end

    local routineAbilities = caster:GetRoutines()

    -- Build chip panels for each routine ability.
    local chipPanels = {}
    for _, routineAbility in pairs(routineAbilities or {}) do
        local capturedAbility = routineAbility

        chipPanels[#chipPanels+1] = gui.Panel{
            classes = {"routine-chip"},
            flow = "horizontal",

            press = function(element)
                if selectedRoutines[capturedAbility.guid] then
                    -- Deselect
                    selectedRoutines[capturedAbility.guid] = nil
                    element:SetClass("routine-chip-selected", false)
                else
                    -- Count current selections
                    local selectedCount = 0
                    for _ in pairs(selectedRoutines) do
                        selectedCount = selectedCount + 1
                    end

                    -- If at the limit, evict the oldest
                    if selectedCount >= numRoutines then
                        local oldestGuid = findOldestSelected()
                        if oldestGuid ~= nil then
                            selectedRoutines[oldestGuid] = nil
                            local oldElement = chipElements[oldestGuid]
                            if oldElement ~= nil then
                                oldElement:SetClass("routine-chip-selected", false)
                            end
                        end
                    end

                    selectedRoutines[capturedAbility.guid] = ServerTimestamp()
                    element:SetClass("routine-chip-selected", true)
                end
            end,

            create = function(element)
                chipElements[capturedAbility.guid] = element
                if selectedRoutines[capturedAbility.guid] then
                    element:SetClass("routine-chip-selected", true)
                end
            end,

            hover = function(element)
                element.tooltip = gui.Panel{
                    width = "auto",
                    height = "auto",
                    bgimage = "panels/square.png",
                    bgcolor = "#222222e9",
                    pad = 8,
                    cornerRadius = 4,
                    capturedAbility:Render{token = casterToken, width = 400},
                }
            end,

            gui.Label{
                classes = {"routine-chip-label"},
                text = capturedAbility.name,
            },
        }
    end

    -- Add a "None" chip at the end to clear all selections.
    chipPanels[#chipPanels+1] = gui.Panel{
        classes = {"routine-chip"},
        flow = "horizontal",

        press = function(element)
            -- Clear all selections.
            for guid, _ in pairs(selectedRoutines) do
                selectedRoutines[guid] = nil
                local el = chipElements[guid]
                if el ~= nil then
                    el:SetClass("routine-chip-selected", false)
                end
            end
        end,

        gui.Label{
            classes = {"routine-chip-label"},
            text = "None",
        },
    }

    -- Assemble main content.
    local mainChildren = {}

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"routine-title"},
        text = ability.name or "Routine Control",
    }

    mainChildren[#mainChildren+1] = gui.Label{
        classes = {"routine-count"},
        text = string.format("Select up to %d routines", numRoutines),
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"routine-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"routine-chips-wrap"},
        children = chipPanels,
    }

    mainChildren[#mainChildren+1] = gui.Panel{ classes = {"routine-divider"} }

    mainChildren[#mainChildren+1] = gui.Panel{
        classes = {"routine-button-row"},
        gui.Panel{
            classes = {"routine-submit"},
            press = function(element)
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

                game.Refresh{
                    tokens = {casterToken.charid},
                }
                finished = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"routine-button-label"},
                text = "Submit",
            },
        },
        gui.Panel{
            classes = {"routine-cancel"},
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            press = function(element)
                finished = true
                canceled = true
                gui.CloseModal()
            end,
            gui.Label{
                classes = {"routine-button-label"},
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
                selectors = {"label", "routine-title"},
                fontFace = "Berling",
                fontSize = 18,
                color = "#5C6860",
                width = "auto",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"label", "routine-count"},
                fontFace = "Berling",
                fontSize = 12,
                color = "#C49A5A",
                width = "100%",
                height = "auto",
                halign = "left",
                bmargin = 2,
            },
            {
                selectors = {"panel", "routine-divider"},
                width = "100%",
                height = 1,
                bgimage = "panels/square.png",
                bgcolor = "#5C3D10",
                vmargin = 8,
            },
            {
                selectors = {"panel", "routine-chips-wrap"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                wrap = true,
                bmargin = 2,
            },
            {
                selectors = {"panel", "routine-chip"},
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
                selectors = {"panel", "routine-chip", "hover"},
                brightness = 1.3,
                transitionTime = 0.15,
            },
            {
                selectors = {"panel", "routine-chip", "routine-chip-selected"},
                borderColor = "#966D4B",
                bgcolor = "#5C3D10",
            },
            {
                selectors = {"label", "routine-chip-label"},
                fontFace = "Berling",
                fontSize = 13,
                color = "#FFFEF8",
                width = "auto",
                height = "auto",
                valign = "center",
            },
            {
                selectors = {"panel", "routine-button-row"},
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                tmargin = 4,
            },
            {
                selectors = {"panel", "routine-submit"},
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
                selectors = {"panel", "routine-submit", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"panel", "routine-cancel"},
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
                selectors = {"panel", "routine-cancel", "hover"},
                brightness = 1.25,
                transitionTime = 0.1,
            },
            {
                selectors = {"label", "routine-button-label"},
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