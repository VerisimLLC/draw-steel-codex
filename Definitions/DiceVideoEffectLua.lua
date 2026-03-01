--- @class DiceVideoEffectLua Represents a video effect that can be applied to dice rolls.
--- @field id string The unique identifier of this video effect.
--- @field video string The video asset path for this effect.
--- @field blend string The blend mode used when compositing this effect.
--- @field scale LuaVector2 The scale of the video effect as a 2D vector.
--- @field beginFade number The time in seconds at which the effect begins fading out.
--- @field fadeTime number The duration in seconds of the fade-out transition.
--- @field randomRotation boolean Whether the effect applies a random rotation.
--- @field color Color Sets the tint color of the video effect.
DiceVideoEffectLua = {}
