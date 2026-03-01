--- @class net Provides HTTP networking utilities for making GET and POST requests from Lua.
net = {}

--- Get: Performs an asynchronous HTTP GET request. The response body is parsed as JSON and passed to the success callback. On failure, an error message string is passed to the error callback.
--- @param args {url: string, success: nil|fun(response: table), error: nil|fun(message: string), headers: nil|table<string, string>}
function net.Get(args)
	-- dummy implementation for documentation purposes only
end

--- Post: Performs an asynchronous HTTP POST request with a JSON body. The data table is serialized to JSON. On success, the response is parsed as JSON and passed to the success callback. Requests to DMHub cloud services automatically include authentication credentials.
--- @param args {url: string, data: table, success: nil|fun(response: table), error: nil|fun(message: string), headers: nil|table<string, string>, timeout: nil|number}
function net.Post(args)
	-- dummy implementation for documentation purposes only
end
