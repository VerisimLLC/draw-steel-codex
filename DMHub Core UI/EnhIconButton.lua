--- @class IconButton:Panel

--- @class IconButtonArgs:PanelArgs
--- @field bgimage string Image to display

--- Creates a generic icon button. The default/hover/press visuals come from
--- the active theme via the `iconButton` selector rules. Callers can:
---   - Pass `bgcolor =` inline to override the default tint (DMHub's inline
---     constructor properties win over class rules).
---   - Add a semantic accent class (`withSuccess`, `withInfo`, `withWarning`,
---     `withDanger`) for themed hover coloring.
---   - Pass their own `styles =` array for one-off rule overrides; it is
---     merged after the function's defaults.
--- @param args IconButtonArgs
--- @return IconButton panel The icon button
local function _iconButton(args)
    local opts = (args and shallow_copy_table(args)) or {}

    if not opts.bgimage then
        error("IconButton requires 'bgimage' parameter")
    end

    local panelArgs = {
        classes = {"iconButton"},
        bgimage = opts.bgimage,
        borderWidth = 0,
        width = opts.width or 20,
        height = opts.height or 20,
    }
    opts.bgimage = nil

    if opts.classes then
        table.move(opts.classes, 1, #opts.classes, #panelArgs.classes + 1, panelArgs.classes)
        opts.classes = nil
    end

    if opts.styles then
        panelArgs.styles = opts.styles
        opts.styles = nil
    end

    for k, v in pairs(opts) do
        if k ~= "width" and k ~= "height" then
            panelArgs[k] = v
        end
    end

    return gui.Panel(panelArgs)
end

if gui.EnhIconButton == nil then
    gui.EnhIconButton = _iconButton
end
