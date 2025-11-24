--- Confirmation Dialog - Reusable confirmation dialog for modal windows
--- Provides consistent confirmation UI with standardized styling
--- @class DTConfirmationDialog
DTConfirmationDialog = RegisterGameType("DTConfirmationDialog")
DTConfirmationDialog.__index = DTConfirmationDialog

--- Shows a generic confirmation dialog with customizable title and message
--- @param title string The title text for the dialog header
--- @param message string The main confirmation message text
--- @param confirmButtonText string Optional text for the confirm button (default: "OK")
--- @param cancelButtonText string Optional text for the cancel button (default: "Cancel")
--- @param onConfirm function Callback function to execute if user confirms
--- @param onCancel function|nil Optional callback function to execute if user cancels (default: just close dialog)
function DTConfirmationDialog.ShowModal(title, message, confirmButtonText, cancelButtonText, onConfirm, onCancel)
    local confirmHandler = function(element)
        gui.CloseModal()
        if onConfirm then
            onConfirm()
        end
    end

    local cancelHandler = function(element)
        gui.CloseModal()
        if onCancel then
            onCancel()
        end
    end

    local confirmationWindow = DTConfirmationDialog._createPanel(title, message, confirmButtonText, cancelButtonText, confirmHandler, cancelHandler)
    gui.ShowModal(confirmationWindow)
end

--- Shows a standardized delete confirmation dialog
--- @param message string Text to place after `are you sure you want to delete...`
--- @param onConfirm function Callback function to execute if user confirms deletion
--- @param onCancel function Optional callback function to execute if user cancels (default: just close dialog)
function DTConfirmationDialog.ShowDeleteModal(message, onConfirm, onCancel)
    local title = "Delete Confirmation"
    local displayMessage = string.format("Are you sure you want to delete %s?", message or "this item")

    DTConfirmationDialog.ShowModal(title, displayMessage, "Delete", "Cancel", onConfirm, onCancel)
end

--- Private helper to create the panel structure
--- @param title string The dialog title text
--- @param message string The main confirmation message
--- @param confirmButtonText string Text for the confirm button
--- @param cancelButtonText string Text for the cancel button
--- @param confirmHandler function Handler function for confirm button click
--- @param cancelHandler function Handler function for cancel button click and escape
--- @return table panel The GUI panel structure
function DTConfirmationDialog._createPanel(title, message, confirmButtonText, cancelButtonText, confirmHandler, cancelHandler)
    -- Set default button text if not provided or empty
    confirmButtonText = (confirmButtonText and confirmButtonText ~= "") and confirmButtonText or "Confirm"
    cancelButtonText = (cancelButtonText and cancelButtonText ~= "") and cancelButtonText or "Cancel"

    local resultPanel = nil
    resultPanel = gui.Panel {
        styles = DTHelpers.GetDialogStyles(),
        classes = {"confirmDialogController", "DTDialog"}, --"DTPanel", "DTBase"},
        width = 400,
        height = 200,
        floating = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        data = {
            close = function()
                resultPanel:DestroySelf()
            end,
        },

        close = function(element)
            element.data.close()
        end,

        escape = function(element)
            cancelHandler()
            element:FireEvent("close")
        end,

        children = {
            -- Header
            gui.Label{
                classes = {"DTLabel", "DTBase"},
                text = title,
                fontSize = 24,
                width = "100%",
                height = 30,
                textAlignment = "center",
                halign = "center"
            },
            gui.Divider { width = "50%" },

            -- Confirmation message
            gui.Label{
                text = message,
                width = "100%",
                height = 80,
                classes = {"DTLabel", "DTBase"},
                textAlignment = "center",
                textWrap = true,
                halign = "center",
                valign = "center"
            },

            -- Button panel
            gui.Panel{
                classes = {"DTPanel", "DTBase"},
                width = "100%",
                height = 40,
                halign = "center",
                valign = "center",
                borderColor = "red",
                children = {
                    gui.Button{
                        text = cancelButtonText,
                        width = 120,
                        classes = {"DTButton", "DTBase"},
                        click = function(element)
                            local controller = element:FindParentWithClass("confirmDialogController")
                            if controller then
                                controller:FireEvent("escape")
                            end
                        end
                    },
                    gui.Button{
                        text = confirmButtonText,
                        width = 120,
                        halign = "right",
                        classes = {"DTButton", "DTBase"},
                        click = function(element)
                            local controller = element:FindParentWithClass("confirmDialogController")
                            confirmHandler()
                            if controller then controller:FireEvent("close") end
                        end
                    }
                }
            }
        },
    }

    return resultPanel
end

--- Creates a confirmation dialog panel for AddChild usage
--- @param title string The dialog title text
--- @param message string The main confirmation message
--- @param confirmButtonText string Text for the confirm button
--- @param cancelButtonText string Text for the cancel button
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTConfirmationDialog.CreateAsChild(title, message, confirmButtonText, cancelButtonText, callbacks)
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

    return DTConfirmationDialog._createPanel(title, message, confirmButtonText, cancelButtonText, confirmHandler, cancelHandler)
end

--- Creates a delete confirmation dialog panel for AddChild usage
--- @param message string Text to place after `are you sure you want to delete...`
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTConfirmationDialog.ShowDeleteAsChild(message, callbacks)
    local title = "Delete Confirmation"
    local displayMessage = string.format("Are you sure you want to delete %s?", message or "this item")

    return DTConfirmationDialog.CreateAsChild(title, displayMessage, "Delete", "Cancel", callbacks)
end