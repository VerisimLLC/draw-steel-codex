--- @class TokenAnimationsLuaInterface Registry of token animations. Mods register category-specific entries via RegisterTeleport / RegisterDeath / RegisterTransformation. Each category has an `xxxAnimations` table iterable from Lua (`for id, entry in pairs(dmhub.tokenAnimations.teleportAnimations) do ... end`).
TokenAnimationsLuaInterface = {}

--- RegisterTeleport: Register a teleport animation. The `animation` function is called locally on each client when a token with appearance.teleportAnimation == this id teleports. Signature: function(token: CharacterToken, targetLoc: Loc, opts: table). The opts table has fields crossMap (boolean), fromLoc (Loc), fromMap (string).
--- @param entry table { id: string, name: string|nil, animation: fun(token, targetLoc, opts) }
function TokenAnimationsLuaInterface:RegisterTeleport(entry)
	-- dummy implementation for documentation purposes only
end

--- RegisterDeath: Register a death animation. Reserved for future use.
--- @param entry table { id: string, name: string|nil, animation: fun(token, opts) }
function TokenAnimationsLuaInterface:RegisterDeath(entry)
	-- dummy implementation for documentation purposes only
end

--- RegisterTransformation: Register a transformation (shape-change) animation. Reserved for future use.
--- @param entry table { id: string, name: string|nil, animation: fun(token, opts) }
function TokenAnimationsLuaInterface:RegisterTransformation(entry)
	-- dummy implementation for documentation purposes only
end

--- GetTeleportAnimationFn
--- @param id string
--- @return any
function TokenAnimationsLuaInterface:GetTeleportAnimationFn(id)
	-- dummy implementation for documentation purposes only
end
