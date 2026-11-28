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

--- The "..." menu: delete, move up, move down.
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
            end
        end)
    end
    element.popupsInheritStyles = true
    element.popupPositioning = "mouse"
    element.popup = gui.ContextMenu{
        entries = {
            {
                text = T("blockeditor.menu.move_up"),
                click = function()
                    Run(T("blockeditor.change.move", { block = label }), function(model) BEState.Move(model, uid, -1) end)
                end,
            },
            {
                text = T("blockeditor.menu.move_down"),
                click = function()
                    Run(T("blockeditor.change.move", { block = label }), function(model) BEState.Move(model, uid, 1) end)
                end,
            },
            {
                text = T("blockeditor.menu.delete"),
                group = "delete",
                click = function()
                    Run(T("blockeditor.change.delete", { block = label }), function(model) BEState.Remove(model, uid) end)
                end,
            },
        },
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
