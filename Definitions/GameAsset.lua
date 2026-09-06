---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class GameAsset
--- @field cachePath string
--- @field sizeInKBytes number
--- @field assetStore any
--- @field description string Human-readable description of this asset.
--- @field parentFolder string The identifier of the folder containing this asset.
--- @field artist string The identifier of the artist who created this asset.
--- @field ord number Sort order value for display ordering.
--- @field ctime number Unix timestamp when this asset was created.
--- @field mtime number Unix timestamp when this asset was last modified.
--- @field hidden boolean True if this asset is hidden (soft-deleted). Hidden assets are not shown to users but existing references continue working.
GameAsset = {}

--- ValidationCheck
--- @param objtype? string
--- @param guid? string
--- @return boolean
function GameAsset:ValidationCheck(objtype, guid) end

--- MatchesSearch
--- @param searchLowercase? string
--- @return boolean
function GameAsset:MatchesSearch(searchLowercase) end

--- OnLoad
function GameAsset:OnLoad() end
