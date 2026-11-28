local mod = dmhub.GetModLoading()

--[[
    BEBlockPanel: one placed block. A head row (grip, group glyph, optional
    tag, the sentence, a "..." menu) and, for a block that holds others, its
    bodies: a tier row (a label beside an inner list) for each labelled body,
    or one inset list.

    A block panel is built once and kept while its block stays in the record;
    "refreshBlock" redraws only its sentence and passes its bodies' lists on
    to their stacks. It finds its block again by uid, so undo (which swaps
    the model for a copy) never leaves it holding a stale table.
]]

local T = UIText.T

--- @class BEBlockPanel
BEBlockPanel = {}

--- Runs one change on the placed block with this uid, as one undo step.
--- @param element Panel any panel inside the editor
--- @param uid string
--- @param description string
--- @param fn fun(instance: BlockInstance, model: BERecordModel)
function BEBlockPanel.ChangeBlock(element, uid, description, fn)
    BlockEditor._fireControllerEvent(element, "editorChange", description, function(state)
        --- @cast state BEState
        local model = state:Model()
        if model == nil then
            return
        end
        local instance = BEState.FindInstance(model, uid)
        if instance ~= nil then
            fn(instance, model)
        end
    end)
end

--- A copy of a placed block that saves as a new one: no editor id, and no
--- link back to the saved step it was read from (inside it too).
--- @param instance BlockInstance
--- @return BlockInstance
local function _freshCopy(instance)
    local copy = DeepCopy(instance)
    local function Clear(item)
        item.uid = nil
        item.src = nil
        item.openSignature = nil
        item.openContext = nil
        for _, list in pairs(item.bodies or {}) do
            for _, inner in ipairs(list) do
                Clear(inner)
            end
        end
    end
    Clear(copy)
    return copy
end

--- The wrapper whose block this is ("Only if"), or nil.
--- @param blockId string
--- @return BlockWrapper|nil
local function _wrapperOf(blockId)
    for _, wrapper in ipairs(Block.All("wrapper")) do
        --- @cast wrapper BlockWrapper
        if wrapper.block == blockId then
            return wrapper
        end
    end
    return nil
end

--- Whether two blocks share a kind of list they fit in.
--- @param a string[]|nil
--- @param b string[]|nil
--- @return boolean
local function _shareFits(a, b)
    for _, kind in ipairs(a or {}) do
        for _, other in ipairs(b or {}) do
            if kind == other then
                return true
            end
        end
    end
    return false
end

