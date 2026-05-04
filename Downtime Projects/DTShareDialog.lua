--- Share dialog for sharing downtime projects with other characters
--- @class DTShareDialog
DTShareDialog = RegisterGameType("DTShareDialog")

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
    local resultPanel = nil

    resultPanel = gui.Panel {
        classes = {"shareController", "dialog"},
        styles = ThemeEngine.GetStyles(),
        width = 500,
        height = 300,
        flow = "vertical",
        halign = "center",
        valign = "center",
        pad = 4,
        floating = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        data = {
            close = function(element)
                resultPanel:DestroySelf()
            end,
        },

        create = function(element)
        end,

        close = function(element)
            element.data.close(element)
        end,

        escape = function(element)
            options.callbacks.cancelHandler()
            element:FireEvent("close")
        end,

        children = {
            -- Header
            gui.Label{
                classes = {"modalTitle"},
                text = "Share This Project With:",
            },

            -- Content - Character selector
            gui.Panel{
                width = "100%",
                height = "100%-110",
                flow = "vertical",
                vmargin = 10,
                children = {
                    gui.CharacterSelect({
                        id = "characterSelector",
                        allTokens = options.showList,
                        initialSelection = options.initialSelection,
                        width = "96%",
                        height = 130,
                        layout = "grid",
                        showShortcuts = true,
                    })
                }
            },

            -- Button panel
            gui.Panel{
                width = "100%",
                height = 40,
                vmargin = 10,
                halign = "center",
                valign = "bottom",
                flow = "horizontal",
                children = {
                    gui.Button{
                        classes = {"sizeL"},
                        text = "Cancel",
                        valign = "bottom",
                        click = function(element)
                            local controller = element:FindParentWithClass("shareController")
                            if controller then
                                controller:FireEvent("escape")
                            end
                        end,
                    },
                    gui.Button{
                        classes = {"sizeL"},
                        text = "Share",
                        halign = "right",
                        valign = "bottom",
                        click = function(element)
                            local controller = element:FindParentWithClass("shareController")
                            if controller then
                                local selector = controller:Get("characterSelector")
                                local selectedTokenIds = {}
                                if selector and selector.value then
                                    -- Extract just the IDs from the keyed format
                                    for tokenId, value in pairs(selector.value) do
                                        if value.selected then
                                            selectedTokenIds[#selectedTokenIds + 1] = tokenId
                                        end
                                    end
                                end
                                options.callbacks.confirmHandler(selectedTokenIds)
                                controller:FireEvent("close")
                            end
                        end,
                    },
                },
            },
        },
    }

    return resultPanel
end
