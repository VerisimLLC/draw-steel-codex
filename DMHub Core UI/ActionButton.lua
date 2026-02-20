local mod = dmhub.GetModLoading()

local COLOR_BLACK = "#000000"
local COLOR_BLACK02 = "#040807"
local COLOR_BLACK03 = "#191A18"
local COLOR_CREAM04 = "#BC9B7B"
local COLOR_GOLD = "#966D4B"
local COLOR_GOLD02 = "#49362C"
local COLOR_GOLD03 = "#F1D3A5"
local COLOR_GOLD04 = "#E9B86F"
local COLOR_GREY02 = "#666663"

local ACTION_BUTTON_WIDTH = 225
local ACTION_BUTTON_HEIGHT = 52
local BUTTON_BASE_HEIGHT = ACTION_BUTTON_HEIGHT - 7
local ACTION_BUTTON_CORNER_RADIUS = 10
local GRADIENT_OVERLAY_HEIGHT = BUTTON_BASE_HEIGHT - 2

local AVAILABLE_DIAMOND_SIZE = 12
local AVAILABLE_LINE_HEIGHT = 10
local AVAILABLE_LINE_WIDTH = 196
local AVAILABLE_LINE_TMARGIN = 10
local AVAILBALE_LINE_HMARGIN = 15

local LABEL_FONT_FACE = "Berling"
local LABEL_FONT_SIZE = 18

