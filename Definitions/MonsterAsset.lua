---@meta

--- Base class for all game assets (images, audio, etc.) stored in the cloud asset system.
--- @class MonsterAsset:GameAsset
--- @field monsterTypeName string
MonsterAsset = {}

--- RecordFork
--- @param upstream? MonsterAsset
function MonsterAsset:RecordFork(upstream) end

--- RecordForkBasisFromUpstream
--- @param upstream? MonsterAsset
--- @return boolean
function MonsterAsset:RecordForkBasisFromUpstream(upstream) end

--- TryMergeFork
--- @param upstream? MonsterAsset
--- @param mine? MonsterAsset
--- @return boolean
function MonsterAsset.TryMergeFork(upstream, mine) end

--- SetMonsterTypeName
--- @param newName? string
--- @return boolean
function MonsterAsset:SetMonsterTypeName(newName) end

--- MatchesSearch
--- @param searchLowercase? string
--- @return boolean
function MonsterAsset:MatchesSearch(searchLowercase) end
