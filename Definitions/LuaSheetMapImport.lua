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

--- Sets the grid from a result of assets:DetectImageGrid and skips straight to reviewing it, as if every calibration point had been placed perfectly by hand; Confirm then imports with that grid (and, for hexes, the matching tile type and map layout settings). grid needs tileType ('squares', 'flattop' or 'pointtop'), periodX, periodY, originX and originY, in image pixels with y down. Returns false, changing nothing, if the image hasn't loaded yet or the grid doesn't fit it.
--- @param grid {tileType: string, periodX: number, periodY: number, originX: number, originY: number}
--- @return boolean
function LuaSheetMapImport:ApplyDetectedGrid(grid) end

--- Removes every calibration point and starts the grid sizing over from its first step, zoomed out to the whole image. Use it to hand an automatically set grid (ApplyDetectedGrid, CreateGridless) back to the user to place by hand.
function LuaSheetMapImport:ResetCalibration() end
