---@meta

--- @class BillboardHandleLua
BillboardHandleLua = {}

--- End the billboard immediately.
function BillboardHandleLua:Stop() end

--- Move the billboard to a new location.
--- @param pos Loc
function BillboardHandleLua:Position(pos) end

--- Resize the billboard.
--- @param scale? number
function BillboardHandleLua:Scale(scale) end
