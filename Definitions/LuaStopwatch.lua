---@meta

--- A stopwatch for measuring elapsed time.
--- @class LuaStopwatch
--- @field milliseconds number (Read-only) The number of milliseconds elapsed since the stopwatch was created.
LuaStopwatch = {}

--- Init
function LuaStopwatch:Init() end

--- Stops the stopwatch from counting further.
function LuaStopwatch:Stop() end

--- Stops the stopwatch and logs the elapsed time with the given label to the debug console.
--- @param str? string
function LuaStopwatch:Report(str) end
