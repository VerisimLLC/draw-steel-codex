---@meta

--- Provides a Lua interface for querying and synchronizing analytics data tables.
--- @class analysis
analysis = {}

--- Sets the ending date for the analytics query range.
--- @param year? number
--- @param month? number
--- @param day? number
function analysis:SetStartingDate(year, month, day) end

--- Synchronizes a named analytics table from the server, downloading any missing daily entries. The callback is invoked with a status string ('downloaded', 'cached', or 'error') and the date string for each day, then invoked with no arguments when complete.
--- @param tableName string The name of the analytics table to sync.
--- @param completeCallback function Callback invoked per day with (status, dateStr) and once with no args on completion.
function analysis:SyncTable(tableName, completeCallback) end

--- Gets locally cached data for the named analytics table as a list of tables, each containing a 'date' string and a 'users' table.
--- @param tableName string The name of the analytics table.
--- @return table[]
function analysis:GetTableData(tableName) end
