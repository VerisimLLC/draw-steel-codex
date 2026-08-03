--- @class ChatMessageInfoLua 
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
