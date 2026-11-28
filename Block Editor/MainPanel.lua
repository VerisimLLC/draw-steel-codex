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

    With no record it opens the first host's demo record (the stub ability).
    A record is read into blocks by BERecordCache from a private copy, so
    every save starts from the record as it was opened (undo after a save
    still works). Each save writes a fresh copy into the live record; the
    window then uploads it through its host's upload, while an embedded
    editor (the ability editor's Simple tab) leaves uploading to the editor
    around it.
]]

local T = UIText.T

local _fireControllerEvent = BlockEditor._fireControllerEvent
local _getState = BlockEditor._getState

--The event the controller fires for cheap updates (button states) that must
--not redraw blocks: after an upload, for one.
local STATUS_EVENT = "refreshEditorStatus"

--- The host the developer window opens when it is given no record: the
--- first that declares a demo record (the stub ability host).
--- @return BlockHost|nil
local function _demoDecl()
    for _, host in ipairs(Block.All("host")) do
        --- @cast host BlockHost
        if host.demo ~= nil then
            return host
        end
    end
    return nil
end

--- Copies a saved record into the live one in place, so everything that
--- holds the live record (its class row, an open editor) sees the change.
--- Values are copied, so later edits never share tables with the editor.
--- @param live table
--- @param saved table
local function _writeInto(live, saved)
    local stale = {}
    for key, _ in pairs(live) do
        if type(key) ~= "string" or not string.starts_with(key, "_tmp_") then
            if rawget(saved, key) == nil then
                stale[#stale + 1] = key
            end
        end
    end
    for _, key in ipairs(stale) do
        live[key] = nil
    end
    for key, value in pairs(saved) do
        if type(key) ~= "string" or not string.starts_with(key, "_tmp_") then
            live[key] = DeepCopy(value)
        end
    end
end

--- The host an editor saves through. Its records are tracked by model id;
--- the demo (no record) has nothing to save and only logs.
--- @param decl BlockHost
--- @param options {embedded?: boolean, changed?: fun(record: table)}
--- @return BlockEditorHost
local function _recordHost(decl, options)
    --- @type table<string, table> the live record of each model, by model id
    local live = {}
    --- @type table<string, table> a copy of each record as this editor last saw or wrote it, to tell
    --- someone else's change from the echo of our own upload
    local known = {}
    return {
        id = decl.id,
        decl = decl,
        immediate = options.embedded == true,
        canWrite = function()
            return true
        end,
        track = function(model, record)
            live[model.id] = record
            known[model.id] = DeepCopy(record)
        end,
        --- The record's current version when someone else has changed it
        --- since this editor last saw or wrote it; nil when it is unchanged
        --- or the host cannot look it up.
        --- @param id string
        --- @return table|nil
        changedElsewhere = function(id)
            local record = live[id]
            if record == nil or known[id] == nil or decl.locate == nil then
                return nil
            end
            local ok, current = pcall(decl.locate, record)
            if not ok or current == nil or dmhub.DeepEqual(current, known[id]) then
                return nil
            end
            return current
        end,
        --- Takes a newer version as the record this editor saves into.
        --- @param id string
        --- @param current table
        adopt = function(id, current)
            live[id] = current
            known[id] = DeepCopy(current)
        end,
        upload = function(source, model)
            local record = live[model.id]
            if source == nil or record == nil then
                dmhub.Debug(string.format("BLOCKEDITOR:: demo '%s' has %d blocks (nothing to save)", model.name, #model.blocks))
                return true
            end
            _writeInto(record, BERecordCache.Save(model, source, decl))
            known[model.id] = DeepCopy(record)
            if options.embedded then
                --the editor around this one uploads the record when it closes.
                if options.changed ~= nil then
                    options.changed(record)
                end
                return true
            end
            if decl.upload == nil then
                error("records of this kind cannot be saved from the Block Editor yet")
            end
            return decl.upload(record) ~= false
        end,
    }
end

--- A model for a record its host cannot read into blocks (it declares no
--- fields): its id and name, and no blocks.
--- @param record table
--- @return BERecordModel
local function _emptyModel(record)
    local id, name = nil, nil
    --a game-typed record raises on a field it does not have.
    pcall(function() id = record.guid end)
    pcall(function() name = record.name end)
    return {
        id = type(id) == "string" and id or "record",
        name = type(name) == "string" and name or "",
        values = {},
        blocks = {},
    }
end

--- The title bar: the title, the Simple / Advanced editor tabs, then on the
--- right the host's dropdown, Paste text, Undo, Redo and Close.
--- @param decl BlockHost
--- @param embedded boolean inside another editor: no title, tabs or Close (that editor has its own)
--- @return Panel
local function _titleBar(decl, embedded)
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
        rmargin = 4,
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
        classes = {"sizeS"},
        width = "auto",
        hpad = 12,
        valign = "center",
        rmargin = 12,
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
    }
    if not embedded then
        tools[#tools + 1] = gui.Button{
            classes = {"closeButton", "sizeS"},
            valign = "center",
            click = function(element)
                _fireControllerEvent(element, "editorClose")
            end,
        }
    end

    if embedded then
        return gui.Panel{
            classes = {"beEditorTitleBar", "beEmbeddedBar"},
            gui.Panel{
                width = "auto",
                height = "auto",
                flow = "horizontal",
                halign = "right",
                valign = "center",
                children = tools,
            },
        }
    end

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

--- The line under the title bar that says when someone else changed the
--- record: a note that fades after a few seconds, or, when this editor has
--- changes of its own still to save, a choice between theirs and ours.
--- @return Panel
local function _noticeBar()
    --- @type Panel
    local bar
    bar = gui.Panel{
        classes = {"beNotice", "collapsed"},
        data = { recordId = nil, serial = 0 },
        gui.Label{
            classes = {"beNoticeText"},
            text = "",
            interactable = false,
        },
        gui.Button{
            classes = {"sizeS", "beNoticeChoice"},
            width = "auto",
            hpad = 12,
            text = T("blockeditor.notice.reload_theirs"),
            click = function(element)
                _fireControllerEvent(element, "editorReloadTheirs", bar.data.recordId)
            end,
        },
        gui.Button{
            classes = {"sizeS", "beNoticeChoice"},
            width = "auto",
            hpad = 12,
            text = T("blockeditor.notice.keep_mine"),
            click = function(element)
                _fireControllerEvent(element, "editorKeepMine", bar.data.recordId)
            end,
        },
        --- @param kind string|nil "updated", "conflict", "closing" (a close waiting on a conflict), or nil to hide
        --- @param recordId string|nil
        --- @param name string|nil the record's name
        editorNotice = function(element, kind, recordId, name)
            element.data.serial = element.data.serial + 1
            element.data.recordId = recordId
            element:SetClass("collapsed", kind == nil)
            if kind == nil then
                return
            end
            local choosing = kind == "conflict" or kind == "closing"
            if kind == "conflict" then
                element.children[1].text = T("blockeditor.notice.conflict", { name = name or "" })
            elseif kind == "closing" then
                element.children[1].text = T("blockeditor.notice.close_conflict", { name = name or "" })
            else
                element.children[1].text = T("blockeditor.notice.updated", { name = name or "" })
            end
            for _, child in ipairs(element.children) do
                if child:HasClass("beNoticeChoice") then
                    child:SetClass("collapsed", not choosing)
                end
            end
            if kind == "updated" then
                --the note goes by itself, unless a newer one replaced it.
                local serial = element.data.serial
                dmhub.Schedule(BlockEditor.NOTICE_SECONDS, function()
                    if mod.unloaded or not element.valid or element.data.serial ~= serial then
                        return
                    end
                    element:FireEvent("editorNotice", nil)
                end)
            end
        end,
    }
    return bar
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

--- The records someone else changed since this editor last saw or wrote them.
--- @param host BlockEditorHost
--- @param state BEState
--- @return table<string, table> current version by record id
local function _changesElsewhere(host, state)
    local result = {}
    if host.changedElsewhere == nil then
        return result
    end
    for id, _ in pairs(state.models) do
        local current = host.changedElsewhere(id)
        if current ~= nil then
            result[id] = current
        end
    end
    return result
end

--- Reads a newer version of a record into the editor in place of the old one.
--- @param state BEState
--- @param host BlockEditorHost
--- @param decl BlockHost
--- @param id string
--- @param current table
local function _reloadRecord(state, host, decl, id, current)
    local source = DeepCopy(current)
    local model = BERecordCache.Open(source, decl)
    model.savesUnchanged = BERecordCache.SavesUnchanged(model, source, decl)
    state:ReplaceRecord(model, source)
    host.adopt(id, current)
end

--- Whether the Block Editor can open this record as blocks: a registered
--- host reads it, and the editor is turned on (developers, for now).
--- @param record table|nil
--- @return boolean
function BlockEditor.CanOpen(record)
    if record == nil or not BlockEditor._isDeveloper() then
        return false
    end
    Block.Gather()
    local decl = Block.FindHost(record)
    return decl ~= nil and decl.fields ~= nil
end

--- Builds the editor for a record: its root panel is the controller. With no
--- record (the developer command) it opens the stub ability host's demo.
--- The record is read from a copy; every save writes into the record itself.
--- @param record? table the record to edit (class, feature, ability, ...)
--- @param options? {embedded?: boolean, changed?: fun(record: table)} embedded: a panel inside another editor, which uploads the record itself; changed: called after each write into the record
--- @return Panel|nil controller the editor's root panel
function BlockEditor.CreatePanel(record, options)
    options = options or {}
    local embedded = options.embedded == true
    --read every registry afresh, so blocks from mods loaded later are included.
    Block.Gather()

    local decl = nil
    local model = nil
    --- @type table|nil the private copy the model is read from and saved against
    local source = nil
    if record ~= nil then
        decl = Block.FindHost(record)
        if decl ~= nil and decl.fields ~= nil then
            source = DeepCopy(record)
            model = BERecordCache.Open(source, decl)
            model.savesUnchanged = BERecordCache.SavesUnchanged(model, source, decl)
        else
            model = _emptyModel(record)
        end
    else
        decl = _demoDecl()
        if decl ~= nil and decl.demo ~= nil then
            model = DeepCopy(decl.demo)
        end
    end
    if decl == nil or model == nil then
        dmhub.Log("The Block Editor has no host for this record yet.")
        return nil
    end
    --- @cast model BERecordModel

    local host = _recordHost(decl, options)
    --- @type table<string, table> per record, the other version the author has not yet chosen about
    local conflicts = {}
    local state = BEState.CreateNew(host)
    state:AddRecord(model, source)
    if record ~= nil and source ~= nil then
        host.track(model, record)
    end

    local SIZES = BEStyles.SIZES
    --- @type table|nil the theme subscription, dropped when the window closes
    local themeSub = nil

    --- @type Panel
    local controller
    controller = gui.Panel{
        classes = {cond(embedded, "beEmbedded", "beWindow"), BlockEditor.CONTROLLER_CLASS},
        styles = ThemeEngine.MergeStyles(BEStyles.GetStyles()),
        width = embedded and "100%" or SIZES.EDITOR_WIDTH,
        height = embedded and "100%" or SIZES.EDITOR_HEIGHT,
        maxWidth = (not embedded) and SIZES.WINDOW_MAX_WIDTH or nil,
        maxHeight = (not embedded) and SIZES.WINDOW_MAX_HEIGHT or nil,
        halign = "center",
        valign = "center",

        data = {
            state = state,
            host = host,
        },

        --inside another editor, Escape belongs to that editor's dialog.
        captureEscape = not embedded,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        escape = function(element)
            --Escape while typing over a word cancels that edit, not the window.
            if BESlots.CancelEdit() then
                return
            end
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
            --A record held for a conflict is not uploaded: their version stays.
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
            --an embedded editor writes into its record at once: nothing goes
            --over the network, and the editor around it may read it any time.
            if host.immediate and state:IsDirty() then
                state:UploadDirty(true)
            end
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

        --- A conflict still waiting stops the close and says so (ledger 2026-11-28).
        editorClose = function(element)
            local held = next(state.held)
            if held ~= nil then
                local model = state:Model(held)
                element:FireEventTree("editorNotice", "closing", held, model ~= nil and model.name or "")
                return
            end
            gui.CloseModal()
        end,

        --- Shows the next record still waiting on a choice, or hides the bar.
        editorNextConflict = function(element)
            local held = next(state.held)
            if held == nil then
                element:FireEventTree("editorNotice", nil)
                return
            end
            local model = state:Model(held)
            element:FireEventTree("editorNotice", "conflict", held, model ~= nil and model.name or "")
        end,

        --Other people's changes (plan 12.6). The window watches the game's
        --tables; inside another editor, that editor owns the record.
        monitorAssets = (not embedded) and decl.locate ~= nil or nil,
        refreshAssets = function(element)
            if mod.unloaded then
                return
            end
            for id, current in pairs(_changesElsewhere(host, state)) do
                local model = state:Model(id)
                local name = model ~= nil and model.name or ""
                if state.dirty[id] == nil and not state.held[id] then
                    --nothing of ours is waiting: show theirs. A word being typed
                    --over is dropped first, as the page is about to be redrawn.
                    BESlots.CancelEdit()
                    _reloadRecord(state, host, decl, id, current)
                    element:FireEvent("editorRefresh")
                    --a conflict bar for another record stays up instead of this note.
                    if not state:AnyHeld() then
                        element:FireEventTree("editorNotice", "updated", id, name)
                    end
                elseif not dmhub.DeepEqual(conflicts[id], current) then
                    --ours is waiting to save: hold it until the author chooses.
                    conflicts[id] = DeepCopy(current)
                    state:Hold(id)
                    element:FireEventTree("editorNotice", "conflict", id, name)
                end
            end
        end,

        --- Drops this editor's changes to a record and shows the other version.
        --- @param id string
        editorReloadTheirs = function(element, id)
            if id == nil then
                return
            end
            local current = host.changedElsewhere(id)
            conflicts[id] = nil
            state:Release(id)
            BESlots.CancelEdit()
            if current ~= nil then
                _reloadRecord(state, host, decl, id, current)
            else
                state.dirty[id] = nil
            end
            element:FireEvent("editorRefresh")
            element:FireEvent("editorNextConflict")
        end,

        --- Keeps this editor's version: it saves over the other one (last save wins).
        --- @param id string
        editorKeepMine = function(element, id)
            if id == nil then
                return
            end
            local current = host.changedElsewhere(id)
            conflicts[id] = nil
            state:Release(id)
            if current ~= nil then
                host.adopt(id, current)
            end
            state.dirty[id] = dmhub.Time() - BlockEditor.UPLOAD_DELAY
            element:FireEvent("editorRefresh")
            element:FireEvent("editorNextConflict")
        end,

        _titleBar(decl, embedded),
        _noticeBar(),
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

    return controller
end

--- Opens the editor on a record, as a modal window. With no record (the
--- developer command) it opens the stub ability host's demo record.
--- @param record? table the record to edit (class, feature, ability, ...)
--- @return Panel|nil controller the editor's root panel
function BlockEditor.Open(record)
    local controller = BlockEditor.CreatePanel(record)
    if controller ~= nil then
        gui.ShowModal(controller)
    end
    return controller
end

Commands.RegisterMacro{
    name = "blockeditor",
    summary = "open an ability in the Block Editor (developers)",
    doc = "Usage: /blockeditor [ability name]\nWith a name, opens that class or subclass ability as blocks; steps no block reads yet open as Advanced blocks. Without one, opens the stub demo (\"Out of the Way!\"). Edits save into the ability's class or subclass two seconds after the last change. Developer mode only.",
    command = function(str)
        if not BlockEditor._isDeveloper() then
            dmhub.Log("The Block Editor is in development: turn on developer mode and the Block Editor setting (developer settings) to open it.")
            return
        end
        local name = trim(str or "")
        if name == "" then
            BlockEditor.Open()
            return
        end
        local record = BERoundTrip.Find(name)
        if record == nil then
            dmhub.Log(string.format("Nothing the Block Editor opens is called '%s'.", name))
            return
        end
        BlockEditor.Open(record)
    end,
}

--The Simple tab of today's ability editor: this editor, inside that one. It
--writes into the ability as it is edited; that editor's dialog uploads it.
if rawget(_G, "AbilityEditor") ~= nil and AbilityEditor.RegisterView ~= nil then
    AbilityEditor.RegisterView{
        id = "blockeditor",
        label = T("blockeditor.tab.simple"),
        tooltip = T("blockeditor.tab.simple_tooltip"),
        available = function(record)
            return not mod.unloaded and BlockEditor.CanOpen(record)
        end,
        create = function(record, options)
            return BlockEditor.CreatePanel(record, { embedded = true, changed = options.changed })
        end,
    }
end
