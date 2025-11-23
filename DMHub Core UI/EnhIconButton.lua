--- @class IconButton:Panel
--- @field value table The list of values currently chosen.

--- @class IconButtonArgs:PanelArgs
--- @field bgimage string Image to display
--- @field defaultColor? string
--- @field hoverColor? string
--- @field pressColor? string
--- @field transitionTime? number

--- Creates a generic icon button control
--- @param args IconButtonArgs
--- @return IconButton panel The icon button
local function _iconButton(args)
    local opts = (args and shallow_copy_table(args)) or {}

    -- Validate required parameter
    if not opts.bgimage then
        error("IconButton requires 'bgimage' parameter")
    end

    -- Extract icon and color options
    local bgimage = opts.bgimage
    local defaultColor = opts.defaultColor or "#ffffff"
    local hoverColor = opts.hoverColor or "#ffffff"
    local pressColor = opts.pressColor or "#808080"
    local transitionTime = opts.transitionTime or 0.2

    -- Remove from opts so they don't get passed through
    opts.bgimage = nil
    opts.defaultColor = nil
    opts.hoverColor = nil
    opts.pressColor = nil
    opts.transitionTime = nil

    -- Styles for icon button tinting
    local iconButtonStyles = {
        {
            priority = 10,
            selectors = {'dt-icon-button'},
            bgcolor = defaultColor,
            borderWidth = 0,
        },
        {
            priority = 10,
            selectors = {'dt-icon-button', 'hover'},
            bgcolor = hoverColor,
            transitionTime = transitionTime
        },
        {
            priority = 10,
            selectors = {'dt-icon-button', 'press'},
            bgcolor = pressColor,
        },
    }

    -- Build panel args table
    local panelArgs = {
        classes = {'dt-icon-button'},
        bgimage = bgimage,
        borderWidth = 0,
        width = opts.width or 20,
        height = opts.height or 20,
        styles = iconButtonStyles,
    }

    -- Merge additional classes
    if opts.classes then
        table.move(opts.classes, 1, #opts.classes, #panelArgs.classes + 1, panelArgs.classes)
        opts.classes = nil
    end

    -- Merge additional styles
    if opts.styles then
        local styles = {}
        table.move(panelArgs.styles, 1, #panelArgs.styles, 1, styles)
        table.move(opts.styles, 1, #opts.styles, #styles + 1, styles)
        panelArgs.styles = styles
        opts.styles = nil
    end

    -- Copy all other options
    for k, v in pairs(opts) do
        if k ~= "width" and k ~= "height" then  -- Already handled above
            panelArgs[k] = v
        end
    end

    return gui.Panel(panelArgs)
end

if gui.EnhIconButton == nil then
    gui.EnhIconButton = _iconButton
end