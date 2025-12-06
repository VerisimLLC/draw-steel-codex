local mod = dmhub.GetModLoading()

local actionButtonStyles = {
    {
        selectors = {"action-button", "hover"},
        brightness = 1.05,
    },
    {
        selectors = {"action-button", "press"},
        scale = 0.98,
    },
    {
        selectors = {"action-button-base"},
        borderColor = "#BC9B7B",
    },
    {
        selectors = {"action-button-label"},
        color = "#966D4B",
    },
    {
        selectors = {"unavailable"},
        borderColor = "#666663",
        color = "#666663",
    },
}

local function _actionButton(options)
    local opts = dmhub.DeepCopy(options or {})

    local mainPanel

    local styles = actionButtonStyles
    if opts.styles and #opts.styles > 0 then
        table.move(opts.styles, 1, #opts.styles, #styles + 1, styles)
    end
    opts.styles = styles

    local classes = {"action-button"}
    if opts.classes and #opts.classes > 0 then
        table.move(opts.classes, 1, #opts.classes, #classes + 1, classes)
    end
    opts.classes = classes

    local data = {
        available = opts.available or false,
        selected = opts.selected or false,
    }
    opts.data = opts.data or {}
    for k,v in pairs(data) do
        opts.data[k] = v
    end
    opts.available = nil
    opts.selected = nil

    opts.width = 225
    opts.height = 52
    opts.halign = opts.halign or "center"
    opts.valign = opts.valign or "center"

    local fnCreate = (opts.create and type(opts.create) == "function") and opts.create or nil
    opts.create = function(element, ...)
        if fnCreate then fnCreate(element, ...) end
        element:FireEvent("setAvailable", element.data.available)
        element:FireEvent("setSelected", element.data.selected)
    end

    opts.setAvailable = function(element, available)
        element.data.available = available
        element.interactable = available
        element:FireEventTree("_setAvailable", available)
    end

    opts.setSelected = function(element, selected)
        element.data.selected = selected
        element:FireEventTree("_setSelected", selected)
    end

    opts.setText = function(element, newText)
        element:FireEventTree("_setText", newText)
    end

    local labelText = opts.text or ""

    opts.children = {

        gui.Panel{ -- Button Base
            classes = {"action-button-base"},
            width = "100%",
            height = 45,
            valign = "bottom",
            bgimage = "panels/square.png",
            bgcolor = "#000000",
            border = 1,
            borderWidth = 1,
            cornerRadius = 10,
            beveledcorners = true,
            interactable = true,

            _setAvailable = function(element, available)
                element.interactable = available
                element:SetClass("unavailable", not available)
            end,

            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                interactable = false,
                gui.Label{
                    classes = {"action-button-label"},
                    width = "auto",
                    height = "auto",
                    fontFace = "Newzald",
                    fontSize = 18,
                    text = labelText,
                    interactable = false,
                    _setAvailable = function(element, available)
                        element:SetClass("unavailable", not available)
                    end,
                    _setText = function(element, newText)
                        element.text = newText
                    end,
                }
            },
        },

        gui.Panel{ -- Selected Overlay
            width = "100%",
            height = 43,
            halign = "center",
            valign = "bottom",
            bgimage = "panels/square.png",
            bgcolor = "white",
            cornerRadius = 10,
            beveledcorners = true,
            interactable = false,

            _setSelected = function(element, selected)
                selected = selected or false
                element:SetClass("collapsed", not selected)
            end,

            gradient = gui.Gradient{
                type = "radial",
                point_a = {x = 0.5, y = -0.9},
                point_b = {x = 0.5, y = 0.4},
                stops = {
                    {position = 0.00, color = "#BC9B7BFF"},
                    {position = 0.15, color = "#BC9B7BE2"},
                    {position = 0.28, color = "#BC9B7BC5"},
                    {position = 0.40, color = "#BC9B7BA8"},
                    {position = 0.51, color = "#BC9B7B8B"},
                    {position = 0.61, color = "#BC9B7B6E"},
                    {position = 0.70, color = "#BC9B7B51"},
                    {position = 0.78, color = "#BC9B7B34"},
                    {position = 0.85, color = "#BC9B7B17"},
                    {position = 1.00, color = "#BC9B7B00"},
                }
            },
        },

        gui.Panel{ -- Available Overlay
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "center",
            interactable = false,

            _setAvailable = function(element, available)
                available = available or false
                element:SetClass("collapsed", not available)
            end,

            gui.Panel{ -- Diamond
                width = 14,
                height = 14,
                rotate = 45,
                valign = "top",
                halign = "center",
                bgimage = "panels/square.png",
                bgcolor = "#BC9B7B",
                interactable = false,

            },

            gui.Panel { -- Line
                height = 11,
                width = "auto",
                halign = "center",
                valign = "top",
                vmargin = 12,
                pad = 0,
                flow = "horizontal",
                interactable = false,
                gui.Panel{
                    width = "35%",
                    height = 11,
                    halign = "right",
                    valign = "top",
                    hmargin = 0,
                    bgimage = mod.images.actionButtonLine,
                    bgcolor = "#ffffff",
                    interactable = false,
                },
                gui.Panel{
                    width = 24,
                    height = 11,
                    halign = "center",
                    valign = "top",
                    hmargin = 0,
                    bgimage = mod.images.actionButtonV,
                    bgcolor = "#ffffff",
                    interactable = false,
                },
                gui.Panel{
                    width = "35%",
                    height = 11,
                    halign = "left",
                    valign = "top",
                    bgimage = mod.images.actionButtonLine,
                    bgcolor = "#ffffff",
                    interactable = false,
                },
            }
        },
    }

    mainPanel = gui.Panel(opts)

    return mainPanel
end

if gui.ActionButton == nil then
    gui.ActionButton = _actionButton
end