local gradientStops = {
    {position = 0.00, color = "#BC9B7BC5"},
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

local actionButtonStyles = {
    {
        selectors = {"action-button"},
    },
    {
        selectors = {"action-button", "press"},
        scale = 0.98,
    },
    {
        selectors = {"action-button-base"},
        valign = "bottom",
        bgimage = true,
        border = 1,
        borderWidth = 1,
        bgcolor = COLOR_BLACK,
        borderColor = COLOR_CREAM04,
    },
    {
        selectors = {"action-button-base", "selected"},
        borderColor = COLOR_GOLD03,
    },
    {
        selectors = {"action-button-base", "hover"},
        bgcolor = COLOR_GOLD04,
    },
    {
        selectors = {"v-line"},
        height = 14,
        width = AVAILABLE_LINE_WIDTH,
        valign = "top",
        halign = "left",
        tmargin = AVAILABLE_LINE_TMARGIN,
        hmargin = AVAILBALE_LINE_HMARGIN,
        pad = 0,
        bgcolor = COLOR_CREAM04,
    },
    {
        selectors = {"v-line", "parent:selected"},
        bgcolor = COLOR_GOLD03,
    },
    {
        selectors = {"v-line", "parent:hover"},
        bgcolor = COLOR_GOLD04,
    },
    {
        selectors = {"action-button-label"},
        color = COLOR_GOLD,
    },
    {
        selectors = {"action-button-label", "selected"},
        color = COLOR_GOLD03,
    },
    {
        selectors = {"action-button-label", "hover"},
        color = COLOR_GOLD02,
    },
    {
        selectors = {"action-button-hover"},
        bgcolor = COLOR_GOLD04,
    },
    {
        selectors = {"action-button-hover", "parent:hover"},
        bgcolor = COLOR_GOLD04,
    },
    {
        selectors = {"unavailable"},
        borderColor = COLOR_GREY02,
        color = COLOR_GREY02,
    },
}

--- Creates a Draw Steel Codex style action button
--- 
--- Size via scale option; width & height ignored
--- 
--- element:FireEvent("setAvailable", isAvailable)
--- 
--- element:FireEvent("setSelected", isSelected)
--- @return Panel
function gui.ActionButton(options)
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
        _available = opts.available or false,
        _selected = opts.selected or false,
    }
    opts.data = opts.data or {}
    for k,v in pairs(data) do
        opts.data[k] = v
    end
    opts.available = nil
    opts.selected = nil

    opts.width = ACTION_BUTTON_WIDTH
    opts.height = ACTION_BUTTON_HEIGHT
    opts.halign = opts.halign or "center"
    opts.valign = opts.valign or "center"

    local fnCreate = (opts.create and type(opts.create) == "function") and opts.create or nil
    opts.create = function(element, ...)
        if fnCreate then fnCreate(element, ...) end
        element:FireEvent("setAvailable", element.data._available)
        element:FireEvent("setSelected", element.data._selected)
    end

    opts.setAvailable = function(element, available)
        element.data._available = available
        element.interactable = available
        element:FireEventTree("_setAvailable", available)
    end

    opts.setSelected = function(element, selected)
        element.data._selected = selected
        element:FireEventTree("_setSelected", selected)
    end

    opts.setText = function(element, newText)
        element:FireEventTree("_setText", newText)
    end

    opts.SetValue = function(element, values)
        if not values or type(values) ~= "table" then return end
        if values.text then element:FireEvent("setText", values.text) end
        if values.available then element.FireEvent("setAvailable", values.available) end
        if values.selected then element.FireEvent("setSelected", values.selected) end
    end

    opts.GetValue = function(element)
        local values = dmhub.DeepCopy(element.data)
        values.selected = values._selected
        values.available = values._available
        values._available = nil
        values._selected = nil
        local label = element:FindChildRecursive(function(e) return e:HasClass("selector-button-label") end)
        if label then values.text = label.text end
        return values
    end

    local labelText = opts.text or ""
    opts.text = nil
    local fontFace = opts.fontFace or LABEL_FONT_FACE
    opts.fontFace = nil
    local fontSize = opts.fontSize or LABEL_FONT_SIZE
    opts.fontSize = nil
    local fontBold = opts.bold or true
    opts.bold = nil

    opts.children = {

        gui.Panel{ -- Button Base / bevel outline
            classes = {"action-button-base"},
            width = "100%",
            height = BUTTON_BASE_HEIGHT,
            cornerRadius = ACTION_BUTTON_CORNER_RADIUS,
            beveledcorners = true,
            interactable = true,

            _setAvailable = function(element, available)
                element.interactable = available
                element:SetClass("unavailable", not available)
            end,

            _setSelected = function(element, selected)
                element:SetClass("selected", selected)
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
                    fontFace = fontFace,
                    fontSize = fontSize,
                    text = labelText,
                    bold = fontBold,
                    interactable = false,
                    _setAvailable = function(element, available)
                        element:SetClass("unavailable", not available)
                    end,
                    _setSelected = function(element, selected)
                        element:SetClass("selected", selected)
                    end,
                    _setText = function(element, newText)
                        element.text = newText
                    end,
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
                width = AVAILABLE_DIAMOND_SIZE,
                height = AVAILABLE_DIAMOND_SIZE,
                rotate = 45,
                valign = "top",
                halign = "center",
                bgimage = true,
                bgcolor = COLOR_CREAM04,
                interactable = false,

            },

            gui.Panel{ -- V-Line
                classes = {"v-line"},
                bgimage = mod.images.actionButtonVLine,
                interactable = false,
            },
        },
    }

    mainPanel = gui.Panel(opts)

    return mainPanel
end

local SELECTOR_BUTTON_CORNER_RADIUS = 2
local SELECTOR_LABEL_FONT_SIZE = LABEL_FONT_SIZE + 4

local selectorButtonStyles = {
    {
        selectors = {"selector-button"},
        bgcolor = COLOR_BLACK02,
    },
    {
        selectors = {"selector-button", "press"},
        scale = 0.98,
    },
    {
        selectors = {"selector-button-base"},
        bgcolor = COLOR_BLACK02,
        borderColor = COLOR_GOLD,
    },
    {
        selectors = {"selector-button-label"},
        color = COLOR_GOLD,
    },
    {
        selectors = {"selected"},
        color = COLOR_GOLD03,
        borderColor = COLOR_GOLD03,
    },
    {
        selectors = {"hover"},
        color = COLOR_GOLD02,
        bgcolor = COLOR_GOLD04,
        -- brightness = 1.5,
    },
    {
        selectors = {"unavailable"},
        borderColor = COLOR_GREY02,
        color = COLOR_GREY02,
    },
}

