--- @class ChatMessageInfoLua
--- @field round number (Read-only) The combat round this message was sent in, or 0 if it was sent outside combat. Stamped on send, so it stays correct for older messages and across a reload. Use with 'turn' to group action-log entries by turn.
--- @field turn number (Read-only) The turn within the combat round this message was sent in, or 0 outside combat. Counts up from 1 and resets each round, so (round, turn) identifies a single turn.
--- @field messageType any
--- @field infoAndAmendments any 
--- @field properties any 
--- @field isComplete boolean 
--- @field userid any 
--- @field nick any 
--- @field message any 
--- @field tokenid any 
--- @field isRoll any 
--- @field timestamp any 
--- @field incomplete any 
--- @field nickColor any 
--- @field formattedText any 
--- @field numVisibleCharacters any 
--- @field realtimeInteractions any 
--- @field gmonly boolean 
ChatMessageInfoLua = {}

--- SetInfo
--- @param info any
--- @return boolean
function ChatMessageInfoLua:SetInfo(info)
	-- dummy implementation for documentation purposes only
end

--- UploadRealtimeInteraction
--- @param userid string
--- @param info any
--- @return nil
function ChatMessageInfoLua:UploadRealtimeInteraction(userid, info)
	-- dummy implementation for documentation purposes only
end

--- UploadProperties
--- @param properties any
--- @return nil
function ChatMessageInfoLua:UploadProperties(properties)
	-- dummy implementation for documentation purposes only
end

--- Delete
--- @return nil
function ChatMessageInfoLua:Delete()
	-- dummy implementation for documentation purposes only
end
