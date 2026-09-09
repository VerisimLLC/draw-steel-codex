---@meta

--- @class DiceMaterialStudioProperties
DiceMaterialStudioProperties = {}

--- Clone
--- @return DiceMaterialStudioProperties
function DiceMaterialStudioProperties:Clone() end

--- ToDebugString
--- @return string
function DiceMaterialStudioProperties:ToDebugString() end

--- TryGetFloat
--- @param s? string
--- @param f? any
--- @return boolean
function DiceMaterialStudioProperties:TryGetFloat(s, f) end

--- TryGetColor
--- @param s? string
--- @param col? any
--- @return boolean
function DiceMaterialStudioProperties:TryGetColor(s, col) end

--- GetFloat
--- @param s? string
--- @param defaultValue? any
--- @return number
function DiceMaterialStudioProperties:GetFloat(s, defaultValue) end

--- GetColor
--- @param s? string
--- @return any
function DiceMaterialStudioProperties:GetColor(s) end

--- GetTexture
--- @param s? string
--- @param index? any
--- @return any
function DiceMaterialStudioProperties:GetTexture(s, index) end

--- HasTextureArray
--- @param s? string
--- @return boolean
function DiceMaterialStudioProperties:HasTextureArray(s) end

--- CreateTextureArray
--- @param s? string
function DiceMaterialStudioProperties:CreateTextureArray(s) end

--- DestroyTextureArray
--- @param s? string
function DiceMaterialStudioProperties:DestroyTextureArray(s) end

--- SetFloat
--- @param s? string
--- @param f? number
function DiceMaterialStudioProperties:SetFloat(s, f) end

--- SetColor
--- @param s? string
--- @param c? any
function DiceMaterialStudioProperties:SetColor(s, c) end

--- SetTexture
--- @param s? string
--- @param t? string
--- @param index? any
function DiceMaterialStudioProperties:SetTexture(s, t, index) end

--- DiceFacesToIndex
--- @param numFaces? number
--- @return number
function DiceMaterialStudioProperties.DiceFacesToIndex(numFaces) end

--- DiceFacesToSurfaceMaterialIndex
--- @param numFaces? number
--- @return number
function DiceMaterialStudioProperties.DiceFacesToSurfaceMaterialIndex(numFaces) end
