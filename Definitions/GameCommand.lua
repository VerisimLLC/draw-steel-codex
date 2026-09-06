---@meta

--- @class GameCommand
--- @field executing boolean
--- @field busy boolean
GameCommand = {}

--- AddCommandToGroup
--- @param cmd? GameCommand
function GameCommand:AddCommandToGroup(cmd) end

--- Execute
--- @param isRedo? boolean
function GameCommand:Execute(isRedo) end

--- Undo
function GameCommand:Undo() end
