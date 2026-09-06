---@meta

--- @class UndoState
--- @field undoStack any
--- @field redoStack any
--- @field changes boolean
--- @field undoPending boolean
--- @field redoPending boolean
--- @field undoDescription string
--- @field redoDescription string
UndoState = {}

--- Equals
--- @param other? UndoState
--- @return boolean
function UndoState:Equals(other) end
