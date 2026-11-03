---@meta

--- @class CharacterAppearance
--- @field effectiveTokenScaling number
--- @field hasCardFraming boolean
--- @field portraitId string
--- @field offtokenPortraitId string
--- @field portraitFrameId string
--- @field portraitFrameMaterial string
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
--- @field cardZoom number
--- @field cardOffsetX number
--- @field cardOffsetY number
--- @field popoutMode number
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

--- IsPopout
--- @overload fun(mode?: number, portraitAsset?: GenericImageAsset): boolean
--- @param portraitAsset? GenericImageAsset
--- @return boolean
function CharacterAppearance:IsPopout(portraitAsset) end

--- Equals
--- @param other? CharacterAppearance
--- @return boolean
function CharacterAppearance:Equals(other) end

--- SameAsBestiary
--- @param other? CharacterAppearance
--- @return boolean
function CharacterAppearance:SameAsBestiary(other) end
