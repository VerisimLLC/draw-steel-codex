---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class ClipboardItem:ImageAsset
--- @field dimensions any
ClipboardItem = {}

--- NormalizeErases
function ClipboardItem:NormalizeErases() end

--- Paste
--- @param options? any
function ClipboardItem:Paste(options) end

--- GetPivot
--- @param tex? any
--- @return Vector2
function ClipboardItem:GetPivot(tex) end

--- Upload
function ClipboardItem:Upload() end

--- Delete
function ClipboardItem:Delete() end
