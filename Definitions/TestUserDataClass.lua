---@meta

--- @class TestUserDataClass
--- @field propertyTest number
TestUserDataClass = {}

--- MyFunction
--- @param x? number
--- @return any
function TestUserDataClass:MyFunction(x) end

--- Create
--- @param x? number
--- @return TestUserDataClass
function TestUserDataClass.Create(x) end

--- AddStrings
--- @param a? any
--- @param b? string
--- @return string
function TestUserDataClass:AddStrings(a, b) end

--- VarArgsFunction
--- @param a? number
--- @param ... any
--- @return number
function TestUserDataClass:VarArgsFunction(a, ...) end

--- VarArgsParamsFunction
--- @param a? number
--- @param ... any
--- @return number
function TestUserDataClass:VarArgsParamsFunction(a, ...) end

--- StaticFunction
--- @param a? any
--- @param b? number
--- @param c? number
--- @return number
function TestUserDataClass.StaticFunction(a, b, c) end
