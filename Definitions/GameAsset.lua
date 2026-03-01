--- @class GameAsset Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @field cachePath string 
--- @field sizeInKBytes number 
GameAsset = {}

--- ValidationCheck
--- @param objtype string
--- @param guid string
--- @return boolean
function GameAsset:ValidationCheck(objtype, guid)
	-- dummy implementation for documentation purposes only
end

--- MatchesSearch
--- @param searchLowercase string
--- @return boolean
function GameAsset:MatchesSearch(searchLowercase)
	-- dummy implementation for documentation purposes only
end

--- OnLoad
--- @return nil
function GameAsset:OnLoad()
	-- dummy implementation for documentation purposes only
end
