--- @class LuaShape 
--- @field perimeter Vector2[] 
--- @field xpos number 
--- @field ypos number 
--- @field shape SpellShapes 
--- @field radius number 
--- @field origin Loc 
--- @field locations Loc[] 
LuaShape = {}

--- Clone
--- @return any
function LuaShape:Clone()
	-- dummy implementation for documentation purposes only
end

--- Grow
--- @param namount number
--- @return any
function LuaShape:Grow(namount)
	-- dummy implementation for documentation purposes only
end

--- ContainsToken
--- @param token any
--- @return boolean
function LuaShape:ContainsToken(token)
	-- dummy implementation for documentation purposes only
end

--- Mark: Mark this shape on the map, returning a reference that you should call Destroy() on when you want to stop displaying it.
--- @param args {color: Color, video: nil|string, showLocs: nil|boolean}
--- @return LuaObjectReference
function LuaShape:Mark(args)
	-- dummy implementation for documentation purposes only
end

--- Equal
--- @param other LuaShape
--- @return boolean
function LuaShape:Equal(other)
	-- dummy implementation for documentation purposes only
end
