---@meta

--- @class StudioDiceInfo
--- @field localPath string
--- @field id string
--- @field name string
--- @field displayName string
--- @field surfaceMaterialName string
--- @field customDiceModel string
--- @field builtinMaterial DiceMaterialStudioProperties
--- @field surfaceMaterial DiceMaterialStudioProperties
--- @field textMaterial DiceMaterialStudioProperties
--- @field numbersMaterialName string
--- @field surfaceMaterialPerType any[]
--- @field hideBaseMaterial boolean
--- @field finishEffect DiceVideoEffect
--- @field fontMaskName string
--- @field borderMaskName string
--- @field specialMovement string
--- @field teleporting boolean
--- @field teleportVelocity number
--- @field teleportDistance number
--- @field teleportDuration number
--- @field portalCreationTime number
--- @field portalFlashPeriod number
--- @field portalFlashIntensity number
--- @field eventEffects any[]
--- @field eventSounds any[]
--- @field impactFamily string
--- @field impactFamilyVolume number
--- @field physicsEnabled boolean
--- @field physicsGravity number
--- @field physicsVelocity number
--- @field physicsDrag number
--- @field physicsAngularDrag number
--- @field physicsBounciness number
--- @field dicePanelStyles any
--- @field curves any[]
--- @field script string
--- @field slots any
--- @field haloEnabled boolean
--- @field haloColor Color
--- @field haloRadius number
--- @field haloSoftness number
--- @field haloIntensity number
--- @field rayBurstEnabled boolean
--- @field rayBurstColor Color
--- @field rayBurstSize number
--- @field rayBurstDuration number
--- @field rayBurstIntensity number
--- @field rayBurstSaturation number
--- @field rayBurstCount number
--- @field rayBurstContrast number
--- @field rayBurstSpeed number
--- @field rayBurstInnerRadius number
--- @field rayBurstStreaks number
--- @field rayBurstCoreFlash number
--- @field rayBurstRing number
--- @field mapWarpEnabled boolean
--- @field mapWarpStrength number
--- @field mapWarpRadius number
--- @field mapWarpSwirl number
--- @field mapWarpDuration number
--- @field mapWarpFlip boolean
--- @field infallHaloEnabled boolean
--- @field infallHaloReach number
--- @field infallHaloBrightness number
--- @field infallHaloOpacity number
--- @field trailSpritesEnabled boolean
--- @field trailShape string
--- @field trailColorA Color
--- @field trailColorB Color
--- @field trailRate number
--- @field trailSize number
--- @field trailSizeVariation number
--- @field trailLifetime number
--- @field trailFlutter number
--- @field trailSpin number
--- @field trailTwinkle number
--- @field trailGlow number
--- @field trailIntensity number
--- @field trailHueVariation number
--- @field trailFall number
--- @field trailSpread number
--- @field trail2Enabled boolean
--- @field trail2Shape string
--- @field trail2ColorA Color
--- @field trail2ColorB Color
--- @field trail2Rate number
--- @field trail2Size number
--- @field trail2SizeVariation number
--- @field trailHaze number
--- @field trailHazeColor Color
--- @field trailHazeSize number
--- @field trailHazeRate number
--- @field trailHazeGrowth number
--- @field trailHazeWisp number
--- @field trailHazeLifetime number
--- @field trailHazeDrift number
--- @field trailIdle number
--- @field trailBurstCount number
--- @field trailBurstSpeed number
--- @field constellationEnabled boolean
--- @field constellationColor Color
--- @field constellationWidth number
--- @field constellationBrightness number
--- @field constellationDrawTime number
--- @field constellationPulse number
--- @field constellationLoop number
--- @field resultLinger number
--- @field version number
--- @field notes string
--- @field billboardEnabled boolean
--- @field billboardImageAsset string
--- @field billboardImageId string
--- @field billboardColorInner Color
--- @field billboardColorOuter Color
--- @field billboardSize number
--- @field billboardStretch number
--- @field billboardFalloff number
--- @field billboardIntensity number
StudioDiceInfo = {}

--- Save
function StudioDiceInfo:Save() end

--- WriteTo
--- @param dir? string
function StudioDiceInfo:WriteTo(dir) end

--- GetSpecialMovement
--- @return string
function StudioDiceInfo:GetSpecialMovement() end

--- SetSpecialMovement
--- @param mode? string
function StudioDiceInfo:SetSpecialMovement(mode) end

--- GetEventEffect
--- @param ev? any
--- @return string
function StudioDiceInfo:GetEventEffect(ev) end

--- GetEventBinding
--- @param ev? any
--- @return any
function StudioDiceInfo:GetEventBinding(ev) end

--- GetEventBindings
--- @param ev? any
--- @return any[]
function StudioDiceInfo:GetEventBindings(ev) end

--- SetEventEffect
--- @param ev? any
--- @param effectName? string
function StudioDiceInfo:SetEventEffect(ev, effectName) end

--- GetEventSoundBinding
--- @param ev? any
--- @return any
function StudioDiceInfo:GetEventSoundBinding(ev) end

--- GetEventSound
--- @param ev? any
--- @return string
function StudioDiceInfo:GetEventSound(ev) end

--- SetEventSound
--- @param ev? any
--- @param soundEventName? string
function StudioDiceInfo:SetEventSound(ev, soundEventName) end

--- GetEventSoundVolume
--- @param ev? any
--- @return number
function StudioDiceInfo:GetEventSoundVolume(ev) end

--- SetEventSoundVolume
--- @param ev? any
--- @param volume? number
function StudioDiceInfo:SetEventSoundVolume(ev, volume) end
