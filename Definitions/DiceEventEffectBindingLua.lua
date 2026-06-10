--- @class DiceEventEffectBindingLua A single particle effect bound to a dice lifecycle event, with its own prefab and tunables. One event can have several. Obtain via DiceStudioLua.GetEventEffectList or AddEventEffect.
--- @field effectName string The effect prefab name bound here, or an empty string if this slot is unbound (renders nothing). Set to nil/empty to unbind.
--- @field scale number Uniform scale multiplier (1 = authored size).
--- @field speed number Playback-speed multiplier applied to each child ParticleSystem (1 = authored speed).
--- @field hueShift number Hue-shift amount (0..1 HSV rotation; 0 = unchanged).
--- @field brightness number Brightness multiplier (1 = authored brightness).
--- @field tint Color Multiply tint colour combined with the material's authored tint (white = unchanged).
--- @field xRotation number Whole-degree rotation of the FX root about its local X axis (0 = unchanged). Used in 90-degree steps to flip 'z up' vs 'y up' authored prefabs.
--- @field layerPlacement "auto"|"above"|"below" Where this effect renders relative to the dice: 'auto' (honor the prefab's TopLayer/BottomLayer convention -- the default), 'above' (force above the dice) or 'below' (force beneath the dice).
DiceEventEffectBindingLua = {}
