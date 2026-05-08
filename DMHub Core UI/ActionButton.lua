local mod = dmhub.GetModLoading()

local ACTION_BUTTON_WIDTH = 225
local ACTION_BUTTON_HEIGHT = 52
local BUTTON_BASE_HEIGHT = ACTION_BUTTON_HEIGHT - 7
local ACTION_BUTTON_CORNER_RADIUS = 10

local AVAILABLE_DIAMOND_SIZE = 12
local AVAILABLE_LINE_WIDTH = 196
local AVAILABLE_LINE_TMARGIN = 10
local AVAILBALE_LINE_HMARGIN = 15

local LABEL_FONT_FACE = "Berling"
local LABEL_FONT_SIZE = 18

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
        bgcolor = "@bg",
        borderColor = "@border",
    },
    {
        selectors = {"action-button-base", "selected"},
        borderColor = "@accent",
    },
    {
        selectors = {"action-button-base", "hover"},
        bgcolor = "@bgInverse",
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
        bgcolor = "@border",
    },
    {
        selectors = {"v-line", "selected"},
        bgcolor = "@accent",
    },
    {
        selectors = {"v-line", "hovered"},
        bgcolor = "@fgInverse",
    },
    {
        selectors = {"button-diamond"},
        bgcolor = "@border",
    },
    {
        selectors = {"button-diamond", "selected"},
        bgcolor = "@accent",
    },
    {
        selectors = {"button-diamond", "hovered"},
        bgcolor = "@fgInverse",
    },
    {
        selectors = {"action-button-label"},
        color = "@fg",
    },
    {
        selectors = {"action-button-label", "selected"},
        color = "@accent",
    },
    {
        selectors = {"action-button-label", "hovered"},
        color = "@fgInverse",
    },
    {
        selectors = {"action-button-hover"},
        bgcolor = "@bgInverse",
    },
    {
        selectors = {"action-button-hover", "parent:hover"},
        bgcolor = "@bgInverse",
    },
    {
        selectors = {"unavailable"},
        borderColor = "@disabled",
        color = "@fgMuted",
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
    local opts = DeepCopy(options or {})

    local mainPanel

    local styles = actionButtonStyles
    if opts.styles and #opts.styles > 0 then
        table.move(opts.styles, 1, #opts.styles, #styles + 1, styles)
    end
    opts.styles = ThemeEngine.MergeTokens(styles)

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
        if values.available then element:FireEvent("setAvailable", values.available) end
        if values.selected then element:FireEvent("setSelected", values.selected) end
    end

    opts.GetValue = function(element)
        local values = DeepCopy(element.data)
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

            -- The engine only applies the "hover" class to the interactable
            -- panel itself. Propagate a "hovered" class to the whole button
            -- subtree (including the sibling overlay with diamond + v-line)
            -- so those elements can react in styles.
            hover = function(element)
                if element.parent then
                    element.parent:SetClassTree("hovered", true)
                end
            end,
            dehover = function(element)
                if element.parent then
                    element.parent:SetClassTree("hovered", false)
                end
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
                classes = {"button-diamond"},
                width = AVAILABLE_DIAMOND_SIZE,
                height = AVAILABLE_DIAMOND_SIZE,
                rotate = 45,
                valign = "top",
                halign = "center",
                bgimage = true,
                interactable = false,
                _setSelected = function(element, selected)
                    element:SetClass("selected", selected)
                end,
            },

            gui.Panel{ -- V-Line
                classes = {"v-line"},
                bgimage = mod.images.actionButtonVLine,
                interactable = false,
                _setSelected = function(element, selected)
                    element:SetClass("selected", selected)
                end,
            },
        },
    }

    mainPanel = gui.Panel(opts)

    ThemeEngine.OnThemeChanged(mod, function()
        if mainPanel ~= nil and mainPanel.valid then
            mainPanel.styles = ThemeEngine.MergeTokens(styles)
        end
    end)

    return mainPanel
end

local SELECTOR_LABEL_FONT_SIZE = LABEL_FONT_SIZE + 4

--- Creates a Draw Steel Codex style selector button.
---
--- Theme-driven: visuals (rest/hover/press/selected/disabled) come from the
--- active theme's {button} cascade. Caller supplies size, font, text, and
--- behavior; theme owns the look.
---
--- element:FireEvent("setAvailable", isAvailable)
--- element:FireEvent("setSelected", isSelected)
--- @return Panel
function gui.SelectorButton(options)
    local opts = DeepCopy(options or {})

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
    opts.fontFace = opts.fontFace or LABEL_FONT_FACE
    opts.fontSize = opts.fontSize or SELECTOR_LABEL_FONT_SIZE
    opts.textAlignment = opts.textAlignment or "center"

    local fnCreate = (opts.create and type(opts.create) == "function") and opts.create or nil
    opts.create = function(element, ...)
        element:SetClass("disabled", not element.data._available)
        element:SetClass("selected", element.data._selected)
        element.interactable = element.data._available
        if fnCreate then fnCreate(element, ...) end
    end

    opts.setAvailable = function(element, available)
        element.data._available = available
        element.interactable = available
        element:SetClass("disabled", not available)
    end

    opts.setSelected = function(element, selected)
        element.data._selected = selected
        element:SetClass("selected", selected)
    end

    opts.setText = function(element, newText)
        element.text = newText
    end

    opts.SetValue = function(element, values)
        if not values or type(values) ~= "table" then return end
        if values.text then element:FireEvent("setText", values.text) end
        if values.available then element:FireEvent("setAvailable", values.available) end
        if values.selected then element:FireEvent("setSelected", values.selected) end
    end

    opts.GetValue = function(element)
        local values = DeepCopy(element.data)
        values.selected = values._selected
        values.available = values._available
        values._selected = nil
        values._available = nil
        values.text = element.text
        return values
    end

    return gui.Button(opts)
end