--- Creates a Draw Steel Codex style selector button
--- 
--- element:FireEvent("setAvailable", isAvailable)
--- 
--- element:FireEvent("setSelected", isSelected)
--- @return Panel
function gui.SelectorButton(options)
    local opts = dmhub.DeepCopy(options or {})

    local mainPanel

    local styles = selectorButtonStyles
    if opts.styles and #opts.styles > 0 then
        table.move(opts.styles, 1, #opts.styles, #styles + 1, styles)
    end
    opts.styles = styles

    local classes = {"selector-button"}
    local buttonClasses = {"selector-button-base"}
    local labelClasses = {"selector-button-label"}
    if opts.classes and #opts.classes > 0 then
        table.move(opts.classes, 1, #opts.classes, #classes + 1, classes)
        table.move(opts.classes, 1, #opts.classes, #buttonClasses + 1, buttonClasses)
        -- table.move(opts.classes, 1, #opts.classes, #labelClasses + 1, labelClasses)
    end

    local data = {
        _available = opts.available or false,
        _selected = opts.selected or false,
    }
    opts.data = opts.data or {}
    for k,v in pairs(data) do
        opts.data[k] = v
    end
    opts.available = nil
    opts.selected = nil

    opts.width = opts.width or math.floor(0.9 * ACTION_BUTTON_WIDTH)
    opts.height = opts.height or BUTTON_BASE_HEIGHT
    opts.halign = opts.halign or "center"
    opts.valign = opts.valign or "center"

    local fnCreate = (opts.create and type(opts.create) == "function") and opts.create or nil
    opts.create = function(element, ...)
        element:FireEvent("setAvailable", element.data._available)
        element:FireEvent("setSelected", element.data._selected)
        if fnCreate then fnCreate(element, ...) end
    end

    opts.setAvailable = function(element, available)
        element.data._available = available
        element.interactable = available
        element:FireEventTree("_setAvailable", available)
    end

    opts.setSelected = function(element, selected)
        element.data._selected = selected
        element:FireEventTree("_setSelected", selected)
    end

    opts.setText = function(element, newText)
        element:FireEventTree("_setText", newText)
    end

    opts.SetValue = function(element, values)
        if not values or type(values) ~= "table" then return end
        if values.text then element:FireEvent("setText", values.text) end
        if values.available then element.FireEvent("setAvailable", values.available) end
        if values.selected then element.FireEvent("setSelected", values.selected) end
    end

    opts.GetValue = function(element)
        local values = dmhub.DeepCopy(element.data)
        values.selected = values._selected
        values.available = values._available
        values._selected = nil
        values._available = nil
        local label = element:FindChildRecursive(function(e) return e:HasClass("selector-button-label") end)
        if label then values.text = label.text end
        return values
    end

    local labelText = opts.text or ""
    opts.text = nil
    local fontFace = opts.fontFace or LABEL_FONT_FACE
    opts.fontFace = nil
    local fontSize = opts.fontSize or SELECTOR_LABEL_FONT_SIZE
    opts.fontSize = nil
    local fontBold = opts.bold or false
    opts.bold = nil
    local labelAlign = opts.textAlignment or "left"
    opts.textAlignment = nil

    opts.children = {

        gui.Panel{ -- Button Base
            classes = buttonClasses,
            width = "100%",
            height = "100%",
            valign = "center",
            bgimage = true,
            border = 1,
            borderWidth = 1,
            cornerRadius = SELECTOR_BUTTON_CORNER_RADIUS,
            interactable = true,

            _setAvailable = function(element, available)
                element.interactable = available
                element:SetClass("unavailable", not available)
            end,
            _setSelected = function(element, selected)
                element:SetClass("selected", selected)
            end,

            gui.Label{
                classes = labelClasses,
                width = "98%-40",
                height = "98%",
                hmargin = 20,
                halign = labelAlign,
                fontFace = fontFace,
                fontSize = fontSize,
                text = labelText,
                bold = fontBold,
                interactable = false,
                _setAvailable = function(element, available)
                    element:SetClass("unavailable", not available)
                    element:SetClass("selected", not available)
                end,
                _setSelected = function(element, selected)
                    element:SetClass("selected", selected)
                end,
                _setText = function(element, newText)
                    element.text = newText
                end,
            },
        },
    }

    mainPanel = gui.Panel(opts)

    return mainPanel
end
