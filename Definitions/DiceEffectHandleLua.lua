---@meta

--- A handle to an effect a dice script spawned via die:PlayEffect{...}. Lets the script tweak the spawned effect's particle materials (hue, tint, brightness, or any shader property), resize/rotate it, and stop it. The effect is parented to the die, so it is cleaned up automatically when the die is destroyed.
--- @class DiceEffectHandleLua
--- @field alive boolean True while the spawned effect still exists.
--- @field hue number Convenience: hue-shift the whole effect (the _HueShift particle property), 0..1. Independent of tint/brightness/opacity (it drives a separate property).
--- @field brightness number Convenience: brightness multiplier on the effect (scales the _Brightness particle property). Composes with tint and opacity.
--- @field tint Color Convenience: tint color on the effect (the _TintColor particle property). Composes with opacity, so you can set a color and still lower the opacity independently. The color's own alpha is honored and multiplied by opacity.
--- @field opacity number Convenience: the effect's opacity, 0..1 (1 = fully visible). Works regardless of blend mode -- it fades alpha-blended particles to transparent (scaling _TintColor's alpha) and additive particles to black (scaling _Brightness), the same way the engine fades dice effects at the end of a roll. Composes with tint/brightness and is safe to drive every frame (e.g. fade a trail out over its life).
DiceEffectHandleLua = {}

--- Sets a float shader property on the effect's particle materials (e.g. '_HueShift', '_Brightness'). Sticky on the renderer until changed.
--- @param name string
--- @param value number
--- @return nil
function DiceEffectHandleLua:SetFloat(name, value) end

--- Sets a color shader property on the effect's particle materials (e.g. '_TintColor').
--- @param name string
--- @param color ColorArg
--- @return nil
function DiceEffectHandleLua:SetColor(name, color) end

--- Resize the effect (multiplies its spawn scale).
--- @param scale? number
function DiceEffectHandleLua:Scale(scale) end

--- Rotate the effect about its local X axis, in degrees (flips prefabs authored z-up vs y-up). Replaces any prior rotation.
--- @param degrees? number
function DiceEffectHandleLua:Rotate(degrees) end

--- Stop emission; live particles fade out naturally, then the effect is destroyed.
function DiceEffectHandleLua:Stop() end
