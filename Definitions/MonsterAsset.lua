--- @class MonsterAsset:GameAsset Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
MonsterAsset = {}

--- RecordFork
--- @param upstream any
--- @return nil
function MonsterAsset:RecordFork(upstream)
	-- dummy implementation for documentation purposes only
end

--- TryMergeFork
--- @param upstream any
--- @param mine any
--- @return boolean
function MonsterAsset.TryMergeFork(upstream, mine)
	-- dummy implementation for documentation purposes only
end

--- MatchesSearch
--- @param searchLowercase string
--- @return boolean
function MonsterAsset:MatchesSearch(searchLowercase)
	-- dummy implementation for documentation purposes only
end
