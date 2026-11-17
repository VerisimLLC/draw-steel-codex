---@meta

--- Provides HTTP networking utilities for making GET and POST requests from Lua.
--- @class net
net = {}

--- Performs an asynchronous HTTP GET request. The response body is parsed as JSON and passed to the success callback. On failure the error callback gets the error message, the HTTP status (0 when there was no response) and the parsed JSON body of the error response when it has one. quiet = true keeps the response out of the logs (use it for requests that carry credentials).
--- @param args {url: string, success: nil|fun(response: table), error: nil|fun(message: string, status: integer, body: nil|table), headers: nil|table<string, string>, quiet: nil|boolean}
function net.Get(args) end

--- Performs an asynchronous HTTP POST request with a JSON body. The data table is serialized to JSON. On success, the response is parsed as JSON and passed to the success callback. On failure the error callback gets the error message, the HTTP status (0 when there was no response) and the parsed JSON body of the error response when it has one. Requests to DMHub cloud services automatically include authentication credentials. quiet = true keeps the request and response out of the logs (use it for requests that carry credentials).
--- @param args {url: string, data: table, success: nil|fun(response: table), error: nil|fun(message: string, status: integer, body: nil|table), headers: nil|table<string, string>, timeout: nil|number, quiet: nil|boolean}
function net.Post(args) end

--- Downloads a URL to a file in the app's downloads folder ({persistentDataPath}/downloads/{name}; name must be a plain file name). The file appears only once it is complete, replacing any older file of that name. success gets the full path and HTTP status; error gets the message, the HTTP status (0 when there was no response) and the parsed JSON body of an error response when it has one.
--- @param args {url: string, name: string, success: nil|fun(path: string, status: integer), error: nil|fun(message: string, status: integer, body: nil|table), progress: nil|fun(fraction: number), headers: nil|table<string, string>}
function net.DownloadFile(args) end
