---@meta

--- @class MonsterAssetLua
--- @field ctime number
--- @field hidden boolean
--- @field info any
--- @field canRotate any
--- @field appearance any
--- @field name any
--- @field description any
--- @field parentFolder any
--- @field source any
--- @field ord any
--- @field properties any
--- @field inCurrentGame boolean
MonsterAssetLua = {}

--- Render
--- @param args? any
--- @param options? any
--- @return any
function MonsterAssetLua:Render(args, options) end

--- GetLocalGameBestiaryToken
--- @return any
function MonsterAssetLua:GetLocalGameBestiaryToken() end

--- DeepCopy
--- @return any
function MonsterAssetLua:DeepCopy() end

--- Duplicate
function MonsterAssetLua:Duplicate() end

--- Upload
function MonsterAssetLua:Upload() end

--- Delete
function MonsterAssetLua:Delete() end

--- ObliterateGameChanges
function MonsterAssetLua:ObliterateGameChanges() end

--- Backup
--- @return string
function MonsterAssetLua:Backup() end

--- Restore
--- @param s? string
function MonsterAssetLua:Restore(s) end
