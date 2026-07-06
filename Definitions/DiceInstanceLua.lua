--- @class DiceInstanceLua A live handle to a single die instance, passed to a dice set's custom script as `die`. Use it to inspect the die's state (phase, motion, current face) and to apply sticky appearance overrides (hue, color, alpha, or any shader property). Physics is read-only. The handle is valid only while die.alive is true; once the die is destroyed or its script is replaced, alive becomes false and the script's loop should exit.
--- @field guid string The per-die unique id, or an empty string before the roll is finalized.
--- @field numFaces number The number of faces on this die (e.g. 6, 20).
--- @field maxFace number The highest face value on this die.
--- @field category string The roll category this die belongs to (e.g. 'default', 'slashing').
--- @field alive boolean True while this handle is bound to a live die running the current script. The main loop should run `while die.alive do ... end`.
--- @field state string The die's lifecycle phase: 'waiting' (preview, not yet rolled), 'rolling' (tumbling), 'result' (landed, showing its face), or 'exiting' (fading out post-roll).
--- @field rolling boolean True iff state == 'rolling'.
--- @field settled boolean True iff state == 'result' (the die has landed on its face).
--- @field preview boolean True iff state == 'waiting' (a preview die that has not been rolled).
--- @field time number Seconds since this die appeared.
--- @field timeRemaining number Seconds remaining in the roll's replay, or -1 if not replaying.
--- @field face number The current up-most face value of the die. Meaningful once it has nearly landed; it jitters while tumbling.
--- @field faceError number How far the die is from cleanly resting on a face: 0 (exactly on a face) to 1. High while tumbling.
--- @field isMax boolean True iff the current top face equals the die's maximum face (a natural max / crit).
--- @field speed number The die's linear speed (magnitude of its velocity), low-pass smoothed so it does not spike down on every impact -- use this to drive effects. Works while rolling on the rolling client and during replay on other clients. See rawSpeed for the unsmoothed value.
--- @field rawSpeed number The die's instantaneous (unsmoothed) linear speed. Spikes sharply on impacts; use 'speed' for a stable value to drive effects, or this if you specifically want to detect impacts.
--- @field spin number The die's angular speed in radians/second.
--- @field velocity LuaVector3 The die's velocity vector.
--- @field position LuaVector3 The die's position in the dice playfield.
--- @field height number The die's height above the playfield floor (its y coordinate).
--- @field hue number Hue shift applied to the die's surface tint, 0..1 (wraps). Sticky: it stays until changed. On dice with a surface-override material that exposes a hue knob (e.g. MatCap's _MatcapHueShift) the shift is applied there too, since the override -- not the base tint -- is what is visible.
--- @field saturation number Saturation multiplier on the die's surface tint (1 = unchanged). Sticky.
--- @field brightness number Brightness (value) multiplier on the die's surface tint (1 = unchanged). Sticky.
--- @field alpha number Die-wide opacity multiplier, 0..1 (1 = fully opaque). Sticky.
--- @field color Color Sets the die's main surface color directly (the _SurfaceTint shader property). Sticky.
--- @field halo boolean Turns this die's glowing outline/halo on or off. Sticky. Overrides the dice set's authored Halo 'enabled' setting.
--- @field haloColor Color Sets the color of this die's outline/halo (HDR). Sticky. Setting it also turns the halo on unless die.halo was explicitly set false.
--- @field haloRadius number Thickness of this die's outline/halo in die-local units (0 = none). Sticky. Setting it > 0 also turns the halo on unless die.halo was explicitly set false.
--- @field haloSoftness number Softness of this die's outline/halo outer edge, 0 (crisp) to 1 (soft glow). Sticky.
--- @field haloIntensity number HDR brightness multiplier of this die's outline/halo (higher = glows brighter). Sticky.
--- @field billboard boolean Turns this die's inner billboard glow on or off. Sticky. Overrides the dice set's authored Billboard 'enabled' setting.
--- @field billboardColor Color Sets the center color of this die's billboard glow gradient (HDR); in image mode it tints the image. Sticky. Setting it also turns the billboard on unless die.billboard was explicitly set false.
--- @field billboardColorOuter Color Sets the outer/edge color of this die's billboard glow gradient (HDR). Gradient mode only. Sticky.
--- @field billboardSize number Size of this die's billboard glow as a fraction of the die's bounding-box size (1 = die-sized, 0 = none). Sticky. Setting it > 0 also turns the billboard on unless die.billboard was explicitly set false.
--- @field billboardFalloff number Falloff exponent of this die's billboard glow gradient (higher = tighter core). Gradient mode only. Sticky.
--- @field billboardIntensity number HDR brightness multiplier of this die's billboard glow (higher = glows brighter). Sticky.
--- @field billboardRotation number Rotation of this die's billboard glow in degrees about the view axis (useful to spin an image as the die rolls). Sticky.
--- @field material any Handle for reading/setting any shader property on the die's base material. Sticky writes.
--- @field surface any Handle for reading/setting any shader property on the die's surface-override material (the MatCap/PBR overlay). Has no visible effect when the set has no surface override.
DiceInstanceLua = {}

--- ClearOverrides: Removes all sticky overrides set by the script, reverting the die to its authored appearance.
--- @return nil
function DiceInstanceLua:ClearOverrides()
	-- dummy implementation for documentation purposes only
end

--- PlayEffect: Spawns a named library effect on this die and returns a handle for tweaking it (DiceEffectHandleLua), or nil if the effect name does not resolve. The effect names are the same ones shown in the Dice Studio particle picker. args fields: id (string, required -- the effect name; 'name' is also accepted), scale (number, default 1), speed (number, default 1, particle simulation-speed multiplier), hue (number 0..1, default 0), brightness (number, default 1), tint (Color, default white), rotate (number degrees about X, default 0), attach (boolean, default true -- the effect follows the die; false leaves it at the die's current spot), layer (string, default 'above' -- 'below' renders the effect beneath the dice instead), trail (boolean, default false -- leave the emitted particles behind in the playfield as the die moves, instead of having them travel with it). Call it once (e.g. guarded on a state change), NOT every frame, or you will spawn an effect per frame.
--- @param args table
--- @return DiceEffectHandleLua|nil
function DiceInstanceLua:PlayEffect(args)
	-- dummy implementation for documentation purposes only
end
