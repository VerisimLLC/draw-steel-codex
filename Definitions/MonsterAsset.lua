--- @class MonsterAsset:GameAsset Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @field monsterTypeName string 
MonsterAsset = {}

--- RecordFork
--- @param upstream any
--- @return nil
function MonsterAsset:RecordFork(upstream)
	-- dummy implementation for documentation purposes only
end

--- RecordForkBasisFromUpstream
--- @param upstream any
--- @return boolean
function MonsterAsset:RecordForkBasisFromUpstream(upstream)
	-- dummy implementation for documentation purposes only
end

--- TryMergeFork
--- @param upstream any
--- @param mine any
--- @return boolean
function MonsterAsset.TryMergeFork(upstream, mine)
	-- dummy implementation for documentation purposes only
end

--- SetMonsterTypeName
--- @param newName string
--- @return boolean
function MonsterAsset:SetMonsterTypeName(newName)
	-- dummy implementation for documentation purposes only
end

--- MatchesSearch
--- @param searchLowercase string
--- @return boolean
function MonsterAsset:MatchesSearch(searchLowercase)
	-- dummy implementation for documentation purposes only
end
