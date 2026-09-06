---@meta

--- @class InfoBubbleHudLua
--- @field id string
--- @field floorid string
--- @field sheet any
--- @field icon string
--- @field description string
--- @field document any
--- @field draggedRecently boolean
--- @field locked boolean
InfoBubbleHudLua = {}

--- BeginChanges
function InfoBubbleHudLua:BeginChanges() end

--- CompleteChanges
--- @param description? string
function InfoBubbleHudLua:CompleteChanges(description) end

--- Delete
function InfoBubbleHudLua:Delete() end

--- BeginDragging
function InfoBubbleHudLua:BeginDragging() end
