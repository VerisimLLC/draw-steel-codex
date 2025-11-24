--- Progress adjustment editing dialog for modifying DTAdjustment instances
--- Provides consistent UI for editing adjustment amount and reason with validation
--- @class DTAdjustmentDialog
DTAdjustmentDialog = RegisterGameType("DTAdjustmentDialog")
DTAdjustmentDialog.__index = DTAdjustmentDialog

--- Creates a progress adjustment edit dialog for AddChild usage
--- @param adjustment DTAdjustment The adjustment instance to edit
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTAdjustmentDialog.CreateAsChild(adjustment, callbacks)
    local confirmHandler = function(element)
        if callbacks.confirm then
            callbacks.confirm()
        end
    end

    local cancelHandler = function(element)
        if callbacks.cancel then
            callbacks.cancel()
        end
    end

    return DTAdjustmentDialog._createPanel(adjustment, confirmHandler, cancelHandler)
end

--- Private helper to create the adjustment dialog panel structure
--- @param adjustment DTAdjustment The adjustment instance to edit
--- @param confirmHandler function Handler function for confirm button click
--- @param cancelHandler function Handler function for cancel button click and escape
--- @return table panel The GUI panel structure
function DTAdjustmentDialog._createPanel(adjustment, confirmHandler, cancelHandler)
    local resultPanel = nil
    resultPanel = gui.Panel {
        classes = {"adjustmentDialogController", "DTDialog"},
        width = 500,
        height = 350,
        styles = DTHelpers.GetDialogStyles(),
        floating = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        data = {
            adjustment = adjustment,
            currentAmount = adjustment:GetAmount(),
            currentReason = adjustment:GetReason(),
            close = function()
                resultPanel:DestroySelf()
            end,
        },

        validateForm = function(element)
            local isValid = false
            local reason = element.data.currentReason or ""

            -- Trim whitespace from reason
            reason = string.match(reason, "^%s*(.-)%s*$") or ""

            isValid = reason ~= ""
            element:FireEventTree("enableSave", isValid)
        end,

        saveAndClose = function(element)
            local amount = element.data.currentAmount or 0
            local reason = element.data.currentReason or ""

            -- Trim whitespace from reason
            reason = string.match(reason, "^%s*(.-)%s*$") or ""

            if amount ~= 0 and reason ~= "" then
                element.data.adjustment:SetAmount(amount)
                element.data.adjustment:SetReason(reason)
                confirmHandler(element)
                element:FireEvent("close")
            end
        end,

        close = function(element)
            element.data.close()
        end,

        escape = function(element)
            cancelHandler(element)
            element:FireEvent("close")
        end,

        create = function(element)
            element:FireEvent("validateForm")
        end,

        adjustAmount = function(element, newValue)
            element.data.currentAmount = newValue
            element:FireEvent("validateForm")
        end,

        children = {
            -- Header
            gui.Label{
                text = "New Project Adjustment",
                fontSize = 24,
                width = "100%",
                height = 30,
                classes = {"DTLabel", "DTBase"},
                textAlignment = "center",
                halign = "center"
            },
            gui.Divider { width = "50%" },

            -- Form content
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "100%",
                height = "100%-110",
                flow = "vertical",
                vmargin = 10,
                children = {
                    -- Amount field with numeric editor
                    gui.Panel{
                        classes = {"DTPanel", "DTBase"},
                        width = "90%",
                        height = "auto",
                        flow = "vertical",
                        vmargin = 10,

                        children = {
                            -- Label
                            gui.Label{
                                text = "Adjustment Amount:",
                                classes = {"DTLabel", "DTBase"},
                                width = "100%",
                                height = 20
                            },
                            -- Input field
                            gui.Label {
                                id = "adjustmentAmountInput",
                                editable = true,
                                numeric = true,
                                characterLimit = 4,
                                swallowPress = true,
                                text = tostring(adjustment:GetAmount()),
                                width = 90,
                                height = 24,
                                cornerRadius = 4,
                                fontSize = 20,
                                bgimage = "panels/square.png",
                                border = 1,
                                textAlignment = "center",
                                valign = "center",
                                halign = "left",
                                classes = {"DTInput", "DTBase"},

                                change = function(element)
                                    local numericValue = tonumber(element.text) or tonumber(element.text:match("%-?%d+")) or 0
                                    element.text = tostring(numericValue)

                                    local controller = element:FindParentWithClass("adjustmentDialogController")
                                    if controller then
                                        controller:FireEvent("adjustAmount", numericValue)
                                    end
                                end
                            }
                        }
                    },

                    -- Reason field
                    gui.Panel{
                        classes = {"DTPanel", "DTBase"},
                        width = "90%",
                        height = 60,
                        flow = "vertical",
                        vmargin = 10,
                        children = {
                            gui.Label{
                                text = "Reason:",
                                classes = {"DTLabel", "DTBase"},
                                width = "100%",
                            },
                            gui.Input{
                                id = "adjustmentReason",
                                text = adjustment:GetReason(),
                                width = "100%",
                                classes = {"DTInput", "DTBase"},
                                placeholderText = "Enter the reason for the adjustment...",
                                editlag = 0.5,
                                edit = function(element)
                                    element:FireEvent("change")
                                end,
                                change = function(element)
                                    local controller = element:FindParentWithClass("adjustmentDialogController")
                                    if controller then
                                        controller.data.currentReason = element.text
                                        controller:FireEvent("validateForm")
                                    end
                                end
                            }
                        }
                    }
                }
            },

            -- Button panel
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "100%",
                height = 40,
                halign = "center",
                valign = "center",
                children = {
                    gui.Button{
                        text = "Cancel",
                        width = 120,
                        classes = {"DTButton", "DTBase"},
                        click = function(element)
                            local controller = element:FindParentWithClass("adjustmentDialogController")
                            if controller then
                                controller:FireEvent("escape")
                            end
                        end
                    },
                    gui.Button{
                        id = "saveButton",
                        text = "Save",
                        width = 120,
                        halign = "right",
                        classes = {"DTButton", "DTBase", "DTDisabled"},
                        interactable = false,
                        enableSave = function(element, enabled)
                            element:SetClass("DTDisabled", not enabled)
                            element.interactable = enabled
                        end,
                        click = function(element)
                            if not element.interactable then return end
                            local controller = element:FindParentWithClass("adjustmentDialogController")
                            if controller then
                                controller:FireEvent("saveAndClose")
                            end
                        end
                    }
                }
            }
        },
    }

    return resultPanel
end
