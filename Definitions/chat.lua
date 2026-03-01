--- @class chat Provides the Lua interface for the chat system, including sending messages, dice events, and chat commands.
--- @field events EventSourceLua An event source that you can subscribe to for chat events.
--- @field messages ChatMessageInfoLua[] All messages in the chat.
chat = {}

--- DiceEvents: Given a dice roll, returns an event source you can subscribe to to get events for the dice.
--- @param guid string
--- @return EventSourceLua
function chat.DiceEvents(guid)
	-- dummy implementation for documentation purposes only
end

--- Send: Send a message to the chat.
--- @param message string
function chat.Send(message)
	-- dummy implementation for documentation purposes only
end

--- SendCustom: Send a CustomChatPanel to chat.
--- @param panel CustomChatPanel
--- @return string The guid of the message.
function chat.SendCustom(panel)
	-- dummy implementation for documentation purposes only
end

--- UpdateCustom: Updates a CustomChatPanel in chat. The key is the guid previously returned by @see SendCustom
--- @param key string
--- @param properties CustomChatPanel
function chat.UpdateCustom(key, properties)
	-- dummy implementation for documentation purposes only
end

--- ShareData: Share a game object (e.g. a spell, ability, or item) to the chat.
--- @param data table
function chat.ShareData(data)
	-- dummy implementation for documentation purposes only
end

--- ShareObjectInfo: Shares a game object from a data table to the chat by table id and object id.
--- @param tableid string The data table identifier.
--- @param objid string The object identifier within the table.
--- @param properties nil|table Optional additional properties to include.
function chat.ShareObjectInfo(tableid, objid, properties)
	-- dummy implementation for documentation purposes only
end

--- Clear: Clear the chat.
--- @return nil
function chat.Clear()
	-- dummy implementation for documentation purposes only
end

--- PreviewChat: Previews a chat message as the user types, updating the chat input display.
--- @param message string The message text to preview.
function chat.PreviewChat(message)
	-- dummy implementation for documentation purposes only
end

--- GetCommandCompletions: Returns a list of matching command completions for a partial chat command string starting with '/'.
--- @param command string The partial command string.
--- @return string[]
function chat.GetCommandCompletions(command)
	-- dummy implementation for documentation purposes only
end

--- GetRollInfo: Returns the chat message info for a dice roll by its key.
--- @param key string The chat message key.
--- @return ChatMessageInfoLua|nil
function chat.GetRollInfo(key)
	-- dummy implementation for documentation purposes only
end
