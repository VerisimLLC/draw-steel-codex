--- @class WallAssetLua:AssetImageBaseLua 
--- @field scale any 
--- @field cornerSize any 
--- @field shadowMask any 
--- @field previewRect any 
--- @field tint any 
--- @field hueshift any 
--- @field saturation any 
--- @field brightness any 
--- @field contrast any 
--- @field invisible any
--- @field openable boolean Openable walls (doors): when true, every wall operation drawn with this type gets a floating open/close icon, and opening it disables the drawn segment's blocking entirely until closed. Probe inside pcall to detect engine builds without door support.
--- @field openSound nil|string Audio asset id played (networked, all clients) when a door of this wall type is opened.
--- @field closeSound nil|string Audio asset id played (networked, all clients) when a door of this wall type is closed.
--- @field visionOneWay any
--- @field visionWidth any 
--- @field movementOneWay any 
--- @field occludesVision any 
--- @field occludesLight any 
--- @field renderParallax any 
--- @field blocksMovement any 
--- @field blocksForcedMovement any 
--- @field blocksFlying any 
--- @field cover any 
--- @field soundOcclusion any 
--- @field wallHeight any 
--- @field shadowDistortion any 
--- @field taper any 
--- @field parallax any 
--- @field shadowGlowThickness any 
--- @field climbable any 
--- @field solidity any 
--- @field breakStamina any 
--- @field rubbleKeyword any 
--- @field rubbleTerrainId any 
--- @field breakSound any 
--- @field replacementWallId any 
WallAssetLua = {}

--- Upload
--- @return nil
function WallAssetLua:Upload()
	-- dummy implementation for documentation purposes only
end

--- Delete
--- @return nil
function WallAssetLua:Delete()
	-- dummy implementation for documentation purposes only
end
