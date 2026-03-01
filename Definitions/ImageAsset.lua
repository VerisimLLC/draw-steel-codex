--- @class ImageAsset:GameAsset An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @field previewSpriteRect any 
--- @field isVideo boolean 
--- @field isLoadedAndVideo any 
--- @field sprite any 
--- @field sizeInKBytes number 
--- @field textureCached boolean 
--- @field textureReadable boolean 
ImageAsset = {}

--- ValidationCheck
--- @param objtype string
--- @param guid string
--- @return boolean
function ImageAsset:ValidationCheck(objtype, guid)
	-- dummy implementation for documentation purposes only
end

--- MatchesSearch
--- @param searchLowercase string
--- @return boolean
function ImageAsset:MatchesSearch(searchLowercase)
	-- dummy implementation for documentation purposes only
end

--- OnBeforeLoadImage
--- @return nil
function ImageAsset:OnBeforeLoadImage()
	-- dummy implementation for documentation purposes only
end

--- GetPivot
--- @param tex any
--- @return any
function ImageAsset:GetPivot(tex)
	-- dummy implementation for documentation purposes only
end

--- GetPPU
--- @param tex any
--- @return number
function ImageAsset:GetPPU(tex)
	-- dummy implementation for documentation purposes only
end

--- SyncSprite
--- @param priority any?
--- @param pin boolean?
--- @return nil
function ImageAsset:SyncSprite(priority, pin)
	-- dummy implementation for documentation purposes only
end

--- GetAndPollTexture
--- @param pin boolean?
--- @return any
function ImageAsset:GetAndPollTexture(pin)
	-- dummy implementation for documentation purposes only
end

--- GetAndPollTexture
--- @param cacheable any
--- @param error any
--- @param videoPlayer any
--- @param pin boolean?
--- @return any
function ImageAsset:GetAndPollTexture(cacheable, error, videoPlayer, pin)
	-- dummy implementation for documentation purposes only
end

--- GetAndPollTexture
--- @param videoPlayer any
--- @return any
function ImageAsset:GetAndPollTexture(videoPlayer)
	-- dummy implementation for documentation purposes only
end

--- GetAndPollUniqueTexture
--- @param id string
--- @param videoPlayer any
--- @return any
function ImageAsset:GetAndPollUniqueTexture(id, videoPlayer)
	-- dummy implementation for documentation purposes only
end

--- MakeLiveEditSession
--- @return any
function ImageAsset:MakeLiveEditSession()
	-- dummy implementation for documentation purposes only
end

--- TryEvictTexture
--- @return boolean
function ImageAsset:TryEvictTexture()
	-- dummy implementation for documentation purposes only
end

--- ForceTextureReadable
--- @return nil
function ImageAsset:ForceTextureReadable()
	-- dummy implementation for documentation purposes only
end
