---@meta

--- @class StudioDiceInfo
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
