--- @class DiceMaterialHandleLua A handle for reading and setting shader properties on one of a die's materials, used from a dice set's custom script. Writes are 'sticky' -- re-applied every frame until changed -- so they are not overwritten by the dice set's authored properties.
DiceMaterialHandleLua = {}

--- SetColor: Sets a color shader property (e.g. '_SurfaceTint', '_FontGlowColor') on this material. Sticky.
--- @param name string
--- @param color Color
--- @return nil
function DiceMaterialHandleLua:SetColor(name, color)
	-- dummy implementation for documentation purposes only
end

--- SetFloat: Sets a float shader property (e.g. '_SurfaceMetallic', '_MatcapHueShift') on this material. Sticky.
--- @param name string
--- @param value number
--- @return nil
function DiceMaterialHandleLua:SetFloat(name, value)
	-- dummy implementation for documentation purposes only
end

--- GetColor: Reads the current value of a color shader property on this material (the authored value, before this frame's overrides), or black if the property is absent.
--- @param name string
--- @return Color
function DiceMaterialHandleLua:GetColor(name)
	-- dummy implementation for documentation purposes only
end

--- GetFloat: Reads the current value of a float shader property on this material, or 0 if the property is absent.
--- @param name string
--- @return number
function DiceMaterialHandleLua:GetFloat(name)
	-- dummy implementation for documentation purposes only
end
