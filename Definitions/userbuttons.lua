--- @class userbuttons Provides the Lua interface for the account-wide store of the user's own authored script buttons: uploading a button definition, querying all of them, and deleting one. Definitions are stored gzip+base64 compressed in /UserButtons/{userid}.
userbuttons = {}

--- Upload: Uploads one authored button to the account store. options.id is the button's id (guid-shaped); options.button is the full definition table (name, icon, script, mode, command, description, packid, ...), which is stored gzip+base64 compressed. Stamps mtime server-record-side. Calls options.success with the id. Fails when not signed in or the id is invalid.
--- @param options table Options table with 'id' (string), 'button' (table), 'success' (function(string)), and 'failure' (function(string)) fields.
function userbuttons.Upload(options)
	-- dummy implementation for documentation purposes only
end

--- Query: Queries every button in the current user's account store. Calls options.success with a table mapping buttonid -> { name, packid, mtime, button = <decoded definition table> }, empty when none exist. Records whose payload fails to decode are skipped with a logged error rather than failing the whole query.
--- @param options table Options table with 'success' (function(table)) and 'failure' (function(string)) fields.
function userbuttons.Query(options)
	-- dummy implementation for documentation purposes only
end

--- Delete: Deletes one button from the current user's account store. A button that no longer exists counts as success. Calls options.success with the id.
--- @param options table Options table with 'id' (string), 'success' (function(string)), and 'failure' (function(string)) fields.
function userbuttons.Delete(options)
	-- dummy implementation for documentation purposes only
end
