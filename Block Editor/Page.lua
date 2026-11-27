local mod = dmhub.GetModLoading()

--[[
    BEPage: a host's page, the detail column of the editor. Everything on it
    comes from the host's declaration (Block.RegisterHost): the "This is"
    switch, then each section in order with its header, its fixed rows (one
    coloured group), the line that sums them up, its add row and its stack of
    blocks, and last the "Start from:" pills.

    Fixed rows edit the record's own fields (model.values); a stack edits a
    list of blocks (model[section.stack]).
]]

local T = UIText.T

--- @class BEPage
BEPage = {}

--- The id the detail column is found by (drag auto-scroll, the section strip).
BEPage.DETAIL_ID = "beDetailScroll"

--- Changes one of the record's own fields, as one undo step.
--- @param source Panel a panel inside the editor
--- @param field string
--- @param value any
--- @param description string
local function _setField(source, field, value, description)
    BlockEditor._fireControllerEvent(source, "editorChange", description, function(state)
        --- @cast state BEState
        local model = state:Model()
        if model ~= nil then
            model.values = model.values or {}
            local previous = model.values[field]
            model.values[field] = value
            --a slot whose meaning depends on another adjusts it in the same undo step.
            local host = BlockEditor._getHost(source)
            local codec = host ~= nil and host.decl ~= nil and (host.decl.fields or {})[field] or nil
            if codec ~= nil and codec.changed ~= nil then
                codec.changed(model.values, previous)
            end
        end
    end)
end

--- "This is [an ability | a triggered ability]".
--- @param choice {label: string, field: string, options: {id: string, text: string}[]}
--- @return Panel
local function _kindRow(choice)
    return gui.Panel{
        classes = {"beIsRow"},
        gui.Label{ classes = {"beIsLabel"}, text = choice.label, interactable = false },
        gui.EnumeratedSliderControl{
            width = 300,
            halign = "left",
            options = choice.options,
            value = choice.options[1].id,
            change = function(element)
                local value = element.value
                for _, option in ipairs(choice.options) do
                    if option.id == value then
                        _setField(element, choice.field, value, T("blockeditor.change.set", { what = option.text }))
                    end
                end
            end,
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                local value = model ~= nil and (model.values or {})[choice.field] or nil
                if value ~= nil and element.value ~= value then
                    element.value = value
                end
            end,
        },
    }
end