--- The "..." menu: move up and down (greyed at the ends), duplicate, wrap in
--- a wrapper block from the shelf, unwrap, delete.
--- @param element Panel the gear
--- @param uid string
--- @param label string the block's name, for the undo step
local function _openBlockMenu(element, uid, label)
    local function Run(description, fn)
        element.popup = nil
        BlockEditor._fireControllerEvent(element, "editorChange", description, function(state)
            --- @cast state BEState
            local model = state:Model()
            if model ~= nil then
                fn(model)
                --blocks it added (a copy, a wrapper) need editor ids.
                BEState.AssignUids(model)
            end
        end)
    end

    --where the block is now, to grey out moves that would do nothing.
    local controller = BlockEditor._getController(element)
    local state = controller ~= nil and controller.data.state or nil
    local model = state ~= nil and state:Model() or nil
    local instance, list, index = nil, nil, nil
    if model ~= nil then
        instance, list, index = BEState.FindInstance(model, uid)
    end
    if instance == nil or list == nil or index == nil then
        return
    end
    local decl = Block.GetBlock(instance.block)
    local host = BlockEditor._getHost(element)
    local advancedBlock = host ~= nil and host.decl ~= nil and host.decl.advancedBlock or nil

    local entries = {
        {
            text = T("blockeditor.menu.move_up"),
            disabled = index <= 1,
            click = function()
                Run(T("blockeditor.change.move", { block = label }), function(m) BEState.Move(m, uid, -1) end)
            end,
        },
        {
            text = T("blockeditor.menu.move_down"),
            disabled = index >= #list,
            click = function()
                Run(T("blockeditor.change.move", { block = label }), function(m) BEState.Move(m, uid, 1) end)
            end,
        },
        {
            text = T("blockeditor.menu.duplicate"),
            group = "edit",
            --a copy of a step no block reads, or of a block that holds options, cannot be saved.
            disabled = instance.block == advancedBlock or (decl ~= nil and decl.split ~= nil),
            click = function()
                Run(T("blockeditor.change.duplicate", { block = label }), function(m)
                    local found, foundList, foundIndex = BEState.FindInstance(m, uid)
                    if found ~= nil and foundList ~= nil and foundIndex ~= nil then
                        table.insert(foundList, foundIndex + 1, _freshCopy(found))
                    end
                end)
            end,
        },
    }

    --wrap in any wrapper block on the shelf that goes where this block goes.
    if decl ~= nil and instance.block ~= advancedBlock then
        for _, wrapper in ipairs(Block.All("wrapper")) do
            --- @cast wrapper BlockWrapper
            local wrapDecl = Block.GetBlock(wrapper.block)
            if wrapDecl ~= nil and wrapDecl.shelf ~= false and _shareFits(decl.fits, wrapDecl.fits) then
                entries[#entries + 1] = {
                    text = T("blockeditor.menu.wrap", { block = wrapDecl.label }),
                    group = "wrap",
                    click = function()
                        Run(T("blockeditor.change.wrap", { block = wrapDecl.label }), function(m)
                            local found, foundList, foundIndex = BEState.FindInstance(m, uid)
                            local holder = Block.Instantiate(wrapper.block)
                            if found ~= nil and foundList ~= nil and foundIndex ~= nil and holder ~= nil then
                                holder.bodies = holder.bodies or {}
                                holder.bodies[wrapper.body or "steps"] = { found }
                                foundList[foundIndex] = holder
                            end
                        end)
                    end,
                }
            end
        end
    end

    --a wrapper unwraps: its steps take its place.
    local ownWrapper = _wrapperOf(instance.block)
    if ownWrapper ~= nil then
        entries[#entries + 1] = {
            text = T("blockeditor.menu.unwrap"),
            group = "wrap",
            click = function()
                Run(T("blockeditor.change.unwrap", { block = label }), function(m)
                    local found, foundList, foundIndex = BEState.FindInstance(m, uid)
                    if found == nil or foundList == nil or foundIndex == nil then
                        return
                    end
                    local inner = (found.bodies or {})[ownWrapper.body or "steps"] or {}
                    table.remove(foundList, foundIndex)
                    for offset, step in ipairs(inner) do
                        table.insert(foundList, foundIndex + offset - 1, step)
                    end
                end)
            end,
        }
    end

    entries[#entries + 1] = {
        text = T("blockeditor.menu.delete"),
        group = "delete",
        click = function()
            Run(T("blockeditor.change.delete", { block = label }), function(m) BEState.Remove(m, uid) end)
        end,
    }

    element.popupsInheritStyles = true
    element.popupPositioning = "mouse"
    element.popup = gui.ContextMenu{
        entries = entries,
        click = function()
            element.popup = nil
        end,
    }
end

--- The sentence for a block's current values.
--- @param decl BlockDecl
--- @param instance BlockInstance
--- @param width string
--- @return Panel
local function _sentence(decl, instance, width)
    local uid = instance.uid or ""
    return BESlots.SentenceRow{
        decl = decl,
        values = instance.values,
        width = width,
        italic = decl.italic,
        onChange = function(slotId, value, description, source)
            BEBlockPanel.ChangeBlock(source, uid, description, function(target, model)
                local previous = target.values[slotId]
                target.values[slotId] = value
                if decl.changed ~= nil then
                    local ok, err = pcall(decl.changed, target, slotId, previous)
                    if not ok then
                        dmhub.Error(string.format("BlockEditor: block '%s' failed to adjust after a change: %s", decl.id, tostring(err)))
                    end
                    --blocks it added to its bodies need editor ids.
                    BEState.AssignUids(model)
                end
            end)
        end,
    }
