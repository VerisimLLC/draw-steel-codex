--- @class Multiselect:Panel
--- @field value table The list of values currently chosen.

--- @class MultiselectArgs:DropdownArgs
--- @field flow? "vertical"|"horizontal"
--- @field chipPos? "top"|"bottom"|"left"|"right" Position of chips relative to dropdown. For vertical flow: "top" or "bottom" (default "top"). For horizontal flow: "left" or "right" (default "right").

-- Multiselect is a first-class widget — its internal selectors
-- (multiselect-chip, multiselect-chip-text, multiselect-chip-remove) live in
-- DefaultStyles.lua alongside other widget vocabulary like dropdownLabel /
-- dropdownTriangle / hudIconButton. This file never sets `styles =` on the
-- controller or chips: theme reach comes from the ancestor cascade through
-- whatever panel the caller wired up with ThemeEngine.MergeStyles(...).
--
-- Callers that want to override chip-specific styling for a single instance
-- pass `chips.styles` and we apply that to each chip panel directly.

--- Creates a generic multiselect control for selecting multiple items from a list
--- Displays selected items as removable chips with a dropdown to add more items
--- @param args MultiselectArgs
--- @return Multiselect panel The multiselect panel with "change" event support
local function _multiselect(args)
    local opts = (args and shallow_copy_table(args)) or {}
    opts.classes = opts.classes or {}

    -- Extract initial value (SetEditor-style dictionary)
    local initialValue = DeepCopy(opts.value or {})
    opts.value = nil

    -- Extract addItemText parameter (optional SetEditor feature)
    local addItemText = opts.addItemText or nil
    opts.addItemText = nil

    -- Retain the original list of options
    local m_options = shallow_copy_list(opts.options or {})
    opts.options = nil

    -- For later value setting
    local optionsById = {}
    for _, opt in ipairs(m_options) do
        optionsById[opt.id] = opt
    end

    -- Reference to ourself
    local m_panel = nil

    -- Store the caller's callback for forwarding
    local fnChange = nil
    if opts.change then
        fnChange = opts.change
        opts.change = nil
    end

    -- Guarantee a layout we know how to use.
    local flow = string.lower(opts.flow or "vertical")
    if flow ~= "horizontal" and flow ~= "vertical" then
        flow = "vertical"
    end
    opts.flow = nil
    local layoutVertical = flow == "vertical"
    if layoutVertical then
        opts.height = "auto"
    else
        opts.width = "auto"
    end

    -- Determine chip position: before (top/left) or after (bottom/right) dropdown
    local chipPos = opts.chipPos and string.lower(opts.chipPos) or nil
    opts.chipPos = nil

    local chipsBefore = layoutVertical
    if chipPos == "top" or chipPos == "left" then
        chipsBefore = true
    elseif chipPos == "bottom" or chipPos == "right" then
        chipsBefore = false
    end

    -- Calculate our dropdown sub-component
    local function buildDropdown()
        local dropdownOpts = opts.dropdown or {}
        opts.dropdown = nil
        -- For vertical flow, leave width unset so gui.Dropdown uses its own
        -- default (sized to widget). Forcing "auto" here makes DMHub stretch
        -- the dropdown to fill the container, which is rarely what callers want.
        -- Horizontal flow defaults to 50% so the dropdown shares space with chips.
        if dropdownOpts.width == nil and flow == "horizontal" then
            dropdownOpts.width = "50%"
        end
        dropdownOpts.hasSearch = dropdownOpts.hasSearch == nil and true or dropdownOpts.hasSearch
        dropdownOpts.textDefault = dropdownOpts.textDefault or addItemText or opts.textDefault or "Select an item..."
        dropdownOpts.sort = dropdownOpts.sort or opts.sort or nil
        dropdownOpts.options = shallow_copy_list(m_options)
        dropdownOpts.change = function(element)
            local controller = element:FindParentWithClass("multiselectController")
            if controller then
                if element.idChosen then
                    for _, item in ipairs(element.options) do
                        if item.id == element.idChosen then
                            controller:FireEventTree("addSelected", item)
                            break
                        end
                    end
                end
            end
        end
        dropdownOpts.addSelected = function(element, item)
            -- Adding to the selected list = removing from dropdown
            local options = element.options
            for i, option in ipairs(options) do
                if option == item then
                    element.idChosen = nil
                    table.remove(options, i)
                    element.options = options
                    break
                end
            end
        end
        -- removeSelected on the dropdown is intentionally not handled here.
        -- The controller's removeSelected fires `repaint` on the tree, which
        -- the dropdown's repaint handler uses to rebuild options from
        -- m_options (preserving the original sort key, including custom ord).
        -- A separate text-based insert here would race with repaint and
        -- corrupt the result.
        dropdownOpts.repaint = function(element, valueDict)
            -- Remove everything from the original options list that is in the dictionary
            local options = {}
            for _, option in ipairs(m_options) do
                if not valueDict[option.id] then
                    options[#options + 1] = option
                end
            end
            element.options = options
        end
        opts.sort = nil
        opts.textDefault = nil
        return gui.Dropdown(dropdownOpts)
    end
    local dropdownPanel = buildDropdown()

    local function buildChips()
        local chipsOpts = opts.chips or {}
        opts.chips = nil
        local chipsClasses = chipsOpts.classes or {}
        -- Caller-passed chips.styles, if any, get applied per-chip below.
        -- Default chip styling lives in DefaultStyles.lua and reaches chips
        -- through the ancestor cascade.
        local chipsCallerStyles = chipsOpts.styles

        -- Calculate for the panel
        local chipPanelOpts = opts.chipPanel or {}
        opts.chipPanel = nil
        -- Vertical multiselects: chip panel fills the controller's width so
        -- horizontal flow + wrap has a stable boundary to wrap against.
        -- Horizontal multiselects: chip panel sizes to its chips next to the
        -- dropdown, so "auto" is the right default.
        chipPanelOpts.width = chipPanelOpts.width or (layoutVertical and "100%" or "auto")
        chipPanelOpts.halign = chipPanelOpts.halign or (layoutVertical and "left" or nil)
        chipPanelOpts.height = "auto"
        chipPanelOpts.flow = chipPanelOpts.flow or "horizontal"
        chipPanelOpts.wrap = true
        chipPanelOpts.children = {}
        chipPanelOpts.addSelected = function(element, item)
            local baseClasses = { item.id, "multiselect-chip" }
            local chipClasses = table.move(chipsClasses, 1, #chipsClasses, #baseClasses + 1, baseClasses)

            local chipPanelArgs = {
                classes = chipClasses,
                id = item.id,
                data = { item = item },
                children = {
                    gui.Label{
                        classes = {"label", "multiselect-chip-text"},
                        text = item.text,
                    },
                    gui.Panel{
                        classes = {"panel", "multiselect-chip-remove"},
                        press = function(el)
                            local controller = el:FindParentWithClass("multiselectController")
                            if controller then
                                local chipItem = el.parent.data.item
                                controller:FireEventTree("removeSelected", chipItem)
                                -- No explicit DestroySelf here. The
                                -- controller's removeSelected fires repaint
                                -- on the tree, and the chip panel's repaint
                                -- handler destroys chips not in the new value
                                -- dict (this chip among them). Scheduling our
                                -- own destroy would race with that and
                                -- eventually try to read .parent on an
                                -- already-destroyed userdata.
                            end
                        end,
                        children = {
                            gui.Label{
                                classes = {"label", "multiselect-chip-remove"},
                                text = "X",
                            },
                        },
                    },
                },
            }
            -- Caller-supplied chip styling applies per-chip when provided.
            -- Skipping it lets chips inherit the default theme through the
            -- ancestor cascade (the desired path for most callers).
            if chipsCallerStyles then
                chipPanelArgs.styles = chipsCallerStyles
            end
            element:AddChild(gui.Panel(chipPanelArgs))
        end
        chipPanelOpts.repaint = function(element, valueDict)
            -- Remove children not in dictionary
            for i = #element.children, 1, -1 do
                if not valueDict[element.children[i].id] then
                    element.children[i]:DestroySelf()
                end
            end

            -- Build lookup of current child IDs
            local childIds = {}
            for _, child in ipairs(element.children) do
                childIds[child.id] = true
            end

            -- Add items from dictionary that aren't in children
            for id, flag in pairs(valueDict) do
                if flag and not childIds[id] then
                    local item = optionsById[id]
                    if item then
                        element:FireEvent("addSelected", item)
                    end
                end
            end
        end
        chipPanelOpts.removeSelected = function(element, item)
            -- They're kind enough to destroy themselves
        end

        return gui.Panel(chipPanelOpts)
    end
    local chipsPanel = buildChips()

    local function buildController()

        local controllerClasses = {"multiselectController"}
        if opts.classes then
            table.move(opts.classes, 1, #opts.classes, #controllerClasses + 1, controllerClasses)
            opts.classes = nil
        end

        local panelData = { selected = {} }
        if opts.data then
            for k, v in pairs(opts.data) do
                if k ~= "selected" then
                    panelData[k] = v
                end
            end
        end

        -- Convert initial dictionary to internal storage
        for id, flag in pairs(initialValue) do
            if flag then
                panelData.selected[id] = true
            end
        end

        local panelOpts = opts or {}
        panelOpts.classes = controllerClasses
        panelOpts.width = panelOpts.width or "98%"
        panelOpts.height = panelOpts.height or "auto"
        panelOpts.flow = flow
        panelOpts.data = panelData
        panelOpts.change = function(element)
            if fnChange then
                fnChange(element, element.data.selected)
            end
        end
        panelOpts.addSelected = function(element, item)
            element.data.selected[item.id] = true
            element:FireEvent("change")
        end
        panelOpts.removeSelected = function(element, item)
            element.data.selected[item.id] = nil
            -- Force a full repaint of the dropdown options so the returning
            -- item lands in its original sorted position (driven by m_options
            -- order). Without this, the dropdown's own removeSelected handler
            -- does a text-based insert that ignores any custom ord/sort key.
            element:FireEventTree("repaint", element.data.selected)
            element:FireEvent("change")
        end
        panelOpts.GetValue = function(element)
            return DeepCopy(element.data.selected)
        end
        panelOpts.SetValue = function(element, valueDict)
            if not dmhub.DeepEqual(valueDict, element.data.selected) then
                element.data.selected = DeepCopy(valueDict or {})
                element:FireEventTree("repaint", element.data.selected)
            end
        end
        panelOpts.refreshSet = function(element, options, values)
            if options then
                m_options = shallow_copy_list(options)
            end
            element:FireEventTree("repaint", values or element.data.selected)
        end
        panelOpts.children = chipsBefore
            and {chipsPanel, dropdownPanel}
            or {dropdownPanel, chipsPanel}

        return gui.Panel(panelOpts)
    end
    m_panel = buildController()

    -- Visually apply initial value (create chips, filter dropdown)
    if next(initialValue) then
        m_panel:FireEventTree("repaint", m_panel.data.selected)
    end

    return m_panel
end

if gui.Multiselect == nil then
    gui.Multiselect = _multiselect
end
