--- Share dialog for sharing downtime projects with other characters
--- @class DTShareDialog
DTShareDialog = RegisterGameType("DTShareDialog")

local WIDTH = 500
local HEIGHT = 300
local SELECTOR_HEIGHT = 130

--- Creates a share dialog for AddChild usage
--- @param options table Table with data, options, and callback functions
--- @return table|nil panel The GUI panel ready for AddChild
function DTShareDialog.CreateAsChild(options)
    if not options then return end
    if not options.callbacks then options.callbacks = {} end

    options.callbacks.confirmHandler = function(selectedTokenIds)
        if options.callbacks and options.callbacks.confirm then
            options.callbacks.confirm(selectedTokenIds)
        end
    end

    options.callbacks.cancelHandler = function()
        if options.callbacks and options.callbacks.cancel then
            options.callbacks.cancel()
        end
    end

    return DTShareDialog._createPanel(options)
end

--- Private helper to create the share dialog panel structure
--- @param options table Table with data, options, and callback functions
--- @return table panel The GUI panel structure
function DTShareDialog._createPanel(options)
    -- Escape and Cancel both cancel, so cancelling is what the shell does on
    -- the way out unless the Share path has said otherwise.
    local confirmed = false

    local selector = gui.CharacterSelect({
        id = "characterSelector",
        allTokens = options.showList,
        initialSelection = options.initialSelection,
        halign = "center",
        width = "96%",
        height = SELECTOR_HEIGHT,
        layout = "grid",
        showShortcuts = true,
    })

    local dlg = DialogShell.CreateNew{
        title = "Share Project",
        subtitle = "Select other heroes to help you.",
        width = WIDTH,
        height = HEIGHT,
        footerCells = {50, 50},
        close = "destroy",
        escape = true,
        floating = true,

        onClose = function()
            if not confirmed then
                options.callbacks.cancelHandler()
            end
        end,
    }

    dlg:SetWorkingContent{
        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "vertical",
            halign = "center",
            valign = "center",

            selector,
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
        text = "Share",
        click = function(shell)
            local selectedTokenIds = {}
            if selector and selector.value then
                -- Extract just the IDs from the keyed format
                for tokenId, value in pairs(selector.value) do
                    if value.selected then
                        selectedTokenIds[#selectedTokenIds + 1] = tokenId
                    end
                end
            end

            confirmed = true
            options.callbacks.confirmHandler(selectedTokenIds)
            shell:Close()
        end,
    }

    return dlg:Root()
end
