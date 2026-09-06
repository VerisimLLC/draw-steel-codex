---@meta

--- @class ObjectKeyFrameData
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
