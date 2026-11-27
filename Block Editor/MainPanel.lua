local mod = dmhub.GetModLoading()

--[[
    The Block Editor's window and controller: BlockEditor.Open / Routes.

    The root panel is the controller (see the design notes at the top of
    BlockEditor.lua). It holds data = { state, host }, runs every change
    through BEState, and fires refreshEditorState down its tree.

    Phase 0: the window opens empty on a demo record. Clicking a shelf block
    appends it to the demo record, so undo, redo and the upload timer can be
    exercised; nothing real is read or saved.
]]

local T = UIText.T

local _fireControllerEvent = BlockEditor._fireControllerEvent
local _getState = BlockEditor._getState

--The event the controller fires for cheap updates (button states, the status
--readout) that must not redraw blocks: after an upload, for one.
local STATUS_EVENT = "refreshEditorStatus"

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
            print(string.format("BLOCKEDITOR:: (phase 0) would upload '%s' with %d blocks", model.name, #model.blocks))
        end,
    }
end

--- The sections of a host's page, or the demo page's when it declares none.
--- @param host BlockEditorHost
--- @return {id: string, label: string}[]
local function _sections(host)
    local result = {}
    if host.decl ~= nil and host.decl.sections ~= nil then
        for _, section in ipairs(host.decl.sections) do
            result[#result + 1] = { id = tostring(section.id), label = tostring(section.label or section.id) }
        end
    end
    if #result == 0 then
        result = {
            { id = "what", label = T("blockeditor.demo.section.what") },
            { id = "who", label = T("blockeditor.demo.section.who") },
            { id = "when", label = T("blockeditor.demo.section.when") },
            { id = "used", label = T("blockeditor.demo.section.used") },
        }
    end
    return result
end

--- A first model for a record: its id and name, and no blocks. RecordCache
--- replaces this in phase 2 by reading the record's own data into blocks.
--- @param record table|nil
--- @return BERecordModel
local function _emptyModel(record)
    local id, name = nil, nil
    if record ~= nil then
        --a game-typed record raises on a field it does not have.
        pcall(function() id = record.id end)
        pcall(function() name = record.name end)
    end
    return {
        id = type(id) == "string" and id or "demo",
        name = type(name) == "string" and name or T("blockeditor.demo.record_name"),
        blocks = {},
    }
end

--- The title bar: the record's name, the Simple / Advanced editor tabs, and
--- Undo, Redo and Close.
--- @return Panel
local function _titleBar()
    return gui.Panel{
        classes = {"beTitleBar"},

        gui.Label{
            classes = {"sizeXl", "bold"},
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 16,
            text = T("blockeditor.title", { name = "" }),
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                element.text = T("blockeditor.title", { name = model ~= nil and model.name or "" })
            end,
        },

        gui.Panel{
            classes = {"tabBar"},
            halign = "left",
            valign = "center",
            gui.Label{
                classes = {"tab", "selected"},
                text = T("blockeditor.tab.simple"),
            },
            gui.Label{
                classes = {"tab"},
                width = 170,
                text = T("blockeditor.tab.advanced"),
                linger = function(element)
                    gui.Tooltip(T("blockeditor.tab.advanced_tooltip"))(element)
                end,
            },
        },

        --one right-aligned group, so the three keep this order.
        gui.Panel{
            width = "auto",
            height = "auto",
            flow = "horizontal",
            halign = "right",
            valign = "center",
            gui.Button{
                classes = {"sizeS"},
                valign = "center",
                rmargin = 6,
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
            },
            gui.Button{
                classes = {"sizeS"},
                valign = "center",
                rmargin = 16,
                text = T("blockeditor.redo"),
                click = function(element)
                    _fireControllerEvent(element, "editorRedo")
                end,
                linger = function(element)
                    local state = _getState(element)
                    local change = state ~= nil and state:RedoDescription() or nil
                    if change ~= nil then
                        gui.Tooltip(T("blockeditor.redo_tooltip", { change = change }))(element)
                    else
                        gui.Tooltip(T("blockeditor.redo_nothing"))(element)
                    end
                end,
                [STATUS_EVENT] = function(element, state)
                    --- @cast state BEState
                    element:SetClass("disabled", not state:CanRedo())
                end,
            },
            gui.Button{
                classes = {"closeButton", "sizeS"},
                valign = "center",
                click = function(element)
                    _fireControllerEvent(element, "editorClose")
                end,
            },
        },
    }
end

--- The section strip: one button per section of the host's page. Phase 0
--- only marks the pressed one; phase 1 scrolls the detail column to it.
--- @param host BlockEditorHost
--- @return Panel
local function _sectionStrip(host)
    local children = {}
    for i, section in ipairs(_sections(host)) do
        children[#children + 1] = gui.Button{
            classes = {"sizeS", cond(i == 1, "selected")},
            width = "auto",
            hpad = 12,
            rmargin = 6,
            text = section.label,
            data = { section = section.id },
            click = function(element)
                element.parent:FireEventTree("selectSection", element.data.section)
            end,
            selectSection = function(element, sectionId)
                element:SetClass("selected", element.data.section == sectionId)
            end,
        }
    end
    return gui.Panel{
        classes = {"beSectionStrip"},
        children = children,
    }
end

--- The detail column: the record's blocks. Phase 0 lists the demo record's
--- blocks as plain sentences and rebuilds the list on every change; the real
--- stack (phase 1) redraws only the block that changed.
--- @return Panel
local function _detailColumn()
    local SIZES = BEStyles.SIZES
    return gui.Panel{
        classes = {"beColumn"},
        width = "100% available",
        rmargin = SIZES.COLUMN_GAP,

        gui.Label{
            classes = {"beHeading"},
            text = T("blockeditor.detail.heading"),
        },
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.detail.empty"),
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                element:SetClass("collapsed", model ~= nil and #model.blocks > 0)
            end,
        },
        gui.Panel{
            classes = {"beScroll"},
            [BlockEditor.REFRESH_EVENT] = function(element, state)
                --- @cast state BEState
                local model = state:Model()
                local children = {}
                for _, instance in ipairs(model ~= nil and model.blocks or {}) do
                    local decl = Block.GetBlock(instance.block)
                    if decl ~= nil then
                        children[#children + 1] = BEStyles.BlockPanel{
                            group = decl.group,
                            text = Block.SentenceText(decl, instance.values),
                            bmargin = SIZES.BLOCK_GAP,
                        }
                    end
                end
                element.children = children
            end,
        },
    }
end

--- The shelf: every registered block, under its colour group, in full colour
--- with the group's glyph. Read from the Block registries when the editor
--- opens, so nothing here names a block.
--- @return Panel
local function _shelfColumn()
    local SIZES = BEStyles.SIZES

    --- @type table<string, BlockDecl[]>
    local byGroup = {}
    for _, decl in ipairs(Block.All("block")) do
        --- @cast decl BlockDecl
        byGroup[decl.group] = byGroup[decl.group] or {}
        table.insert(byGroup[decl.group], decl)
    end

    local rows = {}
    for _, group in ipairs(Block.All("group")) do
        --- @cast group BlockGroup
        local decls = byGroup[group.id]
        if decls ~= nil then
            rows[#rows + 1] = gui.Label{
                classes = {"beGroupHeading"},
                text = group.text,
            }
            for _, decl in ipairs(decls) do
                rows[#rows + 1] = BEStyles.BlockPanel{
                    group = decl.group,
                    text = decl.label,
                    bmargin = SIZES.BLOCK_GAP,
                    data = { block = decl.id, label = decl.label, desc = decl.desc },
                    --click, not press: press would swallow the start of a drag (phase 1).
                    click = function(element)
                        local blockId = element.data.block
                        _fireControllerEvent(element, "editorChange", T("blockeditor.change.add", { block = element.data.label }), function(state)
                            --- @cast state BEState
                            local model = state:Model()
                            local instance = Block.Instantiate(blockId)
                            if model ~= nil and instance ~= nil then
                                model.blocks[#model.blocks + 1] = instance
                            end
                        end)
                    end,
                    linger = function(element)
                        if element.data.desc ~= nil then
                            gui.Tooltip(element.data.desc)(element)
                        end
                    end,
                }
            end
        end
    end

    return gui.Panel{
        classes = {"beColumn"},
        width = SIZES.SHELF_WIDTH,
        rmargin = SIZES.COLUMN_GAP,

        gui.Label{
            classes = {"beHeading"},
            text = T("blockeditor.shelf.heading"),
        },
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.shelf.note"),
        },
        gui.Panel{
            classes = {"beScroll"},
            children = rows,
        },
    }
end

--- The side panel: the checks and the book-style card go here (phase 1).
--- Phase 0 shows what the state holds, so undo and uploads can be watched.
--- @return Panel
local function _sideColumn()
    return gui.Panel{
        classes = {"beColumn"},
        width = BEStyles.SIZES.SIDE_WIDTH,

        gui.Label{
            classes = {"beHeading"},
            text = T("blockeditor.side.checks"),
        },
        gui.Label{
            classes = {"beNote"},
            text = T("blockeditor.side.checks_note"),
        },
        gui.Label{
            classes = {"beHeading"},
            tmargin = 12,
            text = T("blockeditor.side.state"),
        },
        gui.Label{
            classes = {"beNote"},
            text = "",
            [STATUS_EVENT] = function(element, state)
                --- @cast state BEState
                local unsaved = 0
                for _, _ in pairs(state.dirty) do
                    unsaved = unsaved + 1
                end
                element.text = T("blockeditor.side.state_text", {
                    undo = #state.undoStack,
                    redo = #state.redoStack,
                    unsaved = unsaved,
                    uploads = state.uploads,
                })
            end,
        },
    }
end

--- Whether a registered host edits this record, so today's editors can send
--- it here and keep the rest (the Advanced editor). Phase 0: nothing is
--- routed, since no record can be read into blocks yet.
--- @param record table|nil
--- @param where? string where it was opened from ("compendium", ...)
--- @return boolean
function BlockEditor.Routes(record, where)
    return false
end

--- Opens the editor on a record, as a modal window. With no record (the
--- developer command) it opens on an empty demo record.
--- @param record? table the record to edit (class, feature, ability, ...)
--- @return Panel|nil controller the editor's root panel
function BlockEditor.Open(record)
    --read every registry afresh, so blocks from mods loaded later are included.
    Block.Gather()

    local decl = record ~= nil and Block.FindHost(record) or nil
    local host = _demoHost(decl)
    local state = BEState.CreateNew(host)
    state:AddRecord(_emptyModel(record), record)

    local SIZES = BEStyles.SIZES
    --- @type table|nil the theme subscription, dropped when the window closes
    local themeSub = nil

    --- @type Panel
    local controller
    controller = gui.Panel{
        classes = {"framedPanel", BlockEditor.CONTROLLER_CLASS},
        styles = ThemeEngine.MergeStyles(BEStyles.GetStyles()),
        width = SIZES.WINDOW_WIDTH,
        height = SIZES.WINDOW_HEIGHT,
        maxWidth = SIZES.WINDOW_MAX_WIDTH,
        maxHeight = SIZES.WINDOW_MAX_HEIGHT,
        halign = "center",
        valign = "center",
        flow = "vertical",
        pad = SIZES.WINDOW_PAD,
        borderBox = true,

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

        _titleBar(),
        _sectionStrip(host),
        gui.Panel{
            width = "100%",
            height = "100% available",
            flow = "horizontal",
            _detailColumn(),
            _shelfColumn(),
            _sideColumn(),
        },
    }

    gui.ShowModal(controller)
    return controller
end

Commands.RegisterMacro{
    name = "blockeditor",
    summary = "open the empty Block Editor (developers)",
    doc = "Usage: /blockeditor\nOpens the Block Editor on an empty demo record: the shelf lists the registered blocks, and clicking one adds it so undo, redo and the upload timer can be tried. Developer mode only.",
    command = function(str)
        if not BlockEditor._isDeveloper() then
            dmhub.Log("The Block Editor is in development: turn on developer mode to open it.")
            return
        end
        BlockEditor.Open()
    end,
}
