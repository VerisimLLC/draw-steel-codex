--- @class gpt Provides an interface for sending requests to the OpenAI GPT API.
gpt = {}

--- SetAPIKey: Sets the OpenAI API key used for GPT requests. Persists across sessions.
--- @param key string
--- @return nil
function gpt:SetAPIKey(key)
	-- dummy implementation for documentation purposes only
end

--- Send: Sends a streaming GPT request with the given payload. Calls callback with each streamed response chunk, or calls errorCallback on failure.
--- @param val table The request payload table, serialized to JSON for the OpenAI API.
--- @param callback function Called with each streamed response chunk as a table, or with no arguments when the stream is complete.
--- @param errorCallback function Called with an error message string if the request fails.
function gpt:Send(val, callback, errorCallback)
	-- dummy implementation for documentation purposes only
end
