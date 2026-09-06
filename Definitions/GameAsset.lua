---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class GameAsset
--- @field cachePath string
--- @field sizeInKBytes number
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
