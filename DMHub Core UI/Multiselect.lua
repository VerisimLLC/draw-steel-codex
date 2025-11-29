--- @class Multiselect:Panel
--- @field value table The list of values currently chosen.

--- @class MultiselectArgs:DropdownArgs
--- @field flow? "vertical"|"horizontal"
--- @field chipPos? "top"|"bottom"|"left"|"right" Position of chips relative to dropdown. For vertical flow: "top" or "bottom" (default "top"). For horizontal flow: "left" or "right" (default "right").

--- Determines if the contents of two flag lists are the same
--- regardless of order.
--- @param list1 table A flag list
--- @param list2 table Another flag list
--- @return boolean listsIdentical True if the lists contain identical keys & values
local function flagListsEqual(list1, list2)
    -- Check all keys in list1 exist in list2 with same value
    for key, value in pairs(list1) do
        if list2[key] ~= value then
            return false
        end
    end
    
    -- Check all keys in list2 exist in list1
    for key, value in pairs(list2) do
        if list1[key] ~= value then
            return false
        end
    end
    
    return true
end

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
        dropdownOpts.width = dropdownOpts.width or flow == "vertical" and "100%" or "50%"
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
        dropdownOpts.removeSelected = function(element, item)
            -- Removing from the selected list = returning to the dropdown
            local listOptions = element.options
            local insertPos = #listOptions + 1
            for i, option in ipairs(listOptions) do
                if item.text < option.text then
                    insertPos = i
                    break
                end
            end
            table.insert(listOptions, insertPos, item)
        end
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
        local chipsStylesBase = {
            gui.Style {
                selectors = {"multiselect-chip"},
                height = "auto",
                width = "auto",
                pad = 4,
                margin = 4,
                fontSize = 14,
                bgimage = "panels/square.png",
                borderColor = Styles.textColor,
                border = 1,
                cornerRadius = 2,
                bgcolor = "#444444",
            },
            gui.Style {
                selectors = {"multiselect-chip", "hover"},
                bgcolor = "#330000",
                borderColor = "#990000",
            },
        }

        -- Calculate for individual chips
        local chipsOpts = opts.chips or {}
        opts.chips = nil
        local chipsClasses = chipsOpts.classes or {}
        local chipsStyles = chipsOpts.styles or {}
        opts.chips = nil
        chipsOpts.styles = table.move(chipsStyles, 1, #chipsStyles, #chipsStylesBase, chipsStylesBase)

        -- Calculate for the panel
        local chipPanelOpts = opts.chipPanel or {}
        opts.chipPanel = nil
        chipPanelOpts.width = chipPanelOpts.width or flow == "vertical" and "100%" or "auto"
        chipPanelOpts.height = "auto"
        chipPanelOpts.flow = chipPanelOpts.flow or "horizontal"
        chipPanelOpts.wrap = true
        chipPanelOpts.children = {}
        chipPanelOpts.borderColor = "#98F347"
        chipPanelOpts.addSelected = function(element, item)
            local baseClasses = { item.id, "multiselect-chip" }
            local labelOpts = chipsOpts
            labelOpts.id = item.id
            labelOpts.data = { item = item }
            labelOpts.text = item.text
            labelOpts.classes = table.move(chipsClasses, 1, #chipsClasses, #baseClasses + 1, baseClasses)
            labelOpts.click = function(element)
                local controller = element:FindParentWithClass("multiselectController")
                if controller then
                    controller:FireEventTree("removeSelected", element.data.item)
                    dmhub.Schedule(0.1, function()
                        element:DestroySelf()
                    end)
                end
            end
            element:AddChild(gui.Label(labelOpts))
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
        panelOpts.width = panelOpts.width or "100%"
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
            element:FireEvent("change")
        end
        panelOpts.GetValue = function(element)
            return DeepCopy(element.data.selected)
        end
        panelOpts.SetValue = function(element, valueDict)
            if not flagListsEqual(valueDict, element.data.selected) then
                element.data.selected = DeepCopy(valueDict or {})
                element:FireEventTree("repaint", element.data.selected)
            end
        end
        panelOpts.refreshSet = function(element, options, values)
            m_options = shallow_copy_list(options)
            element:FireEventTree("repaint", values)
        end
        panelOpts.children = chipsBefore
            and {chipsPanel, dropdownPanel}
            or {dropdownPanel, chipsPanel}

        return gui.Panel(panelOpts)
    end
    m_panel = buildController()

    return m_panel
end

if gui.Multiselect == nil then
    gui.Multiselect = _multiselect
end
