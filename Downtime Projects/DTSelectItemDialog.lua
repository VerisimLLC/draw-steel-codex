local mod = dmhub.GetModLoading()

--- Select Item Dialog for choosing a crafting item
--- @class DTSelectItemDialog
DTSelectItemDialog = RegisterGameType("DTSelectItemDialog")
DTSelectItemDialog.__index = DTSelectItemDialog

--- Creates a select item dialog for AddChild usage
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTSelectItemDialog.CreateAsChild(callbacks)
    if not callbacks then callbacks = {} end

    callbacks.confirmHandler = function(selectedItemId)
        if callbacks and callbacks.confirm then
            callbacks.confirm(selectedItemId)
        end
    end

    callbacks.cancelHandler = function()
        if callbacks and callbacks.cancel then
            callbacks.cancel()
        end
    end

    return DTSelectItemDialog._createPanel(callbacks)
end

--- Private helper to create the select item dialog panel structure
--- @param callbacks table Table with wrapped callback functions
--- @return table panel The GUI panel structure
--- @private
function DTSelectItemDialog._createPanel(callbacks)
    local resultPanel = nil

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

    local itemSelector = DTUIComponents.CreateLabeledDropdown(
        "Item to Craft",
        {
            id = "itemSelector",
            options = craftableItems,
            idChosen = nil,
            sort = true,
            hasSearch = true,
            textDefault = "Select an item...",
            change = function(element)
                local controller = element:FindParentWithClass("selectItemDialogController")
                if controller then
                    controller:FireEvent("validateForm")
                end
            end
        },
        {
            width = "100%",
            halign = "center",
        }
    )

    resultPanel = gui.Panel {
        classes = {"selectItemDialogController", "DTDialog"},
        width = 400,
        height = 200,
        styles = DTHelpers.GetDialogStyles(),
        floating = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        data = {
            close = function(element)
                resultPanel:DestroySelf()
            end,
        },

        validateForm = function(element)
            local dropdown = element:Get("itemSelector")
            local enabled = dropdown and dropdown.idChosen ~= nil and dropdown.idChosen ~= ""
            element:FireEventTree("enableConfirm", enabled)
        end,

        create = function(element)
            element:FireEvent("validateForm")
        end,

        close = function(element)
            element.data.close(element)
        end,

        escape = function(element)
            callbacks.cancelHandler()
            element:FireEvent("close")
        end,

        children = {
            -- Header
            gui.Label{
                classes = {"DTLabel", "DTBase"},
                text = "Select Crafting Item",
                fontSize = 24,
                width = "100%",
                height = 30,
                textAlignment = "center",
                halign = "center"
            },
            gui.Divider { width = "50%" },

            -- Content
            itemSelector,

            -- Button panel
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "100%",
                height = 40,
                halign = "center",
                valign = "center",
                children = {
                    gui.Button{
                        classes = {"DTButton", "DTBase"},
                        text = "Cancel",
                        width = 120,
                        halign = "center",
                        click = function(element)
                            local controller = element:FindParentWithClass("selectItemDialogController")
                            if controller then
                                controller:FireEvent("escape")
                            end
                        end
                    },
                    gui.Button{
                        classes = {"DTButton", "DTBase", "DTDisabled"},
                        text = "Confirm",
                        width = 120,
                        halign = "center",
                        interactable = false,
                        enableConfirm = function(element, enabled)
                            element:SetClass("DTDisabled", not enabled)
                            element.interactable = enabled
                        end,
                        click = function(element)
                            if not element.interactable then return end
                            local controller = element:FindParentWithClass("selectItemDialogController")
                            if controller then
                                local dropdown = controller:Get("itemSelector")
                                local selectedItemId = dropdown and dropdown.idChosen or nil
                                callbacks.confirmHandler(selectedItemId)
                                controller:FireEvent("close")
                            end
                        end
                    }
                }
            }
        },
    }

    return resultPanel
end
