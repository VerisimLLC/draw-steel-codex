---@meta

--- @class SheetHud
--- @field selectedTokenOverride CharacterToken
--- @field selectedToken any
--- @field selectedOrPrimaryTokens any
--- @field tokens any
--- @field initiativeQueue any
SheetHud = {}

--- PushSelectedTokenOverride
--- @param token? any
function SheetHud:PushSelectedTokenOverride(token) end

--- PopSelectedTokenOverride
function SheetHud:PopSelectedTokenOverride() end

--- GetTokenAbsoluteAltitude
--- @param token? CharacterToken
--- @return number
function SheetHud.GetTokenAbsoluteAltitude(token) end

--- HasVerticalLineOfSight
--- @param originLoc? Loc
--- @param originFloorIndex? number
--- @param targetFloorIndex? number
--- @return boolean
function SheetHud.HasVerticalLineOfSight(originLoc, originFloorIndex, targetFloorIndex) end

--- TokensInShape
--- @param area? any
--- @return any
function SheetHud.TokensInShape(area) end

--- GetToken
--- @param tokenid? any
--- @return any
function SheetHud.GetToken(tokenid) end

--- UploadInitiative
function SheetHud.UploadInitiative() end