end

--- Builds a placed block.
--- @param instance BlockInstance
--- @return Panel|nil nil when its block is not registered
function BEBlockPanel.Create(instance)
    local decl = Block.GetBlock(instance.block)
    if decl == nil then
        return nil
    end
    local uid = instance.uid or ""
    local SIZES = BEStyles.SIZES
    --a tag's width grows with its text ("Text", "Advanced").
    local inset = SIZES.SENTENCE_INSET + (decl.tag ~= nil and (SIZES.TAG_INSET + 10 * math.max(0, #decl.tag - 4)) or 0)
    local sentenceWidth = "100%-" .. inset

    --- @type Panel
    local head
    local headChildren = {
        gui.Panel{
            classes = {"beGrip"},
            draggable = true,
            dragMove = false,
            dragThreshold = 4,
            beginDrag = function(element)
                BEStack.BeginDrag(element, { blockId = decl.id, moveUid = uid })
            end,
        },
    }
    local glyph = BEStyles.Glyph(decl.group, { classes = {"beGlyph", "beBlockGlyph"} })
    if glyph ~= nil then
        glyph:SetClass("beBlockGlyph", true)
        headChildren[#headChildren + 1] = glyph
    end
    if decl.tag ~= nil then
        headChildren[#headChildren + 1] = gui.Label{
            classes = {"beTag"},
            text = decl.tag,
            interactable = false,
        }
    end
    local sentenceIndex = #headChildren + 1
    headChildren[sentenceIndex] = _sentence(decl, instance, sentenceWidth)
    headChildren[#headChildren + 1] = gui.Panel{
        classes = {"beGear"},
        press = function(element)
            _openBlockMenu(element, uid, decl.label)
        end,
    }
    head = gui.Panel{
        classes = {"beBlockHead"},
        children = headChildren,
    }

    --the bodies: one stack each, kept for the life of the block panel.
    local bodyStacks = {}
    local children = { head }
    for _, body in ipairs(decl.bodies or {}) do
        local ref = { field = "blocks", owner = uid, body = body.id }
        if body.label ~= nil then
            local stack = BEStack.Create{ ref = ref, fits = body.fits, max = body.max, classes = {"beInner", "beTierInner"}, addRow = true }
            bodyStacks[body.id] = stack
            children[#children + 1] = gui.Panel{
                classes = {"beTierRow"},
                gui.Panel{
                    classes = {"beTierLabel"},
                    gui.Label{ classes = {"beTierName"}, text = body.label, interactable = false },
                    gui.Label{ classes = {"beTierSub"}, text = body.sublabel or "", interactable = false },
                },
                stack,
            }
        else
            local stack = BEStack.Create{ ref = ref, fits = body.fits, max = body.max, classes = {"beInner", "beInset"}, addRow = true }
            bodyStacks[body.id] = stack
            children[#children + 1] = stack
        end
    end

    --- @type Panel
    local panel
    panel = gui.Panel{
        classes = {"beBlock", BEStyles.GroupClass(decl.group)},
        flow = "vertical",
        valign = "top",
        data = { uid = uid },
        children = children,

        --- Redraws the sentence and hands each body its list.
        --- @param newInstance BlockInstance
        refreshBlock = function(element, newInstance)
            local headPanel = element.children[1]
            local list = {}
            for i, child in ipairs(headPanel.children) do
                list[i] = child
            end
            list[sentenceIndex] = _sentence(decl, newInstance, sentenceWidth)
            headPanel.children = list
            for bodyId, stack in pairs(bodyStacks) do
                stack:FireEvent("refreshStack", (newInstance.bodies or {})[bodyId] or {})
            end
        end,

        --- Rings the block for a moment after it is added.
        flashBlock = function(element, flashUid)
            if flashUid == uid then
                element:SetClass("selected", true)
                element:ScheduleEvent("unflash", 1.6)
            end
        end,
        unflash = function(element)
            element:SetClass("selected", false)
        end,
    }
    panel:FireEvent("refreshBlock", instance)
    return panel
end
