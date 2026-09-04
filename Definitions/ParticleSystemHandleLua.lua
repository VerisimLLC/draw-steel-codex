--- @class ParticleSystemHandleLua A local handle to a particle system created by dmhub.CreateParticleSystem. The effect is removed when Stop()/Destroy() is called, its duration elapses, or the client changes maps.
--- @field alive boolean True while the particle system exists on this client.
ParticleSystemHandleLua = {}

--- Set: Changes any creation option on the live particle system. Passing duration restarts its duration timer; omitted fields retain their current values.
--- @param options ParticleSystemOptions
--- @return nil
function ParticleSystemHandleLua:Set(options)
	-- dummy implementation for documentation purposes only
end

--- SetLoc: Moves the particle system to the center of loc, including its floor.
--- @param loc Loc
--- @return nil
function ParticleSystemHandleLua:SetLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- SetLocs: Replaces the particle producer with a single Mesh emitter covering the exact polygons of locs. All locations must be on one floor; emission rate scales with the covered map area.
--- @param locs Loc[]
--- @return nil
function ParticleSystemHandleLua:SetLocs(locs)
	-- dummy implementation for documentation purposes only
end

--- SetPosition: Moves the particle system to an exact world-space position. Omit floorIndex to keep its current floor.
--- @param position Vector2Arg
--- @param floorIndex number|nil
--- @return nil
function ParticleSystemHandleLua:SetPosition(position, floorIndex)
	-- dummy implementation for documentation purposes only
end

--- Stop: Removes the particle system immediately. Safe to call more than once.
--- @return nil
function ParticleSystemHandleLua:Stop()
	-- dummy implementation for documentation purposes only
end

--- Destroy: Alias for Stop().
--- @return nil
function ParticleSystemHandleLua:Destroy()
	-- dummy implementation for documentation purposes only
end
