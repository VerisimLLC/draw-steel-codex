--- @class TokenEffectsLuaInterface Registry of token effects accessible from Lua. Mods register effects here via Register{...}; the engine resolves an appearance's teleportEffect id against this registry first, then the built-in catalog, then a baked-in fallback.
TokenEffectsLuaInterface = {}

--- Register: Register a new token effect from a table definition.
--- @param table table The effect properties (id, kind, video|particleName, worldSimulation, scale, blend, playbackSpeed, hsv, tint, soundEvent, duration, light, delay, windup, travelTime, travelEffect).
function TokenEffectsLuaInterface:Register(table)
	-- dummy implementation for documentation purposes only
end

--- Get
--- @param id string
--- @return any
function TokenEffectsLuaInterface:Get(id)
	-- dummy implementation for documentation purposes only
end
