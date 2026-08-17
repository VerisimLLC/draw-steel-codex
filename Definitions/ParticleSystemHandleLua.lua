--- @alias ParticleSystemValueArg number|{val: number, maxVal: number?}

--- @class ParticleSystemOptions
--- @field locs Loc[]? Exact tile polygons used as one Mesh emitter. Takes precedence over loc/position; rate scales with covered map area.
--- @field loc Loc? Tile whose center and floor should be used. Takes precedence over position.
--- @field position Vector2Arg? Exact world-space position.
--- @field pos Vector2Arg? Alias for position.
--- @field floorIndex integer? Floor for position; defaults to the current floor.
--- @field image string? Particle image-atlas id, or "none" for the default particle texture.
--- @field rate number? Particles emitted per second; Mesh producers multiply this by their surface area.
--- @field lifetime ParticleSystemValueArg?
--- @field speed ParticleSystemValueArg?
--- @field verticalSpeed number?
--- @field opacity number?
--- @field fadein number?
--- @field fadeout number?
--- @field birthColor Color?
--- @field deathColor Color?
--- @field birthSize number?
--- @field deathSize number?
--- @field producerShape nil|'Circle'|'Edge'|'Rectangle'|'Box'|'Sprite'|'Mesh'
--- @field producerAssetId string? Object asset whose sprite supplies the mask for the Sprite producer shape.
--- @field shape nil|LuaMapPath|Vector2Arg[] Relative producer path used by Mesh.
--- @field producerRadius number?
--- @field producerRotate number?
--- @field producerArc number?
--- @field producerScale Vector3Arg?
--- @field type nil|'Default'|'Lighting'|'Darkness'|'Emissive'
--- @field rotation ParticleSystemValueArg?
--- @field rotationOverLifetime ParticleSystemValueArg?
--- @field position_x number? Local emitter x offset.
--- @field position_y number? Local emitter y offset.
--- @field rotateToVelocity boolean?
--- @field worldSpace boolean?
--- @field dampenSpeed number?
--- @field gravity Vector3Arg?
--- @field noiseStrength ParticleSystemValueArg?
--- @field noiseFrequency number?
--- @field noiseScroll ParticleSystemValueArg?
--- @field maxParticles number?
--- @field renderQueue number?
--- @field parallax number?
--- @field ignoreParallax boolean?
--- @field sortingOrder number?
--- @field duration number? Zero or omitted lasts until Stop().

--- @class ParticleSystemHandleLua A local handle to a particle system created by dmhub.CreateParticleSystem. The effect is removed when Stop()/Destroy() is called, its duration elapses, or the client changes maps.
--- @field alive boolean True while the particle system exists on this client.
ParticleSystemHandleLua = {}

--- Changes any creation option on the live particle system. Passing duration restarts its duration timer; omitted fields retain their current values.
--- @param options ParticleSystemOptions
--- @return nil
function ParticleSystemHandleLua:Set(options)
	-- dummy implementation for documentation purposes only
end

--- Moves the particle system to the center of loc, including its floor.
--- @param loc Loc
--- @return nil
function ParticleSystemHandleLua:SetLoc(loc)
	-- dummy implementation for documentation purposes only
end

--- Replaces the particle producer with a single Mesh emitter covering the exact polygons of locs. All locations must be on one floor; emission rate scales with the covered map area.
--- @param locs Loc[]
--- @return nil
function ParticleSystemHandleLua:SetLocs(locs)
	-- dummy implementation for documentation purposes only
end

--- Moves the particle system to an exact world-space position. Omit floorIndex to keep its current floor.
--- @param position Vector2Arg
--- @param floorIndex number?
--- @return nil
function ParticleSystemHandleLua:SetPosition(position, floorIndex)
	-- dummy implementation for documentation purposes only
end

--- Removes the particle system immediately. Safe to call more than once.
--- @return nil
function ParticleSystemHandleLua:Stop()
	-- dummy implementation for documentation purposes only
end

--- Alias for Stop().
--- @return nil
function ParticleSystemHandleLua:Destroy()
	-- dummy implementation for documentation purposes only
end
