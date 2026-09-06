---@meta

--- @alias ParticleSystemValueArg number|{val: number, maxVal: number}
---
--- @class ParticleSystemOptions The creation options of a particle system; see dmhub.CreateParticleSystem.
--- @field locs Loc[]|nil
--- @field loc Loc|nil
--- @field position Vector2Arg|nil
--- @field pos Vector2Arg|nil
--- @field floorIndex number|nil
--- @field image string|nil
--- @field rate number|nil
--- @field lifetime ParticleSystemValueArg|nil
--- @field speed ParticleSystemValueArg|nil
--- @field verticalSpeed number|nil
--- @field opacity number|nil
--- @field fadein number|nil
--- @field fadeout number|nil
--- @field birthColor Color|nil
--- @field deathColor Color|nil
--- @field birthSize number|nil
--- @field deathSize number|nil
--- @field producerShape 'Circle'|'Edge'|'Rectangle'|'Box'|'Sprite'|'Mesh'|nil
--- @field producerAssetId string|nil
--- @field shape LuaMapPath|Vector2Arg[]|nil
--- @field producerRadius number|nil
--- @field producerRotate number|nil
--- @field producerArc number|nil
--- @field producerScale Vector3Arg|nil
--- @field type 'Default'|'Lighting'|'Darkness'|'Emissive'|nil
--- @field rotation ParticleSystemValueArg|nil
--- @field rotationOverLifetime ParticleSystemValueArg|nil
--- @field position_x number|nil
--- @field position_y number|nil
--- @field rotateToVelocity boolean|nil
--- @field worldSpace boolean|nil
--- @field dampenSpeed number|nil
--- @field gravity Vector3Arg|nil
--- @field noiseStrength ParticleSystemValueArg|nil
--- @field noiseFrequency number|nil
--- @field noiseScroll ParticleSystemValueArg|nil
--- @field maxParticles number|nil
--- @field renderQueue number|nil
--- @field parallax number|nil
--- @field ignoreParallax boolean|nil
--- @field sortingOrder number|nil
--- @field duration number|nil

--- A local handle to a particle system created by dmhub.CreateParticleSystem. The effect is removed when Stop()/Destroy() is called, its duration elapses, or the client changes maps.
--- @class ParticleSystemHandleLua
--- @field alive boolean True while the particle system exists on this client.
ParticleSystemHandleLua = {}

--- Changes any creation option on the live particle system. Passing duration restarts its duration timer; omitted fields retain their current values.
--- @param options ParticleSystemOptions
--- @return nil
function ParticleSystemHandleLua:Set(options) end

--- Moves the particle system to the center of loc, including its floor.
--- @param loc Loc
--- @return nil
function ParticleSystemHandleLua:SetLoc(loc) end

--- Replaces the particle producer with a single Mesh emitter covering the exact polygons of locs. All locations must be on one floor; emission rate scales with the covered map area.
--- @param locs Loc[]
--- @return nil
function ParticleSystemHandleLua:SetLocs(locs) end

--- Moves the particle system to an exact world-space position. Omit floorIndex to keep its current floor.
--- @param position Vector2Arg
--- @param floorIndex number|nil
--- @return nil
function ParticleSystemHandleLua:SetPosition(position, floorIndex) end

--- Removes the particle system immediately. Safe to call more than once.
function ParticleSystemHandleLua:Stop() end

--- Alias for Stop().
function ParticleSystemHandleLua:Destroy() end
