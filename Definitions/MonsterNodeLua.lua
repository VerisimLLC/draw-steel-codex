---@meta

--- @class MonsterNodeLua
--- @field hidden boolean (Read-only) true if the entry has been 'hidden' in this game (i.e. deleted, but can be undeleted)
--- @field ord number The ordering of the node, controls whether it is displayed before or after its siblings.
--- @field description string
--- @field monster nil|MonsterAssetLua (Read-only) Get the monster entry if this is a monster, or nil if it's actually a folder.
--- @field folder nil|MonsterFolderLua (Read-only) Get the folder entry if this is a folder, or nil if it's actually a monster.
--- @field children MonsterNodeLua[]
--- @field parentNode string
--- @field id string
MonsterNodeLua = {}

--- Create a duplicate of this entry in the bestiary.
function MonsterNodeLua:Duplicate() end

--- Save any changes made to this entry to the cloud.
function MonsterNodeLua:Upload() end

--- Delete this bestiary entry.
function MonsterNodeLua:Delete() end

--- Destroy any changes made to this bestiary entry in this game. If it was first created in this game it will be destroyed and unrecoverable.
function MonsterNodeLua:ObliterateGameChanges() end

--- Given a search string, returns true if the entry matches it.
--- @param text string
--- @return boolean
function MonsterNodeLua:MatchesSearch(text) end
