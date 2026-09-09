---@meta

--- Provides the Lua interface for the chat system, including sending messages, dice events, and chat commands.
--- @class chat
--- @field events EventSourceLua An event source that you can subscribe to for chat events.
--- @field messages ChatMessageInfoLua[] All messages in the chat.
chat = {}

--- Given a dice roll, returns an event source you can subscribe to to get events for the dice.
--- @param guid string
--- @return EventSourceLua
function chat.DiceEvents(guid) end

--- Send a message to the chat.
--- @param message string
function chat.Send(message) end

--- Send a CustomChatPanel to chat.
--- @param panel CustomChatPanel
--- @return string The guid of the message.
function chat.SendCustom(panel) end

--- Updates a CustomChatPanel in chat. The key is the guid previously returned by @see SendCustom
--- @param key string
--- @param properties CustomChatPanel
function chat.UpdateCustom(key, properties) end

--- Share a game object (e.g. a spell, ability, or item) to the chat.
--- @param data table
function chat.ShareData(data) end

--- Shares a game object from a data table to the chat by table id and object id.
--- @param tableid string The data table identifier.
--- @param objid string The object identifier within the table.
--- @param properties nil|table Optional additional properties to include.
function chat.ShareObjectInfo(tableid, objid, properties) end

--- Clear the chat.
function chat.Clear() end

--- Previews a chat message as the user types, updating the chat input display.
--- @param message string The message text to preview.
function chat.PreviewChat(message) end

--- Returns a list of matching command completions for a partial chat command string starting with '/'.
--- @param command string The partial command string.
--- @return string[]
function chat.GetCommandCompletions(command) end

--- Returns the chat message info for a dice roll by its key.
--- @param key string The chat message key.
--- @return ChatMessageInfoLua|nil
function chat.GetRollInfo(key) end
