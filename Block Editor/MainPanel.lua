local mod = dmhub.GetModLoading()

--[[
    The Block Editor's window and controller: BlockEditor.Open / Routes.

    The root panel is the controller (see the design notes at the top of
    BlockEditor.lua). It holds data = { state, host }, runs every change
    through BEState, and fires refreshEditorState down its tree.

    The window follows docs/block-editor/lua-preview/ability.html: a title bar
    (title, Simple / Advanced editor tabs, the host's dropdown, Paste text,
    Undo), a strip of section names, then three columns: the page (BEPage),
    the shelf (BEShelf) and the checks and card (BESidePanel).

    Phase 1: with no record it opens the stub ability host's demo record.
    Edits, undo and the upload timer work; the host only logs the upload.
]]

local T = UIText.T

local _fireControllerEvent = BlockEditor._fireControllerEvent
local _getState = BlockEditor._getState

--The event the controller fires for cheap updates (button states) that must
--not redraw blocks: after an upload, for one.
local STATUS_EVENT = "refreshEditorStatus"

--The host the developer window opens when it is given no record.
local DEMO_HOST = "stub.ability"

--- The host the developer window uses: it accepts every change and only logs
--- the upload. Real hosts come from Block.RegisterHost once records can be
--- written (phase 2).
--- @param decl nil|BlockHost
--- @return BlockEditorHost
local function _demoHost(decl)
    return {
        id = decl ~= nil and decl.id or "demo",
        decl = decl,
        canWrite = function()
            return true
        end,
        upload = function(record, model)
            --phase 2a: saving is worked out and logged, not sent (milestone 2c sends it).
            if record ~= nil and decl ~= nil then
                local same, diff = BERecordCache.SavesUnchanged(model, record, decl)
                print(string.format("BLOCKEDITOR:: would upload '%s': %s", model.name, same and "unchanged" or json(diff)))
            else
                print(string.format("BLOCKEDITOR:: would upload '%s' with %d blocks", model.name, #model.blocks))
            end
        end,
    }
end

--- A first model for a record: its id and name, and no blocks. RecordCache
--- replaces this in phase 2 by reading the record's own data into blocks.
--- @param record table
--- @return BERecordModel
local function _emptyModel(record)
    local id, name = nil, nil
    --a game-typed record raises on a field it does not have.
    pcall(function() id = record.id end)
    pcall(function() name = record.name end)
    return {
        id = type(id) == "string" and id or "record",
        name = type(name) == "string" and name or "",
        values = {},
        blocks = {},
    }
end

--- The title bar: the title, the Simple / Advanced editor tabs, then on the
--- right the host's dropdown, Paste text, Undo and Close.
--- @param decl BlockHost
--- @return Panel
local function _titleBar(decl)
    local tools = {}
    local toolbar = decl.toolbar
    if toolbar ~= nil then
        tools[#tools + 1] = gui.Label{
            classes = {"beToolLabel"},
            text = toolbar.label,
            interactable = false,
        }
        tools[#tools + 1] = gui.Dropdown{
            classes = {"sizeS"},
            width = 140,
            valign = "center",
            rmargin = 8,
            options = toolbar.options,
            idChosen = toolbar.options[1].id,
            change = function(element)
                local value = element.idChosen
                for _, option in ipairs(toolbar.options) do
                    if option.id == value then
                        _fireControllerEvent(element, "editorChange", T("blockeditor.change.set", { what = option.text }), function(state)
                            --- @cast state BEState
                            local model = state:Model()
                            if model ~= nil then
                                model.values = model.values or {}
                                model.values[toolbar.field] = value
                            end
                        end)
                    end
                end
            end,
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                local value = model ~= nil and (model.values or {})[toolbar.field] or nil
                if value ~= nil and element.idChosen ~= value then
                    element.idChosen = value
                end
            end,
        }
    end
    tools[#tools + 1] = gui.Button{
        classes = {"sizeS"},
        width = "auto",
        hpad = 12,
        valign = "center",
        rmargin = 8,
        text = T("blockeditor.paste"),
        linger = function(element)
            gui.Tooltip(T("blockeditor.not_yet"))(element)
        end,
    }
    tools[#tools + 1] = gui.Button{
        classes = {"sizeS"},
        width = "auto",
        hpad = 12,
        valign = "center",
        rmargin = 12,
        text = T("blockeditor.undo"),
        click = function(element)
            _fireControllerEvent(element, "editorUndo")
        end,
        linger = function(element)
            local state = _getState(element)
            local change = state ~= nil and state:UndoDescription() or nil
            if change ~= nil then
                gui.Tooltip(T("blockeditor.undo_tooltip", { change = change }))(element)
            else
                gui.Tooltip(T("blockeditor.undo_nothing"))(element)
            end
        end,
        [STATUS_EVENT] = function(element, state)
            --- @cast state BEState
            element:SetClass("disabled", not state:CanUndo())
        end,
    }
    tools[#tools + 1] = gui.Button{
        classes = {"closeButton", "sizeS"},
        valign = "center",
        click = function(element)
            _fireControllerEvent(element, "editorClose")
        end,
    }

    return gui.Panel{
        classes = {"beEditorTitleBar"},
        gui.Label{
            classes = {"beEditorTitle"},
            text = decl.title or T("blockeditor.title", { name = "" }),
            interactable = false,
        },
        gui.Panel{
            classes = {"tabBar"},
            halign = "left",
            valign = "bottom",
            gui.Label{
                classes = {"tab", "selected"},
                text = T("blockeditor.tab.simple"),
            },
            gui.Label{
                classes = {"tab"},
                --wide enough for the name on one line.
                width = 190,
                text = T("blockeditor.tab.advanced"),
                linger = function(element)
                    gui.Tooltip(T("blockeditor.tab.advanced_tooltip"))(element)
                end,
            },
        },
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "bottom",
            bmargin = 8,
            children = tools,
        },
    }
end

--- The strip of section names. A click marks the section and scrolls the page to it.
--- @param decl BlockHost
--- @return Panel
local function _sectionStrip(decl)
    local children = {}
    for i, section in ipairs(decl.sections or {}) do
        local rowChildren = {
            gui.Label{ classes = {"beNavText"}, text = section.title, interactable = false },
        }
        if section.stack ~= nil then
            local field = section.stack
            rowChildren[#rowChildren + 1] = gui.Label{
                classes = {"beCount"},
                text = "",
                interactable = false,
                [BlockEditor.REFRESH_EVENT] = function(element, state)
                    --- @cast state BEState
                    local model = state:Model()
                    local count = model ~= nil and #(model[field] or {}) or 0
                    element.text = count == 1 and T("blockeditor.count.one_step") or T("blockeditor.count.steps", { count = count })
                end,
            }
        end
        children[#children + 1] = gui.Panel{
            classes = {"beNavRow", cond(i == 1, "selected")},
            data = { section = section.id },
            children = rowChildren,
            press = function(element)
                element.parent:FireEventTree("selectSection", element.data.section)
                local controller = BlockEditor._getController(element)
                local detail = controller ~= nil and controller:Get(BEPage.DETAIL_ID) or nil
                if detail ~= nil then
                    BEPage.ScrollTo(detail, element.data.section)
                end
            end,
            selectSection = function(element, sectionId)
                element:SetClass("selected", element.data.section == sectionId)
            end,
        }
    end
    return gui.Panel{
        classes = {"beStrip"},
        children = children,
    }
end

--- Whether a registered host edits this record, so today's editors can send
--- it here and keep the rest (the Advanced editor). Phase 1: nothing is
--- routed, since no record can be read into blocks yet.
--- @param record table|nil
--- @param where? string where it was opened from ("compendium", ...)
--- @return boolean
function BlockEditor.Routes(record, where)
    return false
end

--- Opens the editor on a record, as a modal window. With no record (the
--- developer command) it opens the stub ability host's demo record.
--- @param record? table the record to edit (class, feature, ability, ...)
--- @return Panel|nil controller the editor's root panel
function BlockEditor.Open(record)
    --read every registry afresh, so blocks from mods loaded later are included.
    Block.Gather()

    local decl = nil
    local model = nil
    if record ~= nil then
        decl = Block.FindHost(record)
        if decl ~= nil and decl.fields ~= nil then
            model = BERecordCache.Open(record, decl)
            model.savesUnchanged = BERecordCache.SavesUnchanged(model, record, decl)
        else
            model = _emptyModel(record)
        end
    else
        decl = Block.Get("host", DEMO_HOST) --[[@as BlockHost|nil]]
        if decl ~= nil and decl.demo ~= nil then
            model = DeepCopy(decl.demo)
        end
    end
    if decl == nil or model == nil then
        dmhub.Log("The Block Editor has no host for this record yet.")
        return nil
    end
    --- @cast model BERecordModel

    local host = _demoHost(decl)
    local state = BEState.CreateNew(host)
    state:AddRecord(model, record)

    local SIZES = BEStyles.SIZES
    --- @type table|nil the theme subscription, dropped when the window closes
    local themeSub = nil

    --- @type Panel
    local controller
    controller = gui.Panel{
        classes = {"beWindow", BlockEditor.CONTROLLER_CLASS},
        styles = ThemeEngine.MergeStyles(BEStyles.GetStyles()),
        width = SIZES.EDITOR_WIDTH,
        height = SIZES.EDITOR_HEIGHT,
        maxWidth = SIZES.WINDOW_MAX_WIDTH,
        maxHeight = SIZES.WINDOW_MAX_HEIGHT,
        halign = "center",
        valign = "center",

        data = {
            state = state,
            host = host,
        },

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            element:FireEvent("editorClose")
        end,

        --Ctrl+Z / Ctrl+Y while the editor is open, as the initiative bar's
        --Turn History takes them (MCDMInitiativeBar.lua, CreateUndoListener).
        inputEvents = {"undo", "redo"},
        undo = function(element)
            element:FireEvent("editorUndo")
        end,
        redo = function(element)
            element:FireEvent("editorRedo")
        end,

        create = function(element)
            themeSub = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = ThemeEngine.MergeStyles(BEStyles.GetStyles())
                end
            end)
            element:FireEvent("editorRefresh")
        end,

        destroy = function(element)
            --closing uploads whatever is pending (plan 12.3), then the stacks go.
            state:UploadDirty(true)
            element.inputEvents = nil
            if themeSub ~= nil then
                themeSub:Deregister()
                themeSub = nil
            end
        end,

        --- One author action, as one undo step.
        --- @param description string shown on the Undo button
        --- @param fn fun(state: BEState) changes the models
        --- @param recordIds? string[] the records it touches; the one shown when absent
        editorChange = function(element, description, fn, recordIds)
            if not host.canWrite() then
                return
            end
            local changed = state:Change(description, fn, recordIds)
            if changed ~= nil then
                element:FireEvent("editorRefresh", changed)
            end
        end,

        editorUndo = function(element)
            local changed = state:Undo()
            if changed ~= nil then
                element:FireEvent("editorRefresh", changed)
            end
        end,

        editorRedo = function(element)
            local changed = state:Redo()
            if changed ~= nil then
                element:FireEvent("editorRefresh", changed)
            end
        end,

        --- Redraws after a change and starts the upload timer if needed.
        --- @param changedIds? string[] the records that changed; everything when absent
        editorRefresh = function(element, changedIds)
            element:FireEventTree(BlockEditor.REFRESH_EVENT, state, changedIds)
            element:FireEventTree(STATUS_EVENT, state)
            if state:IsDirty() then
                element.thinkTime = BlockEditor.UPLOAD_THINK_TIME
            end
        end,

        --- Rings a block for a moment after it is added (from a shelf click).
        --- @param uid string
        flashRequest = function(element, uid)
            element:FireEventTree("flashBlock", uid)
        end,

        --Runs only while a record is dirty: uploads what is due, then stops.
        think = function(element)
            if mod.unloaded then
                return
            end
            local before = state.uploads
            if not state:Think() then
                element.thinkTime = nil
            end
            if state.uploads ~= before or not state:IsDirty() then
                element:FireEventTree(STATUS_EVENT, state)
            end
        end,

        editorClose = function(element)
            gui.CloseModal()
        end,

        _titleBar(decl),
        _sectionStrip(decl),
        gui.Panel{
            classes = {"beColumns", "beDropArea"},
            --a drop target, so a drag the ghost carries ends here.
            dragTarget = true,
            BEPage.Create(decl),
            BEShelf.Create(decl),
            BESidePanel.Create(decl),
        },
    }

    gui.ShowModal(controller)
    return controller
end

Commands.RegisterMacro{
    name = "blockeditor",
    summary = "open an ability in the Block Editor (developers)",
    doc = "Usage: /blockeditor [ability name]\nWith a name, opens that class or subclass ability as blocks; steps no block reads yet open as Advanced blocks. Without one, opens the stub demo (\"Out of the Way!\"). Edits, undo and the upload timer work; the upload is only logged. Developer mode only.",
    command = function(str)
        if not BlockEditor._isDeveloper() then
            dmhub.Log("The Block Editor is in development: turn on developer mode to open it.")
            return
        end
        local name = trim(str or "")
        if name == "" then
            BlockEditor.Open()
            return
        end
        local ability = BERoundTrip.FindAbility(name)
        if ability == nil then
            dmhub.Log(string.format("No class or subclass ability is called '%s'.", name))
            return
        end
        BlockEditor.Open(ability)
    end,
}
