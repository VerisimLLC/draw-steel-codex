---@meta

--- @class GameCommand
--- @field executing boolean
--- @field busy boolean
--- @field id string
--- @field uniqueid string
--- @field groupid string
--- @field nextInGroup GameCommand
--- @field tokenid string
--- @field description string
--- @field operation any
--- @field path string
--- @field payload string
--- @field undoable boolean
--- @field combine boolean
--- @field forcePutImmediate boolean
--- @field putImmediate any
--- @field patchImmediate table<string, any>
--- @field applyLocally boolean
--- @field localOnly boolean
--- @field generatePayload any
--- @field onUndo any
--- @field onRedo any
--- @field nerrors number
--- @field identifierGuid string
--- @field undoPayload string
--- @field onFinishedExecuting any
--- @field undoing boolean
GameCommand = {}

--- AddCommandToGroup
--- @param cmd? GameCommand
function GameCommand:AddCommandToGroup(cmd) end

--- Execute
--- @param isRedo? boolean
function GameCommand:Execute(isRedo) end

--- Undo
function GameCommand:Undo() end
