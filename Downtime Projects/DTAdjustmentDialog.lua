--- Progress adjustment editing dialog for modifying DTAdjustment instances
--- Provides consistent UI for editing adjustment amount and reason with validation
--- @class DTAdjustmentDialog
DTAdjustmentDialog = RegisterGameType("DTAdjustmentDialog")

local WIDTH = 500
local HEIGHT = 280

--- @param reason string|nil
--- @return string
local function Trimmed(reason)
    return string.match(reason or "", "^%s*(.-)%s*$") or ""
end

--- Private helper to create the adjustment dialog panel structure
--- @param adjustment DTAdjustment The adjustment instance to edit
--- @param onConfirm function|nil Runs once the edit has been written back
--- @param onCancel function|nil Runs when the user cancels, escapes or closes
--- @return table panel The GUI panel structure
function DTAdjustmentDialog._createPanel(adjustment, onConfirm, onCancel)
    local currentAmount = adjustment:GetAmount()
    local currentReason = adjustment:GetReason()
    local confirmed = false

    --Forward declared: the two fields re-run the footer's Save predicate as
    --they are edited.
    local dlg

    local amountInput = gui.Label{
        id = "adjustmentAmountInput",
        classes = {"number", "bordered"},
        editable = true,
        numeric = true,
        characterLimit = 4,
        swallowPress = true,
        text = tostring(currentAmount),
        width = 90,
        height = 24,
        cornerRadius = 4,
        fontSize = 20,
        bgimage = true,
        border = 1,
        textAlignment = "center",
        valign = "center",
        halign = "left",

        change = function(element)
            local numericValue = tonumber(element.text) or tonumber(element.text:match("%-?%d+")) or 0
            element.text = tostring(numericValue)
            currentAmount = numericValue
            dlg:RefreshFooter()
        end,
    }

    local reasonInput = gui.Input{
        id = "adjustmentReason",
        classes = {"form"},
        text = currentReason,
        width = "100%",
        placeholderText = "Enter the reason for the adjustment...",
        editlag = 0.5,

        edit = function(element)
            element:FireEvent("change")
        end,

        change = function(element)
            currentReason = element.text
            dlg:RefreshFooter()
        end,
    }

    dlg = DialogShell.CreateNew{
        title = "New Project Adjustment",
        width = WIDTH,
        height = HEIGHT,
        footerCells = {50, 50},
        close = "destroy",
        escape = true,
        floating = true,

        onClose = function()
            if not confirmed and onCancel ~= nil then
                onCancel()
            end
        end,
    }

    dlg:SetWorkingContent{
        gui.Panel{
            width = "90%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            vmargin = 8,

            gui.Label{
                classes = {"form"},
                text = "Adjustment Amount:",
                width = "100%",
            },

            amountInput,
        },

        gui.Panel{
            width = "90%",
            height = "auto",
            flow = "vertical",
            halign = "center",
            vmargin = 8,

            gui.Label{
                classes = {"form"},
                text = "Reason:",
                width = "100%",
            },

            reasonInput,
        },
    }

    dlg:AddFooterButton{
        slot = "left",
        text = "Cancel",
        click = function(shell)
            shell:Close()
        end,
    }

    dlg:AddFooterButton{
        slot = "right",
        text = "Save",
        enabled = function()
            return Trimmed(currentReason) ~= ""
        end,
        click = function(shell)
            local reason = Trimmed(currentReason)
            if currentAmount == 0 or reason == "" then
                return
            end

            adjustment:SetAmount(currentAmount)
            adjustment:SetReason(reason)

            confirmed = true
            if onConfirm ~= nil then
                onConfirm()
            end
            shell:Close()
        end,
    }

    return dlg:Root()
end

--- Creates a progress adjustment edit dialog for AddChild usage
--- @param adjustment DTAdjustment The adjustment instance to edit
--- @param callbacks table Table with confirm and cancel callback functions
--- @return table panel The GUI panel ready for AddChild
function DTAdjustmentDialog.CreateAsChild(adjustment, callbacks)
    callbacks = callbacks or {}

    return DTAdjustmentDialog._createPanel(adjustment, callbacks.confirm, callbacks.cancel)
end
