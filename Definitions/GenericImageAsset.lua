--- @class GenericImageAsset:ImageAsset An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @field tokenMaskBorder number 
--- @field tokenMaskTexture any 
--- @field tokenMaskInclusiveTexture any 
--- @field textureReadable boolean 
GenericImageAsset = {}

--- OnBeforeLoadImage
--- @return nil
function GenericImageAsset:OnBeforeLoadImage()
	-- dummy implementation for documentation purposes only
end

--- MatchesSearch
--- @param search string
--- @return boolean
function GenericImageAsset:MatchesSearch(search)
	-- dummy implementation for documentation purposes only
end
