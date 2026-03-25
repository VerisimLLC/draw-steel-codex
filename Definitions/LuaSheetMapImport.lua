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
--- @return nil
function LuaSheetMapImport:Next()
	-- dummy implementation for documentation purposes only
end

--- Previous
--- @return nil
function LuaSheetMapImport:Previous()
	-- dummy implementation for documentation purposes only
end

--- Confirm
--- @param callback any
--- @return nil
function LuaSheetMapImport:Confirm(callback)
	-- dummy implementation for documentation purposes only
end

--- SetWidth
--- @param w any
--- @return nil
function LuaSheetMapImport:SetWidth(w)
	-- dummy implementation for documentation purposes only
end

--- SetHeight
--- @param h any
--- @return nil
function LuaSheetMapImport:SetHeight(h)
	-- dummy implementation for documentation purposes only
end

--- SetMapDimensions
--- @param tilesW any
--- @param tilesH any
--- @return nil
function LuaSheetMapImport:SetMapDimensions(tilesW, tilesH)
	-- dummy implementation for documentation purposes only
end

--- GetCalibrationData
--- @return any
function LuaSheetMapImport:GetCalibrationData()
	-- dummy implementation for documentation purposes only
end

--- ApplyCalibrationTo
--- @param targetObj any
--- @return nil
function LuaSheetMapImport:ApplyCalibrationTo(targetObj)
	-- dummy implementation for documentation purposes only
end

--- CreateGridless
--- @return nil
function LuaSheetMapImport:CreateGridless()
	-- dummy implementation for documentation purposes only
end

--- ClearMarkers
--- @return nil
function LuaSheetMapImport:ClearMarkers()
	-- dummy implementation for documentation purposes only
end
