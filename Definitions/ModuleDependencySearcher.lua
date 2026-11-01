---@meta

--- @class ModuleDependencySearcher
--- @field pending number The number of map downloads still in flight. While above 0, Search results can be missing what those maps use; wait until revision changes and search again.
--- @field revision number Increases each time a map download finishes and adds dependencies. Run Search again when it changes.
ModuleDependencySearcher = {}

--- Search
--- @param dynGuidsSelected? any
--- @return any
function ModuleDependencySearcher:Search(dynGuidsSelected) end
