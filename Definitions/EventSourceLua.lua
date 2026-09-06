---@meta

--- @class EventSourceLua
--- @field hasListeners boolean
EventSourceLua = {}

--- Listen
--- @param panel? any
function EventSourceLua:Listen(panel) end

--- Unlisten
--- @param panel? any
function EventSourceLua:Unlisten(panel) end

--- Push
function EventSourceLua:Push() end

--- Pop
function EventSourceLua:Pop() end
