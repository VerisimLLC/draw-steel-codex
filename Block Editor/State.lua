local mod = dmhub.GetModLoading()

--[[
 BEState: what one open editor is editing, its undo and redo, and what still
 has to be uploaded. Design: BLOCK_EDITOR_IMPLEMENTATION_PLAN.md section 12.

 The rule: undo works on the editor's MODEL (small plain tables, one per
 record); the server only ever receives whole records, through the host.

  * Every author action goes through state:Change(description, fn). It copies
    the model of each record the action touches, runs fn, and pushes ONE undo
    entry. Typing in a field is one step when it is committed, not per key.
  * One undo stack and one redo stack for the whole editor, across records
    (a class and its subclasses are separate records). Limit: 100 entries.
  * A changed record is "dirty" until it uploads: two seconds after the last
    change to it, and at once on tab switch, close or Save (UploadDirty(true)).
  * Undo and redo are ordinary changes: they restore the model, mark the
    records dirty, and the same upload path sends the earlier state.

 Not saved anywhere: the stacks are dropped when the editor closes.
]]

--- The editor's model of one record: plain tables only, never panels or
--- engine objects, so it is cheap to copy for undo.
--- @class BERecordModel
--- @field id string the record's id
--- @field name string
--- @field blocks BlockInstance[] the record's blocks, in order (phase 0: one flat list)
--- @field hidden? boolean soft-deleted; undo clears it

--- One undo (or redo) step.
--- @class BEUndoEntry
--- @field description string what the action was, for the button's tooltip
--- @field before table<string, BERecordModel|false> each touched record's model before the step; false if it did not exist

--- @class BEState
--- @field host BlockEditorHost
--- @field models table<string, BERecordModel> by record id
--- @field sources table<string, table> the engine records the models were opened from, by record id
--- @field current string|nil the record the editor is showing
--- @field undoStack BEUndoEntry[]
--- @field redoStack BEUndoEntry[]
--- @field dirty table<string, number> record id -> dmhub.Time() of its last change
--- @field uploads number how many uploads this editor has sent, for the debug readout
BEState = {}
BEState.__index = BEState

--- A new, empty state for one editor.
--- @param host BlockEditorHost
--- @return BEState
function BEState.CreateNew(host)
    local state = {
        host = host,
        models = {},
        sources = {},
        current = nil,
        undoStack = {},
        redoStack = {},
        dirty = {},
        uploads = 0,
    }
    return setmetatable(state, BEState)
end

--- Adds a record to the editor without an undo step (opening is not an edit).
--- @param model BERecordModel
--- @param source? table the engine record it was read from
function BEState:AddRecord(model, source)
    self.models[model.id] = model
    self.sources[model.id] = source
    if self.current == nil then
        self.current = model.id
    end
end

--- The model of a record, or of the record being shown.
--- @param recordId? string
--- @return BERecordModel|nil
function BEState:Model(recordId)
    recordId = recordId or self.current
    if recordId == nil then
        return nil
    end
    return self.models[recordId]
end

--- Shows another record. Pending changes upload first (plan 12.3).
--- @param recordId string
function BEState:SetCurrent(recordId)
    if recordId ~= self.current then
        self:UploadDirty(true)
        self.current = recordId
    end
end

--- Copies the models of some records, for an undo entry.
--- @param recordIds string[]
--- @return table<string, BERecordModel|false>
function BEState:_snapshot(recordIds)
    local result = {}
    for _, id in ipairs(recordIds) do
        local model = self.models[id]
        result[id] = model ~= nil and DeepCopy(model) or false
    end
    return result
end

--- Puts a snapshot back, and marks its records dirty.
--- @param snapshot table<string, BERecordModel|false>
function BEState:_restore(snapshot)
    local now = dmhub.Time()
    for id, model in pairs(snapshot) do
        if model == false then
            --the step created this record: undoing it is a soft delete, so the
            --same upload path removes it and redo can bring it back.
            local created = self.models[id]
            if created ~= nil then
                created.hidden = true
            end
        else
            self.models[id] = DeepCopy(model)
        end
        self.dirty[id] = now
    end
end

--- The ids a snapshot holds, sorted so callers get a stable order.
--- @param snapshot table<string, BERecordModel|false>
--- @return string[]
local function SnapshotIds(snapshot)
    local ids = {}
    for id, _ in pairs(snapshot) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

