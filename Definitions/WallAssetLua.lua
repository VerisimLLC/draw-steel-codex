---@meta

--- @class WallAssetLua:AssetImageBaseLua
--- @field scale any
--- @field thickness number How wide the wall draws, in units where 1 = half a tile; multiplied by scale. Set from the image height (height / 64) when the wall is uploaded. Visual only: movement and vision blocking ignore it.
--- @field cornerSize any
--- @field shadowMask any
--- @field previewRect any
--- @field tint any
--- @field hueshift any
--- @field saturation any
--- @field brightness any
--- @field contrast any
--- @field invisible any
--- @field openable any Openable walls (doors): when true, every wall operation drawn with this type gets a floating open/close icon, and opening it disables the drawn segment's blocking entirely until closed. Probe inside pcall to detect engine builds without door support.
--- @field openSound any Audio asset id played (networked, all clients) when a door of this wall type is opened.
--- @field closeSound any Audio asset id played (networked, all clients) when a door of this wall type is closed.
--- @field markupColor any Markup wall display color as an html color string like '#ff0000': the DM's wall skeleton overlay and solid-block striping draw every wall of this type in this color. Reads as an empty string (never nil) when unset so pcall probes can detect engine support; set to '' or nil to restore the stock overlay styling.
--- @field markupMapId any Map id this markup wall type is private to: stamped by the Map Markup panel on wall types it creates, hiding them from other maps' pickers until promoted with 'Make Available to All Maps'. Reads as an empty string (never nil) when unset so pcall probes can detect engine support; set to '' or nil to make the wall available game-wide.
--- @field visionOneWay any
--- @field visionWidth any
--- @field visionLimited any Limited vision wall (Foundry's limited sight): sight passes through the first limited wall it meets and is stopped by the second. Only applies when occludesVision is on.
--- @field lightLimited any Limited light wall (Foundry's limited light): light passes through the first limited wall it meets and is stopped by the second. Only applies when occludesLight is on.
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
function WallAssetLua:Upload() end

--- Delete
function WallAssetLua:Delete() end
