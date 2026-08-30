local mod = dmhub.GetModLoading()

--- Select Item Dialog for choosing the source of a downtime project
--- @class DTSelectItemDialog
DTSelectItemDialog = RegisterGameType("DTSelectItemDialog")

local WIDTH = 500
local HEIGHT = 260
local TAB_BAR_HEIGHT = 28

--- Private helper to create the select item dialog panel structure
--- @param callbacks table Table with wrapped callback functions
--- @return table panel The GUI panel structure
--- @private
function DTSelectItemDialog._createPanel(callbacks)
    local craftableItems = {}
    local allItems = dmhub.GetTableVisible(equipment.tableName)
    for key, item in pairs(allItems) do
        -- Filter items to only craftable items with required properties
        local projectGoal = item:try_get("projectGoal")
        local projectSource = item:try_get("projectSource")
        local itemPrerequisite = item:try_get("itemPrerequisite")
        local projectRollChar = item:try_get("projectRollCharacteristic")

        if projectGoal and type(projectGoal) == "string" and #projectGoal > 0 and
           projectSource and type(projectSource) == "string" and #projectSource > 0 and
           itemPrerequisite and type(itemPrerequisite) == "string" and #itemPrerequisite > 0 and
           projectRollChar and type(projectRollChar) == "table" and next(projectRollChar) ~= nil then
            craftableItems[#craftableItems + 1] = { id = key, text = item.name }
        end
    end
    table.sort(craftableItems, function(a, b) return a.text < b.text end)

    local activityItems = {}
    for key, activity in unhidden_pairs(dmhub.GetTable(DowntimeActivity.tableName) or {}) do
        activityItems[#activityItems + 1] = { id = key, text = activity.name }
    end
    table.sort(activityItems, function(a, b) return a.text < b.text end)

    local sourceLists = {
        crafting = craftableItems,
        activity = activityItems,
    }
    local confirmLabels = {
        crafting = "Start Craft",
        activity = "Start Activity",
    }

    local sourceType = "crafting"
    local confirmed = false

    --Forward declared: the tabs, the dropdown and the confirm button all read
    --one another when the source changes.
    local dlg
    local craftingTab
    local activityTab
    local itemSelector
    local confirmButton

    --- Switches the dialog between the crafting-project and activity sources
    --- @param newSourceType string Either "crafting" or "activity"
    local function SelectSource(newSourceType)
        sourceType = newSourceType

        craftingTab:SetClass("selected", sourceType == "crafting")
        activityTab:SetClass("selected", sourceType == "activity")

        itemSelector.options = {}
        itemSelector.options = sourceLists[sourceType] or {}
        itemSelector.idChosen = nil

        if confirmButton ~= nil then
            confirmButton.text = confirmLabels[sourceType] or "Confirm"
        end

        dlg:RefreshFooter()
    end

    craftingTab = gui.Label{
        classes = {"tab", "selected"},
        text = "Crafting Projects",
        width = "50%",
        height = "100%",
        press = function()
            SelectSource("crafting")
        end,
    }

    activityTab = gui.Label{
        classes = {"tab"},
        text = "Activities",
        width = "50%",
        height = "100%",
        press = function()
            SelectSource("activity")
        end,
    }

    itemSelector = gui.Dropdown{
        id = "itemSelector",
        classes = {"formStacked"},
        options = craftableItems,
        idChosen = nil,
        sort = true,
        hasSearch = true,
        textDefault = "Select an item...",
        change = function()
            dlg:RefreshFooter()
        end,
    }

    dlg = DialogShell.CreateNew{
        title = "Select a Project Source",
        width = WIDTH,
        height = HEIGHT,
        footerCells = {50, 50},
        close = "destroy",
        escape = true,
        floating = true,

        onClose = function()
            if not confirmed then
                callbacks.cancelHandler()
            end
        end,
    }

    -- The tab strip is the card's header and the selection sits in its body,
    -- so the two read as one bordered form rather than a bar floating above a
    -- field. featureCardBody carries the sides, the bottom and the rounding.
    dlg:SetWorkingContent{
        gui.Panel{
            classes = {"featureCard"},
            width = "94%",
            height = "100% available",
            halign = "center",
            tmargin = 12,

            gui.Panel{
                classes = {"tabBar"},
                width = "100%",
                height = TAB_BAR_HEIGHT,

                craftingTab,
                activityTab,
            },

            -- Against the card rather than "100% available": the card's own
            -- height is available-derived, and a nested available has nothing
            -- definite to resolve against, so the body falls back to auto and
            -- its border stops short of the fill behind it.
            gui.Panel{
                classes = {"featureCardBody"},
                height = string.format("100%%-%d", TAB_BAR_HEIGHT),

                gui.Label{
                    classes = {"formStacked"},
                    text = "Selection",
                },

                itemSelector,
            },
        },
    }

    dlg:AddFooterButton{
        slot = "left",
        text = "Custom",
        click = function(shell)
            shell:Close()
        end,
    }

    confirmButton = dlg:AddFooterButton{
        slot = "right",
        text = confirmLabels[sourceType],
        enabled = function()
            return itemSelector.idChosen ~= nil and itemSelector.idChosen ~= ""
        end,
        click = function(shell)
            confirmed = true
            callbacks.confirmHandler(sourceType, itemSelector.idChosen)
            shell:Close()
        end,
    }

    SelectSource("crafting")

    return dlg:Root()
end

--- Creates a select item dialog for AddChild usage
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTSelectItemDialog.CreateAsChild(callbacks)
    if not callbacks then callbacks = {} end

    callbacks.confirmHandler = function(sourceType, selectedId)
        if callbacks and callbacks.confirm then
            callbacks.confirm(sourceType, selectedId)
        end
    end

    callbacks.cancelHandler = function()
        if callbacks and callbacks.cancel then
            callbacks.cancel()
        end
    end

    return DTSelectItemDialog._createPanel(callbacks)
end
