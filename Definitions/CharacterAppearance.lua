---@meta

--- @class CharacterAppearance
--- @field effectiveTokenScaling number
--- @field portraitId string
--- @field offtokenPortraitId string
--- @field portraitFrameId string
--- @field portraitRibbon string
--- @field backgroundId string
--- @field anthem string
--- @field anthemVolume number
--- @field tokenScaling number
--- @field tokenZoom number
--- @field portraitOffset Vector2
--- @field frameHueShift number
--- @field frameSaturation number
--- @field frameBrightness number
--- @field popoutScale number
--- @field characterName string
--- @field characterNamePrivate boolean
--- @field flip boolean
--- @field hideShadow boolean
--- @field saddlePositions Vector2[]
--- @field saddles number
--- @field saddleSize number
--- @field teleportAnimation string
CharacterAppearance = {}

--- GetPortraitId
--- @return string
function CharacterAppearance:GetPortraitId() end

--- GetOffTokenPortraitId
--- @return string
function CharacterAppearance:GetOffTokenPortraitId() end

--- Equals
--- @param other? CharacterAppearance
--- @return boolean
function CharacterAppearance:Equals(other) end

--- SameAsBestiary
--- @param other? CharacterAppearance
--- @return boolean
function CharacterAppearance:SameAsBestiary(other) end
