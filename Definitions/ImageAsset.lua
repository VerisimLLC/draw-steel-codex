---@meta

--- An image asset stored in the cloud, with support for keywords, color adjustments, and sprite generation.
--- @class ImageAsset:GameAsset
--- @field previewSpriteRect Vector4
--- @field isVideo boolean
--- @field isLoadedAndVideo boolean?
--- @field sprite Sprite
--- @field sizeInKBytes number
--- @field textureCached boolean
--- @field textureReadable boolean
ImageAsset = {}

--- ValidationCheck
--- @param objtype? string
--- @param guid? string
--- @return boolean
function ImageAsset:ValidationCheck(objtype, guid) end

--- MatchesSearch
--- @param searchLowercase? string
--- @return boolean
function ImageAsset:MatchesSearch(searchLowercase) end

--- OnBeforeLoadImage
function ImageAsset:OnBeforeLoadImage() end

--- GetPivot
--- @param tex? any
--- @return Vector2
function ImageAsset:GetPivot(tex) end

--- GetPPU
--- @param tex? any
--- @return number
function ImageAsset:GetPPU(tex) end

--- SyncSprite
--- @param priority? any
--- @param pin? boolean
function ImageAsset:SyncSprite(priority, pin) end

--- GetAndPollTexture
--- @overload fun(cacheable?: any, error?: any, videoPlayer?: any, pin?: boolean): any
--- @overload fun(videoPlayer?: any): any
--- @param pin? boolean
--- @return any
function ImageAsset:GetAndPollTexture(pin) end

--- GetAndPollUniqueTexture
--- @param id? string
--- @param videoPlayer? any
--- @return any
function ImageAsset:GetAndPollUniqueTexture(id, videoPlayer) end

--- MakeLiveEditSession
--- @return ImageAsset
function ImageAsset:MakeLiveEditSession() end

--- TryEvictTexture
--- @return boolean
function ImageAsset:TryEvictTexture() end

--- ForceTextureReadable
function ImageAsset:ForceTextureReadable() end
