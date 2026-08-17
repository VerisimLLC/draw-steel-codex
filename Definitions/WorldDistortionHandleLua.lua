--- @class WorldDistortionHandleLua A local handle to a world distortion created by dmhub.CreateWorldDistortion. The effect is automatically removed when its duration elapses or the client changes map; call Stop() for immediate removal.
--- @field alive boolean True while the distortion is active on this client.
--- @field strength number The effect strength. For heatwave this is displacement in screen pixels; for radial effects it is the kernel's dimensionless strength (vortex uses radians).
--- @field edgeFade number Inward feather width in tiles for heatwave, clamped to 0..0.5. Zero restores a hard tile boundary. Has no effect on radial effects.
--- @field speed number Heatwave rise speed in tiles per second, or radial animation speed in cycles per second. Negative values reverse the motion.
--- @field frequency number Fine shimmer frequency in cycles per tile (heatwave) or cycles across the radius (ripple).
--- @field direction Vector2 Map-space direction in which heatwave plumes rise. The vector is normalized when assigned and defaults to {x=0, y=1}. Has no effect on radial effects.
--- @field plumeWidth number Approximate width of the broad heatwave plumes in tiles. Clamped to at least 0.05. Has no effect on radial effects.
--- @field plumeHeight number Approximate length of the broad heatwave plumes in tiles. Clamped to at least 0.05. Has no effect on radial effects.
--- @field turbulence number Irregular breakup and lateral meandering of heatwave plumes, clamped to 0..1. Has no effect on radial effects.
--- @field shimmer number Amount of fine, faster heatwave detail, clamped to 0..1. Has no effect on radial effects.
--- @field haze number Heatwave softening radius in screen pixels, clamped to 0..4. The three-tap blur follows plume coverage and is disabled at zero. Has no effect on radial effects.
--- @field radius number Radius in map tiles for radial effects. Has no effect on heatwave.
WorldDistortionHandleLua = {}

--- SetCenter: Moves a radial effect to a new map location. Has no effect on heatwave.
--- @param loc Loc
--- @return nil
function WorldDistortionHandleLua:SetCenter(loc)
	-- dummy implementation for documentation purposes only
end

--- SetLocs: Replaces the exact tile mask of a heatwave effect. Has no effect on radial effects.
--- @param locs Loc[]
--- @return nil
function WorldDistortionHandleLua:SetLocs(locs)
	-- dummy implementation for documentation purposes only
end

--- Stop: Removes the distortion immediately. Safe to call more than once.
--- @return nil
function WorldDistortionHandleLua:Stop()
	-- dummy implementation for documentation purposes only
end

--- Destroy: Alias for Stop().
--- @return nil
function WorldDistortionHandleLua:Destroy()
	-- dummy implementation for documentation purposes only
end
