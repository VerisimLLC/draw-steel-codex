--- @class analysis Provides a Lua interface for querying and synchronizing analytics data tables.
analysis = {}

--- SetStartingDate: Sets the ending date for the analytics query range.
--- @param year number
--- @param month number
--- @param day number
--- @return nil
function analysis:SetStartingDate(year, month, day)
	-- dummy implementation for documentation purposes only
end

--- SyncTable: Synchronizes a named analytics table from the server, downloading any missing daily entries. The callback is invoked with a status string ('downloaded', 'cached', or 'error') and the date string for each day, then invoked with no arguments when complete.
--- @param tableName string The name of the analytics table to sync.
--- @param completeCallback function Callback invoked per day with (status, dateStr) and once with no args on completion.
function analysis:SyncTable(tableName, completeCallback)
	-- dummy implementation for documentation purposes only
end

--- GetTableData: Gets locally cached data for the named analytics table as a list of tables, each containing a 'date' string and a 'users' table.
--- @param tableName string The name of the analytics table.
--- @return table[]
function analysis:GetTableData(tableName)
	-- dummy implementation for documentation purposes only
end