--- Makes one author action: runs fn, which changes the models, as one undo
--- step. If fn fails nothing is changed and no step is added.
--- @param description string what the action is ("Add Deal damage"), shown on the Undo button
--- @param fn fun(state: BEState) changes self.models
--- @param recordIds? string[] the records fn touches; the record being shown when absent. List a record fn creates too.
--- @return string[]|nil changedIds the records touched, or nil when nothing was changed
function BEState:Change(description, fn, recordIds)
    if recordIds == nil then
        if self.current == nil then
            return nil
        end
        recordIds = { self.current }
    end

    local before = self:_snapshot(recordIds)
    local ok, err = pcall(fn, self)
    if not ok then
        dmhub.Error(string.format("BlockEditor: '%s' failed and was undone: %s", description, tostring(err)))
        for id, model in pairs(before) do
            self.models[id] = model or nil
        end
        return nil
    end

    self.undoStack[#self.undoStack + 1] = { description = description, before = before }
    while #self.undoStack > BlockEditor.UNDO_LIMIT do
        table.remove(self.undoStack, 1)
    end
    self.redoStack = {}

    local now = dmhub.Time()
    for _, id in ipairs(recordIds) do
        self.dirty[id] = now
    end
    return recordIds
end

--- Moves one step between the two stacks, restoring the models it holds.
--- @param from BEUndoEntry[]
--- @param to BEUndoEntry[]
--- @return string[]|nil changedIds
--- @return string|nil description
function BEState:_step(from, to)
    local entry = table.remove(from)
    if entry == nil then
        return nil, nil
    end
    local ids = SnapshotIds(entry.before)
    --what the models are now is what the opposite step puts back.
    to[#to + 1] = { description = entry.description, before = self:_snapshot(ids) }
    self:_restore(entry.before)
    return ids, entry.description
end

--- Undoes the last step. The caller shows the record it touched (so nothing
--- changes out of sight) and refreshes.
--- @return string[]|nil changedIds nil when there was nothing to undo
--- @return string|nil description
function BEState:Undo()
    return self:_step(self.undoStack, self.redoStack)
end

--- Redoes the last undone step.
--- @return string[]|nil changedIds nil when there was nothing to redo
--- @return string|nil description
function BEState:Redo()
    return self:_step(self.redoStack, self.undoStack)
end

--- @return boolean
function BEState:CanUndo()
    return #self.undoStack > 0
end

--- @return boolean
function BEState:CanRedo()
    return #self.redoStack > 0
end

--- What the next Undo would undo, for the button's tooltip.
--- @return string|nil
function BEState:UndoDescription()
    local entry = self.undoStack[#self.undoStack]
    return entry ~= nil and entry.description or nil
end

--- What the next Redo would redo.
--- @return string|nil
function BEState:RedoDescription()
    local entry = self.redoStack[#self.redoStack]
    return entry ~= nil and entry.description or nil
end

--- Whether any record has changes that have not uploaded.
--- @return boolean
function BEState:IsDirty()
    return next(self.dirty) ~= nil
end

--- Uploads dirty records through the host: those whose last change is at
--- least UPLOAD_DELAY old, or all of them with force (tab switch, close, Save).
--- @param force? boolean
--- @return number count how many records were uploaded
function BEState:UploadDirty(force)
    local now = dmhub.Time()
    local due = {}
    for id, changedAt in pairs(self.dirty) do
        if force or now - changedAt >= BlockEditor.UPLOAD_DELAY then
            due[#due + 1] = id
        end
    end
    table.sort(due)

    local canWrite = self.host.canWrite()
    for _, id in ipairs(due) do
        self.dirty[id] = nil
        local model = self.models[id]
        if canWrite and model ~= nil then
            local ok, err = pcall(self.host.upload, self.sources[id], model)
            if ok then
                self.uploads = self.uploads + 1
            else
                dmhub.Error(string.format("BlockEditor: uploading '%s' failed: %s", id, tostring(err)))
            end
        end
    end
    return #due
end

--- The controller's think handler calls this while anything is dirty.
--- @return boolean stillDirty false once every record is clean, so the caller can stop its timer
function BEState:Think()
    if mod.unloaded then
        return false
    end
    self:UploadDirty(false)
    return self:IsDirty()
end
