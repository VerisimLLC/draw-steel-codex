---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class GenericImageAsset:ImageAsset
--- @field tokenMaskBorder number
--- @field tokenMaskTexture any
--- @field tokenMaskInclusiveTexture any
--- @field textureReadable boolean
GenericImageAsset = {}

--- OnBeforeLoadImage
function GenericImageAsset:OnBeforeLoadImage() end

--- MatchesSearch
--- @param search? string
--- @return boolean
function GenericImageAsset:MatchesSearch(search) end
