---@meta

--- @class ChatMessageInfoLua
--- @field messageType any
--- @field infoAndAmendments any[]
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
--- @field key string
--- @field isProvisional boolean
--- @field isLocal boolean
ChatMessageInfoLua = {}

--- SetInfo
--- @param info? any
--- @return boolean
function ChatMessageInfoLua:SetInfo(info) end

--- UploadRealtimeInteraction
--- @param userid? string
--- @param info? any
function ChatMessageInfoLua:UploadRealtimeInteraction(userid, info) end

--- UploadProperties
--- @param properties? any
function ChatMessageInfoLua:UploadProperties(properties) end

--- Delete
function ChatMessageInfoLua:Delete() end
