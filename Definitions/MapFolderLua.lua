---@meta

--- @class MapFolderLua
--- @field id string
--- @field valid boolean
--- @field root boolean
--- @field childFolders any
--- @field childMaps any
--- @field description string
--- @field parentFolder any
--- @field ord number
--- @field folderid string
MapFolderLua = {}

--- MarkUndo
function MapFolderLua:MarkUndo() end

--- Delete
function MapFolderLua:Delete() end

--- Upload
--- @param description? string
function MapFolderLua:Upload(description) end