--- The fixed rows of a section: one coloured group, rows split by a hairline.
--- @param rows BlockHeaderRow[]
--- @return Panel
local function _headerGroup(rows)
    local children = {}
    for i, row in ipairs(rows) do
        --- @type Panel|nil the hairline above this row, hidden with it
        local rule = nil
        if i > 1 then
            rule = gui.Panel{ classes = {"beHeaderRule"}, interactable = false }
            children[#children + 1] = rule
        end
        children[#children + 1] = gui.Panel{
            classes = {"beHeaderRow"},
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                if model == nil then
                    return
                end
                local shown = row.when == nil or row.when(model.values or {}) == true
                element:SetClass("collapsed", not shown)
                if rule ~= nil then
                    rule:SetClass("collapsed", not shown)
                end
                if not shown then
                    element.children = {}
                    return
                end
                element.children = {
                    BESlots.SentenceRow{
                        decl = row,
                        values = model.values or {},
                        onChange = function(slotId, value, description, source)
                            _setField(source, slotId, value, description)
                        end,
                    },
                }
            end,
        }
    end
    return gui.Panel{
        classes = {"beHeaderGroup", BEStyles.GroupClass("header")},
        children = children,
    }
end

--- A dashed "add" row, for a list that is empty until the author adds to it.
--- @param text string
--- @return Panel
local function _addRequirementRow(text)
    return gui.Panel{
        classes = {"beAddReq"},
        linger = function(element)
            gui.Tooltip(T("blockeditor.not_yet"))(element)
        end,
        gui.Panel{ classes = {"beAddIcon"}, interactable = false },
        gui.Label{ classes = {"beAddText", "beAddReqText"}, text = text, interactable = false },
    }
end

--- The "+ add step" row under a stack: a menu of the blocks that fit it.
--- @param text string
--- @param fits string
--- @return Panel
local function _addStepRow(text, fits)
    return gui.Panel{
        classes = {"beAddRow"},
        press = function(element)
            local entries = {}
            for _, decl in ipairs(Block.All("block")) do
                --- @cast decl BlockDecl
                if decl.shelf ~= false then
                    for _, kind in ipairs(decl.fits or {}) do
                        if kind == fits then
                            entries[#entries + 1] = {
                                text = decl.label,
                                click = function()
                                    element.popup = nil
                                    BEStack.Append(element, decl.id)
                                end,
                            }
                            break
                        end
                    end
                end
            end
            element.popupsInheritStyles = true
            element.popupPositioning = "mouse"
            element.popup = gui.ContextMenu{
                entries = entries,
                click = function()
                    element.popup = nil
                end,
            }
        end,
        gui.Panel{ classes = {"beAddIcon"}, interactable = false },
        gui.Label{ classes = {"beAddText"}, text = text, interactable = false },
    }
end

--- One section: its header and rule, then its body.
--- @param section BlockHostSection
--- @return Panel[]
local function _section(section)
    local body = {}
    if section.rows ~= nil and #section.rows > 0 then
        body[#body + 1] = _headerGroup(section.rows)
    end
    if section.summary ~= nil then
        local summary = section.summary --[[@as fun(model: table): string|nil]]
        body[#body + 1] = gui.Label{
            classes = {"beSummary"},
            text = "",
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                local ok, text = pcall(summary, model or {})
                element.text = (ok and type(text) == "string") and ("<i>" .. text .. "</i>") or ""
            end,
        }
    end
    if section.addText ~= nil then
        body[#body + 1] = _addRequirementRow(section.addText)
    end
    if section.stack ~= nil then
        local field = section.stack --[[@as string]]
        local stack = BEStack.Create{ ref = { field = field }, fits = section.fits or "step" }
        body[#body + 1] = gui.Panel{
            width = "100%",
            height = "auto",
            flow = "vertical",
            valign = "top",
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                stack:FireEvent("refreshStack", model ~= nil and model[field] or {})
            end,
            stack,
        }
        if section.stackAddText ~= nil then
            body[#body + 1] = _addStepRow(section.stackAddText, section.fits or "step")
        end
    end

    local countFn = nil
    if section.stack ~= nil then
        local field = section.stack
        countFn = function(state)
            local model = state:Model()
            local count = model ~= nil and #(model[field] or {}) or 0
            return count == 1 and T("blockeditor.count.one_step") or T("blockeditor.count.steps", { count = count })
        end
    end

    --- @type Panel
    local content
    content = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        children = body,
    }
    local header, rule = BEStyles.SectionHeader{
        title = section.title,
        optional = section.optional and T("blockeditor.optional") or nil,
        countFn = countFn,
        --the caret folds the section away.
        press = function(element)
            local folded = not content:HasClass("collapsed")
            content:SetClass("collapsed", folded)
            local caret = element.children[1]
            caret.selfStyle.rotate = folded and 90 or 0
        end,
        data = { sectionId = section.id },
    }
    return { header, rule, content }
end

--- The "Start from:" pills.
--- @param templates {label: string, items: string[]}
--- @return Panel
local function _templates(templates)
    local children = {
        gui.Label{ classes = {"beStartLabel"}, text = templates.label, interactable = false },
    }
    for _, item in ipairs(templates.items) do
        children[#children + 1] = gui.Label{
            classes = {"bePill"},
            text = item,
            linger = function(element)
                gui.Tooltip(T("blockeditor.not_yet"))(element)
            end,
        }
    end
    return gui.Panel{
        classes = {"beStartRow"},
        children = children,
    }
end

--- Builds the detail column for a host.
--- @param host BlockHost
--- @return Panel
function BEPage.Create(host)
    local children = {}
    if host.kindChoice ~= nil then
        children[#children + 1] = _kindRow(host.kindChoice)
    end
    for _, section in ipairs(host.sections or {}) do
        for _, panel in ipairs(_section(section)) do
            children[#children + 1] = panel
        end
    end
    if host.templates ~= nil then
        children[#children + 1] = _templates(host.templates)
    end
    return gui.Panel{
        id = BEPage.DETAIL_ID,
        classes = {"beDetail"},
        width = "100%-" .. (BEStyles.SIZES.EDITOR_SHELF_WIDTH + BEStyles.SIZES.EDITOR_SIDE_WIDTH),
        vscroll = true,
        children = children,
    }
end

--- Scrolls the detail column so a section's header is at the top.
--- @param detail Panel the detail column
--- @param sectionId string
function BEPage.ScrollTo(detail, sectionId)
    local children = detail.children
    if #children == 0 then
        return
    end
    local function Top(panel)
        return panel.positionInScreenSpace.y + panel.renderedHeight / 2
    end
    local first, last = children[1], children[#children]
    local contentHeight = Top(first) - (Top(last) - last.renderedHeight) + 36
    local scrollable = contentHeight - detail.renderedHeight
    if scrollable <= 1 then
        return
    end
    for _, child in ipairs(children) do
        if child.data ~= nil and child.data.sectionId == sectionId then
            local offset = Top(first) - Top(child)
            detail.vscrollPosition = math.max(0, math.min(1, 1 - offset / scrollable))
            return
        end
    end
end
