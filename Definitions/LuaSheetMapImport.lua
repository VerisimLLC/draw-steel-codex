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
--- @field processingMessage string|nil What the panel is busy with before the image can be shown: 'Optimizing Image' while an over-size image is shrunk in the background, 'Optimizing Video' while a video is checked or converted. Nil when idle.
--- @field zoom any
--- @field tileType any
--- @field lockDimensions boolean
--- @field tileScaling number
--- @field imageDim any
--- @field imageWidth number
--- @field imageHeight number
--- @field showGrid boolean Whether the grid preview is drawn over the map: the grid lines (or hex overlay) and the calibration points. Set it to false to compare against the bare map. True by default.
--- @field gridColor string|nil The grid preview's color as an HTML color string such as '#ffd21f', or nil for the default (cyan lines, white hex dots).
--- @field gridThickness number The grid preview lines' thickness in screen pixels, centred on each line. 1 by default; hex dots grow with it.
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
