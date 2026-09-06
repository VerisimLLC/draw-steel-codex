---@meta

--- @class AssetNodeBaseLua
--- @field hidden boolean True if the entry has been 'hidden' in this game (i.e. deleted, but can be undeleted)
--- @field artist string The content creator who created this content.
--- @field imageFileId string
--- @field ord number
--- @field description any
--- @field parentFolder string
--- @field parentNode any
--- @field children any
AssetNodeBaseLua = {}

--- Returns a json representation of this node.
--- @return string
function AssetNodeBaseLua:Backup() end

--- Restores this from json.
--- @param json? string
function AssetNodeBaseLua:Restore(json) end

--- Open the image for this content in a web browser.
function AssetNodeBaseLua:OpenImageUrl() end

--- MatchesSearch
--- @param text? any
--- @return any
function AssetNodeBaseLua:MatchesSearch(text) end

--- GetNodeIdsMatchingSearch
--- @param text? any
--- @return any
function AssetNodeBaseLua:GetNodeIdsMatchingSearch(text) end
