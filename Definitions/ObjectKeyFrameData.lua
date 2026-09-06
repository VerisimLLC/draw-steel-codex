---@meta

--- @class ObjectKeyFrameData
--- @field guid string
--- @field name string
--- @field animDuration number
--- @field objectInactive boolean
--- @field components table<string, any>
ObjectKeyFrameData = {}

--- ApproximateEqual
--- @param a? any
--- @param b? any
--- @return boolean
function ObjectKeyFrameData.ApproximateEqual(a, b) end

--- InitFromObject
--- @param obj? any
function ObjectKeyFrameData:InitFromObject(obj) end

--- Restore
--- @param obj? any
--- @param patch? table<string, any>
--- @param unpatch? table<string, any>
function ObjectKeyFrameData:Restore(obj, patch, unpatch) end
