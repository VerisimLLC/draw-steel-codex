--- Confirmation Dialog - Reusable confirmation dialog for modal windows
--- Provides consistent confirmation UI with standardized styling
--- @class DTConfirmationDialog
DTConfirmationDialog = RegisterGameType("DTConfirmationDialog")

local WIDTH = 500
local HEIGHT = 220

--- Private helper to create the panel structure
--- @param title string The dialog title text
--- @param message string The main confirmation message
--- @param confirmButtonText string Text for the confirm button
--- @param cancelButtonText string Text for the cancel button
--- @param onConfirm function|nil Runs when the user confirms
--- @param onCancel function|nil Runs when the user cancels, escapes or closes
--- @param closeMode string How the shell closes: "modal" or "destroy"
--- @return table panel The GUI panel structure
function DTConfirmationDialog._createPanel(title, message, confirmButtonText, cancelButtonText, onConfirm, onCancel, closeMode)
    -- Set default button text if not provided or empty
    confirmButtonText = (confirmButtonText and confirmButtonText ~= "") and confirmButtonText or "Confirm"
    cancelButtonText = (cancelButtonText and cancelButtonText ~= "") and cancelButtonText or "Cancel"

    -- Every way out but the confirm button means cancel, so cancelling is what
    -- the shell does on its way out unless confirm has said otherwise.
    local confirmed = false

    local dlg = DialogShell.CreateNew{
        title = title,
        width = WIDTH,
        height = HEIGHT,
        footerCells = {50, 50},
        close = closeMode,
        escape = true,
        floating = true,

        onClose = function()
            if not confirmed and onCancel ~= nil then
                onCancel()
            end
        end,
    }

    dlg:SetWorkingContent{
        gui.Label{
            classes = {"modalMessage"},
            width = "94%",
            height = "100%",
            halign = "center",
            valign = "center",
            textWrap = true,
            text = message,
        },
    }

    dlg:AddFooterButton{
        slot = "left",
        text = cancelButtonText,
        click = function(shell)
            shell:Close()
        end,
    }

    dlg:AddFooterButton{
        slot = "right",
        text = confirmButtonText,
        click = function(shell)
            confirmed = true
            if onConfirm ~= nil then
                onConfirm()
            end
            shell:Close()
        end,
    }

    return dlg:Root()
end

--- Shows a generic confirmation dialog with customizable title and message
--- @param title string The title text for the dialog header
--- @param message string The main confirmation message text
--- @param confirmButtonText string Optional text for the confirm button (default: "Confirm")
--- @param cancelButtonText string Optional text for the cancel button (default: "Cancel")
--- @param onConfirm function Callback function to execute if user confirms
--- @param onCancel function|nil Optional callback function to execute if user cancels
function DTConfirmationDialog.ShowModal(title, message, confirmButtonText, cancelButtonText, onConfirm, onCancel)
    gui.ShowModal(DTConfirmationDialog._createPanel(title, message, confirmButtonText,
        cancelButtonText, onConfirm, onCancel, "modal"))
end

--- Creates a confirmation dialog panel for AddChild usage
--- @param title string The dialog title text
--- @param message string The main confirmation message
--- @param confirmButtonText string Text for the confirm button
--- @param cancelButtonText string Text for the cancel button
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTConfirmationDialog.CreateAsChild(title, message, confirmButtonText, cancelButtonText, callbacks)
    callbacks = callbacks or {}

    return DTConfirmationDialog._createPanel(title, message, confirmButtonText,
        cancelButtonText, callbacks.confirm, callbacks.cancel, "destroy")
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
