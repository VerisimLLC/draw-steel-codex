---@meta

--- @class LuaSheetMapImport:Panel
--- @field errorMessage any
--- @field path any
--- @field paths any
--- @field imageFromId string Set the image to display from a cloud image ID (asset ID or md5:hash). This loads the image from the ImageManager cache instead of a local file path.
--- @field pathIndex any
--- @field instructionsText any
--- @field haveConfirm any
--- @field haveNext any
--- @field havePrevious any
--- @field tileDim any
--- @field error any
--- @field zoom any
--- @field tileType any
--- @field lockDimensions boolean
--- @field tileScaling number
--- @field imageDim any
--- @field imageWidth number
--- @field imageHeight number
LuaSheetMapImport = {}

--- Next
function LuaSheetMapImport:Next() end

--- Previous
function LuaSheetMapImport:Previous() end

--- Confirm
--- @param callback? any
function LuaSheetMapImport:Confirm(callback) end

--- SetWidth
--- @param w? any
function LuaSheetMapImport:SetWidth(w) end

--- SetHeight
--- @param h? any
function LuaSheetMapImport:SetHeight(h) end

--- SetMapDimensions
--- @param tilesW? any
--- @param tilesH? any
function LuaSheetMapImport:SetMapDimensions(tilesW, tilesH) end

--- GetCalibrationData
--- @return any
function LuaSheetMapImport:GetCalibrationData() end

--- ApplyCalibrationTo
--- @param targetObj? any
function LuaSheetMapImport:ApplyCalibrationTo(targetObj) end

--- CreateGridless
function LuaSheetMapImport:CreateGridless() end

--- ClearMarkers
function LuaSheetMapImport:ClearMarkers() end
