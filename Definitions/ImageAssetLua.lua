---@meta

--- @class ImageAssetLua:AssetImageBaseLua
--- @field imageType string
--- @field tokenZoom any
--- @field ownerid string
--- @field canView any
--- @field disableCompression boolean
ImageAssetLua = {}

--- HaveReadPermissions
--- @return any
function ImageAssetLua:HaveReadPermissions() end

--- HaveEditPermissions
--- @return boolean
function ImageAssetLua:HaveEditPermissions() end

--- Upload
function ImageAssetLua:Upload() end

--- Delete
function ImageAssetLua:Delete() end
