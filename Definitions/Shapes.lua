---@meta

--- @class Shapes
--- @field pencolor any
--- @field thickness any
Shapes = {}

--- AddLine
--- @param node? any
--- @return any
function Shapes:AddLine(node) end

--- AddPath
--- @param node? any
--- @return any
function Shapes:AddPath(node) end

--- AddDisc
--- @param node? any
--- @return any
function Shapes:AddDisc(node) end

--- GetCurvePoints
--- @param controlPoints? any
--- @param numResults? any
--- @return any
function Shapes:GetCurvePoints(controlPoints, numResults) end

--- SetColor
--- @param shapeid? any
--- @param color? any
function Shapes:SetColor(shapeid, color) end

--- Remove
--- @param id? any
function Shapes:Remove(id) end

--- PushStyle
function Shapes:PushStyle() end

--- PopStyle
function Shapes:PopStyle() end
