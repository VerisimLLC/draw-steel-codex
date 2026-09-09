---@meta

--- @class SheetContainer
--- @field wrapper any
--- @field sheet any
--- @field width any
--- @field height any
--- @field isCreating boolean
SheetContainer = {}

--- Close
function SheetContainer:Close() end

--- DestroySelf
function SheetContainer:DestroySelf() end

--- Destroy
function SheetContainer:Destroy() end

--- DestroySheet
function SheetContainer:DestroySheet() end

--- SetDirty
--- @param keys? any
function SheetContainer:SetDirty(keys) end
