---@meta

--- @class InfoBubbleHudLua
--- @field id string
--- @field floorid string
--- @field sheet any
--- @field icon string
--- @field description string
--- @field image string Optional image drawn in place of the round icon badge: an image asset id or anything a gui bgimage accepts. nil or '' = the default badge. Shown at width x height tiles (see width/height), centred on the bubble.
--- @field width number Width in tiles of the bubble's custom image (see image). 0 = the same as height (1 tile when both are 0).
--- @field height number Height in tiles of the bubble's custom image (see image). 0 = the same as width (1 tile when both are 0).
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
