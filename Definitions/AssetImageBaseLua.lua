---@meta

--- @class AssetImageBaseLua:AssetNodeBaseLua
--- @field nodeType string
--- @field isVideo boolean
--- @field loaded boolean
--- @field imageid any
--- @field cachePath nil|string The file on this machine holding the image's bytes as uploaded or downloaded, or nil when it isn't cached here. Its name ends .png whatever its format, which the image loaders sniff. Lets a picture already in the game be handed to something that takes files, such as the map importer.
--- @field width any
--- @field height any
AssetImageBaseLua = {}
