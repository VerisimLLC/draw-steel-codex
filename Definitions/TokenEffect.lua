--- @class TokenEffect
--- @field id string
--- @field kind any
--- @field video string
--- @field playbackSpeed number
--- @field blend string
--- @field particleName string
--- @field worldSimulation boolean Force World simulation space for particles (for a teleport travelEffect).
--- @field scale number
--- @field soundEvent string
--- @field duration number How long (seconds) the call site should wait before continuing.
--- @field delay number Delay (seconds) after the effect is triggered before it plays.
--- @field windup number Teleport only: seconds the token holds at the source before leaving.
--- @field travelTime number Teleport only: duration of the invisible source-to-destination lerp. 0 = instant.
--- @field travelEffect string Teleport only: id of another effect played on the token while it travels.
TokenEffect = {}

--- Clone
--- @return any
function TokenEffect:Clone()
	-- dummy implementation for documentation purposes only
end
